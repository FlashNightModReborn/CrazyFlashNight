"""Default-skill timing and joint-preserving transitions to the actual player stance."""
import copy
import math
from lxml import etree as E

NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
DEFAULTS = {
    'vocal': (list(range(72, 98)), 4, 6),
    'keyboard': ([41, 43, 45, 47] + list(range(49, 92)), 6, 5),
    # Raise, settle overhead, then accelerate into the original slam; lighter recovery than 凶斩.
    'guitar': ([1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 22, 23] + list(range(24, 39)), 6, 5),
    'guitar-gun': ([128, 130, 132, 134, 136, 138] + list(range(139, 158)), 6, 6),
    'guitar-flame': ([25, 27, 29, 31, 33, 35] + list(range(36, 75)), 6, 6),
}

def mat(n):
    m = n.find('./x:matrix/x:Matrix', NS)
    return [float(m.get(k, d)) for k, d in zip(('a','b','c','d','tx','ty'), (1,0,0,1,0,0))]

def put(n, m):
    node = n.find('./x:matrix/x:Matrix', NS)
    node.attrib.clear()
    node.attrib.update({k: str(round(v, 9)) for k, v in zip(('a','b','c','d','tx','ty'), m)})

def mul(m, n):
    a,b,c,d,x,y=m; A,B,C,D,X,Y=n
    return [a*A+c*B,b*A+d*B,a*C+c*D,b*C+d*D,a*X+c*Y+x,b*X+d*Y+y]

def point(m, p):
    a,b,c,d,x,y=m
    return (a*p[0]+c*p[1]+x,b*p[0]+d*p[1]+y)

def inverse(m):
    a,b,c,d,x,y=m; z=a*d-b*c
    return [d/z,-b/z,-c/z,a/z,(c*y-d*x)/z,(b*x-a*y)/z]

def mix(a,b,t): return a+(b-a)*t

def angle(a,b,t): return a+((b-a+math.pi)%(2*math.pi)-math.pi)*t

def interpolate(a,b,t):
    # Preserve a full-sized weapon when the player/Boss grips use opposite handedness.
    # Interpolating the two column angles separately makes mirrored weapons collapse to a line.
    th=angle(math.atan2(a[1],a[0]),math.atan2(b[1],b[0]),t)
    sx=mix(math.hypot(a[0],a[1]),math.hypot(b[0],b[1]),t)
    sy=mix(math.hypot(a[2],a[3]),math.hypot(b[2],b[3]),t)
    selected=a if t<.5 else b
    if selected[0]*selected[3]-selected[1]*selected[2]<0: sy=-sy
    return [math.cos(th)*sx,math.sin(th)*sx,-math.sin(th)*sy,math.cos(th)*sy,
            mix(a[4],b[4],t),mix(a[5],b[5],t)]

def first_parts(path):
    root=E.parse(str(path))
    return [n for lay in root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer',NS)
            for n in lay.find('./x:frames/x:DOMFrame',NS).findall('./x:elements/x:DOMSymbolInstance',NS)]

def neutral_pose(lib,cid):
    gun=cid in ('guitar-gun','guitar-flame')
    parts=first_parts(lib/('主角动画层/长枪站立.xml' if gun else 'sprite/兵器待机.xml'))
    def take(name,number=0):
        return mat([p for p in parts if p.get('libraryItemName')=='主角肢体素材/'+name][number])
    pose={'head':take('头'),'body':take('身体'),'hips':take('屁股'),
          'mainHand':take('右手'),'offHand':take('左手'),
          'mainUpper':take('上臂',0),'offUpper':take('上臂',1),
          'mainLower':take('左下臂'),'offLower':take('左手臂'),
          'backThigh':take('右大腿'),'frontThigh':take('左大腿'),
          'backCalf':take('小腿',0),'frontCalf':take('小腿',1),
          'backFoot':take('脚',0),'frontFoot':take('脚',1)}
    holder='长枪' if gun else '刀-主手'
    pose['weapon']=mul(take(holder),mat(first_parts(lib/('主角肢体素材/'+holder+'.xml'))[0]))
    if cid=='guitar':
        # Normal melee guitar rotates/translates its animation in 吉他喷火刀枪显示控制.
        original=[-4.5340576171875,0,0,-4.5340576171875,339.3,374.45]
        normal=[0,4.5340576171875,-4.5340576171875,0,380,-180]
        pose['weapon']=mul(pose['weapon'],mul(normal,inverse(original)))
    return pose

def roles(cid):
    if cid=='vocal':
        return dict(zip(['mainHand','offHand','mainUpper','offUpper','mainLower','offLower',
                         'frontThigh','backThigh','frontCalf','backCalf','frontFoot','backFoot'],
                        ['持剑手','辅助手','持剑上臂','辅助手上臂','持剑下臂','辅助手下臂',
                         '前大腿','后大腿','前小腿','后小腿','前脚','后脚']),
                    head='头',body='躯干',hips='骨盆',weapon='rockWeapon')
    return dict(zip(['mainHand','offHand','mainUpper','offUpper','mainLower','offLower',
                     'frontThigh','backThigh','frontCalf','backCalf','frontFoot','backFoot'],
                    ['主握手','副握手','主握上臂','副握上臂','主握下臂','副握下臂',
                     '腿1-大腿','腿0-大腿','腿1-小腿','腿0-小腿','腿1-脚','腿0-脚']),
                head='头',body='躯干',hips='骨盆',weapon='rockWeapon')

