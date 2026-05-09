#!/usr/bin/env bash
# modules/30-matugen.sh - Matugen color generation and palette helpers
set -Eeuo pipefail

# =============================================================================
# Run Matugen
# =============================================================================
run_matugen() {
  local wall="$1"

  if ! is_cmd matugen; then
    warn "matugen not found, skipping color generation"
    return 0
  fi

  [[ -f "$wall" ]] || {
    warn "Matugen: wallpaper missing: '$wall'"
    return 0
  }

  info "Running matugen (mode: $MATUGEN_MODE)"

  # matugen 4.x removed the implicit "pick most dominant color" behavior and
  # now prompts interactively when multiple dominant colors are found.  We
  # pass --prefer saturation to pick the most chromatic color automatically
  # (better matches the wallpaper's visual identity than raw dominance, which
  # often selects near-neutral tones on wallpapers with lots of dark/brown
  # areas).  --source-color-index is a fallback alias for compatibility with
  # older matugen installs that honor index-based selection.
  #
  # </dev/null ensures stdin is closed so any unexpected prompt exits instead
  # of blocking the script, even if matugen's flags change again.
  local -a mg_args=(
    matugen image "$wall"
    -m "$MATUGEN_MODE"
    --json hex
    --prefer saturation
  )

  # Single invocation: --json hex outputs JSON to stdout while still applying
  # templates and running post_hooks normally (no need for a second --dry-run).
  #
  # Stderr goes to a per-run temp file (NOT a fixed /tmp path — avoids the
  # symlink/TOCTOU footgun on multi-user boxes) so we can surface diagnostics
  # in DEBUG without poisoning stdout.
  local json_out="" err_out="" err_file
  err_file="$(mktemp --tmpdir matugen-err-XXXXXX)"
  # Bake the path into the trap NOW (double-quote expansion at trap-set time)
  # so the cleanup runs even when `local err_file` has gone out of scope under
  # set -u. The previous `'…$err_file…'` form deferred expansion until after
  # the function returned, by which point err_file was unset.
  trap "rm -f '$err_file' 2>/dev/null || true" RETURN

  if ! json_out=$("${mg_args[@]}" 2>"$err_file" </dev/null); then
    err_out="$(<"$err_file")"
    warn "Matugen failed on first attempt, retrying..."
    ((DEBUG)) && [[ -n "$err_out" ]] && dbg "matugen stderr: $err_out"

    # Retry: keep stderr separate so warnings don't get folded into stdout
    # and silently corrupt the JSON file we're about to write.
    if ! json_out=$("${mg_args[@]}" 2>"$err_file" </dev/null); then
      warn "Matugen failed, using fallbacks"
      ((DEBUG)) && dbg "matugen retry stderr: $(<"$err_file" 2>/dev/null || true)"
      return 0
    fi
  fi

  if [[ -z "$json_out" ]]; then
    warn "Matugen JSON export empty; keeping previous $MATUGEN_JSON_FILE"
    return 0
  fi

  # Matugen 4.x runs post_hooks during --json hex invocation. Some post_hooks
  # write to stdout (e.g. tools that ignore redirection), and that output
  # gets concatenated to the JSON, breaking `jq -e empty`. Use python's
  # JSONDecoder.raw_decode to extract the first valid JSON object regardless
  # of trailing content. Same idea as `jq -c 'inputs'` but works on a single
  # object without --slurp gymnastics.
  #
  # Pass the captured stdout via stdin (here-string) and the python source
  # via -c so they don't fight over fd 0.
  local py json_clean
  py="$(get_python)"
  if ! json_clean="$("$py" -c '
import sys, json
data = sys.stdin.read()

# Try LAST JSON object first, then walk earlier {s. The matugen palette is
# the largest object in the stream; iterating from the end finds it before
# any small preamble (post_hook status, version banner, etc.) can hijack
# the parse. Each candidate must pass a schema gate before it is accepted.
def candidates(s):
    i = len(s)
    while True:
        i = s.rfind("{", 0, i)
        if i < 0:
            return
        yield i

decoder = json.JSONDecoder()
for i in candidates(data):
    try:
        obj, _end = decoder.raw_decode(data[i:])
    except json.JSONDecodeError:
        continue
    # Schema gate: must be a dict with a populated colors map. Matugen 4.x
    # emits 40+ M3 roles under .colors, so anything below 10 is a tiny
    # preamble masquerading as the palette.
    if (isinstance(obj, dict)
        and isinstance(obj.get("colors"), dict)
        and len(obj["colors"]) >= 10):
        json.dump(obj, sys.stdout)
        sys.exit(0)
sys.exit(1)
' <<<"$json_out")"; then
    warn "Matugen produced non-JSON output (or schema check failed); keeping previous $MATUGEN_JSON_FILE"
    ((DEBUG)) && dbg "matugen output (first 200 chars): ${json_out:0:200}"
    return 0
  fi

  printf '%s\n' "$json_clean" > "$MATUGEN_JSON_FILE"
  info "Matugen completed"
}

