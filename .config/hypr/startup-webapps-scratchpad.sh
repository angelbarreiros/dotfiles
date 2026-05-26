#!/bin/bash

set -euo pipefail

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
LOG_FILE="$LOG_DIR/startup-webapps-minimized.log"

GMAIL_CLASS="FFPWA-01KQYXB3Z3YD5GYT1AK67S7Z2D"
WHATSAPP_CLASS="FFPWA-01KQYXB8RBA9AKZET0AX4MJXBS"

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

log() {
    printf '[%(%F %T)T] %s\n' -1 "$*" >> "$LOG_FILE"
}

clients_json() {
    hyprctl -j clients 2>/dev/null || echo '[]'
}

app_addresses() {
    local app="$1"
    local addresses

    case "$app" in
        gmail)
            addresses=$(clients_json | jq -r '
                .[]
                | select(
                    (((.title // "") | ascii_downcase) | test("gmail|mail\\.google\\.com"))
                    or (((.initialTitle // "") | ascii_downcase) | test("gmail|mail\\.google\\.com"))
                )
                | .address
            ')

            if [[ -n "$addresses" ]]; then
                printf '%s\n' "$addresses"
                return 0
            fi

            clients_json | jq -r --arg class_name "$GMAIL_CLASS" '
                .[]
                | select(.class == $class_name)
                | select(
                    ((((.title // "") | ascii_downcase) | test("whatsapp|web\\.whatsapp\\.com")) | not)
                    and ((((.initialTitle // "") | ascii_downcase) | test("whatsapp|web\\.whatsapp\\.com")) | not)
                )
                | .address
            '
            ;;
        whatsapp)
            addresses=$(clients_json | jq -r '
                .[]
                | select(
                    (((.title // "") | ascii_downcase) | test("whatsapp|web\\.whatsapp\\.com"))
                    or (((.initialTitle // "") | ascii_downcase) | test("whatsapp|web\\.whatsapp\\.com"))
                )
                | .address
            ')

            if [[ -n "$addresses" ]]; then
                printf '%s\n' "$addresses"
                return 0
            fi

            clients_json | jq -r --arg class_name "$WHATSAPP_CLASS" '
                .[]
                | select(.class == $class_name)
                | select(
                    ((((.title // "") | ascii_downcase) | test("gmail|mail\\.google\\.com")) | not)
                    and ((((.initialTitle // "") | ascii_downcase) | test("gmail|mail\\.google\\.com")) | not)
                )
                | .address
            '
            ;;
    esac
}

app_is_running() {
    local app="$1"

    [[ -n "$(app_addresses "$app")" ]]
}

app_class() {
    local app="$1"

    case "$app" in
        gmail)
            printf '%s\n' "$GMAIL_CLASS"
            ;;
        whatsapp)
            printf '%s\n' "$WHATSAPP_CLASS"
            ;;
    esac
}

wait_for_app() {
    local app="$1"
    local attempts="${2:-80}"
    local delay="${3:-0.25}"
    local i

    for ((i = 0; i < attempts; i++)); do
        if app_is_running "$app"; then
            log "$app window detected"
            return 0
        fi

        sleep "$delay"
    done

    log "timed out waiting for $app"
    return 1
}

launch_app_if_missing() {
    local app="$1"
    local desktop_entry="$2"

    if app_is_running "$app"; then
        log "$app already running"
        return 0
    fi

    log "launching $app with gtk-launch $desktop_entry"
    gtk-launch "$desktop_entry" >/dev/null 2>&1 &
    wait_for_app "$app" || true
}

minimize_app() {
    local app="$1"
    local class_name addresses address

    if ! app_is_running "$app"; then
        log "no $app window found to hide"
        return 1
    fi

    if ! command -v wlrctl >/dev/null 2>&1; then
        addresses=$(app_addresses "$app")
        while IFS= read -r address; do
            [[ -n "$address" ]] || continue
            log "wlrctl missing; moving $app window $address to special:webapps"
            hyprctl dispatch movetoworkspacesilent "special:webapps,address:$address" >/dev/null 2>&1 || true
        done <<< "$addresses"
        return 0
    fi

    class_name=$(app_class "$app")
    log "minimizing $app window with wlrctl"
    wlrctl window minimize "app_id:$class_name" >/dev/null 2>&1 || {
        log "failed to minimize $app"
        return 1
    }
}

main() {
    launch_app_if_missing gmail Gmail
    sleep 1
    launch_app_if_missing whatsapp Whatsapp

    minimize_app gmail || true
    minimize_app whatsapp || true
}

main "$@"
