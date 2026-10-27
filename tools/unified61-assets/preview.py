"""QA assembly of actual SWF-exported skins using the supplied native pose matrices."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    authored = json.loads((HERE / 'source/assembly.json').read_text('utf-8'))
    manifest = json.loads((ROOT / 'launcher/web/assets/dressup/manifest.json').read_text('utf-8'))
    items = json.loads((HERE / 'design.json').read_text('utf-8'))['items']
    poses = [authored['poses'][i] for i in (0, 2, 4, 6, 8, 10)]
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 19)
    small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 15)
    canvas = Image.new('RGBA', (1080, 800), '#17212b')
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 16), '统合61式  原生SWF导出装配', font=font, fill='#e6edf3')
    draw.text((24, 46), '作者姿态矩阵 × 当前SWF导出分件；离线装配预览，不是游戏截图', font=small, fill='#9baec0')
    reports = []
    for index, pose in enumerate(poses):
        gender = pose['recommendedSkinGender']
        fields = {}
        for item in items:
            fields.update(manifest['items'][item['name']]['fieldsByGender'][gender])
        cell = Image.new('RGBA', (340, 334), '#202f3c')
        placements = []
        for holder in pose['holders']:
            field = holder['field'].removesuffix('_装扮')
            if field not in fields:
                continue
            skin = manifest['skinKeys'][fields[field]]
            fr = skin['frames'][0]
            image = Image.open(ROOT / 'launcher/web/assets/dressup' / fr['uri']).convert('RGBA')
            zoom = float(skin['export']['zoom'])
            m = holder['matrix']
            scale = 1.6
            a, b, c, d = (m[k]*scale/zoom for k in ('a', 'b', 'c', 'd'))
            tx = 170 + scale*m['tx'] - a*fr['originX'] - c*fr['originY']
            ty = 302 + scale*m['ty'] - b*fr['originX'] - d*fr['originY']
            det = a*d-b*c
            if abs(det) < 1e-12:
                raise ValueError('Singular authored matrix')
            inverse = (d/det, -c/det, (c*ty-d*tx)/det, -b/det, a/det, (b*tx-a*ty)/det)
            transformed = image.transform(cell.size, Image.Transform.AFFINE, inverse, Image.Resampling.BICUBIC)
            cell.alpha_composite(transformed)
            placements.append(fields[field])
        assert len(placements) == 15
        cd = ImageDraw.Draw(cell)
        cd.text((12, 10), pose['label'].replace('原生空手', '').replace('架势', ''), font=small, fill='#d0dbe4')
        x, y = 20+(index % 3)*360, 84+(index//3)*350
        canvas.alpha_composite(cell, (x, y))
        reports.append({'pose': pose['label'], 'placements': len(placements), 'uniqueSkins': len(set(placements))})
    destination = ROOT / 'tmp/unified61-assets/preview.png'
    canvas.convert('RGB').save(destination)
    (destination.with_suffix('.json')).write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
    print(destination)


if __name__ == '__main__':
    main()
