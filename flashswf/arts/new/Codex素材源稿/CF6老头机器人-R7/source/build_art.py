"""Manually authored curved SVG reconstruction in original 976 atlas coordinates.
No raster in candidate body. Original alpha is used only as a silhouette clip.
"""
from pathlib import Path
import json,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1]; NS='http://www.w3.org/2000/svg';ET.register_namespace('',NS)
for directory in ['art','parts','qa','previews']:(R/directory).mkdir(parents=True,exist_ok=True)
SM={s['id']:s for s in json.loads((R/'reference/shape-manifest.json').read_text())}
I='#151718'; D='#25282a'; C='#2c2e2f'; L='#3e4142'
def p(d,f,s=None,w=.85):return f'<path d="{d}" fill="{f}"'+(f' stroke="{s}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"' if s else '')+'/>'
def l(d,c=I,w=.85):return p(d,'none',c,w)
def e(x,y,rx,ry,f,s=I,w=.8):return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{f}" stroke="{s}" stroke-width="{w}"/>'
def rect(x,y,w,h,f,rx=0):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{f}" stroke="{I}" stroke-width=".8"/>'
def bolt(x,y,r=2):return e(x,y,r,r,'#666c6c')+l(f'M{x-r*.55} {y}h{r*1.1}',I,.6)
# Continuous metal response: dark environment band, tight reflected strip,
# broad curved return. Skin stays matte, no metallic multi-stop ramp.
def gradient(name,stops,horizontal=False):
 return '<linearGradient id="'+name+'"'+(' x2="0" y2="1"' if horizontal else '')+'>'+''.join(f'<stop offset="{pos}" stop-color="{color}"/>' for pos,color in stops)+'</linearGradient>'
DEFS=gradient('metal',[(0,'#222626'),(.18,'#4a5050'),(.35,'#929997'),(.42,'#d1d6d2'),(.48,'#a6aeaa'),(.61,'#555d5a'),(.78,'#1f2624'),(1,'#6b7570')])
DEFS+=gradient('horizontal',[(0,'#252b29'),(.16,'#67716b'),(.27,'#bcc6bc'),(.32,'#e1e6db'),(.4,'#8c978d'),(.64,'#333e36'),(.84,'#18231c'),(1,'#5a695e')],True)
DEFS+=gradient('darkmetal',[(0,'#111817'),(.25,'#2c3933'),(.43,'#75857a'),(.49,'#b3c0b0'),(.57,'#596f5e'),(.74,'#17281d'),(1,'#364e3d')])
DEFS+=gradient('armour',[(0,'#0d1510'),(.25,'#203126'),(.47,'#4a6050'),(.52,'#9eb29c'),(.57,'#596e59'),(.68,'#15281a'),(1,'#304b33')])
DEFS+='''<radialGradient id="dome" cx=".34" cy=".22" r=".78"><stop stop-color="#d9e2d4"/><stop offset=".12" stop-color="#acb9a9"/><stop offset=".42" stop-color="#687c6b"/><stop offset=".78" stop-color="#263c2b"/><stop offset="1" stop-color="#5c735f"/></radialGradient><radialGradient id="kneecap" cx=".39" cy=".2" r=".85"><stop stop-color="#d2ddc8"/><stop offset=".09" stop-color="#a0b39a"/><stop offset=".3" stop-color="#5a7458"/><stop offset=".7" stop-color="#1d351f"/><stop offset="1" stop-color="#435f3f"/></radialGradient><radialGradient id="skin" cx=".7" cy=".34" r=".8"><stop stop-color="#c5bea1"/><stop offset=".55" stop-color="#a69b7d"/><stop offset="1" stop-color="#716b54"/></radialGradient><linearGradient id="cheek" x1="0" y1="0" x2="1" y2=".7"><stop stop-color="#25392e"/><stop offset=".27" stop-color="#81998a"/><stop offset=".42" stop-color="#d5e1d0"/><stop offset=".52" stop-color="#a1b5a3"/><stop offset=".77" stop-color="#384f40"/><stop offset="1" stop-color="#213527"/></linearGradient>'''
# Metal is neutral steel. Do not tint the whole robot green.
import re
def neutral_gradient(m):
 tag=m.group(0)
 if 'id="skin"' in tag:return tag
 def gray(c):
  h=c.group(1);v=round(sum(int(h[i:i+2],16) for i in (0,2,4))/3);return '#'+f'{v:02x}'*3
 return re.sub(r'#([0-9a-fA-F]{6})',gray,tag)
DEFS=re.sub(r'<(?:linearGradient|radialGradient).*?</(?:linearGradient|radialGradient)>',neutral_gradient,DEFS)
M='url(#metal)';H='url(#horizontal)';DM='url(#darkmetal)';DOM='url(#dome)'
DEFS+='''<radialGradient id="fleshPlane" cx=".65" cy=".35" r=".8"><stop stop-color="#c6c4a5"/><stop offset=".6" stop-color="#a4a184"/><stop offset="1" stop-color="#73745d"/></radialGradient><radialGradient id="fleshLight" cx=".55" cy=".35" r=".9"><stop stop-color="#d1cfb0"/><stop offset=".55" stop-color="#b9b698"/><stop offset="1" stop-color="#95947a"/></radialGradient><radialGradient id="redEye"><stop stop-color="#ff432a"/><stop offset=".45" stop-color="#d41c14"/><stop offset="1" stop-color="#591411"/></radialGradient><radialGradient id="shoulder" cx=".36" cy=".31" r=".76"><stop stop-color="#d1d1ca"/><stop offset=".13" stop-color="#a9aaa5"/><stop offset=".43" stop-color="#757773"/><stop offset=".65" stop-color="#252927"/><stop offset=".83" stop-color="#373d39"/><stop offset="1" stop-color="#71786f"/></radialGradient>'''
a=''
# 977 plain thigh. Cloth planes have curved boundaries and no gradients.
a+=p('M538 252Q558 241 571 258Q581 276 577 299Q575 319 576 338Q584 363 571 384Q557 398 542 386Q526 369 529 348Q535 328 530 310Q519 276 538 252Z',C,I)
a+=p('M540 258Q553 248 562 256Q571 274 568 291Q559 309 542 305Q530 286 540 258Z',L)
a+=p('M534 299Q541 310 548 308Q540 331 546 348Q556 361 548 378Q536 368 537 350Q540 329 534 299Z',D)
a+=p('M565 308Q570 315 566 333Q560 343 566 361Q573 369 567 381Q558 368 557 350Q558 328 565 308Z','#414446')
a+=l('M533 302Q542 313 547 307M566 305Q559 319 559 328M536 348Q541 354 542 360',I,.9)
# 981 R7: reference-aligned torn cloth and exposed piston. Atlas 976 coordinates.
DEFS+=gradient('r7barrel',[(0,'#18191b'),(.18,'#48494c'),(.37,'#a7a8aa'),(.48,'#d5d6d7'),(.58,'#77797d'),(.85,'#343639'),(1,'#141517')])
DEFS+=gradient('r7collar',[(0,'#2a2c30'),(.25,'#91959a'),(.42,'#e3e4e4'),(.55,'#b9bbbd'),(.78,'#62676b'),(1,'#242729')],True)
DEFS+=gradient('r7rod',[(0,'#111416'),(.36,'#3e4549'),(.57,'#a6adb0'),(.68,'#707a7d'),(1,'#151b1e')])
DEFS+='<radialGradient id="r7cloth" gradientUnits="userSpaceOnUse" cx="632" cy="131" r="118"><stop stop-color="#343536"/><stop offset=".64" stop-color="#2d2e2f"/><stop offset="1" stop-color="#202223"/></radialGradient>'
a+=p('M622 64Q648 58 661 78Q673 99 667 129L661 168Q669 201 654 228Q640 251 623 238Q605 222 606 194Q610 168 607 144Q596 91 622 64Z','url(#r7cloth)',I)
# Opening is biased toward the outer/right edge, with long cloth teeth, not a central star.
a+=p('M667 110L665 124L670 126L670 169L666 184L658 185L650 192L647 190L645 195L642 188L638 194L641 177L636 180L639 165L633 170L638 157L630 166L628 165L640 149L632 151L630 150L641 137L643 140L645 132L650 129L652 126L660 120Z','#080a0c')
# Upper cylinder: broad convex body, hidden behind diagonal fabric lip.
a+=p('M649 124Q658 122 665 128L665 141Q657 143 648 138Z','url(#r7barrel)','#1b1b1d',.65)

