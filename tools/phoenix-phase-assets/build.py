"""Import the artist's Phoenix transition into the existing AS2 Codex RSL.

The archived XFL remains the editable art input. Only the reachable visual
closure is assembled; gameplay and its single clock live in asLoader.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import shutil
import subprocess
import tempfile
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/火凤转阶段/火凤转阶段.rar'
ARCHIVE_SHA = 'd4496e35cb3c1a74498cb67a66059bd58e9cca722605de860886fb6df4746434'
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
PREFIX = 'Codex/火凤转阶段/'
LINKAGE = '火凤转阶段演出'
ENTRY = PREFIX + LINKAGE
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{' + NS['x'] + '}'
PARSER = E.XMLParser(strip_cdata=False, resolve_entities=False)


def xml(data):
    return E.tostring(data, encoding='utf-8', pretty_print=True)


def node(tag, **attrs):
    return E.Element(N + tag, {k: str(v) for k, v in attrs.items()}, nsmap={None: NS['x']})


def outputs(source):
    library = source / 'LIBRARY'
    trees = {r.get('name'): r for p in library.rglob('*.xml')
             for r in [E.parse(str(p), PARSER).getroot()]}
    todo, reached = ['转阶段动画'], set()
    while todo:
        name = todo.pop()
        if name in reached:
            continue
        if name not in trees:
            raise ValueError('Missing visual dependency: ' + name)
        reached.add(name)
        todo.extend(el.get('libraryItemName') for el in trees[name].iter()
                    if el.get('libraryItemName'))
    result = {}
    for name in sorted(reached):
        r = copy.deepcopy(trees[name])
        renamed = PREFIX + '原稿/' + name
        r.set('name', renamed)
        for key in list(r.attrib):
            if key.startswith('linkage') or key in ('itemID', 'lastModified'):
                del r.attrib[key]
        # These newer authoring caches are not runtime transforms. Preserve
        # every actual Matrix, frame, filter, blend and graphic firstFrame.
        for el in r.iter():
            el.attrib.pop('rigPropagationMatrix', None)
            ref = el.get('libraryItemName')
            if ref:
                el.set('libraryItemName', PREFIX + '原稿/' + ref)
        for script in r.findall('.//x:Actionscript', NS):
            script.getparent().remove(script)
        result[renamed] = xml(r)

    # Private, graphic-only flame clip. It is a named child of the existing
    # export, so no new runtime linkage or asset-source-map entry is needed.
    charge_name = PREFIX+'蓄焰'
    charge = node('DOMSymbolItem', name=charge_name)
    charge_timeline = E.SubElement(E.SubElement(charge, N+'timeline'), N+'DOMTimeline', name='蓄焰')
    charge_frames = E.SubElement(E.SubElement(E.SubElement(charge_timeline, N+'layers'), N+'DOMLayer', name='原稿余烬'), N+'frames')
    fire = next(name for name in result if name.endswith('/火凤余烬'))
    for tick in range(32):
        frame = E.SubElement(charge_frames, N+'DOMFrame', index=str(tick), keyMode='9728')
        if tick == 0:
            E.SubElement(E.SubElement(frame, N+'Actionscript'), N+'script').text = E.CDATA('stop();')
        E.SubElement(E.SubElement(frame, N+'elements'), N+'DOMSymbolInstance',
                     libraryItemName=fire, symbolType='graphic', firstFrame=str(tick), loop='single frame')
    result[charge_name] = xml(charge)

    r = node('DOMSymbolItem', name=ENTRY, linkageExportForAS='true', linkageIdentifier=LINKAGE)
    timeline = E.SubElement(E.SubElement(r, N+'timeline'), N+'DOMTimeline', name=LINKAGE)
    frames = E.SubElement(E.SubElement(E.SubElement(timeline, N+'layers'), N+'DOMLayer', name='原稿演出'), N+'frames')
    for tick in range(182):
        frame = E.SubElement(frames, N+'DOMFrame', index=str(tick), keyMode='9728')
        if tick == 0:
            E.SubElement(E.SubElement(frame, N+'Actionscript'), N+'script').text = E.CDATA('stop();')
        instance = E.SubElement(E.SubElement(frame, N+'elements'), N+'DOMSymbolInstance',
                                libraryItemName=PREFIX+'原稿/转阶段动画', symbolType='graphic',
                                firstFrame=str(tick), loop='single frame')
        # Match the actor's Symbol 556 (down) placement. The source starts in
        # exactly that lying pose; its shadow deforms and is not a stable pivot.
        # Keep one body registration through both authored transitions.
        x, y = 409.1, 177.8
        E.SubElement(E.SubElement(instance, N+'matrix'), N+'Matrix', tx=str(x), ty=str(y))
    layers = timeline.find(N+'layers')
    charge_frame = E.SubElement(E.SubElement(E.SubElement(layers, N+'DOMLayer', name='蓄焰'), N+'frames'), N+'DOMFrame', index='0', duration='182')
    charge_instance = E.SubElement(E.SubElement(charge_frame, N+'elements'), N+'DOMSymbolInstance',
                                   libraryItemName=charge_name, name='charge')
    E.SubElement(E.SubElement(charge_instance, N+'color'), N+'Color', alphaMultiplier='0')
    result[ENTRY] = xml(r)
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    if hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() != ARCHIVE_SHA:
        raise ValueError('Artist archive identity changed; review the new source first')
    seven = shutil.which('7z') or r'C:\Program Files\7-Zip\7z.exe'
    with tempfile.TemporaryDirectory(prefix='cfn-phoenix-art-') as folder:
        subprocess.run([seven, 'x', '-y', '-o'+folder, '--', str(ARCHIVE)], check=True, capture_output=True)
        result = outputs(Path(folder) / '火凤转阶段')
    for name, data in result.items():
        path = OWNER / 'LIBRARY' / (name+'.xml')
        if args.check:
            if not path.is_file() or path.read_bytes() != data:
                raise ValueError('Stale assembled art: ' + name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    doc_path = OWNER / 'DOMDocument.xml'
    doc = E.parse(str(doc_path), PARSER)
    symbols = doc.getroot().find('x:symbols', NS)
    includes = {el.get('href') for el in symbols}
    required = {name+'.xml' for name in result}
    anchor_path = OWNER / 'LIBRARY/Codex专用素材.xml'
    anchor = E.parse(str(anchor_path), PARSER)
    matches = anchor.findall('.//x:DOMSymbolInstance[@libraryItemName="'+ENTRY+'"]', NS)
    if args.check:
        assert required <= includes, 'Missing Codex Includes'
        assert len(matches) == 1, 'Missing or duplicate Codex anchor'
    else:
        for href in sorted(required-includes):
            E.SubElement(symbols, N+'Include', href=href)
        if not matches:
            layers = anchor.getroot().find('x:timeline/x:DOMTimeline/x:layers', NS)
            layer = E.SubElement(layers, N+'DOMLayer', name='火凤转阶段')
            frame = E.SubElement(E.SubElement(layer, N+'frames'), N+'DOMFrame', index='0')
            instance = E.SubElement(E.SubElement(frame, N+'elements'), N+'DOMSymbolInstance', libraryItemName=ENTRY)
            E.SubElement(E.SubElement(instance, N+'matrix'), N+'Matrix', tx='-2000', ty='-2000')
        doc_path.write_bytes(xml(doc))
        anchor_path.write_bytes(xml(anchor))
    manifest = {
        'schema': 'cf7-phoenix-transition.v1', 'archiveSha256': ARCHIVE_SHA,
        'generatorSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'linkage': LINKAGE, 'registration': {'x': 409.1, 'y': 177.8}, 'phaseTwo': {'first': 1, 'last': 80, 'impact': 35},
        'phaseThree': {'first': 82, 'chargeLast': 93, 'riseFirst': 94, 'riseLast': 121, 'chargeFadeLast': 127, 'fallFirst': 151, 'last': 182, 'impact': 159, 'risePixels': 208.95},
        'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(result.items())}}
    data = (json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode('utf-8')
    path = HERE / 'manifest.json'
    if args.check:
        assert path.read_bytes() == data, 'Stale assembly manifest'
    else:
        path.write_bytes(data)
    print(('Checked' if args.check else 'Assembled') + f' Phoenix: {len(result)} symbols, 182 source frames, no art gameplay scripts')


if __name__ == '__main__':
    main()
