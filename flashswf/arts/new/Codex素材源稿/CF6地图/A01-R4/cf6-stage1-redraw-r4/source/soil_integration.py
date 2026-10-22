"""Stage1 shared procedural soil integration; preserves the R3 material boundary and lamp layers."""
from pathlib import Path
from xml.etree import ElementTree as ET
import base64,json
from soil_material import generate
from svg_native import write_part
R=Path(__file__).resolve().parents[1]
def apply():
 p=R/'parts/01-night-soil.svg';root=ET.parse(p).getroot();kept=[]
 # Retain original R3 night/star elements, replace only its old earth geometry.
 for e in root:
  if e.tag.split('}')[-1]=='path' and e.attrib.get('d','').startswith('M0 162'):break
  kept.append(ET.tostring(e,encoding='unicode'))
 T=R/'textures';T.mkdir(exist_ok=True);dest=T/'soil-stage1-master.png'
 im=generate((1600,904),seed=1580,profile='stage1');im.save(dest)
 b64=base64.b64encode(dest.read_bytes()).decode()
 earth='M0 162 L285 161 L360 177 L508 166 L645 160 L800 155 V452H0Z'
 s=''.join(kept)+'<defs><clipPath id="r4earth"><path d="'+earth+'"/></clipPath></defs><g id="r4proceduralsoil" clip-path="url(#r4earth)"><image x="0" y="0" width="800" height="452" href="data:image/png;base64,'+b64+'"/></g>'
 write_part(p,[0,0,800,452],s)
 (R/'qa/soil-integration.json').write_text(json.dumps({'soilProfile':'stage1','masterPixels':[1600,904],'originalCoordinates':[800,452],'seed':1580,'changedLayer':'01-night-soil','preservedLayers':['02-wreck-pile','03-metal-floor','04-wall','05-markings-lights','06-optional-light-glow'],'method':'procedural texture with editable generator, embedded self-contained PNG in soil SVG; not all-vector soil'},indent=2))
