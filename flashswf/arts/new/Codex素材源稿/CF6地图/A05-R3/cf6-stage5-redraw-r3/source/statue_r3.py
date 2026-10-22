"""CF6 1740 R3: generated non-nude upper-body reconstruction + editable SVG lower body.

Rebuild OFFLINE: python source/statue_r3.py. The original game image is used for
alpha/registration QA, not as a rendered or low-pass-traced colour map. Only the
non-nude y=0..80 bust was generated. The generation is NOT reproducible from a
seed: the retained downsampled output is the deterministic offline input; its
provenance records original-file SHA-256, exact prompt and generation tool.
All lower anatomy is hand-authored SVG, based on the original pose; two tiny PD
marble texture crops carry material variation only, not photographic anatomy.
The whole upper reconstruction is gently registered as ONE continuous surface,
never separate eyes, nose, chin or fingers. The original exact 65×211 cutout clips
all layers. It is a hybrid raster/vector asset, not pure SVG or a museum photo.
"""
from pathlib import Path
import os,io,json,base64,hashlib,tempfile,re,copy
os.environ.setdefault('MPLCONFIGDIR','/tmp/cf6-statue-r3-mpl')
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from scipy.ndimage import gaussian_filter,distance_transform_edt,binary_erosion,label
from scipy.interpolate import RBFInterpolator
from xml.etree import ElementTree as ET
import matplotlib;matplotlib.use('Agg')
import matplotlib.pyplot as plt
from svg_native import write_part,render
def _cf6_font(size):
    # PATCHED(cf6-map-source): 硬编码 Linux 字体路径在 Windows 不存在；仅影响预览标注
    cands=[R/'reference/fonts'/'DejaVuSans.ttf']
    try:
        import matplotlib as _mpl, os as _os
        cands.append(Path(_os.path.join(_os.path.dirname(_mpl.__file__),'mpl-data','fonts','ttf','DejaVuSans.ttf')))
    except Exception:
        pass
    for _c in cands:
        if Path(_c).is_file():return ImageFont.truetype(str(_c),size)
    return ImageFont.load_default()
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'reference/bitmap-1740-original.png'
AI=ROOT/'reference/statue-r3-upper-ai.png'
STONE=ROOT/'reference/statue-r3-stone-crop.jpg'
ROUGH=ROOT/'reference/statue-r3-rough-crop.jpg'
OUT=ROOT/'parts/bitmap-1740.svg'
SCALE=8
REVISION='r3-reference'
NS='{http://www.w3.org/2000/svg}'
# Whole-bust registration: target original-game coordinates -> reconstructed
# image coordinates normalized to 65×80. No separately distorted facial features.
LANDMARKS=[((53,.5),(55,.5)),((59,8),(62,8)),((60,28),(64,28)),((62,52),(63.7,52)),
 ((48,17),(51.5,17)),((48,37),(50,38)),((34,20),(34,20)),((28,18),(28,18.5)),
 ((19,24),(17.7,24.6)),((18.5,33),(18.5,33.6)),((27,40),(28.5,41.5)),
 ((40,36),(43,37.5)),((20,46),(20,46)),((13,56),(11.9,56)),((10,74),(7.5,74)),
 ((23,62),(25,63)),((36,66),(40.4,67)),((35,70),(39,72)),((27,73),(29,74)),
 ((36,51),(38,52)),((56,54),(59,54)),((53,75),(60,75)),((22,79),(25,79)),
 ((0,80),(0,80)),((65,80),(65,80))]

def embed(im,fmt='PNG'):
 b=io.BytesIO();im.save(b,format=fmt,**({'quality':93,'subsampling':0,'optimize':True} if fmt=='JPEG' else {'optimize':True}));return base64.b64encode(b.getvalue()).decode()

def silhouette():
 a=np.asarray(Image.open(REF).convert('RGBA'))[:,:,3]/255
 a=gaussian_filter(a,.30)
 cs=plt.contour(np.arange(-1.5,67.5),np.arange(-1.5,213.5),np.pad(a,2),levels=[.35])
 from statue import smooth_closed_path
 d=' '.join(smooth_closed_path(seg) for seg in cs.allsegs[0] if len(seg)>3)
 plt.close();return d

