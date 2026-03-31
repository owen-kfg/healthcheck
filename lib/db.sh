#!/usr/bin/env bash
# Database helpers for healthcheck application

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/healthcheck"
DB_PATH="$DATA_DIR/healthcheck.db"

get_db_path() {
    echo "$DB_PATH"
}

db_query() {
    sqlite3 "$DB_PATH" "$@"
}

db_init() {
    mkdir -p "$DATA_DIR"
    sqlite3 "$DB_PATH" <<'SQL' >/dev/null
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS checks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    url         TEXT NOT NULL,
    ntfy_topic  TEXT NOT NULL,
    ntfy_url    TEXT NOT NULL DEFAULT 'https://ntfy.sh',
    cron_expr   TEXT NOT NULL,
    threshold   INTEGER NOT NULL DEFAULT 3,
    enabled     INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS check_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    check_id    INTEGER NOT NULL REFERENCES checks(id) ON DELETE CASCADE,
    status      TEXT NOT NULL CHECK(status IN ('ok','fail')),
    http_code   INTEGER,
    response_ms INTEGER,
    checked_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS check_status (
    check_id             INTEGER PRIMARY KEY REFERENCES checks(id) ON DELETE CASCADE,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    alerted              INTEGER NOT NULL DEFAULT 0,
    last_checked_at      TEXT,
    last_status          TEXT CHECK(last_status IN ('ok','fail'))
);
SQL
}
