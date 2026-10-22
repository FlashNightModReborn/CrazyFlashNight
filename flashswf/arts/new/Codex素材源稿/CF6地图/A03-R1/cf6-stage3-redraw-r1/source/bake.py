from pathlib import Path
from svg_native import render
import json
R=Path(__file__).resolve().parents[1];B=R/'baked';B.mkdir(exist_ok=True)
items=[]
for i,w,h in [(1701,306,251),(1702,228,197),(1704,69,94),(1708,143,179),(1717,101,179),(1724,105,178)]:
 render(R/f'parts/bitmap-{i}.svg',w,B/f'bitmap-{i}.png');items.append({'id':i,'png':f'bitmap-{i}.png','size':[w,h],'originalBitmapFillMatrices':'unchanged'})
render(R/'parts/background-1706.svg',1509,B/'background-1706.png');render(R/'parts/foreground-1727.svg',1212,B/'foreground-1727.png')
(B/'registration.json').write_text(json.dumps({'bitmapReplacements':items,'background':{'png':'background-1706.png','viewBox':[-676.95,-240.75,1508.95,483.55],'worldPlacement':[673.5,207.1],'includesWallLightsAndOriginalGlow':True},'foreground':{'png':'foreground-1727.png','viewBox':[111,.55,1211.95,178.75],'cameraParallax':1.2},'worldLogicalSize':[1300,450],'viewport':[600,350],'initialCodeDerivedWorld':[0,-77.2],'door1714':'9 original frames/matrices and clipDepth retained; no game execution','exit1720':'174 original frames incl unchanged player and masks; static samples only','runtime':'not imported; no realtime SVG or animation acceptance; use original bitmap fill pipeline where possible'},indent=2))
print('Baked six original-size material replacements and independent back/front layers')
