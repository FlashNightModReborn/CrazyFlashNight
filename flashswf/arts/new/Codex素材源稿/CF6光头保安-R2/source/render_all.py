"""Render every authored sequence using original recursive display-list matrices.
Nested children advance by placement age; ActionScript stop/goto not executed.
Original blank tail frames are retained and audited rather than invented.
"""
from pathlib import Path
import json,re,xml.etree.ElementTree as E,subprocess,concurrent.futures,argparse,math,hashlib
from PIL import Image
R=Path(__file__).resolve().parents[1];NS='http://www.w3.org/2000/svg'
p=argparse.ArgumentParser();p.add_argument('--keys-only',action='store_true');p.add_argument('--workers',type=int,default=6);args=p.parse_args()
T=json.loads((R/'reference/timelines.json').read_text());S={x['id']:x for x in json.loads((R/'reference/shape-manifest.json').read_text())};M=json.loads((R/'reference/manifest.json').read_text());AD={x['id']:x for x in json.loads((R/'qa/adaptation-build.json').read_text())};SEQS=[s['id'] for s in M['sequences']]
keys={(k['sequence'],k['frame']) for k in json.loads((R/'reference/keyposes.json').read_text())}
# Add articulation extremes and exact branch boundaries/blank-tail evidence.
for sid in SEQS:
 keys|={(sid,1),(sid,len(T[str(sid)]))}
keys|={(611,i) for i in [1,8,16,24,31,32,40,50,60,70,77,78,85,95,105,112]}
keys|={(887,i) for i in [1,5,10,15,20,25,30,35,40,45,50,55,60,65,70,71,75]}
IGNORE={277,280,310}|{i for i,s in S.items() if not s['fills'] and not s.get('lineStyles')}
def mm(m,n):
 a,b,c,d,x,y=m;e,f,g,h,u,v=n;return [a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y]
def flatten(cid,frame,parent=None,opacity=1,trace=''):
 if parent is None:parent=[1,0,0,1,0,0]
 if str(cid) not in T:return [(cid,parent,opacity,trace)]
 ff=T[str(cid)];fi=(frame-1)%len(ff);out=[]
 for dep,o in sorted(ff[fi].items(),key=lambda kv:int(kv[0])):
  cm=o.get('colorMult',[256]*4);ca=o.get('colorAdd',[0]*4)
  assert cm[:3]==[256]*3 and ca==[0]*4 and 'clipDepth' not in o,(cid,frame,o)
  if cm[3]==0:continue
  out+=flatten(o['id'],max(1,fi+2-o['placedAt']),mm(parent,o['matrix']),opacity*cm[3]/256,trace+f'/{cid}:{fi+1}:{dep}')
 return out
all_leaves={};views={};expected_blank=[]
for sid in SEQS:
 pts=[]
 for frame in range(1,len(T[str(sid)])+1):
  ll=flatten(sid,frame);all_leaves[(sid,frame)]=ll
  visible=[z for z in ll if z[0] not in IGNORE]
  if not visible:expected_blank.append([sid,frame])
  for cid,m,op,tr in visible:
   x,y,w,h=S[cid]['viewBox'];a,b,c,d,tx,ty=m
   pts.extend((a*xx+c*yy+tx,b*xx+d*yy+ty) for xx,yy in [(x,y),(x+w,y),(x,y+h),(x+w,y+h)])
 x=math.floor(min(a for a,b in pts))-6;y=math.floor(min(b for a,b in pts))-6;views[sid]=[x,y,math.ceil(max(a for a,b in pts))-x+6,math.ceil(max(b for a,b in pts))-y+6]
