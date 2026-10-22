from pathlib import Path
import xml.etree.ElementTree as ET,json,hashlib,re
R=Path(__file__).resolve().parents[1];rows=[]
for p in sorted((R/'parts').glob('*.svg')):
 s=p.read_text();root=ET.fromstring(s);assert not re.search(r'(?:href|src)=["\'](?:https?:|file:|/workspace)',s)
 rows.append({'file':str(p.relative_to(R)),'viewBox':root.get('viewBox'),'embeddedImages':s.count('<image')+s.count(':image'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for p in (R/'reference/reused').glob('*.svg'):assert p.read_bytes()==(R/'parts'/p.name).read_bytes()
(R/'qa/source-validation.json').write_text(json.dumps({'svg':rows,'reusedSkyUnchanged':True,'runtimeTested':False},indent=2))
print('Offline SVG parse/reuse source validation passed',len(rows))
