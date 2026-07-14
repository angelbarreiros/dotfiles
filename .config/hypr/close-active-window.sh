#!/bin/bash

set -euo pipefail

active_window_json=$(hyprctl -j activewindow)
window_class=$(printf '%s' "$active_window_json" | jq -r '.class // ""')
window_address=$(printf '%s' "$active_window_json" | jq -r '.address // ""')
window_workspace=$(printf '%s' "$active_window_json" | jq -r '.workspace.name // ""')
window_title=$(printf '%s' "$active_window_json" | jq -r '.title // ""')
window_initial_title=$(printf '%s' "$active_window_json" | jq -r '.initialTitle // ""')

window_class_lc="${window_class,,}"
window_title_lc="${window_title,,}"
window_initial_title_lc="${window_initial_title,,}"

is_webapp=false
if [[ "$window_class_lc" == chromiumpwa-* \
    || "$window_class_lc" == chrome-mail.google.com* \
    || "$window_class_lc" == chrome-web.whatsapp.com* \
    || "$window_title_lc" == *gmail* \
    || "$window_title_lc" == *mail.google.com* \
    || "$window_title_lc" == *whatsapp* \
    || "$window_title_lc" == *web.whatsapp.com* \
    || "$window_initial_title_lc" == *gmail* \
    || "$window_initial_title_lc" == *mail.google.com* \
    || "$window_initial_title_lc" == *whatsapp* \
    || "$window_initial_title_lc" == *web.whatsapp.com* ]]; then
    is_webapp=true
fi

if [[ "$is_webapp" == true ]]; then
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
fi

if [[ -n "$window_address" ]]; then
    hyprctl dispatch closewindow "address:$window_address" >/dev/null
else
    hyprctl dispatch killactive >/dev/null
fi
