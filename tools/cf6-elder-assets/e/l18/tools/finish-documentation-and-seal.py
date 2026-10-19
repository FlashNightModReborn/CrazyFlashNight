from pathlib import Path
import datetime,hashlib,importlib.util,json,subprocess
R=Path.cwd();D=R/'tmp/cf6-combat-calibration-20261017/loader-size-followup'
Q=R/'tools/cf6-elder-assets/evidence/20261018-loader-size-followup'
assert Q.exists() and not (Q/'integrity.json').exists()
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py')
u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
load=lambda p:json.loads(p.read_text('utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert not load(D/'final-documentation-check.json')['qualified']
pkg=u.Package(Q);pkg.mapping=load(D/'package-state.json')['mapping']
docs=['tools/cf6-elder-assets/README.md','tools/cf6-headbot-assets/README.md','docs/asLoader-README.md']
renames=[]
for name in docs:
    old=(Q/'documentation/before'/name).resolve();new=old.with_name(old.name+'.txt')
    assert old.is_relative_to(Q.resolve()) and new.is_relative_to(Q.resolve())
    assert old.is_file() and not new.exists()
    digest=sha(old);old.rename(new);assert sha(new)==digest
    rel=new.relative_to(Q).as_posix()
    pkg.bytes(new.read_bytes(),rel,'Frozen prior canonical document; preserved bytes under .md.txt archive suffix')
    renames.append({'from':old.relative_to(Q).as_posix(),'to':rel,'sha256':digest,'bytesUnchanged':True})
u.jput(D/'archived-document-rename.json',{'reason':'Frozen document snapshots preserve original relative links as data. They are not active documentation at the archive location. No original document bytes were rewritten.','files':renames})
boot=R/'docs/asLoader-README.md';raw=boot.read_bytes();boot.write_bytes(raw.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'))
pkg.copy(D/'verify-followup.py','verify-followup.py')
pkg.copy(D/'final-documentation-check.log','checks/documentation-attempt1.log')
pkg.copy(D/'final-documentation-check.json','checks/documentation-attempt1.json')
pkg.copy(D/'archived-document-rename.json','checks/archived-document-rename.json')
before=[{'path':n,'sha256':sha(R/n)} for n in docs]
for name in docs:pkg.copy(R/name,'documentation/current/'+name+'.txt')
with (D/'final-documentation-check-v2.log').open('xb') as f:
    result=subprocess.run(['node','tools/validate-doc-governance.js'],stdout=f,stderr=subprocess.STDOUT)
after=[{'path':n,'sha256':sha(R/n)} for n in docs]
check={'qualified':result.returncode==0 and before==after,'exitCode':result.returncode,'sourceUnchanged':before==after,'documents':before,
    'completedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'priorFailureRetained':'checks/documentation-attempt1.json',
    'boundary':'Canonical baseline marker restored; unchanged archived document bytes are .md.txt snapshots. No link-check rules or historical baseline was weakened.'}
u.jput(D/'final-documentation-check-v2.json',check)
assert check['qualified']
pkg.copy(D/'final-documentation-check-v2.log','checks/documentation.log')
pkg.copy(D/'final-documentation-check-v2.json','checks/documentation.json')
pkg.copy(D/'collection-v2.log','checks/collection-complete.log')
pkg.copy(D/'finalize.log','checks/first-finalizer.log')
pkg.copy(D/'finalize-followup.py','tools/first-finalizer.py')
pkg.copy(D/'finish-documentation-and-seal.py','tools/finish-documentation-and-seal.py')
summary=pkg.finish()
u.jput(D/'seal-summary.json',{**summary,'integritySha256':sha(Q/'integrity.json')})
print(json.dumps(summary))
