"""Independent 2008 static scene compositor. Does not execute ActionScript."""
from pathlib import Path
import json,re,copy,hashlib,subprocess,concurrent.futures,argparse,xml.etree.ElementTree as E
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];(R/'previews').mkdir(parents=True,exist_ok=True);NS='http://www.w3.org/2000/svg';E.register_namespace('',NS)
T=json.loads((R/'reference/timelines.json').read_text());SM={s['id']:s for s in json.loads((R/'reference/shape-manifest.json').read_text())};ROBOT=set(range(977,990));HUMAN=set(range(954,964))|{966};VIEW=[-302.45,-176.95,604.95,353.95];cache={};bitmaps={}
KEYS=[1,17,18,27,28,31,34,37,48,49,52,54,55,58,61,64,79,80,93,94,150,200,236,237,255,282,283]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def mult(m,n):
 a,b,c,d,x,y=m;e,f,g,h,u,v=n;return [a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y]
def mat(m):return 'matrix('+','.join(map(str,m))+')'
def flatten(cid,frame,parent=[1,0,0,1,0,0],colors=(),depth=0):
 assert depth<20
 if str(cid) not in T:return [(cid,parent,colors)]
 ff=T[str(cid)];fi=(frame-1)%len(ff);out=[]
 for _,o in sorted(ff[fi].items(),key=lambda kv:int(kv[0])):
  cm=o.get('colorMult',[256]*4);ca=o.get('colorAdd',[0]*4);assert 'clipDepth' not in o
  if cm[3]==0 and ca[3]==0:continue
  out+=flatten(o['id'],max(1,fi+2-o['placedAt']),mult(parent,o['matrix']),colors+((cm,ca),),depth+1)
 return out

def resources():
 root=E.parse(R/'parts/robot/977.svg').getroot();return ''.join(E.tostring(n,encoding='unicode') for n in root.find('{'+NS+'}defs'))

def readpart(variant,cid):
 key=(variant,cid)
 if key in cache:return cache[key]
 if variant=='candidate' and cid in HUMAN:
  root=E.parse(R/f'parts/human/{cid}.svg').getroot();assert not list(root.iter('{'+NS+'}image'))
 else:
  root=E.parse(R/f'reference/shapes/{cid}.svg').getroot()
  for parent in root.iter():
   for node in list(parent):
    if node.tag==f'{{{NS}}}image':
     if variant=='candidate' and cid in ROBOT:rep=E.Element(f'{{{NS}}}use',{'href':'#vectorAtlas976'})
     else:
      href=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href');bid='raster'+hashlib.sha256(href.encode()).hexdigest()[:12];im=copy.deepcopy(node);im.attrib.pop('transform',None);im.set('id',bid);bitmaps[bid]=E.tostring(im,encoding='unicode');rep=E.Element(f'{{{NS}}}use',{'href':'#'+bid})
     if node.get('transform'):rep.set('transform',node.get('transform'))
     parent.insert(list(parent).index(node),rep);parent.remove(node)
 content=''.join(E.tostring(n,encoding='unicode') for n in root)
 ids={m:f'{variant}_{cid}_{m}' for m in re.findall(r'\bid="([^"]+)"',content)}
 for old,new in ids.items():content=content.replace(f'id="{old}"',f'id="{new}"').replace(f'url(#{old})',f'url(#{new})').replace(f'href="#{old}"',f'href="#{new}"')
 cache[key]=content;return content

def writeframe(fr,variant):
 leaves=flatten(2008,fr);ids=sorted(set(c for c,_,_ in leaves));defs=''.join(f'<g id="shape{c}">{readpart(variant,c)}</g>' for c in ids);used=set(re.findall(r'href="#(raster[^\"]+)"',defs));defs=''.join(bitmaps[b] for b in sorted(used))+defs
 if variant=='candidate':defs=resources()+defs
 body=[]
 for num,(cid,m,colors) in enumerate(leaves):
  content=f'<use href="#shape{cid}"/>'
  for ci,(cm,ca) in reversed(list(enumerate(colors))):
   if cm==[256]*4 and ca==[0]*4:continue
   if cm[:3]==[256]*3 and ca==[0]*4:content=f'<g opacity="{cm[3]/256}">{content}</g>';continue
   vals=[]
   for row in range(4):vals += [cm[row]/256 if row==col else 0 for col in range(4)]+[ca[row]/255]
   fid=f'color_{num}_{ci}';defs+=f'<filter id="{fid}" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="{" ".join(map(str,vals))}"/></filter>';content=f'<g filter="url(#{fid})">{content}</g>'
  body.append(f'<g transform="{mat(m)}">{content}</g>')
 out=f'<svg xmlns="{NS}" viewBox="{" ".join(map(str,VIEW))}" width="960" height="{960*VIEW[3]/VIEW[2]}"><defs>{defs}</defs>{"".join(body)}</svg>'
 p=R/f'qa/frames/{variant}/{fr:03d}.svg';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(out);return p,leaves

def render(p):
 subprocess.run(['inkscape',str(p),'--export-filename='+str(p.with_suffix('.png'))],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE);return p

def comparison(keys,out,cols=2):
 cw,ch=960,330;board=Image.new('RGB',(cw*cols,ch*((len(keys)+cols-1)//cols)),'#ddd9cf');d=ImageDraw.Draw(board)
 for n,fr in enumerate(keys):
  x=n%cols*cw;y=n//cols*ch;d.text((x+10,y+8),f'2008 / {fr:03} | ORIGINAL / R2 | STATIC',fill='black')
  for j,var in enumerate(['original','candidate']):
   im=Image.open(R/f'qa/frames/{var}/{fr:03}.png').convert('RGBA');im.thumbnail((475,290));board.paste(im,(x+j*480,y+30),im)
 board.save(R/'previews'/out)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--key-only',action='store_true');ap.add_argument('--original-only',action='store_true');ap.add_argument('--candidate-only',action='store_true');ap.add_argument('--workers',type=int,default=4);args=ap.parse_args();frames=KEYS if args.key_only else range(1,284);jobs=[];records=[]
 for fr in frames:
  for var in (['original'] if args.original_only else (['candidate'] if args.candidate_only else ['original','candidate'])):
   p,leaves=writeframe(fr,var)
   if var!='original' or not p.with_suffix('.png').exists():jobs.append(p)
   if var=='candidate':records.append({'frame':fr,'leaves':[{'id':c,'matrix':m,'colors':col} for c,m,col in leaves],'file':str(p.relative_to(R))})
 with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
  for i,_ in enumerate(ex.map(render,jobs),1):
   if i%40==0:print('Rendered',i,'/',len(jobs),flush=True)
 if not args.original_only:
  comparison(KEYS,'keyframes-original-r2.png');comparison([17,18,27,28,48,49,54,55,79,80,93,94,236,237,282,283],'replacement-boundaries-original-r2.png')
  (R/'qa/frame-records.json').write_text(json.dumps({'scope':'Static display lists only; not AS runtime','frames':len(records),'fps':30,'stageViewBox':VIEW,'stageClipping':'Original black shape86 extent, identical viewport for both variants. No audit contact-sheet letterboxing.','records':records},indent=2))
 print('Finished scene 2008',len(list(frames)),'frames',flush=True)
if __name__=='__main__':main()
