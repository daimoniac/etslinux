#!/usr/bin/env bash
# Install the "KNX ETS5 Compatibility Components" side package (the ETS3
# plug-in layer): EIBA.Interop.EtecDOM / EtecFwk / EtecHawk, plus
# EIBA.DownloadImageHelper and EIBA.Hawk.Utils. Legacy manufacturer "Baggage"
# plugins such as FastDownload.dll call into these during a device download.
#
# The ETS5 Burn bundle carries this as its own MSI (ProductName "KNX ETS5
# Compatibility Components", ProductCode
# {070C17B5-D0DB-443A-9504-0AF04FE91F1E}) and that MSI ends up registered as
# installed, but its one feature ("Compatibility") is left advertised rather
# than placed on disk: no EIBA.Interop.EtecDOM.dll under Common Files\EIBA
# sc, no GAC entries for the older EIBA.Interop.* versions those plugins
# pin to, no CLSID registration. ETS reaches for all of that lazily, through
# Windows Installer's on-demand/self-heal path (what the ETS log calls
# EtecRedirection), and that path returns ERROR_RESOURCE_NAME_NOT_FOUND
# (0x80070716) under Wine. A direct `msiexec /i` against the same cached MSI
# is a different, synchronous code path and does not go through self-heal.
. "$(dirname "$0")/lib.sh"

need_cmd wine
need_cmd msiinfo
refuse_if_ets_running

drive="$WINEPREFIX/drive_c"
installer_dir="$drive/windows/Installer"
[ -d "$installer_dir" ] || die "no Windows Installer cache at $installer_dir; run scripts/50-ets.sh first"

eiba_dir="$drive/Program Files (x86)/Common Files/EIBA sc"
marker="$eiba_dir/EIBA.Interop.EtecDOM.dll"
if [ -f "$marker" ] && [ "${ETS5_EIBASC_REINSTALL:-0}" != 1 ]; then
  printf 'EIBA.Interop.EtecDOM.dll already present, skipping (set ETS5_EIBASC_REINSTALL=1 to run it again)\n'
  exit 0
fi

msi=""
for cand in "$installer_dir"/*.msi; do
  [ -f "$cand" ] || continue
  name=$(msiinfo export "$cand" Property 2>/dev/null | awk -F'\t' '$1 == "ProductName" { print $2 }')
  case "$name" in
    *'Compatibility Components'*) msi=$cand; break ;;
  esac
done
[ -n "$msi" ] || die "no cached MSI named *Compatibility Components* under $installer_dir; it ships inside Ets5Setup.exe and is only cached there once ETS itself has been installed"

winpath="C:\\windows\\Installer\\$(basename "$msi")"
log="$drive/eibasc-install.log"
rm -f "$log"
# REINSTALL=ALL/REINSTALLMODE=vomus forces every file, GAC assembly, and
# registry entry back onto disk even though the product is already marked
# installed; ADDLOCAL=ALL covers the one Level=1 "Compatibility" feature in
# case it was never marked local to begin with.
wine msiexec /i "$winpath" ADDLOCAL=ALL REINSTALL=ALL REINSTALLMODE=vomus /qn /l*v "C:\\eibasc-install.log" || true
wineserver -k >/dev/null 2>&1 || true
sleep 1

if [ ! -f "$marker" ]; then
  [ -f "$log" ] && tail -60 "$log" >&2
  die "EIBA.Interop.EtecDOM.dll still missing from $eiba_dir after msiexec; see $log"
fi

gac_hits=$(find "$drive/windows/assembly" -iname 'EIBA.Interop.EtecDOM.dll' 2>/dev/null | wc -l)
[ "$gac_hits" -gt 0 ] || printf 'warning: EIBA.Interop.EtecDOM.dll is not in the GAC; older Baggage plugins pinned to it may still fail\n' >&2

printf 'installed %s (%s GAC version(s) of EIBA.Interop.EtecDOM.dll)\n' "$marker" "$gac_hits"
