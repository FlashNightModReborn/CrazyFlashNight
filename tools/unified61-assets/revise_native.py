"""Fit native forearm joint overlap and adopt Titanium-61's masked detail icons."""
from pathlib import Path
import copy
import hashlib
import json
import sys
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
LIBRARY = OWNER / 'LIBRARY'
PREFIX = 'Codex/统合61式/'
X = 'http://ns.adobe.com/xfl/2008/'
NS = {'x': X}
PARSER = E.XMLParser(remove_blank_text=True, strip_cdata=False)


def node(tag, parent, **attrs):
    return E.SubElement(parent, '{%s}%s' % (X, tag), {k: str(v) for k, v in attrs.items()})


def layer(parent, name, **attrs):
    result = node('DOMLayer', parent, name=name, color='#4FFF4F', **attrs)
    return node('frames', result)


def frame(parent, index, elements=(), script=None):
    result = node('DOMFrame', parent, index=index, duration=1, keyMode=9728)
    if script:
        node('script', node('Actionscript', result)).text = E.CDATA(script)
    target = node('elements', result)
    for element in elements:
        target.append(copy.deepcopy(element))


def store(path, root):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(E.tostring(root, encoding='utf-8', pretty_print=True))


def png_bounds(manifest, key):
    skin = manifest['skinKeys'][key]
    image = skin['frames'][0]
    zoom = float(skin['export']['zoom'])
    return [-image['originX']/zoom, -image['originY']/zoom,
            (image['width']-image['originX'])/zoom, (image['height']-image['originY'])/zoom]


def icon_units(art, item, generated, geometry):
    """Lift wholly in-window aperture masks beside, rather than inside, the UI mask."""
    source_name = art.get('libraryItemName')
    source = E.parse(str(LIBRARY / (source_name + '.xml')), PARSER).getroot()
    source_layers = source.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)
    assert len(source_layers) == 1
    elements = source_layers[0].find('x:frames/x:DOMFrame[@index="0"]/x:elements', NS)
    matrix = geometry.matrix(art.find('x:matrix/x:Matrix', NS).attrib)
    masked = {}
    for element in elements:
        if E.QName(element).localname != 'DOMSymbolInstance':
            continue
        name = element.get('libraryItemName')
        child = E.parse(str(LIBRARY / (name + '.xml')), PARSER).getroot()
        if child.find('.//x:DOMLayer[@layerType="mask"]', NS) is not None:
            masked[name] = child
    if not masked:
        return [('window', art)]
    units, batch = [], []

    def flush():
        if not batch:
            return
        name = PREFIX + '图标分层/' + item + '-静态' + str(len(units))
        root = E.Element('{%s}DOMSymbolItem' % X, {'name': name, 'symbolType': 'graphic'}, nsmap={None: X})
        layers = node('layers', node('DOMTimeline', node('timeline', root), name=name.rsplit('/', 1)[-1]))
        frame(layer(layers, '闭合原生图形'), 0, batch)
        store(LIBRARY / (name + '.xml'), root)
        generated.append(name)
        instance = copy.deepcopy(art)
        instance.set('libraryItemName', name)
        units.append(('window', instance))
        batch.clear()

    for element in elements:
        name = element.get('libraryItemName')
        if name not in masked:
            batch.append(element)
            continue
        flush()
        child = masked[name]
        assert not child.findall('.//x:DOMSymbolInstance', NS), 'Deeper aperture needs explicit handling: ' + name
        own = element.find('x:matrix/x:Matrix', NS)
        combined = geometry.multiply(matrix, geometry.matrix(own.attrib) if own is not None else geometry.IDENTITY)
        contours = []
        reader = geometry.Geometry(LIBRARY)
        for mask in child.findall('.//x:DOMLayer[@layerType="mask"]//x:elements/*', NS):
            contours.extend(reader.element(mask, combined, ()))
        bounds = geometry.bounds(contours)
        assert bounds[0] >= -12 and bounds[1] >= -12 and bounds[2] <= 12 and bounds[3] <= 12, (name, bounds)
        instance = copy.deepcopy(element)
        transform = instance.find('x:matrix/x:Matrix', NS)
        for key, value in zip(('a', 'b', 'c', 'd', 'tx', 'ty'), combined):
            transform.set(key, f'{value:.9f}')
        units.append(('aperture', instance))
    flush()
    return units


