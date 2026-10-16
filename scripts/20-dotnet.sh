#!/usr/bin/env bash
# Install .NET Framework 4.8 into the prefix.
#
# The 4.8 installer treats a Wine-reported Windows 10 (build 19045) as
# "already installed" and returns success without writing the Release key.
# It has to run while the prefix claims to be Windows 7 SP1. The prefix is
# put back on Windows 10 afterwards; ETS wants that.
. "$(dirname "$0")/lib.sh"

need_cmd wine
need_cmd curl
refuse_if_ets_running
[ -f "$WINEPREFIX/system.reg" ] || die "no prefix at $WINEPREFIX; run scripts/10-prefix.sh"

ensure_windows_10() {
  product=$(windows_product_name)
  case "$product" in
    *Windows\ 10*) return 0 ;;
  esac
  set_windows_version win10
}

rel=$(dotnet_release 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full')
wow=$(dotnet_release 'HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4\Full')
if [ "$rel" -ge "$DOTNET48_RELEASE" ] && [ "$wow" -ge "$DOTNET48_RELEASE" ]; then
  # A previous run can die after the installer and before the win10 switch.
  ensure_windows_10
  printf '.NET 4.8 already installed (Release %s)\n' "$rel"
  exit 0
fi

download "$DOTNET48_URL" "$ETS5_CACHE/NDP48-x86-x64-AllOS-ENU.exe" "$DOTNET48_SHA256"

set_windows_version win7
product=$(windows_product_name)
case "$product" in
  *Windows\ 7*) ;;
  *) die "prefix still reports '$product'; refusing to run the 4.8 installer" ;;
esac

wine "$ETS5_CACHE/NDP48-x86-x64-AllOS-ENU.exe" /q /norestart
rel=$(dotnet_release 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full')
wow=$(dotnet_release 'HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4\Full')
if [ "$rel" -lt "$DOTNET48_RELEASE" ] || [ "$wow" -lt "$DOTNET48_RELEASE" ]; then
  die ".NET 4.8 installer returned without Release >= $DOTNET48_RELEASE (native=$rel wow=$wow)"
fi

ensure_windows_10
printf '.NET 4.8 installed (Release %s); prefix set back to Windows 10\n' "$rel"
