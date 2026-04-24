#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/notification-count.sh"

while true; do
    mapfile -t raw_entries < <(list_entries | tail -n +2)

    if [[ ${#raw_entries[@]} -eq 0 ]]; then
        gum style --border rounded --padding "1 2" --margin "1 2" "No notifications found."
        exit 0
    fi

    labels=()
    for entry in "${raw_entries[@]}"; do
        labels+=("${entry#*$'\t'}")
    done

    selection=$(printf '%s\n' "${labels[@]}" | gum filter \
        --header "Notification Center" \
        --prompt 'Notifications > ' \
        --placeholder 'Filter notifications...' \
        --height 22 \
        --indicator '▌' \
        --selected-prefix '◆ ' \
        --unselected-prefix '  ' \
        --header.foreground 219 \
        --indicator.foreground 212 \
        --match.foreground 81 \
        --prompt.foreground 240 \
        --placeholder.foreground 240 \
        --no-strip-ansi) || exit 0

    selected_entry=""
    for entry in "${raw_entries[@]}"; do
        if [[ "${entry#*$'\t'}" == "$selection" ]]; then
            selected_entry="$entry"
            break
        fi
    done

    [[ -n "$selected_entry" ]] || exit 0
    action=${selected_entry%%$'\t'*}

    if [[ "$action" == "clear" ]]; then
        clear_all
        continue
    fi

    if [[ "$action" == open:* ]]; then
        open_notification "${action#open:}"
        exit 0
    fi
done