from pathlib import Path
import hashlib,json
ROOT=Path.cwd();OUT=ROOT/'tmp/cf6-combat-audio-20261017/preserved-evidence-check-final.json'
assert not OUT.exists()
def lp(p):return Path('\\\\?\\'+str(Path(p).resolve()))
def sha(p):return hashlib.sha256(lp(p).read_bytes()).hexdigest()
rows=[];diagnostics=[]
for family in ['headbot','elder','bladebot','manman','wings','soldier','guard','zombie']:
    base=ROOT/('tools/cf6-'+family+'-assets/evidence')
    for manifest in base.rglob('integrity.json'):
        data=json.loads(lp(manifest).read_text('utf-8-sig'))
        if 'files' not in data:
            assert manifest.parent.name=='checks' and 'verifiedCopiedArtifacts' in data
            diagnostics.append({'path':manifest.relative_to(ROOT).as_posix(),'sha256':sha(manifest),'role':'nested verification receipt, covered by its parent package manifest'})
            continue
        files=data['files']
        for item in files:
            p=manifest.parent/item['path'];assert sha(p)==item['sha256'].lower(),str(p)
        rows.append({'path':manifest.relative_to(ROOT).as_posix(),'manifestSha256':sha(manifest),'verifiedFiles':len(files)})
originals=[]
for row in json.loads((ROOT/'tmp/cf6-combat-audio-20261017/before-source-index.json').read_text('utf8'))['files']:
    if row['path'].startswith('flashswf/arts/new/Codex素材源稿/'):
        assert sha(ROOT/row['path'])==row['sha256'];originals.append(row)
OUT.write_text(json.dumps({'oldPackages':rows,'nestedDiagnostics':diagnostics,'immutableSourceFiles':originals,'ok':True},ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'oldPackages':len(rows),'oldEvidenceFiles':sum(r['verifiedFiles'] for r in rows),'immutableSources':len(originals)}))
