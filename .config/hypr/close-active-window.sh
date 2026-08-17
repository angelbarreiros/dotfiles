#!/bin/bash

set -euo pipefail

active_window_json=$(hyprctl -j activewindow)

# The Omarchy 4 menu is a Quickshell layer, so ask the menu plugin directly
# whether it is open before falling back to Hyprland's layer list.
menu_state=$(omarchy-shell shell call omarchy.menu state "{}" 2>/dev/null || true)
if [[ "$menu_state" == "open" ]]; then
    omarchy-menu close >/dev/null 2>&1 || true
    exit 0
fi

# Omarchy 4's menu is a layer surface rather than a normal Hyprland window.
# Close it explicitly when SUPER+W is pressed, otherwise continue with the
# normal active-window/webapp behavior below.
if hyprctl -j layers 2>/dev/null | jq -e '
    .. | objects
    | select(.namespace? == "omarchy-menu")
    | select((.mapped? // false) == true or (.visible? // false) == true)
' >/dev/null 2>&1; then
    omarchy-menu close >/dev/null 2>&1 || true
    exit 0
fi

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
        hyprctl dispatch 'hl.dsp.workspace.toggle_special("webapps")' >/dev/null
    else
        hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:webapps", follow = false })' >/dev/null
    fi
    exit 0
fi

hyprctl dispatch 'hl.dsp.window.close()' >/dev/null
