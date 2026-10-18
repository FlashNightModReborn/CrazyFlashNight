from evidence_utils import *
import subprocess

report=js(ROOT/'tmp/arena-worker-experiments/elder-r11-matrix-20261017/experiment-report.json')
assert report['qualified'] and report['status']=='completed' and report['completedGroups']==6 and not report['errors']
review=js(TMP/'r11-matrix-review.json');assert review['games']==36 and not review['acceptedAsFinal']
assert '当前候选为 R12' in read(ROOT/'tools/cf6-elder-assets/README.md').decode('utf8')
for row in js(TMP/'native-r12-evidence.json')['sourceBindings']:assert sha(ROOT/row['path'])==row['sha256']
index=js(TMP/'r11-frozen-inputs/frozen-inputs.zip.index.json')['files']
own=lambda path:path.startswith(('tools/cf6-elder-assets/','flashswf/arts/new/Codex老头素材/')) or path in [
    'flashswf/arts/new/Codex老头素材.swf','scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as']
allowed_non_runtime={
    'scripts/test-runners/cf6-knockback-scope/EnemyKnockbackFixture.as',
    'scripts/test-runners/cf6-knockback-scope/TestLoader.as.template',
    'tools/asset-metrology/xfl_geometry.py','tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py'}
changed=[];unchanged=[];excluded=[]
for name in ['headbot-combat','headbot-combat2']:
    root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for row in index:
        relative=row['path'];target=lp(root/relative);current=sha(ROOT/relative)
        old=sha(target) if target.is_file() else None
        if not own(relative):
            if old!=current:
                assert relative in allowed_non_runtime,'Unexpected non-Elder drift: '+relative
                excluded.append({'root':str(root),'path':relative,'workerSha256':old,'canonicalSha256':current,
                    'reason':'Offline test fixture or source-generation helper; not executed by the arena and not a declared runtime/source binding; canonical build source remains frozen.'})
            continue
        if old==current:
            unchanged.append({'root':str(root),'path':relative,'sha256':current})
            continue
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(read(ROOT/relative))
        assert sha(target)==current
        changed.append({'root':str(root),'path':relative,'beforeSha256':old,'sha256':current})
    for row in js(TMP/'matrix-r11/input-identity.json')['sourceBindings']:
        assert sha(root/row['path'])==sha(ROOT/row['path']),'Declared input mismatch: '+row['path']
jput(TMP/'worker-copy-r12.json',{'scope':'Complete resumed R12 Elder-only synchronization after verified R11 exit. The prior failed synchronization had already copied three native Elder files in worker 1; those are included in verified-identical entries. Offline shared helper differences remain explicit and are not runtime proof.',
    'files':changed,'verifiedIdentical':unchanged,'excludedOfflineSources':excluded})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r12-matrix-20261017',repeat=3,levels=[99,30,60],outputDirectory=str(TMP/'matrix-r12'))
jput(TMP/'matrix-r12-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'matrix-r12-config.json')],cwd=ROOT,check=True)
frozen=Package(TMP/'r12-frozen-inputs');frozen.freeze(row['path'] for row in index)
print(json.dumps({'changedFiles':len(changed),'excludedOfflineSources':len(excluded),'r12FrozenInputs':frozen.finish()},ensure_ascii=False))