# =============================================================================
# Palette Readers
# =============================================================================

# Read from starship palette
starship_palette_hex() {
  local key="$1"
  local f="$HOME/.config/starship/starship.toml"
  [[ -f "$f" ]] || return 1

  awk -v k="$key" '
    /^\[palettes\.matugen\]/ { inside=1; next }
    inside && /^\[/ { exit }
    inside && $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
      if (match($0, /#[0-9a-fA-F]{6}/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$f"
}

# Read from GTK4 colors.css
gtk4_accent_hex() {
  local f="$HOME/.config/gtk-4.0/colors.css"
  [[ -f "$f" ]] || return 1

  local h
  # Try dark mode first
  h="$(sed -n '/@media.*prefers-color-scheme.*dark/,/^}/p' "$f" 2>/dev/null |
       grep -Eo -- '--accent-bg-color:[[:space:]]*#[0-9a-fA-F]{6}' |
       head -n1 | sed -E 's/.*(#[0-9a-fA-F]{6})/\1/')" || true

  [[ -n "$h" ]] && { echo "$h"; return 0; }

  # Fallback to any accent
  h="$(grep -Eo -- '--accent-bg-color:[[:space:]]*#[0-9a-fA-F]{6}' "$f" |
       tail -n1 | sed -E 's/.*(#[0-9a-fA-F]{6})/\1/')" || true

  [[ -n "$h" ]] && { echo "$h"; return 0; }
  return 1
}

# Read from GTK3 colors.css
gtk3_accent_hex() {
  local f="$HOME/.config/gtk-3.0/colors.css"
  [[ -f "$f" ]] || return 1

  grep -Eo -- '@define-color[[:space:]]+accent_bg_color[[:space:]]+#[0-9a-fA-F]{6}' "$f" |
    tail -n1 | sed -E 's/.*(#[0-9a-fA-F]{6})/\1/'
}

# Pick icon color with fallback chain
pick_icon_hex() {
  local h=""

  # Try configured source first
  h="$(starship_palette_hex "$ICON_SOURCE" 2>/dev/null)" || true
  [[ -n "$h" ]] && { echo "$h"; return 0; }

  # Try other palette colors
  local src
  for src in primary secondary tertiary; do
    h="$(starship_palette_hex "$src" 2>/dev/null)" || true
    [[ -n "$h" ]] && { echo "$h"; return 0; }
  done

  # GTK fallbacks
  h="$(gtk4_accent_hex 2>/dev/null)" || true
  [[ -n "$h" ]] && { echo "$h"; return 0; }

  h="$(gtk3_accent_hex 2>/dev/null)" || true
  [[ -n "$h" ]] && { echo "$h"; return 0; }

  # Ultimate fallback (Catppuccin Mocha blue)
  echo "#89b4fa"
}

# =============================================================================
# Matugen JSON Reader
# JSON shape changed in matugen 4.x:
#   Old (≤3.x): .colors.<role>.<dark|light|default>           → "#hex"
#   New (4.x):  .colors.<role>.<dark|light|default>.color     → "#hex"
# We query the new path first, fall back to the old path so the same script
# works on both versions.  Also validate the result looks like a hex color
# before accepting it — guards against jq returning an object by accident.
# =============================================================================
matugen_role_hex() {
  local mode="$1" key="$2" fallback="$3"

  # Map amoled -> dark for JSON lookup
  local jq_mode="$mode"
  [[ "$jq_mode" == "amoled" ]] && jq_mode="dark"

  if [[ ! -s "$MATUGEN_JSON_FILE" ]]; then
    # Fallback firing here means a matugen run failed earlier in the same
    # pipeline; without this dbg trail, every downstream consumer (limine,
    # plymouth, regreet) silently uses Catppuccin defaults with no log.
    dbg "matugen_role_hex: $MATUGEN_JSON_FILE missing/empty, using fallback ($key=$fallback)"
    echo "$fallback"
    return 0
  fi

  local v
  # matugen 4.x wraps each leaf as {"color": "#hex"} — try that first,
  # then fall back to the old direct-string format from matugen ≤3.x.
  v="$(jq -r --arg m "$jq_mode" --arg k "$key" '
    (.colors[$k][$m].color // .colors[$k][$m] // empty)
    | if type == "string" then . else empty end
  ' "$MATUGEN_JSON_FILE" 2>/dev/null)" || true

  # Validate it's actually a hex color (guards against any future schema
  # changes producing unexpected types).
  if [[ -n "$v" && "$v" != "null" && "$v" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    echo "$v"
    return 0
  fi

  dbg "matugen_role_hex: '$key' not found for mode '$jq_mode'; using fallback=$fallback"
  echo "$fallback"
}
