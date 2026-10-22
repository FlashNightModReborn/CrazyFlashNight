from pathlib import Path
from xml.etree import ElementTree as E
import re,json,hashlib
R=Path(__file__).resolve().parents[1];rows=[]
for p in sorted((R/'parts').glob('*.svg')):
 s=p.read_text();r=E.fromstring(s);ids=[e.attrib['id'] for e in r.iter() if 'id' in e.attrib];assert len(ids)==len(set(ids)),p
 refs=re.findall(r'url\(#([^\)]+)\)',s)+re.findall(r'href="#([^"]+)"',s);assert not(set(refs)-set(ids)),(p,set(refs)-set(ids))
 imgs=[e for e in r.iter() if e.tag.endswith('}image')]
 for e in imgs:assert any(v.startswith('data:image/png;base64,') for k,v in e.attrib.items() if k.endswith('href')),p
 if imgs:assert p.name in ['bitmap-1701.svg','bitmap-1702.svg','shape-1703.svg','background-1706.svg'],p
 rows.append({'file':p.name,'viewBox':r.attrib['viewBox'],'paths':sum(e.tag.endswith('}path') for e in r.iter()),'embeddedImages':len(imgs),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(R/'qa/source-validation.json').write_text(json.dumps(rows,indent=2));print('Validated',len(rows),'hybrid SVG files; all references local, IDs unique')
