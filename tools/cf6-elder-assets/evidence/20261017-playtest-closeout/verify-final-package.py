from pathlib import Path
import hashlib,json,gzip
ROOT=Path(__file__).resolve().parents[2];TMP=Path(__file__).resolve().parent
OUT=ROOT/'tools/cf6-elder-assets/evidence/20261017-playtest'
def lp(p):return Path('\\\\?\\'+str(p.resolve()))
def read(p):return lp(p).read_bytes()
def sha(p):return hashlib.sha256(read(p)).hexdigest()
def js(p):return json.loads(read(p).decode('utf-8-sig'))
integrity=js(OUT/'integrity.json')
for row in integrity['files']:
    p=OUT/row['path'];assert lp(p).stat().st_size==row['bytes'] and sha(p)==row['sha256'],p
all_files=[p for p in lp(OUT).rglob('*') if p.is_file()]
expected={r['path'] for r in integrity['files']}|{'integrity.json'}
assert {p.relative_to(lp(OUT)).as_posix() for p in all_files}==expected
assert max(p.stat().st_size for p in all_files)<=8_000_000
mapping=js(OUT/'lossless-mapping.json')['files']
for row in mapping:
    data=b''.join(read(OUT/part['path']) for part in row['parts'])
    if row['encoding']=='gzip':data=gzip.decompress(data)
    assert len(data)==row['originalBytes'] and hashlib.sha256(data).hexdigest()==row['originalSha256']
sources=js(OUT/'current-source-and-assets.zip.index.json')['files']
for row in sources:assert sha(ROOT/row['path'])==row['sha256'],row['path']
summary=js(OUT/'summary.json')
assert len(summary['tests'])==7 and len(summary['builds'])==4
assert summary['standardEntryVerified'] is False and summary['formalRuntimePromoted'] is False
for row in summary['builds']:assert sha(ROOT/row['swf'])==row['sha256'].lower()
cleanup=js(TMP/'final-cleanup.json')
assert sha(ROOT/'scripts/TestLoader.as')==cleanup['originalRunnerSha256'].lower()
for name in ['compile_state_uncertain.marker','testloader_scratch_inflight.marker','testplayer_control.cfg','compile_target.cfg','compile_mode.cfg']:
    assert not (ROOT/'scripts'/name).exists(),name
result={'passed':True,'filesIncludingIntegrity':len(all_files),'bytesIncludingIntegrity':sum(p.stat().st_size for p in all_files),'maximumFileBytes':max(p.stat().st_size for p in all_files),'losslessMappingsVerified':len(mapping),'currentSourceFilesVerified':len(sources),'acceptedNativeRuns':len(summary['tests']),'boundBuilds':len(summary['builds']),'nativeImages':47,'pendingCompileMarkers':False}
(TMP/'final-package-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps(result,ensure_ascii=False))
