#!/usr/bin/env python3
"""CF6 stage 6, display armour, bitmap 1758 (native 68 x 195).

An inert, closed suit of armour; a slender spear at image left and a plain
oblique heater shield at image right. All visible marks are editable SVG paths,
ellipses and gradients. No bitmap, external resource, filter or font is used.
Original-reference registration, pose and handedness are deliberately retained.
Run: python source/display_armor.py
Rebuilds parts/bitmap-1758.svg and transparent 1x / 4x PNG QA renders.
"""
from pathlib import Path
import random, re, math
from svg_native import write_part, render
ROOT=Path(__file__).resolve().parents[1]

def path(d,fill='none',stroke=None,w=.4,extra=''):
    return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{w}"' if stroke else '')+f' {extra}/>'
def line(d,c,w=.35,extra=''):
    return path(d,'none',c,w,extra)
def ellipse(x,y,rx,ry,c,extra=''):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}" {extra}/>'
def grad(id,stops,x1='0%',y1='0%',x2='100%',y2='0%'):
    return f'<linearGradient id="{id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</linearGradient>'
def radial(id,stops,cx='40%',cy='20%',r='80%',fx=None,fy=None):
    return f'<radialGradient id="{id}" cx="{cx}" cy="{cy}" r="{r}" fx="{fx or cx}" fy="{fy or cy}">'+''.join(f'<stop offset="{p}" stop-color="{c}"/>' for p,c in stops)+'</radialGradient>'
def rivet(x,y,r=.24,bright='#aaa99a'):
    return ellipse(x+.08,y+.11,r+.05,r+.07,'#1e201b')+ellipse(x,y,r,r,bright)+ellipse(x-.07,y-.07,r*.38,r*.30,'#d5d2c4')

# These native-coordinate contours also clip the editable etched grain.
HELM='M25.2,58.0 C24.2,51.3 24.2,42.6 25.2,36.3 C26.0,31.1 28.9,27.4 32.5,27.1 C37.8,26.2 41.9,30.1 43,36.1 L43.6,43.5 L43.5,56.8 C39.3,61.1 29.3,61.0 25.2,58Z'
CHEST='M22.1,62.8 Q28.5,60.0 34.5,61.3 Q41.6,60.3 47.4,63.6 C49.8,73.7 48.2,87.8 42.5,99.9 Q34.1,103.8 25.0,100.9 C20.6,93.9 18.9,76.1 22.1,62.8Z'
LPAUL='M21.9,57.9 Q16.2,57.4 12.8,63.2 Q9.3,67.8 8.5,74.6 Q13.5,78.8 20.8,77.4 Q24.1,69.0 24.9,63.2Z'
RPAUL='M44.1,58.4 Q50.0,58.2 54.2,64.5 Q58.1,69.4 59.5,75.9 Q54.4,79.8 48.1,77.6 Q46.0,69.2 43.0,64.0Z'
LARM='M9.4,76.0 L18.7,77.9 Q16.8,87.0 11.4,93.9 L3.1,92.1 Q6.7,85.4 9.4,76.0Z'
RARM='M50.2,77.4 L58.0,76.1 Q62.4,84.4 63.3,91.6 L56.3,95.7 Q51.9,88.9 50.2,77.4Z'
LELBOW='M4.8,89.5 L10.7,91.3 L14.4,95.3 L11.0,101.0 L5.9,100.9 L1.1,96.4 L1.6,93.7Z'
RELBOW='M57.2,89.9 L63.2,90.5 L67.0,95.2 L65.0,101.1 L59.9,103.1 L54.7,97.2Z'
LFORE='M6.5,99.4 L12.7,98.5 Q15.9,104.4 21.1,113.7 L17.2,119.4 Q10.1,113.9 6.8,106.5Z'
RFORE='M59.3,100.3 L64.6,102.2 Q60.7,111.5 54.6,119.7 L47.5,116.0 Q51.2,106.5 56.7,100.1Z'
LHAND='M16.1,115.2 L21.5,115.0 L24.2,119.1 L24.3,121.7 L22.8,125.4 L20.2,127.1 L16.6,125.3 L14.7,121.8 L14.7,118.2Z'
RHAND='M48.4,116.5 L53.1,119.2 L51.0,123.0 L47.9,126.2 L44.8,128.2 L43.7,126.1 L45.0,121.5Z'
LTHIGH='M22.6,127.9 L31.1,130.2 L31.6,145.1 Q28.4,148.2 20.1,144.6 L19.3,135.5Z'
LLEG='M20.0,140.4 Q24.7,139.2 30.2,141.0 L30.0,163.8 L29.1,177.5 Q25.0,181.8 20.1,178.0 L19.3,160.5Z'
RLEG='M37.2,146.7 L46.0,146.0 L46.4,161.0 L44.6,179.3 Q39.9,182.0 35.3,178.2Z'
LBOOT='M20.6,177.6 L28.5,178.7 L30.2,187.1 L29.7,191.6 Q25.2,194.7 18.9,191.9 L18.8,186.7Z'
RBOOT='M37.8,178.3 L44.3,178.4 L45.9,184.4 Q48.7,186.8 49.8,190.3 L49.7,192.1 Q44.7,194.3 38.1,191.9 L36.8,187.9Z'
SHIELD='M31.0,135.0 L41.7,127.8 Q48.7,127.8 56.5,132.0 L58.6,135.1 C59.0,151.8 55.5,166.2 45.6,175.9 C35.7,169.3 31.7,154.4 31.0,135.0Z'

