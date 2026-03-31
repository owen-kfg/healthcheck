#!/usr/bin/env bash
# ntfy notification helper

# send_ntfy BASE_URL TOPIC TITLE MESSAGE [PRIORITY]
# Returns 0 on success, 1 on failure
send_ntfy() {
    local base_url="$1" topic="$2" title="$3" message="$4" priority="${5:-default}"
    curl -s -o /dev/null -w '' --max-time 10 \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: healthcheck" \
        -d "$message" \
        "${base_url}/${topic}"
}
