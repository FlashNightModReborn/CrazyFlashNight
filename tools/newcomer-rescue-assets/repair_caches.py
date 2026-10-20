"""Restore omitted XFL bitmap caches from identical, already cached originals.

Never encodes a cache. CS6 must import any unmatched bitmap into a temporary
XFL before --native-import can consume that document's real bitmap caches.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
import xml.etree.ElementTree as E

from build import ROOT, SOURCE, Q, write_xml


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unpack_native_fla(path: Path):
    path = path.resolve()
    output = path.parent / "native-import"
    output.mkdir(exist_ok=True)
    with zipfile.ZipFile(path) as archive:
        document = archive.read("DOMDocument.xml")
        root = E.fromstring(document)
        if root.get("creatorInfo") != "Adobe Flash Professional CS6":
            raise SystemExit("Expected a real CS6-authored donor FLA")
        items = root.findall(".//" + Q + "DOMBitmapItem")
        if len(items) != 1 or items[0].get("name") != "bitmap45.png":
            raise SystemExit("Unexpected bitmap donor identity")
        item = items[0]
        if (item.get("frameRight"), item.get("frameBottom")) != ("1040", "1780"):
            raise SystemExit("Unexpected native bitmap dimensions")
        for relative, content in [("DOMDocument.xml", document),
                                  ("bin/" + item.get("bitmapDataHRef"), archive.read("bin/" + item.get("bitmapDataHRef"))),
                                  ("LIBRARY/" + item.get("href"), (SOURCE / "ambush/LIBRARY/bitmap45.png").read_bytes())]:
            destination = output / relative
            if not destination.resolve().is_relative_to(output.resolve()):
                raise SystemExit("Unsafe donor path")
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
    return output


def repair(native_import: Path | None = None):
    if native_import:
        native_import = native_import.resolve()
    donors = {}
    for folder in [SOURCE / "clinic", SOURCE / "staging"] + ([native_import] if native_import else []):
        root = E.parse(folder / "DOMDocument.xml").getroot()
        for item in root.findall(".//" + Q + "DOMBitmapItem"):
            original = folder / "LIBRARY" / item.get("href")
            cache = folder / "bin" / item.get("bitmapDataHRef")
            if original.is_file() and cache.is_file():
                donors[sha(original)] = (folder, item, cache)
    receipt_path = ROOT / "tools/newcomer-rescue-assets/source/bitmap-cache-provenance.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8")) if receipt_path.exists() else []
    unresolved = []
    restored = 0
    for name in ["ambush", "return", "raid"]:
        folder = SOURCE / name
        root = E.parse(folder / "DOMDocument.xml").getroot()
        changed = False
        for item in root.findall(".//" + Q + "DOMBitmapItem"):
            cache_name = item.get("bitmapDataHRef")
            destination = folder / "bin" / cache_name
            relative_target = str(destination.relative_to(ROOT))
            prior = next((row for row in receipt if row["target"] == relative_target), None)
            if destination.exists() and prior:
                if sha(destination) != prior["cache_sha256"]:
                    raise SystemExit("Previously restored cache was changed: " + relative_target)
                continue
            original = folder / "LIBRARY" / item.get("href")
            identity = sha(original)
            donor = donors.get(identity)
            if donor is None:
                unresolved.append(str(original.relative_to(ROOT)))
                continue
            donor_folder, donor_item, native_cache = donor
            destination.parent.mkdir(exist_ok=True)
            if destination.exists() and sha(destination) != sha(native_cache):
                raise SystemExit("Refusing to replace an unknown cache: " + relative_target)
            shutil.copy2(native_cache, destination)
            # CS6 stores bitmap bounds in twips. The decompiler's missing-cache
            # declarations used pixels; use the matched native metadata too.
            old_attrs = dict(item.attrib)
            for key, value in donor_item.attrib.items():
                if key not in ("name", "href", "bitmapDataHRef", "itemID", "sourceExternalFilepath"):
                    item.set(key, value)
            receipt.append({"target": str(destination.relative_to(ROOT)),
                            "original_sha256": identity, "cache_sha256": sha(destination),
                            "donor": str(native_cache.relative_to(ROOT)),
                            "old_bounds": [old_attrs.get("frameRight"), old_attrs.get("frameBottom")],
                            "native_bounds": [item.get("frameRight"), item.get("frameBottom")]})
            changed = True
            restored += 1
        if changed:
            write_xml(folder / "DOMDocument.xml", root)
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Restored {restored} native caches by exact original SHA-256; unmatched {len(unresolved)}")
    for filename in unresolved:
        print("CS6 import required:", filename)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    options = parser.add_mutually_exclusive_group()
    options.add_argument("--native-import", type=Path)
    options.add_argument("--native-fla", type=Path)
    args = parser.parse_args()
    repair(unpack_native_fla(args.native_fla) if args.native_fla else args.native_import)
