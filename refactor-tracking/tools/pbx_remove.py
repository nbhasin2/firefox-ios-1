#!/usr/bin/env python3
"""Remove file entries from an Xcode .pbxproj by file name.

Xcode 26 mixes PBXFileSystemSynchronizedRootGroup folders (no entries needed) with
explicit references. Files under an explicit group need four lines dropped:
PBXBuildFile, PBXFileReference, the group's children entry, and the Sources entry.

Usage: pbx_remove.py <project.pbxproj> <FileName.swift> [FileName2.swift ...]
"""
import re
import sys


def remove(path: str, names: list[str]) -> int:
    with open(path) as handle:
        lines = handle.readlines()

    # A file's build-file UUIDs must be collected first so their Sources entries go too.
    ids: set[str] = set()
    for line in lines:
        for name in names:
            if f"/* {name} " in line or f"/* {name} */" in line:
                match = re.match(r"\s*([0-9A-F]{24})\s+/\*", line)
                if match:
                    ids.add(match.group(1))

    kept, dropped = [], 0
    for line in lines:
        hit = any(f"/* {n} " in line or f"/* {n} */" in line for n in names)
        if hit and any(i in line for i in ids):
            dropped += 1
            continue
        kept.append(line)

    with open(path, "w") as handle:
        handle.writelines(kept)
    return dropped


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    count = remove(sys.argv[1], sys.argv[2:])
    print(f"removed {count} pbxproj lines")
