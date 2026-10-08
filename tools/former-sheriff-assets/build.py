"""Import the approved R26 sheriff art into the owned library and two NPC maps.

Sources stay outside the XFL. Rebuilding changes only our namespace and the four
visual references in each existing NPC animation; dialogue/interaction is kept.
"""
from pathlib import Path
import argparse, copy, hashlib, importlib.util, json, math, re, shutil
import xml.etree.ElementTree as SE
from lxml import etree as E
import numpy as np
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'flashswf/arts/new/Codex素材源稿/重装特勤-R26'
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
PREFIX = 'Codex/重装特勤/'
X = 'http://ns.adobe.com/xfl/2008/'
NS = {'x': X}
I = (1, 0, 0, 1, 0, 0)
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False)
GENERATED = {}
EXPORTS = {}
REPORT = {'source': 'approved R26', 'conversion': {}, 'npcFits': []}

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

writer = load('sheriff_xfl_writer', ROOT / 'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py')
reader = load('sheriff_xfl_reader', ROOT / 'tools/xfl-ui-svg/xfl_to_svg.py')

def node(tag, attrs=None, parent=None):
    result = E.Element('{%s}%s' % (X, tag), {k: str(v) for k, v in (attrs or {}).items()})
    if parent is not None:
        parent.append(result)
    return result

def frame(layer, index=0, duration=1, elements=(), script=None):
    frames = layer.find('x:frames', NS)
    if frames is None:
        frames = node('frames', parent=layer)
    f = node('DOMFrame', {'index': index, 'duration': duration, 'keyMode': 9728}, frames)
    if script:
        node('script', parent=node('Actionscript', parent=f)).text = E.CDATA(script)
    els = node('elements', parent=f)
    for el in elements:
        els.append(el)
    return f

def layer(name, elements=(), script=None):
    el = node('DOMLayer', {'name': name, 'color': '#4FFF4F'})
    frame(el, elements=elements, script=script)
    return el

def instance(name, matrix=I, clip=False, instance_name=None):
    attrs = {'libraryItemName': name, 'symbolType': 'movie clip' if clip else 'graphic'}
    if not clip:
        attrs['loop'] = 'loop'
    if instance_name:
        attrs['name'] = instance_name
    el = node('DOMSymbolInstance', attrs)
    node('Matrix', dict(zip(('a', 'b', 'c', 'd', 'tx', 'ty'), (f'{v:.9f}' for v in matrix))), node('matrix', parent=el))
    node('Point', parent=node('transformationPoint', parent=el))
    return el

def symbol(name, layers, export=None, clip=False):
    attrs = {'name': name}
    if not clip and not export:
        attrs['symbolType'] = 'graphic'
    if export:
        attrs.update(linkageExportForAS='true', linkageExportInFirstFrame='true', linkageIdentifier=export)
        EXPORTS[export] = name
    root = E.Element('{%s}DOMSymbolItem' % X, attrs, nsmap={None: X})
    container = node('layers', parent=node('DOMTimeline', {'name': name.rsplit('/', 1)[-1]}, node('timeline', parent=root)))
    for el in layers:
        container.append(el)
    GENERATED[name] = root
    return name

def alias(label, ref, matrix=I, export=None, clip=False):
    return symbol(PREFIX + label, [layer('原位美术', [instance(ref, matrix)])], export, clip)

def write_xml(path, root):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = E.tostring(root, encoding='utf-8', pretty_print=True)
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)

