"""Hand-authored sculptural vector plates for CF6 head robot 952.
Coordinates in the original 927 bitmap's 293 x 278 atlas. No raster, tracing,
filters or texture is included in candidate art. Original target matrices are preserved. R3 explicitly repairs the damaged
929 crown clip; other target clips, including death-fragment crops, remain exact.
"""
from pathlib import Path
import json,re,copy,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1]
NS='http://www.w3.org/2000/svg'; ET.register_namespace('',NS)
SM={s['id']:s for s in json.loads((R/'reference/shape-manifest.json').read_text())}
INK='#191d19'; BLACK='#111714'; DARK='#4e492d'; GOLD='#97874e'; LIGHT='#c2b477'; HI='#e5dbac'; SILVER='#aabbb2'; STEEL='#61736c'
def p(d,f,s=None,w=.8,extra=''):
 return f'<path d="{d}" fill="{f}"'+(f' stroke="{s}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"' if s else '')+extra+'/>'
def l(d,c=INK,w=.7,extra=''):return p(d,'none',c,w,extra)
def e(x,y,rx,ry,f,s=None,w=.7):return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{f}"'+(f' stroke="{s}" stroke-width="{w}"' if s else '')+'/>'
def bolt(x,y,r=1.2):return e(x,y,r,r*.9,'#4a472e',INK,.5)+l(f'M{x-r*.4} {y-r*.5}L{x+r*.4} {y+r*.4}',LIGHT,.4)
DEFS='''
<radialGradient id="dome" cx="65%" cy="24%" r="84%" gradientTransform="translate(0 .015) scale(1 .985)"><stop offset="0" stop-color="#f1e7bc"/><stop offset=".14" stop-color="#dace9a"/><stop offset=".36" stop-color="#b9a96c"/><stop offset=".59" stop-color="#918049"/><stop offset=".78" stop-color="#625a33"/><stop offset="1" stop-color="#3a3c2b"/></radialGradient>
<linearGradient id="shell" x1="0" y1="0" x2="1" y2=".12"><stop offset="0" stop-color="#4e4b2d"/><stop offset=".10" stop-color="#817442"/><stop offset=".23" stop-color="#b7a775"/><stop offset=".29" stop-color="#d3c494"/><stop offset=".38" stop-color="#a59359"/><stop offset=".62" stop-color="#8c7c44"/><stop offset=".76" stop-color="#b8a770"/><stop offset=".88" stop-color="#70623a"/><stop offset="1" stop-color="#41422c"/></linearGradient>
<linearGradient id="goldbar" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6e6137"/><stop offset=".13" stop-color="#c2b079"/><stop offset=".23" stop-color="#f0e3b3"/><stop offset=".32" stop-color="#c9b880"/><stop offset=".52" stop-color="#8e7e47"/><stop offset=".65" stop-color="#4f4b2d"/><stop offset=".78" stop-color="#81713d"/><stop offset=".91" stop-color="#b29c5f"/><stop offset="1" stop-color="#46442b"/></linearGradient>
<linearGradient id="tube" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5b5530"/><stop offset=".16" stop-color="#b2a36c"/><stop offset=".27" stop-color="#eee1ad"/><stop offset=".34" stop-color="#d3c38d"/><stop offset=".57" stop-color="#99864b"/><stop offset=".72" stop-color="#4c482b"/><stop offset=".87" stop-color="#8e7b46"/><stop offset="1" stop-color="#3a3a25"/></linearGradient>
<linearGradient id="steel" x1="0" y1="0" x2="1" y2=".8"><stop offset="0" stop-color="#535f57"/><stop offset=".23" stop-color="#bcc4bc"/><stop offset=".37" stop-color="#d9ded6"/><stop offset=".56" stop-color="#78857c"/><stop offset=".78" stop-color="#2c3c34"/><stop offset="1" stop-color="#77847b"/></linearGradient>
<linearGradient id="nose" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#25352c"/><stop offset=".28" stop-color="#68776b"/><stop offset=".48" stop-color="#ccd3cb"/><stop offset=".61" stop-color="#f0f1e6"/><stop offset=".73" stop-color="#b2bbb0"/><stop offset="1" stop-color="#425246"/></linearGradient>
<linearGradient id="brow" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7e8d80"/><stop offset=".23" stop-color="#daded4"/><stop offset=".38" stop-color="#b9c2b7"/><stop offset=".68" stop-color="#596c5c"/><stop offset=".88" stop-color="#2c3c31"/><stop offset="1" stop-color="#1b2b21"/></linearGradient>
<linearGradient id="hose" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#131b18"/><stop offset=".27" stop-color="#39443c"/><stop offset=".46" stop-color="#657065"/><stop offset=".55" stop-color="#8b9182"/><stop offset=".68" stop-color="#354339"/><stop offset="1" stop-color="#18221c"/></linearGradient>
<linearGradient id="goldEdge" x1="0" y1="0" x2="1" y2=".1"><stop offset="0" stop-color="#6b6038"/><stop offset=".20" stop-color="#b7a775"/><stop offset=".40" stop-color="#e6d9a8"/><stop offset=".49" stop-color="#bfb079"/><stop offset=".61" stop-color="#675f39"/><stop offset=".84" stop-color="#9c8e56"/><stop offset="1" stop-color="#514d2f"/></linearGradient>
<linearGradient id="goldFace" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ded0a1"/><stop offset=".18" stop-color="#c1b480"/><stop offset=".43" stop-color="#9b905a"/><stop offset=".64" stop-color="#6a633d"/><stop offset=".82" stop-color="#b1a16c"/><stop offset="1" stop-color="#827345"/></linearGradient>
<linearGradient id="goldDark" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#3f412b"/><stop offset=".3" stop-color="#837544"/><stop offset=".6" stop-color="#b9a36c"/><stop offset="1" stop-color="#51492b"/></linearGradient>
<radialGradient id="domeSpec" cx="58%" cy="38%" r="55%"><stop offset="0" stop-color="#fff4cb" stop-opacity=".68"/><stop offset=".30" stop-color="#efe3b4" stop-opacity=".36"/><stop offset="1" stop-color="#c7b779" stop-opacity="0"/></radialGradient>
<linearGradient id="domeEdge" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ede0ac" stop-opacity=".7"/><stop offset=".35" stop-color="#b6a369" stop-opacity=".25"/><stop offset="1" stop-color="#c3b173" stop-opacity="0"/></linearGradient>
<linearGradient id="foreheadSteel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#35463a"/><stop offset=".23" stop-color="#8d9b8e"/><stop offset=".40" stop-color="#d4dacf"/><stop offset=".55" stop-color="#adb9ab"/><stop offset=".78" stop-color="#697b6a"/><stop offset="1" stop-color="#384b3b"/></linearGradient>
<linearGradient id="steelRim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4c5b4e"/><stop offset=".25" stop-color="#aebaac"/><stop offset=".39" stop-color="#e3e6db"/><stop offset=".52" stop-color="#bcc4b9"/><stop offset=".76" stop-color="#78877a"/><stop offset="1" stop-color="#314434"/></linearGradient>
<linearGradient id="steelBevel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d4dbcf"/><stop offset=".28" stop-color="#adbaaa"/><stop offset=".57" stop-color="#6a7c6b"/><stop offset=".75" stop-color="#3a4c3c"/><stop offset="1" stop-color="#7f9181"/></linearGradient>
<linearGradient id="lipSteel" x1="0" y1="0" x2=".2" y2="1"><stop offset="0" stop-color="#6f7c6c"/><stop offset=".19" stop-color="#c0c9ba"/><stop offset=".34" stop-color="#daded1"/><stop offset=".47" stop-color="#a4ae9d"/><stop offset=".70" stop-color="#6d7e68"/><stop offset=".86" stop-color="#3a4b3a"/><stop offset="1" stop-color="#253529"/></linearGradient>
<linearGradient id="lipSheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#dee4d5" stop-opacity=".5"/><stop offset=".38" stop-color="#bbc5b4" stop-opacity=".25"/><stop offset="1" stop-color="#657862" stop-opacity="0"/></linearGradient>
<linearGradient id="noseSpec" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#6c7e6a" stop-opacity="0"/><stop offset=".40" stop-color="#d8ded0" stop-opacity=".36"/><stop offset=".60" stop-color="#f6f6e9" stop-opacity=".65"/><stop offset="1" stop-color="#84937f" stop-opacity="0"/></linearGradient>
<linearGradient id="eyeRed" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a7090b"/><stop offset=".35" stop-color="#ff1b20"/><stop offset=".75" stop-color="#eb080f"/><stop offset="1" stop-color="#9a080b"/></linearGradient>
'''

