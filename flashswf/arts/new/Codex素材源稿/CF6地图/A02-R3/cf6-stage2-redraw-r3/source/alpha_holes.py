"""Preserve only meaningful original enclosed transparent openings, simplified to vector paths."""
from PIL import Image
import numpy as np
from collections import deque
def simplify(ps,eps=.65):
 if len(ps)<3:return ps
 a=np.array(ps[0]);b=np.array(ps[-1]);v=b-a;d=np.linalg.norm(v)
 ds=[np.linalg.norm(np.array(p)-a) if d==0 else abs(v[0]*(p[1]-a[1])-v[1]*(p[0]-a[0]))/d for p in ps[1:-1]]
 if not ds or max(ds)<=eps:return [ps[0],ps[-1]]
 k=int(np.argmax(ds))+1;return simplify(ps[:k+1],eps)[:-1]+simplify(ps[k:],eps)
def holes(path):
 a=np.asarray(Image.open(path).convert('RGBA'))[:,:,3]<128;h,w=a.shape;seen=set();loops=[]
 for y in range(h):
  for x in range(w):
   if not a[y,x] or (x,y) in seen:continue
   q=deque([(x,y)]);seen.add((x,y));pts=[];edge=False
   while q:
    xx,yy=q.popleft();pts.append((xx,yy));edge|=xx in (0,w-1) or yy in (0,h-1)
    for u,v in [(xx-1,yy),(xx+1,yy),(xx,yy-1),(xx,yy+1)]:
     if 0<=u<w and 0<=v<h and a[v,u] and (u,v) not in seen:seen.add((u,v));q.append((u,v))
   if edge or len(pts)<3:continue
   cells=set(pts);edges={}
   def add(a,b):edges.setdefault(a,[]).append(b)
   for xx,yy in pts:
    if (xx,yy-1) not in cells:add((xx,yy),(xx+1,yy))
    if (xx+1,yy) not in cells:add((xx+1,yy),(xx+1,yy+1))
    if (xx,yy+1) not in cells:add((xx+1,yy+1),(xx,yy+1))
    if (xx-1,yy) not in cells:add((xx,yy+1),(xx,yy))
   while edges:
    start=next(iter(edges));cur=start;ring=[start]
    while True:
     nxt=edges[cur].pop()
     if not edges[cur]:del edges[cur]
     ring.append(nxt);cur=nxt
     if cur==start:break
    # Eliminate collinear grid points; preserve actual structural holes without adding bitmap content.
    simp=[]
    for i,p in enumerate(ring[:-1]):
     prev=ring[i-1] if i else ring[-2];nex=ring[(i+1)%(len(ring)-1)]
     if (p[0]-prev[0])*(nex[1]-p[1])!=(p[1]-prev[1])*(nex[0]-p[0]):simp.append(p)
    if len(simp)>3:
     k=max(range(1,len(simp)),key=lambda i:(simp[i][0]-simp[0][0])**2+(simp[i][1]-simp[0][1])**2);simp=simplify(simp[:k+1])+simplify(simp[k:]+[simp[0]])[1:-1]
    if len(simp)>2:loops.append('M'+'L'.join(f'{x},{y}' for x,y in simp)+'Z')
 return ''.join(loops)
