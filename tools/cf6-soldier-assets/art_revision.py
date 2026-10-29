"""Frozen Animate 24 poses, baked with native parenting and tween evaluation."""
from pathlib import Path
import copy
import hashlib
import json
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'flashswf/arts/new/Codex素材源稿/CF6特种兵-美术R8'
NS = {'x':'http://ns.adobe.com/xfl/2008/'}


def input_paths():
    return [Path(__file__), Path(__file__).with_name('SoldierRoles.as'),
            *sorted(p for p in SOURCE.rglob('*') if p.is_file())]


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
    def body(name,frames,scripts=None):
        symbols[p+'动作/'+name]=b.make_body(p+'动作/'+name,frames,parts,scripts)
    def art_only(name,frames):
        layers=symbols[p+'动作/'+name].find('x:timeline/x:DOMTimeline/x:layers',NS)
        for layer in list(layers):
            if layer.get('name','').startswith('原始深度_'):layers.remove(layer)
        layers.extend(b.depth_layers(frames,parts))
    for name in ('站立','行走','匕首刺击','持盾站立','持盾行走','被击'):
        art_only(name,poses[name])
    body('跑步',poses['跑步'])
    body('被投',poses['被投'],{13:{'script':'stop();'}})
    body('击飞',poses['击飞'],{0:{'name':'空手','label_type':'name'},28:{'script':'stop();'}})
    body('倒地恢复',poses['倒地恢复'],{8:{'script':'_parent.死亡检测();'},77:{'script':'_parent.动画完毕();'}})
    # The last death branch lands and stays down. Never play the get-up segment.
    death=copy.deepcopy(poses['死亡'][:104])
    fall=copy.deepcopy(poses['倒地恢复'][:14])+[copy.deepcopy(poses['倒地恢复'][13]) for _ in range(21)]
    for pose in fall:
        for row in pose.values():row['matrix'][4]-=2.5;row['matrix'][5]+=.9
    death.extend(fall)
    art_only('死亡',death)
    for name in ('长枪点射与装填','持盾点射与装填'):
        recoil=sample(poses[name][:14],14)
        art_only(name,recoil+[copy.deepcopy(recoil[0]) for _ in range(35)])
    # Both hit variants use the authored cover-and-return movement, compressed
    # to two 20-frame reactions rather than freezing on its first few keys.
    cover=sample(poses['持盾被击'],20)
    body('持盾被击',cover+copy.deepcopy(cover),{0:{'name':'a0','label_type':'name'},
        20:{'name':'a1','label_type':'name'},19:{'script':'_parent.动画完毕();'},39:{'script':'_parent.动画完毕();'}})

    # Preserve the previous shield stab as one branch; new art is a shield bash.
    stab=old['573'];bash=sample(poses['持盾匕首刺击'],34)
    center=-135/2-b.OFFSETS[517][1]-b.GROUND_SHIFT
    def hit(index):
        return {index:{'elements':[n.instance(b.H['Symbol 195'],matrix=(101/25,0,0,135/25,10.3,center),
            symbol_type='movie clip',name='攻击点',alpha_mult=0,
            script='onClipEvent(load){_parent._parent.soldierMeleeHit(_parent,this);}') ]}}
    lifecycle={0:{'script':'_parent.soldierBeginMelee(this);'},
        33:{'script':'_parent.soldierFinishAttack(this);'},
        34:{'name':'挥盾','label_type':'name'},67:{'script':'_parent.soldierFinishAttack(this);'}}
    symbols[p+'动作/持盾匕首刺击']=n.symbol(p+'动作/持盾匕首刺击',[
        n.make_sparse_layer('攻击生命周期',68,lifecycle),
        n.make_sparse_layer('真实近战判定',68,{**hit(13),**hit(49)}),
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
    charge=(sample(poses['持盾点射与装填'][27:47],10)+
            copy.deepcopy(poses['持盾点射与装填'][47:71])+
            sample(poses['持盾点射与装填'][71:],12))
    charge.extend([copy.deepcopy(poses['持盾点射与装填'][0]) for _ in range(35)])
    charge_scripts={0:{'script':'stop();_parent.soldierBeginCharge(this);'},
        46:{'name':'换弹匣','label_type':'name','script':'_parent.soldierReloadStart(this);'},
        66:{'script':'_root.主角函数.换弹门禁(this);'},
        78:{'script':'if(_parent.soldierCanAct(this))换弹匣();'},
        80:{'script':'_parent.soldierReloadEnd(this);'}}
    body('盾冲射击',charge,charge_scripts)
    layers=symbols[p+'动作/盾冲射击'].find('x:timeline/x:DOMTimeline/x:layers',NS)
    layers.insert(1,n.make_sparse_layer('标准射击许可',81,{0:{'duration':46,'elements':[
        n.instance(p+'武器/长枪挂点',symbol_type='movie clip',name='射击许可标签')]}}))

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
