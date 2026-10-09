"""Offline contact sheet from approved vectors and current published skins."""
import argparse,base64,json,html,re,io
from functools import lru_cache
from pathlib import Path
from lxml import etree as E
import cairosvg
from PIL import Image
import shield_rush as s

ROOT=s.b.ROOT
OUT=ROOT/'tmp/former-sheriff-shield-rush'
M=json.loads((ROOT/'launcher/web/assets/dressup/manifest.json').read_text('utf8'))


def skill_tuning():
    item=E.parse(str(ROOT/'data/items/武器_长枪_霰弹枪.xml')).xpath('//item[name="特勤霰弹枪"]')[0]
    return {e.tag:float(e.text) for e in item.find('skill/parameters')}

def mat(m):return 'matrix('+' '.join(map(str,m))+')'


def scoped_gradients(svg,prefix):
    # Separate renderer instances both start at g1; a beam must never recolor
    # the contact shadow when their definitions share the same SVG document.
    for name in re.findall(r'id="([^"]+)"',svg):
        svg=svg.replace('id="'+name+'"','id="'+prefix+name+'"').replace('url(#'+name+')','url(#'+prefix+name+')')
    return svg

def skin(key):
    info=M['skinKeys'][key];f=info['frames'][0];z=info['export']['zoom']
    png=base64.b64encode((ROOT/'launcher/web/assets/dressup'/f['uri']).read_bytes()).decode()
    return '<image x="%s" y="%s" width="%s" height="%s" href="data:image/png;base64,%s"/>'%(-f['originX']/z,-f['originY']/z,f['width']/z,f['height']/z,png)

def ground(matrix=None):
    r=s.b.reader.Renderer(s.shadow_source().parent,[])
    body=r.render_symbol(s.shadow_source().stem,0,'contact shadow')
    return scoped_gradients('<defs>'+''.join(r.defs)+'</defs><g transform="%s">%s</g>'%(mat(s.shadow_matrix() if matrix is None else matrix),body),'ground-')


@lru_cache(None)
def beam_art():
    renderer=s.b.reader.Renderer(s.b.OWNER/'LIBRARY',[])
    body=renderer.render_symbol(s.b.PREFIX+'武器/特勤手电光束',0,'same flashlight beam')
    return scoped_gradients('<defs>'+''.join(renderer.defs)+'</defs>'+body,'torch-')


@lru_cache(None)
def weapon_art(frame,face='内侧'):
    root=s.unlit_motion(face,frame)
    m=s.lamp_matrix(frame)
    body=''.join(E.tostring(c,encoding='unicode') for c in root)
    lamp=''.join(E.tostring(c,encoding='unicode') for c in s.lamp_art())
    light='<g transform="%s">%s</g>'%(mat(s.b.writer.mul(m,(1,0,0,1,0,-3))),beam_art())
    glow='<g class="lamp-glow" opacity=".55"><ellipse rx="5" ry="9" fill="#fff0ba" fill-opacity=".13"/><ellipse rx="2.5" ry="6" fill="#fff4d0" fill-opacity=".35"/><ellipse rx="1.1" ry="3.7" fill="#fffae9"/></g>'
    hardware=s.lamp_rail(frame)+'<g transform="%s">%s%s</g>'%(mat(m),lamp,glow)
    # Inner view: the shield face occludes the exterior lamp and its glow.
    return light+hardware+body if face=='内侧' else light+body+hardware


def actor(frame,gender):
    hs,poses=s.poses()
    return dressed(hs,poses[frame],gender)


def dressed(hs,p,gender,order=None,shadow=None):
    out=[ground(shadow)]
    if order is None:order=s.draw_order(hs)
    for i in order:
        field=hs[i]['field'];m=p['parts'][i];art=''
        if field=='长枪_装扮':
            art=weapon_art(p['progress']);m=p['weapon']
        elif field=='脸型':art=skin(gender+'变装-基本脸型')+skin('变装-Codex-重装特勤头盔')
        elif field=='脚':art=skin('变装-Codex-重装特勤战靴')
        elif field in ['右手','左手']:art=skin('变装-Codex-重装特勤'+field)
        elif '_装扮' not in field:art=skin(gender+'变装-Codex-重装特勤'+field)
        if art:out.append('<g transform="%s">%s</g>'%(mat(m),art))
    return ''.join(out)


