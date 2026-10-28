"""CF6 R9 shared tactics, smoke visuals and instructor art projection."""
from pathlib import Path
import copy
import json
import hashlib
from lxml import etree as E
import elite

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT/'flashswf/arts/new/Codex素材源稿/CF6教官-R9'
SMOKE_SOURCE = ROOT/'flashswf/arts/things5/LIBRARY'
PREFIX = 'Codex/教官/'
LINKAGES = ('敌人-CF6特种教官', '敌人-CF6持盾特种教官')
NS = {'x':'http://ns.adobe.com/xfl/2008/'}


def smoke_sources():
    return [SMOKE_SOURCE/'翅虎/烟雾.xml', *sorted((SMOKE_SOURCE/'翅虎/烟雾素材').glob('*.xml'))]


def input_paths():
    return [Path(__file__), HERE/'TacticalAI.as', HERE/'tactical-profiles.json',
            *sorted(p for p in SOURCE.rglob('*') if p.is_file()), *smoke_sources()]


def load_profiles():
    data=json.loads((HERE/'tactical-profiles.json').read_text(encoding='utf-8'))
    for role, values in data['roles'].items():
        if set(values)!=set(data['bounds']): raise ValueError('Incomplete tactical role '+role)
        for key,value in values.items():
            low,high=data['bounds'][key]
            if not isinstance(value,(int,float)) or not low<=value<=high: raise ValueError('Invalid tactical default '+key)
    return data


def remap(root, mapping):
    root=copy.deepcopy(root)
    old=root.get('name');new=mapping.get(old,old)
    root.set('name',new)
    if new!=old:
        # CS6 uses itemID as library identity, including for graphic masks.
        # A renamed clone must never share it with the soldier source symbol.
        root.set('itemID','6af10000-'+hashlib.sha256(new.encode('utf-8')).hexdigest()[:8])
    root.find('x:timeline/x:DOMTimeline',NS).set('name',new.rsplit('/',1)[-1])
    for inst in root.findall('.//x:DOMSymbolInstance',NS):
        value=inst.get('libraryItemName')
        if value in mapping: inst.set('libraryItemName',mapping[value])
    return root


def add_smoke(b,symbols):
    mapping={}
    sources={}
    for path in smoke_sources():
        root=E.parse(str(path),b.PARSER).getroot()
        name=root.get('name');sources[name]=root
        mapping[name]=b.PREFIX+'烟雾/'+name.rsplit('/',1)[-1]
    for name,root in sources.items():
        projected=remap(root,mapping)
        for attr in ('itemID','linkageIdentifier','linkageExportForAS','linkageExportForRS','linkageImportForRS','linkageURL'):
            projected.attrib.pop(attr,None)
        if name=='翅虎/烟雾':
            projected.set('linkageIdentifier','CF6战术烟雾')
            projected.set('linkageExportForAS','true');projected.set('linkageExportInFirstFrame','true')
            for action in projected.findall('.//x:Actionscript',NS):action.getparent().remove(action)
            layers=projected.find('x:timeline/x:DOMTimeline/x:layers',NS)
            layers.insert(0,b.native.make_sparse_layer('有界烟幕生命周期',26,{0:{'script':'''stop();_xscale=70;_yscale=70;smokeAge=0;fadeAge=0;
onEnterFrame=function():Void {
    if(_root.暂停)return;
    this.smokeAge++;
    var live:Boolean=this.sourceUnit.hp>0 && this.sourceUnit.soldierAttackOwner===this.sourceOwner
        && this.sourceOwner.active && (this.sourceOwner.reload
            || this.sourceOwner.kind=="slide" && this.sourceOwner.age<this.coverSlideFrames) && this.smokeAge<150;
    if(!live)this.fadeAge++;
    this._alpha=Math.max(0,100-this.fadeAge*8);
    this.gotoAndStop(Math.min(21,2+Math.floor(this.smokeAge/2)));
    if(this.fadeAge>12 || this.smokeAge>165)this.removeMovieClip();
};'''}}))
        symbols[projected.get('name')]=projected


def replace_reload_art(b,symbols,parts):
    # Hide the generic reload behind smoke in the slide's own crouched pose.
    # Keep all three real reload transactions and their gate/commit frames.
    name=b.elite.PREFIX+'动作/CF6战术长枪'
    root=symbols[name];layers=root.find('x:timeline/x:DOMTimeline/x:layers',NS)
    for layer in list(layers):
        if not layer.get('name','').startswith('CF6分件_'):continue
        frames=layer.find('x:frames',NS)
        for frame in list(frames):
            start=int(frame.get('index'));end=start+int(frame.get('duration','1'))
            if start>=260:frames.remove(frame)
            elif end>260:frame.set('duration',str(260-start))
    motion=b.elite.retarget_frames()
    poses=[]
    for index in range(105):
        offset=index%35
        # The final six reload frames ARE the slide's windup. Its first live
        # attack frame is the next authored pose, so there is no pose reset.
        pose=copy.deepcopy(motion[205+max(0,offset-29)])
        if offset<32:
            pose={k:v for k,v in pose.items() if v['id'] not in (492,506,'primaryPistol','reloadPistol')}
        poses.append(pose)
    for layer in b.depth_layers(poses,parts):
        layer.set('name','烟雾换弹_'+layer.get('name'))
        for frame in layer.findall('x:frames/x:DOMFrame',NS):frame.set('index',str(int(frame.get('index'))+260))
        layer.find('x:frames',NS).insert(0,b.native.frame(0,260))
        layers.append(layer)


