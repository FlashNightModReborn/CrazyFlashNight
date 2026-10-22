"""R2 editable procedural volumetric sky 1753, 800 x 187 native coordinates.

New RGB artwork only. No reference RGB is sampled. A deterministic small 3-D
extinction field models overlapping, eroded cloud rolls, with directional light
transport and front-to-back compositing. The rendered material is embedded in a
complete SVG. Bank positions, ellipsoid masses, turbulence, light and palette
are editable below; this is intentionally not a sharpen/noise pass over R1.
"""
from pathlib import Path
import base64, io
import numpy as np
from scipy.ndimage import zoom, gaussian_filter, shift
from PIL import Image, ImageDraw
from svg_native import write_part, render
R=Path(__file__).resolve().parents[1]
SEED=175302
S=1.5
Y0=102
# x, y, depth, x-radius, y-radius, depth-radius. Asymmetric shelves,
# detached rolls, undercuts and overlapping shadow layers replace hill contours.
BANKS=[
 (95,186,10,30,18,14),(63,190,9,30,10,12),
 (467,184,13,46,26,19),(505,185,12,42,21,18),(436,190,11,29,16,14),
 (725,181,13,34,26,18),(754,190,13,36,16,15),
 (0,181,1,18,7,8),(18,184,2,16,6,9),(58,183,2,16,8,10),
 (72,177,0,15,10,9),(84,166,1,14,12,11),(100,151,4,13,13,10),
 (105,164,-4,15,10,11),(116,177,-5,15,10,11),(92,184,-2,23,12,12),
 (401,184,4,13,9,9),(422,174,-1,14,10,11),(444,162,4,16,12,12),
 (459,145,8,16,11,13),(478,133,12,22,9,11),(492,143,7,17,8,12),
 (464,158,-8,19,13,13),(487,158,-7,20,12,13),(510,164,-3,22,11,12),
 (479,179,-8,24,15,16),(514,180,-6,23,13,14),(539,180,1,16,8,10),
 (538,149,11,13,7,10),(563,172,9,17,11,10),(583,183,-3,17,11,12),
 (604,172,8,12,11,10),(620,181,-6,16,9,11),
 (663,181,3,14,9,10),(688,171,0,15,11,12),(705,150,8,14,13,12),
 (721,135,10,20,9,11),(738,142,7,17,10,11),(725,159,-7,17,14,14),
 (749,172,-5,21,11,13),(776,181,-4,19,9,11),(800,177,5,15,10,11),
]

def noise_grid(shape, cells, rng):
 a=rng.normal(0,1,cells).astype('float32')
 b=zoom(a,[shape[k]/cells[k] for k in range(len(shape))],order=3,prefilter=True)
 return b[:shape[0],:shape[1],:shape[2]] if len(shape)==3 else b[:shape[0],:shape[1]]