def upper_surface():
 from scipy.ndimage import map_coordinates
 a=np.asarray(Image.open(AI).convert('RGBA')).astype(float)
 # Preserve main generated alpha; remove tiny isolated fringe pixels and borrow
 # edge colour only from fully opaque, neutral-marble interior, never black.
 alpha=a[:,:,3]/255;good=(alpha>.98)&(np.max(a[:,:,:3],axis=2)-np.min(a[:,:,:3],axis=2)<105)
 _,idx=distance_transform_edt(~good,return_indices=True)
 rgb=a[:,:,:3].copy();rgb[~good]=rgb[idx[0][~good],idx[1][~good]]
 smooth=gaussian_filter(rgb,(9,9,0));rgb[~good]=smooth[~good]
 H,W=80*SCALE,65*SCALE;yy,xx=np.mgrid[:H,:W];xy=np.c_[(xx.ravel()+.5)/SCALE,(yy.ravel()+.5)/SCALE]
 dst=np.array([p[0] for p in LANDMARKS]);src=np.array([p[1] for p in LANDMARKS])
 f=RBFInterpolator(dst,src,kernel='thin_plate_spline',smoothing=1.1)
 mp=np.concatenate([f(v) for v in np.array_split(xy,12)])
 mp[:,0]*=a.shape[1]/65;mp[:,1]*=a.shape[0]/80
 warped=np.stack([map_coordinates(rgb[:,:,k],[mp[:,1],mp[:,0]],order=1,mode='nearest').reshape(H,W) for k in range(3)],axis=2)
 # Scene colour adaptation retains the generated relief, with warmer deep shadows.
 lum=warped@np.array([.2126,.7152,.0722]);t=np.clip((lum-35)/215,0,1)**1.14
 stone=np.array([22,15,7])+(np.array([242,229,202])-np.array([22,15,7]))*t[:,:,None]
 warped=.78*stone+.22*warped
 fade=np.clip((80-(yy+.5)/SCALE)/11,0,1);fade=fade*fade*(3-2*fade)
 rgba=np.dstack([np.clip(warped,0,255),fade*255]).astype('uint8')
 return Image.fromarray(rgba)

def old_vector_surfaces():
 # Use the authored anatomical curves, NOT the previous reference-derived
 # isophotes. The old module is unchanged and is only a curve-library dependency.
 import statue
 with tempfile.TemporaryDirectory(prefix='cf6-r3-base-') as td:
  old=(statue.OUT,statue.ROOT,statue.reference_relief,statue.render)
  statue.OUT=Path(td)/'base.svg';statue.ROOT=Path(td)
  statue.reference_relief=lambda:('',0);statue.render=lambda *a,**k:None
  statue.build();root=ET.parse(statue.OUT).getroot()
  statue.OUT,statue.ROOT,statue.reference_relief,statue.render=old
 defs=root.find(NS+'defs');g=root.find(NS+'g')
 # Skip hair/skin scribbles: real PD microtexture supplies restrained material.
 for c in list(g):
  if c.get('id')=='procedural-mineral-marks':g.remove(c)
 for parent in g.iter():
  for e in list(parent):
   if e.tag==NS+'path' and e.get('fill')=='none':parent.remove(e)
 # Roll broad highlights and shadows into the round limb surfaces. These are
 # editable vector shapes with separate gradients; only subpixel edge feathering.
 for e in g.iter():
  if e.tag in (NS+'path',NS+'ellipse') and e.get('fill') not in ('none',None):
   if e.get('id')!='reference-derived-broad-relief':e.set('filter','url(#r3-roll)')
   d=e.get('d','')
   if d.startswith(('M30 105','M33 110')):e.set('filter','url(#r3-soft)');e.set('opacity','.48')
   if d.startswith(('M46 106','M53 101')):e.set('filter','url(#r3-soft)');e.set('opacity','.20')
   if d.startswith(('M34 96','M26 99')):e.set('filter','url(#r3-soft)');e.set('opacity','.22')
 # Warm the lower-body palette to the same aged ivory/ocher as the bust.
 def warmhex(m):
  s=m.group(1);r,g,b=[int(s[i:i+2],16) for i in (0,2,4)]
  v=np.array([r,g,b],float)
  # Increase depth without hue shifts into green.
  v=(v-135)*1.16+135;v*=np.array([1.025,1.0,.965])
  return '#'+''.join(f'{int(np.clip(x,0,255)):02x}' for x in v)
 ds=ET.tostring(defs,encoding='unicode');gs=''.join(ET.tostring(e,encoding='unicode') for e in g)
 ds=re.sub(r'#([0-9a-fA-F]{6})',warmhex,ds);gs=re.sub(r'#([0-9a-fA-F]{6})',warmhex,gs)
 # Rename all old ids to avoid collisions with the final silhouette.
 ids=re.findall(r'\bid="([^"]+)"',ds+gs)
 for k in sorted(ids,key=len,reverse=True):
  ds=ds.replace(f'id="{k}"',f'id="base-{k}"').replace('url(#'+k+')','url(#base-'+k+')')
  gs=gs.replace(f'id="{k}"',f'id="base-{k}"').replace('url(#'+k+')','url(#base-'+k+')')
 return ds,gs

