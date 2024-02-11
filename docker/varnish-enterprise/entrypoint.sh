#!/usr/bin/env sh
# Entrypoint from ffplay https://github.com/MioYvo/docker-varnish/blob/master/bin/docker-entrypoint.sh 

set -e

if [ -z "$LOG_FORMAT" ]
  then
  export LOG_FORMAT="%{Host}i %h %l %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-agent}i\" ucs=\"%{Varnish:hitmiss}x\" rs=\"%{VSL:Timestamp:Process}x"
fi

if [ -z "$VARNISHLOG" ]
    then 
    export VARNISHLOG=false
fi

if [ -z "$LOG_FORMAT_DEBUG" ]
  then
  export LOG_FORMAT_DEBUG="Begin,ReqUrl,Link,BereqURL,ReqMethod,BerespHeader,ObjHeader"
fi

if [ -z "$VARNISHNCSA" ]
    then
    export VARNISHNCSA=false
fi

# validate required variables are set
if [ -z "$TARGET_HOST" ]
  then
  echo >&2 "Error: TARGET_HOST environment variable is required but not set."
  exit 1
fi

if [ -z "$TARGET_PORT" ]
  then
  TARGET_PORT=80
fi


if [ -z "$VARNISHNCSA_QUERY" ]
  then
    export VARNISHNCSA_QUERY="ReqURL ne \"<url_which_should_be_not_logged>\""
fi

if [ -z "$VARNISH_VCL" ]
    then
    export VARNISH_VCL="/etc/varnish/default.vcl"
fi

if [ -z "$VARNISH_PORT" ]
    then
    export VARNISH_PORT=80
fi

if [ -z "$VARNISH_RAM_STORAGE" ]
    then 
    export VARNISH_RAM_STORAGE="128M"
fi

if [ -z "${VARNISHD_DEFAULT_OPTS}" ]; then
    # VARNISHD_DEFAULT_OPTS="-a :${VARNISH_PORT} -s default=malloc,${VARNISH_RAM_STORAGE}"
    VARNISHD_DEFAULT_OPTS="-F -a :${VARNISH_PORT}"
fi

## Entry point that is contained inside  quay.io/varnish-software/varnish-plus:latest'

EXTRA=

if [ ! -f "${VARNISH_SECRET_FILE}" ]; then
  echo "Generating new secrets file: ${VARNISH_SECRET_FILE}"
  uuidgen > "${VARNISH_SECRET_FILE}"
  chmod 0600 "${VARNISH_SECRET_FILE}"
fi

if [ -f "${MSE_CONFIG}" ]; then
	echo "Creating and initializing Massive Storage Engine data files and stores"
	EXTRA="${EXTRA} -s mse,${MSE_CONFIG}"
	mkfs.mse -c "${MSE_CONFIG}" || true
else
	EXTRA="${EXTRA} -s mse"
fi

# When running into a container which have resource limits defined
# we have to handle MSE_MEMORY_TARGET with % differently.
# We are going to use cgroups pseudo fs mounted in /sys/fs/cgroup and use memory subdirectory as references for now
# Only if we have %
# if echo "${MSE_MEMORY_TARGET}" | grep -q "%"; then
#   # 2^63 -> 9223372036854771712 : default value if none are present on container creation
#   if grep -qEv "^9223372036854771712$" /sys/fs/cgroup/memory/memory.limit_in_bytes &>/dev/null; then
#     MSE_MEMORY_TARGET=$(awk -v mmt=${MSE_MEMORY_TARGET%\%} '{ printf("%dk\n", int($1 * mmt / 100 / 1024));}' /sys/fs/cgroup/memory/memory.limit_in_bytes)
#   fi
# fi

