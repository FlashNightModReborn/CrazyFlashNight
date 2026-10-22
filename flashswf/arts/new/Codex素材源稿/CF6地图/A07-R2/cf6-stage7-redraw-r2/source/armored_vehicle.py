"""Stage 7 armored carrier: original-coordinate, editable SVG reconstruction.

Authored from visual observation of bitmap 1806/1808 and audited SWF geometry.
All silhouette, plates, gun, fittings, typography and wheel geometry is new vector
work. Only the optional deterministic painted-metal grain is a generated bitmap;
no original RGB pixels are reused. Typeface outlines: DejaVu Serif Bold (system).
Run this file to reproduce both native SVGs and same-scale review images.
"""
from pathlib import Path
import base64, io, json, hashlib, math, sys
import numpy as np
from PIL import Image, ImageDraw
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from svg_native import write_part, render, inner

R = Path(__file__).resolve().parents[1]
SEED = 18061808
REV = sys.argv[1] if len(sys.argv)>1 else 'r2'
rng = np.random.default_rng(SEED)

def path(d, fill, stroke=None, width=.65, extra=''):
    return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{width}"' if stroke else '')+f' {extra}/>'

def line(d, col='#65717a', width=.5, opacity=.6):
    return path(d,'none',col,width,f'opacity="{opacity}" stroke-linecap="round" stroke-linejoin="round"')

def circle(x,y,r,fill,stroke=None,width=.5,extra=''):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{width}"' if stroke else '')+f' {extra}/>'

def bolt(x,y,r=.75):
    return circle(x+.15,y+.25,r+.25,'#11171a')+circle(x,y,r,'#414a50')+line(f'M{x-r*.45} {y-r*.4}h{r*.8}', '#9ba6ab', .28,.75)+line(f'M{x-.25} {y+.1}l.5 -.2','#151c20',.23,1)

def lettering(text,x,y,w,h):
    font=TTFont('/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf')
    gs=font.getGlyphSet();cm=font.getBestCmap();cursor=0;out=[]
    for c in text:
        glyph=gs[cm[ord(c)]];pen=SVGPathPen(gs);glyph.draw(pen)
        out.append(f'<path transform="translate({cursor} 0)" d="{pen.getCommands()}"/>');cursor+=glyph.width
    # Capitals/figures share cap height; all type is embedded as editable paths.
    return f'<g fill="#b2b7b3" stroke="#b2b7b3" stroke-width="15" transform="translate({x} {y+h}) scale({w/cursor} {-h/1493})">'+''.join(out)+'</g>'

BODY = 'M19 78L103 67L105 77L111 62L115 57L115 0L119 0L119 51L146 54L151 58L151 48L169 44L170 60L188 60L191 57L195 57L196 61L199 62L198 68L171 69L171 74L232 74L254 92L286 85L331 84L332 105L363 152L368 153L369 161L371 163L371 181L339 199L324 207L324 212L273 222L273 212L267 208L263 211L256 221L244 229L233 227L226 221L163 222L163 212L154 208L150 213L143 224L132 230L121 228L112 219L108 212L99 217L85 216L78 211L74 208L70 213L64 225L51 230L39 227L31 217L29 214L5 215L2 211L0 202L0 184L3 183L3 115L19 85Z'

def grain():
    w,h=1113,708
    fine=rng.normal(0,1,(h,w));coarse=np.array(Image.fromarray(rng.integers(0,255,(90,140),dtype=np.uint8)).resize((w,h),Image.Resampling.BICUBIC))/255-.5
    a=np.clip(np.abs(fine)*10+np.abs(coarse)*12,0,29).astype('uint8')
    rgb=np.where((fine+coarse)[...,None]>0,np.array([157,169,177]),np.array([0,3,5]))
    rgba=np.dstack([np.broadcast_to(rgb,(h,w,3)),a]).astype('uint8')
    im=Image.fromarray(rgba);b=io.BytesIO();im.save(b,format='PNG')
    return base64.b64encode(b.getvalue()).decode()