ART={}
# Main body: continuous dome, cylindrical shell, inset sculpted metallic face.
b=''
# Rear right return tube.
b+=p('M155 173Q164 174 165 182Q165 192 149 197L147 190Q159 187 158 182Q157 179 153 179Z','url(#goldbar)',INK,1)
b+=l('M155 176Q160 177 161 182Q160 190 151 192',LIGHT,.7)
# Shell under the helmet and broad lower housing. The material follows a barrel.
b+=p('M16 64Q38 59 80 70L89 68L131 69L147 64Q157 82 160 110L164 143Q160 164 153 180L148 205L144 226L72 240L23 222Q13 202 10 185Q2 163 0 139L0 115Q2 91 12 72Z','url(#shell)',INK,1.1)
b+=p('M9 96Q10 80 18 75Q29 74 36 77Q25 97 22 124Q17 160 27 188L21 208Q11 188 6 164Q-1 133 9 96Z','url(#goldEdge)',extra=' opacity=".20"')
b+=p('M139 72L149 69Q159 92 159 120Q169 147 156 175L146 202L139 205Q146 179 150 156Q153 127 143 101Z','url(#goldDark)',extra=' opacity=".72"')
b+=l('M3 158Q33 168 70 168L131 167Q146 164 158 160',INK,.9)
b+=l('M7 169Q39 179 81 177L128 177Q146 175 157 171',INK,.9)
b+=l('M5 159Q34 169 70 169L130 168',LIGHT,.6)
# R3: authorized crown contour repair. Native cubic curve replaces the explicit
# source clip stair; stays in original viewBox and leaves all rig matrices intact.
DOME='M15.2 44.9C18 20 48 6 75 2.2C103 -1.8 140 11 144 27Q147.7 44.3 151.9 61.05Q153 66 145 69L132 73L87 72Q56 64 12 64Q13.8 54 15.2 44.9Z'
dome_start=len(b)
b+=p(DOME,'url(#dome)',INK,1.1)
b+=p('M23 32Q35 14 65 6Q87 0 107 5Q122 8 134 19Q116 7 98 9Q72 6 48 17Q32 24 23 37Z','url(#domeEdge)')
b+=e(94,23,40,22,'url(#domeSpec)')
b+=p('M15 56Q47 55 77 64L84 69L83 72Q51 63 14 64Z','#343c25',extra=' opacity=".35"')
b+=l('M22 31C35 15 61 6 82 4.2','#e0d4a2',.5,extra=' opacity=".65"')
DOME_ART=b[dome_start:]
b+=l('M14 64Q55 62 83 73M135 73Q145 68 152 65',INK,1.8)
# Narrow layered helmet gasket.
b+=p('M15 65Q55 64 84 75L82 82Q53 72 14 74Z','#1b211b',INK,.6)
b+=p('M136 73Q144 67 151 66L152 73Q144 76 139 82Z','#20251d',INK,.6)
for off in [0,1.3,2.6]:
 b+=l(f'M15 {67+off}Q54 {66+off} 83 {77+off}', '#54543a',.45)
 b+=l(f'M139 {75+off}Q146 {70+off} 152 {69+off}', '#55543b',.45)
