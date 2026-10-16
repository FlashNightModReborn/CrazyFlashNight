"""Editable hard-edge CF6 bald-guard art, in original bitmap 581 atlas pixels.
Only transparency/silhouette is traced. Interior planes are explicitly authored.
Source SWF crop paths, registration, bounds and matrices remain unchanged.
"""
from pathlib import Path
from PIL import Image
import json, math, shutil, xml.etree.ElementTree as E
R=Path(__file__).resolve().parents[1]
NS='http://www.w3.org/2000/svg'; E.register_namespace('',NS)
M={x['id']:x for x in json.loads((R/'reference/shape-manifest.json').read_text())}
INK='#101416';BASE='#292e30'; DARK='#191e20'; LIGHT='#41484b'; MID='#343b3e'
def p(d,f,s=None,w=.9):return f'<path d="{d}" fill="{f}"'+(f' stroke="{s}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"' if s else '')+'/>'
def l(d,c=INK,w=.85):return p(d,'none',c,w)
# Atlas crops are isolated source islands; no light/color samples enter the art.
CROPS={582:(214,84,297,155),583:(209,156,282,318),584:(318,18,386,158),585:(28,256,127,325),586:(139,43,225,149),587:(297,168,387,246),588:(148,181,198,296),589:(0,8,140,251),590:(225,0,295,85),594:(303,254,380,319)}
OPEN={582:('y',102,None),583:('y',181,None),584:('y',32,142),585:('y',276,307),586:('y',63,132),587:('x',319,None),588:('y',199,282),589:('y',30,None),590:('y',None,None),594:('x',325,None)}
A=Image.open(R/'reference/581.png').getchannel('A')
def boundary(cid):
 x0,y0,x1,y1=CROPS[cid];segs=[]
 def val(x,y):return A.getpixel((x,y)) if x0<=x<x1 and y0<=y<y1 and 0<=x<A.width and 0<=y<A.height else 0
 for y in range(y0-1,y1):
  for x in range(x0-1,x1):
   pts=[(x+.5,y+.5),(x+1.5,y+.5),(x+1.5,y+1.5),(x+.5,y+1.5)];vv=[val(x,y),val(x+1,y),val(x+1,y+1),val(x,y+1)];hits=[]
   for k in range(4):
    j=(k+1)%4
    if (vv[k]>=64)!=(vv[j]>=64):
     t=(64-vv[k])/(vv[j]-vv[k]);hits.append(tuple(round(pts[k][c]+t*(pts[j][c]-pts[k][c]),5) for c in (0,1)))
   if len(hits)==2:segs.append(hits)
   elif len(hits)==4:segs.extend([hits[:2],hits[2:]])
 adj={}
 for a,b in segs:adj.setdefault(a,[]).append(b);adj.setdefault(b,[]).append(a)
 rings=[]
 while adj:
  start=next(iter(adj));now=start;ring=[start]
  while True:
   nxt=adj[now].pop()
   if not adj[now]:del adj[now]
   adj[nxt].remove(now)
   if not adj[nxt]:del adj[nxt]
   if nxt==start:break
   ring.append(nxt);now=nxt
  if len(ring)>5:rings.append(ring)
 ring=max(rings,key=len)
 # Retain the actual alpha edge at a 0.12 source pixel simplification tolerance.
 def dist(q,a,b):
  dx=b[0]-a[0];dy=b[1]-a[1];t=max(0,min(1,((q[0]-a[0])*dx+(q[1]-a[1])*dy)/(dx*dx+dy*dy or 1)))
  return math.hypot(q[0]-a[0]-t*dx,q[1]-a[1]-t*dy)
 def simp(q):
  if len(q)<3:return q
  er=[dist(v,q[0],q[-1]) for v in q[1:-1]];j=max(range(len(er)),key=er.__getitem__)+1
  return simp(q[:j+1])[:-1]+simp(q[j:]) if er[j-1]>.12 else [q[0],q[-1]]
 split=max(range(len(ring)),key=lambda i:math.dist(ring[0],ring[i]));q=simp(ring[:split+1])[:-1]+simp(ring[split:]+[ring[0]])[:-1]
 fmt=lambda q:f'{q[0]:.3f},{q[1]:.3f}'
 outline='M'+' L'.join(map(fmt,q))+' Z'
 axis,low,high=OPEN[cid];axis=0 if axis=='x' else 1;out=[];last=None
 for a,b in zip(q,q[1:]+q[:1]):
  cuts=[0,1]
  if abs(a[axis]-b[axis])>1e-8:
   cuts+= [(v-a[axis])/(b[axis]-a[axis]) for v in (low,high) if v is not None and 0<(v-a[axis])/(b[axis]-a[axis])<1]
  cuts=sorted(cuts)
  for t,u in zip(cuts,cuts[1:]):
   v=a[axis]+(b[axis]-a[axis])*(t+u)/2
   if (low is not None and v<low) or (high is not None and v>high):last=None;continue
   aa=tuple(a[c]+(b[c]-a[c])*t for c in (0,1));bb=tuple(a[c]+(b[c]-a[c])*u for c in (0,1))
   if last!=aa:out.append('M'+fmt(aa))
   out.append('L'+fmt(bb));last=bb
 return outline,' '.join(out)
