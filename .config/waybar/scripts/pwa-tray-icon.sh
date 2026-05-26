#!/bin/bash

set -euo pipefail

app="${1:-}"
mode="${2:-status}"

case "$app" in
    gmail)
        class_name="FFPWA-01KQYXB3Z3YD5GYT1AK67S7Z2D"
        label="Gmail"
        ;;
    whatsapp)
        class_name="FFPWA-01KQYXB8RBA9AKZET0AX4MJXBS"
        label="WhatsApp"
        ;;
    *)
        echo "Usage: pwa-tray-icon.sh <gmail|whatsapp> [running]" >&2
        exit 2
        ;;
esac

client_json=$(hyprctl -j clients 2>/dev/null | jq -c --arg class_name "$class_name" '
    [.[] | select(.class == $class_name)] | first // null
')

if [[ "$client_json" == "null" || -z "$client_json" ]]; then
    exit 1
fi

if [[ "$mode" == "running" ]]; then
    exit 0
fi

title=$(printf '%s' "$client_json" | jq -r '.title // ""')
workspace=$(printf '%s' "$client_json" | jq -r '.workspace.name // ""')
class="active"

if [[ "$workspace" == special:* || "$workspace" == "special" ]]; then
    class="minimized"
fi

jq -nc \
    --arg text " " \
    --arg tooltip "$label${title:+ - $title}" \
    --arg class "$class" \
    '{text: $text, tooltip: $tooltip, class: $class}'
