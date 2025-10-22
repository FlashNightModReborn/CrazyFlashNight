import os
import hashlib
import xml.etree.ElementTree as ET
from pathlib import Path
from collections import defaultdict
import re

def extract_graphic_content(xml_path):
    """
    提取XML中的图形内容用于比较
    重点关注 shapes、edges、fills、DOMBitmapInstance 等实际图形数据
    忽略 name、linkageClassName 等元数据
    """
    try:
        with open(xml_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # 移除名称相关的属性
        content = re.sub(r'\s*name="[^"]*"', '', content)
        content = re.sub(r'\s*linkageClassName="[^"]*"', '', content)
        content = re.sub(r'\s*linkageIdentifier="[^"]*"', '', content)
        content = re.sub(r'\s*linkageExportForAS="[^"]*"', '', content)
        content = re.sub(r'\s*linkageExportForRS="[^"]*"', '', content)

        # 移除 itemID (这是唯一标识符，不影响视觉内容)
        content = re.sub(r'\s*itemID="[^"]*"', '', content)

        # 规范化空白字符
        content = re.sub(r'\s+', ' ', content)
        content = content.strip()

        return content
    except Exception as e:
        # print(f"Error parsing {xml_path}: {e}")
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

def find_duplicates():
    base_path = Path("flashswf/arts/things0/LIBRARY")
    reference_folder = base_path / "主角肢体素材"

    if not reference_folder.exists():
        print(f"错误：找不到参考文件夹 {reference_folder}")
        return

    print("=" * 80)
    print("Scanning reference folder: 主角肢体素材")
    print("=" * 80)

    # 收集参考元件的哈希值
    reference_symbols = {}
    reference_hashes = defaultdict(list)

    for xml_file in reference_folder.glob("*.xml"):
        content_hash = get_content_hash(xml_file)
        if content_hash:
            symbol_name = xml_file.stem
            file_size = get_file_size(xml_file)
            reference_symbols[symbol_name] = {
                'path': xml_file,
                'hash': content_hash,
                'size': file_size
            }
            reference_hashes[content_hash].append(symbol_name)

    print(f"\nFound {len(reference_symbols)} symbols in reference folder\n".encode('utf-8').decode('utf-8'))

    # 扫描整个LIBRARY目录查找重复项
    print("\n" + "=" * 80)
    print("Scanning entire LIBRARY for duplicates...")
    print("=" * 80)
    print()

    duplicates_found = defaultdict(list)
    total_files_scanned = 0

    for xml_file in base_path.rglob("*.xml"):
        # 跳过主角肢体素材文件夹内的文件
        if reference_folder in xml_file.parents or xml_file.parent == reference_folder:
            continue

        total_files_scanned += 1
        content_hash = get_content_hash(xml_file)

        if content_hash and content_hash in reference_hashes:
            # 找到匹配的元件
            relative_path = xml_file.relative_to(base_path)
            file_size = get_file_size(xml_file)
            for ref_name in reference_hashes[content_hash]:
                duplicates_found[ref_name].append({
                    'path': str(relative_path),
                    'size': file_size,
                    'full_path': xml_file
                })

    print(f"Scanned {total_files_scanned} symbol files\n")

    # 输出结果
    print("=" * 80)
    print("Duplicate Symbols Report")
    print("=" * 80)
    print()

    if duplicates_found:
        total_duplicates = sum(len(dups) for dups in duplicates_found.values())
        print(f"Found duplicates for {len(duplicates_found)} reference symbols")
        print(f"Total duplicate files found: {total_duplicates}\n")

        for ref_name in sorted(duplicates_found.keys()):
            ref_size = reference_symbols[ref_name]['size']
            print(f"\n[Reference: {ref_name}.xml] (Size: {ref_size} bytes)")
            print(f"  Found {len(duplicates_found[ref_name])} duplicate(s):")
            for dup_info in sorted(duplicates_found[ref_name], key=lambda x: x['path']):
                size_match = "SAME SIZE" if dup_info['size'] == ref_size else f"DIFF SIZE ({dup_info['size']} bytes)"
                print(f"    - {dup_info['path']}")
                print(f"      [{size_match}]")
    else:
        print("No duplicates found!")

    # 输出统计摘要
    print("\n" + "=" * 80)
    print("Summary Statistics")
    print("=" * 80)
    print(f"Reference symbols count: {len(reference_symbols)}")
    print(f"Other symbols scanned: {total_files_scanned}")
    print(f"Reference symbols with duplicates: {len(duplicates_found)}")
    print(f"Total duplicate files: {sum(len(dups) for dups in duplicates_found.values())}")

if __name__ == "__main__":
    find_duplicates()
