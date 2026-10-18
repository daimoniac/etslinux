#!/usr/bin/env bash
# Install the "KNX ETS5 Compatibility Components" side package (the ETS3
# plug-in layer): EIBA.Interop.EtecDOM / EtecFwk / EtecHawk, plus
# EIBA.DownloadImageHelper and EIBA.Hawk.Utils. Legacy manufacturer "Baggage"
# plugins such as FastDownload.dll call into these during a device download.
#
# The ETS5 Burn bundle carries this as its own MSI (ProductName "KNX ETS5
# Compatibility Components", ProductCode
# {070C17B5-D0DB-443A-9504-0AF04FE91F1E}). That MSI registers as installed,
# but its files never land on disk: `wine msiexec /i` exits 0 and writes
# nothing. Two further gaps stay even after the files are extracted.
#
# Knx.Ets.Compatibility.Impl.EtecRedirection's static constructor calls
# CreateActCtx on EtecRedirect.dll, manifest resource 1. The DLL only has
# resource 2 (a plain asInvoker manifest). Windows and Wine then look for
# the sidecar EtecRedirect.dll.manifest, which the installer also does not
# ship, and return ERROR_RESOURCE_NAME_NOT_FOUND (0x80070716). The ETS log
# reports that as "Setting process default activation context failed". The
# sidecar has to name the Win32 SxS assemblies EtecFwk, EtecDom, Hawk,
# EtecCtrl and Falcon (version 5.1.0.0); those DLLs are already in the ETS
# directory and their own manifests satisfy the lookup.
#
# Separately, the Baggage plugin's type initializer loads
# EIBA.Interop.EtecDOM 1.0.3135.0 by strong name. Fusion probes the ETS
# application directory, not Common Files\EIBA sc, so the same DLLs also
# have to sit next to ETS5.exe. There is no Class table entry and no GAC
# component for this version; a copy is enough.
. "$(dirname "$0")/lib.sh"

need_cmd wine
need_cmd msiinfo
need_cmd msiextract
refuse_if_ets_running

drive="$WINEPREFIX/drive_c"
installer_dir="$drive/windows/Installer"
[ -d "$installer_dir" ] || die "no Windows Installer cache at $installer_dir; run scripts/50-ets.sh first"

eiba_dir="$drive/Program Files (x86)/Common Files/EIBA sc"
ets_dir=""
for major in 5 6; do
  cand="$drive/Program Files (x86)/ETS$major"
  if [ -f "$cand/EtecRedirect.dll" ]; then
    ets_dir=$cand
    break
  fi
done
[ -n "$ets_dir" ] || die "EtecRedirect.dll not found under Program Files (x86)/ETS5 or ETS6"

marker="$eiba_dir/EIBA.Interop.EtecDOM.dll"
manifest="$ets_dir/EtecRedirect.dll.manifest"
app_copy="$ets_dir/EIBA.Interop.EtecDOM.dll"
if [ -f "$marker" ] && [ -f "$manifest" ] && [ -f "$app_copy" ] \
   && [ "${ETS5_EIBASC_REINSTALL:-0}" != 1 ]; then
  printf 'EIBAsc compatibility layer already present, skipping (set ETS5_EIBASC_REINSTALL=1 to run it again)\n'
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

# Fusion loads EIBA.Interop.EtecDOM by strong name from the ETS application
# directory. Hawk.Utils stays out of that directory: it is native and its
# DllMain fails when no Hawk interface is attached.
for f in "$eiba_dir"/EIBA.Interop.*.dll "$eiba_dir"/EIBA.DownloadImageHelper.dll; do
  [ -f "$f" ] || continue
  cp -f "$f" "$ets_dir/"
done
[ -f "$app_copy" ] || die "failed to copy EIBA.Interop.EtecDOM.dll next to ETS"

# Resource 1 is absent from EtecRedirect.dll. CreateActCtx falls back to
# this filename exactly (resource 1 does not get a ".1" suffix).
cat > "$manifest" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity name="EtecRedirect" version="1.0.0.0" type="win32"/>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity name="EtecFwk" type="win32" version="5.1.0.0"/>
    </dependentAssembly>
  </dependency>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity name="EtecDom" type="win32" version="5.1.0.0"/>
    </dependentAssembly>
  </dependency>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity name="Hawk" type="win32" version="5.1.0.0"/>
    </dependentAssembly>
  </dependency>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity name="EtecCtrl" type="win32" version="5.1.0.0"/>
    </dependentAssembly>
  </dependency>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity name="Falcon" type="win32" version="5.1.0.0"/>
    </dependentAssembly>
  </dependency>
</assembly>
EOF

printf 'installed %s file(s) into %s\n' "$copied" "$eiba_dir"
printf 'and EtecRedirect.dll.manifest plus the Interop assemblies into %s\n' "$ets_dir"
