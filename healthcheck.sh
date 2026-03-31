#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/db.sh"
source "$SCRIPT_DIR/lib/notify.sh"

CHECK_ID="${1:-}"
if [[ -z "$CHECK_ID" ]]; then
    echo "Usage: healthcheck.sh <check_id>" >&2
    exit 1
fi

# Prevent overlapping runs for the same check
LOCK_FILE="/tmp/healthcheck-${CHECK_ID}.lock"
exec 200>"$LOCK_FILE"
flock -n 200 || exit 0

DB="$(get_db_path)"

# Load check config
ROW=$(sqlite3 "$DB" -separator $'\t' \
    "SELECT url, ntfy_topic, ntfy_url, threshold FROM checks WHERE id=$CHECK_ID AND enabled=1;" 2>/dev/null) || true

if [[ -z "$ROW" ]]; then
    exit 0
fi

IFS=$'\t' read -r URL NTFY_TOPIC NTFY_URL THRESHOLD <<< "$ROW"

# Perform HTTP check
HTTP_CODE=0
START_NS=$(date +%s%N)
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" 2>/dev/null) || HTTP_CODE=0
END_NS=$(date +%s%N)
RESPONSE_MS=$(( (END_NS - START_NS) / 1000000 ))

# Determine status
if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    STATUS="ok"
else
    STATUS="fail"
fi

# Log result
sqlite3 "$DB" "INSERT INTO check_log (check_id, status, http_code, response_ms) VALUES ($CHECK_ID, '$STATUS', $HTTP_CODE, $RESPONSE_MS);"

# Ensure check_status row exists
sqlite3 "$DB" "INSERT OR IGNORE INTO check_status (check_id, consecutive_failures, alerted) VALUES ($CHECK_ID, 0, 0);"

if [[ "$STATUS" == "fail" ]]; then
    sqlite3 "$DB" "UPDATE check_status SET consecutive_failures = consecutive_failures + 1, last_checked_at = datetime('now'), last_status = 'fail' WHERE check_id = $CHECK_ID;"

    CONSEC=$(sqlite3 "$DB" "SELECT consecutive_failures FROM check_status WHERE check_id=$CHECK_ID;")
    ALERTED=$(sqlite3 "$DB" "SELECT alerted FROM check_status WHERE check_id=$CHECK_ID;")

    if [[ "$CONSEC" -ge "$THRESHOLD" && "$ALERTED" -eq 0 ]]; then
        if send_ntfy "$NTFY_URL" "$NTFY_TOPIC" "Healthcheck FAILED" "$URL is down (HTTP $HTTP_CODE, $CONSEC consecutive failures)" "high"; then
            sqlite3 "$DB" "UPDATE check_status SET alerted = 1 WHERE check_id = $CHECK_ID;"
        fi
    fi
else
    ALERTED=$(sqlite3 "$DB" "SELECT COALESCE(alerted, 0) FROM check_status WHERE check_id=$CHECK_ID;")
    if [[ "$ALERTED" -eq 1 ]]; then
        send_ntfy "$NTFY_URL" "$NTFY_TOPIC" "Healthcheck RECOVERED" "$URL is back up (HTTP $HTTP_CODE)" "default" || true
    fi
    sqlite3 "$DB" "UPDATE check_status SET consecutive_failures = 0, alerted = 0, last_checked_at = datetime('now'), last_status = 'ok' WHERE check_id = $CHECK_ID;"
fi

# Prune old log entries (keep last 1000 per check)
sqlite3 "$DB" "DELETE FROM check_log WHERE check_id = $CHECK_ID AND id NOT IN (SELECT id FROM check_log WHERE check_id = $CHECK_ID ORDER BY checked_at DESC LIMIT 1000);"
