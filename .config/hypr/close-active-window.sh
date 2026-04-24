#!/bin/bash

set -euo pipefail

active_window_json=$(hyprctl -j activewindow)
window_class=$(printf '%s' "$active_window_json" | jq -r '.class // ""')
window_title=$(printf '%s' "$active_window_json" | jq -r '.title // ""')
window_address=$(printf '%s' "$active_window_json" | jq -r '.address // ""')

# Keep selected webapps alive: hide to scratchpad instead of closing.
# Chromium webapps have dedicated classes; Firefox webapps reuse class "firefox",
# so we detect those by title.
window_title_lc=${window_title,,}
keep_alive_webapp=0

case "$window_class" in
    chrome-gmail.com__-Default|chrome-web.whatsapp.com__-Default)
        keep_alive_webapp=1
        ;;
esac

if [[ "$keep_alive_webapp" == "1" ]]; then
    if [[ -n "$window_address" ]]; then
        hyprctl dispatch movetoworkspacesilent "special:scratchpad,address:$window_address" >/dev/null
    else
        hyprctl dispatch movetoworkspacesilent "special:scratchpad" >/dev/null
    fi
    exit 0
fi

if [[ -n "$window_address" ]]; then
    hyprctl dispatch closewindow "address:$window_address" >/dev/null
else
    hyprctl dispatch killactive >/dev/null
fi

if [[ "$window_class" == "Alacritty" ]]; then
    tmux list-sessions -F '#{session_name}\t#{session_attached}' 2>/dev/null | while IFS=$'\t' read -r session_name attached_count; do
        [[ -z "$session_name" ]] && continue
        [[ "$attached_count" != "0" ]] && continue
        tmux kill-session -t "$session_name" 2>/dev/null || true
    done

    if ! tmux list-clients >/dev/null 2>&1; then
        tmux kill-server 2>/dev/null || true
    fi
fi