for x,y in [(18,61),(60,63),(80,69),(138,68),(15,78),(53,80),(74,85),(152,78)]:b+=bolt(x,y)
# Face chamber: narrow perspective border descends to two diagonal vents.
b+=p('M90 66Q95 64 99 69L128 69Q132 65 137 69L161 122L143 148L85 151L64 122Z','#5c5b3d',INK,1)
b+=p('M92 69L98 71L128 72L135 70L155 120L140 145L86 146L68 120Z','#111a17',INK,.9)
b+=p('M94 72L97 79Q112 84 128 79L133 73L148 109L152 122L137 143L89 144L72 121L79 101Z','url(#steel)',INK,.9)
# Brow forehead overlaps beneath crest; etched metal crest at brow centre.
b+=p('M94 75Q101 84 111 86Q120 86 130 82L136 78L139 87Q125 89 123 94L119 105L112 105L108 96Q95 91 82 93L85 85Z','url(#foreheadSteel)')
b+=p('M86 90Q94 89 105 94Q110 96 112 101Q98 94 87 97L80 99Q81 94 86 90Z','url(#steelRim)')
b+=p('M131 92Q136 88 140 90L143 96Q133 95 125 101Q125 96 131 92Z','url(#steelRim)')
b+=l('M102 87Q113 90 126 87M105 89Q115 92 125 89', '#334139',.9)
b+=p('M108 92Q117 95 126 91Q127 94 122 97Q118 101 115 99Q111 97 108 92Z','url(#steelRim)',INK,.55)
b+=l('M111 92L113 94L115 94L115 96L118 97L119 94L122 94L124 92M113 91L114 92M120 91L120 92','#505e57',.65)
# Orbital cavities hug brow rather than extra jewel frames.
b+=p('M77 100Q89 94 103 99L114 104L112 110Q99 114 87 112L77 106Z','#1b231f',INK,.5)
b+=p('M123 104Q134 97 145 99L148 104L146 110Q134 113 124 110Z','#1b231f',INK,.5)
b+=p('M80 103Q90 99 101 102L110 106L107 109Q98 111 87 110Z','url(#eyeRed)',INK,.5)
b+=p('M126 105Q135 100 144 102L146 105L142 109L130 110Z','url(#eyeRed)',INK,.5)