a+=p('M645 140Q655 145 667 144L667 150Q655 150 643 145Z','url(#r7collar)','#202326',.55)
a+=l('M645 142Q656 145 666 146','#c8cbcd',.7)
# Long piston assembly: nearly vertical, dark full-width body with restrained reflected edge.
a+=p('M646 151L653 153L651 190L647 193L645 189Z','url(#r7rod)','#101619',.55)
a+=p('M641 154L644 155L641 189L638 193L639 180Z','url(#r7rod)','#14191b',.45)
a+=p('M644 151L647 152L644 159L641 158Z','#4b5358')
# Offset spring sits to the left; unequal visible turns vanish into cloth.
for x,y,w in [(640,155,3.8),(639.6,158,4.1),(639.1,161,3.8),(638.4,164,3.6),(637.8,167,3.3),(637.2,170,2.8)]:
 a+=p(f'M{x} {y}l{w} .6l-.3 1.25l-{w} -.7Z','#777d82','#242a2e',.35)
# Lower right sleeve is broad and partially obscured, not a third floating diagonal rod.
a+=p('M654 170Q660 173 667 173L666 180Q660 180 654 177Z','url(#r7collar)','#14191c',.6)
a+=p('M654 180L666 183L665 185L654 182Z','url(#r7collar)','#151a1d',.5)
# Foreground cloth restores original diagonal upper flap and jagged overlaps.
a+=p('M623 112Q645 116 667 109L660 120L650 128L645 133L641 139L637 143L630 151L628 150L633 144L638 137Q630 132 623 112Z','url(#r7cloth)')
a+=p('M633 155L642 147L639 155L632 164L629 168L628 167Z','#303233')
a+=p('M638 175L640 171L638 191L642 187L645 194L648 190L651 190Q647 205 640 208L634 198Z','url(#r7cloth)')
a+=l('M650 79Q661 94 665 108','#1d1f20',1.5)
a+=l('M607 151Q611 172 621 181M615 208Q619 202 626 199','#202223',1.1)
# 979 upper arm with two scarlet straps, buckle locations retained.
a+=p('M700 7Q721 -2 736 13Q751 36 746 64Q745 87 751 117Q754 148 738 175Q723 190 707 173Q689 151 690 118Q694 96 687 72Q675 26 700 7Z',C,I)
a+=p('M700 12Q714 5 727 16Q738 34 734 57Q725 70 713 69Q698 46 700 12Z','#36393b')
a+=p('M692 34Q694 61 706 75L699 103Q693 90 690 69Z',D)
for y in [80,106]:
 a+=p(f'M685 {y}Q710 {y+7} 747 {y-1}L749 {y+9}Q713 {y+18} 686 {y+10}Z','#a82b23',I,.9)
 a+=l(f'M687 {y+2}Q711 {y+9} 747 {y+1}','#db4930',.85)
 for x in range(690,748,6):a+=l(f'M{x} {y+5}l1 6','#331b18',.8)
 a+=rect(711,y+1,3,11,'#a7afab',.5)+rect(726,y+1,3,11,'#bac1bc',.5)+rect(714,y+5,12,3,'#bac1bc',.3)
a+=p('M747 77Q764 63 763 79L756 92L762 99L753 113L751 133L742 134L742 119L749 113L746 100L753 84L746 88Z','#af2e22',I)
a+=l('M754 80l5 -4M750 95l5 -4M751 107l6 -5','#ee5034',1)
a+=p('M701 131Q712 142 719 143Q712 158 716 174Q706 168 701 152Z',D)
a+=l('M697 119Q703 128 712 133M730 129Q724 151 731 166',I,.9)
# 985 forearm: matt fabric and short metallic cuff.
a+=p('M617 263Q637 257 646 274Q653 287 647 314L647 371L641 388Q624 398 608 387L610 349Q607 327 604 306Q599 275 617 263Z',C,I)
a+=p('M618 272Q626 265 635 272Q641 291 633 312Q629 338 632 369L621 376Q614 350 619 323Q612 296 618 272Z','#363a3b')
a+=p('M610 300Q612 331 612 350L609 375L619 378Q615 349 621 329Z',D)
a+=p('M608 374Q627 381 647 373L646 391Q626 400 607 389Z',M,I)
for y in [378,383,388]:a+=l(f'M609 {y}Q625 {y+6} 646 {y-1}',I,.8)
for x in [612,622,632,642]:a+=l(f'M{x} 379v6h5v4M{x+3} 381h5v5',I,.8)
# 984 glove: four horizontal folded fingers under crossing thumb.
a+=p('M594 5Q612 -2 628 8L653 8Q661 9 659 16L649 20L655 23L653 30L648 33L650 39L646 44L643 49Q621 56 606 45L592 40Q587 24 594 5Z',C,I)
a+=p('M595 9Q606 2 614 6L609 32Q609 42 616 47L599 42Q592 29 595 9Z','#424749')
for d in ['M619 15Q636 21 654 17','M617 25Q635 30 652 27','M616 35Q632 41 649 36','M617 44Q629 49 643 45']:a+=l(d,I,1)
a+=p('M603 11Q607 2 614 3Q619 2 622 8L630 19Q633 23 627 25L623 25Q618 22 615 16L610 28Q609 34 605 34Q600 31 602 25Z','#45494a',I,.8)
# 982: own source atlas anchors, adopting only reviewed961 curved-material principle.
DEFS+='<radialGradient id="bootToeR4" cx="54%" cy="24%" r="77%"><stop stop-color="#747575"/><stop offset=".25" stop-color="#444646"/><stop offset=".57" stop-color="#292b2c"/><stop offset=".86" stop-color="#161819"/><stop offset="1" stop-color="#101213"/></radialGradient><radialGradient id="bootAnkleR4" cx="60%" cy="19%" r="76%"><stop stop-color="#d4d5d3"/><stop offset=".12" stop-color="#929492"/><stop offset=".3" stop-color="#555957"/><stop offset=".6" stop-color="#282b2b"/><stop offset=".85" stop-color="#191b1b"/><stop offset="1" stop-color="#111313"/></radialGradient>'
a+=p('M370 325L396 323L414 336Q430 338 439 348L453 358Q468 367 468 381Q461 392 440 393L412 389L393 376L381 374L373 380L362 375L359 356Z','#202323',I)
# Ankle cap has a rolled dark underside and narrow curved reflected lip.
a+=p('M371 325L395 325L406 336Q391 336 379 350L365 345Z','url(#bootAnkleR4)',I,.9)
a+=l('M365 345Q372 350 380 352Q391 338 406 337','#101313',1.3)+l('M368 344Q375 348 379 348Q391 337 402 336','#777c78',.55)
# Continuous arched instep turns around the actual small side U-opening.
a+=p('M403 340Q414 336 424 344Q429 349 436 357Q418 357 408 369L398 379Q389 378 389 367Q382 361 378 373L373 378L361 370L361 356Q371 361 377 356Q386 344 403 340Z','url(#bootAnkleR4)',I,.9)
a+=l('M362 357Q372 363 379 359Q385 356 390 362Q392 365 392 370Q393 375 397 375Q410 357 433 356','#7a7e7a',.65)
a+=l('M364 370L371 374Q377 361 384 363Q389 364 389 370Q391 380 398 381Q413 361 433 359','#0e1112',1.2)
# Leather toe is convex, not a flat green inset or outline-filled plate.
a+=p('M429 359Q447 356 459 369Q466 378 459 384Q441 393 420 383L407 375Q414 362 429 359Z','url(#bootToeR4)',I,.95)
a+=l('M437 360Q444 368 449 385','#131617',.85)+l('M438 361Q445 369 450 384','#555957',.3)
a+=l('M359 369Q372 382 380 377Q386 374 395 380Q424 397 459 386L467 381',I,2)
a+=l('M407 381Q435 395 459 387','#626762',.6)
# 983 segmented shin armour; rounded knee cup and real tapered steel shaft.
a+=p('M714 195Q738 187 751 204Q760 218 748 240L748 271L743 306L741 341L747 371L765 390L751 387L733 398L712 397L683 384L692 371L697 343L699 302L697 274L696 242Q686 220 697 207Z','url(#armour)',I)
a+=p('M697 214L685 216L685 229L700 232Z','#3d4444',I)
a+=e(725,221,27,28,'url(#kneecap)')+e(729,221,20,23,M)+l('M717 202Q737 196 744 211','#8a998b',1)
for x,y in [(716,209),(714,215),(715,222),(717,230),(721,237)]:a+=l(f'M{x} {y}l4 1',I,.7)
a+=p('M699 243Q721 253 746 242L747 272Q722 280 697 269Z','url(#armour)',I)
a+=p('M700 275Q721 283 746 275L743 306Q722 314 699 305Z','url(#armour)',I)
a+=p('M700 311Q721 318 742 310L740 338Q722 345 699 337Z','url(#armour)',I)
a+=p('M699 341Q719 347 740 340L740 367Q721 375 695 366Z','url(#armour)',I)
# Centre plates overlap sides; side lighting remains the same continuous cylinder.
a+=p('M711 247Q725 250 738 246L738 272Q726 277 712 274Z','url(#metal)',I,.85)
a+=p('M713 278Q727 281 738 277L736 307Q725 312 713 309Z','url(#metal)',I,.85)
a+=p('M714 313Q726 316 736 312L734 337Q725 342 714 339Z','url(#metal)',I,.85)
a+=p('M715 344Q726 346 734 342L734 362Q727 367 716 364Z','url(#metal)',I,.85)
for d in ['M714 271Q725 274 735 271','M715 306Q725 309 733 306','M716 336Q725 339 732 336','M718 361Q725 364 731 361']:a+=l(d,'#272d29',.85)
a+=p('M687 217L694 216L695 228L687 228Z','#141d17',I,.65)+p('M689 219L692 219L692 226L689 226Z','#8c978c',I,.4)
a+=p('M696 368Q717 376 743 368L752 380L734 391Q710 394 692 382Z','url(#armour)',I)
# 980 short cloth pelvis, detailed belt on top.
a+=p('M211 327Q242 330 266 326L330 326Q335 351 329 373L318 392L277 393L256 388L232 392Q213 378 211 355Z',C,I)
a+=p('M221 341Q232 352 237 371Q245 382 252 383L256 388L234 389Q220 376 218 359Z',D)
a+=p('M285 344Q281 363 274 373L277 389L293 386Q290 365 302 348Z','#363a3c')
a+=l('M264 346Q267 361 263 373L256 389M303 356Q294 362 292 373M316 373l-12 8',I,1)
a+=p('M207 310Q235 315 263 313L331 309L334 334Q303 340 277 339L210 337Z',DM,I)
a+=rect(231,313,39,24,'#737b7a',2)+rect(237,317,26,16,'#363d3d')+p('M241 320h20v4h-15v5h15v4h-20Z','#abb3b0',I,.6)
a+=e(294,326,19,20,DOM)+e(295,326,14,16,M)+l('M295 312v28',I,1)
a+=p('M222 311Q227 308 231 312L231 337Q226 340 222 336Z',M,I,.7)
a+=l('M222 316h9M223 332h7',I,.7)
a+=p('M315 314L327 313L329 331L316 334Z',DM,I,.7)
a+=p('M318 316L323 316L324 329L319 330Z','#9ca69e',I,.5)
for x in [211,333]:
 a+=p(f'M{x-7} 294Q{x} 288 {x+7} 294L{x+5} 338Q{x+2} 348 {x-5} 344Z',M,I)
 for y in [298,308,331,338]:a+=l(f'M{x-6} {y}q6 3 12 0',I,.9)
 a+=e(x,294,6,2,'#7e342e')
