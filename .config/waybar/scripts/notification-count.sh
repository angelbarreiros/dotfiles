#!/bin/bash

set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
STATE_FILE="$STATE_DIR/mako-unread-state.json"

get_active_notifications() {
    makoctl list -j 2>/dev/null || echo '[]'
}

get_history_notifications() {
    makoctl history -j 2>/dev/null || echo '[]'
}

get_all_notifications() {
    jq -cs 'add | unique_by(.id) | sort_by(.id) | reverse' \
        <(get_active_notifications) \
        <(get_history_notifications)
}

ensure_state() {
    local notifications max_id

    mkdir -p "$STATE_DIR"
    notifications=$(get_all_notifications)

    if [[ ! -f "$STATE_FILE" ]]; then
        max_id=$(echo "$notifications" | jq 'map(.id) | max // 0')
        jq -cn --argjson baseline "$max_id" '{baseline:$baseline,restored:[]}' > "$STATE_FILE"
    fi
}

get_state() {
    ensure_state
    cat "$STATE_FILE"
}

save_state() {
    printf '%s\n' "$1" > "$STATE_FILE"
}

get_seen_ids() {
    get_state | jq '.seen // .restored // []'
}

notification_by_id() {
    local notification_id="$1"

    get_all_notifications | jq -c --argjson notification_id "$notification_id" '.[] | select(.id == $notification_id)' | head -n 1
}

notification_body_host() {
    local notification_json="$1"

    echo "$notification_json" | jq -r '.body // ""' | sed -n '1p' | sed 's/^ *//; s/ *$//'
}

notification_body_text() {
    local notification_json="$1"

    echo "$notification_json" | jq -r '.body // ""' | tr '[:upper:]' '[:lower:]'
}

notification_provider_key() {
    local notification_json="$1"
    local desktop_entry app_name body_host body_text summary_text

    desktop_entry=$(echo "$notification_json" | jq -r '.desktop_entry // empty')
    app_name=$(echo "$notification_json" | jq -r '.app_name // empty')
    body_host=$(notification_body_host "$notification_json")
    body_text=$(notification_body_text "$notification_json")
    summary_text=$(echo "$notification_json" | jq -r '.summary // ""' | tr '[:upper:]' '[:lower:]')

    if [[ "$body_text" == *"web.whatsapp.com"* || "$summary_text" == *"whatsapp"* ]]; then
        echo "site:web.whatsapp.com"
        return 0
    fi

    if [[ "$body_text" == *"mail.google.com"* || "$body_text" == *"gmail.com"* || "$summary_text" == *"gmail"* ]]; then
        echo "site:gmail.com"
        return 0
    fi

    case "$body_host" in
        web.whatsapp.com)
            echo "site:web.whatsapp.com"
            return 0
            ;;
        gmail.com|mail.google.com)
            echo "site:gmail.com"
            return 0
            ;;
    esac

    if [[ -n "$desktop_entry" ]]; then
        echo "desktop:$desktop_entry"
    elif [[ -n "$app_name" ]]; then
        echo "app:$app_name"
    else
        echo "id:$(echo "$notification_json" | jq -r '.id')"
    fi
}

provider_label_from_key() {
    local provider_key="$1"

    case "$provider_key" in
        site:web.whatsapp.com)
            echo "WhatsApp"
            ;;
        site:gmail.com)
            echo "Gmail"
            ;;
        desktop:*)
            echo "${provider_key#desktop:}"
            ;;
        app:*)
            echo "${provider_key#app:}"
            ;;
        *)
            echo "Notification"
            ;;
    esac
}

notification_provider_label() {
    local notification_json="$1"

    provider_label_from_key "$(notification_provider_key "$notification_json")"
}

mark_ids_seen() {
    local ids_json="$1"
    local state updated_state

    state=$(get_state)
    updated_state=$(jq -cn \
        --argjson state "$state" \
        --argjson ids "$ids_json" \
        '{baseline: ($state.baseline // 0), seen: (($state.seen // $state.restored // []) + $ids | unique)}')
    save_state "$updated_state"
}

