#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

role=$1
shift
case "$role" in
  client|server) ;;
  *) die "usage: $0 client|server <compose args>" ;;
esac
[ -f "$ROOT/.env" ] || die "copy .env.example to .env and edit it"
load_env
if [ "$role" = server ]; then
  case "${USBIP_BIND_ADDRESS:-}" in
    ""|0.0.0.0|"::"|"::0")
      die "USBIP_BIND_ADDRESS must be this host's LAN address, not a wildcard"
      ;;
  esac
fi
if [ "$role" = client ]; then
  [ -n "${USBIP_SERVER:-}" ] || die "set USBIP_SERVER in .env"
fi
files=(-f "$ROOT/compose/$role/docker-compose.yml")
if [ -n "${MQTT_OPTIONS:-}" ]; then
  files+=(-f "$ROOT/compose/$role/mqtt.yml")
fi
exec docker compose --env-file "$ROOT/.env" "${files[@]}" "$@"