def make_body():
    s='''<defs>
    <linearGradient id="side" x1="0" y1="0" x2=".18" y2="1"><stop stop-color="#35414b"/><stop offset=".42" stop-color="#293139"/><stop offset="1" stop-color="#20282d"/></linearGradient>
    <linearGradient id="rear" x2="1" y2="0"><stop stop-color="#28323a"/><stop offset=".45" stop-color="#34414b"/><stop offset="1" stop-color="#202b33"/></linearGradient>
    <linearGradient id="roof" x1="0" y1="0" x2=".1" y2="1"><stop stop-color="#52616d"/><stop offset=".15" stop-color="#3b4954"/><stop offset="1" stop-color="#263039"/></linearGradient>
    <linearGradient id="slope" x1=".1" y1="0" x2=".8" y2="1"><stop stop-color="#2a333c"/><stop offset=".45" stop-color="#455562"/><stop offset=".7" stop-color="#394651"/><stop offset="1" stop-color="#28343d"/></linearGradient>
    <linearGradient id="edge" x2="0" y2="1"><stop stop-color="#60717f"/><stop offset=".2" stop-color="#36434f"/><stop offset=".75" stop-color="#202b33"/><stop offset="1" stop-color="#0f171d"/></linearGradient>
    <linearGradient id="gun" x2="0" y2="1"><stop stop-color="#151c21"/><stop offset=".27" stop-color="#48525a"/><stop offset=".45" stop-color="#313b43"/><stop offset="1" stop-color="#10171c"/></linearGradient>
    <linearGradient id="cupola" x2="1" y2=".15"><stop stop-color="#202a32"/><stop offset=".35" stop-color="#3c4a56"/><stop offset=".68" stop-color="#2b3741"/><stop offset="1" stop-color="#161f26"/></linearGradient>
    <linearGradient id="glass" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#10181d"/><stop offset=".58" stop-color="#17252d"/><stop offset=".75" stop-color="#344853"/><stop offset="1" stop-color="#111a20"/></linearGradient>
    <radialGradient id="underwheel"><stop stop-color="#30373b"/><stop offset=".55" stop-color="#151a1d"/><stop offset="1" stop-color="#080c0e"/></radialGradient>
    <clipPath id="bodyClip">'''+path(BODY,'white')+'''</clipPath></defs>'''
    s+=path(BODY,'#10171c','#070c0f',.7)
    # Chassis and separate wheel wells retain the original footprint under rotation.
    s+=path('M2 183L268 183L285 210L273 222L272 211L263 207L258 210L229 216L220 222H163V211L153 207L148 212L113 216L107 210L98 217H85L77 210L71 207L65 214L5 215L1 207Z','#10171b','#080d10')
    s+=path('M2 185H35L21 214L6 214L2 202Z','url(#side)','#0c1216')
    s+=path('M73 187H106L112 209L101 215H86L80 210Z','url(#side)','#10181c')
    s+=path('M148 187H228L218 221H164V210L158 210Z','url(#side)','#10181c')
    s+=path('M2 185H35L21 214L6 214L2 202ZM73 187H106L112 209L101 215H86L80 210ZM148 187H228L218 221H164V210L158 210Z','#09121a',extra='opacity=".24"')
    s+=line('M4 189H29M77 192H104M83 197H105M154 190H223','#4b565e',.55,.5)
    for x,y in [(52.7,210),(131.2,211.5),(244.65,211)]:
        s+=circle(x,y,20,'url(#underwheel)','#0a1013',.8)+circle(x,y,13,'#161d21','#41494e',.8)+circle(x,y,10.6,'#20282e','#080d10',1.5)+circle(x,y,7.2,'#303a42','#11191e',.7)
    # Main rear box, roof facet and slanted front armor.
    s+=path('M3 114H72V183H3Z','url(#rear)','#111b23',.8)
    s+=path('M72 114H145V183H72Z','url(#side)','#121b22',.75)
    s+=path('M145 114H219L222 184H145Z','url(#side)','#121b22',.8)
    s+=path('M3 114L20 85L158 84L145 114Z','url(#roof)','#121b22',.9)
    s+=path('M145 114L158 84L218 113Z','url(#rear)','#151e25',.75)
    s+=path('M158 84L232 75L253 93L237 97L237 111L218 114Z','url(#slope)','#141e26',.8)
    s+=path('M71 84L105 77L159 77L171 74H232L158 84Z','url(#roof)','#17232c',.6)
    s+=path('M19 78L104 68L105 78L72 84L20 86Z','url(#roof)','#0e171d',.8)
    s+=path('M20 78L51 78L51 85L20 86Z','#33404a','#0d161c',.7)
    s+=path('M51 78L104 68V77L51 85Z','#15212a','#0c151b',.8)
    s+=line('M21 78L100 69M21 86L31 85M4 115V180','#78848c',.55,.58)
    s+=line('M73 86H157L231 76M147 113L158 86M160 85L215 111','#6b7a86',.55,.48)
    # Forebody flank and raised driver vision slit, angled in perspective.
    s+=path('M219 114L238 112L237 95L283 86L331 85L332 106L279 116L269 169L221 168Z','url(#side)','#0d171e',.9)
    s+=path('M238 95L284 86L330 85L319 90L277 97Z','url(#roof)','#141f27',.65)
    s+=path('M277 97L330 87L331 105L277 116Z','url(#edge)','#111a20',.85)
    s+=path('M281 99L327 90V103L281 111Z','#0b1013','#131b20',.85)
    s+=path('M284 100L324 92V101L284 108Z','url(#glass)','#3a4852',.55)
    s+=line('M286 101L319 95M286 106L315 102','#52636a',.45,.35)
    # The original narrow opening is an armored grille with a deeply inset cavity.
    s+=path('M284 100L324 92V101L284 108Z','#080e12',extra='opacity=".55"')
    for yy in [101.2,103.7,106.2]:
        s+=line(f'M284.8 {yy}L323.3 {yy-7.2}','#070c0f',1.15,1)
        s+=line(f'M285 {yy-.45}L323 {yy-7.65}','#59636a',.38,.65)
    s+=line('M284 100V107M323 93V101','#6d777d',.45,.45)
    for x in [282,325,328]:
        yy=99-(x-282)*.18;s+=line(f'M{x} {yy}v12','#10191f',.8,1)+line(f'M{x+.7} {yy+.3}v10','#70808a',.3,.45)
    # Thick sloped nose: deliberately localized cold-steel reflected light.
    s+=path('M279 115L331 106L364 160L319 173L268 168Z','url(#slope)','#101a23',1)
    s+=path('M331 106L335 109L367 159L364 161Z','#202c35','#111b23',.65)
    s+=path('M279 115L282 119L319 170L315 172L268 168Z','#2b3740','#17212a',.65)
    s+=line('M282 116L330 108L361 159M285 120L317 166','#71838e',.65,.58)
    s+=line('M285 119L326 111M289 124L306 120','#b0bec4',.4,.17)
    s+=path('M220 168L268 168L319 173L369 162L370 181L320 198L273 187L220 185Z','url(#edge)','#10171d',.8)
    s+=path('M273 187L319 191L370 180L339 199L323 207L278 213Z','#263139','#0d161b',.9)
    s+=path('M273 187L278 213L322 207L323 212L273 222Z','#1c272f','#10191f',.75)
    s+=line('M275 188L280 210L335 197M278 215L321 209','#586772',.6,.45)
    for y in [174,179,184]:
        s+=line(f'M319 {y}L369 {y-12}','#080f14',1.5,.95)+line(f'M320 {y-1}L368 {y-12.5}','#77848e',.55,.57)
    s+=line('M320 172L320 191M366 163V182','#101a22',.8,1)
    s+=path('M298 159L310 158L317 164V174L298 171Z','#131e26','#0b141a',.8)
    s+=path('M301 161L310 161L313 164V172L302 171Z','#68838e','#0b151b',.6)
    s+=path('M298 159L310 158L313 161L301 162Z','#4d5b64','#10191f',.55)
    s+=path('M364 151L368 153L369 161L367 160Z','#33454f','#0c151a',.7)
    # Recessed vents, access panels and service seams.
    for d in ['M84 124H128V133H84Z','M242 119L263 118L262 125L242 126Z','M156 173H213L213 180H156Z']:
        s+=path(d,'#0a1218','#3e4c56',.65)
    s+=path('M87 126H126V130H87Z','#161e24')+line('M87 131H126','#55616a',.6,.65)
    s+=line('M244 121L260 120M244 123L260 122','#6e7777',.55,.4)
    s+=path('M159 175H209V178H159Z','#243039')+line('M158 179H211','#5f6b72',.5,.5)
    s+=circle(88,173,4.3,'#0d151b','#414c54',.6)+circle(88,173,1.6,'#29363f')+line('M87 172l1.5 2','#81909a',.5,.5)
    # Rear climbing ladder, with shadow cavities and metal rung shoulders.
    s+=path('M33 85Q33 78 39 79L43 80L43 84L39 84V179H33Z','#1a252d','#091219',1)
    s+=path('M66 84L71 83L70 179H65Z','#1a252d','#091219',1)
    s+=line('M35 178V86Q35 81 39 81H41M67 87V177','#71828e',.65,.62)
    for y in [90,101,113,125,137,149,161,173]:
        s+=path(f'M38 {y}H66V{y+4}H38Z','url(#edge)','#101b23',.6)
        s+=line(f'M39 {y+.6}H65','#81909a',.55,.6)+line(f'M39 {y+3}H64','#0b141a',.6,.9)
    # Turret shield, cupola, antenna, and machine-gun barrel.
    s+=path('M151 48Q161 48 169 44V75L158 78L151 68Z','#1b262e','#0b141a',.85)
    s+=line('M153 49Q161 49 168 46V59','#6a7882',.55,.55)
    s+=path('M114 45V11L116 10V0H119V44Z','url(#gun)','#091115',.6)
    s+=path('M113 44H120V52H113Z','#172128','#0a1116',.6)+line('M116 12V43','#6b7880',.45,.56)
    s+=path('M114 52H119V64L112 69Z','#101a21','#0a1116',.6)
    s+=path('M106 78L110 65L118 57L144 55L153 63L158 77Q134 85 106 78Z','url(#cupola)','#0a141c',.9)
    s+=path('M111 65L118 57Q130 52 145 56L152 64Q132 72 111 65Z','url(#roof)','#0d1921',.65)
    s+=path('M118 56Q130 51 143 55L145 57Q132 61 118 58Z','#364650','#0c1720',.7)
    s+=line('M109 73Q132 79 156 73M119 55Q130 53 141 55','#78909d',.55,.58)
    s+=line('M109 67Q129 74 153 67','#0c1922',.7,1)
    s+=path('M159 60H168V71H159Z','#192329','#070e12',.7)
    s+=path('M164 61L190 60L193 63L190 67L164 68Z','url(#gun)','#0a1218',.6)
    s+=path('M182 60L193 59L197 61L199 63L198 67L183 68Z','url(#gun)','#0a1218',.8)
    s+=path('M188 59L189 57H193V60Z','#25313a','#0b141a',.55)
    s+=line('M165 62L180 62M185 61H193','#7b8992',.55,.65)+line('M181 61V67M195 62V67','#0c151b',.8,1)
    s+=path('M160 70L171 70V76L159 79Z','#19252e','#0c161e',.6)+line('M161 73L169 72','#5e707d',.5,.4)
    # Grain coats paint, without changing silhouette or obscuring plate geometry.
    s+=f'<g clip-path="url(#bodyClip)"><image width="371" height="236" href="data:image/png;base64,{grain()}" opacity=".68"/></g>'
    # Fine fasteners and restrained exposed steel, intentionally non-uniform.
    for x,y in [(7,120),(7,177),(75,118),(75,178),(140,118),(140,178),(151,119),(215,119),(215,179),(161,89),(174,88),(222,81),(226,109),(241,99),(270,102),(326,88),(329,103),(274,165),(360,158),(324,176),(277,216),(21,188),(102,188),(216,188)]:s+=bolt(x,y,.65)
    scuffs=['M9 177h11','M77 181h14','M183 181h19','M158 113l11 -.1','M224 112l9 -1','M239 96l13 -2','M303 89l12 -.8','M324 107l5 -.8','M340 124l3 5','M350 143l6 8','M323 172l8 -2','M323 188l8 -2','M286 208l12 -4','M108 76l2 -5','M153 77l2 -1','M70 148v5']
    for i,d in enumerate(scuffs):s+=line(d,['#83939e','#5e6e78','#9ba6ab'][i%3],.4,[.6,.4,.5][i%3])
    for i in range(80):
        x=float(rng.uniform(78,214));y=float(rng.uniform(91,180))
        if 136<y<170:continue
        s+=line(f'M{x:.2f} {y:.2f}l{rng.uniform(.3,2):.2f} {rng.uniform(-.7,.4):.2f}','#8c999f',.24,float(rng.uniform(.15,.38)))
    # Original military serial layout: outlined letters, physical stencil breaks.
    wear='<rect width="371" height="236" fill="white"/>'
    for x in [89.5,102,111.8,164.9,179.2,193.5,207.7]:
        wear+=path(f'M{x} 140l.55 0l.65 25h-.65Z','black')
    for x,y,w in [(82,149,7),(95,157,8),(109,151,7),(159,155,10),(176,148,8),(192,160,9),(207,149,9)]:
        wear+=path(f'M{x} {y}l{w} -.5v.75l-{w} .5Z','black')
    # Chipped ink is clipped to the letter geometry, so wear never becomes dirt confetti.
    for i in range(430):
        x=float(rng.choice([rng.uniform(81,118),rng.uniform(158,215)]));y=float(rng.uniform(141,164));r=float(rng.uniform(.18,1.25))
        wear+=path(f'M{x:.2f} {y:.2f}l{r:.2f} -.4l.3 {r:.2f}l-{r:.2f} .6Z','black')
    for i in range(55):
        x=float(rng.uniform(166,202));y=float(rng.uniform(121,134));r=float(rng.uniform(.15,.6))
        wear+=path(f'M{x:.2f} {y:.2f}h{r:.2f}v{r:.2f}h-{r:.2f}Z','black')
    s+='<defs><mask id="stencilInk" maskUnits="userSpaceOnUse" x="0" y="0" width="371" height="236">'+wear+'</mask></defs>'
    s+='<g mask="url(#stencilInk)">'+lettering('119',81,141,37,23)+lettering('0193',158,141,57,23)+lettering('C. T',166,121,36,13)+'</g>'
    for j,(x,w) in enumerate([(125,17),(120,35),(128,19),(123,29),(123,28)]):
        yy=143+j*4.3
        for k in range(int(w/1.5)):
            xx=x+k*1.5;hh=float(rng.uniform(1.7,2.4));ww=float(rng.uniform(.7,1.15))
            # Irregular letter-like strokes preserve the source's unreadable microtype silhouette.
            forms=[f'M0 {hh}V0H{ww}V{hh}M0 {hh*.5}H{ww}',f'M{ww} 0H0V{hh}H{ww}M0 {hh*.5}H{ww*.8}',f'M0 {hh}V0L{ww} {hh}V0',f'M0 0H{ww}V{hh}H0Z',f'M0 {hh}V0H{ww}V{hh*.5}H0',f'M0 0V{hh}H{ww}V0']
            s+=f'<g transform="translate({xx:.2f} {yy:.2f})">'+line(forms[int(rng.integers(0,len(forms)))],'#a6adab',.32,.68)+'</g>'
    # Worn original location of the heraldic red-and-gold unit insignia.
    s+=path('M239 148H254L253 162L247 168L240 162Z','#1a2025','#707879',.55)
    s+=path('M242 150H251L251 161L247 165L242 161Z','#54221f','#161b1d',.5)
    s+=path('M238 146L240 140L243 145L247 138L249 145L254 141L254 147Z','#9a792c','#302d1d',.55)
    s+=line('M239 147H254','#d0b15e',.65,.65)
    s+=path('M240 151H252V153H249V160H246V153H243V156H240Z','#b6b7a5')
    s+=line('M243 162L247 164L251 160','#a99b6e',.55,.5)+circle(247,158,1.3,'#8c332a')
    # Bottom-only source strip is intentionally preserved (transparent in source art).
    return s

