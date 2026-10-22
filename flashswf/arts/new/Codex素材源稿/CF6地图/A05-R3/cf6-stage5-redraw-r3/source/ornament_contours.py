"""Reference-assisted ornamental topology, not texture/noise tracing.
Coarse source pattern mask is smoothed, tiny components suppressed; outlines become editable curves.
"""
from pathlib import Path
from PIL import Image,ImageFilter
import numpy as np
R=Path(__file__).resolve().parents[1]
def simplify(pts,eps):
 if len(pts)<4:return pts
 a=np.array(pts[0]);b=np.array(pts[-1]);v=b-a;p=np.array(pts[1:-1])-a;den=np.linalg.norm(v)
 dist=np.linalg.norm(p,axis=1) if den==0 else abs(v[0]*p[:,1]-v[1]*p[:,0])/den
 k=int(dist.argmax())+1
 if dist[k-1]<eps:return [pts[0],pts[-1]]
 return simplify(pts[:k+1],eps)[:-1]+simplify(pts[k:],eps)
def make(threshold=35, color="#2c200c"):
 # 2x sampling avoids hard integer-pixel corners; native smoothing <0.4 px.
 im=Image.open(R/'reference/materials/1702.png').convert('L').crop((0,0,228,178)).resize((456,356),Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(.65))
 a=np.array(im);mask=a<threshold;h,w=mask.shape;edges={}
 def add(a,b):edges.setdefault(a,[]).append(b)
 for y,x in zip(*np.where(mask)):
  x=int(x);y=int(y)
  if y==0 or not mask[y-1,x]:add((x,y),(x+1,y))
  if x==w-1 or not mask[y,x+1]:add((x+1,y),(x+1,y+1))
  if y==h-1 or not mask[y+1,x]:add((x+1,y+1),(x,y+1))
  if x==0 or not mask[y,x-1]:add((x,y+1),(x,y))
 loops=[]
 while edges:
  start=next(iter(edges));cur=start;pts=[start]
  while True:
   nxt=edges[cur].pop()
   if not edges[cur]:del edges[cur]
   pts.append(nxt);cur=nxt
   if cur==start:break
  area=abs(sum(pts[i][0]*pts[i+1][1]-pts[i+1][0]*pts[i][1] for i in range(len(pts)-1)))/2
  if area<7:continue
  k=max(range(1,len(pts)-1),key=lambda i:(pts[i][0]-start[0])**2+(pts[i][1]-start[1])**2)
  pp=simplify(pts[:k+1],.7)+simplify(pts[k:],.7)[1:];pp=[(x/2,y/2) for x,y in pp[:-1]]
  if len(pp)<3:continue
  mids=[((pp[i][0]+pp[(i+1)%len(pp)][0])/2,(pp[i][1]+pp[(i+1)%len(pp)][1])/2) for i in range(len(pp))]
  d=f'M{mids[-1][0]:.2f} {mids[-1][1]:.2f}'
  for (x,y),(a,b) in zip(pp,mids):d+=f'Q{x:.2f} {y:.2f} {a:.2f} {b:.2f}'
  loops.append(d+'Z')
 return f'<path id="reference-calibrated-damask-{threshold}" fill="{color}" fill-rule="evenodd" d="'+''.join(loops)+'"/>'
