#!/usr/bin/env bash
# modules/45-profile.sh - Hyprlock profile picture picker
set -Eeuo pipefail

# =============================================================================
# Helper Functions
# =============================================================================
_list_profile_candidates() {
  [[ -d "$PROFILE_DIR" ]] || return 0

  find -L "$PROFILE_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    ! -iname "$(basename "$HYPRLOCK_PROFILE_OUT")" \
    -print 2>/dev/null | sort
}

_profile_state_key() {
  local wall="$1" scorer="${2:-histogram}"
  local wall_hash
  wall_hash="$(md5sum "$wall" 2>/dev/null | awk '{print $1}')" || wall_hash="unknown"

  if [[ "$scorer" == "clip" ]]; then
    printf '%s\n' "${PROFILE_PICKER_VERSION}_${wall_hash}_${MATUGEN_MODE}_clip"
    return
  fi

  local p s t bg
  p="$(matugen_role_hex "$MATUGEN_MODE" primary "#89b4fa")"
  s="$(matugen_role_hex "$MATUGEN_MODE" secondary "#a6adc8")"
  t="$(matugen_role_hex "$MATUGEN_MODE" tertiary "#f5c2e7")"
  bg="$(matugen_role_hex "$MATUGEN_MODE" background "#11111b")"

  printf '%s\n' "${PROFILE_PICKER_VERSION}_${wall_hash}_${MATUGEN_MODE}_${p}_${s}_${t}_${bg}_${PROFILE_PICKER_SAMPLE}_${PROFILE_PICKER_MAX_COLORS}_${PROFILE_PICKER_SAT_MIN}_${PROFILE_PICKER_LUMA_MIN}_${PROFILE_PICKER_LUMA_MAX}_${PROFILE_PICKER_W_MEANLAB}_${PROFILE_PICKER_W_PALETTE}_${PROFILE_PICKER_W_SAT}_${PROFILE_PICKER_W_LUMA}_${PROFILE_PICKER_W_COLORFUL}_${PROFILE_PICKER_W_COV}"
}

_render_profile_for_hyprlock() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")" 2>/dev/null || true

  if im_available; then
    local cmd tmp
    cmd="$(im_cmd)"
    tmp="$(mktemp --tmpdir "hyprlock-profile-XXXXXX.jpg")"

    if "$cmd" "$src" \
      -auto-orient \
      -resize "512x512^" \
      -gravity center -extent "512x512" \
      -strip \
      -interlace Plane \
      -quality 92 \
      "$tmp" 2>/dev/null; then
      install -m 644 "$tmp" "$dst"
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
  fi

  # Fallback: just copy
  install -m 644 "$src" "$dst"
}

# =============================================================================
# Profile Scoring (CLIP via uv)
# =============================================================================
_select_best_profile_clip() {
  local wall="$1"
  is_cmd uv || return 1

  local -a clip_args=(
    uv run --quiet
    "$SCRIPT_DIR/lib/clip-match.py"
    "$wall" "$PROFILE_DIR"
    --model "$CLIP_MODEL"
    --cache "$CLIP_CACHE_FILE"
    --color-weight "$CLIP_COLOR_WEIGHT"
    --exclude "$(basename "$HYPRLOCK_PROFILE_OUT")"
  )
  ((DEBUG)) && clip_args+=(--debug)

  local result
  result="$("${clip_args[@]}" 2>&"$LOG_FD")" || return 1
  [[ -n "$result" && -f "$result" ]] || return 1
  echo "$result"
}

