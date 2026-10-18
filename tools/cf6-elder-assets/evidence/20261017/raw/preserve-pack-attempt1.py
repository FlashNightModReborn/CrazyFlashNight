from evidence_utils import *

source = ROOT/'tools/cf6-elder-assets/evidence/20261017'
assert source.is_dir() and not (source/'integrity.json').exists()
log = read(source/'raw/doc-governance-final.log')
assert b'lossless-mapping.json' in log and b'integrity.json' in log
put(TMP/'review-pack-attempt1-doc-governance.log', log)
put(TMP/'freeze-elder-review-attempt1.py.txt', read(source/'raw/freeze-elder-review.py'))
rows = [{'path':file.relative_to(lp(source)).as_posix(), 'bytes':file.stat().st_size, 'sha256':sha(file)}
        for file in lp(source).rglob('*') if file.is_file()]
jput(TMP/'review-pack-attempt1-failure.json', {'status':'UNSEALED_DOCUMENT_LINK_ORDER_FAILURE',
    'originalPath':str(source), 'preservedPath':str(TMP/'review-pack-attempt1-unsealed'),
    'cause':'Documentation check ran before the lossless mapping and integrity index existed; no gameplay or source failure.',
    'docGovernanceExitCode':1, 'fileCount':len(rows), 'totalBytes':sum(row['bytes'] for row in rows), 'files':rows})
print(json.dumps({'preservedInventoryFiles':len(rows), 'bytes':sum(row['bytes'] for row in rows)}))
