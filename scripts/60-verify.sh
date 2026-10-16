#!/usr/bin/env bash
# Checkpoints. This does not launch the ETS window.
#   --cctor   load ETS5N.exe and run Knx.Ets.Ets5.App's static constructor
#             (fails if ETS is already running)
. "$(dirname "$0")/lib.sh"

need_cmd wine
need_cmd file
fail=0
ok() { printf 'ok  %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1" >&2; fail=1; }

if wine_is_new_enough; then
  ok "wine $(wine_version_number) >= $WINE_MIN_VERSION"
else
  bad "wine $(wine_version_number) is older than $WINE_MIN_VERSION"
fi

if [ -f "$WINEPREFIX/system.reg" ] && grep -q '#arch=win64' "$WINEPREFIX/system.reg"; then
  ok "prefix $WINEPREFIX is win64"
else
  bad "prefix $WINEPREFIX is missing or not win64"
fi

rel=$(dotnet_release 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' || true)
wow=$(dotnet_release 'HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4\Full' || true)
if [ "${rel:-0}" -ge "$DOTNET48_RELEASE" ] && [ "${wow:-0}" -ge "$DOTNET48_RELEASE" ]; then
  ok ".NET 4.8 Release $rel"
else
  bad ".NET Release native=${rel:-missing} wow=${wow:-missing}, want >= $DOTNET48_RELEASE"
fi

for dll in "$WINEPREFIX/drive_c/windows/system32/mscoree.dll" \
           "$WINEPREFIX/drive_c/windows/syswow64/mscoree.dll"; do
  if [ -f "$dll" ] && ! file -b "$dll" | grep -q 'for WINE'; then
    ok "native $(basename "$(dirname "$dll")")/mscoree.dll"
  else
    bad "mscoree is missing or still Wine's builtin: $dll"
  fi
done

root=$(wine reg query 'HKLM\SOFTWARE\Microsoft\.NETFramework' /v InstallRoot 2>/dev/null || true)
if printf '%s' "$root" | grep -q 'Framework64'; then
  ok "InstallRoot"
else
  bad "HKLM InstallRoot is missing (csc then says mscoree.dll could not be loaded)"
fi

drive="$WINEPREFIX/drive_c"
cp -f "$ROOT/scripts/clrtest.cs" "$drive/clrtest.cs"
csc="$drive/windows/Microsoft.NET/Framework/v4.0.30319/csc.exe"
if [ -f "$csc" ]; then
  if wine "$csc" /nologo /noconfig /r:mscorlib.dll /out:C:\\clrtest.exe C:\\clrtest.cs >/tmp/ets5-csc.txt 2>&1 \
     && wine C:\\clrtest.exe 2>/dev/null | grep -q 'CLR OK'; then
    ok "32-bit CLR"
  else
    bad "32-bit csc/clrtest failed (see /tmp/ets5-csc.txt)"
  fi
else
  bad "32-bit csc.exe is missing"
fi

ets="$drive/Program Files (x86)/ETS5/ETS5.exe"
if [ -f "$ets" ]; then
  ok "ETS5.exe present"
else
  bad "ETS5.exe is not installed"
fi

if [ "${1:-}" = "--cctor" ]; then
  refuse_if_ets_running
  if [ ! -f "$ets" ]; then
    bad "cannot probe the static constructor without ETS5.exe"
  else
    cp -f "$ROOT/scripts/ets-probe.cs" "$drive/ets-probe.cs"
    wine "$csc" /nologo /noconfig /r:mscorlib.dll /out:C:\\ets-probe.exe C:\\ets-probe.cs >/tmp/ets5-probe-build.txt 2>&1
    if wine C:\\ets-probe.exe 2>/dev/null | tee /tmp/ets5-probe.txt | grep -q 'cctor OK'; then
      ok "Knx.Ets.Ets5.App static constructor"
    else
      bad "static constructor failed (see /tmp/ets5-probe.txt)"
    fi
  fi
fi

if lsusb -d "$DONGLE_VIDPID" 2>/dev/null | grep -q .; then
  printf 'info dongle %s is attached (lsusb is not success by itself)\n' "$DONGLE_VIDPID"
else
  printf 'info dongle %s is not attached\n' "$DONGLE_VIDPID"
fi

printf '\nSuccess is the ETS window staying open, with its status bar naming the\n'
printf 'license tier that belongs to this stick (for example "ETS5 Lite").\n'

exit "$fail"
