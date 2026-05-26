#!/bin/bash

set -euo pipefail

active_window_json=$(hyprctl -j activewindow)
window_class=$(printf '%s' "$active_window_json" | jq -r '.class // ""')
window_address=$(printf '%s' "$active_window_json" | jq -r '.address // ""')
window_workspace=$(printf '%s' "$active_window_json" | jq -r '.workspace.name // ""')

case "$window_class" in
    FFPWA-*)
        if command -v wlrctl >/dev/null 2>&1; then
            wlrctl window minimize "app_id:${window_class}" state:active >/dev/null 2>&1 && exit 0
            wlrctl window minimize "app_id:${window_class}" >/dev/null 2>&1 && exit 0
        fi

        if [[ "$window_workspace" == "special:webapps" ]]; then
            hyprctl dispatch togglespecialworkspace webapps >/dev/null
        elif [[ -n "$window_address" ]]; then
            hyprctl dispatch movetoworkspacesilent "special:webapps,address:$window_address" >/dev/null
        else
            hyprctl dispatch movetoworkspacesilent "special:webapps" >/dev/null
        fi
        exit 0
        ;;
esac

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