def bone(origin,end,length,template):
    dx=end[0]-origin[0];dy=end[1]-origin[1]
    scale=math.hypot(template[0],template[1]); distance=max(math.hypot(dx,dy),1e-8)
    return [dy/distance*scale,-dx/distance*scale,dx/length,dy/length,*origin]

def blend_pose(nodes,neutral,t,cid):
    actual={k:mat(v) for k,v in nodes.items()}
    blended={k:interpolate(neutral[k],actual[k],t) for k in nodes}
    neutral_grip=point(neutral['mainHand'],(25,0));actual_grip=point(actual['mainHand'],(25,0))
    a=point(inverse(neutral['weapon']),neutral_grip);b=point(inverse(actual['weapon']),actual_grip)
    projected=point(blended['weapon'],(mix(a[0],b[0],t),mix(a[1],b[1],t)))
    blended['weapon'][4]+=mix(neutral_grip[0],actual_grip[0],t)-projected[0]
    blended['weapon'][5]+=mix(neutral_grip[1],actual_grip[1],t)-projected[1]
    # Both hands follow the same interpolated weapon; elbows solve the two-bone chain.
    for side in ('main','off'):
        hand=side+'Hand'; upper=side+'Upper'; lower=side+'Lower'
        a=point(inverse(neutral['weapon']),point(neutral[hand],(25,0)))
        b=point(inverse(actual['weapon']),point(actual[hand],(25,0)))
        grip=point(blended['weapon'],(mix(a[0],b[0],t),mix(a[1],b[1],t)))
        if side=='off' and cid not in ('guitar-gun','guitar-flame'):
            # The resting off-hand is free, so it releases/regrips along its own short path.
            # Rotating that free hand as a weapon-local socket stretches the arm on large scythes.
            a=point(neutral[hand],(25,0));b=point(actual[hand],(25,0))
            grip=(mix(a[0],b[0],t),mix(a[1],b[1],t))
        h=blended[hand];h[4]=grip[0]-25*h[0];h[5]=grip[1]-25*h[1]
        shoulder=blended[upper][4:6]; wrist=h[4:6]
        dx=wrist[0]-shoulder[0];dy=wrist[1]-shoulder[1];dist=max(math.hypot(dx,dy),1e-8)
        l1=95*math.hypot(blended[upper][2],blended[upper][3])
        l2=85*math.hypot(blended[lower][2],blended[lower][3])
        stretch=max(1,dist/(l1+l2-0.01));l1*=stretch;l2*=stretch
        along=max(-l1,min(l1,(l1*l1-l2*l2+dist*dist)/(2*dist)))
        height=math.sqrt(max(0,l1*l1-along*along));ux=dx/dist;uy=dy/dist
        elbows=[(shoulder[0]+along*ux-sign*height*uy,shoulder[1]+along*uy+sign*height*ux) for sign in (-1,1)]
        hint=blended[lower][4:6]
        elbow=min(elbows,key=lambda p:math.hypot(p[0]-hint[0],p[1]-hint[1]))
        blended[upper]=bone(shoulder,elbow,95,blended[upper])
        blended[lower]=bone(elbow,wrist,85,blended[lower])
    # Keep knee/ankle connections while interpolating the planted stance.
    for side in ('back','front'):
        for k,end in (('Thigh','Calf'),('Calf','Foot')):
            name=side+k
            blended[name]=bone(blended[name][4:6],blended[side+end][4:6],114,blended[name])
    for k,n in nodes.items(): put(n,blended[k] if 0<t<1 else (neutral[k] if t==0 else actual[k]))

def retime(body,fx,records,cid,lib):
    if cid not in DEFAULTS: return records,None
    selected,tail,entry=DEFAULTS[cid]
    source=[r.get('sourceFrame',r.get('frame',i+68)) for i,r in enumerate(records)]
    indices=[source.index(f) for f in selected]
    # Tail repeats the last pose without damage/events, blending to the player's stance.
    result=[copy.deepcopy(records[i]) for i in indices]
    for i in range(tail):
        r=copy.deepcopy(result[-1]);r['sourceFrame']=0;r['frame']=0;result.append(r)
    indices+= [indices[-1]]*tail
    for root in (body,fx):
        for frames in root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames',NS):
            old=list(frames);frames[:]=[]
            for at,index in enumerate(indices):
                f=next(f for f in old if int(f.get('index',0))<=index<int(f.get('index',0))+int(f.get('duration',1)))
                f=copy.deepcopy(f);f.set('index',str(at));f.set('duration','1')
                if root is fx and (at<entry-1 or at>=len(indices)-tail):
                    f.find('./x:elements',NS)[:]=[]
                frames.append(f)
    neutral=neutral_pose(lib,cid);mapping=roles(cid)
    for at in list(range(entry))+list(range(len(indices)-tail,len(indices))):
        poses={n.get('name'):n for f in body.findall('.//x:DOMFrame',NS) if int(f.get('index'))==at
               for n in f.findall('./x:elements/x:DOMSymbolInstance',NS)}
        nodes={k:poses[name] for k,name in mapping.items()}
        weight=at/(entry-1) if at<entry else (len(indices)-1-at)/tail
        weight=weight*weight*(3-2*weight)
        blend_pose(nodes,neutral,weight,cid)
    return result,{'entryFrames':entry,'recoveryFrames':tail,'firstSource':selected[0],
                   'lastSource':selected[-1],'stance':'actual player idle','handConstraint':'weapon grips + two-bone IK'}
