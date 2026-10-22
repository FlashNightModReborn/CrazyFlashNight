"""QA-only original/new material assembly, using original placement matrices.

This does not produce replacement artwork. Original RGB is embedded only into
this explicitly labelled comparison. The production replacement parts contain
new artwork plus the original alpha-only registration contract.
"""
from pathlib import Path
import json,base64
from svg_native import write_part,render,inner
R=Path(__file__).resolve().parents[1]
IDS=[1231,1957,1958,1962,1964,1965,1966]
def main():
 shapes=json.loads((R/'reference/industrial-source-shapes.json').read_text())
 shapes=[s for s in shapes if s['id'] in [1959,1963,1967]]
 defs=[]
 for n in IDS:
  defs.append(f'<g id="new_{n}">'+inner(R/f'parts/bitmap-{n}.svg',f'm{n}')+'</g>')
  from PIL import Image
  w,h=Image.open(R/f'reference/{n}.png').size
  data=base64.b64encode((R/f'reference/{n}.png').read_bytes()).decode()
  defs.append(f'<image id="old_{n}" width="{w}" height="{h}" href="data:image/png;base64,{data}"/>')
 bodies=[]
 for typ,y in [('old',30),('new',495)]:
  s=f'<g transform="translate(702 {209+y})">'
  for shape in shapes:
   for j,fill in enumerate(shape['fills']):
    n=fill.get('bitmapId')
    if n not in IDS:continue
    id=f'{typ}_{shape["id"]}_{j}';d=fill['path'];m=' '.join(str(x) for x in fill['matrix'])
    defs.append(f'<clipPath id="{id}"><path d="{d}"/></clipPath>')
    s+=f'<g clip-path="url(#{id})"><g transform="matrix({m})"><use href="#{typ}_{n}"/></g></g>'
  s+='</g>';bodies.append(s)
 body='<defs>'+''.join(defs)+'</defs><rect width="1733" height="945" fill="#293135"/>'+''.join(bodies)
 body+='<g fill="#fff" font-size="16" font-family="sans-serif"><text x="10" y="20">ORIGINAL / shared industrial material placements</text><text x="10" y="485">NEW / original transforms, new material artwork</text></g>'
 p=write_part(R/'previews/industrial-context-compare.svg',[0,0,1733,945],body)
 render(p,1733,R/'previews/industrial-context-compare.png')
if __name__=='__main__':main()
