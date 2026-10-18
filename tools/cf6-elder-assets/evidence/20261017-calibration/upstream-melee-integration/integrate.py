from pathlib import Path
import datetime, hashlib, json, subprocess

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017/upstream-melee-integration'
before = '68473abd27f1d20b13c04f655770745fb42633ba'
target = '1bdc3ccd7382e84839652c2603f7c943ad20c057'
git = lambda *args: subprocess.check_output(['git', *args])
assert git('rev-parse', 'HEAD').decode().strip() == before
assert git('rev-parse', 'origin/main').decode().strip() == target
subprocess.run(['git', 'merge-base', '--is-ancestor', before, target], check=True)
affected = set(filter(None, git('diff', '--name-only', '-z', before, target).decode('utf8').split('\0')))
dirty = set(filter(None, git('diff', 'HEAD', '--name-only', '-z').decode('utf8').split('\0')))
untracked = set(filter(None, git('ls-files', '--others', '--exclude-standard', '-z').decode('utf8').split('\0')))
consumer = 'scripts/asLoader.swf'
assert affected & (dirty | untracked) == {consumer}, affected & (dirty | untracked)
assert not Path(git('rev-parse', '--git-path', 'index.lock').decode().strip()).exists(), 'Preserve an existing Git index lock'
O.mkdir(exist_ok=False)
data = {'local-asLoader.swf': (R / consumer).read_bytes(), 'base-asLoader.swf': git('show', before + ':' + consumer),
        'upstream-asLoader.swf': git('show', target + ':' + consumer), 'index-asLoader.swf': git('show', ':' + consumer)}
for name, blob in data.items():
    (O / name).write_bytes(blob)
index_entry = git('ls-files', '--stage', '--', consumer).decode('utf8').strip()
(O / 'git-status-before.txt').write_bytes(git('status', '--short', '--untracked-files=all'))
(O / 'upstream-diff.patch').write_bytes(git('diff', '--binary', before, target))
(O / 'index-before.bin').write_bytes(Path(git('rev-parse', '--git-path', 'index').decode().strip()).read_bytes())
preparation = {'before': before, 'target': target, 'recordedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'upstreamPaths': sorted(affected), 'localOverlap': [consumer], 'originalIndexEntry': index_entry,
               'swfs': {name: hashlib.sha256(blob).hexdigest() for name, blob in data.items()},
               'boundary': 'The active R15 pilot retains its frozen Worker resources. This integrates Main only and requires a fresh merged-loader publication before further synchronization.'}
(O / 'preparation.json').write_text(json.dumps(preparation, ensure_ascii=False, indent=2), 'utf8')
subprocess.run(['git', 'restore', '--source=HEAD', '--staged', '--worktree', '--', consumer], check=True)
merged = subprocess.run(['git', 'merge', '--ff-only', target], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(O / 'fast-forward.log').write_bytes(merged.stdout)
if merged.returncode:
    assert git('rev-parse', 'HEAD').decode().strip() == before, 'Unexpected HEAD after failed integration'
    assert (R / consumer).read_bytes() == data['base-asLoader.swf'], 'Temporary consumer changed; preserve and inspect'
    (R / consumer).write_bytes(data['local-asLoader.swf'])
    mode, oid, _ = index_entry.split('\t')[0].split()
    subprocess.run(['git', 'update-index', '--cacheinfo', mode + ',' + oid + ',' + consumer], check=True)
    raise SystemExit('Fast-forward failed; exact local consumer and original index entry restored')
assert git('rev-parse', 'HEAD').decode().strip() == target
assert (R / consumer).read_bytes() == data['upstream-asLoader.swf']
result = {'status': 'fast-forward-completed; merged-loader-publication-required', 'before': before, 'head': target,
          'onlyOverlappingPath': consumer, 'originalLocalAndIndexBytesPreserved': True, 'activeWorkerResourcesChanged': False}
(O / 'integration.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps(result))
