#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/db.sh"
source "$SCRIPT_DIR/lib/cron.sh"

db_init

# --- Helpers ---

msg() {
    whiptail --title "Healthcheck Manager" --msgbox "$1" 10 60
}

confirm() {
    whiptail --title "Healthcheck Manager" --yesno "$1" 10 60
}

input() {
    local title="$1" default="$2"
    whiptail --title "Healthcheck Manager" --inputbox "$title" 10 60 "$default" 3>&1 1>&2 2>&3
}

# --- Add/Edit Check ---

check_form() {
    local mode="$1"  # "add" or "edit"
    local id="${2:-}" name="${3:-}" url="${4:-}" topic="${5:-}" ntfy_url="${6:-https://ntfy.sh}" interval="${7:-5m}" threshold="${8:-3}"

    name=$(input "Check name:" "$name") || return 1

    url=$(input "Endpoint URL (https://...):" "$url") || return 1
    if [[ ! "$url" =~ ^https?:// ]]; then
        msg "URL must start with http:// or https://"
        return 1
    fi

    topic=$(input "ntfy topic:" "$topic") || return 1
    if [[ -z "$topic" ]]; then
        msg "Topic cannot be empty."
        return 1
    fi

    ntfy_url=$(input "ntfy base URL:" "$ntfy_url") || return 1

    local interval_choice
    interval_choice=$(whiptail --title "Healthcheck Manager" --menu "Check interval:" 18 60 10 \
        "1m"     "Every minute" \
        "5m"     "Every 5 minutes" \
        "15m"    "Every 15 minutes" \
        "30m"    "Every 30 minutes" \
        "1h"     "Every hour" \
        "6h"     "Every 6 hours" \
        "12h"    "Every 12 hours" \
        "1d"     "Once a day" \
        "custom" "Enter cron expression" \
        3>&1 1>&2 2>&3) || return 1

    local cron_expr
    if [[ "$interval_choice" == "custom" ]]; then
        cron_expr=$(input "Cron expression (5 fields):" "") || return 1
        if ! interval_to_cron "$cron_expr" >/dev/null 2>&1; then
            msg "Invalid cron expression. Must have exactly 5 fields."
            return 1
        fi
    else
        cron_expr=$(interval_to_cron "$interval_choice")
    fi

    threshold=$(input "Failure threshold (consecutive failures before alert):" "$threshold") || return 1
    if ! [[ "$threshold" =~ ^[0-9]+$ ]] || [[ "$threshold" -lt 1 ]]; then
        msg "Threshold must be a positive integer."
        return 1
    fi

    local db
    db="$(get_db_path)"

    if [[ "$mode" == "add" ]]; then
        sqlite3 "$db" "INSERT INTO checks (name, url, ntfy_topic, ntfy_url, cron_expr, threshold) VALUES ('$(sql_escape "$name")', '$(sql_escape "$url")', '$(sql_escape "$topic")', '$(sql_escape "$ntfy_url")', '$(sql_escape "$cron_expr")', $threshold);"
        msg "Check '$name' added."
    else
        sqlite3 "$db" "UPDATE checks SET name='$(sql_escape "$name")', url='$(sql_escape "$url")', ntfy_topic='$(sql_escape "$topic")', ntfy_url='$(sql_escape "$ntfy_url")', cron_expr='$(sql_escape "$cron_expr")', threshold=$threshold, updated_at=datetime('now') WHERE id=$id;"
        msg "Check '$name' updated."
    fi
}

sql_escape() {
    echo "${1//\'/\'\'}"
}

# --- List / Manage ---

list_checks() {
    local db
    db="$(get_db_path)"

    while true; do
        local rows
        rows=$(sqlite3 "$db" -separator $'\t' "SELECT id, name, url FROM checks ORDER BY id;") || true

        if [[ -z "$rows" ]]; then
            msg "No healthchecks configured."
            return
        fi

        local menu_args=()
        while IFS=$'\t' read -r id name url; do
            menu_args+=("$id" "$name - $url")
        done <<< "$rows"

        local choice
        choice=$(whiptail --title "Healthcheck Manager" --menu "Select a check:" 20 70 10 \
            "${menu_args[@]}" \
            3>&1 1>&2 2>&3) || return 0

        manage_check "$choice"
    done
}

manage_check() {
    local check_id="$1"
    local db
    db="$(get_db_path)"

    while true; do
        local row
        row=$(sqlite3 "$db" -separator $'\t' "SELECT name, url, ntfy_topic, ntfy_url, cron_expr, threshold, enabled FROM checks WHERE id=$check_id;") || true

        if [[ -z "$row" ]]; then
            msg "Check not found."
            return
        fi

        local name url topic ntfy_url cron_expr threshold enabled
        IFS=$'\t' read -r name url topic ntfy_url cron_expr threshold enabled <<< "$row"

        local enabled_text="Yes"
        [[ "$enabled" -eq 0 ]] && enabled_text="No"

        local action
        action=$(whiptail --title "$name" --menu "Manage check:" 18 60 8 \
            "status"  "View Status" \
            "edit"    "Edit" \
            "toggle"  "Toggle Enabled (currently: $enabled_text)" \
            "test"    "Test Now" \
            "delete"  "Delete" \
            "back"    "Back" \
            3>&1 1>&2 2>&3) || return

        case "$action" in
            status) view_status "$check_id" "$name" ;;
            edit)   check_form "edit" "$check_id" "$name" "$url" "$topic" "$ntfy_url" "$cron_expr" "$threshold" ;;
            toggle)
                local new_val=$(( 1 - enabled ))
                sqlite3 "$db" "UPDATE checks SET enabled=$new_val, updated_at=datetime('now') WHERE id=$check_id;"
                if [[ "$new_val" -eq 0 ]]; then
                    cron_remove_check "$check_id"
                    msg "Check disabled and removed from crontab."
                else
                    msg "Check enabled. Use Install to add to crontab."
                fi
                ;;
            test)
                local output
                output=$("$SCRIPT_DIR/healthcheck.sh" "$check_id" 2>&1) || true
                local last_status last_code
                last_status=$(sqlite3 "$db" "SELECT last_status FROM check_status WHERE check_id=$check_id;" 2>/dev/null) || last_status="unknown"
                last_code=$(sqlite3 "$db" "SELECT http_code FROM check_log WHERE check_id=$check_id ORDER BY checked_at DESC LIMIT 1;" 2>/dev/null) || last_code="?"
                msg "Test complete.\nResult: $last_status (HTTP $last_code)"
                ;;
            delete)
                if confirm "Delete '$name'? This cannot be undone."; then
                    cron_remove_check "$check_id"
                    sqlite3 "$db" "PRAGMA foreign_keys=ON; DELETE FROM checks WHERE id=$check_id;"
                    msg "Check deleted."
                    return
                fi
                ;;
            back) return ;;
        esac
    done
}

