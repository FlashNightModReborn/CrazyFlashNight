from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]
TMP=Path(__file__).resolve().parent
def lp(p):return Path('\\\\?\\'+str(p.resolve()))
def sha(p):return hashlib.sha256(lp(p).read_bytes()).hexdigest()
rows=[]
for rel in ['tools/cf6-headbot-assets/evidence/20261016','tools/cf6-headbot-assets/evidence/20261016-wave','tools/cf6-headbot-assets/evidence/20261017-knockback','tools/cf6-bladebot-assets/evidence/20261016','tools/cf6-bladebot-assets/evidence/20261017-wave','tools/cf6-elder-assets/evidence/20261017']:
    base=ROOT/rel;manifest=base/'integrity.json'
    if not manifest.exists():continue
    data=json.loads(manifest.read_text('utf-8-sig'))
    for row in data['files']:
        p=base/row['path']
        assert lp(p).stat().st_size==row['bytes'] and sha(p)==row['sha256'].lower(),p
    rows.append({'directory':rel,'filesVerified':len(data['files']),'integritySha256':sha(manifest),'result':'unchanged against sealed integrity manifest'})
archives=[]
for name in ['CF6大头机器人-R3','CF6大刀机器人-R2','CF6老头人形-R7','CF6老头机器人-R7','CF6老头变形-R2']:
    base=ROOT/'flashswf/arts/new/Codex素材源稿'/name
    data=json.loads((base/'archive-origin.json').read_text('utf-8-sig'))
    path=Path('C:/Users/fs/Downloads')/data.get('archiveFile',data.get('archive'))
    assert sha(path)==data['archiveSha256'].lower(),path
    for row in data['members']:
        p=base/row['path']
        assert lp(p).stat().st_size==row['bytes'] and sha(p)==row['sha256'].lower(),p
    archives.append({'directory':base.relative_to(ROOT).as_posix(),'archiveSha256':sha(path),'membersVerified':len(data['members'])})
result={'sealedEvidence':rows,'originalSourceArchives':archives,'passed':True}
(TMP/'old-packages-verified.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps(result,ensure_ascii=False))