ART={}
# 590 HEAD: bald dome, dark sunglasses, prominent nose and severe mouth.
h=p('M228 0H296V87H228Z','#b4825f')
h+=p('M235 29L242 14L251 5L263 2L270 5L264 8L253 11L245 21L242 34L243 47L250 59L255 70L265 78L276 81L268 84L252 78L243 65L235 50Z','#805439')
h+=p('M245 18L253 8L264 5L273 10L279 20L281 31L273 33L263 30L253 32L246 35L243 30Z','#d6a582')
h+=p('M253 12L261 7L270 8L274 13L267 12L260 12L253 16Z','#e2b491')
h+=p('M282 23L288 35L288 44L285 53L285 61L281 67L278 63L281 54L280 44L277 39L280 35Z','#c6946d')
h+=p('M230 35L235 34L240 42L240 53L244 59L238 62L232 57Z','#8b5b40')
h+=p('M233 39L236 41L237 48L235 50L236 55L239 58L236 59L233 54Z','#573c2e')
h+=l('M231 37L234 36L238 43L239 50M234 47L235 53L239 57','#3b2b23',.9)
# Brow and glasses: near lens dominates in the preserved three-quarter view.
h+=p('M244 37L252 35L261 36L270 38L273 41L269 43L260 41L250 42L245 44Z','#8e5f44')
h+=p('M245 41Q250 38 256 39L270 40L272 43L268 48L261 51L253 50L248 47Z','#080e11','#171a19',.85)
h+=p('M249 41L256 40L265 41L261 42L252 43Z','#273238')
h+=p('M277 40L282 40L287 41L286 48L282 51L279 48Z','#080e11','#171a19',.75)
h+=p('M279 41L284 42L283 43L280 43Z','#2b363c')
h+=l('M269 41L273 40L277 42M245 42L238 39','#0c1012',1.1)
# Temple, cheek and jaw planes; angular, not a glossy radial highlight.
h+=p('M245 49L252 53L258 54L262 59L259 65L263 72L268 75L267 79L255 75L248 66Z','#a16f4d')
h+=p('M249 54L255 56L261 57L260 61L254 61L250 58Z','#d1a17a')
h+=p('M266 48L271 45L274 48L273 56L276 59L278 59L277 62L272 63L268 60L268 55Z','#d4a17b')
h+=p('M274 41L276 42L277 51L280 57L278 60L274 59L272 57L274 54Z','#e0ae87')
h+=l('M275 43L275 51L279 58L277 60L273 59','#493125',.8)
h+=p('M270 58L272 57L275 60L272 62L269 61Z M279 59L282 57L282 60L280 62L277 61Z','#3c2c24')
h+=p('M260 67L266 64L273 65L280 65L281 68L278 72L268 72L264 70L259 72Z','#8a5c43')
h+=l('M259 70Q263 66 267 67L273 68L280 67M261 73L266 70L273 71L278 70','#33271f',1)
h+=p('M265 74L273 75L279 73L277 79L272 81L265 79L261 76Z','#cc9c77')
h+=l('M260 75L264 79L271 81L277 79','#76513b',.7)
ART[590]=h
# 589 TORSO: neck, white shirt, red tie, layered lapels and tailored black wool.
t=p('M-2 5H143V253H-2Z',BASE)
t+=p('M57 16L95 18L100 57L91 68L72 58L54 42Z','#a97955')
t+=p('M61 18L70 20L67 35L74 47L87 58L90 63L75 57L57 44Z','#754b34')
t+=p('M82 23L92 25L95 46L99 57L91 63L89 50Z','#bd8e64')
t+=l('M60 23L60 37L64 42','#553b2c',.75)
# Rear side of coat lies underneath the near lapel and sleeve.
t+=p('M7 68L16 58L28 54L37 62L40 87L38 112L45 142L46 172L42 203L29 239L15 242L22 218L27 185L23 153L18 127L9 101Z',DARK)
t+=p('M5 66L13 58L24 53L33 54L38 62L35 70L25 73L15 82L11 94L6 82Z',MID)
t+=p('M30 88L38 91L45 112L53 139L54 170L49 198L43 221L43 242L33 242L39 216L43 188L44 165L41 143L37 119Z','#252b2d')
# Collar and shirt remain readable behind the tie.
t+=p('M56 39L55 47L64 55L89 75L94 111L105 87L112 64L103 58L97 62L72 50Z','#dde2dc',INK,.9)
t+=p('M56 44L63 52L87 69L90 77L80 70L63 58L54 50Z','#a3afac')
t+=p('M101 61L106 64L105 80L100 93L97 93L99 73Z','#a4b1b0')
t+=p('M88 76L92 80L92 101L90 112L86 92Z','#f0eee3')
# Tie knot and hanging blade follow the chest and do not become a bright stripe.
t+=p('M98 64L106 69L100 81L99 86L91 85L88 79Z','#bd2429','#59161b',.7)
t+=p('M98 67L101 69L96 78L95 83L91 82L91 79Z','#e13c36')
t+=p('M93 85L99 85L99 104L105 116L94 133L88 127L91 107Z','#b71f28','#55181d',.7)
t+=p('M94 88L97 88L96 107L100 116L94 126L93 113Z','#df3336')
t+=p('M99 86L99 103L104 116L98 125L99 115L96 108Z','#831722')
# Tailored lapel edges: large wool planes; no metal strips or closed toy rings.
t+=p('M53 43L48 49L58 69L57 84L54 95L88 129L94 136L92 120L79 94L65 72L61 60Z','#3d4548',INK,.95)
t+=p('M53 48L57 58L67 76L78 95L88 117L84 112L71 94L61 82L60 71L53 61L49 51Z','#4a5255')
t+=p('M60 71L60 82L55 94L68 106L84 126L90 133L84 119L67 99L61 91L64 82Z','#30373a')
t+=l('M55 64L56 70L52 80M56 82L51 91L55 95','#171d20',.8)
t+=p('M108 62L116 66L121 77L111 74L129 96L96 128L91 138L96 120L111 91L110 80Z','#424a4d',INK,.9)
t+=p('M113 66L117 69L118 73L111 71L110 77L115 81L112 85L108 81L108 72Z','#586064')
t+=p('M115 82L126 96L105 117L97 124L102 114L116 98L119 95Z','#343c40')
# Cloth drapes from the shoulder and waist. Fold wedges terminate naturally.
t+=p('M129 100L135 89L134 130L129 159L123 186L125 216L132 242L120 246L112 221L110 195L114 166L119 140Z',DARK)
t+=p('M103 132L111 122L119 116L116 138L110 162L107 180L109 198L114 222L120 242L106 244L102 219L99 199L99 174Z','#343b3e')
t+=p('M59 139L67 143L72 165L70 190L63 209L60 235L49 242L54 217L60 192L63 172Z','#353d40')
t+=p('M73 145L80 141L81 160L76 177L75 192L71 195L73 173Z','#22292c')
t+=p('M46 202L53 194L51 204L44 214L39 232L43 216Z',DARK)
t+=p('M113 179L119 173L116 191L118 204L114 201L111 190Z',DARK)
# Front fastening is subtle, not ornamental armor hardware.
t+=l('M93 135L89 160L88 185L87 208L81 228L76 244','#11171a',1.1)
t+=l('M91 208L95 224L100 242M91 213L88 226L94 226','#171d20',.8)
for x,y in [(94,145),(92,191)]:
 t+=f'<ellipse cx="{x}" cy="{y}" rx="2.1" ry="2.5" fill="#191f22" stroke="#101416" stroke-width=".7"/>'
 t+=p(f'M{x-1} {y-1}L{x+1} {y-1.2}L{x+.7} {y+.5}L{x-1} {y+.5}Z','#485053')
