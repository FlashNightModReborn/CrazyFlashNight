from pathlib import Path
import random
from svg_native import write_part,render
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1]
def P(d,f='none',s=None,w=.6,op=1):return f'<path d="{d}" fill="{f}" opacity="{op}"'+(f' stroke="{s}" stroke-width="{w}" stroke-linejoin="round"' if s else '')+'/>'
def E(x,y,rx,ry,f,s=None,w=.5):return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{f}"'+(f' stroke="{s}" stroke-width="{w}"' if s else '')+'/>'
def defs():return '''<defs><linearGradient id="body" x2="0" y2="1"><stop stop-color="#72796e"/><stop offset=".18" stop-color="#414b43"/><stop offset=".55" stop-color="#4d554e"/><stop offset="1" stop-color="#242d29"/></linearGradient><linearGradient id="panel" x2="0" y2="1"><stop stop-color="#5d665d"/><stop offset=".3" stop-color="#37443e"/><stop offset=".8" stop-color="#434d47"/><stop offset="1" stop-color="#1d2823"/></linearGradient><radialGradient id="tire"><stop stop-color="#35403a"/><stop offset=".5" stop-color="#424b45"/><stop offset=".7" stop-color="#29332f"/><stop offset="1" stop-color="#111b16"/></radialGradient></defs>'''
def wheel(x,y,r,flat=1):
 s=E(x,y,r,r*flat,'url(#tire)','#090e0c',1)+E(x,y,r*.64,r*.64*flat,'#4b554b','#727a6c',.6)+E(x,y,r*.43,r*.43*flat,'#303b34','#1c251f',.6)+E(x,y,r*.13,r*.13*flat,'#586055')
 for dx,dy in [(-.3,-.2),(.3,-.2),(0,.3)]:s+=E(x+dx*r,y+dy*r,r*.09,r*.09,'#121e16')
 return s
