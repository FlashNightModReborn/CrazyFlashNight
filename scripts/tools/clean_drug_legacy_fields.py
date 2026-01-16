#!/usr/bin/env python3
"""
清理药剂 XML 中的旧字段

移除 <data> 节点下的以下旧字段：
- friend
- affecthp
- affectmp
- poison
- clean

保留 effects 节点。

使用方法：
    python clean_drug_legacy_fields.py

作者：FlashNight
"""

import re
import os
from pathlib import Path

# 要处理的文件
FILES = [
    r"c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\data\items\消耗品_药剂.xml",
    r"c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\data\items\消耗品_药剂_食品.xml",
]

# 要移除的旧字段（正则模式）
LEGACY_FIELDS = [
    r'\s*<friend>.*?</friend>\n?',
    r'\s*<affecthp>.*?</affecthp>\n?',
    r'\s*<affectmp>.*?</affectmp>\n?',
    r'\s*<poison>.*?</poison>\n?',
    r'\s*<clean>.*?</clean>\n?',
]

def clean_file(filepath: str) -> tuple[int, int]:
    """
    清理单个文件中的旧字段

    返回：(移除的字段数, 处理的item数)
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content
    total_removed = 0

    for pattern in LEGACY_FIELDS:
        matches = re.findall(pattern, content)
        total_removed += len(matches)
        content = re.sub(pattern, '', content)

    # 清理可能产生的多余空行（<data> 内连续空行）
    content = re.sub(r'(<data>)\n\s*\n', r'\1\n', content)
    content = re.sub(r'\n\s*\n(\s*</data>)', r'\n\1', content)

    # 统计处理的 item 数
    item_count = len(re.findall(r'<item>', content))

    if content != original_content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"[OK] {os.path.basename(filepath)}: removed {total_removed} legacy fields, {item_count} items")
    else:
        print(f"[--] {os.path.basename(filepath)}: no changes needed")

    return total_removed, item_count

def update_xml_comment(filepath: str):
    """更新 XML 注释，移除旧字段相关说明"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # 移除旧字段说明注释
    old_comment = r'注意: 旧字段\(friend/affecthp/affectmp/poison/clean\)已废弃，Tooltip和执行逻辑均从effects读取。\n\s*保留旧字段仅供参考，后续版本将移除。'
    new_comment = '注意: 所有效果均通过 effects 词条配置，旧字段已移除。'

    content = re.sub(old_comment, new_comment, content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

def main():
    print("=" * 50)
    print("Drug XML Legacy Field Cleaner")
    print("=" * 50)
    print()

    total_fields = 0
    total_items = 0

    for filepath in FILES:
        if not os.path.exists(filepath):
            print(f"[ERR] File not found: {filepath}")
            continue

        removed, items = clean_file(filepath)
        total_fields += removed
        total_items += items

        # Update XML comment
        update_xml_comment(filepath)

    print()
    print("-" * 50)
    print(f"Total: removed {total_fields} legacy fields from {total_items} items")
    print("Done!")

if __name__ == "__main__":
    main()
