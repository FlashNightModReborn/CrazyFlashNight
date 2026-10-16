"""Build the Wings R3 library from frozen vectors and the enhanced CF7 agent rig."""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import sys
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6Wings-R3'
OWNER = ROOT / 'flashswf/arts/new/CodexWings素材'
ANCHOR = 'CodexWings素材'
LINKAGE = '敌人-CF6Wings'
PREFIX = 'Codex/Wings/'
DONOR = ROOT / 'flashswf/arts/new/素材库-诺亚新敌人/LIBRARY'
DONOR_ROOT = '闪6特工/Symbol 776'
STAND = '闪6特工/MovieClip/sprite 854'
SPECIAL = '闪6特工/MovieClip/sprite 856'
COMBO = '闪6特工/MovieClip/sprite 861'
DEATH = '闪6特工/MovieClip/sprite 865'
WEAPON = '闪6特工/MovieClip/sprite 849'
SHADOW = '诺亚克隆兽/阴影'
POSES = {'闪6特工/人物服装/元件 2', '闪6特工/人物服装/元件 3'}
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{' + NS['x'] + '}'
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False, resolve_entities=False)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


common = module('wings_native_common', ROOT / 'tools/cf6-manman-assets/build.py')
vector = module('wings_vector', HERE / 'vector.py')
native = common.native
# Reuse the existing complete-workspace guard and shared-library writer in an isolated module.
for key, value in {'ROOT': ROOT, 'HERE': HERE, 'OWNER': OWNER, 'ARCHIVE': ARCHIVE,
                   'ANCHOR': ANCHOR, 'LINKAGE': LINKAGE, 'PREFIX': PREFIX}.items():
    setattr(common, key, value)
