"""Import the approved gamma-ECHO SVG pair into the owned CS6 library.

Only --import-approved writes native assets. Subsequent art edits belong to XFL.
SVG clips become native mask layers; paths, strokes and gradients remain vector.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import math
import re
import xml.etree.ElementTree as SE
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/γ-ECHO克隆兽-R3'
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
NOAH = ROOT / 'flashswf/arts/new/素材库-诺亚新敌人/LIBRARY'
PREFIX = 'Codex/γECHO克隆兽/'
SOURCE_ROOT = '诺亚克隆兽/敌人-诺亚克隆兽'
X = 'http://ns.adobe.com/xfl/2008/'
N = '{' + X + '}'
NS = {'x': X}
PARSER = E.XMLParser(remove_blank_text=True, strip_cdata=False)
VARIANTS = [('延寿型', 'stabilized-parts', '敌人-延寿克隆兽', 8),
            ('完全体', 'full-power-parts', '敌人-完全体克隆兽', 9)]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_module('gamma_native_writer', ROOT / 'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py')
geo = load_module('gamma_geometry', ROOT / 'tools/asset-metrology/xfl_geometry.py')
death = load_module('gamma_death', HERE / 'death.py')
connections = load_module('gamma_connections', HERE / 'connections.py')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def item_id(name):
    return '6aa00000-' + hashlib.sha256(name.encode('utf-8')).hexdigest()[:8]


def node(tag, attrs=None, parent=None):
    out = E.Element(N + tag, {k: str(v) for k, v in (attrs or {}).items()})
    if parent is not None:
        parent.append(out)
    return out


def frame(index=0, duration=1, script=None, elements=None, label=None):
    f = node('DOMFrame', {'index': index, 'duration': duration, 'keyMode': 9728})
    if label:
        f.set('name', label)
        f.set('labelType', 'name')
    if script is not None:
        node('script', parent=node('Actionscript', parent=f)).text = E.CDATA(script)
    container = node('elements', parent=f)
    for e in elements or []:
        container.append(e)
    return f


def layer(name, frames=None, **attrs):
    out = node('DOMLayer', {'name': name, 'color': '#9A5E59', **attrs})
    holder = node('frames', parent=out)
    for f in frames or [frame()]:
        holder.append(f)
    return out


def instance(name, matrix=(1, 0, 0, 1, 0, 0)):
    out = node('DOMSymbolInstance', {'libraryItemName': name, 'symbolType': 'graphic', 'loop': 'single frame', 'firstFrame': 0})
    node('Matrix', dict(zip(('a', 'b', 'c', 'd', 'tx', 'ty'), (base.fmt(v) for v in matrix))), node('matrix', parent=out))
    node('Point', parent=node('transformationPoint', parent=out))
    return out


def symbol(name, layers, linkage=None):
    attrs = {'name': name, 'itemID': item_id(name)}
    if linkage:
        attrs.update(linkageExportForAS='true', linkageExportInFirstFrame='true', linkageIdentifier=linkage)
    else:
        attrs['symbolType'] = 'graphic'
    out = E.Element(N + 'DOMSymbolItem', attrs, nsmap={None: X})
    holder = node('layers', parent=node('DOMTimeline', {'name': name.rsplit('/', 1)[-1]}, node('timeline', parent=out)))
    for l in layers:
        holder.append(l)
    return out


def xml_bytes(tree):
    # Preserve inherited frame code while normalizing indentation-only legacy
    # whitespace, so newly tracked XFL passes the repository whitespace check.
    for script in tree.findall('.//x:script', NS):
        source = script.text or ''
        lines = [re.sub(r'^[ \t]+', lambda m: m[0].expandtabs(4), line.rstrip(' \t'))
                 for line in source.splitlines()]
        normalized = '\n'.join(lines) + ('\n' if source.endswith('\n') else '')
        script.text = E.CDATA(normalized)
    return E.tostring(tree, encoding='utf-8', xml_declaration=True, pretty_print=True)


class NativePart:
    """Preserve SVG paint order and nested clip scopes as static native layers."""
    def __init__(self, path, name, origin):
        self.writer = base.Writer(path)
        self.svg = self.writer.root
        self.name = name
        self.origin = origin
        self.symbols = {}
        self.serial = 0
        self.masks = 0
        self.by_id = {e.get('id'): e for e in self.svg.iter() if e.get('id')}

    def paint_shape(self, el, attrs, matrix):
        el = copy.deepcopy(el)
        attrs = dict(attrs)
        fill = attrs.get('fill', '#000000')
        match = re.fullmatch(r'url\(#([^)]*)\)', fill)
        if match:
            original = self.writer.grads[match[1]]
            if original.get('gradientUnits', 'objectBoundingBox') == 'objectBoundingBox':
                # Resolve each element's object-bbox gradient BEFORE origin transforms.
                contours = []
                for start, segs, closed in base.primitive(el):
                    p = start
                    for seg in segs:
                        contours.append((p, *seg[1:]))
                        p = seg[-1]
                x0, y0, x1, y1 = geo.bounds(contours)
                if x1 <= x0 or y1 <= y0:
                    raise ValueError('Degenerate gradient bounds')
                g = copy.deepcopy(original)
                ident = 'resolved-' + str(self.serial)
                self.serial += 1
                g.set('id', ident)
                g.set('gradientUnits', 'userSpaceOnUse')
                for key, default in [('x1', '0%'), ('y1', '0%'), ('x2', '100%'), ('y2', '0%')]:
                    raw = g.get(key, default)
                    g.set(key, str(float(raw[:-1]) / 100 if raw.endswith('%') else float(raw)))
                bbox = (x1-x0, 0, 0, y1-y0, x0, y0)
                gm = base.mul(bbox, base.transform(g.get('gradientTransform')))
                g.set('gradientTransform', 'matrix(' + ' '.join(map(str, gm)) + ')')
                self.writer.grads[ident] = g
                attrs['fill'] = 'url(#' + ident + ')'
        sh = self.writer.shape(el, attrs, matrix)
        if sh is None:
            return None
        sh.attrib.pop('isFloating', None)
        sh.set('isDrawingObject', 'true')
        return E.fromstring(SE.tostring(sh))

    def contents(self, el, inherited=None, matrix=base.I):
        attrs = base.style(el, inherited)
        attrs.pop('clip-path', None)
        m = base.mul(matrix, base.transform(el.get('transform')))
        kind = base.tag(el)
        if kind in ('defs', 'title', 'desc', 'metadata', 'clipPath', 'linearGradient'):
            return []
        if kind not in ('svg', 'g'):
            sh = self.paint_shape(el, attrs, m)
            return [sh] if sh is not None else []
        result = []
        for child in el:
            raw = child.get('clip-path')
            if not raw:
                result.extend(self.contents(child, attrs, m))
                continue
            match = re.fullmatch(r'url\(#([^)]*)\)', raw)
            if not match:
                raise ValueError('Unsupported clip: ' + raw)
            clip = self.by_id[match[1]]
            if clip.get('clipPathUnits', 'userSpaceOnUse') != 'userSpaceOnUse':
                raise ValueError('Only user-space clips are expected')
            child_matrix = base.mul(m, base.transform(child.get('transform')))
            mask_shapes = []
            for mask in clip:
                a = base.style(mask)
                a.update(fill='#FFFFFF', stroke='none')
                sh = self.paint_shape(mask, a, base.mul(child_matrix, base.transform(clip.get('transform'))))
                if sh is not None:
                    mask_shapes.append(sh)
            helper = self.name + '-遮罩' + str(self.masks)
            self.masks += 1
            drawn = self.contents(child, attrs, m)
            self.symbols[helper] = symbol(helper, [
                layer('轮廓遮罩', [frame(elements=mask_shapes)], layerType='mask', locked='true'),
                layer('原生色块与线条', [frame(elements=drawn)], parentLayerIndex='0', locked='true'),
            ])
            result.append(instance(helper))
        return result

    def build(self):
        ox, oy = self.origin
        drawing = self.contents(self.svg, matrix=(1, 0, 0, 1, -ox, -oy))
        self.symbols[self.name] = symbol(self.name, [layer('R3原生矢量', [frame(elements=drawing)])])
        return self.symbols, {'shapes': self.writer.shape_count, 'segments': self.writer.segment_count, 'masks': self.masks}


def verify_input():
    # The accepted handoff is archived beside XFL; regeneration must not need tmp/.
    drawing = json.loads((ARCHIVE / 'drawing-manifest.json').read_text(encoding='utf-8'))
    if len(drawing['parts']) != 13:
        raise ValueError('Expected the thirteen approved body parts')
    if sha(ARCHIVE / 'part-geometry.json') != drawing['geometrySha256']:
        raise ValueError('Archived registration geometry differs')
    for part in drawing['parts']:
        for folder, key in [('full-power-parts', 'fullPowerSha256'),
                            ('stabilized-parts', 'stabilizedSha256')]:
            path = ARCHIVE / folder / f'{part["id"]}.svg'
            if sha(path) != part[key]:
                raise ValueError('Archived approved input differs: ' + str(path))


def generate_variant(label, folder, linkage, stage):
    prefix = PREFIX + label + '/'
    root_name = prefix + linkage
    mapping = {}
    parts = json.loads((ARCHIVE / 'drawing-manifest.json').read_text(encoding='utf-8'))['parts']
    all_symbols, stats = {}, []
    for part in parts:
        name = prefix + '分件/' + part['label']
        mapping['诺亚克隆兽/部件/Symbol ' + str(part['id'] - 7)] = name
        converted, report = NativePart(ARCHIVE / folder / f'{part["id"]}.svg', name, part['origin']).build()
        all_symbols.update(converted)
        stats.append({'id': part['id'], 'name': name, **report})
    mapping[SOURCE_ROOT] = root_name
    live = {part['id']: mapping['诺亚克隆兽/部件/Symbol ' + str(part['id'] - 7)] for part in parts}
    origins = {part['id']: part['origin'] for part in parts}
    connection_changes = connections.apply(globals(), all_symbols, live, origins, stage == 9)
    gore, gore_names = death.create_parts(globals(), prefix, live, origins, stage == 9)
    all_symbols.update(gore)
    death_changes = {}

    def target(name):
        return mapping.setdefault(name, prefix + '原生/' + name)

    def clone(name):
        if name in all_symbols:
            return name
        mapped = target(name)
        if mapped in all_symbols:
            return mapped
        src = E.parse(str(NOAH / (name + '.xml')), PARSER).getroot()
        if name == '诺亚克隆兽/动画合集/死亡':
            death_changes.update(death.apply_timeline(globals(), src, gore_names))
        src.set('name', mapped)
        src.set('itemID', item_id(mapped))
        for k in ('lastModified', 'lastUniqueIdentifier', 'linkageExportForAS', 'linkageExportInFirstFrame',
                  'linkageIdentifier', 'linkageImportForRS', 'linkageExportForRS', 'linkageURL', 'linkageClassName'):
            src.attrib.pop(k, None)
        src.find('x:timeline/x:DOMTimeline', NS).set('name', mapped.rsplit('/', 1)[-1])
        all_symbols[mapped] = src
        if name == SOURCE_ROOT:
            src.set('linkageExportForAS', 'true')
            src.set('linkageExportInFirstFrame', 'true')
            src.set('linkageIdentifier', linkage)
            main_script = src.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer[@name="代码层"]/x:frames/x:DOMFrame[@index="0"]/x:Actionscript/x:script', NS)
            ai = (HERE / 'GammaEchoAI.as').read_text(encoding='utf-8-sig')
            main_script.text = E.CDATA(main_script.text + '\n克隆兽完全体 = ' + ('true' if stage == 9 else 'false') + ';\n' + ai)
            sensor = src.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer[@name="索敌层"]/x:frames/x:DOMFrame/x:elements/x:DOMSymbolInstance/x:Actionscript/x:script', NS)
            body = sensor.text[sensor.text.index('{')+1:sensor.text.rfind('}')]
            sensor.text = E.CDATA('onClipEvent (enterFrame) {\nif (_parent.克隆兽AI模式 == "enhanced") {\n_parent.gammaEchoThink(this);\n} else {\n' + body + '\n}\n}')
        for e in src.iter():
            ref = e.get('libraryItemName')
            if ref:
                e.set('libraryItemName', clone(ref))
        return mapped

    clone(SOURCE_ROOT)
    return all_symbols, {'variant': label, 'displayName': '暴君克隆兽' if stage == 9 else 'λ型克隆兽',
                         'root': root_name, 'linkage': linkage, 'stage': stage, 'parts': stats,
                         'connections': connection_changes,
                         'death': {'parts': gore_names, 'replacedKeyframes': death_changes,
                                   'labelsZeroBased': {'a0': 0, 'a1': 47, 'a2': 78},
                                   'callbackFramesZeroBased': [45, 76, 108]}}


def import_assets():
    verify_input()
    generated, variants = {}, []
    for args in VARIANTS:
        symbols, report = generate_variant(*args)
        generated.update(symbols)
        variants.append(report)
    manifest_path = HERE / 'native-manifest.json'
    prior = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else None
    prior_by_path = {x['path']: x['sha256'] for x in prior['outputs']} if prior else {}
    rows = []
    # Refuse to overwrite native work that has diverged from the prior import.
    for name, tree in generated.items():
        rel = 'LIBRARY/' + name + '.xml'
        path = OWNER / rel
        data = xml_bytes(tree)
        if path.exists() and path.read_bytes() != data and sha(path) != prior_by_path.get(rel):
            raise ValueError('Native source changed since import: ' + rel)
        rows.append({'path': rel, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    for name, tree in generated.items():
        path = OWNER / 'LIBRARY' / (name + '.xml')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(xml_bytes(tree))
    doc_path = OWNER / 'DOMDocument.xml'
    doc_text = doc_path.read_text(encoding='utf-8-sig')
    doc = E.fromstring(doc_text.encode('utf-8'), PARSER)
    includes = {e.get('href') for e in doc.findall('x:symbols/x:Include', NS)}
    additions = []
    for name in sorted(generated):
        if name + '.xml' not in includes:
            additions.append('    <Include href="' + name + '.xml" itemID="' + item_id(name) + '" loadImmediate="false"/>')
    if additions:
        assert doc_text.count('</symbols>') == 1
        doc_text = doc_text.replace('</symbols>', '\n'.join(additions) + '\n  </symbols>')
        doc_path.write_text(doc_text, encoding='utf-8')
    manifest = {'schema': 'gamma-echo.native-import.v1', 'owner': str(OWNER.relative_to(ROOT)),
                'approvedInput': str(ARCHIVE.relative_to(ROOT)), 'variants': variants, 'outputs': rows,
                'sourceNoahRootSha256': sha(NOAH / (SOURCE_ROOT + '.xml')),
                'aiSourceSha256': sha(HERE / 'GammaEchoAI.as'), 'deathSourceSha256': sha(HERE / 'death.py'), 'nativeSymbolCount': len(generated),
                'connectionSourceSha256': sha(HERE / 'connections.py'),
                'notes': ['26 native vector body parts; SVG clipping preserved by native mask layers',
                          'Noah attack/hit windows retained; original three death timelines restored with native wound parts and debris',
                          'No bitmaps; no existing enemy replacement; only two exported enemy linkages']}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'imported': len(generated), 'variants': 2, 'parts': 26}, ensure_ascii=False))


def check():
    manifest = json.loads((HERE / 'native-manifest.json').read_text(encoding='utf-8'))
    failures = []
    for entry in manifest['outputs']:
        path = OWNER / entry['path']
        root = E.parse(str(path), PARSER).getroot()
        if root.findall('.//x:DOMBitmapInstance', NS) or root.findall('.//x:BitmapFill', NS):
            failures.append(entry['path'] + ': bitmap found')
        for e in root.iter():
            ref = e.get('libraryItemName')
            if ref and not (OWNER / 'LIBRARY' / (ref + '.xml')).is_file():
                failures.append(entry['path'] + ': unresolved ' + ref)
    if failures:
        raise ValueError('\n'.join(failures))
    print(json.dumps({'nativeSymbolsChecked': len(manifest['outputs']), 'missingReferences': 0, 'bitmapInstances': 0}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--import-approved', action='store_true')
    args = parser.parse_args()
    if args.import_approved:
        import_assets()
    check()
