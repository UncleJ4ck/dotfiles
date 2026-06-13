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
VIDEO_TMP="${STATE_DIR}/video.mkv"
DESKTOP_WAV="${STATE_DIR}/desktop.wav"
MIC_WAV="${STATE_DIR}/mic.wav"
DESKTOP_PID_FILE="${STATE_DIR}/desktop-audio.pid"
MIC_PID_FILE="${STATE_DIR}/mic-audio.pid"

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
    local apid
    for pid_file in "$DESKTOP_PID_FILE" "$MIC_PID_FILE"; do
        if [[ -f "$pid_file" ]]; then
            apid="$(<"$pid_file")"
            [[ "$apid" =~ ^[0-9]+$ ]] && kill -INT "$apid" 2>/dev/null || true
        fi
    done
    rm -f "$PID_FILE" "$LAST_FILE" "$DESKTOP_PID_FILE" "$MIC_PID_FILE"
    rm -f "$VIDEO_TMP" "$DESKTOP_WAV" "$MIC_WAV"
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

stop_audio_process() {
    local pid_file="$1"
    local apid attempt

    [[ -f "$pid_file" ]] || return 0
    apid="$(<"$pid_file")"
    [[ "$apid" =~ ^[0-9]+$ ]] || return 0
    [[ "$(ps -p "$apid" -o comm= 2>/dev/null | tr -d ' ')" == "pw-record" ]] || return 0
    kill -INT "$apid" 2>/dev/null || true
    for ((attempt = 0; attempt < 30; attempt++)); do
        kill -0 "$apid" 2>/dev/null || break
        sleep 0.1
    done
    rm -f "$pid_file"
}

stop_recording() {
    local pid output attempt

    pid="$(<"$PID_FILE")"
    output=""
    [[ -f "$LAST_FILE" ]] && output="$(<"$LAST_FILE")"

    kill -INT "$pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 50; attempt++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done

    stop_audio_process "$DESKTOP_PID_FILE"
    stop_audio_process "$MIC_PID_FILE"

    if [[ -n "$output" ]] && [[ -f "$VIDEO_TMP" ]] && command -v ffmpeg >/dev/null 2>&1; then
        local -a ffmpeg_inputs=(-i "$VIDEO_TMP")
        local filter_inputs=""
        local audio_count=0
        local idx=1

        if [[ -s "$DESKTOP_WAV" ]]; then
            ffmpeg_inputs+=(-i "$DESKTOP_WAV")
            filter_inputs+="[${idx}:a]"
            idx=$(( idx + 1 ))
            audio_count=$(( audio_count + 1 ))
        fi
        if [[ -s "$MIC_WAV" ]]; then
            ffmpeg_inputs+=(-i "$MIC_WAV")
            filter_inputs+="[${idx}:a]"
            audio_count=$(( audio_count + 1 ))
        fi

        if (( audio_count > 1 )); then
            ffmpeg "${ffmpeg_inputs[@]}" \
                -filter_complex "${filter_inputs}amix=inputs=${audio_count}:duration=longest:normalize=0[aout]" \
                -map 0:v -map "[aout]" \
                -c:v copy -c:a aac -b:a 192k \
                "$output" -y 2>>"$LOG_FILE" \
            && rm -f "$VIDEO_TMP" "$DESKTOP_WAV" "$MIC_WAV" \
            || mv "$VIDEO_TMP" "$output"
        elif (( audio_count == 1 )); then
            ffmpeg "${ffmpeg_inputs[@]}" \
                -map 0:v -map 1:a \
                -c:v copy -c:a aac -b:a 192k \
                "$output" -y 2>>"$LOG_FILE" \
            && rm -f "$VIDEO_TMP" "$DESKTOP_WAV" "$MIC_WAV" \
            || mv "$VIDEO_TMP" "$output"
        else
            mv "$VIDEO_TMP" "$output"
        fi
    elif [[ -f "$VIDEO_TMP" && -n "$output" ]]; then
        mv "$VIDEO_TMP" "$output"
    fi

    rm -f "$PID_FILE" "$LAST_FILE"

    if [[ -n "$output" ]]; then
        notify "Recording saved" "$output"
    else
        notify "Recording stopped"
    fi
}

start_audio() {
    command -v pw-record >/dev/null 2>&1 || return 0
    command -v pactl >/dev/null 2>&1 || return 0

    local desktop_source mic_source default_sink

    default_sink="$(pactl get-default-sink 2>/dev/null || true)"
    if [[ -n "$default_sink" ]]; then
        desktop_source="${default_sink}.monitor"
        pw-record --target "$desktop_source" "$DESKTOP_WAV" >"${LOG_FILE}.desktop" 2>&1 &
        printf '%s\n' "$!" > "$DESKTOP_PID_FILE"
    fi

    mic_source="$(pactl get-default-source 2>/dev/null || true)"
    if [[ -n "$mic_source" ]]; then
        pw-record --target "$mic_source" "$MIC_WAV" >"${LOG_FILE}.mic" 2>&1 &
        printf '%s\n' "$!" > "$MIC_PID_FILE"
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

        cmd=(wf-recorder -g "$geometry" -f "$VIDEO_TMP")
    else
        target_output="$(get_target_output || true)"
        if [[ -z "$target_output" ]]; then
            notify "Recording failed" "Could not resolve a Hyprland monitor"
            exit 1
        fi

        cmd=(wf-recorder -o "$target_output" -f "$VIDEO_TMP")
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

    start_audio

    notify "Recording started" "$output"
}

if is_active_recording; then
    stop_recording
else
    cleanup_stale_state
    start_recording
fi
