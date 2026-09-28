#!/usr/bin/env python3
"""Validate skill-interaction metadata on registered lifecycle bindings."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


VALUES = frozenset(("independent", "fallback", "bound", "managed"))
REGISTRIES = ("data/items/list.xml", "data/items/equipment_mods/list.xml")
MARKER_LINE = re.compile(
    rb"(?m)^[ \t]*<skillInteraction>(?:independent|fallback|bound|managed)"
    rb"</skillInteraction>[ \t]*(?:\r?\n|$)"
)


def without_metadata(raw):
    """Remove only standalone, canonical metadata lines; retain all other bytes."""
    return MARKER_LINE.sub(b"", raw)


def registered_sources(root, errors):
    sources = []
    seen = set()
    for registry in REGISTRIES:
        try:
            entries = ET.parse(root / registry).getroot().findall("items")
        except (OSError, ET.ParseError) as exc:
            errors.append(f"{registry}: {exc}")
            continue
        if not entries:
            errors.append(f"{registry}: no registered items files")
        for entry in entries:
            relative = (entry.text or "").strip()
            full = (root / registry).parent / relative
            try:
                source = full.resolve().relative_to(root).as_posix()
            except ValueError:
                errors.append(f"{registry}: source escapes repository: {relative}")
                continue
            if not relative:
                errors.append(f"{registry}: empty items entry")
            elif source in seen:
                errors.append(f"{registry}: duplicate registered source: {source}")
            else:
                seen.add(source)
                sources.append(source)
    return sources


def validate(root):
    root = Path(root).resolve()
    errors = []
    sources = registered_sources(root, errors)
    bindings = []
    definitions = Counter()
    for source in sources:
        try:
            document = ET.parse(root / source).getroot()
        except (OSError, ET.ParseError) as exc:
            errors.append(f"{source}: {exc}")
            continue
        recognized = set()
        for entry in document:
            if entry.tag not in ("item", "mod"):
                continue
            definitions[entry.tag] += 1
            name = entry.findtext("name") or "<unnamed>"

            def walk(element, parents):
                for child in element:
                    if child.tag != "lifecycle":
                        walk(child, parents + [child.tag])
                        continue
                    scope = "/".join(parents) or "root"
                    if entry.tag == "mod" and scope != "root":
                        errors.append(f"{source}: {name}/{scope}: only top-level mod.lifecycle is supported")
                    for attr in child:
                        # Match the AS2 loader's attr-key selection, including tier overrides.
                        if "attr" not in attr.tag:
                            if entry.tag == "mod":
                                errors.append(f"{source}: {name}: unsupported mod lifecycle child {attr.tag}")
                            continue
                        context = f"{source}: {name}/{scope}/lifecycle/{attr.tag}"
                        markers = attr.findall("skillInteraction")
                        recognized.update(markers)
                        value = (markers[0].text or "").strip() if markers else None
                        if len(markers) != 1:
                            errors.append(f"{context}: expected one skillInteraction, found {len(markers)}")
                        elif (value not in VALUES or list(markers[0]) or markers[0].attrib
                              or markers[0].text != value):
                            errors.append(f"{context}: invalid skillInteraction {value!r}")
                        if value == "independent" and attr.find("skill") is not None:
                            errors.append(f"{context}: independent cannot declare attr.skill")
                        if value == "fallback" and attr.find("skill") is None:
                            errors.append(f"{context}: fallback requires attr.skill")
                        if entry.tag == "mod":
                            if value != "independent" or attr.find("skill") is not None or attr.find("setGate") is not None:
                                errors.append(f"{context}: mod lifecycle must be independent without skill/setGate")
                            routines = [(tag, attr.findall(tag)) for tag in ("init", "cycle")]
                            if not any(nodes for _, nodes in routines):
                                errors.append(f"{context}: mod lifecycle needs init or cycle")
                            for tag, nodes in routines:
                                if len(nodes) > 1 or (nodes and not (nodes[0].findtext(tag + "Routines") or "").strip()):
                                    errors.append(f"{context}: invalid {tag} routine declaration")
                        bindings.append({
                            "source": source, "kind": entry.tag, "item": name,
                            "scope": scope, "attr": attr.tag, "skillInteraction": value,
                            "routines": [node.text for node in attr.iter()
                                         if node.tag.endswith("Routines") and node.text],
                        })

            walk(entry, [])
        for marker in document.iter("skillInteraction"):
            if marker not in recognized:
                errors.append(f"{source}: skillInteraction must be a direct lifecycle attr child")
    return {
        "ok": not errors, "errors": errors, "registeredFiles": sources,
        "definitionCounts": dict(definitions), "bindingCount": len(bindings),
        "counts": dict(sorted(Counter(row["skillInteraction"] or "missing" for row in bindings).items())),
        "bindings": bindings,
    }


def verify_baseline(root, baseline, sources):
    """Ensure registry and registered XML changes contain metadata lines only."""
    errors = []
    try:
        commit = subprocess.check_output(
            ["git", "rev-parse", "--verify", "--end-of-options", f"{baseline}^{{commit}}"],
            cwd=root, stderr=subprocess.PIPE,
        ).decode("ascii").strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        return [f"cannot resolve baseline {baseline!r}: {exc}"]
    paths = sorted(set(REGISTRIES).union(sources))
    try:
        archive = subprocess.check_output(
            ["git", "cat-file", "--batch"], cwd=root, stderr=subprocess.PIPE,
            input="".join(f"{commit}:{source}\n" for source in paths).encode("utf-8"),
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        return [f"cannot read baseline {commit}: {exc}"]
    offset = 0
    for source in paths:
        end = archive.find(b"\n", offset)
        if end < 0:
            errors.append(f"{source}: truncated git cat-file response")
            break
        header = archive[offset:end]
        offset = end + 1
        if header.endswith(b" missing"):
            errors.append(f"{source}: absent from baseline {commit}")
            continue
        fields = header.split()
        if len(fields) != 3 or fields[1] != b"blob" or not fields[2].isdigit():
            errors.append(f"{source}: invalid git cat-file header")
            break
        size = int(fields[2])
        before = archive[offset:offset + size]
        if len(before) != size or archive[offset + size:offset + size + 1] != b"\n":
            errors.append(f"{source}: truncated git cat-file blob")
            break
        offset += size + 1
        try:
            after = (root / source).read_bytes()
        except OSError as exc:
            errors.append(f"{source}: cannot compare baseline: {exc}")
            continue
        if without_metadata(before) != without_metadata(after):
            errors.append(f"{source}: non-metadata bytes differ from {commit}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--verify-against", metavar="COMMIT", help="also prove XML changes are metadata-only")
    parser.add_argument("--json", action="store_true", help="write full machine-readable inventory to stdout")
    args = parser.parse_args()
    root = args.root.resolve()
    result = validate(root)
    if args.verify_against:
        result["errors"].extend(verify_baseline(root, args.verify_against, result["registeredFiles"]))
        result["baseline"] = args.verify_against
    result["ok"] = not result["errors"]
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"{'PASS' if result['ok'] else 'FAIL'} lifecycle skill metadata: "
              f"{result['bindingCount']} bindings, {result['counts']}")
        for error in result["errors"]:
            print(error, file=sys.stderr)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
