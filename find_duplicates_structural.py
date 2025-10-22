#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
结构化重复元件检测器
解析 XML 结构并比较实际的视觉内容，而不是简单的文本比较
"""

import os
import hashlib
import xml.etree.ElementTree as ET
from pathlib import Path
from collections import defaultdict
import json
import re


class SymbolAnalyzer:
    """Flash 元件分析器"""

    def __init__(self, xml_path, ignore_scripts=True):
        self.xml_path = xml_path
        self.ignore_scripts = ignore_scripts
        self.tree = None
        self.root = None
        self._parse()

    def _parse(self):
        """解析 XML 文件"""
        try:
            self.tree = ET.parse(self.xml_path)
            self.root = self.tree.getroot()
        except Exception as e:
            print(f"Error parsing {self.xml_path}: {e}")

    def extract_structure(self):
        """
        提取元件的结构化数据
        返回一个规范化的字典，包含所有视觉相关的信息
        """
        if self.root is None:
            return None

        structure = {
            'type': self.root.tag.split('}')[-1] if '}' in self.root.tag else self.root.tag,
            'timeline': self._extract_timeline(),
            'shapes': self._extract_shapes(),
            'bitmaps': self._extract_bitmaps(),
        }

        return structure

    def _extract_timeline(self):
        """提取时间轴数据"""
        timeline_data = []

        # 查找所有 DOMTimeline
        for timeline in self.root.findall('.//{http://ns.adobe.com/xfl/2008/}DOMTimeline'):
            for layer in timeline.findall('.//{http://ns.adobe.com/xfl/2008/}DOMLayer'):
                layer_name = layer.get('name', '')

                for frame in layer.findall('.//{http://ns.adobe.com/xfl/2008/}DOMFrame'):
                    frame_index = frame.get('index', '0')

                    # 提取元素
                    elements = self._extract_elements(frame)

                    if elements:
                        timeline_data.append({
                            'layer': layer_name,
                            'frame': int(frame_index),
                            'elements': elements
                        })

        return timeline_data

    def _extract_elements(self, frame):
        """提取帧中的元素"""
        elements = []

        # 提取 DOMSymbolInstance（库引用）
        for instance in frame.findall('.//{http://ns.adobe.com/xfl/2008/}DOMSymbolInstance'):
            elem = {
                'type': 'SymbolInstance',
                'library': instance.get('libraryItemName', ''),
                'matrix': self._extract_matrix(instance),
                'color': self._extract_color_effect(instance),
                'centerPoint': self._extract_center_point(instance),
            }

            # 可选：提取脚本
            if not self.ignore_scripts:
                script = self._extract_script(instance)
                if script:
                    elem['script'] = script

            elements.append(elem)

        # 提取 DOMShape（矢量图形）
        for shape in frame.findall('.//{http://ns.adobe.com/xfl/2008/}DOMShape'):
            elem = {
                'type': 'Shape',
                'matrix': self._extract_matrix(shape),
                'geometry': self._extract_shape_geometry(shape)
            }
            elements.append(elem)

        # 提取 DOMBitmapInstance（位图）
        for bitmap in frame.findall('.//{http://ns.adobe.com/xfl/2008/}DOMBitmapInstance'):
            elem = {
                'type': 'BitmapInstance',
                'library': bitmap.get('libraryItemName', ''),
                'matrix': self._extract_matrix(bitmap),
            }
            elements.append(elem)

        return elements

    def _extract_matrix(self, element):
        """提取变换矩阵"""
        matrix_elem = element.find('.//{http://ns.adobe.com/xfl/2008/}Matrix')
        if matrix_elem is not None:
            return {
                'a': float(matrix_elem.get('a', '1')),
                'b': float(matrix_elem.get('b', '0')),
                'c': float(matrix_elem.get('c', '0')),
                'd': float(matrix_elem.get('d', '1')),
                'tx': float(matrix_elem.get('tx', '0')),
                'ty': float(matrix_elem.get('ty', '0')),
            }
        return None

    def _extract_color_effect(self, element):
        """提取颜色效果"""
        color_elem = element.find('.//{http://ns.adobe.com/xfl/2008/}Color')
        if color_elem is not None:
            return dict(color_elem.attrib)
        return None

    def _extract_center_point(self, element):
        """提取中心点"""
        cp3dx = element.get('centerPoint3DX')
        cp3dy = element.get('centerPoint3DY')
        if cp3dx or cp3dy:
            return {
                'x': float(cp3dx) if cp3dx else 0,
                'y': float(cp3dy) if cp3dy else 0,
            }
        return None

    def _extract_script(self, element):
        """提取脚本代码"""
        script_elem = element.find('.//{http://ns.adobe.com/xfl/2008/}script')
        if script_elem is not None and script_elem.text:
            return script_elem.text.strip()
        return None

    def _extract_shape_geometry(self, shape):
        """提取矢量图形的几何数据"""
        geometry = {
            'edges': [],
            'fills': []
        }

        # 提取边缘（edges）
        for edge in shape.findall('.//{http://ns.adobe.com/xfl/2008/}Edge'):
            edge_data = self._normalize_edge(edge)
            if edge_data:
                geometry['edges'].append(edge_data)

        # 提取填充（fills）
        for fill in shape.findall('.//{http://ns.adobe.com/xfl/2008/}Fill'):
            fill_data = self._normalize_fill(fill)
            if fill_data:
                geometry['fills'].append(fill_data)

        # 排序以确保一致性
        geometry['edges'].sort(key=lambda x: json.dumps(x, sort_keys=True))
        geometry['fills'].sort(key=lambda x: json.dumps(x, sort_keys=True))

        return geometry

    def _normalize_edge(self, edge):
        """规范化边缘数据"""
        edge_data = {}

        # 提取属性
        for attr in ['edges', 'fillStyle0', 'fillStyle1', 'strokeStyle']:
            val = edge.get(attr)
            if val:
                edge_data[attr] = val

        return edge_data if edge_data else None

    def _normalize_fill(self, fill):
        """规范化填充数据"""
        fill_data = {}

        # 提取 SolidColor
        solid = fill.find('.//{http://ns.adobe.com/xfl/2008/}SolidColor')
        if solid is not None:
            fill_data['type'] = 'solid'
            fill_data['color'] = solid.get('color', '#000000')

        # 提取 LinearGradient
        linear = fill.find('.//{http://ns.adobe.com/xfl/2008/}LinearGradient')
        if linear is not None:
            fill_data['type'] = 'linearGradient'
            # 可以进一步提取渐变点

        # 提取 RadialGradient
        radial = fill.find('.//{http://ns.adobe.com/xfl/2008/}RadialGradient')
        if radial is not None:
            fill_data['type'] = 'radialGradient'

        return fill_data if fill_data else None

    def _extract_shapes(self):
        """提取所有形状的绘制数据"""
        shapes = []
        for shape in self.root.findall('.//{http://ns.adobe.com/xfl/2008/}DOMShape'):
            shape_data = self._extract_shape_geometry(shape)
            if shape_data['edges'] or shape_data['fills']:
                shapes.append(shape_data)
        return shapes

    def _extract_bitmaps(self):
        """提取位图引用"""
        bitmaps = []
        for bitmap in self.root.findall('.//{http://ns.adobe.com/xfl/2008/}DOMBitmapInstance'):
            bitmaps.append(bitmap.get('libraryItemName', ''))
        return bitmaps

    def get_structure_hash(self):
        """计算结构的哈希值"""
        structure = self.extract_structure()
        if structure is None:
            return None

        # 转换为规范化的 JSON 字符串
        json_str = json.dumps(structure, sort_keys=True, ensure_ascii=False)

        # 计算哈希
        return hashlib.md5(json_str.encode('utf-8')).hexdigest()


def analyze_with_structure():
    """使用结构化分析查找重复元件"""
    base_path = Path("flashswf/arts/things0/LIBRARY")
    reference_folder = base_path / "主角肢体素材"

    if not reference_folder.exists():
        print(f"Error: Reference folder not found")
        return

    print("=" * 80)
    print("STRUCTURAL DUPLICATE ANALYSIS")
    print("Comparing structured visual content (ignoring scripts)")
    print("=" * 80)
    print()

    # 收集参考元件
    print("Step 1: Analyzing reference symbols...")
    reference_symbols = {}
    reference_hashes = defaultdict(list)

    for xml_file in reference_folder.glob("*.xml"):
        symbol_name = xml_file.stem
        analyzer = SymbolAnalyzer(xml_file, ignore_scripts=True)
        struct_hash = analyzer.get_structure_hash()
        structure = analyzer.extract_structure()

        if struct_hash:
            reference_symbols[symbol_name] = {
                'path': xml_file,
                'hash': struct_hash,
                'structure': structure,
                'size': os.path.getsize(xml_file)
            }
            reference_hashes[struct_hash].append(symbol_name)

    print(f"  Analyzed {len(reference_symbols)} reference symbols\n")

    # 扫描所有其他元件
    print("Step 2: Scanning entire LIBRARY...")
    structural_duplicates = defaultdict(list)
    total_scanned = 0

    for xml_file in base_path.rglob("*.xml"):
        # 跳过参考文件夹
        if reference_folder in xml_file.parents or xml_file.parent == reference_folder:
            continue

        total_scanned += 1

        try:
            analyzer = SymbolAnalyzer(xml_file, ignore_scripts=True)
            struct_hash = analyzer.get_structure_hash()

            if struct_hash and struct_hash in reference_hashes:
                relative_path = xml_file.relative_to(base_path)
                file_size = os.path.getsize(xml_file)

                for ref_name in reference_hashes[struct_hash]:
                    structural_duplicates[ref_name].append({
                        'path': str(relative_path),
                        'size': file_size,
                        'full_path': xml_file
                    })
        except Exception as e:
            # 忽略无法解析的文件
            pass

    print(f"  Scanned {total_scanned} other symbols\n")

    # 输出结果
    print("=" * 80)
    print("STRUCTURAL DUPLICATE REPORT")
    print("=" * 80)
    print()

    if structural_duplicates:
        total_dup_count = sum(len(dups) for dups in structural_duplicates.values())
        print(f"Found structural duplicates for {len(structural_duplicates)} reference symbol(s)")
        print(f"Total duplicate files: {total_dup_count}\n")

        # 按文件夹分组
        folder_stats = defaultdict(int)
        for ref_name, dups in structural_duplicates.items():
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

        for ref_name in sorted(structural_duplicates.keys()):
            ref_info = reference_symbols[ref_name]
            print(f"[{ref_name}.xml]")
            print(f"  Reference: 主角肢体素材/{ref_name}.xml")
            print(f"  Size: {ref_info['size']} bytes")
            print(f"  Structure Hash: {ref_info['hash']}")
            print(f"  Structural duplicates found: {len(structural_duplicates[ref_name])}")

            for dup in sorted(structural_duplicates[ref_name], key=lambda x: x['path']):
                size_diff = dup['size'] - ref_info['size']
                size_info = "same size" if size_diff == 0 else f"{size_diff:+d} bytes"
                print(f"    -> {dup['path']}")
                print(f"       Size: {dup['size']} bytes ({size_info})")
            print()
    else:
        print("No structural duplicates found!\n")

    # 统计摘要
    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Reference symbols: {len(reference_symbols)}")
    print(f"Other symbols scanned: {total_scanned}")
    print(f"Reference symbols with structural duplicates: {len(structural_duplicates)}")
    print(f"Total duplicate files found: {sum(len(dups) for dups in structural_duplicates.values())}")

    if structural_duplicates:
        total_dup_size = sum(
            dup['size'] for dups in structural_duplicates.values() for dup in dups
        )
        print(f"Total size of duplicates: {total_dup_size:,} bytes ({total_dup_size/1024:.1f} KB)")
        print()
        print("NOTE: This analysis ignores ActionScript code differences.")
        print("Symbols with identical visual structure but different scripts are considered duplicates.")


def save_structural_report():
    """保存结构化分析报告"""
    import sys

    original_stdout = sys.stdout
    with open('duplicate_report_STRUCTURAL.txt', 'w', encoding='utf-8') as f:
        sys.stdout = f
        analyze_with_structure()
    sys.stdout = original_stdout

    print("\n" + "=" * 80)
    print("Structural analysis complete!")
    print("=" * 80)
    print("\nFull report saved to: duplicate_report_STRUCTURAL.txt")


if __name__ == "__main__":
    save_structural_report()
