from evidence_utils import *

review = js(TMP/'review-candidate-r15.json')
assert review['revision'] == 'r15' and review['games'] == 36 and review['wins'] == 0 and review['timeouts'] == 0
assert not review['balanceCalibrationComplete'] and not review['humanAcceptance'] and review['r16NotExecuted']
report = js(ROOT/'tmp/arena-worker-experiments/elder-r15-matrix-20261017/experiment-report.json')
assert report['qualified'] and report['status'] == 'completed' and report['completedGroups'] == 6 and not report['errors']
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:
        assert outcome['status'] == 'completed' and all(outcome[key] for key in ['cleanupVerified', 'protectedSavesVerified', 'runtimeResourcesVerified'])
saved = []
for index, name in enumerate(['headbot-combat', 'headbot-combat2'], 1):
    root = Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for row in js(TMP/'matrix-r15/input-identity.json')['sourceBindings']:
        assert sha(root/row['path']) == row['sha256']
    for log in ['launcher.log', 'launcher.log.1', 'bootstrap.log']:
        source = root/'logs'/log
        if source.is_file():
            target = TMP/('review-r15-w'+str(index)+'-'+log)
            put(target, read(source))
            saved.append({'source':str(source), 'target':target.name, 'sha256':sha(target)})
put(TMP/'stop-elder-audit-r12.marker', b'User requested handoff for human move review. All combat complete and protection checks passed.\n')
jput(TMP/'review-worker-logs-r15.json', {'files':saved, 'experimentCleanupVerified':True,
    'observerStopRequested':True, 'displayRequestRetainedForPackaging':True})
print(json.dumps({'savedLogs':len(saved), 'observerStopRequested':True}))
