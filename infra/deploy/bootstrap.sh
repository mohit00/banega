#!/usr/bin/env bash
# Banega single-VM bootstrap (Ubuntu 24.04). Idempotent: safe to run again for updates.
#
#   sudo ./bootstrap.sh --repo https://github.com/<org>/banega.git [--branch banega-v1]
#   sudo ./bootstrap.sh --src /tmp/banega          # code already copied to the VM (rsync)
#   sudo ./bootstrap.sh                            # /opt/banega already in place: update + up
#
# Options:
#   --repo URL             git clone (first run) / git pull (later runs) into --dir
#   --branch NAME          branch to check out (default: main)
#   --src DIR              rsync DIR into --dir instead of git (infra/.env and secrets kept)
#   --dir DIR              install directory (default: /opt/banega)
#   --allow-placeholders   start even if infra/.env still has CHANGE_ME values
#   --no-up                prepare everything, do not start the stack
#
# Steps: Docker Engine + compose plugin from Docker's apt repository, a "banega" user in the
# docker group, 2 GB swap if none, ufw (22, 80, 443), the code in /opt/banega, infra/.env
# from infra/.env.prod.example with generated secrets (chmod 600), infra/secrets/ for the
# service-account keys, then docker compose (base + prod override) up -d --build.
set -euo pipefail

REPO=""
BRANCH="main"
SRC=""
DIR="/opt/banega"
ALLOW_PLACEHOLDERS=0
UP=1
APP_USER="banega"
# The API image runs as uid/gid 10001 (backend/Dockerfile): it must read the secrets.
CONTAINER_UID=10001

usage() { sed -n '2,20p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --src) SRC="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --allow-placeholders) ALLOW_PLACEHOLDERS=1; shift ;;
    --no-up) UP=0; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
# shellcheck source=/dev/null
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "this script targets Ubuntu (found ${ID:-unknown})"

# ---- packages and Docker ------------------------------------------------------------------
log "base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q ca-certificates curl gnupg git rsync ufw openssl

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  log "Docker Engine from download.docker.com"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
# Container logs: rotate instead of filling the disk.
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json <<'JSON'
{ "log-driver": "json-file", "log-opts": { "max-size": "20m", "max-file": "5" } }
JSON
  systemctl restart docker
fi

# ---- user, swap, firewall -----------------------------------------------------------------
log "user $APP_USER"
id "$APP_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$APP_USER"
usermod -aG docker "$APP_USER"

if ! swapon --show | grep -q .; then
  log "2 GB swap (image builds on a 4 GB VM)"
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

log "ufw: 22, 80, 443"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 443/udp >/dev/null
ufw --force enable >/dev/null

# ---- code -------------------------------------------------------------------------------------
log "code in $DIR"
mkdir -p "$DIR"
if [ -n "$SRC" ]; then
  rsync -a --delete \
    --exclude '.git/' --exclude 'infra/.env' --exclude 'infra/secrets/' \
    --exclude 'app/build/' --exclude 'app/.dart_tool/' --exclude '.venv/' \
    --exclude '__pycache__/' --exclude 'node_modules/' \
    "${SRC%/}/" "$DIR/"
elif [ -d "$DIR/.git" ]; then
  git config --global --add safe.directory "$DIR"
  git -C "$DIR" fetch --quiet origin
  git -C "$DIR" checkout --quiet "$BRANCH"
  git -C "$DIR" pull --quiet --ff-only origin "$BRANCH"
elif [ -n "$REPO" ]; then
  git clone --quiet --branch "$BRANCH" "$REPO" "$DIR"
elif [ ! -f "$DIR/infra/docker-compose.yml" ]; then
  die "no code in $DIR: pass --repo URL or --src DIR"
fi
chown -R "$APP_USER:$APP_USER" "$DIR"

# ---- infra/.env -------------------------------------------------------------------------------
ENV_FILE="$DIR/infra/.env"
if [ ! -f "$ENV_FILE" ]; then
  log "writing infra/.env from infra/.env.prod.example (generated secrets)"
  tmp="$(mktemp)"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *=__GENERATE__) printf '%s=%s\n' "${line%%=*}" "$(openssl rand -hex 32)" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$DIR/infra/.env.prod.example" > "$tmp"
  install -m 600 -o "$APP_USER" -g "$APP_USER" "$tmp" "$ENV_FILE"
  rm -f "$tmp"
  echo "Generated secrets are in $ENV_FILE. Copy RESTIC_PASSWORD to a password manager now:"
  echo "without it the off-site backups cannot be restored."
else
  chmod 600 "$ENV_FILE"
  chown "$APP_USER:$APP_USER" "$ENV_FILE"
fi

# ---- infra/secrets ----------------------------------------------------------------------------
SECRETS="$DIR/infra/secrets"
mkdir -p "$SECRETS"
chown -R "$CONTAINER_UID:$CONTAINER_UID" "$SECRETS"
chmod 700 "$SECRETS"
find "$SECRETS" -type f -exec chmod 600 {} +

env_value() { grep -E "^$1=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- || true; }

missing_files=""
for var in FCM_SERVICE_ACCOUNT_FILE PLAY_SERVICE_ACCOUNT_FILE; do
  path="$(env_value "$var")"
  json_var="${var%_FILE}_JSON"
  case "$path" in
    /run/secrets/banega/*)
      if [ ! -f "$SECRETS/${path#/run/secrets/banega/}" ] && [ -z "$(env_value "$json_var")" ]; then
        missing_files="$missing_files $SECRETS/${path#/run/secrets/banega/} ($var)"
      fi ;;
  esac
done

placeholders="$(grep -nE '^[A-Z0-9_]+=.*(CHANGE_ME|__GENERATE__)' "$ENV_FILE" | cut -d= -f1 || true)"
if [ -n "$placeholders" ] || [ -n "$missing_files" ]; then
  echo
  [ -n "$placeholders" ] && printf 'Still to fill in %s:\n%s\n' "$ENV_FILE" "$placeholders"
  [ -n "$missing_files" ] && printf 'Missing service-account files:%s\n' "$missing_files"
  if [ "$ALLOW_PLACEHOLDERS" -ne 1 ]; then
    echo "Edit them, then run this script again (or pass --allow-placeholders)."
    exit 2
  fi
  echo "--allow-placeholders: continuing anyway (the API refuses unsafe values at boot)."
fi

# ---- start --------------------------------------------------------------------------------------
COMPOSE=(docker compose -f infra/docker-compose.yml -f infra/docker-compose.prod.yml --env-file infra/.env)
log "validating compose config"
(cd "$DIR" && sudo -u "$APP_USER" "${COMPOSE[@]}" config -q)

if [ "$UP" -eq 1 ]; then
  log "docker compose up -d --build (first build takes a few minutes)"
  (cd "$DIR" && sudo -u "$APP_USER" "${COMPOSE[@]}" up -d --build --remove-orphans)
  (cd "$DIR" && sudo -u "$APP_USER" "${COMPOSE[@]}" ps)
  echo
  echo "Next: infra/deploy/README.md steps 7-10 (staff account, seed, health checks, backups)."
fi
