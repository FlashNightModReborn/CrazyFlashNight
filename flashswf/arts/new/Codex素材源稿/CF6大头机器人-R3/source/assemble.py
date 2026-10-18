"""Faithful static display-list compositor. Does not execute Flash/AS or game."""
from pathlib import Path
import json,re,copy,hashlib,subprocess,concurrent.futures,argparse,xml.etree.ElementTree as E
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];NS='http://www.w3.org/2000/svg';E.register_namespace('',NS)
T=json.loads((R/'reference/timelines.json').read_text());SM={s['id']:s for s in json.loads((R/'reference/shape-manifest.json').read_text())}
NAMES={933:'stand-walk',936:'attack1',937:'attack2',938:'hit',951:'death'};HELPERS={277,280,285,310};NEW=set(range(928,933))|set(range(941,951));cache={};bitmaps={}
def mult(m,n):
 a,b,c,d,x,y=m;e,f,g,h,u,v=n;return [a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y]
def mat(m):return 'matrix('+','.join(map(str,m))+')'
def flatten(cid,frame,parent=[1,0,0,1,0,0],colors=(),depth=0):
 assert depth<20
 if str(cid) not in T:return [(cid,parent,colors)]
 ff=T[str(cid)];fi=(frame-1)%len(ff);out=[]
 for _,o in sorted(ff[fi].items(),key=lambda kv:int(kv[0])):
  cm=o.get('colorMult',[256]*4);ca=o.get('colorAdd',[0]*4)
  assert 'clipDepth' not in o,('Unsupported mask',cid,frame,o)
  if cm[3]==0 and ca[3]==0:continue
  out+=flatten(o['id'],max(1,fi+2-o['placedAt']),mult(parent,o['matrix']),colors+((cm,ca),),depth+1)
 return out
# Load one reusable atlas from a final standalone piece; all part pieces refer to it.
def candidate_resources():
 root=E.parse(R/'parts/929.svg').getroot();defs=root.find('{'+NS+'}defs')
 resource=''.join(E.tostring(n,encoding='unicode') for n in defs)
 return resource
CRES=candidate_resources()
def readpart(variant,cid):
 key=(variant,cid)
 if key in cache:return cache[key]
 root=E.parse(R/(f'parts/{cid}.svg' if variant=='candidate' and cid in NEW else f'reference/shapes/{cid}.svg')).getroot()
 if variant=='candidate' and cid in NEW:
  for node in list(root):
   if node.tag==f'{{{NS}}}defs':root.remove(node)
 for parent in root.iter():
  for node in list(parent):
   if node.tag==f'{{{NS}}}image':
    if variant=='candidate' and cid in NEW:
     replacement=E.Element(f'{{{NS}}}use',{'href':'#vectorAtlas927'})
    else:
     href=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href');bid='raster'+hashlib.sha256(href.encode()).hexdigest()[:12]
     bitmap=copy.deepcopy(node);bitmap.attrib.pop('transform',None);bitmap.set('id',bid);bitmaps[bid]=E.tostring(bitmap,encoding='unicode');replacement=E.Element(f'{{{NS}}}use',{'href':'#'+bid})
    if node.get('transform'):replacement.set('transform',node.get('transform'))
    parent.insert(list(parent).index(node),replacement);parent.remove(node)
 content=''.join(E.tostring(n,encoding='unicode') for n in root)
 idmap={m:f'{variant}_{cid}_{m}' for m in re.findall(r'\bid="([^"]+)"',content)}
 for old,new in idmap.items():content=content.replace(f'id="{old}"',f'id="{new}"').replace(f'url(#{old})',f'url(#{new})').replace(f'href="#{old}"',f'href="#{new}"')
 cache[key]=content;return content

def viewport(leaves):
 pts=[]
 for cid,m,colors in leaves:
  if cid in HELPERS:continue
  x,y,w,h=SM[cid]['viewBox'];a,b,c,d,tx,ty=m;pts.extend((a*xx+c*yy+tx,b*xx+d*yy+ty) for xx,yy in [(x,y),(x+w,y),(x,y+h),(x+w,y+h)])
 if not pts:return [-10,-10,20,20]
 x=min(p[0] for p in pts)-6;y=min(p[1] for p in pts)-6;return [x,y,max(p[0] for p in pts)-x+6,max(p[1] for p in pts)-y+6]
def view_for(seq,body_only=False):
 leaves=[]
 for f in range(1,len(T[str(seq)])+1):
  leaves+= [v for v in flatten(seq,f) if not body_only or v[0] in NEW|{939,940,926}]
 return viewport(leaves)

