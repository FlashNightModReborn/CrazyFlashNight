from pathlib import Path
import datetime, hashlib, json, shutil, subprocess
R=Path.cwd(); O=R/'tmp/cf6-combat-calibration-20261017'; D=O/'loader-size-followup'
P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
W=Path('C:/Users/fs/.codex/worktrees/headbot-combat/CrazyFlashNight')
load=lambda p:json.loads(p.read_text('utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert load(D/'native/completion.json')['ok']
assert load(D/'inputs-after.json')['unchanged']
assert load(D/'c5-c6-class-scope.json')['qualified']
assert sha(R/'scripts/asLoader.swf')==sha(D/'publish/asLoader.swf')
assert sha(W/'scripts/asLoader.swf')==sha(D/'asLoader-c5.swf'),'Worker is not the known idle C5 consumer'
sources={}
for history in ['r22-full-awake','head-c5-full-awake']:
    for row in load(P/'history'/history/'plan/input-identity.json')['sourceBindings']:
        if row['path'] in sources:assert sources[row['path']]==row['sha256']
        sources[row['path']]=row['sha256']
for name,digest in sources.items():
    assert sha(W/name)==digest,name
    if name!='scripts/asLoader.swf':assert sha(R/name)==digest,name
shutil.copy2(W/'scripts/asLoader.swf',D/'worker-before-c5.swf')
shutil.copy2(R/'scripts/asLoader.swf',W/'scripts/asLoader.swf')
bindings=[]
for name,digest in sources.items():
    now=sha(W/name)
    assert now==sha(R/name),name
    if name!='scripts/asLoader.swf':assert now==digest,name
    bindings.append({'path':name,'beforeSha256':digest,'afterSha256':now,'changed':now!=digest})
with (D/'worker-sync.json').open('x',encoding='utf8') as f:json.dump({
    'createdAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'workerRoot':str(W),
    'qualified':True,'onlyChangedBinding':'scripts/asLoader.swf','bindings':bindings},f,ensure_ascii=False,indent=2)
for kind,old_config,tool,expected in [('head','arena-head-current-config.json','cf6-headbot-assets',6),('elder','arena-r22-full-config.json','cf6-elder-assets',12)]:
    cfg=load(O/old_config)
    cfg.update(experimentId=f'cf6-loader-c6-{kind}-20261018',outputDirectory=str(D/f'arena-{kind}'),repeat=1)
    with (D/f'{kind}-config.json').open('x',encoding='utf8') as f:json.dump(cfg,f,ensure_ascii=False,indent=2)
    subprocess.run(['node',f'tools/{tool}/arena-plan.js',str(D/f'{kind}-config.json')],check=True)
    identity=load(D/f'arena-{kind}/input-identity.json')
    assert identity['expectedRows']==expected
    with (D/f'arena-{kind}/preregistered-purpose.json').open('x',encoding='utf8') as f:json.dump({
        'createdAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'purpose':'Current C6 loader bootstrap and combat integration after a function-size repair. No tuning or new full-strength acceptance claim.',
        'expectedRows':expected,'levels':cfg['levels'],'repeatPerSide':1,'fullStrengthMatrix':False,
        'naturalCompletionRequired':True,'timeoutsAllowed':0,'elderTransitionExactlyOnce':kind=='elder',
        'displayLog':str(O/'display-qualified-20261018-r10/display-state.jsonl'),
        'maximumConcurrentGames':1,'formalPromotion':False,'c5FullCalibrationCommit':'dabd11a89570125b6fe2125aa45b5ccaf2d60cd2'},f,ensure_ascii=False,indent=2)
print('C6 current resource sync and 6+12 bounded integration plans frozen.')
