"""Player shield-rush art: shared 15-frame gun/shield, dressed player rig.

The R23 approved occlusion sequence is archived as native SVGs, without review
boards. Runtime limbs remain ordinary dressup holders; no armor is baked into
the action. Only this library is written, never the two civilian NPC maps.
"""
import argparse, copy, hashlib, json, math
from functools import lru_cache
from pathlib import Path
from lxml import etree as E
import build as b

SOURCE = b.ROOT / 'flashswf/arts/new/Codex素材源稿/重装特勤-盾冲'
PREFIX = b.PREFIX + '战技/'
LINKAGE = '战技容器-特勤盾冲'
RUSH_START, RUSH_COUNT, BRAKE_START, CLOSE_START = 19, 16, 35, 41
BASE_COUNT, BRAKE_COUNT = 56, 6
BRAKE_BANK_START = BASE_COUNT
COUNT = BASE_COUNT + RUSH_COUNT * BRAKE_COUNT
STRIDE_STEP = 12
CONTAINER = (.277084350585938, 0, 0, .276901245117188, 3.4, -62.35)
SVG = 'http://www.w3.org/2000/svg'


def archive(workspace):
    SOURCE.mkdir(parents=True, exist_ok=True)
    samples = [round(i * 60 / 14) for i in range(15)]
    files = []
    for face, folder in [('内侧', 'motion-rear'), ('外侧', 'motion')]:
        for i, sample in enumerate(samples):
            src = workspace / 'outputs/former-sheriff-r23' / folder / ('frame-%02d.svg' % sample)
            root = E.parse(str(src)).getroot()
            weapon = next(e for e in root.iter() if e.get('id') == 'weapon')
            art = E.Element('{%s}svg' % SVG, nsmap={None: SVG}, width='320', height='530', viewBox='-160 -16 320 530')
            for child in weapon:
                art.append(copy.deepcopy(child))
            filename = '%s-%02d.svg' % (face, i)
            data = E.tostring(art, encoding='utf8')
            (SOURCE / filename).write_bytes(data)
            files.append(dict(file=filename, sha256=hashlib.sha256(data).hexdigest(), sourceFrame=sample, face=face, frame=i))
    manifest = json.loads((b.ROOT/'launcher/web/assets/dressup/manifest.json').read_text('utf8'))
    pose = manifest['rigs']['battle']['genders']['男']['states']['长枪站立']
    # Freeze the established registrations, not the current web raster cache.
    holders = [{k: e[k] for k in ['field', 'matrix', 'hostSymbol', 'path']} for e in pose['holders']]
    (SOURCE/'pose-source.json').write_text(json.dumps(dict(source=manifest['rigs']['battle']['source'], state='长枪站立', holders=holders), ensure_ascii=False, indent=2)+'\n', 'utf8')
    (SOURCE/'manifest.json').write_text(json.dumps(dict(source='approved R23 exterior/interior occlusion and fixed grip; R26 dressup registrations', frames=15, samples=samples, files=files), ensure_ascii=False, indent=2)+'\n', 'utf8')


def inverse(m):
    a,c0,c,d,x,y = m
    det=a*d-c0*c
    return d/det,-c0/det,-c/det,a/det,(c*y-d*x)/det,(c0*x-a*y)/det


def vals(m):
    return tuple(m.get(k,v) for k,v in zip(['a','b','c','d','tx','ty'],b.I))


def smooth(t):
    t=max(0,min(1,t));return t*t*(3-2*t)


def mix(a,c,t):
    return a+(c-a)*t


def tween(a,c,t):
    # Interpolate rotation and positive lengths, never flatten a limb to zero.
    if t <= 0:return a
    if t >= 1:return c
    aa=math.atan2(a[1],a[0]);cc=math.atan2(c[1],c[0])
    delta=(cc-aa+math.pi)%(2*math.pi)-math.pi
    angle=aa+delta*t
    sx=mix(math.hypot(a[0],a[1]),math.hypot(c[0],c[1]),t)
    sy=mix(math.hypot(a[2],a[3]),math.hypot(c[2],c[3]),t)
    return (sx*math.cos(angle),sx*math.sin(angle),-sy*math.sin(angle),sy*math.cos(angle),mix(a[4],c[4],t),mix(a[5],c[5],t))