b+=p('M80 98Q87 92 98 95Q108 97 114 104L111 106Q102 101 94 101Q85 100 79 104Z','url(#brow)')
b+=p('M124 103Q131 94 140 93L145 97L147 101Q137 98 127 104L125 107Z','url(#brow)')
b+=l('M89 92Q96 91 103 95M131 94Q137 90 141 92','#394a40',.95)
b+=p('M112 100Q117 103 122 100L124 104L121 107L115 107Z','#778a7f')
# Cheek/eye troughs: long curving surfaces sit beneath dark eye slots.
b+=p('M74 110Q83 117 98 115Q105 114 111 110L110 116Q95 125 78 121Q73 120 71 118Z','url(#steelRim)',INK,.5)
b+=p('M76 112Q88 116 102 114L109 112L107 114Q96 118 83 117Q78 116 76 114Z','url(#lipSheen)')
b+=p('M126 112Q135 116 148 111L150 116Q139 122 128 118Z','url(#steelRim)',INK,.5)
b+=p('M129 113Q138 115 146 113L147 114Q138 117 130 115.5Z','url(#lipSheen)')
b+=p('M72 119Q82 124 96 121L94 127Q83 132 77 136L71 127Z','url(#steelBevel)',INK,.5)
b+=p('M133 120L149 118L149 128L143 136L137 128Z','url(#steelBevel)',INK,.5)
# Short nose bridge, round tip, connected alar dark underside. Not a diamond.
b+=p('M115 107Q118 108 121 106Q121 113 124 118Q128 121 125 124Q120 127 114 125Q110 123 112 120Q115 116 115 107Z','url(#nose)',INK,.5)
b+=p('M117 109Q119 110 120 108Q119 115 122 119Q125 123 121 124Q116 125 115 122Q114 120 116 117Z','url(#noseSpec)')
b+=p('M110 116L114 116L112 121L113 124L105 124Q105 119 110 116Z','url(#steelBevel)',INK,.5)
b+=p('M125 117L130 120L132 124L125 124Q128 122 125 117Z','url(#steelBevel)',INK,.5)
b+=p('M111 125Q117 129 125 125L126 128L120 132L114 130Z','#36463d')
# Continuous sculpted cheeks turn into the original downturned upper-lip plate.
b+=p('M100 124Q107 123 112 127Q116 131 120 130Q123 128 128 125Q137 126 143 136Q146 140 143 142Q140 143 135 139Q129 134 124 133Q121 132 118 134Q114 136 110 133Q106 131 100 134Q91 139 83 142Q77 144 78 139Q83 132 92 127Z','url(#lipSteel)',INK,.5)
b+=p('M97 127Q104 125 108 127L112 131Q105 130 99 133Q91 138 83 140Q80 142 81 138Q87 131 97 127Z','url(#lipSheen)')
b+=p('M129 128Q136 129 141 137Q144 140 142 141Q139 141 135 137Q130 134 123 132Z','url(#lipSheen)')
b+=p('M83 144Q95 140 104 135Q109 132 113 135Q117 137 121 134Q127 132 135 140L141 144L139 147Q112 144 85 148Z','#53645c')
# A single shallow mouth opening, instead of parallel central wave marks.
b+=l('M85 144Q100 139 111 140Q120 138 139 144','#283830',.85)
b+=p('M84 147Q109 144 141 147L138 150Q111 152 86 150Z','url(#steelRim)',INK,.5)
for x in range(92,136,3):b+=l(f'M{x} 147.7l1.4 -1.2','#475449',.5)
# Forehead crest: real rounded rectangular relief with lightning insignia.
b+=p('M95 56L130 56L128 79Q126 85 120 86L105 86Q100 85 98 80Z','url(#goldFace)',INK,1)
b+=p('M98 60L127 59L125 78Q123 83 119 84L107 83Q102 81 101 76Z','url(#goldFace)')
for d in ['M101 63Q112 68 126 63Q123 69 105 67Z','M103 70Q113 73 124 69L123 72Q113 75 104 72Z','M105 77Q113 80 122 76L121 78Q113 81 106 79Z']:b+=p(d,'#403f2c')
b+=p('M92 36Q93 33 99 33L129 33Q135 33 135 39L136 55Q136 59 132 60L98 60Q92 60 91 56L91 41Z','#49472f',INK,1)
b+=p('M96 35L129 35Q133 35 133 39L134 55Q134 58 130 58L98 58Q94 58 94 54L94 40Q94 36 96 35Z','url(#goldEdge)',INK,.6)
b+=p('M99 38L129 37Q131 37 131 40L132 53Q132 56 128 56L100 56Q97 56 97 53L97 41Q97 39 99 38Z','url(#goldFace)',INK,.75)
b+=p('M99 39L116 38L99 50Z','url(#goldEdge)')
b+=p('M116 38L108 48L113 46L109 56L127 42L116 48L119 37Z','#22271f',INK,.5)
b+=p('M116 41L112 47L115 46L112 52L121 45L115 49Z','#a49c6d')
b+=l('M98 51L110 44M119 46L131 41','#30372b',1)
b+=l('M96 36L126 35M95 39L95 54',HI,.65)
# Face aperture thin gold rails (not bulky new armour).
b+=p('M89 67L93 66L89 78L67 120L62 119L83 75Q85 68 89 67Z','url(#goldEdge)',INK,.8)
b+=l('M89 69L86 78L65 119', '#d0c187',.9)
b+=p('M135 68L138 69L162 122L158 124L135 77Z','url(#goldEdge)',INK,.85)
b+=l('M138 75L159 121','#d8cd97',.8)
# R3 intake louvers. Original splayed aperture perspective, full-height fins,
# dark recess + bevel + face/edge reflectance, rather than floating line marks.
DEFS += """
<linearGradient id="ventDepth" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#060b0a"/><stop offset=".55" stop-color="#121a16"/><stop offset="1" stop-color="#080d0c"/></linearGradient>
<linearGradient id="ventBladeL" gradientUnits="userSpaceOnUse" x1="0" y1="124" x2="0" y2="160"><stop offset="0" stop-color="#18201c"/><stop offset=".30" stop-color="#323c35"/><stop offset=".58" stop-color="#687069"/><stop offset=".72" stop-color="#424c43"/><stop offset="1" stop-color="#252f28"/></linearGradient>
<linearGradient id="ventBladeR" gradientUnits="userSpaceOnUse" x1="0" y1="125" x2="0" y2="153"><stop offset="0" stop-color="#111914"/><stop offset=".45" stop-color="#303a31"/><stop offset=".74" stop-color="#57625a"/><stop offset="1" stop-color="#202b23"/></linearGradient>
<clipPath id="leftIntake"><path d="M43 132L62 123L82 149L68 160Z"/></clipPath>
<clipPath id="rightIntake"><path d="M144 147L160 125L172 129L152 153Z"/></clipPath>
"""
b+=p('M39 131L63 119L87 150L68 165Z','url(#goldFace)',INK,1)
b+=p('M140 147L159 121L177 127L153 158Z','url(#goldFace)',INK,1)
# Different depth edges on each cheek follow the source's asymmetrical perspective.
b+=p('M39.6 131.3L62.8 120L62 123L43 132L68 160L68 164Z','#b9b38e')
b+=p('M62.8 120L86 149.9L82 149L62 123Z','#d8d2ae')
b+=p('M68 160L82 149L86 149.9L68 164Z','#77744e')
b+=p('M140.8 147L159.2 122L160 125L144 147L152 153L153 157Z','#c4bd96')
b+=p('M159.2 122L176 127.4L172 129L160 125Z','#e0d7af')
b+=p('M153 157L176 127.4L172 129L152 153Z','#77744e')
b+=p('M43 132L62 123L82 149L68 160Z','url(#ventDepth)',INK,.8)
b+=p('M144 147L160 125L172 129L152 153Z','url(#ventDepth)',INK,.8)
for side,pitch,start,n,slope,y0,y1,width in [('L',3.3,44.5,11,-.17,120,165,1.5),('R',2.7,144.2,11,.045,122,156,1.12)]:
 clip='leftIntake' if side=='L' else 'rightIntake'
 b+=f'<g id="intake-blades-{side}" clip-path="url(#{clip})">'
 for i in range(n):
  xx=start+i*pitch;top=xx+slope*(y0-140);bottom=xx+slope*(y1-140)
  # The bright folded edge and shaded side are attached to the same full fin.
  b+=p(f'M{top} {y0}L{top+width} {y0}L{bottom+width} {y1}L{bottom} {y1}Z',f'url(#ventBlade{side})')
  b+=p(f'M{top+width} {y0}L{top+width+.65} {y0}L{bottom+width+.65} {y1}L{bottom+width} {y1}Z','#080e0b')
  b+=l(f'M{top+.14} {y0}L{bottom+.14} {y1}', '#9ba59a',.28,extra=' opacity=".50"')
 b+='</g>'
