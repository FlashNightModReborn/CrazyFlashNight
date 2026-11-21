"""据点 M 控制室首波必须能按现有 WaveSpawner 条件自然结束。"""
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
stage = ET.parse(ROOT / "data/stages/基地车库/据点M.xml")
control = stage.find('.//SubStage[@id="4"]')
assert control is not None, "missing control room"
assert control.find("Trigger") is None, "control room unexpectedly gained a trigger that changes the contract"
waves = control.findall("Wave/SubWave")
assert len(waves) == 2, "control room must retain its empty opening and actual combat wave"
opening = waves[0].find("WaveInformation")
requirement = int(opening.findtext("FinishRequirement"))
opening_enemies = opening.findall("../EnemyGroup/Enemy")
assert not opening_enemies, "opening must remain an empty wave"
assert requirement == 0, f"empty opening cannot finish with threshold {requirement}"
assert len(opening_enemies) <= requirement, "empty opening does not satisfy the production finish condition"
assert waves[1].findall("EnemyGroup/Enemy"), "actual combat wave was removed"
print("stage-m-control-room: empty opening satisfies WaveSpawner finish condition; combat wave preserved")