def native(svg, name, matrix=I):
    w = writer.Writer(svg)
    if name == '部件/头盔':
        shell = next(e for e in w.root if e.get('id') == 'worn-shell-fitted-to-head')
        seal = next(e for e in w.root if e.get('id') == 'neck-seal')
        seal[0].set('d', 'M-19 23 L-22 45 Q-10 54 10 50 L22 40 L21 21 Z')
        # Both basic faces fit the original narrow aperture when the shell
        # sits lower on the head. Keep its proportions and the neck registration
        # unchanged; model the adjustment as suspension/liner fit, not a larger
        # opening in the protective face plate.
        shell.set('transform', 'translate(59.6 -49.9) scale(-.72 .70)')
        lens = next(e for e in shell if e.get('id') == 'transparent-polycarbonate-visor')
        lip = SE.Element('{http://www.w3.org/2000/svg}path', {
            'id': 'inner-front-recess', 'fill': '#222427', 'stroke': 'none',
            'd': 'M25.160222 74 L39 71.1 Q39.6 83 46.5 90.2 L25.604222 90.3 Z'})
        shell.insert(list(shell).index(lens), lip)
        out = ROOT/'tmp/former-sheriff-integration'
        out.mkdir(parents=True, exist_ok=True)
        (out/'helmet-fitted-source.svg').write_bytes(SE.tostring(w.root))
        # R21 cut the visor out by partitioning the outer fill into adjacent
        # curved fragments. They are solid pieces, not nested holes. Classifying
        # all of them together as even-odd contours punches false gaps beside
        # the hinge after CS6 quantizes coordinates to twips. Preserve each
        # original fragment as a separate drawing object, with identical curves.
        base = shell[0]
        fragments = writer.parse_path(base.get('d'))
        group = SE.Element('{http://www.w3.org/2000/svg}g', {'id': 'separate-solid-aperture-fragments'})
        for start, segments, closed in fragments:
            part = copy.deepcopy(base)
            point = lambda p: ' '.join(f'{v:.9f}' for v in p)
            d = 'M' + point(start)
            d += ' '.join(s[0] + ' '.join(point(p) for p in s[1:]) for s in segments)
            part.set('d', d + (' Z' if closed else ''))
            group.append(part)
        shell.remove(base)
        shell.insert(0, group)
    shapes = [E.fromstring(SE.tostring(s)) for s in w.walk(w.root, parent_matrix=matrix)]
    if name == '部件/头盔':
        for shape in shapes:
            shape.attrib.pop('isFloating', None)
            shape.set('isDrawingObject', 'true')
    REPORT['conversion'][name] = {'shapes': len(shapes), 'segments': w.segment_count}
    return symbol(PREFIX + name, [layer('R26 原生矢量', shapes)])

def append_to_document(rootdir, names):
    docpath = rootdir / 'DOMDocument.xml'
    doc = E.parse(str(docpath), PARSER).getroot()
    symbols = doc.find('x:symbols', NS)
    folders = doc.find('x:folders', NS)
    if folders is None:
        folders = node('folders', parent=doc)
    present = {e.get('href') for e in symbols}
    present_folders = {e.get('name') for e in folders}
    for name in sorted(names):
        if name + '.xml' not in present:
            node('Include', {'href': name + '.xml', 'loadImmediate': 'false'}, symbols)
        bits = name.split('/')[:-1]
        for i in range(1, len(bits) + 1):
            folder = '/'.join(bits[:i])
            if folder not in present_folders:
                node('DOMFolderItem', {'name': folder, 'isExpanded': 'false'}, folders)
                present_folders.add(folder)
    write_xml(docpath, doc)

def archive(source, registration, adapter):
    SOURCE.mkdir(parents=True, exist_ok=True)
    parts = json.loads((source / 'clothing-manifest.json').read_text('utf8'))
    names = {p['file'] for p in parts.values()} | {
        '01-tonfa', '02-riot-helmet', '03-xm1014', '04b-hair-and-goatee-layers',
        '06-head-collar-fit', '09-combat-helmet-registered', '09b-combat-helmet-inner-liner',
        '16-tonfa-melee-registered', '17-cutting-blade', '18-cutting-blade-registered',
        '30-full-body-shield', '07c-desert-eagle-modified-duty'}
    for name in sorted(names):
        shutil.copy2(source / (name + '.svg'), SOURCE / (name + '.svg'))
    for filename in ['clothing-manifest.json', 'pistol-source.json']:
        shutil.copy2(source / filename, SOURCE / filename)
    shutil.copy2(registration, SOURCE / 'npc-registration.json')
    shutil.copy2(adapter, SOURCE / 'clipped-contour-normalization.py')
    shutil.copytree(source / 'references/modified-desert-eagle-native/LIBRARY', SOURCE / 'pistol-native', dirs_exist_ok=True)
    # The archive is a source snapshot, never a second publishable XFL library.
    hashes = {p.relative_to(SOURCE).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(SOURCE.rglob('*')) if p.is_file() and p.name != 'source-hashes.json'}
    (SOURCE / 'source-hashes.json').write_text(json.dumps(hashes, ensure_ascii=False, indent=2), 'utf8')

