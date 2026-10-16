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
WORK_ABOVE_DESC=""
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
  work           Apply laptop + one external above and one to the right
  home           Apply one external above the laptop
  travel         Apply one external to the right of the laptop
  laptop         Apply laptop-only layout
  active         Print the currently active layout profile
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
        [.[] | select(.disabled == false) | "\(.name)|\(.description)|\(.width)x\(.height)@\(.refreshRate)|scale=\(.scale)|position=\(.x)x\(.y)"]
        | sort
        | join("\n")
    '
}

external_count() {
    jq -r --arg internal "$INTERNAL_MONITOR" '
        [.[] | select(.disabled == false and .name != $internal)] | length
    '
}

active_profile() {
    json_monitors | jq -r --arg internal "$INTERNAL_MONITOR" --argjson laptop_width "$LAPTOP_LOGICAL_WIDTH" '
        [ .[] | select(.disabled == false) ] as $enabled
        | ($enabled | map(select(.name != $internal))) as $external
        | ($enabled | map(select(.name == $internal)) | first) as $laptop
        | if $laptop == null then
            "unknown"
          elif ($external | length) == 0 then
            "laptop"
          elif ($external | length) >= 2 then
            "work"
          elif ($external[0].x == 0 and $external[0].y == 0
                and ($laptop.y // 0) > 0) then
            "home"
          elif ($laptop.x == 0 and $laptop.y == 0
                and $external[0].x == $laptop_width and $external[0].y == 0) then
            "travel"
          else
            "unknown"
          end
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

name_for_json() {
    jq -r '.name'
}

logical_height_for_json() {
    jq -r '((.height / .scale) | floor)'
}

logical_width_for_scale_json() {
    local scale="$1"

    jq -r --argjson scale "$scale" '((.width / $scale) | floor)'
}

logical_height_for_scale_json() {
    local scale="$1"

    jq -r --argjson scale "$scale" '((.height / $scale) | floor)'
}

mode_for_json() {
    jq -r '"\(.width)x\(.height)@\(.refreshRate)"' | sed -E 's/\.?0+$//'
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

apply_monitor() {
    local output="$1"
    local mode="$2"
    local position="$3"
    local scale="$4"

    # Omarchy 4 uses the Lua parser; the legacy `hyprctl keyword monitor`
    # command is rejected and silently leaves the old position in place.
    hyprctl eval "hl.monitor({ output = \"$output\", mode = \"$mode\", position = \"$position\", scale = $scale })" >/dev/null
}

focus_workspace() {
    local workspace="$1"

    hyprctl dispatch "hl.dsp.focus({ workspace = \"$workspace\" })" >/dev/null || true
}

set_workspace_rule() {
    local workspace="$1"
    local monitor="$2"

    # Keep the assignment declarative so a monitor wake/reload does not leave
    # the workspace on whichever monitor Hyprland chose temporarily.
    hyprctl eval "hl.workspace_rule({ workspace = \"$workspace\", monitor = \"$monitor\", default = true })" >/dev/null || true
}

move_current_workspace_to_monitor() {
    local monitor="$1"

    hyprctl dispatch "hl.dsp.workspace.move({ monitor = \"$monitor\" })" >/dev/null || true
}

pin_workspace_to_monitor() {
    local workspace="$1"
    local monitor="$2"

    set_workspace_rule "$workspace" "$monitor"
    focus_workspace "$workspace"
    sleep 0.05
    move_current_workspace_to_monitor "$monitor"
}

pin_single_external_workspaces() {
    local external_name="$1"

    pin_workspace_to_monitor 1 "$INTERNAL_MONITOR"
    pin_workspace_to_monitor 2 "$external_name"
    focus_workspace 1
}

notify_profile() {
    local message="$1"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u low "Monitor profile" "$message" >/dev/null 2>&1 || true
    fi
}

apply_laptop() {
    local laptop_json laptop_mode

    laptop_json="$(json_monitors | jq -c --arg internal "$INTERNAL_MONITOR" '.[] | select(.disabled == false and .name == $internal)')"
    laptop_mode="$(printf '%s\n' "$laptop_json" | mode_for_json)"
    apply_monitor "$INTERNAL_MONITOR" "$laptop_mode" "0x0" "$LAPTOP_SCALE"
    notify_profile "Laptop"
    echo "Applied laptop profile"
}

apply_work() {
    local above_json right_json above_name right_name
    local laptop_json above_width above_height laptop_x laptop_y
    local above_mode right_mode laptop_mode above_scale right_scale laptop_scale

    if connected_desc "$WORK_ABOVE_DESC" && connected_desc "$WORK_RIGHT_DESC"; then
        above_json="$(external_json_by_desc "$WORK_ABOVE_DESC")"
        right_json="$(external_json_by_desc "$WORK_RIGHT_DESC")"
        above_name="$(printf '%s\n' "$above_json" | name_for_json)"
        right_name="$(printf '%s\n' "$right_json" | name_for_json)"
    else
        above_json="$(external_json_by_index 0)"
        right_json="$(external_json_by_index 1)"

        [[ "$above_json" != "null" && "$right_json" != "null" ]] || {
            echo "ERROR: work profile needs two external monitors" >&2
            return 1
        }

        above_name="$(printf '%s\n' "$above_json" | name_for_json)"
        right_name="$(printf '%s\n' "$right_json" | name_for_json)"
    fi

    laptop_json="$(json_monitors | jq -c --arg internal "$INTERNAL_MONITOR" '.[] | select(.disabled == false and .name == $internal)')"
    above_mode="$(printf '%s\n' "$above_json" | mode_for_json)"
    right_mode="$(printf '%s\n' "$right_json" | mode_for_json)"
    laptop_mode="$(printf '%s\n' "$laptop_json" | mode_for_json)"
    # External displays are intentionally kept at native 1x. Do not inherit
    # a stale scale from the boot-time wildcard monitor rule.
    above_scale="1"
    right_scale="1"
    laptop_scale="$(printf '%s\n' "$laptop_json" | jq -r '.scale')"
    above_width="$(printf '%s\n' "$above_json" | logical_width_for_scale_json "$above_scale")"
    above_height="$(printf '%s\n' "$above_json" | logical_height_for_scale_json "$above_scale")"
    laptop_x="0"
    laptop_y="$above_height"

    # Keep the laptop directly below the first configured work monitor, with
    # the second external to its right.
    apply_monitor "$above_name" "$above_mode" "0x0" "$above_scale"
    apply_monitor "$right_name" "$right_mode" "${above_width}x0" "$right_scale"
    apply_monitor "$INTERNAL_MONITOR" "$laptop_mode" "${laptop_x}x${laptop_y}" "$laptop_scale"
    pin_workspace_to_monitor 1 "$INTERNAL_MONITOR"
    pin_workspace_to_monitor 2 "$above_name"
    pin_workspace_to_monitor 3 "$right_name"
    focus_workspace 1
    notify_profile "Work"
    echo "Applied work profile"
}

apply_home() {
    local external_json external_name external_target external_height external_mode laptop_json laptop_mode

    external_json="$(profile_external_json "$HOME_DESC")"
    external_name="$(printf '%s\n' "$external_json" | name_for_json)"
    external_target="$(printf '%s\n' "$external_json" | target_for_json)"
    external_height="$(printf '%s\n' "$external_json" | logical_height_for_json)"
    external_mode="$(printf '%s\n' "$external_json" | mode_for_json)"
    laptop_json="$(json_monitors | jq -c --arg internal "$INTERNAL_MONITOR" '.[] | select(.disabled == false and .name == $internal)')"
    laptop_mode="$(printf '%s\n' "$laptop_json" | mode_for_json)"

    apply_monitor "$external_name" "$external_mode" "0x0" "1"
    apply_monitor "$INTERNAL_MONITOR" "$laptop_mode" "0x${external_height}" "$LAPTOP_SCALE"
    pin_single_external_workspaces "$external_name"
    notify_profile "Home"
    echo "Applied home profile"
}

apply_travel() {
    local external_json external_name external_target external_mode laptop_json laptop_mode

    external_json="$(profile_external_json "$TRAVEL_DESC")"
    external_name="$(printf '%s\n' "$external_json" | name_for_json)"
    external_target="$(printf '%s\n' "$external_json" | target_for_json)"
    external_mode="$(printf '%s\n' "$external_json" | mode_for_json)"
    laptop_json="$(json_monitors | jq -c --arg internal "$INTERNAL_MONITOR" '.[] | select(.disabled == false and .name == $internal)')"
    laptop_mode="$(printf '%s\n' "$laptop_json" | mode_for_json)"

    apply_monitor "$INTERNAL_MONITOR" "$laptop_mode" "0x0" "$LAPTOP_SCALE"
    apply_monitor "$external_name" "$external_mode" "${LAPTOP_LOGICAL_WIDTH}x0" "1"
    pin_single_external_workspaces "$external_name"
    notify_profile "Travel"
    echo "Applied travel profile"
}

apply_auto() {
    local count

    if connected_desc "$WORK_ABOVE_DESC" && connected_desc "$WORK_RIGHT_DESC"; then
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
    echo "  work above: ${WORK_ABOVE_DESC:-unconfigured}"
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
        active) active_profile ;;
        -h|--help|help) usage ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
