"""Authored fixed-rig phase-two actions. No combat AI or player-rig changes.

Unit-space keys share the existing shield-rush held pose. CS6 publishes these
native timelines; draw/use/stow and all registrations remain in the XFL.
This sibling namespace is independent of phase_one.py's owned closure.
"""
import argparse, copy, hashlib, json, math
from pathlib import Path
from lxml import etree as E
import shield_rush as s

b = s.b
PREFIX = 'Codex/前治安官二阶段/'
SOURCE = b.ROOT/'flashswf/arts/new/Codex素材源稿/前治安官二阶段'
HS, RUSH = s.poses()
GUARD = RUSH[15]
BODY = next(i for i,h in enumerate(HS) if h['field']=='身体')
HIP = next(i for i,h in enumerate(HS) if h['field']=='屁股')
HEAD = next(i for i,h in enumerate(HS) if h['field']=='脸型')
INDEX = {h['field']:i for i,h in enumerate(HS)}
ARMS = [(5,6,7),(14,15,16)]
SKIP = {i for i,h in enumerate(HS) if '_装扮' in h['field']}
KEYS = ['持盾待机','盾击','持盾刺击','持盾射击','持盾冲刺']
PISTOL_SHOTS = tuple(range(25,82,8))  # Native 8-round service magazine, 30 fps.
PISTOL_REST = (32.,-108.)
PISTOL_MAG_SEAT = (28.,-100.)
STOW_SOCKETS = {'knife':(-6.,-59.),'pistol':(-7.,-60.)}
SUPPORT_STEPS = 5
PISTOL_FRAMES = 138
PISTOL_RELOAD = dict(entry=85, dock=92, retained=93, eject=95,
    take=101, seat=109, regrip=113, withdraw=117, fold=121,
    stow=130, end=137)
KNIFE_GRIP = (14., 0.)
KNIFE_WRIST = (-24., -1.)
REMOVED_BODY_GEAR = ('刀鞘','枪套')


def track(keys,frame):
    left=max(k for k in keys if k<=frame);right=min(k for k in keys if k>=frame)
    return keys[left] if left==right else s.mix(keys[left],keys[right],s.smooth((frame-left)/(right-left)))


def matrix(scale, angle, at):
    c,d=math.cos(angle)*scale,math.sin(angle)*scale
    return (c,d,-d,c,*at)


def blend(a,z,t):
    p=copy.deepcopy(a)
    p['parts']=[s.tween(x,y,t) for x,y in zip(a['parts'],z['parts'])]
    p['weapon']=s.tween(a['weapon'],z['weapon'],t)
    p['right']=tuple(s.mix(x,y,t) for x,y in zip(a['right'],z['right']))
    return p


def solve_arm(p,side,target,hand_angle=-.38):
    ui,fi,hi=ARMS[side]
    shoulder=s.point(p['parts'][ui],(0,-47))
    wrist=(target[0]-2.6,target[1]+.5)
    joint=s.elbow(shoulder,wrist)
    p['parts'][ui]=s.limb(shoulder,joint,-47,47,.234)
    p['parts'][fi]=s.limb(joint,wrist,-47,47,.234)
    p['parts'][hi]=matrix(.235,hand_angle,target)


