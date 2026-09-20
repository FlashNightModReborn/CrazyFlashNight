#!/usr/bin/env python3
"""SVG paint geometry to grouped native XFL shapes.

Extends the retained studio writer with SVG arcs, isolated paint planes,
full-affine stroke expansion, clipping, curve-aware topology, and native
linearGradient fills. No bitmap or tracing path is used. Curves are
approximated within a declared tolerance.
"""
from pathlib import Path
import copy,math,re,xml.etree.ElementTree as ET
import pathops
import numpy as np
from shapely.geometry import LineString
from shapely.ops import unary_union,polygonize
from shapely import make_valid,set_precision
from . import svg_to_xfl_legacy as base

NS=base.NS;N='{'+NS+'}';S='{http://www.w3.org/2000/svg}'
E=base.E;I=base.I;mul=base.mul;point=base.point;transform=base.transform;tag=base.tag;fmt=base.fmt
SCALE=20.0
CUBIC_TOL=.0015 # input design units, at the current 20px/unit <=.03px
_CLIP_BOUNDS={}

def clip_boundary_bounds(path):
    key=id(path)
    if key in _CLIP_BOUNDS:return _CLIP_BOUNDS[key][1]
    boxes=[];current=start=None
    try:
        for op,args in path.segments:
            if op=='moveTo':current=start=args[0];continue
            if op=='closePath':points=[current,start];current=start
            elif op=='endPath':continue
            else:points=[current,*args];current=args[-1]
            points=[p for p in points if p is not None]
            if points:boxes.append((min(p[0]for p in points),min(p[1]for p in points),max(p[0]for p in points),max(p[1]for p in points)))
    except Exception:return None
    result=np.array(boxes).reshape(-1,4)
    if len(_CLIP_BOUNDS)>512:_CLIP_BOUNDS.clear()
    _CLIP_BOUNDS[key]=(path,result);return result

def polygon_region(path):
    lines=[]
    for c in path_contours(path):
        points=base.flattened(c)
        if len(points)>=3:
            if points[0]!=points[-1]:points.append(points[0])
            lines.append(LineString(points))
    candidates=polygonize(unary_union(lines));keep=[]
    for p in candidates:
        q=p.representative_point()
        if path.contains((q.x,q.y)):keep.append(p)
    return set_precision(make_valid(unary_union(keep)),.0001)

def region_path(result):
    out=pathops.Path();out.fillType=pathops.FillType.EVEN_ODD
    polys=[result]if result.geom_type=='Polygon'else[p for p in getattr(result,'geoms',[])if p.geom_type=='Polygon']
    for p in polys:
        if p.is_empty:continue
        for ring in [p.exterior,*p.interiors]:
            points=list(ring.coords);out.moveTo(*points[0])
            for q in points[1:-1]:out.lineTo(*q)
            out.close()
    return out

def safe_intersection(a,b):
    if not len(a)or not len(b):return pathops.Path(),False
    bounds=clip_boundary_bounds(b)
    if bounds is not None:
        x0,y0,x1,y1=a.bounds;e=.0001
        crosses=np.any((bounds[:,0]<=x1+e)&(bounds[:,2]>=x0-e)&(bounds[:,1]<=y1+e)&(bounds[:,3]>=y0-e))
        if not crosses:return (a if b.contains(((x0+x1)/2,(y0+y1)/2))else pathops.Path()),False
    try:return pathops.op(a,b,pathops.PathOp.INTERSECTION),False
    except pathops.PathOpsError:
        return region_path(polygon_region(a).intersection(polygon_region(b),grid_size=.0001)),True


