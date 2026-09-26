"""Import frozen P8-H1 art and derive game-only presentation. Never alters gameplay IDs."""
import argparse,hashlib,json,math,random,zipfile
from pathlib import Path
from lib.blackiron_presentation import norm,sub,cross,dot,line_hits_rect,lines_cross
from lib.stage_camera_presets import apply_preset, check_preset, preset_manifest, refresh_preset
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'launcher/web/assets/stage-diorama/fallen-city'
DATA=ROOT/'launcher/web/modules/stage-select/stage-select-fallen-data.js'
ZIP_HASH='5ecd85d19cc5610be63cd1baae2adf94cde6cc0a6713e1118aea21a6abfce01e'
CAPTIONS=['竞赛·入门','竞赛·角斗','堕落城区','游寇基地','黑铁会','摇滚公园','革命军哨所','堕落城深处','A兵团试炼场','压制摇滚','摇滚内战','摇滚·外交','酒吧·外交','大学·外交','大学城周边','下水道入口','商业街·外交','堕落城保卫战','据点M']
def sha(b):return hashlib.sha256(b).hexdigest()
def layout(entries,c):
 forward=norm(sub(c['gltfTarget'],c['gltfPosition']));right=norm(cross(forward,[0,1,0]));up=cross(right,forward)
 pins={}
 for e in entries:
  v=sub(e['worldAnchor'],c['gltfTarget']);i=e['id'];caption=CAPTIONS[int(i.split('_')[-1])] if i.startswith('stage') else e['label']
  pins[i]={'x':512+dot(v,right)*1024/c['horizontalSpan'],'y':288-dot(v,up)*1024/c['horizontalSpan'],'labelAnchor':'ANCHOR_'+i,'building':'FOCUS_'+i,'shortLabel':caption,'labelWidth':max(116 if i.startswith('nav') else 90,len(caption)*14+20),'labelHeight':32,'labelX':0,'labelY':38}
 # Keep marker hit targets distinct without moving world identities.
 markers=[]
 for i,p in sorted(pins.items(),key=lambda row:row[1]['y']):
  if i.startswith('nav'):continue
  offsets=[(dx*dx+dy*dy,dx,dy) for dx in range(-48,49,4) for dy in range(-48,49,4) if 28<p['x']+dx<996 and 78<p['y']+dy<544 and all(abs(p['x']+dx-a)>=43 or abs(p['y']+dy-b)>=43 for a,b in markers)]
  assert offsets,'No marker room '+i
  _,dx,dy=min(offsets);p['screenOffset']=[dx,dy];p['x']+=dx;p['y']+=dy;markers.append((p['x'],p['y']))
 def overlap(a,b):return a[0]<b[2]+4 and b[0]<a[2]+4 and a[1]<b[3]+4 and b[1]<a[3]+4
 ids=list(pins);best=None;bestScore=float('inf')
 for attempt in range(12):
  order=sorted(ids,key=lambda i:sum(math.hypot(pins[i]['x']-q['x'],pins[i]['y']-q['y'])<120 for q in pins.values()),reverse=True)
  if attempt:random.Random(attempt).shuffle(order)
  occupied=[(i,(p['x']-21,p['y']-21,p['x']+21,p['y']+21)) for i,p in pins.items() if not i.startswith('nav')]+[('return',(888,480,1024,536))]
  leaders=[];chosen={};score=0
  for i in order:
   p=pins[i];start=(p['x'],p['y']);w=p['labelWidth']/2;candidates=[]
   for dy in range(-192,193,12):
    for dx in range(-216,217,12):
     x=p['x']+dx;y=p['y']+dy;r=(x-w,y-16,x+w,y+16);end=(x,y)
     if r[0]<8 or r[2]>1016 or r[1]<58 or r[3]>560 or any(overlap(r,b) for _,b in occupied):continue
     crossings=0 if i.startswith('nav') else sum(line_hits_rect(start,end,b) for key,b in occupied if key!=i)+sum(line_hits_rect(a,b,r) or lines_cross(start,end,a,b) for a,b in leaders)
     candidates.append((dx*dx+dy*dy+crossings*1000000,dx,dy,r,end))
   if not candidates:break
   cost,dx,dy,r,end=min(candidates);chosen[i]=(dx,dy);occupied.append((i,r));score+=cost
   if not i.startswith('nav'):leaders.append((start,end))
  if len(chosen)==len(ids) and score<bestScore:best=chosen;bestScore=score
 assert best,'No non-overlapping fallen-city label layout'
 for i,(dx,dy) in best.items():pins[i].update(labelX=dx,labelY=dy)
 return pins
