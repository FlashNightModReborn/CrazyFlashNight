"""CF6 stage-three lamps, hand-authored editable vector replacement.

All dimensions and positions are expressed in the source bitmap's pixel space.
Reference PNGs are packaged at ../reference; no external audit path is used.
No embedded raster image, auto-traced texture, or flattened SVG is included.
"""
from pathlib import Path
import json
import hashlib
from xml.etree import ElementTree as ET
from svg_native import write_part, render

ROOT = Path(__file__).resolve().parents[1]
PARTS = ROOT / 'parts'


def defs():
    return '''<defs>
  <linearGradient id="brass" x1="0" x2="1" y1="0" y2="0">
    <stop stop-color="#1b150f"/><stop offset=".18" stop-color="#5b3e21"/>
    <stop offset=".37" stop-color="#9f793d"/><stop offset=".47" stop-color="#d0b276"/>
    <stop offset=".56" stop-color="#8c622e"/><stop offset=".76" stop-color="#49311b"/>
    <stop offset="1" stop-color="#241b12"/>
  </linearGradient>
  <linearGradient id="plate" x1="0" x2="1" y1="0" y2=".12">
    <stop stop-color="#21180f"/><stop offset=".16" stop-color="#584124"/>
    <stop offset=".30" stop-color="#a17c42"/><stop offset=".38" stop-color="#b79658"/>
    <stop offset=".46" stop-color="#694a25"/><stop offset=".58" stop-color="#3c2a18"/>
    <stop offset=".8" stop-color="#231910"/><stop offset="1" stop-color="#16120d"/>
  </linearGradient>
  <linearGradient id="rim" x1="0" x2="0" y1="0" y2="1">
    <stop stop-color="#f6e6ad"/><stop offset=".24" stop-color="#c4a164"/>
    <stop offset=".48" stop-color="#785526"/><stop offset=".8" stop-color="#36271a"/>
    <stop offset="1" stop-color="#1f1912"/>
  </linearGradient>
  <linearGradient id="rod" x1="0" x2="1" y1="0" y2=".2">
    <stop stop-color="#9c7542"/><stop offset=".24" stop-color="#50361d"/>
    <stop offset=".49" stop-color="#b29458"/><stop offset=".68" stop-color="#624326"/>
    <stop offset="1" stop-color="#302317"/>
  </linearGradient>
  <linearGradient id="rodRear" x1="0" x2="1" y1="0" y2=".2">
    <stop stop-color="#695031"/><stop offset=".24" stop-color="#34271b"/>
    <stop offset=".49" stop-color="#887047"/><stop offset=".68" stop-color="#48331e"/>
    <stop offset="1" stop-color="#241b13"/>
  </linearGradient>
  <linearGradient id="edgeGlint" x1="0" x2="1" y1="0" y2="0">
    <stop stop-color="#e4d19a" stop-opacity=".08"/>
    <stop offset=".17" stop-color="#e4d19a" stop-opacity=".85"/>
    <stop offset=".3" stop-color="#e4d19a" stop-opacity=".08"/>
    <stop offset=".52" stop-color="#e4d19a" stop-opacity="0"/>
    <stop offset=".74" stop-color="#e4d19a" stop-opacity=".32"/>
    <stop offset="1" stop-color="#e4d19a" stop-opacity=".03"/>
  </linearGradient>
  <linearGradient id="glass" x1="0" x2="1" y1="0" y2=".2">
    <stop stop-color="#d3b875"/><stop offset=".12" stop-color="#f3e2ac"/>
    <stop offset=".38" stop-color="#fff4c9"/><stop offset=".65" stop-color="#f7e7b2"/>
    <stop offset=".88" stop-color="#ead293"/><stop offset="1" stop-color="#c9ab65"/>
  </linearGradient>
  <linearGradient id="glassDepth" x1="0" x2="0" y1="0" y2="1">
    <stop stop-color="#fffadd" stop-opacity=".62"/>
    <stop offset=".42" stop-color="#fff5ca" stop-opacity="0"/>
    <stop offset=".84" stop-color="#a77a33" stop-opacity=".07"/>
    <stop offset="1" stop-color="#fff2b8" stop-opacity=".44"/>
  </linearGradient>
  <radialGradient id="knob" cx=".36" cy=".27" r=".74">
    <stop stop-color="#fff4c4"/><stop offset=".3" stop-color="#e0c67d"/>
    <stop offset=".6" stop-color="#a17b37"/><stop offset=".84" stop-color="#50351b"/>
    <stop offset="1" stop-color="#21190f"/>
  </radialGradient>
  <filter id="softShadow" x="-1" y="-.1" width="3" height="1.5">
    <feGaussianBlur stdDeviation="1.1"/>
  </filter>
</defs>'''


