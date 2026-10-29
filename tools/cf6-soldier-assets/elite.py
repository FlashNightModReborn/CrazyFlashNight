"""Retarget 3XF motion onto the existing CF6 limbs, without importing donor art."""
from pathlib import Path
import copy
import json
import math
from lxml import etree as E
import elite_anatomy

NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{'+NS['x']+'}'
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'flashswf/arts/new/原体融合生物/LIBRARY/不明士兵/不明士兵动画/攻击动作.xml'
REFERENCE = ROOT/'flashswf/arts/new/Codex素材源稿/CF6特种兵-R3/reference/timelines.json'
PART_MANIFEST = REFERENCE.parent.parent/'asset-manifest.json'
PROFILE = Path(__file__).with_name('elite-motion-profile.json')
SIDEARM_ITEM = ROOT/'data/items/武器_手枪_大威力手枪.xml'
SIDEARM_ART = ROOT/'flashswf/arts/new/偷吃屑鱼坟头贡品/LIBRARY/枪-手枪-FR506.xml'
SIDEARM_HOLDER_SCALE = 0.2
PREFIX = 'Codex/特种兵/精英/'
LINKAGES = ('敌人-CF6特种精英', '敌人-CF6持盾特种精英')
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False, resolve_entities=False)
ROLES = {'pelvis':('4XG SCOUT BODY2',0), 'torso':('4XG SCOUT BODY',0),
    'head':('4XG SCOUT HEAD',0), 'backUpper':('4XG SCOUT FARM2',0),
    'backFore':('4XG SCOUT SARM',0), 'backHand':('4XG SCOUT HPARTA',0),
    'frontUpper':('4XG SCOUT FARM',0), 'frontFore':('4XG SCOUT SARM',1),
    'frontHand':('4XG SCOUT HAND',0), 'backThigh':('4XG SCOUT LEGB',0),
    'backShin':('4XG SCOUT LEG2',0), 'backFoot':('4XG SCOUT SHOE',0),
    'frontThigh':('4XG SCOUT LEGA',0), 'frontShin':('4XG SCOUT LEG2',1),
    'frontFoot':('4XG SCOUT SHOE',1), 'gun':('HK53 FN',0),
    'sidearm':('FR-506 12.7MM',0), 'knife':('对DLS谐振式匕首',0)}
DEPTH = {'pelvis':'6','torso':'4','head':'5','backUpper':'3','backFore':'8',
    'backHand':'7','frontUpper':'11','frontFore':'13','frontHand':'12',
    'backThigh':'2','backShin':'16','backFoot':'15','frontThigh':'14',
    'frontShin':'18','frontFoot':'17','gun':'9','knife':'1','sidearm':'19'}
ORDER = ['pelvis','torso','head','backUpper','backFore','backHand','frontUpper',
    'frontFore','frontHand','backThigh','backShin','backFoot','frontThigh','frontShin','frontFoot','knife','gun','sidearm']


def input_paths():
    return [Path(__file__), Path(__file__).with_name('EliteAI.as'),
        Path(__file__).with_name('elite_anatomy.py'), PROFILE, SOURCE, REFERENCE, PART_MANIFEST, SIDEARM_ITEM, SIDEARM_ART]


def matrix(node):
    m=node.find('x:matrix/x:Matrix',NS)
    return tuple(float(m.get(k,str(v))) for k,v in [('a',1),('b',0),('c',0),('d',1),('tx',0),('ty',0)])


def source_pose(frame):
    groups={}
    for instance in frame.findall('x:elements/x:DOMSymbolInstance',NS):
        leaf=instance.get('libraryItemName').rsplit('/',1)[-1]
        groups.setdefault(leaf,[]).append(matrix(instance))
    if 'HK53 FN' not in groups and 'HK53 N' in groups:
        groups['HK53 FN']=groups['HK53 N']
    poses={role:groups[name][index] for role,(name,index) in ROLES.items() if name in groups}
    poses['__instances']={role:groups[name] for role,(name,index) in ROLES.items() if name in groups}
    if '4XG SCOUT HPARTB' in groups:
        poses['__instances']['backHand']=poses['__instances']['backHand']+groups['4XG SCOUT HPARTB']
    return poses


def load_profile():
    return json.loads(PROFILE.read_text(encoding='utf-8'))


def as2_literal(value):
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return '['+','.join(as2_literal(item) for item in value)+']'
    if isinstance(value, dict):
        return '{'+','.join(str(key)+':'+as2_literal(item) for key,item in value.items())+'}'
    raise TypeError(type(value))


