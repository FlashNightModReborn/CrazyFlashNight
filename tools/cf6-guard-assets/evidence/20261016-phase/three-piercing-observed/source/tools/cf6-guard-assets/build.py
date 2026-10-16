"""CF6 bald guard R2 humanoid, native vectors and a fixed CF7 shotgun."""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import sys
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ARCHIVE = ROOT/'flashswf/arts/new/Codex素材源稿/CF6光头保安-R2'
OWNER = ROOT/'flashswf/arts/new/Codex光头保安素材'
ANCHOR = 'Codex光头保安素材'
LINKAGE = '敌人-CF6光头保安'
PREFIX = 'Codex/光头保安/'
NS = {'x':'http://ns.adobe.com/xfl/2008/'}
N = '{'+NS['x']+'}'
PARSER = E.XMLParser(remove_blank_text=False,strip_cdata=False,resolve_entities=False)
SEQUENCES = {595:'站立',596:'行走',597:'被击',598:'被投',875:'击倒原稿',611:'死亡',874:'散弹射击'}
OFFSETS = {595:(1.15,-51.4),596:(19.85,-60.85),597:(8.95,-59.95),598:(16.15,-61),
           875:(5.5,-59),611:(5,-61.95),874:(4.75,-62.05)}
GUN_SOURCE = ROOT/'flashswf/arts/things切割/LIBRARY/长枪/SPAS12/枪-长枪-SPAS12.xml'


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    result=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


common=module('guard_common',ROOT/'tools/cf6-manman-assets/build.py')
vector=module('guard_vector',HERE/'vector.py')
transform=module('guard_transform',HERE/'transform.py')
native=common.native
for key,value in {'ROOT':ROOT,'HERE':HERE,'OWNER':OWNER,'ARCHIVE':ARCHIVE,
                  'ANCHOR':ANCHOR,'LINKAGE':LINKAGE,'PREFIX':PREFIX}.items():
    setattr(common,key,value)
native.OWNER,native.HERE=OWNER,HERE
native.MANIFEST_SCHEMA='cf6-guard.native-import.v1'
native.PROJECT_FILES=('DOMDocument.xml',ANCHOR+'.xfl','PublishSettings.xml','MobileSettings.xml')
native.SHARED_HELPERS={old:PREFIX+'CF7/'+old for old in native.SHARED_HELPERS}
H=native.SHARED_HELPERS


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ground_shift(timeline):
    """Ground the visible shoe alpha contour, not the atlas or export rectangle."""
    svg=E.parse(str(ARCHIVE/'parts/582.svg'))
    path=svg.find('.//{http://www.w3.org/2000/svg}clipPath[@id="alpha582"]/{http://www.w3.org/2000/svg}path')
    data=path.get('d')
    if re.search(r'[A-KN-Yb-km-y]',data):
        raise ValueError('Shoe alpha contour must remain an M/L/Z polygon')
    values=[float(v) for v in re.findall(r'-?\d+(?:\.\d+)?',data)]
    points=list(zip(values[::2],values[1::2]))
    candidates=[]
    for row in timeline['595'][0].values():
        if row['id']!=582:
            continue
        a,b,c,d,tx,ty=row['matrix']
        candidates.extend(b*(x-237.7)+d*(y-97.4)+ty+OFFSETS[595][1] for x,y in points)
    if len(candidates)!=2*len(points):
        raise ValueError('Expected two standing shoes')
    return -max(candidates)


def build_inputs():
    paths=[HERE/'build.py',HERE/'vector.py',HERE/'transform.py',HERE/'GuardAI.as',HERE/'GuardTransform.as',GUN_SOURCE,
        ROOT/'tools/cf6-wings-assets/vector.py',ROOT/'tools/cf6-manman-assets/build.py',
        ROOT/'tools/cf6-zombie-assets/build.py',ROOT/'tools/gamma-echo-assets/build.py',
        ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
        ROOT/'tools/asset-metrology/xfl_geometry.py',
        ROOT/'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml']
    paths += [native.THINGS1/(old+'.xml') for old in sorted(H)]
    paths += transform.input_paths()
    paths += [ROOT/'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as',
              ROOT/'scripts/逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as']
    rows=[]
    for p in paths:
        data=p.read_bytes();row={'path':p.relative_to(ROOT).as_posix()}
        if p.suffix=='.as' and p.parent!=HERE:
            data=data.replace(b'\r\n',b'\n');row['lineEndingNormalization']='lf'
        row['sha256']=hashlib.sha256(data).hexdigest();rows.append(row)
    return rows


