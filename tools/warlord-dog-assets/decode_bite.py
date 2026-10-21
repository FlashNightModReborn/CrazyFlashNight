"""Lossless native Flash RLE decode for the fixed-nibble capture format."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont


def decode(path):
    raw = path.read_bytes()
    try:
        text = raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        text = raw.decode('gb18030')
    pattern = r'\[BITE_BITMAP_BEGIN\] ([a-z0-9-]+) (\d+) (\d+)\r?\n(.*?)\[BITE_BITMAP_END\] \1'
    found = {}
    for m in re.finditer(pattern,text,re.S):
        key,w,h = m[1],int(m[2]),int(m[3])
        assert key not in found and (w,h)==(400,240)
        rgba = bytearray(w*h*4)
        for row in re.finditer(r'\[BITE_BITMAP_ROW\] (\d+) ([0-9a-f,:-]+)',m[4]):
            y=int(row[1]);x=0
            assert 0<=y<h
            for segment in row[2].split(','):
                color,count=segment.split(':');count=int(count)
                assert re.fullmatch(r'[0-9a-f]{8}',color), 'Malformed diagnostic serialization is not a pixel receipt'
                argb=int(color,16)&0xffffffff
                assert 0<=count and x+count<=w
                pixel=bytes([(argb>>16)&255,(argb>>8)&255,argb&255,(argb>>24)&255])
                at=(y*w+x)*4;rgba[at:at+count*4]=pixel*count;x+=count
            assert x==w
        found[key]=Image.frombytes('RGBA',(w,h),bytes(rgba))
    expected={f'{kind}-{side}-{f}'for kind in ('guard','legacy') for side in ('left','right') for f in range(1,25)}
    assert set(found)==expected,(len(found),sorted(expected-set(found)))
    return found,raw


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('trace',type=Path)
    ap.add_argument('output',type=Path)
    args=ap.parse_args()
    images,raw=decode(args.trace)
    args.output.mkdir(parents=True,exist_ok=False)
    for key,im in images.items():
        im.save(args.output/(key+'.png'))
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
    sheet=Image.new('RGB',(1200,1040),'#e9e6dd');draw=ImageDraw.Draw(sheet)
    for i,frame in enumerate((1,4,7,10,13,16,19,22)):
        x=i%4*300;y=i//4*520
        for row,kind in enumerate(('legacy','guard')):
            tile=Image.new('RGBA',(400,240),'#e9e6dd');tile.alpha_composite(images[f'{kind}-right-{frame}'])
            sheet.paste(tile.convert('RGB').resize((300,180)),(x,y+row*250+30))
            draw.text((x+8,y+row*250+5),f'{kind} · {frame}',font=font,fill='#303535')
    sheet.save(args.output/'native-keyframes.png')
    (args.output/'identity.json').write_text(json.dumps({'rawTraceSha256':hashlib.sha256(raw).hexdigest(),
        'captures':96,'canvas':[400,240],'scale':2,'origin':[200,170],'perFrameFit':False,
        'pixels':'Actual BitmapData.draw in CS6 supplied standalone Flash debugger; no motion/damage simulation'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'captures':96,'output':str(args.output)},ensure_ascii=False))


if __name__=='__main__':main()
