"""Derive a script-free Wings scene actor from the current native standing art.

The original A06/A08 actor is visual only. This does not export the enemy linkage,
initialize a unit, execute original actions, or write a SWF.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / 'flashswf/arts/new/CodexWings素材'
NAME = 'CF6_ScenicWings'
DEST = ROOT / 'flashswf/backgrounds/cf6/preparation' / NAME
Q = '{http://ns.adobe.com/xfl/2008/}'
NS = {'x': Q[1:-1]}
ET.register_namespace('', Q[1:-1])
STAND = 'Codex/Wings/动作/站立'
ORIGINAL_SHA = 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(data):
    return (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def xml(node):
    return ET.tostring(node, encoding='utf-8', xml_declaration=True)


def element(name, attrs=None, parent=None):
    node = ET.Element(Q + name, attrs or {})
    if parent is not None:
        parent.append(node)
    return node


def build():
    inputs, outputs, symbols = {}, {}, {}

    def read(path):
        data = path.read_bytes()
        inputs[path.relative_to(ROOT).as_posix()] = sha(data)
        return data

    read(Path(__file__))
    palette = json.loads(read(HERE / 'scenic-wings-palette.json'))
    if palette['schema'] != 'cf6-scenic-wings-palette.v1' or palette['originalSwfSha256'] != ORIGINAL_SHA or palette['originalSprite'] != 1777:
        raise ValueError('scene Wings palette provenance changed')
    recolored_sources, recolored_colors = set(), set()
    policy = json.loads(read(ROOT / 'tools/cf6-prop-layout/scale-policy.json'))
    # Preserve the current body policy independently of map scaling.
    unit, = [row for row in policy['humanoids'] if row['unitId'] == 464]
    if unit['heightCm'] != 190:
        raise ValueError('Wings body contract changed')
    for name,digest in unit['nativeSources'].items():
        if sha(read(ROOT/name)) != digest:
            raise ValueError('calibrated Wings source changed: '+name)
    reference=policy['reference']
    body_scale = unit['heightCm'] * reference['relaxedStandingBodyPixels'] / (reference['heightCm'] * unit['nativeStandingBodyHeight'])
    placements=[]
    for map_id,world,depth,matrix in [('A06',1778,186,[-1,0,0,1,1035.7,210]),('A08',1841,158,[1,0,0,1,401.9,260.1])]:
        geometry=json.loads(read(ROOT/('tools/cf6-map-runtime/generated/'+map_id+'-original-geometry.json')))
        if geometry['originalSwfSha256'] != ORIGINAL_SHA or geometry['geometry']['worldSprite'] != world:
            raise ValueError('original world identity changed')
        actor,=[row for row in geometry['geometry']['display'] if row.get('id')==1777]
        if actor['depth']!=depth or actor['matrix']!=matrix or actor['name']!='wings':
            raise ValueError('original scene actor placement changed')
        placements.append({'mapId':map_id,'worldSprite':world,'sourceDepth':depth,'nativeMatrix':matrix})
    placements[0]['speech']='Andy！救我！'
    unit_root = ET.fromstring(read(SOURCE / 'LIBRARY/Codex/Wings/敌人-CF6Wings.xml'))
    stand_placements = unit_root.findall('.//x:DOMFrame[@index="0"]/x:elements/x:DOMSymbolInstance[@libraryItemName="'+STAND+'"]', NS)
    if len(stand_placements) != 1:
        raise ValueError('ambiguous standing placement')
    placement = stand_placements[0]
    original_matrix = placement.find('x:matrix/x:Matrix', NS)
    if original_matrix is None or any(float(original_matrix.get(k, str(v))) != v
                                      for k, v in [('a',1),('b',0),('c',0),('d',1),('tx',30),('ty',-67.3)]):
        raise ValueError('standing foot registration changed')

    def visit(name, stack=()):
        if name in stack:
            raise ValueError('recursive art dependency')
        if name in symbols:
            return
        path = SOURCE / 'LIBRARY' / (name + '.xml')
        if not path.resolve().is_relative_to((SOURCE / 'LIBRARY').resolve()):
            raise ValueError('art dependency escaped owner')
        raw = read(path)
        root = ET.fromstring(raw)
        source_key = path.relative_to(ROOT).as_posix()
        if source_key in palette['sources']:
            if sha(raw) != palette['sources'][source_key]:
                raise ValueError('reviewed scene Wings body source changed: ' + source_key)
            recolored_sources.add(source_key)
            for paint in root.iter():
                color = paint.get('color', '').upper()
                if color in palette['colors']:
                    paint.set('color', palette['colors'][color])
                    recolored_colors.add(color)
        if root.get('name') != name or root.find('.//x:BitmapFill', NS) is not None:
            raise ValueError('unreviewed native source')
        if root.get('linkageImportForRS') == 'true':
            raise ValueError('external actor dependency')
        for key in list(root.attrib):
            if key.startswith('linkage'):
                del root.attrib[key]
        for parent in root.iter():
            for child in list(parent):
                if child.tag == Q + 'Actionscript':
                    parent.remove(child)
            for key in list(parent.attrib):
                if key.startswith('sound'):
                    del parent.attrib[key]
        for child in root.iter(Q + 'DOMSymbolInstance'):
            visit(child.get('libraryItemName'), stack + (name,))
            # The combat weapon's first frame is its resting appearance. Its
            # removed stop() must not expose firing/muzzle frames in a scene.
            if child.get('symbolType') != 'graphic':
                child.set('symbolType', 'graphic')
                child.set('loop', 'single frame')
                child.set('firstFrame', '0')
        symbols[name] = xml(root)

    visit(STAND)
    if recolored_sources != set(palette['sources']) or recolored_colors != set(palette['colors']):
        raise ValueError('scene Wings palette did not consume its exact reviewed body closure')
    stand_tree = ET.fromstring(symbols[STAND])
    frame_count = max(int(f.get('index')) + int(f.get('duration', '1'))
                      for f in stand_tree.iter(Q + 'DOMFrame'))
    if frame_count != 15:
        raise ValueError('standing animation must retain fifteen frames')
    document = element('DOMDocument', {'width':'600','height':'500','frameRate':'30','xflVersion':'2.2',
        'creatorInfo':'Adobe Flash Professional CS6','platform':'Windows','versionInfo':'Saved by Adobe Flash Windows 12.0','majorVersion':'12'})
    includes = element('symbols', parent=document)
    for name in sorted(symbols):
        element('Include', {'href':name+'.xml','loadImmediate':'false'}, includes)
        outputs[DEST / 'LIBRARY' / (name + '.xml')] = symbols[name]
    timeline = element('DOMTimeline', {'name':NAME}, element('timelines', parent=document))
    layer = element('DOMLayer', {'name':'Native standing scene actor'}, element('layers', parent=timeline))
    frames = element('frames', parent=layer)
    for index in range(frame_count):
        frame = element('DOMFrame', {'index':str(index),'keyMode':'9728'}, frames)
        instance = copy.deepcopy(placement)
        instance.attrib.pop('name', None)
        instance.set('symbolType', 'graphic'); instance.set('loop', 'single frame'); instance.set('firstFrame', str(index))
        element('elements', parent=frame).append(instance)
    outputs[DEST / 'DOMDocument.xml'] = xml(document)
    settings = ET.fromstring(read(SOURCE / 'PublishSettings.xml'))
    for name, value in {'flashFileName':NAME+'.swf','defaultNames':'0','flashDefaultName':'0','flash':'1',
                        'html':'0','projectorWin':'0','projectorMac':'0','gif':'0','jpeg':'0','png':'0','swc':'0'}.items():
        target = settings.find('.//PublishFormatProperties/' + name)
        if target is None:
            raise ValueError('missing publish setting: ' + name)
        target.text = value
    outputs[DEST / 'PublishSettings.xml'] = xml(settings)
    outputs[DEST / (NAME + '.xfl')] = read(SOURCE / 'CodexWings素材.xfl')
    manifest = {'schema':'cf6-scenic-wings.v1','originalSha256':ORIGINAL_SHA,
        'sourceSprite':1777,'frames':15,'xfl':(DEST/(NAME+'.xfl')).relative_to(ROOT).as_posix(),
        'swf':'flashswf/backgrounds/cf6/preparation/'+NAME+'.swf','bodyScale':body_scale,
        'role':'visual-only scene actor; no enemy, hp, hit area, reward or AI',
        'palette':'scenic-wings-palette.json', 'bodyColorsReplaced':len(recolored_colors),
        'placements':placements,
        'inputs':inputs,'outputs':{p.relative_to(ROOT).as_posix():{'sha256':sha(d),'bytes':len(d)}
                                 for p,d in sorted(outputs.items())}}
    return outputs, manifest


def main():
    parser = argparse.ArgumentParser();parser.add_argument('--check', action='store_true');args=parser.parse_args()
    outputs, manifest = build()
    target = HERE / 'scenic-wings-manifest.json'
    previous = json.loads(target.read_text('utf-8'))['outputs'] if target.is_file() else {}
    if not args.check:
        for path in outputs:
            if path.exists() and path.read_bytes() != outputs[path]:
                old = previous.get(path.relative_to(ROOT).as_posix())
                if old is None or sha(path.read_bytes()) != old['sha256']:
                    raise ValueError('changed or unowned native source: '+str(path))
    outputs[target] = encoded(manifest)
    for path,data in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes()!=data:
                raise ValueError('stale scene actor: '+str(path))
        else:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    print(json.dumps({'files':len(outputs),'frames':15,'mode':'check' if args.check else 'build'}))


if __name__ == '__main__':
    main()
