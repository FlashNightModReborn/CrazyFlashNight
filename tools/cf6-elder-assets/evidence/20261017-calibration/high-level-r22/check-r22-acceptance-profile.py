from pathlib import Path
import hashlib,importlib.util,json,zipfile
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
area=O/'r22-analysis-profile-test';area.mkdir(exist_ok=False)
with zipfile.ZipFile(O/'before-r22-high-level-budget.zip')as z:
    old=z.read('tools/cf6-elder-assets/analyze-arena.py')
(area/'legacy-analyzer.py').write_bytes(old)
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
legacy=module('legacy_elder_analysis',area/'legacy-analyzer.py')
current=module('current_elder_analysis',R/'tools/cf6-elder-assets/analyze-arena.py')
raw=json.loads((P/'history/r14-full-awake/all-results.json').read_text('utf8'))
worker=Path('C:/Users/fs/.codex/worktrees/headbot-combat/CrazyFlashNight')
before=legacy.analyze(raw,worker);after=current.analyze(raw,worker)
assert before['fullMatrix'] and len(raw)==36
assert after['expectedLevels']==[30,60,99]
assert {k:v for k,v in after.items() if k!='expectedLevels'}==before
different=current.analyze(raw,worker,expected_levels=[60,80,100])
assert not different['fullMatrix'] and not different['strengthPassed'] and different['rows']==before['rows']
rejected=[]
for levels in [[],[60,80],[60,60,100],[60,80,101],[True,80,100]]:
    try:current.analyze([],worker,expected_levels=levels)
    except ValueError:rejected.append(levels)
    else:raise AssertionError(levels)
sha=lambda b:hashlib.sha256(b).hexdigest()
report={'ok':True,'legacyFullMatrixRows':len(raw),'legacyDefaultResultsUnchanged':True,
        'legacyMatrixCannotBeRelabeledAsNewProfile':True,'newProfile':[60,80,100],
        'invalidProfilesRejected':rejected,'legacyAnalyzerSha256':sha(old),
        'currentAnalyzerSha256':sha((R/'tools/cf6-elder-assets/analyze-arena.py').read_bytes()),
        'sourceResultsSha256':sha((P/'history/r14-full-awake/all-results.json').read_bytes()),
        'boundary':'Read-only analysis compatibility and profile-selection checks using preserved historical rows. No new fight was executed and no old result was replaced.'}
with(O/'r22-acceptance-profile-check.json').open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':True,'legacyRowsUnchanged':36,'invalidProfilesRejected':len(rejected),'newProfileRequiresFreshRows':True}))
