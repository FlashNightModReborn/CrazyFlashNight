"""Compare live exported armor in exact authored short-blade and weapon pose keys."""
from pathlib import Path
import argparse
import importlib.util
import json
import sys
from PIL import Image, ImageDraw, ImageFont
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tmp/unified61-review'
X = {'x': 'http://ns.adobe.com/xfl/2008/'}


def load_baker():
    sys.path.insert(0, str(ROOT / 'tools'))
    spec = importlib.util.spec_from_file_location('unified61_pose_baker', ROOT / 'tools/bake-dressup-offline.py')
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def pose_keys():
    baker = load_baker()
    library = ROOT / 'flashswf/arts/things0/LIBRARY'
    symbols = baker.load_xfl_symbols(library)
    # This review visits later action branches, so do not carry an expired
    # layer's last key into a different branch merely because it precedes it.
    def strict_active_frame(layer, index):
        for row in layer.get('frames', []):
            if row['index'] <= index < row['index'] + max(1, row['duration']):
                return row
        return None
    baker.active_layer_frame = strict_active_frame
    parent_frames = baker.active_symbol_frames(symbols['主角-男'], 407)
    parents = [instance for _, _, frame in parent_frames for instance in frame['instances']
               if instance['libraryItemName'] == 'sprite/兵器待机']
    if len(parents) != 1:
        raise ValueError('Expected the unique live weapon-idle container')
    parent_matrix = parents[0]['matrix']
    raw = E.parse(str(library / 'sprite/兵器待机.xml'))
    keys = [('短兵站立', 166), ('短兵格斗架势', 115), ('刀剑站立', 51), ('长柄站立', 502)]
    result = []
    for label, frame in keys:
        # Only render actual authored keys or held frames. Never guess a tween.
        for layer in raw.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', X):
            for row in layer.findall('x:frames/x:DOMFrame', X):
                start = int(row.get('index', 0))
                if start <= frame < start + int(row.get('duration', 1)):
                    if row.get('tweenType') and start != frame:
                        raise ValueError(f'{label}: intermediate tween in {layer.get("name")}')
        holders = []
        baker.traverse_battle_holders(symbols, '男', '兵器站立', 'sprite/兵器待机', frame,
                                     parent_matrix, holders, [], set())
        baker.reorder_battle_head_holders_for_draw(holders)
        result.append({'label': label, 'frame': frame + 1, 'holders': holders})
    return result


def paint(manifest, variant, gender, pose, asset_root, scale=3.0):
    fields = {}
    for part in ('头部装甲', '胸甲', '腿甲', '手甲', '装甲鞋'):
        fields.update(manifest['items'][variant + '61式' + part]['fieldsByGender'][gender])
    cell = Image.new('RGBA', (380, 460), '#24323f')
    used = []
    for holder in pose['holders']:
        field = holder['field'].removesuffix('_装扮')
        if field not in fields:
            continue
        key = fields[field]
        skin = manifest['skinKeys'][key]
        fr = skin['frames'][0]
        relative = Path('launcher/web/assets/dressup') / fr['uri']
        source = asset_root / relative
        if not source.exists():
            source = ROOT / relative
        bitmap = Image.open(source).convert('RGBA')
        zoom = float(skin['export']['zoom'])
        m = holder['matrix']
        a, b, c, d = (m[k] * scale / zoom for k in ('a', 'b', 'c', 'd'))
        tx = 190 + scale*m['tx'] - a*fr['originX'] - c*fr['originY']
        ty = 426 + scale*m['ty'] - b*fr['originX'] - d*fr['originY']
        det = a*d-b*c
        assert abs(det) > 1e-12
        inverse = (d/det, -c/det, (c*ty-d*tx)/det, -b/det, a/det, (b*tx-a*ty)/det)
        cell.alpha_composite(bitmap.transform(cell.size, Image.Transform.AFFINE, inverse, Image.Resampling.BICUBIC))
        used.append(key)
    assert len(used) == 15, (pose['label'], len(used))
    return cell


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', default='before')
    parser.add_argument('--gender', choices=('男', '女'), default='男')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ROOT / 'launcher/web/assets/dressup/manifest.json').read_text('utf-8'))
    before = json.loads((OUT / 'before/launcher/web/assets/dressup/manifest.json').read_text('utf-8'))
    poses = pose_keys()
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
    canvas = Image.new('RGBA', (1180, 1940), '#16212b')
    draw = ImageDraw.Draw(canvas)
    columns = [('钛合金61参考', manifest, '钛合金', ROOT),
               ('统合61修正前', before, '统合', OUT / 'before'),
               ('统合61当前', manifest, '统合', ROOT)]
    for column, (label, data, variant, asset_root) in enumerate(columns):
        draw.text((column*390+20, 10), label + ' · ' + args.gender, font=font, fill='white')
        for index, pose in enumerate(poses):
            cell = paint(data, variant, args.gender, pose, asset_root)
            ImageDraw.Draw(cell).text((12, 10), pose['label'] + ' / 原生帧' + str(pose['frame']), font=font, fill='#c9d4df')
            canvas.alpha_composite(cell, (column*390+10, index*470+42))
    destination = OUT / ('poses-' + args.label + '-' + args.gender + '.png')
    canvas.convert('RGB').save(destination)
    (destination.with_suffix('.json')).write_text(json.dumps({'source': 'things0 sprite/兵器待机',
        'gender': args.gender, 'poses': poses, 'boundary': 'Exact authored keys with actual SWF-exported skins; no continuous motion claim.'},
        ensure_ascii=False, indent=2), encoding='utf-8')
    print(destination)


if __name__ == '__main__':
    main()
