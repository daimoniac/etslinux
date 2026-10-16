#!/usr/bin/env python3
"""Import the .NET 4.0 COM registration ETS needs and the 4.8 installer omits.

Reads the Registry tables of netfx_Core_x86.msi and netfx_Core_x64.msi and
writes a .reg file of keys that are missing from the Wine prefix. x86 rows
land under Wow6432Node. Existing values are left alone; a parent
InprocServer32 that has a 4.0.30319 child but no default value is filled in,
because that missing default is REGDB_E_KEYMISSING.
"""

from __future__ import annotations

import re
import subprocess
import sys
from collections import OrderedDict

SUBS = {
    "FXAssemblyVersion": "4.0.0.0",
    "RTM_ProductVersion": "4.0.30319",
    "VSAssemblyVersion": "10.0.0.0",
    "URTVersion": "v4.0.30319",
    "URTBuildNum": "30319",
    "ProductName": "Microsoft .NET Framework 4 Client Profile",
    "LocProductName": "Microsoft .NET Framework 4 Client Profile",
    "WPFRegistryKey": "Windows Presentation Foundation",
    "WPFStaticVersion": "4.0",
    "ProductCode": "{3C3901C5-3455-3E0A-A214-0B093A5070A6}",
    "SystemFolder_x86": r"C:\windows\syswow64\\",
    "SystemFolder_amd64": r"C:\windows\system32\\",
    "FrameworkVersionFolder_x86": r"C:\windows\Microsoft.NET\Framework\v4.0.30319\\",
    "FrameworkVersionFolder_amd64": r"C:\windows\Microsoft.NET\Framework64\v4.0.30319\\",
    "Framework_x86": r"C:\windows\Microsoft.NET\Framework\\",
    "Framework_amd64": r"C:\windows\Microsoft.NET\Framework64\\",
    "~": "",
}
FILE_TOKENS = {
    "#_003_mscoree_dll_x86": r"C:\windows\syswow64\mscoree.dll",
    "#_003_mscoree_dll_amd64": r"C:\windows\system32\mscoree.dll",
}


def expand(text: str) -> str:
    def repl(match: re.Match[str]) -> str:
        token = match.group(1)
        if token in SUBS:
            return SUBS[token]
        whole = match.group(0)
        if whole in FILE_TOKENS:
            return FILE_TOKENS[whole]
        return whole

    return re.sub(r"\[([^\]]+)\]", repl, text)


def export_registry(msi: str) -> list[list[str]]:
    out = subprocess.check_output(["msiinfo", "export", msi, "Registry"], text=True, errors="replace")
    rows = []
    for i, line in enumerate(out.splitlines()):
        if i < 3:
            continue
        parts = line.split("\t")
        if len(parts) >= 6:
            rows.append(parts)
    return rows


def is_amd64(component: str) -> bool:
    low = component.lower()
    return "amd64" in low or low.endswith("x64")


def place(root: str, key: str, wow: bool) -> str | None:
    if root == "0":
        base = r"Software\Classes\Wow6432Node" if wow else r"Software\Classes"
        return base + "\\" + key
    if root != "2":
        return None
    low = key.lower()
    if low.startswith("software\\classes\\"):
        rest = key.split("\\", 2)[2]
        base = r"Software\Classes\Wow6432Node" if wow else r"Software\Classes"
        return base + "\\" + rest
    if low.startswith("software\\"):
        rest = key.split("\\", 1)[1]
        if wow:
            return "Software\\Wow6432Node\\" + rest
        return "Software\\" + rest
    return None


def parse_system_reg(text: str) -> dict[str, str]:
    blocks = re.split(r"\n(?=\[)", text)
    found: dict[str, str] = {}
    for block in blocks:
        head = block.split("\n", 1)[0]
        if not head.startswith("["):
            continue
        key = head[1:].split("]")[0].replace("\\\\", "\\")
        found[key.lower()] = block
    return found


def rows_to_entries(rows: list[list[str]], wow: bool) -> list[tuple[str, str, str, int | None]]:
    entries = []
    for parts in rows:
        root, key, name, value, comp = parts[1], parts[2], parts[3], parts[4], parts[5]
        if wow is False and not is_amd64(comp):
            continue
        key = expand(key)
        value = expand(value)
        if "[" in key or "[" in value:
            continue
        full = place(root, key, wow)
        if not full:
            continue
        dword = None
        if value.startswith("#%") :
            value = value[2:]
        elif value.startswith("#x") and all(c in "0123456789abcdefABCDEF" for c in value[2:]):
            dword = int(value[2:], 16)
        elif value.startswith("#") and value[1:].isdigit():
            dword = int(value[1:])
        entries.append((full, name, value, dword))
    return entries