def writeframe(seq,fr,variant,view,scale=3,body_only=False):
 leaves=flatten(seq,fr)
 if body_only:leaves=[v for v in leaves if v[0] in NEW|{939,940,926}]
 ids=sorted(set(c for c,_,_ in leaves if c not in HELPERS));definitions=''.join(f'<g id="shape{c}">{readpart(variant,c)}</g>' for c in ids)
 # Only bitmaps actually referenced by these definitions.
 used=set(re.findall(r'href="#(raster[^\"]+)"',definitions));definitions=''.join(bitmaps[b] for b in sorted(used))+definitions
 definitions=(CRES if variant=='candidate' else '')+definitions;body=[]
 for num,(cid,m,colors) in enumerate(leaves):
  if cid in HELPERS:continue
  content=f'<use href="#shape{cid}"/>'
  for ci,(cm,ca) in reversed(list(enumerate(colors))):
   if cm==[256]*4 and ca==[0]*4:continue
   if cm[:3]==[256]*3 and ca==[0]*4:
    content=f'<g opacity="{cm[3]/256}">{content}</g>';continue
   vals=[]
   for row in range(4):vals += [cm[row]/256 if row==col else 0 for col in range(4)]+[ca[row]/255]
   fid=f'color_{num}_{ci}'
   definitions+=f'<filter id="{fid}" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="{" ".join(map(str,vals))}"/></filter>'
   content=f'<g filter="url(#{fid})">{content}</g>'
  body.append(f'<g transform="{mat(m)}">{content}</g>')
 out=f'<svg xmlns="{NS}" viewBox="{" ".join(map(str,view))}" width="{view[2]*scale}" height="{view[3]*scale}"><defs>{definitions}</defs>{"".join(body)}</svg>'
 folder='body-only' if body_only else 'frames';p=R/f'qa/{folder}/{variant}/{NAMES[seq]}-{fr:03d}.svg';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(out);return p,leaves

