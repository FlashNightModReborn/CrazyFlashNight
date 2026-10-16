"""Bake the six torn-atlas drawings into visible native vector contours.

The immutable SVG and its paint adapter remain authoritative. WPF performs
offline vector intersections; no masks or bitmap caching enter the SWF.
"""
from pathlib import Path
import copy
import hashlib
import json
import re
import subprocess
from lxml import etree as E
import vector

base,gamma=vector.base,vector.gamma
N,NS=gamma.N,gamma.NS
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
TOLERANCE=0.0025  # design pixels; finer than the 0.05 px native twip grid


def geometry(shape):
    result=[]
    for edge in shape.findall('x:edges/x:Edge',NS):
        tokens=re.findall(r'[!|\[]|-?\d+',edge.get('edges'))
        i=0;first=last=None
        while i<len(tokens):
            op=tokens[i];i+=1
            count=4 if op=='[' else 2
            values=[int(v)/20 for v in tokens[i:i+count]];i+=count
            result.append({'!':'M','|':'L','[':'Q'}[op]+' '.join(format(v,'.9g') for v in values))
            if first is None:first=values[:2]
            last=values[-2:]
        if first==last:result.append('Z')
    return 'F0 '+' '.join(result)


class ClippedPart(vector.NativePart):
    def build(self):
        jobs=[];paints=[];clips=[];clip_ids={}
        def clip_id(element,matrix):
            raw=element.get('clip-path')
            if not raw:return None
            match=re.fullmatch(r'url\(#([^)]*)\)',raw)
            if not match:raise ValueError('Unsupported clip '+raw)
            clip=self.by_id[match[1]]
            if clip.get('clipPathUnits','userSpaceOnUse')!='userSpaceOnUse':
                raise ValueError('Unexpected clip units')
            paths=[]
            for child in clip:
                attrs=base.style(child);attrs.update(fill='#FFFFFF',stroke='none')
                shape=self.paint_shape(child,attrs,base.mul(matrix,base.transform(clip.get('transform'))))
                if shape is not None:paths.append(geometry(shape))
            key=tuple(paths)
            if key not in clip_ids:clip_ids[key]=len(clips);clips.append(paths)
            return clip_ids[key]
        def walk(element,inherited=None,matrix=base.I,chain=(),seen=()):
            kind=base.tag(element)
            if kind in ('defs','title','desc','metadata','clipPath','linearGradient','radialGradient'):return
            attrs=base.style(element,inherited);attrs.pop('clip-path',None)
            current=base.mul(matrix,base.transform(element.get('transform')))
            index=clip_id(element,current)
            if index is not None:chain=chain+(index,)
            if kind=='use':
                ref=element.get('href',element.get('{http://www.w3.org/1999/xlink}href',''))
                if not ref.startswith('#') or ref[1:] not in self.by_id or ref in seen:
                    raise ValueError('Unresolved or cyclic atlas use '+ref)
                if any(element.get(k) for k in ('width','height')):raise ValueError('Unexpected use viewport')
                current=base.mul(current,(1,0,0,1,float(element.get('x','0')),float(element.get('y','0'))))
                # Match NativePart's independent shared-atlas paint inheritance.
                walk(self.by_id[ref[1:]],None,current,chain,seen+(ref,));return
            if kind in ('svg','g'):
                for child in element:walk(child,attrs,current,chain,seen)
                return
            shape=self.paint_shape(element,attrs,current)
            if shape is None:return
            stroke=shape.find('x:strokes/x:StrokeStyle/x:SolidStroke',NS)
            jobs.append({'path':geometry(shape),'clips':chain,'fill':shape.find('x:fills',NS) is not None,
                'weight':float(stroke.get('weight')) if stroke is not None else 0,
                'caps':stroke.get('caps') if stroke is not None else 'none',
                'joints':stroke.get('joints') if stroke is not None else 'miter'})
            paints.append(shape)
        walk(self.svg,matrix=(1,0,0,1,-self.origin[0],-self.origin[1]))
        payload=json.dumps({'tolerance':TOLERANCE,'clips':clips,'jobs':jobs},separators=(',',':'))
        digest=hashlib.sha256((payload+(HERE/'clip-vectors.ps1').read_text('utf8')).encode()).hexdigest()
        cache=ROOT/'tmp/cf6-guard-vector-clip'/digest
        cache.mkdir(parents=True,exist_ok=True)
        request,response=cache/'request.json',cache/'response.json'
        request.write_text(payload,'utf8')
        if not response.is_file():
            subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
                '-File',str(HERE/'clip-vectors.ps1'),'-InputPath',str(request),'-OutputPath',str(response)],check=True)
        rows=json.loads(response.read_text('utf8'))
        assert len(rows)==len(paints)
        drawings=[];segments=0
        for source,row in zip(paints,rows):
            for mode in ('fill','stroke'):
                if not row[mode]:continue
                paths=base.parse_path(re.sub(r'^F[01]\s*','',row[mode]))
                paths=base.normalize(paths,True)
                shape=E.Element(N+'DOMShape',isDrawingObject='true')
                fills=E.SubElement(shape,N+'fills')
                if mode=='fill':fills.append(copy.deepcopy(source.find('x:fills/x:FillStyle',NS)))
                else:
                    fill=E.SubElement(fills,N+'FillStyle',index='1')
                    paint=source.find('x:strokes/x:StrokeStyle/x:SolidStroke/x:fill',NS)
                    for item in paint:fill.append(copy.deepcopy(item))
                edges=E.SubElement(shape,N+'edges')
                for path in paths:
                    E.SubElement(edges,N+'Edge',fillStyle0='1',edges=base.edge_string(path))
                    segments+=len(path[1])
                if len(edges):drawings.append(shape)
        self.symbols[self.name]=gamma.symbol(self.name,[gamma.layer('预裁切原生矢量',[gamma.frame(elements=drawings)])])
        return self.symbols,{'shapes':len(drawings),'segments':segments,'masks':0,
            'offlineClip':{'expandedPaints':len(jobs),'clipScopes':len(clips),'tolerance':TOLERANCE,
                'method':'Windows WPF vector intersection; native fill contours and original paint matrices'}}