def blocking(hs,p):
    """A shape-only check of the same authored joints, not a separate rig."""
    out=['<path d="M-52 5H82" stroke="#c6c5bf" stroke-width=".5"/>']
    for field,ends,width in [('上臂',(-47,47),6),('左下臂',(-47,47),6),('右下臂',(-47,47),6),('左大腿',(-60,65),10),('右大腿',(-60,65),10),('小腿',(-68,78),7)]:
        for i,e in enumerate(hs):
            if e['field']!=field:continue
            a,z=[s.point(p['parts'][i],(0,y)) for y in ends]
            out.append('<path d="M%g %gL%g %g" fill="none" stroke="%s" stroke-width="%g" stroke-linecap="round"/>'%(*a,*z,'#667374' if i<10 else '#384d50',width))
            out.append('<circle cx="%g" cy="%g" r="1.7" fill="#d7b777"/>'%a)
    body=p['parts'][next(i for i,e in enumerate(hs) if e['field']=='身体')]
    out.append('<path transform="%s" d="M-64 -87Q-15 -110 51 -75L56 93Q0 123 -62 86Z" fill="#4b6062" stroke="#2b3e40" stroke-width="5"/>'%mat(body))
    head=p['parts'][next(i for i,e in enumerate(hs) if e['field']=='脸型')]
    out.append('<ellipse transform="%s" cx="15" cy="-24" rx="38" ry="47" fill="#a4aaa3" stroke="#354d50" stroke-width="4"/>'%mat(head))
    for i,e in enumerate(hs):
        if e['field']=='脚':out.append('<path transform="%s" d="M-25 4Q0 -10 30 8L45 22H-26Z" fill="#354d50"/>'%mat(p['parts'][i]))
    out.insert(1,'<g transform="%s"><path d="M-111 8L74 8L99 35V458L78 490H-114V38Z" fill="#8d9d98" fill-opacity=".65" stroke="#334f50" stroke-width="8"/><path d="M-87 38H52V70H-87Z" fill="#faf8f2" stroke="#334f50" stroke-width="5"/></g>'%mat(p['weapon']))
    return ''.join(out)


def studies(destination,baseline=None):
    hs,poses=s.poses()
    frames=[14,18,19,21,23,35]
    labels=['架盾','蓄力','前脚着地','后蹬与收腿','腾空迈步','跨步制动']
    for name,draw,height,scale in [('pose-study',lambda p:dressed(hs,p,'男'),420,2.35),('blocking-study',lambda p:blocking(hs,p),330,1.85)]:
        rows=[]
        for i,(f,label) in enumerate(zip(frames,labels)):
            x=i*350
            rows.append('<rect x="%s" width="340" height="%s" rx="8" fill="#faf8f2"/><text x="%s" y="28" font-family="Microsoft YaHei" font-size="18">%s</text><g transform="translate(%s %s) scale(%s)">%s</g>'%(x,height,x+12,label,x+185,height-25,scale,draw(poses[f])))
        svg='<svg xmlns="http://www.w3.org/2000/svg" width="2100" height="%s">%s</svg>'%(height,''.join(rows))
        (destination/(name+'.svg')).write_text(svg,'utf8');cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/(name+'.png')))
    if baseline:
        text=baseline.read_text('utf8')
        old=json.loads(re.search(r'const poses=(\[.*?\]),gun=',text,re.S).group(1))
        rows=[]
        for row,(name,ps,fs) in enumerate([('R35',old,[19,21,25,31]),('R36',poses,[19,21,25,31])]):
            for col,(f,label) in enumerate(zip(fs,['着地','推进','回收','迈步'])):
                x,y=col*350,row*425
                rows.append('<rect x="%s" y="%s" width="340" height="415" rx="8" fill="#faf8f2"/><text x="%s" y="%s" font-family="Microsoft YaHei" font-size="18">%s / %s</text><g transform="translate(%s %s) scale(2.25)">%s</g>'%(x,y,x+12,y+28,name,label,x+185,y+388,dressed(hs,ps[f],'男')))
        svg='<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="850">'+''.join(rows)+'</svg>'
        (destination/'pose-comparison.svg').write_text(svg,'utf8');cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/'pose-comparison.png'))
    rows=[]
    for j in range(s.RUSH_COUNT):
        x,y=j%4*390,j//4*430
        rows.append('<rect x="%s" y="%s" width="380" height="420" rx="8" fill="#faf8f2"/><text x="%s" y="%s" font-size="18" font-family="Microsoft YaHei">跑步 %02d / 16</text><g transform="translate(%s %s) scale(2.25)">%s</g>'%(x,y,x+12,y+28,j+1,x+195,y+393,dressed(hs,poses[s.RUSH_START+j],'男')))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="1560" height="1720">'+''.join(rows)+'</svg>'
    (destination/'run-cycle.svg').write_text(svg,'utf8')
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/'run-cycle.png'))