def depth_layers(timeline,parts):
    layers=[]
    for depth in sorted({int(d) for f in timeline for d,row in f.items() if row['id'] in parts},reverse=True):
        states=[f.get(str(depth)) if f.get(str(depth),{}).get('id') in parts else None for f in timeline]
        frames,start=[],0
        while start<len(states):
            row,end=states[start],start+1
            def visual(value):
                return None if value is None else (value['id'],value['matrix'],value.get('colorMult'),value.get('colorAdd'))
            while end<len(states) and visual(states[end])==visual(row):
                end+=1
            elements=[]
            if row is not None:
                inst=native.instance(parts[row['id']],matrix=row['matrix'],
                    **({'symbol_type':'movie clip','name':'guardGun'} if row['id']==593 else {}))
                mult,add=row.get('colorMult',[256]*4),row.get('colorAdd',[0]*4)
                if mult!=[256]*4 or add!=[0]*4:
                    color=E.SubElement(E.SubElement(inst,N+'color'),N+'Color')
                    for i,channel in enumerate(('red','green','blue','alpha')):
                        color.set(channel+'Multiplier',native.num(mult[i]/256))
                        color.set(channel+'Offset',native.num(add[i]))
                elements.append(inst)
            frames.append(native.frame(start,end-start,elements));start=end
        layers.append(native.layer('原始深度_'+str(depth),frames))
    return layers


def make_body(name,timeline,parts,scripts=None):
    return native.symbol(name,[native.make_sparse_layer('CF7生命周期',len(timeline),scripts or {}),
        *depth_layers(timeline,parts)],symbol_type='movie clip')