def make_pose(dx=0,dy=0,lean=0,shield_dx=0,shield_dy=0,shield_angle=0,
              right=None,hand_angle=-.38,feet=None):
    p=copy.deepcopy(GUARD)
    pivot=GUARD['parts'][HIP][4:]
    transform=s.rotate_about(lean,pivot,(pivot[0]+dx,pivot[1]+dy))
    leg={1,2,3,17,18,19}
    for i in range(len(HS)):
        if i not in leg:p['parts'][i]=b.writer.mul(transform,p['parts'][i])
    # Eyes stay level while the trunk loads or drives the shoulder forward.
    h=p['parts'][HEAD]
    p['parts'][HEAD]=b.writer.mul(s.rotate_about(-lean*.40,h[4:],h[4:]),h)
    m=GUARD['weapon'];sp=(m[4]+shield_dx,m[5]+shield_dy)
    p['weapon']=b.writer.mul(s.rotate_about(shield_angle,m[4:],sp),m)
    solve_arm(p,0,s.point(p['weapon'],(36.346794,158.801671)),-.12)
    if right is None:right=s.point(p['weapon'],(13,183))
    p['right']=right
    solve_arm(p,1,right,hand_angle)
    # Plant both soles. Knees follow the moving pelvis, never slide the feet
    # just to increase attack reach. Explicit steps are authored separately.
    for ti,si,fi in [(1,3,2),(17,19,18)]:
        hipjoint=s.point(transform,s.point(GUARD['parts'][ti],(0,-60)))
        ankle=s.point(GUARD['parts'][si],(0,78))
        if feet and fi in feet:ankle=feet[fi]
        knee=s.knee(hipjoint,ankle)
        p['parts'][ti]=s.limb(hipjoint,knee,-60,65)
        p['parts'][si]=s.limb(knee,ankle,-68,78)
        foot=GUARD['parts'][fi]
        p['parts'][fi]=(*foot[:4],ankle[0],ankle[1]+2)
    if not any([dx,dy,lean,shield_dx,shield_dy,shield_angle,right!=s.point(GUARD['weapon'],(13,183)),feet]):
        p['parts']=copy.deepcopy(GUARD['parts'])
    return p


def sample(keys,count):
    out=[]
    for frame in range(count):
        left=max(k for k in keys if k<=frame)
        right=min(k for k in keys if k>=frame)
        out.append(copy.deepcopy(keys[left]) if left==right else blend(keys[left],keys[right],s.smooth((frame-left)/(right-left))))
    return out


def body_socket(p,position):
    return s.point(b.writer.mul(p['parts'][HIP],s.inverse(GUARD['parts'][HIP])),position)


def held_weapon(kind,p,angle=None):
    # Native gun grip is at (0,0). The folded baton blade also keeps its
    # original grip registration, so the right hand and prop share one point.
    return matrix(.235, angle if angle is not None else (0 if kind=='pistol' else -math.pi/2),p['right'])


def knife_sequence():
    guard=make_pose();socket=body_socket(guard,STOW_SOCKETS['knife'])
    frames=sample({0:guard,2:guard,
      8:make_pose(-1,2,-.02,right=socket,hand_angle=.05),
      12:make_pose(-3,4,.03,-2,3,-.02,right=(-18,-90),hand_angle=-.4),
      17:make_pose(-5,6,-.03,-4,5,-.06,right=(0,-122),hand_angle=-1.30,feet={2:(28,-11),18:(-24,0)}),
      23:make_pose(17,10,.32,18,9,.05,right=(63,-95),hand_angle=-.28,feet={2:(49,-4),18:(-10,0)}),
      25:make_pose(17,10,.32,18,9,.05,right=(63,-95),hand_angle=-.28,feet={2:(49,-4),18:(-10,0)}),
      30:make_pose(16,8,.24,19,7,.04,right=(26,-116),hand_angle=-1.28,feet={2:(49,-4),18:(-10,0)}),
      35:make_pose(22,10,.37,23,9,.06,right=(75,-89),hand_angle=-.38,feet={2:(54,-4),18:(-7,0)}),
      37:make_pose(22,10,.37,23,9,.06,right=(75,-89),hand_angle=-.38,feet={2:(54,-4),18:(-7,0)}),
      42:make_pose(20,8,.28,24,7,.04,right=(31,-119),hand_angle=-1.30,feet={2:(54,-4),18:(-3,-3)}),
      47:make_pose(24,11,.44,27,11,.08,right=(82,-90),hand_angle=-.5,feet={2:(57,-4),18:(0,0)}),
      48:make_pose(24,11,.44,27,11,.08,right=(82,-90),hand_angle=-.5,feet={2:(57,-4),18:(0,0)}),
      53:make_pose(20,8,.32,23,8,.05,right=(38,-94),hand_angle=-.25,feet={2:(52,-4),18:(-7,-5)}),
      58:make_pose(10,5,.12,12,4,.02,right=(5,-76),hand_angle=-.12,feet={2:(40,-8),18:(-15,0)}),
      62:make_pose(right=(-12,-72),hand_angle=.03),
      67:make_pose(right=socket,hand_angle=.05),75:guard},76)
    return frames


