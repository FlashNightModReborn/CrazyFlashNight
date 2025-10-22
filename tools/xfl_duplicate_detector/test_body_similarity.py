#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
测试身体.xml与 Symbol 37 的相似性
"""

from find_duplicates_structural import SymbolAnalyzer
from pathlib import Path

def test_body_similarity():
    base_path = Path("flashswf/arts/things0/LIBRARY")

    # 三个要比较的文件
    files = {
        '身体': base_path / "主角肢体素材" / "身体.xml",
        'Symbol 36': base_path / "sprite" / "Symbol 36.xml",
        'Symbol 37': base_path / "sprite" / "Symbol 37.xml",
    }

    print("=" * 80)
    print("Testing Structural Similarity")
    print("=" * 80)
    print()

    analyzers = {}
    structures = {}
    hashes = {}

    # 分析每个文件
    for name, filepath in files.items():
        print(f"Analyzing: {name}")
        print(f"  Path: {filepath}")

        # 忽略脚本的分析
        analyzer_no_script = SymbolAnalyzer(filepath, ignore_scripts=True)
        struct_no_script = analyzer_no_script.extract_structure()
        hash_no_script = analyzer_no_script.get_structure_hash()

        # 包含脚本的分析
        analyzer_with_script = SymbolAnalyzer(filepath, ignore_scripts=False)
        struct_with_script = analyzer_with_script.extract_structure()
        hash_with_script = analyzer_with_script.get_structure_hash()

        print(f"  Hash (no script):   {hash_no_script}")
        print(f"  Hash (with script): {hash_with_script}")
        print()

        analyzers[name] = {
            'no_script': analyzer_no_script,
            'with_script': analyzer_with_script
        }
        structures[name] = {
            'no_script': struct_no_script,
            'with_script': struct_with_script
        }
        hashes[name] = {
            'no_script': hash_no_script,
            'with_script': hash_with_script
        }

    # 比较结果
    print("=" * 80)
    print("Comparison Results")
    print("=" * 80)
    print()

    print("Without scripts:")
    print("-" * 40)
    if hashes['身体']['no_script'] == hashes['Symbol 37']['no_script']:
        print("[MATCH] Body == Symbol 37 (IDENTICAL)")
    else:
        print("[DIFF] Body != Symbol 37 (DIFFERENT)")

    if hashes['身体']['no_script'] == hashes['Symbol 36']['no_script']:
        print("[MATCH] Body == Symbol 36 (IDENTICAL)")
    else:
        print("[DIFF] Body != Symbol 36 (DIFFERENT)")

    if hashes['Symbol 36']['no_script'] == hashes['Symbol 37']['no_script']:
        print("[MATCH] Symbol 36 == Symbol 37 (IDENTICAL)")
    else:
        print("[DIFF] Symbol 36 != Symbol 37 (DIFFERENT)")

    print()
    print("With scripts:")
    print("-" * 40)
    if hashes['身体']['with_script'] == hashes['Symbol 37']['with_script']:
        print("[MATCH] Body == Symbol 37 (IDENTICAL)")
    else:
        print("[DIFF] Body != Symbol 37 (DIFFERENT - likely due to scripts)")

    print()
    print("=" * 80)
    print("Structural Details")
    print("=" * 80)
    print()

    for name in ['身体', 'Symbol 37', 'Symbol 36']:
        print(f"{name}:")
        struct = structures[name]['no_script']
        if struct and struct['timeline']:
            for tl in struct['timeline']:
                print(f"  Layer: {tl['layer']}, Frame: {tl['frame']}")
                for elem in tl['elements']:
                    print(f"    Type: {elem['type']}")
                    if elem.get('library'):
                        print(f"    Library: {elem['library']}")
                    if elem.get('matrix'):
                        print(f"    Matrix: {elem['matrix']}")
                    if elem.get('centerPoint'):
                        print(f"    CenterPoint: {elem['centerPoint']}")
        print()

if __name__ == "__main__":
    test_body_similarity()
