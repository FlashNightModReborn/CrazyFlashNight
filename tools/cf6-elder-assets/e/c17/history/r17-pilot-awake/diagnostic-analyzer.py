"""Join literal shield diagnostics to hash-verified completed arena results."""
from pathlib import Path
import argparse, hashlib, json, re

args = argparse.ArgumentParser()
args.add_argument('experiment')
args.add_argument('--diagnostics', type=Path, required=True)
args.add_argument('--output', type=Path)
a = args.parse_args()
R = Path.cwd()
E = R / 'tmp/arena-worker-experiments' / a.experiment

def lp(p):
    value = str(Path(p).resolve())
    return Path(value if value.startswith('\\\\?\\') else '\\\\?\\' + value)

def read(p): return lp(p).read_bytes()
def load(p): return json.loads(read(p).decode('utf-8-sig'))
def sha(data): return hashlib.sha256(data).hexdigest()

diagnostics = load(a.diagnostics)
assert diagnostics['experiment'] == a.experiment
result = []
for path in sorted(E.rglob('group-report.json')):
    group = load(path)
    for outcome in group['outcomes']:
        if outcome['status'] != 'completed': continue
        assert outcome['cleanupVerified'] and outcome['protectedSavesVerified'] and outcome['runtimeResourcesVerified']
        receipt = load(outcome['expectedReceiptPath'])
        data = read(receipt['resultPath'])
        assert sha(data) == receipt['resultSha256'].removeprefix('sha256:')
        session = next(part.removeprefix('session-') for part in Path(outcome['expectedReceiptPath']).parts if part.startswith('session-'))
        for row in [json.loads(line) for line in data.decode('utf-8-sig').splitlines()]:
            ctx = row['authorityContext']
            side = ctx['candidateSide']
            rival_side = 'red' if side == 'blue' else 'blue'
            own = [s for s in row['spawnedUnits'] if s['side'] == side]
            assert len(own) == 1
            events = [e for e in diagnostics['events'] if e['group'] == group['groupId'] and e['session'] == session
                      and '[CF6_ELDER_COMBAT_END]' in e['message'] and ('unit=' + own[0]['name'] + ' ') in e['message']]
            assert len(events) == 1, (group['groupId'], row['runId'], len(events))
            event = events[0]
            fields = dict(re.findall(r'(\w+)=([^ ]+)', event['message']))
            assert fields['form'] == 'robot' and int(fields['level']) == ctx['level']
            initial = [s for s in row[rival_side + 'SpawnPositions'] if s['index'] is not None]
            assert len(initial) == 1
            successors = {s['name']: s for s in row['spawnedUnits'] if s['side'] == rival_side}
            sources = []
            if fields['rageSources'] != 'none':
                for item in fields['rageSources'].split('|'):
                    name, hits, power, clocks = item.split('@')
                    first, last = clocks.split('-')
                    phase = 'initial' if name == initial[0]['name'] else 'successor' if name in successors else 'unknown'
                    sources.append({'name': name, 'phase': phase, 'hits': int(hits), 'maxRawPower': float(power),
                                    'firstRobotClock': int(first), 'lastRobotClock': int(last)})
            assert sum(s['hits'] for s in sources) == int(fields['rageLeech'])
            result.append({'group': group['groupId'], 'runId': row['runId'], 'rival': ctx['rivalUnitId'],
                           'level': ctx['level'], 'side': side, 'status': row['status'], 'frames': row['frames'],
                           'robotClock': int(fields['clock']), 'rageLeech': int(fields['rageLeech']),
                           'initialPhaseRageLeech': sum(s['hits'] for s in sources if s['phase'] == 'initial'),
                           'successorPhaseRageLeech': sum(s['hits'] for s in sources if s['phase'] == 'successor'),
                           'unknownPhaseRageLeech': sum(s['hits'] for s in sources if s['phase'] == 'unknown'),
                           'rageSources': sources, 'reactiveForcedAndPulses': [int(v) for v in fields['reactive'].split('/')],
                           'reactiveObservedLostGrantedAbsorbed': [float(v) for v in fields['reactiveHp'].split('/')],
                           'beamAbsorbedUnused': [float(v) for v in fields['beamShield'].split('/')],
                           'normalBeamHitsAndPower': [float(v) for v in fields['beamActual'].split('/')],
                           'heavyBeamHitsAndPower': [float(v) for v in fields['heavyActual'].split('/')],
                           'sourceArchiveSha256': event['sourceArchiveSha256'], 'sourceEntrySha256': event['sourceEntrySha256'],
                           'lineNumber': event['lineNumber'], 'resultSha256': sha(data)})

output = {'experiment': a.experiment, 'wholeExperimentFinal': (E / 'experiment-report.json').exists(),
          'rows': result, 'diagnosticsSha256': sha(read(a.diagnostics)),
          'boundary': 'Read-only joins of observed nonlethal robot hit callbacks. A positive production lifesteal flag is an observed event, not a universal heal-amount probe. Lethal or pre-subscription events are not counted. Initial and successor identity are matched to actual arena spawn names; unknown identities remain unknown. This does not establish zero total healing or causality for outcome differences.'}
if a.output:
    with lp(a.output).open('x', encoding='utf8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
        f.write('\n')
print(json.dumps(output, ensure_ascii=False))