(R/'qa/render-config.json').write_text(json.dumps({'views':views,'sequences':SEQS,'keys':sorted(map(list,keys)),'expectedBlankFrames':expected_blank,'excludedTransparentOrEmptyShapes':sorted(IGNORE)},indent=2))
cache={}
for variant in ['original','candidate']:
 (R/f'qa/frames/{variant}').mkdir(parents=True,exist_ok=True)
 for cid in S:
  file=R/f'reference/{cid}.svg' if variant=='original' else R/AD[cid]['file']
  rt=E.parse(file).getroot();content=''.join(E.tostring(c,encoding='unicode') for c in rt)
  # Namespace every ID exactly, preserving references and dependency resolution.
  ids=re.findall(r'\bid="([^"]+)"',content)
  for i in sorted(ids,key=len,reverse=True):
   content=content.replace(f'id="{i}"',f'id="s{cid}_{i}"').replace(f'#{i}"',f'#s{cid}_{i}"').replace(f'#{i})',f'#s{cid}_{i})')
  cache[(variant,cid)]=content
jobs=[];records=[]
for sid in SEQS:
 for frame in range(1,len(T[str(sid)])+1):
  if args.keys_only and (sid,frame) not in keys:continue
  ll=all_leaves[(sid,frame)];visible=[x for x in ll if x[0] not in IGNORE];ids=sorted({x[0] for x in visible});record={'sequence':sid,'frame':frame,'expectedBlank':not visible,'leaves':[{'shape':c,'matrix':m,'opacity':o,'path':tr} for c,m,o,tr in visible],'files':{}}
  for v in ['candidate','original']:
   if v=='original' and (sid,frame) not in keys:continue
   vb=views[sid];defs=''.join(f'<g id="shape{i}">{cache[(v,i)]}</g>' for i in ids)
   body=''.join(f'<use href="#shape{c}" transform="matrix({",".join(map(str,m))})" opacity="{o}"/>' for c,m,o,tr in visible)
   out=f'<svg xmlns="{NS}" viewBox="{" ".join(map(str,vb))}" width="{vb[2]*3}" height="{vb[3]*3}"><defs>{defs}</defs>{body}</svg>'
   f=R/f'qa/frames/{v}/{sid}-{frame:03d}.svg';record['files'][v]=str(f.relative_to(R));changed=not f.exists() or f.read_text()!=out or not f.with_suffix('.png').exists();f.write_text(out)
   if changed:jobs.append(f)
  records.append(record)
def render(f):
 r=subprocess.run(['inkscape',str(f),'--export-filename='+str(f.with_suffix('.png'))],capture_output=True)
 if r.returncode:raise RuntimeError(str(f)+' '+r.stderr.decode()[-1000:])
 return f
print('Rendering',len(jobs),'frames; source blank frames',expected_blank,'viewports',views,flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
 for i,f in enumerate(ex.map(render,jobs),1):
  if i%60==0:print('Rendered',i,'/',len(jobs),flush=True)
checks=[]
for r in records:
 im=Image.open(R/r['files']['candidate']).convert('RGBA') if False else Image.open((R/r['files']['candidate']).with_suffix('.png')).convert('RGBA');bb=im.getbbox();expected=r['expectedBlank'];assert (bb is None)==expected,(r['sequence'],r['frame'],bb,expected)
 inside=bb is None or (bb[0]>0 and bb[1]>0 and bb[2]<im.width and bb[3]<im.height);assert inside,(r['sequence'],r['frame'],bb,im.size)
 checks.append({'sequence':r['sequence'],'frame':r['frame'],'alphaBox':bb,'expectedBlank':expected,'clearOfCanvasEdge':inside,'size':im.size})
(R/'qa/frame-coverage.json').write_text(json.dumps({'staticOnly':True,'assetHashes':{AD[i]['file']:hashlib.sha256((R/AD[i]['file']).read_bytes()).hexdigest() for i in sorted(AD)},'sourceFrames':sum(len(T[str(s)]) for s in SEQS),'renderedCandidateFrames':len(records),'originalKeyFrames':sum('original' in r['files'] for r in records),'expectedBlankFrames':expected_blank,'records':records,'checks':checks},indent=2))
print('Verified',len(records),'candidate frames including',len(expected_blank),'source blank frames.',flush=True)