def main():
    sys.path.insert(0, str(ROOT / 'tools/asset-metrology'))
    import xfl_geometry as geometry
    reference = geometry.Geometry(ROOT / 'flashswf/arts/things/LIBRARY')
    reports = []
    for gender in ('男', '女'):
        for side in ('左', '右'):
            name = gender + '变装-Codex-统合61式胸甲' + side + '下臂'
            donor = '0.防具相关/92&61套装/' + gender + '变装-钛合金61式胸甲' + side + '下臂'
            expected = geometry.bounds(reference.symbol(donor))
            measured = geometry.bounds(geometry.Geometry(LIBRARY).symbol(PREFIX + name))
            stretch = (expected[3]-expected[1])/(measured[3]-measured[1])
            offset = expected[1]-measured[1]*stretch
            path = LIBRARY / (PREFIX + name + '.xml')
            root = E.parse(str(path), PARSER).getroot()
            matrices = root.findall('.//x:DOMSymbolInstance/x:matrix/x:Matrix', NS)
            assert len(matrices) == 1
            matrix = matrices[0]
            # Preserve the exported registration point and transverse width.
            # Fit the artwork's elbow/wrist coverage inside that unchanged holder.
            for key, default in (('b', 0), ('d', 1)):
                matrix.set(key, f'{float(matrix.get(key, default))*stretch:.9f}')
            matrix.set('ty', f'{float(matrix.get("ty", 0))*stretch+offset:.9f}')
            store(path, root)
            actual = geometry.bounds(geometry.Geometry(LIBRARY).symbol(PREFIX + name))
            assert abs(actual[1]-expected[1]) < .001 and abs(actual[3]-expected[3]) < .001
            reports.append({'part': name, 'reference': donor, 'beforeBounds': measured,
                            'afterBounds': actual, 'targetBounds': expected})

    manifest = json.loads((ROOT / 'launcher/web/assets/dressup/manifest.json').read_text('utf-8'))
    shadow_root = E.parse(str(ROOT / 'flashswf/arts/things/LIBRARY/无AS链接/Symbol 16.xml'), PARSER)
    shadow = shadow_root.find('.//x:DOMShape', NS)
    assert shadow is not None
    parts = {'头部装甲': '头部装甲', '胸甲': '胸甲身体', '腿甲': '腿甲屁股', '手甲': '手甲右手', '装甲鞋': '装甲鞋'}
    generated = []
    for item, part in parts.items():
        reference_path = ROOT / ('flashswf/arts/things/LIBRARY/待整理防具相关汇总/图标-钛合金61式' + item + '.xml')
        donor = E.parse(str(reference_path), PARSER).getroot()
        art = donor.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer[@parentLayerIndex="0"]//x:DOMSymbolInstance', NS)
        assert art is not None
        art = copy.deepcopy(art)
        # Icons must not embed the runtime torso's independently ticking
        # closed/open/fire MovieClip. The native closed Graphic is authoritative.
        art.set('libraryItemName', PREFIX + '原生/男变装-Codex-统合61式' + part + '-closed')
        art.attrib.pop('name', None)
        matrix = art.find('x:matrix/x:Matrix', NS)
        old = png_bounds(manifest, '男变装-钛合金61式' + part)
        new = png_bounds(manifest, '男变装-Codex-统合61式' + part)
        scale = max(old[2]-old[0], old[3]-old[1])/max(new[2]-new[0], new[3]-new[1])
        a, b, c, d, tx, ty = (float(matrix.get(k, default)) for k, default in
                            zip(('a', 'b', 'c', 'd', 'tx', 'ty'), (1, 0, 0, 1, 0, 0)))
        ox, oy = (old[0]+old[2])/2, (old[1]+old[3])/2
        nx, ny = (new[0]+new[2])/2, (new[1]+new[3])/2
        values = (a*scale, b*scale, c*scale, d*scale,
                  a*ox+c*oy+tx-scale*(a*nx+c*ny), b*ox+d*oy+ty-scale*(b*nx+d*ny))
        for key, value in zip(('a', 'b', 'c', 'd', 'tx', 'ty'), values):
            matrix.set(key, f'{value:.9f}')
        path = LIBRARY / (PREFIX + '图标-Codex-统合61式' + item + '.xml')
        root = E.parse(str(path), PARSER).getroot()
        layers = root.find('x:timeline/x:DOMTimeline/x:layers', NS)
        layers.clear()
        script_frames = layer(layers, '静止图标与掉落')
        frame(script_frames, 0, script='stop();'); frame(script_frames, 1, script='stop();')
        # XFL layers are top-to-bottom; the source element list paints in the
        # opposite order. Each batch has its own 24-square mask, while source
        # aperture groups (proved wholly inside that square) stay at depth one.
        for index, (kind, element) in enumerate(reversed(icon_units(art, item, generated, geometry))):
            if kind == 'aperture':
                aperture_frames = layer(layers, '独立孔口' + str(index))
                frame(aperture_frames, 0, [element]); frame(aperture_frames, 1, [element])
            else:
                parent_index = len(layers)
                mask_frames = layer(layers, '24×24物品栏遮罩' + str(index), layerType='mask', locked='true')
                frame(mask_frames, 0, [shadow]); frame(mask_frames, 1, [shadow])
                detail_frames = layer(layers, '部件特写' + str(index), parentLayerIndex=parent_index, locked='true')
                frame(detail_frames, 0, [element]); frame(detail_frames, 1, [element])
        background_frames = layer(layers, '钛合金同源底影')
        frame(background_frames, 0, [shadow]); frame(background_frames, 1)
        store(path, root)
    document = OWNER / 'DOMDocument.xml'
    raw = document.read_bytes()
    text = raw.decode('utf-8-sig')
    includes = E.fromstring(raw).find('x:symbols', NS)
    known = {entry.get('href') for entry in includes}
    additions = [name + '.xml' for name in generated if name + '.xml' not in known]
    if additions:
        fragment = ''.join('    <Include href="' + name + '"/>\n' for name in additions)
        text = text.replace('</symbols>', fragment + '</symbols>', 1)
        document.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'') + text.encode('utf-8'))
    static_placements = 0
    for path in (LIBRARY / PREFIX / '总装').glob('*.xml'):
        root = E.parse(str(path), PARSER).getroot()
        for instance in root.findall('.//x:DOMSymbolInstance', NS):
            name = instance.get('libraryItemName')
            if name.startswith(PREFIX + '原生/'):
                continue
            if not name.startswith(PREFIX):
                raise ValueError('Foreign assembly reference: ' + name)
            wrapper = E.parse(str(LIBRARY / (name + '.xml')), PARSER).getroot()
            children = [element for element in wrapper.findall('.//x:DOMFrame[@index="0"]/x:elements/x:DOMSymbolInstance', NS)
                        if element.get('libraryItemName', '').startswith(PREFIX + '原生/')]
            assert len(children) == 1
            child = children[0]
            parent_matrix = instance.find('x:matrix/x:Matrix', NS)
            child_matrix = child.find('x:matrix/x:Matrix', NS)
            combined = geometry.multiply(geometry.matrix(parent_matrix.attrib), geometry.matrix(child_matrix.attrib))
            instance.set('libraryItemName', child.get('libraryItemName'))
            instance.set('symbolType', 'graphic')
            instance.set('loop', 'single frame')
            instance.set('firstFrame', '0')
            for key, value in zip(('a', 'b', 'c', 'd', 'tx', 'ty'), combined):
                parent_matrix.set(key, f'{value:.9f}')
            static_placements += 1
        store(path, root)
    out = ROOT / 'tmp/unified61-review/native-revision.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({'forearms': reports, 'icons': 5, 'generatedIconBatches': generated,
        'staticAssemblyPlacementsUpdated': static_placements,
        'firstFrame': '24x24 masked closed-state detail and native radial shadow',
        'secondFrame': 'identical masked item detail with only the radial background shadow removed',
        'changesToAnimationRig': False},
        ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'forearms': len(reports), 'icons': 5, 'rigUnchanged': True}))


if __name__ == '__main__':
    main()
