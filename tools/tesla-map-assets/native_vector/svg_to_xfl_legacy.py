#!/usr/bin/env python3
"""Native XFL artist-vector writer. SVG subset; no bitmap/auto-tracing dependencies.
Usage: python3 svg_to_xfl.py art.svg output_dir [--name QJZ171]
Top-level <g id> becomes graphic symbol + stage layer. Direct child <g id>
becomes named internal layer. All remaining nested groups retain paint order.
"""
from __future__ import annotations
import argparse, math, re, json, shutil
from pathlib import Path
import xml.etree.ElementTree as ET
NS='http://ns.adobe.com/xfl/2008/'
ET.register_namespace('',NS)
ET.register_namespace('xsi','http://www.w3.org/2001/XMLSchema-instance')
def E(tag,attrs=None,parent=None):
    el=ET.Element('{'+NS+'}'+tag,{k:str(v) for k,v in (attrs or {}).items()})
    if parent is not None: parent.append(el)
    return el
NUM=r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?'
def nums(s):return [float(x) for x in re.findall(NUM,s or '')]
def tag(e):return e.tag.rsplit('}',1)[-1]
def fmt(x):return f'{x:.9g}'
I=(1,0,0,1,0,0)
def mul(A,B):
    a,b,c,d,e,f=A;g,h,i,j,k,l=B
    return a*g+c*h,b*g+d*h,a*i+c*j,b*i+d*j,a*k+c*l+e,b*k+d*l+f
def point(p,m):
    x,y=p;a,b,c,d,e,f=m;return a*x+c*y+e,b*x+d*y+f
def transform(s):
    m=I
    for name,raw in re.findall(r'(\w+)\s*\(([^)]*)\)',s or ''):
        n=nums(raw)
        if name=='matrix':a=tuple(n)
        elif name=='translate':a=(1,0,0,1,n[0],n[1] if len(n)>1 else 0)
        elif name=='scale':a=(n[0],0,0,n[1] if len(n)>1 else n[0],0,0)
        elif name=='rotate':
            t=math.radians(n[0]);a=(math.cos(t),math.sin(t),-math.sin(t),math.cos(t),0,0)
            if len(n)>2:a=mul(mul((1,0,0,1,n[1],n[2]),a),(1,0,0,1,-n[1],-n[2]))
        elif name=='skewX':a=(1,0,math.tan(math.radians(n[0])),1,0,0)
        elif name=='skewY':a=(1,math.tan(math.radians(n[0])),0,1,0,0)
        else:raise ValueError('Unsupported transform '+name)
        m=mul(m,a)
    return m

def mid(a,b):return ((a[0]+b[0])/2,(a[1]+b[1])/2)
def cubic_q(p0,p1,p2,p3,tol=.06,depth=0):
    # Best endpoint tangent quadratic. Subdivide until sampled error < 0.06px.
    q=((3*(p1[0]+p2[0])-p0[0]-p3[0])/4,(3*(p1[1]+p2[1])-p0[1]-p3[1])/4)
    err=0
    for t in (.25,.5,.75):
        u=1-t
        c=tuple(u**3*p0[k]+3*u*u*t*p1[k]+3*u*t*t*p2[k]+t**3*p3[k] for k in (0,1))
        z=tuple(u*u*p0[k]+2*u*t*q[k]+t*t*p3[k] for k in (0,1))
        err=max(err,math.dist(c,z))
    if err<=tol or depth>=12:return [('Q',q,p3)]
    a,b,c=mid(p0,p1),mid(p1,p2),mid(p2,p3);d,e=mid(a,b),mid(b,c);f=mid(d,e)
    return cubic_q(p0,a,d,f,tol,depth+1)+cubic_q(f,e,c,p3,tol,depth+1)