def build_symbols():
    common.verify_input()
    timeline=json.loads((ARCHIVE/'reference/timelines.json').read_text('utf8'))
    assets={r['id']:r for r in json.loads((ARCHIVE/'asset-manifest.json').read_text('utf8'))['assets']}
    required={r['id'] for sid in SEQUENCES for f in timeline[str(sid)] for r in f.values()}
    required-={281,299,311,359,360,506,593}
    if required!={*range(582,591),594,*range(600,611)}:
        raise ValueError('Humanoid drawing closure changed')
    result,parts,stats=native.clone_shared_helpers(),{},[]
    vector.NativePart.shared_references={}
    for cid in sorted(required):
        name=PREFIX+'分件/'+str(cid)
        converted,report=vector.NativePart(ARCHIVE/assets[cid]['file'],name,(0,0)).build()
        for key,item in converted.items():
            if key in result and native.xml_bytes(result[key])!=native.xml_bytes(item):
                raise ValueError('Conflicting vector atlas: '+key)
        result.update(converted);parts[cid]=name;stats.append({'id':cid,**report})

    # The archived CF6 gun is a bitmap. Reuse the existing CF7 SPAS12 vectors,
    # preserving the authored grip at (0,0), with one explicit 0.6 scale.
    gun=PREFIX+'武器/SPAS12原生画稿'
    source=E.parse(str(GUN_SOURCE),PARSER)
    shapes=source.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame/x:elements/x:DOMShape',NS)
    marker=PREFIX+'武器/枪口'
    result[marker]=native.symbol(marker,[native.layer('空挂点',[native.frame(script='stop();')])],symbol_type='movie clip')
    if not shapes or len(source.findall('.//x:DOMSymbolInstance',NS))!=1:
        raise ValueError('SPAS12 artwork dependency changed')
    result[gun]=native.symbol(gun,[native.layer('枪口',[native.frame(elements=[
        native.instance(marker,matrix=(1,0,0,1,302.8,-34.05),symbol_type='movie clip',name='枪口')],script='stop();')]),
        native.layer('CF7原生矢量',[native.frame(elements=[copy.deepcopy(s) for s in shapes])])],symbol_type='movie clip')
    weapon=PREFIX+'武器/固定散弹枪'
    result[weapon]=native.symbol(weapon,[native.layer('握点不变',[native.frame(script='stop();',elements=[
        native.instance(gun,matrix=(0.6,0,0,0.6,0,0),symbol_type='movie clip',name='gunArt')])])],symbol_type='movie clip')
    parts[593]=weapon
    phase_manifest=transform.add_parts(sys.modules[__name__],result,parts,stats)
    actions={sid:PREFIX+'动作/'+name for sid,name in SEQUENCES.items()}
    result[actions[595]]=make_body(actions[595],timeline['595'],parts,
        {4:{'script':'if(_parent.状态=="躲闪" || _parent.状态=="拾取")_parent.动画完毕();'}})
    result[actions[596]]=make_body(actions[596],timeline['596'],parts)
    result[actions[874]]=make_body(actions[874],timeline['874'],parts,{
        0:{'script':'_parent.guardBeginAttack(this);stop();'},
        40:{'script':'_parent.guardShoot(this);stop();'},
        73:{'script':'_parent.guardFinishAttack(this);stop();'}})
    result[actions[597]]=make_body(actions[597],timeline['597'],parts,{
        0:{'name':'a0','label_type':'name'},12:{'name':'a1','label_type':'name'},
        7:{'script':'_parent.动画完毕();'},18:{'script':'_parent.动画完毕();'}})
    result[actions[598]]=make_body(actions[598],timeline['598'],parts,{12:{'script':'stop();'}})
    airborne,down=PREFIX+'动作/击飞',PREFIX+'动作/倒地恢复'
    result[airborne]=make_body(airborne,timeline['875'][:40],parts,{
        0:{'name':'空手','label_type':'name'},39:{'script':'stop();'}})
    result[down]=make_body(down,timeline['875'][40:],parts,{
        8:{'script':'_parent.死亡检测();'},75:{'script':'_parent.动画完毕();'}})
    result[actions[611]]=make_body(actions[611],timeline['611'],parts,{
        0:{'name':'a0','label_type':'name'},31:{'name':'a1','label_type':'name'},77:{'name':'a2','label_type':'name'},
        30:{'script':'_parent.死亡检测();stop();'},76:{'script':'_parent.死亡检测();stop();'},
        111:{'script':'_parent.死亡检测();stop();'}})

    driver=PREFIX+'行为驱动'
    result[driver]=native.symbol(driver,[native.layer('停止',[native.frame(script='stop();')])],symbol_type='movie clip')
    shadow=result[H['Symbol 2']];shadow.set('symbolType','movie clip')
    shadow.find('x:timeline/x:DOMTimeline/x:layers',NS).insert(0,native.layer('全状态接地',[native.frame(script='''guardGround={x:0,y:0};
updateGuardShadow=function():Void {
    var unit:MovieClip=this._parent;
    var visible:Boolean=_root.是否阴影==true;
    if(this._visible!=visible)this._visible=visible;
    if(isNaN(unit.Z轴坐标))return;
    var p:Object=this.guardGround;p.x=unit._x;p.y=unit.Z轴坐标;
    unit._parent.localToGlobal(p);unit.globalToLocal(p);
    if(this._x!=p.x)this._x=p.x;if(this._y!=p.y)this._y=p.y;
    var rotation:Number=unit._xscale<0?unit._rotation:-unit._rotation;
    if(this._rotation!=rotation)this._rotation=rotation;
};
onEnterFrame=updateGuardShadow;updateGuardShadow();stop();''')]))
    phase_shadow=PREFIX+'变身/接地阴影'
    result[phase_shadow]=copy.deepcopy(shadow)
    result[phase_shadow].set('name',phase_shadow)
    result[phase_shadow].set('itemID',native.item_id(phase_shadow))
    for script in result[phase_shadow].findall('.//x:script',NS):
        script.text=E.CDATA(script.text.replace('this._parent;','this._parent._parent;')
            .replace('unit.globalToLocal(p);','this._parent.globalToLocal(p);'))
    phase_action=PREFIX+'动作/变身'
    expected_phase={*range(262,275),*range(582,591),594,878,880,882,883,884,885,886}
    used_phase={r['id'] for f in timeline['887'] for r in f.values()}
    if not used_phase.issubset(expected_phase) or not used_phase.issubset(parts):
        raise ValueError('Transformation drawing closure changed: '+str(used_phase-set(parts)))
    result[phase_action]=make_body(phase_action,timeline['887'],parts,{
        0:{'script':'_parent.guardBeginTransform(this);stop();'},
        69:{'script':'_parent.guardSpawnTyrant(this);stop();'},
        70:{'script':'stop();'}})
    phase_layers=result[phase_action].find('x:timeline/x:DOMTimeline/x:layers',NS)
    phase_layers.insert(0,native.layer('身体内死亡后驱动',[native.frame(0,75,[
        native.instance(driver,symbol_type='movie clip',name='phaseDriver',
            script='onClipEvent(enterFrame){_parent._parent.guardTransformTick(_parent);}')])]))
    phase_layers.append(native.layer('身体内接地阴影',[native.frame(0,75,[
        native.instance(phase_shadow,matrix=(0.62,0,0,0.14,0,0),symbol_type='movie clip',name='phaseShadow')])]))
    shift=ground_shift(timeline)
    def body(sid,script=None,name=None):
        x,y=OFFSETS[sid]
        return native.instance(name or actions[sid],matrix=(1,0,0,1,x,y+shift),
            symbol_type='movie clip',name='man',script=script)
    states={1:'空手站立',9:'空手行走',19:'空手跑',29:'空手跳',37:'近战',41:'空手攻击',
        51:'拾取',61:'躲闪',71:'被击',79:'击倒',88:'倒地',95:'被投',104:'血腥死',120:'消失',130:'变身'}
    init='''攻击模式="空手";x轴攻击范围=0;y轴攻击范围=24;x轴保持距离=340;攻击欲望=3;命中率=20;击中效果="飙血";
'''+(HERE/'GuardAI.as').read_text('utf-8-sig')+'\n'+(HERE/'GuardTransform.as').read_text('utf-8-sig')+'''
_root.敌人函数.配置音效("人类",this);
初始化敌人模板=_root.初始化敌人模板;初始化敌人模板();
'''
    bodies={0:(9,body(595)),9:(10,body(596)),19:(10,body(596)),29:(8,body(598)),
        37:(4,body(874)),41:(10,body(874)),51:(10,body(595)),61:(10,body(595)),
        71:(8,body(597,'onClipEvent(load){_parent.guardCancelAttack();gotoAndPlay("a"+random(2));}')),
        79:(9,body(875,'onClipEvent(load){_parent.guardCancelAttack();_parent.击飞浮空();}',airborne)),
        88:(7,body(875,'onClipEvent(load){_parent.guardCancelAttack();_parent.击飞倒地();}',down)),
        95:(9,body(598,'onClipEvent(load){_parent.guardCancelAttack();}')),
        104:(16,body(611,'onClipEvent(load){_parent.guardCancelAttack();gotoAndPlay("a"+random(3));}')),
        130:(80,native.instance(phase_action,matrix=(1,0,0,1,3,-65.5+shift),symbol_type='movie clip',name='man'))}
    root_name=PREFIX+LINKAGE
    result[root_name]=native.symbol(root_name,[
        native.make_sparse_layer('状态标签',215,{i:{'name':s,'label_type':'name'} for i,s in states.items()}),
        native.make_sparse_layer('初始化与消失',215,{0:{'script':init},1:{'script':'this.swapDepths(this._y);'},120:{'script':'hp=0;guardCancelAttack();'}}),
        native.make_sparse_layer('私有行为',215,{0:{'duration':120,'elements':[
            native.instance(driver,symbol_type='movie clip',name='guardDriver',script='onClipEvent(enterFrame){_parent.guardTick();}')]}}),
        native.make_sparse_layer('文字信息',215,{0:{'duration':120,'elements':[
            native.instance(H['Symbol 32'],matrix=(1,0,0,1,0,-150),symbol_type='movie clip',name='人物文字信息')]}}),
        native.make_sparse_layer('受击包围盒',215,{0:{'duration':79,'elements':[
            native.instance(H['Symbol 19'],matrix=(3.2,0,0,5.2,-44,-132),symbol_type='movie clip',name='area')]},
            79:{'duration':9,'elements':[native.instance(H['Symbol 19'],matrix=(3.2,0,0,5.2,-44,-132),symbol_type='movie clip',name='area')]},
            88:{'duration':7,'elements':[native.instance(H['Symbol 19'],matrix=(5.4,0,0,1.7,-68,-43),symbol_type='movie clip',name='area')]},
            95:{'duration':9,'elements':[native.instance(H['Symbol 19'],matrix=(3.2,0,0,5.2,-44,-132),symbol_type='movie clip',name='area')]}}),
        native.make_sparse_layer('通用索敌',215,{0:{'duration':29,'elements':[native.instance(H['思考标签'],symbol_type='movie clip')]}}),
        native.make_sparse_layer('行走',215,{0:{'duration':29,'elements':[
            native.instance(driver,symbol_type='movie clip',name='控制块',script='onClipEvent(enterFrame){if(!_root.暂停)_parent.行走();}')]}}),
        native.make_sparse_layer('动作',215,{i:{'duration':d,'elements':[b]} for i,(d,b) in bodies.items()}),
        native.make_sparse_layer('全状态接地阴影',215,{0:{'duration':120,'elements':[
            native.instance(H['Symbol 2'],matrix=(0.62,0,0,0.14,0,0),symbol_type='movie clip',name='guardShadow')]}}),
    ],symbol_type='movie clip',linkage=LINKAGE,export_first_frame=True)
    return result,root_name,stats,shift,phase_manifest