def motion_preview(destination):
    """Render the native pose sequence at the existing full-charge timing."""
    hs,poses=s.poses();sequence=[];t=skill_tuning()
    speed=8+t['speedBonus'];length=s.RUSH_COUNT*int(t['maxRushLoops']);distance=speed*length
    charge=int(t['maxChargeFrames'])
    sequence += [(0,0,'准备')] * 10
    sequence += [(f,0,'枪盾展开') for f in range(15)]
    sequence += [(15+min(3,int(c*4/charge)),0,'蓄力') for c in range(1,charge+1)]
    sequence += [(19+i%16,speed*i,'冲撞 · 第 %d / 3 轮 · 跑速 8 + 2 = 10'%((i-1)//16+1)) for i in range(1,length+1)]
    last_run=length%16
    sequence += [(s.BRAKE_BANK_START+last_run*s.BRAKE_COUNT+f,distance,'承接迈步刹停') for f in range(s.BRAKE_COUNT)]
    sequence += [(f,distance,'收盾还枪') for f in range(41,56)]
    sequence += [(55,distance,'恢复')] * 8
    images=[];cache={}
    for f,d,label in sequence:
        key=(f,d,label)
        if key not in cache:
            drift=min(d,16);floor=-(d-drift)*2.3
            marks=''.join('<path d="M%g 415l22 -14"/>'%(i*72+floor%72) for i in range(-1,11))
            svg='<svg xmlns="http://www.w3.org/2000/svg" width="680" height="440"><rect width="680" height="440" fill="#242c2d"/><text x="24" y="34" fill="#dfe5e0" font-size="18" font-family="Microsoft YaHei">R42 · %s</text><g stroke="#697570" stroke-width="1.5">%s</g><g transform="translate(%g 397) scale(2.3)">%s</g></svg>'%(label,marks,245+drift*2.3,dressed(hs,poses[f],'男'))
            cache[key]=Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('RGB')
        images.append(cache[key])
    images[0].save(destination/'motion-preview.webp',save_all=True,append_images=images[1:],duration=33,loop=0,quality=90,method=4)


def light_study(destination):
    rows=[]
    frames=[(0,'持枪 / 原灯头'),(6,'展开 / 灯头转移'),(18,'架盾 / 窗下固定'),(23,'盾冲 / 持续照明'),(48,'收盾 / 沿原路回收'),(55,'还枪 / 恢复灯位')]
    for i,(f,label) in enumerate(frames):
        x,y=i%3*560,i//3*450
        rows.append('<g transform="translate(%d %d)"><defs><clipPath id="panel%d"><rect x="4" y="4" width="552" height="442" rx="10"/></clipPath></defs><g clip-path="url(#panel%d)"><rect width="560" height="450" fill="#242c2d"/><text x="24" y="34" font-size="21" font-family="Microsoft YaHei" fill="#dde5df">%s</text><g transform="translate(220 410) scale(2.35)">%s</g></g></g>'%(x,y,i,i,label,actor(f,'男')))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="1680" height="900">'+''.join(rows)+'</svg>'
    (destination/'light-continuity.svg').write_text(svg,'utf8')
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/'light-continuity.png'))

def layering_study(destination):
    hs,poses=s.poses()
    gun=next(i for i,e in enumerate(hs) if e['field']=='长枪_装扮')
    old=[i for i in range(len(hs)) if i!=gun]
    old.insert(old.index(next(i for i,e in enumerate(hs) if e['field']=='左手')),gun)
    # Compare against the rejected R37 order, with all legs under the shield.
    legs=[i for i in old if hs[i]['field'] in {'左大腿','右大腿','小腿','脚'}]
    first=old.index(legs[0]);old=[i for i in old if i not in legs];old[first:first]=legs
    rows=[]
    for row,(label,order) in enumerate([('R37 · 双腿在盾后',old),('R38 · 盾在所有肢体后',s.draw_order(hs))]):
        for col,f in enumerate([21,24,26]):
            x,y=col*400,row*440
            rows.append('<g transform="translate(%d %d)"><defs><clipPath id="layer-%d-%d"><rect width="390" height="430" rx="9"/></clipPath></defs><g clip-path="url(#layer-%d-%d)"><rect width="390" height="430" fill="#faf8f2"/><text x="16" y="30" font-size="19" font-family="Microsoft YaHei">%s / 跑步 %02d</text><g transform="translate(195 398) scale(2.3)">%s</g></g></g>'%(x,y,row,col,row,col,label,f-s.RUSH_START+1,dressed(hs,poses[f],'男',order)))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="880"><rect width="1200" height="880" fill="#e7e4dd"/>'+''.join(rows)+'</svg>'
    (destination/'shield-layering.svg').write_text(svg,'utf8')
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/'shield-layering.png'))


