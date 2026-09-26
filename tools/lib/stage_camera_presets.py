"""Apply reviewed camera/label inputs to materialized dioramas; never edit GLBs."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'config/stage-select-camera-presets.json'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def preset_input(key):
    source = json.loads(SOURCE.read_text(encoding='utf-8'))
    assert source['schema'] == 1 and source['canvas'] == [1024, 576]
    return source['maps'][key]


def preset_manifest(key):
    return dict(source=SOURCE.relative_to(ROOT).as_posix(),
                sha256=digest(SOURCE.read_bytes()), candidateId=preset_input(key)['candidateId'])


def apply_preset(config, key):
    preset = preset_input(key)
    assert config['frameLabel'] == preset['frameLabel'], 'Preset frame mismatch'
    assert set(config['pins']) == set(preset['pins']), 'Preset entry identities changed'
    camera = copy.deepcopy(config['camera'])
    camera.update(gltfPosition=preset['camera']['position'],
                  gltfTarget=preset['camera']['target'], horizontalSpan=preset['camera']['span'])
    # Keep both coordinate conventions consistent for base-gate authoring tools.
    for name in ('Position', 'Target'):
        if 'blender' + name in camera:
            x, y, z = camera['gltf' + name]
            camera['blender' + name] = [x, -z, y]
    pins = copy.deepcopy(config['pins'])
    for entry_id, values in preset['pins'].items():
        assert set(values) <= {'x', 'y', 'labelX', 'labelY', 'leaderBend', 'screenOffset'}
        pins[entry_id].pop('leaderBend', None)
        pins[entry_id].update(values)
    config.update(camera=camera, pins=pins, presetKey=preset['presetKey'])
    if 'presentationViews' in config:
        config['presentationViews'] = {'refined': dict(label='精修总览', camera=camera, pins=pins),
                                       **{k: v for k, v in config['presentationViews'].items() if k != 'refined'}}
        config['defaultPresentation'] = 'refined'
    # Existing fallbackPins belong to the frozen fallback image, not the new camera.
    return config


def read_config(data_path):
    text = data_path.read_text(encoding='utf-8')
    prefix, body = text.split(' = ', 1)
    return prefix, json.loads(body.rstrip().removesuffix(';'))


def check_preset(data_path, manifest, key):
    _, config = read_config(data_path)
    assert apply_preset(copy.deepcopy(config), key) == config, 'Regenerate camera preset: ' + key
    assert manifest.get('cameraPreset') == preset_manifest(key), 'Stale camera preset source: ' + key


def refresh_preset(data_path, asset_dir, key):
    """Reapply only camera inputs to a verified imported closure, without its art ZIP.

    Full import calls the same apply_preset function. The imported identities,
    materials, focus cameras, fallback image/coordinates and asset bytes stay intact.
    """
    manifest_path = asset_dir / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    for row in manifest['files']:
        data = (ROOT / row['path']).read_bytes()
        if row['path'].endswith('/.gitattributes'):
            data = data.replace(b'\r\n', b'\n')
        assert len(data) == row['bytes'] and digest(data) == row['sha256'], row['path']
    prefix, config = read_config(data_path)
    apply_preset(config, key)
    data = (prefix + ' = ' + json.dumps(config, ensure_ascii=False, indent=2) + ';\n').encode('utf-8')
    relative = data_path.relative_to(ROOT).as_posix()
    rows = [row for row in manifest['files'] if row['path'] == relative]
    assert len(rows) == 1, 'Expected exactly one generated config in the imported closure'
    rows[0].update(bytes=len(data), sha256=digest(data))
    manifest['cameraPreset'] = preset_manifest(key)
    data_path.write_bytes(data)
    manifest_path.write_bytes((json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
