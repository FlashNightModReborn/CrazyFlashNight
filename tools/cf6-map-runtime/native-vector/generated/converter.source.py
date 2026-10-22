"""A01 SVG -> native editable XFL candidate; original embedded texture is unchanged.

The root-owned CS6 imports the sole intrinsic PNG first. This writer never writes SWF.
"""
from pathlib import Path
import argparse
import base64
import copy
import hashlib
import importlib.util
import json
import math
import re
import sys
import xml.etree.ElementTree as ET

from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.svgLib.path import parse_path as parse_svg_path
from PIL import ImageFont

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
LEGACY=ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py'
spec=importlib.util.spec_from_file_location('cf6_vector_base',LEGACY)
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
E=base.E;N='{'+base.NS+'}';tag=base.tag
FONT=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/A08-R5/reference/vehicles-props-DejaVuSans-Bold.ttf'
INHERIT={'fill','fill-rule','fill-opacity','stroke','stroke-opacity','stroke-width','stroke-linecap','stroke-linejoin','stroke-miterlimit','font-family','font-size','font-weight','text-anchor','visibility'}
SKIP={'defs','clipPath','mask','linearGradient','radialGradient','title','desc','metadata','stop'}


def digest(data):return hashlib.sha256(data).hexdigest()
def matrix(node,value):E('Matrix',dict(zip(('a','b','c','d','tx','ty'),map(base.fmt,value))),E('matrix',parent=node))
def color_alpha(node,value):
    if value!=1:E('Color',{'alphaMultiplier':base.fmt(value)},E('color',parent=node))

def background_script():
    return 'stop();if(_root.gameworld!=undefined && (this===_root.gameworld.背景 || this._parent===_root.gameworld.背景) && _root._saveExt.bookRun.bookId=="cf6-sting" && _root._saveExt.bookRun.routeId=="historical" && _root._saveExt.bookRun.outcome=="active" && typeof _root.贴背景图=="function") _root.贴背景图(true);'