# Recessed inner shoulders cover fin tips, seat them into frame and add depth.
b+=l('M43 132L62 123L82 149','#080d0b',1.0)
b+=l('M43 132L68 160L82 149','#85866a',.45)
b+=l('M144 147L160 125L172 129','#080d0b',.85)
b+=l('M144 147L152 153L172 129','#737a61',.4)
b+=l('M40 132L68 164L86 151M141 148L153 157L176 128', '#e2d5a3',.5)
# Lower face and chest seam.
b+=l('M87 151Q113 153 139 150M111 152L110 160M115 152L114 160M118 152L117 160',INK,.8)
# Chest central hexagonal socket with concentric real metal grooves.
b+=p('M92 159L126 159L138 178L129 190L93 190L84 179Z','url(#goldFace)',INK,1)
b+=p('M95 162L124 162L134 178L126 188L95 188L88 178Z','#161e18',INK,.9)
for i in range(4):b+=l(f'M{96+i*2} 163L{91+i*2} 177L{98+i*2} 187M{123-i*2} 163L{130-i*2} 178L{125-i*2} 187','#626643',.75)
b+=p('M99 167L108 166L113 171L111 182L106 186L97 183L94 177Z','url(#goldDark)',INK,.8)
b+=p('M102 167L107 168L107 183L101 184L98 180L99 171Z','url(#goldEdge)')
b+=e(112,177,9.8,10,'url(#goldEdge)',INK,.9)+e(112,177,6.1,6.4,'#262f2a',INK,.7)
b+=p('M109 168Q116 166 120 173L119 177Q116 171 110 171Z','url(#goldFace)')
b+=l('M95 172L101 172M94 176L99 176M95 180L100 180M108 163L108 166',INK,.7)
b+=l('M99 191L99 206M119 190L119 207',INK,.75)
# Front return hose gland and cylinder, round and broad.
b+=e(40,177,12.8,9.7,'url(#goldFace)',INK,.9)+e(35,181,9,8,'url(#goldDark)',INK,.85)
b+=p('M36 180Q43 179 44 184Q44 188 37 190L26 192Q14 194 14 201Q14 205 19 207L19 215Q9 212 7 205Q4 193 15 186Q23 182 36 180Z','url(#tube)',INK,1)
b+=l('M11 200Q10 190 24 186L36 184',LIGHT,1.1)
b+=e(37,184,3.2,4.6,'url(#goldDark)',INK,.7)
# Underbody ribbed belt and continuous flared skirt.
b+=p('M20 215Q76 225 144 213L148 229Q92 244 20 229Z','#171e18',INK,.8)
for yy in [219,222,225,228]:b+=l(f'M20 {yy}Q83 {yy+9} 145 {yy-2}', '#4a4d35',.7)
b+=p('M20 227Q54 236 91 236L131 232L145 226Q152 233 154 241L158 250L157 262Q116 277 69 270Q33 267 7 255L7 246Q11 234 20 227Z','url(#shell)',INK,1)
b+=p('M21 229Q49 237 87 238L78 254Q39 251 10 244Q14 234 21 229Z','url(#goldFace)')
b+=p('M133 233L145 228L150 237L153 244L141 248Z','url(#goldFace)')
b+=p('M8 250Q42 261 78 261L79 267Q37 263 8 254Z','#655b35',INK,.7)
b+=p('M137 251L157 245L158 250L140 257Z','#685c36',INK,.7)
b+=l('M8 245Q38 254 78 256M8 249Q39 258 78 260M8 254Q40 263 79 265M138 249L156 244M139 253L157 248M140 258L157 253',INK,.8)
b+=l('M10 244Q44 252 78 254M139 248L155 243',HI,.7)
for x,y in [(25,231),(41,235),(77,242),(140,237)]:b+=bolt(x,y,1.6 if x in (77,140) else 1)
# Front suspended centre casing / small mechanical clasp.
b+=p('M93 218L125 218L127 237L121 242L103 242L92 237Z','url(#goldFace)',INK,.9)
b+=p('M101 225L116 225L122 234L97 234Z','#635d3b',INK,.8)
b+=p('M104 226L114 226L118 232L101 232Z','url(#goldFace)',INK,.6)
for x in [104,108,112,115]:b+=l(f'M{x} 227L{x-.8} 231',INK,.65)
b+=p('M97 233L123 233L123 239Q110 242 96 239Z','url(#goldFace)',INK,.8)
b+=l('M100 235L119 235',LIGHT,1)
b+=p('M96 241L104 242L100 271L92 276L78 274L76 268L78 253L85 238Z','url(#goldFace)',INK,1)
b+=p('M121 241L129 239L140 251L141 271L132 275L126 268Z','url(#goldDark)',INK,1)
b+=l('M78 257L99 259M77 261L98 263M78 268L97 270M132 258L141 256M134 264L141 262',INK,.9)
b+=p('M100 242Q110 245 123 242Q126 251 128 263L128 274Q118 279 106 277L103 274Q102 257 100 242Z','url(#shell)',INK,1)
b+=p('M104 245L111 246Q111 260 114 275L107 275Q106 258 104 245Z','url(#goldEdge)')
b+=l('M100 242L104 250L106 272M122 244L125 265L125 273',DARK,.9)
# Waist band and four pods; their round caps follow their distinct positions.
b+=p('M17 204Q77 215 147 201L147 216Q79 230 21 218Z','url(#goldFace)',INK,.85)
for yy in [207,211,215]:b+=l(f'M19 {yy}Q82 {yy+10} 146 {yy-4}',INK,.7)
b+=l('M20 206Q79 215 146 201',LIGHT,.65)
b+=p('M103 210L117 209L116 218L103 219Z','#4c4930',INK,.8)+p('M106 211L114 211L114 216L106 217Z','url(#goldFace)',INK,.55)
# Pod 1 hangs below collar; Pod 2 longer, third broad and final short.
for x,y,rx,h in [(29,203,8,20),(53,206,6.5,20),(85,205,8,17),(137,204,8,15)]:
 b+=p(f'M{x-rx} {y}Q{x} {y+3} {x+rx} {y}L{x+rx-1} {y+h-6}Q{x+2} {y+h+2} {x-2} {y+h}Q{x-rx} {y+h-4} {x-rx} {y}Z','url(#shell)',INK,.85)
 b+=p(f'M{x-3} {y+2}L{x+2} {y+3}L{x+2} {y+h-3}Q{x-3} {y+h-5} {x-3} {y+2}Z','url(#goldEdge)')
 b+=e(x,y,rx,3.5,'url(#goldbar)',INK,.8)+e(x,y-.5,rx-1.8,1.5,'url(#goldbar)')
 for dy in [4,7]:b+=l(f'M{x-rx+.5} {y+dy}Q{x} {y+dy+3} {x+rx-.5} {y+dy}',INK,.65)
