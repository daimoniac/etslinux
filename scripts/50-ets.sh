#!/usr/bin/env bash
# Install ETS from an installer the user supplies. Tested with ETS 5.7.7
# (Ets5Setup.exe, a WiX Burn bundle, file version 5.7.1428.39779).
# The installer is not hashed: KNX does not publish a stable URL for it.
. "$(dirname "$0")/lib.sh"

need_cmd wine
refuse_if_ets_running
setup=${1:-${ETS_SETUP:-}}
[ -n "$setup" ] || die "pass the path to Ets5Setup.exe (make ets ETS_SETUP=/path/to/Ets5Setup.exe)"
[ -f "$setup" ] || die "installer not found: $setup"

ets_exe="$WINEPREFIX/drive_c/Program Files (x86)/ETS5/ETS5.exe"
if [ -f "$ets_exe" ] && [ "${ETS_REINSTALL:-0}" != 1 ]; then
  printf 'ETS5.exe already installed, skipping (set ETS_REINSTALL=1 to run it again)\n'
  exit 0
fi

rel=$(dotnet_release 'HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4\Full')
[ "$rel" -ge "$DOTNET48_RELEASE" ] || die ".NET 4.8 is not installed; run scripts/20-dotnet.sh"
if file -b "$WINEPREFIX/drive_c/windows/syswow64/mscoree.dll" | grep -q 'for WINE'; then
  die "mscoree is still Wine's builtin; run scripts/30-mscoree.sh before the ETS installer"
fi

# Burn will not load its managed bootstrapper until native mscoree works.
wine "$setup" /quiet /norestart || true
if [ ! -f "$ets_exe" ]; then
  log=$WINEPREFIX/drive_c/ets5-install.log
  [ -f "$log" ] && tail -40 "$log" >&2
  die "ETS5.exe was not installed; see $log"
fi
printf 'installed %s\n' "$ets_exe"
