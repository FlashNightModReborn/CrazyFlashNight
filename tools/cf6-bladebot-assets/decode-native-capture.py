"""Decode the focused Flash test's lossless RGBA row stream into native capture PNGs."""
from pathlib import Path
import argparse
import re
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('trace', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--beam-only', action='store_true', help='Validate the two supplemental, unclipped beam captures only')
    args = parser.parse_args()
    captures, completed = {}, set()
    def add_row(name, y, encoded):
        item, row = captures[name], []
        if y in item['rows'] or name in completed or not 0 <= y < item['height']:
            raise ValueError('Repeated, late or out-of-range image row')
        for token in encoded.split(','):
            value, count = token.split(':')
            if not re.fullmatch('[0-9a-f]{8}', value) or not 0 < int(count) <= item['width']:
                raise ValueError('Invalid RGBA run')
            color = int(value, 16)
            row.extend([(color >> 16 & 255, color >> 8 & 255, color & 255, color >> 24 & 255)] * int(count))
        if len(row) != item['width']:
            raise ValueError('Wrong image row width')
        item['rows'][y] = row
    for line in args.trace.read_text(encoding='utf-8-sig').splitlines():
        match = re.fullmatch(r'\[BLADEBOT_IMAGE_BEGIN\] ([a-z0-9-]+) (\d+) (\d+)', line)
        if match:
            name, width, height = match.groups()
            if name in captures:
                raise ValueError('Repeated image: ' + name)
            captures[name] = {'width': int(width), 'height': int(height), 'rows': {}}
            continue
        match = re.fullmatch(r'\[BLADEBOT_IMAGE_ROW\] ([a-z0-9-]+) (\d+) (.*)', line)
        if match:
            name, y, encoded = match.groups()
            add_row(name, int(y), encoded)
        match = re.fullmatch(r'\[BLADEBOT_IMAGE_DATA\] ([a-z0-9-]+) (.*)', line)
        if match:
            name, encoded = match.groups()
            if not encoded.endswith(';'):
                raise ValueError('Chunk must contain complete rows')
            for record in encoded[:-1].split(';'):
                y, row = record.split('=', 1)
                add_row(name, int(y), row)
        match = re.fullmatch(r'\[BLADEBOT_IMAGE_END\] ([a-z0-9-]+)', line)
        if match:
            name = match[1]
            if name in completed:
                raise ValueError('Repeated image end')
            completed.add(name)
    expected = {'stand', 'death-start', 'death-fragments', 'death-late', 'cleave-impact', 'sweep-front', 'sweep-back', 'airborne-shadow', 'beam-right', 'beam-left'}
    if args.beam_only: expected = {'beam-right', 'beam-left'}
    if completed != expected or set(captures) != expected:
        raise ValueError('Expected the complete selected fixed-scale Bladebot capture set: ' + str(completed))
    args.output.mkdir(parents=True, exist_ok=True)
    for name, item in captures.items():
        if set(item['rows']) != set(range(item['height'])):
            raise ValueError('Incomplete image: ' + name)
        image = Image.new('RGBA', (item['width'], item['height']))
        image.putdata([pixel for y in range(item['height']) for pixel in item['rows'][y]])
        target = args.output / (name + '.png')
        if target.exists():
            raise ValueError('Preserve the existing capture: ' + str(target))
        image.save(target)
    print('Decoded native Flash captures: ' + ', '.join(sorted(completed)))


if __name__ == '__main__':
    main()
