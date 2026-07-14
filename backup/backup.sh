#!/usr/bin/env bash
#
# Out-of-band homelab backup:  restic -> rclone -> Google Drive.
# Immich's photo library (/srv/immich) is intentionally EXCLUDED (too big for GDrive).
# Secrets (repo URL + password) live in /etc/restic/backup.env (root-only) -- see SETUP.md.
#
# Run manually:  sudo /home/homelab/Docker/backup/backup.sh
# Runs nightly via restic-backup.timer.

set -euo pipefail

# --- load repo location + password (root-only file) ---
# Provides: RESTIC_REPOSITORY (e.g. rclone:gdrive:homelab), RESTIC_PASSWORD_FILE
set -a; . /etc/restic/backup.env; set +a
export RCLONE_CONFIG=${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}

DOCKER=/home/homelab/Docker

# --- consistent point-in-time SQLite snapshots (avoid backing up a mid-write DB) ---
snap_sqlite(){
  local db=$1
  [[ -f "$db" ]] || return 0
  if command -v sqlite3 >/dev/null; then
    sqlite3 "$db" ".backup '${db}.backup'" && echo "  sqlite snapshot -> ${db}.backup"
  else
    echo "  WARN: sqlite3 not installed; backing up live $db (may be inconsistent)"
  fi
}
snap_sqlite /srv/vaultwarden/db.sqlite3
snap_sqlite /srv/beszel/data.db
snap_sqlite /srv/beszel/auxiliary.db
snap_sqlite /mnt/data/hoarder/db.db

# --- back up config + small stateful data (NOT immich photos) ---
restic backup --tag homelab \
  --exclude '/srv/immich' \
  --exclude '*-wal' --exclude '*-shm' \
  --exclude 'icon_cache' \
  "$DOCKER" \
  /srv/vaultwarden \
  /srv/adguardhome \
  /srv/beszel \
  /mnt/data/hoarder

# --- retention ---
restic forget --tag homelab --prune \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6

echo "=== latest snapshots ==="
restic snapshots --tag homelab --latest 3
