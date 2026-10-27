"""Import approved R38 vectors into a reviewable native-XFL candidate.

Default never changes the shared library. --install performs the first import;
after that, the owned XFL is the sole editable authority, not the archived SVGs.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import xml.etree.ElementTree as SE
from lxml import etree as E
from fontTools.svgLib.path import parse_path
from fontTools.pens.svgPathPen import SVGPathPen

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'source'
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
PREFIX = 'Codex/统合61式/'
X = 'http://ns.adobe.com/xfl/2008/'
NS = {'x': X}
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False)


def node(tag, attrs=None, parent=None):
    result = E.Element('{%s}%s' % (X, tag), {k: str(v) for k, v in (attrs or {}).items()})
    if parent is not None:
        parent.append(result)
    return result


def frame(parent, elements, index=0, script=None):
    result = node('DOMFrame', {'index': index, 'duration': 1, 'keyMode': 9728}, parent)
    if script:
        node('script', parent=node('Actionscript', parent=result)).text = E.CDATA(script)
    target = node('elements', parent=result)
    for el in elements:
        target.append(el)
    return result


def layer(name, elements=None, **attrs):
    result = node('DOMLayer', dict(name=name, color='#4FFF4F', **attrs))
    frames = node('frames', parent=result)
    if elements is not None:
        frame(frames, elements)
    return result


def symbol(name, layers, linkage=None, movie=False):
    attrs = {'name': name}
    if linkage:
        attrs.update(linkageExportForAS='true', linkageExportInFirstFrame='true', linkageIdentifier=linkage)
    elif not movie:
        attrs['symbolType'] = 'graphic'
    root = E.Element('{%s}DOMSymbolItem' % X, attrs, nsmap={None: X})
    target = node('layers', parent=node('DOMTimeline', {'name': name.rsplit('/', 1)[-1]}, node('timeline', parent=root)))
    for item in layers:
        target.append(item)
    return root


def instance(name, matrix=(1, 0, 0, 1, 0, 0), instance_name=None, graphic=False):
    attrs = {'libraryItemName': name}
    if graphic:
        attrs.update(symbolType='graphic', loop='single frame', firstFrame=0)
    if instance_name:
        attrs['name'] = instance_name
    result = node('DOMSymbolInstance', attrs)
    node('Matrix', dict(zip(('a', 'b', 'c', 'd', 'tx', 'ty'), (f'{v:.9f}' for v in matrix))), node('matrix', parent=result))
    node('Point', parent=node('transformationPoint', parent=result))
    return result


def writer_module():
    spec = importlib.util.spec_from_file_location('unified61_native', ROOT / 'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def native_art(path, name, generated, module):
    writer = module.Writer(path)
    for element in writer.root.iter():
        if module.tag(element) == 'path' and re.search('[aA]', element.get('d', '')):
            pen = SVGPathPen(None)
            parse_path(element.get('d'), pen)
            element.set('d', pen.getCommands())
    clips = {e.get('id'): e for e in writer.root.iter() if module.tag(e) == 'clipPath'}
    serial = [0]
    masks_created = [0]

    def local_bounds(el):
        points = []
        for start, segments, closed in module.primitive(el):
            previous = start
            points.append(start)
            for segment in segments:
                end = segment[-1]
                points.append(end)
                if segment[0] == 'Q':
                    control = segment[1]
                    for axis in (0, 1):
                        divisor = previous[axis] - 2 * control[axis] + end[axis]
                        if divisor:
                            t = (previous[axis] - control[axis]) / divisor
                            if 0 < t < 1:
                                points.append(tuple((1-t)**2*previous[k] + 2*(1-t)*t*control[k] + t*t*end[k] for k in (0, 1)))
                previous = end
        return min(p[0] for p in points), min(p[1] for p in points), max(p[0] for p in points), max(p[1] for p in points)

    def normalize_gradient(el, styles):
        styles = dict(styles)
        for paint in ('fill', 'stroke'):
            match = re.fullmatch(r'url\(#([^)]*)\)', styles.get(paint, ''))
            if not match:
                continue
            original = writer.grads[match[1]]
            if original.get('gradientUnits', 'objectBoundingBox') != 'objectBoundingBox':
                continue
            left, top, right, bottom = local_bounds(el)
            gradient = copy.deepcopy(original)
            gradient.set('gradientUnits', 'userSpaceOnUse')
            gradient_matrix = module.mul((right-left, 0, 0, bottom-top, left, top), module.transform(gradient.get('gradientTransform')))
            gradient.set('gradientTransform', 'matrix(' + ' '.join(map(str, gradient_matrix)) + ')')
            defaults = {'x1': 0, 'y1': 0, 'x2': 1, 'y2': 0} if module.tag(gradient) == 'linearGradient' else {'cx': .5, 'cy': .5, 'r': .5}
            for key, default in defaults.items():
                value = gradient.get(key, str(default))
                gradient.set(key, str(float(value[:-1])/100 if value.endswith('%') else float(value)))
            for stop in gradient:
                value = stop.get('offset', '0')
                if value.endswith('%'):
                    stop.set('offset', str(float(value[:-1])/100))
            serial[0] += 1
            identifier = '__native_bbox_' + str(serial[0])
            writer.grads[identifier] = gradient
            styles[paint] = 'url(#' + identifier + ')'
        return styles

    def walk(el, parent_style=None, parent_matrix=module.I):
        styles = module.style(el, parent_style)
        matrix = module.mul(parent_matrix, module.transform(el.get('transform')))
        kind = module.tag(el)
        if styles.get('display') == 'none' or styles.get('visibility') == 'hidden':
            return []
        if kind in ('defs', 'title', 'desc', 'metadata', 'linearGradient', 'radialGradient'):
            return []
        clip_ref = el.get('clip-path')
        if clip_ref:
            match = re.fullmatch(r'url\(#([^)]*)\)', clip_ref)
            if not match or match[1] not in clips:
                raise ValueError(f'Unresolved clip {clip_ref}')
            clip = clips[match[1]]
            if clip.get('clipPathUnits', 'userSpaceOnUse') != 'userSpaceOnUse':
                raise ValueError('Object-bbox clipping needs explicit normalization')
            plain = copy.deepcopy(el)
            plain.attrib.pop('clip-path')
            contents = walk(plain, parent_style, parent_matrix)
            masks = []
            clip_matrix = module.mul(matrix, module.transform(clip.get('transform')))
            for child in clip:
                for shape in writer.walk(child, {'fill': '#FFFFFF'}, clip_matrix):
                    masks.append(E.fromstring(SE.tostring(shape)))
            serial[0] += 1
            masks_created[0] += 1
            clip_name = name + '-裁切-' + str(serial[0])
            generated[clip_name] = symbol(clip_name, [
                layer('原稿孔口遮罩', masks, layerType='mask', locked='true'),
                layer('孔内原生矢量', contents, parentLayerIndex=0, locked='true'),
            ])
            return [instance(clip_name, graphic=True)]
        if kind in ('g', 'svg'):
            result = []
            for child in el:
                result.extend(walk(child, styles, matrix))
            return result
        shape = writer.shape(el, normalize_gradient(el, styles), matrix)
        if shape is None:
            return []
        shape.attrib.pop('isFloating', None)
        shape.set('isDrawingObject', 'true')
        return [E.fromstring(SE.tostring(shape))]

    generated[name] = symbol(name, [layer('R38 原生分件', walk(writer.root))])
    return {'shapes': writer.shape_count, 'segments': writer.segment_count, 'masks': masks_created[0]}


def rename_part(old):
    return old.replace('61式', 'Codex-统合61式')


def build():
    source_manifest = json.loads((SOURCE / 'source-manifest.json').read_text('utf-8'))
    for entry in source_manifest['files']:
        if hashlib.sha256((SOURCE / entry['path']).read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('Archived input drift: ' + entry['path'])
    generated, stats = {}, {}
    module = writer_module()
    marker = PREFIX + '接口/炮口'
    generated[marker] = symbol(marker, [layer('接口', [])], movie=True)
    for path in sorted((SOURCE / 'refined/parts').glob('*.svg')):
        linkage = rename_part(path.stem)
        states = ['closed', 'open', 'fire'] if '胸甲身体' in path.stem else ['closed']
        frames = layer('完整系统', None)
        for index, state in enumerate(states):
            src = path if state == 'closed' else SOURCE / ('states/' + state + '/parts') / path.name
            art = PREFIX + '原生/' + linkage + '-' + state
            stats[art] = native_art(src, art, generated, module)
            elements = [instance(art, graphic=True)]
            if len(states) == 3:
                # R38 bay local frame: matrix(1,-.6,.25,.95,47,-19).
                elements.append(instance(marker, (1, -.6, .25, .95, 47, -19), '炮口位置'))
            frame(frames.find('x:frames', NS), elements, index, '__unified61Skin = true; stop();')
        generated[PREFIX + linkage] = symbol(PREFIX + linkage, [frames], linkage)

    assembly = json.loads((SOURCE / 'assembly.json').read_text('utf-8'))
    pose = assembly['poses'][0]
    for item_name, item in assembly['items'].items():
        fields = item['fieldsByGender']['男']
        pieces, corners = [], []
        for holder in pose['holders']:
            key = holder['field'].removesuffix('_装扮')
            if key not in fields:
                continue
            old = fields[key]
            matrix = tuple(holder['matrix'][k] for k in ('a', 'b', 'c', 'd', 'tx', 'ty'))
            pieces.append(instance(PREFIX + rename_part(old), matrix))
            box = [float(v) for v in SE.parse(SOURCE / 'refined/parts' / (old + '.svg')).getroot().get('viewBox').split()]
            x, y, w, h = box
            for u, v in ((x, y), (x+w, y), (x, y+h), (x+w, y+h)):
                corners.append((matrix[0]*u+matrix[2]*v+matrix[4], matrix[1]*u+matrix[3]*v+matrix[5]))
        if not pieces:
            raise ValueError('No native holders: ' + item_name)
        product = PREFIX + '总装/' + item_name
        generated[product] = symbol(product, [layer('原生站姿分件', pieces)])
        left, right = min(p[0] for p in corners), max(p[0] for p in corners)
        top, bottom = min(p[1] for p in corners), max(p[1] for p in corners)
        icon_link = '图标-Codex-统合' + item_name
        timeline = layer('图标与掉落', None)
        for index, size in enumerate((23, 42)):
            scale = size / max(right-left, bottom-top)
            matrix = (scale, 0, 0, scale, -(left+right)*scale/2, -(top+bottom)*scale/2 if index == 0 else -bottom*scale)
            frame(timeline.find('x:frames', NS), [instance(product, matrix, graphic=True)], index, 'stop();')
        generated[PREFIX + icon_link] = symbol(PREFIX + icon_link, [timeline], icon_link)
    return generated, stats


def write_xml(path, root):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = E.tostring(root, encoding='utf-8', pretty_print=True)
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--install', action='store_true')
    args = ap.parse_args()
    if args.install and (OWNER / 'LIBRARY' / PREFIX).exists():
        raise ValueError('Native authority already exists; edit its XFL in place. Reimport would overwrite reviewed limb and icon corrections.')
    generated, stats = build()
    destination = OWNER if args.install else ROOT / 'tmp/unified61-assets/candidate'
    for name, root in generated.items():
        write_xml(destination / 'LIBRARY' / (name + '.xml'), root)
    if args.install:
        document_path = OWNER / 'DOMDocument.xml'
        root = E.parse(str(document_path), PARSER).getroot()
        includes = root.find('x:symbols', NS)
        existing = {e.get('href') for e in includes}
        for name in generated:
            if name + '.xml' not in existing:
                node('Include', {'href': name + '.xml'}, includes)
        write_xml(document_path, root)
    report = {'mode': 'initial-native-import' if args.install else 'candidate', 'symbols': len(generated),
              'exports': [r.get('linkageIdentifier') for r in generated.values() if r.get('linkageIdentifier')],
              'vectors': stats, 'authority': str(OWNER), 'compiled': False}
    (HERE / 'native-manifest.json' if args.install else destination / 'unified61-build.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'mode': report['mode'], 'symbols': report['symbols'], 'exports': len(report['exports']),
                      'shapes': sum(s['shapes'] for s in stats.values()), 'masks': sum(s['masks'] for s in stats.values())}, ensure_ascii=False))


if __name__ == '__main__':
    main()
