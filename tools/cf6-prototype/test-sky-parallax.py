"""Targeted in-memory tests for the sky-parallax fragment merge in build-chapter.py.

These cover the assembler contract only; they do not substitute for AVM1,
visual, or full-route gameplay acceptance, and they never write shared outputs.
"""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('build_chapter',
                                              Path(__file__).with_name('build-chapter.py'))
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)


def real_fragment():
    return bc.read(bc.SKY_PARALLAX)


def fake_chapter():
    """Minimal chapter shell carrying content the merge must never touch."""
    content = {
        'background': 'cf6/CF6_{}_BG.swf',
        'stage': {'BasicInformation': {'PlayerX': 134.95, 'PlayerY': 329.6}},
        'economy': {'gold': 1},
    }
    chapter = {'maps': []}
    for map_id in ('A02', 'A06'):
        stage = copy.deepcopy(content)
        stage['background'] = stage['background'].format(map_id)
        stage['id'] = map_id
        stage['mechanism'] = {'kind': 'exit', 'layers': [
            {'id': 'foreground', 'role': 'foreground',
             'url': 'flashswf/backgrounds/cf6/CF6_' + map_id + '_foreground.swf',
             'x': 114.45, 'y': 34.2, 'width': 1211.95, 'height': 178.75, 'depth': 10}]}
        chapter['maps'].append(stage)
    return chapter


def layers_of(chapter, map_id):
    return next(m for m in chapter['maps'] if m['id'] == map_id)['mechanism']['layers']


class FragmentValidationTests(unittest.TestCase):
    def test_real_fragment_validates(self):
        fragment = bc.load_sky_parallax(bc.SKY_PARALLAX)
        self.assertEqual(set(fragment['maps']), {'A02', 'A06'})

    def reject(self, mutate, pattern='.'):
        fragment = real_fragment()
        mutate(fragment)
        with self.assertRaisesRegex(ValueError, pattern):
            bc.validate_sky_fragment(fragment)

    def test_unknown_map_rejected(self):
        def mutate(f):
            f['maps']['A03'] = copy.deepcopy(f['maps']['A06'])
        self.reject(mutate, 'unknown maps')

    def test_wrong_fragment_space_rejected(self):
        self.reject(lambda f: f.update(coordinateSpace='world'), 'root-stage')

    def test_wrong_layer_space_rejected(self):
        def mutate(f):
            f['maps']['A02']['layers'][0]['coordinateSpace'] = 'world'
        self.reject(mutate, 'root-stage')

    def test_unknown_role_rejected(self):
        def mutate(f):
            f['maps']['A02']['layers'][0]['role'] = 'foreground'
        self.reject(mutate, 'role')

    def test_duplicate_layer_id_rejected(self):
        def mutate(f):
            f['maps']['A02']['layers'][1]['id'] = 'sky'
        self.reject(mutate, 'duplicate')

    def test_duplicate_role_rejected(self):
        def mutate(f):
            f['maps']['A02']['layers'][1]['role'] = 'screen-fixed'
        self.reject(mutate, 'duplicate')

    def test_non_positive_size_rejected(self):
        self.reject(lambda f: f['maps']['A02']['layers'][0].update(width=0), 'positive')
        self.reject(lambda f: f['maps']['A06']['layers'][0].update(height=-187), 'positive')

    def test_non_finite_placement_rejected(self):
        self.reject(lambda f: f['maps']['A06']['layers'][0].update(x=float('nan')), 'non-finite')
        self.reject(lambda f: f['maps']['A02']['layers'][1].update(y=float('inf')), 'non-finite')

    def test_bad_depth_rejected(self):
        self.reject(lambda f: f['maps']['A02']['layers'][0].update(depth=-1), 'depth')
        self.reject(lambda f: f['maps']['A02']['layers'][0].update(depth=0.5), 'depth')

    def test_path_escape_rejected(self):
        def mutate(f):
            f['maps']['A02']['layers'][0]['url'] = 'flashswf/backgrounds/cf6/../CF6_A02_sky.swf'
        self.reject(mutate, 'url')

    def test_cross_map_url_rejected(self):
        def mutate(f):
            f['maps']['A02']['layers'][0]['url'] = 'flashswf/backgrounds/cf6/CF6_A06_sky.swf'
        self.reject(mutate, 'url')

    def test_non_swf_url_rejected(self):
        def mutate(f):
            f['maps']['A06']['layers'][0]['url'] = 'flashswf/backgrounds/cf6/CF6_A06_sky.png'
        self.reject(mutate, 'url')

    def test_bad_schema_rejected(self):
        self.reject(lambda f: f.update(schema='cf6-sky-parallax-fragment.v0'), 'schema')


