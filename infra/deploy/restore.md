# Restoring from the off-site backups

The `db-backup` service (`infra/deploy/backup.sh`, image `backup.Dockerfile` = Postgres 16
client + restic) takes one restic snapshot per night with:

- `/backup/db/banega.dump`: `pg_dump -Fc --no-owner` of the whole database (schema,
  pgvector extension, data, `alembic_version`);
- `/srv/media`: uploaded recipe photos (data exports under `/srv/media/exports` are
  excluded; they expire after 7 days anyway).

Snapshots are tagged `nightly`, host `BACKUP_HOST` (`banega-prod`), kept 7 daily / 4 weekly /
6 monthly. You need `RESTIC_REPOSITORY`, `RESTIC_PASSWORD` and the bucket key
(`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) - all in `infra/.env`, and the password also
in your password manager (if the VM is gone, that copy is the only one).

```bash
cd /opt/banega
alias dc='sudo -u banega docker compose -f infra/docker-compose.yml -f infra/docker-compose.prod.yml --env-file infra/.env'
```

## A. Restore into a scratch database (drill, or to look at old data)

Safe on the live VM: nothing running is touched.

```bash
dc exec db-backup backup.sh snapshots --host banega-prod        # pick an ID, or use "latest"
dc exec db-backup sh -c '
  set -eu
  rm -rf /backup/restore && mkdir -p /backup/restore
  restic restore latest --host banega-prod --target /backup/restore --include /backup/db
  dropdb --if-exists banega_restore_test
  createdb banega_restore_test
  pg_restore --no-owner --exit-on-error -d banega_restore_test /backup/restore/backup/db/banega.dump
  for db in banega banega_restore_test; do
    printf "%s: " "$db"
    psql -d "$db" -At -c "select (select count(*) from recipes) || '"'"' recipes, '"'"' || (select count(*) from users) || '"'"' users, alembic '"'"' || (select version_num from alembic_version)"
  done
  dropdb banega_restore_test
  rm -rf /backup/restore'
```

The counts of the two databases match (the live one may be a few rows ahead since the
snapshot).

## B. Disaster recovery: restore the live database

1. Stop everything that writes, keep `db` running:

   ```bash
   dc stop caddy nginx api worker admin
   ```

2. Take a last dump of the current state, even if broken (`dc exec db-backup backup.sh run`
   if the database is readable at all).

3. Restore the chosen snapshot's dump and replace the database:

   ```bash
   dc exec db-backup sh -c '
     set -eu
     rm -rf /backup/restore && mkdir -p /backup/restore
     restic restore <ID-or-latest> --host banega-prod --target /backup/restore --include /backup/db
     psql -d postgres -c "DROP DATABASE IF EXISTS banega WITH (FORCE)"
     psql -d postgres -c "CREATE DATABASE banega"
     pg_restore --no-owner --exit-on-error -d banega /backup/restore/backup/db/banega.dump
     rm -rf /backup/restore'
   ```

4. Media (only if photos were lost): restore into the backup volume, then copy into the
   media volume (owned by the app user, uid 10001):

   ```bash
   dc exec db-backup restic restore <ID-or-latest> --host banega-prod --target /backup/restore --include /srv/media
   docker run --rm -v banega_db_backups:/backup -v banega_media_data:/srv/media alpine      sh -c 'cp -a /backup/restore/srv/media/. /srv/media/ && chown -R 10001:10001 /srv/media && rm -rf /backup/restore'
   ```

5. Start again; `migrate` brings an older dump up to the current schema:

   ```bash
   dc up -d
   curl -s https://api.banega.kornea.in/v1/health/ready
   ```

Redis holds only rate limits, idempotency keys and queued jobs: it is not backed up and
needs no restore (lost queued pushes are re-sent from `push_outbox` by the worker cron).

## C. New VM (the old one is gone)

1. Steps 2-6 of `README.md` on a new droplet, with the **same** `RESTIC_REPOSITORY`,
   `RESTIC_PASSWORD` and bucket key in `infra/.env` (the other generated secrets may be
   new: `JWT_SECRET` changing logs every user out, OTP / invite HMAC keys changing only
   invalidates pending codes and invite links).
2. `bootstrap.sh --no-up`, then `dc up -d db` and section B steps 3-5. Point DNS at the new
   IP (step 3 of `README.md`).

Without a VM at all (e.g. on a laptop with Docker), the same tools work from the backup
image: `docker build -t banega-backup -f infra/deploy/backup.Dockerfile infra/deploy`, then
`docker run --rm -e RESTIC_REPOSITORY=... -e RESTIC_PASSWORD=... -e AWS_ACCESS_KEY_ID=... -e
AWS_SECRET_ACCESS_KEY=... -v "$PWD/restore:/restore" banega-backup restore latest --target
/restore`.

## Drill log

**2026-10-02, Windows dev machine, Docker 28**: the real `backup.sh` in the real
`backup.Dockerfile` image, against the dev compose Postgres (`banega-db-1`, network
`banega_default`), with a local filesystem restic repository instead of S3 (the S3 backend
is the same code path in restic; only `RESTIC_REPOSITORY` differs). The dev database was only
read (pg_dump); the restore went into a scratch database that was dropped afterwards.

```bash
S=<scratch dir>; mkdir -p "$S/repo" "$S/backup" "$S/media/recipes" "$S/media/exports"
echo photo-bytes > "$S/media/recipes/test.jpg"; echo secret > "$S/media/exports/x.json"
docker build -t banega-backup:test -f infra/deploy/backup.Dockerfile infra/deploy

# backup (init + dump + snapshot + forget/prune)
docker run --rm --network banega_default \
  -e PGHOST=db -e PGUSER=banega -e PGPASSWORD=banega-dev-password -e PGDATABASE=banega \
  -e RESTIC_REPOSITORY=/repo -e RESTIC_PASSWORD=drill-password -e BACKUP_HOST=banega-drill \
  -e TZ=Asia/Kolkata \
  -v "$S/repo:/repo" -v "$S/backup:/backup" -v "$S/media:/srv/media:ro" banega-backup:test run
#   created restic repository d941497eaf at /repo
#   Files: 2 new (dump + test.jpg; exports/ excluded)   snapshot 18d6757c saved
#   keep 1 snapshots (daily, weekly, monthly)            backup: done   exit 0

# restore + verify
docker run --rm --network banega_default -e PGHOST=db -e PGUSER=banega \
  -e PGPASSWORD=banega-dev-password -e RESTIC_REPOSITORY=/repo -e RESTIC_PASSWORD=drill-password \
  -v "$S/repo:/repo" -v "$S/restore:/restore" -v "$S:/drill" --entrypoint sh banega-backup:test -c '
  set -eu
  restic restore latest --host banega-drill --target /restore
  dropdb --if-exists banega_restore_test; createdb banega_restore_test
  pg_restore --no-owner --exit-on-error -d banega_restore_test /restore/backup/db/banega.dump
  for db in banega banega_restore_test; do printf "%s: " "$db"; psql -d "$db" -At -f /drill/verify.sql; done
  dropdb banega_restore_test'
#   Restored 7 files/dirs (867.931 KiB); /restore/srv/media/recipes/test.jpg present
#   banega:              40 tables, 1022 recipes, 3 users, 1 households, alembic 0012_invite_code
#   banega_restore_test: 40 tables, 1022 recipes, 3 users, 1 households, alembic 0012_invite_code
```

(`verify.sql` = the counts query from section A.) Failure path also checked: a wrong
`PGPASSWORD` makes `backup.sh run` exit 1, writes `/backup/.last-failed` (container
healthcheck -> unhealthy) and keeps the previous good dump.

Repeat the drill (section A) on the VM before launch, against the real bucket, and after
every Postgres or restic upgrade.
