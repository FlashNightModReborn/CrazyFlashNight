"""Derive A01 geometry from the pinned original; attribute CF7 manual-exit adaptation."""
from pathlib import Path
import argparse
import json
import geometry as geo

HERE=Path(__file__).resolve().parent


def inside(point,polygon):
    x,y=point;result=False
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:result=not result
    return result


def decompose(paths,bounds):
    """Even-odd solid with a hole -> nonoverlapping exact rectangles inside walkBounds."""
    x0,y0,x1,y1=bounds
    for polygon in paths:
        for a,b in zip(polygon,polygon[1:]+polygon[:1]):
            if a[0]!=b[0] and a[1]!=b[1] and max(a[0],b[0])>x0 and min(a[0],b[0])<x1 and max(a[1],b[1])>y0 and min(a[1],b[1])<y1:
                raise ValueError('nonrectilinear collision edge intersects playable bounds')
    xs=sorted({x0,x1}|{p[0] for path in paths for p in path if x0<p[0]<x1})
    ys=sorted({y0,y1}|{p[1] for path in paths for p in path if y0<p[1]<y1})
    rectangles=[]
    for top,bottom in zip(ys,ys[1:]):
        row=[];run=None
        for left,right in zip(xs,xs[1:]):
            solid=sum(inside([(left+right)/2,(top+bottom)/2],p) for p in paths)%2==1
            if solid:
                if run is None:run=[left,top,right,bottom]
                else:run[2]=right
            elif run is not None:row.append(run);run=None
        if run is not None:row.append(run)
        for rectangle in row:
            previous=next((r for r in rectangles if r[0]==rectangle[0] and r[2]==rectangle[2] and r[3]==top),None)
            if previous is not None:previous[3]=bottom
            else:rectangles.append(rectangle)
    return [[[r[0],r[1]],[r[2],r[1]],[r[2],r[3]],[r[0],r[3]]] for r in rectangles]


def build():
    evidence=json.loads((HERE/'generated/A01-original-geometry.json').read_text(encoding='utf-8'))
    geometry=evidence['geometry'];paths=evidence['children']['1583']['solidPolygons']
    bounds=geometry['walkBounds'];collisions=decompose(paths,bounds)
    assert not any(inside(geometry['spawn'],p) for p in collisions),'original spawn became blocked'
    return {'schema':'cf6-map-runtime-overrides.v1','maps':{'A01':{
        'worldScale':1,'walkBounds':bounds,'spawn':geometry['spawn'],'collisions':collisions,
        'leftSpawnLine':geo.spawn_line(bounds,paths,'left'),'rightSpawnLine':geo.spawn_line(bounds,paths,'right'),
        'exit':{'direction':'右','rect':[740,214,790,440]},
        'layerSourceKinds':{'background':'background'},
        'geometryStatus':'originalStaticGeometryWithPrototypeDerivedExit',
        'geometryBasis':{'originalSwfSha256':evidence['originalSwfSha256'],
            'evidence':'tools/cf6-map-runtime/generated/A01-original-geometry.json',
            'walkBounds':'decoded original world1592 load',
            'spawn':'original man1 PlaceObject2 matrix',
            'collision':'shape1583 solid outer contour minus hole; exact rectilinear decomposition inside walkBounds',
            'worldScale':'1; original equipped player body approx134.17px, current CF7 gun pose138.38px; actual gameplay camera/scale pending',
            'exit':'prototypeDerived: original counter20 auto-transition replaced by standard CF7 right-hand manual exit; not an original visible door'}}}}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    path=HERE/'a01-runtime-overrides.json';content=(json.dumps(build(),ensure_ascii=False,indent=2)+'\n').encode()
    if args.check:assert path.read_bytes()==content,'stale A01 runtime overlay'
    else:path.write_bytes(content)
    print('A01 original geometry + explicitly attributed prototype exit ready')
