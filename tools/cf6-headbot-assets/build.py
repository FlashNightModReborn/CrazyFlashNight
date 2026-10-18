"""CF6 Headbot R3 native vectors, original action timing and CF7 combat authority."""
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
ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6大头机器人-R3'
OWNER = ROOT / 'flashswf/arts/new/Codex大头机器人素材'
ANCHOR = 'Codex大头机器人素材'
LINKAGE = '敌人-CF6大头机器人'
PREFIX = 'Codex/大头机器人/'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{' + NS['x'] + '}'
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False, resolve_entities=False)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


audio = module('cf6_audio_native',ROOT/'tools/cf6-audio/build.py')
common = module('headbot_common', ROOT / 'tools/cf6-manman-assets/build.py')
vector = module('headbot_vector', HERE / 'vector.py')
corpse = module('headbot_corpse', HERE / 'corpse.py')
debris = module('headbot_debris', HERE / 'debris.py')
death = module('headbot_death', HERE / 'robot_death.py')
native = common.native
for key, value in {'ROOT': ROOT, 'HERE': HERE, 'OWNER': OWNER, 'ARCHIVE': ARCHIVE,
                   'ANCHOR': ANCHOR, 'LINKAGE': LINKAGE, 'PREFIX': PREFIX}.items():
    setattr(common, key, value)
native.OWNER, native.HERE = OWNER, HERE
native.MANIFEST_SCHEMA = 'cf6-headbot.native-import.v1'
native.PROJECT_FILES = ('DOMDocument.xml', ANCHOR + '.xfl', 'PublishSettings.xml', 'MobileSettings.xml')
native.SHARED_HELPERS = {old: PREFIX + 'CF7/' + old for old in native.SHARED_HELPERS}
H = native.SHARED_HELPERS
# Ground is the original standing shadow center; the body intentionally floats.
GROUND_SHIFT = -(98.9 * 1.0999908447265625 - 108.45)
OFFSETS = {933: (18.3, -108.45), 936: (4.75, -62.05), 937: (26.5, -53.5),
           938: (8.95, -59.95), 951: (7, -60.15)}
SCALES = {933: 1.0999908447265625, 936: 1, 937: 1, 938: 1, 951: 1}
BEAM_WINDUP = 12
ATTACKS = {'beam': {'id': 936, 'state': '空手攻击', 'hits': [15, 23], 'power': 1.5, 'damageType': '魔法', 'magicAttribute': '波'},
           'thrust': {'id': 937, 'state': '近战', 'hits': [3, 5, 8, 12], 'power': 1, 'damageType': '物理'}}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_inputs():
    paths = [HERE / 'build.py', HERE / 'vector.py', HERE / 'HeadbotAI.as', HERE / 'CorpseFragments.as', HERE / 'corpse.py',
        ROOT / 'tools/cf6-guard-assets/vector.py', ROOT / 'tools/cf6-guard-assets/clipped_vector.py',
        ROOT / 'tools/cf6-guard-assets/clip-vectors.ps1',
        ROOT / 'tools/cf6-wings-assets/vector.py', ROOT / 'tools/cf6-manman-assets/build.py',
        ROOT / 'tools/cf6-zombie-assets/build.py', ROOT / 'tools/gamma-echo-assets/build.py',
        ROOT / 'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
        ROOT / 'tools/asset-metrology/xfl_geometry.py',
        ROOT / 'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml']
    paths += [native.THINGS1 / (old + '.xml') for old in sorted(H)]
    paths += [HERE/'debris.py',*death.input_paths()]
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


def make_body(name, timeline, parts, scripts=None, hits=None):
    count = len(timeline)
    return native.symbol(name, [native.make_sparse_layer('CF7控制', count, scripts or {}),
        native.layer('身体内部时钟', [native.frame(0, count, [native.instance(PREFIX+'行为驱动',
            symbol_type='movie clip', name='headbotBodyDriver',
            script='onClipEvent(enterFrame){_parent._parent.headbotBodyTick(_parent);}')])]),
        native.make_sparse_layer('真实攻击区域', count, hits or {}),
        *depth_layers(timeline, parts),
        native.layer('独立接地阴影', [native.frame(0, count, [native.instance(PREFIX+'接地阴影',
            symbol_type='movie clip', name='headbotShadow')])])], symbol_type='movie clip')


