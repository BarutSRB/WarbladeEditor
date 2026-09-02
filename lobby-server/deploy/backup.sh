#!/bin/sh
# Daily SQLite backup on the droplet (installed to /usr/local/bin and cron
# by deploy.sh). Uses the online backup API, so it is safe while the server
# runs. Keeps fourteen days. Copy one home with:
#   scp DROPLET:/var/backups/warblade-lobby/lobby-YYYY-MM-DD.db ~/
# Restore: stop the service, copy the file over lobby.db, delete lobby.db-wal
# and lobby.db-shm, start the service.
set -eu
cd /
dest=/var/backups/warblade-lobby
db=/var/lib/warblade-lobby/lobby.db
mkdir -p "$dest"
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is missing: apt install sqlite3" >&2
  exit 1
fi
sqlite3 "$db" ".backup '$dest/lobby-$(date -u +%F).db'"
find "$dest" -name 'lobby-*.db' -mtime +14 -delete
