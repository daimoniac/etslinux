#!/usr/bin/env bash
# Install ETS from an installer the user supplies. Tested with ETS 5.7.7
# (Ets5Setup.exe, file version 5.7.1428.39779) and ETS 6.4.1 (Ets6Setup.exe,
# file version 6.4.8718.0). Both are WiX Burn bundles and both are 32-bit.
# The installer is not hashed: KNX does not publish a stable URL for it.
. "$(dirname "$0")/lib.sh"

need_cmd wine
refuse_if_ets_running
setup=${1:-${ETS_SETUP:-}}
[ -n "$setup" ] || die "pass the path to Ets5Setup.exe or Ets6Setup.exe (make ets ETS_SETUP=/path/to/Ets6Setup.exe)"
[ -f "$setup" ] || die "installer not found: $setup"

# ETS 6 installs beside ETS 5 rather than over it, so the two differ only in
# the product directory. Everything before this step is identical.
major=${ETS_MAJOR:-}
if [ -z "$major" ]; then
  case $(basename "$setup") in
    *[Ee]ts5*) major=5 ;;
    *[Ee]ts6*) major=6 ;;
    *) die "cannot tell ETS 5 from ETS 6 by the installer name; set ETS_MAJOR=5 or ETS_MAJOR=6" ;;
  esac
fi
case $major in
  5|6) ;;
  *) die "ETS_MAJOR must be 5 or 6" ;;
esac

ets_exe="$WINEPREFIX/drive_c/Program Files (x86)/ETS$major/ETS$major.exe"
if [ -f "$ets_exe" ] && [ "${ETS_REINSTALL:-0}" != 1 ]; then
  printf 'ETS%s.exe already installed, skipping (set ETS_REINSTALL=1 to run it again)\n' "$major"
  exit 0
fi

rel=$(dotnet_release 'HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4\Full')
[ "$rel" -ge "$DOTNET48_RELEASE" ] || die ".NET 4.8 is not installed; run scripts/20-dotnet.sh"
if file -b "$WINEPREFIX/drive_c/windows/syswow64/mscoree.dll" | grep -q 'for WINE'; then
  die "mscoree is still Wine's builtin; run scripts/30-mscoree.sh before the ETS installer"
fi

# Burn will not load its managed bootstrapper until native mscoree works.
# /log is passed explicitly: ETS 6 does not leave a log at the drive_c root.
log="$WINEPREFIX/drive_c/ets$major-install.log"
wine "$setup" /quiet /norestart /log "c:\\ets$major-install.log" || true
if [ ! -f "$ets_exe" ]; then
  [ -f "$log" ] && tail -40 "$log" >&2
  die "ETS$major.exe was not installed; see $log"
fi
printf 'installed %s\n' "$ets_exe"