def point(m,p):return b.writer.point(p,m)


def bone(a,z):
    # Forearm/upper-arm anatomical endpoints are (0,-47) and (0,47).
    dx,dy=z[0]-a[0],z[1]-a[1]
    return dy/94,-dx/94,dx/94,dy/94,(a[0]+z[0])/2,(a[1]+z[1])/2


def elbow(a,z,side=1):
    dx,dy=z[0]-a[0],z[1]-a[1];d=max(.001,math.hypot(dx,dy));length=max(22.6,d/2+.1)
    h=math.sqrt(max(0,length*length-d*d/4))
    return (a[0]+z[0])/2-side*dy*h/d,(a[1]+z[1])/2+side*dx*h/d


def lamp_matrix(frame):
    # Original lens: (356.9,41) -> the R23 vertical gun at (31,368.9).
    # A sliding bracket travels outside the folding stack and docks below the
    # window. Counter-rotation keeps the light facing the lane while unfolding.
    t=smooth(frame/14)
    angle=math.pi/2*(1-t)
    x=mix(31,50,t)+24*math.sin(math.pi*t)
    y=mix(368.9,108,t)
    return math.cos(angle),math.sin(angle),-math.sin(angle),math.cos(angle),x,y


def unlit_motion(face,frame):
    root=E.parse(str(SOURCE/('%s-%02d.svg'%(face,frame)))).getroot()
    for el in list(root.iter()):
        name=el.get('id','')
        if any(name.endswith(suffix) for suffix in ['-flashlight','-lamp-clamp-band','-forward-lamp-mount','-gun-part-lamp']):
            el.getparent().remove(el)
    return root


def lamp_art():
    root=E.parse(str(SOURCE/'内侧-00.svg')).getroot()
    art=E.Element('{%s}svg'%SVG,nsmap={None:SVG})
    group=E.SubElement(art,'{%s}g'%SVG,transform='translate(-356.9 -41)')
    for el in root.iter():
        if any(el.get('id','').endswith(suffix) for suffix in ['-forward-lamp-mount','-flashlight','-lamp-clamp-band']):
            group.append(copy.deepcopy(el))
    return art


def lamp_rail(frame):
    x,y=lamp_matrix(frame)[4:]
    t=smooth(frame/14)
    # Sliding shoe stays rooted in the right column; an articulated short link
    # reaches the original gun clamp. It never crosses the window or hand grip.
    mount=point(lamp_matrix(frame),(-28,-17))
    anchor=(mix(31,66,t),mix(337,93,t))
    return '<path d="M%g %gL%g %g" fill="none" stroke="#171d1d" stroke-width="9" stroke-linecap="round"/><path d="M%g %gL%g %g" fill="none" stroke="#444d49" stroke-width="5" stroke-linecap="round"/>'%(*anchor,*mount,*anchor,*mount) if frame else ''


def beam_instance(matrix):
    donor=E.parse(str(b.OWNER/'LIBRARY'/ (b.PREFIX+'枪-长枪-Codex-特勤霰弹枪.xml')),b.PARSER)
    light=copy.deepcopy(donor.find('.//x:DOMSymbolInstance[@name="装备光束"]',b.NS))
    light.find('x:matrix/x:Matrix',b.NS).attrib.clear()
    light.find('x:matrix/x:Matrix',b.NS).attrib.update(dict(zip(['a','b','c','d','tx','ty'],map(str,matrix))))
    light.find('x:Actionscript/x:script',b.NS).text=E.CDATA('onClipEvent(load) { this._visible = false; _root.装备生命周期函数.装备光源载入(this,"长枪"); }')
    return light


