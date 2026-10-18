from pathlib import Path
import datetime,hashlib,json,shutil,subprocess,zipfile
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';D=O/'loader-size-followup'
E=R/'tmp/arena-worker-experiments/cf6-loader-c6-elder-20261018'
load=lambda p:json.loads(Path('\\\\?\\'+str(p.resolve())).read_text('utf-8-sig'))
report=load(E/'experiment-report.json')
assert report['status']=='unqualified' and not report['qualified'] and not report['errors']
failed=[(g,o) for g in report['groups'] for o in g['outcomes'] if o['status']!='completed']
assert len(failed)==1 and failed[0][0]['groupId']=='beastking-level100'
g,o=failed[0];assert o['cleanupVerified'] and o['protectedSavesVerified'] and o['runtimeResourcesVerified']
assert g['globalSaveUnchanged'] and g['seedSourcesUnchanged']
p=Path(o['expectedReceiptPath']);receipt=load(p)
assert receipt['resultPath'] is None and receipt['resultSha256'] is None and receipt['rows']==0
assert receipt['runtimeUnchanged'] and receipt['resourcesUnchanged']
assert receipt['shutdown']['hostExited'] and receipt['shutdown']['flashExited']
assert len(receipt['errors'])==2 and all(x['message']=='Worker endpoint ownership probe unavailable; no credential was sent' for x in receipt['errors'])
assert not any(x['phase']=='batch_start' for x in receipt['hostProcessObservations'])
assert 'observedResultPath' not in receipt
W=Path(receipt['projectRoot'])
archive=next((W/'logs').glob('diagnostic-cf7_agent_aw_4b16a43ca71c4d3ea2a4e6a47044c2f9-*.zip'))
private=O/'cf6-loader-c6-failed100-private';private.mkdir(exist_ok=False)
shutil.copy2(archive,private/archive.name)
with zipfile.ZipFile(archive) as z:log=z.read('logs/launcher.log')
(private/'launcher.log').write_bytes(log)
source_files=['tools/arena-calibration/lib/arena-worker-endpoint.js','tools/arena-calibration/lib/arena-worker-client.js','tools/arena-calibration/run-worker-shard.js']
proof={'qualifiedForFreshIsolatedRetry':True,'failedExperiment':report['experimentId'],'failedGroup':g['groupId'],
    'errors':receipt['errors'],'resultPath':None,'rows':0,'startAcknowledgementObserved':False,
    'batchStartedAtIsPreRequestTimestamp':True,'failureOccursBeforeCredentialReadAndHttpTransport':True,
    'ownershipProbeCause':'Unknown nonzero/terminated probe process; the existing sanitized error does not distinguish exit failure from its 15000ms timeout.',
    'hostAndFlashExited':True,'protectedSavesUnchanged':True,'resourcesUnchanged':True,
    'privateArchiveSha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'privateLogSha256':hashlib.sha256(log).hexdigest(),
    'boundary':'Preserve the failed attempt; do not mark it completed, reuse its session, replay persistence writes, bypass endpoint ownership, or change its timeout. Only run the missing two isolated arena cases under a new identity.',
    'sourceBindings':[{'path':n,'sha256':hashlib.sha256((R/n).read_bytes()).hexdigest()} for n in source_files]}
(D/'failed100-assessment.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n','utf8')
for name in source_files:
    dest=D/'failed100-source'/Path(name).name;dest.parent.mkdir(exist_ok=True);shutil.copy2(R/name,dest)
cfg=load(D/'elder-config.json');cfg.update(experimentId='cf6-loader-c6-b100-retry1-20261018',outputDirectory=str(D/'arena-elder-retry'),levels=[100],rivals=['beastking'],repeat=1)
with (D/'elder-retry-config.json').open('x',encoding='utf8') as f:json.dump(cfg,f,ensure_ascii=False,indent=2)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(D/'elder-retry-config.json')],check=True)
purpose={'purpose':'Fresh isolated execution of the two missing level-100 Beast cases after a pre-transport Worker ownership probe failure; retain the original failed attempt.',
    'expectedRows':2,'fullStrengthMatrix':False,'replacesFailedResult':False,'failedAssessmentSha256':hashlib.sha256((D/'failed100-assessment.json').read_bytes()).hexdigest(),
    'displayLog':str(O/'display-qualified-20261018-r11/display-state.jsonl'),'registeredAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
(D/'arena-elder-retry/preregistered-purpose.json').write_text(json.dumps(purpose,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'prepared':True,'rows':2,'originalFailurePreserved':True}))
