#!/bin/bash

set -euo pipefail

app="${1:-}"
mode="${2:-status}"

case "$app" in
    gmail)
        label="Gmail"
        pattern="gmail|mail\\.google\\.com|correo de"
        class_pattern="chrome-mail\\.google\\.com|chromiumpwa-gmail|chromium-pwa-gmail"
        ;;
    whatsapp)
        label="WhatsApp"
        pattern="whatsapp|web\\.whatsapp\\.com"
        class_pattern="chrome-web\\.whatsapp\\.com|chromiumpwa-whatsapp|chromium-pwa-whatsapp"
        ;;
    *)
        echo "Usage: pwa-tray-icon.sh <gmail|whatsapp> [running]" >&2
        exit 2
        ;;
esac

client_json=$(hyprctl -j clients 2>/dev/null | jq -c --arg pattern "$pattern" --arg class_pattern "$class_pattern" '
    [
        .[]
        | select((((.class // "") | startswith("FFPWA-")) | not))
        | select(
            ((((.class // "") | ascii_downcase) | test($class_pattern))
            or (((.title // "") | ascii_downcase) | test($pattern))
            or (((.initialTitle // "") | ascii_downcase) | test($pattern)))
        )
    ] | first // null
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