def render(p):
 subprocess.run(['inkscape',str(p),'--export-filename='+str(p.with_suffix('.png'))],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 return p

def comparison(keys,out,columns=3,cell=(560,500),body_only=False):
 folder='body-only' if body_only else 'frames';board=Image.new('RGB',(cell[0]*columns,cell[1]*((len(keys)+columns-1)//columns)),'#e8e6dc');d=ImageDraw.Draw(board)
 for n,(seq,fr) in enumerate(keys):
  x=n%columns*cell[0];y=n//columns*cell[1];d.text((x+10,y+8),f'{NAMES[seq]} {fr:03d} | ORIGINAL / R3',fill='#202820')
  ims=[Image.open(R/f'qa/{folder}/{v}/{NAMES[seq]}-{fr:03d}.png').convert('RGBA') for v in ('original','candidate')];bbs=[im.getbbox() for im in ims if im.getbbox()]
  if not bbs:continue
  box=(min(b[0] for b in bbs),min(b[1] for b in bbs),max(b[2] for b in bbs),max(b[3] for b in bbs))
  for j,im in enumerate(ims):
   im=im.crop(box);sc=min((cell[0]//2-18)/im.width,(cell[1]-35)/im.height);im=im.resize((round(im.width*sc),round(im.height*sc)),Image.Resampling.LANCZOS);board.paste(im,(x+j*cell[0]//2+(cell[0]//2-im.width)//2,y+30+(cell[1]-35-im.height)//2),im)
 board.save(R/'previews'/out)

def partpreviews():
 jobs=[]
 for sid in [928,929,930,931,932,939,940]+list(range(941,951)):
  p=R/f'parts/{sid}.svg';jobs.append(p)
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:list(ex.map(render,jobs))
 for sid in [928,929,930,931,932,939,940]+list(range(941,951)):
  a=R/f'reference/shapes/{sid}.svg'
  if not a.with_suffix('.png').exists():render(a)
 for label,ids,cell,cols in [('body',[929],(1140,900),1),('weapon',[928],(1000,270),1),('small-parts',[930,931,932,939,940],(800,300),1),('fragments',list(range(941,951)),(750,350),2)]:
  board=Image.new('RGB',(cell[0]*cols,cell[1]*((len(ids)+cols-1)//cols)),'#e6e4db');draw=ImageDraw.Draw(board)
  for idx,sid in enumerate(ids):
   x=idx%cols*cell[0];y=idx//cols*cell[1];draw.text((x+10,y+8),f'{sid} | ORIGINAL / R3',fill='black')
   aa=Image.open(R/f'reference/shapes/{sid}.png').convert('RGBA');bb=Image.open(R/f'parts/{sid}.png').convert('RGBA')
   factor=min((cell[0]//2-20)/aa.width,(cell[1]-45)/aa.height)
   for j,im in enumerate([aa,bb]):
    im=im.resize((round(im.width*factor),round(im.height*factor)),Image.Resampling.LANCZOS);board.paste(im,(x+j*cell[0]//2+(cell[0]//2-im.width)//2,y+35+(cell[1]-40-im.height)//2),im)
  board.save(R/f'previews/{label}-original-r2.png')
 a=Image.open(R/'reference/shapes/929.png').convert('RGBA').crop((195,200,465,455));b=Image.open(R/'parts/929.png').convert('RGBA').crop((195,200,465,455));board=Image.new('RGB',(1110,550),'#e6e4db');draw=ImageDraw.Draw(board);draw.text((10,8),'FACE 2x | ORIGINAL / R3',fill='black')
 for j,im in enumerate([a,b]):
  im=im.resize((540,510));board.paste(im,(j*560,30),im)
 board.save(R/'previews/face-original-r2.png')

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--stand-only',action='store_true');ap.add_argument('--parts',action='store_true');ap.add_argument('--workers',type=int,default=3);a=ap.parse_args()
 if not a.stand_only:raise SystemExit('This R3 local capsule supports --stand-only; full animation assets are intentionally not included.')
 if a.parts:partpreviews()
 seqs=[933] if a.stand_only else list(NAMES);keys={(k['sequence'],k['frame']) for k in json.loads((R/'reference/keyposes.json').read_text())};keys.add((933,1));jobs=[];records=[];views={seq:view_for(seq) for seq in seqs}
 for seq in seqs:
  for fr in ([1] if a.stand_only else range(1,len(T[str(seq)])+1)):
   for variant in ('candidate','original'):
    # All candidate and all original frames support final alpha QA.
    p,leaves=writeframe(seq,fr,variant,views[seq]);
    if variant=='candidate' or not p.with_suffix('.png').exists():jobs.append(p)
    if variant=='candidate':records.append({'sequence':seq,'frame':fr,'file':str(p.relative_to(R)),'leaves':[{'id':c,'matrix':m,'colorTransforms':colors} for c,m,colors in leaves],'excludedHelpers':sorted(set(c for c,_,_ in leaves if c in HELPERS))})
 if not a.stand_only:
  bv=view_for(951,True)
  for fr in range(1,len(T['951'])+1):
   for variant in ('candidate','original'):
    p,_=writeframe(951,fr,variant,bv,body_only=True)
    if variant=='candidate' or not p.with_suffix('.png').exists():jobs.append(p)
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex:
  for n,_ in enumerate(ex.map(render,jobs),1):
   if n%40==0:print(f'Rendered {n}/{len(jobs)}',flush=True)
 checks=[]
 for r in records:
  p=R/r['file'];im=Image.open(p.with_suffix('.png')).convert('RGBA');bb=im.getbbox();clear=not bb or (bb[0]>0 and bb[1]>0 and bb[2]<im.width and bb[3]<im.height)
  checks.append({'sequence':r['sequence'],'frame':r['frame'],'size':im.size,'alphaBox':bb,'clearOfCanvasEdge':clear,'svgSha256':hashlib.sha256(p.read_bytes()).hexdigest(),'pngSha256':hashlib.sha256(p.with_suffix('.png').read_bytes()).hexdigest()})
 assert all(c['clearOfCanvasEdge'] for c in checks)
 report={'scope':'Static decoded display-list reconstruction only, no SWF/AS/EXE, CS6 or runtime gameplay validation','candidateFrames':len(records),'originalFrames':len(records),'viewBoxes':views,'nonempty':sum(bool(c['alphaBox']) for c in checks),'checks':checks,'records':records}
 (R/'qa/frame-coverage.json').write_text(json.dumps(report,indent=2))
 comparison([(933,1)],'stand-original-r3.png',1,(1100,700))
 if not a.stand_only:
  comparison(sorted(k for k in keys if k[0]!=951),'live-actions-original-r2.png',4)
  comparison(sorted(k for k in keys if k[0]==951),'death-original-r2.png',3)
  comparison([(951,k) for k in [1,7,14,20,26,33,39,45,52,58]],'death-body-original-r2.png',2,body_only=True)
 print('Assembled',len(records),'candidate frames; all clear of fixed per-sequence viewport edges.',flush=True)
if __name__=='__main__':main()
