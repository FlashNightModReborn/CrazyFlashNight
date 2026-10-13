"""Import the approved D trousers into the owned Flash library.

The archived SVGs are the approved handoff, not a second live editing source.
Three parts retain the original native XFL edges with the approved fill palette;
the authored shin is imported as native quadratic paths and an open outline.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import xml.etree.ElementTree as SE
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'flashswf/arts/new/Codex素材源稿/Andy工装裤-D'
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
PREFIX = 'Codex/Andy工装裤/'
PARTS = ('屁股', '左大腿', '右大腿', '小腿')
X = 'http://ns.adobe.com/xfl/2008/'
NS = {'x': X}
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False)


def load_writer():
    path = ROOT / 'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py'
    spec = importlib.util.spec_from_file_location('andy_native_writer', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def node(tag, attrs=None, parent=None):
    element = E.Element('{%s}%s' % (X, tag), {key: str(value) for key, value in (attrs or {}).items()})
    if parent is not None:
        parent.append(element)
    return element


def layer(name, elements, index=0):
    result = node('DOMLayer', {'name': name, 'color': '#4FFF4F'})
    frame = node('DOMFrame', {'index': index, 'duration': 1, 'keyMode': 9728}, node('frames', parent=result))
    container = node('elements', parent=frame)
    for element in elements:
        container.append(element)
    return result


def instance(name, matrix=(1, 0, 0, 1, 0, 0)):
    attrs = {'libraryItemName': name}
    if not name.rsplit('/', 1)[-1].startswith(('男变装-', '图标-')):
        attrs.update(symbolType='graphic', loop='loop')
    result = node('DOMSymbolInstance', attrs)
    node('Matrix', dict(zip(('a', 'b', 'c', 'd', 'tx', 'ty'), (f'{value:.9f}' for value in matrix))), node('matrix', parent=result))
    node('Point', parent=node('transformationPoint', parent=result))
    return result


def symbol(name, layers, linkage=None):
    attrs = {'name': name}
    if linkage:
        attrs.update(linkageExportForAS='true', linkageExportInFirstFrame='true', linkageIdentifier=linkage)
    else:
        attrs['symbolType'] = 'graphic'
    result = E.Element('{%s}DOMSymbolItem' % X, attrs, nsmap={None: X})
    container = node('layers', parent=node('DOMTimeline', {'name': name.rsplit('/', 1)[-1]}, node('timeline', parent=result)))
    for element in layers:
        container.append(element)
    return result


def rename_source(root, name, linkage):
    root.set('name', name)
    for key in ('itemID', 'lastModified'):
        root.attrib.pop(key, None)
    root.set('linkageExportForAS', 'true')
    root.set('linkageExportInFirstFrame', 'true')
    root.set('linkageIdentifier', linkage)
    root.find('x:timeline/x:DOMTimeline', NS).set('name', name.rsplit('/', 1)[-1])


def make_symbols():
    generated = {}
    writer = load_writer()
    for part in PARTS:
        linkage = '男变装-Codex-Andy工装裤' + part
        name = PREFIX + linkage
        svg = SOURCE / (part + '.svg')
        if part != '小腿':
            root = E.parse(str(SOURCE / '原始XFL' / (part + '.xml')), PARSER).getroot()
            rename_source(root, name, linkage)
            fills = {element.get('data-fill'): element.get('fill') for element in SE.parse(svg).getroot().iter() if element.get('data-fill')}
            for fill in root.findall('.//x:FillStyle', NS):
                color = fills[fill.get('index')]
                fill.find('x:SolidColor', NS).set('color', color)
        else:
            native = writer.Writer(svg)
            shapes = []
            for element in native.walk(native.root):
                element.attrib.pop('isFloating', None)
                element.set('isDrawingObject', 'true')
                shapes.append(E.fromstring(SE.tostring(element)))
            root = symbol(name, [layer('D 原位布料与开放描边', shapes)], linkage)
        generated[name] = root

    # Ground frame uses the real empty-hand lower-body holder matrices, with
    # only the image registration removed (native paths already use local 0,0).
    holders = json.loads((SOURCE / '下身站姿矩阵.json').read_text('utf-8'))
    product = PREFIX + '完整裤子'
    body_layers = []
    for index, holder in enumerate(holders):
        matrix = tuple(holder['matrix'].get(key, 1 if key in ('a', 'd') else 0) for key in ('a', 'b', 'c', 'd', 'tx', 'ty'))
        body_layers.append(layer(str(index) + '_' + holder['field'], [instance(PREFIX + '男变装-Codex-Andy工装裤' + holder['field'], matrix)]))
    generated[product] = symbol(product, list(reversed(body_layers)))

    icon_name = PREFIX + '图标-Codex-Andy工装裤'
    template = OWNER / 'LIBRARY/Codex/重装特勤/图标-Codex-重装特勤战术裤.xml'
    icon = E.parse(str(template), PARSER).getroot()
    rename_source(icon, icon_name, '图标-Codex-Andy工装裤')
    layers = icon.find('x:timeline/x:DOMTimeline/x:layers', NS)
    art = next(item for item in layers if item.get('name') == '图标细节')
    display = art.find('.//x:DOMSymbolInstance', NS)
    display.set('libraryItemName', PREFIX + '男变装-Codex-Andy工装裤屁股')
    x, y, width, height = map(float, SE.parse(SOURCE / '屁股.svg').getroot().get('viewBox').split())
    scale = 23 / max(width, height)
    matrix = display.find('x:matrix/x:Matrix', NS)
    matrix.attrib.clear()
    matrix.attrib.update({key: f'{value:.9f}' for key, value in zip(('a', 'b', 'c', 'd', 'tx', 'ty'), (scale, 0, 0, scale, -(x + width / 2) * scale, -(y + height / 2) * scale))})
    ground = next(item for item in layers if item.get('name') == '底影与掉落')
    drop = ground.find('x:frames/x:DOMFrame[@index="1"]/x:elements/x:DOMSymbolInstance', NS)
    drop.set('libraryItemName', product)
    # Fit the union of the five native parts, including the original viewBox
    # padding. The screen rig is approximately quarter size, so no extra
    # character scale is applied before this explicit icon fit.
    corners = []
    for holder in holders:
        px, py, w, h = map(float, SE.parse(SOURCE / (holder['field'] + '.svg')).getroot().get('viewBox').split())
        m = holder['matrix']
        for u, v in ((px, py), (px + w, py), (px, py + h), (px + w, py + h)):
            corners.append((m['a'] * u + m['c'] * v + m['tx'], m['b'] * u + m['d'] * v + m['ty']))
    left, top = min(p[0] for p in corners), min(p[1] for p in corners)
    right, bottom = max(p[0] for p in corners), max(p[1] for p in corners)
    scale = min(0.5, 42 / max(right - left, bottom - top))
    drop.find('x:matrix/x:Matrix', NS).attrib.update({key: f'{value:.9f}' for key, value in zip(('a', 'b', 'c', 'd', 'tx', 'ty'), (scale, 0, 0, scale, -(left + right) * scale / 2, -bottom * scale))})
    generated[icon_name] = icon
    return generated


def write_xml(path, root):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = E.tostring(root, encoding='utf-8', pretty_print=True)
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def install(generated):
    for name, root in generated.items():
        write_xml(OWNER / 'LIBRARY' / (name + '.xml'), root)
    document_path = OWNER / 'DOMDocument.xml'
    document = E.parse(str(document_path), PARSER).getroot()
    symbols = document.find('x:symbols', NS)
    folders = document.find('x:folders', NS)
    includes = {element.get('href') for element in symbols}
    if PREFIX.rstrip('/') not in {element.get('name') for element in folders}:
        node('DOMFolderItem', {'name': PREFIX.rstrip('/'), 'isExpanded': 'false'}, folders)
    for name in sorted(generated):
        if name + '.xml' not in includes:
            node('Include', {'href': name + '.xml', 'loadImmediate': 'false'}, symbols)
    write_xml(document_path, document)
    anchor_path = OWNER / 'LIBRARY/Codex专用素材.xml'
    anchor = E.parse(str(anchor_path), PARSER).getroot()
    layers = anchor.find('x:timeline/x:DOMTimeline/x:layers', NS)
    for old in list(layers):
        if old.get('name') == 'Andy工装裤 D':
            layers.remove(old)
    layers.append(layer('Andy工装裤 D', [instance(name) for name in generated if generated[name].get('linkageIdentifier')]))
    write_xml(anchor_path, anchor)


def check():
    for part in PARTS:
        path = OWNER / 'LIBRARY' / (PREFIX + '男变装-Codex-Andy工装裤' + part + '.xml')
        root = E.parse(str(path), PARSER).getroot()
        assert root.get('linkageIdentifier') == '男变装-Codex-Andy工装裤' + part
        assert not root.findall('.//x:DOMBitmapInstance', NS)
        assert not root.findall('.//x:Matrix', NS), 'Part coordinates must remain native local coordinates'
        if part != '小腿':
            original = E.parse(str(SOURCE / '原始XFL' / (part + '.xml')), PARSER).getroot()
            edges = lambda tree: [dict(edge.attrib) for edge in tree.findall('.//x:Edge', NS)]
            assert edges(root) == edges(original), 'Native source edge geometry changed'
        else:
            strokes = root.findall('.//x:SolidStroke', NS)
            assert len(strokes) == 1 and float(strokes[0].get('weight')) == 1.7
            assert strokes[0].get('caps') == 'none' and strokes[0].get('joints') == 'round'
    donor = None
    adopted = None
    for item in E.parse(str(ROOT / 'data/items/防具_0-19级.xml'), PARSER).getroot().findall('item'):
        if item.findtext('name') == '白色中山装裤子':
            donor = item
        elif item.findtext('name') == 'Andy工装裤':
            adopted = item
    assert donor is not None and adopted is not None
    assert donor.findtext('price') == adopted.findtext('price')
    data = lambda item: {field.tag: field.text for field in item.find('data') if field.tag != 'dressup'}
    assert data(donor) == data(adopted), 'All runtime attributes must exactly match the white trousers'
    assert adopted.findtext('data/dressup') == '变装-Codex-Andy工装裤'
    print('PASS: four native vector parts, original geometry/registration, open shin outline, exact donor attributes.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--import-approved', action='store_true', help='Explicit one-time handoff import; edits the owned namespace only.')
    args = parser.parse_args()
    if args.import_approved:
        install(make_symbols())
    else:
        check()
