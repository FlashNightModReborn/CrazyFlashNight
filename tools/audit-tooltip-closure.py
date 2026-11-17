#!/usr/bin/env python3
"""Issue #262 source closure gate. This is not an AVM1/CS6 compilation result."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "org.flashNight.gesh.tooltip."
LEAVES = {
    "TooltipDataSelector", "TooltipConstants", "ItemUseTypes",
    "NativeTooltipBridge", "TooltipInputProjection",
}
LEXICAL_NON_CODE = re.compile(
    r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*[\s\S]*?\*/|//[^\r\n]*'
)


def code_only(text: str) -> str:
    # Preserve line offsets. The source gate inspects identifiers, not comment/history hits.
    return LEXICAL_NON_CODE.sub(lambda m: re.sub(r"[^\r\n]", " ", m.group()), text)


def audit() -> dict:
    baseline = json.loads((ROOT / "tools/tooltip-oracle/baseline.json").read_text("utf-8"))
    manifest = json.loads((ROOT / "tools/asloader-modules.json").read_text("utf-8"))
    errors = []
    archived_names = set()
    old_bytes = 0
    for original, entry in baseline["files"].items():
        raw = (ROOT / entry["path"]).read_bytes()
        if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            errors.append("Changed oracle snapshot: " + entry["path"])
        if original.endswith(".as"):
            archived_names.add(Path(original).stem)
            old_bytes += len(raw)

    before = {name: baseline["tooltipClasses"][name] for name in ("resident", "shared", "boot")}
    after = {name: [c for c in manifest[name]["classes"] if c.startswith(PREFIX)] for name in before}
    expected = {PREFIX + name for name in LEAVES}
    if after["resident"] or after["shared"] or set(after["boot"]) != expected:
        errors.append("Tooltip class ownership must be the five reviewed boot leaves")
    owned = set()
    for module in before:
        for name in manifest[module]["classes"]:
            if name in owned:
                errors.append("Duplicate module owner: " + name)
            owned.add(name)
            if not (ROOT / "scripts/类定义" / (name.replace(".", "/") + ".as")).is_file():
                errors.append("Missing owned source: " + name)

    production = ROOT / "scripts/类定义/org/flashNight/gesh/tooltip"
    actual = {p.stem for p in production.rglob("*.as")}
    if actual != LEAVES:
        errors.append("Unexpected production Tooltip sources: " + repr(sorted(actual ^ LEAVES)))
    removed_identifiers = archived_names - LEAVES
    # Two still-live tests were moved to their owning domains; they are not content rules.
    removed_identifiers -= {"NativeTooltipBridgeTest", "SynthesisIndexTest"}
    pattern = re.compile(r"\b(?:" + "|".join(map(re.escape, sorted(removed_identifiers))) + r")\b")
    scanned = 0
    for path in sorted((ROOT / "scripts").rglob("*")):
        if not path.is_file() or not (path.suffix == ".as" or path.name.endswith(".as.template")):
            continue
        scanned += 1
        raw = path.read_bytes()
        text = code_only(raw.decode("utf-8-sig"))
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            errors.append(f"Retired class reference: {path.relative_to(ROOT)}:{line}: {match.group()}")
    for path in production.rglob("*.as"):
        if not path.read_bytes().startswith(b"\xef\xbb\xbf"):
            errors.append("AS2 source lacks BOM: " + path.relative_to(ROOT).as_posix())

    # Focused runners fingerprint AdditionalAsRelativePaths before launching CS6. A removed
    # builder in that list would fail on Windows even if the live AS2 closure is clean.
    retired_paths = [name for name in baseline["files"]
                     if name.endswith(".as") and not (ROOT / name).is_file()]
    runners_scanned = 0
    for path in sorted((ROOT / "scripts").rglob("*.ps1")):
        runners_scanned += 1
        text = path.read_text("utf-8-sig").replace("\\", "/")
        for retired_path in retired_paths:
            if retired_path in text:
                errors.append("Retired focused-runner source: " + path.relative_to(ROOT).as_posix()
                              + ": " + retired_path)

    # The remaining constants are the old EquipmentStatProjector vocabulary, byte-for-byte.
    old = (ROOT / "tools/tooltip-oracle/as2/org/flashNight/gesh/tooltip/TooltipConstants.as").read_text("utf-8-sig")
    new = (production / "TooltipConstants.as").read_text("utf-8-sig")
    for name in ("PROPERTY_DICT", "PROPERTY_PRIORITIES"):
        pattern_dict = re.compile(r"public static var " + name + r"[\s\S]*?\n  };")
        old_match, new_match = pattern_dict.search(old), pattern_dict.search(new)
        if not old_match or not new_match or old_match.group() != new_match.group():
            errors.append("Changed EquipmentStatProjector vocabulary: " + name)
    constant_re = re.compile(r"public static var (\w+):String\s*=\s*([^;]+);")
    old_constants = dict(constant_re.findall(old))
    for name, value in constant_re.findall(new):
        if old_constants.get(name) != value:
            errors.append("Changed EquipmentStatProjector constant: " + name)

    generated_settings = [ROOT / manifest[name]["xfl"] for name in before]
    for xfl in generated_settings:
        settings = xfl.parent / "PublishSettings.xml"
        if "tooltip-oracle" in settings.read_text("utf-8-sig"):
            errors.append("Oracle archive leaked into production classpath: " + str(settings))
    new_bytes = sum(p.stat().st_size for p in production.rglob("*.as"))
    removed = sorted(set(before["boot"]) - set(after["boot"]))
    added = sorted(set(after["boot"]) - set(before["boot"]))
    return {
        "schema": "cf7.tooltip-source-closure.v1",
        "status": "PASS" if not errors else "FAIL",
        "baselineCommit": baseline["sourceCommit"],
        "evidence": "source/static-only; AVM1, DoInitAction bytes and CS6 memory/time not measured",
        "moduleClassCountsBefore": baseline["moduleClasses"],
        "moduleClassCountsAfter": {name: len(manifest[name]["classes"]) for name in before},
        "tooltipCountsBefore": {name: len(before[name]) for name in before},
        "tooltipCountsAfter": {name: len(after[name]) for name in before},
        "removedRegisteredClasses": removed,
        "retainedRegisteredClasses": sorted(set(before["boot"]) & set(after["boot"])),
        "addedRegisteredClasses": added,
        "registeredNetReduction": len(removed) - len(added),
        "archivedFiles": len(baseline["files"]),
        "sourceFilesScanned": scanned,
        "powerShellRunnersScanned": runners_scanned,
        "as2SourceBytesBefore": old_bytes,
        "as2SourceBytesAfter": new_bytes,
        "sourceBytesCaveat": "Includes retired tests/renderers; not SWF bytes or compile-memory savings",
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = audit()
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{result['status']}: tooltip boot 40 -> {result['tooltipCountsAfter']['boot']}; "
          f"removed {len(result['removedRegisteredClasses'])}, added {len(result['addedRegisteredClasses'])}; "
          f"scanned {result['sourceFilesScanned']} AS2 sources/templates; static only")
    for error in result["errors"]:
        print(error, file=sys.stderr)
    return int(bool(result["errors"]))


if __name__ == "__main__":
    raise SystemExit(main())
