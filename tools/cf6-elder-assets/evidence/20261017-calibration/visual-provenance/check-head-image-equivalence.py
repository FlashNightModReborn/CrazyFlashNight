from pathlib import Path
from lxml import etree as E
import hashlib,json,struct,zipfile,zlib
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
sha=lambda b:hashlib.sha256(b).hexdigest()
z=zipfile.ZipFile(O/'r3-head-before-timing-repair.zip');m=json.loads(z.read('tools/cf6-headbot-assets/native-manifest.json'))
def graphic_xml(b):
 root=E.fromstring(b)
 for n in root.xpath('//*[local-name()="Actionscript"]'):n.getparent().remove(n)
 return E.tostring(root,method='c14n')
checked=[]
for row in m['outputs']+m['projectFiles']:
 rel=m['owner']+'/'+row['path'];now=(R/rel).read_bytes();current=sha(now)
 if current==row['sha256']:kind='byte-identical'
 else:
  old=z.read(rel);assert sha(old)==row['sha256']
  assert rel.endswith('.xml') and graphic_xml(old)==graphic_xml(now),rel
  kind='identical after removing only Actionscript elements'
 checked.append({'path':rel,'capturedSourceSha256':row['sha256'],'currentSha256':current,'comparison':kind})
def shapes(b):
 body=zlib.decompress(b[8:]) if b[:3]==b'CWS' else b[8:]
 assert len(body)+8==struct.unpack_from('<I',b,4)[0]
 start=(5+(body[0]>>3)*4+7)//8+4;found=[]
 def walk(start,end):
  p=start
  while p<end:
   h=struct.unpack_from('<H',body,p)[0];p+=2;code,size=h>>6,h&63
   if size==63:size=struct.unpack_from('<I',body,p)[0];p+=4
   payload=body[p:p+size];assert len(payload)==size
   if code in (2,22,32,83,46,84,6,21,35,90):found.append({'code':code,'id':struct.unpack_from('<H',payload)[0],'sha256':sha(payload)})
   if code==39:walk(p+4,p+size)
   p+=size
   if code==0:break
 walk(start,len(body));return sorted(found,key=lambda r:(r['code'],r['id']))
rel=m['owner']+'.swf';old=z.read(rel);new=(R/rel).read_bytes();before=shapes(old);after=shapes(new);assert before==after
native=O/'native-r3-head/head-charge';result=json.loads((native/'result.json').read_text('utf-8-sig'));assert result['exitCode']==0 and result['bindingsUnchanged']
bindings=json.loads((native/'bindings-before.json').read_text('utf-8-sig'));assert next(r for r in bindings if r['path']==rel)['sha256'].lower()==sha(old)
images=[{'path':p.relative_to(O).as_posix(),'sha256':sha(p.read_bytes())} for p in sorted((O/'head-charge-images').glob('*.png'))];assert len(images)==7
report={'ok':True,'capturedConsumerSha256':sha(old),'currentConsumerSha256':sha(new),'xmlFiles':checked,'identicalEmbeddedGraphics':before,'images':images,
 'captureTraceSha256':sha((native/'flashlog.txt').read_bytes()),'boundary':'Seven images were captured before the code-only timing repair. All source graphics and compiled graphical definitions match the repaired consumer. This is equivalence evidence, not a claim that the seven images were recaptured.'}
with (O/'head-image-equivalence.json').open('x',encoding='utf8') as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':True,'sourceFiles':len(checked),'graphicDefinitions':len(before),'nativeImages':len(images)}))