def path(d, fill='none', stroke=None, width=None, extra=''):
    return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+(f' stroke-width="{width}"' if width else '')+f' {extra}/>'


def rod(d, width=1.6, highlight=True, rear=False):
    """Thin wrought warm-metal member: dark side, copper face, fine glint."""
    s = path(d, stroke='#201a12', width=width+.22, extra='stroke-linecap="round" stroke-linejoin="round"')
    s += path(d, stroke='url(#rodRear)' if rear else 'url(#rod)', width=max(.42, width-.65), extra='stroke-linecap="round" stroke-linejoin="round"')
    if highlight:
        opacity='.22' if rear else '.58'
        s += path(d, stroke='url(#edgeGlint)', width=.21, extra=f'stroke-linecap="round" opacity="{opacity}" transform="translate(-.23,-.12)"')
    return s


def ellipse(cx, cy, rx, ry, fill, stroke=None, sw=.6, extra=''):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'


def chandelier_glass(cx, top, w, bottom, bw, name):
    """One of the six original open, flared cream-glass cups."""
    l, r, bl, br = cx-w/2, cx+w/2, cx-bw/2, cx+bw/2
    d = f'M {l} {top} Q {l+.2} {top+2.5} {l+1.7} {top+5} L {bl} {bottom} Q {cx} {bottom+.8} {br} {bottom} L {r-1.7} {top+5} Q {r-.2} {top+2.5} {r} {top} Z'
    s = f'<g id="glass-{name}">'
    s += path(d, 'url(#glass)', '#2e2617', .85)
    s += path(d, 'url(#glassDepth)')
    s += path(f'M {l+1.3} {top+2.1} L {bl+.65} {bottom-1.2}', stroke='#fff9d9', width=.43, extra='opacity=".7"')
    s += path(f'M {r-1.35} {top+2.6} L {br-.6} {bottom-1}', stroke='#b69555', width=.45, extra='opacity=".32"')
    s += path(f'M {bl+.4} {bottom-1.05} Q {cx} {bottom-.35} {br-.4} {bottom-1.05}', stroke='#fff3bd', width=.6)
    s += ellipse(cx, top, w/2, .83, 'url(#rim)', '#32291b', .5)
    s += ellipse(cx, top-.14, w/2-.95, .34, '#fff4ce')
    s += path(f'M {bl-.2} {bottom+.25} L {br+.2} {bottom+.25} L {br-.6} {bottom+1.6} Q {cx} {bottom+3} {bl+.6} {bottom+1.6} Z','url(#brass)','#231c12',.65)
    s += path(f'M {bl+.65} {bottom+.72} Q {cx} {bottom+1.25} {br-.65} {bottom+.72}',stroke='#b69b58',width=.35)
    s += '</g>'
    return s


