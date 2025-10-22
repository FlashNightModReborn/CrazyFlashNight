import os
import hashlib
from pathlib import Path
from collections import defaultdict
import re

def extract_graphic_content(xml_path):
    """提取图形内容（移除名称等元数据）"""
    try:
        with open(xml_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # 移除名称相关的属性
        content = re.sub(r'\s*name="[^"]*"', '', content)
        content = re.sub(r'\s*linkageClassName="[^"]*"', '', content)
        content = re.sub(r'\s*linkageIdentifier="[^"]*"', '', content)
        content = re.sub(r'\s*linkageExportForAS="[^"]*"', '', content)
        content = re.sub(r'\s*linkageExportForRS="[^"]*"', '', content)
        content = re.sub(r'\s*itemID="[^"]*"', '', content)

        # 规范化空白字符
        content = re.sub(r'\s+', ' ', content)
        content = content.strip()

        return content
    except Exception as e:
        return None

def get_content_hash(xml_path):
    """计算图形内容的哈希值"""
    content = extract_graphic_content(xml_path)
    if content:
        return hashlib.md5(content.encode('utf-8')).hexdigest()
    return None

def get_file_size(xml_path):
    """获取文件大小"""
    try:
        return os.path.getsize(xml_path)
    except:
        return 0

def get_base_name(file_path):
    """获取不含扩展名的文件名"""
    return Path(file_path).stem

def find_similar_names(reference_names, all_symbols):
    """
    查找名称相似的元件（可能是重复的）
    例如：Symbol 3, Symbol 6 等在多个位置出现
    """
    similar_groups = defaultdict(list)

    for ref_name in reference_names:
        base_name = get_base_name(ref_name)
        # 查找所有具有相同基础名的文件
        for sym_path in all_symbols:
            if get_base_name(sym_path) == base_name:
                similar_groups[ref_name].append(sym_path)

    return similar_groups

def analyze_duplicates():
    base_path = Path("flashswf/arts/things0/LIBRARY")
    reference_folder = base_path / "主角肢体素材"

    if not reference_folder.exists():
        print(f"Error: Reference folder not found: {reference_folder}")
        return

    print("=" * 80)
    print("ADVANCED DUPLICATE ANALYSIS")
    print("=" * 80)
    print()

    # 收集所有参考元件
    print("Step 1: Collecting reference symbols...")
    reference_symbols = {}
    for xml_file in reference_folder.glob("*.xml"):
        symbol_name = xml_file.stem
        content_hash = get_content_hash(xml_file)
        file_size = get_file_size(xml_file)

        reference_symbols[symbol_name] = {
            'path': xml_file,
            'hash': content_hash,
            'size': file_size,
            'rel_path': xml_file.relative_to(base_path)
        }

    print(f"  Found {len(reference_symbols)} reference symbols\n")

    # 收集所有其他元件
    print("Step 2: Collecting all other symbols...")
    all_other_symbols = {}
    for xml_file in base_path.rglob("*.xml"):
        if reference_folder in xml_file.parents or xml_file.parent == reference_folder:
            continue

        symbol_key = str(xml_file.relative_to(base_path))
        content_hash = get_content_hash(xml_file)
        file_size = get_file_size(xml_file)

        all_other_symbols[symbol_key] = {
            'path': xml_file,
            'hash': content_hash,
            'size': file_size,
            'name': xml_file.stem
        }

    print(f"  Found {len(all_other_symbols)} other symbols\n")

    # 分析1：完全内容匹配
    print("=" * 80)
    print("Analysis 1: EXACT CONTENT MATCHES")
    print("=" * 80)
    print()

    exact_matches = defaultdict(list)
    for ref_name, ref_info in reference_symbols.items():
        for sym_path, sym_info in all_other_symbols.items():
            if ref_info['hash'] == sym_info['hash']:
                exact_matches[ref_name].append({
                    'path': sym_path,
                    'size': sym_info['size']
                })

    if exact_matches:
        print(f"Found exact content matches for {len(exact_matches)} reference symbol(s):\n")
        for ref_name in sorted(exact_matches.keys()):
            ref_size = reference_symbols[ref_name]['size']
            print(f"[{ref_name}.xml] (Size: {ref_size} bytes)")
            print(f"  Hash: {reference_symbols[ref_name]['hash']}")
            print(f"  {len(exact_matches[ref_name])} exact match(es):")
            for match in sorted(exact_matches[ref_name], key=lambda x: x['path']):
                print(f"    - {match['path']} ({match['size']} bytes)")
            print()
    else:
        print("No exact content matches found.\n")

    # 分析2：按文件名查找可疑重复
    print("=" * 80)
    print("Analysis 2: SYMBOLS WITH SAME NAME (Potential duplicates)")
    print("=" * 80)
    print()

    name_based_duplicates = defaultdict(list)
    for ref_name, ref_info in reference_symbols.items():
        # 查找其他位置有相同名称的元件
        for sym_path, sym_info in all_other_symbols.items():
            if sym_info['name'] == ref_name:
                name_based_duplicates[ref_name].append({
                    'path': sym_path,
                    'size': sym_info['size'],
                    'hash': sym_info['hash'],
                    'same_content': sym_info['hash'] == ref_info['hash']
                })

    if name_based_duplicates:
        print(f"Found {len(name_based_duplicates)} reference symbol(s) with same name elsewhere:\n")
        for ref_name in sorted(name_based_duplicates.keys()):
            ref_info = reference_symbols[ref_name]
            print(f"[{ref_name}.xml]")
            print(f"  Reference: 主角肢体素材/{ref_name}.xml ({ref_info['size']} bytes)")
            print(f"  Found {len(name_based_duplicates[ref_name])} file(s) with same name:")
            for dup in sorted(name_based_duplicates[ref_name], key=lambda x: x['path']):
                content_status = "EXACT MATCH" if dup['same_content'] else "DIFFERENT CONTENT"
                size_diff = dup['size'] - ref_info['size']
                size_info = f"same size" if size_diff == 0 else f"{size_diff:+d} bytes"
                print(f"    - {dup['path']}")
                print(f"      Size: {dup['size']} bytes ({size_info})")
                print(f"      Content: {content_status}")
            print()
    else:
        print("No symbols with same name found elsewhere.\n")

    # 分析3：相似大小的元件
    print("=" * 80)
    print("Analysis 3: SIZE-BASED SIMILARITY (within 10% size difference)")
    print("=" * 80)
    print()

    size_threshold = 0.1  # 10% size difference threshold
    size_similar = defaultdict(list)

    for ref_name, ref_info in reference_symbols.items():
        ref_size = ref_info['size']
        for sym_path, sym_info in all_other_symbols.items():
            sym_size = sym_info['size']
            if ref_size > 0 and sym_size > 0:
                size_ratio = abs(sym_size - ref_size) / ref_size
                if size_ratio <= size_threshold and sym_info['hash'] != ref_info['hash']:
                    size_similar[ref_name].append({
                        'path': sym_path,
                        'size': sym_size,
                        'diff_percent': size_ratio * 100
                    })

    if size_similar:
        print(f"Found potentially similar symbols for {len(size_similar)} reference(s):\n")
        for ref_name in sorted(size_similar.keys()):
            if len(size_similar[ref_name]) > 10:  # Only show if less than 10 matches
                continue
            ref_size = reference_symbols[ref_name]['size']
            print(f"[{ref_name}.xml] (Size: {ref_size} bytes)")
            print(f"  {len(size_similar[ref_name])} similar-sized symbol(s):")
            for sim in sorted(size_similar[ref_name], key=lambda x: x['diff_percent'])[:5]:
                print(f"    - {sim['path']}")
                print(f"      Size: {sim['size']} bytes (diff: {sim['diff_percent']:.1f}%)")
            if len(size_similar[ref_name]) > 5:
                print(f"    ... and {len(size_similar[ref_name]) - 5} more")
            print()
    else:
        print("No size-similar symbols found.\n")

    # 总结
    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Total reference symbols: {len(reference_symbols)}")
    print(f"Total other symbols scanned: {len(all_other_symbols)}")
    print(f"Exact content matches: {sum(len(v) for v in exact_matches.values())}")
    print(f"Same-name duplicates: {sum(len(v) for v in name_based_duplicates.values())}")
    print(f"Size-similar symbols: {sum(len(v) for v in size_similar.values())}")

def save_report_to_file():
    """将分析结果保存到文件"""
    import sys

    # 重定向输出到文件
    original_stdout = sys.stdout
    with open('duplicate_analysis_report.txt', 'w', encoding='utf-8') as f:
        sys.stdout = f
        analyze_duplicates()
    sys.stdout = original_stdout

    print("\nReport saved to: duplicate_analysis_report.txt")
    print("Please open this file to view the full Chinese text correctly.")

if __name__ == "__main__":
    save_report_to_file()
