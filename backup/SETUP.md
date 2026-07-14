# Backup setup (restic → rclone → Google Drive)

Backs up **config + secrets + small stateful data**; **excludes immich's photo library**
(too big for GDrive). restic encrypts everything client-side, so secrets are safe in the cloud.

Backed up: `~/Docker` (all compose + `.env`), `/srv/{vaultwarden,adguardhome,beszel}`,
`/mnt/data/hoarder`. SQLite DBs get a consistent `.backup` snapshot first.

## One-time setup (run as root)

```bash
# 1. Install tools
sudo apt update && sudo apt install -y restic rclone sqlite3

# 2. Configure the Google Drive remote IN ROOT'S config (backup runs as root)
sudo rclone config
#   n) new remote  -> name: gdrive  -> storage: drive
#   follow the OAuth link, authorize, accept defaults
#   (optional) set a root_folder_id to a dedicated "homelab-backup" folder

# 3. Secrets file + restic password (root-only)
sudo mkdir -p /etc/restic
openssl rand -base64 32 | sudo tee /etc/restic/password >/dev/null   # KEEP A COPY OFF-MACHINE
sudo tee /etc/restic/backup.env >/dev/null <<'EOF'
RESTIC_REPOSITORY=rclone:gdrive:homelab-backup
RESTIC_PASSWORD_FILE=/etc/restic/password
EOF
sudo chmod 600 /etc/restic/password /etc/restic/backup.env

# 4. Initialize the restic repo
sudo bash -c 'set -a; . /etc/restic/backup.env; set +a; restic init'

# 5. First backup (test)
sudo /home/homelab/Docker/backup/backup.sh

# 6. Install the nightly timer
sudo cp /home/homelab/Docker/backup/restic-backup.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup.timer
systemctl list-timers restic-backup.timer
```

## ⚠️ Store the restic password off-machine
Without `/etc/restic/password` the backup is unrecoverable. Save a copy in your
password manager (vaultwarden!) or another device.

## Restore test (do this once so you trust it)

```bash
sudo bash -c 'set -a; . /etc/restic/backup.env; set +a; \
  restic restore latest --target /tmp/restore-test \
  --include /home/homelab/Docker/vaultwarden'
ls -R /tmp/restore-test/home/homelab/Docker/vaultwarden && sudo rm -rf /tmp/restore-test
```

## Full-rebuild outline (new machine)
1. Install docker + tailscale-in-container prerequisites; recreate `/srv` bind mount.
2. `restic restore latest --target /` (restores `~/Docker` incl. `.env`, and `/srv/*`).
3. Re-auth tailscale if `state/` didn't restore (new `TS_AUTHKEY`).
4. `cd ~/Docker/<svc> && docker compose up -d` per stack.
5. Immich photos are NOT in this backup restore separately from wherever the 49G lives.
