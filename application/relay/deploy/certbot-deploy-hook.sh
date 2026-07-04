#!/bin/sh
# Certbot deploy hook for nimna-relay (architecture note §28): a PURE
# FILE COPY — no restart, no reload verb. The relay hot-reloads the
# certificate in-process within ~60 s of the cert file's mtime moving
# (handshake-driven, mtime-checked), so live sessions survive renewal.
#
# Install: /etc/letsencrypt/renewal-hooks/deploy/nimna-relay.sh (mode
# 0755, owner root). Certbot exports RENEWED_LINEAGE when it runs this.
set -eu

TLS_DIR=/etc/nimna-relay/tls
umask 027

# Key FIRST, cert SECOND: the relay's reloader triggers on the CERT
# file's mtime, so by the time it fires the matching key is already in
# place — a renewed cert is never paired with a stale key.
for NAME in privkey fullchain; do
    cp "${RENEWED_LINEAGE}/${NAME}.pem" "${TLS_DIR}/${NAME}.pem.new"
    chown root:nimna-relay "${TLS_DIR}/${NAME}.pem.new"
    chmod 0640 "${TLS_DIR}/${NAME}.pem.new"
    mv "${TLS_DIR}/${NAME}.pem.new" "${TLS_DIR}/${NAME}.pem"
done