def build_symbols():
    common.verify_input()
    timeline = json.loads((ARCHIVE/'reference/timelines.json').read_text(encoding='utf8'))
    result, parts, stats = native.clone_shared_helpers(), {}, []
    for cid in [926, *range(928, 933), *range(939, 951), 903, 935]:
        name = PREFIX + ('死亡碎片/' if 941 <= cid <= 950 else '分件/') + str(cid)
        if cid in (903, 935):
            origin = (23.25, 23.25) if cid == 903 else (148.55, 8.25)
            converted, report = vector.original_effect(ARCHIVE/'reference/original-effects'/(str(cid)+'.svg'), name, origin)
        elif cid == 926:
            converted, report = vector.original_effect(ARCHIVE/'parts/926.svg', name, (0, 0))
        else:
            converted, report = vector.NativePart(ARCHIVE/'parts'/(str(cid)+'.svg'), name, (0, 0)).build()
        for key, item in converted.items():
            if key in result and native.xml_bytes(result[key]) != native.xml_bytes(item):
                raise ValueError('Conflicting shared vector atlas: '+key)
        result.update(converted)
        parts[cid] = name
        stats.append({'id': cid, **report})

    # 934 is a one-frame arm wrapper, including the source local registration.
    parts[934] = PREFIX+'分件/934'
    result[parts[934]] = native.symbol(parts[934], depth_layers(timeline['934'], parts))
    cut_symbols,torso_pieces,cut_reports = debris.torso_parts(vector,ARCHIVE/'parts/929.svg',PREFIX)
    result.update(cut_symbols)
    stats.append({'id':929,'kind':'nine-complementary-death-pieces','pieces':cut_reports})
    shadow_part = parts.pop(926)
    names = {sid: PREFIX+'动作/'+label for sid, label in [(933,'悬浮'), (936,'双臂光束'),
             (937,'伸缩冲击'), (938,'被击'), (951,'机械碎裂')]}
    result[names[933]] = make_body(names[933], timeline['933'], parts,
        {0: {'script': 'headbotMode="idle";stop();'},
         4: {'script': 'if(_parent.状态=="躲闪" || _parent.状态=="拾取")_parent.动画完毕();'}})
    for action, spec in ATTACKS.items():
        frames = timeline[str(spec['id'])]
        if action == 'beam': frames = [copy.deepcopy(frames[0]) for _ in range(BEAM_WINDUP)] + frames
        events = {0: {'script': 'headbotMode="attack";_parent.headbotBeginAttack(this,"'+action+'");stop();'},
                  len(frames)-1: {'script': '_parent.headbotFinishAttack(this);stop();'}}
        hits = {}
        for f in spec['hits']:
            original = next(row for row in frames[f-1].values() if row['id'] == 290)
            m = original['matrix']
            # Preserve CF6's horizontal contact span. CF7 needs a vertical area
            # around the visible laser / extended tray, not the old ground test.
            width = 66*abs(m[0])
            center_x = m[4]
            visual_id = 935 if action == 'beam' else 931
            visual = next(row for row in frames[f-1].values() if row['id'] == visual_id)
            height = 30 if action == 'beam' else 50
            center_y = visual['matrix'][5]
            hits[f-1] = {'elements': [native.instance(H['Symbol 195'],
                matrix=(width/25, 0, 0, height/25, center_x, center_y),
                symbol_type='movie clip', name='攻击点',
                script='onClipEvent(load){headbotToken=_parent.headbotToken;headbotHitFrame=_parent._currentframe;_parent._parent.headbotStrike(_parent,this,'+str(spec['power'])+');}',
                alpha_mult=0)]}
        result[names[spec['id']]] = make_body(names[spec['id']], frames, parts, events, hits)
        if action == 'beam':
            charge = {}
            for f in range(BEAM_WINDUP):
                scale = 0.2 + 0.45 * f / (BEAM_WINDUP-1)
                charge[f] = {'elements': [native.instance(parts[903], matrix=(scale,0,0,scale,x,-35.3),
                    alpha_mult=0.25+0.65*f/(BEAM_WINDUP-1)) for x in (99,14)]}
            result[names[spec['id']]].find('x:timeline/x:DOMTimeline/x:layers', NS).insert(0,
                native.make_sparse_layer('双臂蓄光前摇', len(frames), charge))

    result[names[938]] = make_body(names[938], timeline['938'], parts, {
        0: {'name': 'a0', 'label_type': 'name', 'script': 'headbotMode="hit";stop();'},
        6: {'name': 'a1', 'label_type': 'name', 'script': 'headbotMode="hit";stop();'},
        5: {'script': '_parent.动画完毕();'}, 11: {'script': '_parent.动画完毕();'}})
    result[names[951]] = make_body(names[951], timeline['951'][:18]+[{} for _ in range(40)], parts, {
        0: {'name': 'a0', 'label_type': 'name', 'script': 'headbotMode="death";_parent.headbotCancelAttack();_parent.cf6ArmRobotDeath(this,19);stop();'},
        4: {'script': '_parent.headbotDeathFx();'},
        57: {'script': '_parent.cf6FinishCorpse(this);stop();'}})
    result[names[951]].find('x:timeline/x:DOMTimeline/x:layers', NS).insert(0,
        corpse.fragment_layer(native,result,parts,timeline['951'][17],PREFIX+'尸体碎片',18,58,{929:torso_pieces}))
    death.add(native,result,PREFIX,names[951],(1,0,0,1,7,-60.15+GROUND_SHIFT),19,58,H['Symbol 195'])

    driver = PREFIX+'行为驱动'
    result[driver] = native.symbol(driver, [native.layer('停止',[native.frame(script='stop();')])], symbol_type='movie clip')
    result[PREFIX+'接地阴影'] = native.symbol(PREFIX+'接地阴影', [native.layer('接地更新', [native.frame(script='''headbotGround={x:0,y:0};
updateHeadbotShadow=function():Void {
    var body:MovieClip=this._parent,unit:MovieClip=body._parent;
    var visible:Boolean=_root.是否阴影==true;
    if(this._visible!=visible) this._visible=visible;
    if(isNaN(unit.Z轴坐标)) return;
    var p:Object=this.headbotGround; p.x=unit._x; p.y=unit.Z轴坐标;
    unit._parent.localToGlobal(p); body.globalToLocal(p);
    if(this._x!=p.x) this._x=p.x; if(this._y!=p.y) this._y=p.y;
    this._xscale=10999.908447265625/body._xscale;
    this._yscale=3985.443115234375/body._yscale;
};
onEnterFrame=updateHeadbotShadow;updateHeadbotShadow();stop();''',
        elements=[native.instance(shadow_part)])])], symbol_type='movie clip')

    def body(sid, script=None, name=None):
        x, y = OFFSETS[sid]
        scale = SCALES[sid]
        return native.instance(name or names[sid], matrix=(scale,0,0,scale,x,y+GROUND_SHIFT),
                               symbol_type='movie clip', name='man', script=script)

    states = {1:'空手站立',9:'空手行走',19:'空手跑',29:'空手跳',37:'近战',41:'空手攻击',
              51:'拾取',61:'躲闪',71:'被击',79:'击倒',88:'倒地',95:'被投',104:'血腥死',120:'消失'}
    root_name = PREFIX+LINKAGE
    init = '''x轴攻击范围=0;y轴攻击范围=24;x轴保持距离=290;攻击欲望=3;击中效果="火花";命中率=30;
女_攻击呐喊_库=[]; 女_中招呐喊_库=[]; 女_击倒呐喊_库=[];
初始化敌人模板=_root.初始化敌人模板; 初始化敌人模板();
'''+ 'headbotActions={'+','.join(action+':{hits:'+json.dumps(spec['hits'])+',power:'+str(spec['power'])+'}' for action,spec in ATTACKS.items())+'};\n'+(HERE/'HeadbotAI.as').read_text(encoding='utf-8-sig')+'\n'+(HERE/'CorpseFragments.as').read_text('utf-8-sig')+'\n'+(HERE/'RobotDeath.as').read_text('utf-8-sig')
    hit = 'onClipEvent(load){gotoAndStop("a"+random(2));}'
    bodies = {0:(9,body(933)),9:(10,body(933)),19:(10,body(933)),29:(8,body(933)),
        37:(4,body(937)),41:(10,body(936)),51:(10,body(933)),61:(10,body(933)),
        71:(8,body(938,hit)),79:(9,body(938,hit)),88:(7,body(938,hit)),
        95:(9,body(938,hit)),104:(16,body(951))}
    result[root_name] = native.symbol(root_name, [
        native.make_sparse_layer('状态标签',125,{i:{'name':s,'label_type':'name'} for i,s in states.items()}),
        native.make_sparse_layer('初始化与消失',125,{0:{'script':init},1:{'script':'this.swapDepths(this._y);'},120:{'script':'hp=0; headbotCancelAttack();'}}),
        native.make_sparse_layer('私有行为',125,{0:{'duration':120,'elements':[native.instance(driver,symbol_type='movie clip',name='headbotDriver',script='onClipEvent(enterFrame){ _parent.headbotTick(); }')]}}),
        native.make_sparse_layer('文字信息',125,{0:{'duration':120,'elements':[native.instance(H['Symbol 32'],matrix=(1,0,0,1,0,-192),symbol_type='movie clip',name='人物文字信息')]}}),
        native.make_sparse_layer('受击包围盒',125,{0:{'duration':104,'elements':[native.instance(H['Symbol 19'],matrix=(4.24,0,0,6.8,-53,-178),symbol_type='movie clip',name='area')]}}),
        native.make_sparse_layer('通用仇恨驱动',125,{0:{'duration':29,'elements':[native.instance(H['思考标签'],symbol_type='movie clip') ]}}),
        native.make_sparse_layer('行走',125,{0:{'duration':29,'elements':[native.instance(driver,symbol_type='movie clip',name='控制块',script='onClipEvent(enterFrame){ if(!_root.暂停) _parent.行走(); }')]}}),
        native.make_sparse_layer('动作',125,{i:{'duration':d,'elements':[b]} for i,(d,b) in bodies.items()}),
    ], symbol_type='movie clip', linkage=LINKAGE, export_first_frame=True)
    return result, root_name, stats


