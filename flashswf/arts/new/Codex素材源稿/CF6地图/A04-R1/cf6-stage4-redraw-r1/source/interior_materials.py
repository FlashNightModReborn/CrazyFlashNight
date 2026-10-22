"""Original-size interior materials. Native ornament/seams over reproducible texture.
Texture is procedural; ornamental topology is calibrated from retained source masks.
"""
from pathlib import Path
import numpy as np
from scipy.ndimage import gaussian_filter
from PIL import Image,ImageDraw,ImageFont
import base64,io
from svg_native import write_part,render
R=Path(__file__).resolve().parents[1]
def texpng(a):
 b=io.BytesIO();Image.fromarray(np.uint8(np.clip(a,0,255))).save(b,format='PNG');return base64.b64encode(b.getvalue()).decode()
def img(a,w,h):return f'<image width="{w}" height="{h}" href="data:image/png;base64,{texpng(a)}"/>'
def path(d,fill,stroke='none',sw=.4,extra=''):return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" {extra}/>'
def field(rng,shape,sy,sx):
 a=gaussian_filter(rng.normal(size=shape),(sy,sx),mode='wrap');return a/max(a.std(),1e-6)
def floor():
 w,h=306,251;S=3;H,W=h*S,w*S;r=np.random.default_rng(1701);y,x=np.mgrid[:H,:W]/S
 warp=2.3*field(r,(H,W),11*S,28*S)+.5*np.sin(x/29)
 fine=np.sin((y+warp)*2.2)+.45*np.sin((y+warp*.6)*5.1)
 fibre=field(r,(H,W),.45*S,7*S);mid=field(r,(H,W),1.5*S,32*S);broad=field(r,(H,W),12*S,85*S)
 tone=3.4*fine+6.5*fibre+5.3*mid+3*broad+r.normal(0,.65,(H,W))
 a=np.array([54,40,34])[None,None,:]+tone[:,:,None]*np.array([1,.85,.76])
 # Warm, worn streaks in long direction, never diagonal embossed grain.
 streak=np.maximum(0,field(r,(H,W),.28*S,12*S)-.7)
 a+=streak[:,:,None]*np.array([11,8,6])
 s=img(a,w,h)
 ys=[0,19,40,61,83,104,125,146,167,188,209,230,251]
 ends=[12,211,82,275,138,15,211,82,275,138,15,211]
 for k in range(len(ys)-1):
  yy=ys[k];bottom=ys[k+1];ex=ends[k]
  s+=path(f'M0 {yy+.5} H306','none','#090909',1.5)+path(f'M0 {yy+1.4}H306','none','#8c765e',.42,extra='opacity=".5"')
  s+=path(f'M{ex} {yy}l{(bottom-yy)*1.65} {bottom-yy}','none','#080909',.95)+path(f'M{ex+1.1} {yy+1}l{(bottom-yy-2)*1.65} {bottom-yy-2}','none','#6c5a47',.24)
 # Sparse open grain, slight worn ridges. All start positions deterministic.
 for i in range(180):
  xx=r.uniform(0,w);yy=r.uniform(0,h);ln=r.uniform(6,34)
  s+=path(f'M{xx:.2f} {yy:.2f}q{ln*.4:.2f} {r.uniform(-.6,.6):.2f} {ln:.2f} {r.uniform(-.35,.35):.2f}','none',r.choice(['#120f0d','#77614d','#4e3c30']),r.uniform(.23,.65),extra='opacity=".46"')
 return s

