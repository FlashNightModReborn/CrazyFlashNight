from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
p=Path(__file__).parent/'textures';font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';bold='/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
for k,t,s in [('current','当前角色','演示数据 · 当前使用'),('recent02','角色档案 02','演示数据 · 最近档案'),('recent03','角色档案 03','演示数据 · 最近档案'),('all','全部档案','展开目录  ›')]+[(f'demo{i:02}',f'角色档案 {i:02}','演示目录 · 非真实档案') for i in range(1,6)]:
 im=Image.new('RGB',(1000,250),'#263744');d=ImageDraw.Draw(im);d.text((35,-5),t,font=ImageFont.truetype(bold,106),fill='#f3f0e5');d.text((40,156),s,font=ImageFont.truetype(font,37),fill='#aebbc3')
 if k=='current':d.rectangle((0,0,10,250),fill='#9bc7dd');d.rectangle((0,0,220,7),fill='#9bc7dd')
 im.save(p/('archive-'+k+'.png'))
colors=['#6561a3','#bd534e','#774748','#b4bbc2','#737c81','#3d674a']
for i in range(1,7):
 im=Image.new('RGB',(224,1280),'#20232a');d=ImageDraw.Draw(im);d.rectangle((14,14,210,1266),fill=colors[i-1]);d.rectangle((18,20,206,32),fill=colors[i-1]);d.text((23,90),f'CF{i}',font=ImageFont.truetype(bold,66),fill=('#22262b' if i in [4,5] else '#f0eee5'))
 for j,c in enumerate('闪客快打'):d.text((65,335+j*124),c,font=ImageFont.truetype(bold,86),fill=('#22262b' if i in [4,5] else '#f0eee5'))
 d.rectangle((35,1090,189,1105),fill=colors[i-1]);d.text((48,1140),f'0{i}',font=ImageFont.truetype(font,66),fill=('#30343a' if i in [4,5] else '#dddeda'));im.save(p/f'case-spine-cf{i}.png')
