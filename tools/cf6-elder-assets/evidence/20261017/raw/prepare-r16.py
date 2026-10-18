from evidence_utils import *
import re, statistics, subprocess

report = js(ROOT/'tmp/arena-worker-experiments/elder-r15-matrix-20261017/experiment-report.json')
assert report['qualified'] and report['status'] == 'completed' and report['completedGroups'] == 6 and not report['errors']
rows = []
for group in report['groups']:
    assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
    for outcome in group['outcomes']:
        assert outcome['status'] == 'completed' and all(outcome[k] for k in ['cleanupVerified', 'runtimeResourcesVerified', 'protectedSavesVerified'])
        receipt = js(outcome['expectedReceiptPath'])
        assert sha(outcome['expectedReceiptPath']) == outcome['receiptSha256'].removeprefix('sha256:')
        assert receipt['runtimeUnchanged'] and receipt['resourcesUnchanged'] and not receipt['errors']
        assert sha(receipt['resultPath']) == receipt['resultSha256'].removeprefix('sha256:')
        rows.extend(json.loads(line) for line in read(receipt['resultPath']).decode('utf-8-sig').splitlines() if line)
assert len(rows) == 36 and len({(r['batchId'], r['runId']) for r in rows}) == 36
stats = []
for rival in [78, 361]:
    for level in [30, 60, 99]:
        subset = [r for r in rows if r['authorityContext']['rivalUnitId'] == rival and r['authorityContext']['level'] == level]
        assert len(subset) == 6
        for side in ['blue', 'red']:
            assert {r['repeatIndex'] for r in subset if r['authorityContext']['candidateSide'] == side} == {1, 2, 3}
        values = []; wins = 0
        for row in subset:
            side = row['authorityContext']['candidateSide']; other = 'red' if side == 'blue' else 'blue'
            assert row['status'] == 'finished' and row['winner'] in ['blue', 'red'] and not row['errors'] and row['phaseSpawnCount'] == 1
            assert len(row['spawnedUnits']) == 1 and row['spawnedUnits'][0]['unit'] == '敌人-CF6老头机器人'
            wins += int(row['winner'] == side)
            values.append(100*(1-row[other]['remainHp']/row[other]['startMaxHp']))
        stats.append({'rival':rival, 'level':level, 'wins':wins, 'netLoss':values, 'min':min(values),
                      'mean':statistics.mean(values), 'median':statistics.median(values), 'max':max(values)})
# This proposal only addresses high-level excess. Unexpected low-level excess or
# weak groups require review instead of silently applying a pre-written plan.
assert all(r['mean'] >= 25 and r['median'] >= 25 for r in stats), 'Review newly weak R15 groups before reducing growth'
assert all(r['max'] <= 85 and r['wins'] == 0 for r in stats if r['level'] in [30, 60]), 'Review lower-level excess before reducing growth'
assert next(r for r in stats if r['rival'] == 361 and r['level'] == 99)['max'] > 85
jput(TMP/'r15-matrix-review.json', {'games':36, 'wins':sum(r['wins'] for r in stats), 'groups':stats, 'acceptedAsFinal':False,
    'originalWorkingCriterionMet':all(r['mean'] >= 25 and r['median'] >= 25 and r['wins'] == 0 for r in stats),
    'fifteenPercentWinnerMarginMet':all(r['max'] <= 85 for r in stats)})
for index, name in enumerate(['headbot-combat', 'headbot-combat2'], 1):
    root = Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for log in ['launcher.log', 'launcher.log.1', 'bootstrap.log']:
        source = root/'logs'/log
        if source.is_file(): put(TMP/('r15-matrix-final-w'+str(index)+'-'+log), read(source))
for file in TMP.glob('live-elder-audit-r*.jsonl'): put(TMP/('r15-matrix-final-'+file.name), read(file))
bindings = js(TMP/'matrix-r15/input-identity.json')['sourceBindings']
for row in bindings: assert sha(ROOT/row['path']) == row['sha256'], 'Unexpected R15 source drift: '+row['path']
for row in js(TMP/'native-r15-evidence.json')['sourceBindings']:
    assert sha(ROOT/row['path']) == row['sha256'], 'Unexpected native drift: '+row['path']
for relative in ['tools/cf6-elder-assets/balance.py', 'tools/cf6-elder-assets/balance-inputs.json',
                 'data/enemy_properties/CF6重制敌人.xml', 'tools/cf6-elder-assets/README.md']:
    put(TMP/'r15-before-balance'/relative, read(ROOT/relative))
