#!/usr/bin/env bash
# Install the "KNX ETS5 Compatibility Components" side package (the ETS3
# plug-in layer): EIBA.Interop.EtecDOM / EtecFwk / EtecHawk, plus
# EIBA.DownloadImageHelper and EIBA.Hawk.Utils. Legacy manufacturer "Baggage"
# plugins such as FastDownload.dll call into these during a device download.
#
# The ETS5 Burn bundle carries this as its own MSI (ProductName "KNX ETS5
# Compatibility Components", ProductCode
# {070C17B5-D0DB-443A-9504-0AF04FE91F1E}, built from WiX merge modules: its
# File/Component names carry the merge module GUID
# 77626993-DC40-4398-ADFC-4D62EC96B3C0). That MSI ends up registered as
# installed, but nothing it owns is actually on disk: no
# EIBA.Interop.EtecDOM.dll under Common Files\EIBA sc, no CLSID
# registration. `wine msiexec /i` against the very same cached MSI "succeeds"
# (exit 0) and still writes nothing; its InstallExecuteSequence runs under
# Wine's own msi.dll without placing a single file. ETS reaches for the
# missing assembly lazily, through Windows Installer's self-heal path (what
# the ETS log calls EtecRedirection), and that returns
# ERROR_RESOURCE_NAME_NOT_FOUND (0x80070716).
#
# Pulling the files directly out of the MSI's embedded cabinet, the way
# scripts/30-mscoree.sh pulls mscoree.dll out of the .NET 4.0 redistributable,
# does work. The MsiAssembly table says these particular files (unlike the
# older EIBA.Interop.* versions also in this MSI, kept for plugins pinned to
# an exact old strong name) are a plain application-local component, not a
# GAC one: there is no SelfReg and no Class table entry for them, so a CLSID
# registration step is not needed, only the files.
. "$(dirname "$0")/lib.sh"

need_cmd wine
need_cmd msiinfo
need_cmd msiextract
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

extract=$ETS5_CACHE/eibasc-files
rm -rf "$extract"
mkdir -p "$extract"
msiextract --directory "$extract" "$msi" >/dev/null 2>&1

src_dir="$extract/Common Files/EIBA sc"
[ -d "$src_dir" ] || die "msiextract did not produce a 'Common Files/EIBA sc' tree from $msi"

mkdir -p "$eiba_dir"
copied=0
for f in "$src_dir"/EIBA.*.dll; do
  [ -f "$f" ] || continue
  cp -f "$f" "$eiba_dir/"
  copied=$((copied + 1))
done
[ "$copied" -gt 0 ] || die "no EIBA.*.dll files were inside $src_dir"
[ -f "$marker" ] || die "EIBA.Interop.EtecDOM.dll still missing from $eiba_dir after extraction"

# Prove the 32-bit CLR can actually load each file, the same way
# scripts/60-verify.sh proves the CLR itself works, instead of trusting a
# copy that merely looks like the right bytes.
csc="$drive/windows/Microsoft.NET/Framework/v4.0.30319/csc.exe"
if [ -f "$csc" ]; then
  cat > "$drive/eibasc-probe.cs" <<'CS'
using System;
using System.Reflection;
class EibascProbe {
    static int Main(string[] args) {
        var ok = true;
        foreach (var path in args) {
            try {
                var asm = Assembly.LoadFrom(path);
                Console.WriteLine("ok   " + asm.FullName);
            } catch (Exception ex) {
                ok = false;
                Console.WriteLine("FAIL " + path + ": " + ex.Message);
            }
        }
        Console.WriteLine(ok ? "eibasc probe OK" : "eibasc probe FAILED");
        return ok ? 0 : 1;
    }
}
CS
  wine "$csc" /nologo /noconfig /platform:x86 /r:mscorlib.dll \
    /out:C:\\eibasc-probe.exe C:\\eibasc-probe.cs >/tmp/ets5-eibasc-csc.txt 2>&1 || true

  args=()
  for f in "$eiba_dir"/EIBA.*.dll; do
    [ -f "$f" ] || continue
    args+=("C:\\Program Files (x86)\\Common Files\\EIBA sc\\$(basename "$f")")
  done
  # pipefail (lib.sh) would otherwise abort right here on eibasc-probe.exe's
  # own exit code before the grep checks below get to classify it.
  wine C:\\eibasc-probe.exe "${args[@]}" 2>/dev/null | tee /tmp/ets5-eibasc-probe.txt || true
  # EIBA.Hawk.Utils.dll is x86-native-flavoured, not MSIL, and its DllMain
  # appears to probe for a Hawk programming interface; it fails to load
  # here (0x8007045A) with no Hawk dongle attached, on real Windows too.
  # That is not what FastDownload.dll and friends need: only the Interop.*
  # assemblies ETS itself asked for in the log have to load clean.
  if grep -Eq 'FAIL .*EIBA\.Interop\.Etec(DOM|Fwk|Hawk)' /tmp/ets5-eibasc-probe.txt; then
    [ -s /tmp/ets5-eibasc-csc.txt ] && cat /tmp/ets5-eibasc-csc.txt >&2
    die "EIBA.Interop.Etec* failed to load under the 32-bit CLR; see /tmp/ets5-eibasc-probe.txt"
  fi
  grep -q '^FAIL' /tmp/ets5-eibasc-probe.txt && \
    printf 'warning: a non-Interop EIBA.*.dll failed to load, see /tmp/ets5-eibasc-probe.txt (likely harmless, see script comments)\n' >&2
else
  printf 'warning: csc.exe is missing, skipping the load probe\n' >&2
fi

printf 'installed %s file(s) into %s\n' "$copied" "$eiba_dir"