def parse_path(d):
    ts=re.findall(r'[a-zA-Z]|'+NUM,d);i=0;cmd=None;p=(0,0);start=p;paths=[];segs=[];closed=False;prev=None;lastc=None
    def flush():
        nonlocal segs,closed
        if segs:paths.append((start,segs,closed))
        segs=[];closed=False
    count={'M':2,'L':2,'H':1,'V':1,'Q':4,'C':6,'S':4,'T':2,'Z':0}
    while i<len(ts):
        if ts[i].isalpha():cmd=ts[i];i+=1
        if cmd is None:raise ValueError('Missing path command')
        op=cmd.upper();rel=cmd.islower()
        if op not in count:raise ValueError('Unsupported path command '+cmd+' (arcs must be Q/C)')
        if op=='Z':
            if p!=start:segs.append(('L',start))
            p=start;closed=True;flush();cmd=None;prev='Z';continue
        n=count[op];v=list(map(float,ts[i:i+n]));i+=n
        def pt(j):return (v[j]+(p[0] if rel else 0),v[j+1]+(p[1] if rel else 0))
        if op=='M':flush();p=pt(0);start=p;cmd='l' if rel else 'L'
        elif op=='L':p=pt(0);segs.append(('L',p))
        elif op=='H':p=(v[0]+(p[0] if rel else 0),p[1]);segs.append(('L',p))
        elif op=='V':p=(p[0],v[0]+(p[1] if rel else 0));segs.append(('L',p))
        elif op in ('Q','T'):
            q=pt(0) if op=='Q' else ((2*p[0]-lastc[0],2*p[1]-lastc[1]) if prev in ('Q','T') else p)
            end=pt(2 if op=='Q' else 0);segs.append(('Q',q,end));p=end;lastc=q
        elif op in ('C','S'):
            c1=pt(0) if op=='C' else ((2*p[0]-lastc[0],2*p[1]-lastc[1]) if prev in ('C','S') else p)
            c2=pt(2 if op=='C' else 0);end=pt(4 if op=='C' else 2)
            segs+=cubic_q(p,c1,c2,end);p=end;lastc=c2
        prev=op
    flush();return paths

def primitive(el):
    a=el.attrib;t=tag(el);f=lambda k,d=0:float(a.get(k,d))
    if t=='path':return parse_path(a.get('d',''))
    if t in ('polyline','polygon'):
        ns=nums(a['points']);ps=list(zip(ns[::2],ns[1::2]));ss=[('L',p) for p in ps[1:]]
        if t=='polygon':ss.append(('L',ps[0]))
        return [(ps[0],ss,t=='polygon')]
    if t=='line':return [((f('x1'),f('y1')),[('L',(f('x2'),f('y2')))],False)]
    if t=='rect':
        x,y,w,h=f('x'),f('y'),f('width'),f('height');rx=min(w/2,f('rx',a.get('ry',0)));ry=min(h/2,f('ry',rx))
        if not rx or not ry:return parse_path(f'M{x} {y}h{w}v{h}h{-w}z')
        return parse_path(f'M{x+rx} {y}H{x+w-rx}Q{x+w} {y} {x+w} {y+ry}V{y+h-ry}Q{x+w} {y+h} {x+w-rx} {y+h}H{x+rx}Q{x} {y+h} {x} {y+h-ry}V{y+ry}Q{x} {y} {x+rx} {y}Z')
    if t in ('circle','ellipse'):
        x,y=f('cx'),f('cy');rx=f('r') if t=='circle' else f('rx');ry=f('r') if t=='circle' else f('ry');k=.5522847498307936
        return parse_path(f'M{x+rx} {y}C{x+rx} {y+k*ry} {x+k*rx} {y+ry} {x} {y+ry}C{x-k*rx} {y+ry} {x-rx} {y+k*ry} {x-rx} {y}C{x-rx} {y-k*ry} {x-k*rx} {y-ry} {x} {y-ry}C{x+k*rx} {y-ry} {x+rx} {y-k*ry} {x+rx} {y}Z')
    raise ValueError('Unsupported primitive '+t)

def flattened(path):
    p,segs,_=path;pts=[p]
    for s in segs:
        if s[0]=='L':pts.append(s[1])
        else:
            q,e=s[1:]
            for i in range(1,9):
                t=i/8;u=1-t;pts.append((u*u*p[0]+2*u*t*q[0]+t*t*e[0],u*u*p[1]+2*u*t*q[1]+t*t*e[1]))
        p=s[-1]
    return pts

def inside(p,poly):
    x,y=p;result=False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:result=not result
    return result

def normalize(paths,evenodd=True):
    # XFL fillStyle0 corresponds to negative signed screen area for exteriors.
    pol=[flattened(p) for p in paths];result=[]
    for i,(start,segs,closed) in enumerate(paths):
        if not closed:result.append((start,segs,closed));continue
        area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(pol[i],pol[i][1:]+pol[i][:1]))
        depth=sum(inside(pol[i][0],other) for j,other in enumerate(pol) if j!=i) if evenodd else 0
        desired=1 if depth%2 else -1
        if area*desired<0:
            starts=[start]+[s[-1] for s in segs[:-1]]
            rev=[('L',oldstart) if seg[0]=='L' else ('Q',seg[1],oldstart) for oldstart,seg in reversed(list(zip(starts,segs)))]
            result.append((segs[-1][-1],rev,closed))
        else:result.append((start,segs,closed))
    return result