def make_parts():
    adapter = load('sheriff_contour_adapter', SOURCE / 'clipped-contour-normalization.py')
    adapter.writer = writer
    writer.normalize = adapter.stable_normalize
    parts = json.loads((SOURCE / 'clothing-manifest.json').read_text('utf8'))
    refs = {key: native(SOURCE / (data['file'] + '.svg'), '部件/' + key) for key, data in parts.items()}
    for key, filename in {
        'NPC头部': '06-head-collar-fit', '持物头盔': '02-riot-helmet', 'NPC警棍': '01-tonfa',
        '原霰弹枪': '03-xm1014', '头盔': '09-combat-helmet-registered',
        '警棍': '16-tonfa-melee-registered'}.items():
        refs[key] = native(SOURCE / (filename + '.svg'), '部件/' + key)
    hair_m = (.67137922, .09465859, -.09465859, .67137922, -23.80104562, -56.36642239)
    refs['发型'] = native(SOURCE / '04b-hair-and-goatee-layers.svg', '部件/短发及胡须', hair_m)
    alias('发型-男式-Codex-治安官', refs['发型'], export='发型-男式-Codex-治安官')
    for gender in ['男', '女']:
        for field in ['身体', '上臂', '左下臂', '右下臂', '屁股', '左大腿', '右大腿', '小腿']:
            key = gender + '变装-Codex-重装特勤' + field
            alias(key, refs[field], export=key)
    for field in ['左手', '右手']:
        key = '变装-Codex-重装特勤' + field
        alias(key, refs[field], export=key)
    alias('变装-Codex-重装特勤头盔', refs['头盔'], export='变装-Codex-重装特勤头盔')
    alias('变装-Codex-重装特勤战靴', refs['脚'], export='变装-Codex-重装特勤战靴')
    return refs

def pistol():
    src = SOURCE / 'pistol-native'
    rootname = '2副武器/沙鹰战术/Symbol 3799'
    mapping = {}
    def visit(old):
        if old in mapping:
            return mapping[old]
        new = PREFIX + '沙鹰原生/' + old.rsplit('/', 1)[-1]
        # Include the parent folder in case original symbol basenames collide.
        new = PREFIX + '沙鹰原生/' + old.split('沙鹰战术/', 1)[-1]
        mapping[old] = new
        root = E.parse(str(src / (old + '.xml')), PARSER).getroot()
        root.set('name', new)
        for k in list(root.attrib):
            if k.startswith('linkage') or k in ['itemID', 'lastModified', 'lastUniqueIdentifier']:
                del root.attrib[k]
        root.set('symbolType', 'graphic')
        for e in list(root.iter()):
            if e.get('libraryItemName'):
                oldref = e.get('libraryItemName')
                if oldref.endswith('/元件 1'):
                    e.getparent().remove(e)  # conditional laser is a deferred feature
                else:
                    e.set('libraryItemName', visit(oldref))
                    if e.get('name') == '枪口位置':
                        e.getparent().remove(e)  # weapon wrapper owns this interface
            color = e.get('color', '')
            if re.fullmatch(r'#[0-9A-Fa-f]{6}', color):
                rgb = [int(color[i:i+2], 16) for i in (1, 3, 5)]
                avg = sum(rgb) / 3
                if max(rgb) - min(rgb) <= 24 and avg >= 24:
                    grey = round(24 + (avg - 24) * .40)
                    e.set('color', '#%02x%02x%02x' % (grey, grey + 2, grey + 3))
        GENERATED[new] = root
        return new
    return visit(rootname)

