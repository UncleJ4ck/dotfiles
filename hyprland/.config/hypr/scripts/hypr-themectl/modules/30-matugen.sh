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

  info "Running matugen (mode: $MATUGEN_MODE)"

  if ! matugen image "$wall" -m "$MATUGEN_MODE" 2>/dev/null; then
    warn "Matugen failed on first attempt, retrying..."
    matugen image "$wall" -m "$MATUGEN_MODE" || {
      warn "Matugen failed, using fallbacks"
      return 0
    }
  fi

  # Export JSON for Limine and other consumers
  if ! matugen image "$wall" --json hex > "$MATUGEN_JSON_FILE" 2>/dev/null; then
    warn "Matugen JSON export failed"
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
# JSON shape: .colors.<role>.<dark|light|default>
# =============================================================================
matugen_role_hex() {
  local mode="$1" key="$2" fallback="$3"

  # Map amoled -> dark for JSON lookup
  local jq_mode="$mode"
  [[ "$jq_mode" == "amoled" ]] && jq_mode="dark"

  if [[ -s "$MATUGEN_JSON_FILE" ]]; then
    local v
    v="$(jq -r --arg m "$jq_mode" --arg k "$key" \
         '.colors[$k][$m] // empty' "$MATUGEN_JSON_FILE" 2>/dev/null)" || true

    [[ -n "$v" && "$v" != "null" ]] && { echo "$v"; return 0; }
  fi

  echo "$fallback"
}
