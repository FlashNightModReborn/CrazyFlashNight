"""Read original CF6 display matrices/bounds. Never execute imported ActionScript.

The source SWF hash is pinned to the map source packages. Bounds are evidence,
not automatically collision polygons: shape holes/curves require separate proof.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import zlib

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('swfscan',ROOT/'tools/swf-audit/swfscan.py')
swf=importlib.util.module_from_spec(spec);spec.loader.exec_module(swf)
EXPECTED='b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'
FRAMES={'A01':66,'A02':73,'A03':78,'A04':82,'A05':86,'A06':92,'A08':108,'A09':116,
        'A10':131,'A11':138,'A12':143,'A13':148,'A14':152,'A15':157,'A16':162,
        'A17':169,'A18':178,'A19':183,'A20':188,'A22':198,'TUTORIAL':58}


def rect(data,pos):
    b=swf.Bits(data,pos);n=b.u(5);v=[b.s(n)/20 for _ in range(4)];b.align()
    return [v[0],v[2],v[1],v[3]],b.byte


def matrix(data,pos):
    b=swf.Bits(data,pos);a=d=1.;c=bb=0.
    if b.u(1):n=b.u(5);a=b.s(n)/65536;d=b.s(n)/65536
    if b.u(1):n=b.u(5);bb=b.s(n)/65536;c=b.s(n)/65536
    n=b.u(5);x=b.s(n)/20;y=b.s(n)/20;b.align()
    return [a,bb,c,d,x,y],b.byte


def place(data,pos,code):
    flags=data[pos];pos+=1;flags2=0
    if code==70:flags2=data[pos];pos+=1
    depth=struct.unpack_from('<H',data,pos)[0];pos+=2
    if code==70 and (flags2&8 or flags2&16 and flags&2):_,pos=swf.read_string(data,pos)
    result={'depth':depth,'move':bool(flags&1)}
    if flags&2:result['id']=struct.unpack_from('<H',data,pos)[0];pos+=2
    if flags&4:result['matrix'],pos=matrix(data,pos)
    if flags&8:
        b=swf.Bits(data,pos);swf.skip_cxform(b,True);pos=b.byte
    if flags&16:pos+=2
    if flags&32:result['name'],pos=swf.read_string(data,pos)
    return result


def parse(path):
    raw=path.read_bytes();digest=hashlib.sha256(raw).hexdigest()
    if digest!=EXPECTED:raise ValueError('Original CF6 SWF identity mismatch: '+digest)
    data=zlib.decompress(raw[8:]) if raw[:3]==b'CWS' else raw[8:]
    bounds,pos=rect(data,0);start=pos+4
    sprites={};shapes={}
    def timeline(start,end):
        frames=[];display={};pos=start
        while pos<end:
            tag=struct.unpack_from('<H',data,pos)[0];pos+=2;code=tag>>6;length=tag&63
            if length==63:length=struct.unpack_from('<I',data,pos)[0];pos+=4
            at=pos;pos+=length
            if code==0:break
            if code==1:frames.append([dict(v) for k,v in sorted(display.items())])
            elif code==39:
                sid=struct.unpack_from('<H',data,at)[0];sprites[sid]=timeline(at+4,at+length)
            elif code in (2,22,32,83):
                sid=struct.unpack_from('<H',data,at)[0];box,_=rect(data,at+2);shapes[sid]={'bounds':box,'tag':code,'offset':at,'length':length}
            elif code in (26,70):
                row=place(data,at,code);depth=row['depth'];old=display.get(depth,{}) if row['move'] else {}
                display[depth]=dict(old,**row)
            elif code==28:display.pop(struct.unpack_from('<H',data,at)[0],None)
            elif code==5:display.pop(struct.unpack_from('<H',data,at+2)[0],None)
        return frames
    frames=timeline(start,len(data))
    return digest,frames,sprites,shapes


def compose(outer,inner):
    a,b,c,d,x,y=outer;e,f,g,h,u,v=inner
    return [a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y]


def solid_shape_paths(path,shape,approximate=False):
    """Exact solid polygons, or explicitly requested fill approximation for a candidate."""
    raw=path.read_bytes();data=zlib.decompress(raw[8:]) if raw[:3]==b'CWS' else raw[8:]
    pos=shape['offset']+2;box,pos=rect(data,pos)
    color_bytes=4 if shape['tag'] in (32,83) else 3
    if shape['tag']==83:raise ValueError('DefineShape4 geometry requires separate audit')
    count=data[pos];pos+=1
    if count==255:count=struct.unpack_from('<H',data,pos)[0];pos+=2
    for _ in range(count):
        style=data[pos];pos+=1
        if style!=0:raise ValueError('non-solid collision shape')
        pos+=color_bytes
    line_count=data[pos];pos+=1
    if line_count and not approximate:raise ValueError('collision shape has stroked geometry')
    if line_count:
        shape['sourceStrokeWidths']=[struct.unpack_from('<H',data,pos+i*(2+color_bytes))[0]/20 for i in range(line_count)]
        pos+=line_count*(2+color_bytes)
    b=swf.Bits(data,pos);fill_bits=b.u(4);line_bits=b.u(4)
    x=y=0;paths=[];points=[];segments=[];fill0=fill1=0
    while True:
        if b.u(1):
            origin=[x/20,y/20];point_count=len(points)
            straight=b.u(1);bits=b.u(4)+2
            if not straight:
                if not approximate:raise ValueError('curved collision geometry is not an exact polygon')
                cx=x+b.s(bits);cy=y+b.s(bits);ax=cx+b.s(bits);ay=cy+b.s(bits)
                def curve(a,c,z,depth=0):
                    # Bound quadratic deviation by the distance of the control point to the chord.
                    dx=z[0]-a[0];dy=z[1]-a[1];den=(dx*dx+dy*dy)**0.5
                    distance=abs(dx*(a[1]-c[1])-(a[0]-c[0])*dy)/den if den else ((a[0]-c[0])**2+(a[1]-c[1])**2)**0.5
                    if distance<=5 or depth>14: return [[z[0]/20,z[1]/20]]
                    ac=[(a[0]+c[0])/2,(a[1]+c[1])/2];cz=[(c[0]+z[0])/2,(c[1]+z[1])/2]
                    mid=[(ac[0]+cz[0])/2,(ac[1]+cz[1])/2]
                    return curve(a,ac,mid,depth+1)+curve(mid,cz,z,depth+1)
                points.extend(curve([x,y],[cx,cy],[ax,ay]));x,y=ax,ay
                shape['curveApproximationTolerancePixels']=0.25
            else:
                if b.u(1):x+=b.s(bits);y+=b.s(bits)
                elif b.u(1):y+=b.s(bits)
                else:x+=b.s(bits)
                points.append([x/20,y/20])
            previous=origin
            for point in points[point_count:]:
                if fill0!=fill1:
                    if fill0:segments.append((previous,point))
                    if fill1:segments.append((point,previous))
                previous=point
        else:
            flags=b.u(5)
            if flags==0:break
            if flags&1:
                if points:paths.append(points)
                bits=b.u(5);x=b.s(bits);y=b.s(bits);points=[[x/20,y/20]]
            if flags&2:fill0=b.u(fill_bits)
            if flags&4:fill1=b.u(fill_bits)
            if flags&8:b.u(line_bits)
            if flags&16:raise ValueError('collision shape contains new styles')
    # Authoring MoveTo/style records may split one filled contour into fragments.
    # Stitch directed fill edges, excluding line-only marker paths.
    remaining={}
    for a,b in segments:
        a=tuple(a);b=tuple(b)
        if a!=b:remaining.setdefault(a,[]).append(b)
    paths=[]
    while remaining:
        start=next(iter(remaining));cursor=start;path=[]
        while True:
            path.append(list(cursor))
            following=remaining.get(cursor)
            if not following:raise ValueError('open collision fill edge graph')
            end=following.pop()
            if not following:del remaining[cursor]
            cursor=end
            if cursor==start:break
        paths.append(path)
    return paths


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--swf',type=Path,required=True)
    parser.add_argument('--scripts',type=Path,required=True)
    parser.add_argument('--map',choices=FRAMES,default='A01')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args();digest,frames,sprites,shapes=parse(args.swf)
    frame=FRAMES[args.map];root_rows=frames[frame-1]
    root_scripts=args.scripts/f'frame_{frame}'
    world=None;load=None;source_path=None
    for directory in root_scripts.glob('PlaceObject*'):
        for source in directory.glob('*onClipEvent(load)*.as'):
            text=source.read_text(encoding='utf-8-sig')
            if re.search(r'_root\.Xmin\s*=\s*[-\d.]+',text):
                match=re.match(r'PlaceObject2_(\d+)',directory.name)
                if match:world=int(match.group(1));load=text;source_path=source
    if world is None:raise ValueError('No decoded world load with numeric bounds: '+args.map)
    params={key:float(re.search(r'_root\.'+key+r'\s*=\s*([-\d.]+)',load).group(1)) for key in ['Xmin','Xmax','Ymin','Ymax']}
    rows=sprites[world][0]
    actor=next((r for r in rows if r.get('name')=='man1'),None)
    world_data={'worldSprite':world,'mainFrame':frame,'walkBounds':[params['Xmin'],params['Ymin'],params['Xmax'],params['Ymax']],
                'spawn':actor.get('matrix',[1,0,0,1,0,0])[4:] if actor else None,'display':rows}
    evidence={'schema':'cf6-original-geometry.v1','map':args.map,'originalSwfSha256':digest,
              'extractorSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'decodedLoad':str(source_path),'decodedLoadSha256':hashlib.sha256(source_path.read_bytes()).hexdigest(),
              'geometry':world_data,'children':{}}
    def closure(sid,m=None,depth=0):
        if depth>5:return
        if sid in shapes:
            evidence['children'][str(sid)]=shapes[sid];return
        if sid not in sprites:return
        evidence['children'][str(sid)]={'frameCount':len(sprites[sid]),'firstFrame':sprites[sid][0] if sprites[sid] else []}
        for child in sprites[sid][0] if sprites[sid] else []:
            closure(child.get('id'),None,depth+1)
    for row in rows:
        # Restrict to geometry/exit markers rather than monster/weapon display closures.
        if row.get('name')=='地图' or row.get('id') in (1433,1434,1585,1587):closure(row.get('id'))
    for sid,shape in evidence['children'].items():
        if 'tag' in shape:
            try:shape['solidPolygons']=solid_shape_paths(args.swf,shape)
            except ValueError as exc:
                shape['polygonStatus']=str(exc)
                try:shape['candidateApproximateFillPolygons']=solid_shape_paths(args.swf,shape,True)
                except ValueError as approx_error:shape['candidateApproximationError']=str(approx_error)
    content=(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:assert args.output.read_bytes()==content,'stale original geometry evidence: '+args.map
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_bytes(content)
    print(json.dumps({'map':args.map,'world':world,'bounds':world_data['walkBounds'],'spawn':world_data['spawn'],
                      'geometryChildren':list(evidence['children'])},ensure_ascii=False))


if __name__=='__main__':main()