class Candidate(base.Writer):
    def __init__(self,path,textures=None,allow_filters=False):
        super().__init__(path)
        self.byid={n.get('id'):n for n in self.root.iter() if n.get('id')}
        self.symbols={};self.symbol_cache={};self.seq=0;self.masks=[];self.texts=[]
        self.font=TTFont(FONT);self.glyphs=self.font.getGlyphSet();self.cmap=self.font.getBestCmap()
        self.units=self.font['head'].unitsPerEm
        self.pilfont=ImageFont.truetype(str(FONT),self.units)
        self.generated_gradients=0
        self.textures=textures;self.allow_filters=allow_filters;self.filter_reports=[];self.pattern_reports=[];self.use_cache={};self.use_source_nodes={}

    def texture(self,node):
        href=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href') or ''
        if not href.startswith('data:image/png;base64,'):raise ValueError('only pinned intrinsic PNG data is supported')
        key=digest(base64.b64decode(href.split(',',1)[1]))
        if self.textures is None:
            if key!='d59054f5add2bbb73478d7321958e5af0201dde621fbdcf7e9564c45f4c8354a':raise ValueError('unregistered intrinsic image')
            return {'name':'A01-source-soil.png','pixels':[1600,904]}
        if key not in self.textures:raise ValueError('intrinsic PNG absent from native import manifest')
        return self.textures[key]

    def paint(self,parent,fill,attrs,transform,alpha):
        match=re.fullmatch(r'url\(#([^)]*)\)',fill)
        pattern=self.byid.get(match.group(1)) if match else None
        if pattern is None or tag(pattern)!='pattern':return super().paint(parent,fill,attrs,transform,alpha)
        if pattern.get('patternUnits')!='userSpaceOnUse' or pattern.get('patternContentUnits','userSpaceOnUse')!='userSpaceOnUse':raise ValueError('non-user-space pattern requires explicit support')
        images=[n for n in pattern if tag(n)=='image']
        if len(images)!=1 or len(list(pattern))!=1:raise ValueError('pattern must be one intrinsic image')
        img=images[0];texture=self.texture(img)
        width=float(pattern.get('width'));height=float(pattern.get('height'))
        if float(img.get('width'))!=width or float(img.get('height'))!=height or float(img.get('x',0))!=0 or float(img.get('y',0))!=0:raise ValueError('pattern image must fill its tile')
        if img.get('transform') or pattern.get('viewBox'):raise ValueError('pattern viewport/child transform requires explicit support')
        value=base.mul(transform,base.mul(base.transform(pattern.get('patternTransform')),(width/texture['pixels'][0],0,0,height/texture['pixels'][1],float(pattern.get('x',0)),float(pattern.get('y',0)))))
        # Native XFL BitmapFill linear terms use twips/pixel, translation stays px.
        native_matrix=tuple(v*20 if i<4 else v for i,v in enumerate(value))
        node=E('BitmapFill',{'bitmapPath':texture['name'],'bitmapIsClipped':'false'},parent);matrix(node,native_matrix)
        self.pattern_reports.append({'id':pattern.get('id'),'texture':texture['name'],'sourceTile':[width,height],'nativeMatrix':native_matrix})

    def filter_script(self,identifier):
        node=self.byid[identifier]
        if tag(node)!='filter':raise ValueError('filter reference resolves to another element')
        expressions=[];operations=[]
        for effect in node:
            kind=tag(effect)
            if effect.get('in') not in (None,'SourceGraphic') or (expressions and effect.get('in') is not None) or effect.get('result'):raise ValueError('branched filter graphs require explicit support')
            if kind=='feColorMatrix':
                if node.get('color-interpolation-filters','linearRGB')!='sRGB' or effect.get('type','matrix')!='matrix':raise ValueError('only explicit sRGB matrix color filters are supported')
                values=base.nums(effect.get('values'))
                if len(values)!=20 or not all(math.isfinite(v) for v in values):raise ValueError('color matrix requires 20 finite values')
                values=[v*255 if i%5==4 else v for i,v in enumerate(values)]
                expressions.append('new flash.filters.ColorMatrixFilter('+json.dumps(values,separators=(',',':'))+')')
                operations.append({'kind':'ColorMatrixFilter','matrix':values,'mapping':'sRGB normalized offsets to 0..255'})
            elif kind=='feComponentTransfer':
                if node.get('color-interpolation-filters','linearRGB')!='sRGB':raise ValueError('component transfer must explicitly use sRGB')
                values=[0]*20
                for i in range(4):values[i*5+i]=1
                for channel in effect:
                    index={'feFuncR':0,'feFuncG':1,'feFuncB':2,'feFuncA':3}.get(tag(channel))
                    if index is None or channel.get('type')!='linear':raise ValueError('only linear RGBA component transfer is supported')
                    values[index*5+index]=float(channel.get('slope',1));values[index*5+4]=float(channel.get('intercept',0))*255
                if not all(math.isfinite(v) for v in values):raise ValueError('nonfinite component transfer')
                expressions.append('new flash.filters.ColorMatrixFilter('+json.dumps(values,separators=(',',':'))+')')
                operations.append({'kind':'ColorMatrixFilter','matrix':values,'mapping':'linear component transfer'})
            elif kind=='feGaussianBlur':
                deviation=base.nums(effect.get('stdDeviation','0'))
                if len(deviation) not in (1,2) or min(deviation)<0:raise ValueError('invalid blur deviation')
                x=deviation[0];y=deviation[-1]
                if max(x,y)>16:raise ValueError('large blur needs separate performance review')
                expressions.append('new flash.filters.BlurFilter('+base.fmt(x*2)+','+base.fmt(y*2)+',3)')
                operations.append({'kind':'BlurFilter','sourceStdDeviation':[x,y],'blur':[x*2,y*2],'quality':3,'mapping':'three-pass native approximation; actual visual comparison required'})
            else:raise ValueError('unsupported filter primitive '+kind)
        if not expressions:raise ValueError('empty filter')
        self.filter_reports.append({'id':identifier,'operations':operations,'sourceRegion':dict(node.attrib),
            'limit':'source filter-region crop is not yet reproduced; verify no visible spill at intended boundary'})
        return 'stop();this.filters=['+','.join(expressions)+'];'

    def symbol(self,elements,label,script=None):
        root=E('DOMSymbolItem',{'name':'pending','symbolType':'movie clip' if script else 'graphic'})
        layers=E('layers',parent=E('DOMTimeline',{'name':label},E('timeline',parent=root)))
        frame=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':label},layers)))
        if script:E('script',parent=E('Actionscript',parent=frame)).text=script
        els=E('elements',parent=frame)
        for el in elements:els.append(el)
        # Canonical bytes exclude the generated name, preserving identical reusable art.
        key=digest(ET.tostring(root))
        if key not in self.symbol_cache:
            self.seq+=1;name='CF6Vector/'+str(self.seq).zfill(5)+'-'+re.sub(r'[^a-zA-Z0-9_-]','_',label)[:35]
            root.set('name',name);self.symbol_cache[key]=name;self.symbols[name]=root
        return self.symbol_cache[key],bool(script)

    def instance(self,elements,label,transform=base.I,alpha=1,script=None,name=None):
        if name and script is None:script='stop();'
        symbol,movie=self.symbol(elements,label,script)
        attrs={'libraryItemName':symbol,'symbolType':'movie clip' if movie else 'graphic'}
        if not movie:attrs.update(loop='single frame',firstFrame='0')
        if name:attrs['name']=name
        node=E('DOMSymbolInstance',attrs);matrix(node,transform);color_alpha(node,alpha)
        return node

    def gradient(self,identifier,element,mask_mode=False):
        original=self.grads[identifier];g=copy.deepcopy(original)
        if g.get('href') or g.get('{http://www.w3.org/1999/xlink}href'):raise ValueError('gradient inheritance requires explicit handling')
        units=g.get('gradientUnits','objectBoundingBox')
        def coordinate(key,default):
            raw=g.get(key,default)
            return float(raw[:-1])/100 if raw.endswith('%') else float(raw)
        if units=='objectBoundingBox':
            paths=base.primitive(element);points=[p for path in paths for p in base.flattened(path)]
            if not points:raise ValueError('gradient on empty primitive')
            xs=[p[0] for p in points];ys=[p[1] for p in points]
            x,y,w,h=min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)
            if w<=0 or h<=0:raise ValueError('degenerate gradient bbox')
            gt=base.mul((w,0,0,h,x,y),base.transform(g.get('gradientTransform')))
            g.set('gradientTransform','matrix('+' '.join(map(base.fmt,gt))+')')
        elif units!='userSpaceOnUse':raise ValueError('unsupported gradient units')
        g.set('gradientUnits','userSpaceOnUse')
        keys={'x1':'0%','y1':'0%','x2':'100%','y2':'0%'} if tag(g)=='linearGradient' else {'cx':'50%','cy':'50%','r':'50%'}
        for k,default in keys.items():g.set(k,base.fmt(coordinate(k,default)))
        if tag(g)=='radialGradient':
            if ('fx' in g.attrib and not math.isclose(coordinate('fx',g.get('cx')),float(g.get('cx')),abs_tol=1e-9)) or ('fy' in g.attrib and not math.isclose(coordinate('fy',g.get('cy')),float(g.get('cy')),abs_tol=1e-9)) or coordinate('fr','0')!=0:
                raise ValueError('non-centered radial gradient requires explicit implementation')
            g.set('fx',g.get('cx'));g.set('fy',g.get('cy'))
        if mask_mode:
            for s in g:
                if tag(s)!='stop':continue
                a=base.style(s);value=base.color(a.get('stop-color','black'))
                rgb=[int(value[i:i+2],16)/255 for i in (1,3,5)]
                if max(rgb)-min(rgb)>0.00001:raise ValueError('non-grayscale SVG mask needs color-space review')
                s.set('stop-color','#FFFFFF');s.set('stop-opacity',base.fmt(rgb[0]*float(a.get('stop-opacity',1))))
                s.attrib.pop('style',None)
        self.generated_gradients+=1;key='native_gradient_'+str(self.generated_gradients)
        g.set('id',key);self.grads[key]=g
        return 'url(#'+key+')'

    def primitive(self,node,attrs,mask_mode=False):
        if tag(node)=='path' and re.search('[Aa]',node.get('d','')):
            pen=SVGPathPen(None);parse_svg_path(node.get('d'),pen)
            node=copy.deepcopy(node);node.set('d',pen.getCommands())
        attrs=dict(attrs)
        for field in ('fill','stroke'):
            value=attrs.get(field,'#000000' if field=='fill' else 'none')
            match=re.fullmatch(r'url\(#([^)]*)\)',value)
            if match and tag(self.byid.get(match.group(1),ET.Element('unknown')))=='pattern':
                if mask_mode:raise ValueError('pattern luminance masks require explicit support')
            elif match:attrs[field]=self.gradient(match.group(1),node,mask_mode)
            elif mask_mode and value!='none':
                rgb=[int(base.color(value)[i:i+2],16)/255 for i in (1,3,5)]
                if max(rgb)-min(rgb)>0.00001:raise ValueError('non-gray mask paint')
                attrs[field]='#FFFFFF';attrs[field+'-opacity']=base.fmt(float(attrs.get(field+'-opacity',1))*rgb[0])
        fill_match=re.fullmatch(r'url\(#([^)]*)\)',attrs.get('fill',''))
        patterned=fill_match and tag(self.byid.get(fill_match.group(1),ET.Element('unknown')))=='pattern'
        pattern_alpha=1
        if patterned:
            if attrs.get('stroke','none')!='none':raise ValueError('pattern fill plus stroke needs separated paints')
            pattern_alpha=float(attrs.get('opacity',1))*float(attrs.get('fill-opacity',1));attrs['opacity']='1';attrs['fill-opacity']='1'
        shape=self.shape(node,attrs,base.I)
        if shape is not None and patterned and pattern_alpha!=1:return [self.instance([shape],'pattern-opacity',alpha=pattern_alpha)]
        return [shape] if shape is not None else []

    def text_paths(self,node,attrs):
        text=''.join(node.itertext())
        if attrs.get('font-family')!='DejaVu Sans' or attrs.get('font-weight')!='bold':raise ValueError('unreviewed font '+str(attrs))
        size=float(attrs.get('font-size','12'));scale=size/self.units
        x=float(node.get('x','0'));y=float(node.get('y','0'))
        width=self.pilfont.getlength(text)*scale
        if attrs.get('text-anchor')=='middle':x-=width/2
        elif attrs.get('text-anchor')=='end':x-=width
        result=[]
        for i,char in enumerate(text):
            glyph=self.cmap.get(ord(char))
            if not glyph:raise ValueError('missing glyph '+char)
            pen=SVGPathPen(self.glyphs);self.glyphs[glyph].draw(pen);d=pen.getCommands()
            if not d:continue
            # getlength(prefix+char)-getlength(char) keeps kerning across the prior pair.
            advance=(self.pilfont.getlength(text[:i+1])-self.pilfont.getlength(char))*scale
            path=ET.Element('{http://www.w3.org/2000/svg}path',{'d':d})
            elements=self.primitive(path,attrs)
            result.append(self.instance(elements,'glyph-'+str(ord(char)),(scale,0,0,-scale,x+advance,y)))
        self.texts.append({'text':text,'font':str(FONT.relative_to(ROOT)),'fontSha256':digest(FONT.read_bytes()),'policy':'native glyph outlines; source text retained in report'})
        return result

    def walk_native(self,node,inherited=None,mask_mode=False):
        kind=tag(node)
        if kind in SKIP:return []
        attrs=base.style(node,{k:v for k,v in (inherited or {}).items() if k in INHERIT})
        if attrs.get('display')=='none' or attrs.get('visibility')=='hidden':return []
        if attrs.get('filter') and not self.allow_filters:raise ValueError('filter requires bounded explicit implementation')
        transform=base.transform(node.get('transform'))
        opacity=float(attrs.pop('opacity',1))
        if kind in ('svg','g'):
            elements=[]
            for child in node:elements.extend(self.walk_native(child,attrs,mask_mode))
        elif kind=='use':
            ref=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href')
            if not ref or not ref.startswith('#'):raise ValueError('nonlocal use')
            transform=base.mul(transform,(1,0,0,1,float(node.get('x',0)),float(node.get('y',0))))
            cache_key=(id(self.byid[ref[1:]]),tuple(sorted((k,v) for k,v in attrs.items() if k in INHERIT)),mask_mode)
            self.use_source_nodes[id(self.byid[ref[1:]])]=self.byid[ref[1:]]
            if cache_key not in self.use_cache:self.use_cache[cache_key]=self.walk_native(self.byid[ref[1:]],attrs,mask_mode)
            elements=copy.deepcopy(self.use_cache[cache_key])
        elif kind=='image':
            if mask_mode:raise ValueError('image mask needs explicit review')
            texture=self.texture(node)
            node_image=E('DOMBitmapInstance',{'libraryItemName':texture['name']})
            matrix(node_image,(float(node.get('width'))/texture['pixels'][0],0,0,float(node.get('height'))/texture['pixels'][1],float(node.get('x',0)),float(node.get('y',0))))
            elements=[node_image]
        elif kind=='text':elements=self.text_paths(node,attrs)
        elif kind in ('path','rect','ellipse','circle','line','polygon','polyline'):
            attrs['opacity']=opacity;opacity=1
            elements=self.primitive(node,attrs,mask_mode)
        else:raise ValueError('unsupported SVG element '+kind)
        if not elements:return []
        if attrs.get('filter'):
            match=re.fullmatch(r'url\(#([^)]*)\)',attrs['filter'])
            if not match:raise ValueError('invalid filter URL')
            elements=[self.instance(elements,'filter-'+match.group(1),script=self.filter_script(match.group(1)))]
        for field in ('clip-path','mask'):
            ref=attrs.get(field)
            if not ref:continue
            match=re.fullmatch(r'url\(#([^)]*)\)',ref)
            if not match:raise ValueError('invalid mask reference')
            source=self.byid[match.group(1)]
            source=copy.deepcopy(source);source.tag='{http://www.w3.org/2000/svg}g'
            masked=self.instance(elements,field+'-content',name='content')
            masking=self.instance(self.walk_native(source,{},field=='mask'),field+'-shape',name='maskShape')
            # Native timeline masks discard gray/alpha; cacheAsBitmap+setMask is
            # required for the original luminance-gradient mask semantics.
            script='stop();'
            if field=='mask':script+='content.cacheAsBitmap=true;maskShape.cacheAsBitmap=true;'
            script+='content.setMask(maskShape);'
            elements=[self.instance([masked,masking],field+'-'+match.group(1),script=script)]
            self.masks.append({'id':match.group(1),'kind':field,'policy':'runtime cached alpha mask from original grayscale stops' if field=='mask' else 'native vector setMask'})
        label=node.get('id') or kind
        if kind in ('svg','g') or transform!=base.I or opacity!=1:
            script='stop();this.blendMode="layer";' if kind in ('svg','g') and opacity!=1 else None
            return [self.instance(elements,label,transform,opacity,script=script)]
        return elements


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--assemble',action='store_true');args=parser.parse_args()
    manifest=json.loads((HERE/'texture-manifest.json').read_text(encoding='utf-8'))
    source=ROOT/manifest['source']
    if digest(source.read_bytes())!=manifest['sourceSha256']:raise ValueError('source SVG changed')
    converter=Candidate(source);view=base.nums(converter.root.get('viewBox'))
    layers=[]
    for child in converter.root:
        if tag(child) in SKIP:continue
        elements=converter.walk_native(child)
        frame=E('DOMFrame',{'index':'0','duration':'2','keyMode':'9728'},E('frames',parent=(layer:=E('DOMLayer',{'name':child.get('id','layer')}))))
        els=E('elements',parent=frame)
        # Source SVG viewBox registration is removed exactly once.
        els.append(converter.instance(elements,'registered-'+child.get('id','layer'),(1,0,0,1,-view[0],-view[1])))
        layers.append(layer)
    source_bindings=[]
    map_input=json.loads((ROOT/'tools/cf6-map-source/generated/map-input.json').read_text(encoding='utf-8'))['maps']['A01']
    for source_layer in map_input['layers'][1:]:
        path=ROOT/source_layer['source']['svg'];extra=ET.parse(path).getroot()
        prefix=source_layer['id']+'__'
        for element in extra.iter():
            if element.get('id'):element.set('id',prefix+element.get('id'))
            for key,value in list(element.attrib.items()):
                if 'url(#' in value:element.set(key,value.replace('url(#','url(#'+prefix))
                elif key.endswith('href') and value.startswith('#'):element.set(key,'#'+prefix+value[1:])
        converter.byid.update({n.get('id'):n for n in extra.iter() if n.get('id')})
        converter.grads.update({n.get('id'):n for n in extra.iter() if tag(n) in ('linearGradient','radialGradient')})
        ev=base.nums(extra.get('viewBox'));elements=converter.walk_native(extra)
        layer=E('DOMLayer',{'name':source_layer['id']});frame=E('DOMFrame',{'index':'0','duration':'2','keyMode':'9728'},E('frames',parent=layer))
        els=E('elements',parent=frame);origin=map_input['nativeBounds'][:2]
        els.append(converter.instance(elements,source_layer['id'],(1,0,0,1,source_layer['x']-origin[0]-ev[0],source_layer['y']-origin[1]-ev[1])))
        layers.append(layer);source_bindings.append({'path':path.relative_to(ROOT).as_posix(),'sha256':digest(path.read_bytes()),'placement':source_layer})
    out=HERE/'generated';out.mkdir(exist_ok=True)
    (out/'converter.source.py').write_bytes(Path(__file__).read_bytes())
    (out/'legacy-writer.source.py').write_bytes(LEGACY.read_bytes())
    includes=[]
    for name,tree in converter.symbols.items():
        path=out/'LIBRARY'/(name+'.xml');path.parent.mkdir(parents=True,exist_ok=True)
        ET.ElementTree(tree).write(path,encoding='utf-8',xml_declaration=True)
        includes.append(name)
    timeline=E('DOMTimeline',{'name':'A01 Native Vector Candidate'})
    node=E('layers',parent=timeline)
    stop=E('DOMLayer',{'name':'initialize-then-bake'},node);frames=E('frames',parent=stop)
    fr=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},frames);E('elements',parent=fr)
    fr=E('DOMFrame',{'index':'1','duration':'1','keyMode':'9728'},frames)
    E('script',parent=E('Actionscript',parent=fr)).text=background_script()
    E('elements',parent=fr)
    for layer in reversed(layers):node.append(layer)
    ET.ElementTree(timeline).write(out/'timeline.xml',encoding='utf-8',xml_declaration=True)
    report={'schema':'cf6-native-vector-candidate.v1','source':manifest['source'],'sourceSha256':manifest['sourceSha256'],
            'converterSha256':digest(Path(__file__).read_bytes()),'legacyWriterSha256':digest(LEGACY.read_bytes()),
            'nativeShapesProcessed':converter.shape_count,
            'nativeShapes':sum(1 for tree in converter.symbols.values() for n in tree.iter() if n.tag==N+'DOMShape'),
            'nativeSymbols':len(converter.symbols),'nativeEdgesSegments':converter.segment_count,
            'gradientUses':converter.generated_gradients,'masks':converter.masks,'texts':converter.texts,
            'sourceViewBox':view,'additionalSources':source_bindings,'texture':manifest['inputs'],'nativeLayerOrder':[g.get('name') for g in reversed(layers)],
            'state':'source_generated; native assembly, CS6 compilation and pixel/consumer comparison pending',
            'limits':['Native mask alpha/cache semantics require actual AVM1 rendering verification.',
                      'Cubic to quadratic tolerance inherited as 0.06 source px; XFL coordinates quantized to twips.',
                      'Native solid strokes retained locally before full affine instance transforms.',
                      'Source group opacity is preserved via separate native instances, including overlap compositing.']}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if args.assemble:
        sys.path.insert(0,str(HERE.parent));from native_xfl import finalize,audit
        xfl=ROOT/manifest['xfl'];audit(xfl,manifest['inputs'])
        doc=ET.parse(xfl.parent/'DOMDocument.xml');r=doc.getroot()
        old=r.find(N+'symbols')
        if old is not None:r.remove(old)
        symbols=E('symbols',parent=r)
        for name in includes:
            destination=xfl.parent/'LIBRARY'/(name+'.xml');destination.parent.mkdir(parents=True,exist_ok=True)
            destination.write_bytes((out/'LIBRARY'/(name+'.xml')).read_bytes())
            E('Include',{'href':name+'.xml','loadImmediate':'false'},symbols)
        timelines=r.find(N+'timelines');timelines.clear();timelines.append(timeline)
        doc.write(xfl.parent/'DOMDocument.xml',encoding='utf-8',xml_declaration=True)
        finalize(xfl,manifest['swf'],manifest['inputs'])
        report['state']='native_xfl_assembled; fresh CS6 compile and actual rendering still pending'
        (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('nativeShapes','nativeSymbols','nativeEdgesSegments','gradientUses','state')},ensure_ascii=False))


if __name__=='__main__':main()
