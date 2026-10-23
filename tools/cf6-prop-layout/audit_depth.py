"""Read-only candidate selection from current final-world walk bounds and collision polygons."""
from collections import defaultdict,deque
from pathlib import Path
import json
import math
import sys
import xml.etree.ElementTree as ET
import calibrate as c
sys.path.insert(0,str(c.ROOT/'tools/cf6-map-runtime'))
from geometry import point_inside

STEP=16;RADIUS=12;OFFSET=24

def run():
    env_path=c.ROOT/'data/environment/stage_environment.xml'
    chapter_path=c.ROOT/'data/stages/books/cf6-sting.json'
    envs={n.findtext('BackgroundURL'):n for n in ET.parse(env_path).getroot()}
    chapter=c.read(chapter_path);maps={m['id']:m for m in chapter['maps']}
    groups=defaultdict(list)
    for row in c.read(c.HERE/'generated/instance-layout.json')['instances']:groups[row.get('assemblyId',row['id'])].append(row)
    grids={};results=[]
    for group,rows in groups.items():
        mid=rows[0]['mapId'];name='CF6_Tutorial_BG.swf' if mid=='TUTORIAL' else 'CF6_'+mid+'_BG.swf'
        if mid not in grids:
            env=envs[name];wb=[float(env.findtext(k)) for k in ('Xmin','Ymin','Xmax','Ymax')]
            polys=[[[float(v) for v in p.text.split(',')] for p in n.findall('Point')] for n in env.findall('Collision')]
            def clear(p,wb=wb,polys=polys):
                return wb[0]<p[0]<wb[2] and wb[1]<p[1]<wb[3] and not any(point_inside(p,poly) for poly in polys)
            def free(p,clear=clear):
                return all(clear([p[0]+dx,p[1]+dy]) for dx,dy in [(0,0),(RADIUS,0),(-RADIUS,0),(0,RADIUS),(0,-RADIUS),(8.5,8.5),(-8.5,8.5),(8.5,-8.5),(-8.5,-8.5)])
            nodes={(x,y):[wb[0]+x*STEP,wb[1]+y*STEP] for x in range(1,math.ceil((wb[2]-wb[0])/STEP)) for y in range(1,math.ceil((wb[3]-wb[1])/STEP))}
            nodes={k:p for k,p in nodes.items() if free(p)}
            basic=maps[mid]['stage']['BasicInformation'];spawn=[basic['PlayerX'],basic['PlayerY']]
            if not nodes:raise ValueError('empty walkable grid')
            start=min(nodes,key=lambda k:(nodes[k][0]-spawn[0])**2+(nodes[k][1]-spawn[1])**2)
            seen={start};q=deque([start])
            while q:
                x,y=q.popleft()
                for delta in [(1,0),(-1,0),(0,1),(0,-1)]:
                    key=(x+delta[0],y+delta[1])
                    if key in nodes and key not in seen:seen.add(key);q.append(key)
            grids[mid]=(wb,nodes,seen,free,spawn,nodes[start])
        wb,nodes,seen,free,spawn,start=grids[mid]
        pivot=rows[0]['worldPivot'];corners=[]
        for row in rows:
            x0,y0,x1,y1=row['nativeBounds']
            corners.extend([[p[0]+row['worldPivot'][0],p[1]+row['worldPivot'][1]] for p in [c.point(row['artMatrix'],v) for v in [(x0,y0),(x1,y0),(x1,y1),(x0,y1)]]])
        left=min(p[0] for p in corners);right=max(p[0] for p in corners);cx=(left+right)/2
        def reachable(p):
            if not free(p):return False
            gx=round((p[0]-wb[0])/STEP);gy=round((p[1]-wb[1])/STEP)
            return any((gx+dx,gy+dy) in seen and abs(nodes[(gx+dx,gy+dy)][0]-p[0])<=STEP and abs(nodes[(gx+dx,gy+dy)][1]-p[1])<=STEP for dx,dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1)])
        samples={}
        for side,sign in [('behind',-1),('front',1)]:
            width=right-left
            xs=[cx] if width<=2*RADIUS else [left+RADIUS,left+width*.25,cx,right-width*.25,right-RADIUS]
            candidates=[[x,pivot[1]+sign*offset] for x in xs for offset in [OFFSET,40,64]]
            samples[side]=[p for p in candidates if reachable(p)]
        eligible=bool(samples['behind'] and samples['front'])
        results.append({'assemblyId':group,'mapId':mid,'memberIds':[r['id'] for r in rows],'worldPivot':pivot,'visualWorldX':[left,right],
                        'walkBounds':wb,'reachableSamples':samples,'needsDepthSplit':eligible,
                        'criterion':'front/back traversal only; interaction requirements assessed separately',
                        'interactionAssessment':'not assessed',
                        'decision':'front/back traversal demonstrated; depth split candidate' if eligible else 'front/back traversal not demonstrated; no depth split required by this criterion',
                        'spawn':spawn,'gridStart':start})
    return {'schema':'cf6-prop-depth-reachability.v1','environmentSha256':c.sha(env_path.read_bytes()),'chapterSha256':c.sha(chapter_path.read_bytes()),
            'probe':{'gridStepWorldPx':STEP,'footRadiusWorldPx':RADIUS,'frontBackOffsetsWorldPx':[OFFSET,40,64],'widthSamples':'center, quarters, inset edges','meaning':'static 4-neighbor connected walk grid plus nine-point clearance; not runtime actor collision acceptance'},
            'groups':results,'eligibleGroups':sum(r['needsDepthSplit'] for r in results)}

if __name__=='__main__':
    report=run();(c.HERE/'generated/depth-reachability.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('eligible groups',report['eligibleGroups'])
    for r in report['groups']:
        if r['needsDepthSplit']:print(r['assemblyId'],r['worldPivot'])