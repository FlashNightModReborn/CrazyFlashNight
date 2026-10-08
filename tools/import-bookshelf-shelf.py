"""Import the generated bookshelf shelf graybox scene as a bounded presentation asset.

The generator (tools/bookshelf-graybox/generate.js) produces scene.glb + label
textures + report from the design draft and the authoritative book catalog.
This importer derives the runtime config, pins every file with sha256 and can
re-verify the whole closure with --check. No network, saves or gameplay data.
"""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'launcher/web/assets/bookshelf/shelf'
DESIGN = ROOT / 'docs/design-data/bookshelf-shelf-draft.json'
CATALOG = ROOT / 'data/books/catalog.json'
SOURCE = ROOT / 'tools/bookshelf-graybox/out'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def vec(value, label):
    assert isinstance(value, list) and len(value) == 3, label
    assert all(isinstance(n, (int, float)) and math.isfinite(n) for n in value), label
    return value


def glb_parse(data):
    magic, version, length = struct.unpack_from('<III', data)
    assert (magic, version, length) == (0x46546C67, 2, len(data)), 'Invalid GLB'
    n, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4E4F534A, 'Missing JSON chunk'
    doc = json.loads(data[20:20 + n])
    start = 20 + n
    blen, bkind = struct.unpack_from('<II', data, start)
    assert bkind == 0x004E4942 and start + 8 + blen <= len(data), 'Missing BIN chunk'
    return doc, data[start + 8:start + 8 + blen]


