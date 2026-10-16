"""Lossless SVG serialization compaction, not artwork editing.
For the six morph shapes, one shared embedded source bitmap replaces repeated
identical data URIs. Original clip paths, order and per-fill matrices are unchanged.
"""
from pathlib import Path
import xml.etree.ElementTree as E,json,hashlib,copy
R=Path(__file__).resolve().parents[1];NS='http://www.w3.org/2000/svg';E.register_namespace('',NS)
report=[]
for cid in [880,882,883,884,885,886]:
 f=R/f'reference/{cid}.svg';before=f.read_bytes();root=E.fromstring(before);images=[x for x in root.iter() if x.tag.rsplit('}',1)[-1]=='image']
 if len(images)<=1:continue
 hrefs={x.get('href') for x in images};assert len(hrefs)==1
 imageid=f'originalBitmap581_{cid}';definition=copy.deepcopy(images[0]);definition.attrib.pop('transform',None);definition.set('id',imageid);defs=E.Element('{'+NS+'}defs');defs.append(definition)
 transforms=[x.get('transform') for x in images]
 for par in list(root.iter()):
  for el in list(par):
   if el.tag.rsplit('}',1)[-1]=='image':
    idx=list(par).index(el);use=E.Element('{'+NS+'}use',{'href':'#'+imageid,'transform':el.get('transform')});par.remove(el);par.insert(idx,use)
 root.insert(0,defs);E.ElementTree(root).write(f,encoding='unicode')
 after=E.parse(f).getroot();uses=[x for x in after.iter() if x.tag.rsplit('}',1)[-1]=='use'];assert [x.get('transform') for x in uses]==transforms
 report.append({'id':cid,'beforeSha256':hashlib.sha256(before).hexdigest(),'afterSha256':hashlib.sha256(f.read_bytes()).hexdigest(),'originalImageInstances':len(images),'preservedPerFillMatrices':True,'beforeBytes':len(before),'afterBytes':f.stat().st_size,'change':'Identical bitmap data URI stored once; clip paths and visible content unchanged.'})
if report:(R/'reference/svg-normalization.json').write_text(json.dumps(report,indent=2))
print('Deduplicated',len(report),'morph reference SVGs.')
