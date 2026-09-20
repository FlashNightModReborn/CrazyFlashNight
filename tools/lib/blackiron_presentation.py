"""Deterministic visual cameras and screen-space targets; no gameplay state."""
import math

def norm(v):return [x/math.sqrt(sum(a*a for a in v)) for x in v]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def dot(a,b):return sum(x*y for x,y in zip(a,b))

CAPTIONS=['翅虎堂·外围','总部边缘','翅虎堂·内部','火凤堂·外围','火凤堂·内部','黑龙堂·外围','黑龙堂·内部','总堂·外围','总堂·内部','总部遇袭','修炼场·外交']
PREFERRED=[(-104,0),(100,0),(-104,0),(-104,0),(-112,0),(112,32),(112,16),(0,-68),(-104,-8),(40,-68),(112,-40)]

def line_hits_rect(a,b,r,pad=3):
 low,high=0,1
 for axis in range(2):
  delta=b[axis]-a[axis];mn=r[axis]-pad;mx=r[axis+2]+pad
  if abs(delta)<1e-9:
   if a[axis]<mn or a[axis]>mx:return False
  else:
   start,end=sorted(((mn-a[axis])/delta,(mx-a[axis])/delta));low=max(low,start);high=min(high,end)
   if low>high:return False
 return True

def lines_cross(a,b,c,d):
 def side(p,q,r):return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
 if max(a[0],b[0])<min(c[0],d[0]) or max(c[0],d[0])<min(a[0],b[0]) or max(a[1],b[1])<min(c[1],d[1]) or max(c[1],d[1])<min(a[1],b[1]):return False
 return side(a,b,c)*side(a,b,d)<=0 and side(c,d,a)*side(c,d,b)<=0

def layout(entries,camera,order):
 span=camera['horizontalSpan'];target=camera['gltfTarget']
 forward=norm(sub(target,camera['gltfPosition']));right=norm(cross(forward,[0,1,0]));up=cross(right,forward)
 pins={}
 for e in entries:
  p=sub(e['anchor'],target);pins[e['id']]={'x':512+dot(p,right)*1024/span,'y':288-dot(p,up)*1024/span,'labelX':0,'labelY':40,'labelAnchor':e['anchorNode'],'building':e['selectionNode'],'name':e['name']}
 markers=[]
 for id in order:
  p=pins[id];candidates=[]
  for dx in range(-32,33,2):
   for dy in range(-32,33,2):
    x=p['x']+dx;y=p['y']+dy
    if all(abs(x-a)>=44 or abs(y-b)>=44 for a,b in markers):candidates.append((dx*dx+dy*dy,dx,dy))
  assert candidates,'Input targets need layout review'
  _,dx,dy=min(candidates);p['screenOffset']=[dx,dy];p['x']+=dx;p['y']+=dy;markers.append((p['x'],p['y']))
 occupied=[(id,(p['x']-22,p['y']-22,p['x']+22,p['y']+22)) for id,p in pins.items()]
 leaders=[]
 def overlap(a,b):return a[0]<b[2]+4 and b[0]<a[2]+4 and a[1]<b[3]+4 and b[1]<a[3]+4
 for index in [8,9,10,7,4,3,2,0,6,5,1]:
  id='stage_18_'+str(index);p=pins[id];candidates=[];preferred=PREFERRED[index];start=(p['x'],p['y'])
  for dy in range(-144,145,8):
   for dx in range(-200,201,8):
    x=p['x']+dx;y=p['y']+dy;r=(x-52,y-16,x+52,y+16);end=(x,y)
    if r[0]<8 or r[2]>1016 or r[1]<58 or r[3]>532 or any(overlap(r,b) for _,b in occupied):continue
    if any(line_hits_rect(start,end,b) for key,b in occupied if key!=id):continue
    if any(line_hits_rect(a,b,r) or lines_cross(start,end,a,b) for a,b in leaders):continue
    side_penalty=25000 if (preferred[0]<-60 and dx>-56) or (preferred[0]>60 and dx<56) else 0
    score=(dx-preferred[0])**2+(dy-preferred[1])**2+.15*(dx*dx+dy*dy)+side_penalty
    candidates.append((score,dx,dy,r,end))
  assert candidates,'No unambiguous label placement: '+id
  _,p['labelX'],p['labelY'],r,end=min(candidates);occupied.append((id,r));leaders.append((start,end))
  p.update(shortLabel=CAPTIONS[index],labelWidth=104,labelHeight=32)
 return pins

def build_config(interaction,views):
 old=views['overview'];order=['stage_18_'+str(i) for i in [1,0,2,3,4,5,6,7,8,9,10]]
 target=[0,20,-2];elevation=math.radians(47);yaw=math.radians(10);radius=230
 position=[target[0]+radius*math.cos(elevation)*math.sin(yaw),target[1]+radius*math.sin(elevation),target[2]+radius*math.cos(elevation)*math.cos(yaw)]
 front={'gltfPosition':position,'gltfTarget':target,'horizontalSpan':300,'maxSpan':600}
 original={'gltfPosition':old['position'],'gltfTarget':old['target'],'horizontalSpan':old['span']/1.06,'maxSpan':600}
 closer={**original,'horizontalSpan':original['horizontalSpan']/1.12}
 variants={k:{'label':label,'camera':c,'pins':layout(interaction['entries'],c,order)} for k,label,c in [('closer','原镜头·放大',closer),('original','原镜头',original),('front','正面俯视',front)]}
 return {'frameLabel':'黑铁会总部','name':'黑铁会总部','scene':'blackiron','presetKey':'cf7.stage-camera.blackiron-hq.presentation-v2','releaseOnHide':True,'fallback':'assets/stage-diorama/blackiron-hq/fallback.jpg','displayOrder':order,'camera':closer,'pins':variants['closer']['pins'],'presentationViews':variants,'defaultPresentation':'closer','fallbackPins':variants['original']['pins'],'focusCameras':{e['id']:e['focus'] for e in interaction['entries']}}