def import_assets():
    native.guard_overwrite_allowed(False)
    symbols, root_name, stats = build_symbols()
    native.guard_overwrite_allowed(False)
    audio_receipt=audio.apply(symbols,OWNER,native.make_sparse_layer)
    outputs = common.write_workspace(symbols, root_name)
    # Vector adapters own their DOMSymbolItem IDs; Include must use those exact IDs.
    document=E.parse(str(OWNER/'DOMDocument.xml'),PARSER)
    for include in document.findall('x:symbols/x:Include',NS):
        symbol=E.parse(str(OWNER/'LIBRARY'/include.get('href')),PARSER).getroot()
        include.set('itemID',symbol.get('itemID'))
    (OWNER/'DOMDocument.xml').write_bytes(native.xml_bytes(document.getroot()))
    manifest = {'schema':native.MANIFEST_SCHEMA,'owner':OWNER.relative_to(ROOT).as_posix(),
        'approvedInput':ARCHIVE.relative_to(ROOT).as_posix(),'nativeSymbolCount':len(outputs),
        'buildInputs':build_inputs(),'parts':stats,'actions':ATTACKS,'groundShift':GROUND_SHIFT,
        'sourceOffsets':{str(k):v for k,v in OFFSETS.items()},'sourceScales':SCALES,
        'sourceVisualFrames':183,'replacedOriginalControls':[290,299,311,360,914],
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
    includes={i.get('href'):i.get('itemID') for i in E.parse(str(OWNER/'DOMDocument.xml')).findall('x:symbols/x:Include',NS)}
    for row in manifest['outputs']:
        tree=E.parse(str(OWNER/row['path']),PARSER)
        if row['path'][8:] not in includes: errors.append('Missing Include: '+row['path'])
        elif includes[row['path'][8:]]!=tree.getroot().get('itemID'):errors.append('Include identity differs: '+row['path'])
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
