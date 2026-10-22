"""CF6 Manman R2 art on the CF7 undead-orc rig, with unit-private combat control."""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import struct
import sys
import zipfile
import zlib
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6蛮蛮-R2'
OWNER = ROOT / 'flashswf/arts/new/Codex蛮蛮素材'
ANCHOR = 'Codex蛮蛮素材'
LINKAGE = '敌人-CF6蛮蛮'
PREFIX = 'Codex/蛮蛮/'
DONOR = ROOT / 'flashswf/arts/things7.fla'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{' + NS['x'] + '}'
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False, resolve_entities=False)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


audio = module('cf6_audio_native',ROOT/'tools/cf6-audio/build.py')
native = module('manman_native', ROOT / 'tools/cf6-zombie-assets/build.py')
vector = module('manman_vector', ROOT / 'tools/gamma-echo-assets/build.py')
native.OWNER = OWNER
native.HERE = HERE
native.MANIFEST_SCHEMA = 'cf6-manman.native-import.v1'
native.PROJECT_FILES = ('DOMDocument.xml', ANCHOR + '.xfl', 'PublishSettings.xml', 'MobileSettings.xml')

PART_MAP = {1097: 632, 1098: 633, 1099: 634, 1100: 635, 1101: 636, 1102: 637,
            1103: 638, 1104: 639, 1106: 640, 1107: 642, 1108: 643, 1109: 646}
