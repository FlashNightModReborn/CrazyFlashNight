#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CF6 教学炮塔片段测试模板：schema/坐标/闭包字节 SHA/再生成一致性。

用法：python tools/cf6-tutorial-turrets/test-fragment.py
退出码 0 = 全部通过。只读操作 + 在内存中重算，不写任何文件（--check 也是只读校验）。
"""
import hashlib
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FRAGMENT = os.path.join(ROOT, "tools", "cf6-tutorial-turrets", "tutorial-turrets.fragment.json")
RAW_DIR = os.path.join(ROOT, "flashswf", "arts", "new", "Codex素材源稿", "CF6教学炮塔")

failures = []


def check(cond, msg):
    if cond:
        print("ok - " + msg)
    else:
        failures.append(msg)
        print("FAIL - " + msg)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    with open(FRAGMENT, encoding="utf-8") as f:
        frag = json.load(f)

    check(frag.get("schema") == "cf6-tutorial-turrets.v1", "schema 版本")
    check(frag.get("coordinateSpace") == "native-original", "坐标空间为 native-original")
    check(frag["sourceSwf"]["sha256"] ==
          "b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01", "源 SWF SHA256")
    check(frag["sourceSwf"]["fps"] == 30, "源 SWF fps=30")

    check(frag["targetMap"]["mapId"] == "A01", "目标地图 A01")
    check(frag["tutorialRoomCheck"]["turretInstanceCount"] == 0, "教学室确认无炮塔")

    inst = frag["instances"]
    check(len(inst) == 2, "恰好两门炮塔")
    check(abs(inst[0]["x"] - 133.8) < 1e-9 and abs(inst[0]["y"] - 202.4) < 1e-9, "炮塔A 原坐标")
    check(abs(inst[1]["x"] - 249.8) < 1e-9 and abs(inst[1]["y"] - 430.9) < 1e-9, "炮塔B 原坐标")
    check(all(i["matrix"][:4] == [1, 0, 0, 1] for i in inst), "两门均单位矩阵朝右")
    check(all(i["facing"] == "right" for i in inst), "两门朝右")

    sym = frag["turretSymbol"]
    check(sym["originalCharId"] == 1591 and sym["frameCount"] == 18, "符号 1591 / 18 帧")
    check(sym["fireFrame"] == 12 and sym["fireCycleFrames"] == 18, "帧12 开火 / 18 帧循环")
    check(abs(sym["muzzleMarker"]["local"]["x"] - 105.25) < 1e-9
          and abs(sym["muzzleMarker"]["local"]["y"] - (-12.55)) < 1e-9, "枪口位置2 局部坐标")

    # r14 解码修正事实（证据：evidence/verify-decode-r14.json，本测试独立复读 fragment 不断言镜像）
    check("unresolvedRefs" not in sym, "r13 unresolvedRefs 已移除")
    check(sym.get("deadFillEntries") == [65535], "0xFFFF 标为死填充条目")
    check(sym.get("parserArtifactsRemoved") == [1536], "1536 标为 r13 解析器幻影")
    check(sym["bodyClosure"] == [277, 359, 502, 503, 504, 505, 506, 927, 1169, 1588, 1589, 1590, 1591],
          "闭包恰好 13 个真实 tag（含 502/927/1169）")
    check(sym["bitmapRefs"]["1589"] == [1588, 927], "机身引用 1588 与 927 两张位图")
    check(all(sym["bitmapRefs"][k] == [502] for k in ("503", "504", "505")),
          "枪口焰三帧真实渲染位图均为 502")
    check(sym["muzzleFlash"]["bitmapCharId"] == 502, "枪口焰 bitmapCharId=502")
    cm = sym["frame1Filter"]
    check(cm["type"] == "ColorMatrixFilter" and len(cm["matrix"]) == 20
          and abs(cm["matrix"][0] - 0.48174965381622314) < 1e-9
          and abs(cm["matrix"][14] - (-45.89500427246094)) < 1e-9
          and cm["matrix"][18] == 1.0,
          "帧1 ColorMatrixFilter 20 原值")
    fs_ = sym["fireSound"]
    check(fs_["charId"] == 1169 and fs_["frame"] == 12
          and fs_["envelope"] == {"level0": 11022, "level1": 9533}, "帧12 射击声 1169 与包络原值")
    check(fs_["extractedSha256"] == "b5a94b729ae2e50b22049afddbd870afb44941303e0ac1f5435751ddebe1e83c",
          "射击声提取件 SHA 固定")
    aswf = sym["assetSwf"]
    check(aswf["xfl"] == "flashswf/backgrounds/cf6/CF6_A01_Turret/CF6_A01_Turret.xfl"
          and aswf["swf"] == "flashswf/backgrounds/cf6/CF6_A01_Turret.swf"
          and aswf["assetUrl"] == aswf["swf"]
          and aswf["linkage"] == "CF6教学炮塔-A01自动炮", "独立展示 SWF 目标与 linkage 约定")
    check(any("BulletQueueProcessor.targetFilterEnabled" in r and "目标标记" in r
              for r in frag["integrationRequirements"]),
          "接线清单含 r15 逐弹过滤实接线（targetFilterEnabled fail-closed + 目标标记）")
    check(not any("子弹目标过滤启用" in r for r in frag["integrationRequirements"]),
          "旧 _root.子弹目标过滤启用 假开关方案已被 r15 实接线取代")

    beh = frag["behaviorOriginal"]
    check(beh["controllable"] is False and beh["input"] is None, "不可控制/无输入")
    check(beh["fire"]["power"] == 10 and beh["fire"]["speedPxPerFrame30fps"] == 20
          and beh["fire"]["scatterDeg"] == 15, "火力参数")
    check(beh["damage"]["hurtsPlayer"] is False, "不伤主角")

    manifest_path = os.path.join(RAW_DIR, "manifest.json")
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)
    check(manifest.get("schema") == "cf6-turret-native-tags.v2", "manifest schema v2")
    check(manifest.get("sourceSwfSha256") == frag["sourceSwf"]["sha256"], "manifest 源 SHA 一致")
    check(sorted(int(k) for k in manifest["tags"].keys()) ==
          [277, 359, 502, 503, 504, 505, 506, 927, 1169, 1588, 1589, 1590, 1591],
          "manifest 恰好 13 个真实闭包 tag")
    corr = manifest.get("corrections", {})
    check("65535" in corr.get("deadFillEntries", {}) and "1536" in corr.get("parserArtifacts", {}),
          "manifest 记录 r14 修正（死条目/解析器幻影）")
    for char_id, entry in sorted(manifest["tags"].items()):
        check("missing" not in entry, "tag %s 不再标 missing（r14 已区分死条目与幻影）" % char_id)
        p = os.path.join(RAW_DIR, entry["file"])
        check(os.path.isfile(p) and sha256(p) == entry["sha256"],
              "闭包字节 %s (%s)" % (entry["file"], char_id))
    check(sha256(manifest_path) == frag["turretSymbol"]["nativeSourceManifestSha256"],
          "manifest SHA 与片段一致")

    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "cf6-tutorial-turrets",
                                                     "build-manifest.py"), "--check"],
                       capture_output=True, text=True, cwd=ROOT)
    check(r.returncode == 0, "build-manifest.py --check 字节一致")

    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "cf6-tutorial-turrets",
                                                     "build-fragment.py"), "--check"],
                       capture_output=True, text=True, cwd=ROOT)
    check(r.returncode == 0, "build-fragment.py --check 字节一致")

    print()
    if failures:
        print("FAILED: %d" % len(failures))
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
