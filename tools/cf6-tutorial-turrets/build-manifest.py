#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/cf6-tutorial-turrets/build-manifest.py

确定性重建 flashswf/arts/new/Codex素材源稿/CF6教学炮塔/manifest.json（schema v2）
及其 raw-tags/ 字节：从原作已校验 SWF 按 charId 提取 13 个真实闭包 tag
（含 r14 新增核对的 502 枪口焰位图 / 927 枪管细节纹理 / 1169 射击声）。

r14 修正不再把 1536/65535 列为"missing 引用"：
- 65535(0xFFFF) 是 503/504/505 FillStyleArray 中真实存在的死条目（任何 edge 都不
  选用它），不是缺失定义，也不是待修复的坏引用；
- 1536 是 r13 extract-native-tags.js 解析器偏移错误产生的幻影引用
  （readMatrixEnd 把 NbitsScale 位误作 HasRotate，并对 DefineBitsJPEG3(1588) 的
  JPEG 体误跑填充扫描）；1536 实际存在但为无关 DefineEditText，不属于本闭包。

用法：
  python -X utf8 -B tools/cf6-tutorial-turrets/build-manifest.py           # 生成
  python -X utf8 -B tools/cf6-tutorial-turrets/build-manifest.py --check   # 只读校验
"""
import hashlib
import importlib.util
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6教学炮塔")

_spec = importlib.util.spec_from_file_location("build_turret_xfl", os.path.join(HERE, "build-turret-xfl.py"))
_bx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_bx)

TAG_NAMES = {2: "DefineShape", 14: "DefineSound", 22: "DefineShape2", 32: "DefineShape3",
             35: "DefineBitsJPEG3", 36: "DefineBitsLossless2", 39: "DefineSprite"}

# 13 个真实闭包 tag（verify-native-decode.py 字节级核对，evidence/verify-decode-r14.json）。
CLOSURE_IDS = [277, 359, 502, 503, 504, 505, 506, 927, 1169, 1588, 1589, 1590, 1591]

CORRECTIONS = {
    "deadFillEntries": {
        "65535": "0xFFFF 填充条目真实存在于 503/504/505 的 FillStyleArray（type 0x43 位图填充），"
                 "但三个形状的所有 edge 记录均不选用该填充索引（503 fillStyle1=2；504/505 fillStyle0=2，"
                 "均指向有效位图 502）。按原作语义保留：不渲染、不以纯色替代、不视作缺失定义。"
    },
    "parserArtifacts": {
        "1536": "r13 extract-native-tags.js 幻影引用：readMatrixEnd 将 NbitsScale 位误作 HasRotate，"
                "并对 DefineBitsJPEG3(1588) 的 JPEG 体误跑填充扫描。1536 实际存在但为无关 "
                "DefineEditText，不属于炮塔闭包；r14 起不再列入任何引用清单。"
    }
}


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def build():
    data, defs = _bx.load_swf(_bx.SWF_PATH)
    tags = {}
    files = {}
    for cid in CLOSURE_IDS:
        if cid not in defs:
            raise SystemExit("closure tag missing from SWF: %d" % cid)
        code, ts, bs, be = defs[cid]
        raw = data[ts:be]
        name = "tag-%d-%s.bin" % (cid, TAG_NAMES.get(code, str(code)))
        files["raw-tags/" + name] = raw
        tags[str(cid)] = {"file": "raw-tags/" + name, "tag": TAG_NAMES.get(code, str(code)),
                          "offset": ts, "length": be - ts, "sha256": sha256_bytes(raw)}
    manifest = {"schema": "cf6-turret-native-tags.v2",
                "sourceSwfSha256": _bx.EXPECT_SHA256,
                "tags": tags,
                "corrections": CORRECTIONS}
    files["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=1) + "\n").encode("utf-8")
    return files


def main():
    files = build()
    if "--check" in sys.argv:
        bad = []
        for rel, content in sorted(files.items()):
            p = os.path.join(OUT_DIR, rel)
            if not os.path.isfile(p) or io.open(p, "rb").read() != content:
                bad.append(rel)
        # 拒绝残留：目录里不得存在本生成集之外的 tag-*.bin
        tag_dir = os.path.join(OUT_DIR, "raw-tags")
        if os.path.isdir(tag_dir):
            expected = set(os.path.basename(r) for r in files if r.startswith("raw-tags/"))
            for f in os.listdir(tag_dir):
                if f.startswith("tag-") and f.endswith(".bin") and f not in expected:
                    bad.append("stale:" + f)
        if bad:
            raise SystemExit("manifest drift: " + ", ".join(bad))
        print(json.dumps({"check": "ok", "tags": len(files) - 1}, ensure_ascii=False))
        return
    os.makedirs(os.path.join(OUT_DIR, "raw-tags"), exist_ok=True)
    for rel, content in sorted(files.items()):
        with io.open(os.path.join(OUT_DIR, rel), "wb") as f:
            f.write(content)
    print(json.dumps({"wrote": len(files), "outDir": os.path.relpath(OUT_DIR, REPO).replace("\\", "/")},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
