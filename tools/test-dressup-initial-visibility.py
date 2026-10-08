"""Guard static light baking without treating arbitrary AS2 as declarative data."""
import importlib.util
import sys
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET

spec = importlib.util.spec_from_file_location("dressup_bake", Path(__file__).with_name("bake-dressup-offline.py"))
bake = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = bake
spec.loader.exec_module(bake)


def action(script, **extra):
    return {"script": script, "characterId": 17, "depth": 3, "frame": 1, **extra}


off = action("onClipEvent(load) { // External lifecycle owns visibility.\n this._visible = false; }")
result = bake.initially_hidden_clip_actions({"clipActions": [off]})
assert result["neutralRemovals"] == [{"characterId": 17, "depth": 3, "frame": 1}]
assert bake.initially_hidden_clip_actions({"clipActions": [action("onClipEvent(load){this._visible=0}")]})
for script in [
    "onClipEvent(load){if(_parent.active){this._visible=false;}}",
    "onClipEvent(enterFrame){this._visible=false;}",
    "onClipEvent(load){this._visible=false;this._visible=true;}",
    'onClipEvent(load){trace("this._visible=false;");}',
]:
    assert bake.initially_hidden_clip_actions({"clipActions": [action(script)]}) is None
assert bake.initially_hidden_clip_actions({"clipActions": [dict(off, frame=2)]}) is None
assert bake.initially_hidden_clip_actions({"clipActions": [off], "frameScripts": {1: ["effect._visible=true;"]}}) is None
assert bake.initially_hidden_clip_actions({"clipActions": []}) is None

# Only the exact first-frame placement is removed from the temporary render
# input. Other depths and a later placement of the same symbol must survive.
raw = b'''<swf><tags><item type="DefineSpriteTag" spriteId="12"><subTags>
<item type="PlaceObject2Tag" characterId="17" depth="3"/>
<item type="PlaceObject2Tag" characterId="17" depth="4"/>
<item type="ShowFrameTag"/>
<item type="PlaceObject2Tag" characterId="17" depth="3"/>
</subTags></item></tags></swf>'''
with tempfile.TemporaryDirectory() as temp:
    source, output = Path(temp)/"source.xml", Path(temp)/"render.xml"
    source.write_bytes(raw)
    assert bake.remove_frame1_place_objects(source, output, {(12, 17, 3)}) == 1
    assert source.read_bytes() == raw
    placements = ET.parse(output).findall('.//item[@type="PlaceObject2Tag"]')
    assert [p.get("depth") for p in placements] == ["4", "3"]
print("PASS: load-hidden effect preview, ambiguous-script refusal, exact placement isolation")
