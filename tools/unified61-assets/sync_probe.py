"""Keep focused Flash probes identical to the production mode-switch function."""
from pathlib import Path
import argparse
import hashlib

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'
TEMPLATES = [ROOT / f'scripts/test-runners/{domain}/TestLoader.as.template'
             for domain in ('unified61-assets', 'unified61-final')]
SIGNATURE = '_root.主角函数.攻击模式切换 = function(模式) {'


def function_span(text):
    if text.count(SIGNATURE) != 1:
        raise ValueError('Expected exactly one production mode-switch function')
    start = text.index(SIGNATURE)
    cursor = start + len(SIGNATURE)
    depth, state = 1, None
    while cursor < len(text):
        char = text[cursor]
        pair = text[cursor:cursor + 2]
        if state == 'line':
            if char == '\n':
                state = None
        elif state == 'block':
            if pair == '*/':
                state = None
                cursor += 1
        elif state in ('"', "'"):
            if char == '\\':
                cursor += 1
            elif char == state:
                state = None
        elif pair == '//':
            state = 'line'
            cursor += 1
        elif pair == '/*':
            state = 'block'
            cursor += 1
        elif char in ('"', "'"):
            state = char
        elif char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                end = cursor + 1
                if text[end:end + 1] != ';':
                    raise ValueError('Expected function assignment terminator')
                return start, end + 1
        cursor += 1
    raise ValueError('Unterminated production function')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--write', action='store_true')
    args = parser.parse_args()
    source = SOURCE.read_text(encoding='utf-8-sig')
    start, end = function_span(source)
    expected = source[start:end]
    for path in TEMPLATES:
        raw = path.read_bytes()
        text = raw.decode('utf-8-sig').replace('\r\n', '\n')
        start, end = function_span(text)
        if text[start:end] != expected:
            if not args.write:
                raise ValueError(f'Probe differs from production: {path.relative_to(ROOT)}; run --write then recompile')
            newline = '\r\n' if b'\r\n' in raw else '\n'
            updated = (text[:start] + expected + text[end:]).replace('\n', newline)
            bom = b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b''
            path.write_bytes(bom + updated.encode('utf-8'))
    digest = hashlib.sha256(expected.encode('utf-8')).hexdigest()
    print(f'Production mode-switch projection: 2/2 identical; normalized SHA256 {digest}')


if __name__ == '__main__':
    main()
