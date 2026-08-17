#!/bin/bash

# Focus the Gmail Chromium app window if it is open, otherwise launch it.

APP_NAME="Gmail"
APP_URL="https://mail.google.com/mail/u/0/"
PROFILE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/chromium-pwas/gmail"

WINDOW_ADDRESS=$(hyprctl clients -j | jq -r '
    .[]
    | select((((.class // "") | startswith("FFPWA-")) | not))
    | select(
        ((((.class // "") | ascii_downcase) | test("chrome-mail\\.google\\.com|chromiumpwa-gmail|chromium-pwa-gmail"))
        or (((.title // "") | ascii_downcase) | test("gmail|mail\\.google\\.com|correo de"))
        or (((.initialTitle // "") | ascii_downcase) | test("gmail|mail\\.google\\.com")))
    )
    | .address
' | head -1)

if [[ -n "$WINDOW_ADDRESS" ]]; then
    if command -v wlrctl >/dev/null 2>&1; then
        wlrctl window focus "app_id:${CLASS}" >/dev/null 2>&1 && exit 0
    fi

    WORKSPACE_NAME=$(hyprctl clients -j | jq -r --arg addr "$WINDOW_ADDRESS" '.[] | select(.address == $addr) | .workspace.name')
    if [[ "$WORKSPACE_NAME" == special:* ]]; then
        hyprctl dispatch "hl.dsp.workspace.toggle_special(\"${WORKSPACE_NAME#special:}\")" >/dev/null 2>&1 || true
        sleep 0.05
    elif [[ "$WORKSPACE_NAME" == "special" ]]; then
        hyprctl dispatch 'hl.dsp.workspace.toggle_special("special")' >/dev/null 2>&1 || true
        sleep 0.05
    fi
    hyprctl dispatch "hl.dsp.focus({ window = \"address:${WINDOW_ADDRESS}\" })"
else
    mkdir -p "$PROFILE_DIR"
    exec setsid uwsm-app -- chromium \
        --app="$APP_URL" \
        --name="$APP_NAME" \
        --user-data-dir="$PROFILE_DIR" \
        --no-first-run \
        --no-default-browser-check \
        --disable-background-mode \
        --ozone-platform=wayland
fi
