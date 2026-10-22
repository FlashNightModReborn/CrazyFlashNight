from pathlib import Path
from PIL import Image,ImageDraw
from svg_native import write_part,render
R=Path(__file__).resolve().parents[1]
import base64, io
import numpy as np
REF=R/'reference'
WH={1971:(52,89)}
def drum_path(d,fill,stroke=None,width=.5,extra=''):
 return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{width}"' if stroke else '')+f' {extra}/>'

def drum_line(d,c='#224a98',w=.4,o=1):
 return drum_path(d,'none',c,w,f'opacity="{o}" stroke-linecap="round" stroke-linejoin="round"')

def drum_rect(x,y,w,h,c,stroke=None,sw=.5,rx=0,extra=''):
 return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'

def drum_ell(x,y,rx,ry,c,stroke=None,sw=.5,extra=''):
 return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'

def drum_circle(x,y,r,c,stroke=None,sw=.5,extra=''):return drum_ell(x,y,r,r,c,stroke,sw,extra)

def drum_lg(id,stops,x2='0',y2='1',x1='0',y1='0'):
 return f'<linearGradient id="{id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</linearGradient>'

def drum_rg(id,stops,cx='.36',cy='.28',r='.74'):
 return f'<radialGradient id="{id}" cx="{cx}" cy="{cy}" r="{r}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</radialGradient>'

def drum_png_data(im):
 b=io.BytesIO();im.save(b,format='PNG');return base64.b64encode(b.getvalue()).decode()

def drum_original_mask(i):
 im=Image.open(REF/f'{i}.png').convert('RGBA');a=im.getchannel('A');white=Image.new('RGBA',im.size,'white');white.putalpha(a);w,h=im.size
 return f'<mask id="source-alpha-{i}" maskUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{h}" style="mask-type:alpha"><image x="0" y="0" width="{w}" height="{h}" href="data:image/png;base64,{drum_png_data(white)}"/></mask>'

