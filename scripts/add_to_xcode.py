#!/usr/bin/env python3
"""Register Swift files in BarrioMesh.xcodeproj (the project lists files explicitly).

Usage: scripts/add_to_xcode.py core|agent|views|design|networking File.swift [...]
"""
import re
import sys
from pathlib import Path

GROUPS = {
    "core": "400000000000000000000006",
    "views": "400000000000000000000004",
    "networking": "400000000000000000000003",
    "agent": "400000000000000000000008",
    "design": "400000000000000000000009",
}

project = Path(__file__).resolve().parent.parent / "BarrioMesh.xcodeproj" / "project.pbxproj"
text = project.read_text()
group = GROUPS[sys.argv[1]]

for name in sys.argv[2:]:
    if f"path = {name};" in text:
        print(f"skip {name} (already registered)")
        continue
    used = [int(m, 16) for m in re.findall(r"\t\t2([0-9A-F]{23}) /\*", text)]
    n = max(used) + 1
    build_id, file_id = f"1{n:023X}", f"2{n:023X}"
    text = text.replace(
        "/* End PBXBuildFile section */",
        f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};\n/* End PBXBuildFile section */",
    )
    text = text.replace(
        "/* End PBXFileReference section */",
        f'\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n/* End PBXFileReference section */',
    )
    sources = text.index("isa = PBXSourcesBuildPhase;")
    files = text.index("files = (\n", sources) + len("files = (\n")
    text = text[:files] + f"\t\t\t\t{build_id} /* {name} in Sources */,\n" + text[files:]
    definition = re.search(rf"\n\t\t{group} /\* [^*]+ \*/ = \{{", text).start()
    children = text.index("children = (\n", definition) + len("children = (\n")
    text = text[:children] + f"\t\t\t\t{file_id} /* {name} */,\n" + text[children:]
    print(f"added {name}")

project.write_text(text)
