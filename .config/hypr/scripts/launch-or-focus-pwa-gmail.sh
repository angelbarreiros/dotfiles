#!/bin/bash

# Focus the Gmail PWA if it's open, otherwise launch it via PWAsForFirefox.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ULID="$("$SCRIPT_DIR/firefoxpwa-get-ulid.sh" "Gmail")"
if [[ $? -ne 0 || -z "$ULID" ]]; then
    notify-send -u critical "Gmail PWA" "Gmail is not installed via PWAsForFirefox. Install it first with the Firefox extension."
    exit 1
fi

CLASS="FFPWA-${ULID}"

WINDOW_ADDRESS=$(hyprctl clients -j | jq -r --arg c "$CLASS" '.[] | select(.class == $c) | .address' | head -1)

if [[ -n "$WINDOW_ADDRESS" ]]; then
    if command -v wlrctl >/dev/null 2>&1; then
        wlrctl window focus "app_id:${CLASS}" >/dev/null 2>&1 && exit 0
    fi

    WORKSPACE_NAME=$(hyprctl clients -j | jq -r --arg addr "$WINDOW_ADDRESS" '.[] | select(.address == $addr) | .workspace.name')
    if [[ "$WORKSPACE_NAME" == special:* ]]; then
        hyprctl dispatch togglespecialworkspace "${WORKSPACE_NAME#special:}" >/dev/null 2>&1 || true
        sleep 0.05
    elif [[ "$WORKSPACE_NAME" == "special" ]]; then
        hyprctl dispatch togglespecialworkspace >/dev/null 2>&1 || true
        sleep 0.05
    fi
    hyprctl dispatch focuswindow "address:${WINDOW_ADDRESS}"
else
    exec setsid uwsm-app -- firefoxpwa site launch "$ULID"
fi
