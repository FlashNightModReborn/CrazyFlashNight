"""Check exact post-checkout bytes for final arena and frozen source inputs."""
from pathlib import Path
import argparse,hashlib,json,subprocess
parser=argparse.ArgumentParser();parser.add_argument('--source-index',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--head-identity',type=Path);a=parser.parse_args()
R=Path.cwd();P=R/'tools/cf6-elder-assets/evidence/20261017-calibration';sha=lambda data:hashlib.sha256(data).hexdigest()
load=lambda path:json.loads(path.read_text('utf-8-sig'))
source_index=load(a.source_index);source_rows=source_index['files']if isinstance(source_index,dict)else source_index
expected={row['path']:row['sha256']for row in source_rows}
for label in ['r22-full-awake','head-c5-full-awake']:
    identity=load(a.head_identity if label=='head-c5-full-awake'and a.head_identity else P/'history'/label/'plan/input-identity.json')
    for row in identity['sourceBindings']:
        if row['path']in expected:assert expected[row['path']]==row['sha256']
        expected[row['path']]=row['sha256']
index={}
for record in subprocess.check_output(['git','ls-files','--stage','-z']).split(b'\0'):
    if not record:continue
    meta,path=record.split(b'\t',1);mode,oid,stage=meta.decode('ascii').split();assert stage=='0'
    index[path.decode('utf8')]=oid
ordered=sorted(expected);assert all(p in index for p in ordered),[p for p in ordered if p not in index]
attrs={p:{}for p in ordered}
out=subprocess.check_output(['git','check-attr','--cached','-z','--stdin','text','eol','filter'],input=('\0'.join(ordered)+'\0').encode('utf8')).decode('utf8').split('\0')
assert out[-1]==''
for i in range(0,len(out)-1,3):attrs[out[i]][out[i+1]]=out[i+2]
oids=sorted(set(index[p]for p in ordered));raw=subprocess.check_output(['git','cat-file','--batch'],input=('\n'.join(oids)+'\n').encode('ascii'));pos=0;blobs={}
for oid in oids:
    end=raw.index(b'\n',pos);parts=raw[pos:end].decode('ascii').split();assert parts[:2]==[oid,'blob'];n=int(parts[2]);start=end+1
    blobs[oid]=raw[start:start+n];assert raw[start+n:start+n+1]==b'\n';pos=start+n+1
assert pos==len(raw)
rows=[]
for name in ordered:
    at=attrs[name];data=blobs[index[name]];method='raw-index-preserved-by-attributes'
    if not(at['filter']in('unspecified','unset')and(at['text']=='unset'or at['eol']=='lf')):
        data=subprocess.check_output(['git','cat-file','--filters',':'+name]);method='actual-checkout-filters'
    working=sha((R/name).read_bytes());checkout=sha(data)
    rows.append({'path':name,'expectedSha256':expected[name],'workingSha256':working,'checkoutSha256':checkout,
                 'attributes':at,'method':method,'matches':working==expected[name]==checkout})
mismatches=[row for row in rows if not row['matches']]
report={'ok':not mismatches,'files':rows,'mismatches':mismatches,
        'boundary':'Exact raw-byte comparison for both selected arena matrices and the final frozen source index. No line-ending normalization is silently applied. Cached attributes are inspected; actual Git checkout filters are used when raw preservation is not guaranteed.'}
with a.output.open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':not mismatches,'checked':len(rows),'mismatches':mismatches},ensure_ascii=False))
if mismatches:raise SystemExit(1)
