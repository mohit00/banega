# Banega production deploy (single VM)

One Ubuntu 24.04 VM runs the whole stack with Docker Compose:

```
Internet --443/80--> caddy (TLS, Let's Encrypt, HSTS) --> nginx --> api (uvicorn x2) / admin
                                                                     worker (arq), redis, db (Postgres 16 + pgvector)
                                                db-backup: nightly pg_dump + media -> restic -> Spaces / B2
```

- `api.<domain>` serves `/v1` (the app) and `/media` (recipe photos). `/admin` is 404 there.
- `admin.<domain>` serves only `/admin` (and `/media`), `/` redirects to `/admin/`.
  `ADMIN_ALLOW_CIDR` additionally limits it to your office / VPN addresses (nginx).
- Files: `infra/docker-compose.yml` + `infra/docker-compose.prod.yml`, `infra/caddy/Caddyfile`,
  `infra/.env.prod.example` (every variable), `infra/deploy/bootstrap.sh`,
  `infra/deploy/backup.sh` + `backup.Dockerfile`, restore drill in `restore.md`.

The examples use `banega.kornea.in` (you own `kornea.in`): `api.banega.kornea.in` and
`admin.banega.kornea.in`. Replace with your names everywhere if different.

## 1. Accounts you need first

| What | Where | Gives you |
|---|---|---|
| VM | DigitalOcean (or any Ubuntu 24.04 host) | public IPv4 |
| DNS | wherever `kornea.in` is hosted | two A records |
| Object storage | DigitalOcean Spaces (BLR1) **or** Backblaze B2 | bucket + access key |
| MSG91 + DLT | msg91.com, a DLT portal (Jio TrueConnect etc.) | auth key, template id (backend/README.md "MSG91 OTP") |
| Firebase | console.firebase.google.com | FCM service-account JSON |
| Play Console | play.google.com/console | Play service-account JSON, RTDN topic |
| Optional | healthchecks.io | backup ping URL |

## 2. Create the VM (DigitalOcean)

1. Create -> Droplets -> region **Bangalore (BLR1)**, image **Ubuntu 24.04 (LTS) x64**,
   size **Basic, Regular, 2 vCPU / 4 GB** (about $24/month). Authentication: **SSH key**
   (add yours), not a password. Enable **Monitoring**. Optional: weekly droplet backups
   (they do not replace the off-site restic backups).
2. Networking -> Firewalls -> Create firewall `banega-web`: inbound **TCP 22** (better: only
   your IP), **TCP 80**, **TCP 443**, **UDP 443** (HTTP/3); outbound: all. Apply it to the
   droplet. (`bootstrap.sh` also enables `ufw` with the same ports.)
3. Note the droplet's public IPv4, e.g. `203.0.113.10`.

## 3. DNS

At the DNS host of `kornea.in` add:

| Type | Name | Value | TTL |
|---|---|---|---|
| A | `api.banega` | `203.0.113.10` | 300 |
| A | `admin.banega` | `203.0.113.10` | 300 |

Check from your machine: `nslookup api.banega.kornea.in` must answer the droplet IP before
the first start (Caddy requests the certificates on start; Let's Encrypt rate-limits
repeated failures). Do not proxy these records through a CDN for now (Caddy needs to answer
the HTTP-01 / TLS-ALPN challenge itself).

## 4. Off-site backup bucket

**DigitalOcean Spaces** (same account): Spaces Object Storage -> Create bucket, region
**BLR1**, name e.g. `banega-backups` (restrict file listing). API -> Spaces Keys -> Generate
New Key (limit it to that bucket if offered). Values:

```
RESTIC_REPOSITORY=s3:https://blr1.digitaloceanspaces.com/banega-backups/banega
AWS_ACCESS_KEY_ID=<Spaces access key>
AWS_SECRET_ACCESS_KEY=<Spaces secret>
AWS_DEFAULT_REGION=us-east-1
```

**Backblaze B2** (cheaper, different provider = safer): Buckets -> Create, private, name
e.g. `banega-backups`; note the endpoint, e.g. `s3.us-west-004.backblazeb2.com`. Application
Keys -> Add, access to that bucket only, read and write. Values:

```
RESTIC_REPOSITORY=s3:https://s3.us-west-004.backblazeb2.com/banega-backups/banega
AWS_ACCESS_KEY_ID=<keyID>
AWS_SECRET_ACCESS_KEY=<applicationKey>
AWS_DEFAULT_REGION=us-west-004
```

Do not enable bucket lifecycle rules that delete objects: restic prunes itself
(7 daily / 4 weekly / 6 monthly).

