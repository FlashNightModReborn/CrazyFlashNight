"""Deterministic CF6 entrance/timing contracts; AVM1 gates remain separate."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location('spawn_assembly', HERE / 'spawn-assembly.py')
spawn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spawn)


def fixture():
    chapter = json.loads((ROOT / 'data/stages/books/cf6-sting.runtime.json').read_text(encoding='utf-8-sig'))
    # Reconstruct only adapter-owned inputs if the checked-in chapter is already assembled.
    for node in chapter['maps']:
        node.get('sourceNote', {}).pop(spawn.MARKER, None)
        for point in node['stage'].get('SpawnPoint', {}).get('Point', []):
            point.pop('BiasX', None)
            point.pop('BiasY', None)
        for wi,wave in enumerate(node['stage']['Wave']['SubWave']):
            designed = node.get('sourceNote',{}).get('chapterDifficulty',{}).get('waveKinds',[])
            for enemy in wave['EnemyGroup']['Enemy']:
                if enemy.get('Quantity', 0) > 1 or designed and designed[wi]=='combat':
                    enemy['Interval'] = 100
                    enemy.pop('Delay', None)
        plan = node.get('bossEncounter')
        while plan:
            if node['id'] == 'A20':
                for group in plan['groups'][1:]:
                    for enemy in group['enemies']:
                        enemy.pop('x', None)
                        enemy.pop('y', None)
            plan = plan.get('nextPhase')
    environments = {e.findtext('BackgroundURL'): e for e in ET.parse(ROOT / 'data/environment/stage_environment.xml').getroot()}
    return chapter, environments


class SpawnAssembly(unittest.TestCase):
    def setUp(self):
        self.chapter, self.env = fixture()
        self.maps = {m['id']: m for m in self.chapter['maps']}

    def test_all_authority_and_initial_pod_entries_conserved(self):
        before = copy.deepcopy(self.chapter)
        audit = spawn.adapt(self.chapter, self.env)
        self.assertEqual(audit['authorityBeforeSha256'], audit['authorityAfterSha256'])
        designed=any(m.get('sourceNote',{}).get('chapterDifficulty') for m in self.chapter['maps'])
        # Three unique bosses plus twelve already-boarded units in each elevator.
        self.assertEqual(audit['preservedInitialEntries'],27 if designed else 56)
        self.assertEqual(audit['preservedPodEntries'], 10)
        for old, new in zip(before['maps'], self.chapter['maps']):
            for ow, nw in zip(old['stage']['Wave']['SubWave'], new['stage']['Wave']['SubWave']):
                for oe, ne in zip(ow['EnemyGroup']['Enemy'], nw['EnemyGroup']['Enemy']):
                    self.assertEqual(spawn.protected(oe, {'Interval', 'Delay'}), spawn.protected(ne, {'Interval', 'Delay'}))
            for key in ('Pickups', 'Instances'):
                self.assertEqual(old['stage'].get(key), new['stage'].get(key))

    def test_all_counted_ordinary_queues_use_four_hundred_ms(self):
        audit = spawn.adapt(self.chapter, self.env)
        expected=sum(1 for node in self.chapter['maps'] for wi,w in enumerate(node['stage']['Wave']['SubWave'])
                     for e in w['EnemyGroup']['Enemy'] if e.get('Quantity',0)>1 or
                     node.get('sourceNote',{}).get('chapterDifficulty',{}).get('waveKinds',[None]*len(node['stage']['Wave']['SubWave']))[wi]=='combat')
        self.assertEqual(len(audit['waveQueues']),expected)
        self.assertTrue(all(r['intervalMs'] == 400 for r in audit['waveQueues']))
        self.assertEqual(audit['recurringEffectiveMs'], 500)

    def test_two_queue_rooms_have_two_hundred_ms_phase(self):
        audit = spawn.adapt(self.chapter, self.env)
        groups={}
        for row in audit['waveQueues']:groups.setdefault((row['mapId'],row['waveIndex']),[]).append(row)
        for rows in groups.values():self.assertEqual([r['delayMs'] for r in rows],list(range(0,200*len(rows),200)))

    def test_numeric_points_keep_original_positions_and_caps(self):
        before = {mid: copy.deepcopy(m['stage'].get('SpawnPoint')) for mid, m in self.maps.items()}
        spawn.adapt(self.chapter, self.env)
        for mid, old in before.items():
            if old:
                for op, np in zip(old['Point'], self.maps[mid]['stage']['SpawnPoint']['Point']):
                    self.assertEqual(op, spawn.protected(np, {'BiasX', 'BiasY'}))

    def test_every_jitter_envelope_is_collision_safe(self):
        audit = spawn.adapt(self.chapter, self.env)
        seen = 0
        for row in audit['spawnPoints']:
            bx, by = row['bias']
            if bx:
                seen += 1
                x, y = row['position']
                self.assertTrue(spawn.safe_box(self.env['CF6_' + row['mapId'] + '_BG.swf'], [x-bx-12, y-by-6, x+bx+12, y+by+6]))
        self.assertGreater(seen, 0)

    def test_unproven_a01_jitter_is_not_added(self):
        audit = spawn.adapt(self.chapter, self.env)
        rows = [r for r in audit['spawnPoints'] if r['mapId'] == 'A01']
        if self.maps['A01'].get('sourceNote',{}).get('chapterDifficulty'):
            self.assertEqual(len(rows),2)
            self.assertTrue(all(r['quantityMax']==4 for r in rows))
        else:
            self.assertEqual(len(rows), 4)
            self.assertTrue(all(r['bias'] == [0, 0] and r['quantityMax'] == 5 for r in rows))

    def test_transport_events_keep_exact_owner_and_quantity(self):
        before = {mid: copy.deepcopy(self.maps[mid]['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]) for mid in ('A09', 'A14', 'A18')}
        spawn.adapt(self.chapter, self.env)
        for mid, old in before.items():
            new = self.maps[mid]['stage']['Wave']['SubWave'][1]['EnemyGroup']['Enemy'][0]
            self.assertEqual(spawn.protected(old, {'Interval'}), spawn.protected(new, {'Interval'}))

    def test_doorless_boss_spawns_are_real_safe_edge_points(self):
        first = self.maps['A06']['bossEncounter']['groups'][0]['enemies'][0]
        first['x'], first['y'] = 1200, 500
        audit = spawn.adapt(self.chapter, self.env)
        for row in audit['bossEntries']:
            if row['mapId'] not in ('A06', 'A17'):
                continue
            x, y = row['after']
            x0, y0, x1, y1 = row['line']
            self.assertTrue(x0 <= x <= x1 and y0 <= y <= y1)
            self.assertTrue(spawn.safe_box(self.env['CF6_' + row['mapId'] + '_BG.swf'], [x-12, y-6, x+12, y+6]))
        self.assertNotEqual(first['x'], 1200)

    def test_a20_keeps_authored_initial_door_placements(self):
        plan = self.maps['A20']['bossEncounter']
        old = copy.deepcopy([plan['groups'][0], plan['nextPhase']['groups'][0]])
        spawn.adapt(self.chapter, self.env)
        self.assertEqual(old, [plan['groups'][0], plan['nextPhase']['groups'][0]])

    def test_a20_all_later_support_uses_one_of_four_existing_doors(self):
        audit = spawn.adapt(self.chapter, self.env)
        doors = {d['id']: [d['spawnX'], d['spawnY']] for d in self.maps['A20']['mechanism']['layers'] if d.get('role') == 'door-spawn-sequence'}
        rows = [r for r in audit['bossEntries'] if r['mapId'] == 'A20']
        if self.maps['A20'].get('sourceNote',{}).get('chapterDifficulty'):
            self.assertEqual(len(rows),8)
        else:self.assertGreater(len(rows),8)
        self.assertTrue(all(doors[r['entrance']] == r['after'] for r in rows))

    def test_unknown_numeric_entry_does_not_silently_choose_floor(self):
        metadata=self.maps['A03'].get('sourceNote',{}).get('chapterDifficulty')
        if metadata:metadata['sourceSha256']='0'*64
        else:self.maps['A03']['mechanism']['layers'] = []
        with self.assertRaisesRegex(ValueError, 'no visible door|unreviewed difficulty assembly metadata'):
            spawn.adapt(self.chapter, self.env)

    def test_missing_edge_line_fails_instead_of_using_default_random_y(self):
        e = self.env['CF6_A06_BG.swf']
        e.remove(e.find('LeftSpawnLine'))
        with self.assertRaisesRegex(ValueError, 'explicit normalized side spawn line required'):
            spawn.adapt(self.chapter, self.env)

    def test_blocked_edge_fails_instead_of_claiming_safe_spawn(self):
        e = self.env['CF6_A06_BG.swf']
        c = ET.SubElement(e, 'Collision')
        for p in [(-1000, -1000), (10000, -1000), (10000, 10000), (-1000, 10000)]:
            ET.SubElement(c, 'Point').text = ','.join(map(str, p))
        with self.assertRaisesRegex(ValueError, 'no collision-free edge entrance'):
            spawn.adapt(self.chapter, self.env)

    def test_double_assembly_rejected(self):
        spawn.adapt(self.chapter, self.env)
        with self.assertRaisesRegex(ValueError, 'already applied'):
            spawn.adapt(self.chapter, self.env)


if __name__ == '__main__':
    unittest.main()
