"""CF6 stage a1 props: editable native SVG reconstruction, revision 2.

Sources actually inspected:
  reference/props-original/previews/a1-prop-{1591,1442}.svg
  reference/props-original/shapes/{1410,1411,1436-1441,1589}.svg
  R1 original-versus-redraw prop and complete first-stage preview renders.

No bitmap is used by the replacement parts. Geometry is authored as paths,
polygons, ellipses, and restrained material gradients. Coordinates remain in
original symbol space. 1591 is ONE single-barrel turret used by TWO instances.
1411 is already native vector: its original path, registration and gradient
are preserved without a stylistic edit. Original comparisons may embed the
original SWF bitmap, clearly labelled ORIGINAL.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
import json, math, sys
from svg_native import write_part, inner, render

ROOT=Path(__file__).resolve().parents[1]
AUDIT=ROOT/'reference'/'props-original'
PARTS=ROOT/'parts'; PREV=ROOT/'previews'; QA=ROOT/'qa'
for p in (PARTS,PREV,QA):p.mkdir(parents=True,exist_ok=True)
INK='#171b1b'

def p(d,fill='none',sw=6,stroke=INK,extra=''):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'
def poly(pts,fill,sw=6,stroke=INK,extra=''):
    return f'<polygon points="{pts}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" {extra}/>'
def rect(x,y,w,h,fill,sw=6,stroke=INK,rx=0,extra=''):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'
def ellipse(x,y,rx,ry,fill,sw=6,stroke=INK,extra=''):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'
def group(name,body,extra=''):
    return f'<g id="{name}" {extra}>{body}</g>'
def grad(name,stops,x1=0,y1=0,x2=0,y2=1):
    s=''.join(f'<stop offset="{o}" stop-color="{c}"/>' for o,c in stops)
    return f'<linearGradient id="{name}" x1="{x1*100}%" y1="{y1*100}%" x2="{x2*100}%" y2="{y2*100}%">{s}</linearGradient>'

def turret():
    defs='<defs>'+''.join([
      grad('steel',[(0,'#323c40'),(.09,'#697477'),(.25,'#929897'),(.43,'#7a8385'),(.70,'#59646a'),(.91,'#3b454c'),(1,'#242d33')],0,0,1,0),
      grad('steelFront',[(0,'#3c474c'),(.13,'#737e82'),(.32,'#9aa09c'),(.54,'#788486'),(.82,'#4b5960'),(1,'#303b41')],0,0,1,0),
      grad('steelEdge',[(0,'#8e9693'),(.20,'#7c8584'),(.52,'#59686c'),(.82,'#35454b'),(1,'#23333b')]),
      grad('olive',[(0,'#756748'),(.13,'#a79769'),(.25,'#d3c18a'),(.36,'#e4d5a4'),(.48,'#baaa77'),(.62,'#88774e'),(.81,'#574b30'),(1,'#302d20')]),
      grad('oliveRing',[(0,'#c8b782'),(.18,'#b9a878'),(.40,'#9a895c'),(.70,'#6c5c39'),(.91,'#494028'),(1,'#332f20')]),
      grad('barrel',[(0,'#7a6b46'),(.13,'#c1b183'),(.29,'#ded0a1'),(.45,'#c0ad78'),(.69,'#8a764b'),(.88,'#51472e'),(1,'#302d20')]),
      grad('darkSteel',[(0,'#424c52'),(.4,'#343e46'),(1,'#222a30')]),
      grad('cyan',[(0,'#66d5cc'),(.52,'#2cbab4'),(1,'#199591')]),
      grad('red',[(0,'#b34b40'),(1,'#752e2a')]),
    ])+'</defs>'
    # Broad form lighting, seam shadow and edge polish are separate editable layers.
    # No noise filter: dirt follows joints, drains and the parts that take contact.
    defs=defs.replace('</defs>','''
      <linearGradient id="shellBroadReflection" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0" stop-color="#f8e8bc" stop-opacity=".48"/><stop offset=".46" stop-color="#e2ce9e" stop-opacity=".25"/><stop offset="1" stop-color="#d2bd89" stop-opacity="0"/></linearGradient>
      <linearGradient id="jointDirt" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0" stop-color="#101a1d" stop-opacity=".78"/><stop offset=".35" stop-color="#222b28" stop-opacity=".34"/><stop offset="1" stop-color="#28312b" stop-opacity="0"/></linearGradient>
      <linearGradient id="footDirt" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0" stop-color="#30382c" stop-opacity="0"/><stop offset=".64" stop-color="#28302a" stop-opacity=".22"/><stop offset="1" stop-color="#172221" stop-opacity=".70"/></linearGradient>
      <linearGradient id="shellSideShade" x1="0%" y1="0%" x2="100%" y2="0%"><stop offset="0" stop-color="#393622" stop-opacity=".08"/><stop offset=".60" stop-color="#29291c" stop-opacity="0"/><stop offset="1" stop-color="#25291d" stop-opacity=".55"/></linearGradient>
      <linearGradient id="brassRub" x1="0%" y1="0%" x2="100%" y2="0%"><stop offset="0" stop-color="#ebd8a5" stop-opacity=".10"/><stop offset=".2" stop-color="#ebd8a5" stop-opacity=".65"/><stop offset=".7" stop-color="#dbc48b" stop-opacity=".26"/><stop offset="1" stop-color="#b19a68" stop-opacity="0"/></linearGradient>
    </defs>''')
    b=[]
    # Lower drum, angled right panel and front ventilation grille.
    b.append(group('base_lower_drum',
      p('M606 529 Q952 433 1308 528 L1304 746 Q1274 803 1095 827 Q857 855 696 806 Q628 788 610 750 Z','url(#steel)',10)+
      p('M614 598 Q907 698 1303 575 L1302 636 Q953 719 620 657 Z','url(#jointDirt)',0,'none')+
      p('M616 711 Q884 798 1303 709 L1302 746 Q1278 797 1095 821 Q857 850 696 800 Q636 784 616 747 Z','url(#footDirt)',0,'none')+
      p('M1184 580 L1242 563 L1243 786 Q1218 796 1184 802 Z','#4b555c',6)+
      p('M1245 565 L1305 537 L1303 746 Q1294 770 1246 785 Z','#5d676b',6)+
      p('M625 743 Q692 804 885 820 Q1048 831 1176 804','none',4,'#7c8580')+
      p('M636 605 Q867 689 1179 616','none',6,'#364048')+
      p('M809 675 L1115 675 L1115 791 L807 791 Z','url(#jointDirt)',0,'none')+
      rect(815,679,296,105,'#111d23',8)+
      rect(826,688,274,85,'#343f45',3)+
      ''.join(p(f'M830 {y} L1094 {y} L1085 {y+13} L838 {y+13} Z','url(#steelEdge)',4)+p(f'M839 {y+3} L1086 {y+3}','none',2,'#9aa39d') for y in [691,716,741])+
      p('M827 688 L1098 688','none',3,'#929b9a')+
      p('M650 732 l21 7 M669 746 l31 7 M1137 760 l26 -5','none',3,'#8e9693')+
      p('M677 766 l19 6 4 9 32 7 -3 7 -36 -9 -8 -10 -16 -4 Z','#535b50',0,'none')+
      p('M712 795 l33 7 6 -4 27 5 -8 7 -57 -10 Z','#2b3736',0,'none')+
      p('M716 794 l22 6 M751 802 l14 2','none',2,'#9ba29a')+
      p('M1168 637 l-5 74 -5 18 1 29 -7 0 4 -42 5 -80 Z','#25342f',0,'none',extra='opacity=".36"')+
      p('M1132 792 l18 -3 9 -7 19 -4 -5 8 -32 9 Z','#273735',0,'none')))
    # External side lugs retain the original left and right placement.
    for x,mirror in [(521,False),(1307,True)]:
      s=('-1 1' if mirror else '1 1')
      lug=p('M0 4 L68 -7 L74 171 L23 193 L0 178 Z','url(#steelEdge)',9)+poly('19,24 52,17 56,143 25,157','#26333b',7)+p('M20 27 L24 145 M27 170 L58 160','none',4,'#8a9497')
      if mirror: b.append(group('base_right_lug',lug, 'transform="translate(1388 389) scale(-1 1)"'))
      else:b.append(group('base_left_lug',lug,'transform="translate(524 389)"'))
    b.append(group('drum_upper_band',
      p('M603 399 Q946 492 1306 400 L1303 563 Q1288 605 1109 639 Q899 680 703 629 Q620 607 603 567 Z','url(#steelFront)',10)+
      p('M611 484 Q959 594 1300 482 L1300 527 Q960 626 615 531 Z','url(#jointDirt)',0,'none')+
      p('M608 425 Q897 563 1302 438 L1301 482 Q969 586 612 478 Z','#303b41',5)+
      p('M613 480 Q947 594 1298 484','none',5,'#899494')+
      p('M616 562 Q649 608 782 633','none',4,'#9aa19e')+
      p('M617 580 Q685 626 784 640 Q1010 695 1250 602 L1251 612 Q1010 699 782 648 Q670 626 617 593 Z','#273633',0,'none',extra='opacity=".45"')+
      p('M659 537 l-6 31 9 24 -7 -1 -8 -26 7 -29 Z M736 556 l-1 49 7 13 -5 5 -7 -18 2 -49 Z','#34413a',0,'none',extra='opacity=".28"')+
      p('M708 609 l24 8 12 -3 18 9 -24 -3 -17 -5 -13 -2 Z','#b5b9ac',0,'none',extra='opacity=".48"')+
      p('M1130 575 l17 -6 8 4 25 -10 -12 9 -17 8 -7 -3 Z','#243638',0,'none')+
      rect(851,521,225,90,'#344046',7)+rect(865,533,198,65,'#151f25',5)+
      p('M864 533 L1063 533','none',3,'#4f5b61')+
      p('M852 523 L852 608 L1076 608','none',3,'#8a9494')))
    # Distinct gear-tooth band, still following the original elliptical arc.
    teeth=[]
    for i in range(27):
      x=620+i*25; t=(x-960)/345; yy=443+62*(1-t*t)
      teeth.append(poly(f'{x},{yy-10} {x+17},{yy-7} {x+17},{yy+27} {x},{yy+24}','url(#steelEdge)',3))
      teeth.append(p(f'M{x+4} {yy-4} L{x+4} {yy+15}','none',2,'#b2b6aa'))
    b.append(group('ring_gear_teeth',''.join(teeth)))
    b.append(group('turret_rotator',
      p('M610 350 Q948 259 1276 340 L1301 382 Q1308 416 1216 441 Q966 507 693 440 Q606 416 606 384 Z','url(#steelEdge)',10)+
      p('M613 351 Q950 281 1275 341 L1284 366 Q1274 403 1139 426 Q908 465 710 412 Q624 394 613 367 Z','url(#jointDirt)',0,'none')+
      p('M615 352 Q639 398 829 421 Q1052 448 1212 398 Q1266 380 1275 347','none',8,'#26333a')+
      p('M633 368 Q747 431 982 426 Q1164 420 1256 380','none',4,'#929b9b')+
      p('M788 389 L789 417 M1102 386 L1114 416','none',5,'#36434a')))
    # Connecting sleeve to the power unit, behind the box.
    b.append(group('power_conduit',
      p('M379 611 L633 628 Q658 636 674 662 L674 706 Q660 738 635 744 L386 733 Z','url(#darkSteel)',10)+
      p('M509 630 L506 737','none',6,'#25323a')+
      ''.join(p(f'M{x} 625 Q{x-18} 679 {x} 729','none',7,'#1c292f') for x in [379,398,416])+
      p('M427 640 L491 644 M521 646 L615 646','none',5,'#536069')+
      p('M637 637 Q659 683 637 733','none',5,'#4c5961')))
    # The upper housing has the original squat, horizontally ribbed outline.
    b.append(group('turret_olive_housing',
      p('M584 211 L587 124 Q595 86 638 58 Q750 76 834 38 L850 17 Q856 4 878 4 L926 4 Q950 7 973 30 L973 35 L1040 35 Q1143 43 1225 78 Q1260 90 1262 119 L1261 310 Q1254 338 1219 350 Q1057 412 827 379 L661 370 Q609 365 590 325 Z','url(#olive)',11)+
      p('M665 68 Q808 89 849 40 Q1037 28 1206 78 L1225 94 Q1022 61 764 87 L686 102 Z','#bcb08b',0,'none')+
      p('M650 112 Q904 71 1228 121 L1240 315 Q1200 363 1014 383 L836 372 658 356 Q625 316 658 241 Z','url(#shellSideShade)',0,'none')+
      p('M658 241 Q904 280 1233 221 L1245 320 Q1067 399 836 372 L658 356 Q625 316 658 241 Z','#4a432b',0,'none')+
      p('M850 35 L852 18 Q882 12 923 12 Q946 15 961 32 Z','#c7bc91',5)+
      p('M649 114 Q806 82 1044 95 Q1158 99 1217 121 L1211 143 Q1085 106 906 114 L681 132 Z','url(#oliveRing)',7)+
      p('M664 133 Q907 102 1213 144 L1211 157 Q1055 128 893 130 L663 153 Z','url(#jointDirt)',0,'none')+
      p('M667 249 Q922 288 1218 226 L1219 252 Q932 319 675 276 Z','url(#oliveRing)',7)+
      p('M672 293 Q938 336 1215 274 L1214 303 Q951 373 690 322 Z','url(#oliveRing)',7)+
      p('M693 340 Q956 389 1209 324 L1210 343 Q1037 398 836 378 L708 363 Z','url(#oliveRing)',7)+
      p('M679 254 Q918 294 1206 237 M686 301 Q934 345 1207 286 M711 347 Q939 393 1201 334','none',3,'#c7b27c',extra='opacity=".58"')+
      p('M682 279 Q934 323 1216 255 M699 325 Q948 378 1210 306','none',6,'#292b1d')+
      p('M641 62 L702 67 Q652 109 644 176 Q633 226 650 286 Q661 328 689 366 L642 365 Q608 339 601 304 L600 149 Q600 95 641 62 Z','url(#oliveRing)',8)+
      p('M643 78 Q619 112 618 161 L618 281 Q626 323 650 345','none',4,'#c5b892')+
      p('M663 147 Q789 126 920 149 L898 185 Q769 176 650 216 Q648 181 663 147 Z','url(#shellBroadReflection)',0,'none')+
      p('M688 150 L832 145 M692 157 L739 155','none',3,'#e5d7ad')+
      p('M780 233 L815 236 M821 238 L834 237 M697 303 L719 306','none',3,'#514b33')+
      p('M1050 65 l39 7 M1104 74 l16 4','none',3,'#d0c09a')+
      p('M656 130 Q828 104 1018 117 L1013 122 Q834 112 686 137 L657 143 Z','url(#brassRub)',0,'none')+
      p('M640 86 l-14 29 -3 35 6 -11 4 -23 14 -23 Z M622 240 l-2 29 8 30 10 8 -8 -31 -2 -34 Z','#d6c28d',0,'none',extra='opacity=".68"')+
      p('M700 267 l18 5 5 -2 27 4 -11 5 -25 -4 -5 -4 -13 -2 Z M752 316 l34 6 5 -3 11 1 -7 7 -39 -5 Z','#c4ad74',0,'none')+
      p('M710 271 l8 2 M757 322 l24 4','none',2,'#292d22')+
      p('M1018 344 l31 -3 11 -6 31 -6 -12 10 -22 3 -10 5 -30 4 Z','#2b2c20',0,'none')+
      p('M1065 340 l19 -5 M1001 359 l16 -3','none',2,'#9a8757')+
      p('M722 191 l28 -3 10 3 41 -2 -5 3 -37 2 -11 -3 -26 3 Z','#b59f6d',0,'none',extra='opacity=".5"')+
      p('M835 210 l14 -2 9 3 22 -2 -7 4 -20 1 -7 -3 -11 2 Z','#625b3e',0,'none',extra='opacity=".55"')))
    # Barrel neck and collars, one cannon only.
    b.append(group('barrel_neck',
      p('M953 146 L1155 146 L1193 176 L1187 260 L949 278 Q898 263 896 223 L898 196 Q909 158 953 146 Z','url(#oliveRing)',9)+
      p('M944 157 Q920 176 920 214 Q921 248 946 263 L961 265 L951 274 Q901 260 900 223 L902 197 Q914 167 944 157 Z','#303023',0,'none')+
      p('M955 164 L1151 165 L1174 185 L1169 245 L942 248 Q928 210 955 164 Z','url(#barrel)',7)+
      p('M951 154 Q925 168 918 195 Q912 220 925 246 L946 269 L954 267 Q938 246 937 224 Q934 192 953 164 Z','#171e19',0,'none')+
      p('M944 162 Q927 182 925 205 Q922 235 941 256','none',3,'#4c4931')+
      p('M902 214 L931 216 M934 248 L1173 248','none',5,'#3c4637')+
      p('M955 166 L1116 166','none',4,'#d2c49a')))
    b.append(group('barrel_main',
      p('M1144 164 L1476 164 Q1542 172 1592 194 L1597 237 Q1594 247 1584 249 Q1447 271 1190 265 L1145 258 Q1111 240 1111 210 Q1111 181 1144 164 Z','url(#barrel)',10)+
      p('M1180 178 L1471 177 L1552 196 L1552 212 L1158 212 Q1155 189 1180 178 Z','url(#shellBroadReflection)',0,'none')+
      p('M1156 241 L1453 243 L1578 230 L1582 247 Q1440 266 1189 260 L1146 251 Z','#554e36',0,'none')+
      p('M1180 166 Q1151 179 1150 211 Q1151 241 1171 258 L1147 257 Q1115 241 1116 210 Q1116 184 1145 167 Z','url(#oliveRing)',6)+
      p('M1159 190 L1455 191 M1159 242 L1456 242','none',5,'#273a34')+
      p('M1471 175 L1587 198 L1590 239 L1462 254 L1450 235 L1454 197 Z','url(#steelEdge)',6)+
      p('M1454 199 L1569 196 L1583 207 L1582 230 L1465 237 L1453 228 Z','#233b3c',5)+
      rect(1473,202,95,25,'url(#cyan)',5,'#1c4342',1)+
      p('M1479 205 L1558 205','none',3,'#8fe2d3')+
      p('M1171 183 L1409 183','none',3,'#d3c69b')+
      p('M1240 230 l17 0 M1336 230 l38 0','none',3,'#7e7351')+
      p('M1191 181 l71 -1 8 2 54 -1 -8 4 -73 0 -9 -2 -43 1 Z','#eee0b1',0,'none',extra='opacity=".65"')+
      p('M1211 243 l27 2 7 -3 49 2 -7 5 -42 -3 -8 3 -26 -2 Z','#3c3b29',0,'none')+
      p('M1460 186 l9 -6 28 5 -4 5 -16 -5 -11 4 Z M1472 244 l31 -3 10 3 -33 5 Z','#a7aaa0',0,'none')+
      p('M1448 198 l-2 36 M1438 239 l-17 1','none',4,'#302f24')))
    for label,y in [('upper',101),('lower',274)]:
      b.append(group('cyan_'+label+'_housing',
        p(f'M1120 {y} L1254 {y} L1258 {y+48} L1244 {y+62} L1121 {y+62} L1113 {y+47} L1113 {y+12} Z','url(#oliveRing)',7)+
        rect(1134,y+12,107,36,'#233a37',5)+rect(1141,y+18,91,23,'url(#cyan)',3,'#32534b')+
        p(f'M1144 {y+20} L1228 {y+20}','none',3,'#9ae5d4')+
        p(f'M1120 {y+8} L1243 {y+8}','none',3,'#c8bb91')))
    # Original side control box, open riser, and single red indicator.
    b.append(group('control_box_body',
      poly('5,593 129,514 415,510 286,595','url(#steelEdge)',9)+
      poly('286,595 415,517 416,766 287,835','url(#darkSteel)',9)+
      p('M289 607 L398 542 L399 756 L296 811 Z','#37434a',4)+
      p('M295 618 L295 799 M309 618 L392 568','none',3,'#5a6870')+
      rect(5,595,281,240,'url(#steelFront)',9)+
      poly('11,824 47,824 47,850 6,850','#273239',6)+
      poly('248,824 286,824 286,845 248,850','#273239',6)+
      p('M19 714 L151 714 L151 632 L234 632 L234 714 L271 714 L271 821 L18 821 Z','#263840',7)+
      p('M24 703 L143 703 L143 627 L238 627 L238 704 L275 704','none',5,'#9aa4a0')+
      p('M27 731 L165 731 L165 650 L219 650 L219 731 L253 731 L253 803 L27 803 Z','#36454b',5)+
      p('M28 802 L250 802','none',3,'#607276')+
      rect(29,634,61,52,'#46575c',7)+rect(43,647,16,15,'#182b32',4)+
      ellipse(190,764,17,24,'url(#red)',5,'#492b2b')+
      p('M184 748 L192 746','none',4,'#d97759')+
      p('M25 609 L264 609','none',4,'#a2a9a5')+
      p('M13 604 L278 604 L278 627 L13 627 Z','url(#jointDirt)',0,'none')+
      p('M15 782 L278 782 L278 827 L15 827 Z','url(#footDirt)',0,'none')+
      p('M15 609 l26 -1 7 4 31 -1 -8 4 -25 0 -7 -3 -25 3 Z M249 608 l19 0 7 6 -10 1 -5 -4 -11 1 Z','#b4b7a5',0,'none',extra='opacity=".7"')+
      p('M24 811 l28 0 6 -7 20 1 -4 7 34 -2 -8 7 -70 1 Z M233 818 l22 -4 8 3 12 -3 -4 9 -30 0 Z','#172e31',0,'none')+
      p('M26 811 l22 1 7 -7 M237 816 l14 -2','none',2,'#84938a')+
      p('M89 728 l29 1 10 -5 13 2 M301 774 l16 -8 3 5 14 -8','none',3,'#60756d',extra='opacity=".65"')))
    b.append(group('control_box_socket',
      p('M366 608 Q313 615 308 670 Q305 708 362 734 L415 731 L415 619 Z','#293b43',6)+
      ''.join(p(f'M{x} 624 Q{x-21} 672 {x} 720','none',6,'#13272f') for x in [345,364,383,402])+
      p('M333 638 Q322 667 332 692','none',3,'#71817f')))
    b.append(group('control_box_open_riser',
      poly('123,537 133,416 358,416 338,541','#17262c',9)+
      poly('133,416 170,415 157,534 123,539','url(#steelEdge)',6)+
      poly('325,416 358,416 341,538 309,539','url(#steelEdge)',6)+
      p('M148 431 L140 520 M337 430 L323 521','none',5,'#879493')+
      poly('155,539 309,540 304,554 169,555','#1e3036',5)+
      rect(191,548,67,24,'url(#steelEdge)',5)+
      p('M142 417 L150 410 M347 416 L350 410','none',8,'#18252b')))
    # The grid maps exactly to the original complete prop symbol's registration.
    return defs+group('prop_1591_native_redraw',''.join(b),'transform="translate(-80 -94.923) scale(0.114484375 0.114529825)"')


def crate():
    defs='<defs>'+''.join([
      grad('woodFront',[(0,'#444b32'),(.09,'#757a56'),(.35,'#858666'),(.77,'#646d49'),(.95,'#4e5838'),(1,'#343e2a')],0,0,1,0),
      grad('woodTop',[(0,'#8c8e6c'),(.31,'#777d59'),(.74,'#555e3f'),(1,'#3f4a31')]),
      grad('woodSide',[(0,'#4b5438'),(.23,'#5d6645'),(.64,'#3e4d32'),(1,'#283c28')],0,0,1,0),
      grad('brace',[(0,'#8e9474'),(.16,'#a4a58a'),(.29,'#7e8764'),(.69,'#68744e'),(.88,'#485939'),(1,'#33452d')]),
      grad('braceSide',[(0,'#7a8562'),(.23,'#677550'),(.64,'#465b37'),(1,'#2a412a')],0,0,1,0),
      grad('plank0',[(0,'#333e2a'),(.065,'#6b7250'),(.20,'#7c8061'),(.78,'#717653'),(.96,'#525c3c'),(1,'#35412a')],0,0,1,0),
      grad('plank1',[(0,'#303d29'),(.065,'#68714c'),(.22,'#757c57'),(.80,'#68724c'),(.96,'#4c5837'),(1,'#2f3e29')],0,0,1,0),
      grad('plank2',[(0,'#35422b'),(.065,'#717653'),(.24,'#818362'),(.80,'#727951'),(.96,'#4c5837'),(1,'#35452a')],0,0,1,0),
      grad('plank3',[(0,'#303d29'),(.065,'#616b47'),(.23,'#6c7550'),(.80,'#5f6945'),(.96,'#3f4f31'),(1,'#2a3c26')],0,0,1,0),
    ])+'</defs>'
    defs=defs.replace('</defs>','''
      <linearGradient id="woodContact" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0" stop-color="#111f16" stop-opacity=".90"/><stop offset=".3" stop-color="#18251a" stop-opacity=".58"/><stop offset="1" stop-color="#293b21" stop-opacity="0"/></linearGradient>
      <linearGradient id="woodEndGrime" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0" stop-color="#202d1b" stop-opacity="0"/><stop offset=".65" stop-color="#243420" stop-opacity=".26"/><stop offset="1" stop-color="#13251a" stop-opacity=".68"/></linearGradient>
      <linearGradient id="woodBleach" x1="0%" y1="0%" x2="100%" y2="0%"><stop offset="0" stop-color="#b3ac83" stop-opacity="0"/><stop offset=".25" stop-color="#b3ac83" stop-opacity=".16"/><stop offset=".67" stop-color="#a8a37a" stop-opacity=".11"/><stop offset="1" stop-color="#b3ac83" stop-opacity="0"/></linearGradient>
    </defs>''')
    b=[]
    # Three original planes: receding left side, slatted top, front face.
    b.append(group('crate_body',
      poly('110,263 426,425 426,1398 111,1171','url(#woodSide)',13)+
      poly('32,82 1207,81 1515,368 424,424 32,231','url(#woodTop)',13)+
      poly('421,420 1494,420 1490,1423 1449,1474 530,1474 421,1400','url(#woodFront)',13)))
    # Top panels retain slat breaks; no new diagonal gameplay/collision members.
    for i,(x1,x2,x3,x4) in enumerate([(49,345,665,359),(345,641,960,665),(641,940,1262,960),(940,1210,1515,1262)]):
      b.append(group('top_plank_'+str(i),poly(f'{x1},92 {x2},92 {x3},376 {x4},376','url(#woodTop)',7)))
    b.append(group('top_recesses',
      p('M82 157 L1298 157 M168 238 L1392 238 M264 320 L1475 320','none',14,'#1d2b1d')+
      p('M100 168 L1301 168 M191 250 L1395 250 M283 331 L1473 331','none',5,'#9c9c74')+
      p('M101 177 L1303 177 M193 260 L1397 260 M285 341 L1476 341','none',9,'#35462d',extra='opacity=".45"')+
      p('M216 116 l91 0 27 5 66 -1 M805 123 l102 0 20 6 108 0 M275 207 l86 1 36 7 121 -2 M728 279 l99 2 40 5 131 -2','none',3,'#bcc09a',extra='opacity=".26"')+
      p('M215 118 l34 3 71 -1 17 4 M926 219 l42 1 12 -4 70 2 M1139 304 l44 0 18 7 123 -1','none',3,'#243e27',extra='opacity=".55"')))
    # Each projecting strap casts a narrow dirt-filled shadow on the lid.
    for xs,xe in [(352,700),(823,1213)]:
      b.append(group('lid_strap_contact_'+str(xs),poly(f'{xs+216},95 {xs+242},117 {xe+167},365 {xe+129},382','#17271b',0,'none',extra='opacity=".72"')))
    # Four front vertical planks, original strong framing proportions.
    for i,(a,c) in enumerate([(497,758),(768,1018),(1028,1257),(1267,1465)]):
      b.append(group('front_plank_'+str(i),
         poly(f'{a},470 {c},470 {c},1421 {a},1421',f'url(#plank{i})',7)+
         p(f'M{a+13} 553 L{a+12} 676 L{a+16} 694 L{a+13} 847 M{a+13} 1008 L{a+11} 1091 L{a+16} 1117 L{a+12} 1207','none',4,'#9ca17a',extra='opacity=".65"')+
         p(f'M{c-9} 552 L{c-11} 719 L{c-8} 760 L{c-11} 872 M{c-9} 987 L{c-10} 1100 L{c-7} 1149 L{c-10} 1221','none',8,'#2b3d26')+
         p(f'M{a+27} 556 L{a+68} 552 L{a+73} 603 L{a+65} 645 L{a+73} 720 L{a+61} 773 L{a+67} 831 L{a+32} 853 L{a+23} 795 L{a+32} 728 L{a+21} 660 Z','url(#woodBleach)',0,'none')+
         p(f'M{c-92} 558 L{c-66} 558 L{c-59} 611 L{c-68} 670 L{c-61} 746 L{c-70} 804 L{c-59} 870 L{c-86} 871 L{c-81} 803 L{c-93} 744 L{c-84} 673 Z','#273f25',0,'none',extra=f'opacity="{.10+i*.015}"')+
         p(f'M{a+57} 997 L{a+108} 998 L{a+102} 1070 L{a+111} 1116 L{a+98} 1160 L{a+106} 1217 L{a+52} 1214 L{a+63} 1141 L{a+49} 1088 Z','url(#woodBleach)',0,'none')+
         p(f'M{c-55} 994 L{c-32} 992 L{c-29} 1049 L{c-36} 1090 L{c-31} 1151 L{c-41} 1221 L{c-61} 1220 L{c-49} 1149 L{c-57} 1095 Z','#263c26',0,'none',extra='opacity=".13"')))
    b.append(group('front_joint_and_end_dirt',
      poly('497,551 1467,551 1466,598 496,598','url(#woodContact)',0,'none')+
      poly('497,985 1467,985 1466,1030 496,1030','url(#woodContact)',0,'none')+
      poly('496,814 1467,814 1467,880 496,880','url(#woodEndGrime)',0,'none')+
      poly('496,1163 1467,1163 1467,1225 496,1225','url(#woodEndGrime)',0,'none')+
      poly('497,1343 1467,1343 1466,1391 496,1391','url(#woodContact)',0,'none')+
      p('M760 557 L760 872 M1019 557 L1019 872 M1259 557 L1259 872 M760 993 L760 1220 M1019 993 L1019 1220 M1259 993 L1259 1220','none',9,'#1e2d1f')))
    b.append(group('front_bottom',
      poly('500,1369 1468,1369 1465,1422 1438,1450 551,1450 507,1427','url(#woodTop)',8)+
      p('M557 1434 L1419 1434','none',5,'#a2a88b')))
    # Side boards use the same perspective as the original; frame sits over them.
    for i,(xa,xb) in enumerate([(118,195),(207,294),(307,407)]):
      y=(xa-110)*.51+275
      b.append(group('side_plank_'+str(i),
        poly(f'{xa},{y} {xb},{y+(xb-xa)*.51} {xb},{1150+(xb-110)*.72} {xa},{1150+(xa-110)*.72}','url(#woodSide)',6)+
        p(f'M{xa+10} {y+38} L{xa+10} {1131+(xa-110)*.72}','none',3,'#7e8866',extra='opacity=".6"')+
        p(f'M{xa+31} {y+55} l-3 161 5 36 -3 105 m1 126 l-4 134 3 51','none',3,'#263f26')+
        p(f'M{xb-7} {y+40} L{xb-6} {1147+(xb-110)*.72}','none',9,'#22371f')))
    b.append(group('side_shadow_under_lid',poly('111,301 427,470 427,525 111,360','url(#woodContact)',0,'none')))
    # Retain original broad top framing rails and two projecting top straps.
    b.append(group('lid_back_rail',
      poly('25,78 1202,78 1254,134 77,137','url(#brace)',12)+
      p('M76 96 L370 96 M397 96 L804 96 M859 96 L1181 96','none',4,'#b9bb96')+
      p('M109 118 l74 1 15 -4 96 2 28 -2 M897 120 l105 1 18 -4 64 2','none',3,'#414c31')+
      p('M218 80 l36 0 6 8 -17 -2 -9 3 -20 -1 Z M1065 80 l39 0 -7 7 -25 -1 Z','#b6ad82',0,'none')))
    b.append(group('lid_left_edge',
      poly('32,149 389,416 419,500 364,483 18,231','url(#braceSide)',11)+
      p('M47 179 L378 437','none',5,'#a5ad8e')))
    for i,(xs,xe) in enumerate([(352,700),(823,1213)]):
      b.append(group('lid_strap_'+str(i),
        poly(f'{xs},12 {xs+136},12 {xe+136},372 {xe},387','url(#brace)',12)+
        poly(f'{xs+27},46 {xs+111},47 {xe+104},359 {xe+27},365','url(#woodTop)',4)+
        p(f'M{xs+31} 53 L{xe+24} 344','none',6,'#afb38b')+
        p(f'M{xs+110} 61 L{xe+105} 341','none',6,'#2f4329')+
        f'<defs><clipPath id="strap_wear_clip_{i}"><polygon points="{xs},12 {xs+136},12 {xe+136},372 {xe},387"/></clipPath></defs><g clip-path="url(#strap_wear_clip_{i})">'+
        p(f'M{xs+58} 80 l64 63 6 15 76 73 12 3 68 68','none',3,'#a1a67b',extra='opacity=".55"')+
        p(f'M{xs+96} 87 l59 62 5 15 43 43 M{xe+56} 309 l30 29 -3 9','none',3,'#344c2c')+
        poly(f'{xs+2},15 {xs+43},15 {xs+49},21 {xs+22},21 {xs+17},26','#bab491',0,'none')+
        poly(f'{xe+17},362 {xe+53},359 {xe+57},368 {xe+28},375 {xe+12},371','#33442a',0,'none')+'</g>'))
    b.append(group('lid_front_lip',
      poly('399,347 1534,347 1572,375 1575,431 415,453 389,414','url(#brace)',12)+
      p('M421 365 L819 365 M844 365 L1151 365 M1171 365 L1529 365','none',4,'#b1b68e')+
      p('M462 390 l181 -2 27 5 93 -1 M1141 391 l120 -2 16 4 184 -2','none',3,'#354a2e')+
      p('M444 352 l54 0 9 6 -26 1 -8 -3 -23 3 Z M1463 349 l44 1 6 7 -22 -1 -9 3 -18 -4 Z','#c0b68c',0,'none')+
      poly('412,414 1577,414 1583,455 421,466','#607150',8)))
    # Front braces have thickness faces but no glossy centre streaks.
    for name,yt,yb in [('upper',454,551),('middle',878,985),('lower',1223,1343)]:
      wear_offset={'upper':0,'middle':71,'lower':-37}[name]
      b.append(group('front_crossbrace_'+name,
        poly(f'418,{yt} 1568,{yt} 1580,{yt+18} 1578,{yb} 420,{yb}','url(#brace)',12)+
        poly(f'419,{yb-22} 1578,{yb-22} 1578,{yb} 420,{yb}','#34492e',0,'none')+
        p(f'M447 {yt+18} L724 {yt+18} M753 {yt+18} L1102 {yt+18} M1121 {yt+18} L1549 {yt+18}','none',4,'#a5af83')+
        p(f'M492 {yt+2} L492 {yb-5} M1491 {yt+2} L1491 {yb-5}','none',8,'#34492f')+
        p(f'M451 {yt+38} L476 {yt+38} M1510 {yt+38} L1544 {yt+38}','none',3,'#6d7d59')+
        p(f'M{519+wear_offset} {yt+43} l129 -2 27 5 82 -3 21 2 153 -1 M{1013-wear_offset} {yt+51} l98 -1 24 -4 140 2 18 -3 153 0','none',3,'#354c2c',extra='opacity=".74"')+
        p(f'M{542+wear_offset} {yt+49} l88 1 21 4 42 -1 M{1181-wear_offset} {yt+42} l71 -2 16 3 83 0','none',2,'#acaf80',extra='opacity=".56"')+
        p(f'M444 {yt+5} l35 0 11 7 -23 -1 -6 4 -22 -3 Z M1458 {yt+4} l34 0 5 7 -17 -2 -12 2 Z','#b3ae7f',0,'none')+
        p(f'M{570+wear_offset} {yb-7} l37 -1 7 -8 22 1 -7 7 41 -1 -9 8 -84 -1 Z M{1344-wear_offset} {yb-8} l37 -3 8 -7 17 0 -8 10 -51 5 Z','#1f3523',0,'none')+
        p(f'M{572+wear_offset} {yb-9} l32 0 7 -7 M{1348-wear_offset} {yb-10} l28 -2','none',2,'#9a9d73')+
        p(f'M448 {yt+49} l4 18 -3 15 6 3 3 -17 -4 -20 Z M1526 {yt+49} l2 24 6 5 2 -16 -5 -14 Z','#344329',0,'none',extra='opacity=".55"')))
    # Left brace ends project to x=0, matching the old crate silhouette.
    for name,ya,yb in [('upper',551,898),('lower',907,1311)]:
      b.append(group('side_crossbrace_'+name,
        poly(f'36,{ya} 431,{yb-40} 429,{yb+40} 348,{yb+33} 7,{ya+105} 4,{ya+29}','url(#braceSide)',12)+
        p(f'M43 {ya+28} L402 {yb-4}','none',5,'#9eab7d')+
        p(f'M33 {ya+66} L369 {yb+21}','none',5,'#253e26')+
        p(f'M89 {ya+71} l68 60 14 4 87 78 27 13 M219 {ya+171} l64 56 16 6 36 31','none',3,'#1f3b24',extra='opacity=".65"')+
        p(f'M18 {ya+28} l16 -7 8 10 -14 7 -6 27 -8 -2 Z M359 {yb+24} l26 2 18 12 -26 -3 Z','#8f9670',0,'none')))
    # Restrained grain is editable, sparse and clipped to the named wood panels.
    grain=[]
    for x,y,h in [(563,596,205),(628,651,151),(817,602,211),(915,677,156),(1102,594,226),(1339,620,193),(583,1039,143),(856,1046,151),(1134,1033,145),(1357,1040,162)]:
      grain.append(p(f'M{x} {y} q-7 {h*.25} 1 {h*.5} t-2 {h*.5}','none',3,'#384d2e',extra='opacity=".72"'))
      grain.append(p(f'M{x+10} {y+17} q-5 {h*.25} 0 {h*.5}','none',2,'#a4aa7c',extra='opacity=".61"'))
      grain.append(p(f'M{x-16} {y+30} l-3 {h*.23} 4 {h*.16} -2 {h*.19}','none',2,'#3c532e',extra='opacity=".47"'))
    grain+= [p('M690 704 Q666 731 682 767 Q698 791 703 756 Q705 724 690 704 Z','none',3,'#465937'),p('M691 724 Q682 742 691 758 Q698 745 691 724 Z','#4c5e3b',2,'#3a4f31'),p('M686 694 Q660 731 671 761 L675 809 M700 701 Q719 739 707 783 L703 837','none',2,'#939d70',extra='opacity=".56"'),p('M1187 1080 Q1170 1101 1180 1129 Q1194 1147 1198 1119 Q1197 1097 1187 1080 Z','none',3,'#3b542f'),p('M1188 1098 Q1181 1111 1188 1122','none',4,'#354c2c'),p('M602 557 l-1 36 -8 25 2 40 -4 17 M596 615 l-5 16 0 24 M970 993 l-3 32 5 19 -3 44 M1431 1183 l-5 -24 2 -36 -6 -19','none',3,'#243b25')]
    b.append(group('wood_grain',''.join(grain)))
    # Small recessed fasteners use original framing, no extra metallic reinforcement.
    nails=[]
    for x in [453,1530]:
      for y in [504,932,1275]:
        nails.append(ellipse(x,y,7,5,'#34462f',2,'#33442d'))
        nails.append(p(f'M{x-3} {y-1} L{x+3} {y-1}','none',2,'#a5b08f'))
    b.append(group('frame_fasteners',''.join(nails)))
    return defs+group('prop_1442_native_redraw',''.join(b),'transform="translate(-34 -61.5) scale(0.0425 0.04251012146)"')


def lamp():
    defs='<defs><radialGradient id="lampShadow"><stop offset="0" stop-color="#15272a" stop-opacity=".4"/><stop offset=".55" stop-color="#15272a" stop-opacity=".17"/><stop offset="1" stop-color="#15272a" stop-opacity="0"/></radialGradient>'+grad('lampHolder',[(0,'#6b7678'),(.24,'#4d5a60'),(.65,'#293b44'),(1,'#1c2c34')],0,0,1,0)+grad('lampTube',[(0,'#a7b18b'),(.22,'#d1d6af'),(.5,'#e7e9bf'),(.73,'#d0d9ae'),(1,'#7e9374')])+'</defs>'
    b=[]
    b.append(group('holder_original_shadow_footprint',ellipse(-58.7,5,11,7.4,'url(#lampShadow)',0,'none')+ellipse(58.7,5,11,7.4,'url(#lampShadow)',0,'none')))
    b.append(group('tube_recess',rect(-52,-9,104,13,'#263b3e',1.2,INK,1)))
    b.append(group('fluorescent_tube',rect(-53,-7.3,106,10.2,'url(#lampTube)',.8,'#364c43',.7)+p('M-51 -5.5 H51 M-51 0.4 H51','none',.6,'#f0eed0')+p('M-8 -5.2 V0.5 M5 -5.2 V0.5','none',.55,'#a3ac86')))
    for side in [-1,1]:
      body=p('M52 -10 L57 -11 L60 -12.1 L63 -11 L64 -8.4 L65.5 -7 L65.5 3.4 L63.2 4.6 L53.1 4.7 L51 3.7 Z','#192a32',.8)+rect(51,-10.8,13,15.4,'url(#lampHolder)',.95,INK,1)+rect(54,-11.7,3.1,16.9,'#5a696c',.6,INK,.4)+rect(60,-10.7,3.1,14.9,'#4b5e62',.65,INK,.4)+p('M54.7 -9.6 V2.8 M60.7 -9 V2.9','none',.4,'#a0aaa1')
      b.append(group('holder_'+('right' if side==1 else 'left'),body, f'transform="scale({side} 1)"'))
    return defs+''.join(b)


def comparison(sid,viewbox,original,new,kind):
    """Two placements, exact shared native scale; never resize independently."""
    x,y,w,h=viewbox; gap=max(10,w*.12); header=max(8,w*.065); margin=gap
    width=w*2+gap*3; height=h+2*margin+header
    textsize=max(2,w*.032)
    content=rect(0,0,width,height,'#e8e9e4',0,'none')
    content+=f'<text x="{margin}" y="{margin+textsize}" font-family="sans-serif" font-size="{textsize}" fill="#263239">ORIGINAL {sid}</text>'
    content+=f'<text x="{2*margin+w}" y="{margin+textsize}" font-family="sans-serif" font-size="{textsize}" fill="#263239">{kind} {sid}</text>'
    for label,path,tx in [('original',original,margin-x),('redraw',new,2*margin+w-x)]:
      content+=group(label,inner(path,'compare_'+label), f'transform="translate({tx} {margin+header-y})"')
    out=write_part(PREV/f'prop-{sid}-original-vs-redraw.svg',[0,0,width,height],content)
    render(out,2000)


def revision_comparison(sid,viewbox):
    """Rebuild ORIGINAL/R1/R2 at one scale from bundled fixed references.

    R1 snapshots are intentionally fixed source references, not discovered in a
    neighboring project. Their bytes are part of the self-contained package.
    """
    x,y,w,h=viewbox; margin=w*.08; header=w*.07
    width=3*w+4*margin; height=h+header+2*margin
    body=rect(0,0,width,height,'#e8e9e4',0,'none')
    for i,(label,path) in enumerate([
      ('ORIGINAL',AUDIT/f'previews/a1-prop-{sid}.svg'),
      ('R1',ROOT/f'reference/props-r1/prop-{sid}.svg'),
      ('R2',PARTS/f'prop-{sid}.svg')]):
        tx=margin+i*(w+margin)
        body+=f'<text x="{tx}" y="{margin+w*.025}" fill="#263239" font-family="DejaVu Sans" font-size="{w*.028}">{label} / {sid}</text>'
        body+=group('revision_'+label,inner(path,f'panel_{i}'),f'transform="translate({tx-x} {margin+header-y})"')
    out=write_part(PREV/f'prop-{sid}-original-r1-r2.svg',[0,0,width,height],body)
    render(out,3000)



def crate_fragments():
    """Replace bitmap1435 with the complete native material under original masks.

    The intact shape1436 maps bitmap1435 through [-1,0,0,1,34,-61.5].
    Its exact inverse [-1,0,0,1,34,61.5] takes the new artwork into bitmap
    coordinates. Every original fragment's bitmap matrix then positions it;
    original clipping paths, registration and topology are untouched.
    """
    ns='http://www.w3.org/2000/svg'
    ET.register_namespace('',ns)
    material=inner(PARTS/'prop-1442.svg','fragment_material')
    output=[]
    for sid in range(1436,1442):
        original=AUDIT/f'shapes/{sid}.svg'
        root=ET.parse(original).getroot()
        vb=list(map(float,root.attrib['viewBox'].split()))
        mappings=[]
        for parent in list(root.iter()):
            for index,child in enumerate(list(parent)):
                if child.tag.split('}')[-1]!='image':continue
                transform=child.attrib.get('transform','matrix(1 0 0 1 0 0)')
                node=ET.Element('{'+ns+'}g',{'transform':transform})
                ET.SubElement(node,'{'+ns+'}use',{'href':'#crate_native_material','transform':'matrix(-1 0 0 1 34 61.5)'})
                parent.remove(child);parent.insert(index,node)
                mappings.append({'originalBitmapToFragmentMatrix':transform,'nativeArtworkToBitmapMatrix':[-1,0,0,1,34,61.5],'clipReference':parent.attrib.get('clip-path')})
        masks=[e.attrib['d'] for e in root.iter() if e.tag.split('}')[-1]=='path']
        body='<title>CF6 crate shape '+str(sid)+'</title><desc>New native vector material through original SWF clipping paths and matrices. No new fragments or poses.</desc><defs><g id="crate_native_material">'+material+'</g></defs>'+''.join(ET.tostring(e,encoding='unicode') for e in root)
        out=write_part(PARTS/f'shape-{sid}.svg',vb,body)
        parsed=ET.parse(out).getroot();assert not any(e.tag.split('}')[-1]=='image' for e in parsed.iter())
        render(out,1600,PREV/f'shape-{sid}-redraw.png')
        comparison(sid,vb,original,out,'SAME MASK / NATIVE MATERIAL')
        output.append({'shapeId':sid,'part':str(out.relative_to(ROOT)),'viewBox':vb,'fragmentCount':len(mappings),'bitmapIdReplaced':1435,'sourceClippingPaths':masks,'mappings':mappings,'newFragmentsCreated':0,'imageNodes':0})
    (QA/'crate-fragment-mapping.json').write_text(json.dumps(output,ensure_ascii=False,indent=2))
    return output


def main():
    data=[(1591,[-80,-94.923,183.175,97.923],turret(),'redrawn-native-vector'),
          (1442,[-34,-61.5,68,63],crate(),'redrawn-native-vector'),
          (1410,[-69,-12.5,138,25],lamp(),'redrawn-native-vector'),
          (1411,[-99.9,-84.75,199.8,169.5],inner(AUDIT/'shapes/1411.svg','lamp_original_glow'),'preserved-original-native-vector')]
    manifest=[]
    for sid,vb,body,status in data:
        info=f'<title>CF6 a1 prop {sid}</title><desc>{status}. Original symbol coordinate registration retained. Editable paths; no raster images.</desc>'
        out=write_part(PARTS/f'prop-{sid}.svg',vb,info+body)
        render(out,1600,PREV/f'prop-{sid}-redraw.png')
        orig=AUDIT/(f'previews/a1-prop-{sid}.svg' if sid in (1591,1442) else f'shapes/{sid}.svg')
        comparison(sid,vb,orig,out,'NATIVE REDRAW' if sid!=1411 else 'PRESERVED VECTOR')
        if sid in (1591,1442):revision_comparison(sid,vb)
        root=ET.parse(out).getroot(); tags=[e.tag.split('}')[-1] for e in root.iter()]
        assert 'image' not in tags and 'filter' not in tags
        manifest.append({'id':sid,'viewBox':vb,'status':status,'part':str(out.relative_to(ROOT)),'imageNodes':tags.count('image'),'editableShapeCount':sum(tags.count(t) for t in ['path','polygon','rect','ellipse']),'registration':'original-native-symbol-space','notes':'One single-barrel turret; reuse the same symbol for both existing first-stage instances.' if sid==1591 else ('1411 glow path and gradient are unchanged from the original SWF vector.' if sid==1411 else '')})
    (QA/'props-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
    # 1591 places shape1589 at T(20.55,-49.45). Undo it for leaf replacement.
    leaf1589=write_part(PARTS/'shape-1589.svg',[-100.55,-45.45,183.15,97.9],
        '<title>CF6 turret leaf shape1589</title><desc>Exact inverse of 1591 parent placement: nativeProp1591 translated by -20.55,+49.45. Use this file when replacing shape1589, not prop1591.</desc>'+group('shape_1589_registration_adapter',inner(PARTS/'prop-1591.svg','leaf1589'),'transform="translate(-20.55 49.45)"'))
    render(leaf1589,1600,PREV/'shape-1589-redraw.png')
    mapping={
      'prop1591':{'part':'parts/prop-1591.svg','replace':'complete sprite1591 first visible frame','originalChild':'shape1589','childToPropMatrix':[1,0,0,1,20.55,-49.45]},
      'shape1589':{'part':'parts/shape-1589.svg','replace':'leaf shape1589, keeping all original sprite matrices','propToLeafMatrix':[1,0,0,1,-20.55,49.45],'viewBox':[-100.55,-45.45,183.15,97.9]},
      'crate1442':{'frames':[{'frames':[1],'depth':1,'shape':1436},{'frames':[2,3],'depth':6,'shape':1437},{'frames':[4,5],'depth':6,'shape':1438},{'frames':[6,7],'depth':6,'shape':1439},{'frames':[8,9],'depth':6,'shape':1440},{'frames':[10,11],'depth':6,'shape':1441}],'preserveOriginalTimelineMatrices':True,'frame1AreaDepth2':'sprite360 gameplay area; not redrawn','noSupplyDropInArtwork':True},
      'turretAnimation':{'frame12OriginalMuzzleFlash':'sprite506 (original shapes503–505), retain without redraw','keepOriginalTiming':True},
      'provenance':'Source SVGs copied from actual SWF export. Native shape1437–1441 clipping paths and matrices are consumed directly. No original SWF is needed to rebuild.'}
    (QA/'props-symbol-coordinate-map.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2))
    fragments=crate_fragments()
    print(json.dumps({'parts':manifest,'fragmentShapeIds':[x['shapeId'] for x in fragments]},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
