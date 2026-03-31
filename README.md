# healthcheck

A dead-simple Linux healthcheck monitor. Pure bash, cron-scheduled, with [ntfy](https://ntfy.sh) notifications.

No daemons, no containers, no background processes — just cron doing what cron does.

## How it works

1. Use the **TUI** (`ui.sh`) to add endpoints you want to monitor
2. Hit **Install** to write crontab entries
3. Cron runs `healthcheck.sh` on your chosen interval — completely independent of the UI
4. If consecutive failures exceed your threshold, you get a notification via ntfy
5. When the endpoint recovers, you get a recovery notification too

```
┌──────────────────────────────────┐
│      Healthcheck Manager         │
│                                  │
│   1. Add Healthcheck             │
│   2. List / Manage Healthchecks  │
│   3. Install (write to crontab)  │
│   4. Uninstall (remove crontab)  │
│   5. View Cron Status            │
│   6. Exit                        │
│                                  │
└──────────────────────────────────┘
```

## Requirements

- `sqlite3`
- `curl`
- `whiptail` (for the TUI only — not needed for cron checks)
- `cron`
- `flock` (from `util-linux`)

On Debian/Ubuntu:

```bash
sudo apt install sqlite3 curl whiptail cron util-linux
```

## Setup

```bash
git clone https://github.com/youruser/healthcheck.git
cd healthcheck
./install.sh
```

This checks dependencies, initializes the SQLite database at `~/.local/share/healthcheck/healthcheck.db`, and makes scripts executable.

## Usage

### Managing checks

```bash
./ui.sh
```

The TUI walks you through adding checks with:

- **Endpoint URL** — the URL to GET
- **ntfy topic** — where to send alerts
- **ntfy base URL** — defaults to `https://ntfy.sh`, set your own for self-hosted
- **Interval** — presets from 1m to 1d, or a custom cron expression
- **Failure threshold** — consecutive failures before alerting (default: 3)

### Installing to cron

From the TUI, select **Install** to write all enabled checks to your crontab. Each check gets a tagged entry like:

```
# healthcheck:id=1
*/5 * * * * /path/to/healthcheck.sh 1
```

Select **Uninstall** to remove them. Your other crontab entries are never touched.

### Running a check manually

```bash
./healthcheck.sh <check_id>
```

This is exactly what cron runs. It needs no UI, no daemon — just `curl`, `sqlite3`, and the database file.

## How alerts work

- A check is **healthy** if it returns HTTP 2xx
- Consecutive failures are tracked in the database
- When failures hit the threshold, a **single** alert is sent to your ntfy topic (no spam)
- When the endpoint comes back up, a **recovery** notification is sent
- `flock` prevents overlapping runs of the same check

## File structure

```
healthcheck/
├── healthcheck.sh      # Standalone check script (what cron runs)
├── ui.sh               # Whiptail TUI
├── install.sh          # Dependency check + DB init
└── lib/
    ├── db.sh           # SQLite schema and helpers
    ├── cron.sh         # Crontab management
    └── notify.sh       # ntfy integration
```

Data is stored at `~/.local/share/healthcheck/healthcheck.db` (XDG-compliant).

## License

MIT