mark_provider_seen() {
    local provider_key="$1"
    local unread notifications_to_mark ids_json

    unread=$(get_unread_notifications)
    notifications_to_mark=$(while IFS= read -r notification_json; do
        [[ -n "$notification_json" ]] || continue
        if [[ "$(notification_provider_key "$notification_json")" == "$provider_key" ]]; then
            echo "$notification_json"
        fi
    done < <(echo "$unread" | jq -c '.[]'))

    ids_json=$(printf '%s\n' "$notifications_to_mark" | jq -cs 'map(.id)')
    [[ "$ids_json" != "[]" ]] || return 0
    mark_ids_seen "$ids_json"
}

focus_window_by_class() {
    local window_class="$1"
    local window_address workspace_name

    # Find the window by class using hyprctl
    window_address=$(hyprctl -j clients 2>/dev/null | jq -r --arg class "$window_class" '.[] | select(.class == $class) | .address' | head -n 1)

    if [[ -z "$window_address" ]]; then
        return 1  # Window not found
    fi

    workspace_name=$(hyprctl -j clients 2>/dev/null | jq -r --arg addr "$window_address" '.[] | select(.address == $addr) | .workspace.name')

    # For scratchpad windows, show the special workspace first, then focus
    if [[ "$workspace_name" == "special:scratchpad" ]]; then
        hyprctl dispatch togglespecialworkspace scratchpad >/dev/null 2>&1 || true
        sleep 0.05
    fi

    # Hyprland focuswindow switches to the correct workspace automatically
    hyprctl dispatch focuswindow "address:$window_address" >/dev/null 2>&1 || true
    return 0
}

open_source_for_notification() {
    local notification_json="$1"
    local notification_id provider_key desktop_entry is_active

    notification_id=$(echo "$notification_json" | jq -r '.id')
    provider_key=$(notification_provider_key "$notification_json")
    desktop_entry=$(echo "$notification_json" | jq -r '.desktop_entry // empty')
    is_active=$(makoctl list -j 2>/dev/null | jq -r --argjson notification_id "$notification_id" 'any(.[]; .id == $notification_id)')

    case "$provider_key" in
        site:web.whatsapp.com)
            if focus_window_by_class "chrome-web.whatsapp.com__-Default"; then
                return 0
            fi
            uwsm-app -- google-chrome --app="https://web.whatsapp.com/" >/dev/null 2>&1
            return 0
            ;;
        site:gmail.com)
            if focus_window_by_class "chrome-gmail.com__-Default"; then
                return 0
            fi
            uwsm-app -- google-chrome --app="https://mail.google.com/" >/dev/null 2>&1
            return 0
            ;;
        desktop:*)
            # Try to focus an existing window by matching the desktop entry as class name
            if focus_window_by_class "$desktop_entry"; then
                return 0
            fi
            gtk-launch "$desktop_entry" >/dev/null 2>&1
            return 0
            ;;
        app:*)
            local app_name="${provider_key#app:}"
            # Try to focus by app name as class (case-insensitive common matches)
            if focus_window_by_class "$app_name"; then
                return 0
            fi
            # Try lowercase
            if focus_window_by_class "${app_name,,}"; then
                return 0
            fi
            return 0
            ;;
    esac

    if [[ "$is_active" == "true" ]]; then
        makoctl invoke -n "$notification_id" default >/dev/null 2>&1 || true
    fi
}

open_notification() {
    local notification_id="$1"
    local notification_json provider_key

    notification_json=$(notification_by_id "$notification_id")
    [[ -n "$notification_json" ]] || exit 0

    provider_key=$(notification_provider_key "$notification_json")
    mark_provider_seen "$provider_key"
    open_source_for_notification "$notification_json"
}