# 988 shoulder mechanism: continuous housing, rear hose, elbow slider.
# Actual rear support plate, narrow return rod, spring core and side brackets,
# beneath front cylinders; do not leave the generic atlas backdrop as parts.
a+=p('M56 98Q89 103 139 97L143 119L132 127Q91 125 56 118Z',H,I,.8)
a+=p('M92 118L100 118L100 219L92 218Z',M,I,.65)
a+=p('M96 143Q116 147 137 142L138 221Q116 227 96 221Z',M,I,.8)
a+=p('M129 113L142 116L142 139L148 146L148 160L136 163L133 151Z',DM,I,.75)
a+=p('M135 145L145 145L145 157L137 159Z',H,I,.6)
a+=p('M77 169Q86 166 95 170L94 215L75 217Z',DM,I,.65)
a+=p('M68 214Q83 209 100 214L100 231L68 232Z',H,I,.7)

a+=p('M44 11Q66 4 93 5L125 1Q148 0 157 18Q170 40 163 70Q157 87 145 94L91 93L69 81L49 79Q33 72 31 55Q27 25 44 11Z',M,I,1.1)
a+=p('M58 15Q82 10 119 11Q137 9 146 24Q152 45 149 65Q143 78 130 80L75 77Q58 73 54 61Q48 38 58 15Z','url(#shoulder)')
a+=l('M66 21Q92 16 120 20','#bfc4bb',.45)
a+=l('M61 19Q44 38 55 62M130 10Q150 16 154 38L155 58M126 18q8 9 10 21M136 17q9 12 10 24',I,1)
a+=e(47,49,16,25,DM)+e(45,49,9,15,'#3e4646')
# Hose is open loop, underlying tube has no fabricated end joint circles.
# Round hose cross-section: four broad nested values, no outlined flat ribbon.
for width,col in [(10,'#1c1e1c'),(8.4,'#383b38'),(6.5,'#5d605d'),(3.8,'#7e837e'),(1.4,'#979b97')]:
 a+=l('M39 46L22 47Q7 47 6 65L5 89Q6 111 26 117L59 119',col,width)
a+=p('M65 77Q86 70 105 73L125 77Q139 85 132 96Q121 104 95 101L67 96Z',H,I)+e(89,87,11,15,DM)
a+=p('M60 102Q93 110 132 101L135 118Q96 127 59 117Z',H,I,.8)+rect(61,110,15,20,M,2)
a+=rect(76,115,7,83,M,2)+rect(108,108,18,38,M,2)
a+=p('M129 132L136 132L136 146L141 146L141 154L132 156L128 150Z',M,I,.65)
a+=rect(130,135,4,14,'#929b92',.6)
a+=p('M99 218L105 219L105 234L99 234Z',M,I,.65)+rect(126,220,5,14,M,.6)
a+=rect(70,131,23,14,DM,2)+rect(70,158,24,16,H,2)
for y in [174,180,186,192,198,204]:a+=rect(72,y,20,4,'#7c8784',1)
a+=p('M97 143Q113 147 130 143L132 216Q114 224 98 217Z',M,I)+p('M99 147L107 148L108 215L100 217Z','#485252')
a+=e(114,143,17,4,'#7c847c',I,.7)
a+=p('M97 141Q114 146 131 141L132 147Q114 152 97 147Z',H,I,.7)
a+=p('M98 214Q114 220 132 214L132 219Q113 225 98 220Z',H,I,.7)
for y in [153,166,202]:a+=rect(101,y,5,4,'#222c2d')
a+=rect(128,117,13,16,DM,2)+e(134,122,6,8,M)+e(134,122,2.5,3.5,I)
a+=rect(61,214,65,22,DM,2)
# 988 lower transverse axle is a stepped drum with overlapping thick rims.
a+=p('M84 222L131 223Q143 228 147 240L146 254L110 265L82 264Z',H,I)
for x in [136,129,122,115]:
 a+=p(f'M{x} 233L{x+6} 233Q{x+14} 243 {x+9} 256L{x+4} 263L{x-3} 263Q{x+6} 251 {x} 233Z',H,I,.75)
 a+=l(f'M{x+5} 235Q{x+12} 247 {x+5} 260','#242a26',.75)
a+=p('M82 219Q106 217 115 238Q121 255 106 267L83 269L75 246Z',M,I,1)
DEFS+='''<radialGradient id="axleFace" cx=".4" cy=".32" r=".76"><stop stop-color="#aaaaaa"/><stop offset=".55" stop-color="#777777"/><stop offset=".85" stop-color="#3c3c3c"/><stop offset="1" stop-color="#171717"/></radialGradient>'''
a+=e(83,243,23,25,M,I,1)+e(82,243,20.5,22.5,'url(#axleFace)','#272727',.8)+e(82,243,10,12,'#292929',I,.85)+e(82,243,7,9,'#777777',I,.65)+e(82,243,3.5,4.5,'#333333',I,.7)
# 987 gun/piston arm: top axle, spaced cylinder rods, lower open muzzle.
a+=p('M516 15L557 17Q565 17 565 26Q563 33 555 33L517 32Z',H,I)
a+=rect(528,29,11,36,M,2)+rect(545,31,10,34,M,2)
a+=e(513,25,23,25,DOM)+e(510,25,10,12,'#4d514d',I,.75)+e(510,25,8,9.5,'#888c87',I,.6)+e(510,25,5.8,7,'#3f453f',I,.7)+e(510,25,3,4,'#6a7068',I,.6)
for width,col in [(6.5,'#151e18'),(5.2,'#39453b'),(3.9,'#657165'),(2.1,'#909b8b')]:
 a+=l('M495 34L481 36Q477 37 477 45L477 93Q479 102 491 105',col,width)
