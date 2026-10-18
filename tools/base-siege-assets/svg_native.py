"""SVG vector groups to editable XFL, preserving affine transforms and gradients.

Only the finite, checked source vocabulary is accepted. Unknown artwork fails.
"""
import math, re, copy
from lxml import etree as E
from fontTools.svgLib.path import parse_path
from fontTools.pens.basePen import BasePen

URI='http://ns.adobe.com/xfl/2008/'
NS={'x':URI}
def tag(n):return '{'+URI+'}'+n
def sub(e,n,**attrs):return E.SubElement(e,tag(n),{k:str(v) for k,v in attrs.items()})
def ident():return (1.,0.,0.,1.,0.,0.)
def mul(a,b):
    return (a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5])
def transform(s):
    out=ident()
    for kind,nums in re.findall(r'([A-Za-z]+)\(([^)]+)\)',s or ''):
        v=list(map(float,re.findall(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?',nums)))
        if kind=='matrix':m=tuple(v)
        elif kind=='translate':m=(1,0,0,1,v[0],v[1] if len(v)>1 else 0)
        elif kind=='scale':m=(v[0],0,0,v[1] if len(v)>1 else v[0],0,0)
        elif kind=='rotate':
            c=math.cos(math.radians(v[0]));s=math.sin(math.radians(v[0]));m=(c,s,-s,c,0,0)
            if len(v)>1:m=mul(mul((1,0,0,1,v[1],v[2]),m),(1,0,0,1,-v[1],-v[2]))
        else:raise ValueError('unsupported transform '+kind)
        out=mul(out,m)
    return out
def matrix(e,m):sub(sub(e,'matrix'),'Matrix',**dict(zip(['a','b','c','d','tx','ty'],[round(v,8) for v in m])))
def inst(name,m=None,**attrs):
    e=E.Element(tag('DOMSymbolInstance'),libraryItemName=name,symbolType='graphic',loop='single frame',firstFrame='0',**attrs)
    matrix(e,m or ident());return e
def layer(name,els,index=0,**attrs):
    e=E.Element(tag('DOMLayer'),name=name,**attrs);f=sub(sub(e,'frames'),'DOMFrame',index=index,duration=1,keyMode=9728)
    sub(f,'elements').extend(els);return e
def symbol(name,layers):
    e=E.Element(tag('DOMSymbolItem'),nsmap={None:URI},name=name,symbolType='graphic')
    sub(sub(sub(e,'timeline'),'DOMTimeline',name=name.rsplit('/',1)[-1]),'layers').extend(layers);return e

class Pen(BasePen):
    def __init__(self):super().__init__(None);self.edges=[];self.pos=None
    def point(self,p):return '%d %d'%(round(p[0]*20),round(p[1]*20))
    def _moveTo(self,p):self.edges.append('!'+self.point(p));self.pos=p
    def _lineTo(self,p):self.edges.append('|'+self.point(p));self.pos=p
    def _qCurveToOne(self,p1,p2):self.edges.append('['+self.point(p1)+' '+self.point(p2));self.pos=p2
    def _curveToOne(self,p1,p2,p3):
        p0=self.pos
        # Cubic segments are small in the selected sources. <=0.15px chord budget.
        length=sum(math.dist(a,b) for a,b in [(p0,p1),(p1,p2),(p2,p3)])
        count=max(4,min(160,math.ceil(length/1.5)))
        for i in range(1,count+1):
            t=i/count;u=1-t;self._lineTo((u*u*u*p0[0]+3*u*u*t*p1[0]+3*u*t*t*p2[0]+t*t*t*p3[0],u*u*u*p0[1]+3*u*u*t*p1[1]+3*u*t*t*p2[1]+t*t*t*p3[1]))
    def _closePath(self):pass
    def _endPath(self):pass

class Converter:
    def __init__(self,source,prefix):
        self.defs={e.get('id'):e for e in source.iter() if e.get('id')};self.prefix=prefix;self.symbols={};self.serial=0
    def paint(self,parent,color,alpha):
        if color.startswith('url('):
            g=self.defs[color[5:-1]];kind=g.tag.rsplit('}',1)[-1]
            if g.get('gradientUnits')!='userSpaceOnUse':raise ValueError('gradient units')
            ge=sub(parent,'LinearGradient' if kind=='linearGradient' else 'RadialGradient',spreadMethod='extend',interpolationMethod='rgb')
            gm=transform(g.get('gradientTransform'))
            if kind=='linearGradient':
                x1,y1,x2,y2=[float(g.get(k,0)) for k in ['x1','y1','x2','y2']]
                gm=mul(gm,((x2-x1)/1638.4,(y2-y1)/1638.4,-(y2-y1)/1638.4,(x2-x1)/1638.4,(x1+x2)/2,(y1+y2)/2))
            elif kind=='radialGradient':
                radius=float(g.get('r'));gm=mul(gm,(radius/819.2,0,0,radius/819.2,float(g.get('cx',0)),float(g.get('cy',0))))
            else:raise ValueError(kind)
            matrix(ge,gm)
            for stop in g:
                sub(ge,'GradientEntry',color=stop.get('stop-color'),ratio=stop.get('offset'),alpha=float(stop.get('stop-opacity',1))*alpha)
        else:
            color={'black':'#000000','white':'#FFFFFF'}.get(color,color)
            if len(color)==4:color='#'+''.join(x*2 for x in color[1:])
            if not re.fullmatch('#[0-9a-fA-F]{6}',color):raise ValueError('color '+color)
            sub(parent,'SolidColor',color=color,alpha=alpha)
    def draw(self,el,m=None,style=None,alpha=1,ignore_clip=False):
        kind=el.tag.rsplit('}',1)[-1]
        if kind in ['defs','metadata','title','desc']:return []
        if kind not in ['g','svg','path','ellipse','circle','rect','line','polygon','polyline','clipPath']:raise ValueError('unsupported SVG '+kind)
        m=mul(m or ident(),transform(el.get('transform')));style=dict(style or {'fill':'black','stroke':'none','stroke-width':'1'})
        for k in ['fill','stroke','stroke-width','fill-opacity','stroke-opacity','stroke-linecap','stroke-linejoin']:
            if el.get(k)!=None:style[k]=el.get(k)
        alpha*=float(el.get('opacity',1))
        for k in ['filter','mask']:
            if el.get(k):raise ValueError('unsupported '+k)
        if el.get('clip-path') and not ignore_clip:
            self.serial+=1;name=self.prefix+'/clip%03d'%self.serial
            clip=self.defs[el.get('clip-path')[5:-1]]
            local=copy.deepcopy(el);local.attrib.pop('transform',None);local.attrib.pop('opacity',None)
            art=self.draw(local,m=ident(),style=style,alpha=alpha,ignore_clip=True)
            # Clip and content share this element's parent coordinate system.
            masked=symbol(name,[layer('mask',sum([self.draw(z,ident(),{'fill':'#FFFFFF','stroke':'none'}) for z in clip],[]),layerType='mask',locked='true'),layer('art',art,parentLayerIndex='0',locked='true')])
            self.symbols[name]=masked
            return [inst(name,m)]
        if kind in ['g','svg','clipPath']:
            out=[]
            for ch in el:out.extend(self.draw(ch,m,style,alpha))
            return out
        if kind=='path':d=el.get('d')
        elif kind=='rect':
            x,y,w,h=[float(el.get(k,0)) for k in ['x','y','width','height']];d=f'M{x} {y}h{w}v{h}h{-w}Z'
        elif kind in ['circle','ellipse']:
            x,y=[float(el.get(k,0)) for k in ['cx','cy']];rx=float(el.get('r',el.get('rx',0)));ry=float(el.get('r',el.get('ry',0)));k=.5522847498
            d=f'M{x+rx} {y} C{x+rx} {y+k*ry} {x+k*rx} {y+ry} {x} {y+ry} C{x-k*rx} {y+ry} {x-rx} {y+k*ry} {x-rx} {y} C{x-rx} {y-k*ry} {x-k*rx} {y-ry} {x} {y-ry} C{x+k*rx} {y-ry} {x+rx} {y-k*ry} {x+rx} {y} Z'
        elif kind=='line':d='M%s %sL%s %s'%tuple(el.get(k,'0') for k in ['x1','y1','x2','y2'])
        else:d='M'+el.get('points')+('Z' if kind=='polygon' else '')
        pen=Pen();parse_path(d,pen);edges=''.join(pen.edges)
        if not edges:return []
        s=E.Element(tag('DOMShape'),isFloating='true');matrix(s,m);filled=style['fill']!='none';stroked=style['stroke']!='none'
        if filled:self.paint(sub(sub(s,'fills'),'FillStyle',index=1),style['fill'],alpha*float(style.get('fill-opacity',1)))
        if stroked:
            st=sub(sub(sub(s,'strokes'),'StrokeStyle',index=1),'SolidStroke',weight=style['stroke-width'],caps='round',joints='round',scaleMode='normal');self.paint(sub(st,'fill'),style['stroke'],alpha*float(style.get('stroke-opacity',1)))
        if not filled and not stroked:return []
        attrs={'edges':edges}
        if filled:attrs['fillStyle1']='1'
        if stroked:attrs['strokeStyle']='1'
        sub(sub(s,'edges'),'Edge',**attrs)
        return [s]
    def convert(self,source,name,strip_transform=False):
        source=copy.deepcopy(source)
        if strip_transform:source.attrib.pop('transform',None)
        root=symbol(name,[layer('editable-vector',self.draw(source))]);self.symbols[name]=root
        return root
