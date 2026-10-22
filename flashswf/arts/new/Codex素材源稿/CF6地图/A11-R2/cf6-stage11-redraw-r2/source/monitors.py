from pathlib import Path
import random,json
from PIL import Image,ImageDraw
from svg_native import write_part,render
R=Path(__file__).resolve().parents[1];rng=random.Random(18951897)
def p(d,c,w=.3,op=1):return f'<path d="{d}" fill="none" stroke="{c}" stroke-width="{w}" opacity="{op}"/>'
def rect(x,y,w,h,c):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{c}"/>'
def curve(points,c,w=.3):
 out=[]
 for (x,y),(xx,yy) in zip(points,points[1:]):
  for t in [0,.25,.5,.75]:out.append((x+(xx-x)*t,y+(yy-y)*t+rng.uniform(-.3,.3)))
 out.append(points[-1]);return p('M'+'L'.join(f'{x:.2f} {y:.2f}' for x,y in out),c,w)

s='<defs><linearGradient id="screen" x2="0" y2="1"><stop stop-color="#242318"/><stop offset="1" stop-color="#050b0d"/></linearGradient><linearGradient id="rim" x2=".5" y2="1"><stop stop-color="#595143"/><stop offset=".3" stop-color="#25251f"/><stop offset="1" stop-color="#827b68"/></linearGradient></defs>'
for k,(x,y) in enumerate([(0,1),(39,1),(0,33),(39,33)]):
 s+=f'<rect x="{x+.5}" y="{y}" width="37" height="27.8" rx="1.1" fill="url(#rim)"/><rect x="{x+1.6}" y="{y+1.2}" width="34.6" height="24.9" rx=".4" fill="url(#screen)"/>'
 for j in range(18):
  s+=rect(x+2+j*1.8,y+.4,rng.uniform(.3,1.2),.2,'#8c8e7e')
 for j in range(8):
  s+=rect(x+3+j*4,y+26.5,rng.uniform(.5,1.6),.2,'#777f78')
 for xx in range(3,36,4):s+=p(f'M{x+xx} {y+3}v21','#474633',.13,.45)
 for yy in range(4,26,4):s+=p(f'M{x+2} {y+yy}h34','#474633',.13,.45)
 for xx in range(3,36,5):s+=rect(x+xx,y+25.3,1,.35,'#8b9186')
 for yy in range(3,25,4):s+=rect(x+1.8,y+yy,.7,.5,'#9a9b89')
 def pts(vals):return [(x+4+i*31/(len(vals)-1),y+v) for i,v in enumerate(vals)]
 if k==0:
  s+=curve(pts([5,4,7,9,8,7,11,9,10,5,5,4,7,10,8,9,5,3,6,8]),'#bb8b25',.4)
  for yy,c in [(17,'#245bb1'),(22,'#288997')]:s+=curve(pts([yy+rng.uniform(-1,1) for i in range(23)]),c,.4)
 elif k==1:
  vals=[9,8,9,8,7,9,11,10,7,8,6,9,11,10,7,5,4];s+=curve(pts(vals),'#143c71',1.6)+curve(pts(vals),'#1ba1c7',.4)
  vals=[24,19,23,22,20,23,22,16,14,19,17,24,22,23,21,24];v=pts(vals)
  for n in range(48):
   t=n*15/47;ii=min(14,int(t));height=24-(vals[ii]*(1-(t-ii))+vals[ii+1]*(t-ii));height=max(.2,height+rng.uniform(-1.5,1.5));s+=rect(x+4+n*31/48,y+24-height,.42,height,'#956513')
 elif k==2:
  vals=[20,21,20,19,20,19,18,17,16,16,14,12,9,6,9,10];v=pts(vals);s+=f'<path d="M{x+4} {y+24}L'+ 'L'.join(f'{a} {b-3}' for a,b in v)+ 'L'+'L'.join(f'{a} {b+3}' for a,b in v[::-1])+'Z" fill="#0d3b93"/>'+curve(v,'#d9bc64',.42)
  for j in range(4):s+=p(f'M{x+6} {y+4+j*.8}h{12-j*1.5}','#9ca7a3',.25,.7)
 else:
  vals=[8,9,10,8,8,6,7,6,5,6,9,13,13,12,10,6];s+=curve(pts(vals),'#174c7b',1.5)+curve(pts(vals),'#dbad45',.48)
  s+=curve(pts([21,21,21,22,21,22,21,21,19,19,19,19,19,20,20,22]),'#2bb2bd',.45)
 s+=rect(x+9,y+28.2,21,.5,'#464e4c')
 for j in range(4):s+=rect(x+10+j*5,y+28.8,2.1,.6,'#586267')
write_part(R/'parts/bitmap-1895.svg',[0,0,77,63],s)
s=rect(0,0,43,35,'#020607')+rect(0,0,43,1,'#20271a')+rect(0,33,43,2,'#24251a')
for k in range(2):
 y=12+k*8
 s+=rect(11,y-1,14,4,'#0b2420')
 for j in range(7):
  xx=10+rng.uniform(0,3);yy=y-1+j*.65;ww=rng.uniform(7,13)
  s+=rect(xx,yy,ww,.45,rng.choice(['#19be8e','#29d8a4','#2c9975','#0b735b']))
  if j%2==0:s+=rect(xx+ww*.5,yy,rng.uniform(.4,1.3),.5,'#071918')
 s+=rect(21,y-2,4,2,'#ca4218')+rect(12,y+1,3,1,'#2234a0')+rect(24,y+2,1.4,1.6,'#2e72c1')

for j in range(10):
 x=rng.choice([2,27,31]);y=rng.uniform(5,31);s+=rect(x,y,rng.uniform(2,8),.35,rng.choice(['#535b3a','#1f5c56','#765029','#5b6b68']))
for y in [13,18,23]:s+=rect(29,y,1.4,1.4,'#b23914')+rect(27,y+2,3,.4,'#697777')
s+=p('M9 14v5M14 27h10','#12b87a',.7)
for j in range(9):s+=rect(3+j*4,34,.7,.4,'#737b61')
write_part(R/'parts/bitmap-1897.svg',[0,0,43,35],s)
for i in [1895,1897]:
 render(R/f'parts/bitmap-{i}.svg',770,R/f'previews/monitor-{i}-new.png');a=Image.open(R/f'reference/{i}.png').convert('RGBA');b=Image.open(R/f'previews/monitor-{i}-new.png');a=a.resize(b.size);o=Image.new('RGB',(1540,b.height+30),'#303739');d=ImageDraw.Draw(o)
 for j,im in enumerate([a,b]):o.paste(im,(770*j,30),im);d.text((770*j+10,8),f'{i} '+['ORIGINAL','R1 NATIVE CHART SCREEN'][j],fill='white')
 o.save(R/f'previews/monitor-{i}-original-new.png')