def sequence():
    guard=make_pose()
    # A committed step, shoulder and shield arrive together. The short drive
    # and impact hold are intentionally much faster than loading/recovery.
    bash=sample({0:guard,2:guard,
      8:make_pose(-7,7,-.13,-8,6,-.10,feet={2:(18,-4),18:(-24,0)}),
      11:make_pose(-3,9,-.07,-3,7,-.07,feet={2:(33,-12),18:(-22,0)}),
      13:make_pose(10,10,.18,16,5,.07,feet={2:(47,-4),18:(-18,0)}),
      15:make_pose(23,6,.41,35,-1,.24,feet={2:(47,-4),18:(-14,-1)}),
      16:make_pose(23,6,.41,35,-1,.24,feet={2:(47,-4),18:(-14,-1)}),
      19:make_pose(19,9,.32,28,4,.14,feet={2:(47,-4),18:(-14,0)}),
      22:make_pose(19,7,.27,29,2,.12,feet={2:(47,-4),18:(-14,0)}),
      27:make_pose(11,4,.12,15,2,.04,feet={2:(41,-7),18:(-16,0)}),
      34:make_pose(3,1,.035,4,1,.015,feet={2:(28,-6),18:(-18,0)}),41:guard},42)
    knife=knife_sequence()
    pistol_socket=body_socket(guard,STOW_SOCKETS['pistol'])
    aim=make_pose(0,2,.055,right=(39,-106),hand_angle=-.30)
    pistol_keys={0:guard,2:guard,
      8:make_pose(-1,0,-.02,right=pistol_socket,hand_angle=.12),
      16:make_pose(-1,1,-.015,right=(0,-91),hand_angle=-.25),22:aim,
      85:make_pose(0,3,-.025,right=(19,-102),hand_angle=-.25),
      92:make_pose(0,3,-.025,right=PISTOL_REST,hand_angle=-.25),
      95:make_pose(0,3,-.025,right=PISTOL_MAG_SEAT,hand_angle=.15),
      98:make_pose(0,4,-.035,right=(13,-85),hand_angle=.15),
      101:make_pose(0,4,-.035,right=(-5,-69),hand_angle=.15),
      103:make_pose(0,4,-.035,right=(-5,-72),hand_angle=.15),
      108:make_pose(0,3,-.025,right=(25,-94),hand_angle=.15),
      109:make_pose(0,3,-.025,right=PISTOL_MAG_SEAT,hand_angle=.15),
      113:make_pose(0,3,-.025,right=PISTOL_REST,hand_angle=-.3),
      117:make_pose(0,2,-.015,right=(24,-104),hand_angle=-.3),
      121:make_pose(right=(5,-91),hand_angle=-.25),
      130:make_pose(right=pistol_socket,hand_angle=.12),137:guard}
    for shot in PISTOL_SHOTS:
        pistol_keys[shot]=aim
        pistol_keys[shot+1]=make_pose(-2,3,-.025,right=(34,-111),hand_angle=-.6)
        pistol_keys[shot+3]=make_pose(-1,2,.025,right=(37,-107),hand_angle=-.38)
        if shot!=PISTOL_SHOTS[-1]:pistol_keys[shot+7]=aim
    pistol=sample(pistol_keys,PISTOL_FRAMES)
    charge=copy.deepcopy(RUSH[18]);charge['right']=charge['parts'][16][4:]
    run0=copy.deepcopy(RUSH[19]);run0['right']=run0['parts'][16][4:]
    rush=sample({0:guard,8:charge,12:run0},13)
    for p in RUSH[19:35]:
        p=copy.deepcopy(p);p['right']=p['parts'][16][4:];rush.append(p)
    last=rush[-1]
    rush+=sample({0:last,7:guard},8)
    rush.append(copy.deepcopy(guard))
    actions={KEYS[0]:[guard],KEYS[1]:bash,KEYS[2]:knife,KEYS[3]:pistol,KEYS[4]:rush}
    # Generic character animations do not add equipment-specific belt gear.
    # Draw/stow travels through the existing hip silhouette; only the active
    # weapon is shown, behind the body while crossing the storage boundary.
    for name,frames in actions.items():
        for f,p in enumerate(frames):
            p['active']=None;p['prop']=None;p['flash']=False;p['retained']=False
            p['magazine']=None;p['spent_magazine']=None;p['spentAlpha']=1
            p['supportStep']=0;p['propBehindBody']=False
            p['sockets']={k:body_socket(p,v) for k,v in STOW_SOCKETS.items()}
            if name==KEYS[2] and f in [8,67]:p['right']=p['sockets']['knife']
            if name==KEYS[3] and f in [8,PISTOL_RELOAD['stow']]:p['right']=p['sockets']['pistol']
            # Independently interpolated bone rotations can separate elbows.
            # Solve both arms again from the authored shoulder and hand paths.
            if name!=KEYS[4] or f in [0,len(frames)-1]:
                solve_arm(p,0,s.point(p['weapon'],(36.346794,158.801671)),-.12)
                hm=p['parts'][16]
                solve_arm(p,1,p['right'],math.atan2(hm[1],hm[0]))
                # Re-close the knee joints after interpolating the pelvis and
                # authored foot trajectories; no detached armor at in-betweens.
                tr=b.writer.mul(p['parts'][HIP],s.inverse(GUARD['parts'][HIP]))
                for ti,si,fi in [(1,3,2),(17,19,18)]:
                    hj=s.point(tr,s.point(GUARD['parts'][ti],(0,-60)))
                    ankle=(p['parts'][fi][4],p['parts'][fi][5]-2)
                    knee=s.knee(hj,ankle)
                    p['parts'][ti]=s.limb(hj,knee,-60,65)
                    p['parts'][si]=s.limb(knee,ankle,-68,78)
            if f in [0,len(frames)-1]:p['parts']=copy.deepcopy(GUARD['parts'])
            if name==KEYS[2] and 8<=f<=67:
                p['active']='knife'
                # A clenched fist replaces the shooting index-finger pose.
                # Rotate the wrist port with the hand, then solve the arm.
                hm=p['parts'][16]
                wrist=s.point(hm,KNIFE_WRIST)
                shoulder=s.point(p['parts'][14],(0,-47))
                elbow=s.elbow(shoulder,wrist)
                p['parts'][14]=s.limb(shoulder,elbow,-47,47,.234)
                p['parts'][15]=s.limb(elbow,wrist,-47,47,.234)
                p['prop']=b.writer.mul(hm,(1,0,0,1,*KNIFE_GRIP))
                p['propBehindBody']=f<=11 or f>=64
            if name==KEYS[3] and 8<=f<=PISTOL_RELOAD['stow']:
                p['active']='pistol'
                angle=track({8:math.pi/2,16:.5,22:0,84:0,85:.1,92:0,
                  113:0,117:.15,121:.55,130:math.pi/2},f)
                if f in [x+1 for x in PISTOL_SHOTS]:angle=-.18
                p['prop']=held_weapon('pistol',p,angle)
                p['flash']=f in PISTOL_SHOTS
                p['retained']=PISTOL_RELOAD['retained']<=f<PISTOL_RELOAD['regrip']
                p['propBehindBody']=f<=12 or f>=126
                if p['retained']:p['prop']=matrix(.235,0,PISTOL_REST)
                if PISTOL_RELOAD['take']<=f<PISTOL_RELOAD['seat']:
                    p['magazine']=matrix(.235,0,(p['right'][0],p['right'][1]-3))
                if 96<=f<=115:
                    t=f-96;p['spent_magazine']=matrix(.235,t*.11,(28+t*.16,min(-96+.42*t*t,-4)))
                    p['spentAlpha']=min(1,(116-f)/5)
            if name==KEYS[3]:
                p['supportStep']=round(track({0:0,85:0,91:SUPPORT_STEPS-1,
                  113:SUPPORT_STEPS-1,121:0,137:0},f))
    return actions


