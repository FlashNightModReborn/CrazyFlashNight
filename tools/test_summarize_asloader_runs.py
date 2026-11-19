import json
from pathlib import Path
import tempfile
import unittest

import summarize_asloader_runs as summary


class LocalSummaryTests(unittest.TestCase):
    def setUp(self):
        area = tempfile.TemporaryDirectory()
        self.addCleanup(area.cleanup)
        self.root = Path(area.name)

    def write(self, name, **update):
        record = {'schema': 'cf7-asloader-run.v1', 'runScope': 'worktree', 'state': 'reused',
                  'layout': 'overlay', 'previousLayout': 'overlay', 'layoutSelection': 'default',
                  'forceFull': False, 'forcedModule': None, 'hadActiveSet': True,
                  'operations': {m: {'action': 'SKIP'} for m in summary.MODULES},
                  'publishCount': 0, 'phases': {}, 'wallSeconds': 12.5,
                  'source': 'private-user/location', 'run': 'private-run-identifier'}
        record.update(update)
        path = self.root/name
        path.mkdir()
        (path/'result.json').write_text(json.dumps(record), encoding='utf-8')
        return path

    def test_scope_separation_and_old_records(self):
        self.write('a')
        old = self.write('b')
        record = json.loads((old/'result.json').read_bytes())
        for field in ('runScope', 'layout', 'layoutSelection', 'previousLayout', 'hadActiveSet'):
            del record[field]
        (old/'result.json').write_text(json.dumps(record), encoding='utf-8')
        self.write('c', runScope='candidate')
        self.write('d', runScope='candidate', layoutSelection='experiment')
        self.write('e', layoutSelection='experiment')
        self.write('f', runScope=None)
        work = summary.summarize(self.root, 'worktree', 0)
        self.assertEqual(work['included'], 1)
        self.assertEqual(work['groups'][0]['kind'], 'routine')
        self.assertNotIn('recentSamples', work)
        self.assertEqual(summary.summarize(self.root, 'candidate', 0)['included'], 2)
        historical = summary.summarize(self.root, 'historical', 1)
        self.assertEqual(historical['included'], 1)
        self.assertIsNone(historical['recentSamples'][0]['layout'])
        self.assertIsNone(historical['recentSamples'][0]['kind'])

    def test_force_first_switch_and_failure_are_separate(self):
        self.write('a', previousLayout='mirror')
        self.write('b', forceFull=True)
        self.write('c', forcedModule='boot')
        self.write('d', previousLayout=None, hadActiveSet=False)
        self.write('e', state='failed', operations={}, phases={}, hadActiveSet=None)
        d = summary.summarize(self.root, 'worktree', 5)
        self.assertEqual([r['kind'] for r in d['recentSamples']],
                         ['layout-switch', 'forced-full', 'forced-module', 'no-active-set', None])
        self.assertIsNone(d['recentSamples'][-1]['planned'])
        self.assertEqual(d['recentSamples'][-1]['attempted'], ())
        self.assertEqual(d['failuresOrBlocks'], 1)
        self.assertEqual(d['failureReasonUnclassified'], 1)

    def test_planned_and_dispatched_differ_and_private_fields_are_dropped(self):
        plan = {m: {'action': 'BUILD', 'reason': 'private-user'} for m in summary.MODULES}
        a = self.write('a', state='failed', publishCount=1, operations=plan, phases={'resident': 25},
                       error='private-user', modules={'boot': {'origin': {'proof': {'retry32K': 1}}}})
        (a/'resident.log').write_text('private-user\n'+summary.RETRY+'\n', encoding='utf-8')
        self.write('b', state='failed', publishCount=2, operations=plan, phases={'resident': 25},
                   error='Unresolved Flash state: compile_state_uncertain.marker')
        c = self.write('c', state='failed', error='private-user 32K timeout UNKNOWN')
        (c/'compile_output.txt').write_text(summary.RETRY, encoding='utf8')
        self.write('d', layout='private-user', state='private-user')
        out = summary.summarize(self.root, 'worktree', 4)
        first, second = out['recentSamples'][:2]
        self.assertEqual(first['planned'], summary.MODULES)
        self.assertEqual(first['attempted'], ('resident',))
        self.assertEqual(first['childCallSeconds'], 25)
        self.assertIsNone(second['attempted'])
        self.assertIsNone(second['childCallSeconds'])
        self.assertEqual(out['observed32kRejected'], 1)
        self.assertEqual(out['observedUncertainState'], 1)
        self.assertEqual(out['failureReasonUnclassified'], 1)
        exported = json.dumps(out)
        for secret in ('private-user', 'private-run-identifier', str(self.root), 'compile_state_uncertain.marker'):
            self.assertNotIn(secret, exported)

    def test_distribution_and_malformed_input(self):
        self.assertEqual(summary.distribution([1, 4, None]), {'count': 2, 'missing': 1, 'min': 1, 'median': 2.5, 'max': 4})
        self.assertEqual(summary.distribution(range(1, 21))['p95'], 19)
        self.write('a', wallSeconds=-1, publishCount=False)
        p = self.write('b')/'result.json'
        p.write_text('{', encoding='utf-8')
        report = summary.summarize(self.root, 'worktree', 1)
        self.assertEqual(report['excluded'], {'unreadable': 1})
        self.assertEqual(report['groups'][0]['wallSeconds'], {'count': 0, 'missing': 1})
        self.assertIsNone(report['recentSamples'][0]['attemptedCount'])


if __name__ == '__main__':
    unittest.main()
