#!/usr/bin/env bash

set -Eeuo pipefail

interval="${SYNC_INTERVAL:-30}"
if [[ ! "$interval" =~ ^[0-9]+$ ]] || (( interval < 5 )); then
    printf 'SYNC_INTERVAL must be an integer of at least 5 seconds.\n' >&2
    exit 1
fi

while true; do
    if ! /usr/local/bin/sync.sh; then
        printf 'Docker/NPM sync failed; retrying in %s seconds.\n' "$interval" >&2
    fi
    sleep "$interval"
done