# =============================================================================
# Profile Scoring (Histogram fallback)
# =============================================================================
_select_best_profile_histogram() {
  local wall="$1"
  local im py
  im="$(im_cmd)"
  py="$(get_python)"
  [[ -n "$im" ]] || return 1

  local -a _cands
  mapfile -t _cands < <(_list_profile_candidates)
  ((${#_cands[@]})) || return 1

  local listfile
  listfile="$(mktemp)"
  printf '%s\n' "${_cands[@]}" >"$listfile"

  local p s t bg
  p="$(matugen_role_hex "$MATUGEN_MODE" primary "#89b4fa")"
  s="$(matugen_role_hex "$MATUGEN_MODE" secondary "#a6adc8")"
  t="$(matugen_role_hex "$MATUGEN_MODE" tertiary "#f5c2e7")"
  bg="$(matugen_role_hex "$MATUGEN_MODE" background "#11111b")"

  local result
  result="$(
    IM_CMD="$im" DEBUG="$DEBUG" "$py" - \
      "$wall" "$listfile" \
      "$PROFILE_PICKER_SAMPLE" "$PROFILE_PICKER_MAX_COLORS" \
      "$PROFILE_PICKER_SAT_MIN" "$PROFILE_PICKER_LUMA_MIN" "$PROFILE_PICKER_LUMA_MAX" \
      "$p" "$s" "$t" "$bg" \
      "$PROFILE_PICKER_W_MEANLAB" "$PROFILE_PICKER_W_PALETTE" "$PROFILE_PICKER_W_SAT" \
      "$PROFILE_PICKER_W_LUMA" "$PROFILE_PICKER_W_COLORFUL" "$PROFILE_PICKER_W_COV" <<'PY'
import os, sys, re, math, subprocess

WALL, LIST = sys.argv[1], sys.argv[2]
SAMPLE, MAXCOL = int(sys.argv[3]), int(sys.argv[4])
SAT_MIN, LUMA_MIN, LUMA_MAX = float(sys.argv[5]), float(sys.argv[6]), float(sys.argv[7])
T_PRIMARY, T_SECONDARY, T_TERTIARY, T_BG = sys.argv[8], sys.argv[9], sys.argv[10], sys.argv[11]
W_MEANLAB, W_PALETTE, W_SAT = float(sys.argv[12]), float(sys.argv[13]), float(sys.argv[14])
W_LUMA, W_CF, W_COV = float(sys.argv[15]), float(sys.argv[16]), float(sys.argv[17])

DEBUG = int(os.environ.get("DEBUG", "0"))
IM = os.environ.get("IM_CMD", "").strip()
if not IM:
    sys.exit(2)

HEX_RE = re.compile(r"#([0-9A-Fa-f]{6})")
LINE_RE = re.compile(r"^\s*(\d+):\s*\((\d+),\s*(\d+),\s*(\d+)")

def hex_to_rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def rel_luma(rgb):
    r, g, b = rgb
    return 0.2126 * srgb_to_lin(r) + 0.7152 * srgb_to_lin(g) + 0.0722 * srgb_to_lin(b)

def sat_hsv(rgb):
    r, g, b = [x / 255.0 for x in rgb]
    mx, mn = max(r, g, b), min(r, g, b)
    return 0.0 if mx <= 0 else (mx - mn) / mx

def rgb_to_xyz(rgb):
    r, g, b = rgb
    R, G, B = srgb_to_lin(r), srgb_to_lin(g), srgb_to_lin(b)
    x = R * 0.4124564 + G * 0.3575761 + B * 0.1804375
    y = R * 0.2126729 + G * 0.7151522 + B * 0.0721750
    z = R * 0.0193339 + G * 0.1191920 + B * 0.9503041
    return (x, y, z)

def xyz_to_lab(xyz):
    x, y, z = xyz
    xn, yn, zn = 0.95047, 1.0, 1.08883
    def f(t):
        d = 6 / 29
        return t ** (1/3) if t > d**3 else t / (3 * d**2) + 4/29
    fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))

def hex_to_lab(hx):
    return xyz_to_lab(rgb_to_xyz(hex_to_rgb(hx)))

def de76(a, b):
    return math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2 + (a[2] - b[2])**2)

def run_hist(path):
    cmd = [IM, path, "-alpha", "off", "-resize", f"{SAMPLE}x{SAMPLE}!",
           "+dither", "-colors", str(MAXCOL), "-depth", "8",
           "-format", "%c", "histogram:info:-"]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    out = p.stdout or ""
    rows, total = [], 0

    for line in out.splitlines():
        m = LINE_RE.search(line)
        if not m:
            continue
        cnt = int(m.group(1))
        hx = HEX_RE.search(line)
        if not hx:
            continue
        total += cnt
        rgb = hex_to_rgb(hx.group(1))
        rows.append((cnt, "#" + hx.group(1).lower(), rgb))

    if total <= 0 or not rows:
        return [], [], 0.0, 0.0

    ws = [cnt / total for cnt, _, _ in rows]

    # Hasler-Süsstrunk colorfulness
    rgs = [rgb[0] - rgb[1] for _, _, rgb in rows]
    ybs = [0.5 * (rgb[0] + rgb[1]) - rgb[2] for _, _, rgb in rows]
    mu_rg = sum(w * v for w, v in zip(ws, rgs))
    mu_yb = sum(w * v for w, v in zip(ws, ybs))
    var_rg = sum(w * (v - mu_rg)**2 for w, v in zip(ws, rgs))
    var_yb = sum(w * (v - mu_yb)**2 for w, v in zip(ws, ybs))
    cf = math.sqrt(var_rg + var_yb) + 0.3 * math.sqrt(mu_rg**2 + mu_yb**2)

    chroma, cov = [], 0.0
    for (cnt, hx, rgb), w in zip(rows, ws):
        s, l = sat_hsv(rgb), rel_luma(rgb)
        if s >= SAT_MIN and LUMA_MIN <= l <= LUMA_MAX:
            chroma.append((w, hx, rgb))
            cov += w

    if chroma:
        chroma = [(w / cov, hx, rgb) for w, hx, rgb in chroma]
        chroma.sort(key=lambda x: x[0], reverse=True)
    else:
        cov = 0.0

    return rows, chroma, cov, cf

def mean_lab_chroma(chroma, rows):
    if chroma:
        labs = [hex_to_lab(hx) for _, hx, _ in chroma]
        ws = [w for w, _, _ in chroma]
        mean = (sum(w * lab[0] for w, lab in zip(ws, labs)),
                sum(w * lab[1] for w, lab in zip(ws, labs)),
                sum(w * lab[2] for w, lab in zip(ws, labs)))
        sat = sum(w * sat_hsv(rgb) for w, _, rgb in chroma)
        lum = sum(w * rel_luma(rgb) for w, _, rgb in chroma)
        return mean, (sat, lum)

    rows = sorted(rows, key=lambda x: x[0], reverse=True)
    _, hx, rgb = rows[0]
    return hex_to_lab(hx), (sat_hsv(rgb), rel_luma(rgb))

with open(LIST, "r", encoding="utf-8") as f:
    cands = [ln.strip() for ln in f if ln.strip()]

wrows, wchroma, wcov, wcf = run_hist(WALL)
if not wrows:
    sys.exit(0)

wmean, wsl = mean_lab_chroma(wchroma, wrows)
roles = {
    "primary": hex_to_lab(T_PRIMARY),
    "secondary": hex_to_lab(T_SECONDARY),
    "tertiary": hex_to_lab(T_TERTIARY),
    "bg": hex_to_lab(T_BG)
}

def score(path):
    rows, chroma, cov, cf = run_hist(path)
    if not rows:
        return 1e18, None
    mean, sl = mean_lab_chroma(chroma, rows)
    s = W_MEANLAB * de76(mean, wmean)
    s += W_PALETTE * (0.55 * de76(mean, roles["primary"]) +
                      0.25 * de76(mean, roles["secondary"]) +
                      0.20 * de76(mean, roles["tertiary"]) +
                      0.10 * de76(mean, roles["bg"]))
    s += W_SAT * abs(sl[0] - wsl[0]) + W_LUMA * abs(sl[1] - wsl[1])
    s += W_CF * abs(cf - wcf) + W_COV * abs(cov - wcov)
    return s, {"sat": sl[0], "lum": sl[1], "cov": cov, "cf": cf}

rank = []
best, bests = None, 1e18
for pth in cands:
    try:
        sc, dbg = score(pth)
        if dbg is not None:
            rank.append((sc, pth, dbg))
        if sc < bests:
            bests, best = sc, pth
    except Exception:
        continue

rank.sort(key=lambda x: x[0])
if DEBUG:
    for sc, pth, dbg in rank[:10]:
        print(f"[-] {sc:8.3f} sat={dbg['sat']:.3f} lum={dbg['lum']:.3f} cov={dbg['cov']:.3f} cf={dbg['cf']:.2f} {pth}", file=sys.stderr)

if best:
    print(best)
PY
  )" || true

  rm -f "$listfile" 2>/dev/null || true
  echo "$result"
}