def missing_defaults(system: dict[str, str]) -> list[tuple[str, str, str, int | None]]:
    """InprocServer32 parents that only have a versioned child and no default DLL."""
    extra = []
    children = [k for k in system if k.endswith("\\inprocserver32\\4.0.30319")]
    for child in children:
        parent = child.rsplit("\\", 1)[0]
        block = system.get(parent, "")
        if any(line.startswith("@=") for line in block.splitlines()[1:15]):
            continue
        # Preserve the key's original case from the child path's parent segment.
        wow = "wow6432node" in parent
        dll = r"C:\windows\syswow64\mscoree.dll" if wow else r"C:\windows\system32\mscoree.dll"
        # Use the exact casing Wine stored, recovered from the block header of the child.
        header = system[child].split("\n", 1)[0]
        header_key = header[1:].split("]")[0].replace("\\\\", "\\")
        parent_key = header_key.rsplit("\\", 1)[0]
        extra.append((parent_key, "", dll, None))
        extra.append((parent_key, "ThreadingModel", "Both", None))
    return extra


def render(entries: list[tuple[str, str, str, int | None]]) -> str:
    groups: OrderedDict[str, list[tuple[str, str, int | None]]] = OrderedDict()
    for full, name, value, dword in entries:
        groups.setdefault(full, []).append((name, value, dword))
    out = ["Windows Registry Editor Version 5.00\r\n\r\n"]
    for full, vals in groups.items():
        out.append("[HKEY_LOCAL_MACHINE\\" + full + "]\r\n")
        for name, value, dword in vals:
            if dword is not None:
                rendered = f"dword:{dword:08x}"
                out.append(("@=" if name == "" else f'"{name}"=') + rendered + "\r\n")
            else:
                esc = value.replace("\\", "\\\\").replace('"', '\\"')
                if name == "":
                    out.append(f'@="{esc}"\r\n')
                else:
                    nesc = name.replace("\\", "\\\\").replace('"', '\\"')
                    out.append(f'"{nesc}"="{esc}"\r\n')
        out.append("\r\n")
    return "".join(out)


def select_missing(system_text: str, entries: list[tuple[str, str, str, int | None]]) -> list[tuple[str, str, str, int | None]]:
    system = parse_system_reg(system_text)
    chosen = []
    seen = set()
    for full, name, value, dword in entries:
        if full.lower() in system:
            continue
        marker = (full.lower(), name.lower())
        if marker in seen:
            continue
        seen.add(marker)
        chosen.append((full, name, value, dword))
    for item in missing_defaults(system):
        marker = (item[0].lower(), item[1].lower())
        if marker in seen:
            continue
        seen.add(marker)
        chosen.append(item)
    return chosen


def self_test() -> None:
    system = (
        "[Software\\\\Classes\\\\CLSID\\\\{AAA}\\\\InprocServer32\\\\4.0.30319] 1\n"
        '@="4.0.30319"\n'
        "\n"
        "[Software\\\\Classes\\\\Wow6432Node\\\\CLSID\\\\{BBB}\\\\Server] 1\n"
        '@="already.dll"\n'
    )
    rows = [
        ["id", "2", r"SOFTWARE\Classes\CLSID\{AAA}\Server", "", "diasymreader.dll", "sbscmp10_dll_amd64"],
        ["id", "2", r"SOFTWARE\Classes\CLSID\{BBB}\Server", "", "diasymreader.dll", "sbscmp10_dll_x86"],
        ["id", "0", r"CLSID\{CCC}", "", "Example", "some_x86"],
    ]
    entries = rows_to_entries(rows, wow=False) + rows_to_entries(rows, wow=True)
    chosen = select_missing(system, entries)
    keys = {item[0].lower() for item in chosen}
    assert any(k.endswith(r"clsid\{aaa}\server") for k in keys), keys
    assert any("inprocserver32" in k and "4.0.30319" not in k for k in keys), keys
    assert not any(k.endswith(r"clsid\{bbb}\server") for k in keys), keys
    text = render(chosen)
    assert 'Windows Registry Editor Version 5.00' in text
    assert "diasymreader.dll" in text
    assert "mscoree.dll" in text
    print("self-test ok", len(chosen))


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        return
    if len(sys.argv) != 5:
        sys.exit("usage: import_dotnet40_com.py Core_x86.msi Core_x64.msi system.reg out.reg")
    x86, x64, system_path, out_path = sys.argv[1:]
    entries = rows_to_entries(export_registry(x86), wow=True)
    entries += rows_to_entries(export_registry(x64), wow=False)
    system_text = open(system_path, encoding="utf-8", errors="replace").read()
    chosen = select_missing(system_text, entries)
    open(out_path, "wb").write(render(chosen).encode("utf-16"))
    print(f"wrote {out_path} ({len(chosen)} values)")


if __name__ == "__main__":
    main()