S=[]
def p(d,c,o=1,f=None):S.append(f'<path d="{d}" fill="{c}" opacity="{o}"'+(f' filter="url(#{f})"' if f else '')+'/>')
def ell(x,y,rx,ry,c,o=1):S.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}" opacity="{o}"/>')

def texture(im,size,strength):
 a=np.asarray(im.convert('L').resize(size,Image.Resampling.LANCZOS)).astype(float)
 hi=a-gaussian_filter(a,15)
 # White-based multiply map, keeping anatomy out and mild local mineral grain.
 v=np.clip(240+hi*strength,150,255).astype('uint8');return Image.fromarray(np.dstack([v,v,v]))

def build():

 for folder in ['parts','previews','qa']:(ROOT/folder).mkdir(parents=True,exist_ok=True)
 S.clear();outer=silhouette();defs,body=old_vector_surfaces();upper=upper_surface()
 st=texture(Image.open(STONE),(520,1000),1.5);rf=texture(Image.open(ROUGH),(260,650),1.7)
 S.append('''<title>CF6 1740 R3: AI-reconstructed upper marble, editable vector anatomy</title><desc>Hybrid: one generated non-nude upper-body bitmap registered as a continuous surface; authored SVG lower anatomy and form shadows; public-domain marble microtexture. Original game RGB not rendered. Native 65×211. Not a pure vector or an unaltered photograph.</desc>''')
 S.append(defs)
 S.append(f'''<defs><clipPath id="outer-r3"><path d="{outer}" clip-rule="evenodd"/></clipPath>
<clipPath id="lower-r3"><path d="M0 73H65V211H0Z"/></clipPath>
<clipPath id="rough-r3"><path d="M0 184C7 167 8 153 20 141C26 148 27 168 31 184L33 200C21 206 8 203 0 199Z M49 118C58 118 63 130 61 138L64 158C56 163 48 152 43 143Z"/></clipPath>
<filter id="r3-roll"><feGaussianBlur stdDeviation=".24"/></filter><filter id="r3-soft"><feGaussianBlur stdDeviation="1.0"/></filter><filter id="r3-contact"><feGaussianBlur stdDeviation=".25"/></filter>
<radialGradient id="r3-shadow"><stop stop-color="#2e1d0a" stop-opacity=".9"/><stop offset=".53" stop-color="#3c2a12" stop-opacity=".48"/><stop offset="1" stop-color="#4a361a" stop-opacity="0"/></radialGradient>
<radialGradient id="r3-light"><stop stop-color="#f5e6c5" stop-opacity=".65"/><stop offset=".65" stop-color="#e9d6af" stop-opacity=".25"/><stop offset="1" stop-color="#e9d6af" stop-opacity="0"/></radialGradient>
<linearGradient id="r3-right-shadow"><stop stop-color="#30210e" stop-opacity="0"/><stop offset=".6" stop-color="#30210e" stop-opacity=".15"/><stop offset="1" stop-color="#211509" stop-opacity=".8"/></linearGradient>
<linearGradient id="r3-calf" gradientUnits="userSpaceOnUse" x1="31" y1="149" x2="54" y2="193"><stop stop-color="#c5b38a"/><stop offset=".18" stop-color="#9d8c61"/><stop offset=".57" stop-color="#776642"/><stop offset=".82" stop-color="#514023"/><stop offset="1" stop-color="#302010"/></linearGradient><radialGradient id="r3-knee" cx=".3" cy=".2" r=".9"><stop stop-color="#ddd0ad"/><stop offset=".55" stop-color="#c5b78f"/><stop offset="1" stop-color="#928157"/></radialGradient><linearGradient id="r3-down-shadow" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#30210e" stop-opacity="0"/><stop offset="1" stop-color="#211509" stop-opacity=".86"/></linearGradient>
</defs><g clip-path="url(#outer-r3)"><g id="editable-lower-anatomy">{body}</g>''')
 # Additional continuous round volume, with fully feathered interior bounds.
 S.append('<g id="editable-lower-volume">')
 ell(39,83,15,20,'url(#r3-light)',.34);ell(23,76,12,9,'url(#r3-shadow)',.92)
 ell(51,84,11,23,'url(#r3-shadow)',.42)
 p('M26 92C30 98 34 101 39 100C43 99 48 95 51 91L51 96C46 102 41 104 36 104C31 103 28 99 26 96Z','url(#r3-down-shadow)',.40,'r3-soft')
 # Recessed rear leg, original crossing relationship; the front-knee plane stays lit.
 p('M24 109C27 115 28 124 26 135C23 145 25 151 29 161C33 172 34 185 40 191L46 195L34 197C29 190 27 174 23 163C19 149 18 139 20 126Z','url(#r3-right-shadow)',.83,'r3-soft')
 p('M19 104C25 105 30 107 32 112C30 123 27 134 26 144C25 150 29 162 31 172L35 190L40 195L33 196C29 188 27 174 23 163C20 153 18 143 19 130Z','#594025',.42,'r3-soft')
 ell(34,142,5.3,11,'url(#r3-light)',.48)
 p('M30 150C34 151 38 156 41 162C46 172 47 180 52 187L61 193L62 196C53 195 49 191 45 184C41 177 35 166 31 159Z','url(#r3-down-shadow)',.79,'r3-soft')
 p('M33 152C37 156 41 166 45 175C47 181 51 188 57 192L61 196C53 195 48 190 44 183C39 174 34 166 30 157Z','url(#r3-right-shadow)',.65,'r3-soft')
 p('M48 119C57 120 62 132 61 141C62 147 65 155 61 159C55 162 49 153 45 146Z','url(#r3-right-shadow)',.85,'r3-soft')
 p('M25 146C26 158 29 174 32 187L32 200L26 201C29 189 24 169 23 154Z','url(#r3-right-shadow)',.65,'r3-soft')
 p('M0 198C15 204 30 205 44 201L65 197V211H0Z','url(#r3-down-shadow)',.68,'r3-soft')
 p('M48 119C57 120 62 132 61 141C62 147 65 155 61 159C55 162 49 153 45 146Z','#302211',.62,'r3-roll')
 p('M29.5 149C33 151 36 154 39 158C43 164 45 169 47 176C49 181 50 185 54 189C56 191 59 191.7 62 193L61 195L56 195C51 193 49 189 47 186C44 180 41 174 37 169C33 163 30 158 29.5 153Z','url(#r3-calf)',.94,'r3-roll')
 p('M30 141C29 145 28 149 30.6 152C32.4 154 34.5 153 36.2 151.4C37.4 149.2 37.3 145.5 36.6 142.8Z','url(#r3-knee)',.72,'r3-roll')
 p('M52 103C52 112 47 122 43 132C40 138 38 143 37 147C39 140 42 132 46 123C49 116 50 109 50 104Z','#776242',.30,'r3-soft')
 p('M29 157C31 165 33 180 37 186C40 190 43 192 48 194L44 197C37 195 32 189 31 183L27 167Z','#372713',.5,'r3-soft')
 S.append('</g>')
 # Fine source stone texture independent of viewpoint, not warped human anatomy.
 S.append(f'<g id="PD-material-only" clip-path="url(#lower-r3)" style="mix-blend-mode:multiply"><image x="0" y="73" width="65" height="138" href="data:image/jpeg;base64,{embed(st,"JPEG")}" opacity=".82"/><image x="0" y="140" width="33" height="68" clip-path="url(#rough-r3)" href="data:image/jpeg;base64,{embed(rf,"JPEG")}" opacity=".9"/><image x="0" y="191" width="65" height="20" href="data:image/jpeg;base64,{embed(rf,"JPEG")}" opacity=".75"/><image x="43" y="118" width="22" height="44" clip-path="url(#rough-r3)" href="data:image/jpeg;base64,{embed(rf,"JPEG")}" opacity=".55"/></g>')
 S.append(f'<image id="AI-upper-continuous-surface" x="0" y="0" width="65" height="80" href="data:image/png;base64,{embed(upper)}"/>')
 # Directional shadows join the bust to the old-game stage lighting, rather than
 # painting black lines on its features. Generated face/fingers remain untouched.
 S.append('<g id="editable-bust-lighting">')
 p('M47 1H65V58C58 59 53 52 49 47C48 38 48 27 48 17Z','url(#r3-right-shadow)',.75,'r3-soft')
 ell(39,30,7,14,'url(#r3-shadow)',.48)
 ell(34,43,8,6,'url(#r3-shadow)',.22)
 ell(28,74,13,7,'url(#r3-shadow)',.6)
 p('M48 57C53 66 51 73 48 81C53 89 57 87 62 80L64 58Z','url(#r3-right-shadow)',.75,'r3-soft')
 S.append('</g>')
 S.append('<g id="editable-selective-crossing-contact">')
 p('M25.8 147.8C27.1 151.6 28 154 30 156.2C31.8 158.2 33.2 160.5 34 162.7L33.2 163.3C31.8 161.6 29.7 159.3 28.2 156.7C26.8 154.2 25.7 150.4 25.5 149Z','#3f2c14',.78,'r3-contact')
 p('M30.5 153C32.3 153.5 34 152.7 35.4 151.8C34.4 154 35 155.6 35.9 157C33.5 155.9 31.5 154.7 30.5 153Z','#8b7651',.34,'r3-contact')
 p('M34 190C36.6 193 41.5 195.5 46 195L49 194.8C44.5 198 37 196.7 33.5 194Z','#3d2c15',.58,'r3-contact')
 S.append('</g></g>')
 write_part(OUT,[0,0,65,211],''.join(S))
 render(OUT,520,ROOT/f'previews/statue-{REVISION}-8x.png');render(OUT,65,ROOT/f'previews/statue-{REVISION}-1x.png')
 print('Wrote',OUT,OUT.stat().st_size)

