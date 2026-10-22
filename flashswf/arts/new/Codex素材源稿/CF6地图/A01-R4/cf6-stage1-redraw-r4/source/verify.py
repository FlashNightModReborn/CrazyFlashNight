from pathlib import Path
from xml.etree import ElementTree as ET
import json,re,hashlib
R=Path(__file__).resolve().parents[1];out=[]
for p in sorted((R/'parts').glob('*.svg')):
 root=ET.parse(p).getroot();ids=[e.attrib['id'] for e in root.iter() if 'id' in e.attrib];text=p.read_text();refs=re.findall(r'url\(#([^\)]+)\)',text);tags=[e.tag.split('}')[-1] for e in root.iter()]
 assert len(ids)==len(set(ids)),p
 assert all(x in ids for x in refs),(p,set(refs)-set(ids))
 if p.name not in {'01-night-soil.svg','background-1581.svg'}:assert 'image' not in tags,p
 for e in root.iter():
  if e.tag.split('}')[-1]=='image':assert any(str(v).startswith('data:image/png;base64,') for k,v in e.attrib.items() if k.endswith('href')),p
 out.append({'path':str(p.relative_to(R)),'viewBox':root.attrib.get('viewBox'),'elements':len(tags),'images':tags.count('image'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(R/'qa/vector-validation.json').write_text(json.dumps(out,indent=2));print('Validated',len(out),'SVG parts; soil texture embedding allowed only in soil/composite, no duplicate ids or missing refs.')
