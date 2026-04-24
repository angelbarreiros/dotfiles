#!/bin/bash

set -euo pipefail

NOTIFICATION_SCRIPT="$HOME/.config/waybar/scripts/notification-count.sh"
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-mark-focused-notifications-read.lock"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

mark_seen() {
    "$NOTIFICATION_SCRIPT" mark-focused-app-seen >/dev/null 2>&1 || true
}

# Prefer Hyprland event socket so updates happen only on focus changes.
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -S "$SOCKET_PATH" && -x "$(command -v socat 2>/dev/null || true)" ]]; then
    socat -U - "UNIX-CONNECT:$SOCKET_PATH" 2>/dev/null | while IFS= read -r event_line; do
        case "$event_line" in
            activewindow*|activewindowv2*)
                mark_seen
                ;;
        esac
    done
    exit 0
fi

# Fallback polling if socket or socat is unavailable.
last_window_address=""
while true; do
    current_window_address=$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // ""' || echo "")
    if [[ -n "$current_window_address" && "$current_window_address" != "$last_window_address" ]]; then
        mark_seen
        last_window_address="$current_window_address"
    fi
    sleep 1
done