def install(b,symbols,parts):
    data=load_profiles()
    source=('var cf6TacticalDefaults:Object='+elite.as2_literal(data['roles'])+';\n'
            +'var cf6TacticalLimits:Object='+elite.as2_literal(data['bounds'])+';\n'
            +(HERE/'TacticalAI.as').read_text(encoding='utf-8-sig'))
    for link in (b.LINKAGE,b.SHIELD_LINKAGE,*elite.LINKAGES):
        root=symbols[b.PREFIX+link]
        script=root.find('.//x:DOMLayer[@name="初始化与消失"]//x:script',NS)
        script.text=E.CDATA(script.text.replace('soldierInitializePhase();',source+'\nsoldierInstallTactics();soldierInitializePhase();',1))
    replace_reload_art(b,symbols,parts)
    add_smoke(b,symbols)
    origin=json.loads((SOURCE/'archive-origin.json').read_text(encoding='utf-8'))
    for row in origin['members']:
        if hashlib.sha256((SOURCE/row['path']).read_bytes()).hexdigest()!=row['sha256']:
            raise ValueError('Frozen instructor art changed: '+row['path'])
    # Clone the entire anatomical dependency tree. Runtime weapon mounts and CF7
    # shared helpers remain shared; instructor drawings never replace the soldiers.
    mapping={k:PREFIX+k[len(b.PREFIX):] for k in symbols if k.startswith(b.PREFIX)
             and '/CF7/' not in k and '/烟雾/' not in k}
    for old,new in zip(elite.LINKAGES,LINKAGES):mapping[b.PREFIX+old]=PREFIX+new
    for name in (b.PREFIX+b.LINKAGE,b.PREFIX+b.SHIELD_LINKAGE):mapping.pop(name,None)
    for name in list(mapping):
        projected=remap(symbols[name],mapping)
        if name in (b.PREFIX+elite.LINKAGES[0],b.PREFIX+elite.LINKAGES[1]):
            new_link=LINKAGES[elite.LINKAGES.index(name[len(b.PREFIX):])]
            projected.set('linkageIdentifier',new_link)
            script=projected.find('.//x:DOMLayer[@name="初始化与消失"]//x:script',NS)
            script.text=E.CDATA('soldierIsInstructor=true;\n'+script.text)
            # Independent native poses retain the ordinary controller and its
            # recoil/reload labels. Do not park a charge timeline for cover fire.
            original=symbols[b.PREFIX+b.LINKAGE]
            original_layers={layer.get('name'):layer for layer in original.find('x:timeline/x:DOMTimeline/x:layers',NS)}
            for layer in projected.find('x:timeline/x:DOMTimeline/x:layers',NS):
                lname=layer.get('name');frames=layer.find('x:frames',NS)
                if lname not in ('状态标签','动作'):continue
                # Use unused stopped root frames inside the live driver range.
                # This keeps the threat subscription and shadow alive on entry.
                for index,source_index,label in ((211,41,'教官阵地攻击'),(212,180,'教官持盾阵地攻击')):
                    covering=next(f for f in frames if int(f.get('index'))<=index<int(f.get('index'))+int(f.get('duration','1')))
                    end=int(covering.get('index'))+int(covering.get('duration','1'))
                    if int(covering.get('index'))==index:frames.remove(covering)
                    else:covering.set('duration',str(index-int(covering.get('index'))))
                    if lname=='状态标签':
                        frame=b.native.frame(index,name=label,label_type='name')
                    else:
                        src=next(f for f in original_layers[lname].findall('x:frames/x:DOMFrame',NS)
                                 if int(f.get('index'))<=source_index<int(f.get('index'))+int(f.get('duration','1')))
                        frame=copy.deepcopy(src);frame.set('index',str(index));frame.set('duration','1')
                        frame.attrib.pop('name',None);frame.attrib.pop('labelType',None)
                        for inst in frame.findall('.//x:DOMSymbolInstance',NS):
                            old=inst.get('libraryItemName');inst.set('libraryItemName',mapping.get(old,old))
                    frame.set('duration',str(end-index));frames.append(frame)
                    frames[:]=sorted(frames,key=lambda f:int(f.get('index')))
        else:
            for attr in ('linkageIdentifier','linkageExportForAS','linkageExportForRS','linkageImportForRS','linkageURL'):
                projected.attrib.pop(attr,None)
        symbols[projected.get('name')]=projected
    # Both master parts and native atlas poses are provided by the artist.
    for folder in ('parts','variants'):
        for path in sorted((SOURCE/folder).glob('*.svg')):
            cid=int(path.stem);name=PREFIX+'分件/'+str(cid)
            converted,_=(b.holster.build(path,name,b.native,b.vector) if cid==489
                else b.vector.NativePart(path,name,(0,0)).build())
            for key,root in converted.items():symbols[key]=remap(root,mapping)
    # Distinct folders and itemIDs alone are insufficient for these cloned
    # timelines: CS6 merged their bodies into the instructor's black drawings.
    # Isolate the internal leaf names as well; keep the six public linkages stable.
    actor_names={PREFIX+link for link in LINKAGES}
    isolated={name:name.rsplit('/',1)[0]+'/教官_'+name.rsplit('/',1)[1]
              for name in symbols if name.startswith(PREFIX) and name not in actor_names}
    for name in list(isolated):
        projected=remap(symbols.pop(name),isolated)
        symbols[projected.get('name')]=projected
    for name in actor_names:symbols[name]=remap(symbols[name],isolated)
    return {'linkages':list(LINKAGES),'artSource':SOURCE.relative_to(ROOT).as_posix(),
            'strategy':'shared actions with instructor selection and bounded commitment'}
