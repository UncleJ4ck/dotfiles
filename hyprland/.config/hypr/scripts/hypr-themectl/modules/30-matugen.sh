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
  # templates and running post_hooks normally (no need for a second --dry-run call)
  local json_out="" err_out=""
  if ! json_out=$("${mg_args[@]}" 2>/tmp/matugen.err </dev/null); then
    err_out="$(</tmp/matugen.err)"
    warn "Matugen failed on first attempt, retrying..."
    ((DEBUG)) && [[ -n "$err_out" ]] && dbg "matugen stderr: $err_out"

    json_out=$("${mg_args[@]}" </dev/null 2>&1) || {
      warn "Matugen failed, using fallbacks"
      ((DEBUG)) && dbg "matugen retry output: $json_out"
      return 0
    }
  fi
  rm -f /tmp/matugen.err 2>/dev/null || true

  # Save JSON for Limine, Plymouth, and other consumers
  if [[ -n "$json_out" ]]; then
    printf '%s\n' "$json_out" > "$MATUGEN_JSON_FILE"
  else
    warn "Matugen JSON export empty"
    rm -f "$MATUGEN_JSON_FILE" 2>/dev/null || true
  fi

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

  if [[ -s "$MATUGEN_JSON_FILE" ]]; then
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
  fi

  echo "$fallback"
}
