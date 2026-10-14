"""Review disconnected native body pixels without treating death debris as errors."""
from pathlib import Path
from collections import deque
import argparse,json
from PIL import Image


def components(path):
    image=Image.open(path).convert('RGBA')
    alpha=image.getchannel('A');width,height=image.size
    mask=bytearray(1 if a>127 else 0 for a in alpha.tobytes())
    groups=[]
    for start in range(len(mask)):
        if not mask[start]:continue
        mask[start]=0;q=deque([start]);count=0
        x0=x1=start%width;y0=y1=start//width
        while q:
            at=q.popleft();x=at%width;y=at//width;count+=1
            x0=min(x0,x);x1=max(x1,x);y0=min(y0,y);y1=max(y1,y)
            for yy in range(max(0,y-1),min(height,y+2)):
                for xx in range(max(0,x-1),min(width,x+2)):
                    i=yy*width+xx
                    if mask[i]:mask[i]=0;q.append(i)
        groups.append({'pixels':count,'bounds':[x0,y0,x1,y1]})
    return sorted(groups,key=lambda r:-r['pixels'])


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('folder',type=Path);parser.add_argument('--output',type=Path);parser.add_argument('--diagnostic',action='store_true');args=parser.parse_args()
    # Attack frames may intentionally contain an independent slash trail; death
    # frames deliberately separate body parts. Check only intact body poses.
    names=['stabilized-native','full-power-native']+[v+'-'+p for v in ('lambda','tyrant') for p in ('idle','walk-a','walk-b','run-a','run-b','hit','fall')]
    results=[]
    for name in names:
        path=args.folder/(name+'.png')
        if not path.exists():continue
        groups=components(path)
        significant=[g for g in groups if g['pixels']>=12]
        results.append({'image':name,'significantComponents':len(significant),'components':significant,'passed':len(significant)==1})
    report={'schema':'gamma-echo.native-connections.v1','alphaThreshold':127,'minimumPixels':12,
            'scope':'sampled intact native body poses; excludes attack trails and intentional death fragments',
            'images':results,'passed':bool(results) and all(r['passed'] for r in results)}
    if args.output:args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps(report,ensure_ascii=False))
    if not report['passed'] and not args.diagnostic:raise SystemExit(1)
