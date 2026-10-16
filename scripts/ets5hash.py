#!/usr/bin/env python3
"""Recompute ETS5 ProjectStore .ets5hash companions.

Each hashed file is SHA-1 of its bytes, then every byte is increased by 41
(mod 256), then XORed with the project mask: the mask's high byte on even
indexes and its low byte on odd indexes. The mask is the sum of the project
GUID's little-endian bytes and the UTF-8 bytes of the project id, mod 65536.
Both values are in the plaintext P file (Proj/@Id and ProjInfo/@Guid).

This does not touch the license stick. The .store file is a different check
and is left alone.

Usage:
  scripts/ets5hash.py check STORE_DIR
  scripts/ets5hash.py write STORE_DIR [FILE ...]
  scripts/ets5hash.py --self-test
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import sys
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path


def project_mask(project_guid: str, project_id: str) -> int:
    guid_sum = sum(uuid.UUID(project_guid).bytes_le)
    id_sum = sum(project_id.encode("utf-8"))
    return (guid_sum + id_sum) % 65536


def ets5hash(file_bytes: bytes, mask: int) -> bytes:
    digest = bytearray(hashlib.sha1(file_bytes).digest())
    hi = (mask >> 8) & 0xFF
    lo = mask & 0xFF
    for i, value in enumerate(digest):
        mixed = (value + 41) % 256
        digest[i] = mixed ^ (hi if i % 2 == 0 else lo)
    return bytes(digest)


def ets5hash_text(file_bytes: bytes, mask: int) -> str:
    return base64.b64encode(ets5hash(file_bytes, mask)).decode("ascii")


def read_project(store: Path) -> tuple[str, str]:
    root = ET.fromstring((store / "P").read_text(encoding="utf-8-sig"))
    info = root.find("ProjInfo")
    if info is None or "Guid" not in info.attrib or "Id" not in root.attrib:
        raise SystemExit(f"{store / 'P'} has no Proj/@Id or ProjInfo/@Guid")
    return root.attrib["Id"], info.attrib["Guid"]


def hashed_files(store: Path, names: list[str]) -> list[Path]:
    if names:
        files = []
        for name in names:
            path = Path(name)
            if not path.is_absolute():
                path = store / path
            files.append(path)
        return files
    return sorted(
        path
        for path in store.iterdir()
        if path.is_file() and (store / f"{path.name}.ets5hash").is_file()
    )


def cmd_check(store: Path, names: list[str]) -> int:
    project_id, project_guid = read_project(store)
    mask = project_mask(project_guid, project_id)
    failed = 0
    for path in hashed_files(store, names):
        companion = Path(f"{path}.ets5hash")
        expected = companion.read_text(encoding="ascii").strip()
        got = ets5hash_text(path.read_bytes(), mask)
        if got == expected:
            print(f"ok   {path.name}")
        else:
            failed += 1
            print(f"fail {path.name}")
            print(f"     stored   {expected}")
            print(f"     computed {got}")
    return 1 if failed else 0


def cmd_write(store: Path, names: list[str]) -> int:
    project_id, project_guid = read_project(store)
    mask = project_mask(project_guid, project_id)
    for path in hashed_files(store, names):
        text = ets5hash_text(path.read_bytes(), mask)
        Path(f"{path}.ets5hash").write_text(text, encoding="ascii")
        print(f"wrote {path.name}.ets5hash")
    return 0


def self_test() -> int:
    mask = project_mask("00000000-0000-0000-0000-000000000001", "P-0001")
    got = ets5hash_text(b"ets5hash", mask)
    if mask != 319 or got != "TnwiqUYt9qo22B/u9TAwSUUcPTM=":
        print(f"self-test failed: mask={mask} hash={got}", file=sys.stderr)
        return 1
    print("ets5hash self-test OK")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("command", nargs="?", choices=("check", "write"))
    parser.add_argument("store", nargs="?", type=Path)
    parser.add_argument("files", nargs="*")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.command is None or args.store is None:
        parser.error("check or write requires STORE_DIR")
    store = args.store
    if not (store / "P").is_file():
        raise SystemExit(f"no P file in {store}")
    if args.command == "check":
        return cmd_check(store, args.files)
    return cmd_write(store, args.files)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
