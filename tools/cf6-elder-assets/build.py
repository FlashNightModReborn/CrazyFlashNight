"""CF6 elder R7 human/robot rigs and a local, sequential transformation."""
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
ARCHIVES = {key: ROOT/'flashswf/arts/new/Codex素材源稿'/name for key, name in
    [('human','CF6老头人形-R7'), ('robot','CF6老头机器人-R7'), ('phase','CF6老头变形-R2')]}
OWNER = ROOT/'flashswf/arts/new/Codex老头素材'
ANCHOR = 'Codex老头素材'
LINKS = {'human':'敌人-CF6老头人形', 'robot':'敌人-CF6老头机器人'}
LINKAGE = LINKS['human']
PREFIX = 'Codex/老头/'
NS = {'x':'http://ns.adobe.com/xfl/2008/'}
N = '{'+NS['x']+'}'
BEAM_ORIGINAL_WIDTH = 461.05
BEAM_CONTACT_WIDTH = 780.83
BEAM_ORIGINAL_LEFT = -230.5
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False, resolve_entities=False)

def module(name, path):
    spec = importlib.util.spec_from_file_location(name,path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

audio = module('cf6_audio_native',ROOT/'tools/cf6-audio/build.py')
common = module('elder_common', ROOT/'tools/cf6-manman-assets/build.py')
vector = module('elder_vector', ROOT/'tools/cf6-headbot-assets/vector.py')
corpse = module('elder_corpse', ROOT/'tools/cf6-headbot-assets/corpse.py')
death = module('elder_death', ROOT/'tools/cf6-headbot-assets/robot_death.py')
native = common.native
for key, value in {'ROOT':ROOT,'HERE':HERE,'OWNER':OWNER,'ANCHOR':ANCHOR,'LINKAGE':LINKAGE,'PREFIX':PREFIX}.items():
    setattr(common,key,value)
native.OWNER, native.HERE = OWNER,HERE
native.MANIFEST_SCHEMA = 'cf6-elder.native-import.v1'
native.PROJECT_FILES = ('DOMDocument.xml',ANCHOR+'.xfl','PublishSettings.xml','MobileSettings.xml')
native.SHARED_HELPERS = {old:PREFIX+'CF7/'+old for old in native.SHARED_HELPERS}
H = native.SHARED_HELPERS
FORMS = {
    'human': {'root':975, 'stand':967, 'walk':968, 'hit':973, 'fall':974, 'death':974,
        'hitDurations':[12,13], 'canBeAirborne':True, 'ground':-12.35, 'parts':[*range(954,964),965,966], 'deathEnd':31,
        'actions': {'burst':{'id':970,'state':'空手攻击','hits':[13,21,29,37],'power':1,'damage':'物理'},
                    'stab':{'id':972,'state':'近战','hits':[7],'power':1,'damage':'物理'}}},
    'robot': {'root':1011, 'stand':990, 'walk':991, 'hit':1008, 'fall':1008, 'death':1010,
        'hitDurations':[12,13], 'canBeAirborne':False, 'ground':-11.4125, 'parts':list(range(977,990)), 'deathEnd':111,
        'actions': {'beam':{'id':994,'state':'空手攻击','hits':[29],'tailFrames':15,'power':3,'damage':'魔法','attribute':'波'},
                    'kicks':{'id':997,'state':'近战','hits':[9,26],'power':1,'damage':'物理'},
                    'slam':{'id':1007,'state':'重击','hits':[37],'power':18,'damage':'物理'},
                    'heavyBeam':{'id':19940,'sourceId':994,'windupExtra':6,'sustainExtra':36,'state':'蓄能重束','hits':[35,47,59,71],
                        'powers':[0.5,1,1.5,2],'damage':'魔法','attribute':'波','requiresAny':['cf6Elder:beam','ownRecentSlamHit'],'beamThickness':3}}}
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

R8_BAKED = HERE / 'r8-baked'

def verify_inputs():
    for archive in ARCHIVES.values():
        for row in json.loads((archive/'archive-origin.json').read_text('utf8'))['members']:
            p = archive/row['path']
            assert p.stat().st_size == row['bytes'] and sha(p) == row['sha256'], str(p)

def build_inputs():
    paths = [HERE/'build.py', HERE/'ElderAI.as', HERE/'ElderTransform.as', HERE/'bayonet.svg',
        ROOT/'tools/cf6-headbot-assets/corpse.py', ROOT/'tools/cf6-headbot-assets/CorpseFragments.as',
        ROOT/'tools/cf6-headbot-assets/vector.py', ROOT/'tools/cf6-guard-assets/vector.py',
        ROOT/'tools/cf6-guard-assets/clipped_vector.py', ROOT/'tools/cf6-guard-assets/clip-vectors.ps1',
        ROOT/'tools/cf6-wings-assets/vector.py', ROOT/'tools/cf6-manman-assets/build.py',
        ROOT/'tools/cf6-zombie-assets/build.py', ROOT/'tools/gamma-echo-assets/build.py',
        ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
        ROOT/'tools/asset-metrology/xfl_geometry.py',
        ROOT/'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml']
    paths += [a/'archive-origin.json' for a in ARCHIVES.values()]
    paths += [native.THINGS1/(old+'.xml') for old in sorted(H)]
    paths += death.input_paths()
    paths += sorted(R8_BAKED.glob('*.xml'))
    return [{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in paths]

def depth_layers(timeline, parts):
    layers = []
    for depth in sorted({int(d) for fr in timeline for d,r in fr.items() if r['id'] in parts},reverse=True):
        states = [fr.get(str(depth)) if fr.get(str(depth),{}).get('id') in parts else None for fr in timeline]
        frames, start = [],0
        while start < len(states):
            row,end = states[start],start+1
            visual = lambda value: None if value is None else (value['id'],value['matrix'],value.get('colorMult'),value.get('colorAdd'))
            while end < len(states) and visual(states[end]) == visual(row): end += 1
            elements = []
            if row is not None:
                inst = native.instance(parts[row['id']],matrix=row['matrix'])
                mult,add = row.get('colorMult',[256]*4),row.get('colorAdd',[0]*4)
                if mult != [256]*4 or add != [0]*4:
                    color = E.SubElement(E.SubElement(inst,N+'color'),N+'Color')
                    for i,channel in enumerate(('red','green','blue','alpha')):
                        color.set(channel+'Multiplier',native.num(mult[i]/256))
                        color.set(channel+'Offset',native.num(add[i]))
                elements.append(inst)
            frames.append(native.frame(start,end-start,elements)); start=end
        layers.append(native.layer('原始深度_'+str(depth),frames))
    return layers

def make_body(name, timeline, parts, events=None, hits=None):
    count=len(timeline)
    return native.symbol(name,[native.make_sparse_layer('CF7控制',count,events or {}),
        native.layer('身体内部时钟',[native.frame(0,count,[native.instance(PREFIX+'行为驱动',symbol_type='movie clip',
            name='elderBodyDriver',script='onClipEvent(enterFrame){_parent._parent.elderBodyTick(_parent);}')])]),
        native.make_sparse_layer('真实攻击区域',count,hits or {}),*depth_layers(timeline,parts),
        native.layer('身体内接地阴影',[native.frame(0,count,[native.instance(PREFIX+'接地阴影',symbol_type='movie clip',name='elderShadow')])])],symbol_type='movie clip')

def make_r8_body(name, form, act_id, count, events=None, hits=None, top_layers=None):
    r8_root = E.parse(str(R8_BAKED / f'act__{form}__{act_id}.xml'), PARSER).getroot()
    vis_layers = [copy.deepcopy(l) for l in r8_root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS)]
    return native.symbol(name, [
        *(top_layers or []),
        native.make_sparse_layer('CF7控制', count, events or {}),
        native.layer('身体内部时钟', [native.frame(0, count, [native.instance(PREFIX+'行为驱动', symbol_type='movie clip',
            name='elderBodyDriver', script='onClipEvent(enterFrame){_parent._parent.elderBodyTick(_parent);}')])]),
        native.make_sparse_layer('真实攻击区域', count, hits or {}),
        *vis_layers,
        native.layer('身体内接地阴影', [native.frame(0, count, [native.instance(PREFIX+'接地阴影', symbol_type='movie clip', name='elderShadow')])])
    ], symbol_type='movie clip')

# Part 986 is the visible cannon fist. Its outer knuckle/barrel plane is
# x=154; y=4 is the center of that plane in the immutable R7 native part.
SLAM_MUZZLE_LOCAL = (154.0, 4.0)

def slam_muzzle_layer(count, driver):
    source = E.parse(str(R8_BAKED/'act__robot__1007.xml'), PARSER)
    poses = {}
    for frame in source.findall('.//x:DOMFrame', NS):
        start, duration = int(frame.get('index', '0')), int(frame.get('duration', '1'))
        for item in frame.findall('./x:elements/x:DOMSymbolInstance', NS):
            if item.get('libraryItemName') != PREFIX+'分件/986':
                continue
            node = item.find('./x:matrix/x:Matrix', NS)
            m = [float(node.get(k, '1' if k in ('a', 'd') else '0')) for k in ('a','b','c','d','tx','ty')]
            tip_x, tip_y = SLAM_MUZZLE_LOCAL
            m[4] += m[0]*tip_x + m[2]*tip_y
            m[5] += m[1]*tip_x + m[3]*tip_y
            for f in range(start, min(count, start+duration)):
                if f in poses:
                    raise ValueError('Ambiguous slam cannon pose at frame '+str(f+1))
                poses[f] = {'elements':[native.instance(driver, matrix=m,
                    symbol_type='movie clip', name='elderSlamMuzzle')]}
    if set(poses) != set(range(count)):
        raise ValueError('Slam muzzle must follow every authored cannon frame')
    return native.make_sparse_layer('拳头炮口挂点', count, poses)

def build_symbols():
    verify_inputs()
    timelines={k:json.loads((a/'reference/timelines.json').read_text('utf8')) for k,a in ARCHIVES.items()}
    result,parts,stats=native.clone_shared_helpers(),{},[]
    result[PREFIX+'接地阴影']=native.symbol(PREFIX+'接地阴影',[native.layer('接地更新',[native.frame(script='''elderGround={x:0,y:0};
updateElderShadow=function():Void {
    var body:MovieClip=this._parent,unit:MovieClip=body._parent;
    var visible:Boolean=_root.是否阴影==true;
    if(this._visible!=visible)this._visible=visible;
    if(isNaN(unit.Z轴坐标))return;
    var p:Object=this.elderGround;p.x=unit._x;p.y=unit.Z轴坐标;
    unit._parent.localToGlobal(p);body.globalToLocal(p);
    this._x=p.x;this._y=p.y;
    this._xscale=7000/body._xscale;this._yscale=1400/body._yscale;
    this._rotation=-body._rotation+(unit._xscale<0?unit._rotation:-unit._rotation);
};
onEnterFrame=updateElderShadow;updateElderShadow();stop();''',elements=[native.instance(H['Symbol 2'])])])],symbol_type='movie clip')

    for form,spec in FORMS.items():
        for cid in spec['parts']:
            name=PREFIX+'分件/'+str(cid)
            converted,report=vector.NativePart(ARCHIVES[form]/'parts'/f'{cid}.svg',name,(0,0)).build()
            for key,item in converted.items():
                if key in result: assert native.xml_bytes(result[key])==native.xml_bytes(item),key
            result.update(converted);parts[cid]=name;stats.append({'id':cid,'kind':'authored-r7',**report})
    # A small shared CF6 bayonet was still a bitmap in the authoring handoff.
    # Its original silhouette/registration is retained in this explicit native redraw.
    converted,report=vector.original_effect(HERE/'bayonet.svg',PREFIX+'分件/484',(0,0))
    result.update(converted);parts[484]=PREFIX+'分件/484';stats.append({'id':484,'kind':'native-bayonet',**report})
    for archive,ids in [(ARCHIVES['robot'],[903,993,996,*range(999,1007)]),
                        (ARCHIVES['phase'],[*range(1994,2004)])]:
        for cid in ids:
            name=PREFIX+'原始特效/'+str(cid)
            converted,report=vector.original_effect(archive/'reference/shapes'/f'{cid}.svg',name,(0,0))
            result.update(converted);parts[cid]=name;stats.append({'id':cid,'kind':'original-vector',**report})
    for ext_file in sorted(R8_BAKED.glob('ext__*.xml')):
        ext_root = E.parse(str(ext_file), PARSER).getroot()
        result[ext_root.get('name')] = ext_root
    driver=PREFIX+'行为驱动'
    result[driver]=native.symbol(driver,[native.layer('停止',[native.frame(script='stop();')])],symbol_type='movie clip')
    def g_inst(lib_name,matrix,first_frame=0,alpha_mult=None):
        inst=native.instance(lib_name,matrix=matrix,symbol_type='graphic',alpha_mult=alpha_mult)
        if first_frame>0:inst.set('firstFrame',str(first_frame))
        return inst

    wuren_target=PREFIX+'特效/雾人/目标'
    wuren_shell=PREFIX+'特效/雾人/巨型穿刺能量子弹'
    wuren_quake=PREFIX+'特效/雾人/强震地'
    wuren_blue_cannon=PREFIX+'特效/雾人/蓝色炮击'
    wuren_blue_burst=PREFIX+'特效/雾人/蓝芒强击'
    antiair_fx_name=PREFIX+'特效/蓄力对空光束'
    aa_frames={}
    for f in range(14):
        alpha=1.0 if f<10 else max(0.15,1.0-0.2*(f-9))
        els=[
            g_inst(wuren_blue_burst,matrix=(1.1,0,0,1.1,0,-65),first_frame=min(23,f*2),alpha_mult=alpha),
            g_inst(wuren_shell,matrix=(0,-2.2,1.8,0,0,-85-f*26),first_frame=min(17,f*2),alpha_mult=alpha),
        ]
        if f<10:
            els.insert(0,g_inst(wuren_blue_cannon,matrix=(1.15,0,0,1.35,0,0),first_frame=min(9,f),alpha_mult=alpha))
        aa_frames[1+f]={'elements':els}
    result[antiair_fx_name]=native.symbol(antiair_fx_name,[
        native.make_sparse_layer('控制',15,{0:{'script':'stop();'}}),
        native.make_sparse_layer('对空光束与炮口光',15,aa_frames),
    ],symbol_type='movie clip')
    bomb_fx_name=PREFIX+'特效/坠落轰炸弹'
    lock_frames={}
    for f in range(12):
        lock_frames[1+f]={'elements':[
            g_inst(wuren_target,matrix=(1.15,0,0,0.44,-128,-49),first_frame=f),
        ]}
    shell_frames={}
    for s in range(12):
        lock_frames[13+s]={'elements':[
            g_inst(wuren_target,matrix=(1.15,0,0,0.44,-128,-49),first_frame=min(22,12+s)),
        ]}
        ratio=(s+1)/12.0
        head_y=-520.0*(1.0-ratio)-20.0
        shell_frames[13+s]={'elements':[
            g_inst(wuren_shell,matrix=(0,2.5,-1.9,0,0,head_y),first_frame=min(17,1+s)),
            g_inst(wuren_blue_burst,matrix=(0.75,0,0,0.75,0,head_y+40),first_frame=min(23,s*2)),
        ]}
    blast_frames={}
    for e in range(10):
        if e<5:
            lock_frames[25+e]={'elements':[
                g_inst(wuren_target,matrix=(1.15,0,0,0.44,-128,-49),first_frame=22,alpha_mult=max(0.08,0.72-0.15*e)),
            ]}
        q_scale=2.2+0.1*e
        b_scale=1.25+0.06*e
        alpha=1.0 if e<7 else max(0.12,1.0-0.28*(e-6))
        blast_frames[25+e]={'elements':[
            g_inst(wuren_quake,matrix=(q_scale,0,0,q_scale,-12,-14),first_frame=min(14,e),alpha_mult=alpha),
            g_inst(wuren_blue_burst,matrix=(b_scale,0,0,b_scale,0,-10),first_frame=min(23,e*2),alpha_mult=alpha),
        ]}
    result[bomb_fx_name]=native.symbol(bomb_fx_name,[
        native.make_sparse_layer('控制',35,{0:{'script':'stop();'}}),
        native.make_sparse_layer('地面爆破冲击',35,blast_frames),
        native.make_sparse_layer('天降光束弹',35,shell_frames),
        native.make_sparse_layer('地面预警靶标',35,lock_frames),
    ],symbol_type='movie clip')
    roots={}
    for form,spec in FORMS.items():
        timeline=timelines[form]
        source=json.loads((ARCHIVES[form]/'reference/manifest.json').read_text('utf8'))['roots'][0]
        offsets={r['body']['id']:r['body']['matrix'] for r in source['labels'] if r['body']}
        names={sid:PREFIX+form+'/动作/'+str(sid) for sid in {spec['stand'],spec['walk'],spec['hit'],spec['fall'],spec['death'],*[a['id'] for a in spec['actions'].values()]}}
        for sid in [spec['stand'],spec['walk']]:
            result[names[sid]]=make_r8_body(names[sid],form,str(sid),len(timeline[str(sid)]),
                {0:{'script':'elderMode="idle";stop();'},4:{'script':'if(_parent.状态=="拾取" || _parent.状态=="躲闪")_parent.动画完毕();'}})
        if form=='human':
            run_name = PREFIX+'human/动作/跑步'
            result[run_name] = make_r8_body(run_name,'human','跑步',24,
                {0:{'script':'elderMode="idle";stop();'},4:{'script':'if(_parent.状态=="拾取" || _parent.状态=="躲闪")_parent.动画完毕();'}})
        action_durations={}
        for action,a in spec['actions'].items():
            frames=copy.deepcopy(timeline[str(a.get('sourceId',a['id']))]);hits={}
            if 'tailFrames' in a:
                last=a['hits'][-1];tail=frames[last:];count=a['tailFrames']
                assert 2<=count<=len(tail)
                # Keep the authored shot and both recovery endpoints; resample only the return motion.
                frames=frames[:last]+[copy.deepcopy(tail[round(i*(len(tail)-1)/(count-1))]) for i in range(count)]
            if action=='heavyBeam':
                frames=[copy.deepcopy(frames[0]) for _ in range(a['windupExtra'])]+frames
                # Hold the original first firing pose while the four fixed-direction pulses advance.
                first=a['hits'][0]
                frames[first:first]=[copy.deepcopy(frames[first-1]) for _ in range(a['sustainExtra'])]
                for fr in frames:
                    for row in fr.values():
                        if row['id']==993:
                            row['matrix'][2]*=a['beamThickness'];row['matrix'][3]*=a['beamThickness']
            if action in ('beam','heavyBeam'):
                length_scale=BEAM_CONTACT_WIDTH/BEAM_ORIGINAL_WIDTH
                for fr in frames:
                    for row in fr.values():
                        if row['id']==993:
                            m=row['matrix']
                            # Extend along the existing beam axis while preserving its authored muzzle end.
                            shift=BEAM_ORIGINAL_LEFT*(1-length_scale)
                            m[4]+=m[0]*shift;m[5]+=m[1]*shift
                            m[0]*=length_scale;m[1]*=length_scale
            action_durations[action]=94 if action=='burst' else (71 if action=='slam' else len(frames))
            for f in a['hits']:
                if action=='burst':
                    # Original CF6 control 359 sits at ground level. The visible
                    # muzzle flash 506 supplies the actual barrel endpoint.
                    m=next(r['matrix'] for r in frames[f-1].values() if r['id']==506)
                    matrix=(1,0,0,1,m[4],m[5]);helper=driver
                elif action in ('beam','heavyBeam'):
                    m=next(r['matrix'] for r in frames[f-1].values() if r['id']==993)
                    matrix=(BEAM_CONTACT_WIDTH/25,0,0,32*a.get('beamThickness',1)/25,m[4],m[5]);helper=H['Symbol 195']
                else:
                    m=next(r['matrix'] for r in frames[f-1].values() if r['id']==290)
                    # CF6's ground-only probe becomes a vertical CF7 contact box.
                    height=160 if action=='slam' else (140 if action=='kicks' else 90)
                    matrix=(66*abs(m[0])/25,0,0,height/25,m[4],-10 if action=='slam' else (-45 if action=='kicks' else -35))
                    helper=H['Symbol 195']
                hits[f-1]={'elements':[native.instance(helper,matrix=matrix,symbol_type='movie clip',name='攻击点',
                    alpha_mult=0,script='onClipEvent(load){elderToken=_parent.elderToken;elderHitFrame=_parent._currentframe;_parent._parent.elderStrike(_parent,this);}')]}
            if action=='burst':
                r8_burst_root=E.parse(str(R8_BAKED/'act__human__970.xml'),PARSER).getroot()
                gun_mats={}
                for df in r8_burst_root.findall('.//x:DOMFrame',NS):
                    idx=int(df.get('index','0'));dur_f=int(df.get('duration','1'))
                    for inst in df.findall('.//x:DOMSymbolInstance',NS):
                        if inst.get('libraryItemName')=='Codex/老头/分件/965':
                            mel=inst.find('x:matrix/x:Matrix',NS)
                            mat=(float(mel.get('a','1')),float(mel.get('b','0')),float(mel.get('c','0')),float(mel.get('d','1')),float(mel.get('tx','0')),float(mel.get('ty','0')))
                            for fi in range(idx,idx+dur_f):gun_mats[fi]=mat
                for rf in (63,65,68,70):
                    gm=gun_mats[rf-1]
                    mx=round(gm[4]+gm[0]*(-317.011056)+gm[2]*0.730554,2)
                    my=round(gm[5]+gm[1]*(-317.011056)+gm[3]*0.730554,2)
                    hits[rf-1]={'elements':[native.instance(driver,matrix=(1,0,0,1,mx,my),symbol_type='movie clip',name='攻击点',
                        alpha_mult=0,script='onClipEvent(load){elderToken=_parent.elderToken;elderHitFrame=_parent._currentframe;_parent._parent.elderStrike(_parent,this);}')]}
                events={
                    0:{'name':'射击','label_type':'name','script':'elderMode="attack";if(_parent.elderPendingBurstSubmode=="retreat_burst"){_parent.elderPendingBurstSubmode="";gotoAndStop(55);}else{_parent.elderBeginAttack(this,"burst");stop();}'},
                    52:{'script':'_parent.elderFinishAttack(this);stop();'},
                    54:{'name':'后撤射击','label_type':'name','script':'elderMode="attack";_parent.elderBeginAttack(this,"retreat_burst");stop();'},
                    93:{'script':'_parent.elderFinishAttack(this);stop();'}}
                result[names[a['id']]]=make_r8_body(names[a['id']],form,str(a['id']),94,events,hits)
            elif action=='heavyBeam':
                events={0:{'script':'elderMode="attack";_parent.elderBeginAttack(this,"'+action+'");stop();'},
                    len(frames)-1:{'script':'_parent.elderFinishAttack(this);stop();'}}
                result[names[a['id']]]=make_body(names[a['id']],frames,parts,events,hits)
                charge={}
                for f in range(a['hits'][0]-1):
                    scale=0.25+1.6*f/(a['hits'][0]-2)
                    charge[f]={'elements':[native.instance(parts[903],matrix=(scale,0,0,scale,110.3,-31.25),
                        alpha_mult=0.3+0.6*f/(a['hits'][0]-2))]}
                layers_el=result[names[a['id']]].find('x:timeline/x:DOMTimeline/x:layers',NS)
                fx_root=E.parse(str(R8_BAKED/'act__robot__19940_fx.xml'),PARSER).getroot()
                for fx_layer in reversed(fx_root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer',NS)):
                    layers_el.insert(3,copy.deepcopy(fx_layer))
                layers_el.insert(0,native.make_sparse_layer('重束蓄力光',len(frames),charge))
            else:
                dur=action_durations[action]
                events={0:{'script':'elderMode="attack";_parent.elderBeginAttack(this,"'+action+'");stop();'},
                    dur-1:{'script':'_parent.elderFinishAttack(this);stop();'}}
                result[names[a['id']]]=make_r8_body(names[a['id']],form,str(a['id']),dur,events,hits,
                    top_layers=[slam_muzzle_layer(dur, driver)] if form=='robot' and action=='slam' else None)
        first_hit,second_hit=spec['hitDurations']
        hit_events={0:{'name':'a0','label_type':'name','script':'elderMode="hit";stop();'},
            first_hit:{'name':'a1','label_type':'name','script':'elderMode="hit";stop();'},
            first_hit-1:{'script':'_parent.动画完毕();'},first_hit+second_hit-1:{'script':'_parent.动画完毕();'}}
        result[names[spec['hit']]]=make_r8_body(names[spec['hit']],form,str(spec['hit']),len(timeline[str(spec['hit'])]),hit_events)
        if form=='human':
            result[names[974]]=make_r8_body(names[974],'human','974',82,{
                0:{'script':'elderMode=_parent.hp>0?"fall":"death";stop();'},
                28:{'script':'if(_parent.hp<=0){_parent.死亡检测({noCorpse:true});stop();}'},
                81:{'script':'_parent.倒地=false;_parent.动画完毕();'}})
        else:
            result[names[1010]]=make_body(names[1010],timeline['1010'][:31]+[{} for _ in range(80)],parts,{
                0:{'script':'elderMode="death";_parent.elderCancelAttack();_parent.cf6ArmRobotDeath(this,32);stop();'},
                15:{'script':'_parent.elderDeathFx(1);'},31:{'script':'_parent.elderDeathFx(2);'},
                110:{'script':'_parent.cf6FinishCorpse(this);stop();'}})
            result[names[1010]].find('x:timeline/x:DOMTimeline/x:layers',NS).insert(0,
                corpse.fragment_layer(native,result,{cid:parts[cid] for cid in spec['parts']},
                    timeline['1010'][31],PREFIX+'robot/尸体碎片',31,111))
            death_matrix=list(offsets[1010]);death_matrix[5]+=spec['ground']
            death.add(native,result,PREFIX,names[1010],death_matrix,32,111,H['Symbol 195'])
        airborne_name=None
        if spec['canBeAirborne']:
            airborne_name=PREFIX+form+'/动作/击飞姿势'
            result[airborne_name]=make_body(airborne_name,[timeline[str(spec['fall'])][0]],parts,
                {0:{'script':'elderMode="air";stop();'}})
        def body(sid,script=None,override_name=None):
            source_sid=spec['actions']['heavyBeam']['sourceId'] if sid==19940 else sid
            m=list(offsets[source_sid]);m[5]+=spec['ground']
            return native.instance(override_name or names[sid],matrix=m,symbol_type='movie clip',name='man',script=script)
        state_rows=[(0,1,'空手站立',spec['stand']),(9,9,'空手行走',spec['walk']),
            (19,19,'空手跑',spec['walk']),(29,29,'空手跳',spec['fall']),
            (37,37,'近战',spec['actions']['stab' if form=='human' else 'kicks']['id']),
            (41,41,'空手攻击',spec['actions']['burst' if form=='human' else 'beam']['id']),
            (51,51,'重击',spec['actions']['stab' if form=='human' else 'slam']['id']),
            (61,61,'拾取',spec['stand']),(71,71,'躲闪',spec['stand']),
            (81,81,'被击',spec['hit']),(91,91,'击倒',spec['fall']),
            (101,101,'倒地',spec['fall']),(111,111,'被投',spec['fall']),
            (121,121,'血腥死',spec['death'])]
        if form=='robot':state_rows.insert(7,(56,56,'蓄能重束',19940))
        labels={label:{'name':state,'label_type':'name'} for _,label,state,_ in state_rows}
        labels[141]={'name':'变身','label_type':'name'};labels[151]={'name':'消失','label_type':'name'}
        bodies={}
        for i,(index,label,state,sid) in enumerate(state_rows):
            end=state_rows[i+1][0] if i+1<len(state_rows) else 141
            script='onClipEvent(load){gotoAndStop("a"+random(2));}' if state=='被击' else None
            override_name=None
            if form=='human' and state=='空手跑':
                override_name=PREFIX+'human/动作/跑步'
            elif form=='human' and state=='空手攻击':
                script='onClipEvent(load){if(_parent.elderPendingBurstSubmode=="retreat_burst"){_parent.elderPendingBurstSubmode="";gotoAndStop(55);}}'
            if spec['canBeAirborne']:
                if state=='击倒':
                    script='onClipEvent(load){_parent.elderCancelAttack();_parent.击飞浮空();}'
                    override_name=airborne_name
                elif state=='倒地':
                    script='onClipEvent(load){_parent.elderCancelAttack();_parent.击飞倒地();}'
                elif state=='被投':override_name=airborne_name
            bodies[index]={'duration':end-index,'elements':[body(sid,script,override_name)]}
        if form=='human':
            phase_name=PREFIX+'变身/角色演出'
            # Preserve all local body substitutions through f93. The subsequent
            # full-screen zoom, protagonist portrait and scene goto are not unit AI.
            result[phase_name]=make_body(phase_name,timelines['phase']['2008'][:93],parts,{
                0:{'script':'elderMode="phase";_parent.elderBeginTransform(this);stop();'},
                92:{'script':'_parent.elderSpawnRobot(this);stop();'}})
            bodies[141]={'duration':10,'elements':[native.instance(phase_name,
                matrix=(2/3,0,0,2/3,0,-133.325*2/3),symbol_type='movie clip',name='man')]}
        else: bodies[141]={'duration':10,'elements':[body(spec['stand'])]}
        init='''x轴攻击范围=0;y轴攻击范围=30;x轴保持距离=340;攻击欲望=3;命中率=30;
女_攻击呐喊_库=[];女_中招呐喊_库=[];女_击倒呐喊_库=[];
初始化敌人模板=_root.初始化敌人模板;初始化敌人模板();
elderForm="'''+form+'";\n'
        runtime_actions={key:{'totalFrames':action_durations[key],**{k:v for k,v in action.items() if k in ('state','hits','power','powers')}}
                         for key,action in spec['actions'].items()}
        if form=='human':
            runtime_actions['retreat_burst']={'totalFrames':94,'state':'空手攻击','hits':[63,65,68,70],'power':1}
        init+='elderActions={'+','.join(key+':{'+','.join(k+':'+json.dumps(v,ensure_ascii=False,separators=(',',':')) for k,v in action.items())+'}' for key,action in runtime_actions.items())+'};\n'
        init+=(HERE/'ElderAI.as').read_text('utf-8-sig')
        init+='\n'+(ROOT/'tools/cf6-headbot-assets/CorpseFragments.as').read_text('utf-8-sig')
        if form=='robot':init+='\n'+(ROOT/'tools/cf6-headbot-assets/RobotDeath.as').read_text('utf-8-sig')
        if form=='human':init+='\n'+(HERE/'ElderTransform.as').read_text('utf-8-sig')
        name=PREFIX+LINKS[form];roots[form]=name
        result[name]=native.symbol(name,[
            native.make_sparse_layer('状态标签',156,labels),
            native.make_sparse_layer('初始化与消失',156,{0:{'script':init},1:{'script':'this.swapDepths(this._y);'},
                151:{'script':'hp=0;elderCancelAttack();'}}),
            native.make_sparse_layer('私有行为',156,{0:{'duration':121,'elements':[native.instance(driver,symbol_type='movie clip',
                name='elderDriver',script='onClipEvent(enterFrame){_parent.elderTick();}onClipEvent(unload){if(typeof _parent.elderReportCombat=="function")_parent.elderReportCombat();}') ]}}),
            native.make_sparse_layer('文字信息',156,{0:{'duration':151,'elements':[native.instance(H['Symbol 32'],
                matrix=(1,0,0,1,0,-205),symbol_type='movie clip',name='人物文字信息')]}}),
            native.make_sparse_layer('受击包围盒',156,{0:{'duration':121,'elements':[native.instance(H['Symbol 19'],
                matrix=(3.2,0,0,7.2,-40,-184),symbol_type='movie clip',name='area')]}}),
            native.make_sparse_layer('通用仇恨驱动',156,{0:{'duration':29,'elements':[native.instance(H['思考标签'],symbol_type='movie clip')]}}),
            native.make_sparse_layer('行走',156,{0:{'duration':29,'elements':[native.instance(driver,symbol_type='movie clip',name='控制块',
                script='onClipEvent(enterFrame){if(!_root.暂停)_parent.行走();}')]}}),
            *([native.make_sparse_layer('轰炸特效模板',156,{0:{'duration':121,'elements':[
                native.instance(antiair_fx_name,matrix=(1,0,0,1,0,0),symbol_type='movie clip',name='cf6AntiairTemplate'),
                native.instance(bomb_fx_name,matrix=(1,0,0,1,0,0),symbol_type='movie clip',name='cf6BombTemplate')]}})] if form=='robot' else []),
            native.make_sparse_layer('动作',156,bodies)
        ],symbol_type='movie clip',linkage=LINKS[form],export_first_frame=True)
    entry=PREFIX+'两形态共享入口'
    result[entry]=native.symbol(entry,[native.layer('两形态闭包',[native.frame(script='stop();',elements=[
        native.instance(roots['human'],symbol_type='movie clip'),
        native.instance(roots['robot'],matrix=(1,0,0,1,350,0),symbol_type='movie clip')])])],symbol_type='movie clip')
    roots['entry']=entry
    return result,roots,stats

def import_assets(force=False):
    native.guard_overwrite_allowed(force)
    symbols,roots,stats=build_symbols()
    native.guard_overwrite_allowed(force)
    audio_receipt=audio.apply(symbols,OWNER,native.make_sparse_layer)
    outputs=common.write_workspace(symbols,roots['entry'])
    # The common single-root writer synthesizes Include IDs. Use each actual
    # DOMSymbolItem identity, including the vector adapter's distinct ID prefix.
    document=E.parse(str(OWNER/'DOMDocument.xml'),PARSER)
    for include in document.findall('x:symbols/x:Include',NS):
        symbol=E.parse(str(OWNER/'LIBRARY'/include.get('href')),PARSER).getroot()
        include.set('itemID',symbol.get('itemID'))
    (OWNER/'DOMDocument.xml').write_bytes(native.xml_bytes(document.getroot()))
    manifest={'schema':native.MANIFEST_SCHEMA,'owner':OWNER.relative_to(ROOT).as_posix(),
        'approvedInputs':{k:v.relative_to(ROOT).as_posix() for k,v in ARCHIVES.items()},
        'nativeSymbolCount':len(outputs),'buildInputs':build_inputs(),'parts':stats,'forms':FORMS,
        'phase':{'authoredFrames':283,'localFrames':93,'successor':LINKS['robot'],'spawnFrame':93,
            'matrix':[2/3,0,0,2/3,0,-133.325*2/3],'currentBodySources':['human-r7','robot-r7']},
        'omittedLegacyControls':[277,280,281,290,299,359,360],
        'sharedEffectReplacements':{'muzzle':506,'deathExplosion':list(range(364,391,2))},
        'slamMuzzle':{'part':986,'localPoint':list(SLAM_MUZZLE_LOCAL),'outwardAxis':[1,0],'frames':71},
        'outputs':outputs,'projectFiles':[{'path':p,'sha256':sha(OWNER/p),'bytes':(OWNER/p).stat().st_size} for p in native.PROJECT_FILES]}
    manifest['audio']=audio_receipt
    (HERE/'native-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
    common.mount_shared_library()
    print(json.dumps({'symbols':len(outputs),'linkages':LINKS},ensure_ascii=False))

def check():
    verify_inputs()
    manifest=json.loads((HERE/'native-manifest.json').read_text('utf8'))
    audio.check(manifest,OWNER)
    errors=native.workspace_identity_failures(manifest)
    if manifest['buildInputs']!=build_inputs():errors.append('Generator inputs changed; regenerate')
    includes={i.get('href') for i in E.parse(str(OWNER/'DOMDocument.xml')).findall('x:symbols/x:Include',NS)}
    for row in manifest['outputs']:
        tree=E.parse(str(OWNER/row['path']),PARSER)
        if row['path'][8:] not in includes:errors.append('Missing Include: '+row['path'])
        for el in tree.iter():
            ref=el.get('libraryItemName')
            if ref and not (OWNER/'LIBRARY'/(ref+'.xml')).is_file():errors.append('Unresolved '+ref)
        if tree.findall('.//x:BitmapFill',NS) or tree.findall('.//x:DOMBitmapInstance',NS):errors.append('Unexpected bitmap '+row['path'])
    if errors:raise ValueError('\n'.join(errors))
    print(json.dumps({'ok':True,'symbols':len(manifest['outputs']),'projectFiles':len(manifest['projectFiles'])}))

if __name__=='__main__':
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf8')
    parser=argparse.ArgumentParser();parser.add_argument('--import-approved',action='store_true');parser.add_argument('--force',action='store_true');parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if args.import_approved:import_assets(args.force)
    check()