def make_wheel():
    s='''<defs><radialGradient id="rubber" cx=".36" cy=".30" r=".72"><stop stop-color="#2c3032"/><stop offset=".44" stop-color="#202426"/><stop offset=".7" stop-color="#171b1d"/><stop offset=".84" stop-color="#222729"/><stop offset="1" stop-color="#090c0e"/></radialGradient><radialGradient id="hub" cx=".35" cy=".30"><stop stop-color="#3c4449"/><stop offset=".55" stop-color="#242e34"/><stop offset=".82" stop-color="#172127"/><stop offset="1" stop-color="#354148"/></radialGradient></defs>'''
    s+=circle(22.5,22.5,21.9,'#0b1013','#070b0e',.6)+circle(22.5,22.5,20.9,'url(#rubber)','#343a3d',.45)
    # Staggered crown/shoulder lugs read as tire blocks, not turbine spokes.
    for j in range(36):
        a=j*10
        s+=f'<g transform="rotate({a} 22.5 22.5)">'
        s+=path('M19.7 1.1L22.1 .4L24.1 3.3L21.6 4.1Z','#202528','#060a0c',.5)
        s+=line('M20.2 1.45L21.9 .9L23.5 3.0','#62686b',.38,.50)
        s+=path('M22.3 4.3L24.3 3.5L26.4 6.3L24.3 7.2Z','#252b2e','#0d1114',.5)
        s+=line('M22.8 4.7l1.3 -.6l1.5 2.1','#656d72',.35,.44)
        s+='</g>'
    s+=circle(22.5,22.5,16.2,'none','#0a1013',.65)+circle(22.5,22.5,15.7,'none','#343e43',.35)+circle(22.5,22.5,15.0,'none','#10171c',.6)
    for j in range(60):
        a=2*math.pi*j/60;r=15.0
        x,y=22.5+r*math.cos(a),22.5+r*math.sin(a)
        x2,y2=22.5+(r-.6)*math.cos(a+.025),22.5+(r-.6)*math.sin(a+.025)
        s+=line(f'M{x:.2f} {y:.2f}L{x2:.2f} {y2:.2f}','#56636d',.25,.43)
    s+=circle(22.5,22.5,12.0,'#10171c','#050a0d',.65)+circle(22.5,22.5,11.3,'url(#hub)','#465157',.5)+circle(22.5,22.5,9.1,'#152027','#070e12',.85)
    for j in range(8):
        a=math.pi*j/4
        x,y=22.5+7.6*math.cos(a),22.5+7.6*math.sin(a)
        s+=circle(x,y,1.4,'#070e12','#36444c',.35)+circle(x-.1,y-.15,.58,'#5a666d','#1b272e',.3)
        s+=line(f'M{x:.2f} {y:.2f}L{22.5+5.7*math.cos(a):.2f} {22.5+5.7*math.sin(a):.2f}','#39474f',1,.6)
    s+=circle(22.5,22.5,5.9,'url(#hub)','#0c161c',.8)+circle(22.5,22.5,4.3,'#25333c','#48575f',.4)+line('M19.4 20.2Q22.4 18.2 25.1 20.0','#7c8a92',.35,.45)
    for j in range(85):
        a=float(rng.uniform(0,math.tau));r=float(rng.uniform(12.4,19.7));x=22.5+r*math.cos(a);y=22.5+r*math.sin(a)
        s+=circle(round(x,2),round(y,2),float(rng.uniform(.06,.16)),'#9da0a0',extra='opacity=".23"')
    return s