def build_motion():
    manifest=json.loads((SOURCE/'manifest.json').read_text('utf8'))
    scratch=b.ROOT/'tmp/former-sheriff-shield-rush/light-source';scratch.mkdir(parents=True,exist_ok=True)
    lamp_path=scratch/'same-gun-lamp.svg';lamp_path.write_bytes(E.tostring(lamp_art()))
    lamp=b.native(lamp_path,'战技/同源枪灯')
    glow_path=scratch/'lamp-glow.svg'
    glow_path.write_text('<svg xmlns="%s"><ellipse rx="5" ry="9" fill="#fff0ba" fill-opacity=".13"/><ellipse rx="2.5" ry="6" fill="#fff4d0" fill-opacity=".35"/><ellipse rx="1.1" ry="3.7" fill="#fffae9"/></svg>'%SVG,'utf8')
    glow=b.native(glow_path,'战技/灯头亮面')
    for face in ['内侧','外侧']:
        art=b.node('DOMLayer', {'name':face+' / 15帧实体遮挡', 'color':'#4FFF4F'})
        ports=b.node('DOMLayer',{'name':'同源灯头 / 持续出光','color':'#FFFF66'})
        lamps=b.node('DOMLayer',{'name':'枪灯沿滑轨转移','color':'#FFFF66'})
        rails=b.node('DOMLayer',{'name':'滑座与连接臂','color':'#FFFF66'})
        beams=b.node('DOMLayer',{'name':'沿用战术手电光束','color':'#FFFF66'})
        for entry in [q for q in manifest['files'] if q['face']==face]:
            path=SOURCE/entry['file'];assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256']
            f=entry['frame'];edited=scratch/entry['file'];edited.write_bytes(E.tostring(unlit_motion(face,f)))
            ref=b.native(edited,'战技/枪盾%s/帧%02d'%(face,f))
            b.frame(art,f,elements=[b.instance(ref)])
            m=lamp_matrix(f)
            b.frame(ports,f,elements=[b.instance(b.PREFIX+'接口/透明判定',m,True,'手电口')])
            b.frame(lamps,f,elements=[b.instance(lamp,m),b.instance(glow,m,True,'灯晕')])
            rail_path=scratch/('rail-%02d.svg'%f);rail_path.write_text('<svg xmlns="%s">%s</svg>'%(SVG,lamp_rail(f)),'utf8')
            rail=b.native(rail_path,'战技/枪灯滑轨/帧%02d'%f)
            b.frame(rails,f,elements=[b.instance(rail)])
            b.frame(beams,f,elements=[beam_instance(b.writer.mul(m,(1,0,0,1,0,-3)))])
        stop=b.layer('外部战技驱动',script='stop();')
        stop.find('x:frames/x:DOMFrame',b.NS).set('duration','15')
        # The lens is on the enemy-facing exterior. In the player's inner view
        # the opaque shield covers the lamp, glow and bracket; light emerges
        # beyond the rim. Keep the same actual port for native illumination.
        order=[stop,ports,art,lamps,rails,beams] if face=='内侧' else [stop,ports,lamps,rails,art,beams]
        b.symbol(PREFIX+'枪盾变形'+face,order,clip=True)


def holder(field):
    """Preserve the canonical unit.man.wrapper.host ancestry for dressup."""
    leaf=b.symbol(PREFIX+'挂点/'+field+'内层',[b.layer('运行时装扮')],clip=True)
    mount=b.instance(leaf,clip=True,instance_name='挂点')
    if field=='脸型':
        body='''var u = _parent._parent._parent;
var face = u.脸型;
if (!face) face = (u.性别 == "女" ? "女" : "男") + "变装-基本脸型";
_root.装备引用配置.配置装扮(this,face,"装扮","脸型_引用");
_root.装备引用配置.配置装扮(this,u.发型,"装扮2","发型_引用");
_root.装备引用配置.配置装扮(this,u.面具,"装扮3","面具_引用");'''
    else:
        ref=field.replace('_装扮','')+'_引用'
        fallback='' if '_装扮' in field else '\nif (!skin) skin = (u.性别 == "女" ? "女" : "男") + "变装-裸体'+field+'";'
        body='var u = _parent._parent._parent;\nvar skin = u.'+field+';'+fallback+'\n_root.装备引用配置.配置装扮(this,skin,"装扮","'+ref+'");'
    b.node('script',parent=b.node('Actionscript',parent=mount)).text=E.CDATA('onClipEvent(load) {\n'+body+'\n}')
    return b.symbol(PREFIX+'挂点/'+field,[b.layer('保留标准三层引用',[mount])],clip=True)


