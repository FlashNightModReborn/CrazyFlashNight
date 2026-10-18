"""Decode the focused Flash test's lossless RGBA row stream into native capture PNGs."""
from pathlib import Path
import argparse
import re
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('trace', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--fragment', action='store_true')
    parser.add_argument('--partial', action='store_true', help='Decode only completed frames for an in-progress preview; never a complete-set check')
    args = parser.parse_args()
    captures, completed = {}, set()
    source = args.trace.read_text(encoding='utf-8-sig')
    lines = source.splitlines()
    if args.partial and source and not source.endswith('\n'):
        lines = lines[:-1]
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
    for line in lines:
        match = re.fullmatch(r'\[HEADBOT_IMAGE_BEGIN\] ([a-z0-9-]+) (\d+) (\d+)', line)
        if match:
            name, width, height = match.groups()
            if name in captures:
                raise ValueError('Repeated image: ' + name)
            captures[name] = {'width': int(width), 'height': int(height), 'rows': {}}
            continue
        match = re.fullmatch(r'\[HEADBOT_IMAGE_ROW\] ([a-z0-9-]+) (\d+) (.*)', line)
        if match:
            name, y, encoded = match.groups()
            add_row(name, int(y), encoded)
        match = re.fullmatch(r'\[HEADBOT_IMAGE_RECT\] ([a-z0-9-]+) (\d+) (\d+) (\d+) (\d+)', line)
        if match:
            name, *coordinates = match.groups()
            item = captures[name]
            x, y, width, height = map(int, coordinates)
            if 'rect' in item or item['rows'] or name in completed or x+width > item['width'] or y+height > item['height']:
                raise ValueError('Invalid native image rectangle')
            item['rect'] = (x, y, width, height)
        match = re.fullmatch(r'\[HEADBOT_IMAGE_DATA\] ([a-z0-9-]+) (.*)', line)
        if match:
            name, encoded = match.groups()
            if 'rect' not in captures[name] or not encoded.endswith(';'):
                raise ValueError('Chunk must follow its rectangle and contain complete rows')
            for record in encoded[:-1].split(';'):
                y, row = record.split('=', 1)
                add_row(name, int(y), row)
        match = re.fullmatch(r'\[HEADBOT_IMAGE_END\] ([a-z0-9-]+)', line)
        if match:
            name = match[1]
            if name in completed:
                raise ValueError('Repeated image end')
            completed.add(name)
    expected = {'beam-29','beam-30'}
    if args.fragment: expected = {'death-31'}
    if args.partial:
        captures = {k:v for k,v in captures.items() if k in completed}
        expected = completed
    if completed != expected or set(captures) != expected:
        raise ValueError('Expected the complete selected fixed-scale Headbot capture set: ' + str(completed))
    args.output.mkdir(parents=True, exist_ok=True)
    for name, item in captures.items():
        x, top, width, height = item.get('rect', (0, 0, item['width'], item['height']))
        if set(item['rows']) != set(range(top, top+height)):
            raise ValueError('Incomplete image: ' + name)
        for y, row in item['rows'].items():
            if any(pixel != (0,0,0,0) for pixel in row[:x]+row[x+width:]):
                raise ValueError('Nontransparent pixels outside declared native rectangle')
        image = Image.new('RGBA', (item['width'], item['height']))
        empty = [(0,0,0,0)] * item['width']
        image.putdata([pixel for y in range(item['height']) for pixel in item['rows'].get(y, empty)])
        target = args.output / (name + '.png')
        if target.exists():
            raise ValueError('Preserve the existing capture: ' + str(target))
        image.save(target)
    print('Decoded native Flash captures: ' + ', '.join(sorted(completed)))


if __name__ == '__main__':
    main()