def source_frames(profile):
    required={index for action in profile['actions'].values()
        for index in range(action['first']-1,action['last'])}
    frames=E.parse(str(SOURCE),PARSER).findall('.//x:DOMLayer[@name="角色"]/x:frames/x:DOMFrame',NS)
    source={}
    for frame in frames:
        start=int(frame.get('index'));duration=int(frame.get('duration','1'))
        if start not in required:
            continue
        pose=source_pose(frame)
        for index in range(start,start+duration):
            if index in required:
                source[index]=pose
    missing=sorted(required-set(source))
    assert not missing, 'Incomplete 3XF source frames: '+str(missing)
    return source


def make_rig():
    references=json.loads(REFERENCE.read_text(encoding='utf-8'))
    profile=load_profile();source=source_frames(profile)
    bind=profile['targetStandBind'];target=copy.deepcopy(references[bind['sequence']][bind['frame']-1])
    ratios=[]
    for role,parent in elite_anatomy.PARENT.items():
        source_length=math.dist(source[profile['sourceBindFrame']-1][role][4:],source[profile['sourceBindFrame']-1][parent][4:])
        target_length=math.dist(target[DEPTH[role]]['matrix'][4:],target[DEPTH[parent]]['matrix'][4:])
        if source_length>1e-6 and target_length>1e-6:ratios.append(target_length/source_length)
    ratios.sort();scale=ratios[len(ratios)//2]
    side_bind=source[profile['sidearmBindFrame']-1]
    offset=elite_anatomy.multiply(scale,elite_anatomy.subtract(side_bind['sidearm'][4:],side_bind['backHand'][4:]))
    hand=target[DEPTH['backHand']]['matrix']
    target[DEPTH['sidearm']]={'id':506,'matrix':[1,0,0,1,hand[4]+offset[0],hand[5]+offset[1]]}
    parts={row['id']:row for row in json.loads(PART_MANIFEST.read_text(encoding='utf8'))['assets']}
    rig=elite_anatomy.Cf6Rig(target,DEPTH,ORDER,source,profile,references,parts)
    # Standard pistol exports register the trigger grip at the holder origin.
    # Donor sprite coordinates are unrelated to that equipment convention.
    rig.target_grips['sidearm']={side:(0,0) for side in ('front','back')}
    angle=elite_anatomy.matrix_angle(rig.bind['gun'])+math.pi
    rig.pistol_reference={'id':'primaryPistol','matrix':[
        math.cos(angle),math.sin(angle),-math.sin(angle),math.cos(angle),0,0]}
    rig.pistol_grips={'front':(0,0),'back':(8,0)}
    return rig


def retarget_frames():
    rig=make_rig()
    return rig.frames()


def install(symbols, native, base_prefix, ordinary, shield):
    name=PREFIX+'动作/CF6战术长枪'
    pistol_name=PREFIX+'武器/可配置主手枪'
    sidearm_name=PREFIX+'武器/可配置副手枪'
    reload_name=PREFIX+'武器/当前换弹手枪'
    mount=base_prefix+'武器/长枪挂点'
    for symbol,slot in ((pistol_name,'手枪'),(sidearm_name,'手枪2')):
        script=('onClipEvent(load){var unit:MovieClip=_parent._parent._parent;'
            '_root.装备引用配置.配置装扮(this,unit.'+slot+'_装扮,"装扮","'+slot+'_引用");}')
        symbols[symbol]=native.symbol(symbol,[native.layer('标准手枪引用',[native.frame(
            script='stop();',elements=[native.instance(mount,symbol_type='movie clip',name='枪',
                matrix=(SIDEARM_HOLDER_SCALE,0,0,SIDEARM_HOLDER_SCALE,0,0),script=script)])])],symbol_type='movie clip')
    reload_script=('onClipEvent(load){var unit:MovieClip=_parent._parent._parent;'
        'var slot:String=unit.soldierAttackOwner.reloadPair?"手枪":unit.soldierAttackOwner.reloadSlot;'
        '_root.装备引用配置.配置装扮(this,unit[slot+"_装扮"],"装扮",slot+"_引用");}')
    symbols[reload_name]=native.symbol(reload_name,[native.layer('当前事务的手枪',[native.frame(
        script='stop();',elements=[native.instance(mount,symbol_type='movie clip',name='枪',
            matrix=(SIDEARM_HOLDER_SCALE,0,0,SIDEARM_HOLDER_SCALE,0,0),script=reload_script)])])],symbol_type='movie clip')
    poses=retarget_frames();layers=[]
    for depth in sorted({int(value) for pose in poses for value in pose},reverse=True):
        frames=[];start=0
        while start<len(poses):
            row=poses[start].get(str(depth));end=start+1
            while end<len(poses) and poses[end].get(str(depth))==row:end+=1
            elements=[]
            if row is not None:
                if row['id']==492:
                    part=base_prefix+'武器/可配置长枪';instance_name='枪'
                elif row['id']=='primaryPistol':
                    part=pistol_name;instance_name='枪'
                elif row['id']=='reloadPistol':
                    part=reload_name;instance_name='枪'
                elif row['id']==506:
                    part=sidearm_name;instance_name='枪2'
                elif row['id']==489:
                    part=base_prefix+'分件/489';instance_name='腰挂'
                elif row['id']==484:
                    part=base_prefix+'装备/腿挂匕首';instance_name='腿挂匕首'
                else:
                    part=base_prefix+'分件/'+str(row['id']);instance_name=None
                if row['id']==484:instance_name='腿挂匕首'
                options={'symbol_type':'movie clip'} if instance_name else {}
                if row['id']==484:options['script']='onClipEvent(load){_visible=_parent._parent.soldierIsInstructor===true;}'
                if instance_name:options['name']=instance_name
                inst=native.instance(part,matrix=row['matrix'],**options)
                if inst.get('symbolType')=='graphic':
                    inst.set('loop','single frame');inst.set('firstFrame','0')
                elements=[inst]
            frames.append(native.frame(start,end-start,elements));start=end
        layers.append(native.layer('CF6分件_'+str(depth),frames))
    lifecycle={0:{'script':'stop();_parent.eliteBeginAttack(this);'},
        260:{'name':'换弹匣','label_type':'name','script':'_parent.eliteReloadStart(this);'},
        280:{'script':'_parent.eliteReloadGate(this);'},
        292:{'script':'_parent.eliteReloadCommit(this);'},
        294:{'script':'_parent.eliteReloadEnd(this);'},
        295:{'name':'双枪换弹匣','label_type':'name','script':'_parent.eliteReloadStart(this);'},
        315:{'script':'_parent.eliteReloadGate(this);'},
        327:{'script':'_parent.eliteReloadCommit(this);'},
        329:{'script':'_parent.eliteReloadEnd(this);'},
        330:{'name':'双枪同步换弹匣','label_type':'name','script':'_parent.eliteReloadStart(this);'},
        350:{'script':'_parent.eliteReloadGate(this);'},
        362:{'script':'_parent.eliteReloadCommit(this);'},
        364:{'script':'_parent.eliteReloadEnd(this);'}}
    permission=native.instance(mount,symbol_type='movie clip',name='射击许可标签')
    symbols[name]=native.symbol(name,[native.make_sparse_layer('标准生命周期',365,lifecycle),
        native.make_sparse_layer('标准射击许可',365,{0:{'duration':260,'elements':[permission]}}),*layers],symbol_type='movie clip')
    elite_source=('var eliteMotionConfig:Object = '+as2_literal(load_profile())+';\n'
        +Path(__file__).with_name('EliteAI.as').read_text(encoding='utf-8-sig'))
    for original,link in zip((ordinary,shield),LINKAGES):
        full=base_prefix+link
        root=native.symbol(full,copy.deepcopy(list(symbols[base_prefix+original].find('x:timeline/x:DOMTimeline/x:layers',NS))),
            symbol_type='movie clip',linkage=link,export_first_frame=True)
        root.find('x:timeline/x:DOMTimeline',NS).set('name',link)
        script=root.find('.//x:DOMLayer[@name="初始化与消失"]//x:script',NS)
        script.text=script.text.replace('初始化敌人模板=_root.初始化敌人模板;',
            'if(手枪==undefined)手枪="FR506";if(手枪2==undefined)手枪2="FR506";\n'
            '_root.主角函数.初始化掉落物.call(this);\n'
            '初始化敌人模板=_root.初始化敌人模板;')
        script.text=E.CDATA(script.text.replace('soldierInitializePhase();',elite_source+'\nsoldierInitializePhase();eliteInitialize();'))
        body=root.find('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame[@index="41"]/x:elements/x:DOMSymbolInstance',NS)
        body.set('libraryItemName',name)
        symbols[full]=root
    return {'linkages':list(LINKAGES),'motionSource':'3XF attack timeline; no donor drawings',
        'sourceBindFrame':53,'sidearmBindFrame':22,'targetBind':'CF6 507 anatomy and local art sockets',
        'retargeting':'source anatomical sockets; local-basis mirroring; fixed CF6 lengths; standard dual-pistol grips; source low-slide leg directions',
        'importedDonorArtSymbols':0,'legacyScriptsImported':0,'actions':['stand','retreat','run','slide'],
        'panelAuthority':'466/467 inherited panel; explicit toughness exception in elite-tuning.json','hitboxAuthority':'unchanged CF6 receiver',
        'fireBudget':'source fire anchors: stand5; retreat4+4; run8; slide5; standard interval and 30-frame rest',
        'extraWeapons':{'secondary':'FR506','secondary2':'FR506','externalSlots':['手枪','手枪2'],'actions':['retreat']},'grenades':'smoke reload','extraArmor':False}
