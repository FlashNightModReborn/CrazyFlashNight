#!/usr/bin/env python3
"""
SFX 导出 + 归一化重命名 + 校验脚本

工作流:
1. 调用 FFDec CLI 批量导出 3 个 SWF 的音效
2. 将导出文件重命名为 linkageId（文件名即 ID，C# 运行时扫描目录即可）
3. 与 DOMDocument.xml 做集合差校验
4. BGM 完整性扫描

无需生成 manifest —— C# launcher 启动时扫描 sounds/export/{武器,特效,人物}/，
文件名即 linkageId，按固定覆盖顺序（武器→特效→人物）加载。
"""

import os
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import sys

if sys.stdout.encoding != 'utf-8':
    sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='utf-8', buffering=1)

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PACKS = [
    ("武器", "sounds/音效-武器.swf", "sounds/音效-武器/DOMDocument.xml", "sounds/export/武器"),
    ("特效", "sounds/音效-特效.swf", "sounds/音效-特效/DOMDocument.xml", "sounds/export/特效"),
    ("人物", "sounds/音效-人物.swf", "sounds/音效-人物/DOMDocument.xml", "sounds/export/人物"),
]

OVERRIDE_ORDER = ["武器", "特效", "人物"]

FFDEC_CLI = os.path.join(PROJECT_ROOT, "tools", "ffdec", "ffdec-cli.exe")


def normalize_filename(filename, known_ids):
    """
    FFDec 导出格式: {数字}_{linkageId}.{原格式}.{容器格式}
    归一化为 linkageId（文件名即 ID）。

    例: 184_awp1.wav.mp3 -> awp1.wav
    例: 109_爆炸1.mp3 -> 爆炸1.mp3
    例: 50_gunpickup.mp3 -> gunpickup (linkageId 无扩展名)
    """
    m = re.match(r'^(\d+)_(.+)$', filename)
    if not m:
        return None  # 孤儿 (如 -1.wav)
    rest = m.group(2)

    # 双扩展名: base.ext1.ext2 -> base.ext1
    parts = rest.rsplit('.', 1)
    if len(parts) == 2:
        base, outer_ext = parts
        if '.' in base:
            return base

    # 单扩展名: 尝试匹配 known_ids
    if known_ids is not None:
        base_no_ext = os.path.splitext(rest)[0]
        if rest in known_ids:
            return rest
        elif base_no_ext in known_ids:
            return base_no_ext
    return rest


def parse_linkage_ids(xml_rel_path):
    """从 DOMDocument.xml 提取所有 linkageIdentifier"""
    tree = ET.parse(os.path.join(PROJECT_ROOT, xml_rel_path))
    ids = set()
    for item in tree.iter():
        lid = item.get('linkageIdentifier')
        if lid:
            ids.add(lid)
    return ids


def export_and_rename(pack_name, swf_rel, xml_rel, export_rel):
    """导出 SWF 音效并重命名为 linkageId"""
    swf_path = os.path.join(PROJECT_ROOT, swf_rel)
    export_dir = os.path.join(PROJECT_ROOT, export_rel)

    # 1. 清空并创建导出目录
    if os.path.exists(export_dir):
        shutil.rmtree(export_dir)
    os.makedirs(export_dir)

    # 2. FFDec 导出
    print(f"  FFDec 导出 {swf_rel} ...")
    result = subprocess.run(
        [FFDEC_CLI, "-export", "sound", export_dir, swf_path],
        capture_output=True, text=True, encoding='utf-8', errors='replace'
    )
    if result.returncode != 0:
        print(f"  !! FFDec 失败: {result.stderr[:200]}")
        return None, None

    # 3. 解析 XML 获取 linkageId 集合
    xml_ids = parse_linkage_ids(xml_rel)

    # 4. 扫描导出文件并重命名
    renamed = {}  # linkageId -> new_filename
    orphans = []
    for f in os.listdir(export_dir):
        lid = normalize_filename(f, xml_ids)
        if lid is None:
            orphans.append(f)
            # 删除孤儿文件
            os.remove(os.path.join(export_dir, f))
            continue

        # 确定新文件名：linkageId 本身
        # 如果 linkageId 没有扩展名，保留原导出文件的实际扩展名
        new_name = lid
        if '.' not in lid:
            # linkageId 无扩展名，取原文件的实际扩展名
            _, ext = os.path.splitext(f)
            new_name = lid + ext

        old_path = os.path.join(export_dir, f)
        new_path = os.path.join(export_dir, new_name)

        if old_path != new_path:
            # 避免覆盖（同名文件理论上不会出现在同一个包内）
            if os.path.exists(new_path):
                print(f"  !! 冲突: {f} -> {new_name} (已存在)")
                continue
            os.rename(old_path, new_path)

        renamed[lid] = new_name

    return xml_ids, renamed, orphans