def ornament():
 # Bilaterally paired acanthus leaves and pointed central seed, 50x58 native.
 s=''
 for flip in [1,-1]:
  q=''
  q+=path('M0 -27 C5 -23 5 -18 3 -14 C10 -24 17 -20 17 -14 C17 -9 12 -8 10 -11 C12 -10 14 -13 12 -15 C8 -18 6 -11 8 -7 C12 -7 17 -9 21 -14 C20 -3 15 0 10 2 C19 2 22 -3 23 -7 C25 6 16 11 9 10 C20 15 19 21 14 23 C8 24 6 19 9 17 C10 21 14 20 13 17 C10 12 4 13 3 19 L0 28Z','#29200d','#201a0b',.35)
  q+=path('M2 -19 C9 -27 19 -26 23 -18 C18 -22 13 -22 10 -18 M11 -5 C16 -6 18 -8 20 -10 M9 6Q19 8 22 2 M5 12Q9 11 12 13','none','#766035',.55)
  q+=path('M4 -13Q7 -9 5 -4 M6 -1Q11 -1 14 -4 M4 5Q8 4 11 6 M5 17Q6 22 11 25','none','#6b552c',.32)
  q+=path('M18 -22 L24 -29 20 -17 M22 -4L28 -9 23 4 M14 24L20 27 11 26','#302611','#201b0e',.3)
  for yy,xx in [(-17,7),(-10,11),(-3,13),(4,12),(11,9),(18,5)]:
   q+=path(f'M{xx} {yy}q5 -5 7 -1q1 4 -4 4q-3 -1 -1 -3','none','#765f32',.45)
   q+=path(f'M{xx+4} {yy-5}q4 1 3 5q-4 -1 -3 -5Z','#2b220f','#594421',.25)
  s+=f'<g transform="scale({flip} 1)">{q}</g>'
 s+=path('M0 -25 Q9 -14 5 -3 L8 4 0 25 -8 4 -5 -3Q-9 -14 0 -25Z','#413318','#6b552b',.45)
 s+=path('M0 -20Q4 -11 1 -4 L4 4 0 17 -4 4 -1 -4Q-4 -11 0 -20Z','#211b0e','#8b713b',.35)
 s+=path('M0 -13L2 -6 0 -1 -2 -6Z M0 3L2 7 0 12 -2 7Z','#6a542b')
 return s

def wallpaper():
 w,h=228,197;S=3;H,W=h*S,w*S;r=np.random.default_rng(1702)
 a=np.array([91,74,43])[None,None,:]+(2.4*field(r,(H,W),.5*S,.7*S)+2.7*field(r,(H,W),6*S,7*S)+1.6*field(r,(H,W),25*S,18*S))[:,:,None]*np.array([1,.86,.59])
 from ornament_contours import make
 s=img(a,w,h)+make(55,"#433013")+make(40,"#2b1d09")
 s+='<rect y="177.5" width="228" height="19.5" fill="#342320"/><path d="M0 178H228 M0 195.5H228" stroke="#a6976b" stroke-width="1"/>'
 for x in range(-3,230,12):
  s+=f'<g transform="translate({x} 187) scale(.64 1)">'+path('M-8 0Q-6 -8 0 -6Q7 -6 7 0Q6 6 0 6Q-5 5 -4 1Q-2 -3 1 -1Q2 2 -1 2 M-8 0Q-4 0 -1 6 M7 0Q11 -6 13 -5','none','#b6a381',.8)+path('M-3 -5Q0 -8 3 -4L1 -1 -3 1 -5 -1Z','#7d414a','#321e24',.4)+'</g>'
 return s

def main():
 (R/'previews').mkdir(exist_ok=True)
 for i,w,h,builder in [(1701,306,251,floor),(1702,228,197,wallpaper)]:
  p=write_part(R/f'parts/bitmap-{i}.svg',[0,0,w,h],builder());render(p,w*3,R/f'previews/material-{i}-new.png')
  old=Image.open(R/f'reference/materials/{i}.png').convert('RGB').resize((w*3,h*3));new=Image.open(R/f'previews/material-{i}-new.png').convert('RGB');out=Image.new('RGB',(w*6,h*3+35),'#202822');out.paste(old,(0,35));out.paste(new,(w*3,35));d=ImageDraw.Draw(out);d.text((12,10),'ORIGINAL',fill='white');d.text((w*3+12,10),'R1 / ORIGINAL TILE SIZE',fill='white');out.save(R/f'previews/material-{i}-original-new.png')
 print('Rebuilt interior floor and wallpaper hybrid base materials')
if __name__=='__main__':main()
