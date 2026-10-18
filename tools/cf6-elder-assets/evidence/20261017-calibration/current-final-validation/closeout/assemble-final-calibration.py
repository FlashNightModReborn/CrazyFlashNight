"""Seal only the already accepted current results; Git delivery follows outside this seal."""
from pathlib import Path
import datetime, importlib.util, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
summary = u.js(P / 'summary.json')
assert summary['headbot']['goalMet'] and summary['elder']['goalMet']
elder = u.js(P / 'history/r22-full-awake/acceptance-summary.json')
head = u.js(P / 'history/head-c5-full-awake/strength-summary.json')
assert elder['fullMatrix'] and elder['strengthPassed'] and len(elder['rows']) == 36
assert head['fullMatrix'] and head['strengthPassed'] and head['wins'] == 18 and head['timeouts'] == 0
native = u.js(O / 'r22-final-native-assessment.json')
host = u.js(O / 'host-r22-final/assessment.json')
assert native['ok'] and native['passed'] == 2671 and native['failed'] == 0
assert host['ok'] and host['failed'] == 0 and host['serialPolicyObserved']
display = u.js(O / 'test-round-display-cleanup.json')
assert display['ok'] and display['displayHoldActive'] is False
static = u.js(O / 'final-static-gates/summary.json')
assert static['ok'] and static['sourceUnchanged']
guards = ['prior-sealed-evidence-final.json', 'staged-native-input-verification-final.json',
          'staged-current-input-verification-final-v2.json', 'final-documentation-check-v2.json']
for name in guards:
    assert u.js(O / name)['ok'], name
source_index = u.js(O / 'final-source-preseal-index-v2.json')['files']
source_roles = u.js(O / 'final-source-preseal-index-v2.json')
staged_sources = u.js(O / 'staged-current-input-verification-final-v2.json')
assert all(row['matches'] for row in staged_sources['files'] if row['sourceRole'] == 'strict_checkout_input')
assert all(row['canonicalLfSha256'] == row['gitBlobCanonicalLfSha256'] == row['checkoutCanonicalLfSha256'] and row['explicitCheckoutConversion'] == 'line_endings_only'
           for row in staged_sources['hostCheckoutLineEndingDifferences'])
for row in source_index:
    assert u.sha(R / row['path']) == row['sha256'], row['path']
for row in u.js(O / 'host-r22-final/source-before.json')['files']:
    assert u.sha(R / row['path']) == row['sha256'], row['path']
native_bindings = u.js(O / 'native-r22-final/elder-asset/bindings-before.json')
for row in native_bindings:
    if row['path'] == 'scripts/TestLoader.as':
        assert row['sha256'].lower() == native['cleanup']['originalRunnerSha256'].lower()
    else:
        assert u.sha(R / row['path']) == row['sha256'].lower(), row['path']
state = u.js(O / 'evidence-history-assembly.json')
assert sum(r['label'] == 'r22-full-awake' for r in state['runs']) == 1
assert sum(r['label'] == 'head-c5-full-awake' for r in state['runs']) == 1
package = u.Package(P)
package.mapping = state['mapping']
package.copy(P / 'summary.json', 'progress-snapshots/before-final-seal.json')
source_name = 'current-final-source.zip'
frozen = package.freeze([row['path'] for row in source_index], source_name)
assert frozen == source_index
swf_paths = {'scripts/asLoader.swf', 'flashswf/arts/things-new.swf'}
for family in ['headbot', 'elder', 'bladebot', 'manman', 'wings', 'soldier', 'guard', 'zombie']:
    manifest = u.js(R / ('tools/cf6-' + family + '-assets/native-manifest.json'))
    swf_paths.add(manifest['owner'] + '.swf')
swf_paths.add('flashswf/arts/new/素材库-诺亚新敌人.swf')
swfs = []
for name in sorted(swf_paths):
    assert (R / name).stat().st_size <= 8_000_000, name
    target = 'current-runtime-resources/' + name
    package.copy(R / name, target)
    swfs.append({'source': name, 'copy': target, 'bytes': (R / name).stat().st_size, 'sha256': u.sha(R / name)})
package.tree(O / 'final-static-gates', 'current-final-validation/static')
for name in guards + ['freeze-final-source-index.py', 'assemble-final-calibration.py',
                     'verify-sealed-calibration.py', 'verify-prior-evidence-final.py',
                     'check-staged-current-inputs.py', 'check-staged-native-inputs-final.py',
                     'final-source-preseal-index-v2.json', 'run-final-static-gates.py',
                     'final-documentation-check-v2.log', 'test-round-display-cleanup.json',
                     'check-final-documentation.py', 'prepare-final-stage-pathspec.py', 'inspect-final-scope.py',
                     'preseal-binding-preflight.json', 'record-preseal-binding-preflight.py',
                     'preliminary-staged-current-input-verification-r2.json',
                     'preliminary-staged-current-input-verification-r3.json',
                     'preliminary-stage-20261018.log', 'check-final-documentation-v2.py',
                     'final-documentation-check.json', 'final-documentation-check.log',
                     'preliminary-staged-source-with-host-verification.json',
                     'preliminary-staged-source-with-host-batch-verification.json',
                     'staged-current-input-verification-final.json', 'final-source-preseal-index.json',
                     'git-batch-filter-equivalence.json', 'check-git-batch-filters.py',
                     'check-git-batch-filters-failed-header-assumption.py',
                     'check-staged-current-inputs-individual.py',
                     'verify-prior-evidence-final-index-only-assumption.py',
                     'record-final-source-boundaries.py', 'final-source-boundary-assessment.json',
                     'close-final-display-scope.py', 'head-c5-immediate-display-release.log',
                     'head-c5-full-wrapper.log', 'run-bound-validation.ps1']:
    package.copy(O / name, 'current-final-validation/closeout/' + name)
