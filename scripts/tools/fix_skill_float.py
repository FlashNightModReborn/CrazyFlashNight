#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
批量修复技能浮空变量：将 _root.技能浮空 改为单位级别的 技能浮空

替换规则：
1. _root.技能浮空 == true && _parent._parent._name == _root.控制目标
   -> _parent._parent.技能浮空 == true

2. _root.技能浮空 == true and _parent._parent._name == _root.gameworld[_root.控制目标]._name
   -> _parent._parent.技能浮空 == true

3. _root.技能浮空 == true && _parent._name == _root.控制目标
   -> _parent.技能浮空 == true

4. _root.技能浮空 == true and _parent._name == _root.gameworld[_root.控制目标]._name
   -> _parent.技能浮空 == true

5. _parent._name == _root.控制目标 && !_root.技能浮空
   -> !_parent.技能浮空

6. _root.技能浮空 = true (在有 _parent._parent 上下文时)
   -> _parent._parent.技能浮空 = true

7. _root.技能浮空 = false (在有 _parent._parent 上下文时)
   -> _parent._parent.技能浮空 = false

8. _root.技能浮空 = true (在有 _parent 上下文时)
   -> _parent.技能浮空 = true

9. _root.技能浮空 = false (在有 _parent 上下文时)
   -> _parent.技能浮空 = false
"""

import os
import re
import glob

def fix_skill_float(content):
    """修复单个文件的技能浮空引用"""

    # 统计修改次数
    changes = 0

    # 模式1: _root.技能浮空 == true && _parent._parent._name == _root.控制目标
    pattern1 = r'_root\.技能浮空\s*==\s*true\s*&&\s*_parent\._parent\._name\s*==\s*_root\.控制目标'
    if re.search(pattern1, content):
        content = re.sub(pattern1, '_parent._parent.技能浮空 == true', content)
        changes += 1

    # 模式2: _root.技能浮空 == true and _parent._parent._name == _root.gameworld[_root.控制目标]._name
    pattern2 = r'_root\.技能浮空\s*==\s*true\s+and\s+_parent\._parent\._name\s*==\s*_root\.gameworld\[_root\.控制目标\]\._name'
    if re.search(pattern2, content):
        content = re.sub(pattern2, '_parent._parent.技能浮空 == true', content)
        changes += 1

    # 模式3: _root.技能浮空 == true && _parent._name == _root.控制目标
    pattern3 = r'_root\.技能浮空\s*==\s*true\s*&&\s*_parent\._name\s*==\s*_root\.控制目标'
    if re.search(pattern3, content):
        content = re.sub(pattern3, '_parent.技能浮空 == true', content)
        changes += 1

    # 模式4: _root.技能浮空 == true and _parent._name == _root.gameworld[_root.控制目标]._name
    pattern4 = r'_root\.技能浮空\s*==\s*true\s+and\s+_parent\._name\s*==\s*_root\.gameworld\[_root\.控制目标\]\._name'
    if re.search(pattern4, content):
        content = re.sub(pattern4, '_parent.技能浮空 == true', content)
        changes += 1

    # 模式4b: 双空格版本
    pattern4b = r'_root\.技能浮空\s*==\s*true\s+and\s+_parent\._name\s*==\s*_root\.gameworld\[_root\.控制目标\]\._name'
    if re.search(pattern4b, content):
        content = re.sub(pattern4b, '_parent.技能浮空 == true', content)
        changes += 1

    # 模式5: _parent._name == _root.控制目标 && !_root.技能浮空
    pattern5 = r'_parent\._name\s*==\s*_root\.控制目标\s*&&\s*!_root\.技能浮空'
    if re.search(pattern5, content):
        content = re.sub(pattern5, '!_parent.技能浮空', content)
        changes += 1

    # 模式6: 在 _parent._parent 上下文中设置 _root.技能浮空 = true
    # 需要更复杂的上下文检测，暂时简单替换
    pattern6 = r'_root\.技能浮空\s*=\s*true'
    # 先检查是否在 _parent._parent 上下文中
    # 这需要更复杂的分析，暂时跳过自动替换

    # 模式7: _root.技能浮空 = false
    pattern7 = r'_root\.技能浮空\s*=\s*false'
    # 同样需要上下文分析

    return content, changes

def process_files(base_path):
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

    for file_path in all_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            if '_root.技能浮空' not in content:
                continue

            new_content, changes = fix_skill_float(content)

            if changes > 0:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f"Modified: {os.path.basename(file_path)} ({changes} changes)")
                total_changes += changes
                files_changed += 1
        except Exception as e:
            print(f"Error processing {file_path}: {e}")

    print(f"\nTotal: {files_changed} files, {total_changes} changes")

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1:
        base_path = sys.argv[1]
    else:
        base_path = r'c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources'

    process_files(base_path)