def generate(archive):
 assert sha(archive.read_bytes())==ZIP_HASH,'Unexpected handoff ZIP'
 output={}
 with zipfile.ZipFile(archive) as z:
  prefix='P8工程/工程/';read=lambda p:z.read(prefix+p)
  for source,target in [('model/fallen-city-p8.glb','city.glb'),('model/fallen-city-p8-selection.glb','selection.glb'),('review/evidence/P8-C4.jpg','fallback.jpg'),('lighting-profile.json','lighting.json'),('reports/runtime-source-map.json','source-map.json'),('changes.json','changes.json')]:output[DEST/target]=read(source)
  for name in ['building-units.json','activity-scopes.json','selection-anchors.json','navigation-anchors.json','game-frame.snapshot.json','p8-route-plan.json']:output[DEST/name]=read('data/'+name)
  entries=json.loads(read('data/selection-anchors.json'));nav=json.loads(read('data/navigation-anchors.json'));c=json.loads(read('review/cameras.json'))['C4']
  camera={'gltfPosition':c['position'],'gltfTarget':c['target'],'horizontalSpan':c['verticalSpan']*16/9,'maxSpan':600}
  allEntries=entries+[n for n in nav if n['worldAnchor']];pins=layout(allEntries,camera)
  # Route the civil-war leader through the gap below the suppression caption.
  pins['stage_10_10']['leaderBend']=[0,42]
  config={'frameLabel':'基地车库','name':'堕落城','scene':'fallen','assetHashes':{name:sha(output[DEST/name]) for name in ['city.glb','selection.glb']},'presetKey':'cf7.stage-camera.fallen-city.p8-v1','releaseOnHide':True,'fallback':'assets/stage-diorama/fallen-city/fallback.jpg','camera':camera,'pins':pins,'fallbackPins':pins,'entries':entries,'navigation':nav,'places':json.loads(read('data/activity-scopes.json')),'lighting':json.loads(read('lighting-profile.json'))}
  apply_preset(config,'city')
  output[DATA]=('// Generated by tools/import-fallen-city-diorama.py; visual identities only.\nvar StageSelectFallenData = '+json.dumps(config,ensure_ascii=False,indent=2)+';\n').encode()
 # Canonical line endings for derived JSON; retain exact GLB/image bytes.
 output={p:(b.replace(b'\r\n',b'\n') if p.suffix=='.json' else b) for p,b in output.items()}
 manifest={'schema':1,'revision':'P8-H1-I1','sourceZipSha256':ZIP_HASH,'source':'堕落城-P8-H1-完整工程与经验-20260924.zip','changes':'Frozen GLBs preserved; JSON line endings canonical LF; shared Three r180 and postprocessing; game label layout derived. Editable blend remains in source archive.','files':[{'path':p.relative_to(ROOT).as_posix(),'bytes':len(b),'sha256':sha(b)} for p,b in output.items()]}
 manifest['cameraPreset']=preset_manifest('city')
 output[DEST/'manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode();return output
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('archive',nargs='?',type=Path);p.add_argument('--check',action='store_true');p.add_argument('--refresh-camera',action='store_true',help='Regenerate camera/labels on the verified imported assets');a=p.parse_args()
 if a.refresh_camera:refresh_preset(DATA,DEST,'city')
 if a.check:
  m=json.loads((DEST/'manifest.json').read_text('utf8'));total=0
  check_preset(DATA,m,'city')
  for r in m['files']:
   b=(ROOT/r['path']).read_bytes();assert len(b)==r['bytes'] and sha(b)==r['sha256'],r['path'];total+=len(b)
  assert total<40_000_000,'Fallen city reviewed bundle budget exceeded'
  print(json.dumps({'ok':True,'files':len(m['files']),'bytes':total}));return
 if a.refresh_camera:return
 if not a.archive:p.error('archive required')
 for path,b in generate(a.archive).items():path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b)
 print('Fallen city P8 imported')
if __name__=='__main__':main()
