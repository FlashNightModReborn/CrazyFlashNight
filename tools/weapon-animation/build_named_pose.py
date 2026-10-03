#!/usr/bin/env python3
"""M7具名姿态：导入最小原生闭包并派生按需读取的运行时JSON。"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "tools/weapon-animation/profiles/pilebunker-m7.json"
NS_URI = "http://ns.adobe.com/xfl/2008/"
NS = {"x": NS_URI}
ET.register_namespace("", NS_URI)
Q = lambda name: "{" + NS_URI + "}" + name


def read_inputs():
    spec = json.loads(PROFILE.read_text(encoding="utf-8"))
    source = ROOT / spec["poseSource"]
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != spec["sourcePoseSHA256"]:
        raise ValueError("姿态源指纹变化，必须显式更新版本与来源")
    data = json.loads(raw.decode("utf-8-sig"))
    if data["schema"] != "ashmead.named-pose-index.v1":
        raise ValueError("不支持的姿态格式")
    if len(data["targets"]) != 93 or sum(c["frameCount"] for c in data["clips"]) != 589:
        raise ValueError("M7动作/实例合同变化")
    for matrix in data["matrices"]:
        if len(matrix) != 6 or not all(math.isfinite(n) for n in matrix):
            raise ValueError("矩阵无效")
    for state in data["states"]:
        if not (-1 <= state[0] < len(data["parts"]) and 0 <= state[1] < len(data["matrices"]) and 0 <= state[2] <= 1):
            raise ValueError("状态索引无效")
    for pose in data["poses"]:
        if len(pose) != len(data["targets"]) or any(not 0 <= n < len(data["states"]) for n in pose):
            raise ValueError("完整姿态索引无效")
        for target, state_id in zip(data["targets"], pose):
            part = data["states"][state_id][0]
            if part < 0 or target["kind"] == "anchor":
                continue
            allowed = {target["part"], *target["variants"]}
            if data["parts"][part] not in allowed:
                raise ValueError("常驻实例母件不匹配：" + target["name"])
    return spec, data


def validate_config(spec, data):
    for key, minimum in (("chargeCountMax", 1), ("prepareTicks", 2), ("transformTicks", 2)):
        value = spec.get(key)
        if type(value) is not int or not minimum <= value <= 65533:
            raise ValueError(f"{key}必须是{minimum}至65533的整数")
    entry = spec.get("normalFireEntry0")
    normal = next(c for c in data["clips"] if c["id"] == "N0")
    if type(entry) is not int or not 0 <= entry < normal["frameCount"] - 1:
        raise ValueError("normalFireEntry0必须是保留至少两帧的有效整数索引")
    strike_frames = spec.get("strikeFrames0")
    if not isinstance(strike_frames, dict) or set(strike_frames) != {"N0", "N1", "S1"}:
        raise ValueError("strikeFrames0必须明确三路完整出桩帧")
    tip_index = next(i for i, target in enumerate(data["targets"]) if target["name"] == "anchor_tip")
    for branch, frame in strike_frames.items():
        clip = next(c for c in data["clips"] if c["id"] == branch)
        if type(frame) is not int or not 0 <= frame < clip["frameCount"]:
            raise ValueError("完整出桩帧必须是该动作内的整数索引")
        tips = [data["matrices"][data["states"][data["poses"][pose][tip_index]][1]][4] for pose in clip["poseIds"]]
        if tips[frame] != max(tips):
            raise ValueError("桩击判定必须取完整出桩峰值，不能取尚未伸足的首帧")
    for key in ("bladeRotation", "bladeX", "bladeY", "bladeFaceHalfHeight"):
        value = spec.get(key)
        if type(value) not in (int, float) or not math.isfinite(value):
            raise ValueError(f"{key}必须是有限数值")
    if spec["bladeFaceHalfHeight"] <= 0:
        raise ValueError("bladeFaceHalfHeight必须大于零")


def generate_runtime(spec, data):
    validate_config(spec, data)
    result = {"schema": "named-pose.runtime.v1", "version": "P04R3M7", "fps": 30,
              "sourcePoseSHA256": spec["sourcePoseSHA256"]}
    for field in ("parts", "fixedAnchors", "matrices", "states", "poses"):
        result[field] = data[field]
    result["targets"] = [{k: t[k] for k in ("name", "part", "kind", "variants")} for t in data["targets"]]
    result["config"] = {k: spec[k] for k in ("chargeCountMax", "prepareTicks", "transformTicks", "normalFireEntry0", "bladeRotation", "bladeX", "bladeY", "bladeFaceHalfHeight", "strikeFrames0")}
    result["clips"] = {}
    for clip in data["clips"]:
        frames = clip.get("poseIds", [clip.get("holdPose")] * clip["frameCount"])
        milestones = [phase[2] - 1 for phase in clip["phases"]]
        # cancel_ready第11至15帧只是稳定保持，压缩时无需单列其终点。
        if clip["id"] == "cancel_ready":
            milestones = [n for n in milestones if n != 14]
        result["clips"][clip["id"]] = {"frames": frames, "milestones": milestones, "loop": clip["loop"]}
    raw = (json.dumps(result, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
    numbers, number_ids, linear, linear_ids = [], {}, [], {}
    def number_id(value):
        if value not in number_ids:
            number_ids[value] = len(numbers)
            numbers.append(value)
        return number_ids[value]
    matrices = []
    for row in result["matrices"]:
        key = tuple(row[:4])
        if key not in linear_ids:
            linear_ids[key] = len(linear)
            linear.append([number_id(v) for v in key])
        matrices.append([linear_ids[key], number_id(row[4]), number_id(row[5])])
    states = [[r[0]+1, r[1], number_id(r[2])] for r in result["states"]]
    delta = list(result["poses"][0])
    for before, after in zip(result["poses"], result["poses"][1:]):
        changes = [(i, sid) for i, sid in enumerate(after) if before[i] != sid]
        delta.append(len(changes))
        for index, sid in changes:
            delta.extend((index, sid))
    def encode(values):
        stream = bytearray()
        for value in values:
            if not 0 <= value < 65534:
                raise ValueError("索引超过AVM1紧凑字符表边界")
            while value >= 128:
                stream.append((value & 127) | 128)
                value >>= 7
            stream.append(value)
        return base64.b64encode(stream).decode("ascii")
    dense = {k: v for k, v in result.items() if k not in ("matrices", "states", "poses")}
    dense["schema"] = "named-pose.packed.v1"
    dense["numbers"] = numbers
    dense["counts"] = {"linear": len(linear), "matrices": len(matrices), "states": len(states), "poses": len(result["poses"])}
    dense["tables"] = {"linear": encode(v for row in linear for v in row),
                       "matrices": encode(v for row in matrices for v in row),
                       "states": encode(v for row in states for v in row), "poses": encode(delta)}
    # 独立解码回原语义，阻止生成器缩体积时丢失数值、状态或任何完整姿态。
    def decode(text):
        values, value, shift = [], 0, 0
        for byte in base64.b64decode(text, validate=True):
            value |= (byte & 127) << shift
            if byte & 128:
                shift += 7
            else:
                values.append(value)
                value, shift = 0, 0
        if shift:
            raise ValueError("截断的变长整数")
        return values
    decoded_linear = decode(dense["tables"]["linear"])
    decoded_matrices = decode(dense["tables"]["matrices"])
    decoded_states = decode(dense["tables"]["states"])
    restored = []
    for i in range(0, len(decoded_matrices), 3):
        lid, xid, yid = decoded_matrices[i:i+3]
        restored.append([numbers[n] for n in decoded_linear[lid*4:lid*4+4]] + [numbers[xid], numbers[yid]])
    if restored != result["matrices"]:
        raise ValueError("矩阵压缩非无损")
    if [[decoded_states[i]-1, decoded_states[i+1], numbers[decoded_states[i+2]]] for i in range(0, len(decoded_states), 3)] != result["states"]:
        raise ValueError("状态压缩非无损")
    values = decode(dense["tables"]["poses"])
    width = len(result["targets"])
    current = values[:width]
    restored_poses, offset = [current[:]], width
    while offset < len(values):
        count = values[offset]
        offset += 1
        for _ in range(count):
            target, sid = values[offset:offset+2]
            current[target] = sid
            offset += 2
        restored_poses.append(current[:])
    if restored_poses != result["poses"]:
        raise ValueError("完整姿态压缩非无损")
    content = (json.dumps(dense, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
    return content, {"unpackedJSONBytes": len(raw), "numberPool": len(numbers), "linearMatrices": len(linear), "compressionSavingsPercent": round((1-len(content)/len(raw))*100, 1)}


def item_id(name):
    digest = hashlib.sha256(name.encode("utf-8")).hexdigest()
    return digest[:8] + "-" + digest[8:16]


def xml_bytes(element):
    ET.indent(element, space="  ")
    return ET.tostring(element, encoding="utf-8", xml_declaration=True) + b"\n"


def instance(name, library, matrix=None, hidden=False):
    value = ET.Element(Q("DOMSymbolInstance"), {"name": name, "libraryItemName": library, "symbolType": "movie clip"})
    if matrix:
        ET.SubElement(ET.SubElement(value, Q("matrix")), Q("Matrix"), {k: str(v) for k, v in matrix.items()})
    if hidden:
        ET.SubElement(ET.SubElement(value, Q("color")), Q("Color"), {"alphaMultiplier": "0"})
    return value


def new_symbol(name, linkage, elements):
    attributes = {"name": name, "itemID": item_id(name)}
    if linkage:
        attributes.update(linkageExportForAS="true", linkageIdentifier=linkage)
    root = ET.Element(Q("DOMSymbolItem"), attributes)
    timeline = ET.SubElement(ET.SubElement(root, Q("timeline")), Q("DOMTimeline"), {"name": name.split("/")[-1]})
    layers = ET.SubElement(timeline, Q("layers"))
    layer = ET.SubElement(layers, Q("DOMLayer"), {"name": "常驻总装与接口", "color": "#FFFF00"})
    frame = ET.SubElement(ET.SubElement(layer, Q("frames")), Q("DOMFrame"), {"index": "0", "keyMode": "9728"})
    script = ET.SubElement(ET.SubElement(frame, Q("Actionscript")), Q("script"))
    script.text = "stop();"
    target = ET.SubElement(frame, Q("elements"))
    target.extend(elements)
    return root


def import_art(spec, intake):
    source_lib = intake / "原生/P04R3M7/Ashmead-P04R3M7-Native-XFL/LIBRARY"
    old_prefix = "Ashmead/P04R3M7"
    prefix = spec["namespace"]
    pending = [old_prefix + "/NamedRig", old_prefix + "/Icon"]
    source_roots = {}
    while pending:
        name = pending.pop()
        if name in source_roots:
            continue
        source = ET.parse(source_lib / (name + ".xml")).getroot()
        source_roots[name] = source
        pending.extend(n.get("libraryItemName") for n in source.findall(".//x:DOMSymbolInstance", NS))
    imported = {}
    for old_name, source in source_roots.items():
        element = copy.deepcopy(source)
        name = old_name.replace(old_prefix, prefix, 1)
        element.set("name", name)
        element.set("itemID", item_id(name))
        element.attrib.pop("lastModified", None)
        for node in element.iter():
            for key in ("libraryItemName", "name"):
                value = node.get(key)
                if value and value.startswith(old_prefix + "/"):
                    node.set(key, value.replace(old_prefix, prefix, 1))
        if name.endswith("/Icon"):
            element.set("linkageExportForAS", "true")
            element.set("linkageIdentifier", spec["iconLinkage"])
            layers = element.find("./x:timeline/x:DOMTimeline/x:layers", NS)
            layer = ET.SubElement(layers, Q("DOMLayer"), {"name": "停止", "color": "#FFFF00"})
            frame = ET.SubElement(ET.SubElement(layer, Q("frames")), Q("DOMFrame"), {"index": "0", "duration": "2", "keyMode": "9728"})
            ET.SubElement(ET.SubElement(frame, Q("Actionscript")), Q("script")).text = "stop();"
            ET.SubElement(frame, Q("elements"))
        imported[name] = element
    marker = prefix + "/Anchors/Point"
    hit_marker = prefix + "/BladeHitMarker"
    hit_shape = ET.Element(Q("DOMShape"))
    style = ET.SubElement(ET.SubElement(hit_shape, Q("fills")), Q("FillStyle"), {"index": "1"})
    ET.SubElement(style, Q("SolidColor"), {"color": "#FF0000"})
    ET.SubElement(ET.SubElement(hit_shape, Q("edges")), Q("Edge"), {
        "fillStyle0": "1", "edges": "!-400 -1000|-400 1000!-400 1000|400 1000!400 1000|400 -1000!400 -1000|-400 -1000"
    })
    imported[hit_marker] = new_symbol(hit_marker, None, [hit_shape])
    elements = [instance("动画", prefix + "/NamedRig")]
    elements.append(instance("枪口位置", marker, {"tx": 424.1, "ty": 6.45}, True))
    for index in range(1, 4):
        elements.append(instance("刀口位置" + str(index), hit_marker, {"tx": 300, "ty": (index - 2) * 100}, True))
    wrapper_name = prefix + "/Weapon"
    imported[wrapper_name] = new_symbol(wrapper_name, spec["weaponLinkage"], elements)
    library = ROOT / spec["library"]
    document_path = library / "DOMDocument.xml"
    document = ET.parse(document_path).getroot()
    includes = document.find("./x:symbols", NS)
    existing = {n.get("href"): n for n in includes}
    new_includes = []
    for name, element in imported.items():
        relative = name + ".xml"
        path = library / "LIBRARY" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(xml_bytes(element))
        if relative not in existing:
            new_includes.append('          <Include href="' + relative + '" itemID="' + element.get("itemID") + '" loadImmediate="false"/>')
    if new_includes:
        original = document_path.read_text(encoding="utf-8")
        original = original.replace("</symbols>", "\n".join(new_includes) + "\n     </symbols>", 1)
        document_path.write_text(original, encoding="utf-8", newline="")
    # 共享库锚点带入新导出闭包，避免只存在文件却没有进入RSL。
    anchor_path = library / "LIBRARY/Codex专用素材.xml"
    anchor = ET.parse(anchor_path).getroot()
    layers = anchor.find("./x:timeline/x:DOMTimeline/x:layers", NS)
    layer = next((n for n in layers if n.get("name") == "打桩机M7"), None)
    if layer is None:
        layer = ET.SubElement(layers, Q("DOMLayer"), {"name": "打桩机M7", "color": "#FFFF00"})
        frame = ET.SubElement(ET.SubElement(layer, Q("frames")), Q("DOMFrame"), {"index": "0", "keyMode": "9728"})
        entries = ET.SubElement(frame, Q("elements"))
        entries.append(instance("pileBunkerReference", wrapper_name, {"tx": 150, "ty": 130}))
        entries.append(instance("pileBunkerIconReference", prefix + "/Icon", {"tx": 550, "ty": 260}))
        original = anchor_path.read_text(encoding="utf-8")
        closing = "</ns0:layers>" if "</ns0:layers>" in original else "</layers>"
        original = original.replace(closing, ET.tostring(layer, encoding="unicode") + "\n      " + closing, 1)
        anchor_path.write_text(original, encoding="utf-8", newline="")
    return len(imported)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--import-art", type=Path)
    args = parser.parse_args()
    spec, data = read_inputs()
    if args.import_art:
        if args.check:
            parser.error("--check不能导入素材")
        print("Imported symbols:", import_art(spec, args.import_art.resolve()))
    content, packing = generate_runtime(spec, data)
    runtime_path = ROOT / spec["runtimeData"]
    if args.check:
        if not runtime_path.exists() or runtime_path.read_bytes() != content:
            raise ValueError("运行姿态JSON未同步")
    else:
        runtime_path.parent.mkdir(parents=True, exist_ok=True)
        runtime_path.write_bytes(content)
    summary = {"sourceArchiveSHA256": spec["sourceArchiveSHA256"], "sourcePoseSHA256": spec["sourcePoseSHA256"], "runtimeData": spec["runtimeData"], "generatedSHA256": hashlib.sha256(content).hexdigest(), "generatedBytes": len(content), "matrices": len(data["matrices"]), "states": len(data["states"]), "poses": len(data["poses"]), "targets": len(data["targets"]), **packing}
    manifest = ROOT / spec["poseSource"]
    manifest = manifest.parent / "生成清单.json"
    expected = (json.dumps(summary, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        if manifest.read_bytes() != expected:
            raise ValueError("生成清单未同步")
    else:
        manifest.write_bytes(expected)
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
