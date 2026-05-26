#!/usr/bin/env bash

set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_FILE="$CONFIG_HOME/hypr/monitor-profiles.conf"
LOCAL_CONFIG_FILE="$CONFIG_HOME/hypr/monitor-profiles.local.conf"
STATE_DIR="$STATE_HOME/hypr-monitor-profiles"
LOCK_FILE="$STATE_DIR/daemon.lock"

INTERNAL_MONITOR="eDP-1"
LAPTOP_LOGICAL_WIDTH=1440
LAPTOP_LOGICAL_HEIGHT=900
LAPTOP_SCALE=2
WORK_LEFT_DESC=""
WORK_RIGHT_DESC=""
HOME_DESC=""
TRAVEL_DESC=""
UNKNOWN_SINGLE_EXTERNAL_PROFILE="home"
POLL_INTERVAL=2

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
[[ -f "$LOCAL_CONFIG_FILE" ]] && source "$LOCAL_CONFIG_FILE"

usage() {
    cat <<EOF
Usage: $(basename "$0") COMMAND

Commands:
  auto           Detect and apply the best monitor profile
  daemon         Watch monitor changes and run auto when needed
  work           Apply laptop + two externals above/right
  home           Apply one external above the laptop
  travel         Apply one external to the right of the laptop
  laptop         Apply laptop-only layout
  learn home     Save the currently connected external as the home monitor
  learn travel   Save the currently connected external as the travel monitor
  status         Show connected monitors and learned profiles
EOF
}

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $1" >&2
        exit 1
    }
}

json_monitors() {
    hyprctl -j monitors all
}

monitor_signature() {
    json_monitors | jq -r --arg internal "$INTERNAL_MONITOR" '
        [.[] | select(.disabled == false) | "\(.name)|\(.description)|\(.width)x\(.height)@\(.refreshRate)|scale=\(.scale)"]
        | sort
        | join("\n")
    '
}

external_count() {
    jq -r --arg internal "$INTERNAL_MONITOR" '
        [.[] | select(.disabled == false and .name != $internal)] | length
    '
}

connected_desc() {
    local desc="$1"
    [[ -n "$desc" ]] || return 1

    json_monitors | jq -e --arg desc "$desc" '
        any(.[]; .disabled == false and .description == $desc)
    ' >/dev/null
}

external_json_by_desc() {
    local desc="$1"

    json_monitors | jq -c --arg internal "$INTERNAL_MONITOR" --arg desc "$desc" '
        .[] | select(.disabled == false and .name != $internal and .description == $desc)
    ' | head -n 1
}

external_json_by_index() {
    local index="$1"

    json_monitors | jq -c --arg internal "$INTERNAL_MONITOR" --argjson index "$index" '
        [.[] | select(.disabled == false and .name != $internal)]
        | sort_by(.name)
        | .[$index]
    '
}

target_for_json() {
    jq -r '
        if (.description // "") != "" then
            "desc:" + .description
        else
            .name
        end
    '
}

logical_height_for_json() {
    jq -r '((.height / .scale) | floor)'
}

first_external_json() {
    local json

    json="$(external_json_by_index 0)"
    [[ "$json" != "null" && -n "$json" ]] || return 1
    printf '%s\n' "$json"
}

profile_external_json() {
    local preferred_desc="$1"
    local json=""

    if [[ -n "$preferred_desc" ]]; then
        json="$(external_json_by_desc "$preferred_desc" || true)"
    fi

    if [[ -z "$json" || "$json" == "null" ]]; then
        json="$(first_external_json || true)"
    fi

    [[ -n "$json" && "$json" != "null" ]] || {
        echo "ERROR: no external monitor is connected" >&2
        return 1
    }

    printf '%s\n' "$json"
}

keyword_monitor() {
    local rule="$1"
    hyprctl keyword monitor "$rule" >/dev/null
}

notify_profile() {
    local message="$1"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u low "Monitor profile" "$message" >/dev/null 2>&1 || true
    fi
}

apply_laptop() {
    keyword_monitor "$INTERNAL_MONITOR,preferred,0x0,$LAPTOP_SCALE"
    notify_profile "Laptop"
    echo "Applied laptop profile"
}

apply_work() {
    local left_json right_json left_target right_target

    if connected_desc "$WORK_LEFT_DESC" && connected_desc "$WORK_RIGHT_DESC"; then
        left_target="desc:$WORK_LEFT_DESC"
        right_target="desc:$WORK_RIGHT_DESC"
    else
        left_json="$(external_json_by_index 0)"
        right_json="$(external_json_by_index 1)"

        [[ "$left_json" != "null" && "$right_json" != "null" ]] || {
            echo "ERROR: work profile needs two external monitors" >&2
            return 1
        }

        left_target="$(printf '%s\n' "$left_json" | target_for_json)"
        right_target="$(printf '%s\n' "$right_json" | target_for_json)"
    fi

    keyword_monitor "$left_target,preferred,1440x0,1,vrr,1"
    keyword_monitor "$right_target,preferred,3360x0,1,vrr,1"
    keyword_monitor "$INTERNAL_MONITOR,preferred,1440x1080,$LAPTOP_SCALE"
    notify_profile "Work"
    echo "Applied work profile"
}

apply_home() {
    local external_json external_target external_height

    external_json="$(profile_external_json "$HOME_DESC")"
    external_target="$(printf '%s\n' "$external_json" | target_for_json)"
    external_height="$(printf '%s\n' "$external_json" | logical_height_for_json)"

    keyword_monitor "$external_target,preferred,0x0,1"
    keyword_monitor "$INTERNAL_MONITOR,preferred,0x${external_height},$LAPTOP_SCALE"
    notify_profile "Home"
    echo "Applied home profile"
}

apply_travel() {
    local external_json external_target

    external_json="$(profile_external_json "$TRAVEL_DESC")"
    external_target="$(printf '%s\n' "$external_json" | target_for_json)"

    keyword_monitor "$INTERNAL_MONITOR,preferred,0x0,$LAPTOP_SCALE"
    keyword_monitor "$external_target,preferred,${LAPTOP_LOGICAL_WIDTH}x0,1"
    notify_profile "Travel"
    echo "Applied travel profile"
}

apply_auto() {
    local count

    if connected_desc "$WORK_LEFT_DESC" && connected_desc "$WORK_RIGHT_DESC"; then
        apply_work
        return
    fi

    if connected_desc "$HOME_DESC"; then
        apply_home
        return
    fi

    if connected_desc "$TRAVEL_DESC"; then
        apply_travel
        return
    fi

    count="$(json_monitors | external_count)"
    case "$count" in
        0)
            apply_laptop
            ;;
        1)
            case "$UNKNOWN_SINGLE_EXTERNAL_PROFILE" in
                travel) apply_travel ;;
                home|*) apply_home ;;
            esac
            ;;
        *)
            apply_work
            ;;
    esac
}

