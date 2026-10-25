#!/usr/bin/env bash
# Waybar IP module. Shows the default-route SOURCE address and its interface.
# The native network module latches onto the wrong iface on this box (a dozen
# docker/libvirt bridges, several UP), so read the real uplink from the route.
line="$(ip route get 1.1.1.1 2>/dev/null)"
ip="$(grep -oP 'src \K\S+' <<<"$line")"
dev="$(grep -oP 'dev \K\S+' <<<"$line")"

if [[ -z "$ip" ]]; then
  printf '{"text":"","tooltip":"no network","class":"disconnected"}\n'
  exit 0
fi
printf '{"text":"%s","tooltip":"%s  •  %s","class":"connected"}\n' "$ip" "$dev" "$ip"