def weapons(refs):
    marker_src = ROOT / 'flashswf/arts/things切割/LIBRARY/判定使用.xml'
    root = E.parse(str(marker_src), PARSER).getroot()
    name = PREFIX + '接口/透明判定'
    root.set('name', name)
    for k in list(root.attrib):
        if k.startswith('linkage') or k in ['itemID', 'lastModified']:
            del root.attrib[k]
    GENERATED[name] = root
    refs['沙鹰'] = pistol()
    refs['霰弹枪'] = alias('部件/已注册霰弹枪', refs['原霰弹枪'], (1, 0, 0, 1, -101.65, -48.75))
    # Reuse the authored tactical XM1014 beam (gradient, additive blend, blur).
    # Our approved R26 art already contains a lamp; its lens is (356.9, 41)
    # before the weapon registration offset, independent of the muzzle.
    beam_name = PREFIX + '武器/特勤手电光束'
    beam = E.parse(str(ROOT/'flashswf/arts/things/LIBRARY/无AS链接/Symbol 4024.xml'), PARSER).getroot()
    beam.set('name', beam_name)
    for k in ('itemID', 'lastModified'):
        beam.attrib.pop(k, None)
    beam.find('x:timeline/x:DOMTimeline', NS).set('name', '特勤手电光束')
    GENERATED[beam_name] = beam
    for key, export, muzzle in [
        ('沙鹰', '枪-手枪-Codex-特勤沙鹰', (138.4, -34.05)),
        ('霰弹枪', '枪-长枪-Codex-特勤霰弹枪', (297.15, -33.9))]:
        anim = alias('武器/' + key + '静态动画', refs[key], clip=True)
        interfaces = [instance(name, (1, 0, 0, 1, *muzzle), True, '枪口位置')]
        layers = [layer('接口', interfaces), layer('美术', [instance(anim, clip=True, instance_name='动画')])]
        if key == '霰弹枪':
            interfaces.append(instance(name, (1, 0, 0, 1, 255.25, -7.75), True, '手电口'))
            # The layer copied the earlier list, so append the new port explicitly.
            layers[0].find('x:frames/x:DOMFrame/x:elements', NS).append(interfaces[-1])
            donor = E.parse(str(ROOT/'flashswf/arts/things/LIBRARY/1.枪械相关/长枪/XM1014战术版/枪-长枪-XM1014战术版.xml'), PARSER)
            light = copy.deepcopy(donor.find('.//x:DOMSymbolInstance[@name="装备光束"]', NS))
            light.set('libraryItemName', beam_name)
            light.attrib.pop('centerPoint3DX', None)
            light.attrib.pop('centerPoint3DY', None)
            light.find('x:matrix/x:Matrix', NS).attrib.update({'tx': '255.25', 'ty': '-10.75'})
            layers.append(layer('持枪照明', [light]))
        symbol(PREFIX + export, layers, export)
    # Three transparent collision boxes follow the shaft in the approved grip registration.
    markers = [instance(name, (.72, 0, 0, 2.64, -9, y), True, '刀口位置' + str(i + 1))
               for i, y in enumerate((-27, 39, 105))]
    motion_source = ROOT / 'flashswf/arts/new/Codex素材源稿/重装特勤-Q变形'
    motion = json.loads((motion_source / 'manifest.json').read_text('utf8'))
    assert motion['frameCount'] == 31
    samples = [0,2,4,6,9,11,13,15,17,19,21,24,26,28,30]
    count = len(samples)
    artwork = node('DOMLayer', {'name': 'Q变形 / 固定握点侧柄折回', 'color': '#4FFF4F'})
    for i, entry in enumerate(motion['files']):
        source = motion_source / entry['file']
        assert hashlib.sha256(source.read_bytes()).hexdigest() == entry['sha256']
        part = native(source, '武器/警棍变形/帧%02d' % i)
        if i in samples:
            frame(artwork, index=samples.index(i), elements=[instance(part)])
    collisions = layer('原短兵判定接口', markers)
    collisions.find('x:frames/x:DOMFrame', NS).set('duration', str(count))
    stop = layer('停止 / 外部生命周期按Q驱动', script='stop();')
    stop.find('x:frames/x:DOMFrame', NS).set('duration', str(count))
    symbol(PREFIX + '刀-Codex-特勤警棍', [stop, collisions, artwork], '刀-Codex-特勤警棍')
    REPORT['batonTransformation'] = {'frames': count, 'key': 'configured weapon transform key',
        'source': motion_source.relative_to(ROOT).as_posix(), 'hitboxes': 3}

