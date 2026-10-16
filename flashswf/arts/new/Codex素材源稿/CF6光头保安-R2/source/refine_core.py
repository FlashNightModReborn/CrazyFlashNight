"""R2 core artwork: original facial landmarks and tailored cloth before stylization.
Coordinates are native bitmap 581 pixels (385x321), not resized preview pixels.
R1 remains frozen. All interiors are authored paths; no source lighting sampling.
"""
from pathlib import Path
import json
R=Path(__file__).resolve().parents[1]
def p(d,f,s=None,w=.75):return f'<path d="{d}" fill="{f}"'+(f' stroke="{s}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"' if s else '')+'/>'
def l(d,c='#211e1b',w=.7):return p(d,'none',c,w)
A={}
# HEAD R2 pass 3: coherent skin volume; no separate cheek/chin face-mask plates.
# One restrained gradient carries the skull/cheek/jaw lighting. Hard detail is
# confined to brow pressure, glasses, alar shadow, lip seam and ear cartilage.
h='<defs><radialGradient id="guardHeadSkinVolume" gradientUnits="userSpaceOnUse" cx="276" cy="39" r="42" gradientTransform="matrix(1 0 0 1.7 0 -27.3)"><stop offset="0" stop-color="#cba080"/><stop offset=".38" stop-color="#bc8d6c"/><stop offset=".70" stop-color="#9a6b4c"/><stop offset="1" stop-color="#62412d"/></radialGradient></defs>'+p('M225 -3H297V88H225Z','url(#guardHeadSkinVolume)')
# The small side shadow sits beside the ear; it does not encircle the jaw.
h+=p('M232 33Q233 24 238 17Q235 29 238.7 36.3Q237.5 47 241.9 56.3L247 66Q241.4 61 238.8 55.2L232.5 53Z','#735039')
# One connected temple/cheek turn retains the original side shadow; no mirrored mask.
h+='<defs><radialGradient id="guardCheekTurn" gradientUnits="userSpaceOnUse" cx="239" cy="61" r="31" gradientTransform="matrix(1 0 0 1.2 0 -12.2)"><stop offset="0" stop-color="#583322" stop-opacity=".82"/><stop offset=".45" stop-color="#583322" stop-opacity=".65"/><stop offset="1" stop-color="#583322" stop-opacity="0"/></radialGradient></defs>'+p('M225 -3H297V88H225Z','url(#guardCheekTurn)')
# Ear is a narrow irregular cartilage shape, with open curved ridges.
h+=p('M230.1 34.4Q234 34.8 237.4 41.3Q239.2 46.2 238.9 51.2L239.4 56.7Q236.4 59.3 233.7 56.8Q233.4 50.8 231.5 44.6Q229.6 38.8 230.1 34.4Z','#735039')
h+=p('M231.9 37.2Q234.8 38.2 236.5 42.9Q237.5 46.2 236.2 49L237 53.5Q235.8 54.2 234.8 52.8Q234.8 47.9 232.9 43Z','#593e2d')
h+=l('M231.8 36.5Q235.2 37.7 237 43.1Q238.1 46.3 237.1 48.4M234.1 45.9Q235 49.3 235 51.5Q235.1 53.5 236.9 54.4','#3c2b20',.7)
# A compact dark orbital recess; original dark lens landmarks are retained.
h+=p('M248.7 40.8Q254.1 36.5 260.6 37.5Q268.3 37.8 273.7 40.8Q272.9 46 267.8 48.3Q258.3 51 251.5 47.4Q248.8 44.6 248.7 40.8Z','#65442f')
h+=p('M250.1 40.8Q254.5 36.9 260.4 38Q267.1 38.3 272.8 40.9Q270.2 45.7 265 47.4Q258.3 49.2 253.7 46.3Q251.2 44.1 250.1 40.8Z','#080c0d')
h+=p('M282 40.3Q285 39.6 288 40.3L287.7 45.5Q287.1 48.9 285.6 49.2Q282.1 47.5 282 43.3Z','#090e0f')
# Brow folds press into the bridge instead of becoming a thick glasses frame.
h+=l('M272.4 41.2Q275.2 40.1 274.2 37.3M278.8 37.5Q279.1 40.9 282 41.1','#2e231a',.8)
h+=p('M272.7 41.4Q272 44.9 269.5 48.7L270.6 52.3Q272.3 48.7 273.7 44.5Z','#906347')
h+=p('M282.2 48Q284.6 50 286.7 49.8L285.1 56Q282.6 52.3 282.2 48Z','#9b6d50')
# Narrow, short, rounded nose: the dark bulb is a basal shadow, never a U rim.
bridge='M275.2 39.8Q276.5 37.8 277.7 39.8Q278.8 44.6 278.4 48.8Q278.5 53.1 280.1 55.5Q281.1 57.3 280.2 58.4Q278.3 59.6 276.3 58.7Q274.6 57.9 275.1 56Q276.2 53.2 276.2 50.2Z'
h+=p(bridge,'#c39776')
h+=p('M275.2 41.9Q276.1 46.8 275.6 51.3Q274.8 54.2 274.7 56.3Q274.2 58.4 276.2 59.2Q278.4 60 280.6 58.4L280.6 57.5Q278.8 59 277 58.1Q275.8 57.8 276.2 55.8Q277.2 53.1 277 49.3L276.6 42.1Z','#a17352')
h+=p('M276.9 40Q277.9 43.6 277.7 48.5Q277.8 52.9 279.2 55.6Q279.8 57 279.2 57.6Q278 58.2 276.9 57.4Q276.7 56.2 277.6 54.8Q276.9 50.8 276.9 47.4Z','#d1a581')
h+=p('M275.1 57.3Q276.1 57.1 276.7 58.2Q278.8 59 280.5 57.7Q280.4 59.9 278.1 60.3Q275.8 59.8 275.1 58.6Z','#4f3222')
h+=p('M274.8 44Q275.5 49.7 274.4 52.8Q273.6 55.4 274.8 57.2L275.5 57Q274.9 55.4 275.7 53.1Q276.2 49.3 275.6 45.6Z','#69442d')
h+=l('M274.9 54.7Q274.1 56.3 274.6 57.6M280.3 54.8Q281 56.1 280.9 57.4','#6a4731',.5)
# Short cast shadow below the nasal wings, ending above the lips.

