"""Decode lossless Flash captures and compare the same native draw workload."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import statistics
import numpy as np
from PIL import Image,ImageDraw,ImageFilter

FRAMES=(1,40,43,46,49,52,55,58,61,70)


def read(path,tag):
    text=path.read_text('utf-8-sig')
    starts=re.findall(r'^FocusedTestRunId cf6-guard-render Start: (\w+)$',text,re.M)
    ends=re.findall(r'^FocusedTestRunId cf6-guard-render Complete: (\w+)$',text,re.M)
    assert len(starts)==1 and starts==ends and '[TEST_FAIL]' not in text
    assert text.count('Cf6GuardRenderTest: 21 passed, 0 failed; 10 draw points')==1
    images={};finished=set();samples={}
    for line in text.splitlines():
        m=re.fullmatch(r'\[GUARD_IMAGE_BEGIN\] '+tag+r'-(\d+) 480 360',line)
        if m:
            frame=int(m[1]);assert frame not in images
            images[frame]={};continue
        m=re.fullmatch(r'\[GUARD_IMAGE_ROW\] '+tag+r'-(\d+) (\d+) (.*)',line)
        if m:
            frame,row=int(m[1]),int(m[2]);assert frame not in finished and row not in images[frame]
            pixels=[]
            for run in m[3].split(','):
                color,count=run.split(':');assert re.fullmatch('[0-9a-f]{8}',color) and 0<int(count)<=480
                value=int(color,16);pixels.extend([(value>>16&255,value>>8&255,value&255,value>>24&255)]*int(count))
            assert len(pixels)==480;images[frame][row]=pixels;continue
        m=re.fullmatch(r'\[GUARD_IMAGE_END\] '+tag+r'-(\d+)',line)
        if m:
            frame=int(m[1]);assert frame not in finished and set(images[frame])==set(range(360))
            finished.add(frame);continue
        m=re.fullmatch(r'\[GUARD_RENDER_SAMPLE\] tag='+tag+r' frame=(\d+) firstMs=(\d+) repeatMs=([0-9,]+) pixels=(\d+)',line)
        if m:
            frame=int(m[1]);assert frame not in samples
            repeat=list(map(int,m[3].split(',')));assert len(repeat)==5
            samples[frame]={'firstMs':int(m[2]),'repeatMs':repeat,'repeatMedianMs':statistics.median(repeat),'visibleGridSamples':int(m[4])}
    assert set(samples)==finished==set(FRAMES)
    decoded={}
    for frame,rows in images.items():
        decoded[frame]=Image.fromarray(np.asarray([rows[y] for y in range(360)],dtype=np.uint8),'RGBA')
    return starts[0],decoded,samples


def composite(image):
    result=Image.new('RGBA',image.size,(232,230,226,255));result.alpha_composite(image)
    return result.convert('RGB')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('before',type=Path);parser.add_argument('after',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();assert not args.output.exists(),'Preserve earlier comparison output'
    before_id,before,bs=read(args.before,'before');after_id,after,as_=read(args.after,'after')
    args.output.mkdir(parents=True);rows=[]
    for frame in FRAMES:
        left,right=before[frame],after[frame]
        left.save(args.output/f'before-{frame}.png');right.save(args.output/f'after-{frame}.png')
        a,b=np.asarray(left),np.asarray(right)
        mask_a,mask_b=a[:,:,3]>0,b[:,:,3]>0;union=mask_a|mask_b
        rgb_diff=np.abs(np.asarray(composite(left)).astype(float)-np.asarray(composite(right)).astype(float))
        equal=bool(np.array_equal(a,b))
        if frame in (1,40,61,70):assert equal,'Unmodified frame changed: '+str(frame)
        expanded_a=np.asarray(Image.fromarray(mask_a.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(3)))>0
        expanded_b=np.asarray(Image.fromarray(mask_b.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(3)))>0
        outside=int(np.count_nonzero((mask_a&~expanded_b)|(mask_b&~expanded_a)))
        row={'frame':frame,'before':bs[frame],'after':as_[frame],'pixelIdentical':equal,
            'beforeBounds':left.getbbox(),'afterBounds':right.getbbox(),'silhouetteOutsideOnePixel':outside,
            'meanRgbDifferenceOnVisibleUnion':round(float(rgb_diff[union].mean()),5),
            'repeatMedianReductionPercent':round(100*(1-as_[frame]['repeatMedianMs']/max(1,bs[frame]['repeatMedianMs'])),3)}
        rows.append(row)
        pair=Image.new('RGB',(960,384),(232,230,226));pair.paste(composite(left),(0,24));pair.paste(composite(right),(480,24))
        draw=ImageDraw.Draw(pair);draw.text((10,7),f'BEFORE / frame {frame}',fill='black');draw.text((490,7),f'AFTER / frame {frame}',fill='black')
        pair.save(args.output/f'compare-{frame}.png')
    summary={'schema':'cf6-guard.native-render-comparison.v1','beforeRunId':before_id,'afterRunId':after_id,
        'traceHashes':{key:hashlib.sha256(path.read_bytes()).hexdigest() for key,path in [('before',args.before),('after',args.after)]},
        'workload':'One isolated Flash MovieClip at 480x360; BitmapData.draw; first draw and five clear/redraw samples per selected frame; no combat/save I/O',
        'limits':'Native draw cost only, not game frame time or physical-machine acceptance. Preclipped vector edges can change subpixel antialiasing.',
        'rows':rows}
    (args.output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n','utf8')
    print(json.dumps(summary,ensure_ascii=False))


if __name__=='__main__':main()