cases={
1603:((150,56),'M2 36L5 30L9 28L11 22L24 20L35 18L44 7L53 4L61 5L68 2L80 4L87 2L93 6L107 19L117 20L121 23L142 25L147 29L148 36L143 41L137 43L132 42Q132 31 120 31Q108 32 107 45L46 46Q45 31 33 32Q21 31 20 44L9 43L8 40L1 40Z'),
1604:((150,52),'M1 37L5 31L7 24L18 21L35 20L44 8L48 6L59 4L65 1L75 4L82 1L90 5L105 18L116 20L139 22L146 25L149 29L147 35L142 38L136 39L132 45Q133 33 121 32Q110 33 108 45L95 45L78 48L65 46L48 48Q45 35 34 34Q23 34 22 46L13 45L11 40L4 40L3 37Z'),
1602:((118,50),'M1 37L3 29L9 25L15 18L24 10L35 7L43 8L51 3L60 5L67 1L74 3L87 19L101 22L111 26L114 31L117 34L115 41L109 43Q107 32 95 33Q86 32 85 44L75 46L62 44L49 46Q47 35 34 35Q23 35 22 46L14 44L9 40L1 42Z')}
for cid,(size,outline) in cases.items():
 s=defs()+f'<defs><clipPath id="sil"><path d="{outline}"/></clipPath></defs>'
 s+=P(outline,'url(#body)','#0b1410',1.1)
 if cid==1603:
  s+=P('M38 20L46 10L55 8L64 8L64 20L54 22L47 20Z','#0b1511','#7a8175',.6)
  s+=P('M69 8L87 9L99 21L73 20Z','#0a1411','#7b8277',.6)
  s+=P('M48 11L52 13L48 18L58 17L60 20 M75 12L83 10L89 16L81 15L78 18','#344239',None)
  s+=P('M67 6L70 22L72 40L71 44 M39 23L43 28L45 43 M101 23L106 28L104 40 M48 42Q62 43 68 41 M76 42L99 40',s='#1b2821',w=.8)
  s+=P('M48 25L64 24L66 38L50 39Z','url(#panel)')+P('M74 24L99 25L101 36L96 39L77 39Z','url(#panel)')
  s+=P('M19 23L33 22 M111 24L137 28 M45 6L56 5L65 7L78 5L90 7',s='#919385',w=.75,op=.65)
  s+=P('M56 26h5 M88 27h5',s='#101a15',w=1.4)
  s+=wheel(33,43,11)+wheel(120,43,11)
  s+=P('M3 36L14 36L18 39L11 40L4 39 M135 35L146 33L143 38L136 39','#1a241e','#697063',.5)
 elif cid==1604:
  s+=P('M46 13L51 10L61 10L64 19L65 39L58 43L47 41L41 31L40 24Z','#080e0c','#7c8478',.85)
  s+=P('M69 10L80 10L86 13L98 24L98 40L88 43L72 40Z','#080f0c','#747e70',.85)
  s+=P('M45 25L50 25L54 29L60 28L63 32L61 36L54 35L49 37L46 34Z','#38463a','#202c24',.7)
  s+=P('M75 27L82 27L86 30L93 29L96 33L91 37L78 37L74 35Z','#354237','#1b271e',.65)
  s+=P('M47 17L50 19L49 26L53 29 M74 17L78 20L78 27 M44 34L49 39L58 40 M77 39L91 40',s='#586451',w=.9)
  s+=P('M63 7L67 17L69 39L72 44L66 45L63 35L61 19Z','url(#body)','#222d25',.8)
  s+=P('M47 7L61 5L69 6L78 4L90 7 M106 22L135 24L143 28 M13 25L31 23',s='#969c88',w=.8,op=.7)
  s+=P('M45 43L64 44L70 46L96 44L108 42',s='#7b8472',w=1.1)
  s+=wheel(34,45,6.6,.8)+wheel(121,43,6.8,.8)
  s+=P('M23 27L28 27L29 30L23 31Z M140 30L146 29L146 33L140 34Z','#0b140f')
 else:
  s+=P('M20 23L29 13L40 13L46 16L45 26L32 25L28 29Z','#0a1410','#6d7868',.8)
  s+=P('M59 10L66 8L72 11L82 23L80 35L71 40L59 39L55 29Z','#08120e','#798470',.8)
  s+=P('M47 8L53 13L54 28L60 41L56 43L49 35L48 22L43 12Z','url(#body)','#18271c',.7)
  s+=P('M23 29L34 28L43 30L49 29L51 35L43 39L31 35L27 37L22 34Z','#1b2920','#68775f',.7)
  s+=P('M60 29L64 26L69 29L77 27L79 31L75 36L63 36Z','#364732','#101d13',.5)
  s+=P('M17 24L23 22L25 25L22 28L18 27 M6 30L14 30L16 35L11 36 M88 25L105 28L110 32 M33 8L43 9L50 6L60 8L68 5L76 8',s='#7a856d',w=.8)
  s+=P('M81 28L92 29L102 31 M53 39L64 41L80 40',s='#66775a',w=.8)
  s+=wheel(35,44,8,.8)+wheel(95,43,8.5,.8)
  s+=P('M2 35L7 37L4 40 M104 35L113 36L112 40',s='#89917b',w=.8)
 # Curved stamped metal and torn door sills: broad cold steel turns, narrow edge scars, dark creases.
 s+='<g clip-path="url(#sil)">'
 if cid==1604:
  s+=P('M5 30Q12 23 23 25L34 24L37 27Q24 27 20 30L12 31Z','#788075',None,op=.55)
  s+=P('M105 24Q117 25 134 25L144 29L135 30Q121 26 108 28Z','#7f8479',None,op=.6)
  s+=P('M106 30Q115 28 125 30L131 33Q116 29 110 35L108 39L104 38Z','#26322d',None)
  s+=P('M43 11Q42 17 40 22L43 31L47 38L48 42L43 38L38 26L40 18Z','#859082',None,op=.6)
  s+=P('M67 10Q70 23 70 31L73 38L72 42L68 35Z','#8a9385',None,op=.65)
  s+=P('M48 30Q52 26 57 29L61 31Q56 33 49 33Z','#5d6b5a','#1d2921',.5)
  s+=P('M76 30Q80 27 87 30L93 31Q92 34 87 35L77 34Z','#5a6756','#1b271e',.5)
  s+=P('M48 35L52 37L60 36 M77 36L92 36 M49 39L61 39 M77 40L88 39',s='#7a856f',w=.55,op=.65)
  s+=P('M9 36L17 34L23 35 M99 39L104 36L108 38 M137 33L144 32L142 35',s='#0b1510',w=1)
 elif cid==1603:
  s+=P('M12 25Q23 21 35 23L36 25Q26 25 16 28Z','#7f877a',None,op=.5)
  s+=P('M47 28Q56 24 63 27L64 31Q56 29 49 31Z','#6d786b',None,op=.45)
  s+=P('M75 28Q85 25 97 28L99 31Q87 28 77 31Z','#788172',None,op=.4)
  s+=P('M109 26L122 26L138 29L132 30L116 28Z','#8b8f7e',None,op=.6)
  s+=P('M49 35L57 34L63 36 M76 36L86 37L96 34 M20 31L25 29 M125 31L132 33',s='#1b2821',w=.8)
 else:
  s+=P('M10 28L18 22L20 25L17 29L13 32Z','#88917b',None,op=.65)
  s+=P('M29 30L35 30L39 32L46 30L46 33L40 35L36 33Z','#8a927e',None,op=.6)
  s+=P('M58 17Q60 20 60 26L63 35L61 38L57 32Z','#78866c',None,op=.6)
  s+=P('M85 24Q96 23 106 28L110 30L100 28L89 28Z','#8b937e',None,op=.55)
  s+=P('M64 31Q70 28 76 31L75 33L65 34Z','#66765a','#1b291e',.5)
 s+='</g>'
 if cid in [1602,1604]:
  # Flattened stripped wheel hubs, rather than intact new concentric tyres.
  for x,y,r in ([(35,44,5.8),(95,43,6)] if cid==1602 else [(34,45,5.6),(121,43,5.9)]):
   s+=P(f'M{x-r} {y-1}L{x-r*.45} {y-r*.8}L{x+r*.25} {y-r*.9}L{x+r} {y-r*.2}L{x+r*.7} {y+r*.6}L{x-r*.2} {y+r*.8}L{x-r} {y+r*.3}Z','#757c70','#29352c',.7)
   s+=E(x,y,r*.55,r*.48,'#5c6759')+E(x-.5,y,r*.12,r*.12,'#343f35')
 if cid==1604:
  s+=P('M45 22Q44 18 47 18L51 20L53 27Q51 30 48 28Z','#596653','#18251c',.6)
  s+=P('M73 24Q71 20 73 18Q75 17 77 21L80 27L77 31Z','#58644f','#18251c',.6)
  s+=P('M46 20Q48 20 50 24 M74 20L77 25','none','#89917b',.55,.65)
 # Sparse paint abrasion is clipped to actual panel silhouette, with narrow dark cracks.
 rng=random.Random(cid)
 s+='<g clip-path="url(#sil)">'
 for _ in range(52):
  x=rng.uniform(4,size[0]-4);y=rng.uniform(8,size[1]-11);w=rng.uniform(1,4)
  s+=P(f'M{x:.2f} {y:.2f} l{w:.2f} -.4 l-1 .8Z',rng.choice(['#8b907a','#9a9475','#101c14','#273325']),None,op=.18)
 s+='</g>'
 from alpha_holes import holes
 hole=holes(R/f'reference/background/{cid}.png')
 s=f'<defs><mask id="original_openings"><rect width="{size[0]}" height="{size[1]}" fill="white"/><path d="{hole}" fill="black"/></mask></defs><g mask="url(#original_openings)">'+s+'</g>'
 import re
 def neutral(m):
  h=m.group(0)[1:];r,g,b=[int(h[i:i+2],16) for i in (0,2,4)];v=(r+g+b)/3;return '#%02x%02x%02x'%(int(v*.99),int(v*1.01),int(v*.99))
 s=re.sub(r'#[0-9a-fA-F]{6}',neutral,s)
 p=write_part(R/f'parts/bitmap-{cid}.svg',[0,0,*size],s);render(p,size[0]*5,R/f'previews/car-{cid}.png')
 out=Image.new('RGB',(size[0]*10,size[1]*5+32),'#243029');d=ImageDraw.Draw(out)
 for i,im in enumerate([Image.open(R/f'reference/background/{cid}.png'),Image.open(R/f'previews/car-{cid}.png')]):
  im=im.convert('RGBA').resize((size[0]*5,size[1]*5));out.paste(im,(i*size[0]*5,32),im);d.text((i*size[0]*5+6,8),['Original '+str(cid),'R1 editable vector'][i],fill='white')
 out.save(R/f'previews/car-{cid}-original-new.png')