def one_frame(name,source,frame=0):
    root=E.parse(str(b.OWNER/'LIBRARY'/(source+'.xml')),b.PARSER).getroot()
    layers=[]
    for layer in root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer',b.NS):
        old=next((f for f in layer.findall('x:frames/x:DOMFrame',b.NS)
            if int(f.get('index'))<=frame<int(f.get('index'))+int(f.get('duration','1'))),None)
        if old is None:continue
        elements=[copy.deepcopy(x) for x in old.findall('x:elements/*',b.NS)]
        for el in elements:
            for action in list(el.findall('.//x:Actionscript',b.NS)):action.getparent().remove(action)
        if elements:layers.append(b.layer(layer.get('name'),elements))
    b.symbol(name,layers,clip=True)
    return name


def closed_glove():
    root=E.parse(str(b.SOURCE/'15-right-glove.svg')).getroot()
    ns={'v':'http://www.w3.org/2000/svg'}
    paths=root.findall('.//v:g[@id="preserved-grip"]//v:path',ns)
    for el in paths[:2]:
        value=el.get('d')
        for old,new in [('30.450000','23.500000'),('34.200000','26.000000'),('30.45','23.5'),('34.2','26')]:value=value.replace(old,new)
        el.set('d',value)
    fingers=root.find('.//v:g[@id="finger-shells-and-flex-seams"]',ns)
    fingers[0].set('d','M96 27 L108 31 Q115 33 112 39 L99 37 Z')
    fingers[-1].set('d','M103 27 L108 29 M95 73 L101 74')
    thumb=E.SubElement(root,'{http://www.w3.org/2000/svg}path')
    thumb.attrib.update({'d':'M6 -19 Q10 -20 13 -15 L22 -9 Q25 -6 22 -3 Q20 -1 17 -4 L11 -8 Q7 -12 6 -19 Z','fill':'#343633','stroke':'#17191b','stroke-width':'.75'})
    path=SOURCE/'握刀右手.svg';path.write_bytes(E.tostring(root,encoding='utf-8'))
    ref=b.native(path,'二阶段临时/握刀右手')
    hand=b.GENERATED.pop(ref);hand.set('name',PREFIX+'握刀右手')
    hand.find('x:timeline/x:DOMTimeline',b.NS).set('name','握刀右手')
    hand.attrib.pop('symbolType',None)
    # Named static ports retain the actual palm and cuff registrations.
    ports=b.layer('握持与护腕定位',[
      b.instance(PREFIX+'接口',(1,0,0,1,14,0),True,'握点'),
      b.instance(PREFIX+'接口',(1,0,0,1,-24,-1),True,'腕点')])
    hand.find('.//x:layers',b.NS).insert(0,ports)
    b.GENERATED[PREFIX+'握刀右手']=hand


