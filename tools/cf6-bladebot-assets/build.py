"""CF6 Bladebot R2 native vectors, CF7 lifecycle, and unit-private blade / wave-beam control."""
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
ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6大刀机器人-R2'
OWNER = ROOT / 'flashswf/arts/new/Codex大刀机器人素材'
ANCHOR = 'Codex大刀机器人素材'
LINKAGE = '敌人-CF6大刀机器人'
PREFIX = 'Codex/大刀机器人/'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{' + NS['x'] + '}'
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False, resolve_entities=False)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


audio = module('cf6_audio_native',ROOT/'tools/cf6-audio/build.py')
common = module('bladebot_common', ROOT / 'tools/cf6-manman-assets/build.py')
vector = module('bladebot_vector', HERE / 'vector.py')
death = module('bladebot_death', ROOT/'tools/cf6-headbot-assets/robot_death.py')
native = common.native
for key, value in {'ROOT': ROOT, 'HERE': HERE, 'OWNER': OWNER, 'ARCHIVE': ARCHIVE,
                   'ANCHOR': ANCHOR, 'LINKAGE': LINKAGE, 'PREFIX': PREFIX}.items():
    setattr(common, key, value)
native.OWNER, native.HERE = OWNER, HERE
native.MANIFEST_SCHEMA = 'cf6-bladebot.native-import.v1'
native.PROJECT_FILES = ('DOMDocument.xml', ANCHOR + '.xfl', 'PublishSettings.xml', 'MobileSettings.xml')
native.SHARED_HELPERS = {old: PREFIX + 'CF7/' + old for old in native.SHARED_HELPERS}
H = native.SHARED_HELPERS
# The source root has its feet 44.0325 px below the origin. Keep every action's
# original registration, applying the same grounding translation to the root.
GROUND_SHIFT = -44.03251647949219
OFFSETS = {906: (4.75, -62.05), 901: (22.5, -76.55), 902: (21.5, -80.7), 910: (26.5, -53.5),
           912: (21.5, -79.55), 913: (8.95, -59.95), 924: (7, -61.0)}
