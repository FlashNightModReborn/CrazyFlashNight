"""R3: broad three-zone ground overlap and original two-slot recessed floor lamps."""
from pathlib import Path
import random,math,re
from atmosphere_r2 import P,E,G
from svg_native import write_part
R=Path(__file__).resolve().parents[1]
def apply():
 p=R/'parts/03-metal-floor.svg';s=p.read_text()
 # A broad remaining steel shelf extends under sediment; local mud coverage supplies real material overlap.
 s=s.replace('x1="255" y1="164" x2="335" y2="120"','x1="120" y1="170" x2="245" y2="45"')
 s=s.replace('<stop stop-color="white"/><stop offset="1" stop-color="black"/>','<stop stop-color="white"/><stop offset=".45" stop-color="#d2d2d2"/><stop offset=".78" stop-color="#777777"/><stop offset="1" stop-color="black"/>')
 rng=random.Random(3031580);a='<g id="r3-mixed-sediment-cover">'
 # Broad but torn sediment islands form the middle material zone, leaving complete steel islands between them.
 for _ in range(450):
  y=rng.uniform(185,452);inner=135+(y-170)*1.04;x=rng.uniform(inner,inner+195);u=(x-inner)/195
  w=rng.uniform(8,31);h=rng.uniform(1.3,4.5)
  a+=P(f'M{x:.1f} {y:.1f} l{w*.2:.1f} {-h*.45:.1f} l{w*.15:.1f} {h*.15:.1f} l{w*.25:.1f} {-h*.5:.1f} l{w*.4:.1f} {h*.4:.1f} l{-w*.12:.1f} {h*.8:.1f} l{-w*.25:.1f} {-h*.15:.1f} l{-w*.3:.1f} {h*.4:.1f}Z',rng.choice(['#49412e','#51462f','#5b4e33']),None,op=.22+u*.28)
 # Mud settles into steel grooves in broken, shallow lenses, not one solid diagonal stripe.
 for _ in range(1900):
  y=rng.uniform(180,452);inner=135+(y-170)*1.04;outer=inner+205
  x=rng.uniform(inner-25,outer+20);u=(x-inner)/(outer-inner)
  chance=.25+.65*max(0,min(1,u))
  if rng.random()>chance:continue
  w=rng.uniform(2,11)*( .6+(y-170)/400);h=rng.uniform(.35,1.8)
  a+=P(f'M{x:.1f} {y:.1f} q{w*.3:.1f} {-h:.1f} {w*.55:.1f} {-h*.5:.1f} l{w*.45:.1f} {h*.25:.1f} l{-w*.2:.1f} {h:.1f} q{-w*.3:.1f} {-h*.2:.1f} {-w*.8:.1f} {h*.1:.1f}Z',rng.choice(['#514730','#5b4e32','#6a5838','#413b2a','#706042']),None,op=rng.uniform(.28,.6))
  if rng.random()<.4:a+=P(f'M{x:.1f} {y+h*.4:.1f} l{w*.7:.1f} .2','none','#24291e',.35,.5)
 # Connected sand tongues bury complete groups in selected grooves, leaving dark exposed plate islands.
 for x,y,w,h in [(195,226,48,5),(260,245,55,6),(301,266,38,4),(280,291,54,6),(348,311,57,7),(332,331,43,5),(392,346,49,7),(408,371,55,7),(440,391,46,6),(479,411,63,8),(516,430,48,6),(373,286,28,4),(479,353,31,5),(552,414,36,5)]:
  a+=P(f'M{x} {y} q{w*.15:.1f} {-h:.1f} {w*.3:.1f} {-h*.6:.1f} l{w*.16:.1f} {h*.18:.1f} q{w*.25:.1f} {-h*.55:.1f} {w*.54:.1f} {h*.12:.1f} l{-w*.12:.1f} {h*.5:.1f} q{-w*.23:.1f} {-h*.22:.1f} {-w*.38:.1f} {h*.35:.1f} l{-w*.2:.1f} {-h*.12:.1f}Z','#62553a',None,op=.65)
  a+=P(f'M{x+3} {y-1} q{w*.35:.1f} {-h*.7:.1f} {w*.8:.1f} {-h*.3:.1f}','none','#82714c',.55,.28)
 # Fine sand over the exposed metal is deliberately densest in this middle zone.
 for _ in range(4200):
  y=rng.uniform(181,452);inner=135+(y-170)*1.04;x=rng.uniform(inner-18,inner+230)
  a+=E(round(x,2),round(y,2),rng.uniform(.2,.8),rng.uniform(.12,.35),rng.choice(['#82704b','#66583b','#302d20','#a18c60']),rng.uniform(.18,.5))
 a+='</g>';s=s.replace('</svg>',a+'</svg>');p.write_text(s)
 # Preserve R2 stencil, rebuild only fixtures using individual measured corners.
 p=R/'parts/05-markings-lights.svg';s=p.read_text();s=s[:s.index('</g>')+4]
 # outer quad: rear-left/rear-right/front-right/front-left, source pixels; each fixture measured independently.
 lamps=[([(235,167.5),(286.5,168),(304,180.3),(251,180.5)],.85), ([(377.5,279.3),(430.2,279.8),(453.2,294.4),(396.5,294.2)],.92), ([(577.5,435.2),(625.7,435.8),(649.5,451.2),(600.3,451.2)],1)]
 for n,(q,k) in enumerate(lamps):
  def pt(u,v):
   return ((1-v)*((1-u)*q[0][0]+u*q[1][0])+v*((1-u)*q[3][0]+u*q[2][0]),(1-v)*((1-u)*q[0][1]+u*q[1][1])+v*((1-u)*q[3][1]+u*q[2][1]))
  def quad(u0,v0,u1,v1):return 'M'+' L'.join(f'{x:.2f} {y:.2f}' for x,y in [pt(u0,v0),pt(u1,v0),pt(u1,v1),pt(u0,v1)])+'Z'
  s+='<defs>'+G(f'frame{n}',[(0,'#788785'),(.2,'#354344'),(.7,'#263234'),(1,'#7d8f8e')])+G(f'slot{n}',[(0,'#205257'),(.4,'#38c6c5'),(.68,'#40d6d1'),(1,'#1b777c')])+'</defs>'
  s+=P(quad(-.04,.02,1.04,1.12),'#111e1d',None,op=.85)
  s+=P(quad(0,0,1,1),f'url(#frame{n})','#8a9d9b',.45,.9)
  s+=P(quad(.045,.11,.965,.9),'#101d20','#344e50',.5)
  for v0,v1 in [(.24,.36),(.63,.76)]:
   s+=P(quad(.13,v0-.045,.87,v1+.05),'#122d32')
   s+=P(quad(.14 if v0<.5 else .12,v0,.86 if v0<.5 else .9,v1),f'url(#slot{n})')
   x,y=pt(.16,v0+.035);xx,yy=pt(.84,v0+.035);s+=P(f'M{x:.2f} {y:.2f} L{xx:.2f} {yy:.2f}','none','#72dad2',.38,.65)
  # The front lip catches reflected cyan; it is separate from the two emitting bars.
  x,y=pt(.02,.96);xx,yy=pt(.99,.96);s+=P(f'M{x:.2f} {y:.2f} L{xx:.2f} {yy:.2f}','none','#75a09a',.6,.65)
 s+='</svg>';p.write_text(s)
 p=R/'parts/06-optional-light-glow.svg';s=p.read_text().replace('stop-opacity=".2"','stop-opacity=".29"').replace('ry="22"','ry="30"').replace('cy="288"','cy="279"').replace('cy="175"','cy="169"').replace('cy="444"','cy="438"');p.write_text(s)
