#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDOW_CLASS="TUI.float"
WINDOW_TITLE="Notification Center"
PROJECT_BIN="$SCRIPT_DIR/../notification-center-tui/target/release/omarchy-notification-center"
APP_BIN="$HOME/.local/bin/omarchy-notification-center"

if [[ -x "$PROJECT_BIN" ]]; then
	APP_CMD="$PROJECT_BIN"
elif [[ -x "$APP_BIN" ]]; then
	APP_CMD="$APP_BIN"
else
	APP_CMD="$SCRIPT_DIR/notification-center.sh"
fi

WINDOW_ADDRESS=$(hyprctl clients -j | jq -r --arg cls "$WINDOW_CLASS" --arg title "$WINDOW_TITLE" '.[] | select((.class == $cls) and ((.title // "") | test($title; "i"))) | .address' | head -n1)

if [[ -n "$WINDOW_ADDRESS" ]]; then
	hyprctl dispatch focuswindow "address:$WINDOW_ADDRESS" >/dev/null 2>&1 || true
	hyprctl dispatch bringactivetotop >/dev/null 2>&1 || true
	exit 0
fi

exec setsid uwsm-app -- xdg-terminal-exec --app-id="$WINDOW_CLASS" --title="$WINDOW_TITLE" -e "$APP_CMD"