def draw():
    defs=''.join([
      grad('spear',[('0%','#24271f'),('24%','#5d6155'),('45%','#8d8e7f'),('68%','#4a4d43'),('100%','#1c2018')]),
      grad('darksteel',[('0%','#1b1e19'),('18%','#484d3f'),('37%','#8c9180'),('49%','#535b48'),('64%','#353d2d'),('85%','#171d14'),('100%','#080c08')]),
      grad('legsteel',[('0%','#171e15'),('15%','#525d43'),('33%','#626e52'),('42%','#7e896d'),('53%','#424f36'),('74%','#202d1b'),('100%','#0b110c')]),
      grad('armsteel',[('0%','#161c15'),('18%','#3a4435'),('38%','#8f9787'),('48%','#c6c7b6'),('56%','#7f8976'),('76%','#454f3a'),('100%','#141d13')]),
      grad('rightarm',[('0%','#242d20'),('26%','#596451'),('43%','#b6beaa'),('54%','#d1d1c0'),('64%','#828d76'),('86%','#3b4532'),('100%','#131c12')],x1='5%',y1='40%',x2='100%',y2='80%'),
      grad('joint',[('0%','#10180f'),('28%','#7d8870'),('48%','#d0d0bc'),('60%','#858d75'),('100%','#1f281a')],x1='10%',y1='10%',x2='95%',y2='100%'),
      grad('flange',[('0%','#303a27'),('20%','#777e66'),('42%','#d7d6c2'),('57%','#727a63'),('80%','#39422f'),('100%','#131b11')]),
      grad('helmet',[('0%','#2c2e24'),('17%','#515344'),('31%','#777867'),('49%','#a4a28a'),('61%','#727460'),('77%','#575c49'),('100%','#272d22')]),
      radial('dome',[('0%','#b5b19b'),('25%','#93917d'),('50%','#727363'),('77%','#505448'),('100%','#2c3028')],cx='49%',cy='27%',r='74%'),
      grad('ridge',[('0%','#535641'),('35%','#999a7b'),('49%','#c0baa0'),('68%','#8d8c70'),('100%','#545c45')]),
      radial('chest',[('0%','#e2e0d4'),('12%','#d2d1c6'),('27%','#adb0a4'),('44%','#737c6b'),('61%','#3b4834'),('78%','#202d1b'),('94%','#111c0f'),('100%','#141d11')],cx='47%',cy='23%',r='83%'),
      radial('leftshoulder',[('0%','#b8b7a6'),('20%','#92988a'),('49%','#697362'),('75%','#414d39'),('100%','#202d1d')],cx='48%',cy='23%',r='87%'),
      radial('rightshoulder',[('0%','#afb7a6'),('25%','#949e8b'),('53%','#697963'),('80%','#344830'),('100%','#132810')],cx='44%',cy='24%',r='84%'),
      grad('waist',[('0%','#1c2418'),('20%','#525a46'),('39%','#a0a18c'),('48%','#d4cfb8'),('58%','#7c8269'),('78%','#343f2c'),('100%','#172312')]),
      grad('skirt',[('0%','#13170e'),('18%','#292d1b'),('39%','#3b3b25'),('57%','#262a19'),('80%','#161e10'),('100%','#0b1409')]),
      grad('shieldface',[('0%','#757b6b'),('15%','#a4a797'),('32%','#929988'),('50%','#a3a894'),('67%','#8e9782'),('82%','#7b866f'),('100%','#555f49')]),
      grad('shieldside',[('0%','#575e4c'),('21%','#747961'),('47%','#656d55'),('79%','#3e4935'),('100%','#252f23')]),
      grad('shieldrim',[('0%','#b2b3a2'),('15%','#828b75'),('36%','#c0bfab'),('61%','#7c866c'),('84%','#a4a88f'),('100%','#535e44')],x1='0%',y1='0%',x2='100%',y2='100%'),
      radial('boot',[('0%','#8e947e'),('25%','#6b765e'),('52%','#444f38'),('78%','#242e1f'),('100%','#10190f')],cx='37%',cy='29%',r='88%'),
    ])
    defs=defs.replace('<radialGradient id="chest"', '<radialGradient id="chest" gradientTransform="matrix(.72 0 0 1 .18 0)"')
    defs+='<radialGradient id="chest-side-reflection" cx="52%" cy="43%" r="53%"><stop offset="0%" stop-color="#d8d5c6" stop-opacity=".50"/><stop offset="40%" stop-color="#c6c7b4" stop-opacity=".30"/><stop offset="74%" stop-color="#a5ae98" stop-opacity=".13"/><stop offset="100%" stop-color="#747f68" stop-opacity="0"/></radialGradient>'
    allmetal=[HELM,CHEST,LPAUL,RPAUL,LARM,RARM,LELBOW,RELBOW,LFORE,RFORE,LHAND,RHAND,LTHIGH,LLEG,RLEG,LBOOT,RBOOT,SHIELD]
    defs+='<clipPath id="metal-grain">'+''.join(path(d,'white') for d in allmetal)+'</clipPath>'
    defs+='<clipPath id="chest-clip">'+path(CHEST,'white')+'</clipPath>'
    defs+='<clipPath id="shield-clip">'+path(SHIELD,'white')+'</clipPath>'
    a=['<title>1758 · static closed steel armour display, spear and oblique shield</title>',
       '<desc>Hand-redrawn native SVG at 68 by 195; quiet aged black steel and silver-grey planes; original empty-helmet display stance.</desc>',
       '<defs>'+defs+'</defs>','<g stroke-linejoin="round" stroke-linecap="round">']
    # The spear is exceptionally narrow in the reference. It remains behind the
    # left shoulder and fist, with a slender pointed leaf and plain shaft.
    a+=['<g id="spear">',path('M22.45,1.2 L22.85,8.0 L23.65,11.0 L22.85,15.1 L22.6,26.5 L21.55,26.5 L21.65,15.1 L21.15,12.3 L22.0,8.1Z','url(#spear)'),
        path('M21.6,22 L22.9,22 L21.7,186.7 L20.4,187.4Z','url(#spear)'),
        line('M22.22,2.8 L22.18,14.3 M22.15,23.2 L21.4,111.7','#9c9e8e',.20,'opacity=".6"'),
        line('M21.52,29.8 L20.75,112.9','#1c2119',.28),
        path('M21.46,14.6 L22.78,14.6 L22.72,17.6 L21.46,17.6Z','#5b5f50'),line('M21.48,15.1 L22.68,15.1','#a3a491',.22),'</g>']
    # Deep interior gaps and the almost hidden right thigh. No skin or face.
    a+=['<g id="empty-articulation-and-legs">',
        path('M23,92 L44.4,92 L47,119 L44.9,142 L38,158 L32.2,153 L29.5,141 L20.0,139 L18.1,124Z','#0d130b'),
        path('M37.7,126.9 L45.7,127.1 L47.3,145.1 L44.8,150.1 L36.1,147.9Z','url(#darksteel)','#111c0f',.5),
        path(LTHIGH,'url(#legsteel)','#121b0f',.6),
        path('M21.0,128.9 Q25.9,130.4 30.8,129.5 L30.7,134.4 Q26.2,137.1 19.8,134.2Z','url(#darksteel)'),
        line('M21.7,129.4 Q26.2,132.2 30.8,131.3','#a8ad95',.45),
        path(LLEG,'url(#legsteel)','#0d180c',.6),path(RLEG,'url(#darksteel)','#111a0e',.6),
        # Poleyns overlap the shins; lateral flanges preserve the plated silhouette.
        path('M19.8,134.7 Q24.5,132.5 30.6,134.5 L31.4,138.5 L29.7,142.0 Q24.3,142.1 19.2,139.5Z','url(#darksteel)','#182512',.35),
        path('M20.2,135.1 Q25.9,133.0 29.9,135.2 L29.1,139.1 Q25.4,140.8 20.0,138.7Z','url(#legsteel)'),
        line('M20.4,135.5 Q24.8,134.0 29.4,136.0','#8d977b',.38),
        line('M20.7,140.7 Q24.5,142.0 29.9,140.5','#3a4a2c',.6),
        line('M23.9,151.2 Q24.8,164.0 24.1,175.6','#a7ab90',.36,'opacity=".45"'),
        line('M21.8,153.5 L22.2,171.6','#727d5f',.32,'opacity=".58"'),
        line('M28.1,151.0 L27.8,176.1','#131f0f',.6),
        path('M20.2,175.5 Q24.4,177.9 29.4,175.5 L29.0,181.1 Q24.4,184.7 19.7,180.6Z','url(#darksteel)','#10190c',.4),
        path('M37.0,174.8 Q40.6,177.4 44.8,175.4 L44.3,180.1 L38.0,182.7 L36.7,179.1Z','url(#darksteel)'),
        line('M21.3,179.1 Q24.1,181.4 28.2,178.9','#90987a',.55),
        path(LBOOT,'url(#boot)','#11190e',.6),path(RBOOT,'url(#boot)','#11190e',.6),
        path('M19.3,186.3 Q24.2,188.1 29.7,185.8 L30.1,188.3 Q24.9,190.9 18.9,188.6Z','url(#darksteel)'),
        path('M37.4,184.1 Q41.4,185.6 45.3,183.3 L47.3,186.3 Q43.4,188.6 37.4,187.2Z','url(#flange)'),
        line('M19.6,184.7 Q23.8,186.4 29.2,184.9 M19.5,187.9 Q24.3,189.8 29.4,187.7','#6c7759',.40),
        line('M37.6,185.3 Q41.8,186.9 45.3,185.3 M38,188.2 Q43.1,190.2 48.0,188.3','#8e987b',.40),
        line('M19.4,191.4 Q24.6,193.1 29.4,191.1 M38.9,191.3 Q43.9,192.9 49.1,191.4','#0c150b',.7),
        '</g>']
    # Arms are behind the cuirass. Articulation is divided into upper cannon,
    # overlapping lames, elbow bowl and tapering forearm, rather than one tube.
    a+=['<g id="arm-articulation">',path('M11,72 L19.4,73.3 L20.1,81.7 L14.4,92.8 L5.0,95.2 L4.8,91.1Z','#111a0e'),
        path('M49.7,72.4 L58.3,73.9 L61.5,84.5 L63.9,94 L55.7,98.1 L50.7,84.8Z','#111a0e'),
        path(LARM,'url(#armsteel)','#172110',.45),path(RARM,'url(#rightarm)','#1b2916',.45)]
    for d in ['M9.4,77.1 Q12.7,79.3 17.8,79.0','M8.2,80.2 Q11.3,82.5 16.2,82.2','M6.9,84.0 Q10.1,86.3 14.8,85.7','M52.2,80.7 Q56.3,82.1 59.2,79.5','M53.3,84.1 Q57.4,86.4 60.7,83.7','M54.5,88.1 Q58.6,90.4 61.6,87.8']:
        a += [line(d,'#172413',.48),line(d,'#8d997e',.18)]
    a += [path(LELBOW,'url(#joint)','#1b2517',.45),path(RELBOW,'url(#joint)','#1b2918',.5),
          path('M1.7,94.8 Q5.6,93.0 8.6,94.7 L10.5,98.3 L6.8,100.5 Q3.0,98.9 1.7,96.7Z','url(#flange)'),
          path('M58.3,92.3 Q62.2,91.7 65.6,95.3 L64.3,99.2 L59.6,101.0 Q58.1,97.6 58.3,92.3Z','url(#flange)'),
          line('M2.4,94.5 Q5.6,93.8 8.3,95.2 M58.8,92.5 Q62.3,92.9 65.2,95.5','#c1c5ae',.42),
          rivet(8.8,96.8,.45,'#7b856b'),rivet(60.0,96.2,.48,'#8b9679'),
          path(LFORE,'url(#armsteel)','#182312',.5),path(RFORE,'url(#rightarm)','#172713',.5),
          path('M7.9,100.0 Q10.9,102.4 13.5,102.7 L20.0,114.7 L17.4,117.0 Q12.4,111.2 10.1,106.3Z','url(#flange)'),
          path('M58.2,102.6 L61.0,102.7 Q57.9,110.5 52.9,117.8 L49.2,115.6 Q53.1,109.0 58.2,102.6Z','url(#rightarm)'),
          line('M8.4,101.6 Q12.0,109.3 17.9,114.9','#c5cab5',.43),
          line('M59.6,103.7 Q56.5,111.2 51.8,116.6','#d2d6c0',.49),
          line('M12.7,100.4 Q14.9,106.8 20.4,113.5 M63.6,103 Q59.8,112.0 54.2,118.7','#25371c',.65),
          '</g>']
    # Gorget and pauldrons sit above the breastplate. Quiet closed-display stance.
    a += ['<g id="gorget-and-cuirass">',
          path('M25,55.4 Q34.0,51.7 43.6,55.7 L48.9,63.3 Q35.1,69.3 20.9,63.4Z','url(#darksteel)','#152011',.55),
          path('M24.4,57.4 Q34.6,61.9 44.1,57.2 L47.2,62.3 Q35.1,67.9 22.2,62.2Z','url(#waist)'),
          line('M24.8,59.5 Q33.8,63.9 44.5,59.5','#a2a78f',.45),
          path(LPAUL,'url(#leftshoulder)','#263322',.55),path(RPAUL,'url(#rightshoulder)','#253722',.55),
          path('M9.5,69.6 Q13.9,74.0 22.4,72.4 L20.9,77.4 Q13.8,78.8 8.5,74.6Z','url(#darksteel)'),
          path('M47.0,71.7 Q53.1,76.3 57.6,72.8 L58.8,75.9 Q54.4,79.8 48.1,77.6Z','url(#darksteel)'),
          line('M9.7,70.4 Q15.1,75.3 22.0,72.9','#9aa38b',.33,'opacity=".65"'),
          line('M9.0,74.4 Q14.5,78.1 20.7,76.6','#7e8971',.43),
          line('M47.3,72.8 Q52.9,77.0 57.8,74.4','#acb59a',.33,'opacity=".6"'),
          line('M48.6,77.0 Q53.5,79.0 58.2,75.8','#7f8d70',.40),
          line('M15.2,61.4 Q18.6,58.8 21.2,60.3 M46.4,60.1 Q50.0,61.0 52.0,64.2','#b6bba7',.42),
          rivet(21.2,65.5,.3),rivet(48.2,65.2,.3),rivet(11.3,72.1,.24),rivet(55.6,74.0,.24),
          path('M21.2,73.0 L25.1,76.0 L27.0,101.3 L21.6,104.5 L18.3,93.6 L17.7,84.6Z','url(#darksteel)'),
          path('M44.7,73.4 L48.0,77.9 L49.3,94.8 L47.4,106.4 L42.1,103.4 L41.0,86.3Z','url(#darksteel)'),
          path(CHEST,'url(#chest)','#1f2c1b',.55),
          path('M38.2,67.8 Q45.5,68.0 46.2,75.7 C46.1,84.9 42.6,93.3 39.0,97.7 C43.2,85.0 42.6,74.9 38.2,67.8Z','url(#chest-side-reflection)'),
          # Folded armpit rims and soft compound curvature, not a flat white bib.
          line('M22.7,63.5 C20.7,74.1 21.0,83.6 24.6,93.3','#737f68',.65),
          line('M46.7,64.2 C49,74.0 46.9,88.1 42.4,97.4','#111f0d',.72),
          line('M23.6,64.4 Q34.3,68.9 45.8,64.4','#919984',.35),
          path('M30.0,65.9 C32.6,69.8 34.5,79.0 34.1,94.2 L32.0,98.2 C31.8,85.2 30.0,73.9 27.0,67.2Z','#ece8dd',None,extra='opacity=".09"'),
          path('M35.3,68.2 C40.4,72.9 41.4,81.2 38.6,91.9 C41.9,84.1 43.0,75.6 39.7,68.4Z','#f2f0e7',None,extra='opacity=".055"'),
          line('M34.1,69.3 C35.0,79.0 34.0,91.6 34.3,99.9','#d6d7c6',.28,'opacity=".27"'),
          path('M25.0,97.6 Q34.6,101.3 43.1,96.7 L42.6,101.7 Q33.4,104.2 25.0,101.1Z','url(#darksteel)'),
          line('M25.1,99.4 Q33.7,102.1 42.5,99.0','#899279',.5),'</g>']
    # The fauld is short and dark. The central codpiece is closed empty armour,
    # flanked by separate hanging plates rather than skin, cloth or a figure.
    a += ['<g id="waist-and-tassets">',
          path('M21.3,99.3 L25.3,102.9 L25.7,119.2 L23.4,129.4 L20.1,132.0 L16.8,126.6 L17.3,113.5Z','url(#darksteel)','#111a0d',.3),
          path('M43.1,99.9 L46.7,103.1 L49.3,114.8 L48.0,122.4 L44.7,128.9 L41.4,126.0 L40.0,112.4Z','url(#darksteel)','#111a0d',.3),
          path('M25.0,99.2 Q33.7,102.0 42.8,98.5 L46.1,111.8 L42.0,119.7 L25.6,120.4 L19.5,113.9Z','url(#skirt)','#111b0d',.55),
          path('M24.4,98.8 Q34.2,101.9 43.4,98.4 L44.9,104.4 L41.2,108.4 Q34.6,101.3 27.8,107.2 L21.9,107.7Z','url(#waist)'),
          line('M24.6,100.5 Q34.2,103.4 43.5,99.9','#b4b59e',.43),
          path('M21.7,107.1 L27.1,106.7 Q31.3,102.6 35.7,104.0 L40.8,108.5 L45.1,106.2 L44.5,113.0 L38.8,116.5 L29.5,116.3 L22.4,114.4Z','url(#skirt)'),
          path('M24.8,105.7 L28.4,105.0 L28.2,112.2 L25.1,121.0 L22.5,126.3 L19.0,124.3 L20.1,114.7Z','url(#darksteel)','#172210',.45),
          path('M40.3,106.1 L44.6,104.9 L47.1,115.0 L44.0,124.5 L40.8,125.5 L38.4,114.4Z','url(#darksteel)','#14210f',.45),
          line('M24.9,106.3 L23.1,116.6 L21.4,122.7 M42.2,107.4 L44.1,116.2 L42.5,123.0','#768065',.48),
          path('M29.0,107.2 Q33.4,102.7 37.6,106.7 L40.0,117.2 Q39.9,126.4 33.6,132.1 Q27.2,131.6 24.5,125.8 L26.8,115.8Z','#11130b','#0b1408',.25),
          line('M29.3,108.0 Q33.4,104.2 36.8,107.9','#343b25',.25,'opacity=".6"'),
          line('M26.6,123.5 Q28.9,128.9 33.6,130.4','#26321b',.25,'opacity=".4"'),
          line('M22.1,115.1 L25.2,116.4 M21.0,119.0 L24.0,120.2 M42.3,113.5 L45.1,112.2 M42.1,118.2 L44.8,116.4','#1a2a13',.55),
          rivet(25.9,108.8,.24,'#8b927a'),rivet(43.0,109.2,.24,'#8b927a'),'</g>']
    # Helm. The four-armed cross is structural: a thin brow and a projecting
    # centre ridge between narrow sight slots. Breathing holes are black metal.
    a += ['<g id="closed-great-helm">',path(HELM,'url(#helmet)','#2d3527',.55),
          path('M25.2,39.4 L25.2,36.3 C26.0,31.1 28.9,27.4 32.5,27.1 C37.8,26.2 41.9,30.1 43.0,36.1 L43.3,40.4 Q34.7,37.5 25.2,39.4Z','url(#dome)'),
          path('M33.1,27.2 Q34.7,31.3 34.9,38.8 L36.5,39.3 Q36.0,31.9 34.8,27.1Z','url(#ridge)'),
          line('M31.6,28.1 Q28.5,31.8 27.2,37.5','#a1a18b',.27,'opacity=".6"'),
          line('M38.3,29.3 Q40.8,33.4 41.6,38.9','#b2ad96',.3,'opacity=".5"'),
          path('M25.5,40.0 Q29.4,38.9 33.7,39.6 L33.9,41.7 Q29.6,41.5 25.0,42.1Z','#080e08'),
          path('M35.7,39.7 Q39.8,39.6 43.3,40.8 L43.8,43.0 Q39.7,41.7 35.8,41.8Z','#080d07'),
          line('M26.0,39.9 Q29.6,39.3 33.4,39.8 M36.4,39.9 Q39.5,40.0 42.6,40.9','#817f6c',.22),
          path('M25.1,42.7 Q34.5,41.5 43.6,43.4 L43.6,45.2 Q34.8,43.1 25.1,44.6Z','url(#ridge)'),
          path('M34.0,38.5 L35.9,38.5 L36.5,54.3 Q36.0,55.9 34.2,55.8 L33.7,51.8Z','url(#ridge)'),
          line('M34.2,39.0 L34.4,53.9','#d1c8a9',.3),
          path('M25.0,45.0 Q29.0,44.1 33.6,44.8 L33.4,54.0 Q31.4,58.7 25.4,56.7Z','#373e2e',None,extra='opacity=".36"'),
          line('M26.0,45.1 L25.8,54.9 Q27.7,57.4 32.1,57.7','#848870',.4),
          line('M42.8,45.0 L42.7,55.7 Q40.7,58.0 36.9,58.3','#8d9378',.38),
          line('M26.0,57.4 Q34.0,61.3 43.0,56.7','#1b2817',.6),
          path('M29.2,54.6 Q33.8,56.7 39.7,54.9 L39.3,56.4 Q34.0,58.1 29.7,56.0Z','#9a9e81',None,extra='opacity=".3"')]
    # Symmetrical groups are constrained to the curved cylindrical face planes.
    vents=[(27.1,46.2,1.4,.74),(30.1,46.5,1.3,.72),(27.1,49.0,1.4,.76),(30.2,49.5,1.1,.68),(27.6,52.1,1.2,.67),(30.3,52.4,.9,.64),
           (38.0,46.9,1.2,.7),(40.7,47.3,1.3,.68),(38.1,49.7,1.2,.7),(40.7,50.1,1.3,.68),(37.9,52.5,1.0,.63),(40.4,52.6,1.0,.60)]
    for x,y,w,h in vents:
        a += [path(f'M{x},{y} l{w},.12 l0,{h} l-{w},-.08Z','#101b0d'),line(f'M{x+.1},{y+h+.14} l{w-.1},.08','#aaa88a',.17,'opacity=".56"')]
    for x,y in [(26.2,37.8),(41.8,38.6),(26.3,44.1),(42.7,44.9),(26.3,55.9),(41.9,56.2),(35.1,43.0)]:a.append(rivet(x,y,.22,'#a7a48b'))
    a+=['</g>']
    # Hands: articulated gauntlets visibly close around the pole and the shield
    # suspension grip. They terminate into real wrist cuffs, not floating gloves.
    a += ['<g id="gauntlets-and-grips">',
          path('M16.0,114.1 L21.7,113.9 L22.6,117.1 L17.4,118.4 L15.5,116.3Z','url(#flange)','#27331d',.4),
          path('M48.2,114.3 L54.7,117.1 L53.1,119.6 L46.9,117.7Z','url(#flange)','#283b1e',.4),
          path(LHAND,'url(#armsteel)','#23321a',.45),path(RHAND,'url(#rightarm)','#20321b',.45),
          path('M20.6,118.5 L22.6,118.2 L23.9,122.4 L22.7,126.5 L20.5,126.1Z','#171e12'),
          path('M18.0,117.5 L20.4,116.9 L23.0,120.0 L22.9,121.7 L19.6,120.2Z','url(#flange)'),
          path('M16.5,120.0 L19.4,121.2 L21.2,123.8 L20.6,126.8 L18.2,125.8 L16.1,122.5Z','url(#joint)'),
          line('M16.8,120.7 L19.0,121.8 M17.1,122.2 L19.8,123.6 M17.7,124.0 L20.0,125.5','#15260e',.42),
          line('M16.9,120.4 L19.0,121.5 M17.5,122.4 L19.9,123.8','#ccd0b8',.22),
          path('M46.1,120.7 L49.0,119.2 L51.4,121.2 L49.8,123.1 L47.0,122.5Z','url(#flange)'),
          path('M44.2,124.1 L47.0,122.4 L49.1,124.0 L47.9,126.4 L45.5,128.0 L43.8,126.6Z','url(#armsteel)'),
          line('M44.7,124.2 L47.8,124.9 M44.3,125.8 L46.5,126.8 M46.9,120.7 L49.6,121.8','#1b2b12',.46),
          path('M44.0,124.5 Q41.5,127.1 41.7,131.8 L44.2,134.6 L47.0,131.7 L47.0,126.0 L45.7,125.5 L45.2,130.0 L43.6,130.0 L44.7,126.1Z','#303d25','#15240f',.35),
          line('M43.6,126.0 Q42.7,128.4 43.3,131.4','#959c82',.4),
          rivet(19.2,116.8,.23),rivet(51.1,117.3,.23),'</g>']
    # Oblique plain heater shield. The far side is a distinct narrow plane and
    # its rolled edge maintains the original slanted upper line and lower point.
    a += ['<g id="oblique-heater-shield">',path(SHIELD,'url(#shieldface)','#36442d',.58),
          path('M47.9,129.2 Q52.1,129.8 56.5,132.0 L58.6,135.1 C59.0,151.8 55.5,166.2 45.6,175.9 C48.6,162.4 50.1,145.6 47.9,129.2Z','url(#shieldside)'),
          path('M31.0,135.0 L41.7,127.8 Q44.7,128.0 47.9,129.2 L47.3,131.1 L42.0,130.1 L33.0,136.3 C33.8,153.1 37.3,165.4 45.6,173.7 L45.6,175.9 C35.7,169.3 31.7,154.4 31.0,135.0Z','url(#shieldrim)'),
          line('M32.2,135.8 L42.0,129.1 Q44.6,128.7 47.5,130.2','#c9c8b5',.43),
          line('M32.4,138.2 C33.8,155.7 37.6,168.1 45.2,174.0','#b5bba2',.43),
          line('M47.8,130.3 C50.8,145.6 48.2,164.2 45.7,174.3','#b4b89b',.65),
          line('M49.1,131.1 C52.0,147.3 49.5,163.0 46.9,173.1','#38472e',.58),
          line('M56.9,134.0 C57.5,151.0 53.6,165.9 47.1,173.3','#829073',.43),
          # Simple folded brace over the upper shield plane. It catches light at
          # the rim, then recedes; no invented heraldic emblem or fantasy symbol.
          path('M35.2,137.7 L41.1,137.9 L44.3,140.1 L46.5,137.1 L47.6,137.6 L44.7,142.2 L40.8,139.4 L35.0,139.1Z','url(#shieldrim)'),
          line('M35.4,138.0 L41.1,138.2 L44.1,140.4 L46.4,137.8','#e0dec8',.50),
          line('M35.2,139.2 L40.7,139.5 L44.4,142.2 L46.4,139.6','#4c5c40',.46),
          path('M34.8,142.9 L41.4,143.8 L43.0,142.8 L44.2,144.6 L42.6,146.2 L35.1,145.3Z','#7f8b73',None,extra='opacity=".5"'),
          line('M35.5,144.9 L41.5,145.6 L43.4,144.0','#4c5f40',.4,'opacity=".6"'),
          path('M45.8,147.6 L47.2,146.4 L47.7,147.6 L46.3,149.4 L44.7,149.5Z','#b2b99f',None,extra='opacity=".8"'),
          line('M38.4,164.3 Q42.8,170.3 46.3,169.2 L48.4,167.8','#c0c3a8',.47),
          line('M38.6,165.4 Q43.0,171.3 46.3,170.2 L48.4,168.6','#5b6a4b',.45),
          rivet(33.6,137.4,.26,'#a5ae94'),rivet(44.2,132.4,.25,'#bac0a5'),rivet(55.5,135.1,.24,'#8c997b'),rivet(36.0,155.2,.24,'#aeb79d'),rivet(53.0,154.4,.23,'#7c8e6d'),
          '</g>']
    # Fine physically plausible age: tiny directional scuffs, forging speckles,
    # occasional darker pits. Seeded, individually editable and clipped to metal.
    rr=random.Random(1758)
    a += ['<g id="editable-micro-patina" clip-path="url(#metal-grain)">']
    for i in range(1020):
        x=rr.uniform(1,66.5);y=rr.uniform(27,192.7)
        if i%5==0:
            w=rr.uniform(.10,.34);h=rr.uniform(.06,.21)
            a.append(ellipse(round(x,3),round(y,3),round(w,3),round(h,3),rr.choice(['#151c12','#e9e5ce','#afa995']),f'opacity="{rr.uniform(.045,.13):.3f}"'))
        else:
            length=rr.uniform(.18,1.05);dy=rr.uniform(-.12,.18)
            a.append(line(f'M{x:.3f},{y:.3f} l{length:.3f},{dy:.3f}',rr.choice(['#e2dfc9','#192516','#b4b399']),rr.uniform(.045,.12),f'opacity="{rr.uniform(.045,.14):.3f}"'))
    for i in range(480):
        x=rr.uniform(1,66.5);y=rr.uniform(28,191.5);r=rr.uniform(.14,.72)
        pts=[]
        for j in range(7):
            theta=j*math.pi*2/7;rad=r*rr.uniform(.65,1.3)
            pts.append(f'{x+math.cos(theta)*rad:.3f},{y+math.sin(theta)*rad*.65:.3f}')
        a.append(path('M'+' L'.join(pts)+'Z',rr.choice(['#b8b49e','#141e10','#c8c5af']),None,extra=f'opacity="{rr.uniform(.018,.07):.3f}"'))
    a += ['</g>']
    # Local wear follows surface direction; a handful of long scratches are
    # intentionally low contrast, not heavy etched ornamental outlines.
    a += ['<g id="surface-wear" fill="none" opacity=".18">',
          line('M29.1,32.6 l-.9,2.2 M38.6,34.5 l1.1,2.2 M28.6,54.9 l1.5,.5','#d3cdb6',.18),
          line('M28.7,73.0 q-.9,4.0 -.2,6.6 M39.2,79.4 l-.5,5.2 M25.9,88.0 l.7,2.5','#d7d8c6',.16),
          line('M16.2,66.2 l2.6,1.3 M51.6,66.5 l1.5,2.6 M11.8,108.7 l1.1,1.5 M56.5,109.6 l-1.9,2.9','#e1e2cb',.18),
          line('M35.3,148.4 l.5,6.2 M39.1,151.0 l.2,5.8 M44.6,154.8 l-.5,8.0 M53.1,144.4 l-.2,6.0','#d6d6ba',.16),
          line('M36.0,141.3 l2.1,.4 M39.0,158.0 l2.1,.5 M50.7,151.4 l1.6,-.5 M38.0,161.5 l1.4,.3','#354a2a',.18),
          '</g>','</g>']
    # Palette finishing: reduce green cast of the traditional steel underpaint.
    # The result is warm neutral gunmetal, not olive armour or bright chrome.
    def neutral_steel(match):
        v=match.group(0)[1:]; r,g,b=[int(v[k:k+2],16) for k in (0,2,4)]
        l=.299*r+.587*g+.114*b
        l=255*(l/255)**1.095
        rgb=[round(.10*c+.90*t) for c,t in zip((r,g,b),(l*1.017,l,l*.967))]
        return '#'+''.join(f'{max(0,min(255,c)):02x}' for c in rgb)
    content=re.sub(r'#[0-9a-fA-F]{6}',neutral_steel,''.join(a))
    write_part(ROOT/'parts/bitmap-1758.svg',[0,0,68,195],content)

if __name__=='__main__':
    draw()
    render(ROOT/'parts/bitmap-1758.svg',68,ROOT/'previews/bitmap-1758-1x.png')
    render(ROOT/'parts/bitmap-1758.svg',272,ROOT/'previews/bitmap-1758-4x.png')
    print('Created native editable display armour 1758 at 1x and 4x.')