def drum_grain(w,h,seed,strength=14):
 rng=np.random.default_rng(seed);ww,hh=w*3,h*3
 a=rng.normal(0,1,(hh,ww));b=np.array(Image.fromarray(rng.integers(0,255,(max(2,h//4),max(2,w//4)),dtype=np.uint8)).resize((ww,hh),Image.Resampling.BICUBIC))/255-.5
 rgb=np.where((a+b)[...,None]>0,np.array([192,202,208]),np.array([3,5,8]));alpha=np.minimum(np.abs(a)*strength+np.abs(b)*strength,35).astype('uint8');im=Image.fromarray(np.dstack((np.broadcast_to(rgb,(hh,ww,3)),alpha)).astype('uint8'))
 return f'<image width="{w}" height="{h}" href="data:image/png;base64,{drum_png_data(im)}"/>'

def drum_coated(i,body,base='#040811'):
 w,h=WH[i];return '<defs>'+drum_original_mask(i)+'</defs>'+f'<g mask="url(#source-alpha-{i})">'+drum_rect(0,0,w,h,base)+body+'</g>'

def drum_drum():
 s='<defs>'+drum_lg('barrel',[(0,'#0a162e'),(.07,'#152e5d'),(.21,'#1d3d7e'),(.48,'#19356d'),(.76,'#142b59'),(.94,'#0e1e3f'),(1,'#081225')],'1','0')+drum_lg('rib',[(0,'#214791'),(.25,'#183369'),(.48,'#0c1a35'),(.7,'#132a57'),(1,'#224995')])+drum_rg('lid',[(0,'#234c9c'),(.6,'#1f4287'),(1,'#102247')],'.34','.25','.83')+drum_lg('rim',[(0,'#2754ac'),(.27,'#1c3c7c'),(.56,'#0d1c39'),(.8,'#152d5c'),(1,'#234b99')],'1','.7')+'</defs>'
 # Original cylinder is almost front-on: keep its shallow ellipse, round rim,
 # two raised bands and four narrow end ribs instead of a generic drum icon.
 s+=drum_path('M1 7.6Q2 1 26 0Q49 1 51 7.6L50.6 81.9Q49.6 88.2 26 88.8Q2.8 88.1 .8 82Z','url(#barrel)','#081123',.6)
 s+=drum_ell(26,82.4,25.1,6.2,'url(#rim)','#0c1934',.6)+drum_ell(26,80.8,24.9,5.6,'url(#barrel)','#0c1b37',.45)
 s+=drum_path('M2 10Q25 15 49.6 9V80.6Q25.6 87.6 1.7 80.8Z','url(#barrel)')
 s+=drum_ell(26,6.6,25.1,5.3,'url(#rim)','#0b1730',.6)+drum_ell(26,5.4,23.8,3.9,'url(#lid)','#0f2041',.55)
 s+=drum_line('M5.3 4.9Q24.3 -.6 45.2 4.6','#2b5cbd',.6,.76)+drum_line('M5 7.1Q25 12.9 46.9 7.5','#122751',.55,.84)
 # Repeating formed steel ribs curve around the cylindrical shell.
 for y in [12.3,16.6,20.5,24.3,68.2,72.5,76.6,80.3]:
  s+=drum_path(f'M1.7 {y}Q25.5 {y+3.5} 50.1 {y-0.2}L50.1 {y+1.6}Q25.5 {y+5.0} 1.7 {y+1.8}Z','url(#rib)','#0c1b37',.35)
  s+=drum_line(f'M2.6 {y+.3}Q25.6 {y+3.3} 49.3 {y+.1}','#224995',.45,.6)
 # Broad rolled hoops at original atlas y=30 and 62.
 for y in [29.2,61.9]:
  s+=drum_path(f'M.9 {y}Q25.5 {y+4.7} 50.8 {y-.2}L50.8 {y+2.6}Q25.5 {y+7.3} 1 {y+2.7}Z','url(#rim)','#0c1934',.45)
  s+=drum_line(f'M1.6 {y+.15}Q25.5 {y+4.4} 50.1 {y-.05}','#2856b0',.58,.75)
  s+=drum_line(f'M2 {y+2.75}Q26 {y+7} 50 {y+2.4}','#081226',.6,.9)
 # Original two bung closures on top; ellipse perspective, no invented fittings.
 s+=drum_ell(34,3.2,5.3,1.9,'#0b1730','#1a3771',.4)+drum_path('M29.2 2.2H38.7V4.8Q34 7.1 29.2 4.8Z','url(#rib)','#0b1730',.45)+drum_ell(34,2.3,4.7,1.45,'#224995','#11244a',.45)+drum_line('M31 2.1H36.7','#2b5cbc',.35,.7)
 s+=drum_ell(11.2,8.8,3.1,1.5,'#09152b','#1a3872',.45)+drum_path('M8.9 8L13.6 8L14.1 10.5H8.5Z','url(#rim)','#0d1c3a',.4)+drum_ell(11.2,7.9,2.4,1.05,'#214894','#0f2042',.4)
 # Radiation decal on the same original curved front panel.
 s+=drum_path('M25 28L43 57Q44 60 40 60H10Q6 60 8 57L23 28Z','#d0b92d','#1c2634',1.1)
 s+='<g transform="translate(25.5 45) scale(.78) translate(-25.5 -45)">'
 s+=drum_circle(25.5,45,2.3,'#101b25')
 for angle in [60,180,300]:
  s+=f'<path transform="rotate({angle} 25.5 45)" d="M23.7 41.8L20.3 35.8Q25.5 32.9 30.7 35.8L27.3 41.8Q25.5 40.8 23.7 41.8Z" fill="#102030"/>'
 s+='</g>'
 rng=np.random.default_rng(1833)
 for i in range(90):
  x=float(rng.uniform(4,49));y=float(rng.uniform(12,83));leng=float(rng.uniform(.2,2.2))
  s+=drum_line(f'M{x:.2f} {y:.2f}l{leng:.2f} {rng.uniform(-.2,.2):.2f}',rng.choice(['#e1c77d','#3f330f','#6c5317']),float(rng.uniform(.13,.32)),float(rng.uniform(.12,.34)))
 s+=f'<g opacity=".42">{drum_grain(52,89,1833,9)}</g>'
 s+=drum_line('M3.2 35V58M4.4 37V48','#c2a255',.35,.4)+drum_line('M48.6 36V59','#34290c',.6,.55)
 return drum_coated(1971,s,'#614a15')


p=write_part(R/'parts/bitmap-1971.svg',[0,0,52,89],drum_drum());render(p,416,R/'previews/radiation-drum-new.png')
a=Image.open(R/'reference/1971.png').convert('RGBA').resize((416,712));b=Image.open(R/'previews/radiation-drum-new.png');o=Image.new('RGB',(832,745),'#394044');d=ImageDraw.Draw(o)
for j,im in enumerate([a,b]):o.paste(im,(416*j,33),im);d.text((416*j+10,8),['ORIGINAL1971','R1 / BLUE RADIATION DRUM'][j],fill='white')
o.save(R/'previews/radiation-drum-original-new.png')