# Death's first pose is 0.85 px lower in the original; align the identical pelvis.
ATTACKS = {'cleave': {'id': 910, 'state': '空手攻击', 'hits': [20, 22], 'hitboxSourceFrames': {22: 20}, 'power': 2.4},
           'sweep': {'id': 912, 'state': '近战', 'hits': [19, 22, 25, 28, 31, 34], 'power': 1.0},
           'beam': {'id': 906, 'state': '激光束', 'hits': [11], 'power': 1.0, 'damageType': '魔法', 'magicAttribute': '波'}}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_inputs():
    paths = [HERE / 'build.py', HERE / 'vector.py', HERE / 'BladebotAI.as',
        ROOT / 'tools/cf6-wings-assets/vector.py', ROOT / 'tools/cf6-manman-assets/build.py',
        ROOT / 'tools/cf6-zombie-assets/build.py', ROOT / 'tools/gamma-echo-assets/build.py',
        ROOT / 'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
        ROOT / 'tools/asset-metrology/xfl_geometry.py',
        ROOT / 'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml']
    paths += [native.THINGS1 / (old + '.xml') for old in sorted(H)]
    paths += death.input_paths()
    return [{'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p)} for p in paths]


def depth_layers(timeline, parts):
    """Retain display-list depth, matrices and full color transforms, skipping CF6 controls."""
    layers = []
    for depth in sorted({int(d) for fr in timeline for d, row in fr.items() if row['id'] in parts}, reverse=True):
        states = [fr.get(str(depth)) if fr.get(str(depth), {}).get('id') in parts else None for fr in timeline]
        frames, start = [], 0
        while start < len(states):
            row, end = states[start], start+1
            # Placement bookkeeping is not visual; color changes are visual.
            visual = lambda value: None if value is None else (value['id'], value['matrix'], value.get('colorMult'), value.get('colorAdd'))
            while end < len(states) and visual(states[end]) == visual(row):
                end += 1
            elements = []
            if row is not None:
                inst = native.instance(parts[row['id']], matrix=row['matrix'])
                if row['id'] == 905:
                    inst.set('symbolType', 'movie clip')
                    inst.set('name', 'bladebotBeamVisual')
                    actions = E.SubElement(inst, N+'Actionscript')
                    E.SubElement(actions, N+'script').text = E.CDATA('onClipEvent(load){_parent._parent.bladebotAimPart(this);}')
                mult, add = row.get('colorMult', [256]*4), row.get('colorAdd', [0]*4)
                if mult != [256]*4 or add != [0]*4:
                    color = E.SubElement(E.SubElement(inst, N+'color'), N+'Color')
                    for i, channel in enumerate(('red', 'green', 'blue', 'alpha')):
                        color.set(channel+'Multiplier', native.num(mult[i]/256))
                        color.set(channel+'Offset', native.num(add[i]))
                elements.append(inst)
            frames.append(native.frame(start, end-start, elements))
            start = end
        layers.append(native.layer('原始深度_' + str(depth), frames))
    return layers


def make_body(sid, name, timeline, parts, scripts=None):
    return native.symbol(name, [native.make_sparse_layer('CF7控制', len(timeline), scripts or {}),
                               *depth_layers(timeline, parts)], symbol_type='movie clip')


def build_symbols():
    common.verify_input()
    timeline = json.loads((ARCHIVE/'reference/timelines.json').read_text(encoding='utf8'))
    result, parts, stats = native.clone_shared_helpers(), {}, []
    for cid in [*range(890, 901), *range(916, 924), 903, 905, 909]:
        folder = 'parts' if cid < 901 else 'reference' if cid in (903,905,909) else 'death-parts'
        name = PREFIX + ('死亡碎片/' if cid > 915 else '分件/') + str(cid)
        converted, report = vector.NativePart(ARCHIVE/folder/(str(cid)+'.svg'), name, (0, 0)).build()
        for key, item in converted.items():
            if key in result and native.xml_bytes(result[key]) != native.xml_bytes(item):
                raise ValueError('Conflicting shared vector atlas: '+key)
        result.update(converted)
        parts[cid] = name
        stats.append({'id': cid, **report})

    beam_wrapper=PREFIX+'分件/可瞄准光束'
    result[beam_wrapper]=native.symbol(beam_wrapper,[native.layer('原始光束',[native.frame(elements=[native.instance(parts[905])])])],symbol_type='movie clip')
    parts[905]=beam_wrapper

    names = {sid: PREFIX+'动作/'+label for sid, label in [(901,'站立'), (902,'行走'),
             (906,'波属性光束'), (910,'重劈'), (912,'横扫'), (913,'被击'), (924,'机械碎裂')]}
    result[names[901]] = make_body(901, names[901], timeline['901'], parts,
        {4: {'script': 'if(_parent.状态=="躲闪" || _parent.状态=="拾取") _parent.动画完毕();'}})
    result[names[902]] = make_body(902, names[902], timeline['902'], parts)
    for action, spec in ATTACKS.items():
        frames = timeline[str(spec['id'])]
        events = {0: {'script': '_parent.bladebotBeginAttack(this,"'+action+'");stop();'},
                  len(frames)-1: {'script': '_parent.bladebotFinishAttack(this);'}}
        if action == 'cleave':
            for f in range(9, 19):
                events[f-1] = {'script': '_parent.bladebotAdvance(this,8);'}
        hits = {}
        for f in spec['hits']:
            source_frame = spec.get('hitboxSourceFrames', {}).get(f, f)
            if source_frame != f:
                # CF7's second heavy contact uses the same held blade pose,
                # not a second visual swing or an unrelated hitbox.
                weapon = lambda n: [row['matrix'] for row in frames[n-1].values() if row['id'] == 899]
                if weapon(source_frame) != weapon(f):
                    raise ValueError('Held heavy-contact blade pose changed')
            original = next(row for row in frames[source_frame-1].values() if row['id'] == 290)
            m = original['matrix']
            # CF6's helper is a ground projection. In CF7 the melee area is the
            # vertical swept blade volume; retain the authored horizontal span.
            if action == 'beam':
                beam = next(row['matrix'] for row in frames[f-1].values() if row['id'] == 905)
                width, height = 619.05, 32
                center_x, center_y = beam[4]+292.925, beam[5]-16.35
            else:
                width = 66*abs(m[0])
                center_x = m[4]
                height = 180 if action == 'cleave' else 200
                center_y = -height/2 - OFFSETS[spec['id']][1] - GROUND_SHIFT
            hits[f-1] = {'elements': [native.instance(H['Symbol 195'],
                matrix=(width/25, 0, 0, height/25, center_x, center_y),
                symbol_type='movie clip', name='攻击点',
                script='onClipEvent(load){ bladebotToken=_parent.bladebotToken;bladebotHitFrame=_parent._currentframe;_parent._parent.bladebotStrike(_parent,this,'+str(spec['power'])+'); }',
                alpha_mult=0)]}
        result[names[spec['id']]] = native.symbol(names[spec['id']], [
            native.make_sparse_layer('攻击生命周期', len(frames), events),
            native.layer('身体内部攻击时钟',[native.frame(0,len(frames),[native.instance(PREFIX+'行为驱动',symbol_type='movie clip',
                name='bladebotBodyDriver',script='onClipEvent(enterFrame){_parent._parent.bladebotBodyTick(_parent);}')])]),
            native.make_sparse_layer('真实近战判定', len(frames), hits),
            *depth_layers(frames, parts)], symbol_type='movie clip')

    result[names[913]] = make_body(913, names[913], timeline['913'], parts, {
        0: {'name': 'a0', 'label_type': 'name'}, 12: {'name': 'a1', 'label_type': 'name'},
        7: {'script': '_parent.动画完毕();'}, 18: {'script': '_parent.动画完毕();'}})
    result[names[924]] = make_body(924, names[924], timeline['924'], parts, {
        0: {'name': 'a0', 'label_type': 'name', 'script': 'bladebotMode="death";_parent.bladebotCancelAttack();_parent.cf6ArmRobotDeath(this,32);stop();'},
        4: {'script': '_parent.bladebotDeathFx();'},
        57: {'script': '_parent.死亡检测(); stop();'}})
    result[names[924]].find('x:timeline/x:DOMTimeline/x:layers',NS).insert(0,
        native.layer('死亡内部时钟',[native.frame(0,len(timeline['924']),[
            native.instance(PREFIX+'行为驱动',symbol_type='movie clip',name='bladebotBodyDriver',
                script='onClipEvent(enterFrame){_parent._parent.bladebotBodyTick(_parent);}')])]))
    death.add(native,result,PREFIX,names[924],(1,0,0,1,7,-61+GROUND_SHIFT),32,len(timeline['924']),H['Symbol 195'])
    knocked, down = PREFIX+'动作/击飞姿势', PREFIX+'动作/倒地恢复'
    result[knocked] = make_body(913, knocked, [timeline['913'][12]], parts,
        {0: {'name': '空手', 'label_type': 'name', 'script': 'stop();'}})
    result[down] = make_body(913, down, [timeline['913'][12]]*25, parts,
        {8: {'script': '_parent.死亡检测();'}, 24: {'script': '_parent.动画完毕();'}})

    driver = PREFIX+'行为驱动'
    result[driver] = native.symbol(driver, [native.layer('停止',[native.frame(script='stop();')])], symbol_type='movie clip')
    shadow = result[H['Symbol 2']]
    shadow.set('symbolType', 'movie clip')
    shadow.find('x:timeline/x:DOMTimeline/x:layers', NS).insert(0, native.layer('独立接地更新', [native.frame(script='''bladebotGround={x:0,y:0};
updateBladebotShadow=function():Void {
    var unit:MovieClip=this._parent;
    var visible:Boolean=_root.是否阴影==true;
    if(this._visible!=visible) this._visible=visible;
    if(isNaN(unit.Z轴坐标)) return;
    var p:Object=this.bladebotGround; p.x=unit._x; p.y=unit.Z轴坐标;
    unit._parent.localToGlobal(p); unit.globalToLocal(p);
    if(this._x!=p.x) this._x=p.x; if(this._y!=p.y) this._y=p.y;
    var rotation:Number=unit._xscale<0?unit._rotation:-unit._rotation;
    if(this._rotation!=rotation) this._rotation=rotation;
};
onEnterFrame=updateBladebotShadow; updateBladebotShadow(); stop();''')]))

    def body(sid, script=None, name=None):
        x, y = OFFSETS[sid]
        return native.instance(name or names[sid], matrix=(1,0,0,1,x,y+GROUND_SHIFT),
                               symbol_type='movie clip', name='man', script=script)

    states = {1:'空手站立',9:'空手行走',19:'空手跑',29:'空手跳',37:'近战',41:'空手攻击',
              51:'激光束',61:'拾取',71:'躲闪',81:'被击',89:'击倒',98:'倒地',105:'被投',114:'血腥死',130:'消失'}
    root_name = PREFIX+LINKAGE
    init = '''x轴攻击范围=0; y轴攻击范围=30; x轴保持距离=185; 攻击欲望=3; 击中效果="火花"; 命中率=30;
女_攻击呐喊_库=[]; 女_中招呐喊_库=[]; 女_击倒呐喊_库=[];
初始化敌人模板=_root.初始化敌人模板; 初始化敌人模板();
'''+(HERE/'BladebotAI.as').read_text(encoding='utf-8-sig')+'\n'+(ROOT/'tools/cf6-headbot-assets/RobotDeath.as').read_text('utf-8-sig')
    bodies = {0:(9,body(901)),9:(10,body(902)),19:(10,body(902)),29:(8,body(901)),
        37:(4,body(912)),41:(10,body(910)),51:(10,body(906)),61:(10,body(901)),71:(10,body(901)),
        81:(8,body(913,'onClipEvent(load){ _parent.bladebotCancelAttack(); gotoAndPlay("a"+random(2)); }')),
        89:(9,body(913,'onClipEvent(load){ _parent.bladebotCancelAttack(); _parent.击飞浮空(); }',knocked)),
        98:(7,body(913,'onClipEvent(load){ _parent.bladebotCancelAttack(); _parent.击飞倒地(); }',down)),
        105:(9,body(913,'onClipEvent(load){ _parent.bladebotCancelAttack(); stop(); }',knocked)),
        114:(16,body(924))}
    result[root_name] = native.symbol(root_name, [
        native.make_sparse_layer('状态标签',135,{i:{'name':s,'label_type':'name'} for i,s in states.items()}),
        native.make_sparse_layer('初始化与消失',135,{0:{'script':init},1:{'script':'this.swapDepths(this._y);'},130:{'script':'hp=0; bladebotCancelAttack();'}}),
        native.make_sparse_layer('私有行为',135,{0:{'duration':130,'elements':[native.instance(driver,symbol_type='movie clip',name='bladebotDriver',script='onClipEvent(enterFrame){ _parent.bladebotTick(); }')]}}),
        native.make_sparse_layer('文字信息',135,{0:{'duration':130,'elements':[native.instance(H['Symbol 32'],matrix=(1,0,0,1,0,-182),symbol_type='movie clip',name='人物文字信息')]}}),
        native.make_sparse_layer('受击包围盒',135,{0:{'duration':114,'elements':[native.instance(H['Symbol 19'],matrix=(5.4,0,0,6,-67.5,-158),symbol_type='movie clip',name='area')]}}),
        native.make_sparse_layer('通用仇恨驱动',135,{0:{'duration':29,'elements':[native.instance(H['思考标签'],symbol_type='movie clip') ]}}),
        native.make_sparse_layer('行走',135,{0:{'duration':29,'elements':[native.instance(driver,symbol_type='movie clip',name='控制块',script='onClipEvent(enterFrame){ if(!_root.暂停) _parent.行走(); }')]}}),
        native.make_sparse_layer('动作',135,{i:{'duration':d,'elements':[b]} for i,(d,b) in bodies.items()}),
        native.make_sparse_layer('全状态接地阴影',135,{0:{'duration':130,'elements':[native.instance(H['Symbol 2'],matrix=(0.95,0,0,0.2,0,0),symbol_type='movie clip',name='bladebotShadow')]}}),
    ], symbol_type='movie clip', linkage=LINKAGE, export_first_frame=True)
    return result, root_name, stats


def import_assets():
    native.guard_overwrite_allowed(False)
    symbols, root_name, stats = build_symbols()
    native.guard_overwrite_allowed(False)
    audio_receipt=audio.apply(symbols,OWNER,native.make_sparse_layer)
    outputs = common.write_workspace(symbols, root_name)
    manifest = {'schema':native.MANIFEST_SCHEMA,'owner':OWNER.relative_to(ROOT).as_posix(),
        'approvedInput':ARCHIVE.relative_to(ROOT).as_posix(),'nativeSymbolCount':len(outputs),
        'buildInputs':build_inputs(),'parts':stats,'actions':ATTACKS,'groundShift':GROUND_SHIFT,
        'sourceOffsets':{str(k):v for k,v in OFFSETS.items()},'restoredOriginalAttack':906,
        'sharedDeathEffects':['火花','小烟雾'],'outputs':outputs,
        'projectFiles':[{'path':p,'sha256':sha(OWNER/p),'bytes':(OWNER/p).stat().st_size} for p in native.PROJECT_FILES]}
    manifest['audio']=audio_receipt
    (HERE/'native-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
    common.mount_shared_library()
    print(json.dumps({'symbols':len(outputs),'linkage':LINKAGE},ensure_ascii=False))


def check():
    common.verify_input()
    manifest = json.loads((HERE/'native-manifest.json').read_text(encoding='utf8'))
    audio.check(manifest,OWNER)
    errors = native.workspace_identity_failures(manifest)
    if manifest['buildInputs'] != build_inputs(): errors.append('Generator/AI inputs changed; guarded regeneration required')
    includes={i.get('href') for i in E.parse(str(OWNER/'DOMDocument.xml')).findall('x:symbols/x:Include',NS)}
    for row in manifest['outputs']:
        tree=E.parse(str(OWNER/row['path']),PARSER)
        if row['path'][8:] not in includes: errors.append('Missing Include: '+row['path'])
        for el in tree.iter():
            ref=el.get('libraryItemName')
            if ref and not (OWNER/'LIBRARY'/(ref+'.xml')).is_file(): errors.append('Unresolved '+ref)
        if tree.findall('.//x:BitmapFill',NS) or tree.findall('.//x:DOMBitmapInstance',NS): errors.append('Unexpected bitmap '+row['path'])
    if errors: raise ValueError('\n'.join(errors))
    print(json.dumps({'ok':True,'symbols':len(manifest['outputs']),'projectFiles':len(manifest['projectFiles'])}))


if __name__ == '__main__':
    if hasattr(sys.stdout,'reconfigure'): sys.stdout.reconfigure(encoding='utf8')
    parser=argparse.ArgumentParser()
    parser.add_argument('--import-approved',action='store_true')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if args.import_approved: import_assets()
    check()
