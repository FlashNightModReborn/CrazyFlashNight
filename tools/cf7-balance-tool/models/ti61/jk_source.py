"""Read JK's authored FLA without CS6 or modifying assets.

Local ZIP records are used because this FLA's central directory is not usable by
zipfile. Every member's size and CRC are checked. This is source evidence, not a
Flash execution or proof of collisions in the published SWF.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[4]
FLA = "flashswf/arts/new/武装JK.fla"
GROUND = "LIBRARY/居合/女仆白/Symbol 217.xml"
AIR = "LIBRARY/居合/女仆白/跳跃攻击.xml"
UNIT = "LIBRARY/敌人-武装JK.xml"


def local(tag):
    return tag.rsplit("}", 1)[-1]


def clean(code):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", code, flags=re.S)).strip()


def read_fla(path):
    raw = path.read_bytes()
    offset, members, count = 0, {}, 0
    while raw[offset:offset + 4] == b"PK\x03\x04":
        _, version, flags, method, time, date, crc, size, expanded, nl, xl = struct.unpack_from(
            "<IHHHHHIIIHH", raw, offset)
        if flags & 8 or method not in (0, 8):
            raise ValueError("unsupported FLA ZIP record")
        name = raw[offset + 30:offset + 30 + nl].decode("utf-8")
        start = offset + 30 + nl + xl
        payload = raw[start:start + size]
        offset = start + size
        data = zlib.decompress(payload, -15) if method == 8 else payload
        if len(data) != expanded or zlib.crc32(data) != crc:
            raise ValueError("FLA CRC/size mismatch: " + name)
        if name in members and members[name] != data:
            raise ValueError("conflicting duplicate FLA member: " + name)
        members[name] = data
        count += 1
    if not members:
        raise ValueError("no local ZIP records")
    return members, {"sha256": hashlib.sha256(raw).hexdigest(), "localRecords": count,
                     "uniqueMembers": len(members), "bytes": len(raw)}


def timeline(data):
    root = ET.fromstring(data)
    labels, frames, duration = {}, [], 1
    for layer in root.iter():
        if local(layer.tag) != "DOMLayer":
            continue
        for child in layer:
            if local(child.tag) != "frames":
                continue
            for frame in child:
                if local(frame.tag) != "DOMFrame":
                    continue
                index = int(frame.get("index", 0)) + 1
                span = int(frame.get("duration", 1))
                duration = max(duration, index + span - 1)
                if frame.get("name"):
                    labels[frame.get("name")] = index
                for script_index, script in enumerate(e for e in frame.iter() if local(e.tag) == "script"):
                    code = clean(script.text or "")
                    if code:
                        frames.append({"frame": index, "duration": span,
                                       "layer": layer.get("name", ""),
                                       "id": f"{layer.get('name')}:{index}:{script_index}",
                                       "code": code})
    return {"labels": labels, "frames": frames, "duration": duration}


def collect():
    members, identity = read_fla(ROOT / FLA)
    unit = timeline(members[UNIT])
    initialization = next(r["code"] for r in unit["frames"] if "hp_min =" in r["code"])
    ai = next(r["code"] for r in unit["frames"] if "无敌反制技能库[random" in r["code"])
    source = {"fla": FLA, "identity": identity, "initialization": initialization, "ai": ai,
              "timelines": {"ground": timeline(members[GROUND]), "air": timeline(members[AIR])},
              "members": {"ground": GROUND, "air": AIR, "unit": UNIT},
              "projectiles": {}}
    for name, data in members.items():
        if not name.endswith(".xml") or not any(x in name for x in ("次元斩", "麻醉")):
            continue
        try:
            t = timeline(data)
        except ET.ParseError:
            continue
        source["projectiles"][name] = t
    # A source change must not silently retain the level-100 projection.
    for token in ("hp_min = -1390000", "hp_max = 320000", "空手攻击力_min = -7000",
                  "空手攻击力_max = 2200", "基本防御力_min = 950", "基本防御力_max = 1050"):
        if token not in initialization:
            raise ValueError("JK endpoints changed: " + token)
    return source


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(collect(), ensure_ascii=False, indent=2), encoding="utf-8")