for name in ['impact.json', 'fast-forward.log', 'upstream-changed-sources.zip',
             'native-plan-before-shared-source-refresh.json']:
    package.copy(O / 'upstream-terminal-integration' / name, 'upstream-terminal-integration/' + name)
package.copy(O / 'upstream-terminal-integration/lock-recovery/recovery.json',
             'upstream-terminal-integration/lock-recovery.json')
closure = {
    'schema': 'cf6-combat-calibration.final-closure.v1',
    'sealedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'gitBaseAtSeal': subprocess.check_output(['git', 'rev-parse', 'HEAD']).decode().strip(),
    'frozenSourceArchive': source_name, 'frozenSourceFiles': len(frozen),
    'sourceCheckoutPolicy': {'strictCheckoutFiles': staged_sources['strictCheckoutFiles'],
        'additionalFrozenHostSourceFiles': len(source_roles['additionalFrozenHostSourcePaths']),
        'explicitExistingHostLineEndingConversions': len(staged_sources['hostCheckoutLineEndingDifferences']),
        'report': 'current-final-validation/closeout/staged-current-input-verification-final-v2.json',
        'boundary': 'The source archive preserves every actual source byte. Additional Host evidence may retain explicitly recorded existing Git line-ending differences, with all raw hashes and a canonical LF comparison. Exact Host-source replay uses the archive; an ordinary checkout is not claimed to reproduce its execution bytes. Gameplay/AS2 and original bound inputs have no such exception.'},
    'restorationOnlyBindings': [{'path': 'scripts/TestLoader.as',
        'sha256': native['cleanup']['originalRunnerSha256'].lower(), 'gitIgnored': True,
        'purpose': 'Private pre-existing scratch original: compared before and after to prove restoration, excluded from the committed-source archive. Actual suite templates and executed test SWFs are preserved in the package.'}],
    'currentSwfs': swfs,
    'selectedArena': [
        {'unit': 'elder', 'path': 'history/r22-full-awake', 'expectedRows': 36},
        {'unit': 'headbot', 'path': 'history/head-c5-full-awake', 'expectedRows': 18},
    ],
    'mergedLoaderClassScopePath': 'upstream-base-siege-integration/base-siege-loader-class-scope.json',
    'nativeReport': 'current-final-validation/native/r22-final-native-assessment.json',
    'hostReport': 'current-final-validation/host/assessment.json',
    'displayClosure': 'display-scopes/final-completed/closure.json',
    'priorIntegrityReport': 'current-final-validation/closeout/prior-sealed-evidence-final.json',
    'scope': 'Current Headbot 472 and Elder 473 -> 474 acceptance under the explicitly requested criteria. Bladebot 465 retains its unchanged-resource historical evidence; no new C5 Bladebot arena execution is claimed.',
    'statusAtSeal': 'validated_ready_for_commit', 'gitDeliveryTrackedOutsideSeal': True,
    'formalRuntimePromoted': False, 'standardEntryVerified': False, 'humanPlayerAcceptance': False,
}
u.jput(P / 'final-closure.json', closure)
summary.update(schema='cf6-combat-calibration.final.v1', status='validated_ready_for_commit',
               updatedAtUtc=closure['sealedAtUtc'], sealed=True, allGoalsMet=True,
               formalRuntimePromoted=False, finalClosure='final-closure.json')
summary['goalScope'] = 'The allGoalsMet flag covers the authorized combat targets and selected machine checks; Git delivery is recorded separately after this immutable package is sealed.'
summary.pop('committed', None)
summary.pop('pushed', None)
summary['gitDelivery'] = {'stateAtSeal': 'validated_ready_for_commit', 'trackedOutsideSeal': True,
                          'reason': 'This immutable evidence package cannot contain the hash of its own future commit. The final conversation and external local Git receipt record commit and push completion.'}
summary['headbot']['subsequentMergedLoaderIntegrationPending'] = False
summary['nextStep'] = {'machineAcceptanceComplete': True, 'displayObservationActive': False,
                       'gitDeliveryAtSeal': 'ready', 'formalPromotionAuthorized': False,
                       'humanAcceptance': 'Player feel, actual audio, weak-machine behavior and standard-entry experience remain separate.'}
summary['history'] = [{**{k: v for k, v in row.items() if k != 'runtimeIdentities'},
                       'selectedForFinalClosure': row['label'] in ['r22-full-awake', 'head-c5-full-awake']}
                      for row in state['runs']]
summary['historySelectionBoundary'] = 'Earlier selection flags record selections at that historical step. Only selectedForFinalClosure names the two current matrices in final-closure.json.'
summary['historyRows'] = sum(row['rows'] for row in state['runs'])
summary['evidenceBoundary'] = 'The selected 54 current-candidate fights satisfy their explicit matrix criteria. All historical rows, failures, interrupted attempts and original identities remain preserved. Machine acceptance does not sign off player feel, physical audio, weak-machine performance, standard-entry experience or formal runtime deployment.'
summary['currentBindings'] = [{'path': row['source'], 'bytes': row['bytes'], 'sha256': row['sha256']} for row in swfs]
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
sealed = package.finish()
state['sealed'] = True
state['finalClosure'] = closure
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'ok': True, 'sealed': True, 'currentArenaRows': 54,
                  'historyRows': summary['historyRows'], 'sourceFiles': len(frozen), **sealed}))
