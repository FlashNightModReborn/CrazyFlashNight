#!/usr/bin/env python3
"""Fix singleshoot parameter across weapon XML files.
For weapons changing from auto to single-shot: add singleshoot=true and increase power by 8%.
  (Skip power increase if interval > 1000ms)
For weapons incorrectly marked as single-shot: remove singleshoot=true (no power change).

Uses positional text replacement to preserve all XML comments and formatting.
"""

import re
import os
import math

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "data", "items")

# Weapons that need singleshoot=true ADDED (currently missing)
ADD_SINGLESHOOT = {
    "武器_手枪_手枪.xml": [
        "PPK", "LugerP08", "毛瑟手枪", "PMM", "MK23手枪", "m9", "M1911",
        "鲁格LCR", "BergmannM1910", "HKUSP9", "中国54式手枪", "M92F",
        "WaltherP99", "WaltherP99C", "Beretta90TWO", "PMR3", "SIGP210",
        "Type92G", "ashcore"
    ],
    "武器_手枪_大威力手枪.xml": [
        "Webley", "恒宇银星", "恒宇红星", "STI2011", "FR506",
        "S&amp;W M500", "Glock40", "BOUNCER LEONE", "湛蓝玫瑰"
    ],
    "武器_手枪_发射器.xml": ["M79式榴弹发射器"],
    "武器_手枪_反器材武器.xml": ["T181S"],
    "武器_手枪_特殊.xml": ["远古诛神短枪"],
    "武器_手枪_霰弹枪.xml": ["超级矮子", "HDBHshotgun", "双管猎枪", "Mossberg500"],
    "武器_长枪_狙击步枪.xml": ["单管步枪", "M24SWS", "Marlin1895", "芬兰之星", "HSR10S"],
    "武器_长枪_霰弹枪.xml": ["单管霰弹枪", "DBHshotgun", "勃朗宁725双管霰弹枪"],
    "武器_长枪_战斗步枪.xml": [
        "HKSL8", "SteyrScout", "Type56R", "G3SG1", "SteyrScout10",
        "KaiShek", "HKSL8BLACK", "QBU-191", "HKSL8EX", "HKSL8GOLD", "战术-QBU-191"
    ],
    "武器_长枪_发射器.xml": [
        "Milkor MGL榴弹发射器", "XM25", "M3 Rocket Launcher", "追月弩", "轰天巨炮"
    ],
    "武器_长枪_特殊.xml": ["天使铳", "诛神枪", "远古诛神枪"],
    "武器_长枪_反器材武器.xml": ["061ABSR", "GM6_LYNX"],
}

# Weapons that need singleshoot=true REMOVED
REMOVE_SINGLESHOOT = {
    "武器_长枪_机枪.xml": ["M1915Chauchat"],
    "武器_长枪_霰弹枪.xml": ["AA12丧尸"],
    "武器_手枪_冲锋枪.xml": ["TTI Glock 34"],
}


def find_item_blocks(content):
    """Find all <item>...</item> blocks with their exact positions."""
    blocks = []
    pattern = re.compile(r'<item\b[^>]*>.*?</item>', re.DOTALL)
    for match in pattern.finditer(content):
        name_match = re.search(r'<name>(.*?)</name>', match.group())
        if name_match:
            blocks.append({
                'name': name_match.group(1),
                'start': match.start(),
                'end': match.end(),
                'text': match.group()
            })
    return blocks


def get_interval(item_text):
    """Get the interval value from an item block."""
    match = re.search(r'<interval>(\d+)</interval>', item_text)
    if match:
        return int(match.group(1))
    return None


def add_singleshoot_to_item(item_text):
    """Add <singleshoot>true</singleshoot> to an item's data block."""
    if '<singleshoot>' in item_text:
        return item_text, False

    # Find <interval>...</interval> line and add singleshoot after it
    match = re.search(r'(<interval>.*?</interval>)', item_text)
    if match:
        line_start = item_text.rfind('\n', 0, match.start())
        indent = item_text[line_start+1:match.start()] if line_start >= 0 else '        '
        insert_pos = match.end()
        new_text = item_text[:insert_pos] + '\n' + indent + '<singleshoot>true</singleshoot>' + item_text[insert_pos:]
        return new_text, True

    # Fallback: add after <data> tag
    match = re.search(r'(<data>)', item_text)
    if match:
        line_start = item_text.rfind('\n', 0, match.start())
        indent = (item_text[line_start+1:match.start()] + '  ') if line_start >= 0 else '          '
        insert_pos = match.end()
        new_text = item_text[:insert_pos] + '\n' + indent + '<singleshoot>true</singleshoot>' + item_text[insert_pos:]
        return new_text, True

    return item_text, False


def remove_singleshoot_from_item(item_text):
    """Remove <singleshoot>true</singleshoot> line from an item."""
    if '<singleshoot>true</singleshoot>' not in item_text:
        return item_text, False
    new_text = re.sub(r'\n[ \t]*<singleshoot>true</singleshoot>', '', item_text)
    return new_text, True


