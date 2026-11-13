"""Check authored boss/protection rosters per substage, wave and difficulty."""
import json
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

STAGES = Path(__file__).resolve().parents[1] / "data" / "stages"
DIFFICULTIES = ("简单", "冒险", "修罗", "地狱")
CAPACITY = 8


def rows(value):
    if isinstance(value, list):
        return value
    return [] if value is None else [value]


def xml_enemies(nodes):
    for node in nodes:
        entry = {child.tag: child.text for child in node}
        entry["Parameters"] = {child.tag: child.text for child in node.findall("Parameters/*")}
        yield entry


def groups(path):
    # Only production declarations opt in. Ordinary combat focus is chosen live and
    # cannot create a ninth resident. Scripts with dynamic spawns use the CS6 suite.
    if path.suffix == ".xml":
        root = ET.parse(path).getroot()
        for index, stage in enumerate(root.findall("SubStage")):
            name = stage.get("id", str(index))
            for ordinal, wave in enumerate(stage.findall("./Wave/SubWave"), 1):
                yield name, f"第 {ordinal} 波", xml_enemies(wave.findall("EnemyGroup/Enemy"))
            for ordinal, event in enumerate(stage.findall("Event"), 1):
                yield name, f"事件 {ordinal}", xml_enemies(event.findall("Enemy"))
    else:
        chapter = json.loads(path.read_text("utf-8-sig"))
        for area in chapter.get("maps", []):
            stage = area.get("stage") or {}
            for ordinal, wave in enumerate(rows((stage.get("Wave") or {}).get("SubWave")), 1):
                enemies = [enemy for group in rows(wave.get("EnemyGroup")) for enemy in rows(group.get("Enemy"))]
                yield area["id"], f"第 {ordinal} 波", enemies


def difficulty_index(value):
    # WaveSpawner uses _root.计算难度等级, whose fallback for an unknown label is 简单.
    return DIFFICULTIES.index(value) if value in DIFFICULTIES else 0


def capacity_rows(path):
    for area, wave, group in groups(path):
        enemies = [unit for unit in group if (unit.get("Parameters") or {}).get("focusHudRole") in ("boss", "protect")]
        if not enemies:
            continue
        for index, difficulty in enumerate(DIFFICULTIES):
            labels = []
            count = 0
            for unit in enemies:
                minimum, maximum = unit.get("DifficultyMin"), unit.get("DifficultyMax")
                if (minimum and index < difficulty_index(minimum)) or (maximum and index > difficulty_index(maximum)):
                    continue
                quantity = int(unit.get("Quantity", 1))
                if quantity < 1:
                    continue
                label = unit["Parameters"].get("focusHudLabel") or unit.get("InstanceName") or unit.get("Type")
                labels.append(f"{label} ×{quantity}" if quantity > 1 else str(label))
                count += quantity
            if count:
                yield area, wave, difficulty, count, labels


def main(arguments):
    if arguments:
        paths = [Path(arg) for arg in arguments]
    else:
        paths = sorted(STAGES.rglob("*.xml")) + sorted(
            path for path in (STAGES / "books").glob("*.json") if not path.name.endswith(".runtime.json"))
    largest = 0
    over = []
    rosters = 0
    for path in paths:
        if b"focusHudRole" not in path.read_bytes():
            continue
        for area, wave, difficulty, count, labels in capacity_rows(path):
            rosters += 1
            largest = max(largest, count)
            if count > CAPACITY:
                over.append(f"{path} · 子图 {area} · {wave} · {difficulty} · {count}/{CAPACITY} · " + "、".join(labels))
    for message in over:
        print(f"[需核实同时在场] {message}")
    print(f"目标血条名册：{rosters} 组同难度、同波次或同事件的声明，最多 {largest} 个，超限 {len(over)} 组。")
    # Spawn intervals and scripted retirement can separate units within a single wave.
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