# =============================================================================
# Profile Scoring Dispatcher (CLIP → histogram fallback)
# =============================================================================
_select_best_profile_python() {
  local wall="$1"

  # Try CLIP first — prefix output with scorer name
  local result
  if result="$(_select_best_profile_clip "$wall" 2>&"$LOG_FD")" && [[ -n "$result" ]]; then
    dbg "CLIP scorer selected: $(basename "$result")"
    echo "clip:$result"
    return 0
  fi

  # Fall back to histogram scorer
  dbg "CLIP unavailable, using histogram scorer"
  result="$(_select_best_profile_histogram "$wall")" || return 1
  [[ -n "$result" ]] || return 1
  echo "histogram:$result"
}

# =============================================================================
# Main Entry Point
# =============================================================================
apply_profile_picture() {
  local wall="$1"
  [[ -f "$wall" ]] || die "Wallpaper missing: $wall"

  [[ -d "$PROFILE_DIR" ]] || {
    warn "Profile directory missing: $PROFILE_DIR"
    return 0
  }

  # Quick cache check before expensive scoring (unless forced)
  if ((!PROFILE_PICKER_FORCE)) && ((!DEBUG)) && [[ -s "$HYPRLOCK_PROFILE_OUT" ]]; then
    local prev
    prev="$(read_state "$STATE_PROFILE_FILE")"
    # Check both possible scorer keys
    if [[ "$prev" == "$(_profile_state_key "$wall" clip)" ]] || \
       [[ "$prev" == "$(_profile_state_key "$wall" histogram)" ]]; then
      dbg "Profile picture unchanged (cache hit)"
      return 0
    fi
  fi

  local raw chosen="" scorer="histogram"
  raw="$(_select_best_profile_python "$wall")" || true

  # Parse "scorer:path" output
  if [[ "$raw" == *:* ]]; then
    scorer="${raw%%:*}"
    chosen="${raw#*:}"
  fi

  # Fallback to first candidate
  if [[ -z "$chosen" || ! -f "$chosen" ]]; then
    dbg "No ranked profile, falling back to first"
    chosen="$(_list_profile_candidates | head -n1)" || true
  fi

  if [[ -z "$chosen" || ! -f "$chosen" ]]; then
    warn "No profile images found in $PROFILE_DIR"
    return 0
  fi

  info "Profile selected: $(basename "$chosen")"
  _render_profile_for_hyprlock "$chosen" "$HYPRLOCK_PROFILE_OUT"
  write_state "$STATE_PROFILE_FILE" "$(_profile_state_key "$wall" "$scorer")"
}