def get_power_factor(interval):
    """Get power compensation factor via linear interpolation.
    Anchor points:
      1000ms -> 0%    (player can match fire rate easily)
       500ms -> 8%    (slight DPS loss from clicking)
       250ms -> 12%   (noticeable DPS loss)
       100ms -> 16%   (hard to click fast enough)
         0ms -> 20%   (theoretical cap)
    """
    if interval is None or interval > 1000:
        return None

    # Interpolation anchors: (interval_ms, boost_percent)
    anchors = [(1000, 0), (500, 8), (250, 12), (100, 16), (0, 20)]

    # Find the two anchors to interpolate between
    for i in range(len(anchors) - 1):
        hi_ms, hi_boost = anchors[i]
        lo_ms, lo_boost = anchors[i + 1]
        if interval >= lo_ms:
            # Linear interpolation
            t = (hi_ms - interval) / (hi_ms - lo_ms)
            boost = hi_boost + t * (lo_boost - hi_boost)
            return 1.0 + boost / 100.0

    return 1.20  # fallback cap


def increase_power(item_text, factor):
    """Increase the <power> value by the given factor."""
    match = re.search(r'<power>(\d+)</power>', item_text)
    if match:
        old_power = int(match.group(1))
        new_power = math.ceil(old_power * factor)
        new_text = item_text[:match.start()] + f'<power>{new_power}</power>' + item_text[match.end():]
        return new_text, old_power, new_power
    return item_text, None, None


def process_file(filename, add_names=None, remove_names=None):
    """Process a single XML file using positional replacement to preserve comments."""
    filepath = os.path.join(DATA_DIR, filename)
    if not os.path.exists(filepath):
        print(f"  WARNING: File not found: {filepath}")
        return

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content
    changes = []

    # Collect all replacements as (start, end, new_text) tuples
    replacements = []

    blocks = find_item_blocks(content)

    # Process additions (add singleshoot + conditionally increase power)
    if add_names:
        for weapon_name in add_names:
            found = False
            for block in blocks:
                if block['name'] == weapon_name:
                    found = True
                    old_text = block['text']
                    new_text = old_text

                    # Add singleshoot
                    new_text, ss_added = add_singleshoot_to_item(new_text)

                    # Get power compensation factor based on interval
                    interval = get_interval(old_text)
                    factor = get_power_factor(interval)

                    if factor is None:
                        # No power increase for slow-firing weapons (interval > 1000ms)
                        old_power = re.search(r'<power>(\d+)</power>', old_text)
                        old_power_val = int(old_power.group(1)) if old_power else None
                        power_info = f", power: {old_power_val} (no boost, interval={interval}ms)" if old_power_val else ""
                    else:
                        new_text, old_power_val, new_power_val = increase_power(new_text, factor)
                        boost_pct = round((factor - 1.0) * 100, 1)
                        power_info = f", power: {old_power_val} -> {new_power_val} (+{boost_pct}%, interval={interval}ms)" if old_power_val else ""

                    if old_text != new_text:
                        replacements.append((block['start'], block['end'], new_text))
                        changes.append(f"  + {weapon_name}: added singleshoot=true{power_info}")
                    break

            if not found:
                print(f"  WARNING: Weapon '{weapon_name}' not found in {filename}")

    # Process removals (remove singleshoot, no power change)
    if remove_names:
        for weapon_name in remove_names:
            found = False
            for block in blocks:
                if block['name'] == weapon_name:
                    found = True
                    old_text = block['text']
                    new_text, removed = remove_singleshoot_from_item(old_text)
                    if removed:
                        replacements.append((block['start'], block['end'], new_text))
                        changes.append(f"  - {weapon_name}: removed singleshoot=true")
                    break
            if not found:
                print(f"  WARNING: Weapon '{weapon_name}' not found in {filename}")

    # Apply replacements from end to start to preserve positions
    if replacements:
        replacements.sort(key=lambda r: r[0], reverse=True)
        for start, end, new_text in replacements:
            content = content[:start] + new_text + content[end:]

        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"\n[{filename}] {len(changes)} changes:")
        for c in changes:
            print(c)
    else:
        print(f"\n[{filename}] No changes needed")


def main():
    print("=" * 60)
    print("Singleshoot Parameter Fix Script")
    print("=" * 60)

    total_add = sum(len(v) for v in ADD_SINGLESHOOT.values())
    total_remove = sum(len(v) for v in REMOVE_SINGLESHOOT.values())
    print(f"\nPlanned: {total_add} additions, {total_remove} removals")
    print(f"Total: {total_add + total_remove} weapons across "
          f"{len(set(list(ADD_SINGLESHOOT.keys()) + list(REMOVE_SINGLESHOOT.keys())))} files")
    print(f"Note: Power +8% skipped for weapons with interval > 1000ms")
    print()

    all_files = set(list(ADD_SINGLESHOOT.keys()) + list(REMOVE_SINGLESHOOT.keys()))

    for filename in sorted(all_files):
        add_names = ADD_SINGLESHOOT.get(filename, None)
        remove_names = REMOVE_SINGLESHOOT.get(filename, None)
        process_file(filename, add_names, remove_names)

    print("\n" + "=" * 60)
    print("Done!")


if __name__ == '__main__':
    main()
