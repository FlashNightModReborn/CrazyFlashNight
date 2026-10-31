"""Project the main-story ally Lee and full-scene assault roster into the playable chapter.

Run without arguments to regenerate; --check verifies exact derived bytes.
Combat facts come from the existing stage XML and unit catalog. Story events,
account rewards and enemy loot are deliberately outside this temporary trial.
"""
from pathlib import Path
import argparse
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'data/stages/books/lee-trial.json'
ALLY_STAGE = 'data/stages/黑铁会总部/黑铁会黑龙堂外围.xml'
COMBAT_STAGE = 'data/stages/黑铁会总部/黑铁会黑龙堂内部.xml'


def value(node):
    children = list(node)
    if children:
        result = {}
        for child in children:
            item = value(child)
            if child.tag in result:
                if not isinstance(result[child.tag], list):
                    result[child.tag] = [result[child.tag]]
                result[child.tag].append(item)
            else:
                result[child.tag] = item
        return result
    text = (node.text or '').strip()
    if text in ('true', 'false'):
        return text == 'true'
    try:
        return int(text)
    except ValueError:
        return text


def opening_waves(extras, original):
    # Preserve every guard, spreading each kind across two dense, mixed waves.
    from copy import deepcopy
    buckets, seen = [[], []], {}
    for enemy in extras:
        key = (enemy['Type'], enemy['Level'])
        bucket = buckets[seen.get(key, 0) % 2]
        seen[key] = seen.get(key, 0) + 1
        entry = deepcopy(enemy)
        entry['SpawnIndex'] = 'right' if len(bucket) % 2 == 0 else 'left'
        bucket.append(entry)
    buckets[1].extend(deepcopy(enemy) for wave in original for enemy in wave['EnemyGroup']['Enemy'])
    result = []
    for bucket in buckets:
        compact = {}
        for enemy in bucket:
            fields = {k:v for k,v in enemy.items() if k != 'Quantity'}
            key = json.dumps(fields, ensure_ascii=False, sort_keys=True)
            if key not in compact:
                compact[key] = dict(fields, Quantity=0)
            compact[key]['Quantity'] += enemy['Quantity']
        entries = list(compact.values())
        assert 0 < len(entries) <= 8 and all(1 <= e['Quantity'] <= 12 for e in entries)
        result.append(dict(WaveInformation=dict(Duration=0), EnemyGroup=dict(Enemy=entries)))
    assert [sum(e['Quantity'] for e in wave['EnemyGroup']['Enemy']) for wave in result] == [10, 10]
    return result