view_status() {
    local check_id="$1" name="$2"
    local db
    db="$(get_db_path)"

    local status_row
    status_row=$(sqlite3 "$db" -separator $'\t' \
        "SELECT COALESCE(last_status,'never'), consecutive_failures, alerted, COALESCE(last_checked_at,'never') FROM check_status WHERE check_id=$check_id;" 2>/dev/null) || true

    local last_status="never" consec="0" alerted="0" last_checked="never"
    if [[ -n "$status_row" ]]; then
        IFS=$'\t' read -r last_status consec alerted last_checked <<< "$status_row"
    fi

    local alert_text="No"
    [[ "$alerted" -eq 1 ]] && alert_text="YES - alert sent"

    local recent
    recent=$(sqlite3 "$db" "SELECT status || ' (HTTP ' || http_code || ')' FROM check_log WHERE check_id=$check_id ORDER BY checked_at DESC LIMIT 10;" 2>/dev/null) || recent="No history"

    msg "Status for: $name

Last checked:          $last_checked
Last status:           $last_status
Consecutive failures:  $consec
Alert active:          $alert_text

Recent results (newest first):
$recent"
}

# --- Install / Uninstall ---

do_install() {
    local count
    count=$(cron_install_all)
    msg "Installed $count healthcheck(s) to crontab."
}

do_uninstall() {
    if confirm "Remove all healthcheck entries from crontab?"; then
        cron_uninstall_all
        msg "All healthcheck crontab entries removed."
    fi
}

view_cron() {
    local entries
    entries=$(crontab -l 2>/dev/null | grep -A1 "$CRON_TAG" 2>/dev/null) || entries="No healthcheck entries in crontab."
    msg "$entries"
}

# --- Main Menu ---

main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Healthcheck Manager" --menu "Choose an action:" 18 60 8 \
            "1" "Add Healthcheck" \
            "2" "List / Manage Healthchecks" \
            "3" "Install (write to crontab)" \
            "4" "Uninstall (remove from crontab)" \
            "5" "View Cron Status" \
            "6" "Exit" \
            3>&1 1>&2 2>&3) || break

        case "$choice" in
            1) check_form "add" ;;
            2) list_checks ;;
            3) do_install ;;
            4) do_uninstall ;;
            5) view_cron ;;
            6) break ;;
        esac
    done
}

main_menu
