from evidence_utils import *
from xml.etree import ElementTree as E
import re,sys

revision=sys.argv[1] if len(sys.argv)>1 else None
assert revision is None or re.fullmatch(r'r\d+',revision)

def canonical(element):
 return E.canonicalize(E.tostring(element,encoding='unicode'),strip_text=True).encode('utf8')

result=[]
current_data=read(ROOT/'data/enemy_properties/CF6重制敌人.xml')
for unit,folder,tag in [
 ('headbot','tools/cf6-headbot-assets/evidence/20261017-knockback','敌人-CF6大头机器人'),
 ('bladebot','tools/cf6-bladebot-assets/evidence/20261017-wave','敌人-CF6大刀机器人')]:
 base=ROOT/folder
 integrity=js(base/'integrity.json')
 for row in integrity['files']:assert sha(base/row['path'])==row['sha256'],'Sealed packet drift: '+row['path']
 mapping=next(r for r in js(base/'lossless-mapping.json')['files'] if r['parts'][0]['path'].startswith('frozen-inputs.zip'))
 encoded=b''.join(read(base/r['path']) for r in mapping['parts'])
 archive=gzip.decompress(encoded) if mapping['encoding']=='gzip' else encoded
 assert digest(archive)==mapping['originalSha256'] and len(archive)==mapping['originalBytes']
 with zipfile.ZipFile(io.BytesIO(archive)) as z:
  same=[];exceptions=[]
  summary=js(base/'summary.json')
  for row in summary['sourceBindings']:
   if sha(ROOT/row['path'])==row['sha256']:
    same.append(row['path']);continue
   assert row['path']=='data/enemy_properties/CF6重制敌人.xml','Unexpected bound-input drift: '+row['path']
   before=E.fromstring(z.read(row['path']));after=E.fromstring(current_data)
   assert [c.tag for c in before]==[c.tag for c in after]
   old=canonical(before.find(tag));new=canonical(after.find(tag))
   assert old==new,'Unit panel changed: '+tag
   changed=[c.tag for c in before if canonical(c)!=canonical(after.find(c.tag))]
   assert set(changed)<={'敌人-CF6老头人形','敌人-CF6老头机器人'},changed
   exceptions.append({'path':row['path'],'oldFileSha256':row['sha256'],'currentFileSha256':digest(current_data),
    'unitSubtreeUnchanged':tag,'canonicalSubtreeSha256':digest(new),'changedSubtrees':changed})
 result.append({'unit':unit,'evidence':folder,'sealedIntegrityVerified':True,'identicalBoundInputs':same,
  'semanticExceptions':exceptions,'scope':'Does not relabel the prior complete dataset as current; only unit-specific data equivalence and unchanged other bound inputs are asserted.'})
jput(TMP/('final-integration-'+revision+'.json' if revision else 'final-integration.json'),{'units':result})
print(json.dumps({'units':[{'unit':r['unit'],'identicalBoundInputs':len(r['identicalBoundInputs']),'semanticExceptions':len(r['semanticExceptions'])} for r in result]},ensure_ascii=False))
