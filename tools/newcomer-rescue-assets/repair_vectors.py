"""Isolate native XFL drawing palettes without changing their geometry.

CS6 merges sibling DOMShape elements in one drawing layer. The source packages
gave each shape its own palette starting at index 1, so the final shape's palette
recoloured earlier geometry. A DOMGroup per shape preserves the SVG paint order
and makes each drawing's palette private. Real CS6 color-probe confirmed this.
"""
from pathlib import Path
import argparse
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "flashswf/backgrounds/70002"
Q = "{http://ns.adobe.com/xfl/2008/}"
E.register_namespace("", Q[1:-1])


def repair(check=False):
    changed = shapes = 0
    for path in sorted(SOURCE.rglob("*.xml")):
        if path.name == "PublishSettings.xml":
            continue
        tree = E.parse(path)
        count = 0
        for parent in list(tree.getroot().iter()):
            if parent.tag not in (Q + "elements", Q + "members"):
                continue
            drawings = parent.findall(Q + "DOMShape")
            if len(drawings) < 2:
                continue
            count += len(drawings)
            for shape in drawings:
                index = list(parent).index(shape)
                parent.remove(shape)
                group = E.Element(Q + "DOMGroup")
                E.SubElement(group, Q + "members").append(shape)
                parent.insert(index, group)
        if count:
            if check:
                raise SystemExit("Unisolated sibling drawing palettes: " + str(path))
            tree.write(path, encoding="utf-8", xml_declaration=True)
            changed += 1
            shapes += count
    print(f"Native drawing palettes: {changed} files repaired, {shapes} shapes isolated" if not check else "Native drawing palettes are isolated")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    repair(parser.parse_args().check)
