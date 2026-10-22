"""Reference-assisted contour drawing for irregular wrecks.
Raster is used at build time only as a topology guide: palette regions become closed editable paths;
small regions are suppressed and boundaries simplified. No image nodes in the deliverable.
"""
from PIL import Image,ImageFilter,ImageEnhance
from pathlib import Path
import numpy as np,math
R=Path(__file__).resolve().parents[1]
def simplify(points,eps=.42):
 if len(points)<=3:return points
 a=np.asarray(points[0],float);b=np.asarray(points[-1],float);v=b-a;den=np.linalg.norm(v)
 ps=np.asarray(points[1:-1],float);dist=np.linalg.norm(ps-a,axis=1) if den==0 else abs(v[0]*(ps[:,1]-a[1])-v[1]*(ps[:,0]-a[0]))/den
 if len(dist)==0:return points
 k=int(np.argmax(dist))+1
 if dist[k-1]<=eps:return [points[0],points[-1]]
 return simplify(points[:k+1],eps)[:-1]+simplify(points[k:],eps)
def contours(blur,colors,minarea):
 im=Image.open(R/'reference/original-1580.png').convert('RGB').crop((292,38,610,184)).filter(ImageFilter.MedianFilter(3)).filter(ImageFilter.GaussianBlur(blur))
 im=ImageEnhance.Contrast(im).enhance(1.08)
 q=im.quantize(colors=colors,method=Image.Quantize.MEDIANCUT);arr=np.asarray(q);pal=q.getpalette();h,w=arr.shape;out=[]
 for ci in range(colors):
  rgb=pal[ci*3:ci*3+3]
  if sum(rgb)<9:continue
  mask=arr==ci;edges={}
  def add(a,b):edges.setdefault(a,[]).append(b)
  ys,xs=np.where(mask)
  for y,x in zip(ys.tolist(),xs.tolist()):
   if y==0 or not mask[y-1,x]:add((x,y),(x+1,y))
   if x==w-1 or not mask[y,x+1]:add((x+1,y),(x+1,y+1))
   if y==h-1 or not mask[y+1,x]:add((x+1,y+1),(x,y+1))
   if x==0 or not mask[y,x-1]:add((x,y+1),(x,y))
  loops=[]
  while edges:
   start=next(iter(edges));curr=start;pts=[start]
   while True:
    targets=edges[curr];nxt=targets.pop();
    if not targets:del edges[curr]
    pts.append(nxt);curr=nxt
    if curr==start:break
   area=abs(sum(pts[i][0]*pts[i+1][1]-pts[i+1][0]*pts[i][1] for i in range(len(pts)-1)))/2
   if area<minarea:continue
   # Split closed ring at its farthest point so simplification does not collapse its end points.
   k=max(range(1,len(pts)-1),key=lambda i:(pts[i][0]-start[0])**2+(pts[i][1]-start[1])**2)
   pp=simplify(pts[:k+1])+simplify(pts[k:])[1:]
   loops.append('M'+' L'.join(f'{x+292},{y+38}' for x,y in pp)+'Z')
  if loops:
   # Very restrained warm lift distinguishes sheet metal from flat black without making it shiny.
   color='#'+''.join(f'{min(255,int(v*1.07)):02x}' for v in rgb)
   out.append(f'<path data-material-region="{ci}" fill="{color}" fill-rule="evenodd" d="'+''.join(loops)+'"/>')
 return ''.join(out)


# Exact-reference structural masks replace the rejected manually-offset floating frames.
def feature_mask(box,threshold,light=False):
 im=Image.open(R/'reference/original-1580.png').convert('L').crop(box).filter(ImageFilter.GaussianBlur(.35));v=np.asarray(im);mask=v>threshold if light else v<threshold;h,w=mask.shape;edges={}
 def add(a,b):edges.setdefault(a,[]).append(b)
 for y,x in zip(*np.where(mask)):
  x=int(x);y=int(y)
  if y==0 or not mask[y-1,x]:add((x,y),(x+1,y))
  if x==w-1 or not mask[y,x+1]:add((x+1,y),(x+1,y+1))
  if y==h-1 or not mask[y+1,x]:add((x+1,y+1),(x,y+1))
  if x==0 or not mask[y,x-1]:add((x,y+1),(x,y))
 paths=[]
 while edges:
  start=next(iter(edges));cur=start;pts=[start]
  while True:
   nxt=edges[cur].pop()
   if not edges[cur]:del edges[cur]
   pts.append(nxt);cur=nxt
   if cur==start:break
  area=abs(sum(pts[i][0]*pts[i+1][1]-pts[i+1][0]*pts[i][1] for i in range(len(pts)-1)))/2
  if area<3:continue
  k=max(range(1,len(pts)-1),key=lambda i:(pts[i][0]-start[0])**2+(pts[i][1]-start[1])**2)
  pp=simplify(pts[:k+1],.3)+simplify(pts[k:],.3)[1:]
  paths.append('M'+'L'.join(f'{x+box[0]},{y+box[1]}' for x,y in pp)+'Z')
 return f'<path fill="{"#8a8e80" if light else "#030907"}" opacity="{.28 if light else .72}" fill-rule="evenodd" d="'+''.join(paths)+'"/>'
def make():
 # Keep only the calibrated common silhouette and color planes; no separately positioned line drawing.
 clip='<defs><clipPath id="wreck_silhouette"><path d="M292 42L314 46L332 54L339 65L363 71L369 86L380 99L398 110L410 96L443 89L468 72L500 79L521 90L547 97L559 113L593 130L600 145L583 157L538 166L497 167L465 171L436 181L401 178L375 181L342 179L292 178Z"/></clipPath></defs>'
 base=clip+'<g id="wreck_reference_contours" clip-path="url(#wreck_silhouette)">'+contours(.55,48,0)+'</g>'
 for box,t,light in [((296,46,336,68),23,False),((302,89,369,105),24,False),((381,130,435,163),20,False),((472,112,503,151),22,False),((300,90,367,104),67,True),((326,146,359,176),80,True)]:base+=feature_mask(box,t,light)
 return '<defs><linearGradient id="wreck_contact_fade" gradientUnits="userSpaceOnUse" x1="0" y1="170" x2="0" y2="184"><stop stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient><mask id="wreck_contact_mask"><rect x="280" y="0" width="350" height="190" fill="url(#wreck_contact_fade)"/></mask></defs><g mask="url(#wreck_contact_mask)">'+base+'</g>'
