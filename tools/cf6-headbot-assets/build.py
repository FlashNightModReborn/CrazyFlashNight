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
R8_BAKED = HERE / 'r8-baked'
ATTACKS = {'beam': {'id': 936, 'state': '空手攻击', 'hits': [15, 23], 'power': 1.5, 'damageType': '魔法', 'magicAttribute': '波'},
           'thrust': {'id': 937, 'state': '近战', 'hits': [3, 5, 8, 12], 'power': 1, 'damageType': '物理'},
           'antiair': {'id': 936, 'state': '空手攻击', 'hits': [45, 49], 'power': 1.5, 'damageType': '魔法', 'magicAttribute': '波'},
           'retreat_blast': {'id': 936, 'state': '空手攻击', 'hits': [83, 86, 89, 92, 95], 'power': 1.8, 'damageType': '魔法', 'magicAttribute': '波'}}


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
    paths += sorted(R8_BAKED.glob('*.xml'))
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


def r8_part_matrix(r8_stem, frame_index, part_suffix):
    r8_root = E.parse(str(R8_BAKED / f'act__{r8_stem}.xml'), PARSER).getroot()
    for fr in r8_root.findall('.//x:DOMFrame', NS):
        idx = int(fr.get('index', '0'))
        dur = int(fr.get('duration', '1'))
        if idx <= frame_index < idx + dur:
            for inst in fr.findall('.//x:DOMSymbolInstance', NS):
                if inst.get('libraryItemName', '').endswith(part_suffix):
                    mat = inst.find('x:matrix/x:Matrix', NS)
                    if mat is None:
                        return (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
                    return (
                        float(mat.get('a', '1')),
                        float(mat.get('b', '0')),
                        float(mat.get('c', '0')),
                        float(mat.get('d', '1')),
                        float(mat.get('tx', '0')),
                        float(mat.get('ty', '0')),
                    )
    raise ValueError(f'Missing {part_suffix} at frame {frame_index} in act__{r8_stem}.xml')


# Visible barrel tip in native part 928, also used by its wrapper 934.
ANTIAIR_MUZZLE_LOCAL = (66.0, 0.0)

def antiair_cannon_pose(frame_index, front):
    tree=E.parse(str(R8_BAKED/'act__双臂光束.xml'),PARSER)
    poses=[]
    for frame in tree.findall('.//x:DOMFrame',NS):
        start=int(frame.get('index','0'));duration=int(frame.get('duration','1'))
        if not start<=frame_index<start+duration:continue
        for item in frame.findall('x:elements/x:DOMSymbolInstance',NS):
            if item.get('libraryItemName')!=PREFIX+'分件/934':continue
            node=item.find('x:matrix/x:Matrix',NS)
            poses.append([float(node.get(k,'1' if k in ('a','d') else '0')) for k in ('a','b','c','d','tx','ty')])
    if len(poses)!=2:raise ValueError('Expected both native headbot cannon poses')
    pose=sorted(poses,key=lambda m:m[4])[1 if front else 0]
    x,y=ANTIAIR_MUZZLE_LOCAL
    pose[4]+=pose[0]*x+pose[2]*y;pose[5]+=pose[1]*x+pose[3]*y
    return pose

def align_antiair_layers(layers):
    # Expand only effect-bearing exposures; each frame follows its own recoil pose.
    for layer in layers:
        frames=layer.find('x:frames',NS)
        for frame in list(frames):
            effects=frame.findall('x:elements/x:DOMSymbolInstance[@libraryItemName="'+PREFIX+'特效/对空枪火"]',NS)
            if not effects:continue
            start=int(frame.get('index','0'));duration=int(frame.get('duration','1'));position=frames.index(frame)
            for offset in range(duration):
                single=copy.deepcopy(frame);single.set('index',str(start+offset));single.set('duration','1')
                for effect in single.findall('x:elements/x:DOMSymbolInstance',NS):
                    if effect.get('libraryItemName')!=PREFIX+'特效/对空枪火':continue
                    node=effect.find('x:matrix/x:Matrix',NS);front=float(node.get('tx','0'))>50
                    m=antiair_cannon_pose(start+offset,front)
                    old_scale=(float(node.get('a','1'))**2+float(node.get('b','0'))**2)**0.5
                    ratio=old_scale/(m[0]*m[0]+m[1]*m[1])**0.5
                    values=(m[0]*ratio,m[1]*ratio,-m[2]*ratio,-m[3]*ratio,m[4],m[5])
                    for key,value in zip(('a','b','c','d','tx','ty'),values):node.set(key,native.num(value))
                    effect.set('firstFrame',str(int(effect.get('firstFrame','0'))+offset))
                frames.insert(position+offset,single)
            frames.remove(frame)

def antiair_muzzle_markers(count):
    markers={}
    for f in range(31,70):
        markers[f]={'elements':[native.instance(PREFIX+'行为驱动',matrix=antiair_cannon_pose(f,front),
            symbol_type='movie clip',name='headbotAntiairMuzzle'+('Front' if front else 'Rear')) for front in (False,True)]}
    return native.make_sparse_layer('逐帧对空炮口',count,markers)

def make_r8_body(name, r8_stem, count, scripts=None, hits=None, top_layers=None):
    r8_root = E.parse(str(R8_BAKED / f'act__{r8_stem}.xml'), PARSER).getroot()
    vis_layers = [copy.deepcopy(l) for l in r8_root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)]
    if r8_stem=='双臂光束':align_antiair_layers(vis_layers)
    return native.symbol(name, [
        *(top_layers or []),
        native.make_sparse_layer('CF7控制', count, scripts or {}),
        native.layer('身体内部时钟', [native.frame(0, count, [native.instance(PREFIX+'行为驱动',
            symbol_type='movie clip', name='headbotBodyDriver',
            script='onClipEvent(enterFrame){_parent._parent.headbotBodyTick(_parent);}')])]),
        native.make_sparse_layer('真实攻击区域', count, hits or {}),
        *vis_layers,
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
            if cid in (929, 930, 931, 932):
                converted[name].attrib.pop('symbolType', None)
        for key, item in converted.items():
            if key in result and native.xml_bytes(result[key]) != native.xml_bytes(item):
                raise ValueError('Conflicting shared vector atlas: '+key)
        result.update(converted)
        parts[cid] = name
        stats.append({'id': cid, **report})

    # 934 is a one-frame arm wrapper, including the source local registration.
    parts[934] = PREFIX+'分件/934'
    result[parts[934]] = native.symbol(parts[934], depth_layers(timeline['934'], parts), symbol_type='movie clip')
    for ext_file in sorted(R8_BAKED.glob('ext__*.xml')):
        ext_root = E.parse(str(ext_file), PARSER).getroot()
        result[ext_root.get('name')] = ext_root
    cut_symbols,torso_pieces,cut_reports = debris.torso_parts(vector,ARCHIVE/'parts/929.svg',PREFIX)
    result.update(cut_symbols)
    stats.append({'id':929,'kind':'nine-complementary-death-pieces','pieces':cut_reports})
    shadow_part = parts.pop(926)
    names = {sid: PREFIX+'动作/'+label for sid, label in [(933,'悬浮'), (936,'双臂光束'),
             (937,'伸缩冲击'), (938,'被击'), (951,'机械碎裂')]}
    result[names[933]] = make_r8_body(names[933], '悬浮', 45,
        {0: {'script': 'headbotMode="idle";stop();'},
         4: {'script': 'if(_parent.状态=="躲闪" || _parent.状态=="拾取")_parent.动画完毕();'}})

    # Thrust (伸缩冲击, 37f)
    thrust_spec = ATTACKS['thrust']
    thrust_hits = {}
    for f in thrust_spec['hits']:
        m = r8_part_matrix('伸缩冲击', f-1, '分件/931')
        left = -40.15
        right = m[4] + 60.95 * abs(m[0])
        width = right - left
        center_x = (left + right) / 2
        center_y = m[5]
        thrust_hits[f-1] = {'elements': [native.instance(H['Symbol 195'],
            matrix=(width/25, 0, 0, 50/25, center_x, center_y),
            symbol_type='movie clip', name='攻击点',
            script='onClipEvent(load){headbotToken=_parent.headbotToken;headbotHitFrame=_parent._currentframe;_parent._parent.headbotStrike(_parent,this,'+str(thrust_spec['power'])+');}',
            alpha_mult=0)]}
    result[names[937]] = make_r8_body(names[937], '伸缩冲击', 37, {
        0: {'script': 'headbotMode="attack";_parent.headbotBeginAttack(this,"thrust");stop();'},
        36: {'script': '_parent.headbotFinishAttack(this);stop();'}}, thrust_hits)

    # Beam / Anti-air / Retreat blast (双臂光束, 109f)
    beam_spec = ATTACKS['beam']
    beam_hits = {}
    for f in beam_spec['hits']:
        m = r8_part_matrix('双臂光束', f-1, '分件/935')
        width = 297.08 * abs(m[0])
        center_x = m[4]
        center_y = m[5]
        beam_hits[f-1] = {'elements': [native.instance(H['Symbol 195'],
            matrix=(width/25, 0, 0, 36/25, center_x, center_y),
            symbol_type='movie clip', name='攻击点',
            script='onClipEvent(load){headbotToken=_parent.headbotToken;headbotHitFrame=_parent._currentframe;_parent._parent.headbotStrike(_parent,this,'+str(beam_spec['power'])+');}',
            alpha_mult=0)]}
    for f in ATTACKS['antiair']['hits']:
        m=antiair_cannon_pose(f-1,f==49)
        length=(m[0]*m[0]+m[1]*m[1])**0.5;dx,dy=m[0]/length,m[1]/length
        beam_hits[f-1] = {'elements': [native.instance(H['Symbol 195'],
            matrix=(-dy*120/25, dx*120/25, dx*190/25, dy*190/25, m[4]+dx*95, m[5]+dy*95),
            symbol_type='movie clip', name='攻击点',
            script='onClipEvent(load){headbotToken=_parent.headbotToken;headbotHitFrame=_parent._currentframe;_parent._parent.headbotStrike(_parent,this,'+str(ATTACKS['antiair']['power'])+');}',
            alpha_mult=0)]}
    for f in ATTACKS['retreat_blast']['hits']:
        beam_hits[f-1] = {'elements': [native.instance(H['Symbol 195'],
            matrix=(250/25, 0, 0, 165/25, 90, -20),
            symbol_type='movie clip', name='攻击点',
            script='onClipEvent(load){headbotToken=_parent.headbotToken;headbotHitFrame=_parent._currentframe;_parent._parent.headbotStrike(_parent,this,'+str(ATTACKS['retreat_blast']['power'])+');}',
            alpha_mult=0)]}
    charge = {}
    for f in range(BEAM_WINDUP):
        scale = 0.2 + 0.45 * f / (BEAM_WINDUP-1)
        charge[f] = {'elements': [native.instance(parts[903], matrix=(scale,0,0,scale,x,-35.3),
            alpha_mult=0.25+0.65*f/(BEAM_WINDUP-1)) for x in (99,14)]}
    beam_events = {
        0: {'name': '射击', 'label_type': 'name', 'script': 'headbotMode="attack";if(_parent.headbotPendingBeamSubmode=="antiair"){_parent.headbotPendingBeamSubmode="";gotoAndStop(32);}else if(_parent.headbotPendingBeamSubmode=="retreat_blast"){_parent.headbotPendingBeamSubmode="";gotoAndStop(72);}else{_parent.headbotBeginAttack(this,"beam");stop();}'},
        29: {'script': '_parent.headbotFinishAttack(this);stop();'},
        31: {'name': '对空射击', 'label_type': 'name', 'script': 'headbotMode="attack";_parent.headbotBeginAttack(this,"antiair");stop();'},
        69: {'script': '_parent.headbotFinishAttack(this);stop();'},
        71: {'name': '后撤爆破', 'label_type': 'name', 'script': 'headbotMode="attack";_parent.headbotBeginAttack(this,"retreat_blast");stop();'},
        108: {'script': '_parent.headbotFinishAttack(this);stop();'},
    }
    result[names[936]] = make_r8_body(names[936], '双臂光束', 109, beam_events, beam_hits,
        [native.make_sparse_layer('双臂蓄光前摇', 109, charge),antiair_muzzle_markers(109)])

    result[names[938]] = make_r8_body(names[938], '被击', 88, {
        0: {'name': 'a0', 'label_type': 'name', 'script': 'headbotMode="hit";stop();'},
        6: {'name': 'a1', 'label_type': 'name', 'script': 'headbotMode="hit";stop();'},
        24: {'script': '_parent.动画完毕();stop();'},
        26: {'name': '护盾', 'label_type': 'name', 'script': 'headbotMode="shield";_parent.headbotBeginShield(this);stop();'},
        87: {'script': '_parent.动画完毕();stop();'}})
    result[names[951]] = make_body(names[951], timeline['951'][:18]+[{} for _ in range(40)], parts, {
        0: {'name': 'a0', 'label_type': 'name', 'script': 'headbotMode="death";_parent.headbotCancelAttack();_parent.cf6ArmRobotDeath(this,19);stop();'},
        4: {'script': '_parent.headbotDeathFx();'},
        57: {'script': '_parent.cf6FinishCorpse(this);stop();'}})
    result[names[951]].find('x:timeline/x:DOMTimeline/x:layers', NS).insert(0,
        corpse.fragment_layer(native,result,parts,timeline['951'][17],PREFIX+'尸体碎片',18,58,{929:torso_pieces}))
    death.add(native,result,PREFIX,names[951],(1,0,0,1,7,-60.15+GROUND_SHIFT),19,58,H['Symbol 195'])

    driver = PREFIX+'行为驱动'
    result[driver] = native.symbol(driver, [native.layer('停止',[native.frame(script='stop();')])], symbol_type='movie clip')
    def g_inst(lib_name, matrix, first_frame=0, alpha_mult=None):
        inst = native.instance(lib_name, matrix=matrix, symbol_type='graphic', alpha_mult=alpha_mult)
        if first_frame > 0:
            inst.set('firstFrame', str(first_frame))
        return inst

    bomb_fx_name = PREFIX+'特效/坠落轰炸弹'
    wuren_target = PREFIX+'特效/雾人/目标'
    wuren_shell = PREFIX+'特效/雾人/巨型穿刺能量子弹'
    wuren_quake = PREFIX+'特效/雾人/强震地'
    wuren_blast = PREFIX+'特效/雾人/强烈震爆'
    lock_frames = {}
    for f in range(12):
        lock_frames[1 + f] = {'elements': [
            g_inst(wuren_target, matrix=(1.15, 0, 0, 0.44, -128, -49), first_frame=f),
        ]}
    shell_frames = {}
    for s in range(12):
        lock_frames[13 + s] = {'elements': [
            g_inst(wuren_target, matrix=(1.15, 0, 0, 0.44, -128, -49), first_frame=min(22, 12 + s)),
        ]}
        ratio = (s + 1) / 12.0
        head_y = -520.0 * (1.0 - ratio) - 20.0
        shell_frames[13 + s] = {'elements': [
            g_inst(wuren_shell, matrix=(0, 2.5, -1.9, 0, 0, head_y), first_frame=min(17, 1 + s)),
            g_inst(wuren_blast, matrix=(0.75, 0, 0, 0.75, 0, head_y + 40), first_frame=min(14, s)),
        ]}
    blast_frames = {}
    for e in range(10):
        if e < 5:
            lock_frames[25 + e] = {'elements': [
                g_inst(wuren_target, matrix=(1.15, 0, 0, 0.44, -128, -49), first_frame=22, alpha_mult=max(0.08, 0.72 - 0.15 * e)),
            ]}
        q_scale = 2.2 + 0.1 * e
        b_scale = 1.45 + 0.06 * e
        alpha = 1.0 if e < 7 else max(0.12, 1.0 - 0.28 * (e - 6))
        blast_frames[25 + e] = {'elements': [
            g_inst(wuren_quake, matrix=(q_scale, 0, 0, q_scale, -12, -14), first_frame=min(14, e), alpha_mult=alpha),
            g_inst(wuren_blast, matrix=(b_scale, 0, 0, b_scale, 0, 0), first_frame=min(14, e), alpha_mult=alpha),
        ]}
    result[bomb_fx_name] = native.symbol(bomb_fx_name, [
        native.make_sparse_layer('控制', 35, {0: {'script': 'stop();'}}),
        native.make_sparse_layer('地面爆破冲击', 35, blast_frames),
        native.make_sparse_layer('天降光束弹', 35, shell_frames),
        native.make_sparse_layer('地面预警靶标', 35, lock_frames),
    ], symbol_type='movie clip')
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
    hit = 'onClipEvent(load){if(_parent.headbotPendingShield===true){_parent.headbotPendingShield=false;gotoAndStop("护盾");}else{gotoAndStop("a"+random(2));}}'
    beam_load = 'onClipEvent(load){if(_parent.headbotPendingBeamSubmode=="antiair"){_parent.headbotPendingBeamSubmode="";gotoAndStop(32);}else if(_parent.headbotPendingBeamSubmode=="retreat_blast"){_parent.headbotPendingBeamSubmode="";gotoAndStop(72);}}'
    bodies = {0:(9,body(933)),9:(10,body(933)),19:(10,body(933)),29:(8,body(933)),
        37:(4,body(937)),41:(10,body(936,beam_load)),51:(10,body(933)),61:(10,body(933)),
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
        native.make_sparse_layer('轰炸特效模板',125,{0:{'duration':120,'elements':[native.instance(bomb_fx_name,matrix=(1,0,0,1,0,0),symbol_type='movie clip',name='cf6BombTemplate')]}}),
        native.make_sparse_layer('动作',125,{i:{'duration':d,'elements':[b]} for i,(d,b) in bodies.items()}),
    ], symbol_type='movie clip', linkage=LINKAGE, export_first_frame=True)
    return result, root_name, stats


def import_assets(force=False):
    native.guard_overwrite_allowed(force)
    symbols, root_name, stats = build_symbols()
    native.guard_overwrite_allowed(force)
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
        'sourceVisualFrames':279,'replacedOriginalControls':[290,299,311,360,914],
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
    parser.add_argument('--force',action='store_true')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if args.import_approved: import_assets(args.force)
    check()
