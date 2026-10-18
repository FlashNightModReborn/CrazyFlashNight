"""Read-only verification of the sealed package and its exact current-source closure."""
from pathlib import Path
import gzip,hashlib,io,json,zipfile
R=Path.cwd();P=R/'tools/cf6-audio/evidence/20261017-combat-audio';T=R/'tmp/cf6-combat-audio-20261017'
def lp(p):
    s=str(Path(p).resolve());return Path(s if s.startswith('\\\\?\\') else '\\\\?\\'+s)
def read(p):return lp(p).read_bytes()
def sha(p):return hashlib.sha256(read(p)).hexdigest()
def load(p):return json.loads(read(p).decode('utf-8-sig'))
manifest=load(P/'integrity.json');expected={r['path'] for r in manifest['files']}|{'integrity.json'}
actual={p.relative_to(lp(P)).as_posix() for p in lp(P).rglob('*') if p.is_file()}
assert actual==expected,(actual-expected,expected-actual)
for row in manifest['files']:
    assert len(read(P/row['path']))==row['bytes'] and sha(P/row['path'])==row['sha256']
assert max(lp(P/f).stat().st_size for f in actual)<=8_000_000
restored_sources=[];source_zip=None
mapping=load(P/'lossless-mapping.json')['files']
for row in mapping:
    pieces=[]
    for part in row['parts']:
        data=read(P/part['path']);assert len(data)==part['bytes'] and hashlib.sha256(data).hexdigest()==part['sha256'];pieces.append(data)
    data=b''.join(pieces)
    if row['encoding']=='gzip':data=gzip.decompress(data)
    else:assert row['encoding']=='identity'
    assert len(data)==row['originalBytes'] and hashlib.sha256(data).hexdigest()==row['originalSha256']
    if row['source']=='current verified source inputs':
        assert source_zip is None;source_zip=data
    restored_sources.append(row['source'])
index=load(P/'current-source.zip.index.json')['files']
assert source_zip is not None
with zipfile.ZipFile(io.BytesIO(source_zip)) as z:
    assert z.namelist()==[r['path'] for r in index]
    for row in index:
        data=z.read(row['path']);assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']
        assert sha(R/row['path'])==row['sha256'],'Current source changed: '+row['path']
summary=load(P/'summary.json')
assert (summary['behaviorAssertions'],summary['renderAssertions'],summary['totalArenaRows'])==(3180,116,84)
assert len(summary['builds'])==9 and len(summary['nativeRuns'])==9
for row in summary['builds']:
    assert sha(R/row['consumer'])==row['sha256']==sha(P/'current-swfs'/Path(row['consumer']).name)
images=load(P/'image-review.json')['images'];assert len(images)==24
for row in images:assert sha(P/'images'/row['family']/Path(row['image']).name)==row['sha256']
for run in summary['arenaRuns']:
    rows=load(P/run['label']/'all-results.json')
    assert len(rows)==run['expectedRows'] and all(not row['errors'] for row in rows)
    assert run['experimentQualified'] and run['saveProtectionAndCleanupVerified']
    assert all(identity['runtimeMode']=='isolated_candidate' for identity in run['runtimeIdentities'])
audio=load(P/'audio-audit.json')
assert audio['originalTimelineSitesMissingBefore']==45 and audio['originalTimelineSitesMissingAfter']==0
assert audio['legacyAdditionalNativeCalls']==2 and len(audio['decodedAssets'])==44 and audio['restoredLegacyWav']['decodeToEnd']
assert all(not r['missingFiles'] and r['embeddedStartSoundsInConsumerClosure']==0 for r in audio['legacyAndDerivedUnits'])
result={'ok':True,'indexedFiles':len(manifest['files']),'totalBytes':manifest['totalBytes'],'maximumFileBytes':max(lp(P/f).stat().st_size for f in actual),
 'losslessSourcesVerified':len(mapping),'frozenSourceFilesMatchingCurrent':len(index),'currentBuildsVerified':9,'nativeImagesVerified':24,
 'behaviorAssertions':3180,'renderAssertions':116,'arenaRows':84,'primaryIntegritySha256':sha(P/'integrity.json'),
 'humanListeningOrAestheticAcceptance':False,'formalRuntimePromotion':False,'standardEntryVerified':False}
with (T/'package-verification.json').open('x',encoding='utf8') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps(result))
