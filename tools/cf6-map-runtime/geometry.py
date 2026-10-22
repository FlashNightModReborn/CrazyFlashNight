"""Pure polygon conversion for the original Flash even-odd collision fill."""


def point_inside(point,polygon):
    x,y=point;result=False
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:result=not result
    return result


def transform(point,matrix):
    a,b,c,d,x,y=matrix
    return [a*point[0]+c*point[1]+x,b*point[0]+d*point[1]+y]


def compose(outer,inner):
    a,b,c,d,x,y=outer;e,f,g,h,u,v=inner
    return [a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y]


def collision_paths(evidence):
    """Only the named original 地图 tree. Spawn/exit marker rectangles are not obstacles."""
    display=evidence['geometry']['display'];children=evidence['children']
    source=next(row for row in display if row.get('name')=='地图')
    polygons=[];notes=[]
    def visit(sid,matrix):
        node=children[str(sid)]
        if 'bounds' in node:
            paths=node.get('solidPolygons')
            if paths is None:
                paths=node.get('candidateApproximateFillPolygons')
                if paths is None:raise ValueError(f'{sid}: collision fill unsupported')
                notes.append({'shape':sid,'reason':node.get('polygonStatus'),
                    'curveTolerance':node.get('curveApproximationTolerancePixels'),
                    'ignoredStrokeWidths':node.get('sourceStrokeWidths',[])})
            polygons.extend([[transform(p,matrix) for p in path] for path in paths])
        else:
            for row in node['firstFrame']:
                visit(row['id'],compose(matrix,row.get('matrix',[1,0,0,1,0,0])))
    visit(source['id'],source.get('matrix',[1,0,0,1,0,0]))
    return polygons,notes


def filled_trapezoids(paths,bounds):
    """Clip even-odd filled contours and holes into standalone convex polygons.

    Split at all vertex Y values and at clipping-line intersections. Inside each
    open Y slab, each contour edge is linear, so its fill boundaries are exact.
    """
    x0,y0,x1,y1=bounds
    edges=[(a,b) for p in paths for a,b in zip(p,p[1:]+p[:1]) if a[1]!=b[1]]
    ys={y0,y1}|{p[1] for path in paths for p in path if y0<p[1]<y1}
    for a,b in edges:
        for x in (x0,x1):
            if a[0]!=b[0] and min(a[0],b[0])<x<max(a[0],b[0]):
                y=a[1]+(x-a[0])*(b[1]-a[1])/(b[0]-a[0])
                if y0<y<y1:ys.add(y)
    ys=sorted(ys);result=[]
    def crossing(edge,y):
        a,b=edge;return a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1])
    for top,bottom in zip(ys,ys[1:]):
        mid=(top+bottom)/2
        active=[edge for edge in edges if min(edge[0][1],edge[1][1])<mid<max(edge[0][1],edge[1][1])]
        active.sort(key=lambda edge:crossing(edge,mid))
        if len(active)%2:raise ValueError('unbalanced collision contour scanline')
        for left,right in zip(active[::2],active[1::2]):
            if crossing(right,mid)<=x0 or crossing(left,mid)>=x1:continue
            points=[[max(x0,crossing(left,top)),top],[min(x1,crossing(right,top)),top],
                    [min(x1,crossing(right,bottom)),bottom],[max(x0,crossing(left,bottom)),bottom]]
            polygon=[]
            for point in points:
                point=[round(v,6) for v in point]
                if not polygon or polygon[-1]!=point:polygon.append(point)
            if polygon[0]==polygon[-1]:polygon.pop()
            if len(polygon)>2:result.append(polygon)
    # Adjacent slabs often repeat the same wall. Merge collinear quadrilaterals
    # so one curved decoration does not multiply unrelated wall collision tests.
    merged=[];bottoms={}
    for polygon in result:
        if len(polygon)!=4:merged.append(polygon);continue
        top_key=(tuple(polygon[0]),tuple(polygon[1]))
        previous=bottoms.get(top_key)
        combined=False
        if previous is not None:
            height=polygon[3][1]-polygon[0][1];oldheight=previous[3][1]-previous[0][1]
            left=(polygon[3][0]-polygon[0][0])*oldheight-(previous[3][0]-previous[0][0])*height
            right=(polygon[2][0]-polygon[1][0])*oldheight-(previous[2][0]-previous[1][0])*height
            if abs(left)<0.000001 and abs(right)<0.000001:
                del bottoms[top_key]
                previous[2]=polygon[2];previous[3]=polygon[3];polygon=previous;combined=True
        if not combined:merged.append(polygon)
        bottoms[(tuple(polygon[3]),tuple(polygon[2]))]=polygon
    return merged


def safe_spawn(original,bounds,paths):
    """Keep authored placement if valid; otherwise choose a declared nearest valid prototype point."""
    x0,y0,x1,y1=bounds
    def free(p):
        return x0<p[0]<x1 and y0<p[1]<y1 and sum(point_inside(p,path) for path in paths)%2==0
    if free(original):return original,False
    candidates=[]
    for y in range(int(y0)+10,int(y1),10):
        for x in range(int(x0)+20,int(x1),10):
            p=[x,y]
            if free(p):candidates.append(p)
    if not candidates:raise ValueError('no valid spawn in original walkable fill')
    return min(candidates,key=lambda p:(p[0]-original[0])**2+(p[1]-original[1])**2),True


def manual_exit(bounds,paths):
    """Find a free right-side standard CF7 exit zone, never claim original automatic transition."""
    x0,y0,x1,y1=bounds
    for right in range(int(x1),int(x0)+60,-10):
        runs=[];start=None;last=None
        for y in range(int(y0)+10,int(y1)-9,5):
            free=all(sum(point_inside([x,y],path) for path in paths)%2==0 for x in (right-49,right-25,right-1))
            if free:
                if start is None:start=y
                last=y
            elif start is not None:runs.append([start,last]);start=None
        if start is not None:runs.append([start,last])
        runs=[r for r in runs if r[1]-r[0]>=20]
        if runs:
            best=max(runs,key=lambda r:r[1]-r[0])
            return {'direction':'右','rect':[right-50,best[0],right,best[1]]}
    raise ValueError('no passable exit corridor; needs explicit map-specific adaptation')


def spawn_line(bounds,paths,side):
    x0,y0,x1,y1=bounds
    columns=range(int(x0)+10,int(x1)-10,10) if side=='left' else range(int(x1)-10,int(x0)+10,-10)
    for x in columns:
        runs=[];start=None;last=None
        for y in range(int(y0)+10,int(y1)-9,5):
            free=all(sum(point_inside([px,y],path) for path in paths)%2==0 for px in (x-8,x,x+8))
            if free:
                if start is None:start=y
                last=y
            elif start is not None:runs.append([start,last]);start=None
        if start is not None:runs.append([start,last])
        runs=[r for r in runs if r[1]-r[0]>=20]
        if runs:
            best=max(runs,key=lambda r:r[1]-r[0])
            return [x-1,best[0]+5,x+1,best[1]-5]
    raise ValueError('no safe '+side+' spawn line')