def source_symbols():
    SOURCE.mkdir(parents=True,exist_ok=True)
    one_frame(PREFIX+'头部', 'Codex/前治安官/固定装备/头部',1)
    one_frame(PREFIX+'匕首',b.PREFIX+'刀-Codex-特勤警棍',14)
    # Exclude legacy marker geometry from visual-only weapon timelines.
    knife=b.GENERATED[PREFIX+'匕首']
    for lay in list(knife.findall('.//x:DOMLayer',b.NS)):
        if lay.get('name')=='原短兵判定接口':lay.getparent().remove(lay)
    one_frame(PREFIX+'手枪',b.PREFIX+'武器/沙鹰静态动画')
    b.symbol(PREFIX+'接口',[b.layer('空定位点')],clip=True)
    closed_glove()
    for name,port,xy in [('手枪','枪口位置',(138.4,-34.05)),('匕首','刀口位置',(0,164.16))]:
        b.GENERATED[PREFIX+name].find('.//x:layers',b.NS).insert(0,
            b.layer('攻击定位 / 未接伤害',[b.instance(PREFIX+'接口',(1,0,0,1,*xy),True,port)]))
    one_frame(PREFIX+'盾牌',s.PREFIX+'枪盾变形内侧',14)
    # Shared light ports stay named and available. The new preview poses do
    # not install a second light controller or add another defense modifier.
    for el in b.GENERATED[PREFIX+'盾牌'].findall('.//x:DOMSymbolInstance',b.NS):
        if el.get('name')=='装备光束':
            b.node('script',parent=b.node('Actionscript',parent=el)).text=E.CDATA('onClipEvent(load) { this._visible=false; }')
    # Only weapon-owned hardware and transient effects. No holster, sheath or
    # persistent spare gun is attached to the character's clothing.
    designs={
      '换弹承托':'<path d="M-5 -4L-3 -4L-2 0L3 0L4 -4L6 -4L5 3L-4 3Z" fill="#343b3b" stroke="#171b1d" stroke-width=".7"/><path d="M-3 3L-2 8L1 8L2 3" fill="#232a2a" stroke="#171b1d" stroke-width=".7"/>',
      '手枪弹匣':'<path d="M-8 -3L7 -3L9 43L-6 44Z" fill="#2b3030" stroke="#141a1b" stroke-width="2.2"/><path d="M-8 43L11 42L12 47L-8 48Z" fill="#181e20" stroke="#121617" stroke-width="2"/><path d="M-3 1L2 1L4 37M-4 12L-1 12M-3 22L0 22M-3 32L1 32" fill="none" stroke="#606461" stroke-width="1.2"/>',
      '枪口火光':'<path d="M0 0L8 -4L6 -1L17 -1L8 2L9 5L1 2Z" fill="#efbb73" fill-opacity=".85"/><path d="M0 0L10 0L3 2Z" fill="#fff5ce"/>'}
    for name,art in designs.items():
        path=SOURCE/(name+'.svg')
        text='<svg xmlns="http://www.w3.org/2000/svg">'+art+'</svg>'
        if not path.exists() or path.read_text('utf8')!=text:path.write_text(text,'utf8')
        ref=b.native(path,'二阶段临时/'+name)
        root=b.GENERATED.pop(ref);root.set('name',PREFIX+name);b.GENERATED[PREFIX+name]=root
    # Each folded/open state is a single native display list. Parenting to the
    # shield gives scale, mirroring and local registration without per-frame
    # dressup or an onEnterFrame attachment controller.
    b.GENERATED[PREFIX+'换弹承托'].attrib.pop('symbolType',None)
    base=copy.deepcopy(b.GENERATED[PREFIX+'盾牌'])
    for step in range(SUPPORT_STEPS):
        ref=PREFIX+('盾牌' if step==0 else '盾牌-承托'+str(step))
        root=copy.deepcopy(base);root.set('name',ref)
        root.find('x:timeline/x:DOMTimeline',b.NS).set('name',ref.split('/')[-1])
        t=step/(SUPPORT_STEPS-1)
        support=b.writer.mul(s.inverse(GUARD['weapon']),(.18+.82*t,0,0,1,47,-109))
        rest=s.point(s.inverse(GUARD['weapon']),PISTOL_REST)
        layer=b.layer('盾内可折叠承托 / 不依赖人物服装',[
          b.instance(PREFIX+'换弹承托',support,True,'换弹承托'),
          b.instance(PREFIX+'接口',(1,0,0,1,*rest),True,'承托枪位')])
        root.find('.//x:layers',b.NS).insert(0,layer)
        b.GENERATED[ref]=root


