"""Show actual applied item icons beside Titanium and the preserved review baseline."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tmp/unified61-review'
ICONS = Path('launcher/web/icons')


def main():
    current = json.loads((ROOT / ICONS / 'manifest.json').read_text('utf-8'))
    before = json.loads((OUT / 'before' / ICONS / 'manifest.json').read_text('utf-8'))
    native_hash = hashlib.sha256((ROOT / 'flashswf/arts/new/Codex专用素材.swf').read_bytes()).hexdigest()
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 19)
    small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 16)
    canvas = Image.new('RGBA', (1000, 1000), '#17212b')
    draw = ImageDraw.Draw(canvas)
    labels = ['钛合金61参考', '统合61修正前', '统合61当前', '当前掉落帧']
    for col, label in enumerate(labels):
        draw.text((30 + 245*col, 16), label, fill='white', font=font)
    records = []
    for row, part in enumerate(['头部装甲', '胸甲', '腿甲', '手甲', '装甲鞋']):
        key = 'Codex-统合61式' + part
        assert current[key]['bakeProvenance']['sourceArtifactSha256'] == native_hash
        cells = [(ROOT, current, '钛合金61式' + part, 'f1'),
                 (OUT / 'before', before, key, 'f1'),
                 (ROOT, current, key, 'f1'), (ROOT, current, key, 'f2')]
        for col, (base, manifest, name, frame) in enumerate(cells):
            path = base / ICONS / manifest[name][frame]
            original = Image.open(path).convert('RGBA')
            image = original.copy()
            image.thumbnail((160, 145), Image.Resampling.NEAREST)
            ratio = min(145 / image.width, 145 / image.height)
            image = image.resize((round(image.width*ratio), round(image.height*ratio)), Image.Resampling.NEAREST)
            x, y = 20 + col*245, 50 + row*185
            draw.rectangle((x, y, x+225, y+170), fill='#263541')
            canvas.alpha_composite(image, (x+(225-image.width)//2, y+8+(145-image.height)//2))
            draw.text((x+8, y+148), part + ' ' + str(original.width) + '×' + str(original.height), font=small, fill='#c9d4df')
            records.append({'item': name, 'frame': frame, 'path': path.relative_to(ROOT).as_posix(),
                            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    canvas.convert('RGB').save(OUT / 'icons-after.png')
    (OUT / 'icons-after.json').write_text(json.dumps({'nativeSwfSha256': native_hash,
        'boundary': 'Applied WebP pixels; enlarged without retouching. Not an in-game screenshot.',
        'files': records}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(OUT / 'icons-after.png')


if __name__ == '__main__':
    main()
