#!/bin/bash

set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
STATE_FILE="$STATE_DIR/mako-unread-state.json"
GMAIL_PWA_CLASS="FFPWA-01KQYXB3Z3YD5GYT1AK67S7Z2D"
WHATSAPP_PWA_CLASS="FFPWA-01KQYXB8RBA9AKZET0AX4MJXBS"
GMAIL_DESKTOP_ENTRY="Gmail"
WHATSAPP_DESKTOP_ENTRY="Whatsapp"

get_active_notifications() {
    makoctl list -j 2>/dev/null || echo '[]'
}

get_history_notifications() {
    makoctl history -j 2>/dev/null || echo '[]'
}

get_all_notifications() {
    jq -cs 'add | unique_by(.id) | sort_by(.id) | reverse' \
        <(get_active_notifications) \
        <(get_history_notifications) \
    | jq 'map(select(((.app_name // "") | ascii_downcase) != "notify-send"))'
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

is_notifications_muted() {
    makoctl mode 2>/dev/null | grep -q 'do-not-disturb'
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
    local desktop_entry app_name body_host body_text summary_text desktop_entry_lc app_name_lc

    desktop_entry=$(echo "$notification_json" | jq -r '.desktop_entry // empty')
    app_name=$(echo "$notification_json" | jq -r '.app_name // empty')
    body_host=$(notification_body_host "$notification_json")
    body_text=$(notification_body_text "$notification_json")
    summary_text=$(echo "$notification_json" | jq -r '.summary // ""' | tr '[:upper:]' '[:lower:]')
    desktop_entry_lc="${desktop_entry,,}"
    app_name_lc="${app_name,,}"

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

    case "$desktop_entry_lc" in
        whatsapp)
            echo "site:web.whatsapp.com"
            return 0
            ;;
        gmail)
            echo "site:gmail.com"
            return 0
            ;;
    esac

    case "$app_name_lc" in
        whatsapp)
            echo "site:web.whatsapp.com"
            return 0
            ;;
        gmail)
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
        desktop:firefox|app:Firefox|app:firefox)
            echo "Firefox"
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

provider_scope_from_key() {
    local provider_key="$1"
    local raw lower

    case "$provider_key" in
        site:web.whatsapp.com)
            echo "scope:whatsapp"
            return 0
            ;;
        site:gmail.com)
            echo "scope:gmail"
            return 0
            ;;
        desktop:*|app:*)
            raw="${provider_key#*:}"
            lower="${raw,,}"

            case "$lower" in
                whatsapp|web.whatsapp.com)
                    echo "scope:whatsapp"
                    return 0
                    ;;
                gmail|mail|google\ mail|mail.google.com|gmail.com)
                    echo "scope:gmail"
                    return 0
                    ;;
                code|vscode|visual\ studio\ code)
                    echo "scope:code"
                    return 0
                    ;;
            esac

            echo "scope:generic:$lower"
            return 0
            ;;
        *)
            echo "scope:key:$provider_key"
            return 0
            ;;
    esac
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
    local unread notifications_to_mark ids_json target_scope

    target_scope=$(provider_scope_from_key "$provider_key")

    unread=$(get_unread_notifications)
    notifications_to_mark=$(while IFS= read -r notification_json; do
        [[ -n "$notification_json" ]] || continue
        if [[ "$(provider_scope_from_key "$(notification_provider_key "$notification_json")")" == "$target_scope" ]]; then
            echo "$notification_json"
        fi
    done < <(echo "$unread" | jq -c '.[]'))

    ids_json=$(printf '%s\n' "$notifications_to_mark" | jq -cs 'map(.id)')
    [[ "$ids_json" != "[]" ]] || return 0
    mark_ids_seen "$ids_json"
}

