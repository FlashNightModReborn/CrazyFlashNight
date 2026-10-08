"""Bind writer to the imported svg_to_xfl_legacy module; then assign
writer.normalize = stable_normalize before converting a clipped source.
This fixes containment classification at shared clipping boundaries.
"""
import math

writer = None  # set by the assembly caller

def stable_normalize(paths,evenodd=True):
    """A clipped hole may share its first vertex with the exterior crop edge.
    Test nesting at a point just inside an edge, rather than on that vertex.
    This scratch adapter avoids converting a narrow open gap to a black wedge.
    It does not modify the repository converter or the SVG drawing authority.
    """
    polys=[writer.flattened(p) for p in paths];result=[]
    for i,(start,segs,closed) in enumerate(paths):
        if not closed:result.append((start,segs,closed));continue
        poly=polys[i]
        area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))
        sample=poly[0]
        for a,b in zip(poly,poly[1:]+poly[:1]):
            dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
            if length<1e-6:continue
            sign=1 if area>0 else -1
            step=min(1e-4,length*1e-3)
            candidate=((a[0]+b[0])/2-sign*dy/length*step,(a[1]+b[1])/2+sign*dx/length*step)
            if writer.inside(candidate,poly):sample=candidate;break
        depth=sum(writer.inside(sample,other) for j,other in enumerate(polys) if j!=i) if evenodd else 0
        desired=1 if depth%2 else -1
        if area*desired<0:
            starts=[start]+[s[-1] for s in segs[:-1]]
            reverse=[('L',p) if s[0]=='L' else ('Q',s[1],p) for p,s in reversed(list(zip(starts,segs)))]
            result.append((segs[-1][-1],reverse,closed))
        else:result.append((start,segs,closed))
    return result