native.OWNER, native.HERE = OWNER, HERE
native.MANIFEST_SCHEMA = 'cf6-wings.native-import.v1'
native.PROJECT_FILES = ('DOMDocument.xml', ANCHOR + '.xfl', 'PublishSettings.xml', 'MobileSettings.xml')
PART_MAP = {old: old + 7 for old in (840, 841, 842, 843, 844, 845, 847, 850, 851, 852, 853)}
WEAPON_NAME = PREFIX + '武器/双枪刃'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_inputs():
    paths = [HERE / 'build.py', HERE / 'vector.py', HERE / 'WingsAI.as',
             ROOT / 'tools/cf6-manman-assets/build.py', ROOT / 'tools/cf6-zombie-assets/build.py',
             ROOT / 'tools/gamma-echo-assets/build.py',
             ROOT / 'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
             ROOT / 'tools/asset-metrology/xfl_geometry.py',
             ROOT / 'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml']
    return [{'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p)} for p in paths]


def set_script(frame, text):
    node = frame.find('x:Actionscript/x:script', NS)
    if node is None:
        node = E.SubElement(E.SubElement(frame, N + 'Actionscript'), N + 'script')
    node.text = E.CDATA(text)


def bind_weapon_instances(root):
    for layer_index, layer in enumerate(root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)):
        for frame in layer.findall('x:frames/x:DOMFrame', NS):
            for child_index, inst in enumerate(frame.findall('x:elements/x:DOMSymbolInstance', NS)):
                ref = inst.get('libraryItemName')
                if ref == WEAPON_NAME or ref in {PREFIX + 'CF7/' + p for p in POSES}:
                    inst.set('name', ('wingsGun' if ref == WEAPON_NAME else 'wingsPose') + str(layer_index) + '_' + str(child_index))
                    inst.set('symbolType', 'movie clip')
                    inst.attrib.pop('firstFrame', None)
                    inst.attrib.pop('loop', None)


def build_symbols():
    common.verify_input()
    timelines = json.loads((ARCHIVE / 'reference/timelines.json').read_text(encoding='utf8'))
    root_name, stand_name, death_name = PREFIX + LINKAGE, PREFIX + '动作/站立', PREFIX + '动作/死亡'
    mapped = {'闪6特工/人物服装/shape ' + str(old): PREFIX + '分件/' + str(cid) for old, cid in PART_MAP.items()}
    mapped.update({DONOR_ROOT: root_name, STAND: stand_name, DEATH: death_name, WEAPON: WEAPON_NAME})
    replacements = set(mapped) - {DONOR_ROOT}
    generated, source_rows, pending, originals = {}, [], [DONOR_ROOT], {}
    while pending:
        name = pending.pop()
        if name in replacements or name in originals:
            continue
        path = DONOR / (name + '.xml')
        source = E.parse(str(path), PARSER).getroot()
        if source.get('linkageImportForRS') == 'true' or source.findall('.//x:BitmapFill', NS):
            raise ValueError('Unexpected donor external/bitmap dependency: ' + name)
        originals[name] = source
        mapped.setdefault(name, PREFIX + 'CF7/' + name)
        source_rows.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path)})
        pending.extend(i.get('libraryItemName') for i in source.findall('.//x:DOMSymbolInstance', NS))

    for cid in (*PART_MAP.values(), 855):
        parts, _ = vector.NativePart(ARCHIVE / 'parts' / (str(cid) + '.svg'), PREFIX + '分件/' + str(cid), (0, 0)).build()
        generated.update(parts)
    marker_name = PREFIX + '武器/枪口定位'
    generated[marker_name] = native.symbol(marker_name, [native.layer('注册点', [native.frame(script='stop();')])], symbol_type='movie clip')
    generated[WEAPON_NAME] = native.symbol(WEAPON_NAME, [
        native.layer('真实枪口', [native.frame(script='wingsWeapon=true; stop();', elements=[
            native.instance(marker_name, matrix=(1, 0, 0, 1, -76.25, -32.9), symbol_type='movie clip', name='枪口')])]),
        native.layer('R3枪刃', [native.frame(elements=[native.instance(PREFIX + '分件/855')])]),
    ], symbol_type='movie clip')
    part_refs = {cid: PREFIX + '分件/' + str(cid) for cid in PART_MAP.values()}
    part_refs[856] = WEAPON_NAME
    generated[stand_name] = native.symbol(stand_name, [
        native.make_sparse_layer('躲闪结束', 15, {4: {'script': 'if(_parent.状态=="躲闪") _parent.动画完毕();'}}),
        *native.build_depth_layers(timelines['861'], part_refs),
    ], symbol_type='movie clip')
    generated[death_name] = native.symbol(death_name, [
        native.make_sparse_layer('CF7死亡回调', 132, {
            0: {'name': 'a0', 'label_type': 'name'}, 58: {'name': 'a1', 'label_type': 'name'},
            95: {'name': 'a2', 'label_type': 'name'},
            57: {'script': '_parent.死亡检测(); stop();'},
            94: {'script': '_parent.死亡检测(); stop();'},
            131: {'script': '_parent.死亡检测(); stop();'},
        }), *native.build_depth_layers(timelines['872'], part_refs),
    ], symbol_type='movie clip')
    stand_root = originals[DONOR_ROOT].find('.//x:DOMFrame[@index="0"]/x:elements/x:DOMSymbolInstance[@libraryItemName="' + STAND + '"]/x:matrix/x:Matrix', NS)
    if any(float(stand_root.get(k, str(v))) != v for k, v in [('a', 1), ('b', 0), ('c', 0), ('d', 1)]):
        raise ValueError('Donor standing scale changed; review source-space alignment')
    stand_pelvis = next(v['matrix'] for v in timelines['861'][0].values() if v['id'] == 852)
    death_pelvis = next(v['matrix'] for v in timelines['872'][0].values() if v['id'] == 852)
    death_matrix = (1, 0, 0, 1, float(stand_root.get('tx', '0')) + stand_pelvis[4] - death_pelvis[4],
                    float(stand_root.get('ty', '0')) + stand_pelvis[5] - death_pelvis[5])

    for name, original in originals.items():
        root = copy.deepcopy(original)
        new_name = mapped[name]
        root.set('name', new_name)
        root.set('itemID', native.item_id(new_name, '6b080000'))
        for key in ('linkageIdentifier', 'linkageExportForAS', 'linkageExportForRS', 'linkageImportForRS',
                    'linkageExportInFirstFrame', 'linkageURL', 'linkageClassName', 'lastModified', 'lastUniqueIdentifier'):
            root.attrib.pop(key, None)
        root.find('x:timeline/x:DOMTimeline', NS).set('name', new_name.rsplit('/', 1)[-1])
        for inst in root.findall('.//x:DOMSymbolInstance', NS):
            inst.set('libraryItemName', mapped[inst.get('libraryItemName')])
        if name == SHADOW:
            # This shadow is a direct unit child, not a child of the standard player rig.
            # Keep its authored ellipse and own the ground projection locally; the legacy
            # player flight writer assumes a different 233.05 baseline and parent scale.
            frame = root.find('.//x:DOMFrame[x:Actionscript]', NS)
            if '_parent._parent.shadow' not in frame.find('x:Actionscript/x:script', NS).text:
                raise ValueError('Donor shadow ownership changed; review before generating')
            set_script(frame, '''wingsGroundPoint = {x:0, y:0};
updateWingsShadow = function():Void {
    var unit:MovieClip = this._parent;
    var visible:Boolean = _root.是否阴影 == true;
    if(this._visible != visible) this._visible = visible;
    if(isNaN(unit.Z轴坐标)) return;
    var ground:Object = this.wingsGroundPoint;
    ground.x = unit._x;
    ground.y = unit.Z轴坐标;
    unit._parent.localToGlobal(ground);
    unit.globalToLocal(ground);
    if(this._x != ground.x) this._x = ground.x;
    if(this._y != ground.y) this._y = ground.y;
    var rotation:Number = unit._xscale < 0 ? unit._rotation : -unit._rotation;
    if(this._rotation != rotation) this._rotation = rotation;
};
onEnterFrame = updateWingsShadow;
updateWingsShadow();
stop();''')
        if name in POSES:
            root.set('symbolType', 'movie clip')
            root.find('x:timeline/x:DOMTimeline/x:layers', NS).insert(0, native.layer('姿势作用域', [native.frame(script='wingsPose=true; stop();')]))
        if name in (SPECIAL, COMBO):
            for frame in root.findall('.//x:DOMFrame', NS):
                script = frame.find('x:Actionscript/x:script', NS)
                if script is None or not script.text:
                    continue
                text = script.text
                if 'function 斩击' in text:
                    set_script(frame, 'function 斩击(){ _parent.wingsSlash(this,this.攻击点); }\n'
                        + ('function 射击(point,angle){ _parent.wingsShoot(this,point,angle); }\n' if name == SPECIAL else ''))
                elif int(frame.get('index')) == 0:
                    begin = '_parent.wingsBeginAttack(this,"combo");\n' if name == COMBO else (
                        '_parent.wingsBeginAttack(this,_parent.近战招式=="后空翻"?"flip":_parent.近战招式=="斩击"?"slash":"shoot");\n')
                    set_script(frame, begin + 'function 攻击时移动(amount){ _parent.wingsMove(this,amount,0); }\n'
                        + 'function Z轴追踪移动(amount){ _parent.wingsMove(this,0,amount); }\n'
                        + ('gotoAndPlay(_parent.近战招式);\n' if name == SPECIAL else ''))
                elif name == SPECIAL and int(frame.get('index')) == 60:
                    set_script(frame, '_parent.wingsFinishFlip(this);')
                elif '_parent.动画完毕();' in text:
                    set_script(frame, text.replace('_parent.动画完毕();', '_parent.wingsFinishAttack(this);'))
        if name == DONOR_ROOT:
            root.set('linkageExportForAS', 'true')
            root.set('linkageExportInFirstFrame', 'true')
            root.set('linkageIdentifier', LINKAGE)
            first = next(f for f in root.findall('.//x:DOMFrame[@index="0"]', NS) if f.find('x:Actionscript', NS) is not None)
            script = first.find('x:Actionscript/x:script', NS)
            script.text = E.CDATA((script.text or '') + '\n' + (HERE / 'WingsAI.as').read_text(encoding='utf-8-sig'))
            shadow_inst = root.find('.//x:DOMSymbolInstance[@libraryItemName="' + mapped[SHADOW] + '"]', NS)
            shadow_frame = shadow_inst.getparent().getparent()
            shadow_frames = shadow_frame.getparent()
            if shadow_frame.get('index') != '0' or shadow_frame.get('duration') != '79' or len(shadow_frames) != 2:
                raise ValueError('Donor shadow timeline changed; review state coverage')
            shadow_frame.set('duration', '120')
            shadow_frames[1].set('index', '120')
            shadow_frames[1].set('duration', '5')
            shadow_inst.set('name', 'wingsShadow')
            shadow_inst.set('symbolType', 'movie clip')
            shadow_inst.remove(shadow_inst.find('x:Actionscript', NS))
            for inst in root.findall('.//x:DOMSymbolInstance', NS):
                ref = inst.get('libraryItemName')
                if ref in {mapped[s] for s in (STAND, SPECIAL, COMBO, DEATH,
                    '闪6特工/MovieClip/sprite 855', '闪6特工/MovieClip/跑步', '闪6特工/MovieClip/sprite 862',
                    '闪6特工/MovieClip/sprite 863', '闪6特工/MovieClip/起身')}:
                    inst.set('name', 'man')
                if ref == death_name:
                    mx = inst.find('x:matrix/x:Matrix', NS)
                    mx.attrib.clear()
                    for k, v in zip(('a', 'b', 'c', 'd', 'tx', 'ty'), death_matrix):
                        mx.set(k, native.num(v))
                    common.event_script(inst, 'onClipEvent(load){ _parent.wingsCancelAttack(); gotoAndPlay("a"+random(3)); }')
                if ref == mapped['area框/索敌框载体']:
                    inst.set('name', 'wingsSensor')
                    script = inst.find('x:Actionscript/x:script', NS)
                    old = script.text
                    start = old.index('{')
                    end = old.rfind('}')
                    script.text = E.CDATA(old[:start + 1] + '\nif(_parent.WingsAI模式=="baseline" && !_root.暂停){\n' + old[start + 1:end] + '\n}\n' + old[end:])
            driver_name = PREFIX + '行为驱动'
            generated[driver_name] = native.symbol(driver_name, [native.layer('停止', [native.frame(script='stop();')])], symbol_type='movie clip')
            driver = native.instance(driver_name, symbol_type='movie clip', name='wingsDriver',
                script='onClipEvent(enterFrame){ _parent.wingsTick(); }')
            root.find('x:timeline/x:DOMTimeline/x:layers', NS).insert(0, native.layer('私有控制器', [native.frame(duration=125, elements=[driver])]))
        generated[new_name] = root
    for root in generated.values():
        bind_weapon_instances(root)
    return generated, root_name, sorted(source_rows, key=lambda row: row['path'])


