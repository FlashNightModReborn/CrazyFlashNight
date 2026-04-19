#!/usr/bin/env python3
"""Copy all Flash loading-background bitmaps to launcher web assets.

Uses UTF-8 hex fingerprints of on-disk names as source-of-truth matching,
avoiding any Chinese-literal comparison pitfalls.
"""
import shutil, os, json, sys

SRC_ROOT = r"e:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\CrazyFlashNight\flashswf\UI\加载背景\LIBRARY"
DEST = r"e:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\CrazyFlashNight\launcher\web\assets\bg"

SUBDIR_HEX = {
    "deprecated": "e58e9fe78988e58aa0e8bdbde8838ce699af2de5bc83e794a8",  # 原版加载背景-弃用
    "remake":     "e58e9fe78988e58aa0e8bdbde8838ce699af2de9878de5819a",  # 原版加载背景-重做
    "official":   "e5ae98e7bd91e5a381e7bab8",                              # 官网壁纸
    "fanmade":    "e697a0e5908de6b08fe887aae588b6e8838ce699af",           # 无名氏自制背景
}

# (subdir-key, dest-suffix) -> on-disk file UTF-8 hex
FILE_HEX = {
    ("deprecated", "01.png"):        "6269746d61703232392e706e67",                       # bitmap229.png
    # 重做 subdir contains 背景-*.png (7 files)
    ("remake",     "andy.png"):      "e8838ce699af2d416e64792e706e67",                   # 背景-Andy.png
    ("remake",     "blue.png"):      "e8838ce699af2d426c75652e706e67",                   # 背景-Blue.png
    ("remake",     "boy.png"):       "e8838ce699af2d426f792e706e67",                     # 背景-Boy.png
    ("remake",     "king.png"):      "e8838ce699af2d4b696e672e706e67",                   # 背景-King.png
    ("remake",     "pig.png"):       "e8838ce699af2d5069672e706e67",                     # 背景-Pig.png
    ("remake",     "shopgirl.png"):  "e8838ce699af2d53686f704769726c2e706e67",           # 背景-ShopGirl.png
    ("remake",     "thegirl.png"):   "e8838ce699af2d5468654769726c2e706e67",             # 背景-TheGirl.png
    # 官网壁纸 subdir
    ("official",   "hero1.jpg"):     "37e4bba3e4b8bbe8a792312e6a7067",                   # 7代主角1.jpg
    ("official",   "hero2.jpg"):     "37e4bba3e4b8bbe8a792322e6a7067",                   # 7代主角2.jpg
    ("official",   "andy.jpg"):      "416e64792e6a7067",                                 # Andy.jpg
    ("official",   "bpk.jpg"):       "42504b2e6a7067",                                   # BPK.jpg
    ("official",   "weapons.jpg"):   "e6ada6e599a82e6a7067",                             # 武器.jpg
    ("official",   "ark.jpg"):       "e8afbae4ba9ae696b9e8889f312e6a7067",              # 诺亚方舟1.jpg
    ("official",   "garage.jpg"):    "e8bda6e5ba932e6a7067",                             # 车库.jpg
    ("official",   "ironcrew.jpg"):  "e9bb91e99381e4bc972e6a7067",                       # 黑铁众.jpg
    # 无名氏自制背景 subdir contains 过场1-3.png
    ("fanmade",    "01.png"):        "e8bf87e59cba312e706e67",                           # 过场1.png
    ("fanmade",    "02.png"):        "e8bf87e59cba322e706e67",                           # 过场2.png
    ("fanmade",    "03.png"):        "e8bf87e59cba332e706e67",                           # 过场3.png
}

os.makedirs(DEST, exist_ok=True)

real_subdirs = {}
for name in os.listdir(SRC_ROOT):
    h = name.encode("utf-8").hex()
    for k, v in SUBDIR_HEX.items():
        if h == v:
            real_subdirs[k] = name
            break

copied = []
missing = []
for (sub_key, dst_suffix), file_hex in FILE_HEX.items():
    if sub_key not in real_subdirs:
        missing.append(f"subdir absent: {sub_key}")
        continue
    sub_path = os.path.join(SRC_ROOT, real_subdirs[sub_key])
    real_file = None
    for name in os.listdir(sub_path):
        if name.encode("utf-8").hex() == file_hex:
            real_file = name; break
    if not real_file:
        missing.append(f"file absent: {sub_key}/{file_hex}")
        continue
    src = os.path.join(sub_path, real_file)
    dst_name = f"{sub_key}-{dst_suffix}"
    dst = os.path.join(DEST, dst_name)
    shutil.copy2(src, dst)
    copied.append(dst_name)

manifest = {"backgrounds": sorted(copied), "count": len(copied)}
with open(os.path.join(DEST, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)

sys.stderr.write(f"Copied: {len(copied)} / {len(FILE_HEX)}\n")
for m in missing:
    sys.stderr.write(f"  {m}\n")
