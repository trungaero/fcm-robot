#!/bin/sh
# Renders the illustrative config template into a runnable config.
# Only plain `sed` substitutions are used so the image needs no extra tooling.
set -eu

: "${LIVEKIT_API_KEY:?LIVEKIT_API_KEY is required}"
: "${LIVEKIT_API_SECRET:?LIVEKIT_API_SECRET is required}"

NODE_IP="${NODE_IP:-127.0.0.1}"
TURN_ENABLED="${TURN_ENABLED:-false}"
TURN_DOMAIN="${TURN_DOMAIN:-turn.invalid}"
TURN_EXTERNAL_TLS="${TURN_EXTERNAL_TLS:-true}"

sed \
  -e "s|__API_KEY__|${LIVEKIT_API_KEY}|g" \
  -e "s|__API_SECRET__|${LIVEKIT_API_SECRET}|g" \
  -e "s|__NODE_IP__|${NODE_IP}|g" \
  -e "s|__TURN_ENABLED__|${TURN_ENABLED}|g" \
  -e "s|__TURN_DOMAIN__|${TURN_DOMAIN}|g" \
  -e "s|__TURN_EXTERNAL_TLS__|${TURN_EXTERNAL_TLS}|g" \
  /etc/livekit/livekit.tpl.yaml > /etc/livekit/livekit.yaml

exec /livekit-server "$@"
