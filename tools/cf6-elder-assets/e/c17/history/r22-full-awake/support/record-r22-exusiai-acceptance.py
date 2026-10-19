from pathlib import Path
import datetime, importlib.util, json

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
E = R / 'tmp/arena-worker-experiments/cf6-cal-r22-full-20261018'
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
assert not (P / 'integrity.json').exists()
old = u.js(O / 'r22-beast-acceptance-addendum.json')
profile = 'high-level-beast-near-death-exusiai-net-hp-minority-wins-v2'
started = u.js(E / 'execution-started.json')
assert started['frozenPlanHash'] == old['frozenPlanHash']
for row in u.js(O / 'arena-r22-full/input-identity.json')['sourceBindings']:
    assert u.sha(R / row['path']) == row['sha256'], row['path']
scope = {**old, 'profile': profile,
         'recordedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'userInstructionAtUtc': '2026-10-18T09:52:24.866223Z',
         'userInstruction': '整体达标即可，允许少量胜局',
         'questionAnswered': 'EXUSIAI 的 50%–80% 交换目标，是要求每场都落败，还是按整体表现判断、允许少量胜局？当前 60 级六场平均净削血 57.65%、中位 53.19%，其中五负一胜；我会继续完成其余等级并保留全部结果。',
         'previousScopeFile': 'r22-beast-acceptance-addendum.json',
         'previousScopeSha256': u.sha(O / 'r22-beast-acceptance-addendum.json'),
         'exusiaiCriterion': 'Each six-row group mean and median full-chain net HP loss is 50-80 percent. A small number of naturally finished wins is allowed; losses must remain a strict majority in each group. No draws, timeouts, missing phase handoffs or execution errors.',
         'smallNumberInterpretation': 'Strict minority of wins in each six-row group: at most two wins and at least four losses. This conservative operational interpretation was stated in the response as each group remaining predominantly losses; the user did not prescribe a numeric cap.',
         'winsAllowed': {'beast': 0, 'exusiai': 'strict minority per six-row group'},
         'supersedesOnly': 'EXUSIAI zero-win requirement in the previous acceptance addendum. The Beast criterion and 60/80/100 level scope remain unchanged; the original frozen plan and both prior criteria are retained.',
         'frozenPlanFileSha256': u.sha(E / 'frozen-plan.json'),
         'productionSourceBindingsUnchanged': True,
         'boundary': 'Human-requested acceptance clarification after some results were observed. This is recorded explicitly and does not claim that the original zero-win criterion was met. No battle condition, source, resource, result or runtime identity was changed.'}
u.jput(O / 'r22-exusiai-acceptance-addendum.json', scope)
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
for name in ['r22-exusiai-acceptance-addendum.json', 'before-r22-exusiai-acceptance.zip', 'record-r22-exusiai-acceptance.py']:
    package.copy(O / name, 'high-level-r22/acceptance-clarification/' + name)
package.copy(P / 'summary.json', 'progress-snapshots/before-r22-exusiai-clarification.json')
summary = u.js(P / 'summary.json')
summary['elder'].update(target='60/80/100 full 36-row matrix. Beast reaches observed initial-form rage or first-form defeat, then loses naturally in every row. EXUSIAI each six-row mean and median net HP loss is 50-80 percent, with a small minority of wins allowed and losses remaining the majority. No draws or timeouts.',
                        acceptanceAddendum='high-level-r22/acceptance-clarification/r22-exusiai-acceptance-addendum.json',
                        acceptanceProfile=profile)
summary['updatedAtUtc'] = scope['recordedAtUtc']
(P / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf8')
package.copy(P / 'high-level-r22/summary.json', 'progress-snapshots/r22-before-exusiai-clarification.json')
mechanism = u.js(P / 'high-level-r22/summary.json')
mechanism.update(acceptanceProfile=profile, exusiaiCriterion=scope['exusiaiCriterion'],
                 exusiaiClarification='acceptance-clarification/r22-exusiai-acceptance-addendum.json')
(P / 'high-level-r22/summary.json').write_text(json.dumps(mechanism, ensure_ascii=False, indent=2), 'utf8')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'recorded': True, 'productionUnchanged': True, 'profile': profile, 'sealed': False}))
