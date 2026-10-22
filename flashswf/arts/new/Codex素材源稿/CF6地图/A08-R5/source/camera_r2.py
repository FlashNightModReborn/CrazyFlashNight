"""R2 suspended camera, bitmap 1828, two authored views and original state clips.
Only original alpha registration is reused. Run after vehicles_props.py.
"""
from pathlib import Path
import base64, io, json, hashlib, math
import numpy as np
from PIL import Image, ImageDraw
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from svg_native import write_part, render, inner
R=Path(__file__).resolve().parents[1]
REF=R/'reference'
IDS=(1828,)
WH={1823:(411,144),1420:(144,176),1828:(55,44),1833:(52,89)}
SEED=1828

def path(d,fill,stroke=None,width=.5,extra=''):
 return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{width}"' if stroke else '')+f' {extra}/>'
def line(d,c='#99a0a6',w=.4,o=1):
 return path(d,'none',c,w,f'opacity="{o}" stroke-linecap="round" stroke-linejoin="round"')
def rect(x,y,w,h,c,stroke=None,sw=.5,rx=0,extra=''):
 return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'
def ell(x,y,rx,ry,c,stroke=None,sw=.5,extra=''):
 return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' {extra}/>'
def circle(x,y,r,c,stroke=None,sw=.5,extra=''):return ell(x,y,r,r,c,stroke,sw,extra)
def bolt(x,y,r=.55):
 return circle(x+.15,y+.2,r+.17,'#0b1013')+circle(x,y,r,'#60696f')+line(f'M{x-r*.4:.2f} {y-r*.35:.2f}l{r*.7:.2f} -.1','#b4b9ba',.2,.7)
def lg(id,stops,x2='0',y2='1',x1='0',y1='0'):
 return f'<linearGradient id="{id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</linearGradient>'
def rg(id,stops,cx='.36',cy='.28',r='.74'):
 return f'<radialGradient id="{id}" cx="{cx}" cy="{cy}" r="{r}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</radialGradient>'
def label(text,x,y,w,h,c='#d4d7d6',font='DejaVuSans-Bold.ttf'):
 f=TTFont(REF/('vehicles-props-'+font));gs=f.getGlyphSet();cm=f.getBestCmap();n=0;els=[]
 for ch in text:
  g=gs[cm[ord(ch)]];pen=SVGPathPen(gs);g.draw(pen);els.append(f'<path transform="translate({n} 0)" d="{pen.getCommands()}"/>');n+=g.width
 return f'<g fill="{c}" transform="translate({x} {y+h}) scale({w/n} {-h/1493})">'+''.join(els)+'</g>'
def png_data(im):
 b=io.BytesIO();im.save(b,format='PNG');return base64.b64encode(b.getvalue()).decode()
def original_mask(i):
 im=Image.open(REF/f'{i}.png').convert('RGBA');a=im.getchannel('A');white=Image.new('RGBA',im.size,'white');white.putalpha(a);w,h=im.size
 return f'<mask id="source-alpha-{i}" maskUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{h}" style="mask-type:alpha"><image x="0" y="0" width="{w}" height="{h}" href="data:image/png;base64,{png_data(white)}"/></mask>'
