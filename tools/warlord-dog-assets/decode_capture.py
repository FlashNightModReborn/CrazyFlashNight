"""Decode bounded, lossless ARGB rows emitted by the native Flash fixture."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from PIL import Image,ImageDraw,ImageFont


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('trace',type=Path)
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    text=args.trace.read_text(encoding='utf-8-sig')
    pattern=r'\[ASSET_BITMAP_BEGIN\] iron-guard-([a-z0-9-]+) (\d+) (\d+)\r?\n(.*?)\[ASSET_BITMAP_END\] iron-guard-\1'
    found={}
    args.output.mkdir(parents=True,exist_ok=True)
    for match in re.finditer(pattern,text,re.S):
        name,width,height=match[1],int(match[2]),int(match[3])
        assert name not in found and width==256 and height==256
        rgba=bytearray(width*height*4)
        for row in re.finditer(r'\[ASSET_BITMAP_ROW\] (\d+) ([0-9a-f:,]+)',match[4]):
            y=int(row[1]);x=0;assert 0<=y<height
            for segment in row[2].split(','):
                color,count=segment.split(':');value=int(color,16);count=int(count)
                assert count>=0 and x+count<=width
                pixel=bytes([(value>>16)&255,(value>>8)&255,value&255,(value>>24)&255])
                start=(y*width+x)*4;rgba[start:start+count*4]=pixel*count;x+=count
            assert x==width
        image=Image.frombytes('RGBA',(width,height),bytes(rgba))
        path=args.output/(name+'.png');assert not path.exists();image.save(path)
        found[name]=image
    expected=['charged','spent']+['pose-'+str(i) for i in range(9)]
    assert set(found)==set(expected),list(found)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
    title_font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',23)
    board=Image.new('RGB',(768,1220),'#E9E6DD');draw=ImageDraw.Draw(board)
    draw.text((16,10),'军阀铁卫犬 · Flash 原生绘制',font=title_font,fill='#26292B')
    labels=['满能：护盾与指示灯亮','放电后：护盾与指示灯灭','站立','行走','奔跑','撕咬','受击','击倒','倒地','被投','死亡']
    for index,name in enumerate(expected):
        col=index%3;row=index//3;x=col*256;y=50+row*288
        tile=Image.new('RGBA',(256,256),'#DDDAD2')
        tile.alpha_composite(found[name]);board.paste(tile.convert('RGB'),(x,y+28))
        draw.text((x+9,y+3),labels[index],font=font,fill='#303535')
        for start in range(0,256,12):draw.line((x+start,y+28+128,x+start+5,y+28+128),fill='#A9A59C')
    draw.text((16,1200),'固定画布与原生倍率；虚线标示单位原点。',font=font,fill='#555B5C')
    board.save(args.output/'native-contact-sheet.png')
    (args.output/'capture-identity.json').write_text(json.dumps({'traceSha256':hashlib.sha256(args.trace.read_bytes()).hexdigest(),
        'captures':expected,'nativeFlash':True,'perFrameFit':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'captures':len(found),'contactSheet':str(args.output/'native-contact-sheet.png')},ensure_ascii=False))


if __name__=='__main__':main()
