"""Decode the optional actual-Flash RLE capture into viewable death animations."""
from pathlib import Path
import argparse
import hashlib
import json
import re
from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('trace')
    parser.add_argument('output')
    args = parser.parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    frames = {}
    for line in Path(args.trace).read_text(encoding='utf-8-sig').splitlines():
        if line.startswith('[GAMMA_DEATH_BEGIN] '):
            _, key, width, height = line.split()
            assert key not in frames
            frames[key] = {'width': int(width), 'height': int(height), 'rows': {}, 'closed': False}
        elif line.startswith('[GAMMA_DEATH_ROW] '):
            _, key, index, payload = line.split()
            data = bytearray()
            for run in payload.split(','):
                count, color = run.split(':')
                assert len(color) == 8 and re.fullmatch('[0-9a-f]{8}', color)
                data.extend(bytes.fromhex(color) * int(count))
            index = int(index)
            assert index not in frames[key]['rows'] and len(data) == frames[key]['width'] * 4
            frames[key]['rows'][index] = data
        elif line.startswith('[GAMMA_DEATH_END] '):
            _, key = line.split()
            frames[key]['closed'] = True
    assert len(frames) == 76
    for key, frame in frames.items():
        width, height = frame['width'], frame['height']
        assert frame['closed'] and set(frame['rows']) == set(range(height))
        raw = b''.join(frame['rows'][row] for row in range(height))
        image = Image.frombytes('RGBA', (width, height), raw, 'raw', 'ARGB')
        assert image.getbbox() is not None
        image.save(output / (key + '.png'))
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 22)
    small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 14)
    names = ['断腿前扑', '断臂后仰', '屈膝侧倒']
    all_frames, all_delays = [], []
    for branch in range(3):
        numbers = sorted(int(k.rsplit('-f', 1)[1]) for k in frames if k.startswith(f'stabilized-a{branch}-'))
        pictures, delays = [], []
        for index, number in enumerate(numbers):
            canvas = Image.new('RGB', (1280, 382), '#f1ede7')
            draw = ImageDraw.Draw(canvas)
            for left, variant, label in [(0, 'stabilized', '延寿型'), (640, 'full-power', '完全体')]:
                draw.text((left + 30, 12), label + ' · ' + names[branch], font=font, fill='#2d2926')
                image = Image.open(output / f'{variant}-a{branch}-f{number}.png')
                canvas.paste(image, (left, 44), image)
            draw.line((640, 10, 640, 355), fill='#d0c5b9')
            draw.text((30, 359), '实际发布 SWF · Flash 原生帧采样 · 末帧增加停留供查看', font=small, fill='#70665d')
            pictures.append(canvas)
            delay = round((numbers[index+1]-number) * 1000 / 30) if index+1 < len(numbers) else 700
            delays.append(max(300, delay) if index == 0 else delay)
        pictures[0].save(output / f'death-{branch}.gif', save_all=True, append_images=pictures[1:],
                         duration=delays, loop=0, disposal=2, optimize=False)
        pictures[-1].save(output / f'death-{branch}-last.png')
        all_frames.extend(pictures)
        all_delays.extend(delays)
    all_frames[0].save(output / 'death-preview.gif', save_all=True, append_images=all_frames[1:],
                       duration=all_delays, loop=0, disposal=2, optimize=False)
    report = {'rawTraceSha256': hashlib.sha256(Path(args.trace).read_bytes()).hexdigest(),
              'actualFlashFrames': len(frames), 'pairedPreviewFrames': len(all_frames),
              'actions': names, 'previewChanges': 'paired layout, background, labels and endpoint holds only'}
    (output / 'preview-evidence.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