def arc_cubics(start,rx,ry,phi,large,sweep,end):
    rx,ry=abs(rx),abs(ry)
    if rx==0 or ry==0 or start==end:return [('L',end)] if start!=end else []
    phi=math.radians(phi%360);cp,sp=math.cos(phi),math.sin(phi)
    dx,dy=(start[0]-end[0])/2,(start[1]-end[1])/2
    xx,yy=cp*dx+sp*dy,-sp*dx+cp*dy
    lam=xx*xx/(rx*rx)+yy*yy/(ry*ry)
    if lam>1:rx*=math.sqrt(lam);ry*=math.sqrt(lam)
    den=rx*rx*yy*yy+ry*ry*xx*xx
    numerator=max(0.,rx*rx*ry*ry-den)
    k=(-1 if bool(large)==bool(sweep) else 1)*math.sqrt(numerator/den) if den else 0
    xc,yc=k*rx*yy/ry,-k*ry*xx/rx
    cx=cp*xc-sp*yc+(start[0]+end[0])/2;cy=sp*xc+cp*yc+(start[1]+end[1])/2
    ux,uy=(xx-xc)/rx,(yy-yc)/ry;vx,vy=(-xx-xc)/rx,(-yy-yc)/ry
    angle=math.atan2(uy,ux);delta=math.atan2(ux*vy-uy*vx,ux*vx+uy*vy)
    if sweep and delta<0:delta+=2*math.pi
    if not sweep and delta>0:delta-=2*math.pi
    count=max(1,math.ceil(abs(delta)/(math.pi/2)));step=delta/count;out=[]
    def pos(t):return cx+cp*rx*math.cos(t)-sp*ry*math.sin(t),cy+sp*rx*math.cos(t)+cp*ry*math.sin(t)
    def tangent(t):return -cp*rx*math.sin(t)-sp*ry*math.cos(t),-sp*rx*math.sin(t)+cp*ry*math.cos(t)
    for i in range(count):
        a=angle+i*step;b=a+step;f=4/3*math.tan(step/4);p0=pos(a);p3=pos(b);d0=tangent(a);d1=tangent(b)
        p1=tuple(p0[j]+f*d0[j] for j in (0,1));p2=tuple(p3[j]-f*d1[j] for j in (0,1))
        out.extend(base.cubic_q(p0,p1,p2,p3,tol=CUBIC_TOL))
    if out:out[-1]=(*out[-1][:-1],end)
    return out


def parse_path(d):
    tokens=re.findall(r'[a-zA-Z]|'+base.NUM,d or '');i=0;cmd=None;p=(0.,0.);start=p;paths=[];segments=[];previous=None;control=None
    sizes={'M':2,'L':2,'H':1,'V':1,'Q':4,'C':6,'S':4,'T':2,'A':7}
    def flush(closed=False):
        nonlocal segments
        if segments:paths.append((start,segments,closed))
        segments=[]
    while i<len(tokens):
        if tokens[i].isalpha():cmd=tokens[i];i+=1
        if not cmd:raise ValueError('Missing SVG path command')
        op=cmd.upper();relative=cmd.islower()
        if op=='Z':
            if p!=start:segments.append(('L',start))
            p=start;flush(True);previous='Z';cmd=None;continue
        if op not in sizes:raise ValueError('Unsupported SVG path command '+op)
        count=sizes[op];v=list(map(float,tokens[i:i+count]));i+=count
        if len(v)!=count:raise ValueError('Incomplete SVG command '+op)
        def pt(j):return v[j]+(p[0] if relative else 0),v[j+1]+(p[1] if relative else 0)
        if op=='M':flush();p=pt(0);start=p;cmd='l' if relative else 'L'
        elif op=='L':p=pt(0);segments.append(('L',p))
        elif op=='H':p=(v[0]+(p[0] if relative else 0),p[1]);segments.append(('L',p))
        elif op=='V':p=(p[0],v[0]+(p[1] if relative else 0));segments.append(('L',p))
        elif op in ('Q','T'):
            q=pt(0) if op=='Q' else tuple(2*p[k]-control[k] for k in (0,1)) if previous in ('Q','T') else p
            end=pt(2 if op=='Q' else 0);segments.append(('Q',q,end));p=end;control=q
        elif op in ('C','S'):
            c1=pt(0) if op=='C' else tuple(2*p[k]-control[k] for k in (0,1)) if previous in ('C','S') else p
            c2=pt(2 if op=='C' else 0);end=pt(4 if op=='C' else 2)
            segments.extend(base.cubic_q(p,c1,c2,end,tol=CUBIC_TOL));p=end;control=c2
        elif op=='A':
            end=pt(5);segments.extend(arc_cubics(p,v[0],v[1],v[2],v[3],v[4],end));p=end
        previous=op
    flush();return paths


