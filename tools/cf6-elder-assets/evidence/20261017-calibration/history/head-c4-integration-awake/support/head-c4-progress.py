from pathlib import Path
import hashlib, json, sys

R = Path.cwd()
assert sys.argv[1] == 'cf6-cal-head-c4-20261018'
E = R / 'tmp/arena-worker-experiments' / sys.argv[1]
def lp(p):
    value = str(Path(p).resolve())
    return Path(value if value.startswith('\\\\?\\') else '\\\\?\\' + value)
def load(p): return json.loads(lp(p).read_text('utf-8-sig'))
groups = []
for path in E.rglob('group-report.json'):
    group = load(path)
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    rows = []
    for outcome in group['outcomes']:
        if outcome['status'] != 'completed': continue
        assert outcome['cleanupVerified'] and outcome['protectedSavesVerified'] and outcome['runtimeResourcesVerified']
        receipt = load(outcome['expectedReceiptPath'])
        data = lp(receipt['resultPath']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == receipt['resultSha256'].removeprefix('sha256:')
        rows.extend(json.loads(line) for line in data.decode('utf-8-sig').splitlines())
    if not rows: continue
    level = rows[0]['authorityContext']['level']
    for row in rows:
        context = row['authorityContext']
        assert context['candidateUnitId'] == 470 and context['rivalUnitId'] == 286 and context['level'] == level
        assert not row['errors'] and row['phaseSpawnCount'] == 0 and not row['spawnedUnits']
    wins = sum(row['status'] == 'finished' and row['winner'] == row['authorityContext']['candidateSide'] for row in rows)
    groups.append({'level': level, 'n': len(rows), 'wins': wins,
                   'timeouts': sum(row['status'] == 'timeout' for row in rows),
                   'minimumRemainingHpPercent': round(100 * min(row[row['authorityContext']['candidateSide']]['remainHp'] / row[row['authorityContext']['candidateSide']]['startMaxHp'] for row in rows), 3),
                   'frameRange': [min(row['frames'] for row in rows), max(row['frames'] for row in rows)],
                   'integrationGroupPassed': len(rows) == 2 and wins == 2})
print(json.dumps({'experiment': sys.argv[1], 'groups': groups, 'rows': sum(group['n'] for group in groups),
                  'wholeExperimentFinal': (E / 'experiment-report.json').exists()}))
