from assemble import *
import subprocess
A=B/'art'
def text(r,x,y,txt,size=18,color='#dfe7ed'):
 t=el('text',x=x,y=y,font_size=size,fill=color,font_family='Noto Sans CJK SC, sans-serif');t.text=txt;r.append(t)
def embed(r,var,sid,x,y,s,prefix):
 g=el('g',transform=f'translate({x} {y}) scale({s})');g.append(sprite(sid,1,var,prefix));r.append(g)
def output(r,n):
 for j,c in enumerate(list(r)):
  if c.tag.endswith('svg') and c.get('overflow')=='hidden':
   defs=el('defs');cp=el('clipPath',id=f'panel-clip-{j}',clipPathUnits='userSpaceOnUse');cp.append(el('rect',x=c.get('x','0'),y=c.get('y','0'),width=c.get('width'),height=c.get('height')));defs.append(cp)
   idx=list(r).index(c);r.remove(c);wrap=el('g',clip_path=f'url(#panel-clip-{j})');wrap.append(c);r.insert(idx,wrap);r.append(defs)
 E.ElementTree(r).write(A/(n+'.svg'),encoding='unicode');subprocess.run(['inkscape',str(A/(n+'.svg')),'-o',str(A/(n+'.png'))],capture_output=True,check=True)
r=el('svg',viewBox='0 0 1240 1420',width=1240,height=1420);r.append(el('rect',width=1240,height=1420,fill='#172129'))
text(r,32,45,'CT 教官 R9 · CT教官领扣配色呼应',29);text(r,32,78,'两粒领扣呼应袖章暖棕铜色浅条；其余配色、结构与动作注册保持R8。',18)
for row,sid in enumerate([498,562]):
 for col,var in enumerate(['r8','instructor']):
  x=20+col*610;y=100+row*625;r.append(el('rect',x=x,y=y,width=590,height=605,rx=7,fill='#e4e8e9'))
  text(r,x+23,y+35,('R8 · 前版' if col==0 else 'R9 · 领扣暖铜小修')+(' / 无盾' if row==0 else ' / 持盾'),21,'#24333b')
  embed(r,var,sid,x+355,y+286,3.7,f'c{row}{col}')
text(r,30,1380,'原时间轴同姿离线装配，不是游戏运行截图；武器占位与空握继承原稿，未修复。',17)
output(r,'教官R9-R8同姿四格对照')
r=el('svg',viewBox='0 0 960 590',width=960,height=590);r.append(el('rect',width=960,height=590,fill='#172129'));text(r,24,38,'100% 源逻辑尺寸 · 明暗背景',23)
for row,bg in enumerate(['#e4e8e9','#26343d']):
 y=65+row*240;r.append(el('rect',x=12,y=y,width=936,height=225,fill=bg))
 for col,(var,sid) in enumerate([('r8',498),('instructor',498),('r8',562),('instructor',562)]):
  embed(r,var,sid,155+col*230,y+97,1,f'n{row}{col}');text(r,70+col*230,y+205,('R8' if var=='r8' else 'R9')+(' 无盾' if sid==498 else ' 持盾'),17,'#31464f' if row==0 else '#c2cfd5')
text(r,24,576,'不等于运行时单位缩放；请本地游戏验证最终尺寸、遮挡与动画。',15)
output(r,'教官R9-100pct双背景')
r=el('svg',viewBox='0 0 1250 760',width=1250,height=760);r.append(el('rect',width=1250,height=760,fill='#e4e8e9'));text(r,25,40,'R9 改动部件 · 原注册 / 外轮廓内局部试制',25,'#24333b')
for col,(n,label) in enumerate([(488,'统一三目头舱'),(487,'胸硬区 / 暖布带 / 柔腹'),(485,'绑带腿 / 同系宽壳'),(495,'口袋腿 / 同系宽壳')]):
 root=E.parse(B/'parts'/f'{n}.svg').getroot();box=root.get('viewBox');v=el('svg',x=20+col*310,y=85,width=290,height=555,viewBox=box)
 for child in shape(n,'instructor',f'd{n}'):v.append(child)
 r.append(v);text(r,25+col*310,675,f'{n} · {label}',17,'#24333b')
text(r,25,720,'新增领扣暖铜小修为 MOD 设计，非原作肩章/军衔。章面采用 CF5 真实字标；小尺寸主要读章形。',16,'#425963')
output(r,'教官R9-部件近景')
for n in ['instructor-unshielded','instructor-shielded']:
 subprocess.run(['inkscape',str(A/(n+'.svg')),'-o',str(A/(n+'.png'))],capture_output=True,check=True)

r=el('svg',viewBox='0 0 1100 880',width=1100,height=880);r.append(el('rect',width=1100,height=880,fill='#e4e8e9'));text(r,35,45,'R8 / R9 · 领胸近景与袖章色系核对',27,'#24333b')
for col,(var,label) in enumerate([('r8','R8 · 深灰领扣'),('instructor','R9 · 暖铜色领扣')]):
 v=el('svg',x=35+col*540,y=115,width=490,height=570,viewBox='-35 -164 90 86',overflow='hidden')
 for c in shape(487,var,f'collar{col}'):v.append(c)
 r.append(v);text(r,45+col*540,94,label,22,'#24333b')
# Same sleeve swatch/reference for both: the pale warm stripe, not the red cloth base.
v=el('svg',x=60,y=710,width=260,height=100,viewBox='-23 25 49 31',overflow='hidden')
for c in shape(486,'r8','sleeve-reference'):v.append(c)
r.append(v);text(r,365,747,'目标：袖章浅条 #947664（暖棕铜色）',20,'#24333b');text(r,365,783,'保留小面积亮面与深边；不恢复高亮黄，不整粒平涂。',17,'#425963')
text(r,35,850,'仅改487及其图集中的两粒扣件填色；原几何、袖章本身和其他装饰均不变。',17,'#425963');output(r,'教官R9-R8领胸近景')