def edge_string(path):
    start,segs,_=path
    def xy(p):return f'{round(round(p[0]*20,8))} {round(round(p[1]*20,8))}'
    return '!'+xy(start)+''.join('|'+xy(s[1]) if s[0]=='L' else '['+xy(s[1])+' '+xy(s[2]) for s in segs)

def style(el,parent=None):
    a=dict(parent or {});a.update(el.attrib)
    for x in el.get('style','').split(';'):
        if ':' in x:k,v=x.split(':',1);a[k.strip()]=v.strip()
    return a

def color(c):
    c=c.strip();named={'black':'#000000','white':'#FFFFFF','red':'#FF0000','blue':'#0000FF','transparent':'#000000'}
    c=named.get(c,c)
    if re.fullmatch(r'#[a-fA-F0-9]{3}',c):c='#'+''.join(x*2 for x in c[1:])
    if not re.fullmatch(r'#[a-fA-F0-9]{6}',c):raise ValueError('Use hex color: '+c)
    return c.upper()

class Writer:
    def __init__(self,svg):
        self.root=ET.parse(svg).getroot();self.grads={e.get('id'):e for e in self.root.iter() if tag(e) in ('linearGradient','radialGradient')};self.shape_count=0;self.segment_count=0
    def paint(self,parent,fill,a,m,alpha):
        match=re.fullmatch(r'url\(#([^)]*)\)',fill)
        if not match:
            attrs={'color':color(fill)}
            if alpha!=1:attrs['alpha']=fmt(alpha)
            E('SolidColor',attrs,parent);return
        g=self.grads[match[1]]
        if g.get('gradientUnits','objectBoundingBox')!='userSpaceOnUse':raise ValueError('Use gradientUnits="userSpaceOnUse"')
        gm=mul(m,transform(g.get('gradientTransform')))
        if tag(g)=='radialGradient':
            # Native radial coordinates describe a circle of radius 819.2 px.
            # Compose the FULL affine matrix so ellipticity, rotation and skew survive.
            def number(key,default=None):
                raw=g.get(key,default)
                if raw is None or not re.fullmatch(NUM,str(raw)):
                    raise ValueError('Radial gradient '+key+' must be an explicit numeric user-space value')
                value=float(raw)
                if not math.isfinite(value):raise ValueError('Non-finite radial gradient '+key)
                return value
            if g.get('href') or g.get('{http://www.w3.org/1999/xlink}href'):
                raise ValueError('Radial gradient inheritance via href is not supported; provide explicit stops')
            stops=[style(s) for s in g if tag(s)=='stop']
            if not 2<=len(stops)<=15:raise ValueError('Radial gradients require 2 to 15 explicit stops')
            previous=-1.0
            for stop in stops:
                raw=stop.get('offset','0');ratio=float(raw[:-1])/100 if raw.endswith('%') else float(raw)
                opacity=float(stop.get('stop-opacity',1))
                if not math.isfinite(ratio) or not previous<=ratio<=1 or ratio<0:
                    raise ValueError('Radial stop offsets must be ordered and within 0..1')
                if not math.isfinite(opacity) or not 0<=opacity<=1:
                    raise ValueError('Radial stop-opacity must be within 0..1')
                previous=ratio
            cx,cy,r=number('cx'),number('cy'),number('r')
            if r<=0:raise ValueError('Radial gradient r must be greater than zero')
            fx,fy,fr=number('fx',str(cx)),number('fy',str(cy)),number('fr','0')
            if not (math.isclose(fx,cx,abs_tol=1e-10) and math.isclose(fy,cy,abs_tol=1e-10)) or fr!=0:
                raise ValueError('Only centered radial gradients are supported: fx=cx, fy=cy, fr=0')
            if g.get('spreadMethod','pad')!='pad':raise ValueError('Radial gradient currently supports spreadMethod=pad only')
            if g.get('color-interpolation','sRGB')!='sRGB':raise ValueError('Radial gradient currently supports sRGB interpolation only')
            rm=mul(gm,(r/819.2,0,0,r/819.2,cx,cy))
            if not all(math.isfinite(v) for v in rm) or abs(rm[0]*rm[3]-rm[1]*rm[2])<1e-18:
                raise ValueError('Radial gradient transform must be finite and non-singular')
            grad=E('RadialGradient',{'focalPointRatio':'0'},parent);mat=E('matrix',parent=grad)
            E('Matrix',dict(zip(('a','b','c','d','tx','ty'),map(fmt,rm))),mat)
        else:
            # Preserve the full affine basis. Object-bbox gradients can be skewed
            # by non-uniform scaling; mapping just the endpoints loses that basis.
            p=(float(g.get('x1',0)),float(g.get('y1',0)));q=(float(g.get('x2',1)),float(g.get('y2',0)))
            dx,dy=q[0]-p[0],q[1]-p[1]
            lm=mul(gm,(dx/1638.4,dy/1638.4,-dy/1638.4,dx/1638.4,(p[0]+q[0])/2,(p[1]+q[1])/2))
            grad=E('LinearGradient',{'spreadMethod':g.get('spreadMethod','pad')},parent);mat=E('matrix',parent=grad)
            E('Matrix',dict(zip(('a','b','c','d','tx','ty'),map(fmt,lm))),mat)
        for s in g:
            if tag(s)!='stop':continue
            sa=style(s);v=sa.get('offset','0');ratio=float(v[:-1])/100 if v.endswith('%') else float(v)
            attrs={'color':color(sa.get('stop-color','#000000')),'ratio':fmt(ratio)}
            al=alpha*float(sa.get('stop-opacity',1))
            if al!=1:attrs['alpha']=fmt(al)
            E('GradientEntry',attrs,grad)
    def shape(self,el,a,m):
        ps=primitive(el);ps=[(point(p,m),[tuple([s[0]]+[point(q,m) for q in s[1:]]) for s in segs],closed) for p,segs,closed in ps]
        fill=a.get('fill','#000000');stroke=a.get('stroke','none');opacity=float(a.get('opacity',1))
        if not ps or (fill=='none' and stroke=='none'):return None
        # SVG filled open paths close implicitly. Stroke should stay open, so separate if needed.
        if fill!='none':
            ps=[(p,segs+([('L',p)] if not cl and segs[-1][-1]!=p else []),True) for p,segs,cl in ps]
            ps=normalize(ps,True)
        sh=E('DOMShape',{'isFloating':'true'})
        if fill!='none':
            f=E('FillStyle',{'index':'1'},E('fills',parent=sh));self.paint(f,fill,a,m,opacity*float(a.get('fill-opacity',1)))
        if stroke!='none':
            sw=float(a.get('stroke-width',1))*math.sqrt(abs(m[0]*m[3]-m[1]*m[2]));ss=E('StrokeStyle',{'index':'1'},E('strokes',parent=sh))
            s=E('SolidStroke',{'weight':fmt(sw),'scaleMode':'normal','caps':{'butt':'none','square':'square'}.get(a.get('stroke-linecap','butt'),'round'),'joints':a.get('stroke-linejoin','miter')},ss)
            self.paint(E('fill',parent=s),stroke,a,m,opacity*float(a.get('stroke-opacity',1)))
        edges=E('edges',parent=sh)
        for ps1 in ps:
            attrs={'edges':edge_string(ps1)}
            if fill!='none':attrs['fillStyle0']='1'
            if stroke!='none':attrs['strokeStyle']='1'
            E('Edge',attrs,edges);self.segment_count+=len(ps1[1])
        self.shape_count+=1;return sh
    def walk(self,el,parent_style=None,parent_matrix=I):
        a=style(el,parent_style);m=mul(parent_matrix,transform(el.get('transform')))
        if a.get('display')=='none' or a.get('visibility')=='hidden':return []
        if tag(el) in ('g','svg'):
            out=[]
            # Group opacity is inherited for non-overlapping art, not isolated compositing.
            for c in el:out+=self.walk(c,a,m)
            return out
        if tag(el) in ('defs','title','desc','metadata','linearGradient','radialGradient'):return []
        sh=self.shape(el,a,m);return [sh] if sh is not None else []
    def layer(self,name,shapes):
        layer=E('DOMLayer',{'name':name,'color':'#4FFF4F'});fr=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},E('frames',parent=layer));els=E('elements',parent=fr)
        for sh in shapes:els.append(sh)
        return layer
    def write(self,destination,name='Artwork',pivots=None,scale=1.0):
        pivots=pivots or {}
        if not math.isfinite(scale) or scale<=0:raise ValueError('scale must be finite and greater than zero')
        for key,value in pivots.items():
            if len(value)!=2 or not all(isinstance(v,(int,float)) and math.isfinite(v) for v in value):raise ValueError('pivot must be [x,y]: '+key)
        self.shape_count=0;self.segment_count=0
        out=Path(destination);(out/'LIBRARY'/'Parts').mkdir(parents=True,exist_ok=True)
        vb=nums(self.root.get('viewBox',''));w=vb[2] if vb else float(self.root.get('width',1898));h=vb[3] if vb else float(self.root.get('height',829))
        w*=scale;h*=scale
        doc=E('DOMDocument',{'width':fmt(w),'height':fmt(h),'frameRate':'24','currentTimeline':'1','xflVersion':'2.2','creatorInfo':'Adobe Animate','platform':'Macintosh','versionInfo':'Native vector art','backgroundColor':'#FFFFFF'})
        E('DOMFolderItem',{'name':'Parts'},E('folders',parent=doc));includes=E('symbols',parent=doc);tls=E('timelines',parent=doc);layers=E('layers',parent=E('DOMTimeline',{'name':name},tls))
        rootstyle=style(self.root);rootmatrix=transform(self.root.get('transform'));parts=[];part_pivots={}
        for i,group in enumerate(self.root):
            if tag(group) in ('defs','metadata','title','desc'):continue
            pn=group.get('id',f'Part_{i:02d}');safe=re.sub(r'[^\w\-]','_',pn);libname='Parts/'+safe
            px,py=pivots.get(pn,(0,0));part_pivots[pn]=[px*scale,py*scale]
            localmatrix=mul((scale,0,0,scale,-px*scale,-py*scale),rootmatrix)
            sy=E('DOMSymbolItem',{'name':libname,'symbolType':'graphic'});sl=E('layers',parent=E('DOMTimeline',{'name':pn},E('timeline',parent=sy)))
            if tag(group)=='g':
                ga=style(group,rootstyle);gm=mul(localmatrix,transform(group.get('transform')));sublayers=[];pending=[];seq=0
                for c in group:
                    if tag(c)=='g':
                        if pending:sublayers.append(self.layer(f'{seq:02d}_shapes',pending));pending=[];seq+=1
                        sublayers.append(self.layer(c.get('id',f'{seq:02d}_detail'),self.walk(c,ga,gm)));seq+=1
                    else:pending+=self.walk(c,ga,gm)
                if pending:sublayers.append(self.layer(f'{seq:02d}_shapes',pending))
                for layer in reversed(sublayers):sl.append(layer)
            else:sl.append(self.layer('Shapes',self.walk(group,rootstyle,localmatrix)))
            ET.indent(sy,space='  ');ET.ElementTree(sy).write(out/'LIBRARY'/(libname+'.xml'),encoding='utf-8',xml_declaration=True)
            E('Include',{'href':libname+'.xml','loadImmediate':'false'},includes)
            instance=E('DOMSymbolInstance',{'libraryItemName':libname,'symbolType':'graphic','loop':'loop'});E('Matrix',{'tx':fmt(px*scale),'ty':fmt(py*scale)},parent=E('matrix',parent=instance));E('Point',parent=E('transformationPoint',parent=instance))
            parts.append(self.layer(pn,[instance]))
        for layer in reversed(parts):layers.append(layer)
        ET.indent(doc,space='  ');ET.ElementTree(doc).write(out/'DOMDocument.xml',encoding='utf-8',xml_declaration=True)
        (out/(name+'.xfl')).write_text('PROXY-CS5',encoding='utf-8');(out/'mimetype').write_text('application/vnd.adobe.xfl',encoding='utf-8')
        report={'width':w,'height':h,'symbols':len(parts),'native_shapes':self.shape_count,'edge_segments':self.segment_count,'scale':scale,'pivots_output_pixels':part_pivots,'unused_pivot_ids':sorted(set(pivots)-set(part_pivots)),'entry':str((out/(name+'.xfl')).resolve())}
        (out/'conversion-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');return report

def main():
    p=argparse.ArgumentParser();p.add_argument('svg');p.add_argument('destination');p.add_argument('--name',default='Artwork');p.add_argument('--pivots',help='JSON object mapping SVG root part id to [x,y] in original SVG coordinates');p.add_argument('--scale',type=float,default=1.0);a=p.parse_args();pivots=json.loads(Path(a.pivots).read_text(encoding='utf-8')) if a.pivots else {};print(json.dumps(Writer(a.svg).write(a.destination,a.name,pivots=pivots,scale=a.scale),ensure_ascii=False,indent=2))
if __name__=='__main__':main()