a+=p('M514 60Q537 55 563 62L574 72L586 108L584 120Q536 129 501 118L502 101L510 76Z',M,I)
for y in [69,78,87,97,108]:a+=l(f'M{510-(y-69)*.18:.1f} {y}Q535 {y+7} {572+(y-69)*.28:.1f} {y}',I,1)
a+=rect(510,122,11,77,M,2)+rect(536,123,11,78,M,2)+rect(557,122,11,77,M,2)
a+=rect(522,125,8,70,DM,1)
for y in [138,146,154]:a+=l(f'M523 {y}h7','#a5afac',1.4)
# Second return hose visible behind upper telescope, separately attached.
for width,col in [(4.8,'#1d251f'),(3.5,'#4c594e'),(1.9,'#8a9789')]:a+=l('M511 45L500 46Q489 47 489 61L489 112',col,width)
# Original double-thickness coupling, open service bay and asymmetric circuitry.
a+=p('M507 195Q538 202 571 194L585 201L585 229Q549 243 508 233Z',M,I,1)
a+=e(546,201,39,8,'#737777',I,.8)
a+=p('M508 205Q548 216 585 205L585 229Q549 243 508 233Z',M,I,.8)
a+=p('M508 229Q546 239 585 225L585 232Q548 245 508 236Z','#535858',I,.8)
a+=l('M510 232Q550 242 582 230','#adb0ae',.65)
a+=p('M520 211Q549 216 575 210L575 230Q548 237 520 231Z','#151b19',I,1)
a+=p('M522 213L537 215L537 221L531 221L531 226L524 225Z','#929993',I,.6)
a+=p('M541 215L550 215L550 226L546 227L546 231L541 232Z','#6b756d',I,.6)
a+=p('M554 214L561 214L560 220L554 222Z','#a9afa8',I,.5)
a+=p('M524 227L528 227L528 232L524 231Z','#666f67',I,.5)
for x in [532,535,539]:a+=l(f'M{x} 224v9','#949d94',.65)
for d in ['M563 230L563 222L570 216L574 217','M567 230L568 224L574 219','M550 229L555 225L561 225','M552 217L552 223L557 223','M529 216L529 222L537 222']:a+=l(d,'#89998b',.65)
for x,y in [(565,220),(570,216),(558,226)]:a+=e(x,y,1.1,1.1,'#c0c5ba',I,.35)
a+=rect(510,143,11,20,DM,1)+rect(509,179,11,15,DM,1)
# Layered piston collars and left service-box outline are visible between rods.
for y in [135,145,151]:a+=p(f'M556 {y}q6 3 13 0v3q-7 3 -13 0Z',H,I,.6)
a+=p('M510 167L528 168L531 173L531 196L512 195Z','#56615b',I,.8)
a+=p('M514 174L524 174L524 189L514 189Z','#26302b',I,.65)
a+=l('M512 171L527 172L528 193L513 192','#a0aaa1',.65)
# Cannon below, source ellipse opening stays visibly hollow.
a+=p('M446 124L501 125L506 329Q480 341 445 330Z',M,I,1)
for y in [140,158,182,204,224,255,263,270]:
 a+=p(f'M444 {y}Q473 {y+9} 506 {y}L506 {y+6}Q473 {y+14} 444 {y+6}Z',H,I,.8)
a+=p('M447 278Q464 283 503 277L504 327Q479 336 447 327Z',M,I)
a+=e(474,123,34,10,'#57635f')+e(474,122,27,6,'#111a18')
for x in range(451,498,5):a+=l(f'M{x} 119l1 6','#77817d',.8)
a+=e(474,125,33,8,'none',I,1.4)
a+=rect(426,213,18,9,DM,1)
for x in [429,433,437]:a+=l(f'M{x} 213v9','#acb4b0',.8)
# 986 R3: source-led curved dorsal shell, wrapped return, overlapping cylinders.
# The four fingers have independent curvature/light fields, not repeated stripes.
FIST_DEFS='''<radialGradient id="palmDome" cx=".36" cy=".27" r=".78"><stop stop-color="#cdcdcd"/><stop offset=".18" stop-color="#afafaf"/><stop offset=".44" stop-color="#868686"/><stop offset=".67" stop-color="#585858"/><stop offset=".85" stop-color="#333333"/><stop offset="1" stop-color="#202020"/></radialGradient><linearGradient id="palmReturn" x2="0" y2="1"><stop stop-color="#454545"/><stop offset=".32" stop-color="#757575"/><stop offset=".58" stop-color="#656565"/><stop offset=".82" stop-color="#3e3e3e"/><stop offset="1" stop-color="#1f1f1f"/></linearGradient><radialGradient id="thumbDome" cx=".65" cy=".26" r=".85"><stop stop-color="#b7b7b7"/><stop offset=".42" stop-color="#909090"/><stop offset=".72" stop-color="#595959"/><stop offset="1" stop-color="#343434"/></radialGradient><linearGradient id="indexCylinder" x1=".08" y1="0" x2=".14" y2="1"><stop stop-color="#242424"/><stop offset=".19" stop-color="#666666"/><stop offset=".35" stop-color="#afafaf"/><stop offset=".45" stop-color="#8b8b8b"/><stop offset=".66" stop-color="#575757"/><stop offset=".89" stop-color="#282828"/><stop offset="1" stop-color="#191919"/></linearGradient><linearGradient id="middleCylinder" x1="0" y1="0" x2=".12" y2="1"><stop stop-color="#212121"/><stop offset=".22" stop-color="#767676"/><stop offset=".4" stop-color="#969696"/><stop offset=".62" stop-color="#5b5b5b"/><stop offset=".87" stop-color="#2e2e2e"/><stop offset="1" stop-color="#1c1c1c"/></linearGradient><linearGradient id="ringCylinder" x1="0" y1="0" x2=".08" y2="1"><stop stop-color="#1d1d1d"/><stop offset=".29" stop-color="#6d6d6d"/><stop offset=".48" stop-color="#7c7c7c"/><stop offset=".72" stop-color="#515151"/><stop offset="1" stop-color="#232323"/></linearGradient><linearGradient id="littleCylinder" x1="0" y1="0" x2=".12" y2="1"><stop stop-color="#272727"/><stop offset=".26" stop-color="#707070"/><stop offset=".48" stop-color="#6e6e6e"/><stop offset=".72" stop-color="#464646"/><stop offset="1" stop-color="#212121"/></linearGradient><radialGradient id="knuckleIndex" cx=".5" cy=".32" r=".7"><stop stop-color="#e0e0e0"/><stop offset=".18" stop-color="#bdbdbd"/><stop offset=".44" stop-color="#868686"/><stop offset=".77" stop-color="#454545"/><stop offset="1" stop-color="#1e1e1e"/></radialGradient><radialGradient id="knuckleMiddle" cx=".54" cy=".42" r=".74"><stop stop-color="#bbbbbb"/><stop offset=".23" stop-color="#909090"/><stop offset=".6" stop-color="#555555"/><stop offset="1" stop-color="#202020"/></radialGradient><radialGradient id="knuckleLower" cx=".42" cy=".3" r=".82"><stop stop-color="#868686"/><stop offset=".5" stop-color="#545454"/><stop offset="1" stop-color="#272727"/></radialGradient><radialGradient id="indexGlint" cx=".15" cy=".4" r=".83"><stop stop-color="#eeeeee" stop-opacity=".75"/><stop offset=".4" stop-color="#d4d4d4" stop-opacity=".22"/><stop offset="1" stop-color="#c5c5c5" stop-opacity="0"/></radialGradient>'''
FIST_DEFS+='''<radialGradient id="wristDome" cx=".4" cy=".37" r=".72"><stop stop-color="#cfcfcf"/><stop offset=".17" stop-color="#a8a8a8"/><stop offset=".45" stop-color="#6d6d6d"/><stop offset=".75" stop-color="#3a3a3a"/><stop offset="1" stop-color="#262626"/></radialGradient>'''
FIST_DEFS+='''<radialGradient id="upperPalmBulge" cx=".35" cy=".42" r=".75" gradientTransform="translate(0 .05) scale(1 .92)"><stop stop-color="#d2d2d2"/><stop offset=".17" stop-color="#bdbdbd"/><stop offset=".4" stop-color="#939393"/><stop offset=".64" stop-color="#616161"/><stop offset=".82" stop-color="#363636"/><stop offset="1" stop-color="#1e1e1e"/></radialGradient><radialGradient id="lowerPalmBulge" cx=".31" cy=".34" r=".78"><stop stop-color="#adadad"/><stop offset=".16" stop-color="#9c9c9c"/><stop offset=".4" stop-color="#787878"/><stop offset=".68" stop-color="#4c4c4c"/><stop offset=".88" stop-color="#292929"/><stop offset="1" stop-color="#1c1c1c"/></radialGradient><linearGradient id="rootContact"><stop stop-color="#141414" stop-opacity="0"/><stop offset=".65" stop-color="#141414" stop-opacity=".66"/><stop offset="1" stop-color="#0d0d0d" stop-opacity="1"/></linearGradient>'''
# Neutralise these metal ramps before using them; hues are not a new green finish.
DEFS+=FIST_DEFS
# Back silhouette and three exposed parallel connector rods.
a+=p('M16 308L35 308L39 315L51 315L54 306L111 294L134 299L171 298Q183 304 179 328L177 334L180 346L176 355L178 367L173 380Q155 386 118 383L84 380L55 372L36 368L17 371Q8 345 12 325Z','#232323',I,.9)
for d in ['M35 313L54 313L54 321L36 321Z','M36 336L56 336L57 348L36 348Z','M35 359L54 358L53 367L35 368Z']:a+=p(d,H,I,.65)
a+=p('M17 307L33 307Q42 337 33 372L17 372Q8 352 11 328Z','url(#wristDome)',I,.8)
a+=l('M33 312Q39 339 33 367','#1b1b1b',1)
# Fingers behind the palm/knuckle row, drawn far-to-near for real overlap.
a+=p('M122 367Q143 369 176 366Q178 374 173 381Q151 385 124 381Z','url(#littleCylinder)',I,.85)
a+=p('M124 348Q147 351 178 347Q180 357 175 366Q153 372 124 367Z','url(#ringCylinder)',I,.85)
a+=p('M124 327Q150 331 178 326Q181 337 176 347Q152 353 125 348Z','url(#middleCylinder)',I,.85)
a+=p('M123 299Q145 301 168 299Q179 299 180 311Q181 321 177 328Q154 333 127 328L120 319Z','url(#indexCylinder)',I,.9)
# Root-concentrated, tapering reflection on the index, not four white bars.
a+=p('M131 307Q151 310 176 311Q173 315 163 316Q146 315 132 312Z','url(#indexGlint)')
a+=l('M130 329Q151 333 176 329','#141414',1.1)
a+=l('M129 349Q152 353 175 349','#1c1c1c',.9)
a+=l('M129 368Q151 372 173 368','#1f1f1f',.8)
# Rounded tips turn away: the far seam is curved and continuous, not a cut plate.
a+=l('M173 303Q177 315 173 326M173 331Q175 339 172 346M172 352Q173 359 170 365M170 372Q170 378 168 381','#2e2e2e',.8)
# Curved main handback, tapering to wrist. Broad light climbs over its bulge.
a+=p('M54 306Q79 299 111 298Q118 305 120 320L120 338Q119 359 122 382Q90 382 56 372Q61 352 58 332Q57 316 54 306Z','url(#palmDome)',I,1)
# The upper and lower dorsal shells each have their own broad convex response.
a+=p('M57 309Q82 303 112 301Q118 315 120 338Q88 344 59 338Q59 323 57 309Z','url(#upperPalmBulge)')
# Lower shell rolls back underneath; same silhouette, no extra flat rectangle.
a+=p('M58 339Q85 344 120 339Q118 356 122 382Q87 383 56 372Q61 358 58 339Z','url(#lowerPalmBulge)',I,.6)
a+=p('M57 369Q82 378 119 379L122 382Q86 383 56 372Z','#343434')
a+=l('M59 337Q86 342 120 337','#151515',1.6)
a+=l('M60 340Q88 345 119 340','#878787',.55)
# Left return edge narrows/curves; the centre joint follows convex surface.
a+=p('M53 307L57 309Q63 336 61 355L58 371L53 369Q58 343 53 307Z','#414141',I,.55)
a+=l('M56 310Q61 334 59 358','#aaaaaa',.6)
a+=l('M86 303Q84 320 85 338Q85 358 88 380','#212121',.95)
for d in ['M85 308L90 307L89 315L85 315','M85 324L80 324L80 330L85 330','M85 346L90 346L90 352L86 352','M86 361L81 361L81 367L87 367']:
 a+=p(d,'none',I,.8)
