from evidence_utils import *
import statistics, sys

assert len(sys.argv) == 2
revision = sys.argv[1]
assert revision == 'r15'
packages = []
for name, folder in [
    ('headbot', 'tools/cf6-headbot-assets/evidence/20261017-knockback'),
    ('bladebot', 'tools/cf6-bladebot-assets/evidence/20261017-wave'),
    ('elder', 'tools/cf6-elder-assets/evidence/20261017'),
]:
    base = ROOT/folder
    integrity = js(base/'integrity.json')
    indexed = integrity['files']
    actual = {p.relative_to(lp(base)).as_posix() for p in lp(base).rglob('*') if p.is_file()}
    assert actual == {r['path'] for r in indexed} | {'integrity.json'}, name
    assert len(indexed) == integrity['fileCount']
    assert sum(r['bytes'] for r in indexed) == integrity['totalBytes']
    for row in indexed:
        data = read(base/row['path'])
        assert len(data) == row['bytes'] and digest(data) == row['sha256'], row['path']
        assert len(data) <= LIMIT, row['path']
    mapping = js(base/'lossless-mapping.json')['files']
    restored_files = {}
    for row in mapping:
        encoded = b''.join(read(base/p['path']) for p in row['parts'])
        for part in row['parts']:
            data = read(base/part['path'])
            assert len(data) == part['bytes'] and digest(data) == part['sha256']
        assert row['encoding'] in ['identity', 'gzip']
        restored = gzip.decompress(encoded) if row['encoding'] == 'gzip' else encoded
        assert len(restored) == row['originalBytes'] and digest(restored) == row['originalSha256']
        if row.get('source') == 'current verified source inputs':
            restored_files['source-zip'] = restored
    if name == 'elder':
        index = js(base/'frozen-inputs.zip.index.json')['files']
        with zipfile.ZipFile(io.BytesIO(restored_files['source-zip'])) as archive:
            assert archive.testzip() is None
            assert archive.namelist() == [r['path'] for r in index]
            for row in index:
                data = archive.read(row['path'])
                assert len(data) == row['bytes'] and digest(data) == row['sha256']
                assert sha(ROOT/row['path']) == row['sha256'], 'Current source changed: '+row['path']
        summary = js(base/'summary.json')
        assert summary['revision'] == revision and summary['games'] == 36 and summary['wins'] == 0
        assert summary['timeouts'] == 0 and summary['singleSuccessorPerMatch']
        assert not summary['positioningMatrixVerified'] and not summary['balanceCalibrationComplete']
        assert summary['humanReviewRequested'] and summary['userTargetNetHpExchangePercent'] == [50, 80]
        assert summary['preparedButNotExecuted'][0]['revision'] == 'r16' and not summary['preparedButNotExecuted'][0]['combatExecuted']
        assert summary['evidenceState'] == 'candidate_executed'
        assert not any(summary[key] for key in ['formalRuntimePromoted', 'standardEntryVerified', 'humanAcceptance'])
        report = js(base/'matrix/coordinator/experiment-report.json')
        assert report['qualified'] and report['status'] == 'completed' and not report['errors']
        rows = []
        for p in lp(base/'matrix').rglob('*.jsonl'):
            for line in read(p).decode('utf-8-sig').splitlines():
                if not line: continue
                item = json.loads(line)
                if 'authorityContext' in item and 'candidateSide' in item['authorityContext']:
                    rows.append(item)
        unique = {}
        for row in rows:
            key = (row['batchId'], row['runId'])
            if key in unique: assert unique[key] == row
            unique[key] = row
        assert len(unique) == 36, len(unique)
        rows = list(unique.values())
        for group in summary['levels']:
            subset = [r for r in rows if r['authorityContext']['rivalUnitId'] == group['rivalUnitId'] and r['authorityContext']['level'] == group['level']]
            assert len(subset) == 6
            values = []
            for row in subset:
                side = row['authorityContext']['candidateSide']
                other = 'red' if side == 'blue' else 'blue'
                assert row['status'] == 'finished' and row['winner'] == other and row['phaseSpawnCount'] == 1
                values.append(100*(1-row[other]['remainHp']/row[other]['startMaxHp']))
            calculated = {'minPercent':min(values), 'maxPercent':max(values), 'meanPercent':statistics.mean(values), 'medianPercent':statistics.median(values)}
            for key, value in calculated.items(): assert abs(group[key]-value) < 1e-9
            assert group['withinTargetBand'] == sum(50 <= value <= 80 for value in values)
        assert summary['targetBandMatches'] == sum(group['withinTargetBand'] for group in summary['levels'])
        assert any(group['meanPercent'] < 50 for group in summary['levels']) and any(group['maxPercent'] > 80 for group in summary['levels'])
        identities = summary['runtimeIdentities']
        assert len(identities) == 12
        for field in ['coreSha256', 'buildIdentity', 'payloadClosure']:
            assert len({r[field] for r in identities}) == 1, field
        for row in summary['sourceBindings']: assert sha(ROOT/row['path']) == row['sha256']
        diagnostics = js(base/'field-diagnostics.json')
        assert len(diagnostics['rows']) == 36
        phase_observed = sum(row['phaseEventsObserved'] == 1 for row in diagnostics['rows'])
    packages.append({'name':name, 'files':len(indexed), 'bytes':integrity['totalBytes'], 'losslessSources':len(mapping)})

assert sha(ROOT/'scripts/TestLoader.as') == 'e38e2151bf619814a0ea65bf2b19d11d8f78a7704787c47c046666acee2f090b'
result = {'ok':True, 'revision':revision, 'packages':packages, 'currentElderSourceSnapshotMatches':True,
          'elderMatrixRowsRecomputed':36, 'phaseDiagnosticRowsObserved':phase_observed, 'testLoaderOriginalRestored':True,
          'humanReviewHandoff':True, 'balanceCalibrationComplete':False, 'targetBandMatches':summary['targetBandMatches']}
jput(TMP/('review-delivery-integrity-'+revision+'.json'), result)
print(json.dumps(result, ensure_ascii=False))
