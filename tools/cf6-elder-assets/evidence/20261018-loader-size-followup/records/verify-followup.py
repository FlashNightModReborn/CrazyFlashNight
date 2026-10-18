"""Verify the frozen follow-up; use --check-current only for this exact C6 checkout."""
from pathlib import Path
import argparse,gzip,hashlib,io,json,zipfile
p=argparse.ArgumentParser();p.add_argument('--check-current',action='store_true');a=p.parse_args()
Q=Path(__file__).resolve().parent
if Q.name!='20261018-loader-size-followup':Q=Path.cwd()/'tools/cf6-elder-assets/evidence/20261018-loader-size-followup'
R=Q.parents[3]
def lp(p):
    p=str(Path(p).resolve());return Path(p if p.startswith('\\\\?\\') else '\\\\?\\'+p)
def data(p):return lp(p).read_bytes()
def sha(p):return hashlib.sha256(data(p)).hexdigest()
def load(p):return json.loads(data(p).decode('utf-8-sig'))
index=load(Q/'integrity.json')
assert index['fileCount']==len(index['files'])
assert index['totalBytes']==sum(x['bytes'] for x in index['files'])
expected={r['path'] for r in index['files']}|{'integrity.json'}
actual={p.relative_to(lp(Q)).as_posix() for p in lp(Q).rglob('*') if p.is_file()}
assert actual==expected,(actual-expected,expected-actual)
for row in index['files']:
    assert row['bytes']<=8_000_000 and len(data(Q/row['path']))==row['bytes'] and sha(Q/row['path'])==row['sha256'],row['path']
mapping=load(Q/'lossless-mapping.json')['files']
for row in mapping:
    restored=b''.join(data(Q/x['path']) for x in row['parts'])
    if row['encoding']=='gzip':restored=gzip.decompress(restored)
    assert len(restored)==row['originalBytes'] and hashlib.sha256(restored).hexdigest()==row['originalSha256']
source=load(Q/'records/inputs-before.json')
with zipfile.ZipFile(io.BytesIO(data(Q/'records/actual-as2-source.zip'))) as z:
    assert set(z.namelist())=={x['path'] for x in source['bindings']}
    for row in source['bindings']:assert hashlib.sha256(z.read(row['path'])).hexdigest()==row['sha256']
summary=load(Q/'summary.json')
assert summary['qualified'] and summary['nativeBoot']['passed']==103
assert summary['headIntegration']['rows']==6 and summary['elderIntegration']['rows']==12
assert not summary['formalRuntimePromoted'] and summary['displayCleanup']['displayHoldActive'] is False
assert summary['retainedFailedAttempts']==1
assert load(Q/'elder-primary/coordinator/experiment-report.json')['status']=='unqualified'
assert load(Q/'elder-retry/coordinator/experiment-report.json')['qualified']
for scope in summary['displayScopes']:
    events=[json.loads(x) for x in data(Q/scope/'display-state.jsonl').decode('utf8').splitlines()]
    assert len([e for e in events if e['event']=='display_request_released' and e['result']!=0])==1
    assert len([e for e in events if e['event']=='subscription_ended' and e['result']==0])==1
prior=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
assert sha(prior/'integrity.json')==summary['priorC5Calibration']['filesUnchanged']['integritySha256']
prior_index=load(prior/'integrity.json')
assert {p.relative_to(lp(prior)).as_posix() for p in lp(prior).rglob('*') if p.is_file()}=={x['path'] for x in prior_index['files']}|{'integrity.json'}
for row in prior_index['files']:assert sha(prior/row['path'])==row['sha256']
if a.check_current:
    assert sha(R/'scripts/asLoader.swf')==summary['loaderC6']['sha256'].lower()
    for row in source['bindings']:assert sha(R/row['path'])==row['sha256'],row['path']
    for kind in ['head','elder']:
        for row in load(Q/kind/'integration-summary.json')['sourceBindings']:assert sha(R/row['path'])==row['sha256'],row['path']
print(json.dumps({'qualified':True,'files':len(index['files']),'bytes':index['totalBytes'],
    'mappingEntries':len(mapping),'actualSourceFiles':len(source['bindings']),'currentChecked':a.check_current,'priorC5FilesUnchanged':True}))
