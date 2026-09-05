#!/usr/bin/env python3
"""装备度量衡：现实长度换算、单元件轮廓测量、175 cm 男模标定复算。"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from xfl_geometry import Geometry, bounds, contour_svg, matrix, multiply

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
OUTPUT_ROOT = ROOT / 'tmp' / 'asset-metrology'
PROFILE_PATH = TOOL_DIR / 'profiles.json'
SCOPE = '静态 XFL 轮廓；不执行脚本、播放时钟、滤镜或描边扩张，不代表 Flash 运行态验收'


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('必须是大于零的有限数')
    return number


def load_profiles():
    return json.loads(PROFILE_PATH.read_text(encoding='utf-8'))


def convert_length(profile, length_cm, source_px=None, nested_scale=1, style_factor=1):
    values = [length_cm, nested_scale, style_factor, profile['pixelsPerMeter']]
    if source_px is not None:
        values.append(source_px)
    if any(not math.isfinite(v) or v <= 0 for v in values):
        raise ValueError('长度、像素和倍率必须是大于零的有限数')
    outer = length_cm / 100 * profile['pixelsPerMeter'] * style_factor
    target = outer / nested_scale
    result = {'lengthCm': length_cm, 'pixelsPerMeter': profile['pixelsPerMeter'],
              'styleFactor': style_factor, 'nestedScaleToOuter': nested_scale,
              'outerTargetPx': outer, 'editingLayerTargetPx': target}
    if source_px is not None:
        result.update(sourceContentPx=source_px, resizePercent=target/source_px*100)
    if any(not math.isfinite(v) or v <= 0 for v in result.values()):
        raise ValueError('换算结果超出有限正数范围')
    return result


def display_path(path):
    path = path.resolve()
    return path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path)


def source_records(paths):
    return [{'path': display_path(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
            for p in sorted(set(paths))]


def resolve_library(value):
    path = Path(value)
    path = (ROOT / path).resolve() if not path.is_absolute() else path.resolve()
    if not path.exists():
        raise FileNotFoundError(path)
    library = (path if path.is_dir() else path.parent) / 'LIBRARY'
    if not library.is_dir():
        raise ValueError('XFL 路径旁缺少 LIBRARY：' + str(path))
    return library


def measure_symbol(args):
    if args.frame < 1:
        raise ValueError('--frame 使用 Flash 的 1-based 帧号，至少为 1')
    geo = Geometry(resolve_library(args.xfl), include_markers=args.include_markers)
    contours = list(geo.symbol(args.symbol, frame=args.frame-1))
    bb = bounds(contours)
    result = {'kind': 'symbol', 'scope': SCOPE, 'symbol': args.symbol, 'frame': args.frame,
              'boundsPx': bb, 'widthPx': bb[2]-bb[0], 'heightPx': bb[3]-bb[1],
              'excludedMarkers': sorted(geo.skipped), 'warnings': sorted(geo.warnings),
              'sources': source_records(geo.source_files)}
    return result, {'contours.svg': contour_svg(contours, args.symbol)}


def calibrate(profiles):
    """复用纸娃娃的装扮路径定义，只替换其全库扫描为按引用惰性读取。"""
    sys.path.insert(0, str(ROOT / 'tools'))
    spec = importlib.util.spec_from_file_location('asset_metrology_dressup', ROOT / 'tools/bake-dressup-offline.py')
    bake = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = bake
    spec.loader.exec_module(bake)
    paths = set()

    class LazySymbols(dict):
        def __init__(self, library):
            super().__init__()
            self.library = library

        def get(self, name, default=None):
            if name not in self:
                path = (self.library / (name+'.xml')).resolve()
                if not path.is_relative_to(self.library.resolve()):
                    raise ValueError('符号路径越出 LIBRARY')
                self[name] = bake.parse_symbol_file(path)
                paths.add(path)
            return super().get(name, default)

    original_loader = bake.load_xfl_symbols
    bake.load_xfl_symbols = LazySymbols
    try:
        rig = bake.build_battle_rig(ROOT)
    finally:
        bake.load_xfl_symbols = original_loader
    if rig.get('error') or rig.get('auditErrors'):
        raise ValueError('battle rig 解析不完整：' + json.dumps(rig, ensure_ascii=False)[:1500])
    geo = Geometry(ROOT / 'flashswf/arts/things0/LIBRARY')
    states = {}
    reference_contours = []
    for label, state in rig['genders'][profiles['gender']]['states'].items():
        contours = []
        holders = []
        for holder in state['holders']:
            m = matrix(holder['matrix'])
            holders.append({'field': holder['field'], 'path': holder['path'],
                            'matrix': holder['matrix'], 'scaleX': math.hypot(m[0], m[1]),
                            'scaleY': math.hypot(m[2], m[3])})
            basic = holder['basic']
            if basic:
                transform = multiply(m, matrix(basic['matrix']))
                contours.extend(geo.symbol(basic['libraryItemName'], transform=transform))
        bb = bounds(contours)
        states[label] = {'boundsPx': bb, 'heightPx': bb[3]-bb[1], 'holders': holders}
        if label == profiles['referenceState']:
            reference_contours = contours
    root_ppm = states[profiles['referenceState']]['heightPx'] / (profiles['heightCm']/100)
    rates = {}
    for key, state, field in (('weapon', '长枪站立', '长枪_装扮'), ('body', '空手站立', '身体'), ('head', '空手站立', '脸型')):
        holder = next(h for h in states[state]['holders'] if h['field'] == field)
        nominal = profiles['profiles'][key]['pixelsPerMeter']
        rates[key] = {'measuredPixelsPerMeterX': root_ppm/holder['scaleX'],
                      'measuredPixelsPerMeterY': root_ppm/holder['scaleY'],
                      'authoringPixelsPerMeter': nominal,
                      'differencePercentX': (root_ppm/holder['scaleX']/nominal-1)*100}
    paths.update(geo.source_files)
    paths.update(ROOT/p for p in ('scripts/类定义/org/flashNight/arki/unit/UnitUtil.as',
        'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as',
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManager.as'))
    result = {'kind': 'calibrate', 'scope': SCOPE, 'referenceState': profiles['referenceState'],
              'referenceHeightCm': profiles['heightCm'], 'rootPixelsPerMeter': root_ppm,
              'rates': rates, 'states': states, 'warnings': sorted(geo.warnings),
              'sources': source_records(paths)}
    return result, {'reference-contours.svg': contour_svg(reference_contours, profiles['referenceState'])}


def output_path(value):
    path = Path(value)
    path = (ROOT/path).resolve() if not path.is_absolute() else path.resolve()
    managed = OUTPUT_ROOT.resolve()
    if not managed.is_relative_to(ROOT/'tmp') or not path.is_relative_to(managed):
        raise ValueError('输出仅允许位于 tmp/asset-metrology/，源资产目录不可作为输出')
    return path


def main(argv=None):
    profiles = load_profiles()
    parser = argparse.ArgumentParser(description=__doc__)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument('--output-dir', help='相对仓库根目录或绝对路径，仅允许 tmp/asset-metrology/ 下')
    common.add_argument('--dry-run', action='store_true', help='计算并报告结果，不写输出文件')
    commands = parser.add_subparsers(dest='command', required=True)
    convert = commands.add_parser('convert', parents=[common], help='按已标定的外层元件尺度换算')
    convert.add_argument('--profile', choices=profiles['profiles'], required=True)
    convert.add_argument('--length-cm', type=positive, required=True)
    convert.add_argument('--source-px', type=positive, help='源图中对应长度的内容像素，不含留白与标记')
    convert.add_argument('--nested-scale', type=positive, default=1, help='当前编辑层到直接挂载外层的等比倍率')
    convert.add_argument('--style-factor', type=positive, default=1, help='独立记录的美术放大倍率')
    symbol = commands.add_parser('symbol', parents=[common], help='测量指定 XFL 元件的静态轮廓')
    symbol.add_argument('--xfl', required=True, help='XFL 文件或其目录，相对仓库根目录或绝对路径')
    symbol.add_argument('--symbol', required=True, help='库中的完整 symbol 名称，不是 linkage ID')
    symbol.add_argument('--frame', type=int, default=1, help='Flash 的 1-based 帧号，默认第 1 帧')
    symbol.add_argument('--include-markers', action='store_true', help='保留已知枪口、刀口等标记以供诊断')
    commands.add_parser('calibrate', parents=[common], help='从现有 things0 重算男模和各挂载点倍率')
    args = parser.parse_args(argv)
    destination = output_path(args.output_dir) if args.output_dir else None
    if args.command == 'convert':
        result = {'kind': 'convert', 'profile': args.profile, 'profileLabel': profiles['profiles'][args.profile]['label'],
                  **convert_length(profiles['profiles'][args.profile], args.length_cm, args.source_px, args.nested_scale, args.style_factor)}
        extra = {}
    elif args.command == 'symbol':
        result, extra = measure_symbol(args)
    else:
        result, extra = calibrate(profiles)
    result['calibrationId'] = profiles['calibrationId']
    result['calibrationEvidence'] = profiles['evidence']
    result['methodSources'] = source_records([Path(__file__), TOOL_DIR/'xfl_geometry.py', PROFILE_PATH]
        + ([ROOT/'tools/bake-dressup-offline.py'] if args.command == 'calibrate' else []))
    serialized = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)+'\n'
    if destination and not args.dry_run:
        files = {'result.json': serialized, **extra}
        targets = {name: output_path(str(destination/name)) for name in files}
        destination.mkdir(parents=True, exist_ok=True)
        for name, content in files.items():
            targets[name].write_text(content, encoding='utf-8')
        print(json.dumps({'kind': args.command, 'outputs': [display_path(p) for p in targets.values()]}, ensure_ascii=False))
    else:
        print(serialized, end='')
    return 0


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    try:
        raise SystemExit(main())
    except (ValueError, OSError, ET.ParseError) as error:
        print('ERROR: '+str(error), file=sys.stderr)
        raise SystemExit(1)