def icons(refs):
    source = ROOT / 'flashswf/arts/things/LIBRARY/无AS链接/Symbol 16.xml'
    shade = E.parse(str(source), PARSER).getroot()
    shade_name = PREFIX + '图标部件/底影'
    shade.set('name', shade_name)
    shade.attrib.pop('itemID', None)
    GENERATED[shade_name] = shade
    icon_refs = {
        '重装特勤头盔': (refs['头盔'], (-43, -68, 76, 69)),
        '重装特勤背心': (refs['身体'], (-76, -115, 148, 231)),
        '重装特勤手套': (refs['右手'], (-39, -26, 77, 54)),
        '重装特勤战术裤': (refs['屁股'], (-75, -65, 145, 126)),
        '重装特勤战靴': (refs['脚'], (-30, -30, 82, 59)),
        '特勤警棍': (refs['警棍'], (-10, -27, 53, 180)),
        '特勤霰弹枪': (refs['霰弹枪'], (-102, -49, 427, 96)),
        '特勤沙鹰': (refs['沙鹰'], (-36, -44, 198, 102))}
    # Bounds from the actual native shapes, excluding invisible interfaces.
    scratch = ROOT / 'tmp/former-sheriff-native-icons/LIBRARY'
    for name, root in GENERATED.items():
        write_xml(scratch / (name + '.xml'), root)
    rend = reader.Renderer(scratch, [])
    for item, (ref, fallback) in icon_refs.items():
        bounds = rend.symbol_bbox(ref)
        if bounds:
            x, y, right, bottom = bounds
            w, h = right-x, bottom-y
        else:
            x, y, w, h = fallback
        if item == '特勤霰弹枪':
            m = (.16, -.16, .16, .16, -1, 9)
        elif item == '特勤警棍':
            m = (.55, 0, 0, .55, -5, -6)
        else:
            s = 23 / max(w, h)
            m = (s, 0, 0, s, -(x+w/2)*s, -(y+h/2)*s)
        scripts = layer('停止', script='stop();')
        scripts.find('x:frames/x:DOMFrame', NS).set('duration', '2')
        mask = layer('24 像素裁切', [instance(shade_name)])
        mask.set('layerType', 'mask'); mask.set('locked', 'true')
        art = layer('图标细节', [instance(ref, m)])
        art.set('parentLayerIndex', '1'); art.set('locked', 'true')
        shadow = layer('底影与掉落', [instance(shade_name)])
        ground_scale = min(.33, 70 / max(w, h))
        frame(shadow, 1, elements=[instance(ref, (ground_scale, 0, 0, ground_scale, -(x+w/2)*ground_scale, -(y+h)*ground_scale))])
        symbol(PREFIX + '图标-Codex-' + item, [scripts, mask, art, shadow], '图标-Codex-' + item)

def point_cloud(elements):
    points = []
    for e in elements.iter():
        if e.tag.endswith('}Edge') and e.get('edges'):
            for segment in reader.edge_segments(e.get('edges')):
                # The native reader returns (start, ..., endpoint), in pixels.
                for value in segment:
                    if isinstance(value, (tuple, list)) and len(value) == 2:
                        points.append(value)
    return np.array(points, dtype=float)

def pose_delta(base, target):
    a, b = point_cloud(base), point_cloud(target)
    if len(a) == 0 or len(b) == 0:
        return I, 0
    # Native contours can reorder edges between poses; never pair by index.
    # These four poses translate the existing layers for breathing. Preserve
    # that motion without introducing an estimated stretch into new armour.
    shift = (b.min(axis=0)+b.max(axis=0)-a.min(axis=0)-a.max(axis=0))/2
    tree = cKDTree(b)
    for _ in range(12):
        distances, ix = tree.query(a+shift)
        keep = distances <= np.quantile(distances, .75)
        shift = np.median(b[ix[keep]]-a[keep], axis=0)
    params = np.array([[1., 0.], [0., 1.], shift])
    residual = tree.query(a+shift)[0]
    m = tuple(params.flatten()[[0, 1, 2, 3, 4, 5]])
    # Reject distorted fits; the source is a small breathing motion.
    if max(abs(m[0]-1), abs(m[3]-1), abs(m[1]), abs(m[2])) > .15:
        raise ValueError('NPC pose fit changes geometry unexpectedly: ' + str(m))
    error = float(np.quantile(residual, .9))
    if error > 1.0:
        raise ValueError('NPC breathing fit residual exceeds one pixel: ' + str(error))
    return m, error

