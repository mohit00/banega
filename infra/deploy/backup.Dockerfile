# Backup runner: pg_dump must match the server's major version (pgvector/pgvector:pg16), and
# restic comes from Alpine's community repo, so one small image has both (no runtime
# installs, no registry: compose builds it on the VM).
FROM postgres:16-alpine

RUN apk add --no-cache restic tzdata curl ca-certificates

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod 0755 /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/backup.sh"]
CMD ["loop"]
