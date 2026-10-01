#!/usr/bin/env bash
# Banega developer tasks. Works in Git Bash (Windows), macOS and Linux.
#   scripts/dev.sh setup | test | lint | fmt | migrate | revision "msg" |
#                  compose-config | compose-up | compose-down | logs
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/backend"
VENV="$BACKEND/.venv"
COMPOSE=(docker compose -f "$ROOT/infra/docker-compose.yml")
if [[ -f "$ROOT/infra/.env" ]]; then
  COMPOSE+=(--env-file "$ROOT/infra/.env")
fi

if [[ -x "$VENV/Scripts/python.exe" || -x "$VENV/Scripts/python" ]]; then
  PY="$VENV/Scripts/python"
else
  PY="$VENV/bin/python"
fi

find_python() {
  for candidate in python3.13 python3.12 python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return
    fi
  done
  echo "No python found" >&2
  exit 1
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  setup)
    if [[ ! -d "$VENV" ]]; then
      "$(find_python)" -m venv "$VENV"
      if [[ -x "$VENV/Scripts/python.exe" || -x "$VENV/Scripts/python" ]]; then
        PY="$VENV/Scripts/python"
      else
        PY="$VENV/bin/python"
      fi
    fi
    "$PY" -m pip install --upgrade pip
    "$PY" -m pip install -e "$BACKEND[dev]"
    # Admin deps in the same venv so the admin panel runs locally too.
    "$PY" -m pip install -e "$ROOT/admin"
    [[ -f "$ROOT/infra/.env" ]] || cp "$ROOT/infra/.env.example" "$ROOT/infra/.env"
    echo "Setup done. Python: $PY"
    ;;
  test)
    (cd "$ROOT" && "$PY" -m pytest backend/tests -q "$@")
    ;;
  lint)
    "$PY" -m ruff check "$BACKEND" "$ROOT/admin"
    "$PY" -m ruff format --check "$BACKEND" "$ROOT/admin"
    (cd "$BACKEND" && "$PY" -m mypy)
    ;;
  fmt)
    "$PY" -m ruff check --fix "$BACKEND" "$ROOT/admin"
    "$PY" -m ruff format "$BACKEND" "$ROOT/admin"
    ;;
  migrate)
    # Inside compose (default) or against DATABASE_URL locally with --local.
    if [[ "${1:-}" == "--local" ]]; then
      (cd "$BACKEND" && "$PY" -m alembic upgrade head)
    else
      "${COMPOSE[@]}" run --rm migrate
    fi
    ;;
  revision)
    (cd "$BACKEND" && "$PY" -m alembic revision --autogenerate -m "${1:?message required}")
    ;;
  compose-config)
    "${COMPOSE[@]}" config -q && echo "compose config OK"
    ;;
  compose-up)
    "${COMPOSE[@]}" up --build -d "$@"
    ;;
  compose-down)
    "${COMPOSE[@]}" down "$@"
    ;;
  logs)
    "${COMPOSE[@]}" logs -f "$@"
    ;;
  help | *)
    sed -n '2,4p' "$0"
    ;;
esac
