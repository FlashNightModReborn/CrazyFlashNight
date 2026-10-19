"""Assess the authorized high-level targets separately from historical net-HP metrics."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[2]
LEVELS = [60, 80, 100]
LEGACY_PROFILE = 'high-level-beast-near-death-exusiai-net-hp-v1'
PROFILE = 'high-level-beast-near-death-exusiai-net-hp-minority-wins-v2'
AI_SOURCE = 'tools/cf6-elder-assets/ElderAI.as'


def assess(analysis, diagnostics, near_death_observations=None, profile=PROFILE):
    if profile not in (PROFILE, LEGACY_PROFILE):
        raise ValueError('Unknown explicit acceptance profile')
    if analysis['expectedLevels'] != LEVELS:
        raise ValueError('This acceptance profile requires levels 60/80/100')
    entries = {}
    notices = {}
    for entry in (near_death_observations or {}).get('rows', []):
        key = (entry['rival'], entry['level'], entry['side'], entry['runId'])
        if key in notices:
            raise ValueError('Duplicate notification identity: ' + str(key))
        notices[key] = entry
    for entry in diagnostics['rows']:
        key = (entry['rival'], entry['level'], entry['side'], entry['runId'])
        if key in entries:
            raise ValueError('Duplicate diagnostic run: ' + str(key))
        entries[key] = entry
    rows = []
    for row in analysis['rows']:
        identity_key = (row['rival'], row['level'], row['side'], row['runId'])
        evidence = entries.pop(identity_key, None)
        if evidence is None:
            raise ValueError('Missing literal diagnostic: ' + row['runId'])
        for key in ('rival', 'level', 'side', 'status', 'frames'):
            if evidence[key] != row[key]:
                raise ValueError('Diagnostic/result identity differs: ' + key)
        if evidence['unknownPhaseRageLeech'] != 0:
            raise ValueError('Unknown rage-source identity: ' + row['runId'])
        notice = notices.pop(identity_key, None)
        if near_death_observations is not None:
            if notice is None or notice['resultSha256'] != evidence['resultSha256']:
                raise ValueError('Missing or mismatched notification result identity')
            for field in ('status', 'frames'):
                if notice[field] != row[field]:
                    raise ValueError('Notification/result identity differs: ' + field)
        notification_observed = row['rival'] == 78 and bool(notice and notice['notifications'])
        hit_observed = row['rival'] == 78 and evidence['initialPhaseRageLeech'] > 0
        near_death_observed = hit_observed or notification_observed
        first_form_defeated = row['rival'] == 78 and row['opponentPhaseSpawns'] == 1
        natural_loss = row['status'] == 'finished' and row['lost'] and not row['won'] and row['ownPhaseValid'] and not row['errors']
        natural_outcome = row['status'] == 'finished' and bool(row['lost']) != bool(row['won']) and row['ownPhaseValid'] and not row['errors']
        rows.append({
            **row,
            'observedInitialFormRage': near_death_observed,
            'observedInitialFormRageByHit': hit_observed,
            'observedInitialFormRageByNotification': notification_observed,
            'rageNotifications': notice['notifications'] if notice else [],
            'initialFormDefeated': first_form_defeated,
            'beastRequiredProgress': (near_death_observed or first_form_defeated) if row['rival'] == 78 else None,
            'beastProgressEvidence': ('observed_rage_and_successor' if near_death_observed and first_form_defeated
                else 'observed_rage' if near_death_observed else 'successor_spawned' if first_form_defeated
                else 'not_established') if row['rival'] == 78 else None,
            'naturalLoss': natural_loss,
            'naturalOutcome': natural_outcome,
            'literalDiagnostic': {key: evidence[key] for key in ('sourceArchiveSha256', 'sourceEntrySha256', 'lineNumber', 'resultSha256')},
        })
    if entries or notices:
        raise ValueError('Unmatched diagnostic or notification runs')
    groups = []
    for group in analysis['groups']:
        members = [r for r in rows if (r['rival'], r['level']) == (group['rival'], group['level'])]
        all_losses = all(r['naturalLoss'] for r in members)
        wins = sum(r['status'] == 'finished' and r['won'] for r in members)
        losses = sum(r['naturalLoss'] for r in members)
        minority_wins = wins < losses
        if group['rival'] == 78:
            target = all(r['beastRequiredProgress'] for r in members) and all_losses
        elif group['rival'] == 361:
            accepted_outcomes = all_losses if profile == LEGACY_PROFILE else all(r['naturalOutcome'] for r in members) and minority_wins
            target = .5 <= group['netLoss']['mean'] <= .8 and .5 <= group['netLoss']['median'] <= .8 and accepted_outcomes
        else:
            raise ValueError('Unknown rival in acceptance matrix')
        groups.append({**group, 'historicalNetHpTargetMet': group['meetsGroupTarget'],
            'observedInitialFormRage': sum(r['observedInitialFormRage'] for r in members),
            'initialFormDefeated': sum(r['initialFormDefeated'] for r in members),
            'beastProgressEstablished': sum(r['beastRequiredProgress'] is True for r in members),
            'criterion': 'near_death_or_first_form_defeated_then_natural_loss' if group['rival'] == 78 else ('mean_and_median_net_hp_50_to_80_then_natural_loss' if profile == LEGACY_PROFILE else 'mean_and_median_net_hp_50_to_80_with_minority_wins'),
            'winsRemainMinority': minority_wins,
            'draws': sum(r['status'] == 'finished' and not r['won'] and not r['lost'] for r in members),
            'meetsGroupTarget': target})
    full_matrix = analysis['fullMatrix'] and len(rows) == 36 and len(groups) == 6
    return {'schema': 'cf6-elder.arena-acceptance.v3', 'profile': profile,
        'expectedLevels': LEVELS, 'fullMatrix': full_matrix,
        'strengthPassed': full_matrix and all(g['meetsGroupTarget'] for g in groups),
        'allHistoricalNetHpTargetsMet': analysis['strengthPassed'],
        'groups': groups, 'rows': rows,
        'method': 'Beast: each fight must contain an observed initial-form rage hit, its unique rage notification matched to the exact battle interval, or an actual first-form-to-successor transition, and naturally end in an Elder loss. A successor transition establishes progress beyond the first-form threshold, but does not assert that the rage callback was observed. EXUSIAI: each six-fight group must have mean and median full-chain net HP loss within 50-80 percent. ' + ('Every row must naturally lose; no wins are accepted.' if profile == LEGACY_PROFILE else 'The human-authorized small number of wins is interpreted as a strict minority within each group; losses must remain the majority. All rows must naturally finish with one winner.') + ' Draws, timeouts, phase failures and errors are not accepted.',
        'boundary': 'A positive initial-form rage hit records the executed shooter rage flag. Zero such hits do not establish absence of rage. Final Beast HP is retained for reference and is not attributed entirely to Elder damage because Beast also drains its own HP. Execution, candidate identity, display continuity and save protection require their separate receipts. These results do not certify human or standard-entry acceptance.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--diagnostics', type=Path, required=True)
    parser.add_argument('--scope', type=Path, required=True)
    parser.add_argument('--near-death-observations', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    read = lambda path: path.read_bytes()
    digest = lambda data: hashlib.sha256(data).hexdigest()
    decode = lambda data: json.loads(data.decode('utf-8-sig'))
    raw_data, diagnostic_data, scope_data = map(read, (args.results, args.diagnostics, args.scope))
    raw, diagnostics, scope = map(decode, (raw_data, diagnostic_data, scope_data))
    notification_data = read(args.near_death_observations)
    notifications = decode(notification_data)
    if scope['profile'] not in (PROFILE, LEGACY_PROFILE) or scope['levels'] != LEVELS:
        raise ValueError('Wrong explicit authorization profile')
    if diagnostics['experiment'] != scope['experiment'] or not diagnostics['wholeExperimentFinal']:
        raise ValueError('Diagnostics do not cover the complete selected experiment')
    if notifications['experiment'] != scope['experiment'] or not notifications['wholeExperimentFinal']:
        raise ValueError('Notifications do not cover the complete selected experiment')
    source_contract = notifications['sourceContract']
    if digest(read(args.source_root / source_contract['path'])) != source_contract['sha256']:
        raise ValueError('Beast notification source differs from the frozen contract')
    source = read(args.source_root / AI_SOURCE)
    source_hash = digest(source)
    for row in raw:
        bindings = {item['path']: item['sha256'] for item in row['authorityContext']['sourceBindings']}
        if bindings[AI_SOURCE] != source_hash:
            raise ValueError('Executed diagnostic source differs from the supplied source')
    source_text = source.decode('utf-8-sig')
    for clause in ('if(shooter.狂暴模式==1)', 'stats.reactiveRageLeechHits++', 'sourceKey:String="n:"+shooter._name'):
        if clause not in source_text:
            raise ValueError('Rage diagnostic contract changed: ' + clause)
    spec = importlib.util.spec_from_file_location('phase_analysis', Path(__file__).with_name('analyze-arena.py'))
    analyzer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analyzer)
    analysis = analyzer.analyze(raw, args.source_root, expected_levels=LEVELS)
    result = assess(analysis, diagnostics, notifications, profile=scope['profile'])
    result['inputs'] = {name: {'path': str(path), 'sha256': digest(data)} for name, path, data in (
        ('results', args.results, raw_data), ('diagnostics', args.diagnostics, diagnostic_data), ('scope', args.scope, scope_data),
        ('nearDeathObservations', args.near_death_observations, notification_data))}
    result['executedDiagnosticSource'] = {'path': AI_SOURCE, 'sha256': source_hash}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf8') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps({'fullMatrix': result['fullMatrix'], 'strengthPassed': result['strengthPassed'], 'groups': result['groups']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