def make_material():
 rng=np.random.default_rng(SEED)
 w,h=round(800*S),round(253*S)
 yy,xx=np.mgrid[0:h,0:w].astype('float32');yy/=S;xx/=S
 stops=np.array([0,40,88,135,187]);cols=np.array([[105,106,111],[120,128,148],[148,172,224],[174,196,240],[180,202,239]])
 sky=np.stack([np.interp(yy,stops,cols[:,k]) for k in range(3)],axis=-1)
 # Thin horizontally sheared distant vapour, not granular sharp detail.
 n=noise_grid((h,w),(21,69),rng)*.60+noise_grid((h,w),(58,140),rng)*.25
 n=gaussian_filter(n,[.7,.45]);haze=np.clip((n+.1)*.19,0,.29)*np.clip((yy-70)/45,0,1)
 sky=sky*(1-haze[...,None])+np.array([209,219,241])*haze[...,None]
 # Continuous distant sea of cloud connects the dark near towers. Large
 # low-contrast folds live below y~127, with a soft irregular upper boundary.
 # This is a separate depth layer, not additional foreground dark spheres.
 far_rng=np.random.default_rng(SEED+71)
 far_large=noise_grid((h,w),(13,35),far_rng)
 far_fold=noise_grid((h,w),(32,93),far_rng)
 far_fine=noise_grid((h,w),(67,173),far_rng)
 front=133+far_large*8+np.sin(xx/91)*4
 sea_envelope=np.clip((yy-front)/26,0,1)
 sea_density=np.clip(.48+far_large*.22+far_fold*.15+far_fine*.04,.10,.82)
 sea_alpha=gaussian_filter(sea_envelope*sea_density,[1.2,.8])
 sea_rgb=np.array([217,227,246])[None,None,:]+np.clip(far_fold,-1.6,1.6)[...,None]*np.array([6,6,4])[None,None,:]
 sky=sky*(1-sea_alpha[...,None])+sea_rgb*sea_alpha[...,None]
 # Native 3-D density field, restricted to the lower cloud band for memory.
 ny=h-round(Y0*S);nz=74;nx=w
 z=np.linspace(-30,30,nz,dtype='float32')[:,None,None]
 y=np.arange(ny,dtype='float32')[None,:,None]/S+Y0
 x=np.arange(nx,dtype='float32')[None,None,:]/S
 field=np.full((nz,ny,nx),-2,dtype='float32')
 for cx,cy,cz,rx,ry,rz in BANKS:
  xl=max(0,int((cx-rx*1.4)*S));xr=min(nx,int((cx+rx*1.4)*S)+1)
  yl=max(0,int((cy-ry*1.4-Y0)*S));yr=min(ny,int((cy+ry*1.4-Y0)*S)+1)
  if xr<=xl or yr<=yl:continue
  dist=((x[:,:,xl:xr]-cx)/rx)**2+((y[:,yl:yr,:]-cy)/ry)**2+((z-cz)/rz)**2
  f=1.04-np.sqrt(dist)
  old=field[:,yl:yr,xl:xr]
  # Smooth union blends separate puffs but retains overhangs and recesses.
  mx=np.maximum(old,f);field[:,yl:yr,xl:xr]=mx+np.log1p(np.exp(-np.abs(old-f)*12))/12
 del x,y,z
 shape=field.shape
 turbulence=noise_grid(shape,(10,19,88),rng)*.16
 turbulence+=noise_grid(shape,(24,44,190),rng)*.075
 turbulence+=noise_grid(shape,(41,79,350),rng)*.035
 density=np.clip((field+turbulence-.035)*4.8,0,1.4).astype('float32')
 del field,turbulence
 # Light arrives upper left and from behind. The accumulated optical depth
 # produces cool shadowed bellies, irregular lit ridges and thin bright rims.
 optical=np.zeros_like(density);d=density.copy()
 for k in range(16):
  d=shift(d,(-2.25,2.4,2.4),order=1,mode='constant',cval=0,prefilter=False)
  optical+=d*.66
 del d
 direct=np.exp(-optical*.77)
 multi=np.exp(-optical*.11)
 light=np.clip(.045+.55*direct+.17*multi,0,1)
 # Palette deliberately nearly neutral in dense shade, blue only from sky fill.
 low=np.array([48,53,63],dtype='float32');high=np.array([211,224,245],dtype='float32')
 cloud=np.zeros((ny,nx,3),dtype='float32');trans=np.ones((ny,nx),dtype='float32')
 for iz in range(nz):
  a=1-np.exp(-density[iz]*.37)
  rgb=low[None,None,:]+light[iz,:,:,None]*(high-low)[None,None,:]
  cloud+=trans[:,:,None]*a[:,:,None]*rgb
  trans*=1-a
 sky[-ny:]=sky[-ny:]*trans[:,:,None]+cloud
 # Sparse sunward silver lining follows the density silhouette. It is broken
 # by local folds and cannot form a uniform stroked outline.
 opacity=1-trans
 gy,gx=np.gradient(gaussian_filter(opacity,.7))
 facing=np.clip((gy+gx*.65)*.9,0,.16)
 varied=np.clip(noise_grid((ny,nx),(13,74),rng)+.35,0,1)
 rim=facing*varied
 sky[-ny:]=sky[-ny:]*(1-rim[...,None])+np.array([216,229,246])*rim[...,None]
 return Image.fromarray(np.uint8(np.clip(sky,0,255))).resize((2400,759),Image.Resampling.LANCZOS)

def make_extension(material):
 """Crop the continuous 3-D cloud field below native y=186.5.

 This is newly simulated cloud volume beyond the source sky rectangle, never
 a stretched scanline or scaled cloud silhouette. The 0.5-pixel overlap hides
 raster rounding while retaining the original 1753 and 1754 bounds.
 """
 return material.transform((2400,200),Image.Transform.EXTENT,(0,559.5,2400,759),resample=Image.Resampling.BICUBIC)


def build():
 (R/'previews').mkdir(exist_ok=True)
 full=make_material();im=full.crop((0,0,2400,561));buf=io.BytesIO();im.save(buf,format='PNG')
 data=base64.b64encode(buf.getvalue()).decode()
 body='<title>1753 R2 directional volumetric cloud material</title><desc>Deterministic procedural 3D density with light transport; fully rebuildable from source/sky.py. Native 800x187 registration.</desc>'
 body+=f'<image x="0" y="0" width="800" height="187" href="data:image/png;base64,{data}"/>'
 p=write_part(R/'parts/bitmap-1753.svg',[0,0,800,187],body)
 render(p,1600,R/'baked/bitmap-1753.png')
 im.save(R/'previews/sky-r2-3x.png')
 extension=make_extension(full);eb=io.BytesIO();extension.save(eb,format='PNG')
 extdata=base64.b64encode(eb.getvalue()).decode()
 write_part(R/'parts/sky-1753-extension.svg',[0,0,800,66.5],'<title>A7 decorative lower sky continuity, original 1753 unchanged</title>'+f'<image x="0" y="0" width="800" height="66.5" href="data:image/png;base64,{extdata}"/>')
 extension.save(R/'previews/sky-1753-extension.png')
 return p
if __name__=='__main__':build()
