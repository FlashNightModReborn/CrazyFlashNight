"""Summarize existing Worker receipts; never start or replay an arena run."""
from collections import Counter, defaultdict
from pathlib import Path
import argparse
import hashlib
import json
import os
import statistics


def native_path(path):
    value = str(Path(path).resolve())
    if os.name == 'nt' and not value.startswith('\\\\?\\'):
        value = '\\\\?\\UNC\\' + value[2:] if value.startswith('\\\\') else '\\\\?\\' + value
    return Path(value)


def load(path):
    return json.loads(native_path(path).read_text(encoding='utf-8-sig'))


def digest(path):
    return 'sha256:' + hashlib.sha256(native_path(path).read_bytes()).hexdigest()


def summarize(report_path):
    report = load(report_path)
    measurement = load(report['measurementPath'])
    qualifications = {g['groupId']: g['qualified'] for g in measurement['groups']}
    buckets = defaultdict(list)
    inputs, rejected = [], []
    worker_ms = 0
    for group in report['groups']:
        for outcome in group['outcomes']:
            receipt_path = Path(outcome['expectedReceiptPath'])
            if not receipt_path.is_file():
                rejected.append({'jobId': outcome['jobId'], 'reason': 'missing receipt'})
                continue
            receipt = load(receipt_path)
            assert digest(receipt_path) == outcome['receiptSha256']
            worker_ms += receipt.get('wallDurationMs', 0)
            result_path = receipt.get('resultPath')
            if not result_path:
                rejected.append({'jobId': outcome['jobId'], 'reason': receipt['status']})
                continue
            assert digest(result_path) == receipt['resultSha256']
            inputs.append({'receiptPath': str(receipt_path), 'receiptSha256': digest(receipt_path),
                           'resultPath': result_path, 'resultSha256': receipt['resultSha256'],
                           'runtimeIdentity': receipt['runtimeIdentity'],
                           'sourceSwf': next(x for x in receipt['resourceClosure']['files']
                                            if x['path'] == 'flashswf/arts/new/Codex专用素材.swf')})
            rows = [json.loads(line) for line in native_path(result_path).read_text(encoding='utf-8-sig').splitlines() if line.strip()]
            for row in rows:
                context = row.get('authorityContext', {})
                side = context.get('enhancedSide')
                if side not in ('blue', 'red'):
                    rejected.append({'runId': row['runId'], 'reason': 'missing candidate side'})
                    continue
                other = 'red' if side == 'blue' else 'blue'
                units = row.get(side + 'UnitResults') or []
                level = units[0]['level'] if units else 'unknown'
                same_panel = context.get('experiment') in ('gamma-echo-ai-ab', 'gamma-echo-default-parity', 'gamma-echo-lifesteal-ab')
                panel_equal = row[side]['startMaxHp'] == row[other]['startMaxHp'] > 0
                admissible = qualifications[group['groupId']] and not row['errors'] and (panel_equal or not same_panel)
                eligible = admissible and row['status'] == 'finished'
                hp_delta = None
                if row[side]['startMaxHp'] > 0 and row[other]['startMaxHp'] > 0:
                    hp_delta = 100 * (row[side]['remainHp'] / row[side]['startMaxHp']
                                      - row[other]['remainHp'] / row[other]['startMaxHp'])
                key = (context.get('variant'), level, context.get('aiRevision'), context.get('experiment'))
                buckets[key].append({'runId': row['runId'], 'status': row['status'],
                                     'candidateSide': side, 'candidateWon': row['winner'] == side,
                                     'candidateLost': row['winner'] == other,
                                     'startHpEqual': panel_equal, 'eligible': eligible,
                                     'hpDeltaPP': hp_delta, 'frames': row['frames'],
                                     'durationMs': row['durationMs']})
    summaries = []
    for (variant, level, revision, experiment), rows in buckets.items():
        valid = [r for r in rows if r['eligible']]
        summaries.append({'variant': variant, 'level': level, 'aiRevision': revision,
                          'comparison': experiment, 'observed': len(rows),
                          'statusCounts': dict(Counter(r['status'] for r in rows)),
                          'qualifiedFinished': len(valid),
                          'wins': sum(r['candidateWon'] for r in valid),
                          'losses': sum(r['candidateLost'] for r in valid),
                          'draws': sum(not r['candidateWon'] and not r['candidateLost'] for r in valid),
                          'meanHpDeltaPP': statistics.mean(r['hpDeltaPP'] for r in valid) if valid else None,
                          'bySide': {s: {'finished': sum(r['candidateSide'] == s for r in valid),
                                         'wins': sum(r['candidateSide'] == s and r['candidateWon'] for r in valid)}
                                     for s in ('blue', 'red')}, 'runs': rows})
    return {'experimentId': report['experimentId'], 'qualified': report['qualified'],
            'reportPath': str(Path(report_path).resolve()), 'reportSha256': digest(report_path),
            'wallDurationMs': sum(g.get('wallDurationMs', 0) for g in report['groups']),
            'aggregateWorkerMs': worker_ms, 'summaries': summaries, 'inputs': inputs,
            'rejected': rejected}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('reports', nargs='+')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result = {'schema': 'gamma-echo.arena-analysis.v1',
              'policy': 'Only qualified finished rows enter strength statistics; natural timeouts are separate.',
              'experiments': [summarize(p) for p in args.reports]}
    Path(args.output).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for experiment in result['experiments']:
        print(json.dumps({'experimentId': experiment['experimentId'], 'qualified': experiment['qualified'],
                          'summaries': [{k: v for k, v in s.items() if k != 'runs'} for s in experiment['summaries']]},
                         ensure_ascii=False))
