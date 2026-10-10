"""Read-only Blender source inspection; no rendering and no .blend saving.

Run from the merged package root:
  blender -b model-source/bookshelf-v3.blend --python source-qa/verify-blend.py
The report is written only to source-qa/blend-dependencies.json.
"""
from pathlib import Path
import hashlib
import json
import bpy

ROOT = Path(__file__).resolve().parent.parent
report_path = ROOT / 'source-qa' / 'blend-dependencies.json'
images = []
for im in bpy.data.images:
    if im.source != 'FILE':
        continue
    packed = im.packed_file
    data = bytes(packed.data) if packed else b''
    name = Path(im.filepath).name
    supplied = ROOT / 'model-source' / 'textures' / name
    size = list(im.size)
    pixels_readable = False
    if all(size) and len(im.pixels):
        float(im.pixels[0])
        pixels_readable = True
    images.append({
        'image': im.name,
        'texture': 'model-source/textures/' + name,
        'packed': packed is not None,
        'packedBytes': len(data),
        'dimensions': size,
        'pixelsReadable': pixels_readable,
        'suppliedTextureExists': supplied.is_file(),
        'packedMatchesSuppliedTexture': bool(data) and supplied.is_file() and data == supplied.read_bytes(),
        'sha256': hashlib.sha256(data).hexdigest() if data else None,
    })
expected = {
    'CF7_BOOKSHELF_ROOT', 'BOOK_dust', 'BOOK_babylon', 'BOOK_guardian',
    'BOOK_sail-twins', 'COLLECTION_CF1_6', 'ARCHIVE_BANK',
    'ARCHIVE_ALL_DRAWER', 'ARCHIVE_SHORTCUT_current',
    'ARCHIVE_SHORTCUT_recent02', 'ARCHIVE_SHORTCUT_recent03',
    *('DISC_CF' + str(i) for i in range(1, 7)),
}
missing = sorted(expected - set(bpy.data.objects.keys()))
external = [lib.name for lib in bpy.data.libraries]
image_ok = len(images) == 26 and all(
    i['packed'] and i['pixelsReadable'] and i['packedMatchesSuppliedTexture']
    for i in images
)
report = {
    'scope': 'Read-only Blender scene load, packed image decode and byte comparison, external library and semantic-node checks. No render, browser or gameplay validation.',
    'blenderVersion': bpy.app.version_string,
    'source': 'model-source/bookshelf-v3.blend',
    'sourceSHA256': hashlib.sha256((ROOT / 'model-source/bookshelf-v3.blend').read_bytes()).hexdigest(),
    'imageCount': len(images),
    'images': images,
    'linkedLibraries': external,
    'missingSemanticNodes': missing,
    'allPassed': image_ok and not external and not missing,
}
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'images'}, ensure_ascii=False))
if not report['allPassed']:
    raise RuntimeError('Source dependency validation failed; inspect source-qa/blend-dependencies.json')
