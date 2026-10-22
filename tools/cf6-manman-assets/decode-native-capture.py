"""Decode the focused Flash test's lossless RGBA row stream into native capture PNGs."""
from pathlib import Path
import argparse
import re
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('trace', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    captures, completed = {}, set()
    for line in args.trace.read_text(encoding='utf-8-sig').splitlines():
        match = re.fullmatch(r'\[MANMAN_IMAGE_BEGIN\] ([a-z-]+) (\d+) (\d+)', line)
        if match:
            name, width, height = match.groups()
            if name in captures:
                raise ValueError('Repeated image: ' + name)
            captures[name] = {'width': int(width), 'height': int(height), 'rows': {}}
            continue
        match = re.fullmatch(r'\[MANMAN_IMAGE_ROW\] ([a-z-]+) (\d+) (.*)', line)
        if match:
            name, y, encoded = match.groups()
            item, row = captures[name], []
            if int(y) in item['rows'] or name in completed:
                raise ValueError('Repeated or late image row')
            for token in encoded.split(','):
                value, count = token.split(':')
                if not re.fullmatch('[0-9a-f]{8}', value) or not 0 < int(count) <= item['width']:
                    raise ValueError('Invalid RGBA run')
                color = int(value, 16)
                row.extend([(color >> 16 & 255, color >> 8 & 255, color & 255, color >> 24 & 255)] * int(count))
            if len(row) != item['width']:
                raise ValueError('Wrong image row width')
            item['rows'][int(y)] = row
        match = re.fullmatch(r'\[MANMAN_IMAGE_END\] ([a-z-]+)', line)
        if match:
            name = match[1]
            if name in completed:
                raise ValueError('Repeated image end')
            completed.add(name)
    legacy = {'stand', 'cleave-impact', 'death-late'}
    current = legacy | {'death-start', 'death-transition'}
    wolf = current | {'wolf-windup', 'wolf-flight', 'wolf-impact', 'wolf-recovery', 'wolf-left'}
    motion = {'wolf-motion-right','wolf-motion-left'}
    if completed not in (legacy, current, wolf, motion) or set(captures) != completed:
        raise ValueError('Expected a complete legacy or fixed-scale stand/impact/death capture set')
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
