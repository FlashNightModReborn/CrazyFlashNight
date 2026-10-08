"""Assemble original battle holders using PNGs read from the published SWF.

This is an offline fit preview, not gameplay or save/reload evidence. Using the
actual exported pixels also avoids the source reader's native fill limitations.
"""
import base64, json
from pathlib import Path
import build as b
import cairosvg

OUT = b.ROOT/'tmp/former-sheriff-integration'
OUT.mkdir(parents=True, exist_ok=True)
manifest = json.loads((b.ROOT/'launcher/web/assets/dressup/manifest.json').read_text('utf8'))
fields = ['身体','上臂','左下臂','右下臂','左手','右手','屁股','左大腿','右大腿','小腿','脚']

def transform(m):
    return 'matrix('+' '.join(str(m.get(k,v)) for k,v in zip(['a','b','c','d','tx','ty'],b.I))+')'

def skin_image(key):
    basic=manifest['skinKeys'][key]
    if not basic or not basic.get('frames'):
        return ''
    f=basic['frames'][0];z=basic['export']['zoom']
    data=base64.b64encode((b.ROOT/'launcher/web/assets/dressup'/f['uri']).read_bytes()).decode()
    image='<image x="%s" y="%s" width="%s" height="%s" href="data:image/png;base64,%s"/>' % (-f['originX']/z,-f['originY']/z,f['width']/z,f['height']/z,data)
    return '<g transform="%s">%s</g>'%(transform(basic.get('matrix',{})),image)

def draw(gender, state, helmet):
    out=[]
    for holder in manifest['rigs']['battle']['genders'][gender]['states'][state]['holders']:
        field=holder['field'];key=None;content=''
        if field in fields:
            if field in ['左手','右手']:
                key='变装-Codex-重装特勤'+field
            elif field=='脚':
                key='变装-Codex-重装特勤战靴'
            else:
                key=gender+'变装-Codex-重装特勤'+field
        elif field=='脸型':
            key=gender+'变装-基本脸型'
        elif field=='面具' and helmet:
            key='变装-Codex-重装特勤头盔'
        elif field=='发型' and not helmet and gender=='男':
            key='发型-男式-Codex-治安官'
        elif field=='长枪_装扮' and state=='长枪站立':
            key='枪-长枪-Codex-特勤霰弹枪'
        elif field=='手枪_装扮' and state=='手枪站立':
            key='枪-手枪-Codex-特勤沙鹰'
        elif field in ['刀_装扮','刀1_装扮'] and state=='兵器站立':
            key='刀-Codex-特勤警棍'
        if key:
            content=skin_image(key)
        if content:
            out.append('<g transform="%s">%s</g>'%(transform(holder['matrix']),content))
    return ''.join(out)

body=[]
card_widths=[510,510,620,510,510]
for row,gender in enumerate(['男','女']):
    for col,(state,helmet) in enumerate([('空手站立',False),('空手站立',True),('长枪站立',True),('手枪站立',True),('兵器站立',True)]):
        x=25+sum(card_widths[:col])+col*10;y=20+row*550
        body.append('<rect x="%s" y="%s" width="%s" height="530" rx="12" fill="#faf9f5"/>'%(x,y,card_widths[col]))
        label=' / 头盔' if helmet else (' / 发型' if gender=='男' else ' / 基础脸型')
        body.append('<text x="%s" y="%s" font-family="Microsoft YaHei" font-size="19" fill="#26343c">%s / %s%s</text>'%(x+15,y+32,gender,state,label))
        body.append('<g transform="translate(%s %s) scale(3.25)">%s</g>'%(x+145,y+485,draw(gender,state,helmet)))
width=50+sum(card_widths)+40
svg='<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="1120"><rect width="%s" height="1120" fill="#e7e4dd"/>'%(width,width)+''.join(body)+'</svg>'
(OUT/'player-published-fit.svg').write_text(svg,'utf8')
cairosvg.svg2png(bytestring=svg.encode(),write_to=str(OUT/'player-published-fit.png'))
print('Original battle holders + actual published pixels:',OUT/'player-published-fit.png')
