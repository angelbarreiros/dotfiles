#!/bin/bash

set -euo pipefail

launch_if_missing() {
    local class_name="$1"
    local launch_cmd="$2"

    if hyprctl -j clients | jq -e --arg class_name "$class_name" '.[] | select(.class == $class_name)' >/dev/null; then
        return 0
    fi

    sh -lc "$launch_cmd" >/dev/null 2>&1 &
}

move_class_to_scratchpad() {
    local class_name="$1"
    local attempts="${2:-80}"
    local delay="${3:-0.25}"
    local i addresses address

    for ((i = 0; i < attempts; i++)); do
        addresses=$(hyprctl -j clients | jq -r --arg class_name "$class_name" '.[] | select(.class == $class_name) | .address')

        if [[ -n "$addresses" ]]; then
            while IFS= read -r address; do
                [[ -n "$address" ]] || continue
                hyprctl dispatch movetoworkspacesilent "special:scratchpad,address:$address" >/dev/null 2>&1 || true
            done <<< "$addresses"
            return 0
        fi

        sleep "$delay"
    done

    return 1
}

launch_if_missing "chrome-gmail.com__-Default" 'omarchy-launch-webapp "https://gmail.com"'
launch_if_missing "chrome-web.whatsapp.com__-Default" 'omarchy-launch-webapp "https://web.whatsapp.com"'

move_class_to_scratchpad "chrome-gmail.com__-Default" || true
move_class_to_scratchpad "chrome-web.whatsapp.com__-Default" || true
