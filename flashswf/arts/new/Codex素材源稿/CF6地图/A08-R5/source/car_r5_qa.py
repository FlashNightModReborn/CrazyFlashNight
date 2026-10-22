from pathlib import Path
import json,xml.etree.ElementTree as ET
from PIL import Image,ImageDraw,ImageFont
import numpy as np
from svg_native import render
R=Path(__file__).resolve().parents[1];P=R/'previews';Q=R/'qa'
font=ImageFont.truetype(str(R/'reference/fonts/DejaVuSans.ttf'),20)
paths=[R/'reference/1823.png',R/'reference/car-r4-review.png',P/'vehicles-props-1823-r5-4x.png']
for name,box,scale in [('whole',(0,0,411,144),3),('cockpit',(180,0,390,78),5)]:
 w,h=box[2]-box[0],box[3]-box[1];out=Image.new('RGB',(w*scale,(h*scale+38)*3),'#bec5c9');d=ImageDraw.Draw(out)
 for i,(p,lbl) in enumerate(zip(paths,['ORIGINAL 1823','R4','R5 / LOWER WINDSHIELD + MATCHING GUN SUPPORTS'])):
  im=Image.open(p).convert('RGBA');f=im.width/411;im=im.crop(tuple(round(x*f) for x in box)).resize((w*scale,h*scale),Image.Resampling.LANCZOS);out.paste(im,(0,i*(h*scale+38)+38),im);d.text((9,i*(h*scale+38)+8),lbl,fill='#182631',font=font)
 out.save(P/f'car-r5-{name}-original-r4-r5.png')
# Individual editable cockpit groups are retained in production SVG.
base=ET.parse(R/'parts/bitmap-1823.svg')
for role,hide in [('interior',{'cockpit-glass-r5'}),('glass',{'cockpit-interior-r5'}),('composite',set())]:
 tree=ET.parse(R/'parts/bitmap-1823.svg');root=tree.getroot()
 # Only cockpit relevant defs + groups; no full car behind the layer sample.
 keep={'cockpit-interior-r5','cockpit-glass-r5','cockpit-frame-r5'}-hide
 found=[n for n in root.iter() if n.get('id') in keep]
 defs=[n for n in root.iter() if n.tag.endswith('defs')]
 new=ET.Element(root.tag,{'width':'135','height':'51','viewBox':'185 0 135 51'})
 for n in defs+found:new.append(n)
 dest=R/'parts'/f'cockpit-r5-{role}.svg';ET.ElementTree(new).write(dest,encoding='unicode')
 render(dest,1080,P/f'cockpit-r5-{role}.png')
canvas=Image.new('RGB',(1080,3*(408+38)),'#303c44');draw=ImageDraw.Draw(canvas)
for i,(role,label) in enumerate([('interior','1. OPAQUE COCKPIT / SEATS + DASHBOARD'),('glass','2. TRANSLUCENT GLASS / SEPARATE OVERLAY'),('composite','3. COMPOSITED COCKPIT')]):
 y=i*446;draw.text((12,y+8),label,font=font,fill='white');im=Image.open(P/f'cockpit-r5-{role}.png').convert('RGBA');canvas.paste(im,(0,y+38),im)
canvas.save(P/'car-r5-cockpit-layers.png')
a=np.array(Image.open(R/'reference/car-r4-1x-review.png').convert('RGBA'));b=np.array(Image.open(P/'vehicles-props-1823-r5-1x.png').convert('RGBA'))
change=(a!=b).any(2);yy,xx=np.indices(change.shape);allowed=(xx>=160)&(xx<=400)&(yy<=79)
assert int((change&~allowed).sum())==0
svg=(R/'parts/bitmap-1823.svg').read_text();assert svg.index('far-gun-behind-body-r5')<svg.index('car-body-envelope-r3')<svg.index('m134near-project-core')
report={'revision':'R5','canvas':[411,144],'changed_pixels':int(change.sum()),'scope':'cockpit, silver shoulder transition, connected front bonnet and supports; wheels/livery/rear aero unchanged','outside_local_scope':int((change&~allowed).sum()),'glass':'Editable separate fill-opacity .16-.22 overlays over opaque cabin, not background transparency','windshield_anchors':{'previous_front_lower':[311,47],'new_front_lower':[319,60],'new_front_upper':[322,30],'original_basis':'visual estimate on source raster, not recovered vector path'},'gun_order':'far weapon before body; near weapon after body; far translated 4 units down for hidden lower saddle','brace':'Short triangular receiver support attached to gun cradle; not identified as windshield reinforcement','runtimeTested':False,'otherMapsChanged':False}
(Q/'car-r5-local-scope.json').write_text(json.dumps(report,indent=2));print(report)
# Actual compositing order: far gun, car with cockpit/glass, near gun.
from vehicles_props import car,project_m134_r3,gun_cradle_brace_r5
from svg_native import write_part
root=ET.parse(R/'parts/bitmap-1823.svg').getroot()
all_defs=''.join(ET.tostring(n,encoding='unicode') for n in root.iter() if n.tag.endswith('defs'))
full=car()
far='<g transform="translate(0 4)">'+gun_cradle_brace_r5(True)+project_m134_r3(True)+'</g>'
near=gun_cradle_brace_r5(False)+project_m134_r3(False)
# Body only: hide far group and remove the trailing near hardware from generated markup.
body=full.replace('<g id="far-gun-behind-body-r5" transform="translate(0 4)">'+gun_cradle_brace_r5(True)+project_m134_r3(True)+'</g>','').replace(near,'')
layout=Image.new('RGB',(1233,4*(432+40)),'#bac3c8');ld=ImageDraw.Draw(layout)
for idx,(label,node) in enumerate([('1. FAR GUN / BEHIND BODY',all_defs+far),('2. BODY / INTERIOR THEN TRANSLUCENT GLASS',body),('3. NEAR GUN / FRONT OF BODY',all_defs+near),('4. COMPOSITE',full)]):
 dest=P/f'car-r5-draw-order-{idx+1}.svg';write_part(dest,[0,0,411,144],node);render(dest,1233,dest.with_suffix('.png'))
 im=Image.open(dest.with_suffix('.png')).convert('RGBA');layout.paste(im,(0,idx*472+40),im);ld.text((12,idx*472+10),label,font=font,fill='#182936')
layout.save(P/'car-r5-draw-order.png')

# Source-raster visual anchors are estimates; overlay uses identical coordinate scale.
anchor=Image.new('RGB',(900,3*503),'#bdc4c9');ad=ImageDraw.Draw(anchor)
anchors=[[(252,8),(322,30),(319,60),(251,32)],[(252,8),(317,37),(311,47),(251,32)],[(252,8),(322,30),(319,60),(251,32)]]
for i,(p,lbl,pts) in enumerate(zip(paths,['ORIGINAL / VISUAL ANCHOR ESTIMATE','R4 / TOO HIGH LOWER CORNER','R5 / LOWERED AND WIDENED FRONT'],anchors)):
 im=Image.open(p).convert('RGBA');f=im.width/411;im=im.crop(tuple(round(x*f) for x in (240,0,390,78))).resize((900,468),Image.Resampling.LANCZOS);anchor.paste(im,(0,i*503+35),im);ad.text((8,i*503+8),lbl,fill='#162835',font=font)
 xy=[((x-240)*6,y*6+i*503+35) for x,y in pts];ad.line(xy+[xy[0]],fill='#e55f47',width=3)
 for x,y in xy:ad.ellipse((x-4,y-4,x+4,y+4),fill='#ffdf85')
anchor.save(P/'car-r5-anchor-overlay.png')