ART[929]=b
# Integrated gun arm, fitted to its original projection and muzzle lights.
g=''
g+=p('M164 17Q169 15 175 17Q183 15 193 14L196 10L205 10L209 14Q231 13 245 21L249 23L249 30L275 31L292 34L292 42L275 45L249 45L249 50Q249 54 239 57Q203 65 166 58Q159 54 158 48L157 36Q157 22 164 17Z','url(#goldbar)',INK,1)
g+=p('M166 20Q180 21 193 17Q213 15 231 18Q240 20 245 23L238 24Q211 20 184 24L166 29Z','url(#goldFace)')
g+=p('M168 21L165 29L164 47L170 57L164 56L159 50L159 30Z','#655b33',INK,.7)
g+=p('M170 24Q201 20 223 24L239 28L238 49Q210 55 176 50Q171 48 169 43Q166 34 170 24Z','url(#goldbar)',INK,.8)
g+=p('M175 26Q199 23 220 26L232 29L190 29L172 30Z','url(#goldbar)')
g+=p('M173 44Q201 49 236 45L237 49Q205 54 176 49Z','#776b3d')
g+=l('M169 25Q200 19 226 23L240 28M168 50Q197 57 235 51M169 53Q199 59 237 54',INK,.8)
g+=l('M175 21L194 20M172 28L190 27', '#524e30',.9)
# Rear collar and cartridge sleeve step from broad casing to round barrel.
g+=p('M206 28L235 29L237 45L208 47Q200 45 200 38Q200 30 206 28Z','#837747',INK,.9)
g+=p('M211 30L236 31L237 42L210 44Q205 44 205 38Q205 32 211 30Z','url(#tube)',INK,.7)
g+=p('M236 31L278 32L282 35L281 43L237 44Q232 44 231 38Q231 33 236 31Z','url(#tube)',INK,.9)
g+=l('M237 33L275 34',HI,1)
g+=p('M277 33L288 35L292 37L292 42L278 43Z','#3c4d43',INK,.8)
# Paired source cyan emitters and narrow muzzle slot.
for x,y,w,h in [(230,23,16,4.2),(230,48,16,4.3),(280,37,11,3.4)]:
 g+=p(f'M{x-1} {y-1}H{x+w+1}V{y+h+1}H{x-1}Z','#283a32',INK,.65)
 g+=p(f'M{x} {y}H{x+w}V{y+h}H{x}Z','#00c9d5')
 g+=l(f'M{x+1} {y+1}H{x+w-1}','#9dfbf0',.75)
