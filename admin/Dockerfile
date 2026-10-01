# syntax=docker/dockerfile:1.7
# Banega admin panel. Build context is the repo root (it needs backend/ for the models):
#   docker build -f admin/Dockerfile .
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/srv/backend:/srv/admin

RUN groupadd --system --gid 10001 banega \
    && useradd --system --uid 10001 --gid banega --home-dir /srv --shell /usr/sbin/nologin banega

# Backend package (models, db, config) first, then the admin's own deps.
WORKDIR /srv/backend
COPY backend/pyproject.toml backend/README.md ./
COPY backend/app ./app
RUN pip install --upgrade pip && pip install .

WORKDIR /srv/admin
COPY admin/pyproject.toml ./
COPY admin/*.py ./
COPY admin/templates ./templates
# /srv/media is the photo upload volume; create it owned by the app user so a fresh named
# volume inherits the ownership.
RUN pip install . && mkdir -p /srv/media && chown -R banega:banega /srv/admin /srv/media

USER banega
EXPOSE 8001

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=5 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8001/healthz', timeout=2).status == 200 else 1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001", "--proxy-headers", "--forwarded-allow-ips", "*"]
