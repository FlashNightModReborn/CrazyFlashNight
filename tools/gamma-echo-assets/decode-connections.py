"""Decode native connection-review pixels; partial mode is diagnostic only."""
from pathlib import Path
import argparse,hashlib,json,re
from PIL import Image,ImageDraw,ImageFont


def decode(trace, output, partial=False):
    raw=trace.read_bytes();text=raw.decode('utf-8-sig')
    starts=list(re.finditer(r'FocusedTestRunId gamma-echo Start: ([a-f0-9]+)',text))
    assert starts,'Missing run identity'
    run=starts[-1].group(1);text=text[starts[-1].start():]
    healthy=bool(re.search(r'GammaEchoAssetTest: \d+ passed, 0 failed; 28 actual timeline cases',text))
    closed=f'FocusedTestRunId gamma-echo Complete: {run}' in text
    if not partial:
        assert healthy and closed and '[TEST_FAIL]' not in text
        assert '[GAMMA_CONNECTION_EXPORT_COMPLETE] frames=28' in text
    frames={};still={}
    for line in text.splitlines():
        if line.startswith('[GAMMA_CONNECTION_BEGIN] ') or line.startswith('[GAMMA_IMAGE_BEGIN] '):
            marker,key,w,h=line.split();target=frames if 'CONNECTION' in marker else still
            assert key not in target
            target[key]={'w':int(w),'h':int(h),'rows':{},'closed':False}
        elif line.startswith('[GAMMA_CONNECTION_ROW] '):
            _,key,y,payload=line.split();data=bytearray()
            for entry in payload.split(','):
                count,color=entry.split(':');assert len(color)==8
                data.extend(bytes.fromhex(color)*int(count))
            assert len(data)==frames[key]['w']*4 and int(y) not in frames[key]['rows']
            frames[key]['rows'][int(y)]=data
        elif line.startswith('[GAMMA_ROW] '):
            _,key,y,payload=line.split();data=bytes.fromhex(payload)
            assert len(data)==still[key]['w']*4 and int(y) not in still[key]['rows']
            still[key]['rows'][int(y)]=data
        elif line.startswith('[GAMMA_CONNECTION_END] '):frames[line.split()[1]]['closed']=True
        elif line.startswith('[GAMMA_IMAGE_END] '):still[line.split()[1]]['closed']=True
    output.mkdir(parents=True,exist_ok=True)
    images={};empty=[]
    for key,f in {**frames,**still}.items():
        if not f['closed'] and partial:continue
        assert f['closed'] and set(f['rows'])==set(range(f['h']))
        image=Image.frombytes('RGBA',(f['w'],f['h']),b''.join(f['rows'][y] for y in range(f['h'])),'raw','ARGB')
        if not image.getbbox():
            empty.append(key)
            if partial:continue
            raise ValueError('Empty native frame: '+key)
        image.save(output/(key+'.png'));images[key]=image
    if not partial:assert len(images)==30
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',21)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',14)
    if all(k in images for k in ('stabilized-native','full-power-native')):
        pair=Image.new('RGB',(940,510),'#f1ede7');d=ImageDraw.Draw(pair)
        for x,key,label in [(25,'stabilized-native','λ型克隆兽 · 阶段 8'),(495,'full-power-native','暴君克隆兽 · 阶段 9 · 吸血 5%')]:
            d.text((x,12),label,font=font,fill='#282420');pair.paste(images[key],(x,55),images[key])
        d.text((25,483),'实际发布库 · Flash 原生像素',font=small,fill='#62584e');pair.save(output/'native-comparison.png')
    names={'idle':'站立','walk-a':'行走 A','walk-b':'行走 B','run-a':'奔跑 A','run-b':'奔跑 B','basic':'普通爪击',
           'leap':'跳跃撕咬','rush':'跑动捕杀','roar':'撕裂嘶吼','hit':'受击','fall':'击倒',
           'death-leg':'断腿死亡','death-arm':'断臂死亡','death-side':'侧倒死亡'}
    for variant,label in [('lambda','λ型克隆兽'),('tyrant','暴君克隆兽')]:
        selected=[(key,picture) for key,picture in images.items() if key.startswith(variant+'-')]
        if not selected:continue
        canvas=Image.new('RGB',(420*4,400*((len(selected)+3)//4)),'#f1ede7');d=ImageDraw.Draw(canvas)
        for index,(key,picture) in enumerate(selected):
            x=index%4*420;y=index//4*400
            d.text((x+15,y+9),label+' · '+names[key[len(variant)+1:]],font=font,fill='#282420')
            canvas.paste(picture,(x,y+35),picture)
        canvas.save(output/(variant+'-poses.png'))
    report={'runId':run,'traceSha256':hashlib.sha256(raw).hexdigest(),
            'complete':closed and healthy and len(images)==30 and not empty,'behaviorComplete':closed and healthy,
            'partialDiagnostic':partial,'connectionFrames':sum(k in images for k in frames),
            'nativeStillFrames':sum(k in images for k in still),'emptyFrames':empty,'imageNames':sorted(images)}
    (output/'capture-evidence.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('trace',type=Path);p.add_argument('output',type=Path);p.add_argument('--partial',action='store_true');a=p.parse_args()
    decode(a.trace,a.output,a.partial)