## 5. First run of bootstrap

From your machine (code is not public, so copy it rather than clone, or use a deploy key):

```bash
rsync -az --exclude .git --exclude app/build --exclude .venv ./ root@203.0.113.10:/tmp/banega/
ssh root@203.0.113.10
bash /tmp/banega/infra/deploy/bootstrap.sh --src /tmp/banega
```

or, with a GitHub deploy key on the VM:

```bash
bash bootstrap.sh --repo git@github.com:<org>/banega.git --branch main
```

The first run installs Docker, creates the `banega` user, 2 GB swap, ufw, copies the code to
`/opt/banega`, writes `/opt/banega/infra/.env` from `infra/.env.prod.example` with random
values for every `__GENERATE__` (`POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `JWT_SECRET`,
`OTP_HMAC_KEY`, `INVITE_HMAC_KEY`, `ADMIN_SECRET_KEY`, `PLAY_WEBHOOK_SECRET`,
`RESTIC_PASSWORD`), then **stops** and lists what you still have to fill (exit code 2).

**Copy `RESTIC_PASSWORD` into your password manager now.** Without it no backup can be
restored, and it lives only on this VM.

## 6. Fill infra/.env and the secrets, then start

`sudo -u banega nano /opt/banega/infra/.env` and set:

| Variable | Value |
|---|---|
| `API_DOMAIN`, `ADMIN_DOMAIN` | `api.banega.kornea.in`, `admin.banega.kornea.in` |
| `ACME_EMAIL` | your ops email |
| `MSG91_AUTH_KEY`, `MSG91_OTP_TEMPLATE_ID` (`MSG91_SENDER_ID`, `OTP_VOICE_FALLBACK`) | from MSG91 |
| `PLAY_PUBSUB_AUDIENCE` | `https://api.banega.kornea.in/v1/webhooks/play` |
| `PLAY_PUBSUB_SERVICE_ACCOUNT` | the push subscription's service account (step 11) |
| `RESTIC_REPOSITORY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` | step 4 |
| `ADMIN_ALLOW_CIDR` (optional) | e.g. your office / VPN egress `198.51.100.7/32` |
| `BACKUP_HEALTHCHECK_URL` (optional) | `https://hc-ping.com/<uuid>` |
| `IMAGE_TAG` | release tag, e.g. `v1` or the git short sha |
| `APPSTORE_ENABLED` | `0` for the Android-only launch |

Service-account keys (JSON files downloaded from Google Cloud, see backend/README.md):

```bash
# from your machine
scp fcm-service-account.json play-service-account.json root@203.0.113.10:/opt/banega/infra/secrets/
```

Then run bootstrap again; it fixes the file ownership (uid 10001, the API image user, mode
600), validates the compose config and starts everything:

```bash
bash /opt/banega/infra/deploy/bootstrap.sh
```

The first build takes a few minutes. `docker compose ... ps` should show every service
`healthy` (migrate `exited (0)`).

For brevity below:

```bash
cd /opt/banega
alias dc='sudo -u banega docker compose -f infra/docker-compose.yml -f infra/docker-compose.prod.yml --env-file infra/.env'
```

## 7. Check TLS and health

```bash
curl -s https://api.banega.kornea.in/v1/health/ready      # {"status":"ok",...}
curl -sI https://api.banega.kornea.in/v1/health | grep -i strict-transport
curl -s -o /dev/null -w '%{http_code}\n' https://api.banega.kornea.in/admin/   # 404
curl -s -o /dev/null -w '%{http_code}\n' https://admin.banega.kornea.in/admin/ # 200 (or 403 outside ADMIN_ALLOW_CIDR)
dc logs caddy | grep -i certificate                        # "certificate obtained successfully"
```

If the API container restarts in a loop, `dc logs api` starts with "Refusing to start with an
unsafe configuration" and lists every value to fix.

## 8. First staff account (admin panel)

```bash
dc exec api python -m app.cli staff-create --email you@kornea.in
```

It prompts for the password and prints an `otpauth://` URI: add it to your authenticator
app. Log in at `https://admin.banega.kornea.in/admin/`.

## 9. Seed the catalogue

The prod images do not mount `content/`; copy it in once:

```bash
dc cp content api:/tmp/content
dc exec api python -m app.cli seed --no-demo --content-dir /tmp/content
```

`--no-demo` skips the demo family (Purohit Parivaar) used in development. Then review and
publish recipes from the admin as usual.

## 10. Backups: first run and drill

```bash
dc exec db-backup backup.sh run          # init the repository + first snapshot now
dc exec db-backup backup.sh snapshots    # any restic command passes through
dc logs db-backup                        # nightly at BACKUP_AT (02:30 IST)
```

The container is `unhealthy` after a failed run until the next good one; with
`BACKUP_HEALTHCHECK_URL` you also get an email from healthchecks.io when a night is missed.
Do the restore drill in `restore.md` once before launch and after every major upgrade.

## 11. Google Play RTDN (subscription notifications)

Pub/Sub push cannot add custom headers, so the webhook authenticates the push with the
Google-signed OIDC token (`PLAY_PUBSUB_AUDIENCE` + `PLAY_PUBSUB_SERVICE_ACCOUNT`). The
`X-Webhook-Secret` header (`PLAY_WEBHOOK_SECRET`) only works behind a proxy that adds it.

1. Google Cloud console (the project linked to Play Console) -> Pub/Sub -> Create topic
   `play-rtdn`. Permissions: add principal `google-play-developer-notifications@system.gserviceaccount.com`
   with role **Pub/Sub Publisher**.
2. IAM -> Service accounts -> create `rtdn-push` (no roles needed). Give the Pub/Sub service
   agent (`service-<project-number>@gcp-sa-pubsub.iam.gserviceaccount.com`) the role
   **Service Account Token Creator** on it.
3. Pub/Sub -> topic `play-rtdn` -> Create subscription `play-rtdn-push`: delivery **Push**,
   endpoint `https://api.banega.kornea.in/v1/webhooks/play`, **Enable authentication**,
   service account `rtdn-push@<project>.iam.gserviceaccount.com`, audience
   `https://api.banega.kornea.in/v1/webhooks/play`. Retry policy: exponential backoff.
4. `infra/.env`: `PLAY_PUBSUB_AUDIENCE=https://api.banega.kornea.in/v1/webhooks/play`,
   `PLAY_PUBSUB_SERVICE_ACCOUNT=rtdn-push@<project>.iam.gserviceaccount.com`; `dc up -d`.
5. Play Console -> the app -> Monetize -> Monetization setup -> Real-time developer
   notifications: topic `projects/<project>/topics/play-rtdn` -> **Send test notification**.
   `dc logs api | grep webhooks/play` should show a 200.

## Updates and rollback

```bash
# new code (git or rsync as in step 5), then a new tag:
sudo -u banega sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=v2/' /opt/banega/infra/.env
bash /opt/banega/infra/deploy/bootstrap.sh            # pulls/rsyncs, builds, migrates, restarts
```

`migrate` runs `alembic upgrade head` before api / worker / admin start. Rollback: set
`IMAGE_TAG` back to the previous tag (the old images are still on the VM) and `dc up -d`.
If the new release ran a migration that the old code cannot read, restore the database
from the snapshot taken before the update (`dc exec db-backup backup.sh run` first; see
`restore.md`) or `dc run --rm migrate alembic downgrade <rev>`.

Clean old images now and then: `docker image prune -a --filter until=720h`.

## Logs and operations

```bash
dc ps
dc logs -f --tail=100 api worker      # JSON logs (structlog); nginx access log: dc logs nginx
dc restart api
dc exec db psql -U banega banega
```

Container logs rotate at 5 x 20 MB (`/etc/docker/daemon.json`). Unattended security updates
are on by default on Ubuntu; reboot after kernel updates (`needrestart`), the stack comes back
by itself (`restart: unless-stopped`).

## How the pieces fit

- **TLS**: Caddy obtains and renews certificates (`caddy_data` volume), redirects HTTP to
  HTTPS, sets `Strict-Transport-Security: max-age=31536000; includeSubDomains` (replacing
  nginx's copy) and proxies to `nginx:80` with `X-Forwarded-Proto: https`. nginx is not
  published on the host.
- **Client address**: Caddy replaces any client-sent `X-Forwarded-For` with the real peer
  address. nginx trusts it from `REAL_IP_FROM` (the private compose ranges, i.e. only Caddy)
  via `set_real_ip_from` + `real_ip_header`, so `ADMIN_ALLOW_CIDR` and the `limit_req` zones
  apply to the real client; a forged `X-Forwarded-For` does not get past the allow-list
  (tested). The API resolves the same address from `X-Forwarded-For` with `TRUSTED_PROXIES`
  (private ranges by default: caddy and nginx).
- **Secrets**: `infra/.env` (600, owned by `banega`) and `infra/secrets/*.json` (600, uid
  10001) never leave the VM and are git-ignored.