# Nasolabial definition is short and low contrast, preserving cheek flesh.
h+=l('M271.8 62.4Q269.2 64.2 267.7 66.2','#895f44',.5)
# Tight closed lip seam. The near corner pulls down; the far end stays tucked in.
h+=p('M266.9 68.9Q270.2 67.5 273.5 68.1Q277.1 67.7 280.8 68L281.2 68.8Q276.9 70 272.6 69.6Q269.4 69.3 266.8 69.6Z','#38271b')
h+=p('M268.1 69.4Q272.9 70.3 277.5 69.5L280.4 68.8Q279.7 70 276.1 70.6Q271.2 71 267.9 70.1Z','#ad8362')
h+=l('M264.4 72Q264.7 69.7 267.1 68.1Q270 66.3 273.2 67.3Q276.2 66.5 279.4 67.1L281 67.8','#3d2a1d',.65)
# One small underlip crease; no rectangle, beard patch or isolated chin plate.
h+=l('M270.2 73.4Q273.2 73.9 276.3 73.1','#956d50',.45)
outline='M234.8 34.2Q233.8 23.2 241.4 12.1Q250.4 -.6 263.5 .7Q276.8 -.2 283.7 13.7Q287.8 21.3 288.5 31.6Q288.7 33 289.5 34.2Q289.8 35.6 288.5 37Q287.4 41.7 287.8 46.6Q287.5 51.8 285.4 58.9Q283.4 65.1 283.1 71.9Q282.9 78 280.7 81Q278 84.2 271.3 82.5Q259.5 80.3 251 74.5Q243.3 66.6 238.9 57.8Q235 61.7 232.5 57.7Q232.6 52.2 230.3 44.7Q228.2 37.6 229.6 34.7Q231.2 32.7 234.8 34.2Z'
h+=l(outline,'#2c241c',.7)
A['590']={'body':h,'skipAutoOutline':True,'scope':'Original compressed brow/lenses, narrow rounded nasal tip and tight closed lips; one coherent skin-volume transition, no cheek/chin mask panels.'}

