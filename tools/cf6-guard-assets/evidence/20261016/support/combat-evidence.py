"""Freeze completed two-Worker threat evidence without replaying any game action."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import statistics
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
UNIT_SWF = 'flashswf/arts/new/Codex光头保安素材.swf'
TEST_SOURCE = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6GuardAssetTest.as'


def disk(path):
    value = str(Path(path).absolute())
    if os.name == 'nt' and not value.startswith('\\\\?\\'):
        value = '\\\\?\\UNC\\' + value[2:] if value.startswith('\\\\') else '\\\\?\\' + value
    return Path(value)


def read(path):
    return json.loads(disk(path).read_text(encoding='utf-8-sig'))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('experiment', 'inputs', 'native-dir', 'native-log', 'publish-log', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=ROOT)
    args = parser.parse_args()
    out = args.output.resolve()
    assert out.is_relative_to(HERE / 'evidence') and not out.exists(), 'Fresh owned evidence directory required'
    experiment = args.experiment.resolve()
    report = read(experiment / 'experiment-report.json')
    frozen = read(experiment / 'frozen-plan.json')
    inputs = read(args.inputs / 'input-identity.json')
    assert report['status'] == 'completed' and report['qualified'] is True
    assert report['frozenPlanHash'] == frozen['frozenPlanHash']
    assert all(g['globalSaveUnchanged'] and g['seedSourcesUnchanged'] for g in report['groups'])
    out.mkdir(parents=True)
    copies = []

    def copy(source, relative, expected=None):
        source = Path(source)
        data = disk(source).read_bytes()
        digest = sha(data)
        if expected:
            assert digest == expected.removeprefix('sha256:').lower(), str(source)
        target = out / relative
        assert target.resolve().is_relative_to(out)
        if disk(target).exists():
            assert disk(target).read_bytes()==data
            return data
        disk(target.parent).mkdir(parents=True, exist_ok=True)
        disk(target).write_bytes(data)
        assert disk(target).read_bytes() == data
        copies.append(dict(path=Path(relative).as_posix(), originalPath=str(source), bytes=len(data), sha256=digest))
        return data

    def source(relative, expected=None):
        rel = Path(relative)
        assert not rel.is_absolute() and '..' not in rel.parts
        for base in (args.source_root, ROOT):
            candidate = base / rel
            if disk(candidate).is_file() and (expected is None or sha(disk(candidate).read_bytes()) == expected.lower()):
                return candidate
        raise AssertionError('No matching preserved source: ' + relative)

    for name in ('experiment-report.json', 'frozen-plan.json', 'measurement.json', 'expected-receipts.json'):
        copy(experiment / name, 'coordinator/' + name)
    for group in frozen['groups']:
        for name in ('group-report.json', 'save-protection.json'):
            copy(experiment / 'groups' / group['groupId'] / name, 'coordinator/' + group['groupId'] + '/' + name)
    copy(args.inputs / 'input-identity.json', 'input-identity.json')
    copy(args.inputs / 'experiment-plan.json', 'experiment-plan.json')
    trace = copy(args.native_dir / 'test-flashlog.txt', 'native/trace.txt').decode('utf-8-sig').replace('\r\n', '\n')
    starts = re.findall(r'^FocusedTestRunId cf6-guard Start: (\w+)$', trace, re.M)
    ends = re.findall(r'^FocusedTestRunId cf6-guard Complete: (\w+)$', trace, re.M)
    assert len(starts) == 1 and starts == ends
    result = re.findall(r'Cf6GuardAssetTest: (\d+) passed, (\d+) failed; (\d+) actual timeline cases', trace)
    assert len(result) == 1 and result[0][1] == '0' and int(result[0][2]) == 22
    for name in ('publish-compiler_errors.txt', 'test-compiler_errors.txt'):
        text = copy(args.native_dir / name, 'native/' + name).decode('utf-8-sig').strip()
        assert text == '0 个错误, 0 个警告'
    for name in ('publish-compile_output.txt', 'test-compile_output.txt'):
        copy(args.native_dir / name, 'native/' + name)
    log = copy(args.native_log, 'native/run.log').decode('utf-8-sig')
    assert '32K retry=0' in log and '[OK] cf6-guard:' in log
    copy(args.publish_log, 'native/publish.log')
    for binding in inputs['sourceBindings']:
        candidate = source(binding['path'], binding['sha256'])
        if binding['path'] == UNIT_SWF or binding['path'] == 'flashswf/arts/new/Codex特种兵素材.swf' or binding['path'].startswith('tools/cf6-guard-assets/') \
                or binding['path'] in ('scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as',
                    'data/enemy_properties/CF6重制敌人.xml','data/units/units.json','data/items/asset_source_map.xml'):
            copy(candidate, 'source/' + binding['path'], binding['sha256'])
    for rel in (TEST_SOURCE, 'scripts/TestLoader.swf',
                'tools/cf6-guard-assets/native-manifest.json', 'tools/cf6-guard-assets/worker-plan.js',
                'tools/cf6-guard-assets/build.py','tools/cf6-guard-assets/balance.py',
                'tools/cf6-guard-assets/balance-inputs.json',
                'tools/cf6-guard-assets/verify.py','scripts/run-cf6-guard-asset-tests.ps1',
                'scripts/test-runners/cf6-guard/TestLoader-capture.as.template'):
        copy(source(rel), 'source/' + rel)
    native_manifest = read(source('tools/cf6-guard-assets/native-manifest.json'))
    archive = out / 'source/guard-project.zip'
    project = Path('flashswf/arts/new/Codex光头保安素材')
    with zipfile.ZipFile(disk(archive), 'x', compression=zipfile.ZIP_DEFLATED) as z:
        for entry in native_manifest['outputs'] + native_manifest['projectFiles']:
            data = disk(source((project / entry['path']).as_posix(), entry['sha256'])).read_bytes()
            z.writestr(entry['path'], data)
    with zipfile.ZipFile(disk(archive)) as z:
        assert z.testzip() is None
    archives = [dict(path=archive.relative_to(out).as_posix(), bytes=disk(archive).stat().st_size,
                     sha256=sha(disk(archive).read_bytes()), entries=len(native_manifest['outputs'] + native_manifest['projectFiles']))]
    all_rows, identities, cases, seen = [], [], {}, set()
    for group in frozen['groups']:
        for job in group['jobs']:
            receipt_path = Path(job['expectedReceiptPath'])
            receipt = read(receipt_path)
            outcome = next(o for g in report['groups'] for o in g['outcomes'] if o['jobId'] == job['jobId'])
            assert all(outcome[k] for k in ('cleanupVerified', 'protectedSavesVerified', 'runtimeResourcesVerified'))
            assert not outcome['forcedRecycling'] and not receipt['errors']
            assert receipt['resourcesUnchanged'] and receipt['runtimeUnchanged']
            worker_dir = 'workers/' + job['workerId']
            copy(receipt_path, worker_dir + '/receipt.json', outcome['receiptSha256'])
            raw = copy(receipt['resultPath'], worker_dir + '/results.jsonl', receipt['resultSha256'])
            assert sha(disk(receipt['sourceResultPath']).read_bytes()) == sha(raw)
            manifest = read(receipt_path.parent / 'manifest.json')
            copy(receipt_path.parent / 'manifest.json', worker_dir + '/manifest.json', receipt['manifestSha256'])
            copy(receipt_path.parent / 'launch.json', worker_dir + '/launch.json', receipt['launchSha256'])
            rows = [json.loads(line) for line in raw.decode('utf-8').splitlines() if line.strip()]
            assert len(rows) == receipt['expectedRunCount'] == receipt['rows']
            for row in rows:
                for field in ('workerId', 'sessionEpoch', 'assignmentId', 'attemptId', 'batchId', 'manifestHash'):
                    assert row[field] == receipt[field]
                case = next(c for c in manifest['cases'] if c['caseId'] == row['caseId'])
                assert row['caseHash'] == case['caseHash']
                key = (row['workerId'], row['caseId'], row['repeatIndex'])
                assert key not in seen and 1 <= row['repeatIndex'] <= case['repeat']
                seen.add(key)
                context = case['authorityContext']
                side = context['candidateSide']
                guard = row[side + 'UnitResults'][0]
                soldier = row[('blue' if side == 'red' else 'red') + 'UnitResults'][0]
                assert guard['identifier'] == '敌人-CF6光头保安' and soldier['identifier'] == '敌人-CF6特种兵'
                item = dict(worker=row['workerId'], caseId=row['caseId'], repeatIndex=row['repeatIndex'],
                    level=guard['level'], weapon=context['weapon'], guardSide=side, winner=row['winner'],
                    status=row['status'], frames=row['frames'], guardStartHp=guard['startMaxHp'],
                    guardRemainHp=guard['remainHp'], soldierStartHp=soldier['startMaxHp'], soldierRemainHp=soldier['remainHp'],
                    soldierHpMultiplier=context['soldierHpMultiplier'],
                    soldierDamagePercent=100 * (1 - soldier['remainHp'] / soldier['startMaxHp']))
                all_rows.append(item)
                cases.setdefault((side,guard['level'],context['weapon']),[]).append(item)
            identities.append(receipt['runtimeIdentity'])
    assert len(all_rows) == inputs['expectedRows']
    groups = []
    for (side,level,weapon),rows in cases.items():
        damage=[r['soldierDamagePercent'] for r in rows]
        groups.append(dict(guardSide=side,level=level,weapon=weapon,samples=len(rows),
            guardWins=sum(r['winner']==side for r in rows),naturalFinishes=sum(r['status']=='finished' for r in rows),
            soldierHpMultiplier=rows[0]['soldierHpMultiplier'],
            soldierDamagePercent=dict(min=min(damage),max=max(damage),mean=statistics.mean(damage))))
    summary = dict(schema='cf6-guard.threat-evidence.v1', experimentId=report['experimentId'],
        qualified=True, native=dict(runId=starts[0], passed=int(result[0][0]), failed=0, cases=int(result[0][2]),
            compilerErrors=0, compilerWarnings=0, retry32K=0),
        sourceBindings=inputs['sourceBindings'], runtimeIdentities=identities, rows=all_rows, groups=groups,
        protectedSavesUnchanged=True, resourcesUnchanged=True, ownedProcessesExited=True,
        physicalWorkers=len(frozen['workers']), wallDurationMs=sum(g['wallDurationMs'] for g in report['groups']),
        copies=copies, archives=archives,
        sourceCoverage='Guard changed sources, native XFL, test SWF and both combat unit SWFs copied; shared inputs remain hash-bound repository files.',
        boundaries=['Guard blue versus normal enemy soldier is the base comparison; reverse-side soldier triple HP is separate.', 'No RNG equivalence or speed-up benchmark is claimed.',
                    'Candidate combat evidence is not formal runtime deployment or human visual/gameplay acceptance.'])
    (out / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(output=str(out), rows=len(all_rows), groups=groups), ensure_ascii=False))


if __name__ == '__main__':
    main()
