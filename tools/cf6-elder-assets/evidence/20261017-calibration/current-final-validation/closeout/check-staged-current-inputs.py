"""Check exact post-checkout bytes for final arena and frozen source inputs."""
from pathlib import Path
import argparse,hashlib,json,subprocess
parser=argparse.ArgumentParser();parser.add_argument('--source-index',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--head-identity',type=Path);parser.add_argument('--host-source-index',type=Path);a=parser.parse_args()
R=Path.cwd();P=R/'tools/cf6-elder-assets/evidence/20261017-calibration';sha=lambda data:hashlib.sha256(data).hexdigest()
load=lambda path:json.loads(path.read_text('utf-8-sig'))
source_index=load(a.source_index);source_rows=source_index['files']if isinstance(source_index,dict)else source_index
expected={row['path']:row['sha256']for row in source_rows}
host_archive_only=set(source_index.get('additionalFrozenHostSourcePaths',[]))if isinstance(source_index,dict)and a.host_source_index else set()
if host_archive_only:
    host_expected={row['path']:row['sha256']for row in load(a.host_source_index)['files']}
    assert all(name in host_expected and host_expected[name]==expected[name]and(name.startswith('launcher/')or name=='global.json')for name in host_archive_only)
    assert not host_archive_only.intersection(source_index['strictCheckoutPaths'])
for label in ['r22-full-awake','head-c5-full-awake']:
    identity=load(a.head_identity if label=='head-c5-full-awake'and a.head_identity else P/'history'/label/'plan/input-identity.json')
    for row in identity['sourceBindings']:
        if row['path']in expected:assert expected[row['path']]==row['sha256']
        expected[row['path']]=row['sha256']
        assert row['path']not in host_archive_only
index={}
for record in subprocess.check_output(['git','ls-files','--stage','-z']).split(b'\0'):
    if not record:continue
    meta,path=record.split(b'\t',1);mode,oid,stage=meta.decode('ascii').split();assert stage=='0'
    index[path.decode('utf8')]=oid
ordered=sorted(expected);assert all(p in index for p in ordered),[p for p in ordered if p not in index]
attrs={p:{}for p in ordered}
out=subprocess.check_output(['git','check-attr','--cached','-z','--stdin','text','eol','filter','working-tree-encoding'],input=('\0'.join(ordered)+'\0').encode('utf8')).decode('utf8').split('\0')
assert out[-1]==''
for i in range(0,len(out)-1,3):attrs[out[i]][out[i+1]]=out[i+2]
oids=sorted(set(index[p]for p in ordered));raw=subprocess.check_output(['git','cat-file','--batch'],input=('\n'.join(oids)+'\n').encode('ascii'));pos=0;blobs={}
for oid in oids:
    end=raw.index(b'\n',pos);parts=raw[pos:end].decode('ascii').split();assert parts[:2]==[oid,'blob'];n=int(parts[2]);start=end+1
    blobs[oid]=raw[start:start+n];assert raw[start+n:start+n+1]==b'\n';pos=start+n+1
assert pos==len(raw)
def preserved(at):
    return at['filter']in('unspecified','unset')and at['working-tree-encoding']in('unspecified','unset')and(at['text']=='unset'or at['eol']=='lf')
filtered_names=[p for p in ordered if not preserved(attrs[p])]
batch_names=[p for p in filtered_names if b'\0'not in blobs[index[p]]and attrs[p]['filter']in('unspecified','unset')and attrs[p]['working-tree-encoding']in('unspecified','unset')]
filtered={}
if batch_names:
    payload=('\0'.join(index[p]+' '+p for p in batch_names)+'\0').encode('utf8')
    batch=subprocess.check_output(['git','cat-file','--batch','--filters','-Z'],input=payload);position=0
    for name in batch_names:
        end=batch.index(b'\0',position);header=batch[position:end].decode('ascii').split()
        assert header[:2]==[index[name],'blob']and int(header[2])==len(blobs[index[name]])
        start=end+1;finish=batch.index(b'\0',start);filtered[name]=batch[start:finish];position=finish+1
    assert position==len(batch)
rows=[]
for name in ordered:
    at=attrs[name];data=blobs[index[name]];method='raw-index-preserved-by-attributes'
    if name in filtered:
        data=filtered[name];method='actual-checkout-filters-batch'
    elif not preserved(at):
        data=subprocess.check_output(['git','cat-file','--filters',':'+name]);method='actual-checkout-filters-individual'
    working_bytes=(R/name).read_bytes();working=sha(working_bytes);checkout=sha(data);raw_blob=blobs[index[name]];blob_sha=sha(raw_blob)
    raw_match=working==expected[name]==checkout
    canonical=working_bytes.replace(b'\r\n',b'\n')
    host_eol_only=(name in host_archive_only and working==expected[name]
        and b'\r'not in canonical and canonical==raw_blob.replace(b'\r\n',b'\n')==data.replace(b'\r\n',b'\n')
        and at['filter']in('unspecified','unset')and at['working-tree-encoding']in('unspecified','unset'))
    rows.append({'path':name,'indexOid':index[name],'expectedSha256':expected[name],'workingSha256':working,'checkoutSha256':checkout,
                 'rawGitBlobSha256':blob_sha,'attributes':at,'method':method,'matches':raw_match,
                 'accepted':raw_match or host_eol_only,
                 'sourceRole':'additional_frozen_host_source'if name in host_archive_only else'strict_checkout_input',
                 'canonicalLfSha256':sha(canonical)if name in host_archive_only else None,
                 'gitBlobCanonicalLfSha256':sha(raw_blob.replace(b'\r\n',b'\n'))if name in host_archive_only else None,
                 'checkoutCanonicalLfSha256':sha(data.replace(b'\r\n',b'\n'))if name in host_archive_only else None,
                 'explicitCheckoutConversion':'line_endings_only'if host_eol_only and not raw_match else None,
                 'gitBlobMatchesTestedBytes':blob_sha==expected[name]})
mismatches=[row for row in rows if not row['accepted']]
eol_differences=[row for row in rows if row['explicitCheckoutConversion']]
report={'ok':not mismatches,'files':rows,'mismatches':mismatches,'batchedFilteredFiles':len(batch_names),
        'individualFilteredFiles':len(filtered_names)-len(batch_names),
        'strictCheckoutFiles':sum(row['sourceRole']=='strict_checkout_input'for row in rows),
        'hostCheckoutLineEndingDifferences':eol_differences,
        'hostSourceIndexSha256':sha(a.host_source_index.read_bytes())if a.host_source_index else None,
        'boundary':'Gameplay, AS2 and original bound inputs require exact raw Git checkout bytes. Additional Host evidence is bound to the exact raw source archive. Existing Git line-ending differences are accepted only for these separately declared Host files when actual tested bytes, committed blob and real checkout output have identical bytes after explicitly removing CR from CRLF pairs; bare CR is rejected. All three raw hashes and canonical hashes remain recorded, matches stays false, and this does not certify identical bytes or identical new test execution from a fresh ordinary checkout. Exact replay uses the frozen source archive. No production file or existing C# format policy is changed.'}
with a.output.open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':not mismatches,'checked':len(rows),'strictCheckoutFiles':report['strictCheckoutFiles'],'explicitHostCheckoutConversions':len(eol_differences),'unacceptedPaths':[row['path']for row in mismatches]},ensure_ascii=False))
if mismatches:raise SystemExit(1)