# Deep turning surface/contact immediately behind the spherical roots.
a+=p('M111 303Q115 320 116 338Q114 359 118 380L124 383Q122 360 123 338L121 318Q119 306 116 301Z','url(#rootContact)')
# Knuckles are irregular ovoid root pads, with contact shadow behind each.
a+=p('M115 299Q126 299 131 311Q135 320 132 328Q124 331 119 326Q114 316 115 299Z','url(#knuckleIndex)',I,.85)
a+=p('M120 327Q129 328 132 333Q136 341 132 348Q126 352 121 346Q119 337 120 327Z','url(#knuckleMiddle)',I,.8)
a+=p('M122 349Q129 349 132 355Q135 363 131 369Q124 372 122 366Q121 357 122 349Z','url(#knuckleLower)',I,.8)
a+=p('M123 370Q129 369 132 376Q134 382 129 384L124 383Q122 378 123 370Z','url(#knuckleLower)',I,.75)
a+=l('M132 313Q135 322 132 328M132 335Q135 343 132 348','#1d1d1d',.7)
# R4b 986 measured anchors: root(125,292), flexion(105,294), tip(54,307).
# Two short domed shells turn around the flexion; only a thin rounded return.
a+=p('M101 287Q109 282 118 283Q128 283 133 290Q136 295 132 298Q123 301 114 297Q106 294 101 287Z','url(#thumbDome)',I,.6)
a+=p('M105 291Q112 290 119 295Q123 298 130 298Q120 302 113 298Q108 296 105 291Z','#575757')
# Distal thumb bends inward with a rounded root, not a triangular roof panel.
a+=p('M101 293Q94 288 87 292Q76 298 63 302Q54 304 51 307Q49 310 55 310Q72 309 87 305Q101 303 111 301Q114 299 109 296Q105 294 101 293Z','url(#thumbDome)',I,.65)
a+=l('M54 308Q70 307 86 303Q100 300 108 300','#c0c0c0',.55)
a+=l('M56 311Q73 310 88 306Q102 303 111 302','#262626',.65)
# Short curved flexion seam only; no fan rays or double straight rim.
a+=l('M99 292Q103 296 107 298','#414141',.7)
# Three wrist rods remain separate; underside visible behind the return flange.
a+=p('M36 314L52 314L53 319L37 319Z','#9a9a9a',I,.5)
a+=p('M37 338L56 338L56 345L37 345Z',M,I,.5)
a+=p('M36 360L53 359L52 365L36 366Z','#777777',I,.5)
a+=p('M51 311L55 311Q61 339 55 369L51 367Q56 338 51 311Z','#5c5c5c',I,.7)
# 978 backpack and damaged uniform, anchored to large atlas panel.
a+=p('M184 69L210 55L215 28L241 4L322 2L343 28L371 37L390 81L396 244L377 274L235 278Q195 270 185 236Z','#4e5654',I,1)
a+=p('M185 73L211 92L209 242Q216 262 236 277L207 262L187 239Z','#69726f',I)
a+=p('M211 92L236 79L366 80L390 98L388 244L371 270L236 274L211 243Z','#3c4543',I)
a+=p('M215 32L244 7L320 6L340 33L333 48L223 49Z',DM,I)
a+=p('M224 32L246 14L316 13L331 34L327 47L228 47Z','#202927',I)
# two rear rounded caps and central connector are actual metal.
for x,y in [(232,42),(356,44)]:
 a+=p(f'M{x-19} {y+19}L{x-16} {y-6}Q{x} {y-29} {x+14} {y-5}L{x+20} {y+20}Q{x} {y+28} {x-19} {y+19}Z',M,I)
 a+=p(f'M{x-22} {y+22}Q{x} {y+30} {x+21} {y+21}L{x+24} {y+36}Q{x} {y+43} {x-25} {y+35}Z',M,I)
 a+=l(f'M{x+4} {y-14}Q{x+11} {y} {x+11} {y+18}',I,.8)