def glb_audit(data):
    doc, _ = glb_parse(data)
    assert all('uri' not in r for r in doc.get('buffers', [])), 'External buffer'
    assert all('uri' not in r for r in doc.get('images', [])), 'External image'
    primitives = [p for m in doc.get('meshes', []) for p in m['primitives']]
    triangles = sum(doc['accessors'][p['indices']]['count'] // 3 for p in primitives if p.get('mode', 4) == 4)
    return {'bytes': len(data), 'meshes': len(doc.get('meshes', [])),
            'primitives': len(primitives), 'triangles': triangles,
            'materials': len(doc.get('materials', [])), 'images': len(doc.get('images', []))}


def glb_images(data):
    doc, binchunk = glb_parse(data)
    result = {}
    for image in doc.get('images', []):
        view = doc['bufferViews'][image['bufferView']]
        offset = view.get('byteOffset', 0)
        result[image['name']] = binchunk[offset:offset + view['byteLength']]
    return result


def identities():
    design, catalog = read(DESIGN), read(CATALOG)
    assert design['schema'] == 'bookshelf-shelf-design/1', 'Unexpected design draft'
    books = [b['id'] for b in catalog['books']]
    assert design['books'] + [design['playableBook']] == books, 'Design/catalog book mismatch'
    playable = next(b for b in catalog['books'] if b['id'] == design['playableBook'])
    discs = [c['id'] for c in playable['chapters']]
    assert design['discs'] == discs, 'Design/catalog disc mismatch'
    for book in catalog['books']:
        asset = book.get('boxArt') if book['format'] == 'playable' else book.get('spine')
        assert isinstance(asset, str) and asset.startswith('shelf/textures/'), 'Missing presentation asset: ' + book['id']
    for chapter in playable['chapters']:
        assert chapter.get('cover') == f"shelf/textures/disc-{chapter['id']}.png", 'Missing disc cover: ' + chapter['id']
    return design, catalog, books, discs


def derive_config(design, catalog, discs, scene_hash):
    entries = {}
    for book in catalog['books']:
        if book['format'] == 'playable':
            meshes = ['BOX_crazy-flasher', 'LABEL_box_crazy-flasher']
            for disc in discs:
                meshes += ['DISC_' + disc, 'LABEL_' + disc]
            entries[book['id']] = {'kind': 'box', 'meshes': meshes}
        else:
            entries[book['id']] = {'kind': 'book', 'meshes': ['BOOK_' + book['id'], 'LABEL_' + book['id']]}
    camera = design['camera']
    zone = design['archiveZone']
    archive_zone = {'leftEdge': zone['leftEdge'], 'floorY': zone['floorY'], 'gap': zone['gap'], 'width': zone['width'],
                    'height': zone['height'], 'depth': zone['depth'], 'z': zone['z'],
                    'max': zone['max'], 'color': zone['color'], 'label': zone['label']}
    return {'schema': 'bookshelf-shelf.v1',
            'camera': {'gltfPosition': vec(camera['gltfPosition'], 'camera position'),
                       'gltfTarget': vec(camera['gltfTarget'], 'camera target'),
                       'horizontalSpan': camera['horizontalSpan'],
                       'minSpan': camera['minSpan'], 'maxSpan': camera['maxSpan']},
            'lighting': design['lighting'], 'hoverPull': design['hoverPull'], 'archiveZone': archive_zone,
            'entries': entries, 'assetHashes': {'scene.glb': scene_hash}}


def generator_inputs(report):
    paths = [Path(__file__)]
    return report['generatorInputs'] + [{'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p.read_bytes())} for p in paths]


def check_generator_inputs(report):
    for item in generator_inputs(report):
        assert sha((ROOT / item['path']).read_bytes()) == item['sha256'], 'Generator input changed: ' + item['path']


def texture_names(catalog, design):
    names = set()
    for book in catalog['books']:
        if book['format'] == 'playable':
            names.add('box-crazy-flasher')
        else:
            names.add('spine-' + book['id'])
        for chapter in book.get('chapters', []):
            names.add('disc-' + chapter['id'])
    names.add(design['extractSources']['body'])
    return names


def source_assets():
    """Extraction closures: Ruffle channel (CF1 title) and ffdec vector channel
    (shelf body + native spines), each pinned by its own report."""
    assets = []
    channels = []
    for folder, report_name, schema in [
            (ROOT / 'tools/bookshelf-shelf-extract/out', 'extract-report.json', 'bookshelf-shelf-extract-report/1'),
            (ROOT / 'tools/bookshelf-shelf-extract/out-ffdec', 'ffdec-report.json', 'bookshelf-shelf-ffdec-report/1')]:
        report = read(folder / report_name)
        assert report['schema'] == schema, 'Unexpected extract report: ' + report_name
        for name, entry in sorted(report['files'].items()):
            data = (folder / name).read_bytes()
            assert len(data) == entry['bytes'] and sha(data) == entry['sha256'], 'Extracted art drift: ' + name
            assets.append({'path': f'{folder.relative_to(ROOT).as_posix()}/{name}',
                           'bytes': entry['bytes'], 'sha256': entry['sha256']})
        channels.append(report.get('sources') or [report.get('source')])
    return channels, assets


def assemble(source):
    scene = (source / 'scene.glb').read_bytes()
    report = read(source / 'report.json')
    check_generator_inputs(report)
    assert report['schema'] == 'bookshelf-shelf-graybox-report/1', 'Unexpected generator report'
    assert report['scene']['sha256'] == sha(scene) and report['scene']['bytes'] == len(scene), 'Report belongs to another GLB'
    extract_channels, assets = source_assets()
    design, catalog, _, discs = identities()
    names = texture_names(catalog, design)
    textures = {}
    for name in sorted(names):
        data = (source / 'textures' / (name + '.png')).read_bytes()
        assert report['textures'][name]['sha256'] == sha(data), 'Texture differs from report: ' + name
        textures['textures/' + name + '.png'] = data
    embedded = glb_images(scene)
    assert set(embedded) == names, 'GLB embedded images differ from catalog texture set'
    for name in names:
        assert embedded[name] == textures['textures/' + name + '.png'], 'Embedded texture differs: ' + name
    config = derive_config(design, catalog, discs, sha(scene))
    node_names = {node.get('name') for node in glb_parse(scene)[0].get('nodes', [])}
    for entry in config['entries'].values():
        assert all(mesh in node_names for mesh in entry['meshes']), 'Entry mesh missing from GLB'
    output = {'scene.glb': scene, 'config.json': encoded(config), 'report.json': encoded(report)}
    output.update(textures)
    manifest = {'schema': 'bookshelf-shelf.v1',
                'scope': 'Bookshelf overview graybox presentation; no Host, save or gameplay authority',
                'generatorInputs': generator_inputs(report),
                'designSha256': sha(DESIGN.read_bytes()), 'catalogSha256': sha(CATALOG.read_bytes()),
                'artSources': {'channels': ['tools/bookshelf-shelf-extract/out/extract-report.json',
                                            'tools/bookshelf-shelf-extract/out-ffdec/ffdec-report.json'],
                               'movies': extract_channels, 'files': assets},
                'audit': glb_audit(scene),
                'files': [{'path': name, 'bytes': len(data), 'sha256': sha(data)} for name, data in sorted(output.items())]}
    output['manifest.json'] = encoded(manifest)
    return output


def import_export(source):
    output = assemble(source)
    DEST.mkdir(parents=True, exist_ok=True)
    for old in DEST.rglob('*'):
        if old.is_file():
            old.unlink()
    for name, data in output.items():
        target = DEST / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    audit = json.loads(output['manifest.json'])['audit']
    print(f"bookshelf shelf: {audit['meshes']} meshes, {audit['triangles']} triangles, "
          f"{audit['images']} images, {audit['bytes']} bytes; imported")


def check():
    report = read(DEST / 'report.json')
    check_generator_inputs(report)
    manifest = read(DEST / 'manifest.json')
    assert manifest['generatorInputs'] == generator_inputs(report), 'Generator/importer changed; regenerate and reimport'
    expected = assemble(DEST)
    for name, data in expected.items():
        target = DEST / name
        assert target.is_file() and target.read_bytes() == data, 'Shelf asset stale: ' + name
    actual = {p.relative_to(DEST).as_posix() for p in DEST.rglob('*') if p.is_file()}
    assert actual == set(expected), 'Unexpected files in shelf closure: ' + json.dumps(sorted(actual - set(expected)))
    assert manifest['audit'] == glb_audit((DEST / 'scene.glb').read_bytes()), 'Audit drift'
    print(json.dumps({'ok': True, **manifest['audit']}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', nargs='?', type=Path, help='Generator output directory (default tools/bookshelf-graybox/out)')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check and args.source:
        parser.error('--check does not import')
    if args.check:
        check()
    else:
        import_export(args.source or SOURCE)
