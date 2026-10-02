@echo off
REM ---------------------------------------------------------------
REM  Banega local dev servers (Windows)
REM    dev-servers.bat        -> start db + redis in Docker, migrate, then API (8765) and admin (8766) in new windows
REM    dev-servers.bat seed   -> same, plus load the demo data and content\recipes-master.csv first
REM  API:   http://127.0.0.1:8765/v1/health   (emulator: http://10.0.2.2:8765)
REM  Admin: http://127.0.0.1:8766/admin/login  (dev login: admin / change-me)
REM ---------------------------------------------------------------
setlocal
set "ROOT=%~dp0.."
set "PY=%ROOT%\backend\.venv\Scripts\python.exe"
set "MASTER=%ROOT%\content\recipes-master.csv"
set "DATABASE_URL=postgresql+asyncpg://banega:banega-dev-password@127.0.0.1:5432/banega"
set "REDIS_URL=memory://"
set "ENV=dev"
set "OTP_PROVIDER=dev"
set "JWT_SECRET=dev-only-secret-change-me-please-0123456789"
set "CONTENT_DIR=%ROOT%\content"
set "ADMIN_USERNAME=admin"
set "ADMIN_PASSWORD=change-me"
set "ADMIN_SECRET_KEY=dev-only-admin-secret-change-me"
set "ADMIN_BASE_URL=/admin"
rem Real push when the Firebase server key is present (kept outside the repo).
set "FCM_KEY=%USERPROFILE%\.banega\secrets\fcm-service-account.json"
if exist "%FCM_KEY%" (
  set "PUSH_PROVIDER=fcm"
  set "FCM_PROJECT_ID=banega-fb1ed"
  set "FCM_SERVICE_ACCOUNT_FILE=%FCM_KEY%"
)

echo [banega] Starting Postgres and Redis...
docker compose -f "%ROOT%\infra\docker-compose.yml" --env-file "%ROOT%\infra\.env.example" up -d db redis || exit /b 1
timeout /t 5 /nobreak >nul

pushd "%ROOT%\backend"
echo [banega] Migrating database...
"%PY%" -m alembic upgrade head || (popd & exit /b 1)
if /i "%~1"=="seed" (
  echo [banega] Seeding demo data...
  "%PY%" -m app.cli seed --publish all
  if exist "%MASTER%" (
    echo [banega] Importing the recipe master sheet...
    "%PY%" -m app.cli import-recipes "%MASTER%" --publish clean --supersede-same-name
  )
  "%PY%" -m app.cli demo-day
)
echo [banega] Starting API on 8765...
start "banega-api" cmd /k ""%PY%" -m uvicorn app.main:app --host 0.0.0.0 --port 8765"
popd

pushd "%ROOT%\admin"
set "PYTHONPATH=%ROOT%\backend;%ROOT%\admin"
echo [banega] Starting admin on 8766...
start "banega-admin" cmd /k ""%PY%" -m uvicorn main:app --host 127.0.0.1 --port 8766"
popd

echo [banega] API:   http://127.0.0.1:8765/v1/health
echo [banega] Admin: http://127.0.0.1:8766/admin/login  (admin / change-me)
endlocal