class MergeTests(unittest.TestCase):
    def test_layers_appended_without_second_transform(self):
        chapter = fake_chapter()
        bc.apply_sky_parallax(chapter, real_fragment(), require_swfs=False)
        a02 = layers_of(chapter, 'A02')
        sky, city = a02[1], a02[2]
        # Exact declared root-stage values: no map-origin subtraction, no world scale.
        self.assertEqual((sky['x'], sky['y'], sky['width'], sky['height'], sky['depth']),
                         (0, 0, 600, 187, 0))
        self.assertEqual((city['x'], city['y'], city['width'], city['height'], city['depth']),
                         (0, 109, 1441.4, 66.45, 1))
        self.assertEqual(city['coordinateSpace'], 'root-stage')
        a06 = layers_of(chapter, 'A06')
        self.assertEqual((a06[1]['x'], a06[1]['y'], a06[1]['width'], a06[1]['height']),
                         (0, -20, 800, 187))

    def test_replacement_idempotent(self):
        chapter = fake_chapter()
        fragment = real_fragment()
        bc.apply_sky_parallax(chapter, fragment, require_swfs=False)
        once = copy.deepcopy(layers_of(chapter, 'A02'))
        bc.apply_sky_parallax(chapter, fragment, require_swfs=False)
        twice = layers_of(chapter, 'A02')
        self.assertEqual(once, twice)
        self.assertEqual([l['id'] for l in twice].count('sky'), 1)
        self.assertEqual([l['id'] for l in twice].count('city-parallax'), 1)

    def test_old_layers_removed_others_kept(self):
        chapter = fake_chapter()
        old = {'id': 'sky', 'role': 'legacy-sky', 'url': 'x', 'depth': 3}
        layers_of(chapter, 'A02').insert(0, old)
        bc.apply_sky_parallax(chapter, real_fragment(), require_swfs=False)
        layers = layers_of(chapter, 'A02')
        self.assertNotIn(old, layers)
        self.assertEqual(layers[0]['id'], 'foreground')

    def test_other_content_untouched(self):
        chapter = fake_chapter()
        before = copy.deepcopy(chapter)
        bc.apply_sky_parallax(chapter, real_fragment(), require_swfs=False)
        for original, merged in zip(before['maps'], chapter['maps']):
            for key in original:
                if key != 'mechanism':
                    self.assertEqual(merged[key], original[key])
            self.assertEqual(merged['mechanism']['kind'], original['mechanism']['kind'])
            self.assertEqual(merged['mechanism']['layers'][0], original['mechanism']['layers'][0])

    def test_duplicate_role_after_merge_rejected(self):
        chapter = fake_chapter()
        layers_of(chapter, 'A06').append({'id': 'other-sky', 'role': 'screen-fixed'})
        with self.assertRaisesRegex(ValueError, 'duplicate screen-fixed'):
            bc.apply_sky_parallax(chapter, real_fragment(), require_swfs=False)

    def test_duplicate_id_after_merge_rejected(self):
        chapter = fake_chapter()
        bc.apply_sky_parallax(chapter, real_fragment(), require_swfs=False)
        weakened = real_fragment()
        weakened['maps']['A06']['replaceLayerIds'] = []
        with self.assertRaisesRegex(ValueError, 'duplicate mechanism layer id'):
            bc.apply_sky_parallax(chapter, weakened, require_swfs=False)

    def test_strict_mode_requires_layer_swfs(self):
        # Simulate a missing exact resource without deleting the compiled canonical asset.
        fragment = real_fragment()
        skies = [l['url'] for entry in fragment['maps'].values() for l in entry['layers']
                 if l['role'] == 'screen-fixed']
        self.assertTrue(skies)
        missing = bc.ROOT / skies[0]
        actual_is_file = Path.is_file
        with patch.object(Path, 'is_file', lambda p: False if p == missing else actual_is_file(p)):
            with self.assertRaisesRegex(ValueError, 'missing sky-parallax layer SWF'):
                bc.apply_sky_parallax(fake_chapter(), fragment, require_swfs=True)


class AuthorBuildTests(unittest.TestCase):
    """In-memory author-mode build: no shared outputs are written."""

    def test_author_build_merges_and_manifests(self):
        outputs = bc.build(require_swfs=False)
        chapter = json.loads(outputs[bc.OUTPUT].decode('utf-8'))
        fragment = real_fragment()
        maps = {m['id']: m for m in chapter['maps']}
        for map_id, entry in fragment['maps'].items():
            merged = maps[map_id]['mechanism']['layers']
            self.assertEqual([l['id'] for l in merged[-len(entry['layers']):]],
                             [l['id'] for l in entry['layers']])
            for declared, appended in zip(entry['layers'], merged[-len(entry['layers']):]):
                self.assertEqual(appended, declared)
        runtime_path = bc.TOOLS / 'cf6-map-runtime/generated/runtime-index.json'
        runtime = {m['id']: m for m in bc.read(runtime_path)['maps']}
        for map_id in ('A01', 'A03', 'A10'):
            merged = maps[map_id]['mechanism']
            self.assertEqual(merged['kind'], runtime[map_id]['mechanism']['kind'])
            self.assertEqual([(l['id'], l['url']) for l in merged['layers']],
                             [(l['id'], l['url']) for l in runtime[map_id]['mechanism']['layers']])
            self.assertAlmostEqual(merged['assetScale'], 128/75)
        self.assertEqual(maps['A02']['background'], 'cf6/CF6_A02_BG.swf')
        manifest = json.loads(outputs[bc.HERE / 'generated/assembly.json'].decode('utf-8'))
        paths = {i['path']: i['sha256'] for i in manifest['inputs']}
        rel = 'tools/cf6-map-runtime/sky-parallax.fragment.json'
        self.assertIn(rel, paths)
        self.assertEqual(paths[rel],
                         hashlib.sha256(bc.SKY_PARALLAX.read_bytes()).hexdigest())
        self.assertEqual(manifest['skyParallaxLayers']['A02'],
                         {'replaced': ['sky', 'city-parallax'], 'layers': ['sky', 'city-parallax']})
        self.assertEqual(manifest['skyParallaxLayers']['A06'],
                         {'replaced': ['sky'], 'layers': ['sky']})


if __name__ == '__main__':
    unittest.main()