def rotate_about(angle, pivot, destination):
    c,d=math.cos(angle),math.sin(angle)
    return c,d,-d,c,destination[0]-c*pivot[0]+d*pivot[1],destination[1]-d*pivot[0]-c*pivot[1]


def limb(a,z,top,bottom,width=.236):
    dx,dy=z[0]-a[0],z[1]-a[1];length=max(.001,math.hypot(dx,dy))
    sx,sy=dx/length,dy/length;scale=length/(bottom-top)
    return sy*width,-sx*width,sx*scale,sy*scale,a[0]-sx*scale*top,a[1]-sy*scale*top


def knee(a,z):
    # Fixed anatomical lengths, with the knee always bending towards travel.
    dx,dy=z[0]-a[0],z[1]-a[1];d=max(.001,math.hypot(dx,dy))
    l1,l2=30.,34.
    if d>l1+l2-.2:l1*=d/(l1+l2-.2);l2*=d/(l1+l2-.2)
    along=(l1*l1-l2*l2+d*d)/(2*d);h=math.sqrt(max(0,l1*l1-along*along))
    return a[0]+dx*along/d+dy*h/d,a[1]+dy*along/d-dx*h/d


@lru_cache(maxsize=1)
def run_reference():
    """Read the game's authored long-gun run keys, including dressup offsets.

    Keep the connected hip/thigh/shin/boot chain as a unit. R35's ankle-only
    solve erased the folded recovery leg and flight phase of a real run.
    This is a local player-animation reference, not traced ASTLIBRA footage.
    """
    lib=b.ROOT/'flashswf/arts/things0/LIBRARY'
    root=E.parse(str(lib/'sprite/Symbol 627.xml'))
    container=(.277084350585938,0,0,.276809692382813,3.35,-60.9)
    def matrix(el):
        m=el.find('x:matrix/x:Matrix',b.NS)
        return vals({k:float(v) for k,v in m.attrib.items()}) if m is not None else b.I
    keys=[]
    for f in range(0,22,3):
        pose={};occurrences={}
        for lay in reversed(root.findall('.//x:DOMLayer',b.NS)):
            frame=next((x for x in lay.findall('x:frames/x:DOMFrame',b.NS) if int(x.get('index','0'))==f),None)
            if frame is None:continue
            for inst in frame.findall('x:elements/x:DOMSymbolInstance',b.NS):
                ref=inst.get('libraryItemName');field=ref.split('/')[-1]
                if field not in {'屁股','左大腿','右大腿','小腿','脚'}:continue
                occurrence=occurrences.get(field,0);occurrences[field]=occurrence+1
                child=E.parse(str(lib/(ref+'.xml'))).find('.//x:DOMSymbolInstance',b.NS)
                pose[(field,occurrence)]=b.writer.mul(container,b.writer.mul(matrix(inst),matrix(child)))
        keys.append(pose)
    assert len(keys)==8 and all(len(k)==7 for k in keys)
    return keys


@lru_cache(maxsize=1)
def combat_reference():
    """Resolve the real return stance, including the combat legs at frame 0.

    The web dressup snapshot deliberately uses relaxed legs at frame 8. A
    weapon skill sets 格斗架势, so that snapshot is not a valid return pose.
    Read the owning player XFL registrations instead of fitting screenshots.
    """
    lib=b.ROOT/'flashswf/arts/things0/LIBRARY'
    hs=[h for h in json.loads((SOURCE/'pose-source.json').read_text('utf8'))['holders'] if h['field'] not in ['发型','面具']]
    def matrix(inst):
        m=inst.find('x:matrix/x:Matrix',b.NS)
        return vals({k:float(v) for k,v in m.attrib.items()}) if m is not None else b.I
    def instances(name,frame):
        root=E.parse(str(lib/(name+'.xml')))
        result=[]
        for layer in reversed(root.findall('.//x:DOMTimeline/x:layers/x:DOMLayer',b.NS)):
            for f in layer.findall('x:frames/x:DOMFrame',b.NS):
                start=int(f.get('index','0'))
                if start<=frame<start+int(f.get('duration','1')):
                    result.extend(f.findall('x:elements/x:DOMSymbolInstance',b.NS))
        return result
    branches={i.get('libraryItemName'):matrix(i) for i in instances('主角-男',142)}
    result=[]
    for h in hs:
        branch=h['path'][1].split('@')[0];host,leaf=h['path'][2:4]
        options=[]
        for inst in instances(branch,0):
            if inst.get('libraryItemName')!=host:continue
            for child in instances(host,0):
                if child.get('libraryItemName')==leaf:
                    options.append(b.writer.mul(branches[branch],b.writer.mul(matrix(inst),matrix(child))))
        assert options,(h['field'],h['path'])
        # Two upper arms share a host symbol. Their registrations disambiguate
        # them without depending on native display-list enumeration order.
        old=vals(h['matrix'])
        result.append(min(options,key=lambda m:sum((m[i]-old[i])**2 for i in range(6))))
    return result