def grain(w,h,seed,strength=14):
 rng=np.random.default_rng(seed);ww,hh=w*3,h*3
 a=rng.normal(0,1,(hh,ww));b=np.array(Image.fromarray(rng.integers(0,255,(max(2,h//4),max(2,w//4)),dtype=np.uint8)).resize((ww,hh),Image.Resampling.BICUBIC))/255-.5
 rgb=np.where((a+b)[...,None]>0,np.array([192,202,208]),np.array([3,5,8]));alpha=np.minimum(np.abs(a)*strength+np.abs(b)*strength,35).astype('uint8');im=Image.fromarray(np.dstack((np.broadcast_to(rgb,(hh,ww,3)),alpha)).astype('uint8'))
 return f'<image width="{w}" height="{h}" href="data:image/png;base64,{png_data(im)}"/>'
def coated(i,body,base='#101317'):
 w,h=WH[i];return '<defs>'+original_mask(i)+'</defs>'+f'<g mask="url(#source-alpha-{i})">'+rect(0,0,w,h,base)+body+'</g>'

def pedestal():
 # The old name is retained for compatibility. 1828 is the suspended camera
 # atlas: left three-quarter view and right front view, used by 1829/1830/1831.
 s='<defs>'+lg('caseTop',[(0,'#adb3b0'),(.26,'#7c8988'),(.62,'#536364'),(1,'#35464a')],'1','.65')+lg('caseFace',[(0,'#718182'),(.23,'#56696c'),(.64,'#34494d'),(1,'#26383e')],'.5','1')+lg('caseSide',[(0,'#40565d'),(.28,'#34494f'),(.7,'#243a41'),(1,'#182b32')],'1','.8')+lg('steelRod',[(0,'#17282e'),(.18,'#617575'),(.35,'#b9c8c0'),(.52,'#859996'),(.76,'#3d555c'),(1,'#1c313a')],'1','0')+lg('cap',[(0,'#6d817f'),(.2,'#536864'),(.38,'#334b4a'),(.78,'#203538'),(1,'#12262c')])+rg('joint',[(0,'#94a6a1'),(.28,'#677d7b'),(.65,'#384e53'),(1,'#192e36')],'.29','.20','.82')+rg('glass',[(0,'#577985'),(.30,'#284854'),(.57,'#0e2530'),(.81,'#06131c'),(1,'#193440')],'.28','.25','.85')+lg('lensRing',[(0,'#a0b3b4'),(.22,'#6f8a90'),(.47,'#1c343e'),(.73,'#253e48'),(1,'#8a9e9e')],'1','1')+'</defs>'
 # LEFT CAMERA. Main shell planes first: continuous metal top, side and belly.
 s+=path('M.8 31.2L9.8 25.5L20.0 24.8L21.4 35.4L13.2 41.8L1.1 42.5Z','#172c33','#10232b',.52)
 s+=path('M1.2 31.4L10 25.7L19.8 25.1L12.5 31.1Z','url(#caseTop)','#2a4149',.38)
 s+=path('M12.5 31.1L19.8 25.1L20.8 35.1L13 41.1Z','url(#caseSide)','#172d35',.48)
 s+=path('M1.1 40.8L12.9 40.1L20.8 34.4L21 36.1L13.1 42.2L1.1 42.4Z','#172a31','#0c2028',.36)
 s+=path('M1.1 31.5L12.5 31L12.9 40.7L1.1 41.6Z','url(#caseFace)','#182e36',.48)
 # Slight front rim and a recessed round optical barrel, visibly an actual lens.
 s+=path('M2.0 32.6L11.6 32.1L11.9 40.1L2.0 40.7Z','#1f363f','#829696',.36)
 s+=ell(6.7,36.4,2.75,3.22,'#0c2029','#213b47',.42)
 s+=ell(6.6,36.25,2.32,2.78,'url(#lensRing)','#98a9a6',.25)
 s+=ell(6.5,36.3,1.72,2.17,'#071621','#142b36',.26)+ell(6.43,36.15,1.38,1.76,'url(#glass)')
 s+=path('M5.55 35.6Q5.75 34.5 6.65 34.67L6.37 35.34Z','#a8cbce',extra='opacity=".72"')+ell(6.72,37.0,.45,.6,'#496b7a',extra='opacity=".5"')
 s+=line('M2.1 32.6L11.3 32.1M13.3 31.3L19.5 26.3','#9cacaa',.29,.63)
 s+=line('M13.5 39.9L19.5 35.5M2 41.2L11.8 40.6','#080f17',.34,.85)
 # Housing seam recedes with the side plane, with tiny flush service screws.
 s+=line('M14.3 32.4L19.7 28M14.6 32.9L19.8 28.6','#92a4a2',.22,.43)
 for x,y in [(2.75,33.25),(10.9,39.1),(18.8,33.7)]:s+=bolt(x,y,.23)
 # Spherical swivel within a two-cheek clevis. Both cheeks meet the housing.
 s+=ell(15.1,24.25,3.25,3.3,'url(#joint)','#1a3039',.4)
 s+=path('M10.9 22.2L12.4 21.3L13.1 26.6L11.3 27.4Z','url(#caseTop)','#1b333b',.33)
 s+=path('M17.5 21.5L19 21.1L19.3 25.5L17.9 26.4Z','url(#caseSide)','#172d36',.34)
 s+=ell(12.2,24.2,.8,1.05,'#253d45','#9caaa4',.24)+line('M12.05 23.8L12.3 24.65','#182c35',.22)
 # Shaft seats into the swivel socket; highlight follows a cylindrical section.
 s+=rect(13.2,7.7,3.2,13.4,'url(#steelRod)','#243b43',.3)+ell(14.8,20.9,2.1,.75,'#263e45')
 s+=path('M12.2 20.5L17.3 20.4L17.7 22.0L12 22.3Z','url(#cap)','#193039',.36)+line('M12.7 20.8L16.8 20.7','#b4c0b6',.26,.5)
 s+=path('M7.5 1.4L25.7 1.1L25.6 6.7L16.5 8.6L7.6 7.7Z','url(#cap)','#162a32',.4)
 s+=path('M7.9 1.7L24.9 1.4L23.4 3.4L10.2 3.7L7.8 3Z','url(#caseTop)')+line('M9.5 5.4L24 5.1','#80948f',.3,.5)
 s+=line('M13.8 9V18.8','#cfdbce',.25,.48)
 # RIGHT CAMERA. Same hardware in the alternate original atlas view.
 s+=path('M39 28.2L41.6 25.2H50.1L52 28.5V42.2H39Z','url(#caseSide)','#122730',.42)
 s+=path('M39.4 28.4L42.1 25.8H49.7L51.4 28.4Z','url(#caseTop)','#344b50',.32)
 s+=rect(39.6,29.1,11.8,12.8,'url(#caseFace)','#29414a',.4)
 s+=rect(40.4,31.4,10.1,9.5,'#203640','#809693',.32)
 s+=ell(45.5,36.2,3.05,3.15,'#0c2029','#3e5963',.38)+ell(45.45,36.1,2.6,2.7,'url(#lensRing)','#97aaa8',.22)
 s+=ell(45.4,36.1,1.99,2.12,'#071822','#122b36',.22)+ell(45.3,35.97,1.67,1.79,'url(#glass)')
 s+=path('M44.2 35.5Q44.4 34.35 45.35 34.4L45.05 35.1Z','#adcccb',extra='opacity=".75"')+ell(45.9,37,.5,.6,'#456775',extra='opacity=".48"')
 s+=line('M40 29.4H50.8M40.2 41.5H50.7','#a4b2a9',.26,.43)
 s+=ell(45.5,24.2,3.25,3.1,'url(#joint)','#233b43',.34)
 s+=path('M40.8 22.1L42.3 21.3L43 26.6L41.3 27.3Z','url(#caseTop)','#243c43',.3)+path('M48.6 21.4L50.1 22L49.7 26.7L48.2 26.4Z','url(#caseSide)','#1c333c',.3)
 s+=ell(42.3,24.3,.77,.9,'#334d53','#a8b6ac',.24)+line('M42.1 23.9L42.45 24.7','#17303a',.22)
 s+=rect(43.7,7.6,3.6,13.4,'url(#steelRod)','#20363f',.32)+ell(45.5,20.9,2.3,.75,'#1e3740')
 s+=path('M42.4 20.5H48.5L49 22.1H42Z','url(#cap)','#17313b',.34)
 s+=path('M35.8 1H54.7V7.1L45.2 8.7L35.8 7.4Z','url(#cap)','#16303a',.4)+path('M36.2 1.4H54.2L52.7 3H38Z','url(#caseTop)')
 s+=line('M36.8 5H53.5M43 20.8H48M44.4 9V19','#c0cbbb',.25,.43)
 for x,y in [(40.9,32),(49.7,40.2)]:s+=bolt(x,y,.23)
 # Extremely restrained fine wear; broad gradients, not grain, describe volume.
 s+=f'<g opacity=".25">{grain(55,44,1828,5)}</g>'
 return coated(1828,s,'#243b44')

def main():
 for d in ['parts','previews','qa']:(R/d).mkdir(exist_ok=True)
 p=write_part(R/'parts/bitmap-1828.svg',[0,0,55,44],pedestal())
 for scale in [1,4,8]:render(p,55*scale,R/f'previews/camera-1828-r2-{scale}x.png')
 a=np.array(Image.open(REF/'1828.png').convert('RGBA'));b=np.array(Image.open(R/'previews/camera-1828-r2-1x.png').convert('RGBA'))
 evidence={'bitmap':1828,'shape_ids':[1829,1830,1831],'sprite':1832,'source':'New editable suspended-camera geometry with two optical lens barrels, clevis swivel and metal shell planes. Original alpha only.','alpha_mismatch_pixels':int(np.count_nonzero(a[:,:,3]!=b[:,:,3])),'max_alpha_difference':int(np.abs(a[:,:,3].astype(int)-b[:,:,3].astype(int)).max()),'dimensions':[55,44],'unchanged':'Atlas coordinates; both viewpoints; scene and animation matrices; clip paths; collision data.','sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
 (R/'qa/camera-r2.json').write_text(json.dumps(evidence,indent=2))
 # Keep the shared vehicle/prop manifest accurate after this intentional override.
 manifest=R/'qa/vehicles-props-method.json'
 if manifest.exists():
  data=json.loads(manifest.read_text());data['files']['1828']={'sha256':evidence['sha256'],'source':'source/camera_r2.py','override':'R2 suspended camera, applied after vehicles_props.py'}
  manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2))
 print(json.dumps(evidence,indent=2))
if __name__=='__main__':main()