def npcs(refs):
    maps = ['基地场景合集', '地图-第一防线防区']
    maproot = ROOT / 'flashswf/levels' / maps[0]
    originals = ['shape/Symbol 1626'] + ['NPC/前治安官/图形/Symbol ' + str(n) for n in (2700, 2701, 2702)]
    fits = json.loads((SOURCE / 'npc-registration.json').read_text('utf8'))
    special = {2: ('NPC头部', (1, 0, 0, 1, -56.2, -262.2)),
               3: ('持物头盔', (-.76, 0, 0, .76, -61, -164)),
               9: ('原霰弹枪', (0, -1, 1, 0, 117.475, 265.25)),
               12: ('NPC警棍', (-.75, 0, 0, .75, -103, -102))}
    def source_layers(name):
        root = E.parse(str(maproot / 'LIBRARY' / (name + '.xml')), PARSER).getroot()
        return {int(re.search(r'(\d+)$', l.get('name')).group(1)): l for l in root.findall('.//x:DOMLayer', NS)}
    base = source_layers(originals[0])
    pose_names = []
    for pose, old in enumerate(originals):
        src = source_layers(old)
        layers = []
        for number in range(1, 27):
            if number in [1, 4, 15, 18, 24, 25]:
                continue
            delta, error = (I, 0) if pose == 0 else pose_delta(base[number], src[number])
            REPORT['npcFits'].append({'pose': pose, 'layer': number, 'matrix': delta, 'p90': error})
            if number in special:
                key, transform = special[number]
                elements = [instance(refs[key], writer.mul(delta, transform))]
            elif str(number) in fits:
                fit = fits[str(number)]
                elements = [instance(refs[fit['field']], writer.mul(delta, fit['matrix']))]
            else:
                elements = [copy.deepcopy(x) for x in src[number].find('x:frames/x:DOMFrame/x:elements', NS)]
            layers.append(layer('原层 ' + str(number), elements))
        # Existing NPC secondary sidearm position, behind the protective equipment.
        layers.insert(len(layers)-1, layer('深色特勤沙鹰', [instance(refs['沙鹰'], (0, 1, -1, 0, -32.4, -54.4))]))
        pose_names.append(symbol(PREFIX + 'NPC/呼吸姿态' + str(pose), layers))
    def closure(seeds):
        pending = list(seeds); found = set()
        while pending:
            name = pending.pop()
            if name in found:
                continue
            found.add(name)
            pending.extend(e.get('libraryItemName') for e in GENERATED[name].iter() if e.get('libraryItemName'))
        return found
    names = closure(pose_names)
    for mapname in maps:
        target = ROOT / 'flashswf/levels' / mapname
        for name in names:
            root = copy.deepcopy(GENERATED[name])
            for key in list(root.attrib):
                if key.startswith('linkage'):
                    del root.attrib[key]
            write_xml(target / 'LIBRARY' / (name + '.xml'), root)
        append_to_document(target, names)
        path = target / 'LIBRARY/NPC/前治安官/图形/Symbol 2703.xml'
        root = E.parse(str(path), PARSER).getroot()
        frames = root.findall('.//x:DOMFrame', NS)
        assert [(int(f.get('index')), int(f.get('duration'))) for f in frames] == [(0, 24), (24, 11), (35, 11), (46, 13)]
        for f, name in zip(frames, pose_names):
            f.find('x:elements/x:DOMSymbolInstance', NS).set('libraryItemName', name)
        write_xml(path, root)
    REPORT['npcSymbols'] = pose_names
    REPORT['mapDependencies'] = len(names)

def finish():
    for name, root in GENERATED.items():
        write_xml(OWNER / 'LIBRARY' / (name + '.xml'), root)
    append_to_document(OWNER, GENERATED)
    anchor_path = OWNER / 'LIBRARY/Codex专用素材.xml'
    anchor = E.parse(str(anchor_path), PARSER).getroot()
    layers = anchor.find('.//x:layers', NS)
    for old in list(layers):
        if old.get('name') == '重装特勤 R26':
            layers.remove(old)
    layers.append(layer('重装特勤 R26', [instance(name, clip=True) for name in EXPORTS.values()]))
    write_xml(anchor_path, anchor)
    REPORT['exports'] = EXPORTS
    REPORT['generatedSymbols'] = len(GENERATED)
    out = ROOT / 'tmp/former-sheriff-integration'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'build-report.json').write_text(json.dumps(REPORT, ensure_ascii=False, indent=2), 'utf8')
    print(json.dumps({'symbols': len(GENERATED), 'exports': len(EXPORTS), 'mapDependencies': REPORT['mapDependencies']}, ensure_ascii=False))

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', type=Path)
    ap.add_argument('--registration', type=Path)
    ap.add_argument('--contour-adapter', type=Path)
    args = ap.parse_args()
    if args.source:
        assert args.registration and args.contour_adapter
        archive(args.source, args.registration, args.contour_adapter)
    refs = make_parts()
    weapons(refs)
    icons(refs)
    npcs(refs)
    finish()
