"""Seal this bounded CF6 change after native checks and all owned arena runs finish."""
from pathlib import Path
import hashlib,importlib.util,json,re,sys,zlib
ROOT=Path.cwd();TMP=ROOT/'tmp/cf6-combat-audio-20261017';OUT=ROOT/'tools/cf6-audio/evidence/20261017-combat-audio'
spec=importlib.util.spec_from_file_location('cf6_evidence',ROOT/'tmp/cf6-elder-20261016/evidence_utils.py')
u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
config=u.js(TMP/'delivery-inputs.json')
assert not OUT.exists(),'Preserve the sealed package'
assert u.sha(TMP/'before-source.zip')==u.js(TMP/'before-source-index.json')['archiveSha256']
assert not any((ROOT/'scripts'/name).exists() for name in ['compile_state_uncertain.marker','testloader_scratch_inflight.marker','compile_target.cfg','compile_mode.cfg'])
assert u.sha(ROOT/'scripts/TestLoader.as')=='e38e2151bf619814a0ea65bf2b19d11d8f78a7704787c47c046666acee2f090b'
assert u.js(TMP/config['cleanup'])['ok'] is True
tests=[]
for entry in config['nativeRuns']:
    folder=TMP/entry['folder'];result=u.js(folder/'result.json');trace=u.read(folder/'flashlog.txt').decode('utf-8-sig').replace('\r\n','\n')
    assert result['exitCode']==0 and result['bindingsUnchanged'],entry
    before=u.js(folder/'bindings-before.json');after=u.js(folder/'bindings-after.json');assert before==after
    assert u.read(folder/'compiler_errors.txt').decode('utf-8-sig').strip()=='0 个错误, 0 个警告'
    start=re.findall(r'^FocusedTestRunId (\S+) Start: (\w+)$',trace,re.M);end=re.findall(r'^FocusedTestRunId (\S+) Complete: (\w+)$',trace,re.M)
    assert len(start)==1 and end==start and '[TEST_FAIL]' not in trace,entry
    totals=[]
    for pattern in entry['patterns']:
        matches=re.findall(pattern,trace,re.M);assert len(matches)==1,(entry,pattern)
        totals.append(int(matches[0]))
    snapshots={r['path']:r for r in before}
    for rel in entry['executedConsumers']:
        assert snapshots[rel]['sha256'].lower()==u.sha(ROOT/rel),'Executed consumer changed: '+rel
    differences=[{'path':r['path'],'testedSha256':r['sha256'],'currentSha256':u.sha(ROOT/r['path'])}
        for r in before if u.sha(ROOT/r['path'])!=r['sha256'].lower()]
    tests.append({**entry,'runId':start[0][1],'passedAssertions':sum(totals),'failedAssertions':0,
        'testSwfSha256':u.sha(folder/'TestLoader.swf'),'bindingsStableDuringRun':True,
        'postRunDifferences':differences,'sourceBoundary':'The original before/after snapshots and test binary are retained. Actual loaded consumer SWFs must match current bytes. Later changes to other consumers, metadata or capture-only inputs are listed and are not upgraded to re-execution.'})
builds=[]
for entry in config['builds']:
    folder=TMP/entry['folder'];identity=u.js(folder/'identity.json');assert identity['exitCode']==0
    assert u.read(folder/'compiler_errors.txt').decode('utf-8-sig').strip()=='0 个错误, 0 个警告'
    assert u.sha(ROOT/entry['consumer'])==identity['sha256'].lower()==u.sha(folder/'candidate.swf')
    builds.append({**entry,'sha256':identity['sha256'].lower(),'bytes':identity['bytes']})
if '--native-only' in sys.argv:
    print(json.dumps({'nativeRuns':len(tests),'builds':len(builds),
        'behaviorAssertions':sum(t['passedAssertions'] for t in tests if t['kind']=='behavior'),
        'renderAssertions':sum(t['passedAssertions'] for t in tests if t['kind']=='render'),
        'allCurrentConsumersMatch':True,'postRunDifferences':[{'folder':t['folder'],'differences':len(t['postRunDifferences'])} for t in tests]}))
    raise SystemExit(0)
assert u.js(TMP/'arena-final-cleanup.json')['ok'] is True
package=u.Package(OUT);arena=[]
for entry in config['arenaRuns']:
    report,rows,identities=package.collect(entry['label'],entry['experimentId'],TMP/entry['planFolder'],require_qualified=True)
    assert report['status']=='completed' and not report['errors']
    for group in report['groups']:
        assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
        for outcome in group['outcomes']:
            assert outcome['status']=='completed' and all(outcome[k] for k in ['cleanupVerified','protectedSavesVerified','runtimeResourcesVerified'])
    assert len(rows)==entry['expectedRows'] and all(not row['errors'] for row in rows)
    for identity in identities:assert identity['runtimeMode']=='isolated_candidate'
    u.jput(OUT/entry['label']/'all-results.json',rows)
    arena.append({**entry,'rows':len(rows),'finished':sum(r['status']=='finished' for r in rows),
        'timeouts':sum(r['status']=='timeout' for r in rows),'candidateWins':sum(r['winner']==r['authorityContext']['candidateSide'] for r in rows),
        'candidateLosses':sum(r['winner']==('red' if r['authorityContext']['candidateSide']=='blue' else 'blue') for r in rows),'draws':sum(r['winner']=='draw' for r in rows),
        'experimentQualified':report['qualified'],'runtimeIdentities':identities,'saveProtectionAndCleanupVerified':True})
