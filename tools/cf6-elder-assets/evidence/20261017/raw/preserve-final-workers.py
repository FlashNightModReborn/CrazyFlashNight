from evidence_utils import *
import re, sys

revision = sys.argv[1]
assert re.fullmatch(r'r\d+', revision)
report = js(ROOT/'tmp/arena-worker-experiments'/('elder-'+revision+'-matrix-20261017')/'experiment-report.json')
assert report['qualified'] and report['status'] == 'completed' and report['completedGroups'] == 6 and not report['errors']
review = js(TMP/('final-field-review-'+revision+'.json'))
assert review['games'] == 36 and review['wins'] == 0 and review['timeouts'] == 0
assert review['minimumOpponentRemainingHpPercent'] >= 15
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:
        assert outcome['status'] == 'completed' and all(outcome[k] for k in ['cleanupVerified', 'protectedSavesVerified', 'runtimeResourcesVerified'])
saved = []
for index, name in enumerate(['headbot-combat', 'headbot-combat2'], 1):
    base = Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log', 'launcher.log.1', 'bootstrap.log']:
        source = base/'logs'/log
        if source.is_file():
            target = TMP/('final-'+revision+'-w'+str(index)+'-'+log)
            put(target, read(source))
            saved.append({'source':str(source), 'target':target.name, 'sha256':sha(target)})
put(TMP/'stop-elder-audit-r12.marker', b'Final matrix completed and protection checks passed; stop the owned read-only observer.\n')
jput(TMP/('final-worker-logs-'+revision+'.json'), {'revision':revision, 'files':saved, 'experimentCleanupVerified':True})
print(json.dumps({'savedLogs':len(saved), 'observerStopRequested':True, 'displayRequestRetainedForPackaging':True}))
