"""Summarize local asLoader publication receipts without exporting identifying data."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import statistics
import sys


MODULES = ('resident', 'shared', 'boot')
LAYOUTS = ('mirror', 'overlay')
STATES = ('compiled', 'reused', 'revalidated', 'failed', 'invalid', 'unknown', 'planned')
DEFAULT_RUNS = Path(__file__).resolve().parents[1] / 'tmp/asloader-p1/runs'
RETRY = '[ERROR] Module required a 32K recovery retry; see compile_output.txt.'


def allowed(value, choices):
    return value if value in choices else None


def seconds(value):
    if type(value) in (int, float) and 0 <= value <= sys.float_info.max and math.isfinite(value):
        return value
    return None


def distribution(values):
    valid = sorted(n for n in values if n is not None)
    result = {'count': len(valid), 'missing': len(values) - len(valid)}
    if valid:
        result.update(min=round(valid[0], 3), median=round(statistics.median(valid), 3),
                      max=round(valid[-1], 3))
    if len(valid) >= 20:
        result['p95'] = round(valid[math.ceil(len(valid) * .95) - 1], 3)
    return result


def change_kind(d, layout):
    forced = d.get('forcedModule')
    if d.get('forceFull') is True:
        return 'forced-full'
    if forced in MODULES:
        return 'forced-module'
    if d.get('forceFull') is not False or 'forcedModule' not in d or forced is not None:
        return None
    if d.get('hadActiveSet') is False:
        return 'no-active-set'
    old = allowed(d.get('previousLayout'), LAYOUTS)
    if d.get('hadActiveSet') is True and old and layout:
        return 'routine' if old == layout else 'layout-switch'
    return None


def failed_signals(d, run_dir):
    """Only use this receipt and its own original child console, never a global Output file."""
    error = d.get('error')
    signals = set()
    if d.get('state') == 'unknown' or (isinstance(error, str) and
            error in ('Unresolved Flash state: compile_state_uncertain.marker',
                      'Unresolved Flash state blocks module generation: compile_state_uncertain.marker')):
        signals.add('uncertain-state')
    for module in MODULES:
        try:
            with (run_dir / (module + '.log')).open(encoding='utf-8-sig', errors='replace') as log:
                for line in log:
                    line = line.strip()
                    if line == RETRY:
                        signals.add('32k-rejected')
                    if (line.startswith('[ERROR] CS6 已退出且没有终态编译证据') or
                            line.startswith('[ERROR] 检测到 scripts/compile_state_uncertain.marker')):
                        signals.add('uncertain-state')
        except OSError:
            continue
    return sorted(signals)


def sample(d, run_dir):
    comparison = d.get('comparison')
    layout = allowed(d.get('layout'), LAYOUTS)
    if layout is None and 'runScope' not in d and isinstance(comparison, dict):
        layout = allowed(comparison.get('layout'), LAYOUTS)
    operations, phases = d.get('operations'), d.get('phases')
    planned = None
    if isinstance(operations, dict) and all(isinstance(operations.get(m), dict) and
            operations[m].get('action') in ('BUILD', 'SKIP') for m in MODULES):
        planned = tuple(m for m in MODULES if operations[m]['action'] == 'BUILD')
    count = d.get('publishCount')
    if type(count) != int or not 0 <= count <= len(MODULES):
        count = None
    attempted, child_seconds = None, None
    if isinstance(phases, dict):
        observed = tuple(m for m in MODULES if m in phases)
        if len(observed) == count:
            attempted = observed
            durations = [seconds(phases[m]) for m in observed]
            if all(x is not None for x in durations):
                child_seconds = round(sum(durations), 3)
    state = allowed(d.get('state'), STATES)
    return {'layout': layout, 'selection': allowed(d.get('layoutSelection'), ('default', 'explicit', 'experiment')),
            'kind': change_kind(d, layout), 'forcedModule': allowed(d.get('forcedModule'), MODULES),
            'state': state, 'planned': planned, 'attempted': attempted, 'attemptedCount': count,
            'wallSeconds': seconds(d.get('wallSeconds')), 'childCallSeconds': child_seconds,
            'observedSignals': failed_signals(d, run_dir) if state in ('failed', 'invalid', 'unknown') else []}


def summarize(directory, scope, sample_limit):
    rows, excluded = [], Counter()
    for p in sorted(directory.glob('*/result.json')):
        try:
            d = json.loads(p.read_bytes())
            if not isinstance(d, dict) or d.get('schema') != 'cf7-asloader-run.v1':
                excluded['unsupportedSchema'] += 1
                continue
            actual_scope = allowed(d.get('runScope'), ('worktree', 'candidate')) if 'runScope' in d else 'historical'
            if actual_scope != scope or (scope == 'worktree' and d.get('layoutSelection') == 'experiment'):
                excluded['otherScope'] += 1
                continue
            rows.append(sample(d, p.parent))
        except (OSError, ValueError):
            excluded['unreadable'] += 1
    keys = ('layout', 'selection', 'kind', 'forcedModule', 'state', 'planned', 'attempted', 'attemptedCount')
    groups = defaultdict(list)
    for row in rows:
        groups[tuple(row[k] for k in keys)].append(row)
    summary = []
    for key, members in groups.items():
        group = dict(zip(keys, key))
        group.update(count=len(members), wallSeconds=distribution([r['wallSeconds'] for r in members]),
                     childCallSeconds=distribution([r['childCallSeconds'] for r in members]))
        summary.append(group)
    failures = [r for r in rows if r['state'] in ('failed', 'invalid', 'unknown')]
    report = {'included': len(rows), 'excluded': dict(excluded), 'byState': dict(Counter(
        r['state'] or 'unrecognized' for r in rows)), 'failuresOrBlocks': len(failures),
        'observed32kRejected': sum('32k-rejected' in r['observedSignals'] for r in failures),
        'observedUncertainState': sum('uncertain-state' in r['observedSignals'] for r in failures),
        'failureReasonUnclassified': sum(not r['observedSignals'] for r in failures), 'groups': summary}
    if sample_limit:
        report['recentSamples'] = rows[-sample_limit:]
    return report


def main():
    cli = argparse.ArgumentParser(description=__doc__, epilog=(
        'Each directory is summarized independently. Wall time is the publisher time. Child call time '
        'includes child prechecks and verification. P95 uses nearest rank for groups of 20 or more. '
        'Counts cover persisted receipts only. Null means unrecorded.'))
    cli.add_argument('--runs-dir', type=Path, action='append', help='One local runs directory per dataset')
    cli.add_argument('--scope', choices=('worktree', 'candidate', 'historical'), default='worktree',
                     help='Historical reads older P1 result.json files without runScope')
    cli.add_argument('--samples', nargs='?', const=10, type=int, default=0, metavar='N',
                     help='Include the most recent N sanitized rows (default 10 when specified)')
    cli.add_argument('--output', type=Path, help='Write a new JSON file instead of stdout')
    args = cli.parse_args()
    if not 0 <= args.samples <= 100:
        cli.error('--samples must be between 0 and 100')
    if args.runs_dir and any(not d.is_dir() for d in args.runs_dir):
        cli.error('A requested runs directory does not exist')
    report = {'schema': 'cf7-asloader-local-summary.v1', 'scope': args.scope,
              'datasets': [summarize(d, args.scope, args.samples) for d in args.runs_dir or [DEFAULT_RUNS]]}
    data = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    if args.output:
        with args.output.open('x', encoding='utf-8') as stream:
            stream.write(data)
    else:
        sys.stdout.write(data)


if __name__ == '__main__':
    main()