ATTACKS = {'Symbol 1116': 'advance', 'Symbol 1117': 'cleave'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_inputs():
    paths = [HERE / 'build.py', HERE / 'ManmanAI.as', HERE / 'wolf_leap.py',
        ROOT / 'flashswf/arts/things0/LIBRARY/容器/战技容器/战技容器-狼跳.xml',
        ROOT / 'tools/cf6-zombie-assets/build.py', ROOT / 'tools/gamma-echo-assets/build.py',
        ROOT / 'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
        ROOT / 'tools/asset-metrology/xfl_geometry.py',
        ROOT / 'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml']
    return [{'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p)} for p in paths]


def read_fla_members(path):
    """Read and CRC-check local ZIP records; the donor's central directory is legacy-invalid."""
    raw = path.read_bytes()
    result = {}
    pos = 0
    while pos < len(raw) - 30:
        pos = raw.find(b'PK\x03\x04', pos)
        if pos < 0:
            break
        flags, method = struct.unpack_from('<HH', raw, pos + 6)
        crc, size, usize = struct.unpack_from('<III', raw, pos + 14)
        nlen, xlen = struct.unpack_from('<HH', raw, pos + 26)
        name = raw[pos + 30:pos + 30 + nlen].decode('utf-8')
        start = pos + 30 + nlen + xlen
        if method == 8:
            dec = zlib.decompressobj(-15)
            compressed = raw[start:start + size] if size else raw[start:]
            data = dec.decompress(compressed)
            if not dec.eof:
                raise ValueError('Truncated donor entry: ' + name)
            consumed = len(compressed) - len(dec.unused_data)
        elif method == 0 and not flags & 8:
            data, consumed = raw[start:start + size], size
        else:
            raise ValueError('Unsupported donor ZIP entry: ' + name)
        pos = start + consumed
        if flags & 8:
            descriptor = pos + (4 if raw[pos:pos + 4] == b'PK\x07\x08' else 0)
            crc, size, usize = struct.unpack_from('<III', raw, descriptor)
            pos = descriptor + 12
        if consumed != size or len(data) != usize or zlib.crc32(data) & 0xffffffff != crc:
            raise ValueError('Donor entry integrity mismatch: ' + name)
        if name in result and result[name] != data:
            raise ValueError('Conflicting duplicate donor member: ' + name)
        result[name] = data
    return result


def verify_input():
    origin = json.loads((ARCHIVE / 'archive-origin.json').read_text(encoding='utf-8'))
    for row in origin['members']:
        if sha(ARCHIVE / row['path']) != row['sha256']:
            raise ValueError('Frozen input changed: ' + row['path'])


def clipped_timeline(root, count):
    for frames in root.findall('.//x:frames', NS):
        for fr in list(frames):
            start = int(fr.get('index', '0'))
            if start >= count:
                frames.remove(fr)
            elif start + int(fr.get('duration', '1')) > count:
                fr.set('duration', str(count - start))


def event_script(instance, script):
    for old in instance.findall('x:Actionscript', NS):
        instance.remove(old)
    E.SubElement(E.SubElement(instance, N + 'Actionscript'), N + 'script').text = E.CDATA(script)


def align_death_to_cf7(timelines, docs, donor_root):
    """Undo CF6's baked death scale and align the pelvis to the CF7 standing pose."""
    source_stand = next(row for row in timelines['692'][0].values() if row['id'] == 647)['matrix']
    if source_stand[0] <= 0 or source_stand[0] != source_stand[3] or source_stand[1:3] != [0, 0]:
        raise ValueError('Expected a uniform CF6 standing scale')
    scale = 1 / source_stand[0]
    root_instance = docs[donor_root][1].find('.//x:DOMFrame[@index="0"]/x:elements/x:DOMSymbolInstance[@name="man"]', NS)
    root_matrix = root_instance.find('x:matrix/x:Matrix', NS)
    if any(float(root_matrix.get(key, default)) != default for key, default in [('a', 1), ('b', 0), ('c', 0), ('d', 1)]):
        raise ValueError('CF7 standing placement changed; review death-space conversion')
    standing = docs[root_instance.get('libraryItemName')][1]
    pelvis = standing.find('.//x:DOMFrame[@index="0"]/x:elements/x:DOMSymbolInstance[@libraryItemName="Symbol 1104"]/x:matrix/x:Matrix', NS)
    source_pelvis = next(row['matrix'] for row in timelines['691'][0].values() if row['id'] == 639)
    tx = float(root_matrix.get('tx', '0')) + float(pelvis.get('tx', '0')) - scale * source_pelvis[4]
    ty = float(root_matrix.get('ty', '0')) + float(pelvis.get('ty', '0')) - scale * source_pelvis[5]
    return (scale, 0, 0, scale, tx, ty)


def build_symbols():
    verify_input()
    members = read_fla_members(DONOR)
    docs = {}
    for name, data in members.items():
        if name.startswith('LIBRARY/') and name.endswith('.xml'):
            root = E.fromstring(data, PARSER)
            if root.tag == N + 'DOMSymbolItem':
                docs[root.get('name')] = (name, root)
    donor_root = next(name for name, (_, root) in docs.items() if root.get('linkageIdentifier') == '敌人-不死兽人')
    mapped = {'Symbol ' + str(old): PREFIX + '分件/' + str(cid) for old, cid in PART_MAP.items()}
    generated = {}
    for cid in PART_MAP.values():
        syms, _ = vector.NativePart(ARCHIVE / 'parts' / f'{cid}.svg', PREFIX + '分件/' + str(cid), (0, 0)).build()
        generated.update(syms)
    for cid in range(660, 691):
        syms, _ = vector.NativePart(ARCHIVE / 'death-effects' / f'{cid}.svg', PREFIX + '死亡血肉/' + str(cid), (0, 0)).build()
        generated.update(syms)

    root_name = PREFIX + LINKAGE
    death_name = PREFIX + '动作/血腥死'
    mapped[donor_root] = root_name
    mapped['Symbol 1153'] = death_name
    replacement_names = set(mapped) - {donor_root}
    timelines = json.loads((ARCHIVE / 'reference/timelines.json').read_text(encoding='utf-8'))
    death_matrix = align_death_to_cf7(timelines, docs, donor_root)
    parts = {cid: PREFIX + '分件/' + str(cid) for cid in PART_MAP.values()}
    parts.update({cid: PREFIX + '死亡血肉/' + str(cid) for cid in range(660, 691)})
    death_layers = [native.make_sparse_layer('结束回调', 88, {
        0: {'name': 'a0', 'label_type': 'name'},
        87: {'script': '_parent.死亡检测();\nstop();\n'},
    }), *native.build_depth_layers(timelines['691'], parts)]
    generated[death_name] = native.symbol(death_name, death_layers, symbol_type='movie clip')

    pending = [donor_root]
    copied = {}
    source_rows = []
    while pending:
        old_name = pending.pop()
        if old_name in copied or old_name in replacement_names:
            continue
        filename, original = docs[old_name]
        root = copy.deepcopy(original)
        copied[old_name] = root
        source_rows.append({'member': filename, 'sha256': hashlib.sha256(members[filename]).hexdigest()})
        if old_name == 'Symbol 1116':
            # Only a0 is reachable on the undead-orc reference; do not enable its stale firearm branches.
            clipped_timeline(root, 33)
        # This added groin plate belongs to CF7's old skin, not the approved CF6 drawing.
        for inst in root.findall('.//x:DOMSymbolInstance[@libraryItemName="Symbol 1105"]', NS):
            inst.getparent().remove(inst)
        for inst in root.findall('.//x:DOMSymbolInstance', NS):
            ref = inst.get('libraryItemName')
            if ref not in mapped:
                mapped[ref] = PREFIX + 'CF7/' + ref
            if ref != 'Symbol 1153' and mapped[ref] not in generated:
                pending.append(ref)

    # All names are known before rewriting the copied tree.
    ai = (HERE / 'ManmanAI.as').read_text(encoding='utf-8-sig')
    for old_name, root in copied.items():
        name = mapped.get(old_name, PREFIX + 'CF7/' + old_name)
        root.set('name', name)
        root.set('itemID', native.item_id(name))
        for key in list(root.attrib):
            if key.startswith('linkage') or key in ('lastModified', 'lastUniqueIdentifier'):
                root.attrib.pop(key)
        root.find('x:timeline/x:DOMTimeline', NS).set('name', name.rsplit('/', 1)[-1])
        for inst in root.findall('.//x:DOMSymbolInstance', NS):
            inst.set('libraryItemName', mapped[inst.get('libraryItemName')])
        if old_name in ATTACKS:
            for script in root.findall('.//x:script', NS):
                text = script.text or ''
                if '子弹威力' in text:
                    inner = text[text.index('{') + 1:text.rfind('}')]
                    endpoint = '击倒率,击中后子弹的效果);'
                    if inner.count(endpoint) != 1:
                        raise ValueError('Unexpected donor melee emission signature')
                    inner = inner.replace(endpoint, '击倒率,击中后子弹的效果,undefined,undefined,undefined,undefined,undefined,_parent._parent.manmanCrumblePercent);')
                    script.text = E.CDATA('onClipEvent(load){\nif(_parent._parent.manmanCanHit(_parent.manmanToken)) {\n_parent._parent.manmanHitCount++;\n' + inner + '\n}\n}\n')
                elif 'function 攻击时移动' in text:
                    script.text = E.CDATA('function 攻击时移动(慢速度, 快速度) {\n'
                        'if(_parent.manmanCanHit(manmanToken) && !_parent.硬直中) _parent.移动(_parent.方向, 慢速度);\n}\n'
                        + ('gotoAndPlay("a0");\n' if old_name == 'Symbol 1116' else ''))
                elif '_parent.动画完毕()' in text:
                    script.text = E.CDATA('_parent.manmanAnimationDone(this);\n')
        if old_name == 'Symbol 1120':
            for frame in root.findall('.//x:DOMFrame', NS):
                for script in frame.findall('x:Actionscript/x:script', NS):
                    idx = int(frame.get('index'))
                    script.text = E.CDATA('_parent.死亡检测();\n' if idx in (13, 17) else '_parent.动画完毕();\n')
        if old_name == donor_root:
            root.set('linkageExportForAS', 'true')
            root.set('linkageExportInFirstFrame', 'true')
            root.set('linkageIdentifier', LINKAGE)
            init = root.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer[@name="Script Layer"]/x:frames/x:DOMFrame[@index="0"]/x:Actionscript/x:script', NS)
            init.text = E.CDATA(init.text + '\n' + ai)
            for inst in root.findall('.//x:DOMSymbolInstance', NS):
                ref = inst.get('libraryItemName')
                if ref == mapped['Symbol 377']:
                    # Sensor stays as a geometric envelope; this unit's driver owns the decision.
                    inst.set('name', 'manmanSensor')
                    event_script(inst, 'onClipEvent(load){ stop(); this._visible=false; }\n')
                if inst.get('name') == 'man' or ref == death_name:
                    if ref in [mapped[n] for n in ATTACKS]:
                        key = next(k for k in ATTACKS if mapped[k] == ref)
                        event_script(inst, 'onClipEvent(load){ _parent.manmanBeginAttack(this,"' + ATTACKS[key] + '"); }\n')
                    elif ref == mapped['Symbol 1118']:
                        event_script(inst, 'onClipEvent(load){ gotoAndPlay("a"+random(2)); }\n')
                    elif ref == mapped['Symbol 1119']:
                        event_script(inst, 'onClipEvent(load){ _parent.状态改变("倒地"); }\n')
                    elif ref == mapped['Symbol 1120']:
                        event_script(inst, 'onClipEvent(load){ _parent._y=_parent.Z轴坐标; _parent.倒地=true; _parent.格斗架势=true; }\n'
                            'onClipEvent(unload){ _parent.倒地=false; }\n'
                            'onClipEvent(enterFrame){ if(_parent.hp<=0) _parent.状态改变("血腥死"); }\n')
                    elif ref == death_name:
                        inst.set('name', 'man')
                        mx = inst.find('x:matrix/x:Matrix', NS)
                        mx.attrib.clear()
                        for key, value in zip(('a', 'b', 'c', 'd', 'tx', 'ty'), death_matrix):
                            mx.set(key, native.num(value))
                        event_script(inst, 'onClipEvent(load){ _parent.manmanCancelAttack(); gotoAndPlay("a0"); }\n')
            driver_name = PREFIX + '行为驱动'
            generated[driver_name] = native.symbol(driver_name, [native.layer('停止', [native.frame(script='stop();')])], symbol_type='movie clip')
            driver = native.instance(driver_name, symbol_type='movie clip', name='manmanDriver',
                script='onClipEvent(enterFrame){ _parent.manmanTick(); }\n')
            root.find('x:timeline/x:DOMTimeline/x:layers', NS).insert(0, native.layer('私有行为', [native.frame(duration=127, elements=[driver])]))
        generated[name] = root
    wolf = module('manman_wolf_leap', HERE / 'wolf_leap.py')
    wolf.add_action(generated, root_name, native)
    return generated, root_name, source_rows


def write_workspace(symbols, root_name):
    anchor = native.symbol(ANCHOR, [native.layer('入口', [native.frame(script='stop();', elements=[
        native.instance(root_name, symbol_type='movie clip')])])], symbol_type='movie clip', linkage=ANCHOR,
        export_rs=True, url='flashswf/arts/new/' + ANCHOR + '.swf')
    symbols = {**symbols, ANCHOR: anchor}
    rows = []
    for name, tree in sorted(symbols.items()):
        rel = 'LIBRARY/' + name + '.xml'
        p = OWNER / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(native.xml_bytes(tree))
        rows.append({'path': rel, 'sha256': sha(p), 'bytes': p.stat().st_size})
    doc = E.Element(N + 'DOMDocument', nsmap={None: NS['x']}, width='550', height='400', frameRate='30',
                    xflVersion='2.2', backgroundColor='#E5E3DF', creatorInfo='Adobe Flash Professional CS6',
                    platform='Windows', versionInfo='Saved by Adobe Flash Windows 12.0 build 481', majorVersion='12', buildNumber='481')
    folders = sorted({('/'.join(name.split('/')[:i])) for name in symbols for i in range(1, len(name.split('/')))})
    ff = E.SubElement(doc, N + 'folders')
    for name in folders:
        E.SubElement(ff, N + 'DOMFolderItem', name=name, itemID=native.item_id(name, '6af20000'))
    includes = E.SubElement(doc, N + 'symbols')
    for name in sorted(symbols):
        E.SubElement(includes, N + 'Include', href=name + '.xml', itemID=native.item_id(name), loadImmediate='false')
    E.SubElement(doc, N + 'media')
    timeline = E.SubElement(E.SubElement(doc, N + 'timelines'), N + 'DOMTimeline', name='场景 1')
    E.SubElement(timeline, N + 'layers').append(native.layer('共享入口', [native.frame(script='stop();', elements=[native.instance(ANCHOR, symbol_type='movie clip')])]))
    (OWNER / 'DOMDocument.xml').write_bytes(native.xml_bytes(doc))
    (OWNER / (ANCHOR + '.xfl')).write_bytes(b'PROXY-CS5\n')
    (OWNER / 'MobileSettings.xml').write_bytes(b'')
    pub = (ROOT / 'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml').read_text(encoding='utf-8').replace('Codex黑仔素材', ANCHOR)
    (OWNER / 'PublishSettings.xml').write_text(pub, encoding='utf-8', newline='\n')
    return rows


def mount_shared_library():
    fla = ROOT / 'flashswf/arts/things-new.fla'
    with zipfile.ZipFile(fla) as z:
        entries = [(i, z.read(i.filename)) for i in z.infolist()]
    content = {i.filename: data for i, data in entries}
    item = native.item_id(ANCHOR)
    xml = native.symbol(ANCHOR, [native.layer('导入', [native.frame()])], symbol_type='movie clip')
    xml.attrib.update({'linkageImportForRS': 'true', 'linkageExportInFirstFrame': 'false',
                      'linkageIdentifier': ANCHOR, 'linkageURL': 'flashswf/arts/new/' + ANCHOR + '.swf'})
    member = 'LIBRARY/' + ANCHOR + '.xml'
    if member in content:
        existing = E.fromstring(content[member], PARSER)
        if any(existing.get(k) != xml.get(k) for k in ('linkageIdentifier', 'linkageImportForRS', 'linkageURL')):
            raise ValueError('Existing shared-library import differs')
        if (ANCHOR + '.xml') not in content['DOMDocument.xml'].decode('utf-8') or ('libraryItemName="' + ANCHOR + '"') not in content['LIBRARY/things-new.xml'].decode('utf-8'):
            raise ValueError('Existing shared-library mount is incomplete')
        return
    doc = content['DOMDocument.xml'].decode('utf-8')
    doc = doc.replace('</symbols>', '<Include href="' + ANCHOR + '.xml" itemID="' + item + '" loadImmediate="false"/>\n</symbols>', 1)
    main = E.fromstring(content['LIBRARY/things-new.xml'], PARSER)
    frames = main.findall('.//x:DOMFrame[@index="3"]/x:elements', NS)
    if len(frames) != 1:
        raise ValueError('Expected exactly one things-new frame 4 mount')
    frames[0].append(native.instance(ANCHOR, matrix=(1, 0, 0, 1, 1800, 500), symbol_type='movie clip'))
    updates = {'DOMDocument.xml': doc.encode('utf-8'), 'LIBRARY/things-new.xml': E.tostring(main, encoding='utf-8'), member: native.xml_bytes(xml)}
    temporary = fla.with_suffix('.manman.tmp')
    if temporary.exists():
        raise ValueError('Unresolved prior shared-library write: ' + str(temporary))
    with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as z:
        for info, data in entries:
            z.writestr(info, updates.get(info.filename, data))
        z.writestr(member, updates[member])
    temporary.replace(fla)


def import_assets(force=False):
    native.guard_overwrite_allowed(force)
    generated, root_name, donor = build_symbols()
    native.guard_overwrite_allowed(force)
    audio_receipt=audio.apply(generated,OWNER,native.make_sparse_layer)
    outputs = write_workspace(generated, root_name)
    manifest = {'schema': native.MANIFEST_SCHEMA, 'owner': OWNER.relative_to(ROOT).as_posix(),
        'approvedInput': ARCHIVE.relative_to(ROOT).as_posix(), 'nativeSymbolCount': len(outputs), 'buildInputs': build_inputs(),
        'donor': {'path': DONOR.relative_to(ROOT).as_posix(), 'sha256': sha(DONOR), 'members': donor},
        'outputs': outputs, 'projectFiles': [{'path': p, 'sha256': sha(OWNER / p), 'bytes': (OWNER / p).stat().st_size} for p in native.PROJECT_FILES]}
    manifest['audio']=audio_receipt
    (HERE / 'native-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    mount_shared_library()
    print(json.dumps({'symbols': len(outputs), 'linkage': LINKAGE}, ensure_ascii=False))


def check():
    verify_input()
    manifest = json.loads((HERE / 'native-manifest.json').read_text(encoding='utf-8'))
    audio.check(manifest,OWNER)
    errors = native.workspace_identity_failures(manifest)
    if manifest.get('buildInputs') != build_inputs():
        errors.append('Generator/AI inputs changed; guarded regeneration is required')
    if manifest['donor']['sha256'] != sha(DONOR):
        errors.append('Donor FLA changed; review the source before regeneration')
    includes = {i.get('href') for i in E.parse(str(OWNER / 'DOMDocument.xml')).findall('x:symbols/x:Include', NS)}
    for row in manifest['outputs']:
        path = OWNER / row['path']
        root = E.parse(str(path), PARSER).getroot()
        if row['path'][8:] not in includes:
            errors.append('Missing Include: ' + row['path'])
        for element in root.iter():
            ref = element.get('libraryItemName')
            if ref and not (OWNER / 'LIBRARY' / (ref + '.xml')).is_file():
                errors.append('Unresolved: ' + ref)
        if root.findall('.//x:BitmapFill', NS) or root.findall('.//x:DOMBitmapInstance', NS):
            errors.append('Unexpected bitmap: ' + row['path'])
    if errors:
        raise ValueError('\n'.join(errors))
    print(json.dumps({'ok': True, 'symbols': len(manifest['outputs']), 'projectFiles': len(manifest['projectFiles'])}))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--import-approved', action='store_true')
    mode.add_argument('--check', action='store_true')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    if args.import_approved:
        import_assets(args.force)
    check()
