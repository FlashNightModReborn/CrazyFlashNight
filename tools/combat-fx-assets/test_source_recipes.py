"""Focused adapter contracts; no Flash, Java, network or source writes."""
import copy
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import source_recipes as recipes


class SourceRecipeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plans, cls.sources = recipes.recipe()
        cls.by_name = {p['linkage']: p for p in cls.plans}

    def test_new_styles_append_to_the_original_35_and_bind_their_sources(self):
        self.assertEqual(42, len(self.plans))
        expected = ['冰汽', '烈焰火花', '能量火花', '空手攻击火花', '铁枪能量弹枪火', '飙血', '子弹碎片-飞血']
        self.assertEqual(expected, [p['linkage'] for p in self.plans[35:]])
        self.assertEqual(list(range(42)), [p['index'] for p in self.plans])
        libraries = {s['key']: s for s in recipes.SOURCE_LIBRARIES}
        self.assertEqual({'stock', 'mist', 'fs'}, set(libraries))
        for plan in self.plans:
            self.assertIn((recipes.ROOT / libraries[plan['sourceKey']]['libraryRoot'] /
                           (plan['sourceSymbol'] + '.xml')).resolve(), self.sources)

    def test_removal_frames_are_not_extra_visible_ticks(self):
        for name, length in [('冰汽', 7), ('烈焰火花', 9), ('能量火花', 9), ('空手攻击火花', 3)]:
            self.assertEqual([list(range(length))], self.by_name[name]['variants'])
        self.assertEqual([5, 3, 4], [len(v) for v in self.by_name['铁枪能量弹枪火']['variants']])

    def test_bullet_consumer_can_load_the_helper_without_adding_its_directory(self):
        result = subprocess.run([sys.executable, '-B', '-X', 'utf8', '-c',
            'import runpy,sys; m=runpy.run_path(sys.argv[1]); '
            'assert callable(m["exports"]) and callable(m["java_tool"])',
            str(recipes.ROOT / 'tools/combat-fx-assets/build.py')], cwd=recipes.ROOT,
            capture_output=True, text=True, encoding='utf-8', timeout=10)
        self.assertEqual(0, result.returncode, result.stderr)

    def test_ordinary_blood_has_seven_birth_cues_and_five_static_droplets(self):
        blood = self.by_name['飙血']
        self.assertEqual([12, 10, 8, 24, 18, 39, 18], [len(v) for v in blood['variants']])
        self.assertEqual(['blood1.mp3', 'blood2.wav', 'blood3.mp3', 'blood4.mp3',
                          'blood5.wav', 'blood6.wav', 'blood7.wav'], blood['variantSounds'])
        self.assertTrue(blood['soundAtBirth'])
        self.assertTrue(blood['worldLit'])
        droplets = self.by_name['子弹碎片-飞血']
        self.assertEqual('blood', droplets['kind'])
        self.assertEqual([[i] for i in range(5)], droplets['variants'])
        self.assertEqual('无AS链接/飞血动画', droplets['sourceSymbol'])
        self.assertEqual('child', droplets['renderMode'])

    def test_unarmed_texture_bakes_fixed_scale_once_and_keeps_child_translation(self):
        unarmed = self.by_name['空手攻击火花']
        self.assertEqual([1, 0, 0, 1, -1.2, -1.7], unarmed['nestedTransform'])
        self.assertEqual(.284439086914063, unarmed['sourceNestedTransform'][0])
        self.assertTrue(unarmed['randomRotation'])
        self.assertTrue(unarmed['unitScaleXOnly'])
        self.assertEqual('nested-scaled', unarmed['renderMode'])

    def test_a_sound_moved_off_its_variant_birth_is_rejected(self):
        file = recipes.ROOT / recipes.SOURCE_LIBRARIES[0]['libraryRoot'] / '特效-血液组/飙血.xml'
        root = ET.parse(file).getroot()
        for frame in root.iter(recipes.NS + 'DOMFrame'):
            if any('blood1.wav' in (script.text or '') for script in frame.iter(recipes.NS + 'script')):
                frame.set('index', '2')
        with self.assertRaisesRegex(ValueError, 'birth frames'):
            recipes.sequence(root, 'blood-impact')

    def test_unknown_gameplay_script_is_not_treated_as_a_visual_sequence(self):
        root = ET.fromstring('<DOMSymbolItem xmlns="http://ns.adobe.com/xfl/2008/">'
            '<DOMFrame index="0"><script>_root.子弹区域shoot传递(this);</script></DOMFrame>'
            '<DOMFrame index="3"><script>this.removeMovieClip();</script></DOMFrame></DOMSymbolItem>')
        with self.assertRaisesRegex(ValueError, 'Unknown effect behavior'):
            recipes.sequence(root, 'sequence')
    def test_changed_unarmed_filter_is_rejected(self):
        real_parse = recipes.ET.parse
        def altered(path):
            tree = real_parse(path)
            if Path(path).name == '空手攻击火花.xml':
                tree = copy.deepcopy(tree)
                next(tree.getroot().iter(recipes.NS + 'GlowFilter')).set('blurX', '100')
            return tree
        with patch.object(recipes.ET, 'parse', side_effect=altered):
            with self.assertRaisesRegex(ValueError, 'unarmed filter'):
                recipes.recipe()

    def test_legacy_event_sounds_are_bound_to_each_variant_birth(self):
        expected = {'火花': [13, 12, 11, 10, 9], '击中金属': [8, 7, 6, 5],
                    '拼刀火花': [530, 531, 532, 533, 534, 535],
                    '战术巴雷特击中特效': [454], '屎花': [4, 3, 2, 1]}
        for name, ids in expected.items():
            plan = self.by_name[name]
            self.assertTrue(plan['soundAtBirth'])
            self.assertEqual(['cfnfx-stock-%d.wav' % sound_id for sound_id in ids], plan['variantSounds'])
        self.assertEqual(set(expected) | {'飙血'}, {p['linkage'] for p in self.plans if p['soundAtBirth']})

    def test_common_frame_zero_event_applies_to_every_selected_variant(self):
        root = ET.parse(recipes.ROOT / recipes.SOURCE_LIBRARIES[0]['libraryRoot'] /
                        '特效-击中效果组/战术巴雷特击中特效.xml').getroot()
        self.assertEqual(['cfnfx-stock-454.wav'] * 3, recipes.timeline_cues(
            root, '战术巴雷特击中特效', [[1, 2], [4, 5], [8, 9]]))

    def test_timeline_sound_sync_or_delayed_event_is_not_ignored(self):
        file = recipes.ROOT / recipes.SOURCE_LIBRARIES[0]['libraryRoot'] / '特效-击中效果组/火花.xml'
        for change in ('soundSync', 'index'):
            root = ET.parse(file).getroot()
            frame = next(f for f in root.iter(recipes.NS + 'DOMFrame') if f.get('soundName'))
            frame.set(change, 'stream' if change == 'soundSync' else '2')
            with self.assertRaisesRegex(ValueError, 'timeline sound'):
                recipes.timeline_cues(root, '火花', self.by_name['火花']['variants'])

    def test_a_new_nested_sound_requires_explicit_adaptation(self):
        real_parse = recipes.ET.parse
        def altered(path):
            tree = real_parse(path)
            if Path(path).name == 'Symbol 617.xml':
                tree = copy.deepcopy(tree)
                next(tree.getroot().iter(recipes.NS + 'DOMFrame')).set('soundName', 'unreviewed.wav')
            return tree
        with patch.object(recipes.ET, 'parse', side_effect=altered):
            with self.assertRaisesRegex(ValueError, 'Nested sound'):
                recipes.recipe()

    def test_published_swf_audio_matches_all_roots_and_retains_mp3_seek(self):
        helper = runpy.run_path(str(recipes.ROOT / 'tools/combat-fx-assets/build.py'))
        sounds = helper['published_sound_plan'](self.plans)
        by_id = {s['sourceSoundId']: s for s in sounds}
        self.assertEqual(20, len(by_id))
        self.assertEqual((1677, 44100, 29611), tuple(by_id[13][k] for k in
                         ('sourceSeekSamples', 'sampleRate', 'sampleFrames')))
        self.assertEqual((1669, 11025, 3834), tuple(by_id[8][k] for k in
                         ('sourceSeekSamples', 'sampleRate', 'sampleFrames')))
        self.assertEqual(0, by_id[530]['sourceSeekSamples'])
        for sound in sounds:
            self.assertEqual('sounds/export/特效/' + sound['id'], sound['path'])

    def test_canonical_blood_cues_exist_as_exact_sfx_filenames(self):
        available = {p.name for pack in ('武器', '特效', '人物')
                     if (recipes.ROOT / 'sounds/export' / pack).is_dir()
                     for p in (recipes.ROOT / 'sounds/export' / pack).iterdir() if p.is_file()}
        self.assertTrue(set(recipes.BLOOD_CUES) <= available)

    def test_generated_pcm_is_checked_and_missing_full_basename_is_rejected(self):
        helper = runpy.run_path(str(recipes.ROOT / 'tools/combat-fx-assets/build.py'))
        catalog = json.loads((recipes.ROOT / 'data/combat_visuals/effects.v1.json').read_text(encoding='utf-8'))
        self.assertGreater(helper['verify_sound_assets'](catalog, self.plans), 0)
        damaged = copy.deepcopy(catalog)
        damaged['soundAssets'][0]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'integrity'):
            helper['verify_sound_assets'](damaged, self.plans)
        plans = copy.deepcopy(self.plans)
        plans[40]['variantSounds'][0] = 'blood1.wav'
        with self.assertRaisesRegex(ValueError, 'exact preloaded filename'):
            helper['verify_sound_assets'](catalog, plans)

    def test_sparse_sound_pack_skips_missing_packs_but_requires_every_actual_cue(self):
        helper = runpy.run_path(str(recipes.ROOT / 'tools/combat-fx-assets/build.py'))
        catalog = json.loads((recipes.ROOT / 'data/combat_visuals/effects.v1.json').read_text(encoding='utf-8'))
        published = helper['published_sound_plan'](self.plans)
        scratch = (recipes.ROOT / 'tmp/combat-fx-assets').resolve()
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='sparse-audio-', dir=scratch) as directory:
            sparse = Path(directory).resolve()
            self.assertTrue(sparse.is_relative_to(scratch))
            target = sparse / 'sounds/export/特效'
            target.mkdir(parents=True)
            cues = {cue for plan in self.plans for cue in plan['variantSounds']}
            self.assertEqual(27, len(cues))
            for cue in cues:
                shutil.copyfile(recipes.ROOT / 'sounds/export/特效' / cue, target / cue)
            self.assertFalse((sparse / 'sounds/export/武器').exists())
            self.assertFalse((sparse / 'sounds/export/人物').exists())
            # Published SWF identities are exercised separately; this fixture only
            # materializes the exact 27 audio files consumed by a sparse request.
            with patch.dict(helper['verify_sound_assets'].__globals__, {
                    'ROOT': sparse, 'published_sound_plan': lambda _: published}):
                self.assertGreater(helper['verify_sound_assets'](catalog, self.plans), 0)
                (target / 'blood1.mp3').unlink()
                with self.assertRaisesRegex(ValueError, 'exact preloaded filename'):
                    helper['verify_sound_assets'](catalog, self.plans)


if __name__ == '__main__':
    unittest.main()
