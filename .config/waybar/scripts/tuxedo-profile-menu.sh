#!/usr/bin/env bash

set -euo pipefail

readonly TCC_SERVICE="com.tuxedocomputers.tccd"
readonly TCC_OBJECT_PATH="/com/tuxedocomputers/tccd"
readonly TCC_INTERFACE="com.tuxedocomputers.tccd"

notify_error() {
    notify-send -u critical "TUXEDO profile" "$1"
}

if pgrep -f "walker.*--dmenu" >/dev/null; then
    walker --close >/dev/null 2>&1
    exit 0
fi

for command in busctl jq omarchy-launch-walker; do
    if ! command -v "$command" >/dev/null 2>&1; then
        notify_error "Required command not found: $command"
        exit 1
    fi
done

if ! profiles_reply="$(
    busctl --system --json=short call \
        "$TCC_SERVICE" \
        "$TCC_OBJECT_PATH" \
        "$TCC_INTERFACE" \
        GetProfilesJSON
)"; then
    notify_error "Could not read profiles from TUXEDO Control Center"
    exit 1
fi

if ! active_reply="$(
    busctl --system --json=short call \
        "$TCC_SERVICE" \
        "$TCC_OBJECT_PATH" \
        "$TCC_INTERFACE" \
        GetActiveProfileJSON
)"; then
    notify_error "Could not read the active TUXEDO profile"
    exit 1
fi

if ! profiles_json="$(jq -er '.data[0] | fromjson' <<<"$profiles_reply")" ||
    ! active_id="$(jq -er '.data[0] | fromjson | .id' <<<"$active_reply")"; then
    notify_error "TUXEDO Control Center returned invalid profile data"
    exit 1
fi

mapfile -t profile_names < <(jq -r '.[].name' <<<"$profiles_json")
mapfile -t profile_ids < <(jq -r '.[].id' <<<"$profiles_json")

if ((${#profile_names[@]} == 0)); then
    notify_error "TUXEDO Control Center has no available profiles"
    exit 1
fi

active_index=""
display_names=()
for index in "${!profile_ids[@]}"; do
    if [[ "${profile_ids[$index]}" == "$active_id" ]]; then
        active_index=$((index + 1))
        display_names+=("${profile_names[$index]} (active)")
    else
        display_names+=("${profile_names[$index]}")
    fi
done

walker_args=(
    --dmenu
    --width 295
    --minheight 1
    --maxheight 630
    -p "Power Profile…"
)

if [[ -n "$active_index" ]]; then
    walker_args+=(-c "$active_index")
fi

selection="$(
    printf '%s\n' "${display_names[@]}" |
        omarchy-launch-walker "${walker_args[@]}" 2>/dev/null
)"

[[ -z "$selection" ]] && exit 0

selected_id=""
for index in "${!display_names[@]}"; do
    if [[ "${display_names[$index]}" == "$selection" ]]; then
        selected_id="${profile_ids[$index]}"
        break
    fi
done

if [[ -z "$selected_id" ]]; then
    notify_error "Unknown TUXEDO profile: $selection"
    exit 1
fi

if ! set_reply="$(
    busctl --system --json=short call \
        "$TCC_SERVICE" \
        "$TCC_OBJECT_PATH" \
        "$TCC_INTERFACE" \
        SetTempProfileById \
        s "$selected_id"
)" || ! jq -e '.data[0] == true' >/dev/null <<<"$set_reply"; then
    notify_error "Could not activate TUXEDO profile: $selection"
    exit 1
fi