t+=l('M19 241Q45 247 75 244M101 244L119 246L132 242','#141a1c',.8)
ART[589]=t
# 584 THIGH: broad black trouser fabric with a lateral shadow and restrained crease.
h=p('M316 17H389V160H316Z',BASE)
h+=p('M323 24L332 24L331 46L334 75L333 106L337 131L340 144L335 145L329 134L326 110L327 76Z',MID)
h+=p('M370 24L383 24L381 68L378 98L380 133L374 145L366 150L362 145L367 128L368 93L370 61Z',DARK)
h+=p('M341 43L348 38L351 63L347 90L347 115L350 135L346 141L341 128L342 100L344 78Z','#363e41')
h+=p('M337 119L341 128L349 136L361 136L356 140L345 140L339 134Z','#20272a')
h+=l('M347 46L348 72L345 97','#252c2e',.6)
ART[584]=h
# 583 LOWER TROUSER: cloth compresses into the cuff, rather than shiny shin armor.
h=p('M208 153H285V320H208Z',BASE)
h+=p('M225 173L236 165L241 169L236 184L234 211L234 247L231 275L234 292L228 297L223 283L224 254L226 220Z',MID)
h+=p('M259 168L269 176L271 213L271 249L273 282L279 304L273 315L260 314L264 295L261 271L262 233L261 196Z',DARK)
h+=p('M239 196L245 190L248 204L244 236L245 262L241 280L237 277L239 251L239 225Z','#353d40')
h+=p('M221 282L231 285L245 291L260 290L268 286L266 294L253 296L236 291L229 292L224 299L217 303L220 295Z','#171e21')
h+=p('M217 303L226 299L240 302L255 302L267 299L274 303L272 308L259 308L242 307L228 307Z','#42494c')
h+=p('M226 309L241 310L254 310L269 308L271 313L257 315L240 314L228 313Z','#242b2e')
h+=l('M226 292L237 295L247 296M234 304L245 305L260 305','#1b2326',.8)
ART[583]=h
# 585 PELVIS: naturally curved trouser seat; no closed hip/socket line.
h=p('M26 252H130V330H26Z',BASE)
h+=p('M34 269L51 266L60 268L54 280L54 299L59 313L68 320L56 322L42 315L36 301Z',MID)
h+=p('M111 267L123 272L123 303L116 315L97 319L86 315L91 310L108 305L113 294Z',DARK)
h+=p('M70 266L78 264L84 270L82 288L83 306L78 312L75 303L76 285Z','#353d40')
h+=p('M85 313L95 306L101 297L102 302L98 312L92 317L85 318Z','#161d20')
h+=l('M86 316Q97 310 100 301','#151c20',.8)
ART[585]=h
# 586 UPPER SLEEVE: open shoulder/elbow insertion, pressure folds at bent arm.
h=p('M137 40H227V153H137Z',BASE)
h+=p('M172 59L188 50L204 50L212 57L212 65L201 64L191 72L180 92L167 112L160 129L153 132L151 124L158 105Z',MID)
h+=p('M211 59L220 69L221 85L203 108L185 130L171 146L156 145L163 134L180 116L197 91L207 73Z',DARK)
h+=p('M166 88L179 67L190 59L195 60L189 70L178 92L170 104L166 102Z','#454d50')
h+=p('M158 116L168 117L177 112L174 118L164 122L159 130L153 132L155 124Z','#20282b')
h+=l('M159 122L166 118L172 118','#171f22',.7)
ART[586]=h
# 588 LOWER SLEEVE: taper, compressed elbow and slight wrist fold.
h=p('M144 177H203V301H144Z',BASE)
h+=p('M159 200L165 191L172 190L170 209L169 237L173 264L170 281L162 282L161 263L158 238Z',MID)
h+=p('M181 190L189 202L191 238L195 287L185 292L181 278L182 253L178 224Z',DARK)
h+=p('M163 208L168 205L168 231L166 246L167 268L164 267L162 244Z','#454d50')
h+=p('M155 276L163 274L172 279L183 279L189 275L190 282L181 285L169 282L160 283L153 282Z','#20272a')
h+=l('M159 279L168 280L176 283','#141c1f',.7)
ART[588]=h
# 582 SHOE: matte leather quarter and vamp, restrained plane on toe, visible sole.
h=p('M211 81H300V159H211Z','#202629')
h+=p('M229 89L239 88L247 94L248 102L241 105L234 101L226 105L220 111L219 104L223 96Z','#394247')
h+=p('M222 110L229 106L237 107L245 117L260 123L275 126L286 135L287 143L280 146L267 143L251 137L242 129L233 126L227 130L219 129Z','#171e21')
h+=p('M240 111L246 115L252 121L269 126L280 130L285 136L282 138L274 136L262 132L250 130L244 124Z','#394247')
h+=p('M254 125L265 127L274 131L277 134L268 132L257 129Z','#495156')
h+=l('M228 111L234 107L241 109M241 118Q248 119 253 126','#10181c',1)
h+=p('M219 131L228 134L237 132L246 138L261 145L278 148L288 143L288 148L278 151L261 148L248 143L237 137L230 139L220 136Z','#101719')
h+=l('M251 140Q268 149 286 144','#5a6263',.55)
ART[582]=h
# 587 forward hand: cuff, back of glove and separated bent finger segments.
h=p('M296 165H392V250H296Z','#22292c')
h+=p('M303 189L313 176L324 173L333 178L319 190L311 201L306 203L301 197Z','#414a4e')
h+=p('M314 202L326 188L338 181L354 182L361 190L358 202L352 205L344 198L339 203L333 208L328 214Z','#30393d')
h+=p('M329 196L337 189L351 187L355 191L352 197L343 194L337 199L333 205Z','#465055')
h+=p('M355 198L368 204L381 215L382 221L375 221L365 216L356 213L351 208Z','#3d474c')
h+=l('M358 203L365 208L377 215','#111a1e',.8)
h+=p('M343 204L352 207L367 220L365 226L360 231L350 228L336 216L333 212Z','#4a5357')
h+=p('M332 211L341 217L357 231L352 237L347 240L335 235L322 225L322 220Z','#3b454a')
h+=p('M322 219L329 225L344 238L344 243L336 239L325 233L316 224Z','#2f383c')
h+=l('M340 202L336 207L349 218L365 227M332 209L327 215L340 227L354 235M323 216L320 221L332 232L344 239','#11191d',1)
h+=l('M312 202L318 194L330 183','#131b1f',1)
ART[587]=h
# 594 second grip: wrist insertion kept open, glove thumb and finger planes.
h=p('M299 250H386V325H299Z','#20282c')
h+=p('M309 275L316 264L327 260L337 265L328 274L320 286L313 288L307 282Z','#3c464b')
h+=p('M324 280L333 267L350 265L359 270L360 279L371 286L375 292L370 297L358 293L354 305L347 314L337 310L325 301L318 289Z','#2d373c')
h+=p('M334 273L344 270L353 271L354 278L347 282L345 292L338 290L330 282Z','#454f54')
h+=p('M354 284L361 285L369 289L371 294L366 293L359 289L355 291Z','#3b4549')
h+=p('M330 293L338 297L345 305L345 312L337 309L327 300Z','#172125')
h+=l('M348 282L346 292L339 299M356 291L352 301L348 307M321 287L325 278L333 268','#141d21',.85)
ART[594]=h