def wall_glass(cx, name):
    s=f'<g id="wall-glass-{name}">'
    s+=path(f'M {cx-.55} 6.8 L {cx-.4} 3.3 Q {cx+.1} .65 {cx+.45} 1.45 L {cx+1} 7.1 Z','url(#brass)','#211a11',.4)
    s+=ellipse(cx,8.3,10.7,1.5,'url(#brass)','#1e1b13',.65)
    s+=ellipse(cx-.4,7.9,8.6,.43,'#efdc9e',extra='opacity=".9"')
    s+=path(f'M {cx-11.1} 10.3 L {cx+11.1} 10.3 L {cx+5.7} 31.5 Q {cx} 32.3 {cx-5.7} 31.5 Z','url(#glass)','#241d13',.95)
    s+=path(f'M {cx-10.3} 11 L {cx+10.3} 11 L {cx+5.3} 30.6 L {cx-5.3} 30.6 Z','url(#glassDepth)')
    s+=path(f'M {cx-9.8} 11.7 L {cx-5} 29.9',stroke='#fff6d2',width=.52,extra='opacity=".75"')
    s+=path(f'M {cx+9.7} 11.7 L {cx+5.1} 29.9',stroke='#b18d4a',width=.45,extra='opacity=".4"')
    s+=path(f'M {cx-5.1} 30.1 Q {cx} 30.5 {cx+5.1} 30.1',stroke='#fff3bc',width=.7)
    s+=path(f'M {cx-11.2} 9.7 Q {cx} 10.6 {cx+11.2} 9.7 L {cx+10.9} 11.2 Q {cx} 11.8 {cx-10.9} 11.2 Z','url(#rim)','#251f13',.35)
    s+=path(f'M {cx-5.9} 31.1 Q {cx} 31.8 {cx+5.9} 31.1 L {cx+5.4} 32.4 Q {cx} 33.2 {cx-5.4} 32.4 Z','url(#brass)','#201b12',.6)
    s+='</g>'
    return s


def wall_lamp():
    s=defs()+'<g id="wall-lamp-1704">'
    # The original backing shadow is deliberately translucent and extends below
    # the metal plate; it is not a solid replacement for the open cut-outs.
    s+='<g id="backplate-soft-shadow" fill="#1c160e" filter="url(#softShadow)">'
    s+=path('M 27.2 51 Q 31 53 31.5 65 L 34 89 L 36 65 Q 40 57 41 51 Z','#1c160e',extra='opacity=".10"')
    s+=path('M 31 56 L 33.9 84 L 36.2 57 Z','#1c160e',extra='opacity=".1"')+'</g>'
    s+='<g id="oval-backplate">'
    s+=path('M 34.7 30.8 C 27.5 30.8 24.7 38.3 25.1 45.3 C 24.8 53 28.8 58.5 34.5 58.8 C 40.6 58.6 44.2 53.3 44.3 45.7 C 44.6 38.2 41.4 30.8 34.7 30.8 Z','url(#plate)','#201a11',1.05)
    s+=path('M 34.7 32.2 C 28.8 32.3 26.3 38.4 26.4 45.8 C 26.1 52.4 29.7 56.9 34.6 57.2 C 39.7 56.9 42.8 52 42.8 45.7 C 43 38.4 40.6 32.2 34.7 32.2 Z','url(#plate)','#392a19',.6)
    s+=path('M 27.7 38.4 Q 29.4 31.8 34.6 31.8 Q 39.2 31.9 41.3 37.3',stroke='url(#edgeGlint)',width=.55)
    s+=path('M 27.7 50 Q 29.1 56.5 34.6 56.9 Q 40 56.4 41.7 50',stroke='#70532d',width=.36)
    s+=path('M 30.1 35.1 Q 34.5 33.4 39 35.2 L 36.8 45.7 L 32.4 45.7 Z','url(#brass)','#2a2012',.5)
    s+=path('M 29.8 34.2 Q 34.5 31.6 39.3 34.2 L 39.5 35.3 L 29.6 35.3 Z','url(#rim)','#3a2b18',.45)
    s+='</g><g id="two-curved-arms">'
    arm='M 30.2 46 L 30.1 41.2 C 30 38.1 27.2 37.8 24.4 41.5 L 18.9 48.2 C 16.4 51.1 14.4 52.2 11.9 51.6 C 11.2 50.9 11.4 48.7 11.4 44.7 L 11.4 32.3'
    s+=rod(arm,1.85)
    s+='<g transform="translate(69,0) scale(-1,1)">'+rod(arm,1.85)+'</g>'
    for cx in [11.4,57.6]:
        s+=path(f'M {cx-.7} 34.1 L {cx+.75} 34.1 L {cx+.68} 43.5 Q {cx} 44.7 {cx-.62} 43.5 Z','url(#brass)','#211b12',.35)
    s+='</g><g id="central-socket">'
    s+=path('M 28.5 45.6 Q 34.6 46.2 40.8 45.6 L 39.5 52.4 Q 34.8 55.1 29.9 52.5 Z','url(#brass)','#251c11',.8)
    s+=path('M 29 46 Q 34.5 46.6 40.1 46',stroke='#e0c481',width=.55)
    s+=path('M 31 52.2 Q 34.5 53.5 38.5 52.1',stroke='#92713b',width=.35)+'</g>'
    s+=wall_glass(11.7,'left')+wall_glass(57.1,'right')+'</g>'
    return write_part(PARTS/'bitmap-1704.svg',(0,0,69,94),s)