def primitive(node):
    if tag(node)=='path':return parse_path(node.get('d',''))
    original=base.parse_path;base.parse_path=parse_path
    try:return base.primitive(node)
    finally:base.parse_path=original


def path_from(paths,fill=False,fillrule='nonzero'):
    out=pathops.Path();out.fillType=pathops.FillType.EVEN_ODD if fillrule=='evenodd' else pathops.FillType.WINDING
    for start,segs,closed in paths:
        out.moveTo(*start)
        for seg in segs:
            if seg[0]=='L':out.lineTo(*seg[1])
            elif seg[0]=='Q':out.quadTo(*seg[1],*seg[2])
            else:raise ValueError(seg)
        if closed or fill:out.close()
    return out


def path_contours(path):
    # Skia stroke expansion creates conics; lower them before segment iteration.
    path.convertConicsToQuads(.018)
    result=[];start=None;segs=[];current=None
    def flush(closed):
        nonlocal segs
        if start is not None and segs:result.append((start,segs,closed))
        segs=[]
    for op,args in path.segments:
        if op=='moveTo':flush(False);start=current=args[0]
        elif op=='lineTo':current=args[0];segs.append(('L',current))
        elif op=='qCurveTo':
            controls=list(args[:-1]);end=args[-1]
            for i,q in enumerate(controls):
                target=base.mid(q,controls[i+1]) if i+1<len(controls) else end
                segs.append(('Q',q,target));current=target
        elif op=='curveTo':
            values=list(args)
            for i in range(0,len(values),3):
                c1,c2,end=values[i:i+3];segs.extend(base.cubic_q(current,c1,c2,end,tol=.025));current=end
        elif op=='closePath':
            if current!=start:segs.append(('L',start))
            current=start;flush(True)
        elif op=='endPath':flush(False)
        else:raise ValueError('Unknown pathops verb '+op)
    flush(False)
    return base.normalize(result,True)


def isolated_shape(path,color=None,alpha=1,paint=None):
    if not len(path):return None
    contours=path_contours(path)
    if not contours:return None
    shape=E('DOMShape');fills=E('fills',parent=shape);fill=E('FillStyle',{'index':'1'},fills)
    if paint is not None:fill.append(paint)
    else:
        attrs={'color':base.color(color)}
        if abs(alpha-1)>1e-9:attrs['alpha']=fmt(alpha)
        E('SolidColor',attrs,fill)
    edges=E('edges',parent=shape)
    for contour in contours:
        if not contour[2]:raise ValueError('A filled native outline was left open')
        E('Edge',{'edges':base.edge_string(contour),'fillStyle0':'1'},edges)
    group=E('DOMGroup');E('members',parent=group).append(shape)
    return group


def segments_bbox(paths):
    # True geometric bbox: quadratic extrema are solved, not the control hull.
    xs=[];ys=[]
    def add(p):xs.append(p[0]);ys.append(p[1])
    for start,segs,_ in paths:
        add(start);p=start
        for seg in segs:
            if seg[0]=='L':add(seg[1]);p=seg[1]
            elif seg[0]=='Q':
                q,e=seg[1],seg[2]
                for k in (0,1):
                    den=p[k]-2*q[k]+e[k]
                    if not den:continue
                    t=(p[k]-q[k])/den
                    if 0<t<1:
                        u=1-t;add((u*u*p[0]+2*u*t*q[0]+t*t*e[0],u*u*p[1]+2*u*t*q[1]+t*t*e[1]))
                add(e);p=e
            else:raise ValueError(seg)
    return min(xs),min(ys),max(xs),max(ys)


def geometry_bbox(node,paths):
    # Bounds of the ORIGINAL local geometry: unclipped, unstroked, un-transformed.
    # Primitive attributes give exact bounds (rounded corners never exceed them).
    t=tag(node);a=node.attrib;f=lambda k,d=0:float(a.get(k,d))
    if t=='circle':cx,cy,r=f('cx'),f('cy'),f('r');return cx-r,cy-r,cx+r,cy+r
    if t=='ellipse':cx,cy,rx,ry=f('cx'),f('cy'),f('rx'),f('ry');return cx-rx,cy-ry,cx+rx,cy+ry
    if t=='rect':x,y,w,h=f('x'),f('y'),f('width'),f('height');return x,y,x+w,y+h
    return segments_bbox(paths)


