"""Cross-check stage information rewards. A reviewed exception must match the exact values."""
from pathlib import Path
import sys
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
# Keys are (stage path, item name, quantity maximum, holding cap, unit price).
# Values explain why this stage intentionally requests excess information.
EXCEPTIONS = {}
KEY_STAGES = {"data/stages/诺亚前线基地深处/决战之地.xml",
              "data/stages/诺亚前线基地深处第二层/终结者决战之地.xml"}


def main():
    catalog = {}
    for item in ET.parse(ROOT / "data/items/收集品_情报.xml").iterfind(".//item"):
        if item.findtext("use") != "情报":
            continue
        name = item.findtext("name")
        if not name or name in catalog:
            raise ValueError(f"Missing or duplicate information name: {name}")
        catalog[name] = int(item.findtext("maxvalue")), int(item.findtext("price"))
    files = sorted((ROOT / "data/stages").rglob("*.xml"))
    total = matched = 0
    keys = {}
    seen = set()
    errors = []
    for path in files:
        stage = path.relative_to(ROOT).as_posix()
        for row in ET.parse(path).iterfind(".//Rewards/Reward"):
            total += 1
            name = row.findtext("Name")
            if name not in catalog:
                continue
            matched += 1
            quantity = int(row.findtext("QuantityMax"))
            cap, price = catalog[name]
            if name == "方舟秘钥" and stage in KEY_STAGES:
                keys.setdefault(stage, []).append((quantity, cap))
            if quantity <= cap:
                continue
            key = (stage, name, quantity, cap, price)
            seen.add(key)
            reason = EXCEPTIONS.get(key)
            print(f"{stage} | {name} | 数量 {quantity} | 上限 {cap} | 差值 {quantity-cap} | 单价 {price} | 情报 | {reason or '待审'}")
            if not reason:
                errors.append(f"Unreviewed excess: {key}")
    if keys != {stage: [(1, 1)] for stage in KEY_STAGES}:
        errors.append("Both Ark Key rewards must occur once with quantity and cap 1.")
    if set(EXCEPTIONS) - seen:
        errors.append("Unused or stale exception.")
    print(f"{len(files)} XML, {len(catalog)} information items, {total} rewards, {matched} information rewards, {len(seen)} excess definitions")
    for error in errors:
        print(error, file=sys.stderr)
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