mark_scope_seen() {
    local target_scope="$1"
    local unread notifications_to_mark ids_json

    [[ -n "$target_scope" ]] || return 0

    unread=$(get_unread_notifications)
    notifications_to_mark=$(while IFS= read -r notification_json; do
        [[ -n "$notification_json" ]] || continue
        if [[ "$(provider_scope_from_key "$(notification_provider_key "$notification_json")")" == "$target_scope" ]]; then
            echo "$notification_json"
        fi
    done < <(echo "$unread" | jq -c '.[]'))

    ids_json=$(printf '%s\n' "$notifications_to_mark" | jq -cs 'map(.id)')
    [[ "$ids_json" != "[]" ]] || return 0
    mark_ids_seen "$ids_json"
}

focused_window_scope() {
    local active_window_json window_class window_class_lc window_title_lc window_initial_title_lc

    active_window_json=$(hyprctl -j activewindow 2>/dev/null || echo '{}')
    window_class=$(echo "$active_window_json" | jq -r '.class // ""')
    window_class_lc="${window_class,,}"
    window_title_lc=$(echo "$active_window_json" | jq -r '.title // ""' | tr '[:upper:]' '[:lower:]')
    window_initial_title_lc=$(echo "$active_window_json" | jq -r '.initialTitle // ""' | tr '[:upper:]' '[:lower:]')

    if [[ "$window_title_lc" == *"whatsapp"* || "$window_title_lc" == *"web.whatsapp.com"* || "$window_initial_title_lc" == *"whatsapp"* || "$window_initial_title_lc" == *"web.whatsapp.com"* ]]; then
        echo "scope:whatsapp"
        return 0
    fi

    if [[ "$window_title_lc" == *"gmail"* || "$window_title_lc" == *"mail.google.com"* || "$window_initial_title_lc" == *"gmail"* || "$window_initial_title_lc" == *"mail.google.com"* ]]; then
        echo "scope:gmail"
        return 0
    fi

    if [[ "$window_class" == "$WHATSAPP_PWA_CLASS" || "$window_class_lc" == *"whatsapp"* ]]; then
        echo "scope:whatsapp"
        return 0
    fi

    if [[ "$window_class" == "$GMAIL_PWA_CLASS" || "$window_class_lc" == *"gmail"* ]]; then
        echo "scope:gmail"
        return 0
    fi

    if [[ "$window_class_lc" == "code" || "$window_class_lc" == "vscode" ]]; then
        echo "scope:code"
        return 0
    fi

    [[ -n "$window_class_lc" ]] || return 1
    echo "scope:generic:$window_class_lc"
}

mark_focused_app_seen() {
    local scope

    scope=$(focused_window_scope || true)
    [[ -n "$scope" ]] || return 0

    # FirefoxPWA currently emits ambiguous browser-owned notifications for
    # multiple webapps, so focusing Firefox must not clear those unread counts.
    case "$scope" in
        scope:generic:firefox|scope:generic:firefoxdeveloperedition|scope:generic:librewolf)
            return 0
            ;;
    esac

    mark_scope_seen "$scope"
}

focus_window_address() {
    local window_address="$1"
    local workspace_name special_name

    [[ -n "$window_address" ]] || return 1

    workspace_name=$(hyprctl -j clients 2>/dev/null | jq -r --arg addr "$window_address" '.[] | select(.address == $addr) | .workspace.name')

    if [[ "$workspace_name" == special:* ]]; then
        special_name="${workspace_name#special:}"
        hyprctl dispatch togglespecialworkspace "$special_name" >/dev/null 2>&1 || true
        sleep 0.05
    elif [[ "$workspace_name" == "special" ]]; then
        hyprctl dispatch togglespecialworkspace >/dev/null 2>&1 || true
        sleep 0.05
    fi

    hyprctl dispatch focuswindow "address:$window_address" >/dev/null 2>&1 || true
    return 0
}

focus_window_by_class() {
    local window_class="$1"
    local window_address

    window_address=$(hyprctl -j clients 2>/dev/null | jq -r --arg class "$window_class" '.[] | select(.class == $class) | .address' | head -n 1)
    focus_window_address "$window_address"
}

