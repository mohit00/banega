#!/usr/bin/env bash
# Run the backend suite against a real Postgres (pgvector) instead of in-memory SQLite.
#
#   TEST_DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/banega_test scripts/test-postgres.sh [pytest args]
#
# Default URL: the dev compose database (infra/docker-compose.yml, port 5432 on localhost),
# database "banega_test" (created on the fly when `docker exec banega-db-1` works).
# Steps: alembic upgrade head -> alembic check (models == migrations) -> downgrade base ->
# upgrade head (round trip) -> pytest with TEST_DATABASE_URL (the suite recreates the schema
# from the models and truncates between tests). The database is wiped: never point it at data
# you want to keep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/backend"
VENV="$BACKEND/.venv"
if [[ -n "${PYTHON:-}" ]]; then
  PY="$PYTHON"
elif [[ -x "$VENV/Scripts/python.exe" || -x "$VENV/Scripts/python" ]]; then
  PY="$VENV/Scripts/python"
elif [[ -x "$VENV/bin/python" ]]; then
  PY="$VENV/bin/python"
else
  PY="python"
fi

export TEST_DATABASE_URL="${TEST_DATABASE_URL:-postgresql+asyncpg://banega:banega-dev-password@127.0.0.1:5432/banega_test}"
case "$TEST_DATABASE_URL" in
  *banega_test* | *_test | *_test\?*) ;;
  *)
    if [[ "${I_KNOW_THIS_WIPES_THE_DB:-}" != "1" ]]; then
      echo "Refusing: TEST_DATABASE_URL does not look like a test database (set I_KNOW_THIS_WIPES_THE_DB=1)." >&2
      exit 2
    fi
    ;;
esac

# Local convenience: create the database in the dev compose container if it is missing.
if command -v docker >/dev/null 2>&1 && docker inspect banega-db-1 >/dev/null 2>&1; then
  db_name="${TEST_DATABASE_URL##*/}"
  db_name="${db_name%%\?*}"
  if ! docker exec banega-db-1 psql -U banega -d banega -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'" | grep -q 1; then
    docker exec banega-db-1 psql -U banega -d banega -c "CREATE DATABASE \"$db_name\"" >/dev/null
  fi
fi

cd "$BACKEND"
export DATABASE_URL="$TEST_DATABASE_URL"
export ENV=test
echo "== alembic round trip on $TEST_DATABASE_URL"
# Start from nothing (the pytest run below leaves a models-created schema without alembic_version).
"$PY" - <<'PYEOF'
import asyncio, os
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

async def main() -> None:
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    async with engine.begin() as conn:
        await conn.execute(text("DROP SCHEMA public CASCADE"))
        await conn.execute(text("CREATE SCHEMA public"))
    await engine.dispose()

asyncio.run(main())
PYEOF
"$PY" -m alembic upgrade head
"$PY" -m alembic check
"$PY" -m alembic downgrade base
"$PY" -m alembic upgrade head
"$PY" -m alembic check

echo "== pytest on Postgres"
unset DATABASE_URL ENV
if [[ $# -eq 0 ]]; then set -- tests; fi
"$PY" -m pytest -q -p no:cacheprovider "$@"