a+=p('M271 39Q292 28 317 39L324 75L321 104L277 103L267 74Z',DM,I)+e(293,39,24,9,'#67726e')+e(293,39,19,6,'#565e57')
for x,y,rx,ry in [(283,38,4,1.8),(294,36,4,1.5),(304,39,4,1.8),(294,42,4,1.5)]:a+=e(x,y,rx,ry,'#121b16',I,.4)
for x in range(276,316,7):a+=l(f'M{x} 39l-1 22',I,.8)
for y in [64,71,79]:a+=l(f'M270 {y}Q294 {y+9} 322 {y}',I,1)
# jacket central continuous cloth, open torn chest.
a+=p('M250 94L285 88L313 94L332 87L366 89L388 101L390 142L379 186L377 241L376 275L271 277L258 244L247 205L233 173L235 129Z',C,I)
a+=p('M370 111Q383 131 376 146L361 161L374 162L368 175L352 182L368 191L366 213L347 220L366 224L365 271L331 273L331 223L318 209L316 172L340 145Z','#3c3f3e')
a+=p('M249 117Q252 108 258 114L266 118L269 113L275 123L283 119Q287 103 296 107L302 113L310 109L319 116L326 112Q336 116 335 126L341 129L338 139L346 144L343 151L350 156L343 162L348 170L340 176L339 189L330 187L333 201L324 202L326 211L315 211L309 218L302 211L294 215L287 203L279 202L278 189L268 194L264 181L256 184L254 167L247 171L250 158L242 153L247 143L241 138L245 128Z','#080e0e')
# Exposed mechanism: four partial bearing brackets beneath three diagonal rails.
for x,y in [(266,139),(286,148),(307,160),(330,172)]:
 a+=p(f'M{x-5} {y-7}Q{x+4} {y-8} {x+13} {y-3}L{x+11} {y+7}L{x+6} {y+8}L{x+3} {y+16}L{x-5} {y+18}L{x-9} {y+13}L{x-5} {y+9}Z','#6e7d70',I,.7)
 a+=p(f'M{x-3} {y-4}Q{x+4} {y-4} {x+9} {y+1}L{x+7} {y+6}L{x+2} {y+6}L{x} {y+12}L{x-7} {y+13}L{x-6} {y+8}Q{x+2} {y+7} {x+2} {y+2}Q{x+1} {y-1} {x-3} {y}Z','#b8c3ad')
 a+=e(x-2,y+4,3.5,4.5,'#8b9c86','none',0)
 a+=l(f'M{x+12} {y+1}l-2 18l-2 5','#acbca5',.8)
 a+=p(f'M{x-2} {y+17}l6 1l-2 14l-4 5l-3 -5Z','#172722')
for d in ['M260 121Q292 130 351 154','M260 127Q301 140 352 161','M261 134Q309 150 354 168']:
 a+=l(d,'#111d18',4)+l(d,'#a0af9c',1.6)
# Distinct upper coil, two slanted cap bars and three separate cable runs.
a+=p('M304 106L327 114L321 138L299 130Z','#20322a',I)
for y in [108,114,125,131]:a+=p(f'M304 {y}l20 7l-2 4l-20 -6Z',M,I,.5)
for x,y in [(282,117),(299,127),(334,147)]:
 a+=l(f'M{x} {y}l-2 9l-4 5l3 6l-4 14','#101b20',4)
 a+=l(f'M{x} {y}l-2 9l-4 5l3 6l-4 14','#597b94',1.35)
 for z in [2,6,10]:a+=l(f'M{x-2} {y+z}l4 1','#a0b4ba',.75)
 a+=l(f'M{x+2} {y+3}l-2 9l3 5l-3 14','#708f9b',.65)
# Lower oblique drive box and its stacked flex coupling.
a+=p('M284 181Q299 176 316 183L327 190L326 203L304 207L283 198Z','#354531',I)
a+=p('M285 182Q302 179 316 185L324 190L312 192L286 187Z','#7e8a69')
a+=p('M287 188L312 194L325 192L324 200L310 203L285 196Z','#293824')
a+=l('M302 181l7 3l-1 5M316 185l5 3l-1 3','#a5ae8b',.9)
for y in [205,209,213]:a+=p(f'M298 {y}l17 4l-2 3l-15 -4Z','#69795f',I,.6)
a+=e(300,218,4,4,'#9e9154')+e(300,218,2,2,'#283422')
for d in ['M243 116l13 5l4 -7','M250 178l-3 12','M265 199l-1 10','M337 173l13 9','M323 208l11 10']:
 a+=l(d,'#0c1313',3)
# Cloth stress folds radiate from missing chest into still-connected jacket.
for d in ['M346 137Q360 136 374 125','M347 148Q360 145 374 141','M349 158Q362 156 375 151','M342 168Q353 176 372 178','M339 183Q349 194 367 197','M335 199Q342 215 357 219','M281 221Q278 240 284 257','M312 229Q306 246 309 268','M344 239Q354 245 366 245','M347 251Q357 258 366 255']:
 a+=l(d,I,1.3)
# Red piping and collar/epaulettes, retained narrow trim.
a+=l('M367 101L379 126Q386 143 378 162L371 197L370 229L373 274','#111919',4)
a+=l('M367 101L379 126Q386 143 378 162L371 197L370 229L373 274','#b73120',2.2)
a+=l('M315 213L317 276','#101817',4)+l('M315 213L317 276','#af2d1c',2)
for x,y in [(302,228),(301,263),(386,116)]:a+=e(x,y,3.6,4.2,'#ac9560')+e(x,y,1.8,2.4,'#50482d')
a+=p('M317 60Q331 55 341 65L344 91L330 97L312 88Z','#9b9a78',I)+p('M321 64L325 82L322 88L333 91L336 72L341 90L345 92L330 97L318 90Z','#686e51')
a+=p('M309 88L327 94L330 106L309 100Z','#a92c1c',I)+p('M332 95L351 89L354 101L333 108Z','#a92c1c',I)
a+=rect(335,97,9,6,'#d1b363')
# Neck-side connector loops and compressed black corrugated throat.
a+=l('M315 67Q305 66 306 76Q305 84 314 84','#242d27',3)+l('M315 68Q308 67 308 76Q308 81 314 82','#9ba597',1.2)
a+=l('M343 68Q350 71 348 79L345 83','#252e27',3)+l('M343 68Q348 72 346 79L344 81','#aeb7a8',1)
a+=p('M317 101L330 105L330 118L318 114Z','#0a100d',I,.5)
for y in [103,106,109,112]:a+=l(f'M319 {y}l9 3','#7c8479',.55)
a+=p('M255 94Q274 85 301 91L312 101L273 110L255 106Z','#bfa461',I)+p('M261 95Q280 89 299 94L305 99L273 105L260 102Z','#c32f20',I)
a+=p('M269 96L285 95L282 104L278 104L280 98Z','#e3cb82')
a+=p('M349 91Q366 87 386 96L391 105Q371 113 351 105Z','#bea45e',I)+p('M355 93L382 99L385 104L358 103Z','#c53221',I)
a+=p('M367 95L379 100L377 102L370 99L372 103L369 103Z','#e0c67e',I,.4)
# Low harness strap crosses uniform without changing the underlying torso joint.
for x in [214,385]:
 a+=p(f'M{x-9} 195Q{x-8} 178 {x} 179Q{x+10} 181 {x+10} 199L{x+12} 229L{x-11} 230Z',M,I)
 a+=l(f'M{x-10} 201q10 4 21 0M{x-11} 225q11 3 23 0',I,1)
