from pathlib import Path
import sys,json
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).parent));from svg_native import assemble,render
R=Path(__file__).resolve().parents[1];vb=[-3.45,-5.85,800,452]
old=[{'path':R/'reference/background-1582.svg','matrix':[1,0,0,1,673.5,207.1]}]
new=[{'path':R/'parts/background-1581.svg','matrix':[1,0,0,1,673.5,207.1]}]
for cid in [1410,1411]:new.append({'path':R/f'parts/prop-{cid}.svg','matrix':[1,0,0,1,53.2,27.45]})
for cid,x,y,depth in [(1591,133.8,202.4,152),(1591,249.8,430.9,160),(1442,75.1,427.35,212)]:
 old.append({'path':R/f'reference/a1-prop-{cid}.svg','matrix':[1,0,0,1,x,y]});new.append({'path':R/f'parts/prop-{cid}.svg','matrix':[1,0,0,1,x,y]})
for label,ls in [('original',old),('r4',new)]:assemble(vb,ls,R/f'previews/scene-{label}.svg');render(R/f'previews/scene-{label}.svg',1600)
out=Image.new('RGB',(2400,720),'#deded8');d=ImageDraw.Draw(out)
for i,name in enumerate(['original','r4']):
 im=Image.open(R/f'previews/scene-{name}.png').convert('RGBA').resize((1200,678));out.paste(im,(1200*i,42),im);d.text((1200*i+20,15),['ORIGINAL A1 ENVIRONMENT / FIXED MAP CAMERA','R4 HYBRID ENVIRONMENT / SAME MAP CAMERA'][i],fill='#18221b')
out.save(R/'previews/scene-original-r4.png')
(R/'source/scene-layout.json').write_text(json.dumps({'root':1592,'root_label':'a1','viewBox':vb,'background_placement':[673.5,207.1],'lamp_world':[53.2,27.45],'turrets':[[133.8,202.4],[249.8,430.9]],'crate':[75.1,427.35],'characters':'omitted equally from both environment comparisons; unchanged','glows':'separate optional layer; source 1411 retained'},indent=2))
