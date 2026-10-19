"""Preserve the final four fresh suites after the concurrent upstream merge."""
from pathlib import Path
import datetime, importlib.util, json, re
from PIL import Image

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
plan = u.js(O / 'native-r22-final-plan.json')
assert len(plan['bindings']) == 148
expected = {
    'elder-asset': ('cf6-elder', [('Cf6ElderAssetTest', 908), ('Cf6ElderCombatEffectsTest', 127), ('Cf6RobotCombatTest elder', 45)]),
    'audio': ('cf6-audio', [('Cf6AudioTest', 340)]),
    'player-aim': ('cf6-player-aim', [('Cf6PlayerAimTest', 1211)]),
    'elder-render': ('cf6-elder-render', [('Cf6ElderRenderTest', 40)]),
}
assert [r['name'] for r in plan['runs']] == list(expected)
suites = []
for name, (run_label, checks) in expected.items():
    folder = O / 'native-r22-final' / name
    result = u.js(folder / 'result.json')
    assert result['exitCode'] == 0 and result['bindingsUnchanged'], name
    before, after = [u.js(folder / ('bindings-' + suffix + '.json')) for suffix in ['before', 'after']]
    assert before == after and len(before) == 148
    for row in before:
        assert u.sha(R / row['path']) == row['sha256'].lower(), row['path']
    trace = u.read(folder / 'flashlog.txt').decode('utf-8-sig').replace('\r\n', '\n')
    starts = re.findall(r'^FocusedTestRunId ' + re.escape(run_label) + r' Start: ([0-9a-f]+)$', trace, re.M)
    ends = re.findall(r'^FocusedTestRunId ' + re.escape(run_label) + r' Complete: ([0-9a-f]+)$', trace, re.M)
    assert len(starts) == len(ends) == 1 and starts == ends, name
    for check, count in checks:
        matches = re.findall(re.escape(check) + r': (\d+) passed, (\d+) failed', trace)
        assert matches == [(str(count), '0')], (check, matches)
    compiler = u.read(folder / 'compiler_errors.txt').decode('utf-8-sig').strip()
    assert compiler == '0 个错误, 0 个警告', compiler
    suites.append({'suite': name, 'runId': starts[0], 'passed': sum(n for _, n in checks),
                   'failed': 0, 'compilerErrors': 0, 'compilerWarnings': 0,
                   'currentBindings': len(before), 'traceSha256': u.sha(folder / 'flashlog.txt'),
                   'testSwfSha256': u.sha(folder / 'TestLoader.swf')})
cleanup = u.js(O / 'native-cleanup-after-r22-final.json')
assert cleanup['ok'] and cleanup['pendingMarkersAbsent'] and cleanup['editorPreserved']
images = u.js(O / 'r22-native-render-verification.json')
assert images['ok'] and images['images'] == 12
equivalence = []
for row in images['files']:
    current = O / row['path']
    prior = O / 'native-r21-captures' / current.name
    with Image.open(current) as a, Image.open(prior) as b:
        same = a.size == b.size and a.mode == b.mode and a.tobytes() == b.tobytes()
    assert same, current.name
    equivalence.append({'image': current.name, 'pixelIdentical': same,
                        'currentSha256': u.sha(current), 'priorSha256': u.sha(prior)})
report = {'ok': True, 'completedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'freshSuites': suites, 'passed': sum(s['passed'] for s in suites), 'failed': 0,
          'currentBindingsPerSuite': 148, 'selectedNativeImages': 12,
          'pixelEquivalenceToR21': equivalence, 'cleanup': cleanup,
          'initialCleanupTimedOut': True, 'cleanupRecoveryFreshlyConfirmed': True,
          'boundary': 'Four fresh real-CS6 suites after the upstream terminal source merge. The first post-suite player-close acknowledgement timed out; its failure and late close receipt are retained, and a new canonical control transaction confirmed closed=false in both phases without deleting a marker or ending the original editor. Earlier focused runs remain historical. Twelve selected draw points are not a full 805-frame scan or human acceptance. The arena C5 loader and R4 candidate are unchanged; this test build does not deploy the new terminal feature.'}
assert report['passed'] == 2671
u.jput(O / 'r22-final-native-assessment.json', report)
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
base = 'current-final-validation/native/'
for source, target in [('native-r22-final', 'four-suites'), ('native-r22-captures', 'selected-images'),
                       ('native-cleanup-after-r22-final-receipts', 'cleanup-receipts'),
                       ('r22-final-native-cleanup-failure-1', 'initial-cleanup-failure')]:
    package.tree(O / source, base + target)
for name in ['native-r22-final-plan.json', 'run-r22-final-native.ps1',
             'finish-native-cleanup-after-r22-final.ps1', 'native-cleanup-after-r22-final.json',
             'verify-r22-native-images.py', 'r22-native-image-verification.log',
             'r22-native-render-verification.json', 'r22-final-native-assessment.json',
             'r22-final-native-wrapper.log', 'native-cleanup-after-r22-final.log',
             'finish-native-cleanup-after-r22-final-retry1.ps1',
             'native-cleanup-after-r22-final-retry1.log', 'r22-final-native-cleanup-retry1-wrapper.log',
             'collect-r22-final-native.py']:
    package.copy(O / name, base + name)
package.copy(P / 'summary.json', 'progress-snapshots/20261018-before-r22-final-native.json')
summary = u.js(P / 'summary.json')
summary.update(updatedAtUtc=report['completedAtUtc'], sealed=False, allGoalsMet=False)
summary['elder'].update(nativeChecksPassed=2671, nativeCheckBoundary=report['boundary'],
                        selectedNativeReport=base + 'r22-final-native-assessment.json')
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
package.copy(P / 'high-level-r22/summary.json', 'progress-snapshots/r22-before-final-native.json')
mechanism = u.js(P / 'high-level-r22/summary.json')
mechanism.update(nativeAudioPlayerAimAndRenderPending=False, finalFreshNativeChecksPassed=2671,
                 finalNativeReport='../' + base + 'r22-final-native-assessment.json')
(P / 'high-level-r22/summary.json').write_text(json.dumps(mechanism, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'ok': True, 'freshPassed': report['passed'], 'selectedImages': 12, 'sealed': False}))