g+=p('M194 14L197 11L204 11L208 14Z','url(#goldFace)',INK,.6)
ART[928]=g
# Horizontal corrugated connection bar, two nested metal cuffs.
r=p('M183 89Q183 85 188 85L211 87L226 86Q234 81 245 84L256 87L287 86Q292 87 292 91L291 98Q276 101 257 98L247 100L224 100L206 98L186 98Q181 97 181 92Z','url(#tube)',INK,.8)
r+=p('M208 88L223 87L224 96L208 96Q205 92 208 88Z','url(#goldbar)',INK,.7)
r+=p('M224 87Q234 83 244 85L244 98Q233 99 225 96Z','url(#tube)',INK,.7)
r+=p('M245 85L255 87L257 96L248 99L243 97L242 90Z','#655b34',INK,.7)
for x in [185,190,195,201,263,272,282]:r+=l(f'M{x} 86Q{x-3} 92 {x} 98',INK,1.1)+l(f'M{x+1} 87Q{x-1} 91 {x} 94',HI,.55)
r+=l('M209 89L222 88M227 87Q234 85 241 87M246 88L254 90M245 92L255 92M245 96L254 94',LIGHT,.7)
ART[930]=r
# Hover tray. Distinct wire loops, little contact feet, saucer and handle.
v=''
v+=l('M192 240L193 250L235 250L236 240',INK,2.5)
v+=l('M193 241V249M235 241V249',LIGHT,.7)
v+=p('M191 215L191 202Q191 195 198 195H232Q239 196 239 202V214L235 214V202Q235 199 232 199H198Q195 199 195 203V215Z','url(#goldEdge)',INK,.8)
v+=l('M193 214V202Q193 197 199 197H232Q237 198 237 203',HI,.7)
v+=p('M210 219V211Q211 207 217 208V218L251 218V209Q257 206 259 212L259 221L211 224Z','url(#goldFace)',INK,.7)
for x in [221,226,231,242,247]:v+=l(f'M{x} 210V219',INK,.7)
# Left float bulb and right platter, both flattened ellipses in original view.
v+=p('M167 223Q176 214 193 214Q208 214 217 221L216 232Q200 242 180 235Q169 232 167 227Z','url(#goldbar)',INK,.85)
v+=e(193,221,19.5,6.2,'url(#goldbar)',INK,.75)
v+=p('M176 220Q191 216 205 220Q199 223 184 223Z','url(#goldbar)')
v+=l('M173 231Q190 237 210 232M180 234Q194 239 206 236',INK,.7)
# Energy loops are discrete silver strokes, with open transparent centres.
v+=p('M208 221Q199 222 199 225L206 228L212 229L209 232Q200 231 195 227Q193 224 199 222Z','#d6e3da',INK,.65)
v+=p('M252 223Q272 224 282 231L275 232L267 229Q258 228 252 227Z','#b8cbc0',INK,.7)
v+=p('M266 232L278 233Q279 235 270 239L266 239Q273 235 266 234Z','#c9d9d0',INK,.6)
v+=p('M204 228Q221 237 252 234L266 230L270 234Q256 243 229 241Q207 241 198 234L198 231Z','#687c70',INK,.75)
v+=l('M201 233Q217 242 244 238Q261 237 267 232','#d3e2d6',1)
# Saucer stack body and central concentric taper.
v+=p('M211 220Q218 216 235 216Q255 216 267 225L269 230Q262 236 239 237Q216 238 206 231L205 227Z','url(#goldbar)',INK,.85)
v+=e(237,225,30,7.8,'url(#goldFace)',INK,.8)
v+=p('M218 220Q237 213 254 220L259 225Q255 230 238 230Q223 230 215 226Z','url(#goldbar)',INK,.7)
v+=p('M222 216Q236 212 249 216L254 221Q248 225 236 225Q225 224 219 222Z','url(#goldbar)',INK,.7)
v+=p('M227 213Q236 210 244 214L248 217Q238 221 225 218Z','url(#goldbar)',INK,.65)
v+=e(236,213,7,2.2,'url(#goldbar)',INK,.6)
v+=l('M217 221Q235 227 252 222M211 228Q236 235 264 229',LIGHT,.7)
for x in [193,236]:
 v+=p(f'M{x-3} 248Q{x} 246 {x+3} 249V252L{x+1} 254L{x} 257L{x-1} 254L{x-3} 252Z','url(#goldDark)',INK,.75)
 v+=e(x,249,3,1.1,'url(#goldbar)',INK,.5)
ART[931]=v
# Corrugated flexible tube with upper brass end, in original pose.
h=p('M224 139Q227 137 231 139Q237 140 237 145L237 149Q231 156 226 152L223 147Z','url(#goldbar)',INK,.8)
h+=p('M229 140Q234 140 235 145Q235 148 232 150L228 151L226 148Q232 146 229 140Z','url(#goldFace)')
h+=l('M230 139Q235 142 233 147',HI,.7)
h+=p('M215 173Q211 175 209 172L206 162Q203 159 204 153Q202 143 207 136Q210 132 217 133Q222 133 224 136L228 140L226 145Q222 146 219 141Q216 138 214 140Q211 144 211 152L212 158L212 163L217 172Z','url(#hose)',INK,.8)
for d in ['M208 137Q211 141 215 140','M205 143Q208 146 212 144','M204 148Q207 150 211 149','M204 154Q207 156 211 155','M205 159Q208 161 212 160','M207 164Q210 166 213 165','M209 169Q212 171 215 169','M215 133L215 140','M222 135Q222 139 219 141','M226 139Q226 142 223 144']:
 h+=l(d,INK,.85)
h+=p('M211 170L216 170L219 175Q215 178 211 175L209 173Z','url(#goldbar)',INK,.75)
h+=l('M211 171L216 172',LIGHT,.7)
ART[932]=h

