#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Checking dependencies..."

missing=0
for cmd in sqlite3 curl whiptail crontab flock; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  MISSING: $cmd"
        missing=1
    else
        echo "  OK: $cmd"
    fi
done

if [[ "$missing" -eq 1 ]]; then
    echo ""
    echo "Install missing dependencies. On Debian/Ubuntu:"
    echo "  sudo apt install sqlite3 curl whiptail cron util-linux"
    exit 1
fi

source "$SCRIPT_DIR/lib/db.sh"
db_init

chmod +x "$SCRIPT_DIR/healthcheck.sh" "$SCRIPT_DIR/ui.sh" "$SCRIPT_DIR/install.sh"

echo ""
echo "Setup complete. Database at: $(get_db_path)"
echo "Run ./ui.sh to manage healthchecks."
