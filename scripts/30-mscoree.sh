#!/usr/bin/env bash
# Replace Wine's builtin mscoree with Microsoft's, point .NET at its
# InstallRoot, and import the .NET 4.0 COM registration the 4.8 installer
# does not write. ETS's static constructor fails without that registration
# (REGDB_E_KEYMISSING, then REGDB_E_CLASSNOTREG).
. "$(dirname "$0")/lib.sh"

need_cmd wine
need_cmd 7z
need_cmd msiextract
need_cmd msiinfo
need_cmd file
need_cmd python3
refuse_if_ets_running
[ -f "$WINEPREFIX/system.reg" ] || die "no prefix at $WINEPREFIX"

download "$DOTNET40_URL" "$ETS5_CACHE/dotNetFx40_Full_x86_x64.exe" "$DOTNET40_SHA256"

extract=$ETS5_CACHE/dotnet40-msis
rm -rf "$extract"
mkdir -p "$extract"
7z x -y "-o$extract" "$ETS5_CACHE/dotNetFx40_Full_x86_x64.exe" \
  netfx_Core_x86.msi netfx_Core_x64.msi >/dev/null

x86=$extract/netfx_Core_x86.msi
x64=$extract/netfx_Core_x64.msi
[ -f "$x86" ] && [ -f "$x64" ] || die "netfx_Core MSIs were not inside the .NET 4.0 redistributable"

files=$ETS5_CACHE/dotnet40-files
rm -rf "$files"
mkdir -p "$files/x86" "$files/x64"
msiextract --directory "$files/x86" "$x86" >/dev/null
msiextract --directory "$files/x64" "$x64" >/dev/null

sys32=$WINEPREFIX/drive_c/windows/system32
syswow=$WINEPREFIX/drive_c/windows/syswow64
mkdir -p "$sys32" "$syswow"
copied32=0
copied64=0
while IFS= read -r dll; do
  kind=$(file -b "$dll")
  case "$kind" in
    PE32+*) cp -f "$dll" "$sys32/mscoree.dll"; copied64=1 ;;
    PE32*) cp -f "$dll" "$syswow/mscoree.dll"; copied32=1 ;;
  esac
done < <(find "$files" -iname 'mscoree.dll' -type f)

[ "$copied32" = 1 ] && [ "$copied64" = 1 ] || die "could not find both 32-bit and 64-bit mscoree.dll"
if file -b "$sys32/mscoree.dll" | grep -q 'for WINE'; then
  die "system32/mscoree.dll is still Wine's builtin"
fi
if file -b "$syswow/mscoree.dll" | grep -q 'for WINE'; then
  die "syswow64/mscoree.dll is still Wine's builtin"
fi

wine reg add 'HKCU\Software\Wine\DllOverrides' /v mscoree /d native /f >/dev/null
wine reg add 'HKLM\SOFTWARE\Microsoft\.NETFramework' /v InstallRoot /t REG_SZ \
  /d 'C:\windows\Microsoft.NET\Framework64\' /f >/dev/null
wine reg add 'HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework' /v InstallRoot /t REG_SZ \
  /d 'C:\windows\Microsoft.NET\Framework\' /f >/dev/null

wineserver -k >/dev/null 2>&1 || true
sleep 1
regfile=$ETS5_CACHE/dotnet40-com.reg
python3 "$ROOT/scripts/import_dotnet40_com.py" "$x86" "$x64" "$WINEPREFIX/system.reg" "$regfile"
wine regedit /s "$regfile"
wineserver -k >/dev/null 2>&1 || true
printf 'Microsoft mscoree in place and .NET 4.0 COM registration imported\n'
