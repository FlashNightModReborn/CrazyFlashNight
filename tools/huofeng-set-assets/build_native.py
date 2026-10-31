"""Build a separate native XFL library candidate from the frozen R2 motion data.

No shared source writes, no Flash invocation, no edits to either art handoff.
Original vector anatomy replaces the existing PNG preview underlays. Native FX
timelines are sampled with the same frozen interpolator used by the R2 preview.
"""
from pathlib import Path
import json,copy,hashlib,importlib.util,sys,math,re
import xml.etree.ElementTree as E
from fit_torso_collar import fit_torso_collar
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
import argparse,zipfile
parser=argparse.ArgumentParser(description="Rebuild a separate Huofeng XFL candidate; never writes the installed library.")
parser.add_argument('--output',required=True,type=Path)
args=parser.parse_args()
REPO=HERE.parents[1]
OUT=args.output.resolve()
SOURCE=REPO/'flashswf/arts/new/Codex素材源稿/火凤套装'
if OUT.is_relative_to(REPO/'flashswf/arts/new/Codex专用素材'):
    raise SystemExit('Generate a separate candidate and review it before installation')
spec=json.loads((SOURCE/'inputs-manifest.json').read_text('utf8'))
archive=SOURCE/'frozen-inputs.zip'
assert hashlib.sha256(archive.read_bytes()).hexdigest()==spec['archiveSha256']
inputs=OUT/'.inputs';inputs.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive) as z:
    assert set(z.namelist())==set(spec['entries'])
    for name,expected in spec['entries'].items():
        target=(inputs/name).resolve()
        assert target.is_relative_to(inputs.resolve())
        content=z.read(name);assert hashlib.sha256(content).hexdigest()==expected
        target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists() or target.read_bytes()!=content:target.write_bytes(content)
FROZEN=inputs/'R2'
BASELIB=inputs/'R9/LIBRARY'
REFERENCE=inputs/'native-references'
LIB=OUT/'LIBRARY'
NS='http://ns.adobe.com/xfl/2008/'
N={'x':NS}
I=(1.,0.,0.,1.,0.,0.)
PREFIX='Codex/火凤套装/'
E.register_namespace('',NS)

