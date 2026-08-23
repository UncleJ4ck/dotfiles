# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "torch==2.7.1+cpu",
#   "transformers>=4.40",
#   "Pillow>=10.0",
# ]
#
# [tool.uv]
# extra-index-url = ["https://download.pytorch.org/whl/cpu"]
# ///
"""CLIP + color hybrid profile picture matcher for hypr-themectl.

Usage:
  uv run clip-match.py <wallpaper> <profile_dir> [--cache <path>] [--model <name>] [--color-weight 0.5] [--setup] [--debug]

Scores = blend of CLIP semantic similarity and LAB color similarity.
Prints the best-matching profile path to stdout.
Exits silently (no output) on any failure so bash can fall back.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="CLIP + color hybrid profile matcher")
    p.add_argument("wallpaper", nargs="?", help="Wallpaper image path")
    p.add_argument("profile_dir", nargs="?", help="Directory of profile images")
    p.add_argument("--cache", default=None, help="Embedding cache JSON path")
    p.add_argument("--model", default="openai/clip-vit-base-patch32", help="CLIP model name")
    p.add_argument("--color-weight", type=float, default=0.5, help="Color vs CLIP blend (0=CLIP only, 1=color only)")
    p.add_argument("--exclude", default=None, help="Filename to exclude (e.g. output file)")
    p.add_argument("--setup", action="store_true", help="Pre-download model and exit")
    p.add_argument("--debug", action="store_true", help="Print ranked list to stderr")
    return p.parse_args()


def load_model(model_name: str):
    """Load CLIP model + processor, returns (model, processor)."""
    import torch
    from transformers import CLIPModel, CLIPProcessor

    processor = CLIPProcessor.from_pretrained(model_name)
    model = CLIPModel.from_pretrained(model_name)
    model.eval()
    # Force CPU — GPU not worth it for single-image inference on small VRAM
    model = model.to("cpu")
    return model, processor


def embed_image(model, processor, image_path: str) -> list[float]:
    """Compute a normalized CLIP embedding for a single image."""
    import torch
    from PIL import Image

    img = Image.open(image_path).convert("RGB")
    inputs = processor(images=img, return_tensors="pt")
    with torch.no_grad():
        out = model.get_image_features(**inputs)
    # Handle both raw tensor and BaseModelOutputWithPooling
    emb = out if isinstance(out, torch.Tensor) else out.pooler_output
    # L2-normalize so cosine similarity = dot product
    emb = emb / emb.norm(dim=-1, keepdim=True)
    return emb.squeeze().tolist()


def cosine_sim(a: list[float], b: list[float]) -> float:
    """Dot product of two L2-normalized vectors = cosine similarity."""
    return sum(x * y for x, y in zip(a, b))


# ── Color extraction (sRGB → LAB) ────────────────────────────────────────────

def _srgb_to_lin(c: float) -> float:
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgb_to_lab(r: float, g: float, b: float) -> tuple[float, float, float]:
    """Convert sRGB (0-255) to CIELAB."""
    R, G, B = _srgb_to_lin(r), _srgb_to_lin(g), _srgb_to_lin(b)
    # sRGB → XYZ (D65)
    x = R * 0.4124564 + G * 0.3575761 + B * 0.1804375
    y = R * 0.2126729 + G * 0.7151522 + B * 0.0721750
    z = R * 0.0193339 + G * 0.1191920 + B * 0.9503041
    # XYZ → LAB
    xn, yn, zn = 0.95047, 1.0, 1.08883
    d = 6.0 / 29.0

    def f(t):
        return t ** (1.0 / 3.0) if t > d**3 else t / (3.0 * d**2) + 4.0 / 29.0

    fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
    return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


def _delta_e76(lab1: tuple, lab2: tuple) -> float:
    """Euclidean distance in LAB space (CIE76)."""
    return math.sqrt(
        (lab1[0] - lab2[0]) ** 2 + (lab1[1] - lab2[1]) ** 2 + (lab1[2] - lab2[2]) ** 2
    )


def color_palette(image_path: str, n_colors: int = 10, max_pixels: int = 4096) -> list[list]:
    """Extract dominant color palette as [[weight, L, a, b], ...].

    Uses Pillow's median-cut quantization — no extra deps needed.
    Thumbnail preserves aspect ratio so tall/wide images don't lose
    accent colors that get squished by forced square resize.
    """
    from PIL import Image

    img = Image.open(image_path).convert("RGB")
    # thumbnail() preserves aspect ratio, caps total pixels
    w, h = img.size
    scale = min(1.0, (max_pixels / (w * h)) ** 0.5)
    if scale < 1.0:
        img = img.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    quantized = img.quantize(colors=n_colors, method=Image.Quantize.MEDIANCUT)
    # getpalette() returns flat [R,G,B, R,G,B, ...] for up to 256 entries
    raw_palette = quantized.getpalette()
    # histogram() returns pixel count per palette index
    hist = quantized.histogram()

    total = sum(hist[:n_colors])
    if total <= 0:
        return []

    palette = []
    for i in range(n_colors):
        if hist[i] <= 0:
            continue
        r, g, b = raw_palette[i * 3], raw_palette[i * 3 + 1], raw_palette[i * 3 + 2]
        weight = hist[i] / total
        lab = _rgb_to_lab(r, g, b)
        palette.append([weight, lab[0], lab[1], lab[2]])

    # Sort by weight descending
    palette.sort(key=lambda x: x[0], reverse=True)
    return palette


def _pal_directed(pal_from: list[list], pal_to: list[list]) -> float:
    """Weighted min-distance from one palette to another."""
    dist = 0.0
    for w, L, a, b in pal_from:
        min_d = min(
            _delta_e76((L, a, b), (pL, pa, pb))
            for _, pL, pa, pb in pal_to
        )
        dist += w * min_d
    return dist


def _pal_worst_outlier(pal_from: list[list], pal_to: list[list]) -> float:
    """Worst single-color mismatch (unweighted) — catches any jarring accent."""
    worst = 0.0
    for _, L, a, b in pal_from:
        min_d = min(
            _delta_e76((L, a, b), (pL, pa, pb))
            for _, pL, pa, pb in pal_to
        )
        worst = max(worst, min_d)
    return worst


def palette_distance(pal_wall: list[list], pal_prof: list[list]) -> float:
    """Palette distance with outlier penalty.

    Blends three signals:
    - wall→prof: "does the profile have the wallpaper's colors?"
    - prof→wall: "does the profile avoid colors the wallpaper doesn't have?"
    - outlier:   "does the profile have ANY color that really doesn't belong?"
      (unweighted — even a small blue accent gets penalized)
    """
    if not pal_wall or not pal_prof:
        return 100.0  # large penalty

    fwd = _pal_directed(pal_wall, pal_prof)
    rev = _pal_directed(pal_prof, pal_wall)
    outlier = _pal_worst_outlier(pal_prof, pal_wall)
    # outlier is raw deltaE (~0-100), fwd/rev are weighted averages (~0-30)
    # Scale outlier to comparable range, but keep it impactful
    return 0.30 * fwd + 0.30 * rev + 0.40 * (outlier * 0.5)


def z_normalize(values: list[float]) -> list[float]:
    """Z-score normalize a list. Returns zeros if no variance."""
    n = len(values)
    if n < 2:
        return [0.0] * n
    mu = sum(values) / n
    var = sum((v - mu) ** 2 for v in values) / n
    std = math.sqrt(var) if var > 0 else 1.0
    return [(v - mu) / std for v in values]


def list_profiles(profile_dir: Path, exclude: str | None) -> list[Path]:
    """List image files in profile_dir, excluding the output file."""
    results = []
    for f in sorted(profile_dir.iterdir()):
        if not f.is_file():
            continue
        if f.suffix.lower() not in IMAGE_EXTS:
            continue
        if exclude and f.name == exclude:
            continue
        results.append(f)
    return results


def load_cache(cache_path: Path, model_name: str) -> dict:
    """Load cached embeddings, returning empty dict if stale/missing."""
    if not cache_path.is_file():
        return {}
    try:
        data = json.loads(cache_path.read_text())
        if data.get("model") != model_name:
            return {}
        return data.get("profiles", {})
    except (json.JSONDecodeError, KeyError):
        return {}


def save_cache(cache_path: Path, model_name: str, profiles: dict) -> None:
    """Write embedding cache atomically."""
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = cache_path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"model": model_name, "profiles": profiles}, separators=(",", ":")))
    tmp.replace(cache_path)


def main() -> None:
    args = parse_args()

    if args.setup:
        # Just load model (triggers download) and exit
        if args.debug:
            print(f"[clip] Downloading model: {args.model}", file=sys.stderr)
        load_model(args.model)
        if args.debug:
            print("[clip] Model ready", file=sys.stderr)
        return

    # Validate inputs
    if not args.wallpaper or not args.profile_dir:
        return  # silent exit — let bash fallback handle it

    wall_path = Path(args.wallpaper)
    prof_dir = Path(args.profile_dir)
    if not wall_path.is_file() or not prof_dir.is_dir():
        return

    profiles = list_profiles(prof_dir, args.exclude)
    if not profiles:
        return

    # Load model
    model, processor = load_model(args.model)

    # Load/update embedding cache
    cache: dict = {}
    if args.cache:
        cache = load_cache(Path(args.cache), args.model)

    # Compute profile embeddings + palette (cached)
    updated = False
    profile_data: dict[str, dict] = {}  # key -> {"embedding": [...], "palette": [[w,L,a,b],...]}

    for p in profiles:
        key = str(p)
        mtime = p.stat().st_mtime

        cached_entry = cache.get(key)
        if cached_entry and cached_entry.get("mtime") == mtime and "palette" in cached_entry:
            profile_data[key] = {
                "embedding": cached_entry["embedding"],
                "palette": cached_entry["palette"],
            }
        else:
            if args.debug:
                print(f"[clip] Embedding: {p.name}", file=sys.stderr)
            emb = embed_image(model, processor, key)
            pal = color_palette(key)
            profile_data[key] = {"embedding": emb, "palette": pal}
            cache[key] = {"mtime": mtime, "embedding": emb, "palette": pal}
            updated = True

    # Prune stale entries (deleted files)
    current_keys = {str(p) for p in profiles}
    stale = [k for k in cache if k not in current_keys]
    for k in stale:
        del cache[k]
        updated = True

    # Save cache if anything changed
    if updated and args.cache:
        save_cache(Path(args.cache), args.model, cache)

    # Compute wallpaper embedding + palette
    wall_emb = embed_image(model, processor, str(wall_path))
    wall_pal = color_palette(str(wall_path))

    # Compute raw scores for each profile
    cw = args.color_weight  # 0.0 = pure CLIP, 1.0 = pure color
    sw = 1.0 - cw           # semantic (CLIP) weight

    paths = list(profile_data.keys())
    clip_scores = [cosine_sim(wall_emb, profile_data[p]["embedding"]) for p in paths]
    color_dists = [palette_distance(wall_pal, profile_data[p]["palette"]) for p in paths]

    # Z-score normalize both dimensions so they're on equal footing
    clip_z = z_normalize(clip_scores)
    color_z = z_normalize(color_dists)

    # Blend: higher clip_z = better, lower color_z = better (negate)
    final = [sw * cz - cw * dz for cz, dz in zip(clip_z, color_z)]

    ranked = sorted(zip(final, clip_scores, color_dists, paths), key=lambda x: x[0], reverse=True)

    if args.debug:
        for score, clip_s, col_d, path_str in ranked[:10]:
            print(
                f"[clip] {score:+.3f}  clip={clip_s:.4f} pal_dE={col_d:5.1f}  {Path(path_str).name}",
                file=sys.stderr,
            )

    if ranked:
        print(ranked[0][3])


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # stdout stays empty so bash falls back to the histogram scorer, but the
        # reason goes to stderr and the exit code is non-zero. Swallowing both is
        # what let `clip-setup` report a model as ready after a failed download.
        print(f"clip-match: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
