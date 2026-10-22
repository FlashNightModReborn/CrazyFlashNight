"""Native-size PNG option for the static JPEG1580 replacement; vector editing source retained."""
from pathlib import Path
from svg_native import assemble,render
import json
R=Path(__file__).resolve().parents[1];B=R/'baked';B.mkdir(exist_ok=True)
render(R/'parts/background-1581.svg',800,B/'background-1580-r4-800x452.png')
names=['01-night-soil','02-wreck-pile','03-metal-floor','04-wall','05-markings-lights']
assemble([0,0,800,452],[{'path':R/f'parts/{n}.svg'} for n in names],B/'background-without-glow.svg');render(B/'background-without-glow.svg',800,B/'background-1580-r4-without-glow-800x452.png')
render(R/'parts/06-optional-light-glow.svg',800,B/'cyan-glow-800x452.png')
(B/'registration.json').write_text(json.dumps({'originalBitmap':1580,'replacementBitmapSize':[800,452],'shape1581ViewBox':[-676.95,-212.95,800,452],'originalBitmapToShapeMatrix':[1,0,0,1,-676.95,-212.95],'yellowLamp1410':'separate vector, not included in baked background','yellowGlow1411':'separate preserved vector','cyanGlow':'included in default bitmap; alternative no-glow background and transparent glow image provided','runtimeStatus':'not imported into Flash/game; no performance guarantee'},indent=2))
