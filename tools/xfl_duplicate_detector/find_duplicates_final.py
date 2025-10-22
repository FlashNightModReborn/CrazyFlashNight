import os
import hashlib
from pathlib import Path
from collections import defaultdict
import re

def extract_visual_content(xml_path):
    """
    提取实际的视觉内容，忽略所有元数据
    包括名称、ID、时间戳、lastUniqueIdentifier等
    """
    try:
        with open(xml_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # 移除所有元数据属性
        content = re.sub(r'\s*name="[^"]*"', '', content)
        content = re.sub(r'\s*linkageClassName="[^"]*"', '', content)
        content = re.sub(r'\s*linkageIdentifier="[^"]*"', '', content)
        content = re.sub(r'\s*linkageExportForAS="[^"]*"', '', content)
        content = re.sub(r'\s*linkageExportForRS="[^"]*"', '', content)
        content = re.sub(r'\s*itemID="[^"]*"', '', content)
        content = re.sub(r'\s*lastModified="[^"]*"', '', content)
        content = re.sub(r'\s*lastUniqueIdentifier="[^"]*"', '', content)
        content = re.sub(r'\s*persistentGUID="[^"]*"', '', content)

        # 规范化空白字符
        content = re.sub(r'\s+', ' ', content)
        content = content.strip()

        return content
    except Exception as e:
        return None

def get_visual_hash(xml_path):
    """计算视觉内容的哈希值"""
    content = extract_visual_content(xml_path)
    if content:
        return hashlib.md5(content.encode('utf-8')).hexdigest()
    return None

def get_file_size(xml_path):
    """获取文件大小"""
    try:
        return os.path.getsize(xml_path)
    except:
        return 0

def analyze_final():
    base_path = Path("flashswf/arts/things0/LIBRARY")
    reference_folder = base_path / "主角肢体素材"

    if not reference_folder.exists():
        print(f"Error: Reference folder not found")
        return

    print("=" * 80)
    print("FINAL DUPLICATE ANALYSIS")
    print("Comparing visual content (ignoring all metadata)")
    print("=" * 80)
    print()

    # 收集参考元件
    print("Collecting reference symbols from: 主角肢体素材")
    reference_symbols = {}
    reference_hashes = defaultdict(list)

    for xml_file in reference_folder.glob("*.xml"):
        symbol_name = xml_file.stem
        visual_hash = get_visual_hash(xml_file)
        file_size = get_file_size(xml_file)

        reference_symbols[symbol_name] = {
            'path': xml_file,
            'hash': visual_hash,
            'size': file_size
        }
        if visual_hash:
            reference_hashes[visual_hash].append(symbol_name)

    print(f"  Found {len(reference_symbols)} reference symbols\n")

    # 扫描所有其他元件
    print("Scanning entire LIBRARY for visual duplicates...")
    all_duplicates = defaultdict(list)
    total_scanned = 0

    for xml_file in base_path.rglob("*.xml"):
        # 跳过参考文件夹
        if reference_folder in xml_file.parents or xml_file.parent == reference_folder:
            continue

        total_scanned += 1
        visual_hash = get_visual_hash(xml_file)

        if visual_hash and visual_hash in reference_hashes:
            relative_path = xml_file.relative_to(base_path)
            file_size = get_file_size(xml_file)

            for ref_name in reference_hashes[visual_hash]:
                all_duplicates[ref_name].append({
                    'path': str(relative_path),
                    'size': file_size,
                    'full_path': xml_file
                })

    print(f"  Scanned {total_scanned} other symbols\n")

    # 输出结果
    print("=" * 80)
    print("DUPLICATE SYMBOLS REPORT")
    print("=" * 80)
    print()

    if all_duplicates:
        total_dup_count = sum(len(dups) for dups in all_duplicates.values())
        print(f"Found visual duplicates for {len(all_duplicates)} reference symbol(s)")
        print(f"Total duplicate files: {total_dup_count}\n")

        # 按文件夹分组统计
        folder_stats = defaultdict(int)
        for ref_name, dups in all_duplicates.items():
            for dup in dups:
                folder = str(Path(dup['path']).parent)
                folder_stats[folder] += 1

        print("Duplicates by folder:")
        for folder, count in sorted(folder_stats.items(), key=lambda x: -x[1]):
            print(f"  {folder}: {count} duplicate(s)")
        print()

        print("-" * 80)
        print("DETAILED LIST:")
        print("-" * 80)
        print()

        for ref_name in sorted(all_duplicates.keys()):
            ref_info = reference_symbols[ref_name]
            print(f"[{ref_name}.xml]")
            print(f"  Reference: 主角肢体素材/{ref_name}.xml")
            print(f"  Size: {ref_info['size']} bytes")
            print(f"  Hash: {ref_info['hash']}")
            print(f"  Visual duplicates found: {len(all_duplicates[ref_name])}")

            for dup in sorted(all_duplicates[ref_name], key=lambda x: x['path']):
                size_diff = dup['size'] - ref_info['size']
                size_info = "same size" if size_diff == 0 else f"{size_diff:+d} bytes"
                print(f"    ✗ {dup['path']}")
                print(f"      Size: {dup['size']} bytes ({size_info})")
            print()
    else:
        print("No visual duplicates found!\n")

    # 统计摘要
    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Reference symbols: {len(reference_symbols)}")
    print(f"Other symbols scanned: {total_scanned}")
    print(f"Reference symbols with duplicates: {len(all_duplicates)}")
    print(f"Total duplicate files found: {sum(len(dups) for dups in all_duplicates.values())}")

    # 计算可清理的潜在空间
    if all_duplicates:
        total_duplicate_size = sum(
            dup['size'] for dups in all_duplicates.values() for dup in dups
        )
        print(f"Total size of duplicate files: {total_duplicate_size:,} bytes ({total_duplicate_size/1024:.1f} KB)")
        print()
        print("RECOMMENDATION:")
        print("These duplicate symbols should be consolidated to use the reference")
        print("symbols from '主角肢体素材' folder to reduce file size and maintain consistency.")

def save_final_report():
    """保存最终报告到文件"""
    import sys

    original_stdout = sys.stdout
    with open('duplicate_report_FINAL.txt', 'w', encoding='utf-8') as f:
        sys.stdout = f
        analyze_final()
    sys.stdout = original_stdout

    print("\n" + "=" * 80)
    print("Analysis complete!")
    print("=" * 80)
    print("\nFull report saved to: duplicate_report_FINAL.txt")
    print("\nKey findings will be displayed below...")

    # 同时输出到控制台
    analyze_final()

if __name__ == "__main__":
    save_final_report()