def make():
 overrides={}
 for name in ['core-r2.json','limbs-r2.json']:
  file=R/'source'/name
  if file.exists():
   data=json.loads(file.read_text())
   if 'parts' in data:data=data['parts']
   for cid,item in data.items():
    if isinstance(item,dict) and 'body' in item:ART[int(cid)]=item.get('defs','')+item['body'];item.setdefault('skipAutoOutline',True);overrides[int(cid)]=item
 atlas=[];audit=[]
 for cid,art in ART.items():
  outline,ink=boundary(cid);clip=f'alpha{cid}';body=f'<defs><clipPath id="{clip}"><path d="{outline}" fill-rule="evenodd"/></clipPath></defs><g clip-path="url(#{clip})">'+art+('' if overrides.get(cid,{}).get('skipAutoOutline',False) else l(ink,INK,1.0))+'</g>'
  item={'body':body,'boundary':outline,'openOutline':ink,'scope':overrides.get(cid,{}).get('scope','hand-authored hard-edge planes; original alpha silhouette only; original SWF coordinate mapping')}
  atlas.append(body);audit.append({'id':cid,'outlineOpenAt':OPEN[cid],'atlasCrop':CROPS[cid]})
  spec=M[cid];src=E.parse(R/f'reference/{cid}.svg').getroot();n=0
  for par in src.iter():
   for el in list(par):
    if el.tag.rsplit('}',1)[-1]=='image':
     i=list(par).index(el);rep=E.fromstring(f'<g xmlns="{NS}" transform="{el.get("transform")}">{body}</g>');par.remove(el);par.insert(i,rep);n+=1
  assert n==1,cid
  E.ElementTree(src).write(R/f'parts/{cid}.svg',encoding='unicode')
  item['id']=cid; ART_EXPORT[str(cid)]=item
 shutil.copy2(R/'reference/592.svg',R/'parts/592.svg')
 (R/'source/atlas-art.json').write_text(json.dumps(ART_EXPORT,indent=2))
 (R/'source/joint-openings.json').write_text(json.dumps(audit,indent=2))
 (R/'parts/atlas581.svg').write_text(f'<svg xmlns="{NS}" viewBox="0 0 385 321" width="1155" height="963">'+''.join(atlas)+'</svg>')
 print('Built 10 editable body parts and preserved 592 weapon.')
ART_EXPORT={}
if __name__=='__main__':make()