def import_assets():
    native.guard_overwrite_allowed(False)
    symbols,root_name,stats,shift,phase_manifest=build_symbols()
    native.guard_overwrite_allowed(False)
    outputs=common.write_workspace(symbols,root_name)
    manifest={'schema':native.MANIFEST_SCHEMA,'owner':OWNER.relative_to(ROOT).as_posix(),
        'approvedInput':ARCHIVE.relative_to(ROOT).as_posix(),'nativeSymbolCount':len(outputs),
        'buildInputs':build_inputs(),'parts':stats,'groundShift':shift,
        'sourceOffsets':{str(k):v for k,v in OFFSETS.items()},'sourceRoot':888,'transformationIncluded':True,'transformation':phase_manifest,
        'sourceBodyFrames':525,'attackFrames':{'fire':41,'finish':74,'authored':87},'pellets':int(re.search(r'\bpellets\s*:\s*(\d+)',(HERE/'GuardAI.as').read_text('utf-8-sig'))[1]),
        'deathBranches':[[1,31],[32,77],[78,112]],'airborneSourceFrames':[1,40],'landedSourceFrames':[41,116],
        'gun':{'source':GUN_SOURCE.relative_to(ROOT).as_posix(),'scale':0.6,'muzzle':[302.8,-34.05],
            'archivedBitmapReplaced':592,'equipmentConfigurable':False},'outputs':outputs,
        'projectFiles':[{'path':p,'sha256':sha(OWNER/p),'bytes':(OWNER/p).stat().st_size} for p in native.PROJECT_FILES]}
    (HERE/'native-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
    common.mount_shared_library()
    print(json.dumps({'symbols':len(outputs),'linkage':LINKAGE,'groundShift':shift},ensure_ascii=False))


def check():
    common.verify_input()
    transform.verify_archive()
    manifest=json.loads((HERE/'native-manifest.json').read_text('utf8'))
    errors=native.workspace_identity_failures(manifest)
    if manifest['buildInputs']!=build_inputs():
        errors.append('Generator inputs changed; guarded regeneration required')
    includes={i.get('href') for i in E.parse(str(OWNER/'DOMDocument.xml')).findall('x:symbols/x:Include',NS)}
    masks=0
    for row in manifest['outputs']:
        tree=E.parse(str(OWNER/row['path']),PARSER)
        if row['path'][8:] not in includes:errors.append('Missing Include: '+row['path'])
        for element in tree.iter():
            ref=element.get('libraryItemName')
            if ref and not (OWNER/'LIBRARY'/(ref+'.xml')).is_file():errors.append('Unresolved '+ref)
        if tree.findall('.//x:BitmapFill',NS) or tree.findall('.//x:DOMBitmapInstance',NS):
            errors.append('Unexpected bitmap '+row['path'])
        layers=tree.findall('.//x:DOMLayer',NS)
        if len(layers)==2 and layers[0].get('layerType')=='mask':
            masks+=1;mask,paint=native._layer_bbox(layers[0]),native._layer_bbox(layers[1])
            if not mask or not paint or min(mask[1],paint[1])<=max(mask[0],paint[0]) or min(mask[3],paint[3])<=max(mask[2],paint[2]):
                errors.append('Empty or disjoint mask '+row['path'])
    if errors:raise ValueError('\n'.join(errors))
    print(json.dumps({'ok':True,'symbols':len(manifest['outputs']),'masksChecked':masks}))


if __name__=='__main__':
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf8')
    parser=argparse.ArgumentParser()
    parser.add_argument('--import-approved',action='store_true');parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if args.import_approved:import_assets()
    check()