def poses():
    src=json.loads((SOURCE/'pose-source.json').read_text('utf8'))['holders']
    hs=[e for e in src if e['field'] not in ['发型','面具']]
    init=[vals(e['matrix']) for e in hs]
    index=lambda field:next(i for i,e in enumerate(hs) if e['field']==field)
    gun_index=index('长枪_装扮')
    hip0=init[index('屁股')][4:]
    legfields={'左大腿','右大腿','小腿','脚'}
    runkeys=run_reference()

    def braced(charge=0,run=None,brake=0):
        rushing=run is not None
        if rushing:
            # Start on the lead-foot landing; the authored cycle provides
            # push-off, rear-heel recovery and a distinct flight interval.
            phase=(run/RUSH_COUNT*21+6)%21
            key=int(phase/3);t=phase/3-key
            gait={k:tween(runkeys[key][k],runkeys[key+1][k],t) for k in runkeys[key]}
            hip=gait[('屁股',0)][4:]
        else:
            hip=(hip0[0]-3-3*charge-brake*2,hip0[1]+2+3*charge+brake*1.5)
        lean=(.30 if rushing else mix(.07,.15,charge))+.09*brake
        shift=rotate_about(lean,hip0,hip)
        pose=[b.writer.mul(shift,m) if e['field'] not in legfields else m for e,m in zip(hs,init)]
        # Keep the gaze on the charge lane while the shoulders hunch behind steel.
        head=index('脸型');h=pose[head]
        pose[head]=b.writer.mul(rotate_about(-lean*.65,h[4:],h[4:]),h)
        theta=(.14 if rushing else .035+.045*charge)+brake*.06
        # A three-quarter shield keeps its rim readable while reducing the
        # billboard face. Its top/window follows the head, not a fixed world Y.
        sx,sy=(.165 if rushing else .18),.235
        weapon=(sx*math.cos(theta),sx*math.sin(theta),-sy*math.sin(theta),sy*math.cos(theta),
                (40 if rushing else 30)+charge*1+brake*3,
                (-119+(hip[1]-hip0[1]-4)*.9 if rushing else -126)+charge*3+brake*2)
        for side,fore,hand in [('far','左下臂','左手'),('near','右下臂','右手')]:
            ui=index('上臂') if side=='far' else max(i for i,e in enumerate(hs) if e['field']=='上臂')
            fi,hi=index(fore),index(hand)
            shoulder=point(pose[ui],(0,-47))
            grip=(36.346794,158.801671) if side=='far' else (13,183)
            target=point(weapon,grip);wrist=(target[0]-2.6,target[1]+.5)
            joint=elbow(shoulder,wrist)
            pose[ui]=limb(shoulder,joint,-47,47,.234)
            pose[fi]=limb(joint,wrist,-47,47,.234)
            angle=-.12 if side=='far' else -.38
            pose[hi]=(.235*math.cos(angle),.235*math.sin(angle),-.235*math.sin(angle),.235*math.cos(angle),*target)
        if rushing:
            occurrences={}
            for i,e in enumerate(hs):
                field=e['field']
                if field not in legfields|{'屁股'}:continue
                occurrence=occurrences.get(field,0);occurrences[field]=occurrence+1
                pose[i]=gait[(field,occurrence)]
            return pose,weapon
        for thighfield,offset in [('左大腿',0),('右大腿',4)]:
            ti=index(thighfield)
            footi=next(i for i in range(ti+1,len(hs)) if hs[i]['field']=='脚')
            shini=next(i for i in range(ti+1,len(hs)) if hs[i]['field']=='小腿')
            hipjoint=point(shift,point(init[ti],(0,-60)))
            ankle=((20+8*brake if offset==0 else -19-3*brake),(-4 if offset==0 else 0))
            tilt=.0 if offset==0 else -.06
            joint=knee(hipjoint,ankle)
            pose[ti]=limb(hipjoint,joint,-60,65)
            pose[shini]=limb(joint,ankle,-68,78)
            pose[footi]=(.236*math.cos(tilt),.236*math.sin(tilt),-.236*math.sin(tilt),.236*math.cos(tilt),ankle[0],ankle[1]+2)
        return pose,weapon

    guard,shield=braced()
    combat=combat_reference()
    gun_end=b.writer.mul(combat[gun_index],b.writer.mul((1,0,0,1,-101.65,-48.75),inverse((0,1,-1,0,72,12))))

    def close_pose(f):
        # Fold beside the torso first, then bring the compact weapon onto the
        # shoulder. Pivot at the firing hand instead of swinging a whole shield
        # around its top-left registration. The supporting hand changes grip.
        t=smooth(f/14)
        lift=smooth((f-2)/12)
        pose=[tween(a,z,t) for a,z in zip(guard,combat)]
        near=index('右手');far=index('左手')
        final_grips={i:point(inverse(gun_end),combat[i][4:]) for i in [near,far]}
        local_near=tuple(mix(a,z,t) for a,z in zip((13,183),final_grips[near]))
        pivot=tuple(mix(a,z,t) for a,z in zip(guard[near][4:],combat[near][4:]))
        weapon=tween(shield,gun_end,lift)
        offset=point(weapon,local_near)
        weapon=(*weapon[:4],weapon[4]+pivot[0]-offset[0],weapon[5]+pivot[1]-offset[1])
        for side,fore,hi,startgrip in [('far','左下臂',far,(36.346794,158.801671)),('near','右下臂',near,(13,183))]:
            ui=index('上臂') if side=='far' else max(i for i,e in enumerate(hs) if e['field']=='上臂')
            fi=index(fore)
            grip_t=smooth((f-3)/10) if side=='far' else t
            local=tuple(mix(a,z,grip_t) for a,z in zip(startgrip,final_grips[hi]))
            target=point(weapon,local)
            end_wrist=point(combat[fi],(0,47))
            wrist=tuple(target[j]+mix((-2.6,.5)[j],end_wrist[j]-combat[hi][4+j],t) for j in range(2))
            shoulder=tuple(mix(a,z,t) for a,z in zip(point(guard[ui],(0,-47)),point(combat[ui],(0,-47))))
            joint=elbow(shoulder,wrist)
            pose[ui]=limb(shoulder,joint,-47,47,.234)
            pose[fi]=limb(joint,wrist,-47,47,.234)
            hm=tween(guard[hi],combat[hi],t)
            pose[hi]=(*hm[:4],*target)
            # Match the authored asymmetrical arm registration exactly at the
            # endpoint, after the new grip has been established.
            settle=smooth((f-10)/4)
            pose[ui]=tween(pose[ui],combat[ui],settle)
            pose[fi]=tween(pose[fi],combat[fi],settle)
        if f==14:return dict(parts=combat,weapon=gun_end,progress=0)
        return dict(parts=pose,weapon=weapon,progress=14-f)

    allposes=[]
    for f in range(BASE_COUNT):
        if f<15:
            # Enter from the same native aiming stance used on return. Reverse
            # the accepted hand-pivot transfer instead of sliding free hands
            # between unrelated relaxed legs and shield registrations.
            opening=close_pose(14-f)
            if f==14:opening=dict(parts=guard,weapon=shield,progress=14)
            allposes.append(opening);continue
        elif f>=CLOSE_START:
            allposes.append(close_pose(f-CLOSE_START));continue
        elif f<19:
            pose,weapon=braced((f-15)/3);progress=14
        elif f<BRAKE_START:
            pose,weapon=braced(run=f-RUSH_START);progress=14
        else:
            # Catch the mass with a planted lead foot, then recover to low guard.
            settle=smooth((f-BRAKE_START)/5)
            recoil,ws=braced(charge=.3,brake=1-settle)
            end,wend=braced()
            pose=[tween(a,z,settle) for a,z in zip(recoil,end)]
            weapon=tween(ws,wend,settle);progress=14
        allposes.append(dict(parts=pose,weapon=weapon,progress=progress))
    # A stop can arrive on any stride (tap, partial/full charge, wall). Each
    # six-frame branch starts at the exact last displayed run key and lands in
    # the common low guard. Native keys avoid script-owned transform overrides.
    for run in range(RUSH_COUNT):
        start=allposes[RUSH_START+run]
        for f in range(BRAKE_COUNT):
            t=smooth(f/(BRAKE_COUNT-1))
            allposes.append(dict(parts=[tween(a,z,t) for a,z in zip(start['parts'],guard)],weapon=tween(start['weapon'],shield,t),progress=14))
    return hs,allposes


