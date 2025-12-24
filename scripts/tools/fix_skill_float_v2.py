#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
批量修复技能浮空变量：将 _root.技能浮空 改为单位级别的 技能浮空

替换规则（按优先级顺序）：
1. _root.技能浮空 == true && _parent._parent._name == _root.控制目标
   -> _parent._parent.技能浮空 == true

2. _root.技能浮空 == true and _parent._parent._name == _root.gameworld[_root.控制目标]._name
   -> _parent._parent.技能浮空 == true

3. _root.技能浮空 == true && _parent._name == _root.控制目标
   -> _parent.技能浮空 == true

4. _root.技能浮空 == true and _parent._name == _root.gameworld[_root.控制目标]._name
   -> _parent.技能浮空 == true

5. _parent._name == _root.控制目标 && !_root.技能浮空 && !_parent.浮空
   -> !_parent.技能浮空 && !_parent.浮空

6. _parent._name == _root.控制目标 && !_root.技能浮空
   -> !_parent.技能浮空

7. _root.是否阴影 == true or _root.技能浮空 == false
   -> _root.是否阴影 == true or _parent.技能浮空 == false

8. _root.技能浮空 = true  -> _parent.技能浮空 = true
9. _root.技能浮空 = false -> _parent.技能浮空 = false
"""

import os
import re
import glob

def fix_skill_float(content, filename):
    """修复单个文件的技能浮空引用"""

    original_content = content
    changes = []

    # 模式1: _root.技能浮空 == true && _parent._parent._name == _root.控制目标
    pattern1 = r'_root\.技能浮空\s*==\s*true\s*&&\s*_parent\._parent\._name\s*==\s*_root\.控制目标'
    replacement1 = '_parent._parent.技能浮空 == true'
    if re.search(pattern1, content):
        content = re.sub(pattern1, replacement1, content)
        changes.append(('pattern1', pattern1, replacement1))

    # 模式1b: _root.技能浮空 == true and _parent._parent._name == _root.控制目标 (使用 and 而不是 &&)
    pattern1b = r'_root\.技能浮空\s*==\s*true\s+and\s+_parent\._parent\._name\s*==\s*_root\.控制目标'
    replacement1b = '_parent._parent.技能浮空 == true'
    if re.search(pattern1b, content):
        content = re.sub(pattern1b, replacement1b, content)
        changes.append(('pattern1b', pattern1b, replacement1b))

    # 模式2: _root.技能浮空 == true and _parent._parent._name == _root.gameworld[_root.控制目标]._name
    pattern2 = r'_root\.技能浮空\s*==\s*true\s+and\s+_parent\._parent\._name\s*==\s*_root\.gameworld\[_root\.控制目标\]\._name'
    replacement2 = '_parent._parent.技能浮空 == true'
    if re.search(pattern2, content):
        content = re.sub(pattern2, replacement2, content)
        changes.append(('pattern2', pattern2, replacement2))

    # 模式3: _root.技能浮空 == true && _parent._name == _root.控制目标 (处理可能的多空格)
    pattern3 = r'_root\.技能浮空\s*==\s*true\s*&&\s*_parent\._name\s*==\s*_root\.控制目标'
    replacement3 = '_parent.技能浮空 == true'
    if re.search(pattern3, content):
        content = re.sub(pattern3, replacement3, content)
        changes.append(('pattern3', pattern3, replacement3))

    # 模式4: _root.技能浮空 == true and _parent._name == _root.gameworld[_root.控制目标]._name
    pattern4 = r'_root\.技能浮空\s*==\s*true\s+and\s+_parent\._name\s*==\s*_root\.gameworld\[_root\.控制目标\]\._name'
    replacement4 = '_parent.技能浮空 == true'
    if re.search(pattern4, content):
        content = re.sub(pattern4, replacement4, content)
        changes.append(('pattern4', pattern4, replacement4))

    # 模式5: _parent._name == _root.控制目标 && !_root.技能浮空 && !_parent.浮空 (完整版本)
    pattern5 = r'_parent\._name\s*==\s*_root\.控制目标\s*&&\s*!_root\.技能浮空\s*&&\s*!_parent\.浮空'
    replacement5 = '!_parent.技能浮空 && !_parent.浮空'
    if re.search(pattern5, content):
        content = re.sub(pattern5, replacement5, content)
        changes.append(('pattern5', pattern5, replacement5))

    # 模式6: _parent._name == _root.控制目标 && !_root.技能浮空 (简化版本)
    pattern6 = r'_parent\._name\s*==\s*_root\.控制目标\s*&&\s*!_root\.技能浮空'
    replacement6 = '!_parent.技能浮空'
    if re.search(pattern6, content):
        content = re.sub(pattern6, replacement6, content)
        changes.append(('pattern6', pattern6, replacement6))

    # 模式7: _root.是否阴影 == true or _root.技能浮空 == false
    pattern7 = r'_root\.是否阴影\s*==\s*true\s+or\s+_root\.技能浮空\s*==\s*false'
    replacement7 = '_root.是否阴影 == true or _parent.技能浮空 == false'
    if re.search(pattern7, content):
        content = re.sub(pattern7, replacement7, content)
        changes.append(('pattern7', pattern7, replacement7))

    # 模式8: else if(_root.技能浮空 == true and _parent._name == ...
    # 这个模式在模式4中已经处理

    # 模式9: _root.技能浮空 = true (赋值)
    pattern9 = r'_root\.技能浮空\s*=\s*true(?!\s*&&|\s*and|\s*\|\||\s*or|\s*==)'
    replacement9 = '_parent.技能浮空 = true'
    if re.search(pattern9, content):
        content = re.sub(pattern9, replacement9, content)
        changes.append(('pattern9_assign_true', pattern9, replacement9))

    # 模式10: _root.技能浮空 = false (赋值)
    pattern10 = r'_root\.技能浮空\s*=\s*false(?!\s*&&|\s*and|\s*\|\||\s*or|\s*==)'
    replacement10 = '_parent.技能浮空 = false'
    if re.search(pattern10, content):
        content = re.sub(pattern10, replacement10, content)
        changes.append(('pattern10_assign_false', pattern10, replacement10))

    return content, changes

def process_files(base_path, dry_run=False):
    """处理所有 XML 文件"""

    # 技能容器目录
    skill_container_path = os.path.join(base_path, 'flashswf', 'arts', 'things0', 'LIBRARY', '技能容器')
    sprite_path = os.path.join(base_path, 'flashswf', 'arts', 'things0', 'LIBRARY', 'sprite')
    main_char_path = os.path.join(base_path, 'flashswf', 'arts', 'things0', 'LIBRARY')

    all_files = []

    # 收集所有需要处理的文件
    for path in [skill_container_path, sprite_path]:
        if os.path.exists(path):
            all_files.extend(glob.glob(os.path.join(path, '*.xml')))

    # 添加主角-男.xml
    main_char_file = os.path.join(main_char_path, '主角-男.xml')
    if os.path.exists(main_char_file):
        all_files.append(main_char_file)

    total_changes = 0
    files_changed = 0
    remaining_files = []

    print(f"Scanning {len(all_files)} files...")
    print("=" * 60)

    for file_path in all_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            if '_root.技能浮空' not in content:
                continue

            filename = os.path.basename(file_path)
            new_content, changes = fix_skill_float(content, filename)

            if changes:
                if not dry_run:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                print(f"{'[DRY RUN] ' if dry_run else ''}Modified: {filename}")
                for change in changes:
                    print(f"  - {change[0]}")
                total_changes += len(changes)
                files_changed += 1

                # 检查是否还有残留的 _root.技能浮空
                if '_root.技能浮空' in new_content:
                    remaining_files.append((filename, new_content))
            else:
                # 文件包含 _root.技能浮空 但没有被任何模式匹配
                remaining_files.append((filename, content))

        except Exception as e:
            print(f"Error processing {file_path}: {e}")

    print("=" * 60)
    print(f"\nTotal: {files_changed} files, {total_changes} pattern replacements")

    if remaining_files:
        print(f"\nWARNING: {len(remaining_files)} files still contain _root.技能浮空:")
        for filename, content in remaining_files:
            print(f"\n  {filename}:")
            # 找出残留的行
            for i, line in enumerate(content.split('\n')):
                if '_root.技能浮空' in line:
                    # 清理XML标签
                    clean_line = line.strip()
                    if len(clean_line) > 100:
                        clean_line = clean_line[:100] + "..."
                    print(f"    Line {i+1}: {clean_line}")

if __name__ == '__main__':
    import sys

    dry_run = '--dry-run' in sys.argv

    if len(sys.argv) > 1 and sys.argv[1] != '--dry-run':
        base_path = sys.argv[1]
    else:
        base_path = r'c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources'

    if dry_run:
        print("Running in DRY RUN mode - no files will be modified\n")

    process_files(base_path, dry_run)
