from pathlib import Path
from copy import deepcopy
import json,re,xml.etree.ElementTree as E
B=Path(__file__).resolve().parents[1]; NS='http://www.w3.org/2000/svg';E.register_namespace('',NS)
def el(n,**kw):return E.Element('{'+NS+'}'+n,{k.replace('_','-'):str(v) for k,v in kw.items()})
T=json.loads((B/'reference/timelines.json').read_text())
S=B/'reference/baseline'
def shape(i,variant='ordinary',prefix=''):
 p=B/'parts'/f'{i}.svg' if variant in ['instructor','instructor-ct'] else Path('/nonexistent')
 if variant=='r8':
  p=B/'reference/r8/parts'/f'{i}.svg'
  if not p.exists():p=B/'reference/r8/variants'/f'{i}.svg'
 if variant=='r7':
  p=B/'reference/r7/parts'/f'{i}.svg'
  if not p.exists():p=B/'reference/r7/variants'/f'{i}.svg'
 if variant=='r5':
  p=B/'reference/r5/parts'/f'{i}.svg'
  if not p.exists():p=B/'reference/r5/variants'/f'{i}.svg'
 if variant=='r4':
  p=B/'reference/r4/parts'/f'{i}.svg'
  if not p.exists():p=B/'reference/r4/variants'/f'{i}.svg'
 if variant=='r3':
  p=B/'reference/r3/parts'/f'{i}.svg'
  if not p.exists():p=B/'reference/r3/variants'/f'{i}.svg'
 if variant=='r2':
  p=B/'reference/r2/parts'/f'{i}.svg'
  if not p.exists():p=B/'reference/r2/variants'/f'{i}.svg'
 if variant=='instructor-ct' and i==561:p=B/'reference/r1-shield/561.svg'
 if not p.exists() and variant in ['instructor','instructor-ct']:p=B/'variants'/f'{i}.svg'
 if not p.exists():
  ps=list(S.glob(f'*/parts/{i}.svg'))+list(S.glob(f'*/variants/{i}.svg'))+list(S.glob(f'*/preserved/{i}.svg'));p=ps[0] if ps else B/'reference'/f'{i}.svg'
 if not p.exists(): raise FileNotFoundError(i)
 r=E.parse(p).getroot();g=el('g')
 for c in r:g.append(deepcopy(c))
 if i==238: g[0].attrib.pop('transform',None)
 txt=E.tostring(g,encoding='unicode');ids=re.findall(r'\bid="([^"]+)"',txt)
 for id in sorted(ids,key=len,reverse=True):txt=txt.replace('id="'+id+'"','id="'+prefix+id+'"').replace('#'+id+'"','#'+prefix+id+'"').replace('#'+id+')','#'+prefix+id+')')
 return E.fromstring(txt)
def sprite(i,frame=1,variant='ordinary',prefix='s'):
 if str(i) not in T:return shape(i,variant,prefix)
 seq=T[str(i)]; idx=(frame-1)%len(seq); g=el('g')
 for depth,v in sorted(seq[idx].items(),key=lambda x:int(x[0])):
  m=v.get('matrix',[1,0,0,1,0,0]);sub=el('g',transform='matrix('+ ' '.join(map(str,m))+')'); sub.append(sprite(v['id'],idx+2-v.get('placedAt',1),variant,prefix+'d'+depth+'x'));g.append(sub)
 return g
def save(name,variant='ordinary',sid=498,frame=1,scale=4):
 r=el('svg',viewBox='-90 -85 150 170',width=150*scale,height=170*scale);r.append(sprite(sid,frame,variant));E.ElementTree(r).write(B/'art'/name,encoding='unicode')
if __name__=='__main__':
 save('ordinary-unshielded.svg')
 for i in [487,488,489,486]:
  p=list(S.glob(f'*/parts/{i}.svg'))[0];r=E.parse(p).getroot();r.set('width','600');r.set('height','600');E.ElementTree(r).write(B/'art'/f'part-{i}.svg',encoding='unicode')
