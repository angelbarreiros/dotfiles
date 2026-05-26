#!/bin/bash

# Return the FFPWA ULID for an installed PWA by its name.
# Usage: firefoxpwa-get-ulid.sh <AppName>
# Exit 1 if not found.

APP_NAME="$1"

if [[ -z "$APP_NAME" ]]; then
    echo "Usage: firefoxpwa-get-ulid.sh <AppName>" >&2
    exit 1
fi

DESKTOP_FILE=$(grep -rl "^Name=${APP_NAME}$" ~/.local/share/applications/*.desktop 2>/dev/null | head -1)

if [[ -n "$DESKTOP_FILE" ]]; then
    ULID=$(sed -n 's/^StartupWMClass=FFPWA-\(.*\)$/\1/p' "$DESKTOP_FILE" | head -1)
    if [[ -z "$ULID" ]]; then
        ULID=$(sed -n 's/^Exec=.*firefoxpwa site launch \([^ ]*\).*$/\1/p' "$DESKTOP_FILE" | head -1)
    fi
else
    ULID=""
fi

if [[ -z "$ULID" ]]; then
    echo "firefoxpwa-get-ulid: no PWA named '${APP_NAME}' found" >&2
    exit 1
fi

echo "$ULID"
