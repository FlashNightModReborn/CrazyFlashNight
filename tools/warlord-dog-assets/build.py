"""Deterministic R2 iron guard dog assembly in the existing Codex native library."""
import argparse
import ast
import copy
import hashlib
import importlib.util
import json
import math
import re
from pathlib import Path
import sys
from lxml import etree as E
import bite_support

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/军阀铁卫犬-R2'
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
SOURCE = ROOT / 'flashswf/arts/things1/LIBRARY'
PREFIX = 'Codex/铁卫犬/'
KIND = '敌人-军阀铁卫犬'
N = {'x': 'http://ns.adobe.com/xfl/2008/'}
X = '{' + N['x'] + '}'
spec = importlib.util.spec_from_file_location('cf6_native_dog_reuse', ROOT / 'tools/cf6-zombie-assets/build.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
# Reuse the retained converter's pure arc/path mathematics without importing its
# optional Skia boolean/stroke stack. Inputs here contain no clipping or strokes.
geometry_path = ROOT / 'tools/tesla-map-assets/native_vector/vector_shapes.py'
geometry_ast = ast.parse(geometry_path.read_text(encoding='utf-8-sig'))
geometry_defs = [n for n in geometry_ast.body if isinstance(n, ast.FunctionDef)
                 and n.name in ('arc_cubics', 'parse_path')]
assert len(geometry_defs) == 2
geometry_scope = {'base':native.base, 'math':math, 're':re, 'CUBIC_TOL':.0015}
exec(compile(ast.Module(body=geometry_defs, type_ignores=[]), str(geometry_path), 'exec'), geometry_scope)
native.base.parse_path = geometry_scope['parse_path']
PARTS = {f'Symbol {726+i}': 1331+i for i in range(13)}
PARTS.update({f'Symbol {747+i}': 1351+i for i in range(25)})
MOUTH_SCRIPT = '''onClipEvent(enterFrame) {
    var head = _parent.part230;
    var jaw = _parent.part235;
    this._visible = head != undefined && jaw != undefined;
    if (this._visible) {
        var hinge = {x:60,y:110};
        var upper = {x:320,y:107};
        var lower = {x:205,y:76};
        head.localToGlobal(hinge); _parent.globalToLocal(hinge);
        head.localToGlobal(upper); _parent.globalToLocal(upper);
        jaw.localToGlobal(lower); _parent.globalToLocal(lower);
        var liveTransform = new flash.geom.Transform(this);
        liveTransform.matrix = new flash.geom.Matrix(upper.x-hinge.x,upper.y-hinge.y,
            lower.x-hinge.x,lower.y-hinge.y,hinge.x,hinge.y);
    }
}'''
LAMP_SCRIPT = '''onClipEvent(load) {
    gotoAndStop(_parent._parent.__ironGuard.ready && _parent._parent.hp > 0 ? 1 : 2);
}
onClipEvent(enterFrame) {
    gotoAndStop(_parent._parent.__ironGuard.ready && _parent._parent.hp > 0 ? 1 : 2);
}'''


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def archive_inputs(source):
    if ARCHIVE.exists():
        raise RuntimeError('Input archive already exists; preserve it and use the recorded source.')
    paths = sorted((source / 'artwork/03-warlord/normal').glob('*.svg'))
    paths += sorted((source / 'artwork/03-warlord/death').glob('*.svg'))
    paths += sorted((source / 'artwork/03-warlord/auxiliary').glob('*.svg'))
    paths += [source / 'rig-adaptation/rig.json', source / 'rig-adaptation/mouth-rule.json',
              source / 'DELIVERY.json', source / 'SHA256SUMS.json']
    assert sum(p.suffix == '.svg' for p in paths) == 50
    rows = []
    for p in paths:
        relative = p.relative_to(source)
        dest = ARCHIVE / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(p.read_bytes())
        rows.append({'path': relative.as_posix(), 'sha256': sha(dest)})
    (ARCHIVE / 'source-provenance.json').write_text(json.dumps({
        'source': 'CF7-Warlord-R2-Animation-Assets.zip',
        'originalUnmodified': True, 'files': rows,
        'nativeSource': 'flashswf/arts/new/Codex专用素材',
        'assembly': 'tools/warlord-dog-assets/build.py',
        'humanVisualApproval': 'pending'}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def recolor_lamp(tree):
    colors = {'#ffcc3c': '#4A4332', '#ffad11': '#38332C',
              '#91eee8': '#334744', '#65e0dd': '#2B3937'}
    result = copy.deepcopy(tree)
    for fill in result.findall('.//x:SolidColor', N):
        value = fill.get('color', '').lower()
        if value in colors:
            fill.set('color', colors[value])
    return result


def color_instance(inst, values):
    if values == [1, 1, 1, 1, 0, 0, 0, 0]:
        return
    color = E.SubElement(inst, X+'color')
    names = ['redMultiplier','greenMultiplier','blueMultiplier','alphaMultiplier',
             'redOffset','greenOffset','blueOffset','alphaOffset']
    E.SubElement(color, X+'Color', **{k: native.num(v) for k, v in zip(names, values)})


def action_symbol(seq, part_names, action_names, helpers):
    old = seq['symbol']
    tree = E.parse(str(SOURCE / f'{old}.xml'), native.PARSER).getroot()
    name = action_names[old]
    tree.set('name', name)
    tree.set('itemID', native.item_id(name, '6b100000'))
    for key in ('lastModified','lastUniqueIdentifier'):
        tree.attrib.pop(key,None)
    for key in list(tree.attrib):
        if key.startswith('linkage'):
            del tree.attrib[key]
    timeline = tree.find('./x:timeline/x:DOMTimeline', N)
    timeline.set('name', name.rsplit('/', 1)[-1])
    layers = timeline.find('./x:layers', N)
    # Preserve actual source actions, hit emitters, shadows and cleanup controllers.
    for inst in list(tree.findall('.//x:DOMSymbolInstance', N)):
        ref = inst.get('libraryItemName')
        if ref in PARTS or ref in action_names:
            inst.getparent().remove(inst)
        else:
            inst.set('libraryItemName', clone_helper(ref, helpers))
            for script in inst.findall('./x:Actionscript/x:script', N):
                if '_root.子弹区域shoot(' in (script.text or ''):
                    script.text = E.CDATA('onClipEvent(load) { _root.铁卫犬.撕咬(_parent._parent); }')
    # Remove paint-only empty layers, while retaining source labels and actions.
    for layer in list(layers):
        meaningful = layer.findall('.//x:script', N) or layer.findall('.//x:DOMSymbolInstance', N)
        meaningful = meaningful or any(f.get('name') for f in layer.findall('./x:frames/x:DOMFrame', N))
        if not meaningful:
            layers.remove(layer)
    all_depths = sorted({p['depth'] for f in seq['frames'] for p in f['placements']} | {215}, reverse=True)
    for depth in all_depths:
        keys = []
        previous = None
        for f in seq['frames']:
            row = next((p for p in f['placements'] if p['depth'] == depth), None)
            if depth == 215:
                present = {p['depth'] for p in f['placements']}
                row = {'depth':215,'characterId':1800,'matrix':[1,0,0,1,0,0],
                       'colorTransform':[1,1,1,1,0,0,0,0]} if {230,235} <= present else None
            signature = json.dumps(row, sort_keys=True)
            if signature == previous:
                keys[-1].set('duration', str(int(keys[-1].get('duration','1'))+1))
                continue
            previous = signature
            elems = []
            if row:
                cid = row['characterId']
                symbol_name = part_names[cid]
                is_death = old == 'Symbol 772'
                if cid == 1339 and is_death:
                    symbol_name += '-熄灭'
                clip = depth in (215,230,235) or (cid == 1339 and not is_death)
                script = MOUTH_SCRIPT if depth == 215 else (LAMP_SCRIPT if cid == 1339 and not is_death else None)
                inst = native.instance(symbol_name, matrix=row['matrix'],
                    symbol_type='movie clip' if clip else 'graphic',
                    name=f'part{depth}' if clip else None, script=script)
                color_instance(inst, row['colorTransform'])
                elems.append(inst)
            keys.append(native.frame(index=f['frame']-1, elements=elems))
        layers.append(native.layer(f'R2原生分件-{depth}', keys))
    return name, tree


def clone_helper(old, helpers):
    if old in helpers:
        return PREFIX+'共用/'+old
    name = PREFIX+'共用/'+old
    src = SOURCE / f'{old}.xml'
    tree = E.parse(str(src), native.PARSER).getroot()
    helpers[old] = tree
    tree.set('name', name)
    tree.set('itemID', native.item_id(name, '6b200000'))
    for key in ('lastModified','lastUniqueIdentifier'):
        tree.attrib.pop(key,None)
    tree.find('./x:timeline/x:DOMTimeline',N).set('name',name.rsplit('/',1)[-1])
    for key in list(tree.attrib):
        if key.startswith('linkage'):
            del tree.attrib[key]
    for inst in tree.findall('.//x:DOMSymbolInstance', N):
        inst.set('libraryItemName', clone_helper(inst.get('libraryItemName'), helpers))
    return name


def generate():
    provenance = json.loads((ARCHIVE / 'source-provenance.json').read_text(encoding='utf-8'))
    for row in provenance['files']:
        assert sha(ARCHIVE / row['path']) == row['sha256'], row['path']
    rig = json.loads((ARCHIVE / 'rig-adaptation/rig.json').read_text(encoding='utf-8'))
    support = json.loads((HERE / 'bite-support.json').read_text(encoding='utf-8'))
    rig = bite_support.apply(rig, support)
    generated, part_names, reports = {}, {}, {}
    for path in sorted((ARCHIVE / 'artwork/03-warlord').rglob('*.svg')):
        cid = int(path.stem.split('_')[0].split('-')[-1]) if path.stem != 'mouth-web-1800' else 1800
        name = PREFIX+'分件/'+str(cid)
        # Rear cheek membrane only: the front mouth opening remains transparent.
        # The delivered full triangle remains byte-for-byte in the source archive.
        art_input = HERE/'mouth-web.svg' if cid == 1800 else path
        converted, report = native.NativePart(art_input, name).build()
        if cid in (1340,1342,1800):
            converted[name].attrib.pop('symbolType', None)
        if 1351 <= cid <= 1375:
            converted = {k: recolor_lamp(v) for k, v in converted.items()}
        generated.update(converted)
        part_names[cid], reports[str(cid)] = name, report
        if cid == 1339:
            off = recolor_lamp(converted[name])
            off.set('name', name+'-熄灭')
            off.set('itemID', native.item_id(name+'-熄灭', '6b300000'))
            generated[name+'-熄灭'] = off
            lit = converted[name]
            lit.attrib.pop('symbolType', None)
            frames = lit.find('.//x:DOMLayer/x:frames', N)
            lit_frame = frames[0]
            asc = E.SubElement(lit_frame, X+'Actionscript')
            E.SubElement(asc, X+'script').text = E.CDATA('stop();')
            dark_frame = copy.deepcopy(off.find('.//x:DOMFrame', N))
            dark_frame.set('index','1')
            asc = E.SubElement(dark_frame, X+'Actionscript')
            E.SubElement(asc, X+'script').text = E.CDATA('stop();')
            frames.append(dark_frame)
    helpers = {}
    action_names = {s['symbol']:PREFIX+'动作/'+key for key,s in rig['sequences'].items()}
    for seq in rig['sequences'].values():
        name, tree = action_symbol(seq, part_names, action_names, helpers)
        generated[name] = tree
    actor = E.parse(str(SOURCE / '敌人-僵尸1-狗.xml'), native.PARSER).getroot()
    actor_name = PREFIX+KIND
    actor.set('name', actor_name)
    actor.set('itemID',native.item_id(actor_name,'6b400000'))
    actor.set('linkageIdentifier',KIND)
    actor.set('linkageExportInFirstFrame','true')
    actor.attrib.pop('lastModified',None)
    actor.attrib.pop('lastUniqueIdentifier',None)
    actor.find('./x:timeline/x:DOMTimeline',N).set('name',KIND)
    for inst in actor.findall('.//x:DOMSymbolInstance',N):
        ref = inst.get('libraryItemName')
        inst.set('libraryItemName',action_names[ref] if ref in action_names else clone_helper(ref,helpers))
    init = actor.find('.//x:DOMLayer[@name="Script Layer"]/x:frames/x:DOMFrame/x:Actionscript/x:script',N)
    init.text = E.CDATA('''不掉钱 = true;
奔跑速度倍率 = 1;
中心高度 = 30;
随机移动机率 = 100;
根据等级初始数值 = _root.铁卫犬.属性初始化;
初始化敌人模板 = _root.初始化敌人模板;
初始化敌人模板();
_root.铁卫犬.初始化(this);
''')
    generated[actor_name] = actor
    generated.update({PREFIX+'共用/'+k:v for k,v in helpers.items()})
    return generated, reports


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive-from', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.archive_from:
        archive_inputs(args.archive_from)
    generated, reports = generate()
    output = {OWNER/'LIBRARY'/f'{k}.xml':native.xml_bytes(v) for k,v in generated.items()}
    doc_path = OWNER/'DOMDocument.xml'
    doc_text = doc_path.read_text(encoding='utf-8-sig')
    doc = E.fromstring(doc_text.encode('utf-8'),native.PARSER)
    includes = doc.find('./x:symbols',N)
    existing = {el.get('href') for el in includes}
    additions = []
    for name in sorted(generated):
        item_id = generated[name].get('itemID')
        if name+'.xml' not in existing:
            additions.append(f'    <Include href="{name}.xml" itemID="{item_id}" loadImmediate="false"/>\n')
        else:
            pattern = r'(<Include href="'+re.escape(name)+r'\.xml"[^>]*itemID=")[^"]*(")'
            doc_text = re.sub(pattern,lambda match:match[1]+item_id+match[2],doc_text)
    if additions:
        assert doc_text.count('</symbols>') == 1
        doc_text = doc_text.replace('</symbols>', ''.join(additions)+'</symbols>')
    folders = doc.find('./x:folders',N)
    existing = {el.get('name') for el in folders}
    additions = []
    for name in sorted({x.rsplit('/',1)[0] for x in generated} | {'Codex/铁卫犬'}):
        if name not in existing:
            additions.append(f'    <DOMFolderItem name="{name}" itemID="{native.item_id(name,"6b500000")}"/>\n')
    if additions:
        doc_text = doc_text.replace('  </folders>', ''.join(additions)+'  </folders>')
    output[doc_path] = doc_text.encode('utf-8')
    registered = {el.get('href') for el in E.fromstring(output[doc_path],native.PARSER).find('./x:symbols',N)}
    assert all(name+'.xml' in registered for name in generated), 'Incomplete native library Include closure'
    failures = []
    for path,data in output.items():
        if args.check:
            if not path.exists() or path.read_bytes()!=data:
                failures.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            if not path.exists() or path.read_bytes()!=data:
                path.write_bytes(data)
    if failures:
        raise SystemExit('Stale native assembly: '+', '.join(failures))
    manifest={'kind':KIND,'owner':str(OWNER.relative_to(ROOT)), 'symbols':len(generated),
        'runtimeSvgParts':50,'liveMouth':True,'lampFrames':2,'deathLampOff':True,
        'biteSupport':{'scope':'attack four-paw braced pose; connected body and rigid limbs', 'inputs':[
            {'path':str(p.relative_to(ROOT)), 'sha256':sha(p)}
            for p in (HERE/'bite_support.py',HERE/'bite-support.json',HERE/'mouth-web.svg')]},
        'parts':reports,'outputs':[{'path':str(p.relative_to(ROOT)), 'sha256':hashlib.sha256(d).hexdigest()}
                                   for p,d in sorted(output.items())]}
    if not args.check:
        (HERE/'native-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'check':args.check,'symbols':len(generated),'parts':50,'failures':len(failures)},ensure_ascii=False))


if __name__ == '__main__':
    main()
