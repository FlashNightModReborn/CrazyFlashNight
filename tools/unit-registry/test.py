"""Production Python identity, writeback and book-normalization regressions."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from unit_registry import UnitRegistry, valid_key, preserve_unit_key, normalize_book_units
from validate import validate_registry_delta, audit

CASES = json.loads(Path(__file__).with_name('cases.json').read_text('utf-8'))


def module_at(relative, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class UnitRegistryTests(unittest.TestCase):
    def setUp(self):
        self.units = copy.deepcopy(CASES['units'])
        self.registry = UnitRegistry(self.units)

    def test_shared_reference_cases(self):
        for case in CASES['references']:
            with self.subTest(reference=case['input']):
                self.assertEqual(case['expected'], self.registry.resolve_type(case['input']))
        for value in CASES['rejectedReferences']:
            with self.subTest(reference=value), self.assertRaisesRegex(ValueError, 'fixture.Type'):
                self.registry.resolve_type(value, 'fixture.Type')

    def test_shared_key_cases_and_length(self):
        for value in CASES['validKeys']:
            self.assertTrue(valid_key(value), value)
        for value in CASES['invalidKeys']:
            self.assertFalse(valid_key(value), value)
        self.assertTrue(valid_key('x.' + '甲' * 94))
        self.assertFalse(valid_key('x.' + '甲' * 95))

    def test_numeric_ids_and_duplicate_names(self):
        self.assertEqual(0, self.registry.resolve_id(0))
        self.assertEqual(466, self.registry.get('cf6.特种兵.二阶段')['id'])
        self.assertEqual(len(self.units), len(self.registry.by_id))
        self.assertEqual('兵种1', UnitRegistry([dict(id=1.0, spritename='x', key='测试.整数')]).resolve_type('测试.整数'))
        for value in [True, None, -1, 1.5, float('inf'), float('nan'), '466']:
            with self.subTest(reference=value), self.assertRaises(ValueError):
                self.registry.resolve_id(value)

    def test_invalid_registries_fail(self):
        for bad in [None, [], {}, [dict(id=True, spritename='x')], [dict(id=-1, spritename='x')],
                    [dict(id=1.5, spritename='x')], [dict(id=float('inf'), spritename='x')],
                    [dict(id=2147483648, spritename='x')], [dict(id=0, spritename='')],
                    [dict(id=0, spritename='x', key=None)], self.units + [self.units[0]],
                    self.units + [dict(id=500, spritename='x', key='测试.零号')]]:
            with self.subTest(units=bad), self.assertRaises(ValueError):
                UnitRegistry(bad)

    def test_writeback_keeps_target_identity_and_drops_template_identity(self):
        candidate = copy.deepcopy(self.units[0])
        candidate.update(id=466, spritename='敌人-CF6特种兵')
        self.assertEqual('cf6.特种兵.二阶段', preserve_unit_key(candidate, self.units)['key'])
        candidate.update(id=1)
        self.assertNotIn('key', preserve_unit_key(candidate, self.units))
        candidate.update(id=500)
        with self.assertRaises(ValueError):
            preserve_unit_key(candidate, self.units)
        self.assertEqual('测试.新单位', preserve_unit_key(candidate, self.units, new_key='测试.新单位')['key'])
        with self.assertRaisesRegex(ValueError, 'duplicate unit key'):
            preserve_unit_key(candidate, self.units, new_key='测试.零号')
        self.assertEqual(CASES['units'], self.units)

    def test_real_text_writers_keep_keys_and_unrelated_records(self):
        for index, folder in enumerate(['cf6-wings-assets', 'cf6-manman-assets', 'cf6-bladebot-assets']):
            with self.subTest(writer=folder):
                writer = module_at('tools/' + folder + '/balance.py', 'unit_writer_' + str(index))
                writer.UNIT_ID = 466
                original = json.dumps(self.units, ensure_ascii=False, indent=2) + '\n'
                candidate = copy.deepcopy(self.registry.get(466))
                candidate.pop('key')
                candidate['level'] = 31
                result = json.loads(writer.update_registration_text(original, candidate))
                target = next(row for row in result if row['id'] == 466)
                self.assertEqual('cf6.特种兵.二阶段', target['key'])
                self.assertEqual(31, target['level'])
                self.assertEqual([row for row in self.units if row['id'] != 466], [row for row in result if row['id'] != 466])
                self.assertEqual(writer.update_registration_text(original, candidate), writer.update_registration_text(writer.update_registration_text(original, candidate), candidate))

    def test_stable_identity_and_new_unit_rules(self):
        validate_registry_delta(self.registry, self.units)
        mutations = [self.units[:-1], self.units + [dict(id=500, spritename='x')],
                     self.units + [dict(id=2, spritename='x', key='测试.空缺')]]
        renamed = copy.deepcopy(self.units)
        renamed[0]['key'] = '测试.改名'
        mutations.append(renamed)
        for rows in mutations:
            with self.assertRaises(ValueError):
                validate_registry_delta(UnitRegistry(rows), self.units)
        validate_registry_delta(UnitRegistry(self.units + [dict(id=500, spritename='x', key='测试.新增')]), self.units)

    def test_book_spawn_normalization_preserves_parameters_order_and_source(self):
        enemy = dict(Type='cf6.特种兵.二阶段', Level=30, Quantity=2, Parameters=dict(Type='opaque.parameter'))
        phase = dict(groups=[dict(enemies=[dict(Type='cf6.特种兵.持盾一阶段')])])
        stage = dict(enemies=['堕落城.左轮', 1, '测试.零号'],
                     stage=dict(Wave=dict(SubWave=[dict(EnemyGroup=dict(Enemy=[enemy, dict(Type='兵种467')]))])),
                     bossEncounter=dict(groups=[dict(enemies=[copy.deepcopy(enemy)])], nextPhase=phase))
        data = dict(maps=[stage], bossEncounter=dict(groups=[dict(pools=[['堕落城.左轮', 1], ['测试.零号']])]))
        original = copy.deepcopy(data)
        result = normalize_book_units(data, self.registry)
        self.assertEqual([44, 1, 0], result['maps'][0]['enemies'])
        out = result['maps'][0]['stage']['Wave']['SubWave'][0]['EnemyGroup']['Enemy']
        self.assertEqual(['兵种466', '兵种467'], [row['Type'] for row in out])
        self.assertEqual('opaque.parameter', out[0]['Parameters']['Type'])
        self.assertEqual('兵种467', result['maps'][0]['bossEncounter']['nextPhase']['groups'][0]['enemies'][0]['Type'])
        self.assertEqual([[44, 1], [0]], result['bossEncounter']['groups'][0]['pools'])
        self.assertEqual(original, data)
        data['maps'][0]['bossEncounter']['groups'][0]['enemies'][0]['Type'] = 'cf6.拼错'
        with self.assertRaisesRegex(ValueError, 'bossEncounter.*unknown unit reference'):
            normalize_book_units(data, self.registry)

    def test_current_books_remain_byte_equivalent_after_normalization(self):
        registry = UnitRegistry.load(ROOT)
        builder = module_at('tools/build-book-definition.py', 'semantic_book_builder')
        for stem in ['repair-campus', 'cf6-sting', 'cf6-type61']:
            source = json.loads((ROOT / 'data/stages/books' / (stem + '.json')).read_text('utf-8-sig'))
            runtime = json.loads((ROOT / 'data/stages/books' / (stem + '.runtime.json')).read_text('utf-8-sig'))
            if stem == 'repair-campus':
                source = builder.resolve_book_choices(source)
            self.assertEqual(runtime, normalize_book_units(source, registry), stem)

    def test_real_cf6_books_accept_keys_and_keep_generated_runtime_bytes(self):
        registry = UnitRegistry.load(ROOT)
        builder = module_at('tools/build-book-definition.py', 'semantic_book_builder')
        keys = {'兵种' + str(identity): row['key'] for identity, row in registry.by_id.items() if 'key' in row}
        def author(value):
            if isinstance(value, list):
                return [author(item) for item in value]
            if isinstance(value, dict):
                return {key: (keys.get(item, item) if key == 'Type' and isinstance(item, str)
                              else copy.deepcopy(item) if key == 'Parameters' else author(item))
                        for key, item in value.items()}
            return value
        for stem in ['cf6-sting', 'cf6-type61']:
            source = json.loads((ROOT / 'data/stages/books' / (stem + '.json')).read_text('utf-8-sig'))
            runtime = json.loads((ROOT / 'data/stages/books' / (stem + '.runtime.json')).read_text('utf-8-sig'))
            semantic = author(source)
            self.assertNotEqual(runtime, semantic, stem)
            normalized = normalize_book_units(semantic, registry)
            self.assertEqual(runtime, normalized, stem)
            self.assertEqual(builder.generated_cf6(runtime), builder.generated_cf6(normalized), stem)

    def test_current_references_and_registered_keys(self):
        result = audit(ROOT, 'HEAD')
        self.assertEqual(len(UnitRegistry.load(ROOT).by_id), result['unit_count'])
        self.assertEqual(result['unit_count'], result['semantic_key_count'] + result['legacy_only_count'])
        self.assertGreater(result['semantic_key_count'], 0)
        self.assertGreater(result['semantic_references'], 0)

    def test_stage_and_book_audit_reject_dialogue_typos_whitespace_and_legacy_under_require_all(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            all_keyed_units = [dict(row, key=row.get('key', f'测试.补齐{row["id"]}')) for row in self.units]
            (root / 'data/units').mkdir(parents=True)
            (root / 'data/units/units.json').write_text(json.dumps(all_keyed_units, ensure_ascii=False), 'utf-8')
            (root / 'data/stages/books').mkdir(parents=True)
            stage_dir = root / 'data/stages/测试区'
            stage_dir.mkdir(parents=True)
            (stage_dir / '__list__.xml').write_text('<root><StageInfo><Name>测试关</Name></StageInfo></root>', 'utf-8')
            stage_file = stage_dir / '测试关.xml'
            stage_file.write_text(
                '<GameStage><SubStage id="0">'
                '<Event><Dialogue id="0"><Type>测试.零号</Type></Dialogue></Event>'
                '<Wave><SubWave id="0"><Dialogue><SubDialogue id="0"><Type>cf6.特种兵.二阶段</Type></SubDialogue></Dialogue>'
                '<EnemyGroup><Enemy><Type>cf6.特种兵.持盾一阶段</Type></Enemy></EnemyGroup></SubWave></Wave>'
                '</SubStage></GameStage>',
                'utf-8',
            )
            counts = audit(root, None, require_all=True)
            self.assertEqual(3, counts['semantic_references'])
            self.assertEqual(0, counts.get('legacy_references', 0))

            # Event/Dialogue/Type typo must fail
            stage_file.write_text(
                '<GameStage><SubStage id="0"><Event><Dialogue id="0"><Type>测试.不存在</Type></Dialogue></Event></SubStage></GameStage>',
                'utf-8',
            )
            with self.assertRaisesRegex(ValueError, 'unknown unit reference'):
                audit(root, None)

            # Leading/trailing whitespace in direct Type or CaseSwitch/Case must fail (matching AS2 ignoreWhite=true)
            for xml in [
                '<GameStage><SubStage id="0"><EnemyGroup><Enemy><Type> 测试.零号 </Type></Enemy></EnemyGroup></SubStage></GameStage>',
                '<GameStage><SubStage id="0"><Event><Dialogue id="0"><Type> 测试.零号 </Type></Dialogue></Event></SubStage></GameStage>',
                '<GameStage><SubStage id="0"><EnemyGroup><Enemy><Type><CaseSwitch expression="x"><Case> 测试.零号 </Case></CaseSwitch></Type></Enemy></EnemyGroup></SubStage></GameStage>',
            ]:
                stage_file.write_text(xml, 'utf-8')
                with self.subTest(xml=xml), self.assertRaisesRegex(ValueError, 'unknown unit reference'):
                    audit(root, None)

            # Legacy reference under require_all=True must fail
            stage_file.write_text(
                '<GameStage><SubStage id="0"><EnemyGroup><Enemy><Type>兵种0</Type></Enemy></EnemyGroup></SubStage></GameStage>',
                'utf-8',
            )
            with self.assertRaisesRegex(ValueError, 'Legacy references remain'):
                audit(root, None, require_all=True)


if __name__ == '__main__':
    unittest.main()
