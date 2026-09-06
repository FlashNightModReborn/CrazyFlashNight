"""从静态分件和显式位移轨迹生成射击动画，不重绘形状或猜测补间。"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{' + NS['x'] + '}'
ET.register_namespace('', NS['x'])
ET.register_namespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance')
EDITOR = {'current', 'currentFrame', 'isSelected', 'selected', 'lastModified', 'lastUniqueIdentifier'}


def repo_path(value: str) -> Path:
    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError('目标必须位于仓库内')
    return path


def symbol_path(xfl: Path, name: str) -> Path:
    path = (xfl / 'LIBRARY' / (name + '.xml')).resolve()
    if not path.is_relative_to((xfl / 'LIBRARY').resolve()):
        raise ValueError('元件路径越界')
    return path


def strip_editor(root: ET.Element) -> ET.Element:
    for node in root.iter():
        for key in EDITOR:
            node.attrib.pop(key, None)
    return root


def canonical(node: ET.Element):
    """允许 IDE 编辑元数据与浮点打印形式变化，保留帧、脚本、图层及引用语义。"""
    attributes = []
    values = dict(node.attrib)
    defaults = {'Matrix': {'a': '1', 'b': '0', 'c': '0', 'd': '1', 'tx': '0', 'ty': '0'},
                'Point': {'x': '0', 'y': '0'}, 'DOMFrame': {'duration': '1'}}
    for key, value in defaults.get(node.tag.removeprefix(N), {}).items():
        values.setdefault(key, value)
    for key, value in sorted(values.items()):
        if key in EDITOR:
            continue
        try:
            normalized = round(float(value), 9)
            if not math.isfinite(normalized):
                raise ValueError('非有限 XML 数值')
        except ValueError:
            normalized = value
        attributes.append((key, normalized))
    return node.tag, tuple(attributes), (node.text or '').strip(), tuple(canonical(child) for child in node)


def inspect(xfl: Path, name: str) -> dict:
    root = ET.parse(symbol_path(xfl, name)).getroot()
    layers = []
    for layer in root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS):
        frames = []
        for frame in layer.findall('./x:frames/x:DOMFrame', NS):
            instances = []
            for instance in frame.findall('./x:elements/x:DOMSymbolInstance', NS):
                matrix = instance.find('./x:matrix/x:Matrix', NS)
                instances.append({'symbol': instance.get('libraryItemName'), 'name': instance.get('name'),
                                  'matrix': dict(matrix.attrib) if matrix is not None else {}})
            script = frame.find('./x:Actionscript/x:script', NS)
            frames.append({'frame': int(frame.get('index', '0')) + 1, 'duration': int(frame.get('duration', '1')),
                           'tween': frame.get('tweenType'), 'instances': instances,
                           'script': script.text if script is not None else None})
        layers.append({'name': layer.get('name'), 'type': layer.get('layerType', 'normal'), 'frames': frames})
    return {'symbol': name, 'type': root.get('symbolType', 'movie clip'),
            'linkage': root.get('linkageIdentifier'), 'layers': layers}


def check_binding(profile: dict) -> None:
    runtime = profile.get('runtime')
    if runtime is None:
        return  # 尚未绑定物品的制作 profile 可先独立制作/检查 XFL。
    items = ET.parse(repo_path(runtime['itemSource'])).getroot().findall('item')
    matches = [item for item in items if item.findtext('name') == runtime['item']]
    if len(matches) != 1:
        raise ValueError('物品定义不唯一或缺失')
    item = matches[0]
    if item.findtext('data/dressup') != runtime['linkage'] or item.findtext('use') != runtime['weaponType']:
        raise ValueError('物品装扮/类型与 profile 不符')
    lifecycle = item.find('lifecycle')
    bindings = [] if lifecycle is None else [entry for entry in lifecycle
        if entry.findtext('init/initRoutines') == runtime['initRoutine']
        and entry.findtext('cycle/cycleRoutines') == runtime['cycleRoutine']]
    if len(bindings) != 1:
        raise ValueError('物品必须有唯一的对应射击动画 lifecycle')
    param = bindings[0].find('init/initParam')
    if param is None or int(param.findtext('fireStart', '0')) != profile['fireStartFrame'] or int(param.findtext('fireEnd', '0')) != profile['frameCount']:
        raise ValueError('物品 XML 的 fireStart/fireEnd 与 profile 不符；同轮同步帧区间')
    target = param.find('animationTarget')
    target_name = '动画' if target is None else (target.text or '')
    if target_name != runtime['animationTarget'] or param.findtext('instanceContainer', '长枪_引用') != runtime['instanceContainer']:
        raise ValueError('物品动画目标与 profile 不符')


def build(profile: dict) -> tuple[Path, ET.Element, dict]:
    if profile.get('schema') != 1:
        raise ValueError('不支持的动画 profile 版本')
    check_binding(profile)
    xfl = repo_path(profile['xfl'])
    if xfl.is_file():
        xfl = xfl.parent
    source_path = symbol_path(xfl, profile['sourceSymbol'])
    destination = symbol_path(xfl, profile['animationSymbol'])
    if source_path == destination:
        raise ValueError('静态总装与动画目标必须独立')
    source = ET.parse(source_path).getroot()
    target = ET.parse(destination).getroot()
    if target.get('symbolType', 'movie clip') != 'movie clip':
        raise ValueError('射击动画目标必须是 MovieClip')
    document = ET.parse(xfl / 'DOMDocument.xml').getroot()
    if float(document.get('frameRate', '24')) != profile['fps']:
        raise ValueError('profile fps 与 XFL 文档帧率不一致')
    includes = {item.get('href') for item in document.findall('./x:symbols/x:Include', NS)}
    for name in ('sourceSymbol', 'animationSymbol'):
        if profile[name] + '.xml' not in includes:
            raise ValueError('元件未登记在 DOMDocument Include: ' + profile[name])

    tracks = profile['tracks']
    if not tracks:
        raise ValueError('至少需要一个运动轨迹')
    count = profile['frameCount']
    if not isinstance(count, int) or not 3 <= count <= 120:
        raise ValueError('帧数必须是 3..120 的整数')
    fire_start = profile['fireStartFrame']
    if not isinstance(fire_start, int) or not 2 <= fire_start < count:
        raise ValueError('击发帧必须位于待机帧之后、末帧之前')
    by_symbol = {}
    for track in tracks:
        offsets = track['offsets']
        if len(offsets) != count:
            raise ValueError('每条轨迹必须逐帧给出偏移')
        for offset in offsets:
            if len(offset) != 2 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in offset):
                raise ValueError('偏移必须是有限的 [dx, dy]')
            if any(abs(v * 20 - round(v * 20)) > 1e-7 for v in offset):
                raise ValueError('偏移必须落在 0.05 px 的 twip 网格')
        if offsets[0] != [0, 0] or offsets[fire_start - 1] != [0, 0] or offsets[-1] != [0, 0]:
            raise ValueError('待机、击发与末帧须回到零偏移，保持现有枪口发射接口')
        for symbol in track['symbols']:
            if symbol in by_symbol:
                raise ValueError('一个分件不能归属两条轨迹: ' + symbol)
            by_symbol[symbol] = offsets

    result = strip_editor(deepcopy(target))
    for child in list(result):
        result.remove(child)
    timeline = ET.SubElement(ET.SubElement(result, N + 'timeline'), N + 'DOMTimeline', {'name': profile['animationSymbol'].split('/')[-1]})
    layers = ET.SubElement(timeline, N + 'layers')
    control = ET.SubElement(layers, N + 'DOMLayer', {'name': '播放控制', 'color': '#4FFF4F'})
    control_frames = ET.SubElement(control, N + 'frames')
    for index, duration in ((0, count - 1), (count - 1, 1)):
        frame = ET.SubElement(control_frames, N + 'DOMFrame', {'index': str(index), 'duration': str(duration), 'keyMode': '9728'})
        ET.SubElement(ET.SubElement(frame, N + 'Actionscript'), N + 'script').text = 'stop();'
        ET.SubElement(frame, N + 'elements')

    consumed = set()
    source_layers = source.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)
    for original_layer in source_layers:
        frames = original_layer.findall('./x:frames/x:DOMFrame', NS)
        if len(frames) != 1 or frames[0].get('index', '0') != '0' or frames[0].get('tweenType'):
            raise ValueError('静态总装只能包含第 1 帧，不能隐式读取已有动画')
        if original_layer.get('layerType', 'normal') != 'normal' or original_layer.get('parentLayerIndex'):
            raise ValueError('总装遮罩与层级分组需先显式展平，工具不猜测其语义')
        original_frame = frames[0]
        elements = original_frame.find('x:elements', NS)
        if original_frame.find('x:Actionscript', NS) is not None or elements is None or len(elements) != 1 or elements[0].tag != N + 'DOMSymbolInstance':
            raise ValueError('总装每层必须是一个无脚本分件实例')
        symbol = elements[0].get('libraryItemName')
        if not symbol_path(xfl, symbol).is_file() or symbol + '.xml' not in includes:
            raise ValueError('分件引用未闭合: ' + str(symbol))
        moving = symbol in by_symbol
        if moving:
            consumed.add(symbol)
        layer = strip_editor(deepcopy(original_layer))
        for child in list(layer):
            layer.remove(child)
        new_frames = ET.SubElement(layer, N + 'frames')
        for index in range(count if moving else 1):
            frame = strip_editor(deepcopy(original_frame))
            frame.attrib = {'index': str(index), 'duration': str(1 if moving else count), 'keyMode': '9728'}
            if moving:
                instance = frame.find('./x:elements/x:DOMSymbolInstance', NS)
                matrix = instance.find('./x:matrix/x:Matrix', NS)
                if matrix is None:
                    matrix = ET.SubElement(ET.SubElement(instance, N + 'matrix'), N + 'Matrix')
                for key, delta in zip(('tx', 'ty'), by_symbol[symbol][index]):
                    value = float(matrix.get(key, '0')) + delta
                    if not math.isfinite(value):
                        raise ValueError('分件矩阵非有限')
                    matrix.set(key, format(value, '.12g'))
            new_frames.append(frame)
        layers.append(layer)
    if consumed != set(by_symbol):
        raise ValueError('轨迹包含总装中不存在的分件: ' + ', '.join(sorted(set(by_symbol) - consumed)))
    return destination, result, {'sourceSymbol': profile['sourceSymbol'], 'animationSymbol': profile['animationSymbol'],
                                 'frames': count, 'fps': profile['fps'], 'movingParts': sorted(consumed),
                                 'staticPartCount': len(source_layers) - len(consumed),
                                 'sourceSha256': hashlib.sha256(source_path.read_bytes()).hexdigest()}


def serialize(root: ET.Element) -> bytes:
    ET.indent(root, space='  ')
    text = ET.tostring(root, encoding='unicode')
    text = text.replace('<script>stop();</script>', '<script><![CDATA[stop();]]></script>')
    return (text + '\n').encode('utf-8')


def native_probe(profile: dict, animation: ET.Element, output: Path) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    expected = []
    layers = animation.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)[1:]
    for index in range(profile['frameCount']):
        symbols = {}
        for layer in layers:
            frames = layer.findall('./x:frames/x:DOMFrame', NS)
            frame = next(f for f in frames if int(f.get('index')) <= index < int(f.get('index')) + int(f.get('duration', '1')))
            instance = frame.find('./x:elements/x:DOMSymbolInstance', NS)
            matrix = instance.find('./x:matrix/x:Matrix', NS)
            values = matrix.attrib if matrix is not None else {}
            symbols[instance.get('libraryItemName')] = {key: float(values.get(key, default))
                for key, default in zip(('a', 'b', 'c', 'd', 'tx', 'ty'), (1, 0, 0, 1, 0, 0))}
        expected.append(symbols)
    def adobe_uri(path: Path) -> str:
        return path.as_uri().replace('file:///' + path.drive, 'file:///' + path.drive.replace(':', '|'))
    return {'entryUri': adobe_uri(repo_path(profile['xfl'])), 'symbol': profile['animationSymbol'],
            'frameCount': profile['frameCount'], 'frames': expected,
            'reportUri': adobe_uri(output / 'native-check.log')}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    inspect_parser = sub.add_parser('inspect')
    inspect_parser.add_argument('--xfl', required=True)
    inspect_parser.add_argument('--symbol', required=True)
    build_parser = sub.add_parser('build')
    build_parser.add_argument('--profile', required=True)
    build_parser.add_argument('--check', action='store_true')
    probe_parser = sub.add_parser('emit-probe')
    probe_parser.add_argument('--profile', required=True)
    probe_parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    if args.command == 'inspect':
        path = repo_path(args.xfl)
        report = inspect(path.parent if path.is_file() else path, args.symbol)
    else:
        profile = json.loads(repo_path(args.profile).read_text('utf-8-sig'))
        destination, result, report = build(profile)
        if args.command == 'emit-probe':
            if canonical(ET.parse(destination).getroot()) != canonical(result):
                raise ValueError('先 build，再生成 CS6 校验输入')
            output = repo_path(args.output_dir)
            if not output.is_relative_to(ROOT / 'tmp/weapon-animation'):
                raise ValueError('原生检查输出只能放在 tmp/weapon-animation 下')
            probe = native_probe(profile, result, output)
            (output / 'native-probe.json').write_text(json.dumps(probe, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            report['state'] = 'probe_written'
        elif args.check:
            if canonical(ET.parse(destination).getroot()) != canonical(result):
                raise ValueError('现役动画与 profile 不一致；先审查差异，再显式 build')
            report['state'] = 'current'
        else:
            destination.write_bytes(serialize(result))
            report['state'] = 'written'
        report['path'] = destination.relative_to(ROOT).as_posix()
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, ET.ParseError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
