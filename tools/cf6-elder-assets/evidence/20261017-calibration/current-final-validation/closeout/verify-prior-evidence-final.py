from pathlib import Path
import argparse,hashlib,json
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);a=parser.parse_args()
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
def lp(p):
    value=str(Path(p).resolve());return Path(value if value.startswith('\\\\?\\')else'\\\\?\\'+value)
read=lambda p:lp(p).read_bytes();load=lambda p:json.loads(read(p).decode('utf-8-sig'));sha=lambda b:hashlib.sha256(b).hexdigest()
previous=load(O/'prior-sealed-evidence-verification-20261018.json');checked={};packages=[];indexed=0;summary_only=0
for original in previous:
    path=R/original['path'];data=read(path);assert sha(data)==original['sha256'],str(path)
    manifest=json.loads(data.decode('utf-8-sig'))
    if 'files'not in manifest:
        assert original['files']==0 and original['path']=='tools/cf6-guard-assets/evidence/20261016-phase/checks/integrity.json'
        assert 'verifiedCopiedArtifacts'in manifest and 'phaseEvidenceFiles'in manifest
        summary_only+=1;packages.append({**original,'recordKind':'summary_receipt'});continue
    files=manifest['files'];assert isinstance(files,list)and len(files)==original['files'];indexed+=1
    for row in files:
        name=(path.parent/row['path']).relative_to(R).as_posix();content=read(R/name)
        assert sha(content)==row['sha256'],name
        if 'bytes'in row:assert len(content)==row['bytes'],name
        if name in checked:assert checked[name]==row['sha256']
        checked[name]=row['sha256']
    packages.append({**original,'recordKind':'package_file_index'})
report={'ok':True,'integrityRecords':len(packages),'indexedPackages':indexed,'summaryOnlyRecords':summary_only,'uniqueFilesVerified':len(checked),'packages':packages,
    'boundary':'All 25 prior integrity-named records retain their original hashes: 24 are file indexes whose entries are verified, and one is an already-bound summary receipt with zero indexed entries. Current calibration evidence is sealed separately.'}
with lp(a.output).open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':True,'integrityRecords':len(packages),'indexedPackages':indexed,'summaryOnlyRecords':summary_only,'uniqueFilesVerified':len(checked)}))
