#!/bin/bash
# Pre-boot lid decision for 3-CRTC safety (Intel HD 630)
LID_DISABLE_AT=3
ext=0
for f in /sys/class/drm/card*-{DP,HDMI,VGA}*/status; do
  [[ -f "$f" && $(< "$f") == connected ]] && ((++ext)) || true
done
lid_closed=0
grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null && lid_closed=1
mkdir -p ~/.cache/hypr
if (( lid_closed || ext >= LID_DISABLE_AT )); then
  echo "monitor = eDP-1, disable" > ~/.cache/hypr/lid-preboot.conf
else
  echo "monitor = eDP-1, preferred, auto, 1" > ~/.cache/hypr/lid-preboot.conf
fi
