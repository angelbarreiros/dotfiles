#!/usr/bin/env bash

set -u

SERVICE="com.tuxedocomputers.tccd"
OBJECT="/com/tuxedocomputers/tccd"
INTERFACE="com.tuxedocomputers.tccd"

profile_json() {
    gdbus call --system \
        --dest "$SERVICE" \
        --object-path "$OBJECT" \
        --method "$INTERFACE.$1" \
        | sed -e "s/^('//" -e "s/',)$//"
}

case "${1:-}" in
    list)
        profile_json GetProfilesJSON
        ;;
    active)
        profile_json GetActiveProfileJSON
        ;;
    set)
        [[ -n "${2:-}" ]] || exit 2
        gdbus call --system \
            --dest "$SERVICE" \
            --object-path "$OBJECT" \
            --method "$INTERFACE.SetTempProfileById" \
            "$2" >/dev/null
        ;;
    *)
        printf 'Usage: %s {list|active|set PROFILE_ID}\n' "$0" >&2
        exit 2
        ;;
esac
