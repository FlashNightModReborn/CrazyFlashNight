"""据点 M 控制室必须保留互动开闸，并在闸门动画中立即移除碰撞。"""
from pathlib import Path
from xml.etree import ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
stage = ET.parse(ROOT / "data/stages/基地车库/据点M.xml")
control = stage.find('.//SubStage[@id="4"]')
assert control is not None, "missing control room"
trigger = control.find("Trigger")
assert trigger is not None and trigger.get("id") == "0" and trigger.findtext("Xmin") == "600", \
    "control room must expose the gate interaction trigger at x=600"
event = control.find("./Event[EventName='TriggerPressed']")
assert event is not None and event.findtext("Parameter") == "0" \
    and event.findtext("StageProgress") == "ForceFinishWave", \
    "gate interaction must publish ForceFinishWave"
waves = control.findall("Wave/SubWave")
assert len(waves) == 2, "control room must retain its interaction gate and actual combat wave"
opening = waves[0].find("WaveInformation")
assert opening.findtext("FinishRequirement") == "-1", "first wave must wait for interaction"
assert not opening.findall("../EnemyGroup/Enemy"), "interaction gate must remain an empty first wave"
assert waves[1].findall("EnemyGroup/Enemy"), "actual combat wave was removed"
with zipfile.ZipFile(ROOT / "flashswf/movies/竖直闸门.fla") as archive:
    document = archive.read("DOMDocument.xml").decode("utf-8")
assert 'subscribeOnce("WaveFinished"' in document, "gate animation must start from the actual wave event"
immediate = "_root.移除影片剪辑外框地图碰撞箱(this, true);"
assert document.count(immediate) == 1, "gate must remove its collision in the same frame"
print("stage-m-control-room: interaction-gated wave and same-frame gate collision removal verified")