def comparisons():
 orig=Image.open(REF).convert('RGBA');r2svg=ROOT/'reference/r2-1740.svg';r2png=ROOT/'qa/statue-frozen-r2-8x.png';render(r2svg,520,r2png)
 ims=[('ORIGINAL',orig),('R2',Image.open(r2png).convert('RGBA')),('R3 / AI + VECTOR',Image.open(ROOT/f'previews/statue-{REVISION}-8x.png').convert('RGBA'))]
 try:fnt=_cf6_font(18)
 except:fnt=None
 for scale in [1,4,8]:
  w,h=65*scale,211*scale;pad=16 if scale==1 else 30;top=36;b=Image.new('RGB',(w*3+pad*4,h+top+pad),'#373a3b');dr=ImageDraw.Draw(b)
  for i,(label,im) in enumerate(ims):
   im=im.resize((w,h),Image.Resampling.LANCZOS);x=pad+(w+pad)*i;dr.text((x,8),label if scale>1 else ['ORIG','R2','R3'][i],fill='#efe6cf',font=fnt if scale>1 else None);b.paste(im,(x,top),im)
  b.save(ROOT/f'qa/statue-original-r2-r3-{scale}x.png')
 for name,box,scale in [('head-chest',(13,15,62,80),16),('crossed-knees',(16,112,58,176),12)]:
  bw,bh=(box[2]-box[0])*scale,(box[3]-box[1])*scale;b=Image.new('RGB',(bw*3+80,bh+60),'#373a3b');dr=ImageDraw.Draw(b)
  for i,(label,im) in enumerate(ims):
   im=im.resize((65*scale,211*scale),Image.Resampling.LANCZOS).crop(tuple(v*scale for v in box));x=20+i*(bw+20);dr.text((x,8),label,fill='#efe6cf',font=fnt);b.paste(im,(x,40),im)
  b.save(ROOT/f'qa/statue-{name}-original-r2-r3.png')
 a=np.asarray(orig)[:,:,3]>.35*255;new=Image.open(ROOT/f'previews/statue-{REVISION}-1x.png').convert('RGBA');b=np.asarray(new)[:,:,3]>.35*255
 metrics=dict(revision=REVISION,alpha_iou=float((a&b).sum()/(a|b).sum()),alpha_area_change=float(b.sum()/a.sum()-1),native_size=[65,211],original_rgb_used=False,technique='AI upper-body bitmap + editable SVG lower anatomy and occlusion + PD material microtexture',svg_bytes=OUT.stat().st_size)
 (ROOT/'qa/statue-r3-reference-metrics.json').write_text(json.dumps(metrics,indent=2));print(metrics)
if __name__=='__main__':build();comparisons()