def fill_element(spec,alpha=1):
    if spec[0]=='solid':
        attrs={'color':base.color(spec[1])}
        if abs(alpha-1)>1e-9:attrs['alpha']=fmt(alpha)
        return E('SolidColor',attrs)
    _,lm,spread,stops=spec
    grad=E('LinearGradient',{'spreadMethod':spread})
    E('Matrix',dict(zip(('a','b','c','d','tx','ty'),map(fmt,lm))),E('matrix',parent=grad))
    for ratio,col,stop_alpha in stops:
        attrs={'color':col,'ratio':fmt(ratio)}
        al=alpha*stop_alpha
        if abs(al-1)>1e-9:attrs['alpha']=fmt(al)
        E('GradientEntry',attrs,grad)
    return grad


INHERITED={'fill','stroke','stroke-width','stroke-linecap','stroke-linejoin','stroke-miterlimit','fill-rule','fill-opacity','stroke-opacity','visibility'}
def style(node,parent=None):
    current={k:v for k,v in (parent or {}).items() if k in INHERITED}
    current.update(node.attrib)
    for part in node.get('style','').split(';'):
        if ':' in part:
            key,value=part.split(':',1);current[key.strip()]=value.strip()
    return current


class ShapeConverter:
    def __init__(self,root):
        self.root=root;self.byid={n.get('id'):n for n in root.iter() if n.get('id')}
        self.stats={'svg_primitives':0,'native_shapes':0,'stroke_outlines':0,'clipped_paints':0,'arcs':0,'skipped_empty':0,'gradient_fills':0}
        vb=base.nums(self.root.get('viewBox'))
        w=base.nums(self.root.get('width'));h=base.nums(self.root.get('height'))
        self.viewport=(vb[2],vb[3]) if len(vb)==4 else (w[0] if w else None,h[0] if h else None)
    def clip(self,identifier,matrix):
        node=self.byid[identifier]
        if node.get('clipPathUnits','userSpaceOnUse')!='userSpaceOnUse':raise ValueError('Only userSpaceOnUse clip paths in this input are supported.')
        out=pathops.Path()
        def walk(n,mat,inherited=None):
            nonlocal out
            attrs=style(n,inherited)
            mat=mul(mat,transform(n.get('transform')))
            if tag(n) in ['g','clipPath']:
                for c in n:walk(c,mat,{'clip-rule':attrs.get('clip-rule','nonzero')})
            elif tag(n) in ['path','circle','ellipse','rect','polygon','polyline']:
                p=path_from(primitive(n),True,attrs.get('clip-rule','nonzero')).transform(*mat)
                out=pathops.op(out,p,pathops.PathOp.UNION)
        walk(node,matrix);return out
    def gradient_paint(self,ident,node,paths,matrix):
        # Resolve a linearGradient into a fixed XFL paint spec. The domain is
        # decided HERE from the original local geometry, before the caller runs
        # stroke expansion, the element matrix, or boolean clipping.
        g=self.byid.get(ident)
        if g is None:raise ValueError('Paint url(#'+ident+') does not resolve in this document')
        if tag(g)=='radialGradient':raise ValueError('radialGradient fills are not supported by this converter: '+ident)
        if tag(g)!='linearGradient':raise ValueError('Paint url(#'+ident+') does not reference a linearGradient')
        if g.get('href') or g.get('{http://www.w3.org/1999/xlink}href'):raise ValueError('Gradient href inheritance is not supported; expand stops explicitly: '+ident)
        units=g.get('gradientUnits','objectBoundingBox')
        if units not in ('objectBoundingBox','userSpaceOnUse'):raise ValueError('Unsupported gradientUnits '+units)
        spread=g.get('spreadMethod','pad')
        if spread not in ('pad','reflect','repeat'):raise ValueError('Unsupported spreadMethod '+spread)
        stops=[]
        for s in g:
            if tag(s)!='stop':continue
            sa=style(s);raw=str(sa.get('offset','0')).strip()
            try:
                ratio=float(raw[:-1])/100 if raw.endswith('%') else float(raw)
                stop_alpha=float(sa.get('stop-opacity',1))
            except ValueError:raise ValueError('Unparseable stop offset or stop-opacity in gradient '+ident)
            if not math.isfinite(ratio) or not 0<=ratio<=1:raise ValueError('Stop offset must be within 0..1 in gradient '+ident)
            if stops and ratio<stops[-1][0]:raise ValueError('Stop offsets must be ordered in gradient '+ident)
            if not math.isfinite(stop_alpha) or not 0<=stop_alpha<=1:raise ValueError('stop-opacity must be within 0..1 in gradient '+ident)
            stops.append((ratio,base.color(sa.get('stop-color','#000000')),stop_alpha))
        if not 2<=len(stops)<=15:raise ValueError('linearGradient requires 2 to 15 stops, got '+str(len(stops))+' in '+ident)
        def coord(key,default,axis):
            raw=str(g.get(key,default)).strip()
            try:value=float(raw[:-1] if raw.endswith('%') else raw)
            except ValueError:raise ValueError('Unparseable gradient coordinate '+key+'='+raw)
            if not math.isfinite(value):raise ValueError('Non-finite gradient coordinate '+key)
            if raw.endswith('%'):
                if units=='objectBoundingBox':return value/100
                dim=self.viewport[0] if axis=='x' else self.viewport[1]
                if dim is None:
                    if value==0:return 0.0
                    raise ValueError('Percentage '+key+' needs an svg viewBox/width+height for userSpaceOnUse')
                return value/100*dim
            return value
        p=(coord('x1','0%','x'),coord('y1','0%','y'));q=(coord('x2','100%','x'),coord('y2','0%','y'))
        dx,dy=q[0]-p[0],q[1]-p[1]
        if math.hypot(dx,dy)==0:raise ValueError('linearGradient vector has zero length: '+ident)
        gt=transform(g.get('gradientTransform'))
        if units=='objectBoundingBox':
            bx0,by0,bx1,by1=geometry_bbox(node,paths);w,h=bx1-bx0,by1-by0
            if not all(map(math.isfinite,(bx0,by0,bx1,by1))) or w<=0 or h<=0:raise ValueError('objectBoundingBox gradient on degenerate geometry bbox: '+ident)
            gm=mul(mul(matrix,(w,0,0,h,bx0,by0)),gt)
        else:gm=mul(matrix,gt)
        # XFL linear gradients live in a square [-819.2,819.2] around the centre;
        # the inner basis maps that square's X axis onto p->q (perpendicular
        # basis vector preserved so skew/non-uniform scaling survive).
        lm=mul(gm,(dx/1638.4,dy/1638.4,-dy/1638.4,dx/1638.4,(p[0]+q[0])/2,(p[1]+q[1])/2))
        if not all(math.isfinite(v) for v in lm) or abs(lm[0]*lm[3]-lm[1]*lm[2])<1e-18:raise ValueError('linearGradient transform must be finite and non-singular: '+ident)
        return ('linear',lm,spread,stops)
    def paints(self,node,attributes,matrix,clip=None,opacity=1):
        self.stats['svg_primitives']+=1
        if tag(node)=='path':self.stats['arcs']+=len(re.findall('[Aa]',node.get('d','')))
        paths=primitive(node)
        if not paths:return []
        fill=attributes.get('fill','#000000');stroke=attributes.get('stroke','none')
        opacity*=float(attributes.get('opacity',1))
        jobs=[]
        if fill!='none':
            paint=('solid',fill)
            if fill.startswith('url('):
                match=re.fullmatch(r'url\(#([^)]*)\)',fill)
                if not match:raise ValueError('Unsupported paint reference '+fill)
                paint=self.gradient_paint(match.group(1),node,paths,matrix);self.stats['gradient_fills']+=1
            path=path_from(paths,True,attributes.get('fill-rule','nonzero'))
            jobs.append((path,paint,opacity*float(attributes.get('fill-opacity',1))))
        if stroke!='none' and float(attributes.get('stroke-width','1'))>0:
            if stroke.startswith('url('):raise ValueError('Gradient strokes are not supported; use a flat stroke colour')
            caps={'butt':pathops.LineCap.BUTT_CAP,'round':pathops.LineCap.ROUND_CAP,'square':pathops.LineCap.SQUARE_CAP}
            joins={'miter':pathops.LineJoin.MITER_JOIN,'round':pathops.LineJoin.ROUND_JOIN,'bevel':pathops.LineJoin.BEVEL_JOIN}
            path=path_from(paths)
            path.stroke(float(attributes.get('stroke-width',1)),caps[attributes.get('stroke-linecap','butt')],joins[attributes.get('stroke-linejoin','miter')],float(attributes.get('stroke-miterlimit',4)))
            path.convertConicsToQuads(CUBIC_TOL)
            self.stats['stroke_outlines']+=1
            stroke_alpha=opacity*float(attributes.get('stroke-opacity',1))
            if jobs and fill==stroke and abs(stroke_alpha-1)<1e-9 and abs(jobs[0][2]-1)<1e-9:
                try:jobs[0]=(pathops.op(jobs[0][0],path,pathops.PathOp.UNION),jobs[0][1],stroke_alpha)
                except pathops.PathOpsError:
                    # Identical opaque paint can safely remain two native vector
                    # shapes; overlapping areas have the same final colour.
                    jobs.append((path,('solid',stroke),stroke_alpha))
                    self.stats['opaque_union_split']=self.stats.get('opaque_union_split',0)+1
            else:jobs.append((path,('solid',stroke),stroke_alpha))
        result=[]
        for path,paint,alpha in jobs:
            path=path.transform(*matrix)
            path.convertConicsToQuads(.018)
            try:path=pathops.simplify(path,fix_winding=True)
            except pathops.PathOpsError:
                path=region_path(polygon_region(path))
                self.stats['simplify_polygon_fallbacks']=self.stats.get('simplify_polygon_fallbacks',0)+1
            if clip is not None:
                path,fallback=safe_intersection(path,clip);self.stats['clipped_paints']+=1
                if fallback:self.stats['boolean_polygon_fallbacks']=self.stats.get('boolean_polygon_fallbacks',0)+1
            shape=isolated_shape(path,paint=fill_element(paint,alpha))
            if shape is not None:result.append(shape);self.stats['native_shapes']+=1
            else:self.stats['skipped_empty']+=1
        return result
    def flatten(self,node,matrix=I,inherited=None,clip=None,opacity=1,force_visible=False):
        inheritable={'fill','stroke','stroke-width','fill-rule','clip-rule','fill-opacity','stroke-opacity','stroke-linecap','stroke-linejoin','stroke-miterlimit','visibility','color'}
        attrs=style(node,{k:v for k,v in (inherited or {}).items()if k in inheritable})
        if not force_visible and (attrs.get('display')=='none' or attrs.get('visibility')=='hidden'):return []
        mat=mul(matrix,transform(node.get('transform')))
        raw=attrs.get('clip-path')
        if raw:
            ident=re.fullmatch(r'url\(#([^)]*)\)',raw).group(1);own=self.clip(ident,mat)
            # G06 isolated benchmark: match Builder.smart_flat's robust clip
            # intersection. This copy is never used to rebuild the native asset.
            clip=own if clip is None else safe_intersection(clip,own)[0]
        kind=tag(node)
        if kind in ['defs','title','desc','metadata','clipPath','linearGradient','radialGradient']:return []
        if kind=='use':
            ref=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href')
            if not ref or not ref.startswith('#'):raise ValueError('Nonlocal SVG use')
            mat=mul(mat,(1,0,0,1,float(node.get('x',0)),float(node.get('y',0))))
            return self.flatten(self.byid[ref[1:]],mat,attrs,clip,opacity*float(attrs.get('opacity',1)))
        if kind in ['svg','g']:
            out=[]
            for child in node:out.extend(self.flatten(child,mat,attrs,clip,opacity*float(attrs.get('opacity',1)),force_visible))
            return out
        return self.paints(node,attrs,mat,clip,opacity)
