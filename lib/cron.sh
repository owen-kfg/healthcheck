#!/usr/bin/env bash
# Crontab management for healthcheck application

CRON_TAG="healthcheck:id"
_CRON_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

interval_to_cron() {
    case "$1" in
        1m)  echo "* * * * *" ;;
        5m)  echo "*/5 * * * *" ;;
        15m) echo "*/15 * * * *" ;;
        30m) echo "*/30 * * * *" ;;
        1h)  echo "0 * * * *" ;;
        6h)  echo "0 */6 * * *" ;;
        12h) echo "0 */12 * * *" ;;
        1d)  echo "0 0 * * *" ;;
        *)
            if [[ $(echo "$1" | awk '{print NF}') -eq 5 ]]; then
                echo "$1"
            else
                return 1
            fi
            ;;
    esac
}

cron_remove_check() {
    local check_id="$1"
    local tag_line="# ${CRON_TAG}=${check_id}"
    local cmd_pattern="healthcheck.sh ${check_id}$"
    local current
    current=$(crontab -l 2>/dev/null) || true
    if [[ -n "$current" ]]; then
        echo "$current" | grep -v -F "$tag_line" | grep -v -E "$cmd_pattern" | crontab -
    fi
}

cron_install_check() {
    local check_id="$1" cron_expr="$2"
    local tag_line="# ${CRON_TAG}=${check_id}"
    local job_line="$cron_expr ${_CRON_PROJECT_DIR}/healthcheck.sh ${check_id}"

    cron_remove_check "$check_id"

    (crontab -l 2>/dev/null; echo "$tag_line"; echo "$job_line") | crontab -
}

cron_install_all() {
    local db count=0
    db="$(get_db_path)"
    while IFS=$'\t' read -r id expr; do
        cron_install_check "$id" "$expr"
        ((count++))
    done < <(sqlite3 "$db" -separator $'\t' "SELECT id, cron_expr FROM checks WHERE enabled=1;")
    echo "$count"
}

cron_uninstall_all() {
    local current
    current=$(crontab -l 2>/dev/null) || true
    if [[ -n "$current" ]]; then
        echo "$current" | grep -v -F "$CRON_TAG" | grep -v -F "healthcheck.sh" | crontab -
    fi
}
