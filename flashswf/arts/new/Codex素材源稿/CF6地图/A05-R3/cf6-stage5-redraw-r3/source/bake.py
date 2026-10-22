from pathlib import Path
from svg_native import render
import json
R=Path(__file__).resolve().parents[1];B=R/'baked';B.mkdir(exist_ok=True)
items=[]
for i,w,h in [(1701,306,251),(1702,228,197),(1704,69,94),(1717,101,179),(1724,105,178),(1740,65,211),(1742,901,145),(1743,72,89),(1746,232,176)]:
 render(R/f'parts/bitmap-{i}.svg',w,B/f'bitmap-{i}.png');items.append({'id':i,'png':f'bitmap-{i}.png','size':[w,h],'originalBitmapFillMatrices':'unchanged'})
render(R/'parts/background-1745.svg',1517,B/'background-1745.png');render(R/'parts/foreground-1727.svg',1212,B/'foreground-1727.png')
(B/'registration.json').write_text(json.dumps({'bitmapReplacements':items,'background':{'png':'background-1745.png','viewBox':[-684.75,-240.5,1516.75,483.3],'worldPlacement':[673.5,207.1],'includesWallLightsAndOriginalGlow':True},'foreground':{'png':'foreground-1727.png','viewBox':[111,.55,1211.95,178.75],'cameraParallax':1.2},'worldLogicalSize':[1300,450],'viewport':[600,350],'authoredPlayerLoadFormulaOnly':[0,-77.2],'arrivalOverridesRealPlayer':[1190.45,231.4],'initialRuntimeCamera':'unverified; arrival scripts change player position' ,'grandDoor1750':'40 original frames, original depth, six static samples incl unchanged character','arrival1729':'174 original frames incl unchanged player and masks; seven static samples','crate1442':'approved material reused through original fragment clips; six static samples','runtime':'not imported; no realtime SVG or animation acceptance; use original bitmap fill pipeline where possible'},indent=2))
print('Baked nine original-size material replacements and independent back/front layers')
