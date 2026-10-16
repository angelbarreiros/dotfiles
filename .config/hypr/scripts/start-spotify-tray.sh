#!/usr/bin/env bash

set -u

previous_workspace="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.name // (.id | tostring) // empty')"

# Launch directly so Spotify stays registered with the status notifier. If it
# is already running, continue below and move its existing window instead.
if ! pgrep -x spotify >/dev/null 2>&1; then
    setsid spotify >/dev/null 2>&1 &
fi

for _ in {1..75}; do
    address="$(hyprctl clients -j 2>/dev/null | jq -r '
        .[]
        | select(
            (((.class // "") | ascii_downcase) | contains("spotify"))
            or (((.title // "") | ascii_downcase) | contains("spotify"))
            or (((.initialClass // "") | ascii_downcase) | contains("spotify"))
            or (((.initialTitle // "") | ascii_downcase) | contains("spotify"))
        )
        | .address
    ' | head -n 1)"

    if [[ -n "$address" ]]; then
        hyprctl dispatch movetoworkspacesilent "special:spotify,address:$address" >/dev/null 2>&1 || true
        if [[ -n "$previous_workspace" ]]; then
            hyprctl dispatch workspace "$previous_workspace" >/dev/null 2>&1 || true
        fi
        exit 0
    fi

    sleep 0.2
done