def compare(i,rev='r1'):
    original=Image.open(R/f'reference/{i}.png').convert('RGBA');new=Image.open(R/f'previews/armored-{i}-{rev}-1x.png').convert('RGBA')
    w,h=original.size
    for scale in [1,4]:
        pad=12;label=22;out=Image.new('RGB',((w*2+pad*3)*scale,(h+label+pad*2)*scale),'#d7dadb');d=ImageDraw.Draw(out)
        for j,im in enumerate([original,new]):
            bg=Image.new('RGBA',(w,h),'#d7dadb');bg.alpha_composite(im)
            out.paste(bg.convert('RGB').resize((w*scale,h*scale),Image.Resampling.NEAREST if scale==1 else Image.Resampling.LANCZOS),((pad+j*(w+pad))*scale,(label+pad)*scale))
            d.text(((pad+j*(w+pad))*scale,8*scale),['ORIGINAL '+str(i),rev.upper()+' VECTOR '+str(i)][j],fill='#202832')
        out.save(R/f'previews/armored-{i}-original-{rev}-{scale}x.png')

def main():
    for i,wh,content in [(1806,(371,236),make_body()),(1808,(45,45),make_wheel())]:
        p=write_part(R/f'parts/bitmap-{i}.svg',[0,0,*wh],content)
        render(p,wh[0],R/f'previews/armored-{i}-{REV}-1x.png')
        render(p,wh[0]*4,R/f'previews/armored-{i}-{REV}-4x.png')
        compare(i,REV)
    centers=[(52.7,210),(131.2,211.5),(244.65,211)]
    s=inner(R/'parts/bitmap-1806.svg','body')
    for j,(x,y) in enumerate(centers):s+=f'<g transform="translate({x-22.5} {y-22.5})">'+inner(R/'parts/bitmap-1808.svg',f'w{j}')+'</g>'
    p=write_part(R/f'previews/armored-assembled-{REV}.svg',[0,0,371,236],s)
    render(p,371,R/f'previews/armored-assembled-{REV}-1x.png')
    render(p,1484,R/f'previews/armored-assembled-{REV}-4x.png')
    orig=Image.open(R/'reference/1806.png').convert('RGBA');wheel=Image.open(R/'reference/1808.png').convert('RGBA')
    for x,y in centers:orig.alpha_composite(wheel,(round(x-22.5),round(y-22.5)))
    new=Image.open(R/f'previews/armored-assembled-{REV}-1x.png').convert('RGBA');out=Image.new('RGBA',(778,282),'#d7dadb');d=ImageDraw.Draw(out)
    out.alpha_composite(orig,(12,34));out.alpha_composite(new,(395,34));d.text((12,8),'ORIGINAL ASSEMBLED',fill='#202832');d.text((395,8),f'{REV.upper()} ASSEMBLED / EXACT WHEEL CENTERS',fill='#202832');out.convert('RGB').save(R/f'previews/armored-assembled-original-{REV}-1x.png')
    evidence={'source':'New hand-authored native SVG reconstruction; visual references 1806/1808; generated stochastic grain, no original RGB reused. Typography outlines from system DejaVu Serif Bold.','seed':SEED,'revision':REV,'review_changes':['Inset front horizontal grille restored','Chipped stencil ink and irregular microtype','Darker coarse diagonal tire blocks, subdued hub rings','Lower fenders darkened; connecting roof plate restored'],'dimensions':{'1806':[371,236],'1808':[45,45]},'audit':{'body_shape':1807,'body_fragments':2,'body_bitmap_translation':[-185.5,-209.1],'wheel_shape':1809,'wheel_animation':1810,'wheel_rotation_frames':20,'root':1813,'root_frames':209,'wheel_centers_bitmap':[[52.7,210],[131.2,211.5],[244.65,211]],'root_geometry_changes':0,'occupant':'unchanged'},'files':{str(i):{'sha256':hashlib.sha256((R/f'parts/bitmap-{i}.svg').read_bytes()).hexdigest()} for i in [1806,1808]}}
    (R/'qa/armored-vehicle-method.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
