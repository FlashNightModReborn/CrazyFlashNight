from pathlib import Path
from svg_native import render
import json
from xml.etree import ElementTree as ET
R=Path(__file__).resolve().parents[1];B=R/'baked';B.mkdir(exist_ok=True);out=[]
for p in sorted((R/'parts').glob('bitmap-*.svg')):
 vb=list(map(float,ET.parse(p).getroot().attrib['viewBox'].split()));dest=B/(p.stem+'.png');render(p,round(vb[2]),dest);out.append({'bitmapId':int(p.stem.split('-')[1]),'svg':str(p.relative_to(R)),'png':str(dest.relative_to(R)),'originalNativePixels':[int(vb[2]),int(vb[3])],'registration':'replace original bitmap content; preserve original bitmap-fill matrix and clip'})
render(R/'parts/background-1613.svg',1331,B/'background-1613.png')
render(R/'parts/shape-1598.svg',1441,B/'city-shape-1598.png')
(B/'registration.json').write_text(json.dumps({'bitmapReplacements':out,'optionalFlattenedBackground':{'png':'background-1613.png','nativeViewBox':[-716.95,-183,1330.9,469.8],'pixelSize':[1331,470],'worldPlacement':[673.5,207.1],'note':'Keep native viewBox scale; excludes root sky/city and interactive crate. Do not stretch to logical1250x450.'},'optionalCityLayer':{'png':'city-shape-1598.png','nativeViewBox':[0,109,1441.4,66.45],'note':'separate root parallax layer; use source viewBox scale, not rounded PNG width'},'sky':'bitmap-1595.png fixed screen600x187','runtime':'Not installed or runtime tested. SVG filters intentionally baked to PNG; no Flash SVG filter support/performance guarantee.'},indent=2))
