#!/bin/sh
# nginx entrypoint: render /etc/nginx/nginx.conf from the template, test it, then hand over
# to the image's own entrypoint.
#   ADMIN_ALLOW_CIDR="203.0.113.0/24,198.51.100.7"  ->  allow ...; allow ...; deny all;
set -eu
rules=""
if [ -n "${ADMIN_ALLOW_CIDR:-}" ]; then
  for cidr in $(echo "$ADMIN_ALLOW_CIDR" | tr ',' ' '); do
    rules="${rules}allow ${cidr}; "
  done
  rules="${rules}deny all;"
else
  rules="# ADMIN_ALLOW_CIDR not set: /admin is open (staff login + TOTP still required)"
fi
export ADMIN_ALLOW_RULES="$rules"
envsubst '${ADMIN_ALLOW_RULES}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -t -q
exec /docker-entrypoint.sh nginx -g 'daemon off;'
