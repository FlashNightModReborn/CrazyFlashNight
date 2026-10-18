from pathlib import Path
import importlib.util,json,sys,re,hashlib,zipfile,io,zlib
ROOT=Path(__file__).resolve().parents[2]
TMP=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('feedback_evidence_utils',ROOT/'tmp/cf6-elder-20261016/evidence_utils.py')
util=importlib.util.module_from_spec(spec);spec.loader.exec_module(util)
config=json.loads(Path(sys.argv[1]).read_text('utf-8-sig'))
OUT=ROOT/'tools/cf6-elder-assets/evidence/20261017-playtest'
assert not OUT.exists(),'Preserve prior package'
assert util.sha(TMP/'baseline-source.zip')==util.js(TMP/'baseline-source.index.json')['zipSha256']
package=util.Package(OUT)
# Every accepted test is a unique terminal native run with strict current compiler diagnostics.
tests=[]
for entry in config['tests']:
    folder=TMP/entry['folder'];trace=(folder/'flashlog.txt').read_text('utf-8-sig')
    compiler=(folder/'compiler_errors.txt').read_text('utf-8-sig').strip()
    result=util.js(folder/'result.json');assert result['exitCode']==0,result
    entry={**entry,'perRunSourceBindingsCaptured':(folder/'bindings-before.json').exists()}
    if (folder/'bindings-before.json').exists():
        assert result['bindingsUnchanged'] and util.js(folder/'bindings-before.json')==util.js(folder/'bindings-after.json')
        post_run_capture_changes=[]
        raw_test=util.read(folder/'TestLoader.swf')
        test_body=zlib.decompress(raw_test[8:]) if raw_test[:3]==b'CWS' else raw_test[8:]
        allowed=set(config.get('captureOnlyChangesAfterBehavior',[]))
        for row in util.js(folder/'bindings-after.json'):
            current=util.sha(ROOT/row['path'])
            if current!=row['sha256'].lower():
                assert row['path'] in allowed,row['path']
                if row['path'].endswith('.as'):
                    assert Path(row['path']).stem.encode() not in test_body,'Changed class is present in this test binary'
                elif row['path'].endswith('.as.template'):
                    excluded=config['captureOnlyTemplateClasses'][row['path']]
                    assert excluded.encode() not in test_body,'Changed capture template suite is present in this test binary'
                else:assert row['path'].endswith('/decode-native-capture.py')
                post_run_capture_changes.append({'path':row['path'],'testedSnapshotSha256':row['sha256'].lower(),'currentSha256':current,
                    'reason':'capture-only class absent from this TestLoader, or offline pixel decoder; runtime and executed test sources unchanged'})
        entry={**entry,'postRunCaptureOnlyChanges':post_run_capture_changes}
    assert compiler=='0 个错误, 0 个警告',(entry['folder'],compiler)
    assert re.search(entry['pattern'],trace),entry
    for pattern in entry.get('additionalPatterns',[]):assert re.search(pattern,trace),(entry,pattern)
    assert '[TEST_FAIL]' not in trace and '32K' not in compiler
    starts=re.findall(r'FocusedTestRunId ([a-z0-9-]+) Start: ([0-9a-f]+)',trace)
    ends=re.findall(r'FocusedTestRunId ([a-z0-9-]+) Complete: ([0-9a-f]+)',trace)
    assert len(starts)==len(ends)==1 and starts==ends,(entry,starts,ends)
    tests.append({**entry,'runId':starts[0][1],'domain':starts[0][0],
        'traceSha256':util.sha(folder/'flashlog.txt'),'testSwfSha256':util.sha(folder/'TestLoader.swf')})
# Match the exact resource and loader builds selected after all fixes.
builds=[]
for entry in config['builds']:
    folder=TMP/entry['folder'];identity=util.js(folder/'identity.json')
    assert identity['exitCode']==0
    assert util.sha(ROOT/identity['swf'])==identity['sha256'].lower()
    assert util.sha(folder/'candidate.swf')==identity['sha256'].lower()
    assert (folder/'compiler_errors.txt').read_text('utf-8-sig').strip()=='0 个错误, 0 个警告'
    builds.append({**identity,'evidence':entry['folder']})
# Reuse the baseline selection and include every newly added owned source and fixture.
paths={r['path'] for r in util.js(TMP/'baseline-source.index.json')['files'] if (ROOT/r['path']).is_file()}
folders=['tools/cf6-headbot-assets','tools/cf6-elder-assets','tools/cf6-bladebot-assets',
 'flashswf/arts/new/Codex大头机器人素材','flashswf/arts/new/Codex老头素材','flashswf/arts/new/Codex大刀机器人素材',
 'scripts/test-runners/cf6-playtest','scripts/test-runners/cf6-player-aim']
