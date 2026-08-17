#!/usr/bin/env bash

# Focus an application represented by a StatusNotifier item, or launch it when
# it has no mapped window. Unknown/system tray indicators are intentionally
# ignored; their native tray activation remains responsible for them.

set -u

identity="$(printf '%s ' "$@" | tr '[:upper:]' '[:lower:]')"

case "$identity" in
    *bluetooth*|*network*|*wifi*|*audio*|*volume*|*microphone*|*battery*|*power*|*display*|*monitor*|*keyboard*|*agent*|*update*|*tray*)
        exit 0
        ;;
esac

pattern=""
desktop_id=""

case "$identity" in
    *spotify*)
        pattern="spotify"
        desktop_id="spotify"
        ;;
    *tuxedo*|*tcc*)
        pattern="tuxedo-control-center"
        desktop_id="tuxedo-control-center"
        ;;
    *)
        for value in "$@"; do
            candidate="$(printf '%s' "$value" \
                | tr '[:upper:]' '[:lower:]' \
                | sed -E 's/(_status_icon|_status|[-_]indicator|[-_]tray|[-_]client)$//; s/[^a-z0-9.-]+/-/g; s/^-+|-+$//g')"
            [[ -z "$candidate" ]] && continue
            if [[ -f "/usr/share/applications/$candidate.desktop" \
                || -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/$candidate.desktop" ]]; then
                pattern="$candidate"
                desktop_id="$candidate"
                break
            fi
        done
        ;;
esac

[[ -z "$pattern" || -z "$desktop_id" ]] && exit 0

window_address="$(hyprctl clients -j 2>/dev/null | jq -r --arg pattern "$pattern" '
    .[]
    | select(
        (((.class // "") | ascii_downcase) | contains($pattern))
        or (((.title // "") | ascii_downcase) | contains($pattern))
        or (((.initialClass // "") | ascii_downcase) | contains($pattern))
        or (((.initialTitle // "") | ascii_downcase) | contains($pattern))
    )
    | .address
' | head -n 1)"

if [[ -n "$window_address" ]]; then
    workspace_name="$(hyprctl clients -j 2>/dev/null | jq -r --arg address "$window_address" '.[] | select(.address == $address) | .workspace.name' | head -n 1)"
    if [[ "$workspace_name" == special:* ]]; then
        hyprctl dispatch "hl.dsp.workspace.toggle_special(\"${workspace_name#special:}\")" >/dev/null 2>&1 || true
        sleep 0.05
    elif [[ "$workspace_name" == "special" ]]; then
        hyprctl dispatch 'hl.dsp.workspace.toggle_special("special")' >/dev/null 2>&1 || true
        sleep 0.05
    fi
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$window_address\" })" >/dev/null 2>&1 \
        || hyprctl dispatch focuswindow "address:$window_address" >/dev/null 2>&1 || true
    exit 0
fi

exec setsid uwsm-app -- gtk-launch "$desktop_id"
