"""Analyze frozen Elder arena rows without changing the original receipts."""
from pathlib import Path
from evidence_paths import validate_output
import argparse
import hashlib
import json
import math
import re
import statistics
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL_XML = 'data/enemy_properties/原版敌人 2013-2016.xml'
SKYNET_XML = 'data/enemy_properties/天网.xml'
LEVEL_SOURCE = 'scripts/引擎/引擎_lsy_等级与经验值.as'
FORMULA_SOURCE = 'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'
SUPPORTING_SOURCES = (
    ORIGINAL_XML, SKYNET_XML, LEVEL_SOURCE, FORMULA_SOURCE,
    'scripts/类定义/org/flashNight/arki/merc/ArenaCalibrationService.as',
    'scripts/类定义/org/flashNight/arki/component/Damage/CrumbleDamageHandle.as',
    'flashswf/arts/things5/LIBRARY/敌人-方舟兽王.xml',
    'flashswf/arts/things5/LIBRARY/Symbol 2151.xml',
)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def analyze(raw, source_root=ROOT, expected_levels=(30, 60, 99)):
    expected_levels = tuple(expected_levels)
    if len(expected_levels) != 3 or len(set(expected_levels)) != 3 or any(type(level) is not int or not 1 <= level <= 100 for level in expected_levels):
        raise ValueError('An explicit three-level acceptance profile within 1..100 is required')
    sources = {p: (source_root / p).read_bytes() for p in SUPPORTING_SOURCES}
    maximum_level = int(re.search(r'_root\.最大等级\s*=\s*(\d+)',
        sources[LEVEL_SOURCE].decode('utf-8-sig')).group(1))
    formula = sources[FORMULA_SOURCE].decode('utf-8-sig')
    assert '最小值 + (最大值 - 最小值) / (_root.最大等级 - 1) * 目前等级' in formula
    assert '该等级值 = Math.floor(该等级值)' in formula
    original = ET.fromstring(sources[ORIGINAL_XML])
    skynet = ET.fromstring(sources[SKYNET_XML])

    def hp(xml, name, level):
        node = xml.find(name)
        low, high = float(node.findtext('hp_min')), float(node.findtext('hp_max'))
        return math.floor(low + (high - low) / (maximum_level - 1) * level)

    rows, groups, identities, seen = [], {}, {}, set()
    for raw_row in raw:
        context = raw_row['authorityContext']
        candidate_id = context['candidateUnitId']
        # Historical frozen rows retain their original registrations; this is not a runtime alias.
        assert candidate_id in (471, 473) and context['rivalUnitId'] in (78, 361)
        assert context['successorUnitId'] == (472 if candidate_id == 471 else 474)
        side = context['candidateSide']
        assert side in ('blue', 'red')
        opponent = 'red' if side == 'blue' else 'blue'
        rival, level = context['rivalUnitId'], context['level']
        key = (rival, level, raw_row['runId'])
        assert key not in seen, ('Duplicate result', key)
        seen.add(key)
        bindings = {p['path']: p['sha256'] for p in context['sourceBindings']}
        for source in (ORIGINAL_XML, SKYNET_XML):
            assert bindings[source] == sha(sources[source]), ('Source differs from executed inputs', source)
        identities[bindings['scripts/asLoader.swf']] = True
        own_spawns = [p for p in raw_row['spawnedUnits'] if p['side'] == side]
        rival_spawns = [p for p in raw_row['spawnedUnits'] if p['side'] == opponent]
        phase_ok = (len(own_spawns) == 1 and own_spawns[0]['from'] == '兵种' + str(candidate_id)
            and own_spawns[0]['unit'] == '敌人-CF6老头机器人')
        assert phase_ok, ('Invalid own successor identity or side', raw_row['runId'], own_spawns)
        assert len(own_spawns) + len(rival_spawns) == len(raw_row['spawnedUnits']), ('Unknown successor side', raw_row['runId'])
        assert raw_row['phaseSpawnCount'] == len(raw_row['spawnedUnits']), ('Successor count differs', raw_row['runId'])
        initial = hp(original, '敌人-方舟兽王', level) if rival == 78 else hp(skynet, '敌人-EXUSIAI指挥官', level)
        unit_results = raw_row[opponent + 'UnitResults']
        assert len(unit_results) == 1 and unit_results[0]['startMaxHp'] == initial
        reserve = hp(original, '敌人-方舟兽王虎', level) if rival == 78 else 0
        assert len(rival_spawns) <= (1 if rival == 78 else 0)
        assert all(p['unit'] == '敌人-方舟兽王虎' and p['from'] == '兵种78' for p in rival_spawns)
        full_max = initial + reserve
        remaining = raw_row[opponent]['remainHp'] + (reserve if not rival_spawns else 0)
        row = {
            'runId': raw_row['runId'], 'rival': rival, 'level': level, 'side': side,
            'candidateUnitId': candidate_id, 'successorUnitId': context['successorUnitId'],
            'status': raw_row['status'], 'won': raw_row['winner'] == side,
            'lost': raw_row['winner'] == opponent, 'frames': raw_row['frames'],
            'ownPhaseSpawns': len(own_spawns), 'ownPhaseValid': phase_ok,
            'opponentPhaseSpawns': len(rival_spawns), 'errors': raw_row['errors'],
            'initialFormMaxHp': initial, 'successorFormMaxHp': reserve,
            'fullChainMaxHp': full_max, 'fullChainRemainingHp': remaining,
            'fullChainNetLoss': 1 - remaining / full_max,
            'reportedSideMaxHp': raw_row[opponent]['startMaxHp'],
            'reportedSideNetLoss': 1 - raw_row[opponent]['remainHp'] / raw_row[opponent]['startMaxHp'],
        }
        rows.append(row)
        groups.setdefault((rival, level), []).append(row)

    summaries = []
    for (rival, level), group in sorted(groups.items()):
        values = [r['fullChainNetLoss'] for r in group]
        mean, median = statistics.mean(values), statistics.median(values)
        all_loss = all(r['lost'] and r['status'] == 'finished' and r['ownPhaseValid'] and not r['errors'] for r in group)
        summaries.append({
            'rival': rival, 'level': level, 'n': len(group),
            'sides': {s: sum(r['side'] == s for r in group) for s in ('blue', 'red')},
            'wins': sum(r['won'] for r in group), 'losses': sum(r['lost'] for r in group),
            'timeouts': sum(r['status'] == 'timeout' for r in group),
            'netLoss': {'mean': mean, 'median': median, 'min': min(values), 'max': max(values)},
            'opponentTransformed': sum(r['opponentPhaseSpawns'] for r in group),
            'in50to80': sum(.5 <= value <= .8 for value in values),
            'meetsGroupTarget': .5 <= mean <= .8 and .5 <= median <= .8 and all_loss,
        })
    full_matrix = (set(groups) == {(r, level) for r in (78, 361) for level in expected_levels}
        and all(g['sides'] == {'blue': 3, 'red': 3} for g in summaries))
    return {
        'schema': 'cf6-elder.arena-analysis.v1',
        'method': 'Fixed full-opponent-chain HP, including the full reserve of an unspawned beast form. HP comes from hash-matched enemy XML and the shipped level interpolation; every initial form is checked against its observed initial snapshot. Legacy phase HP can be sampled after Crumble reduces maximum HP and is kept separately. Healing remains part of the final HP. This is net HP loss, not cumulative damage.',
        'sourceBindings': [{'path': p, 'sha256': sha(data)} for p, data in sources.items()],
        'executedAsLoaderSha256': sorted(identities), 'fullMatrix': full_matrix,
        'expectedLevels': list(expected_levels),
        'strengthPassed': full_matrix and all(g['meetsGroupTarget'] for g in summaries),
        'boundary': 'Analysis does not certify execution, runtime identity, save protection, or cleanup. Those require the original coordinator and Worker receipts. Group averages and medians do not assert that every individual result is within 50-80 percent.',
        'groups': summaries, 'rows': rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, required=True, help='Frozen JSON array of original arena result rows')
    parser.add_argument('--output', type=Path, required=True, help='New analysis JSON; existing files are never overwritten')
    parser.add_argument('--source-root', type=Path, default=ROOT, help='Checkout or extracted source snapshot matching the result bindings')
    parser.add_argument('--expected-levels', type=int, nargs=3, default=[30, 60, 99], help='Explicit acceptance levels; legacy analyses retain 30/60/99 by default')
    args = parser.parse_args()
    data = args.results.read_bytes()
    result = analyze(json.loads(data.decode('utf-8-sig')), args.source_root, args.expected_levels)
    result['input'] = {'path': str(args.results.resolve()), 'sha256': sha(data)}
    validate_output(args.output)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf8') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps({'fullMatrix': result['fullMatrix'], 'strengthPassed': result['strengthPassed'],
        'groups': result['groups']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
