#!/bin/sh
# Off-site backups: pg_dump (custom format) + the media volume -> restic.
#
#   backup.sh run     one backup now (init the repo if needed, dump, backup, forget/prune)
#   backup.sh loop    run every day at BACKUP_AT (HH:MM, container TZ), forever
#   backup.sh init    create the restic repository if it does not exist
#   backup.sh <restic args...>   pass through, e.g. "snapshots" or "restore latest ..."
#
# Environment: PGHOST/PGUSER/PGPASSWORD/PGDATABASE, RESTIC_REPOSITORY, RESTIC_PASSWORD,
# AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (S3-compatible storage), BACKUP_AT (02:30),
# BACKUP_HOST (stable snapshot host name, the container's changes), BACKUP_HEALTHCHECK_URL
# (optional, healthchecks.io style: pinged on success, <url>/fail on failure),
# MEDIA_PATH (/srv/media), BACKUP_DIR (/backup).
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backup}"
MEDIA_PATH="${MEDIA_PATH:-/srv/media}"
BACKUP_HOST="${BACKUP_HOST:-banega-prod}"
BACKUP_AT="${BACKUP_AT:-02:30}"
DUMP_DIR="$BACKUP_DIR/db"
DUMP="$DUMP_DIR/banega.dump"

log() {
  printf '%s backup: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

ping_hc() {
  if [ -n "${BACKUP_HEALTHCHECK_URL:-}" ]; then
    curl -fsS -m 10 --retry 3 -o /dev/null "${BACKUP_HEALTHCHECK_URL}$1" || log "healthcheck ping failed"
  fi
}

init_repo() {
  if restic cat config >/dev/null 2>&1; then
    return 0
  fi
  log "initialising restic repository"
  restic init
}

run_once() {
  mkdir -p "$DUMP_DIR"
  init_repo
  log "pg_dump ${PGDATABASE:-?} from ${PGHOST:-?}"
  # Dump to a temp file first: a failed dump never replaces the last good one.
  pg_dump -Fc --no-owner -f "$DUMP.partial"
  mv "$DUMP.partial" "$DUMP"
  paths="$DUMP_DIR"
  if [ -d "$MEDIA_PATH" ]; then
    paths="$paths $MEDIA_PATH"
  fi
  log "restic backup $paths"
  # shellcheck disable=SC2086 # $paths is a space-separated list of fixed paths
  restic backup --host "$BACKUP_HOST" --tag nightly --exclude "$MEDIA_PATH/exports" $paths
  log "restic forget --prune (7 daily, 4 weekly, 6 monthly)"
  restic forget --host "$BACKUP_HOST" --tag nightly --prune \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 6
  # Weekly integrity check of the repository structure (Sunday).
  if [ "$(date +%u)" = "7" ]; then
    log "restic check"
    restic check
  fi
  date '+%Y-%m-%dT%H:%M:%S%z' > "$BACKUP_DIR/.last-success"
  rm -f "$BACKUP_DIR/.last-failed"
  log "done"
}

run_checked() {
  ping_hc /start
  # A separate process: "set -e" is ignored inside an if condition in this shell.
  if "$0" once; then
    ping_hc ""
  else
    log "FAILED"
    date '+%Y-%m-%dT%H:%M:%S%z' > "$BACKUP_DIR/.last-failed"
    ping_hc /fail
    return 1
  fi
}

loop() {
  log "scheduled daily at $BACKUP_AT ($(date +%Z))"
  last=""
  while true; do
    today="$(date +%F)"
    if [ "$(date +%H:%M)" = "$BACKUP_AT" ] && [ "$last" != "$today" ]; then
      last="$today"
      run_checked || true
    fi
    sleep 30
  done
}

cmd="${1:-loop}"
case "$cmd" in
  run) mkdir -p "$BACKUP_DIR"; run_checked ;;
  once) run_once ;;
  loop) mkdir -p "$BACKUP_DIR"; loop ;;
  init) init_repo ;;
  *) exec restic "$@" ;;
esac
