"""Real key-frame colour renders plus all-49-phase, three-camera alpha audit.

The all-phase contact sheet uses Inkscape-rasterized native shape alpha masks,
then original display-list matrices. This avoids 147 repeated RGB texture parses.
It is an alpha-only composition check, not a replacement for colour scene QA.
"""
from pathlib import Path
import json,sys,base64,io,hashlib
import numpy as np
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];Q=R/'qa'
sys.path.insert(0,str(R/'source'))
from svg_native import render,write_part,inner
src=(R/'source/assemble_scene.py').read_text();ns={'__file__':str(R/'source/assemble_scene.py')}
exec(compile(src.split("font=ImageFont.truetype")[0],str(R/'source/assemble_scene.py'),'exec'),ns)
node=ns['node'];N=ns['NODES'];audit=Q/'a7-coverage-audit';audit.mkdir(exist_ok=True)
# Colour verification uses the actual material SVGs and unmodified matrices.
key=[];views=[('author',0,0),('middle',-275,-50),('right',-550,-100)]
sky='<g transform="translate(400 -16.5)"><g transform="translate(-400 93)">'+inner(R/'parts/sky-1753-extension.svg','coverageLower')+'</g>'+node(1754,mode='new')+'</g>'
for f in [1,13,25,37,49]:
 bg=node(1791,f,'new');env='<g transform="matrix(1.000030517578125 0 0 1 0 0)"><g transform="translate(632.35 250.75)">'+bg+'</g></g>'
 for name,x,y in views:
  p=write_part(audit/f'phase-{f}-{name}.svg',[0,0,600,350],sky+f'<g transform="translate({x} {y})">'+env+'</g>')
  render(p,600)
  a=np.array(Image.open(p.with_suffix('.png')).convert('RGBA'))[:,:,3]
  key.append({'frame':f,'camera':name,'size':[600,350],'fully_transparent_pixels':int(np.count_nonzero(a==0)),'partially_transparent_pixels':int(np.count_nonzero(a<255))})
 print('Actual colour key phase',f,'rendered',flush=True)
# The 49 frame background contains only four static leaf shapes.
leafs=sorted({v['id']for fr in N['1791']['frames']for v in fr.values()})
defs=[]
for sid in leafs:
 vb=N[str(sid)]['viewBox'];p=R/f'parts/shape-{sid}.svg';dst=audit/f'alpha-shape-{sid}.png';render(p,round(vb[2]*4),dst)
 im=Image.open(dst).convert('RGBA');alpha=im.getchannel('A');white=Image.new('RGBA',im.size,'white');white.putalpha(alpha);buf=io.BytesIO();white.save(buf,format='PNG');data=base64.b64encode(buf.getvalue()).decode()
 defs.append(f'<g id="shape{sid}"><image x="{vb[0]}" y="{vb[1]}" width="{vb[2]}" height="{vb[3]}" href="data:image/png;base64,{data}"/></g>')
body='<defs>'+''.join(defs)+'</defs>';panels=[];idx=0
for f,fr in enumerate(N['1791']['frames'],1):
 for name,cx,cy in views:
  col=idx%7;row=idx//7;x=col*600;y=row*350;clip=f'v{idx}'
  body+=f'<clipPath id="{clip}"><rect x="0" y="0" width="600" height="350"/></clipPath><g transform="translate({x} {y})"><g clip-path="url(#{clip})"><rect x="0" y="-110" width="800" height="253" fill="white"/>'
  body+=f'<g transform="translate({cx} {cy})"><g transform="matrix(1.000030517578125 0 0 1 0 0)"><g transform="translate(632.35 250.75)">'
  for d,o in sorted(fr.items(),key=lambda t:int(t[0])):
   m=' '.join(map(str,o['matrix']));body+=f'<use href="#shape{o["id"]}" transform="matrix({m})"/>'
  body+='</g></g></g></g></g>';panels.append((f,name,col,row));idx+=1
# Bound renderer memory with seven phase batches, each 21 small viewports.
from xml.etree import ElementTree as ET
root=ET.fromstring('<svg xmlns="http://www.w3.org/2000/svg">'+body+'</svg>');children=list(root)
definition=ET.tostring(children[0],encoding='unicode');pairs=[children[1+k*2:3+k*2] for k in range(147)]
allrows=[]
for batch in range(7):
 start=batch*21;end=start+21;batch_body=definition+f'<g transform="translate(0 {-batch*1050})">'+''.join(ET.tostring(c,encoding='unicode')for pair in pairs[start:end]for c in pair)+'</g>'
 p=write_part(audit/f'alpha-batch-{batch+1}.svg',[0,0,4200,1050],batch_body);render(p,2100)
 a=np.array(Image.open(p.with_suffix('.png')).convert('RGBA'))[:,:,3]
 for k,(f,name,col,row) in enumerate(panels[start:end]):
  yy=(row-batch*3)*175;aa=a[yy:yy+175,col*300:(col+1)*300]
  allrows.append({'frame':f,'camera':name,'size':[300,175],'fully_transparent_pixels':int(np.count_nonzero(aa==0)),'partially_transparent_pixels':int(np.count_nonzero(aa<255))})
 print('Alpha phase batch',batch+1,'rendered',flush=True)
res={'original_sky_logical_bounds':[0,-110,800,77],'decorative_extension_logical_bounds':[0,76.5,800,143],'river_top_y':139.65,'unchanged':'Original bitmap1753 and shape1754 dimensions/clip, world and root display lists, camera matrices, all collision data. A6 needs no extension and its three actual views remain alpha-hole free.','actual_colour_keyframes':key,'all_49_phases_three_cameras_low_resolution_alpha':allrows,'alpha_method':'Original shape SVGs rendered at 4x alpha; original 49 display lists and camera/world matrices composited in seven bounded-memory Inkscape contact sheets at 0.5x. Actual full-colour keyframes separately rendered at 1x.'}
(audit/'coverage-validation.json').write_text(json.dumps(res,indent=2));print('Final alpha audit',sum(v['fully_transparent_pixels']for v in allrows),'fully transparent pixels; actual key colour',sum(v['fully_transparent_pixels']for v in key),flush=True)