def fixed_instance(ref,m=b.I,name=None):
    el=b.instance(ref,m,clip=False,instance_name=name)
    el.set('loop','single frame');el.set('firstFrame','0')
    return el


def action_symbol(name,frames):
    # Coordinates are in unit space. The wrapper exposes the usual man-local
    # scale separately, so controller integration does not have to guess it.
    inv=s.inverse(s.CONTAINER);layers=[]
    timeline=b.node('DOMLayer',{'name':'动作节点 / 不执行战斗'})
    events={0:'持盾开始',len(frames)-1:'持盾结束'}
    if name=='盾击':events.update({8:'压低蓄势',11:'抢步发力',13:'前脚踩稳',15:'盾击命中',17:'撞击回震',27:'退步收势'})
    elif name=='持盾刺击':events.update({8:'反握取刀',17:'抬肘蓄势',23:'斜下刺一',30:'短回拉',35:'斜下刺二',42:'回拉预备',47:'斜下刺三',58:'收刀开始',67:'收刀到位'})
    elif name=='持盾射击':
        events.update({8:'拔枪',22:'瞄准',85:'移入承托',92:'枪械承托',95:'空匣脱离',101:'取新弹匣',
          108:'对准匣口',109:'弹匣到位',113:'握枪复位',117:'撤出承托',121:'承托折回并收枪',130:'收枪到位'})
        events.update({f:'射击'+str(i+1) for i,f in enumerate(PISTOL_SHOTS)})
    elif name=='持盾冲刺':events.update({8:'蓄势',13:'冲刺循环开始',28:'冲刺循环结束',29:'制动'})
    for f in range(len(frames)):
        script='stop();' if f==len(frames)-1 else None
        frame=b.frame(timeline,f,script=script)
        if f in events:frame.set('name',events[f]);frame.set('labelType','name')
    layers.append(timeline)
    channels=['flash','hand_prop','occluded_prop','magazine','spent_magazine']
    channel_layers={k:b.node('DOMLayer',{'name':k}) for k in channels}
    for f,p in enumerate(frames):
        draws={k:[] for k in channels}
        if p['active']:
            channel='occluded_prop' if p['propBehindBody'] else 'hand_prop'
            draws[channel].append(b.instance(PREFIX+('匕首' if p['active']=='knife' else '手枪'),b.writer.mul(inv,p['prop']),True,'承托武器' if p['retained'] else '手持武器'))
        if p['magazine']:draws['magazine'].append(fixed_instance(PREFIX+'手枪弹匣',b.writer.mul(inv,p['magazine']),'新弹匣'))
        if p['spent_magazine']:
            mag=fixed_instance(PREFIX+'手枪弹匣',b.writer.mul(inv,p['spent_magazine']),'空弹匣')
            if p['spentAlpha']<1:b.node('Color',{'alphaMultiplier':str(p['spentAlpha'])},b.node('color',parent=mag))
            draws['spent_magazine'].append(mag)
        if p['flash']:
            m=b.writer.mul(p['prop'],(1,0,0,1,138.4,-34.05))
            # Flash art is unit-sized; cancel the gun asset's local scale.
            m=(*matrix(1,math.atan2(m[1],m[0]),m[4:]),)
            draws['flash'].append(fixed_instance(PREFIX+'枪口火光',b.writer.mul(inv,m)))
        for channel in channels:b.frame(channel_layers[channel],f,elements=draws[channel])
    # Native order is front to back. Left-hand shield remains behind every
    # body part; foreground glove covers the held gun/knife's grip.
    order=[i for i in s.draw_order(HS) if i not in SKIP]
    for i in reversed(order):
        field=HS[i]['field']
        if i==16:layers.extend([channel_layers['flash'],channel_layers['magazine']])
        lay=b.node('DOMLayer',{'name':field+' / '+str(i)})
        ref=PREFIX+'头部' if field=='脸型' else b.PREFIX+'部件/'+field
        for f,p in enumerate(frames):
            if i==16 and p['active']=='knife':
                hand=b.instance(PREFIX+'握刀右手',b.writer.mul(inv,p['parts'][i]),True,'肢体16')
            else:hand=fixed_instance(ref,b.writer.mul(inv,p['parts'][i]),'肢体'+str(i))
            b.frame(lay,f,elements=[hand])
        layers.append(lay)
        if i==16:layers.extend([channel_layers['hand_prop'],channel_layers['spent_magazine']])
    layers.append(channel_layers['occluded_prop'])
    shield=b.node('DOMLayer',{'name':'左手盾牌 / 全部肢体之后'})
    for f,p in enumerate(frames):
        # MovieClip wrapper preserves functional ports; the art inside is a
        # one-frame fixed shield with no dressup or transformation callbacks.
        ref=PREFIX+('盾牌' if p['supportStep']==0 else '盾牌-承托'+str(p['supportStep']))
        b.frame(shield,f,elements=[b.instance(ref,b.writer.mul(inv,p['weapon']),True,'盾具')])
    layers.append(shield)
    ground=b.node('DOMLayer',{'name':'原生接地阴影'})
    for f,p in enumerate(frames):
        sm=list(s.shadow_matrix())
        if name not in ['持盾待机','持盾冲刺']:
            sm[4]+=((p['parts'][2][4]+p['parts'][18][4])-(GUARD['parts'][2][4]+GUARD['parts'][18][4]))*.5
        b.frame(ground,f,elements=[fixed_instance(s.PREFIX+'接地阴影',b.writer.mul(inv,sm))])
    layers.append(ground)
    ref=b.symbol(PREFIX+name,layers,'前治安官动作-'+name,True)
    result=dict(name=name,linkage='前治安官动作-'+name,symbol=ref,frames=len(frames),
                events={str(k+1):v for k,v in events.items()},container=s.CONTAINER)
    if name=='持盾射击':result['segments']={
        'draw':[1,23],'fireCycle':[26,33],'shots':[f+1 for f in PISTOL_SHOTS],
        'defaultMagazine':8,'reloadEntry':86,'supportedGun':[94,113],
        'magazineInHand':[102,109],'reloadCommit':110,'stow':[122,138],
        'supportDeployment':[86,92],'supportFold':[114,122],
        'contract':'Full-magazine animation preview. Future AI may repeat fireCycle while loaded, then jump to reloadEntry; no ammo mutation or shot damage in asset scripts.'}
    return result