@lru_cache(maxsize=1)
def shadow_reference():
    """Resolve the ordinary player's shadow in unit space, not man space.

    The action and ordinary lower-body containers have slightly different
    scales/origins. Compose the authored chain once, then compensate for the
    action container when placing it. Never fit a second ellipse by eye.
    """
    lib=b.ROOT/'flashswf/arts/things0/LIBRARY'
    player=E.parse(str(lib/'主角-男.xml'))
    frame=int(player.find('.//x:DOMFrame[@name="长枪站立"]',b.NS).get('index'))
    branch='移动射击动画层/长枪-手枪站立左腿'
    hosts=[]
    for f in player.findall('.//x:DOMFrame',b.NS):
        start=int(f.get('index','0'))
        if start<=frame<start+int(f.get('duration','1')):
            hosts.extend(i for i in f.findall('x:elements/x:DOMSymbolInstance',b.NS) if i.get('libraryItemName')==branch)
    assert len(hosts)==1,'ordinary long-gun shadow host must be unambiguous'
    root=E.parse(str(lib/(branch+'.xml')))
    inst=root.find('.//x:DOMSymbolInstance[@libraryItemName="主角肢体素材/Symbol 3"]',b.NS)
    def matrix(i):
        return vals({k:float(v) for k,v in i.find('x:matrix/x:Matrix',b.NS).attrib.items()})
    return dict(source=lib/(inst.get('libraryItemName')+'.xml'),
                matrix=b.writer.mul(matrix(hosts[0]),matrix(inst)),
                load=inst.find('x:Actionscript',b.NS),branch=branch)