def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);sys.modules[name]=m;spec.loader.exec_module(m);return m
V=load_module('hf_svg_native',REPO/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py')
P=load_module('hf_nv_sampler',FROZEN/'source/prepare_nirvana.py')
SNAP=json.loads((FROZEN/'source/snapshot.json').read_text('utf8'))
DATA=json.loads((FROZEN/'source/animation-data.json').read_text('utf8'))
symbols={};provenance={};warnings=[]
def tag(e):return e.tag.rsplit('}',1)[-1]
def node(t,a=None,parent=None):
    e=E.Element('{'+NS+'}'+t,{k:str(v) for k,v in (a or {}).items()})
    if parent is not None:parent.append(e)
    return e
def num(v):return f'{v:.9f}'.rstrip('0').rstrip('.') if abs(v)>1e-10 else '0'
def matrix(m,parent):node('Matrix',dict(zip(('a','b','c','d','tx','ty'),map(num,m))),node('matrix',parent=parent))
def mul(a,b):return V.mul(a,b)
def inv(m):
    a,b,c,d,x,y=m;z=a*d-b*c
    return (d/z,-b/z,-c/z,a/z,(c*y-d*x)/z,(b*x-a*y)/z)
def instance(name,m=I,instance_name=None,opacity=1):
    e=node('DOMSymbolInstance',{'libraryItemName':name,'symbolType':'graphic','loop':'single frame','firstFrame':0})
    if instance_name:e.set('name',instance_name);e.set('symbolType','movie clip');e.attrib.pop('loop',None);e.attrib.pop('firstFrame',None)
    matrix(m,e)
    if opacity!=1:node('Color',{'alphaMultiplier':num(opacity)},node('color',parent=e))
    return e
def script(frame,text):node('script',parent=node('Actionscript',parent=frame)).text=text
def layer(name,frames):
    l=node('DOMLayer',{'name':name});fs=node('frames',parent=l)
    for index,elements,code in frames:
        f=node('DOMFrame',{'index':index,'duration':1,'keyMode':9728},fs)
        if code:script(f,code)
        es=node('elements',parent=f)
        for e in elements:es.append(e)
    return l
def symbol(name,layers,linkage=None):
    r=node('DOMSymbolItem',{'name':name,'itemID':'78f00000-'+hashlib.sha256(name.encode()).hexdigest()[:8]})
    if linkage:r.set('linkageIdentifier',linkage);r.set('linkageExportForAS','true');r.set('linkageExportInFirstFrame','true')
    ls=node('layers',parent=node('DOMTimeline',{'name':name.rsplit('/',1)[-1]},node('timeline',parent=r)))
    for l in layers:ls.append(l)
    symbols[name]=r
    return name
def static(name,elements,linkage=None,code=None):return symbol(name,[layer('Artwork',[(0,elements,code)])],linkage)
def used_file(p):provenance[str(p)]=hashlib.sha256(p.read_bytes()).hexdigest()

# Native original female anatomy, identical geometry to the preview source.
# R9 body references preserve the original anatomy. Hair is imported separately.
basic={}
for field in ['上臂','左大腿','右大腿','身体','屁股','脸型']:
    src=BASELIB/f'HF8/Basic/{field}.xml';used_file(src)
    els=list(E.parse(src).find('.//x:elements',N))
    if field in ('身体','屁股'):
        colored=BASELIB/f'HF8/Skin/{field}/Art.xml';used_file(colored)
        candidates=list(E.parse(colored).find('.//x:elements',N))[:len(els)]
        def geometry(e):
            e=copy.deepcopy(e)
            for x in e.iter():x.attrib.pop('color',None);x.text=None;x.tail=None
            return E.tostring(e)
        assert all(geometry(a)==geometry(b) for a,b in zip(els,candidates)),'Changed anatomy geometry'
        els=candidates
    basic[field]=static(PREFIX+'原生底模/'+field,copy.deepcopy(els))

hair_source=REFERENCE/'flashswf/arts/things切割/LIBRARY/发型/发型-女式-咖啡色中长马尾.xml'
used_file(hair_source)
hair_elements=list(E.parse(hair_source).find('.//x:elements',N))
assert not any(tag(e)=='DOMSymbolInstance' for root0 in hair_elements for e in root0.iter())
basic['发型']=static(PREFIX+'预览默认发型',copy.deepcopy(hair_elements))

def appearance(field):
    name=PREFIX+'玩家外观/'+field
    fallback=[instance(basic[field],instance_name='基本款')]
    code='''stop();
var unit = _parent._parent._parent;
if (unit != undefined && _root.装备引用配置 != undefined) {
    var key = unit.%s;
    _root.装备引用配置.配置装扮(this, key, "装扮", "%s_引用");
    %s
}
'''%(field,field,'if (!key) 基本款._visible = false;' if field=='发型' else '')
    holder=static(name+'/holder',fallback,code=code)
    elements=[instance(holder,instance_name='holder')]
    if field=='脸型':
        mask=static(name+'/helmet',[],code='''stop();
var unit = _parent._parent._parent;
if (_root.装备引用配置 != undefined) _root.装备引用配置.配置装扮(this, unit.面具, "装扮3", "面具_引用");
''')
        elements.append(instance(mask,instance_name='helmet'))
    return static(name,elements)
face=appearance('脸型');hair=appearance('发型')

# Human selected R9 for this integration; its final visual acceptance is pending.
for part in ('Front','BackUpper','BackTail'):
    src=BASELIB/f'HF8/Hair/{part}.xml';used_file(src)
    original=E.parse(src).getroot();name=PREFIX+'R9长发/'+part
    original.set('name',name)
    original.set('itemID','78f90000-'+hashlib.sha256(name.encode()).hexdigest()[:8])
    # CS6's XFL reader expects frame actions before elements.
    for frame in original.findall('.//x:DOMFrame',N):
        code=frame.find('x:Actionscript',N)
        if code is not None:frame.remove(code);frame.insert(0,code)
    symbols[name]=original

class SvgWriter(V.Writer):
    def paint(self,parent,fill,a,m,alpha):
        match=re.fullmatch(r'url\(#([^)]*)\)',fill)
        g=self.grads.get(match[1]) if match else None
        if g is not None and tag(g)=='radialGradient' and g.get('fx') is not None:
            old=dict(g.attrib);cx=float(g.get('cx',0));cy=float(g.get('cy',0));r=float(g.get('r',1))
            assert float(g.get('fy',cy))==cy and float(g.get('fr',0))==0,'Unsupported radial focal direction'
            focal=(float(g.get('fx',cx))-cx)/r
            g.set('fx',str(cx));g.set('fy',str(cy))
            super().paint(parent,fill,a,m,alpha)
            for x in parent.iter():
                if tag(x)=='RadialGradient':x.set('focalPointRatio',num(focal))
            g.attrib.clear();g.attrib.update(old)
        else:super().paint(parent,fill,a,m,alpha)

def svg_art(path,name,underlay=None):
    used_file(path);writer=SvgWriter(path)
    if path.name=='huofeng-r14-refined-torso.svg':
        used_file(HERE/'fit_torso_collar.py')
        fit_torso_collar(writer.root,V)
    ids={e.get('id'):e for e in writer.root.iter() if e.get('id')};serial=[0]
    def walk(e,style=None,mat=I):
        a=V.style(e,style);m=mul(mat,V.transform(e.get('transform')));kind=tag(e)
        if a.get('display')=='none' or a.get('visibility')=='hidden':return []
        if kind in ('defs','title','desc','metadata','clipPath','linearGradient','radialGradient'):return []
        clip=e.get('clip-path')
        if clip:
            key=re.fullmatch(r'url\(#([^)]*)\)',clip)[1];cl=ids[key]
            clone=copy.deepcopy(e);clone.attrib.pop('clip-path',None)
            # The artwork and mask share their SVG local coordinate system.
            serial[0]+=1;sub=name+'/clip'+str(serial[0]);mask=[]
            for c in cl:mask.extend(walk(c,{'fill':'#FFFFFF'},I))
            masklayer=layer('Mask',[(0,mask,None)]);masklayer.set('layerType','mask')
            artlayer=layer('Masked artwork',[(0,walk(clone,style,I),None)]);artlayer.set('parentLayerIndex','0');artlayer.set('locked','true')
            symbol(sub,[masklayer,artlayer]);return [instance(sub,mat,instance_name='clip'+str(serial[0]))]
        if kind in ('g','svg'):
            out=[]
            for c in e:out.extend(walk(c,a,m))
            return out
        if kind=='image':
            assert underlay in basic,('Unexpected preview bitmap',path,underlay)
            # Original native vector registration is the same as the frozen preview.
            return [instance(basic[underlay],m)]
        if kind=='use':
            ref=e.get('href',e.get('{http://www.w3.org/1999/xlink}href'))
            assert ref and ref.startswith('#')
            return walk(ids[ref[1:]],a,m)
        assert kind in ('path','rect','circle','ellipse','polyline','polygon','line'),(path,kind)
        sh=writer.shape(e,a,m)
        return [sh] if sh is not None else []
    static(name,walk(writer.root))
    return name

# Reproduce R2 sequential asset IDs exactly (shared path reuses the first ID).
assets={};by_id={};fields={};asset_boxes={}
for item in list(SNAP['nodes'])+list(SNAP['bossParts'].values()):
    path=item['asset']
    if path not in assets:
        aid='a'+str(len(assets));assets[path]=aid
        if item.get('field')=='脸型':by_id[aid]=face
        elif item.get('field')=='发型':by_id[aid]=hair
        elif path.endswith('.png'):
            assert item['field'] in basic,(path,item)
            by_id[aid]=basic[item['field']]
        else:
            by_id[aid]=svg_art(FROZEN/path,PREFIX+'R2画稿/'+aid,item.get('field'))
            asset_boxes[aid]=list(map(float,E.parse(FROZEN/path).getroot().get('viewBox').split()))
    if item.get('id'):fields[item['id']]=by_id[assets[path]]

# Rebuild only the instance cache of the frozen native FX renderer. The replay
# order is identical to prepare_nirvana.py, so every nvi/nvs ID is checked below.
r=P.MotionRenderer(FROZEN/'source/nirvana-library','nv');r.instance_cache={}
d=P.MotionRenderer(FROZEN/'source/down-library','dn');d.instance_cache={}
root=P.translation(409.1,177.8)
for f in range(182):
    for li,ln,els,elapsed in reversed(r.layers_at(P.PREFIX+'转阶段动画',f)):
        for e in els:
            if tag(e)!='DOMSymbolInstance':continue
            if ln=='人物动画' and e.get('libraryItemName').endswith('/起身'):
                P.body_elements(r,e.get('libraryItemName'),r.childframe(e,elapsed),P.M(root,P.matrix(e)))
            else:P.instance_asset(r,e,elapsed)
for f in range(30):P.body_elements(d,'Symbol 556',f,root)
for f in range(32):r.render_symbol('Codex/火凤转阶段/蓄焰',f,'charge')
aura=P.PREFIX+'1.特效文件夹/03.赤橙色系/火焰与爆炸/余烬重生/火凤余烬'
for f in range(r.duration(aura)):r.render_symbol(aura,f,'aura')

frozen_cache={}
def freeze_symbol(renderer,name,frame):
    key=(renderer.prefix,name,int(frame)%renderer.duration(name))
    if key in frozen_cache:return frozen_cache[key]
    outname=PREFIX+'原生特效/'+renderer.prefix+'-'+hashlib.sha256(repr(key).encode()).hexdigest()[:16]
    frozen_cache[key]=outname
    layers=[]
    for li,ln,els,elapsed in renderer.layers_at(name,key[2]):
        outels=[]
        for e in els:
            e=copy.deepcopy(e)
            for parent in e.iter():
                for child in list(parent):
                    if tag(child)=='Actionscript':parent.remove(child)
            if tag(e)=='DOMSymbolInstance':
                child=freeze_symbol(renderer,e.get('libraryItemName'),renderer.childframe(e,elapsed))
                e.set('libraryItemName',child);e.set('symbolType','graphic');e.set('loop','single frame');e.set('firstFrame','0');e.attrib.pop('name',None)
            assert tag(e) not in ('DOMBitmapInstance','DOMVideoInstance'),(name,tag(e))
            outels.append(e)
        layers.append(layer(ln,[(0,outels,None)]))
    symbol(outname,layers)
    used_file(renderer.library/(name+'.xml'))
    return outname

instances={aid:(rr,sig) for rr in (r,d) for sig,aid in rr.instance_cache.items()}
top_symbols={aid:(rr,key) for rr in (r,d) for key,aid in rr.symbols.items()}
used={draw['aid'] for key in ['combo','run','skill','nirvana-ground','nirvana-full'] for frame in DATA['clips'][key]['frames'] for draw in frame['draws']}
for aid in sorted(used):
    if aid in by_id:continue
    if aid in instances:
        rr,sig=instances[aid];e=E.fromstring(sig)
        child=freeze_symbol(rr,e.get('libraryItemName'),int(e.get('firstFrame',0)))
        e.set('libraryItemName',child);e.set('symbolType','graphic');e.set('loop','single frame');e.set('firstFrame','0');e.attrib.pop('name',None)
        by_id[aid]=static(PREFIX+'R2特效实例/'+aid,[e])
    else:
        rr,key=top_symbols[aid];name,f,ct=key
        assert ct==P.X.CT_IDENTITY,('Top level color transform',aid)
        by_id[aid]=freeze_symbol(rr,name,f)

# Registration follows the actual player's container, not a guessed body scale.
player=E.parse(REFERENCE/'flashswf/arts/things0/LIBRARY/主角-男.xml')
containers=[x for x in player.findall('.//x:DOMSymbolInstance',N) if x.get('name')=='container']
container_matrix=P.matrix(containers[0]);normalize=inv(container_matrix)
used_file(REFERENCE/'flashswf/arts/things0/LIBRARY/主角-男.xml')

def sample_range(start,end,count):return [round(start+(end-start)*i/max(1,count-1)) for i in range(count)]
mapping={
 'combo':list(range(83))+sample_range(83,106,12),
 'run':sample_range(0,9,6)+sample_range(10,34,24)+sample_range(35,65,18),
 'skill':sample_range(0,16,12)+sample_range(17,72,48)+list(range(73,79))+sample_range(79,134,48)+sample_range(135,160,12),
 'nirvana-ground':list(range(30,122)),
 'nirvana-full':list(range(113))}
names={'combo':'五段普攻','run':'位移扫击','skill':'焰链回旋','nirvana-ground':'普通涅槃','nirvana-full':'完整涅槃'}
# Visible art and collision sample symbols are distinct. Alpha-zero fill keeps
# reliable native bounds without adding a visible debug overlay.
hitbox=svg_art(FROZEN/'source/boss-parts/Symbol 499.svg',PREFIX+'碰撞占位锤')
def area_symbol(name,w,h):
    sh=node('DOMShape');fill=node('FillStyle',{'index':1},node('fills',parent=sh));node('SolidColor',{'color':'#FFFFFF','alpha':0},fill)
    edges=f'!{num(-w*10)} {num(-h*10)}|{num(w*10)} {num(-h*10)}|{num(w*10)} {num(h*10)}|{num(-w*10)} {num(h*10)}|{num(-w*10)} {num(-h*10)}'
    node('Edge',{'fillStyle0':1,'edges':edges},node('edges',parent=sh));return static(name,[sh])
contact=area_symbol(PREFIX+'判定/接触',24,36)
blast1=area_symbol(PREFIX+'判定/普通涅槃',150,140)
blast2=area_symbol(PREFIX+'判定/完整涅槃',180,170)

def weapon(draw):return draw['part'].startswith(('Symbol ','authored-'))
def at(m,x,y):return (m[0]*x+m[2]*y+m[4],m[1]*x+m[3]*y+m[5])
# The boss turns its mace behind the torso in these three backswing poses.
# For the player chain, reflect only the visible weapon about the gripping wrist:
# the second/fourth/fifth strike must reach the opponent in the facing direction.
# Body anatomy, cadence and frozen R2 inputs remain unchanged.
FORWARD_POSES=((16,21),(46,49),(68,70))
def face_weapon(key,source_frame,wm,wx):
    if key=='combo' and any(first<=source_frame<=last for first,last in FORWARD_POSES):
        return mul((-1,0,0,1,2*wx,0),wm)
    return wm

# Preserve the approved R2/Boss-relative chain length and sweep effects.
# The previous 110-pixel clamp reduced normal/run/spin to 59%/30%/49%.
weapon_scales={key:1. for key in ('combo','run','skill')}

# Use the same native ground shadow and placement as the ordinary sword action.
shadow_source=REPO/'flashswf/arts/things0/LIBRARY/主角肢体素材/Symbol 3.xml'
used_file(shadow_source)
shadow=E.parse(shadow_source).getroot()
shadow_name=PREFIX+'落地影子'
shadow.set('name',shadow_name)
shadow.set('itemID','78f00000-'+hashlib.sha256(shadow_name.encode()).hexdigest()[:8])
shadow.find('x:timeline/x:DOMTimeline',N).set('name','落地影子')
symbols[shadow_name]=shadow

def shadow_layer(length):
    inst=instance(shadow_name,(1.37506103515625,0,0,0.559799194335938,-15.2,233.05),'hfShadow')
    node('script',parent=node('Actionscript',parent=inst)).text='onClipEvent(load){this._visible=(_root.是否阴影==true);}'
    result=layer('落地影子',[(0,[inst],None)])
    result.find('x:frames/x:DOMFrame',N).set('duration',str(length))
    return result

def native_fade(name,element):
    art=static(name+'/art',[element])
    # Cached alpha masks reproduce R2's 30..130 world-pixel ground fade.
    # The actual artwork bounds limit the bitmap, not the 4000-pixel SVG mask.
    return static(name,[instance(art,instance_name='art')],code='''stop();
// The child timeline must be placed before measuring its native bounds.
onEnterFrame = function() {
var bounds = this.art.getBounds(this);
if (!(bounds.xMax > bounds.xMin) || !(bounds.yMax > bounds.yMin)) return;
var fade = createEmptyMovieClip("fade", 10);
var gradient = new flash.geom.Matrix();
gradient.createGradientBox(1, 100, Math.PI / 2, 0, 30);
fade.beginGradientFill("linear", [0xFFFFFF, 0xFFFFFF], [100, 0], [0, 255], gradient);
fade.moveTo(bounds.xMin, bounds.yMin);
fade.lineTo(bounds.xMax, bounds.yMin);
fade.lineTo(bounds.xMax, Math.min(130, bounds.yMax));
fade.lineTo(bounds.xMin, Math.min(130, bounds.yMax));
fade.endFill();
this.art.cacheAsBitmap = true;
fade.cacheAsBitmap = true;
this.art.setMask(fade);
delete this.onEnterFrame;
};
''')

# Native unarmed carry poses, expressed relative to the same registered torso
# and hip geometry used by R2. Do not inherit the Boss's missing player slots.
# Read only the first native pose; each authored frame supplies its own anatomy.
carry_lib=REPO/'flashswf/arts/things0/LIBRARY'
carry_donor=carry_lib/'容器/空手攻击容器/平A/空手攻击容器-1连招.xml'
used_file(carry_donor)
carry_pose={}
for donor_layer in E.parse(carry_donor).findall('.//x:DOMLayer',N):
    first=donor_layer.find('x:frames/x:DOMFrame',N)
    if first is None or first.get('index')!='0':continue
    for el in first.findall('x:elements/x:DOMSymbolInstance',N):
        carry_pose[el.get('libraryItemName')]=P.matrix(el)
carry_specs=[('长枪','torso','身体','hfCarryRifle'),('刀','torso','身体','hfCarryBlade'),
             ('手枪2','hip','屁股','hfCarryPistol2'),('手枪','hip','屁股','hfCarryPistol')]
carry_symbols={};carry_relative={}
for field,part,bone,handle in carry_specs:
    carry_relative[field]=mul(inv(carry_pose['主角肢体素材/'+bone]),carry_pose['主角肢体素材/'+field])
    source=carry_lib/('主角肢体素材/'+field+'.xml');used_file(source)
    original=E.parse(source).find('.//x:elements/x:DOMSymbolInstance',N)
    name=PREFIX+'背负武器/'+field
    # Same two-level wrapper and reference contract as the native player. An
    # empty slot stays empty; no default G36/M9/blade leaks into the display.
    holder=static(name+'/holder',[])
    mount=instance(holder,P.matrix(original),original.get('name'))
    # Empty clips may be coalesced by CS6. Keep slot-specific initialization on
    # the placement's load event, exactly like the native player weapon holder.
    node('script',parent=node('Actionscript',parent=mount)).text='''onClipEvent (load) {
var unit = _parent._parent._parent;
if (unit != undefined && _root.装备引用配置 != undefined) {
    _root.装备引用配置.配置装扮(this, unit.%s_装扮, "装扮", "%s_引用");
}
}
'''%(field,field)
    carry_symbols[field]=static(name,[mount])

frame_manifest={}
for key,indexes in mapping.items():
    frames=[];collision=[];last_ball=None;frame_manifest[key]=[]
    for fi,srcindex in enumerate(indexes):
        source=DATA['clips'][key]['frames'][srcindex];rx=source.get('rootX',0) if key=='run' else 0
        world=(1,0,0,1,-rx,0);out=[];weapon_draws=[]
        wx,wy=source['wrist'];wx-=rx
        scale=weapon_scales.get(key,1)
        shortened=(scale,0,0,scale,wx*(1-scale),wy*(1-scale))
        anatomy={d['part']:d for d in source['draws'] if d['part'] in ('torso','hip')}
        carry_draws={}
        for field,part,bone,handle in carry_specs:
            anchor=anatomy[part]
            assert not anchor.get('mask'),'Carry anchor must be the living body, not the fading corpse'
            pose=mul(normalize,mul(world,mul(anchor['matrix'],carry_relative[field])))
            carry_draws[field]=instance(carry_symbols[field],pose,handle,anchor.get('opacity',1))
        for draw_index,draw in enumerate(source['draws']):
            # Native back-to-front relations: back weapons behind the torso,
            # far pistol behind the waist, near pistol before the near arm.
            if draw['part']=='arm-far-under':out.extend([carry_draws['长枪'],carry_draws['刀']])
            if draw['part']=='torso':out.append(carry_draws['手枪2'])
            if draw['part']=='arm-near-under':out.append(carry_draws['手枪'])
            wm=mul(world,draw['matrix'])
            if weapon(draw) and key in weapon_scales:
                wm=face_weapon(key,srcindex+1,wm,wx)
                sm=mul(shortened,wm)
                if draw['part'] in ('Symbol 499','authored-ball'):sm=(*wm[:4],*sm[4:])
                wm=sm;weapon_draws.append((draw,wm))
            m=mul(normalize,wm)
            instance_name={'face':'hfFace','hair':'hfHair','torso':'hfTorso','hip':'hfHip'}.get(draw['part'])
            if draw.get('mask'):
                fade=native_fade(PREFIX+'地面渐隐/'+key+'-'+str(fi)+'-'+str(draw_index),instance(by_id[draw['aid']],wm,opacity=draw.get('opacity',1)))
                out.append(instance(fade,normalize,instance_name='fxFade'+str(draw_index)))
            else:out.append(instance(by_id[draw['aid']],m,instance_name,draw.get('opacity',1)))
        balls=[(d,m) for d,m in weapon_draws if d['part'] in ('Symbol 499','authored-ball')]
        ball=list(balls[-1][1][4:]) if balls else None
        chains=[list(m[4:]) for d,m in weapon_draws if d['part'] in ('Symbol 496','authored-chain')]
        # Contact nodes follow visible chain tail and head; never clamp an
        # invisible hitbox away from the rendered weapon.
        if ball is not None and chains:
            chains.sort(key=lambda p:(p[0]-wx)**2+(p[1]-wy)**2)
            points=[chains[int((len(chains)-1)*.35)],chains[int((len(chains)-1)*.72)],ball]
        elif weapon_draws:
            sweep=next(((d,m) for d,m in weapon_draws if d['part'] in ('Symbol 512','Symbol 515','Symbol 517')),None)
            if sweep:
                d,m=sweep;x,y,w,h=asset_boxes[d['aid']]
                points=[list(at(m,x+w*.5,y+h*.12)),list(at(m,x+w*.86,y+h*.5)),list(at(m,x+w*.5,y+h*.88))]
            else:points=[[wx,wy]]*3
        else:points=[[wx,wy]]*3
        # Three contiguous bands cover the rendered chain/sweep, not three
        # tiny isolated dots. They still share ONE hit receipt per pulse.
        if ball is not None and chains:
            path=[[wx,wy]]+chains+[ball]
            boxes=[]
            for group in range(3):
                first=group*(len(path)-1)//3;last=(group+1)*(len(path)-1)//3
                chunk=path[first:last+1]
                xs=[p[0] for p in chunk];ys=[p[1] for p in chunk]
                boxes.append([min(xs)-14,min(ys)-18,max(xs)+14,max(ys)+18])
        elif weapon_draws:
            corners=[]
            for draw,wm in weapon_draws:
                x,y,w,h=asset_boxes[draw['aid']]
                corners.extend(at(wm,px,py) for px,py in ((x,y),(x+w,y),(x+w,y+h),(x,y+h)))
            left=min(p[0] for p in corners);right=max(p[0] for p in corners)
            top=min(p[1] for p in corners);bottom=max(p[1] for p in corners)
            boxes=[[left+(right-left)*j/3,top,left+(right-left)*(j+1)/3,bottom] for j in range(3)]
        else:boxes=[[p[0]-12,p[1]-18,p[0]+12,p[1]+18] for p in points]
        hit=[]
        for j,(left,top,right,bottom) in enumerate(boxes,1):
            hit.append(instance(contact,mul(normalize,((right-left)/24,0,0,(bottom-top)/36,(left+right)/2,(top+bottom)/2)),f'hfHit{j}'))
        # The visible flame follows the head; it must not be displaced by a
        # contact band's centre changing when the sweep widens.
        hit.append(instance(contact,mul(normalize,(0.01,0,0,0.01,*(ball or points[-1]))),'hfTip'))
        if key.startswith('nirvana'):
            hit.append(instance(blast1 if key.endswith('ground') else blast2,mul(normalize,(1,0,0,1,0,-55)),'hfBlast'))
        frames.append((fi,list(reversed(out)) if False else out,'stop();' if fi==0 else None));collision.append((fi,hit,None))
        frame_manifest[key].append({'runtimeFrame':fi+1,'sourceFrame':srcindex+1,'hitCenter':ball,'samples':points,'contactBounds':boxes})
        assert all(sum(e.get('name')==handle for e in out)==1 for field,part,bone,handle in carry_specs),'Missing/duplicate carry node'
    symbol(PREFIX+'动作/'+names[key],[layer('判定',collision),layer('R2 原生重建',frames),shadow_layer(len(indexes))],'火凤套装_'+names[key])

# Wardrobe exports use the same R2 part geometry as the action study.
field_parts={'身体':'torso','上臂':'arm-near','左下臂':'forearm-far','右下臂':'forearm-near','屁股':'hip',
             '左大腿':'thigh-far','右大腿':'thigh-near','小腿':'shin-near','左手':'hand-far','右手':'hand-near','脚':'foot-near'}
for field,part in field_parts.items():
    if field in ('身体','上臂','左下臂','右下臂'):link='火凤上装'+field
    elif field in ('屁股','左大腿','右大腿','小腿'):link='火凤下装'+field
    elif field in ('左手','右手'):link='火凤手甲'+field
    else:link='火凤战靴'
    elements=[]
    if part+'-under' in fields:
        front=next(x for x in SNAP['nodes'] if x['id']==part)
        under=next(x for x in SNAP['nodes'] if x['id']==part+'-under')
        elements.append(instance(fields[part+'-under'],mul(inv(front['matrix']),under['matrix'])))
    elements.append(instance(fields[part]))
    for gender in ('男变装-','女变装-'):
        static(PREFIX+'装扮/'+gender+link,copy.deepcopy(elements),gender+link)
static(PREFIX+'装扮/后披摆',[instance(fields['rear-skirt'])],'火凤套装_后披摆')

OUT.mkdir(parents=True,exist_ok=True)
exec(compile((HERE/'build_cold.py').read_text('utf8'),str(HERE/'build_cold.py'),'exec'))

# A Flash library cannot have both a symbol and a folder at the same name.
# Filesystem-valid "Face.xml" + "Face/holder.xml" silently loses child content
# in CS6. Resolve only generated names before materializing this candidate.
folders={name[:i] for name in symbols for i,c in enumerate(name) if c=='/'}
renamed={name:name+'__元件' for name in symbols if name in folders}
if renamed:
    revised={}
    for name,r0 in symbols.items():
        actual=renamed.get(name,name);r0.set('name',actual)
        r0.find('x:timeline/x:DOMTimeline',N).set('name',actual.rsplit('/',1)[-1])
        for el in r0.iter():
            if tag(el)=='DOMSymbolInstance':
                ref=el.get('libraryItemName');el.set('libraryItemName',renamed.get(ref,ref))
        revised[actual]=r0
    symbols=revised
assert not ({name[:i] for name in symbols for i,c in enumerate(name) if c=='/'} & set(symbols))

LIB.mkdir(parents=True,exist_ok=True)
for name,r0 in symbols.items():
    if r0.get('linkageIdentifier'):
        identifier=r0.attrib.pop('linkageIdentifier')
        # Canonical linkage scanner reads export flags before the identifier.
        r0.set('linkageIdentifier',identifier)
    p=LIB/(name+'.xml');p.parent.mkdir(parents=True,exist_ok=True);E.indent(r0,space='  ');E.ElementTree(r0).write(p,encoding='utf-8',xml_declaration=True)
manifest={'schema':'cf7.huofeng.native-candidate.v1','sourceAnimationArchiveSha256':'377ba2dde6b34208b814a45e2ee80d47c27681b71254fe467026369888a4f6d1',
    'carryRelativeMatrices':carry_relative,'carryPoseSource':str(carry_donor.relative_to(REPO)),
    'playerWeaponFacingRevision':'R3-wrist-reflection','forwardWeaponSourceFrames':FORWARD_POSES,
    'symbols':len(symbols),'symbolNames':sorted(symbols),'containerMatrix':container_matrix,'weaponScales':weapon_scales,'frameCounts':{k:len(v) for k,v in mapping.items()},'warnings':warnings,
    'links':{r.get('linkageIdentifier'):name for name,r in symbols.items() if r.get('linkageIdentifier')},'folderSymbolRenames':renamed,'sourceHashes':provenance}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),'utf8')
(OUT/'frame-map.json').write_text(json.dumps(frame_manifest,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({k:manifest[k] for k in ('symbols','containerMatrix','frameCounts','warnings')},ensure_ascii=False))