a+=p('M228 216Q299 230 382 212L381 235Q303 253 227 239Z',H,I,1)
a+=p('M238 224Q270 230 308 229L307 241Q267 242 238 236Z','#4e5956',I)+p('M319 228L368 221L368 233L319 240Z','#4e5956',I)
a+=l('M232 219Q303 234 378 216','#b7c1ba',1)
DEFS+='''<radialGradient id="foreheadSteel" cx=".35" cy=".25" r=".85"><stop stop-color="#b5b8ae"/><stop offset=".3" stop-color="#777e75"/><stop offset=".7" stop-color="#343a34"/><stop offset="1" stop-color="#171f1a"/></radialGradient>'''
# R5 989 rebuilt against original989; no wholesale transfer of human963 geometry.
DEFS+='<radialGradient id="r5skin" cx=".62" cy=".28" r=".82"><stop stop-color="#d1c9a7"/><stop offset=".42" stop-color="#b3ab8d"/><stop offset=".75" stop-color="#817c64"/><stop offset="1" stop-color="#514d3e"/></radialGradient><radialGradient id="r5cheek" cx=".35" cy=".47" r=".8"><stop stop-color="#e2e4db"/><stop offset=".13" stop-color="#b9c0b5"/><stop offset=".34" stop-color="#78877d"/><stop offset=".65" stop-color="#36453d"/><stop offset="1" stop-color="#15251d"/></radialGradient><linearGradient id="r5hair" x1="0" y1="0" x2=".4" y2="1"><stop stop-color="#fafafa"/><stop offset=".45" stop-color="#eeeeee"/><stop offset="1" stop-color="#a8a8a8"/></linearGradient><radialGradient id="r5browMetal" cx=".4" cy=".2" r=".85"><stop stop-color="#a6a79c"/><stop offset=".38" stop-color="#6b7068"/><stop offset=".78" stop-color="#343932"/><stop offset="1" stop-color="#1c241d"/></radialGradient>'
# Overall face and stern squared lower jaw, original local contour remains clip.
a+=p('M405 28Q414 16 427 18Q438 23 445 20Q455 24 456 38L458 50Q457 60 455 67Q459 77 452 89Q449 96 441 98Q431 97 423 90Q406 81 401 64Q398 45 405 28Z','#595647',I,.8)
a+=p('M418 22Q426 18 436 23Q441 26 445 22Q452 24 453 34Q455 45 453 52Q451 58 453 67L451 82Q452 91 445 96Q436 97 431 91L429 82L431 73L432 59L434 49L431 39Q422 34 418 22Z','url(#r5skin)')
# Forehead's single diagonal depression and nose-root compression.
a+=p('M420 26Q428 28 434 33Q439 35 438 41Q432 40 426 35Q421 32 420 26Z','#62634f')
a+=p('M438 25Q443 28 447 23Q449 31 445 37Q443 40 441 45L437 47Q439 38 438 34Z','#b9b292')
a+=l('M445 28Q445 35 440 40M450 34Q450 40 444 44M452 39Q450 44 446 46','#454b37',.8)
# Exposed skull shell continues through temple. Its damaged inner edge is irregular.
a+=p('M407 29Q413 20 419 22Q421 28 427 31Q433 33 436 38Q437 42 434 45L436 49L432 50Q427 45 420 43Q412 41 408 46Q404 54 404 62L400 58Q398 42 407 29Z','url(#r5browMetal)',I,.55)
a+=p('M412 35Q416 37 421 39Q425 41 430 44L434 48Q430 47 427 45Q425 45 423 43Q420 44 417 41Q414 42 411 39Z','#cbc9aa')
a+=p('M414 38Q422 40 429 44L432 47Q423 44 419 43Q416 42 414 38Z','#adae91')
for x,y in [(408,34),(406,38),(410,37)]:a+=e(x,y,.9,1.1,'#101b13','#4f5c49',.3)
# Mechanical eye corners anchored outer(410,47), inner(432,50); roof descends inward.
a+=p('M409 46Q420 46 431 49Q434 50 432 53L429 56Q420 58 411 54Z','#09130e',I,.65)
a+=p('M412 50Q421 50 430 51L428 54Q419 56 413 53Z','#17271e')
a+=e(423.5,52,2.6,2.1,'url(#redEye)','none',0)
a+=l('M410 46Q419 47 431 50','#172017',1.25)+l('M412 55Q420 58 429 56','#46564a',.75)
# Cheek is a compact curved cheekbone shell, stepped into the dark nasal bracket.
a+=p('M406 51Q409 57 415 59Q421 60 428 58Q426 64 424 70L422 76Q416 79 411 74Q405 68 403 59Z','url(#r5cheek)',I,.6)
a+=p('M428 57Q431 56 433 52L435 55L432 61L431 68L426 70L424 67Z','#233c30',I,.65)
a+=p('M430 60L432 59L430 67L427 68Z','#728573')
a+=l('M405 58Q406 68 412 73','#bfc9ba',.5)
# Continuous soft orbital volume, bounded only by the hard upper brow and nose.
DEFS+='<radialGradient id="r5orbital" cx=".38" cy=".12" r=".95"><stop stop-color="#25291c"/><stop offset=".28" stop-color="#414631"/><stop offset=".6" stop-color="#7a7b5e"/><stop offset=".85" stop-color="#a5a082"/><stop offset="1" stop-color="#b7ad8e"/></radialGradient>'
a+=p('M444 50Q451 47 456 49Q457 56 454 63Q454 69 450 73Q447 71 446 66Q445 59 444 50Z','url(#r5orbital)')
# Human eye socket: sloping upper hood, visible eye aperture/iris, curved lower lid.
# Outer corner(456,50), inner corner(444,53), iris(451,52.5), lower rim(451,56).
a+=l('M437 43Q438 46 439 49Q442 49 444 47','#313d27',.8)
a+=p('M437 47Q441 46 445 43Q452 40 457 44L457 47Q450 45 445 49L441 52L437 51Z','#c1bfa0')
a+=l('M442 49Q448 46 456 46','#444b36',.85)
# Deep compressed human socket: outer corner high, nasal corner lower.
# The original does not show a readable round iris or a full bright lower eyelid.

a+=p('M445 51Q450 49 455 49L454 52Q449 54 446 54Z','#11190f')




# Tight bridge, alar turn and separate nostrils; no duplicate nose-base arcs.
a+=p('M437 49Q440 50 442 49Q441 57 444 62Q449 65 447 68Q444 71 439 69Q435 70 433 68Q432 66 436 64Q438 57 437 49Z','url(#r5skin)')
a+=p('M439.5 51Q441 51 441 54Q440.5 60 442.5 64Q444 66 443 68Q440 68.5 439 66.5Q439 64 439.5 61Z','#c6c1a1')
a+=p('M434 65Q436 64 437 67Q437 69 434 69Q431 68 434 65Z','#8f9070')
a+=l('M436 65Q437 68 435 69M441 69Q445 71 448 67','#303c29',.7)
a+=p('M434 68Q435 67.2 436 68L435.5 68.7L434 68.8Z','#323424')
a+=p('M445.5 68Q447 67 448 67.2L447 68.4L445.5 68.7Z','#333627')
# Right malar plane/crease, short tight lips and hard chin undercut.

a+=l('M450 71Q451 74 449 77','#6b6a50',.55)
a+=p('M434 76Q439 74.8 443 75.5Q445 75.8 447 75.7L447 77Q442 76.5 438 77.2L433 78L432 77.5Z','#c3bfa0')
a+=l('M432 79Q437 77.6 442 78Q445 78.2 447 77.5','#283825',.95)
a+=p('M433 80Q438 79.5 443 80L447 79.2Q446 80.6 443 80.8Q438 80.6 433 81.5Z','#d0cbae')
a+=p('M431 83Q437 81 444 83L448 82L448 85Q441 84 436 87L432 89L429 89Z','#68614b')
a+=p('M434 87Q439 84 447 86L447 92Q444 97 437 95L432 91Z','url(#r5skin)')
a+=p('M435 87Q440 85 444 87L443 92Q439 94 434 91Z','#aaa98a')
a+=l('M448 85L449 90L446 94M432 86L430 90L435 95M441 87Q442 89 441 91','#464633',.7)
# Mechanical lower cheek/jaw recess with short original tooth blocks.
a+=p('M404 69Q410 76 419 78L425 75L425 81L431 90L435 95Q424 91 414 84Q407 79 404 69Z','#1a2c23',I,.65)
for x,y in [(413,74),(417,75),(421,74)]:a+=p(f'M{x} {y}q1 -.8 2 -.2l.2 3.1l-2 .3Z','#c0cbb7',I,.3)
a+=l('M409 78Q416 85 424 84M414 84Q421 90 429 89','#607363',.65)
a+=e(402.8,63.5,2.7,5,DM)+e(402.8,63.5,1,2.8,'#273c2c')

