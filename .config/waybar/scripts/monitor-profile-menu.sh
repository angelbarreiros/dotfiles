#!/usr/bin/env bash

set -euo pipefail

PROFILE_SCRIPT="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/monitor-profile.sh"

run_profile() {
    "$PROFILE_SCRIPT" "$@"
}

show_status() {
    if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
        omarchy-launch-floating-terminal-with-presentation "$PROFILE_SCRIPT status"
    else
        run_profile status
    fi
}

selection="$(
    printf '%s\n' \
        "Auto" \
        "Work" \
        "Home" \
        "Travel" \
        "Laptop only" \
        "Learn home from connected external" \
        "Learn travel from connected external" \
        "Status" |
        omarchy-launch-walker --dmenu --nosearch --placeholder "Monitor profile"
)"

case "$selection" in
    Auto) run_profile auto ;;
    Work) run_profile work ;;
    Home) run_profile home ;;
    Travel) run_profile travel ;;
    "Laptop only") run_profile laptop ;;
    "Learn home from connected external") run_profile learn home ;;
    "Learn travel from connected external") run_profile learn travel ;;
    Status) show_status ;;
    "") exit 0 ;;
esac
