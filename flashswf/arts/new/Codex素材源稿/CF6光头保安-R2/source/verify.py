"""Structural/registration/identity audit; this is not Flash/runtime validation."""
from pathlib import Path
import json,re,xml.etree.ElementTree as E,hashlib
from collections import Counter
R=Path(__file__).resolve().parents[1];AD=json.loads((R/'qa/adaptation-build.json').read_text());checks=[];assets=[]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for a in AD:
 cid=a['id'];ref=R/f'reference/{cid}.svg';dst=R/a['file'];orig=E.parse(ref).getroot();root=E.parse(dst).getroot()
 metrics={k:[float(x) for x in orig.get(k).split()] for k in ['viewBox','width','height']}
 for k in metrics:assert [float(x) for x in root.get(k).split()]==metrics[k],(cid,k,root.get(k),orig.get(k))
 ids=[e.get('id') for e in root.iter() if e.get('id')];assert len(set(ids))==len(ids),(cid,'duplicate id')
 s=dst.read_text();refs=re.findall(r'url\(#([^)]*)\)',s)+re.findall(r'(?:href|xlink:href)="#([^"]*)"',s);assert set(refs)<=set(ids),(cid,set(refs)-set(ids))
 kinds=Counter(e.tag.rsplit('}',1)[-1] for e in root.iter());redrawn=a['class'] in ['redrawn-live-body','redrawn-atlas-projected-original-crops']
 if redrawn:
  assert not kinds['image'] and not kinds['filter'],(cid,kinds)
  if a['class']=='redrawn-live-body' and cid!=590:assert not kinds['linearGradient'] and not kinds['radialGradient'],(cid,kinds)
  if cid==590:assert kinds['radialGradient']==2 and not kinds['linearGradient'],(cid,kinds)
 untouched=a['class'].startswith('original-')
 if untouched:assert ref.read_bytes()==dst.read_bytes(),(cid,'original changed')
 checks.append({'id':cid,'dimensionsAndViewBoxPreserved':True,'idsUnique':True,'referencesResolve':True,'pureVectorNoRasterOrFilter':redrawn,'skinGradients':kinds['radialGradient'] if redrawn else 0,'unchangedOriginal':untouched})
 assets.append({**a,'viewBox':metrics['viewBox'],'exportWidth':metrics['width'][0],'exportHeight':metrics['height'][0],'sha256':sha(dst),'originalSha256':sha(ref),'svgElements':dict(kinds)})
assert len(AD)==110
source=json.loads((R/'reference/manifest.json').read_text())
result={'title':'CF6 bald guard 612 / 888 hard-edge vector redraw R2','sourceSwfSha256':source['sourceSwfSha256'],'sourceRoots':[612,888],'revision':'R2 fidelity refinement after frozen R1','artMaterialPolicy':{'cloth':'curved hard-edge vector planes, no gradients','leather':'rounded volumes, restrained hard-edge planes','skin':'two controlled radial gradients for connected skull and cheek volume','noNewRasterOrFilter':True},'authoredBodyParts':10,'authoredProjectionShapes':9,'projectedFills':181,'reusedCloneParts':13,'cloneVariant':'stabilized archive, historical approved SVG, not current native XFL equivalence','classes':dict(Counter(a['class'] for a in AD)),'assets':assets,'runtimeVerified':False,'productionModified':False}
(R/'asset-manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));(R/'qa/structural-checks.json').write_text(json.dumps({'passed':len(checks),'checks':checks},indent=2));print('PASS',len(checks),'shapes:',result['classes'])