learn_profile() {
    local profile="$1"
    local external_json desc key tmp_file

    case "$profile" in
        home) key="HOME_DESC" ;;
        travel) key="TRAVEL_DESC" ;;
        *)
            echo "ERROR: learn only supports 'home' or 'travel'" >&2
            exit 1
            ;;
    esac

    if [[ "$(json_monitors | external_count)" != "1" ]]; then
        echo "ERROR: connect exactly one external monitor before learning $profile" >&2
        exit 1
    fi

    external_json="$(first_external_json)"
    desc="$(printf '%s\n' "$external_json" | jq -r '.description')"

    [[ -n "$desc" && "$desc" != "null" ]] || {
        echo "ERROR: connected external monitor has no description to learn" >&2
        exit 1
    }

    mkdir -p "$(dirname "$LOCAL_CONFIG_FILE")"
    tmp_file="$(mktemp)"

    if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
        grep -v "^${key}=" "$LOCAL_CONFIG_FILE" >"$tmp_file" || true
    fi

    printf '%s=%q\n' "$key" "$desc" >>"$tmp_file"
    mv "$tmp_file" "$LOCAL_CONFIG_FILE"

    echo "Learned $profile monitor: $desc"
    apply_auto
}

show_status() {
    echo "Connected monitors:"
    json_monitors | jq -r '
        .[] | select(.disabled == false)
        | "  \(.name): \(.description) at \(.x)x\(.y), \(.width)x\(.height), scale \(.scale)"
    '
    echo
    echo "Configured profiles:"
    echo "  work left:  ${WORK_LEFT_DESC:-unconfigured}"
    echo "  work right: ${WORK_RIGHT_DESC:-unconfigured}"
    echo "  home:       ${HOME_DESC:-not learned}"
    echo "  travel:     ${TRAVEL_DESC:-not learned}"
    echo "  fallback:   unknown single external -> $UNKNOWN_SINGLE_EXTERNAL_PROFILE"
}

run_daemon() {
    mkdir -p "$STATE_DIR"
    exec 9>"$LOCK_FILE"
    flock -n 9 || exit 0

    local previous current
    apply_auto || true
    previous="$(monitor_signature || true)"

    while sleep "$POLL_INTERVAL"; do
        current="$(monitor_signature || true)"
        if [[ "$current" != "$previous" ]]; then
            apply_auto || true
            previous="$current"
        fi
    done
}

main() {
    need hyprctl
    need jq

    case "${1:-auto}" in
        auto) apply_auto ;;
        daemon) run_daemon ;;
        work) apply_work ;;
        home) apply_home ;;
        travel) apply_travel ;;
        laptop) apply_laptop ;;
        learn)
            [[ $# -eq 2 ]] || {
                usage >&2
                exit 1
            }
            learn_profile "$2"
            ;;
        status) show_status ;;
        -h|--help|help) usage ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
