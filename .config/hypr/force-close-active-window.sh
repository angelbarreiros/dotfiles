#!/bin/bash

set -euo pipefail

active_window_json=$(hyprctl -j activewindow)
window_class=$(printf '%s' "$active_window_json" | jq -r '.class // ""')
window_address=$(printf '%s' "$active_window_json" | jq -r '.address // ""')

if [[ -n "$window_address" ]]; then
    hyprctl dispatch closewindow "address:$window_address" >/dev/null
else
    hyprctl dispatch killactive >/dev/null
fi