DEFS+='''<radialGradient id="r5whisker0" cx="0.25" cy="0.2" r="0.95"><stop stop-color="#f2f2f2"/><stop offset=".4" stop-color="#dedede"/><stop offset=".78" stop-color="#a8a8a8"/><stop offset="1" stop-color="#777777"/></radialGradient>'''
DEFS+='''<radialGradient id="r5whisker1" cx="0.4" cy="0.15" r="0.8"><stop stop-color="#f2f2f2"/><stop offset=".4" stop-color="#dedede"/><stop offset=".78" stop-color="#a8a8a8"/><stop offset="1" stop-color="#777777"/></radialGradient>'''
DEFS+='''<radialGradient id="r5whisker2" cx="0.18" cy="0.4" r="1.1"><stop stop-color="#f2f2f2"/><stop offset=".4" stop-color="#dedede"/><stop offset=".78" stop-color="#a8a8a8"/><stop offset="1" stop-color="#777777"/></radialGradient>'''
DEFS+='''<radialGradient id="r5whisker3" cx="0.3" cy="0.15" r="0.85"><stop stop-color="#f2f2f2"/><stop offset=".4" stop-color="#dedede"/><stop offset=".78" stop-color="#a8a8a8"/><stop offset="1" stop-color="#777777"/></radialGradient>'''
DEFS+='''<radialGradient id="r5whisker4" cx="0.5" cy="0.3" r="0.9"><stop stop-color="#f2f2f2"/><stop offset=".4" stop-color="#dedede"/><stop offset=".78" stop-color="#a8a8a8"/><stop offset="1" stop-color="#777777"/></radialGradient>'''
DEFS+='''<radialGradient id="r5whisker5" cx="0.22" cy="0.25" r="1.05"><stop stop-color="#f2f2f2"/><stop offset=".4" stop-color="#dedede"/><stop offset=".78" stop-color="#a8a8a8"/><stop offset="1" stop-color="#777777"/></radialGradient>'''
# Unequal whisker bundles: sharp tips, dark split roots; not equal stacked crescents.
a+=p('M453 65Q457 66 464 68L468 73L465 95L450 97Q453 88 451 82Q453 75 453 65Z','#4b4b4b')
a+=p('M454 66Q457 67 465 68Q461 70 458 70L461 72Q455 72 453 69Z','url(#r5whisker0)')
a+=p('M454 71Q457 73 462 73L460 75Q464 76 468 77Q461 78 457 77Q455 75 453 74Z','url(#r5whisker1)')
a+=p('M454 77Q457 79 464 80L461 81Q465 83 467 83Q460 84 455 81L453 80Z','url(#r5whisker2)')
a+=p('M452 82Q457 84 461 84L458 86Q462 87 465 89Q459 89 454 87L452 85Z','url(#r5whisker3)')
a+=p('M453 88Q457 90 466 91Q461 92 458 92L460 94Q455 93 452 91Z','url(#r5whisker4)')
a+=p('M452 93Q455 95 461 97Q455 97 451 95L450 94Z','url(#r5whisker5)')
for d in ['M454 69l3 1','M454 75l4 2','M453 81l3 1','M452 87l3 1','M452 92l2 1']:a+=l(d,'#777777',.45)
# Hair: a continuous pale curved mass with restrained irregular grooves.
a+=p('M398 35Q400 11 411 3Q427 -2 443 2Q457 2 468 7L469 22Q456 18 450 21L442 24Q426 14 416 21Q406 29 403 38Z','url(#r5hair)',I,.65)
for d in ['M403 29Q410 13 422 17Q432 17 440 23','M407 16Q414 7 425 12Q432 14 438 20','M417 5Q429 6 439 19','M429 4Q438 5 442 20','M447 5Q440 11 443 21','M458 6Q450 9 445 21','M466 12Q456 12 450 19']:
 a+=l(d,'#777777',.75)
for d in ['M408 15Q418 9 426 14','M444 7Q441 12 443 17','M457 8Q451 11 448 16']:
 a+=l(d,'#ffffff',.55)
ATLAS=a
(R/'art/atlas-976.svg').write_text(f'<svg xmlns="{NS}" width="767" height="409" viewBox="0 0 767 409"><defs>{DEFS}</defs>{a}</svg>')

def atlasclip():
 from PIL import Image
 import math
 alpha=Image.open(R/'reference/bitmaps/976.png').getchannel('A')
 def val(x,y):return alpha.getpixel((x,y)) if 0<=x<alpha.width and 0<=y<alpha.height else 0
 segs=[]
 for y in range(-1,alpha.height):
  for x in range(-1,alpha.width):
   corners=[(x+.5,y+.5),(x+1.5,y+.5),(x+1.5,y+1.5),(x+.5,y+1.5)]
   vv=[val(x,y),val(x+1,y),val(x+1,y+1),val(x,y+1)];cross=[]
   for k in range(4):
    z=(k+1)%4
    if (vv[k]>=64)!=(vv[z]>=64):
     t=(64-vv[k])/(vv[z]-vv[k]);cross.append(tuple(round(corners[k][c]+t*(corners[z][c]-corners[k][c]),5) for c in (0,1)))
   if len(cross)==2:segs.append(cross)
   elif len(cross)==4:segs.extend([cross[:2],cross[2:]])
 adj={}
 for a,b in segs:adj.setdefault(a,[]).append(b);adj.setdefault(b,[]).append(a)
 rings=[]
 while adj:
  start=next(iter(adj));now=start;ring=[start]
  for _ in range(len(segs)+1):
   opts=adj.get(now,[])
   if not opts:break
   nxt=opts.pop();adj[nxt].remove(now)
   if not adj[now]:del adj[now]
   if not adj.get(nxt):adj.pop(nxt,None)
   now=nxt
   if now==start:break
   ring.append(now)
  if len(ring)>3:rings.append(ring)
 def dist(pt,a,b):
  dx=b[0]-a[0];dy=b[1]-a[1]
  if dx==dy==0:return math.dist(pt,a)
  t=max(0,min(1,((pt[0]-a[0])*dx+(pt[1]-a[1])*dy)/(dx*dx+dy*dy)))
  return math.hypot(pt[0]-a[0]-t*dx,pt[1]-a[1]-t*dy)
 def rdp(ps,tol=.42):
  if len(ps)<3:return ps
  errs=[dist(q,ps[0],ps[-1]) for q in ps[1:-1]];k=max(range(len(errs)),key=errs.__getitem__)+1
  if errs[k-1]>tol:return rdp(ps[:k+1],tol)[:-1]+rdp(ps[k:],tol)
  return [ps[0],ps[-1]]
 def paths(smooth=False):
  out=[]
  for pp in rings:
   pts=pp
   if smooth:
    j=max(range(len(pts)),key=lambda i:math.dist(pts[i],pts[0]));pts=rdp(pts[:j+1])[:-1]+rdp(pts[j:]+[pts[0]])[:-1]
   def near(a,b,t=.24):return (a[0]*(1-t)+b[0]*t,a[1]*(1-t)+b[1]*t)
   for i,pt in enumerate(pts):
    pre=near(pt,pts[i-1]);post=near(pt,pts[(i+1)%len(pts)])
    out.append(('M' if i==0 else 'L')+f'{pre[0]:.3f},{pre[1]:.3f}Q{pt[0]:.3f},{pt[1]:.3f} {post[0]:.3f},{post[1]:.3f}')
   out.append('Z')
  return ' '.join(out)
 return paths(),paths(True)

AC,AO=atlasclip()
DEFS+='<clipPath id="hairEdge"><path d="M397 0H468V24L445 23L416 22L402 39L397 39Z M451 64H468V99H451Z"/></clipPath>'
ATLAS+=f'<path d="{AO}" fill="none" stroke="#383838" stroke-width=".6" clip-path="url(#hairEdge)"/>' 
(R/'art/atlas-alpha-path.txt').write_text(AC)
for sid in range(977,990):
 root=ET.parse(R/f'reference/shapes/{sid}.svg').getroot()
 defs=ET.Element(f'{{{NS}}}defs');defs.extend(ET.fromstring(f'<defs xmlns="{NS}">{DEFS}<clipPath id="atlasAlpha"><path d="{AC}" fill-rule="evenodd" clip-rule="evenodd"/></clipPath><g id="vectorAtlas976" clip-path="url(#atlasAlpha)"><rect width="767" height="409" fill="#343b39"/>{ATLAS}</g></defs>'));root.insert(0,defs)
 for parent in list(root.iter()):
  for node in list(parent):
   if node.tag==f'{{{NS}}}image':
    g=ET.Element(f'{{{NS}}}use',{'href':'#vectorAtlas976','transform':node.get('transform','')});ix=list(parent).index(node);parent.remove(node);parent.insert(ix,g)
 ET.ElementTree(root).write(R/f'parts/{sid}.svg',encoding='unicode')
(R/'source/art-manifest.json').write_text(json.dumps({'unit':1011,'revision':'R6 hair-whisker neutral silver only','atlas':976,'parts':list(range(977,990)),'style':'Hand-authored curved material-aware SVG. Source alpha only as silhouette. No raster or interior autotrace.','skinAndClothGradients':'Matte skin gradient only; cloth flat curved planes','candidateBodyRaster':False,'death':'111 frames, body remains complete. Shared explosions retained.','transformation':'Separate confirmed sprite2008 has283 frames; not part of this377-frame combat package.'},indent=2))
print('Built 13 editable vector parts.')