focus_webapp_window() {
    local app="$1"
    local window_address class_name title_pattern other_title_pattern

    case "$app" in
        gmail)
            class_name="$GMAIL_PWA_CLASS"
            title_pattern="gmail|mail\\.google\\.com"
            other_title_pattern="whatsapp|web\\.whatsapp\\.com"
            ;;
        whatsapp)
            class_name="$WHATSAPP_PWA_CLASS"
            title_pattern="whatsapp|web\\.whatsapp\\.com"
            other_title_pattern="gmail|mail\\.google\\.com"
            ;;
        *)
            return 1
            ;;
    esac

    window_address=$(hyprctl -j clients 2>/dev/null | jq -r --arg title_pattern "$title_pattern" '
        .[]
        | select(
            (((.title // "") | ascii_downcase) | test($title_pattern))
            or (((.initialTitle // "") | ascii_downcase) | test($title_pattern))
        )
        | .address
    ' | head -n 1)

    if [[ -z "$window_address" ]]; then
        window_address=$(hyprctl -j clients 2>/dev/null | jq -r --arg class "$class_name" --arg other_title_pattern "$other_title_pattern" '
            .[]
            | select(.class == $class)
            | select(
                ((((.title // "") | ascii_downcase) | test($other_title_pattern)) | not)
                and ((((.initialTitle // "") | ascii_downcase) | test($other_title_pattern)) | not)
            )
            | .address
        ' | head -n 1)
    fi

    focus_window_address "$window_address"
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
            if focus_webapp_window whatsapp; then
                return 0
            fi
            gtk-launch "$WHATSAPP_DESKTOP_ENTRY" >/dev/null 2>&1 || true
            return 0
            ;;
        site:gmail.com)
            if focus_webapp_window gmail; then
                return 0
            fi
            gtk-launch "$GMAIL_DESKTOP_ENTRY" >/dev/null 2>&1 || true
            return 0
            ;;
        desktop:Gmail)
            if focus_webapp_window gmail; then
                return 0
            fi
            gtk-launch "$GMAIL_DESKTOP_ENTRY" >/dev/null 2>&1 || true
            return 0
            ;;
        desktop:Whatsapp)
            if focus_webapp_window whatsapp; then
                return 0
            fi
            gtk-launch "$WHATSAPP_DESKTOP_ENTRY" >/dev/null 2>&1 || true
            return 0
            ;;
        desktop:firefox|app:Firefox)
            if [[ "$is_active" == "true" ]]; then
                makoctl invoke -n "$notification_id" default >/dev/null 2>&1 || true
            fi
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

    if is_notifications_muted; then
        if [[ "$count" -gt 0 ]]; then
            jq -cn \
                --arg text "" \
                --arg tooltip "Notifications silenced ($count unread tracked)" \
                --arg class "muted" \
                '{"text":$text,"tooltip":$tooltip,"class":$class}'
        else
            jq -cn \
                --arg text "" \
                --arg tooltip "Notifications silenced" \
                --arg class "muted" \
                '{"text":$text,"tooltip":$tooltip,"class":$class}'
        fi
        return 0
    fi

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

debug_state() {
    local active history all state unread render_json

    active=$(get_active_notifications)
    history=$(get_history_notifications)
    all=$(get_all_notifications)
    state=$(get_state)
    unread=$(get_unread_notifications)
    render_json=$(render)

    jq -cn \
        --argjson state "$state" \
        --argjson active "$active" \
        --argjson history "$history" \
        --argjson all "$all" \
        --argjson unread "$unread" \
        --argjson render "$render_json" \
        '{
            state: {
                baseline: ($state.baseline // 0),
                seen_count: (($state.seen // $state.restored // []) | length),
                seen: ($state.seen // $state.restored // [])
            },
            counts: {
                active: ($active | length),
                history: ($history | length),
                all: ($all | length),
                unread: ($unread | length)
            },
            unread_ids: ($unread | map(.id)),
            render: $render
        }'
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
        debug-state)
            debug_state
            ;;
        mark-focused-app-seen)
            mark_focused_app_seen
            ;;
        *)
            render
            ;;
    esac
fi