def return_study(destination,baseline):
    hs,poses=s.poses();rows=[]
    old=json.loads(re.search(r'const poses=(\[.*?\]),gun=',baseline.read_text('utf8'),re.S).group(1)) if baseline else poses
    stop=s.BRAKE_BANK_START+9*s.BRAKE_COUNT
    for row,(label,ps,fs) in enumerate([('此前',old,[28,36,41,46,50,55]),('R39',poses,[28,stop+1,41,46,50,55])]):
        for col,f in enumerate(fs):
            x,y=col*330,row*420
            title=['最后一步','落脚承重','开始收盾','折叠与换握','抬枪','交回普通动作'][col]
            rows.append('<g transform="translate(%d %d)"><rect width="322" height="412" rx="9" fill="#faf8f2"/><text x="14" y="30" font-size="17" font-family="Microsoft YaHei">%s / %s</text><g transform="translate(150 385) scale(2.25)">%s</g></g>'%(x,y,label,title,dressed(hs,ps[f],'男')))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="1980" height="840"><rect width="1980" height="840" fill="#e7e4dd"/>'+''.join(rows)+'</svg>'
    (destination/'return-comparison.svg').write_text(svg,'utf8')
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/'return-comparison.png'))
    rows=[]
    for col,(face,label) in enumerate([('外侧','朝向敌人：灯装在盾外'),('内侧','玩家视角：盾面遮住灯头')]):
        rows.append('<g transform="translate(%d 0)"><rect width="480" height="620" rx="10" fill="#293032"/><text x="24" y="40" fill="#e5e8de" font-family="Microsoft YaHei" font-size="22">%s</text><g transform="translate(220 90)">%s</g></g>'%(col*500,label,weapon_art(14,face)))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="620">'+''.join(rows)+'</svg>'
    (destination/'lamp-mount.svg').write_text(svg,'utf8')
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/'lamp-mount.png'))


def shadow_study(destination):
    hs,poses=s.poses();rows=[]
    references=[('原生持枪影子',s.shadow_matrix(),'66.0 × 26.9'),
                ('此前盾冲影子',(.48,0,0,.105,5,5),'83.2 × 18.2'),
                ('R40 · 对齐后',s.shadow_matrix(),'66.0 × 26.9')]
    for col,(label,m,size) in enumerate(references):
        body=scoped_gradients(dressed(hs,poses[55],'男',shadow=m),'shadow-study-%d-'%col)
        rows.append('<g transform="translate(%d 0)"><rect width="440" height="690" rx="10" fill="#faf8f2"/><text x="20" y="36" font-family="Microsoft YaHei" font-size="23">%s</text><text x="20" y="66" font-family="Microsoft YaHei" font-size="16" fill="#637372">影子范围 %s · 同一人物比例</text><g transform="translate(173 410) scale(2.1)">%s</g><path d="M20 465H420" stroke="#d0d6d0"/><text x="20" y="497" font-family="Microsoft YaHei" font-size="17">脚下局部放大</text><defs><clipPath id="foot-%d"><rect x="12" y="510" width="416" height="165"/></clipPath></defs><g clip-path="url(#foot-%d)"><g transform="translate(195 607) scale(4.2)">%s</g></g></g>'%(col*450,label,size,body,col,col,body))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="1350" height="700"><rect width="1350" height="700" fill="#e7e4dd"/>'+''.join(rows)+'</svg>'
    (destination/'shadow-comparison.svg').write_text(svg,'utf8')
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/'shadow-comparison.png'))


def opening_study(destination,baseline):
    hs,poses=s.poses();rows=[]
    old=json.loads(re.search(r'const poses=(\[.*?\]),gun=',baseline.read_text('utf8'),re.S).group(1)) if baseline else poses
    for row,(label,ps) in enumerate([('此前 R40',old),('当前 R41',poses)]):
        for col,(f,title) in enumerate([(55,'施放前持枪'),(0,'进入战技'),(3,'下压转盾'),(7,'展开换握'),(14,'进入架盾')]):
            body=scoped_gradients(dressed(hs,ps[f],'男'),'entry-%d-%d-'%(row,col))
            rows.append('<g transform="translate(%d %d)"><rect width="350" height="425" rx="9" fill="#faf8f2"/><text x="14" y="28" font-size="18" font-family="Microsoft YaHei">%s / %s</text><g transform="translate(146 392) scale(2.25)">%s</g></g>'%(col*360,row*435,label,title,body))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="870"><rect width="1800" height="870" fill="#e7e4dd"/>'+''.join(rows)+'</svg>'
    (destination/'opening-comparison.svg').write_text(svg,'utf8')
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(destination/'opening-comparison.png'))