def chandelier():
    s=defs()+'<g id="chandelier-1724">'
    s+='<g id="chain-and-crown">'
    s+=rod('M 52 1.1 L 52 5.7',1.45,False)
    s+=rod('M 51.8 4.6 C 48.6 5.2 48.2 13.4 51.6 14.2 C 55.2 14.5 55.3 5.4 51.8 4.6 Z',1.1)
    s+=rod('M 51.8 13.4 L 51.8 17.5',1.4,False)
    s+=rod('M 51.8 17 C 48.3 17.2 48.7 24.8 51.7 25.8 C 55.1 25.8 55 17.6 51.8 17 Z',1.1)
    s+=rod('M 51.7 25.3 L 51.7 29.7',1.35,False)
    s+=rod('M 47.8 34.2 C 47.4 31.7 49.7 29.9 51.8 30 C 54.3 29.8 56.5 32 56.1 34.3',1)
    s+=path('M 47.5 34.5 L 56.4 34.5 L 55.1 38.4 Q 51.9 41 48.9 38.3 Z','url(#brass)','#221b12',.8)
    s+=ellipse(51.9,34.8,4.7,.8,'url(#rim)','#21190f',.65)
    s+=rod('M 51.9 39.3 L 51.9 73.1',1.45)
    s+='</g>'
    # Upper opposed scrolls retain the two open inward curls and forked crown.
    s+='<g id="upper-open-scrolls">'
    upper='M 51.8 52.5 C 48.7 54.4 49.7 49.1 48.4 46.4 C 46.6 43.4 43.1 41.7 40.6 42.9 L 40.3 46.6 M 48.7 48.8 C 49.4 53.6 48.1 56.3 45.1 57.9 C 42 59.5 40.9 56.9 40.8 54.8'
    s+=rod(upper,1.35)
    s+='<g transform="translate(103.8,0) scale(-1,1)">'+rod(upper,1.35)+'</g>'
    scroll='M 48.8 83.6 C 47.1 80.5 44.2 76.9 41.4 73.5 C 37.6 69.6 34.9 66.4 36.6 62.8 C 38 59.5 41.3 58.6 44.4 60.6 C 47.2 62.5 49 66.1 47.2 68.5 C 46 70.2 44.3 68.7 43.4 67.6'
    # Draw scroll lower portions above the rear glass later, as in source.
    s+='</g>'
    # Six support arms: a wide outer pair, nested front pair, short rear pair.
    s+='<g id="six-open-support-arms">'
    outer='M 14.2 94.1 L 14.3 97 C 18.6 98.5 20.5 105.3 18.8 110.7 C 17.2 113.2 14.1 109.4 13.1 107.7 M 14.3 97 C 11.7 98.7 6.5 107.1 1.7 117.4 C .2 120.5 1.6 127.1 5 132.8 C 9.2 140.6 16.4 143.2 25.2 140.5 C 37.2 137.6 44.3 129 47.6 119.5'
    front='M 29.9 104.3 L 29.7 107.4 C 26 108.1 24.4 112.1 24.7 119.9 L 25.4 138 C 25.7 143.7 30.2 149.6 35.3 148.5 C 41.1 147.7 46.6 133.9 48.3 121.4 M 29.8 107.8 C 32.5 109.2 33.3 113.3 32 115.4 C 31.3 116.7 29.5 115.5 29 114.5'
    rear='M 40.6 96.2 L 40.6 99.4 C 37.6 101.5 36.5 107.5 36.7 114.7 L 37.2 134.2 C 37.3 138.5 40.6 141.7 43.2 137.5 C 46 133.2 48 126.3 48.2 120 M 40.6 100.2 C 43.2 102.1 44 109.1 43 113.4 C 42.5 115 41.3 114.2 40.5 112.6'
    for d,w in [(rear,1.25),(front,1.5),(outer,1.8)]:
        s+=rod(d,w,rear=(d==rear))
        s+='<g transform="translate(104,0) scale(-1,1)">'+rod(d,w,rear=(d==rear))+'</g>'
    s+='</g>'
    s+='<g id="rear-glass-pair">'
    s+=chandelier_glass(40.2,73.8,20.8,94.9,11.5,'rear-left')
    s+=chandelier_glass(63.8,73.8,20.8,94.9,11.5,'rear-right')+'</g>'
    # Central column, cylindrical with one narrow warm specular face.
    s+='<g id="central-column">'
    s+=path('M 47 83.7 L 57 83.7 L 57 120.2 L 55.5 121 L 55.4 160.3 L 48.7 160.3 L 48.7 121 L 47 120.2 Z','url(#brass)','#261d10',.8)
    s+=path('M 50 85 L 50 119.6 M 50.4 122 L 50.4 159.2',stroke='#cbb174',width=.35,extra='opacity=".5"')
    s+=path('M 47.2 119.3 L 56.8 119.3 L 56.5 121.1 L 47.7 121.1 Z','url(#brass)','#302211',.4)
    s+=path('M 48 83.7 C 49 79.6 49.9 76 51.9 71.2 C 53.3 75.8 55.2 79.7 56 83.7 Z','url(#brass)','#251d11',.65)
    s+=rod('M 51.9 72.2 L 51.9 83.3',.8)
    s+='</g><g id="scrolls-over-rear-cups">'+rod(scroll,1.75)
    s+='<g transform="translate(103.8,0) scale(-1,1)">'+rod(scroll,1.75)+'</g></g>'
    s+='<g id="outer-glass-pair">'
    s+=chandelier_glass(14.2,68.5,22.2,91.6,12.1,'outer-left')
    s+=chandelier_glass(89.8,68.5,22.2,91.6,12.1,'outer-right')+'</g>'
    s+='<g id="front-glass-pair">'
    s+=chandelier_glass(29.8,79.6,22.6,103.1,12.4,'front-left')
    s+=chandelier_glass(74.2,79.6,22.6,103.1,12.4,'front-right')+'</g>'
    # Original lower ornamental basket: three opposed open curl pairs.
    s+='<g id="lower-open-scroll-basket">'
    basket_outer='M 49.4 164.6 C 46.1 170.7 40.3 173.9 34.9 173.4 C 29.1 173.5 25.5 168.5 26.4 162.3 C 26.7 158.2 30.8 152.3 32.4 151.6 C 34.5 151.2 35.9 154.6 35.3 158 C 34.6 160 33.2 157.6 32.8 156.9'
    basket_mid='M 49.2 165.9 C 47.8 174.3 44.1 179.1 40.8 176.1 C 37.7 173.5 38.5 165.8 39.1 161.3 C 39.6 157.2 40.4 156.2 41.9 158.3 C 43 160.1 41.6 161 40.7 159.7'
    basket_inner='M 49.9 165.1 C 49.6 168 45.4 170.1 44.6 168 C 44.2 166.2 44.8 161.9 44.7 157.2 C 44.8 153.1 46.2 151.2 47.2 155.9 L 47.1 158.8'
    for d,w in [(basket_outer,1.35),(basket_mid,1.15),(basket_inner,1.15)]:
        s+=rod(d,w,rear=(d!=basket_outer))
        s+='<g transform="translate(104,0) scale(-1,1)">'+rod(d,w,rear=(d!=basket_outer))+'</g>'
    s+='</g><g id="lower-central-finial">'
    s+=path('M 48.5 160.2 Q 52 158.8 55.7 160.2 L 55.8 165.8 Q 52.2 168.1 48.3 165.8 Z','url(#knob)','#322611',.8)
    s+=path('M 49.1 160.6 Q 51.7 159.5 54.3 160.4',stroke='#f7edb4',width=.5)
    s+=ellipse(51.8,163.4,3.7,3.3,'url(#knob)')
    s+='</g></g>'
    return write_part(PARTS/'bitmap-1724.svg',(0,0,105,178),s)


