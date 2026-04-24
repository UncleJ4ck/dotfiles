#!/usr/bin/env bash

set -euo pipefail

MODE="${1:-screen}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-screen-record"
VIDEO_DIR="${HOME}/Videos"

if ! mkdir -p "$STATE_DIR" >/dev/null 2>&1 || ! touch "${STATE_DIR}/.write-test" >/dev/null 2>&1; then
    STATE_DIR="/tmp/hypr-screen-record-${UID:-$(id -u)}"
    mkdir -p "$STATE_DIR"
else
    rm -f "${STATE_DIR}/.write-test"
fi

PID_FILE="${STATE_DIR}/wf-recorder.pid"
LAST_FILE="${STATE_DIR}/last-recording"
LOG_FILE="${STATE_DIR}/wf-recorder.log"

if command -v xdg-user-dir >/dev/null 2>&1; then
    video_dir_override="$(xdg-user-dir VIDEOS 2>/dev/null || true)"
    if [[ -n "$video_dir_override" ]]; then
        VIDEO_DIR="$video_dir_override"
    fi
fi

OUTPUT_DIR="${VIDEO_DIR}/Recordings"

notify() {
    local title="${1:-Screen Recorder}"
    local body="${2:-}"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Screen Recorder" "$title" "$body"
    else
        printf '%s: %s\n' "$title" "$body"
    fi
}

cleanup_stale_state() {
    rm -f "$PID_FILE" "$LAST_FILE"
}

get_target_output() {
    if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        return 1
    fi

    hyprctl monitors -j 2>/dev/null | jq -r '([.[] | select(.focused == true) | .name] + [.[] | .name])[0] // empty'
}

is_active_recording() {
    local pid

    [[ -f "$PID_FILE" ]] || return 1

    pid="$(<"$PID_FILE")"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ "$(ps -p "$pid" -o comm= 2>/dev/null | tr -d ' ')" == "wf-recorder" ]]
}

stop_recording() {
    local pid output attempt

    pid="$(<"$PID_FILE")"
    output=""
    [[ -f "$LAST_FILE" ]] && output="$(<"$LAST_FILE")"

    kill -INT "$pid"
    for ((attempt = 0; attempt < 50; attempt++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done

    cleanup_stale_state

    if [[ -n "$output" ]]; then
        notify "Recording saved" "$output"
    else
        notify "Recording stopped"
    fi
}

start_recording() {
    local geometry output pid target_output fail_reason
    local -a cmd

    if ! command -v wf-recorder >/dev/null 2>&1; then
        notify "wf-recorder is missing" "Install it with: sudo pacman -S wf-recorder"
        exit 1
    fi

    mkdir -p "$STATE_DIR" "$OUTPUT_DIR"
    : > "$LOG_FILE"
    output="${OUTPUT_DIR}/$(date +%Y%m%d_%H%M%S).mkv"

    if [[ "$MODE" == "region" ]]; then
        if ! command -v slurp >/dev/null 2>&1; then
            notify "slurp is missing" "Install it with: sudo pacman -S slurp"
            exit 1
        fi

        geometry="$(slurp 2>/dev/null || true)"
        if [[ -z "$geometry" ]]; then
            notify "Recording cancelled" "No region selected"
            exit 0
        fi

        cmd=(wf-recorder -g "$geometry" -f "$output")
    else
        target_output="$(get_target_output || true)"
        if [[ -z "$target_output" ]]; then
            notify "Recording failed" "Could not resolve a Hyprland monitor"
            exit 1
        fi

        cmd=(wf-recorder -o "$target_output" -f "$output")
    fi

    "${cmd[@]}" >"$LOG_FILE" 2>&1 &
    pid=$!

    printf '%s\n' "$pid" > "$PID_FILE"
    printf '%s\n' "$output" > "$LAST_FILE"

    sleep 0.2
    if ! kill -0 "$pid" 2>/dev/null; then
        fail_reason="$(tail -n 1 "$LOG_FILE" 2>/dev/null || true)"
        cleanup_stale_state
        if [[ -n "$fail_reason" ]]; then
            notify "Recording failed" "$fail_reason"
        else
            notify "Recording failed" "wf-recorder exited immediately"
        fi
        exit 1
    fi

    notify "Recording started" "$output"
}

if is_active_recording; then
    stop_recording
else
    cleanup_stale_state
    start_recording
fi
