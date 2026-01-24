#!/bin/bash
# Calendar/date script for swaync

# Get current date info
day=$(date +"%d")
weekday=$(date +"%a")
month=$(date +"%b")
time=$(date +"%H:%M")

echo "$weekday $day $month • $time"