def scan_bgm():
    """扫描 bgm_list.xml，检查文件存在性"""
    bgm_xml = os.path.join(PROJECT_ROOT, "sounds/bgm_list.xml")
    tree = ET.parse(bgm_xml)

    results = []
    for music in tree.iter():
        title = None
        url = None
        for child in music:
            if child.tag == 'title':
                title = child.text
            elif child.tag == 'url':
                url = child.text
        if title and url and url != 'stop':
            exists = os.path.isfile(os.path.join(PROJECT_ROOT, url))
            results.append({"title": title, "url": url, "exists": exists})
    return results


def main():
    print("=" * 60)
    print("SFX 导出 + 归一化重命名 + 校验")
    print("=" * 60)

    total_matched = 0
    total_missing = 0
    total_renamed = 0

    for pack_name, swf_rel, xml_rel, export_rel in PACKS:
        print(f"\n--- {pack_name} ---")

        result = export_and_rename(pack_name, swf_rel, xml_rel, export_rel)
        if result[0] is None:
            continue

        xml_ids, renamed, orphans = result

        print(f"  DOMDocument linkageIds: {len(xml_ids)}")
        print(f"  重命名文件: {len(renamed)}, 孤儿(已删): {len(orphans)}")

        # 集合差校验
        matched = xml_ids & set(renamed.keys())
        missing = xml_ids - set(renamed.keys())

        print(f"  匹配: {len(matched)}")
        if missing:
            print(f"  !! 缺失: {len(missing)}")
            for mid in sorted(missing)[:5]:
                print(f"     {mid}")
            if len(missing) > 5:
                print(f"     ... 及其他 {len(missing) - 5} 个")
        else:
            print(f"  缺失: 0 (完美匹配)")

        total_matched += len(matched)
        total_missing += len(missing)
        total_renamed += len(renamed)

    print(f"\n{'=' * 60}")
    print(f"汇总: 匹配 {total_matched}, 缺失 {total_missing}, 重命名 {total_renamed}")
    print(f"{'=' * 60}")

    # 跨包重名统计
    print(f"\n--- 跨包重名 ---")
    all_files = {}
    for pack_name, _, _, export_rel in PACKS:
        export_dir = os.path.join(PROJECT_ROOT, export_rel)
        if not os.path.exists(export_dir):
            continue
        for f in os.listdir(export_dir):
            # 文件名即 linkageId（可能带或不带扩展名）
            lid = f
            base_no_ext = os.path.splitext(f)[0]
            # 用不带扩展名的 base 作为查重键（因为同一 linkageId 在不同包可能有不同扩展名）
            key = f  # 实际上 linkageId 完全相同才算重名
            if key not in all_files:
                all_files[key] = []
            all_files[key].append(pack_name)

    dupes = {k: v for k, v in all_files.items() if len(v) > 1}
    if dupes:
        for lid, packs in sorted(dupes.items()):
            print(f"  {lid}: {packs} -> 最终归属: {packs[-1]}")
    else:
        print("  无重名")

    # BGM 扫描
    print(f"\n--- BGM 完整性扫描 ---")
    bgm_results = scan_bgm()
    missing_bgm = [r for r in bgm_results if not r["exists"]]
    print(f"  总条目: {len(bgm_results)}, 存在: {len(bgm_results) - len(missing_bgm)}")
    if missing_bgm:
        print(f"  !! 缺失: {len(missing_bgm)}")
        for r in missing_bgm:
            print(f"     [{r['title']}] {r['url']}")

    print(f"\n完成。C# 运行时将扫描 sounds/export/{{武器,特效,人物}}/ 目录自动加载。")
    return 0 if total_missing == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
