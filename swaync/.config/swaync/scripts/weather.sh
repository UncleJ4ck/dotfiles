#!/bin/bash
# Weather script for swaync
# Uses wttr.in for simple weather fetching (no API key needed)

CACHE_FILE="/tmp/swaync-weather-cache"
CACHE_MAX_AGE=1800  # 30 minutes

# Check if cache is fresh
if [[ -f "$CACHE_FILE" ]]; then
    cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
    if [[ $cache_age -lt $CACHE_MAX_AGE ]]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Fetch weather (format: icon temp condition)
weather=$(curl -sf --max-time 5 "wttr.in/?format=%c+%t" 2>/dev/null | tr -d '+')

if [[ -n "$weather" ]]; then
    echo "$weather" > "$CACHE_FILE"
    echo "$weather"
else
    # Fallback if fetch fails
    if [[ -f "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
    else
        echo "󰖐 --"
    fi
fi
