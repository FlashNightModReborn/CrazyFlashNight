"""Bounded static visual repair for CF6's repeated 1957 floor fills.

Only shape 1959 (a18), 1978 (a19), and 1986 (a20/a22) are eligible. The
caller supplies the original shape detail and current SVG inner content. All
floor placements sample one continuous lattice; their original clip coverage
is combined into one union at the first floor paint position. All non-floor content is retained verbatim. One documented
1px top-edge jog is filled in shape1959/fill16. No world transforms, clipDepth,
collision shapes, timeline frames, root layers, or runtime data are changed.

Integration in rebuild.make_shapes(), after bitmap replacements and before
write_part:
    from floor_seams import correct_floor_seams
    s, floor_audit = correct_floor_seams(a, s)
The existing material_{shape}_1957 definition must remain available to s.
"""
import re
from xml.sax.saxutils import escape

SUPPORTED={1959:16,1978:15,1986:21}
NATIVE_SIZE=(207,128)
LATTICE_X=207
LATTICE_ROW=(-28,128)

def _n(v):return ('%.6f'%v).rstrip('0').rstrip('.')

def correct_floor_seams(shape, svg_inner):
 cid=shape['id'];fills=[f for f in shape.get('fills',[]) if f.get('bitmapId')==1957]
 if not fills:return svg_inner,None
 if cid not in SUPPORTED:raise ValueError(f'Unreviewed 1957 shape {cid}')
 if len(fills)!=SUPPORTED[cid]:raise ValueError(f'Unexpected floor fill count in {cid}')
 for f in fills:
  if f['matrix'][:4]!=[1,0,0,1]:raise ValueError(f'Unreviewed floor matrix in {cid}/{f["fillIndex"]}')
 # Keep the first native source registration. The source floor polygons are
 # combined into one nonzero-winding union, removing antialias cracks at their
 # former internal borders while preserving their visible external contour.
 ox,oy=fills[0]['matrix'][4:];pid=f'floor_lattice_{cid}';material=f'material_{cid}_1957'
 vb=shape['viewBox'];x,y,w,h=vb;contours=[];corrections=[]
 for fill in fills:
  pts=[tuple(map(float,p)) for p in re.findall(r'(-?[\d.]+),(-?[\d.]+)',fill['path'])]
  if cid==1959 and fill['fillIndex']==16:
   pts=[(px,-44 if py==-43 else py) for px,py in pts]
   corrections.append({'fillIndex':16,'change':'top y -43 to -44; bottom unchanged','maxDisplacementPx':1,'reason':'isolated source 1px cross-rail step'})
  if pts[0]==pts[-1]:pts=pts[:-1]
  area=sum(p[0]*q[1]-q[0]*p[1] for p,q in zip(pts,pts[1:]+pts[:1]))
  if area<0:pts.reverse()
  contours.append('M'+'L'.join(_n(px)+' '+_n(py) for px,py in pts)+'Z')
 clipid=f'floor_union_{cid}'
 defs=f'<defs><pattern id="{pid}" patternUnits="userSpaceOnUse" width="207" height="128" patternTransform="matrix(1 0 -0.21875 1 {_n(ox)} {_n(oy)})"><g transform="matrix(1 0 0.21875 1 0 0)"><use href="#{material}"/></g></pattern><clipPath id="{clipid}"><path clip-rule="nonzero" d="'+''.join(contours)+'"/></clipPath></defs>'
 paint=f'<g clip-path="url(#{clipid})"><rect x="{_n(x-1)}" y="{_n(y-1)}" width="{_n(w+2)}" height="{_n(h+2)}" fill="url(#{pid})"/></g>'
 s=svg_inner;repaired=[]
 for f in fills:
  fi=f['fillIndex'];clip=f'c{cid}f{fi}'
  pattern=r'<g\s+clip-path="url\(#'+re.escape(clip)+r'\)"\s*>(.*?)</g>'
  matches=list(re.finditer(pattern,s,re.S))
  if len(matches)!=1:raise ValueError(f'Expected one original floor group {clip}, found {len(matches)}')
  m=matches[0]
  if '<image' not in m.group(1) and f'#{material}' not in m.group(1):raise ValueError(f'Unrecognized floor paint in {clip}')
  s=s[:m.start()]+(paint if not repaired else '')+s[m.end():]
  token=f'<clipPath id="{clip}"><path d="{f["path"]}"/></clipPath>'
  if s.count(token)!=1:raise ValueError(f'Original floor clip not found verbatim: {clip}')
  s=s.replace(token,'');repaired.append(fi)
 audit={'shape':cid,'bitmap':1957,'rephasedFillIndices':repaired,'phaseOrigin':[ox,oy],
        'canvas':[207,128],'latticeVectors':[[207,0],[-28,128]],
        'geometryCorrections':corrections,'originalFloorCoverageUnion':True,
        'nonFloorClipsAndContentUnchanged':True,'worldAndTimelineUnchanged':True,
        'method':'single periodic phase inside exact floor-polygon union; interior clip cracks removed'}
 return defs+s,audit
