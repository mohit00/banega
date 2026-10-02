#!/bin/sh
# nginx entrypoint: render /etc/nginx/nginx.conf from the template, test it, then hand over
# to the image's own entrypoint.
#   ADMIN_ALLOW_CIDR="203.0.113.0/24,198.51.100.7"  ->  allow ...; allow ...; deny all;
#   REAL_IP_FROM="172.16.0.0/12,10.0.0.0/8"         ->  set_real_ip_from ...; (the client
#     address then comes from X-Forwarded-For set by that proxy, e.g. Caddy in prod, so the
#     admin allow-list and the rate limits see the real client and not the proxy)
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
real_ip=""
if [ -n "${REAL_IP_FROM:-}" ]; then
  for cidr in $(echo "$REAL_IP_FROM" | tr ',' ' '); do
    real_ip="${real_ip}set_real_ip_from ${cidr}; "
  done
  real_ip="${real_ip}real_ip_header X-Forwarded-For; real_ip_recursive on;"
else
  real_ip="# REAL_IP_FROM not set: the client address is the TCP peer"
fi
export ADMIN_ALLOW_RULES="$rules"
export REAL_IP_RULES="$real_ip"
# shellcheck disable=SC2016 # literal variable names for envsubst, not expansions
envsubst '${ADMIN_ALLOW_RULES} ${REAL_IP_RULES}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -t -q
exec /docker-entrypoint.sh nginx -g 'daemon off;'
