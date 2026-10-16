#!/bin/bash

# Focus the WhatsApp Chromium app window if it is open, otherwise launch it.

APP_NAME="WhatsApp"
APP_URL="https://web.whatsapp.com/"
PROFILE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/chromium-pwas/whatsapp"

WINDOW_ADDRESS=$(hyprctl clients -j | jq -r '
    .[]
    | select((((.class // "") | startswith("FFPWA-")) | not))
    | select(
        ((((.class // "") | ascii_downcase) | test("chrome-web\\.whatsapp\\.com|chromiumpwa-whatsapp|chromium-pwa-whatsapp"))
        or (((.title // "") | ascii_downcase) | test("whatsapp|web\\.whatsapp\\.com"))
        or (((.initialTitle // "") | ascii_downcase) | test("whatsapp|web\\.whatsapp\\.com")))
    )
    | .address
' | head -1)

if [[ -n "$WINDOW_ADDRESS" ]]; then
    WORKSPACE_NAME=$(hyprctl clients -j | jq -r --arg addr "$WINDOW_ADDRESS" '.[] | select(.address == $addr) | .workspace.name')
    if [[ "$WORKSPACE_NAME" == special:* ]]; then
        ACTIVE_WINDOW_ADDRESS=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // ""')
        ACTIVE_WORKSPACE_NAME=$(hyprctl activewindow -j 2>/dev/null | jq -r '.workspace.name // ""')

        # The bar button is a toggle: close the special workspace when this
        # webapp is already the active window instead of focusing it again.
        if [[ "$ACTIVE_WINDOW_ADDRESS" == "$WINDOW_ADDRESS" \
            && "$ACTIVE_WORKSPACE_NAME" == "$WORKSPACE_NAME" ]]; then
            hyprctl dispatch "hl.dsp.workspace.toggle_special(\"${WORKSPACE_NAME#special:}\")" >/dev/null 2>&1 || true
            exit 0
        fi

        if [[ "$ACTIVE_WORKSPACE_NAME" != "$WORKSPACE_NAME" ]]; then
            hyprctl dispatch "hl.dsp.workspace.toggle_special(\"${WORKSPACE_NAME#special:}\")" >/dev/null 2>&1 || true
            sleep 0.05
        fi
    elif [[ "$WORKSPACE_NAME" == "special" ]]; then
        ACTIVE_WINDOW_ADDRESS=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // ""')
        ACTIVE_WORKSPACE_NAME=$(hyprctl activewindow -j 2>/dev/null | jq -r '.workspace.name // ""')
        if [[ "$ACTIVE_WINDOW_ADDRESS" == "$WINDOW_ADDRESS" \
            && "$ACTIVE_WORKSPACE_NAME" == "$WORKSPACE_NAME" ]]; then
            hyprctl dispatch 'hl.dsp.workspace.toggle_special("special")' >/dev/null 2>&1 || true
            exit 0
        fi
        if [[ "$ACTIVE_WORKSPACE_NAME" != "$WORKSPACE_NAME" ]]; then
            hyprctl dispatch 'hl.dsp.workspace.toggle_special("special")' >/dev/null 2>&1 || true
            sleep 0.05
        fi
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
