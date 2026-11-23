"""Frozen Animate 24 poses, baked with native parenting and tween evaluation."""
from pathlib import Path
import copy
import hashlib
import json
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'flashswf/arts/new/Codex素材源稿/CF6特种兵-美术R8'
ALTER_SOURCE = ROOT/'flashswf/arts/new/Codex素材源稿/CF6特种兵-美术Alter'
NS = {'x':'http://ns.adobe.com/xfl/2008/'}


def input_paths():
    return [Path(__file__), Path(__file__).with_name('SoldierRoles.as'),
            *sorted(p for p in SOURCE.rglob('*') if p.is_file()),
            *sorted(p for p in ALTER_SOURCE.rglob('*') if p.is_file())]


def load_alter():
    origin=json.loads((ALTER_SOURCE/'archive-origin.json').read_text(encoding='utf-8'))
    for row in origin['members']:
        if hashlib.sha256((ALTER_SOURCE/row['path']).read_bytes()).hexdigest()!=row['sha256']:
            raise ValueError('Frozen alter motion changed: '+row['path'])
    return json.loads((ALTER_SOURCE/'native-alter-samples.json').read_text(encoding='utf-8'))['actions']


def alter_poses(action_data, start_1, end_1):
    result=[]
    for raw in action_data['poses'][start_1-1:end_1]:
        pose={}
        for row in raw:
            part=row['part']
            if part.endswith('/可配置长枪'):
                pid=492
            elif '/分件/' in part:
                pid=int(part.rsplit('/',1)[-1])
            else:
                continue
            pose[str(row['depth'])]={'id':pid,
                'matrix':row['matrix'],
                'colorMult':[v*2.56 for v in row['colorMult']],
                'colorAdd':row['colorAdd']}
        result.append(pose or copy.deepcopy(result[-1]))
    return result


def install_fx(b, symbols):
    p=b.PREFIX
    for leaf in ('smoke17', '速度线'):
        root=E.parse(str(ALTER_SOURCE/'fx'/(leaf+'.xml')),b.PARSER).getroot()
        name=p+'特效/'+leaf
        root.set('name',name)
        root.set('symbolType','graphic')
        root.set('itemID','6af20000-'+hashlib.sha256(name.encode('utf-8')).hexdigest()[:8])
        for attr in ('sourceFlashFilepath','sourceLibraryItemHRef','sourceLastModified','sourceItemID',
                     'linkageIdentifier','linkageExportForAS','linkageExportForRS','linkageImportForRS','linkageURL'):
            root.attrib.pop(attr,None)
        tl=root.find('x:timeline/x:DOMTimeline',NS)
        tl.set('name',leaf)
        tl.attrib.pop('layerDepthEnabled',None)
        symbols[name]=root


def load():
    origin=json.loads((SOURCE/'archive-origin.json').read_text(encoding='utf-8'))
    for row in origin['members']:
        if hashlib.sha256((SOURCE/row['path']).read_bytes()).hexdigest()!=row['sha256']:
            raise ValueError('Frozen native motion changed: '+row['path'])
    report=json.loads((SOURCE/'native-motion-samples.json').read_text(encoding='utf-8'))
    result={}
    for name,action in report['actions'].items():
        poses=[]
        for raw in action['poses']:
            pose={}
            for row in raw:
                leaf=row['part'].rsplit('/',1)[-1]
                pose[str(row['depth'])]={'id':492 if leaf=='可配置长枪' else int(leaf),
                    'matrix':row['matrix'], 'colorMult':[v*2.56 for v in row['colorMult']],
                    'colorAdd':row['colorAdd']}
            # Authoring timelines end with a blank stop key. The runtime retains
            # the last visible pose until the owning state changes.
            poses.append(pose or copy.deepcopy(poses[-1]))
        result[name]=poses
    return result


def sample(poses,count):
    return [copy.deepcopy(poses[round(i*(len(poses)-1)/(count-1))]) for i in range(count)]