for folder in folders:
    for path in (ROOT/folder).rglob('*'):
        if path.is_file() and not any(part in ('evidence','__pycache__','bin') for part in path.relative_to(ROOT/folder).parts):paths.add(path.relative_to(ROOT).as_posix())
paths.update(['scripts/类定义/org/flashNight/arki/component/Buff/Effect/ElderBeamVulnerability.as',
 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6PlayerAimTest.as',
 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as',
 'scripts/run-cf6-player-aim-tests.ps1','scripts/test-runners/cf6-knockback-scope/EnemyKnockbackFixture.as',
 'tools/cf7-balance-tool/data/monster-flag-ledger.json'])
for entry in config['tests']:
    bindings=TMP/entry['folder']/'bindings-after.json'
    if bindings.exists():paths.update(row['path'] for row in util.js(bindings))
source_index=package.freeze(paths,'current-source-and-assets.zip')
# Preserve raw successful and failed attempts; large streams are reversibly mapped below 8 MB.
for folder in sorted(TMP.iterdir()):
    if folder.is_dir() and folder.name.startswith(('baseline-player-aim-','build-pass','native-tests-pass','render-pass','render-stop','render-projector','source-attempt','runtime-smoke','head-preview')):
        package.tree(folder,'attempts/'+folder.name)
for path in sorted(TMP.glob('*.ps1')):package.copy(path,'commands/'+path.name)
for path in sorted(TMP.glob('*.py')):
    if path.name!='freeze-feedback.py':package.copy(path,'commands/'+path.name)
for path in sorted(TMP.glob('*-plan*.json')):package.copy(path,'commands/'+path.name)
for path in sorted(TMP.glob('*.as.template')):package.copy(path,'commands/'+path.name)
for entry in config.get('recoveryFolders',[]):package.tree(ROOT/entry,'recovery/'+Path(entry).name)
for name in ['baseline-source.zip','baseline-source.index.json','corpse-resting-bound.json']:
    package.copy(TMP/name,'before-and-diagnostics/'+name)
package.tree(TMP/'user-report','user-report')
for entry in config['imageFolders']:
    package.tree(TMP/entry['source'],'images/'+entry['name'])
for name in config.get('extraReceipts',[]):package.copy(TMP/name,'checks/'+Path(name).name)
package.copy(Path(__file__),'packaging/freeze-feedback.py')
package.copy(ROOT/'tmp/cf6-elder-20261016/evidence_utils.py','packaging/evidence_utils.py')
package.copy(Path(sys.argv[1]),'packaging/accepted-inputs.json')
summary={'schema':'cf6.playtest-feedback.v1','state':'candidate_executed','executionScope':'isolated Flash TestLoader resources and production-class fixtures',
 'asLoaderState':'compiled','formalRuntimePromoted':False,'standardEntryVerified':False,'humanAcceptance':False,
 'newFullCombatMatrixExecuted':False,'targetNetHpExchangePercent':[50,80],'balanceCalibrationComplete':False,
 'builds':builds,'tests':tests,'sourceFiles':len(source_index),'changes':config['changes'],
 'failedAttemptsRetained':True,'oldSealedPackagesModified':False,
 'limitations':['Actual player input, aesthetic and feel acceptance remains human.','Older R15 36-match statistics do not qualify the new two-beam kit.','Point trajectory fixture is narrower than a rendered piercing bullet; it is not a full projectile-factory lifecycle test.']}
summary['renderCoverage']=config.get('renderCoverage',{})
summary['humanAcceptanceState']='pending'
util.jput(OUT/'summary.json',summary)
package.bytes(('# 2026-10-17 CF6 试玩反馈证据\n\n此包保存这轮角色资源、共享逻辑编译、实际 Flash 回归、原生关键帧，以及全部失败尝试。当前结论是隔离候选执行与专项验证；标准入口、操作手感和新招式的 50%–80% 血量交换目标仍待人工验收。\n\n- [本轮摘要](summary.json)\n- [源码与资源清单](current-source-and-assets.zip.index.json)\n- [无损映射](lossless-mapping.json)\n- [逐文件完整性](integrity.json)\n\n旧 R15 和两份机器人的已封存证据不在本轮改写。`attempts` 保留修复前的失败，不能把其中的旧产物当作当前通过版本。文件超过 8,000,000 字节时自动 gzip 或分片；无损映射记录原始字节数、SHA-256 和重建顺序。\n').encode('utf8'),'README.md','package overview')
receipt=package.finish()
assert all(p.stat().st_size<=8_000_000 for p in util.lp(OUT).rglob('*') if p.is_file())
util.jput(TMP/'package-created.json',{'directory':str(OUT),**receipt,'tests':len(tests),'builds':len(builds)})
print(json.dumps({'directory':str(OUT),**receipt,'tests':len(tests),'builds':len(builds)},ensure_ascii=False))
