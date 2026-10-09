"""Decode lossless bitmaps emitted by the real Flash focused test."""
import argparse,re
from pathlib import Path
from PIL import Image,ImageDraw

def read(log,out):
    out.mkdir(parents=True,exist_ok=True);frames=[];active=None
    for line in log.read_text('utf8').splitlines():
        m=re.match(r'\[ASSET_BITMAP_BEGIN\] (\S+) (\d+) (\d+)',line)
        if m:
            name,w,h=m.groups();active=Image.new('RGBA',(int(w),int(h)));continue
        m=re.match(r'\[ASSET_BITMAP_ROW\] (\d+) (.+)',line)
        if m and active is not None:
            y,raw=m.groups();x=0
            for run in raw.split(','):
                code,count=run.split(':');pixel=int(code,16);count=int(count)
                rgba=((pixel>>16)&255,(pixel>>8)&255,pixel&255,(pixel>>24)&255)
                for ix in range(x,x+count):active.putpixel((ix,int(y)),rgba)
                x+=count
            assert x==active.width
        if line.startswith('[ASSET_BITMAP_END]') and active is not None:
            active.save(out/(name+'.png'));frames.append((name,active));active=None
    if frames:
        board=Image.new('RGB',(640*min(4,len(frames)),520*((len(frames)+3)//4)), '#f6f3eb')
        draw=ImageDraw.Draw(board)
        for i,(name,im) in enumerate(frames):
            x=i%4*640;y=i//4*520;board.paste(im,(x,y+30),im);draw.text((x+10,y+10),name,fill='#253536')
        board.save(out/'actual-flash-contact.png')
    print('Decoded',len(frames),'complete Flash bitmaps into',out)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('log',type=Path);p.add_argument('out',type=Path);a=p.parse_args();read(a.log,a.out)