def run():
    OUT.mkdir(exist_ok=True,parents=True)
    rows=[]
    for gender in ['男','女']:
        for frame in [0,4,9,14,18,19,23,29,35,55]:
            x=[0,4,9,14,18,19,23,29,35,55].index(frame)%5*390
            y=(0 if gender=='男' else 2)*490+[0,4,9,14,18,19,23,29,35,55].index(frame)//5*490
            rows.append('<rect x="%s" y="%s" width="382" height="482" rx="8" fill="#faf9f5"/>'%(x,y))
            rows.append('<text x="%s" y="%s" font-family="Microsoft YaHei" font-size="18">%s / %s</text>'%(x+12,y+28,gender,frame+1))
            rows.append('<g transform="translate(%s %s) scale(2.65)">%s</g>'%(x+195,y+446,actor(frame,gender)))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="1950" height="1960"><rect width="1950" height="1960" fill="#e7e4dd"/>'+''.join(rows)+'</svg>'
    (OUT/'pose-contact.svg').write_text(svg,'utf8');cairosvg.svg2png(bytestring=svg.encode(),write_to=str(OUT/'pose-contact.png'))
    print(OUT/'pose-contact.png')

def review(destination):
    """Interactive source preview. It is explicitly not a Flash gameplay test."""
    destination.mkdir(parents=True,exist_ok=True)
    hs,poses=s.poses();defs=[];keys={};actors=[]
    for f,p in enumerate(poses):defs.append('<g id="block%d">%s</g>'%(f,blocking(hs,p)))
    gun=next(i for i,e in enumerate(hs) if e['field']=='长枪_装扮')
    order=s.draw_order(hs)
    for f in range(15):
        defs.append('<g id="shield%d">%s</g>'%(f,weapon_art(f)))
    for g,gender in enumerate(['男','女']):
        uses=[ground()]
        for i in order:
            field=hs[i]['field'];ids=[]
            if i==gun:ids=['shield0']
            elif field=='脸型':ids=[gender+'变装-基本脸型','变装-Codex-重装特勤头盔']
            elif field=='脚':ids=['变装-Codex-重装特勤战靴']
            elif field in ['右手','左手']:ids=['变装-Codex-重装特勤'+field]
            elif '_装扮' not in field:ids=[gender+'变装-Codex-重装特勤'+field]
            references=[]
            for key in ids:
                if key.startswith('shield'):sid=key
                else:
                    if key not in keys:
                        keys[key]='skin'+str(len(keys));defs.append('<g id="%s">%s</g>'%(keys[key],skin(key)))
                    sid=keys[key]
                references.append('<use href="#%s"/>'%sid)
            uses.append('<g id="p%d-%d">%s</g>'%(g,i,''.join(references)))
        actors.append('<g id="actor%d" transform="translate(%d 475) scale(2.65)"><g class="dressed">%s</g><use class="blocking" href="#block0" style="display:none"/></g>'%(g,235+450*g,''.join(uses)))
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>特勤盾冲 · 长枪吸血继承 R44</title><style>
body{margin:0;background:#eeeae2;color:#263438;font:16px/1.7 'Microsoft YaHei',sans-serif}main{max-width:1050px;margin:auto;padding:32px 24px}h1{font-size:30px;margin:0}p{max-width:880px;color:#526064}small{color:#697577}svg{width:100%;max-height:650px;background:#faf8f2;border:1px solid #d7d4cb;border-radius:12px}button,input{font:inherit}button{background:#faf8f2;border:1px solid #bfc8c6;border-radius:7px;padding:10px 18px;cursor:pointer;touch-action:none}button:active{background:#b5d1cc}.controls{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:14px 0}input{flex:1;min-width:180px;accent-color:#356e70}table{border-collapse:collapse;width:100%;margin:25px 0}td,th{text-align:left;padding:10px;border-bottom:1px solid #d7d4cb}.note{border-left:3px solid #356e70;padding-left:15px}a{color:#356e70}
</style><main><small>前治安官装备 / R44</small><h1>防御力伤害，继承长枪吸血</h1><p>三级单次撞击以施放时防御力为基底，普通射击保持原有威力与加成。保留跑速＋2、三级一至三轮跑步和全程转向。</p>
<p>速度降低为施放时玩家跑速＋2。一级冲一轮，二级两轮，三级三轮；每轮完整播放 16 帧跑步动作。按住 F 蓄力，松开发动；展开、蓄力、冲刺、刹停、收枪均可左右转向，冲刺时还能上下调整路线。</p>
<p>持用特勤霰弹枪，按住战技键 <b>F</b>：变盾后蓄力，松开发动冲撞；蓄满自动冲出，刹停后收盾还枪。下方可对照男女装扮与各阶段姿态。</p>
<svg id="stage" style="background:#242c2d" viewBox="0 0 900 520" xmlns="http://www.w3.org/2000/svg"><defs>__DEFS__<pattern id="floor" width="100" height="520" patternUnits="userSpaceOnUse"><path d="M15 490 L35 475 M65 510 L85 495" stroke="#78837b" stroke-width="2"/></pattern></defs><rect id="groundTrack" y="465" width="900" height="55" fill="url(#floor)"/><text x="30" y="35" fill="#98a9a8" font-size="16">男装扮</text><text x="480" y="35" fill="#98a9a8" font-size="16">女装扮</text>__ACTORS__</svg>
<div class="controls"><button id="hold">按住蓄力 / 松开盾冲</button><button id="tap">一级 · 一轮</button><button id="mid">二级 · 两轮</button><button id="full">三级 · 三轮</button><button id="reset">归位</button></div>
<div class="controls"><button data-move="left">← 转左</button><button data-move="right">转右 →</button><button data-move="up">↑ 向上换线</button><button data-move="down">↓ 向下换线</button><span>也可用 WASD／方向键。游戏沿用你的方向键设置。</span></div>
<div class="controls"><label for="runSpeed">玩家跑速</label><input id="runSpeed" type="range" min="0" max="40" step="1" value="8"><span id="speedSummary"></span></div>
<div class="controls"><button id="blockToggle">查看简化人形</button><button id="mirror">切换朝向</button><button id="background">切换浅色背景</button><label>播放速度 <select id="speed"><option value="1">正常</option><option value="0.5">半速</option><option value="0.25">四分之一</option></select></label></div>
<div class="controls"><input id="scrub" type="range" min="0" max="55" value="0" aria-label="动作帧"><span id="frame">1 / 56</span></div><p id="status">待机 · 按住按钮或 F 开始</p>
<p class="note">灯头位于朝向敌人的盾外面；玩家看到的内侧盾面遮住灯壳与光晕，光束从边缘外射出。展开与收回沿用同一灯位。启动只出现一次短促的灯头亮度变化，没有新增眩晕或伤害属性。本页是源稿与装扮的离线预览；光束来自同一原生素材，深色背景用于检查连续性，不模拟游戏场景的原生照明。</p>
<table><tr><th>项目</th><th>当前占位</th></tr><tr><td>消耗 / 冷却</td><td>30 MP / 8 秒；不消耗霰弹</td></tr><tr><td>变盾 / 还枪</td><td>各 15 帧</td></tr><tr><td>蓄力档位</td><td>轻点一级；蓄力满 18 帧二级；满 36 帧三级并自动发动</td></tr><tr><td>冲刺循环</td><td>1 / 2 / 3 轮，每轮 16 帧，共 16 / 32 / 48 帧</td></tr><tr><td>冲撞速度</td><td>施放时玩家跑速＋2；蓄力不改变速度</td></tr><tr><td>跑速 8 的直线距离</td><td>一级 160；二级 320；三级 480</td></tr><tr><td>转向</td><td>全程左右转向；冲刺中上下换线，纵向速度为横向的一半</td></tr><tr><td>持盾防护</td><td>50% 减伤、抗打断与防御力 × 1 的临时护盾；护盾不回充，收盾或中断时移除</td></tr><tr><td>沿途判定</td><td>最多间隔 3 帧，高速提前补判；转向前后分别计算路径，每帧最多一次</td></tr><tr><td>撞击吸血</td><td>继承施放时的长枪吸血，加上角色当前基础吸血一次；枪自带 3%，角色另有 2% 时合计 5%。继续遵循目标护盾和实际伤害的吸血结算规则。</td></tr><tr><td>每次撞击倍率</td><td>三级分别为施放时防御力 × 0.6 / 1.0 / 1.4；防御 1000 时为 600 / 1000 / 1400。锁定施放时数值，破盾不降低伤害；强度待实战调节</td></tr></table>
<p>上述数值是单次撞击送入近战结算的威力；目标防御等仍参与最终伤害结算，多次命中不能直接按一次倍率估算整招。防御为 0 或无效时保留移动与减伤，不产生伤害判定。</p><p>本轮动作图沿用 R42，实际 Flash 关键帧来自 R44 专项回归。本轮也通过实际吸血处理器核对了 HP 增量；这是隔离场景中的运行回归，尚未替代正式游戏实战。</p><p>按左手持盾、观察盾牌内侧的视角，盾牌放在所有肢体之后。保留既有迈步跑、刹停与收枪动作，影子沿用已校准的玩家原生大小和落点。高速移动的地形检查步长不超过 8，命中区域覆盖采样间走过的路段；这些碰撞行为由 Flash 专项验证，本页只演示姿态、速度和路程。</p>
<img src="light-continuity.png" alt="从持枪、展开、持盾、盾冲到收盾的灯位连续性" style="width:100%;border-radius:10px">
<p>以下六张简化姿态与完整装扮使用同一组关节。可在上方切换简化人形，先检查重心和步幅。</p><img src="blocking-study.png" alt="架盾、蓄力、着地、蹬伸、腾空、制动六个关键姿态" style="width:100%"><img src="pose-study.png" alt="相同姿态套回重装特勤装备" style="width:100%">
<p>盾灯参考：<a href="https://www.foxfury.com/product/taker-b70-ballistic-shield-light/">FoxFury Taker B70 防弹盾灯</a>具有常亮及闪烁模式。本装备使用原有枪灯转移到盾外侧的设计，发光位置避开观察窗与握柄。</p>
<p><a href="pose-contact.png">查看完整装扮动作分解</a> · <a href="run-cycle.png">查看全部跑步姿态</a> · <a href="actual-flash-contact.png">查看实际 Flash 专项的关键帧</a> · 专项测试未装入基础人脸库，截图目镜内的空白不代表正式装扮的面部效果。</p>
<script>const poses=__POSES__,gun=__GUN__,count=__COUNT__,tuning=__TUNING__;let phase='idle',age=0,charge=0,held=false,released=false,ratio=0,level=1,runFrames=16,distance=0,positionX=0,positionZ=0,facing=1,block=false,brakeStart=56,rushSpeed=10,stopChargeAt=Infinity,holdPointer=false,keyHeld=false;
const move={left:false,right:false,up:false,down:false};
const scrub=document.getElementById('scrub'),status=document.getElementById('status');
const runSpeed=document.getElementById('runSpeed');function speedSummary(){const r=+runSpeed.value,v=r+tuning.speedBonus;document.getElementById('speedSummary').textContent=r+' + '+tuning.speedBonus+' = '+v+'／帧 · 三级直线 '+v*16*tuning.maxRushLoops}runSpeed.oninput=speedSummary;speedSummary();
function chargeLevel(){return 1+Math.min(tuning.maxRushLoops-1,Math.floor(charge*(tuning.maxRushLoops-1)/tuning.maxChargeFrames))}
function draw(f){const p=poses[f];document.querySelectorAll('.lamp-glow').forEach(e=>e.setAttribute('opacity',.55+.4*(phase==='rush'?Math.max(0,1-age/6):0)));for(let g=0;g<2;g++){document.querySelector('#actor'+g+' .blocking').setAttribute('href','#block'+f);for(let i=0;i<count;i++){const el=document.getElementById(`p${g}-${i}`);if(!el)continue;el.setAttribute('transform','matrix('+(i===gun?p.weapon:p.parts[i]).join(' ')+')');if(i===gun)el.firstElementChild.setAttribute('href','#shield'+p.progress)}}scrub.value=f;document.getElementById('frame').textContent=(f<56?(f+1)+' / 56':'刹停过渡 '+((f-56)%6+1)+' / 6')}
function travel(){const dx=Math.max(-16,Math.min(positionX,16)),dz=Math.max(-12,Math.min(positionZ,12));document.getElementById('floor').setAttribute('patternTransform',`translate(${-(positionX-dx)*2.65} ${-(positionZ-dz)*2.65})`);for(let g=0;g<2;g++)document.getElementById('actor'+g).setAttribute('transform',`translate(${235+450*g+dx*2.65} ${475+dz*2.65}) scale(${facing*2.65} 2.65)`)}
function start(h){if(phase!=='idle')return;held=h;released=false;phase='open';age=0;charge=0;level=1;distance=positionX=positionZ=0;stopChargeAt=Infinity;rushSpeed=+runSpeed.value+tuning.speedBonus;travel();draw(0)}
function rush(){level=chargeLevel();ratio=(level-1)/(tuning.maxRushLoops-1);runFrames=16*level;phase='rush';age=0;draw(19)}
function reset(){phase='idle';held=keyHeld=holdPointer=released=false;age=charge=distance=positionX=positionZ=0;Object.keys(move).forEach(k=>move[k]=false);travel();draw(0);status.textContent='待机 · 按住按钮或 F 开始'}
function tick(){if(phase==='idle')return;if(move.right)facing=1;else if(move.left)facing=-1;if(!held&&(phase==='open'||phase==='hold'))released=true;age++;if(phase==='open'){draw(Math.min(14,age));if(age>=15){phase='hold';age=0;if(released)rush()}}else if(phase==='hold'){if(released)rush();else{charge++;draw(15+Math.min(3,Math.floor(charge*4/tuning.maxChargeFrames)));if(charge>=tuning.maxChargeFrames)rush();else if(charge>=stopChargeAt)held=false}}else if(phase==='rush'){distance+=rushSpeed;positionX+=facing*rushSpeed;positionZ+=(move.up?-1:move.down?1:0)*rushSpeed*tuning.laneSpeedRatio;draw(19+age%16);if(age>=runFrames){brakeStart=56+(age%16)*6;phase='brake';age=0}}else if(phase==='brake'){draw(brakeStart+Math.min(5,age-1));if(age>=6){phase='close';age=0}}else if(phase==='close'){draw(41+Math.min(14,age-1));if(age>15)phase='idle'}travel();status.textContent=({open:'枪械展开',hold:'持盾蓄力',rush:'冲刺',brake:'跨步制动',close:'收盾还枪',idle:'完成 · 恢复持枪'})[phase]+' · '+chargeLevel()+'级 / '+chargeLevel()+'轮 · 速度 '+rushSpeed+'／帧 · 路程 '+distance+' · 横向 '+positionX+' / 纵向 '+positionZ}
let last=performance.now(),clock=0;function animate(now){clock+=Math.min(100,now-last)*+document.getElementById('speed').value;last=now;while(clock>=1000/30){tick();clock-=1000/30}requestAnimationFrame(animate)}requestAnimationFrame(animate);
document.getElementById('blockToggle').onclick=()=>{block=!block;document.querySelectorAll('.dressed').forEach(e=>e.style.display=block?'none':'');document.querySelectorAll('.blocking').forEach(e=>e.style.display=block?'':'none');document.getElementById('blockToggle').textContent=block?'查看完整装备':'查看简化人形'};document.getElementById('mirror').onclick=()=>{facing=-facing;travel()};
let dark=true;document.getElementById('background').onclick=()=>{dark=!dark;document.getElementById('stage').style.background=dark?'#242c2d':'#faf8f2';document.getElementById('background').textContent=dark?'切换浅色背景':'切换深色背景'};
document.getElementById('hold').onpointerdown=e=>{e.preventDefault();holdPointer=true;start(true)};
function releasePointer(){if(holdPointer){holdPointer=false;held=keyHeld}document.querySelectorAll('[data-move]').forEach(b=>move[b.dataset.move]=false)}window.addEventListener('pointerup',releasePointer);window.addEventListener('pointercancel',releasePointer);
document.querySelectorAll('[data-move]').forEach(b=>{b.onpointerdown=e=>{e.preventDefault();move[b.dataset.move]=true}});
const movementKeys={KeyA:'left',ArrowLeft:'left',KeyD:'right',ArrowRight:'right',KeyW:'up',ArrowUp:'up',KeyS:'down',ArrowDown:'down'};
window.addEventListener('keydown',e=>{if(e.target&&e.target.matches('input,select'))return;if(e.code==='KeyF'){e.preventDefault();keyHeld=true;if(!e.repeat)start(true)}else if(movementKeys[e.code]){e.preventDefault();move[movementKeys[e.code]]=true}});
window.addEventListener('keyup',e=>{if(e.code==='KeyF'){keyHeld=false;held=holdPointer}else if(movementKeys[e.code])move[movementKeys[e.code]]=false});window.addEventListener('blur',()=>{held=keyHeld=holdPointer=false;Object.keys(move).forEach(k=>move[k]=false)});
document.getElementById('tap').onclick=()=>{reset();start(false)};document.getElementById('mid').onclick=()=>{reset();start(true);stopChargeAt=tuning.maxChargeFrames/2};document.getElementById('full').onclick=()=>{reset();start(true)};document.getElementById('reset').onclick=reset;scrub.oninput=()=>{phase='idle';distance=positionX=positionZ=0;travel();draw(+scrub.value);status.textContent='逐帧查看 · '+(+scrub.value+1)+' / 56'};draw(0);
</script></main></html>'''
    page=page.replace('__DEFS__',''.join(defs)).replace('__ACTORS__',''.join(actors)).replace('__POSES__',json.dumps(poses)).replace('__GUN__',str(gun)).replace('__COUNT__',str(len(hs))).replace('__STRIDE__',str(s.STRIDE_STEP)).replace('__TUNING__',json.dumps(skill_tuning()))
    page=page.replace('<table>', '<p>外侧灯头与内侧遮挡对照：</p><img src="lamp-mount.png" alt="盾外装灯，内侧不透光" style="width:100%;border-radius:10px"><p>既有收势修正对照：本轮保留这些动作。</p><img src="return-comparison.png" alt="从刹停到持枪的衔接对照" style="width:100%;border-radius:10px"><table>')
    if (destination/'pose-comparison.png').exists():
        page=page.replace('<table>', '<p>上排 R35 / 下排 R36，跑步周期对照</p><img src="pose-comparison.png" alt="R35 与 R36 跑步周期对照" style="width:100%;border-radius:10px"><table>')
    (destination/'review.html').write_text(page,'utf8')
    print(destination/'review.html')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--review',type=Path);parser.add_argument('--baseline',type=Path);parser.add_argument('--ending-baseline',type=Path);parser.add_argument('--opening-baseline',type=Path);args=parser.parse_args()
    run()
    if args.review:
        args.review.mkdir(parents=True,exist_ok=True)
        (args.review/'pose-contact.png').write_bytes((OUT/'pose-contact.png').read_bytes())
        studies(args.review,args.baseline)
        motion_preview(args.review)
        light_study(args.review)
        layering_study(args.review)
        return_study(args.review,args.ending_baseline)
        shadow_study(args.review)
        opening_study(args.review,args.opening_baseline)
        review(args.review)