def build(check=False):
    actions=sequence();source_symbols()
    # Death-only prop: random choice belongs to the NPC controller, while this
    # finite native timeline collapses the shield over the existing 15 poses.
    drop=b.node('DOMLayer',{'name':'死亡落盾 / 既有变形反向'})
    for f in range(15):
        ref=one_frame(PREFIX+'落盾形态'+str(f),s.PREFIX+'枪盾变形内侧',14-f)
        for element in list(b.GENERATED[ref].findall('.//x:DOMSymbolInstance',b.NS)):
            if element.get('name') in ['装备光束','灯晕','手电口']:
                element.getparent().remove(element)
        # Centered in shield-local space. Controller copies the exact departing
        # shield matrix; scale, facing and grip do not jump at detachment.
        b.frame(drop,f,elements=[b.instance(ref,(1,0,0,1,-60,-250),False)],script='stop();')
    b.symbol(PREFIX+'落盾',[drop],export='前治安官落盾',clip=True)
    metadata=[action_symbol(name,frames) for name,frames in actions.items()]
    stale=[]
    for name,root in b.GENERATED.items():
        path=b.OWNER/'LIBRARY'/(name+'.xml')
        raw=E.tostring(root,encoding='utf-8',pretty_print=True)
        if not path.exists() or path.read_bytes()!=raw:
            stale.append(name)
            if not check:b.write_xml(path,root)
    # Exact, owned obsolete assets only. They were introduced by this module,
    # have no export IDs, and are no longer referenced by any generated frame.
    removed=[PREFIX+x for x in REMOVED_BODY_GEAR]
    if check:
        for ref in removed:
            if (b.OWNER/'LIBRARY'/(ref+'.xml')).exists():stale.append(ref)
        if stale:raise SystemExit('Stale phase-two assets: '+str(stale))
    else:
        docpath=b.OWNER/'DOMDocument.xml';doc=E.parse(str(docpath),b.PARSER).getroot()
        for include in list(doc.findall('x:symbols/x:Include',b.NS)):
            if include.get('href') in [x+'.xml' for x in removed]:include.getparent().remove(include)
        b.write_xml(docpath,doc)
        for ref in removed:
            path=b.OWNER/'LIBRARY'/(ref+'.xml')
            assert path.resolve().is_relative_to((b.OWNER/'LIBRARY'/PREFIX).resolve())
            if path.exists():path.unlink()
        for name in REMOVED_BODY_GEAR:
            path=SOURCE/(name+'.svg')
            assert path.resolve().is_relative_to(SOURCE.resolve())
            if path.exists():path.unlink()
        b.append_to_document(b.OWNER,b.GENERATED)
        anchor_path=b.OWNER/'LIBRARY/Codex专用素材.xml'
        anchor=E.parse(str(anchor_path),b.PARSER).getroot();layers=anchor.find('.//x:layers',b.NS)
        for lay in list(layers):
            if lay.get('name')=='前治安官二阶段动作':layers.remove(lay)
        layers.append(b.layer('前治安官二阶段动作',[b.instance(x['symbol'],(1,0,0,1,-3000,-3000),True) for x in metadata]))
        b.write_xml(anchor_path,anchor)
        out=b.ROOT/'tmp/former-sheriff-phase-two';out.mkdir(parents=True,exist_ok=True)
        (out/'poses.json').write_text(json.dumps(actions,ensure_ascii=False),'utf8')
        (out/'manifest.json').write_text(json.dumps(dict(actions=metadata,symbols=len(b.GENERATED),runtimeDressup=False,
            combatEnabled=False,bodyGearAdded=False,shieldOwnedFoldingSupport=True,
            source='native fixed rig; shared R36 run and R40 shadow registrations',fps=30),ensure_ascii=False,indent=2),'utf8')
    print(json.dumps(dict(actions=metadata,symbols=len(b.GENERATED),check=check),ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args();build(args.check)