paths={r['path'] for r in u.js(TMP/'before-source-index.json')['files'] if (ROOT/r['path']).is_file()}
paths.add('agentsDoc/art-asset-assembly.md')
for family in ['headbot','elder','bladebot','manman','wings','soldier','guard','zombie']:
    folder=ROOT/('tools/cf6-'+family+'-assets');manifest=u.js(folder/'native-manifest.json')
    for item in manifest.get('buildInputs',[]):
        if (ROOT/item['path']).is_file():paths.add(item['path'])
    for base in [folder,ROOT/manifest['owner']]:
        for p in base.rglob('*'):
            if p.is_file() and 'evidence' not in p.parts and '__pycache__' not in p.parts:paths.add(p.relative_to(ROOT).as_posix())
    approved=list(manifest.get('approvedInputs',{}).values())
    if manifest.get('approvedInput'):approved.append(manifest['approvedInput'])
    for rel in approved:
        for p in (ROOT/rel).rglob('*'):
            if p.is_file():paths.add(p.relative_to(ROOT).as_posix())
    donor=manifest.get('donor',{})
    if donor.get('path'):paths.add(donor['path'])
    for row in donor.get('members',[]):
        if row.get('path'):paths.add(row['path'])
for p in (ROOT/'tools/cf6-audio').glob('*'):
    if p.is_file():paths.add(p.relative_to(ROOT).as_posix())
for name in ['head-final-plan1.json','blade-final-plan1.json','legacy-audio-plan1.json','audio-legacy-final-plan.json']:
    paths.update(u.js(TMP/name)['bindings'])
for p in (ROOT/'flashswf/arts/new/素材库-诺亚新敌人').rglob('*'):
    if p.is_file():paths.add(p.relative_to(ROOT).as_posix())
for p in (ROOT/'scripts').glob('run-cf6-*.ps1'):paths.add(p.relative_to(ROOT).as_posix())
for r in u.js(ROOT/'tools/cf6-audio/assets.json')['files']:paths.add(r['path'])
paths.add('sounds/export/人物/soundheadexplode.wav')
sourceIndex=package.freeze(paths,'current-source.zip')
for row in builds:package.copy(ROOT/row['consumer'],'current-swfs/'+Path(row['consumer']).name)
originalAudio=ROOT/'tmp/cf6-headbot-20261016/original-source.swf'
assert u.sha(originalAudio)==u.js(ROOT/'tools/cf6-audio/cues.json')['sourceSwfSha256']
package.copy(originalAudio,'original-cf6/source.swf')
# Preserve every attempt, including failed capture, stale fixture check and initial audio duplication.
package.tree(TMP,'attempts')
for family,folder in config['finalImages'].items():
    for image in (TMP/folder).glob('*.png'):package.copy(image,'images/'+family+'/'+image.name)
package.copy(TMP/config['visualReview'],'image-review.json')
package.copy(TMP/config['audioAudit'],'audio-audit.json')
package.copy(TMP/config['arenaSummary'],'arena-summary.json')
package.copy(TMP/'head-death-preview.png','images/head-death-preview.png')
package.copy(TMP/'head-death-preview.json','images/head-death-preview.json')
summary={'schema':'cf6.combat-audio.delivery.v1','state':'candidate_executed','nativeRuns':tests,'builds':builds,
    'behaviorAssertions':sum(t['passedAssertions'] for t in tests if t['kind']=='behavior'),
    'renderAssertions':sum(t['passedAssertions'] for t in tests if t['kind']=='render'),
    'nativeImages':24,'arenaRuns':arena,'totalArenaRows':sum(x['rows'] for x in arena),
    'sourceSnapshotScope':'Current asset sources, supplied artwork, generators, edited XFL, selected validation inputs and actual SWFs. Host runtime identity remains bound by each isolated-candidate receipt; this is not a full repository or formal producer bundle.',
    'audioAudit':'audio-audit.json','arenaSummary':'arena-summary.json','frozenCurrentSourceFiles':len(sourceIndex),
    'qualification':{'newMechanicsNativeBehavior':True,'nativeImageAgentReview':True,'nativeEndpointListening':False,
        'humanAestheticAcceptance':False,'balanceCalibrationComplete':False,'formalRuntimePromotion':False,'standardEntryVerified':False},
    'constraints':{'allNewSoundCalls':'_root.播放音效','newEmbeddedSoundTracks':0,'cf6ConsumerEmbeddedStartSounds':0,'unrelatedExistingLibrarySoundTracksRetained':True,'realPlayerSaveWrites':False,'commitOrPush':False},
    'retainedFailures':'All attempts, render failures, duplicate-voice failures, stale fixture checks, negative arena rows and recovery receipts are preserved under attempts and arena folders.'}
u.jput(OUT/'summary.json',summary);result=package.finish();print(json.dumps(result))
