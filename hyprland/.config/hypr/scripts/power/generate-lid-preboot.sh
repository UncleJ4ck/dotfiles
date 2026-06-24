#!/bin/bash
# Pre-boot lid decision: disable eDP-1 when externals would exceed the Intel iGPU
# CRTC budget (LID_DISABLE_AT) or the lid is closed. MSI Intel iGPU (RPL-P) has 4 CRTCs, so
# eDP-1 + 3 externals fits; disable only at 4. Revert to 3 if a dock blanks a screen.
LID_DISABLE_AT=4
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
