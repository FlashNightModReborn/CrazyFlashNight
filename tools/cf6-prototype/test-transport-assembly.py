"""Run after chapter assembly; strip only this adapter output for its baseline."""
import copy
import importlib.util
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('transport', HERE / 'transport-assembly.py')
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)

class TransportAssembly(unittest.TestCase):
    def setUp(self):
        self.chapter = json.loads((transport.ROOT / 'data/stages/books/cf6-sting.json').read_text(encoding='utf-8-sig'))
        for stage in self.chapter['maps']:
            if stage['id'] in transport.EXPECTED:
                stage['mechanism'].pop('transport', None)
                entry = stage['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]
                entry['Interval'] = 100
                if entry.get('TriggerEvent', {}).get('EventName') == 'Cf6TransportReady':
                    del entry['TriggerEvent']
    def test_only_transport_and_event_added(self):
        before = copy.deepcopy(self.chapter)
        audit = transport.adapt(self.chapter, False)
        self.assertEqual([r['finalQuantity'] for r in audit], [5,7,5])
        for stage in self.chapter['maps']:
            if stage['id'] in transport.EXPECTED:
                prop = stage['mechanism'].pop('transport')
                event = stage['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0].pop('TriggerEvent')
                self.assertEqual(event, {'EventName':'Cf6TransportReady','Parameters':[prop['id']]})
                self.assertEqual(prop['artMatrix'], [1,0,0,1,0,0])
                self.assertEqual(prop['frames'], 29)
                entry = stage['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]
                self.assertEqual(entry['Interval'], 400)
                entry['Interval'] = 100
        self.assertEqual(before, self.chapter)
    def test_double_assembly_rejected(self):
        transport.adapt(self.chapter, False)
        with self.assertRaises(ValueError): transport.adapt(self.chapter, False)
    def test_changed_budget_rejected(self):
        stage = next(m for m in self.chapter['maps'] if m['id']=='A09')
        stage['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]['Quantity'] = 6
        with self.assertRaises(ValueError): transport.adapt(self.chapter, False)
    def test_foreign_event_rejected(self):
        stage = next(m for m in self.chapter['maps'] if m['id']=='A09')
        stage['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]['TriggerEvent'] = {'EventName':'foreign'}
        with self.assertRaises(ValueError): transport.adapt(self.chapter, False)

if __name__ == '__main__': unittest.main()
