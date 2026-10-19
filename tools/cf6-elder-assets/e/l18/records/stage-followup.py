from pathlib import Path
import hashlib,json,subprocess
R=Path.cwd();D=R/'tmp/cf6-combat-calibration-20261017/loader-size-followup'
q='tools/cf6-elder-assets/evidence/20261018-loader-size-followup'
Q=R/q
def run(*args):return subprocess.check_output(['git',*args])
def paths(*args):return [s.decode('utf8') for s in run(*args).split(b'\0') if s]
def data(p):
    s=str(p.resolve());return Path(s if s.startswith('\\\\?\\') else '\\\\?\\'+s).read_bytes()
assert (Q/'integrity.json').exists()
assert run('rev-parse','HEAD').decode().strip()=='dabd11a89570125b6fe2125aa45b5ccaf2d60cd2'
assert not paths('diff','--cached','--name-only','-z'),'Preserve existing index'
expected=['scripts/asLoader.swf','scripts/asLoaderManifest/frame3.as','scripts/asLoaderManifest/_collapsed_frame.as',
          'docs/asLoader-README.md','tools/cf6-headbot-assets/README.md','tools/cf6-elder-assets/README.md']
assert set(paths('diff','--name-only','-z'))==set(expected)
untracked=paths('ls-files','--others','--exclude-standard','-z')
assert untracked and all(n.startswith(q+'/') for n in untracked),untracked[:10]
subprocess.run(['git','add','--',*expected,q],check=True)
staged=paths('diff','--cached','--name-only','-z')
assert set(staged)==set(expected+untracked)
subprocess.run(['git','diff','--cached','--check'],check=True)
subprocess.run(['git','diff','--check'],check=True)
source_matches=[]
for name in expected:
    checkout=run('cat-file','--filters',':'+name)
    assert checkout==data(R/name),name
    source_matches.append({'path':name,'sha256':hashlib.sha256(checkout).hexdigest(),'indexCheckoutMatchesActual':True})
records=[]
for row in run('ls-files','-s','-z','--',q).split(b'\0'):
    if not row:continue
    info,name=row.split(b'\t',1);mode,oid,stage=info.decode().split()
    name=name.decode('utf8');raw=data(R/name)
    expected_oid=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
    assert stage=='0' and oid==expected_oid,name
    records.append({'path':name,'gitBlob':oid,'rawBytesMatch':True})
assert len(records)==len(untracked)
result={'qualified':True,'stagedFiles':len(staged),'frozenFiles':len(records),'sourceFiles':source_matches,
        'tree':run('write-tree').decode().strip(),'evidenceBlobIds':records,
        'primaryC5PackageChanged':False}
with (D/'staged-verification.json').open('x',encoding='utf8') as f:json.dump(result,f,ensure_ascii=False,indent=2)
print(json.dumps({k:result[k] for k in ['qualified','stagedFiles','frozenFiles','tree']}))
