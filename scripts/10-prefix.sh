#!/usr/bin/env bash
# Create the dedicated win64 prefix. WineHQ's Ubuntu builds are new WoW64:
# there is no usable WINEARCH=win32 prefix.
. "$(dirname "$0")/lib.sh"

need_cmd wine
need_cmd wineboot
refuse_if_ets_running

if ! wine_is_new_enough; then
  die "Wine $(wine_version_number) is older than $WINE_MIN_VERSION; run scripts/00-host.sh client"
fi
if [ "${WINEARCH}" != win64 ]; then
  die "WINEARCH must be win64 (this Wine build is new WoW64)"
fi

mkdir -p "$(dirname "$WINEPREFIX")"
if [ -f "$WINEPREFIX/system.reg" ]; then
  if ! grep -q '#arch=win64' "$WINEPREFIX/system.reg"; then
    die "$WINEPREFIX is not a win64 prefix; remove it or set WINEPREFIX to a new directory"
  fi
  printf 'prefix already exists: %s\n' "$WINEPREFIX"
  exit 0
fi

# Empty overrides skip the Mono/Gecko download prompts during first boot.
WINEDLLOVERRIDES='mscoree=,mshtml=' wineboot --init
wineserver -k >/dev/null 2>&1 || true
printf 'created %s\n' "$WINEPREFIX"
