from pathlib import Path
from xml.etree import ElementTree as ET
import json,re,hashlib
R=Path(__file__).resolve().parents[1];out=[]
for p in sorted((R/'parts').glob('*.svg')):
 root=ET.parse(p).getroot();text=p.read_text();ids=[x.attrib['id'] for x in root.iter() if 'id' in x.attrib];refs=re.findall(r'url\(#([^\)]+)\)',text)+re.findall(r'href="#([^"]+)"',text);tags=[x.tag.split('}')[-1] for x in root.iter()]
 assert len(ids)==len(set(ids)),p
 assert set(refs)<=set(ids),(p,set(refs)-set(ids))
 allowed_soil={'bitmap-1611.svg','shape-1612.svg','background-1613.svg'}
 if p.name not in allowed_soil:assert 'image' not in tags,p
 for e in root.iter():
  if e.tag.split('}')[-1]=='image':assert any(str(v).startswith('data:image/png;base64,') for k,v in e.attrib.items() if k.endswith('href')),p
 out.append({'path':str(p.relative_to(R)),'elements':len(tags),'paths':tags.count('path'),'filters':tags.count('filter'),'images':tags.count('image'),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
reuse={p.name:p.read_bytes()==(R/'parts'/p.name).read_bytes() for p in (R/'reference/stage1-crate').glob('*.svg')};assert all(reuse.values())
(R/'qa/vector-validation.json').write_text(json.dumps({'assets':out,'crateUnchanged':reuse,'note':'Procedural soil texture is intentionally embedded in soil/composite SVG; mechanical assets remain vector. Baked PNG supplied; no runtime guarantee.'},indent=2));print('Verified',len(out),'SVG files and',len(reuse),'unchanged crate assets')
