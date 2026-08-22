#!/usr/bin/env python3
"""Add a Swift file to an Xcode .pbxproj under an existing group and Sources phase.

Mirrors an existing sibling file's wiring rather than reconstructing it: the sibling
pins the right group and the right target's Sources phase, which is what makes this
safe to run repeatedly across a large migration.

Usage: pbx_add.py <project.pbxproj> <NewFile.swift> <SiblingFile.swift>
"""
import re
import sys
import hashlib


def uuid_for(seed: str) -> str:
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def add(path: str, new: str, sibling: str) -> None:
    with open(path) as handle:
        text = handle.read()

    if f"/* {new} */" in text:
        print(f"{new} already present")
        return

    ref_match = re.search(
        rf"\t\t([0-9A-F]{{24}}) /\* {re.escape(sibling)} \*/ = \{{isa = PBXFileReference;.*\n", text)
    build_match = re.search(
        rf"\t\t([0-9A-F]{{24}}) /\* {re.escape(sibling)} in Sources \*/ = \{{isa = PBXBuildFile;.*\n", text)
    if not ref_match or not build_match:
        sys.exit(f"could not find sibling {sibling}")

    file_id, build_id = uuid_for(new + "file"), uuid_for(new + "build")

    text = text.replace(
        ref_match.group(0),
        ref_match.group(0)
        + f"\t\t{file_id} /* {new} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {new}; sourceTree = \"<group>\"; }};\n")
    text = text.replace(
        build_match.group(0),
        build_match.group(0)
        + f"\t\t{build_id} /* {new} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {new} */; }};\n")

    child = f"\t\t\t\t{ref_match.group(1)} /* {sibling} */,\n"
    text = text.replace(child, child + f"\t\t\t\t{file_id} /* {new} */,\n", 1)

    src = f"\t\t\t\t{build_match.group(1)} /* {sibling} in Sources */,\n"
    text = text.replace(src, src + f"\t\t\t\t{build_id} /* {new} in Sources */,\n", 1)

    with open(path, "w") as handle:
        handle.write(text)
    print(f"added {new} next to {sibling}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    add(sys.argv[1], sys.argv[2], sys.argv[3])
