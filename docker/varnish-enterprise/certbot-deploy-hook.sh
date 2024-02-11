#!/bin/bash
# Full path to pre-generated Diffie Hellman Parameters file
dhparams=/etc/varnish/certs/dhparams.pem
if [ ! -f ${dhparams} ]; then
    mkdir -p /etc/varnish/certs
    openssl dhparam -out $dhparams 4096
fi

if [[ "${RENEWED_LINEAGE}" == "" ]]; then
    echo "Error: missing RENEWED_LINEAGE env variable." >&2
    exit 1
fi

umask 077
cat ${RENEWED_LINEAGE}/privkey.pem \
${RENEWED_LINEAGE}/fullchain.pem \
${dhparams} > ${RENEWED_LINEAGE}/bundle.pem