def install(b, symbols, parts, old):
    n,p=b.native,b.PREFIX
    poses=load()
    alter=load_alter()
    install_fx(b,symbols)
    def body(name,frames,scripts=None):
        symbols[p+'动作/'+name]=b.make_body(p+'动作/'+name,frames,parts,scripts)
    def art_only(name,frames):
        layers=symbols[p+'动作/'+name].find('x:timeline/x:DOMTimeline/x:layers',NS)
        for layer in list(layers):
            if layer.get('name','').startswith('原始深度_'):layers.remove(layer)
        layers.extend(b.depth_layers(frames,parts))
    for name in ('站立','行走','匕首刺击','持盾站立','持盾行走'):
        art_only(name,poses[name])
    # Authored 被击.xml has two distinct reactions: f1-7 (head-back) and f8-16 (duck-forward).
    hit_a0=copy.deepcopy(poses['被击'][:7])+[copy.deepcopy(poses['被击'][6])]
    hit_a1=copy.deepcopy(poses['被击'][7:16])+[copy.deepcopy(poses['被击'][15])]
    body('被击',hit_a0+hit_a1,{0:{'name':'a0','label_type':'name'},
        len(hit_a0)-1:{'script':'_parent.动画完毕();'},
        len(hit_a0):{'name':'a1','label_type':'name'},
        len(hit_a0)+len(hit_a1)-1:{'script':'_parent.动画完毕();'}})
    body('跑步',poses['跑步'])
    body('被投',poses['被投'],{13:{'script':'stop();'}})
    body('击飞',poses['击飞'],{0:{'name':'空手','label_type':'name'},28:{'script':'stop();'}})
    body('倒地恢复',poses['倒地恢复'],{13:{'script':'_parent.死亡检测();'},77:{'script':'_parent.动画完毕();'}})
    # Use the authored 139-frame 死亡.xml verbatim across all three branches (a0/a1/a2).
    art_only('死亡',poses['死亡'])
    holder=p+'武器/长枪挂点'
    for name,move_range in (('长枪点射与装填',(243,263)),('持盾点射与装填',(113,133))):
        recoil=sample(poses[name][:14],14)
        reload_hold=[copy.deepcopy(recoil[0]) for _ in range(35)]
        moving=alter_poses(alter[name],move_range[0],move_range[1])
        total_shoot=len(recoil)+len(reload_hold)+len(moving)
        symbols[p+'动作/'+name]=n.symbol(p+'动作/'+name,[
            n.make_sparse_layer('标准射击与装填',total_shoot,{
                0:{'script':'_parent.soldierBeginAttack(this,"shoot");'},
                2:{'name':'射击','label_type':'name'},
                5:{'script':'gotoAndStop("空闲");'},
                13:{'name':'空闲','label_type':'name','script':'stop();'},
                14:{'name':'换弹匣','label_type':'name','script':'_parent.soldierReloadStart(this);'},
                34:{'script':'_root.主角函数.换弹门禁(this);'},
                46:{'script':'if(_parent.soldierCanAct(this))换弹匣();'},
                48:{'script':'_parent.soldierReloadEnd(this);'},
                49:{'name':'移动射击','label_type':'name','script':'stop();'}}),
            n.make_sparse_layer('标准射击许可',total_shoot,{
                0:{'duration':14,'elements':[n.instance(holder,symbol_type='movie clip',name='射击许可标签')]},
                49:{'duration':len(moving),'elements':[n.instance(holder,symbol_type='movie clip',name='射击许可标签')]}}),
            *b.depth_layers(recoil+reload_hold+moving,parts)],symbol_type='movie clip')
    # Both hit variants use the full 62-frame authored crouch-guard-and-return motion.
    cover=copy.deepcopy(poses['持盾被击'])
    body('持盾被击',cover+copy.deepcopy(cover),{0:{'name':'a0','label_type':'name'},
        12:{'script':'_parent.soldierGuardPose(this,true);'},
        50:{'script':'_parent.soldierGuardPose(this,false);'},
        62:{'name':'a1','label_type':'name'},
        74:{'script':'_parent.soldierGuardPose(this,true);'},
        112:{'script':'_parent.soldierGuardPose(this,false);'},
        61:{'script':'_parent.soldierEndShieldGuard();_parent.动画完毕();'},
        123:{'script':'_parent.soldierEndShieldGuard();_parent.动画完毕();'}})

    # Preserve the previous shield stab as one branch; unify shield bash with the 59-frame authored motion.
    melee=b.tactics.instructor_melee
    stab=old['573'];bash=melee.source.load_poses()['持盾匕首刺击']
    bash_offset=len(stab);bash_total=bash_offset+len(bash)
    center=-135/2-b.OFFSETS[517][1]-b.GROUND_SHIFT
    stab_hit={13:{'elements':[n.instance(b.H['Symbol 195'],matrix=(135/25,0,0,135/25,27.3,center),
        symbol_type='movie clip',name='攻击点',alpha_mult=0,
        script='onClipEvent(load){_parent._parent.soldierMeleeHit(_parent,this);}') ]}}
    bash_hit_idx=bash_offset+melee.BASH_IMPACT-1
    bash_hit={bash_hit_idx:{'elements':[melee.contact(b,bash[melee.BASH_IMPACT-1],561,melee.SHIELD_RIM,'soldierMeleeHit')]}}
    lifecycle={0:{'script':'_parent.soldierBeginMelee(this);'},
        33:{'script':'_parent.soldierFinishAttack(this);'},
        bash_offset:{'name':'挥盾','label_type':'name'},bash_total-1:{'script':'_parent.soldierFinishAttack(this);'}}
    symbols[p+'动作/持盾匕首刺击']=n.symbol(p+'动作/持盾匕首刺击',[
        n.make_sparse_layer('攻击生命周期',bash_total,lifecycle),
        n.make_sparse_layer('真实近战判定',bash_total,{**stab_hit,**bash_hit}),
        *b.depth_layers(stab+bash,parts)],symbol_type='movie clip')
    throw=poses['长枪点射与装填'][23:59]
    body('投掷手雷',throw,{0:{'script':'_parent.soldierBeginGrenade(this);'},
        24:{'script':'_parent.soldierThrowGrenade(this);'},35:{'script':'_parent.soldierFinishAttack(this);'}})
    throw_root=symbols[p+'动作/投掷手雷']
    for inst in throw_root.findall('.//x:DOMSymbolInstance',NS):
        if inst.get('libraryItemName')==parts[490]:
            inst.set('symbolType','movie clip');inst.set('name','投掷手')
    held=p+'武器/可配置投掷物'
    symbols[held]=n.symbol(held,[n.layer('当前投掷物',[n.frame(script='''stop();
var unit:MovieClip=_parent._parent;
var data:Object=_root.getItemData(unit.特种兵投掷物).data;
if(typeof data.dressup=="string")attachMovie(data.dressup,"装扮",1);''')])],symbol_type='movie clip')
    held_frames=[]
    for index,pose in enumerate(throw):
        hand=next(row for row in pose.values() if row['id']==490)
        m=hand['matrix'];scale=(m[0]*m[0]+m[1]*m[1])**.5
        elements=[n.instance(held,matrix=tuple(v*.12/scale for v in m[:4])+(m[4],m[5]-3),
            symbol_type='movie clip',name='手持投掷物')] if 10<=index<24 else []
        held_frames.append(n.frame(index,elements=elements))
    throw_root.find('x:timeline/x:DOMTimeline/x:layers',NS).insert(1,n.layer('取出后握持至出手',held_frames))
    # Root-aligned 84-frame authored shield charge (20 windup + 24 loop + 40 recovery) + 35-frame reload.
    charge=alter_poses(alter['持盾点射与装填'],28,111)
    charge_len=len(charge)
    charge.extend([copy.deepcopy(poses['持盾点射与装填'][0]) for _ in range(35)])
    charge_total=len(charge)
    charge_scripts={0:{'script':'stop();_parent.soldierBeginCharge(this);'},
        20:{'name':'循环开始','label_type':'name'},
        44:{'name':'结束','label_type':'name'},
        charge_len:{'name':'换弹匣','label_type':'name','script':'_parent.soldierReloadStart(this);'},
        charge_len+20:{'script':'_root.主角函数.换弹门禁(this);'},
        charge_len+32:{'script':'if(_parent.soldierCanAct(this))换弹匣();'},
        charge_total-1:{'script':'_parent.soldierReloadEnd(this);'}}
    body('盾冲射击',charge,charge_scripts)
    layers=symbols[p+'动作/盾冲射击'].find('x:timeline/x:DOMTimeline/x:layers',NS)
    # Apply the exact Alter horizontal motion-blur ramp (f21-47: 20, f48-50: 12.8, f51-53: 6.8, f54-56: 3, f57-59: 0.9).
    blur_spans=((20,47,'20'),(47,50,'12.8'),(50,53,'6.8'),(53,56,'3'),(56,59,'0.9'))
    def charge_blur(frame_idx):
        for s0,s1,val in blur_spans:
            if s0<=frame_idx<s1:return val
        return None
    cuts={20,47,50,53,56,59}
    for layer in layers:
        if not layer.get('name','').startswith('原始深度_'):continue
        frames_el=layer.find('x:frames',NS)
        rebuilt=[]
        for fr in list(frames_el):
            i0=int(fr.get('index','0'));i1=i0+int(fr.get('duration','1'))
            pts=sorted({i0,i1}|{c for c in cuts if i0<c<i1})
            for a,b_end in zip(pts,pts[1:]):
                seg=copy.deepcopy(fr)
                seg.set('index',str(a))
                if b_end-a>1:seg.set('duration',str(b_end-a))
                elif 'duration' in seg.attrib:del seg.attrib['duration']
                bx=charge_blur(a)
                if bx is not None:
                    for inst in seg.findall('x:elements/x:DOMSymbolInstance',NS):
                        inst.set('symbolType','movie clip')
                        for attr in ('loop','firstFrame'):
                            if attr in inst.attrib:del inst.attrib[attr]
                        flts=inst.find('x:filters',NS)
                        if flts is None:flts=E.SubElement(inst,b.N+'filters')
                        else:flts.clear()
                        E.SubElement(flts,b.N+'BlurFilter',blurX=bx,blurY='0')
                rebuilt.append(seg)
        frames_el[:]=rebuilt
    layers.insert(1,n.make_sparse_layer('标准射击许可',charge_total,{0:{'duration':charge_len,'elements':[
        n.instance(holder,symbol_type='movie clip',name='射击许可标签')]}}))

    broken=copy.deepcopy(poses['破盾'])
    final_break=next(f for f in reversed(broken) if any(v['id']==578 for v in f.values()))
    fragments={k:v for k,v in final_break.items() if v['id']==578}
    if len(fragments)!=1:raise ValueError('Expected final broken-shield drawing without soldier parts')
    body('破盾碎片',[fragments],{0:{'script':'stop();'}})
    broken[-1]={k:v for k,v in broken[-1].items() if v['id'] not in (575,577,578)}
    body('破盾',broken,{0:{'script':'soldierPhaseToken=_parent.soldierPhaseToken;stop();'},10:{'script':'stop();'}})
    symbols[p+'动作/破盾'].find('x:timeline/x:DOMTimeline/x:layers',NS).insert(1,
        n.make_sparse_layer('仅碎盾贴图',11,{10:{'elements':[n.instance(p+'动作/破盾碎片',symbol_type='movie clip',name='盾碎片')]}}))
    for link in (b.LINKAGE,b.SHIELD_LINKAGE):
        root=symbols[p+link]
        layers=root.find('x:timeline/x:DOMTimeline/x:layers',NS)
        action=root.find('.//x:DOMLayer[@name="动作"]/x:frames',NS)
        action.find('x:DOMFrame[@index="19"]/x:elements/x:DOMSymbolInstance',NS).set('libraryItemName',p+'动作/跑步')
        for index,x,y in ((194,27.15,-66.6),(202,27.5,-67.6)):
            m=action.find('x:DOMFrame[@index="'+str(index)+'"]//x:Matrix',NS);m.set('tx',str(x));m.set('ty',str(y))
        action.append(n.frame(120,10,[n.instance(p+'动作/投掷手雷',matrix=(1,0,0,1,4.75,-74.55),symbol_type='movie clip',name='man')]))
        root.find('.//x:DOMLayer[@name="状态标签"]/x:frames',NS).append(n.frame(120,10,name='投掷手雷',label_type='name'))
        root.find('.//x:DOMLayer[@name="受击包围盒"]/x:frames',NS).append(n.frame(120,10,[
            n.instance(b.H['Symbol 19'],matrix=(3.2,0,0,5.2,-44,-132),symbol_type='movie clip',name='area')]))
        # Sparse-layer fillers already cover the gap: split them before adding.
        for layer_name in ('动作','状态标签','受击包围盒'):
            frames=root.find('.//x:DOMLayer[@name="'+layer_name+'"]/x:frames',NS)
            for frame in list(frames):
                i=int(frame.get('index'));end=i+int(frame.get('duration','1'))
                if i<120<end:frame.set('duration',str(120-i))
                elif i==120 and frame is not frames[-1] and len(frame.find('x:elements',NS))==0 and not frame.get('name'):frames.remove(frame)
            frames[:]=sorted(frames,key=lambda f:int(f.get('index')))


def install_elite(b,symbols):
    for link in b.elite.LINKAGES:
        root=symbols[b.PREFIX+link]
        inst=root.find('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame[@index="180"]/x:elements/x:DOMSymbolInstance',NS)
        inst.set('libraryItemName',b.PREFIX+'动作/盾冲射击')
