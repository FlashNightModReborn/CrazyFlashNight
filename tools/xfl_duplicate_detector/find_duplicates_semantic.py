#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
语义级重复元件检测器
更宽松的比较，忽略命名细微差异，专注于实际视觉内容
"""

import os
import hashlib
import xml.etree.ElementTree as ET
from pathlib import Path
from collections import defaultdict
import json
import re


class SemanticSymbolAnalyzer:
    """语义级 Flash 元件分析器"""

    def __init__(self, xml_path, ignore_scripts=True, ignore_layer_names=True):
        self.xml_path = xml_path
        self.ignore_scripts = ignore_scripts
        self.ignore_layer_names = ignore_layer_names
        self.tree = None
        self.root = None
        self._parse()

    def _parse(self):
        """解析 XML 文件"""
        try:
            self.tree = ET.parse(self.xml_path)
            self.root = self.tree.getroot()
        except Exception as e:
            pass

    def _normalize_layer_name(self, name):
        """规范化图层名称"""
        if not name:
            return ""
        # 移除空格、下划线，统一转换为小写
        normalized = name.lower().replace(' ', '').replace('_', '')
        # 如果是 "layer" + 数字的模式，统一为 "layer"
        if re.match(r'^layer\d*$', normalized):
            return "layer"
        return normalized

    def extract_semantic_structure(self):
        """提取语义级结构"""
        if self.root is None:
            return None

        structure = {
            'type': self.root.tag.split('}')[-1] if '}' in self.root.tag else self.root.tag,
            'timeline': self._extract_timeline_semantic(),
            'shapes': self._extract_shapes_semantic(),
        }

        return structure

    def _extract_timeline_semantic(self):
        """提取语义级时间轴数据"""
        timeline_data = []

        for timeline in self.root.findall('.//{http://ns.adobe.com/xfl/2008/}DOMTimeline'):
            for layer in timeline.findall('.//{http://ns.adobe.com/xfl/2008/}DOMLayer'):
                layer_name = layer.get('name', '')
                if self.ignore_layer_names:
                    layer_name = self._normalize_layer_name(layer_name)

                for frame in layer.findall('.//{http://ns.adobe.com/xfl/2008/}DOMFrame'):
                    frame_index = frame.get('index', '0')

                    elements = self._extract_elements_semantic(frame)

                    if elements:
                        timeline_data.append({
                            'layer': layer_name,
                            'frame': int(frame_index),
                            'elements': elements
                        })

        return timeline_data

    def _extract_elements_semantic(self, frame):
        """提取语义级元素"""
        elements = []

        # DOMSymbolInstance
        for instance in frame.findall('.//{http://ns.adobe.com/xfl/2008/}DOMSymbolInstance'):
            elem = {
                'type': 'SymbolInstance',
                'library': instance.get('libraryItemName', ''),
                'matrix': self._extract_matrix_rounded(instance),
                'centerPoint': self._extract_center_point_rounded(instance),
            }

            if not self.ignore_scripts:
                script = self._extract_script(instance)
                if script:
                    elem['script'] = script

            elements.append(elem)

        # DOMShape
        for shape in frame.findall('.//{http://ns.adobe.com/xfl/2008/}DOMShape'):
            elem = {
                'type': 'Shape',
                'matrix': self._extract_matrix_rounded(shape),
                'geometry': self._extract_shape_geometry_sorted(shape)
            }
            elements.append(elem)

        # DOMBitmapInstance
        for bitmap in frame.findall('.//{http://ns.adobe.com/xfl/2008/}DOMBitmapInstance'):
            elem = {
                'type': 'BitmapInstance',
                'library': bitmap.get('libraryItemName', ''),
                'matrix': self._extract_matrix_rounded(bitmap),
            }
            elements.append(elem)

        return elements

    def _extract_matrix_rounded(self, element, precision=3):
        """提取变换矩阵并四舍五入到指定精度"""
        matrix_elem = element.find('.//{http://ns.adobe.com/xfl/2008/}Matrix')
        if matrix_elem is not None:
            return {
                'a': round(float(matrix_elem.get('a', '1')), precision),
                'b': round(float(matrix_elem.get('b', '0')), precision),
                'c': round(float(matrix_elem.get('c', '0')), precision),
                'd': round(float(matrix_elem.get('d', '1')), precision),
                'tx': round(float(matrix_elem.get('tx', '0')), precision),
                'ty': round(float(matrix_elem.get('ty', '0')), precision),
            }
        return None

    def _extract_center_point_rounded(self, element, precision=2):
        """提取中心点并四舍五入"""
        cp3dx = element.get('centerPoint3DX')
        cp3dy = element.get('centerPoint3DY')
        if cp3dx or cp3dy:
            return {
                'x': round(float(cp3dx), precision) if cp3dx else 0,
                'y': round(float(cp3dy), precision) if cp3dy else 0,
            }
        return None

    def _extract_script(self, element):
        """提取脚本代码"""
        script_elem = element.find('.//{http://ns.adobe.com/xfl/2008/}script')
        if script_elem is not None and script_elem.text:
            return script_elem.text.strip()
        return None

    def _extract_shape_geometry_sorted(self, shape):
        """提取排序后的矢量几何数据"""
        geometry = {
            'edges': [],
            'fills': []
        }

        # 提取并规范化边缘
        for edge in shape.findall('.//{http://ns.adobe.com/xfl/2008/}Edge'):
            edge_data = self._normalize_edge(edge)
            if edge_data:
                geometry['edges'].append(edge_data)

        # 提取并规范化填充
        for fill in shape.findall('.//{http://ns.adobe.com/xfl/2008/}Fill'):
            fill_data = self._normalize_fill(fill)
            if fill_data:
                geometry['fills'].append(fill_data)

        # 排序以确保顺序无关
        geometry['edges'].sort(key=lambda x: json.dumps(x, sort_keys=True))
        geometry['fills'].sort(key=lambda x: json.dumps(x, sort_keys=True))

        return geometry

    def _normalize_edge(self, edge):
        """规范化边缘数据"""
        edge_data = {}
        for attr in ['edges', 'fillStyle0', 'fillStyle1', 'strokeStyle']:
            val = edge.get(attr)
            if val:
                edge_data[attr] = val
        return edge_data if edge_data else None

    def _normalize_fill(self, fill):
        """规范化填充数据"""
        fill_data = {}

        solid = fill.find('.//{http://ns.adobe.com/xfl/2008/}SolidColor')
        if solid is not None:
            fill_data['type'] = 'solid'
            fill_data['color'] = solid.get('color', '#000000')

        linear = fill.find('.//{http://ns.adobe.com/xfl/2008/}LinearGradient')
        if linear is not None:
            fill_data['type'] = 'linearGradient'

        radial = fill.find('.//{http://ns.adobe.com/xfl/2008/}RadialGradient')
        if radial is not None:
            fill_data['type'] = 'radialGradient'

        return fill_data if fill_data else None

    def _extract_shapes_semantic(self):
        """提取所有形状的语义级数据"""
        shapes = []
        for shape in self.root.findall('.//{http://ns.adobe.com/xfl/2008/}DOMShape'):
            shape_data = self._extract_shape_geometry_sorted(shape)
            if shape_data['edges'] or shape_data['fills']:
                shapes.append(shape_data)
        return shapes

    def get_semantic_hash(self):
        """计算语义级哈希"""
        structure = self.extract_semantic_structure()
        if structure is None:
            return None

        json_str = json.dumps(structure, sort_keys=True, ensure_ascii=False)
        return hashlib.md5(json_str.encode('utf-8')).hexdigest()


def analyze_with_semantic():
    """使用语义级分析查找重复元件"""
    base_path = Path("flashswf/arts/things0/LIBRARY")
    reference_folder = base_path / "主角肢体素材"

    if not reference_folder.exists():
        print("Error: Reference folder not found")
        return

    print("=" * 80)
    print("SEMANTIC-LEVEL DUPLICATE ANALYSIS")
    print("Ignoring: Scripts, Layer name variations")
    print("=" * 80)
    print()

    # 收集参考元件
    print("Step 1: Analyzing reference symbols...")
    reference_symbols = {}
    reference_hashes = defaultdict(list)

    for xml_file in reference_folder.glob("*.xml"):
        symbol_name = xml_file.stem
        analyzer = SemanticSymbolAnalyzer(xml_file, ignore_scripts=True, ignore_layer_names=True)
        semantic_hash = analyzer.get_semantic_hash()

        if semantic_hash:
            reference_symbols[symbol_name] = {
                'path': xml_file,
                'hash': semantic_hash,
                'size': os.path.getsize(xml_file)
            }
            reference_hashes[semantic_hash].append(symbol_name)

    print(f"  Analyzed {len(reference_symbols)} reference symbols\n")

    # 扫描所有其他元件
    print("Step 2: Scanning entire LIBRARY...")
    semantic_duplicates = defaultdict(list)
    total_scanned = 0

    for xml_file in base_path.rglob("*.xml"):
        if reference_folder in xml_file.parents or xml_file.parent == reference_folder:
            continue

        total_scanned += 1

        try:
            analyzer = SemanticSymbolAnalyzer(xml_file, ignore_scripts=True, ignore_layer_names=True)
            semantic_hash = analyzer.get_semantic_hash()

            if semantic_hash and semantic_hash in reference_hashes:
                relative_path = xml_file.relative_to(base_path)
                file_size = os.path.getsize(xml_file)

                for ref_name in reference_hashes[semantic_hash]:
                    semantic_duplicates[ref_name].append({
                        'path': str(relative_path),
                        'size': file_size,
                        'full_path': xml_file
                    })
        except Exception:
            pass

    print(f"  Scanned {total_scanned} other symbols\n")

    # 输出结果
    print("=" * 80)
    print("SEMANTIC DUPLICATE REPORT")
    print("=" * 80)
    print()

    if semantic_duplicates:
        total_dup_count = sum(len(dups) for dups in semantic_duplicates.values())
        print(f"Found semantic duplicates for {len(semantic_duplicates)} reference symbol(s)")
        print(f"Total duplicate files: {total_dup_count}\n")

        folder_stats = defaultdict(int)
        for ref_name, dups in semantic_duplicates.items():
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

        for ref_name in sorted(semantic_duplicates.keys()):
            ref_info = reference_symbols[ref_name]
            print(f"[{ref_name}.xml]")
            print(f"  Reference: {ref_info['size']} bytes")
            print(f"  Hash: {ref_info['hash']}")
            print(f"  Duplicates: {len(semantic_duplicates[ref_name])}")

            for dup in sorted(semantic_duplicates[ref_name], key=lambda x: x['path']):
                size_diff = dup['size'] - ref_info['size']
                size_info = "same" if size_diff == 0 else f"{size_diff:+d}B"
                print(f"    -> {dup['path']} ({dup['size']}B, {size_info})")
            print()
    else:
        print("No semantic duplicates found!\n")

    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Reference symbols: {len(reference_symbols)}")
    print(f"Other symbols scanned: {total_scanned}")
    print(f"Symbols with semantic duplicates: {len(semantic_duplicates)}")
    print(f"Total duplicate files: {sum(len(dups) for dups in semantic_duplicates.values())}")


def save_semantic_report():
    """保存语义级报告"""
    import sys

    original_stdout = sys.stdout
    with open('duplicate_report_SEMANTIC.txt', 'w', encoding='utf-8') as f:
        sys.stdout = f
        analyze_with_semantic()
    sys.stdout = original_stdout

    print("\n" + "=" * 80)
    print("Semantic analysis complete!")
    print("=" * 80)
    print("\nReport saved to: duplicate_report_SEMANTIC.txt")


if __name__ == "__main__":
    save_semantic_report()