def import_assets():
    native.guard_overwrite_allowed(False)
    generated, root_name, donors = build_symbols()
    native.guard_overwrite_allowed(False)
    outputs = common.write_workspace(generated, root_name)
    manifest = {'schema': native.MANIFEST_SCHEMA, 'owner': OWNER.relative_to(ROOT).as_posix(),
        'approvedInput': ARCHIVE.relative_to(ROOT).as_posix(), 'nativeSymbolCount': len(outputs), 'buildInputs': build_inputs(),
        'donor': {'rootSymbol': DONOR_ROOT, 'members': donors}, 'outputs': outputs,
        'projectFiles': [{'path': p, 'sha256': sha(OWNER / p), 'bytes': (OWNER / p).stat().st_size} for p in native.PROJECT_FILES]}
    (HERE / 'native-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    common.mount_shared_library()


def check():
    common.verify_input()
    manifest = json.loads((HERE / 'native-manifest.json').read_text(encoding='utf8'))
    failures = native.workspace_identity_failures(manifest)
    if manifest.get('buildInputs') != build_inputs():
        failures.append('Build recipe changed; perform protected regeneration')
    for row in manifest['donor']['members']:
        if sha(ROOT / row['path']) != row['sha256']:
            failures.append('Donor changed: ' + row['path'])
    if failures:
        raise ValueError('\n'.join(failures))
    print(json.dumps({'ok': True, 'symbols': len(manifest['outputs']), 'projectFiles': len(manifest['projectFiles'])}))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--import-approved', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.import_approved:
        import_assets()
    check()