# Varnish in-core tls
# If VARNISH_TLS_CFG is set and is not a file, generate tlf.cfg and self-signed cert
# If VARNISH_TLS_CFG is set and is a file, use that file. The user is responsible to
# provide the certificate in the correct path as specified in the TLS config file.
if [ -n "${VARNISH_TLS_CFG}" ]; then
	echo "Enabling Varnish in-core TLS"
  if [ -f "${VARNISH_TLS_CFG}" ]; then
    EXTRA="${EXTRA} -A ${VARNISH_TLS_CFG}"
  else
    openssl req -x509 -nodes -days 365 \
			-subj "/CN=localhost" -addext "subjectAltName=DNS:localhost" \
			-newkey rsa:2048 -keyout /dev/shm/varnish-selfsigned.key \
			-out /dev/shm/varnish-selfsigned.crt
    # Concatenate files
    cat /dev/shm/varnish-selfsigned.key /dev/shm/varnish-selfsigned.crt > /dev/shm/varnish-selfsigned.pem
    rm -f /dev/shm/varnish-selfsigned.key /dev/shm/varnish-selfsigned.crt
    # Generate varnishd tls file
    echo -e 'frontend = {\nhost = ""\nport = "6443"\n}\npem-file = "/dev/shm/varnish-selfsigned.pem"\n' \
    > /dev/shm/varnish-tls.cfg
    # Add -A argument with generated config to varnishd
    EXTRA="${EXTRA} -A /dev/shm/varnish-tls.cfg"
  fi
fi





VARNISHD_FULL_OPTS="-f /etc/varnish/default.vcl ${VARNISHD_DEFAULT_OPTS} \
    ${VARNISHD_OPTS} ${VARNISHD_ADDITIONAL_OPTS} "

# update configuration based on env vars
/bin/sed "s|{{TARGET_HOST}}|${TARGET_HOST}|g; s|{{TARGET_PORT}}|${TARGET_PORT}|g" \
  /etc/varnish/default.vcl.in > /etc/varnish/default.vcl

start_varnishd () {
# -p vcc_allow_inline_c=on \
# -p vsl_mask=+Hash \
    # TODO: Verify that the other options are required for performance
    # exec varnishd -f "${VARNISH_VCL_CONF}" \
    #   -F -a "${VARNISH_LISTEN_ADDRESS}":"${VARNISH_LISTEN_PORT}" \
    #   -p thread_pool_min="${VARNISH_MIN_THREADS}" \
    #   -p thread_pool_max="${VARNISH_MAX_THREADS}" \
    #   -p thread_pool_timeout="${VARNISH_THREAD_TIMEOUT}" \
    #   -S "${VARNISH_SECRET_FILE}" \
    #   -t "${VARNISH_TTL}" \
    #   -T "${VARNISH_ADMIN_LISTEN_ADDRESS}:${VARNISH_ADMIN_LISTEN_PORT}" \
    #   -p memory_target="${MSE_MEMORY_TARGET}" ${VARNISH_EXTRA} ${EXTRA}

    # varnishd development configuration
    # VARNISHD="$(command -v varnishd)  \
    #                 -p vcc_allow_inline_c=on \
    #                 -p vsl_mask=+Hash \
    #                 ${VARNISHD_FULL_OPTS}"

    VARNISHD="$(command -v varnishd)  -f ${VARNISH_VCL_CONF} \
      -F -a ${VARNISH_LISTEN_ADDRESS}:${VARNISH_LISTEN_PORT} \
      -p memory_target=${MSE_MEMORY_TARGET} ${VARNISH_EXTRA} ${EXTRA}"

    echo "VARNISHD: $VARNISHD"
    eval "${VARNISHD}"

    echo "VARNISHLOG: $VARNISHLOG"
    # varnishlog and varnishncsa are mutually exclusive
    if [ ${VARNISHLOG} = true ]
    then
          # Only enable for debguging certain requests using varnishlog. Varnishlog has priority over varnishncsa
      VARNISH_DEBUG_LOG="exec $(command -v varnishlog)  -i '${LOG_FORMAT_DEBUG}' -g session"
      echo $VARNISH_DEBUG_LOG
      eval "${VARNISH_DEBUG_LOG}"
    fi
    ## varnishncsa can also run separately from varnishd
    if [ ${VARNISHNCSA} = true ]
    then
      VARNISHD_NCSA="exec $(command -v varnishncsa) \
                      -q '${VARNISHNCSA_QUERY}' -F '${LOG_FORMAT}' -w /var/log/varnish/access.log"

      echo $VARNISHD_NCSA
      eval "${VARNISHD_NCSA}"

    fi 
    # ssl stuff
    certbot renew
}

start_varnishd
