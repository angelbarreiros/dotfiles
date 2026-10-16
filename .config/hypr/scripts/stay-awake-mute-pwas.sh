#!/bin/bash

# Mute the WhatsApp and Gmail Chromium PWAs while Omarchy stay-awake is on.
# Streams are matched by walking each sink input's process ancestry up to the
# Chromium instance started with the PWA's --user-data-dir.

FLAG="$HOME/.local/state/omarchy/indicators/stay-awake"
PWA_PATTERN='chromium-pwas/(whatsapp|gmail)'

is_pwa_pid() {
    local pid="$1"
    while [[ -n "$pid" && "$pid" -gt 1 ]]; do
        if tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -Eq -- "--user-data-dir=[^ ]*$PWA_PATTERN"; then
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    return 1
}

apply() {
    local want=0 id pid
    [[ -e "$FLAG" ]] && want=1

    while IFS=$'\t' read -r id pid; do
        [[ -n "$id" && -n "$pid" ]] || continue
        is_pwa_pid "$pid" && pactl set-sink-input-mute "$id" "$want"
    done < <(pactl --format=json list sink-inputs 2>/dev/null \
        | jq -r '.[] | [.index, (.properties["application.process.id"] // "")] | @tsv')
}

apply
# React to new audio streams immediately, and re-check every 2s for flag changes.
while true; do
    coproc SUB { pactl subscribe 2>/dev/null; }
    while read -r -t 2 -u "${SUB[0]}" line; do
        [[ "$line" == *"sink-input"* ]] && apply
    done
    kill "$SUB_PID" 2>/dev/null
    wait "$SUB_PID" 2>/dev/null
    apply
done
