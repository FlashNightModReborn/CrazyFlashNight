"""Decode the focused suite's actual Flash BitmapData rows and compose review sheets."""
from pathlib import Path
import argparse,json,re
from PIL import Image,ImageDraw,ImageFont

def main():
    parser=argparse.ArgumentParser();parser.add_argument('trace',type=Path);parser.add_argument('--out',type=Path,required=True);parser.add_argument('--expected-count',type=int,default=18);args=parser.parse_args()
    text=args.trace.read_text(encoding='utf-8-sig');args.out.mkdir(parents=True,exist_ok=True)
    images={};pending={}
    for line in text.splitlines():
        m=re.fullmatch(r'\[DOG_IMAGE_BEGIN\] (\S+) (\d+) (\d+)(?: (sparse))?',line)
        if m:
            key,w,h=m.group(1),int(m.group(2)),int(m.group(3));assert key not in pending and key not in images
            pending[key]={'w':w,'h':h,'rows':{},'sparse':bool(m.group(4))};continue
        m=re.fullmatch(r'\[DOG_IMAGE_ROW\] (\S+) (\d+) (.+)',line)
        if m:
            key,y,runs=m.group(1),int(m.group(2)),m.group(3);p=pending[key];row=bytearray()
            for run in runs.split(','):
                count,color=run.split(':');assert len(color)==8;value=int(color,16)
                row.extend(bytes(((value>>16)&255,(value>>8)&255,value&255,(value>>24)&255))*int(count))
            assert len(row)==p['w']*4 and y not in p['rows'];p['rows'][y]=row;continue
        m=re.fullmatch(r'\[DOG_IMAGE_END\] (\S+)(?: rows=(\d+))?',line)
        if m:
            key=m.group(1);p=pending.pop(key)
            expected=int(m.group(2)) if p['sparse'] else p['h']
            assert len(p['rows'])==expected and all(0<=y<p['h'] for y in p['rows'])
            empty=bytes(p['w']*4)
            image=Image.frombytes('RGBA',(p['w'],p['h']),b''.join(p['rows'].get(y,empty) for y in range(p['h'])))
            image.save(args.out/(key+'.png'));images[key]=image
    if args.expected_count:assert len(images)==args.expected_count,(len(images),args.expected_count)
    fontpath=Path('C:/Windows/Fonts/msyh.ttc');font=ImageFont.truetype(str(fontpath),22) if fontpath.exists() else ImageFont.load_default()
    small=ImageFont.truetype(str(fontpath),17) if fontpath.exists() else font
    def sheet(filename,poses,labels):
        cellw,cellh=340,280
        out=Image.new('RGBA',(cellw*len(poses),cellh*2+100),'#e9e8e1');draw=ImageDraw.Draw(out)
        draw.text((20,16),'两犬 · Flash 原生帧读回',font=font,fill='#25333b')
        draw.text((20,52),'原生共享导入宿主 / 视觉与继承动作专项；初始化、移动及子弹接收器为夹具',font=small,fill='#56616a')
        for y,variant in enumerate(('military','raider')):
            for x,pose in enumerate(poses):
                key=variant+'-'+pose
                if key not in images:continue
                source=images[key];bounds=source.getbbox();label=('军警犬' if y==0 else '盗贼犬')+' · '+labels[x]
                draw.text((x*cellw+16,110+y*cellh),label,font=small,fill='#25333b')
                if bounds is None:
                    draw.text((x*cellw+35,200+y*cellh),'原作空体 / 清理阶段',font=small,fill='#647078');continue
                crop=source.crop(bounds);crop.thumbnail((cellw-36,cellh-70),Image.Resampling.LANCZOS)
                # Upscale native captures uniformly for inspection, with margins.
                scale=min((cellw-36)/crop.width,(cellh-70)/crop.height)
                crop=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.LANCZOS)
                out.alpha_composite(crop,(x*cellw+(cellw-crop.width)//2,145+y*cellh+(cellh-70-crop.height)//2))
        out.convert('RGB').save(args.out/filename)
    sheet('native-actions.png',['idle','walk','attack-open','attack-bite','hit','knockdown','down'],['站立','跑动','张口特写','咬合特写','受击','击倒','倒地'])
    sheet('native-deaths.png',['death-1','death-56'],['死亡起始','原 a2 空体'])
    contact=Image.new('RGB',(900,820),'#d6e9e4');draw=ImageDraw.Draw(contact)
    draw.text((20,12),'口腔修正 · 实际 Flash 张口 / 咬合读回',font=font,fill='#25383c')
    for row,(variant,label) in enumerate((('military','制式军警犬'),('raider','盗贼撕咬犬'))):
        for col,(pose,title) in enumerate((('attack-open','张口 · 第 4 帧'),('attack-bite','咬合 · 第 7 帧'))):
            key=variant+'-'+pose
            if key not in images:continue
            draw.text((col*450+16,55+row*380),label+' · '+title,font=small,fill='#25383c')
            thumb=images[key].resize((450,350),Image.Resampling.LANCZOS)
            contact.paste(thumb,(col*450,80+row*380),thumb)
    contact.save(args.out/'native-mouth-keyframes.png')
    result={'evidence':'actual_flash_BitmapData_from_focused_host','images':len(images),'pendingImages':list(pending),'files':sorted(images),'sourceTrace':str(args.trace.resolve())}
    (args.out/'preview-manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({'nativeImagesDecoded':len(images),'output':str(args.out)},ensure_ascii=False))
if __name__=='__main__':main()