# Write independent atlas-space authoring parts, each preserves semantically named groups.
for sid,art in ART.items():
 (R/f'art/{sid}-atlas.svg').write_text(f'<svg xmlns="{NS}" viewBox="0 0 293 278" width="879" height="834"><defs>{DEFS}</defs><g id="hand-drawn-{sid}">{art}</g></svg>')
(R/'art/927-vector-atlas.svg').write_text(f'<svg xmlns="{NS}" viewBox="0 0 293 278" width="879" height="834"><defs>{DEFS}</defs>'+''.join(f'<g id="part-{i}">{ART[i]}</g>' for i in [929,928,930,931,932])+'</svg>')
# Main body and gun derive from the original clip, rather than drawn external bounds.
ATLAS=''.join(ART[i] for i in [929,928,930,931,932])
# The tiny source material fringe lives outside the live-body clip. Provide this
# beneath vector material so the original death crops can sample it, never clip
# a fragment through the live-body mask a second time.
BLEED=p('M-2 -2H180V280H-2Z','#817547')
BLEED+=p('M156 7H294V63H156Z','url(#goldFace)')+p('M179 82H294V102H179Z','#97874e')+p('M201 130H239V180H201Z','#4c5140')+p('M163 192H287V260H163Z','#98874c')
# Original bitmap alpha remains as a native vector clipping path, converted only
# from alpha connectivity; it is not used to create interior surfaces or texture.
def atlasclip():
 from PIL import Image
 import math
 alpha=Image.open(R/'reference/bitmaps/927.png').getchannel('A')
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
# Transparent slots on tray stay open. The raw atlas alpha preserves source holes.
AC,AO=atlasclip()
(R/'art/atlas-alpha-path.txt').write_text(AC)
for sid in [928,929,930,931,932]+list(range(941,951)):
 s=SM[sid];root=ET.parse(R/f'reference/shapes/{sid}.svg').getroot()
 # Replace each bitmap image with the vector atlas under the unchanged matrix.
 defs=ET.Element(f'{{{NS}}}defs')
 defs.extend(ET.fromstring(f'<defs xmlns="{NS}">{DEFS}<clipPath id="atlasAlpha"><path d="{AC}" fill-rule="evenodd" clip-rule="evenodd"/></clipPath><clipPath id="r3KeepOutsideCrown"><path d="M0 64H155V278H0Z M155 0H293V278H155Z"/></clipPath><clipPath id="r3Dome"><path d="{DOME}"/></clipPath><clipPath id="r3CrownBand"><path d="M0 0H155V64H0Z"/></clipPath><g id="vectorAtlas927"><g clip-path="url(#r3KeepOutsideCrown)"><g clip-path="url(#atlasAlpha)">{BLEED}{ATLAS}<path d="{AO}" fill="none" stroke="#25291d" stroke-width=".82" stroke-linejoin="round"/></g></g><g clip-path="url(#r3CrownBand)"><g clip-path="url(#r3Dome)">{ART[929]}</g></g></g></defs>'))
 if sid==929:
  # Replace only source's crown contour. Everything from right crown landing
  # through body and back up to left crown landing is verbatim source geometry.
  cp=root.find(f'{{{NS}}}clipPath/{{{NS}}}path');old=cp.get('d')
  a=old.index(' Q60.6,-167.6');z=old.index(' Q-68.5,-188.85')
  cp.set('d','M-71.9,-167 C-69.1,-191.9 -39.1,-205.9 -12.1,-209.7 C15.9,-213.7 52.9,-200.9 56.9,-184.9'+old[a:z]+' Z')
 root.insert(0,defs)
 counter=0
 for parent in list(root.iter()):
  for node in list(parent):
   if node.tag==f'{{{NS}}}image':
    # 927 is the only bitmap in these shapes; preserve every original target clip.
    transform=node.get('transform','')
    g=ET.fromstring(f'<use xmlns="{NS}" transform="{transform}" href="#vectorAtlas927"/>')
    ix=list(parent).index(node);parent.remove(node);parent.insert(ix,g);counter+=1
 assert counter==len([f for f in s['fills'] if f['type']=='bitmap'])
 ET.ElementTree(root).write(R/f'parts/{sid}.svg',encoding='unicode')
# 939/940 are original vector connector-tray assemblies, not fractures. Retain
# their exact authored paths and projection. Do not reinterpret them as smoke.
for sid in [926,939,940]:
 (R/f'parts/{sid}.svg').write_bytes((R/f'reference/shapes/{sid}.svg').read_bytes())
(R/'source/art-manifest.json').write_text(json.dumps({'unit':952,'revision':'R3 local crown and intake repair; 183-frame rerun intentionally not performed','atlas':927,'handAuthoredParts':list(ART),'newVectorFragments':list(range(941,951)),'retainedNativeVector':[926,939,940],'note':'939/940 are connector and tray composites; original source statement calling them cracks was incorrect. Main-body clipping is never reapplied inside death fills.','sculpturalAnchors':{'crestRect':[91,33,136,60],'leftRedEye':[80,101,110,110],'rightRedEye':[126,102,146,110],'nose':[112,104,125,127],'mouth':[84,135,141,150],'leftGill':[39,119,87,165],'rightGill':[140,121,177,158],'chestSocket':[84,159,138,190]},'style':'hand-authored curves and controlled metallic gradients; no interior autotrace; original alpha outside authorized R3 crown repair','clipExceptions':[929],'localRasterValidationOnly':True,'rasterImagesInCandidateBody':False},indent=2))
print('Built R3 local crown and intake hand-drawn atlas, 5 live pieces, 10 original-matrix fragments and 3 retained native vector shapes.')
