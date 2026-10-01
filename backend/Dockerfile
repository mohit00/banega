# syntax=docker/dockerfile:1.7
# Banega API image. Also used by the worker (arq) and the one-shot migrate job.
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /srv/backend

RUN groupadd --system --gid 10001 banega \
    && useradd --system --uid 10001 --gid banega --home-dir /srv --shell /usr/sbin/nologin banega

# Dependencies first for layer caching.
COPY pyproject.toml README.md ./
COPY app/__init__.py app/__init__.py
RUN pip install --upgrade pip && pip install .

COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./
# Reinstall so the installed package matches the full source (deps are already cached).
# /srv/media: data exports (MEDIA_DIR). Created owned by the app user so a fresh named
# volume mounted there inherits the ownership.
RUN pip install --no-deps --force-reinstall . \
    && mkdir -p /srv/media \
    && chown -R banega:banega /srv/backend /srv/media

USER banega
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=5 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/v1/health/ready', timeout=3).status == 200 else 1)"

# No --proxy-headers: the API resolves the client IP from X-Forwarded-For (TRUSTED_PROXIES).
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-proxy-headers"]