file = ROOT/'tools/cf6-elder-assets/balance.py'; old = read(file).decode('utf8')
needle = "'growth':1,'attackBias':2,'defenseBias':34}"
assert old.count(needle) == 1
file.write_text(old.replace(needle, "'growth':0.9,'attackBias':2,'defenseBias':34}"), encoding='utf8', newline='\n')
subprocess.run(['python', '-X', 'utf8', '-B', str(file), '--write'], cwd=ROOT, check=True)
subprocess.run(['python', '-X', 'utf8', '-B', str(file)], cwd=ROOT, check=True)
changed_bindings = {row['path'] for row in bindings if sha(ROOT/row['path']) != row['sha256']}
assert changed_bindings == {'data/enemy_properties/CF6重制敌人.xml', 'tools/cf6-elder-assets/balance-inputs.json'}
robot_pattern = r'<敌人-CF6老头机器人>.*?</敌人-CF6老头机器人>'
before_xml = read(TMP/'r15-before-balance/data/enemy_properties/CF6重制敌人.xml').decode('utf8')
after_xml = read(ROOT/'data/enemy_properties/CF6重制敌人.xml').decode('utf8')
assert re.subn(robot_pattern, '<OWN_ROBOT/>', before_xml, flags=re.S) == re.subn(robot_pattern, '<OWN_ROBOT/>', after_xml, flags=re.S)
previous_inputs = js(TMP/'r15-before-balance/tools/cf6-elder-assets/balance-inputs.json')
current_inputs = js(ROOT/'tools/cf6-elder-assets/balance-inputs.json')
assert previous_inputs['human'] == current_inputs['human']
assert [key for key in previous_inputs['robot']['flags'] if previous_inputs['robot']['flags'][key] != current_inputs['robot']['flags'][key]] == ['成长系数']
readme = ROOT/'tools/cf6-elder-assets/README.md'; text = read(readme).decode('utf8')
before = '当前候选为 R15：行为与发布 SWF 为 R15，配表沿用 R14。'
assert text.count(before) == 1
text = text.replace(before, '当前候选为 R16：行为与发布 SWF 沿用 R15，配表为 R16。')
before = '机器人成长 1.0、高攻低血防 2、高防低血 34。机器人成长 1.0 用于补足高等级压力，30 级面板几乎不变；'
assert text.count(before) == 1
text = text.replace(before, '机器人成长 0.9、高攻低血防 2、高防低血 34。机器人成长 0.9 用于收回 R15 高等级对局过近的取胜边界，30 级面板几乎不变；')
failures = []
for row in stats:
    name = '兽王' if row['rival'] == 78 else '指挥官'
    if row['mean'] < 25 or row['median'] < 25:
        failures.append(f"{row['level']} 级{name}均值／中位数 {row['mean']:.2f}%／{row['median']:.2f}% 未同时达线")
    if row['wins'] or row['max'] > 85:
        failures.append(f"{row['level']} 级{name}出现 {row['wins']} 胜、最大净失血 {row['max']:.2f}%，胜方最少余血 {100-row['max']:.2f}%")
wins = sum(row['wins'] for row in stats)
history = f"R15 完整 36 场为 {wins} 胜、{36-wins} 负；"+'；'.join(failures)+'。R16 仅将机器人成长从 1.0 收至 0.9，保留高防低血 34、R15 光束收招、全部伤害倍率与用户指定阶段／档次。按同一公式，30 级面板几乎不变，99 级 HP／攻击／防御从 27549／7231／7224 收至 26545／6874／6580；这只是公式预估，完整两对手、三等级矩阵仍须重跑，不用预估替代战斗证据。\n\n'
needle = '工作判据在 R8 开跑前选定：'; assert text.count(needle) == 1
text = text.replace(needle, history+needle)
readme.write_text(text, encoding='utf8', newline='\n')
changed = []
for name in ['headbot-combat', 'headbot-combat2']:
    root = Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
    for relative in ['tools/cf6-elder-assets/balance.py', 'tools/cf6-elder-assets/balance-inputs.json', 'data/enemy_properties/CF6重制敌人.xml']:
        destination = lp(root/relative); before = sha(destination)
        assert before == sha(TMP/'r15-before-balance'/relative), 'Unexpected owned Worker drift: '+relative
        data = read(ROOT/relative); destination.write_bytes(data); assert sha(destination) == digest(data)
        changed.append({'root':str(root), 'path':relative, 'beforeSha256':before, 'sha256':digest(data)})
    for row in bindings: assert sha(root/row['path']) == sha(ROOT/row['path']), 'Declared Worker input drift: '+row['path']
jput(TMP/'worker-copy-r16.json', {'scope':'Only robot growth 1.0 to 0.9. R15 native assets, all measured flags, other allocations and user C/D unchanged. All 17 declared inputs verified; prior offline helper exclusions remain explicit.', 'files':changed})
config = js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r16-matrix-20261017', repeat=3, levels=[99, 30, 60], rivals=['exusiai', 'beastking'], outputDirectory=str(TMP/'matrix-r16'))
jput(TMP/'matrix-r16-config.json', config)
subprocess.run(['node', 'tools/cf6-elder-assets/arena-plan.js', str(TMP/'matrix-r16-config.json')], cwd=ROOT, check=True)
frozen = Package(TMP/'r16-frozen-inputs')
frozen.freeze(row['path'] for row in js(TMP/'r15-frozen-inputs/frozen-inputs.zip.index.json')['files'])
print(json.dumps({'priorGroups':stats, 'growth':0.9, 'r16FrozenInputs':frozen.finish()}, ensure_ascii=False))