def shadow_source():
    return shadow_reference()['source']


def shadow_matrix():
    return shadow_reference()['matrix']


def draw_order(hs):
    """Back to front: far-hand shield first, then the complete player rig."""
    gun=next(i for i,e in enumerate(hs) if e['field']=='长枪_装扮')
    return [gun]+[i for i in range(len(hs)) if i!=gun]


def build_action():
    hs,frames=poses();inv=inverse(CONTAINER)
    actions=b.layer('战技控制器',script='stop();\n_root.主动战技函数.长枪.特勤盾冲.载入(this);')
    actions.find('x:frames/x:DOMFrame',b.NS).set('duration',str(COUNT))
    layers=[actions]
    # We see the inner face of the far/left-hand shield. Every body part is
    # nearer the camera; keep the original limb ordering above the shield.
    for i in reversed(draw_order(hs)):
        field=hs[i]['field'];weapon=field=='长枪_装扮'
        ref=PREFIX+'枪盾变形内侧' if weapon else holder(field)
        lay=b.node('DOMLayer',{'name':'枪盾实体' if weapon else field+' / '+str(i),'color':'#4FFF4F'})
        for f,p in enumerate(frames):
            mat=b.writer.mul(inv,p['weapon'] if weapon else p['parts'][i])
            el=b.instance(ref,mat,True,'盾具' if weapon else '肢体'+str(i))
            b.frame(lay,f,elements=[el])
        layers.append(lay)
    # A wide front area in man-local space, hidden through _visible, not alpha.
    hit=b.instance(b.PREFIX+'接口/透明判定',(4,0,0,16,155,-190),True,'冲撞区域')
    hitlayer=b.layer('碰撞定位',[hit]);hitlayer.find('x:frames/x:DOMFrame',b.NS).set('duration',str(COUNT));layers.insert(1,hitlayer)
    shadow=E.parse(str(shadow_source()),b.PARSER).getroot()
    shadow.set('name',PREFIX+'接地阴影')
    for k in ['itemID','lastModified']:shadow.attrib.pop(k,None)
    # Keep the native gradient only. Its donor flight script assumes a
    # different local origin; this grounded action owns its placement.
    for script in shadow.findall('.//x:Actionscript',b.NS):script.getparent().remove(script)
    b.GENERATED[PREFIX+'接地阴影']=shadow
    ground_instance=b.instance(PREFIX+'接地阴影',b.writer.mul(inv,shadow_matrix()),True,'接地阴影')
    ground_instance.append(copy.deepcopy(shadow_reference()['load']))
    ground=b.layer('接地阴影',[ground_instance])
    ground.find('x:frames/x:DOMFrame',b.NS).set('duration',str(COUNT))
    layers.append(ground)
    b.symbol(PREFIX+LINKAGE,layers,LINKAGE)
    return hs,frames


