"""Static point connectivity and fill equivalence; not player-radius/AVM1 acceptance."""
from collections import deque
from pathlib import Path
import json
import math
import random
import geometry

HERE=Path(__file__).resolve().parent
overrides=json.loads((HERE/'route-geometry-overrides.json').read_text(encoding='utf-8'))
report={'schema':'cf6-static-geometry-audit.v1','evidenceBoundary':'point-based offline geometry only; actual player radius, camera and gameplay pending','maps':[]}
failed=[]
for key,row in overrides['maps'].items():
    original=json.loads((HERE/'generated'/(key+'-original-geometry.json')).read_text(encoding='utf-8'))
    paths,notes=geometry.collision_paths(original)
    bounds=row['walkBounds'];x0,y0,x1,y1=bounds
    rng=random.Random(key);mismatches=0
    for _ in range(1000):
        p=[rng.uniform(x0,x1),rng.uniform(y0,y1)]
        a=sum(geometry.point_inside(p,path) for path in paths)%2
        b=sum(geometry.point_inside(p,path) for path in row['collisions'])
        if a!=b:mismatches+=1
    spawn_line_blocked=0
    for field in ('leftSpawnLine','rightSpawnLine'):
        line=row[field]
        for i in range(101):
            p=[(line[0]+line[2])/2,line[1]+(line[3]-line[1])*i/100]
            if sum(geometry.point_inside(p,path) for path in paths)%2:spawn_line_blocked+=1
    step=5;nx=int((x1-x0)/step);ny=int((y1-y0)/step)
    def point(cell):return [x0+(cell[0]+0.5)*step,y0+(cell[1]+0.5)*step]
    free=set()
    for xi in range(nx):
        for yi in range(ny):
            if sum(geometry.point_inside(point((xi,yi)),path) for path in paths)%2==0:free.add((xi,yi))
    spawn=row['spawn'];start=min(free,key=lambda p:(point(p)[0]-spawn[0])**2+(point(p)[1]-spawn[1])**2)
    exit_rect=row['exit']['rect']
    targets={cell for cell in free if exit_rect[0]<point(cell)[0]<exit_rect[2] and exit_rect[1]<point(cell)[1]<exit_rect[3]}
    visited={start};queue=deque([start]);reached=False
    while queue:
        cell=queue.popleft()
        if cell in targets:reached=True;break
        for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
            neighbor=(cell[0]+dx,cell[1]+dy)
            if neighbor in free and neighbor not in visited:visited.add(neighbor);queue.append(neighbor)
    item={'id':key,'collisionPolygons':len(row['collisions']),'fillSamples':1000,'fillMismatches':mismatches,
          'spawnLineSamples':202,'spawnLineBlockedSamples':spawn_line_blocked,
          'pointGridStep':step,'reachableExit':reached,'reachableSamples':len(visited),'freeSamples':len(free),
          'spawnAdjusted':row['geometryBasis']['spawnAdjusted'],'approximations':notes}
    report['maps'].append(item)
    if mismatches or not reached or spawn_line_blocked:failed.append(key)
output=HERE/'generated/geometry-audit.json';output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'maps':len(report['maps']),'failed':failed,'report':str(output)},ensure_ascii=False))
if failed:raise SystemExit(1)