# SUIT: charcoal wool in three low-contrast curved masses, original tailoring.
BASE='#272a2b';DARK='#191c1d';MID='#303435';LIGHT='#373c3d';INK='#131718'
t=p('M-3 4H143V254H-3Z',BASE)
# Back-side shadow is continuous with the silhouette, not floating armor bands.
t+=p('M1 65Q20 48 42 46Q49 54 51 65Q45 76 40 89Q36 102 42 124Q46 145 44 167Q42 194 36 215L29 241Q20 243 13 240Q25 208 27 187Q25 164 20 140Q17 116 8 98Q0 83 1 65Z',DARK)
t+=p('M7 64Q21 51 40 48Q46 49 49 55Q43 57 35 59Q21 65 16 75Q10 82 10 92Q5 82 5 72Z',MID)
# Front wool plane is a broad taper attached to the shoulder/chest.
t+=p('M44 82Q54 82 62 98Q76 115 80 141Q82 158 78 180Q74 202 71 222L69 243Q56 246 42 244Q44 227 50 208Q58 181 56 157Q55 130 45 111Q41 97 44 82Z',MID)
t+=p('M124 75Q131 73 134 80Q134 107 129 135Q124 160 122 182Q120 205 128 232L133 242L120 245Q109 222 108 199Q108 181 113 160Q120 133 122 109Z',DARK)
t+=p('M110 112Q118 107 124 104Q124 130 117 156Q110 184 113 204Q114 220 121 244L104 246Q99 228 98 211Q97 195 100 173Q106 143 110 112Z',MID)
# Neck: curved sternocleidomastoid planes; top boundary is insertion, not inked.
t+=p('M55 41L67 15L94 20L101 59L94 64Q74 57 55 44Z','#986c4c')
t+=p('M59 38Q65 26 67 17L72 19Q67 34 71 42Q77 51 92 58L96 61L91 63Q72 57 56 44Z','#795036')
t+=p('M82 21L93 23Q94 40 98 55Q96 58 93 58Q88 51 87 42Q86 30 82 21Z','#ad815d')
# Original shirt/collar: unequal wings and curved folded seam.
t+=p('M56 39.2Q53.3 40 54.3 45.8Q61 53.9 78.8 63.4L92.5 70.9L98 103.8L105.7 87.9L107.8 60.4Q103.9 57.6 100.1 60.6L95.4 64Q73.7 55.1 57 43.8Z','#d8dcd7',INK,.75)
t+=p('M56 40.8Q54.2 44.7 59.3 48.8Q71 57.5 92 66.3L88.1 79.1Q74.6 61.7 59.1 51.8Q53.6 48 53.8 44Z','#e5e7df',INK,.65)
t+=p('M55 44.8Q61.7 52.4 76.6 60.6Q86.5 66.6 89.8 71.6L87.9 78Q76.2 62.9 59.7 53.2L54.4 48Z','#b4c0bc')
t+=p('M100.3 61.1Q104.1 59.4 106.4 61L106.2 76Q100.2 71.5 95.1 66.4Z','#e3e5dd',INK,.65)
t+=p('M104.6 61.2L106.4 61L106.1 73.8L102.5 70.4Z','#adb9b6')
t+=p('M88.3 80L93.8 85L94 107L89.9 106Q87.8 93.7 86.4 82.4Z','#f0eee4')
t+=p('M100.6 81L104.8 76.2L107.6 81.6Q106.5 92.2 102 100.4L98.7 106Z','#d4dcd5')
# Tie is red cloth: one broad face and one narrow curved side, no hard jewel stripes.
t+=p('M96.2 66.7L102.9 72Q99.2 77.4 98.7 84.4Q95.5 85.5 91.5 84.4L88.9 79.8Z','#b8151d','#621218',.6)
t+=p('M96.3 68.4L100.7 72Q96.6 77.5 95.5 83.7L91.7 83.5L90.3 80Z','#d32328')
t+=p('M91.9 84.4Q95.5 85 98.7 84.4Q99.2 95.9 102.4 103.3Q101.6 111.6 95.7 121.4L88.6 131.2Q89.3 118.7 89.8 105.9Z','#c41b22','#64151b',.6)
t+=p('M97.4 87.2Q98.2 96.3 100.9 104Q100 110.6 96.9 115.6L93.8 121.9Q96.8 111.8 96.7 106.2Q95.2 97.8 95.8 87.8Z','#ad111b')
# Broad near lapel and its notch follow the original, without a bright border strip.
left='M54.2 43.6Q48.8 43.4 43.5 47.9Q48.4 54.2 50.5 61.2Q53.6 69.3 52.5 80L59.8 73.4Q60.1 79.4 56.5 85.2L51 94.9Q69.6 111.5 89.2 134.3Q88.4 113.5 83.5 95.8Q78.4 78 64.9 60.3L57.1 49.2Z'
t+=p(left,'#35393a',INK,.85)
t+=p('M48.3 49.5Q52.2 55.6 54.6 62.5Q58.7 72.3 57.1 77.8L59.7 73.7Q61.4 79.2 56.7 85.8L52.6 94.3Q65 104.7 77.6 120.1L85 129Q77.8 116.1 68.9 106.4Q59.8 96.4 57.8 95L61.6 86.3Q65.3 77.2 62 68.4Q58.2 59.2 52.1 52.5Z','#303435')
t+=l('M52.9 62.3Q55.6 69.1 54.7 75.1','#434747',.5)
# Far lapel retains the sharp textile fold but not a metallic rim.
right='M108.9 61.5Q115.3 64.4 119.4 69.4L122.1 74.7L111.1 72.9Q121 84.1 127.6 95.1Q108.7 114.2 90.2 134.1Q98.6 116.1 103.6 101.8Q109 85.8 108.9 61.5Z'
t+=p(right,'#393d3e',INK,.8)
t+=p('M110.2 64.8Q116 67.5 119.3 72.6L110.3 71.7L109.4 74.5Q112 79.4 116.2 84.8Q122.1 92.1 124.8 95.1L106.1 114L95.7 126Q102.8 116 109.3 106.8L120.7 94.9Q111.9 83.2 109.1 78.7Z','#343839')
# Compression wrinkles are short and terminate at tension points.
t+=p('M42.1 125.8Q48.9 134.5 50.6 146.1Q48.2 143.1 47.1 137.8L43.2 132.1Z','#202425')
t+=p('M77.1 145.6Q81.4 149.1 82.4 157.7L79.7 170.2Q81.1 156.7 77.1 145.6Z','#242829')
t+=p('M47.6 202.1Q43.1 211.8 41.2 225L36.7 238Q38.6 224.1 43.4 214Z','#242829')
t+=p('M112.9 177.8Q110.7 190.6 113.2 201.4Q109 195.8 109.9 189.8Z','#232728')
# Front fastening and hem: real coat edges, modest dark fabric-covered buttons.
t+=l('M89.8 133.7Q88.2 147.6 88.2 164.2L86.7 190.7Q86.4 208.6 80.3 225.5L74.4 242.9',INK,.9)
t+=l('M86.4 210.5Q89.6 222.8 95.3 236L99.2 245.2','#171b1c',.8)
t+=p('M85.7 212.2Q88 219.1 89.7 223.5L81.7 223.8Z','#313536',INK,.6)
for x,y,rx,ry in [(94.2,145,2.9,3.1),(91.5,190.6,3.0,3.15)]:
 t+=f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="#343839" stroke="#15191a" stroke-width=".8"/>'
 t+=f'<path d="M{x-rx*.65} {y-.8}Q{x} {y-2} {x+rx*.65} {y-.8}" fill="none" stroke="#4a4e4e" stroke-width=".45"/>'
# Smooth external coat edge; no neck insertion stroke, no all-edge mechanical ring.
t+=l('M55.2 39.3Q51.8 39.8 53.9 45.9Q45 42.1 37.8 47.2Q17.4 50 6.9 65.2Q-1.1 72.7 1.1 84.8Q5.1 105.2 15.4 124.3Q22.5 153.5 26.4 181.8Q27.5 189.7 25.4 200.4Q22.3 223.4 14.3 240Q39.7 246.9 74.4 243.9M100.1 245Q118 247 132.5 241.5Q125.9 221.8 121.4 195.8Q121 183.6 123.3 168Q128.3 145.7 131.4 118.5Q134.4 92.6 133.6 77.5Q124.1 67.4 109 61.3','#121617',.85)
A['589']={'body':t,'skipAutoOutline':True,'scope':'Original lapel/collar/tie and coat skirt tailoring; low-contrast charcoal wool, curved broad drape, small structural creases.'}
(R/'source/core-r2.json').write_text(json.dumps(A,ensure_ascii=False,indent=2))
print('Wrote R2 head and suit torso in source-atlas coordinates.')