def build():
    build_motion();hs,frames=build_action()
    for name,root in b.GENERATED.items():b.write_xml(b.OWNER/'LIBRARY'/(name+'.xml'),root)
    b.append_to_document(b.OWNER,b.GENERATED)
    # The parent things-new RSL imports this anchor. Keep the action reachable
    # through the same owning library as its gun, rather than test-only exports.
    anchor_path=b.OWNER/'LIBRARY/Codex专用素材.xml'
    anchor=E.parse(str(anchor_path),b.PARSER).getroot()
    layers=anchor.find('.//x:layers',b.NS)
    for old in list(layers):
        if old.get('name')=='重装特勤盾冲':layers.remove(old)
    layers.append(b.layer('重装特勤盾冲',[b.instance(PREFIX+LINKAGE,clip=True)]))
    b.write_xml(anchor_path,anchor)
    out=b.ROOT/'tmp/former-sheriff-shield-rush';out.mkdir(parents=True,exist_ok=True)
    reference=b.ROOT/'flashswf/arts/things0/LIBRARY/sprite/Symbol 627.xml'
    report=dict(linkage=LINKAGE,frames=COUNT,transformFrames=15,phaseFrames=dict(open=[1,15],hold=[16,19],rush=[20,35],brake=[36,41],close=[42,56],strideBrakes=[BRAKE_BANK_START+1,COUNT]),brakeBranchFrames=BRAKE_COUNT,returnPose='native long-gun combat legs frame 0; upper-body idle',strideStep=STRIDE_STEP,light=dict(source='same R26 shotgun lamp and authored tactical beam',mount='exterior, occluded by inner shield face',port='手电口',beam='装备光束',path=[lamp_matrix(f) for f in range(15)],launchGlintTicks=6),runReference=dict(source=reference.relative_to(b.ROOT).as_posix(),sha256=hashlib.sha256(reference.read_bytes()).hexdigest(),keyframes=list(range(0,22,3)),startFrame=6),holders=hs,poses=frames,symbolCount=len(b.GENERATED))
    report['shadow']=dict(source=shadow_source().relative_to(b.ROOT).as_posix(),sha256=hashlib.sha256(shadow_source().read_bytes()).hexdigest(),host=shadow_reference()['branch'],unitMatrix=shadow_matrix(),actionLocalMatrix=b.writer.mul(inverse(CONTAINER),shadow_matrix()),visibility='native player shadow setting')
    (out/'art-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf8')
    print('Shield rush native art:',len(b.GENERATED),'symbols;',COUNT,'action frames, 15 transform frames')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--archive',type=Path);args=parser.parse_args()
    if args.archive:archive(args.archive)
    build()