def build(root=ROOT):
    units = json.loads((root / 'data/units/units.json').read_text(encoding='utf-8-sig'))
    ally = next(u for u in units if u['id'] == 257)
    assert ally['spritename'] == '敌人-李小龙' and ally['is_hostile'] is False
    from unit_registry import UnitRegistry
    registry = UnitRegistry(units)
    appearances = [e for e in ET.parse(root / ALLY_STAGE).findall('.//Enemy') if e.findtext('Type') in ('兵种257', ally.get('key'))]
    levels = {int(e.findtext('Level')) for e in appearances}
    assert len(appearances) == 5 and levels == {35}, 'Review changed story-ally balance before regenerating this baseline'
    assert all(e.find('Parameters') is None for e in appearances), 'Review new ally overrides before regenerating'
    actor = dict(identifier=ally['spritename'], name=ally['name'], level=levels.pop(),
                 height=ally['height'], gender='男')
    stages = []
    source = ET.parse(root / COMBAT_STAGE)
    for index, source_stage in enumerate(source.findall('SubStage')):
        basic = value(source_stage.find('BasicInformation'))
        background = Path(basic['Background']).name
        assert background == f'hthhltnb_{(3, 2, 4, 5)[index]}_BG.swf'
        # Story backgrounds show the aftermath. Lee's assault uses untouched original art.
        basic['Background'] = 'flashswf/backgrounds/black-dragon-original/' + background
        basic['EndFrame'] = '房间'
        waves = []
        for source_wave in source_stage.findall('Wave/SubWave'):
            enemies = []
            for source_enemy in source_wave.findall('EnemyGroup/Enemy'):
                enemy = value(source_enemy)
                if 'Type' in enemy:
                    enemy['Type'] = registry.resolve_type(str(enemy['Type']))
                params = enemy.get('Parameters', {})
                # Match ObjectUtil.cloneParameters: original text key/value pairs
                # are valid. Keep nested keys inert rather than promoting typos.
                if isinstance(params, str):
                    parsed = {}
                    for pair in params.split(','):
                        parts = pair.split(':')
                        if len(parts) == 2:
                            key, item = parts
                            try:
                                numeric = float(item)
                                item = int(numeric) if numeric.is_integer() else numeric
                            except ValueError:
                                item = True if item == 'true' else False if item == 'false' else item
                            parsed[key] = item
                    params = parsed
                assert isinstance(params, dict)
                params.update(不掉钱=True, 不掉装备=True, 最小经验值=0, 最大经验值=0, 掉落物=[])
                enemy['Parameters'] = params
                enemies.append(enemy)
            waves.append(dict(WaveInformation=value(source_wave.find('WaveInformation')),
                              EnemyGroup=dict(Enemy=enemies)))
        stages.append(dict(BasicInformation=basic, Wave=dict(SubWave=waves),
            Event=[dict(EventName='Start', Message='黑龙堂冷却试战 ' + str(index + 1) + '/4：J截击／跑+J连击，空格小跳（2.5秒）；35级无龙息、无补给，血量连续。')],
            Instances=dict(Instance=[]), Pickups=dict(Pickup=[])))
    assert len(stages) == 4
    assert sum(e['Quantity'] for s in stages for w in s['Wave']['SubWave'] for e in w['EnemyGroup']['Enemy']) == 10
    assault = json.loads((root / 'data/books/lee-assault-rules.json').read_text(encoding='utf-8'))
    assert len(assault['corpseRosters']) == len(stages)
    for index, stage in enumerate(stages):
        roster = assault['corpseRosters'][index]
        extras = []
        for row in roster['units'] + (assault.get('finalReserve', []) if index == 3 else []):
            assert any(u['id'] == row['type'] for u in units)
            for count in range(row['count']):
                extras.append(dict(Type='兵种'+str(row['type']), Level=row['level'], Quantity=1,
                    SpawnIndex='right' if count % 2 == 0 else 'left', Interval=450,
                    Parameters=dict(不掉钱=True, 不掉装备=True, 最小经验值=0, 最大经验值=0, 掉落物=[])))
        # Ordinary guards arrive in groups. The two original room-3 hammers remain together.
        source_waves = stage['Wave']['SubWave']
        groups = [dict(WaveInformation=dict(Duration=0),EnemyGroup=dict(Enemy=extras[i:i+5]))
                  for i in range(0,len(extras),5)]
        if index == 0:
            stage['Wave']['SubWave'] = opening_waves(extras, source_waves)
        elif index == 3:
            # A second pair of inner-hall guards accounts for the final pair, rather than reviving prior kills.
            original = source_waves[0]['EnemyGroup']['Enemy']
            for enemy in original:
                if enemy['Type'] == '兵种68': enemy['Parameters'].update(魔法抗性=dict(电=300),称号='黑龙堂主')
            final = [dict(Type='兵种269',Level=35,Quantity=2,SpawnIndex='right',Interval=450,
                Parameters=dict(不掉钱=True, 不掉装备=True,最小经验值=0,最大经验值=0,掉落物=[],称号='内堂亲卫'))]
            # Final wave includes Black Dragon, his two guards and at least one mob group concurrently.
            tail = groups.pop()['EnemyGroup']['Enemy'] if groups else []
            stage['Wave']['SubWave'] = groups + [dict(WaveInformation=dict(Duration=0),EnemyGroup=dict(Enemy=original+final+tail))]
        else:
            stage['Wave']['SubWave'] = groups + source_waves
        stage['Event'] = [dict(EventName='Start',Message='攻入黑龙堂 · '+str(index+1)+'/4')]
    dialogue = json.loads((root / 'data/books/lee-assault-dialogue.json').read_text(encoding='utf-8'))
    required_beats = set()
    required_beats.add('lee-entry-0')
    required_beats.add('lee-clear-0')
    required_beats.add('lee-after-0')
    required_beats.add('lee-after-0-dodged')
    required_beats.add('lee-after-0-revived')
    required_beats.add('lee-entry-1')
    required_beats.add('lee-entry-1-revived')
    required_beats.add('lee-clear-1')
    required_beats.add('lee-clear-1-observe')
    required_beats.add('lee-clear-1-revived')
    required_beats.add('lee-awaken-early')
    required_beats.add('lee-after-1')
    required_beats.add('lee-after-1-dodged')
    required_beats.add('lee-after-1-revived')
    required_beats.add('lee-entry-2-awakened')
    required_beats.add('lee-entry-2')
    required_beats.add('lee-entry-2-revived')
    required_beats.add('lee-clear-2-awakened')
    required_beats.add('lee-clear-2')
    required_beats.add('lee-clear-2-observe')
    required_beats.add('lee-clear-2-revived')
    required_beats.add('lee-after-2-awakened')
    required_beats.add('lee-awaken-late')
    required_beats.add('lee-after-2')
    required_beats.add('lee-entry-3-early')
    required_beats.add('lee-entry-3-late')
    required_beats.add('lee-clear-3')
    required_beats.add('lee-after-3')
    assert dialogue['schema'] == 'lee-assault-dialogue.v1' and set(dialogue['beats']) == required_beats
    for rows in dialogue['beats'].values():
        assert isinstance(rows,list) and 1 <= len(rows) <= 6
        assert all(row['name'] in ('Lee', '黑龙') and row['char'] == row['name'] and isinstance(row['text'],str)
                   and 0 < len(row['text']) <= 500 for row in rows)
    public_rules = {k:v for k,v in assault.items() if k not in ('corpseRosters','finalReserve')}
    public_rules['dialogues'] = dialogue['beats']
    return dict(schema='lee-trial.v1', id='lee-trial', stageName='Lee攻入黑龙堂',
                actor=actor, assault=public_rules, stages=stages)


def payload(root=ROOT):
    return (json.dumps(build(root), ensure_ascii=False, indent=2) + '\n').encode('utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = payload()
    manifest = json.loads((ROOT / 'flashswf/backgrounds/black-dragon-original/source-manifest.json').read_text(encoding='utf-8'))
    assert manifest['unmodifiedSourceBytes'] is True
    import hashlib
    for row in manifest['files']:
        background = ROOT / 'flashswf/backgrounds/black-dragon-original' / row['file']
        assert background.stat().st_size == row['bytes']
        assert hashlib.sha256(background.read_bytes()).hexdigest() == row['sha256']
    if args.check:
        assert OUT.read_bytes() == expected, 'Lee baseline is stale; regenerate from owning source data'
    else:
        OUT.write_bytes(expected)
    print('Lee assault: canonical Lv35 ally, full-scene guard roster, story rules ' + ('verified' if args.check else 'written'))
