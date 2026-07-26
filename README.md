# homelab

Self-hosted Docker stacks on `homelab` (Debian 13). Each service is its own compose
project with a **Tailscale sidecar** (`network_mode: service:<svc>-ts`) that publishes it
on the tailnet via `ts-config/serve-config.json`. No ports are exposed to the LAN — access
is Tailscale-only (`https://<hostname>.your-tailnet.ts.net`).

## Services

| Dir | App | Host (TS) | URL | Data location |
|-----|-----|-----------|-----|---------------|
| `immich` | Immich (photos) | pixie | https://pixie.your-tailnet.ts.net | `/srv/immich/{library,postgres}`, vol `immich_model-cache` |
| `adguardhome` | AdGuard Home (DNS) | aegis | https://aegis.your-tailnet.ts.net | `/srv/adguardhome/{work,conf}` |
| `vaultwarden` | Vaultwarden (Bitwarden) | raziel | https://raziel.your-tailnet.ts.net | `/srv/vaultwarden` |
| `karakeep` | Karakeep (bookmarks) | tagnest | https://tagnest.your-tailnet.ts.net | `/mnt/data/hoarder`, vol `karakeep_meilisearch` |
| `searxng` | SearXNG (metasearch) | savitri | https://savitri.your-tailnet.ts.net | `./searxng` (config), vols `searxng_{searxng-data,valkey-data2}` |
| `beszel` | Beszel (monitoring) | argus | https://argus.your-tailnet.ts.net | `/srv/beszel`; agent runs on host net |

The Tailscale sidecar (image, caps, TS env vars) is defined once in
[`common/tailscale.yml`](common/tailscale.yml) and pulled into each stack via `extends:` — bump
the pinned tag there instead of in all six compose files.

Pinned image versions (bump deliberately, then `make pull up`):
tailscale `v1.98.8` (in `common/tailscale.yml`) · immich `${IMMICH_VERSION}` (v3) ·
adguard `v0.107.77` · vaultwarden `1.36.0` · beszel + agent `0.18.7` ·
searxng `2026.7.7-f69b22c45` · karakeep `${KARAKEEP_VERSION}` · meilisearch `v1.13.3`.

## Layout & conventions

- **Config lives in git** (`~/Docker`): compose files + `ts-config/serve-config.json`.
  `.gitignore` is `*` (allowlist) — secrets/state/data are never committed.
- **Data lives outside git** under `/srv/<svc>/` (bind-mounted to `/home/srv`, on the nvme
  SSD) or Docker named volumes. Karakeep is on `/mnt/data` (HDD).
- **Secrets** are in each stack's `.env` (git-ignored). Variable names:
  - all: `TS_AUTHKEY`
  - immich: `IMMICH_VERSION DB_PASSWORD DB_USERNAME DB_DATABASE_NAME UPLOAD_LOCATION DB_DATA_LOCATION`
  - searxng: `SEARXNG_SECRET`
  - karakeep: `KARAKEEP_VERSION NEXTAUTH_SECRET MEILI_MASTER_KEY NEXTAUTH_URL`
- **Logging**: every service caps json-file logs at 10 MB × 3 (via the `x-logging` anchor).

### Disk layout
| Mount | Device | Size | Holds |
|-------|--------|------|-------|
| `/` | nvme0n1p2 | 23G | OS |
| `/home` | nvme0n1p6 | 895G | `~/Docker` (config) + `/srv` (data, bind mount) |
| `/mnt/data` | sda1 (HDD, btrfs) | 932G | karakeep data, beszel-agent extra-fs |

## Operations

Cross-stack, from the repo root:

```bash
make up             # start every stack
make down           # stop every stack
make pull           # pull latest images for every stack (then `make up` to apply)
make restart        # down + up
make ps             # status, all stacks
make logs SVC=immich    # tail logs for one stack
make scan           # gitleaks secret scan before pushing
```

Per-stack (equivalent to the above, one at a time):

```bash
cd <svc>
docker compose ps                 # status
docker compose logs -f            # tail logs
docker compose up -d              # apply changes / recreate
docker compose pull && docker compose up -d   # update (after bumping a pinned tag)
docker exec <svc>-ts tailscale status         # tailnet health for a stack
```

## Backup / disaster recovery

Nightly `restic` → Google Drive (via rclone), encrypted. Covers config + `.env` + small
stateful data; **immich's photo library is excluded** (back it up separately). Setup and
restore steps: [`backup/SETUP.md`](backup/SETUP.md).

## Restore (new machine, outline)
1. Install docker; recreate the `/srv` bind mount (`/home/srv` → `/srv`).
2. `restic restore latest --target /` (brings back `~/Docker` incl. `.env` and `/srv/*`).
3. Re-auth Tailscale if `state/` is absent (fresh `TS_AUTHKEY` per stack).
4. `make up` (or `docker compose up -d` in each service dir).
5. Restore immich photos separately.