notification_preview_line() {
    local notification_json="$1"
    local summary preview body

    summary=$(echo "$notification_json" | jq -r '.summary // "(no title)"')
    body=$(echo "$notification_json" | jq -r '.body // ""' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')

    if [[ -n "$body" ]]; then
        preview="$summary | $body"
    else
        preview="$summary"
    fi

    printf '%s' "$preview" | cut -c1-140
}

get_unread_notifications() {
    local notifications state

    notifications=$(get_all_notifications)
    state=$(get_state)

    jq -cn \
        --argjson notifications "$notifications" \
        --argjson baseline "$(echo "$state" | jq '.baseline // 0')" \
        --argjson seen "$(get_seen_ids)" \
        '$notifications
        | map(select(.id > $baseline and ((.id as $id | $seen | index($id)) | not)))'
}

render() {
    local unread count tooltip

    unread=$(get_unread_notifications)
    count=$(echo "$unread" | jq 'length')

    if [[ "$count" -gt 0 ]]; then
        tooltip=$(while IFS= read -r notification_json; do
            [[ -n "$notification_json" ]] || continue
            printf '%s: %s\n' "$(notification_provider_label "$notification_json")" "$(echo "$notification_json" | jq -r '.summary // "(no title)"')"
        done < <(echo "$unread" | jq -c '.[0:5][]'))
        jq -cn \
            --arg text " $count" \
            --arg tooltip "$tooltip" \
            --arg class "active" \
            '{"text":$text,"tooltip":$tooltip,"class":$class}'
    else
        jq -cn \
            --arg text "" \
            --arg tooltip "No unread notifications" \
            --arg class "inactive" \
            '{"text":$text,"tooltip":$tooltip,"class":$class}'
    fi
}

restore_next() {
    local history state next_id

    history=$(get_history_notifications)
    state=$(get_state)
    next_id=$(jq -rn \
        --argjson history "$history" \
        --argjson baseline "$(echo "$state" | jq '.baseline // 0')" \
        --argjson seen "$(get_seen_ids)" \
        '$history
        | map(select(.id > $baseline and ((.id as $id | $seen | index($id)) | not)))
        | .[0].id // empty')

    [[ -n "$next_id" ]] || exit 0

    mark_ids_seen "[$next_id]"
    makoctl restore >/dev/null 2>&1 || true
}

clear_all() {
    local notifications max_id

    notifications=$(get_all_notifications)
    max_id=$(echo "$notifications" | jq 'map(.id) | max // 0')
    save_state "$(jq -cn --argjson baseline "$max_id" '{baseline:$baseline,seen:[]}')"
    makoctl dismiss -a >/dev/null 2>&1 || true
}

list_entries() {
    local unread all unread_ids_json

    unread=$(get_unread_notifications)
    all=$(get_all_notifications)
    unread_ids_json=$(echo "$unread" | jq '[.[].id]')

    declare -A unread_by_id=()
    declare -A provider_labels=()
    declare -A provider_rows=()
    declare -A provider_max_id=()
    declare -A provider_count=()

    while IFS= read -r unread_id; do
        [[ -n "$unread_id" ]] || continue
        unread_by_id["$unread_id"]=1
    done < <(echo "$unread_ids_json" | jq -r '.[]')

    while IFS= read -r notification_json; do
        [[ -n "$notification_json" ]] || continue

        local id provider_key provider_label status summary row_label row_action provider_line
        id=$(echo "$notification_json" | jq -r '.id')
        provider_key=$(notification_provider_key "$notification_json")
        provider_label=$(notification_provider_label "$notification_json")
        summary=$(notification_preview_line "$notification_json")

        if [[ -n "${unread_by_id[$id]:-}" ]]; then
            status="\033[1;38;5;82mNEW\033[0m"
        else
            status="\033[38;5;244mOLD\033[0m"
        fi

        if [[ -z "${provider_labels[$provider_key]:-}" ]]; then
            provider_labels["$provider_key"]="$provider_label"
            provider_max_id["$provider_key"]="$id"
            provider_count["$provider_key"]=0
        fi

        if (( id > ${provider_max_id[$provider_key]} )); then
            provider_max_id["$provider_key"]="$id"
        fi

        provider_count["$provider_key"]=$((provider_count[$provider_key] + 1))

        row_action="open:$id"
        row_label=$(printf "  %b | %s" "$status" "$summary")
        provider_rows["$provider_key"]+="${row_action}"$'\t'"${row_label}"$'\x1f'
    done < <(echo "$all" | jq -c '.[0:200][]')

    echo $'action\tlabel'
    echo -e $'clear\t\033[1;38;5;81m[ Clear unread notifications ]\033[0m'

    while IFS=$'\t' read -r max_id provider_key; do
        [[ -n "$provider_key" ]] || continue

        local header count rows
        count=${provider_count[$provider_key]}
        rows=${provider_rows[$provider_key]}
        header=$(printf "\033[1;38;5;219m┌─ %s\033[0m \033[38;5;244m(%s)\033[0m" "${provider_labels[$provider_key]}" "$count")

        echo -e "section:$provider_key\t$header"
        printf '%s' "$rows" | tr '\037' '\n'
        echo -e "section-end:$provider_key\t\033[38;5;240m└────────────────────────────────────────────────────────────\033[0m"
        echo -e $'spacer\t '
    done < <(
        for provider_key in "${!provider_max_id[@]}"; do
            printf '%s\t%s\n' "${provider_max_id[$provider_key]}" "$provider_key"
        done | sort -rn
    )

    echo -e $'help\t\033[1;38;5;75mEnter: Open\033[0m \033[38;5;240m|\033[0m \033[1;38;5;75mSelect [Clear unread] to dismiss\033[0m \033[38;5;240m|\033[0m \033[1;38;5;75mEsc: Close\033[0m'
}

dump_json() {
    local unread all unread_ids_json

    unread=$(get_unread_notifications)
    all=$(get_all_notifications)
    unread_ids_json=$(echo "$unread" | jq '[.[].id]')

    declare -A unread_by_id=()

    while IFS= read -r unread_id; do
        [[ -n "$unread_id" ]] || continue
        unread_by_id["$unread_id"]=1
    done < <(echo "$unread_ids_json" | jq -r '.[]')

    while IFS= read -r notification_json; do
        [[ -n "$notification_json" ]] || continue

        local id provider_key provider_label status unread_bool preview summary
        id=$(echo "$notification_json" | jq -r '.id')
        provider_key=$(notification_provider_key "$notification_json")
        provider_label=$(notification_provider_label "$notification_json")
        preview=$(notification_preview_line "$notification_json")
        summary=$(echo "$notification_json" | jq -r '.summary // "(no title)"')

        if [[ -n "${unread_by_id[$id]:-}" ]]; then
            status="NEW"
            unread_bool=true
        else
            status="OLD"
            unread_bool=false
        fi

        jq -cn \
            --argjson id "$id" \
            --arg provider_key "$provider_key" \
            --arg provider_label "$provider_label" \
            --arg status "$status" \
            --arg summary "$summary" \
            --arg preview "$preview" \
            --argjson unread "$unread_bool" \
            '{id:$id,provider_key:$provider_key,provider_label:$provider_label,status:$status,summary:$summary,preview:$preview,unread:$unread}'
    done < <(echo "$all" | jq -c '.[0:300][]') | jq -sc '
        sort_by(.provider_key)
        | group_by(.provider_key)
        | map({
            provider_key: .[0].provider_key,
            provider_label: .[0].provider_label,
            latest_id: (map(.id) | max),
            items: (sort_by(.id) | reverse | map({id,status,summary,preview,unread}))
          })
        | sort_by(.latest_id)
        | reverse
    '
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-render}" in
        render)
            render
            ;;
        restore-next)
            restore_next
            ;;
        clear-all)
            clear_all
            ;;
        open-id)
            open_notification "${2:?missing notification id}"
            ;;
        list-entries)
            list_entries
            ;;
        dump-json)
            dump_json
            ;;
        *)
            render
            ;;
    esac
fi