def main():
    files=[wall_lamp(),chandelier()]
    for p,w in zip(files,[69,105]):
        render(p,w*6,ROOT/'previews'/(p.stem+'-new-6x.png'))
        render(p,w,ROOT/'baked'/(p.stem+'.png'))
    (ROOT/'qa'/'lamps-manifest.json').write_text(json.dumps({
        'assets':{'1704':{'dimensions':[69,94],'lamp_count':2},'1724':{'dimensions':[105,178],'lamp_count':6}},
        'editable_native_svg':True,'raster_embeds':False,
        'reference_dir':'reference','generator':'source/lamps.py',
        'note':'Original halo 1411 stays outside these parts and is assembled by the scene owner.'
    },indent=2))
    # Preview generation uses only the references shipped inside this package.
    from PIL import Image, ImageDraw
    native=Image.new('RGBA',(670,290),(113,106,94,255))
    nd=ImageDraw.Draw(native)
    nd.text((16,12),'NATIVE SIZE   ORIGINAL / REDRAW',fill='white')
    qa={}
    ns={'s':'http://www.w3.org/2000/svg'}
    for i,n in enumerate([1704,1724]):
        original=Image.open(ROOT/'reference'/f'bitmap-{n}-original.png').convert('RGBA')
        close=Image.open(ROOT/'previews'/f'bitmap-{n}-new-6x.png').convert('RGBA')
        cmp=Image.new('RGBA',(close.width*2+48,close.height+40),(113,106,94,255))
        cmp.alpha_composite(original.resize(close.size,Image.Resampling.NEAREST),(12,30))
        cmp.alpha_composite(close,(close.width+36,30))
        cd=ImageDraw.Draw(cmp)
        cd.text((12,8),f'ORIGINAL {n} / 6x',fill='white')
        cd.text((close.width+36,8),'NATIVE SVG REDRAW / 6x / ROUND 2',fill='white')
        cmp.convert('RGB').save(ROOT/'previews'/f'lamps-round2-{n}.png')
        baked=Image.open(ROOT/'baked'/f'bitmap-{n}.png').convert('RGBA')
        x=20+i*300
        native.alpha_composite(original,(x,55)); native.alpha_composite(baked,(x+130,55))
        nd.text((x,35),str(n),fill='white')
        p=PARTS/f'bitmap-{n}.svg';tree=ET.parse(p);markup=p.read_text()
        assert not tree.findall('.//s:image',ns), 'A lamp must stay native editable vector.'
        assert 'href=' not in markup, 'A lamp must have no external dependency.'
        assert baked.size==original.size, 'Native canvas dimensions must be preserved.'
        qa[str(n)]={
            'viewBox':tree.getroot().get('viewBox'),
            'paths':len(tree.findall('.//s:path',ns)),
            'raster_image_elements':0,'has_external_href':False,
            'render_dimensions':list(baked.size),
            'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
            'round_1_preview':f'previews/lamps-round1-{n}.png',
            'round_2_preview':f'previews/lamps-round2-{n}.png'
        }
    native.convert('RGB').save(ROOT/'previews'/'lamps-native-size-check.png')
    (ROOT/'qa'/'lamps-two-round-validation.json').write_text(json.dumps(qa,indent=2))


if __name__=='__main__':
    main()
