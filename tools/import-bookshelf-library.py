"""Import the supplied comic/novel without re-encoding or rewriting their content.

--check verifies the local reading closure, authored catalog and novel generation.
Import sources stay explicit; no network, runtime saves or gameplay data are used.
"""
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/books/sources'
OUTPUT = ROOT / 'launcher/web/assets/bookshelf'
ORIGINAL = ROOT / 'flashswf/originals/crazy-flasher-1.swf'
ORIGINAL_HASH = 'aa1cb17a60b9efaffe8e969bb33d77342657728af0203f8bb0b5fcf07b145a00'
NOVEL_FILES = ['SK20130906144634339.html.txt', 'SK20130906145311471.html.txt',
               'SK20130906145723846.html.txt', 'SK20130906145936755.html.txt']


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n').encode('utf-8')


def safe_path(name):
    return (isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9_./-]+', name)
            and not PurePosixPath(name).is_absolute()
            and all(x not in ('', '.', '..') for x in name.split('/')))


def novel():
    chapters, sources = [], []
    for name in NOVEL_FILES:
        path = SOURCE / 'sail-twins' / name
        raw = path.read_bytes()
        text = raw.decode('utf-8-sig')
        url = re.search(r'^SOURCE: (https://andylaw\.games/[^\n]+)', text).group(1).strip()
        headings = list(re.finditer(r'^第[一二三四五六七八九十]+章[^\n]*', text, re.M))
        for i, match in enumerate(headings):
            end = headings[i + 1].start() if i + 1 < len(headings) else len(text)
            paragraphs = [s.strip() for s in text[match.end():end].splitlines()
                          if s.strip() and not re.fullmatch(r'[=\-]{5,}', s.strip())]
            if not paragraphs:
                raise ValueError('empty novel chapter')
            chapters.append({'id': 'chapter-' + str(len(chapters) + 1),
                             'title': match.group().strip(), 'paragraphs': paragraphs, 'source': url})
        sources.append({'file': path.relative_to(ROOT).as_posix(), 'sha256': digest(raw), 'url': url})
    if len(chapters) != 28:
        raise ValueError('expected all 28 novel chapters')
    return {'schema': 'bookshelf-novel.v1', 'title': '风帆双子', 'author': 'Forever爱牛',
            'sources': sources, 'chapters': chapters}


def comic_index(source):
    if source.get('format') != 'comic-mixed-storage-experiment-v1' or source.get('page_count') != 1227:
        raise ValueError('unexpected comic source')
    chapters, last = [], None
    for n, page in enumerate(source['pages'], 1):
        if page['page'] != n or not safe_path(page['file']) or page['file'] not in source['files']:
            raise ValueError('invalid comic page identity')
        if page['storage'] not in ('image', 'video-frame') or min(page['width'], page['height']) < 1:
            raise ValueError('invalid comic page')
        parts = page['source'].replace('\\', '/').split('/')
        label = ' / '.join(parts[1:-1]).replace('漫画-', '').replace('官网12集全', '').replace('第一季-', '第一季')
        if label != last:
            chapters.append({'title': label, 'page': n})
            last = label
    return {'schema': 'bookshelf-comic.v1', 'title': '守护之力', 'chapters': chapters,
            'pages': [{k: p[k] for k in ('page', 'width', 'height', 'storage', 'file', 'frame', 'time_seconds', 'crop') if k in p}
                      for p in source['pages']]}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--comic-bundle', type=Path)
    parser.add_argument('--novel-texts', type=Path)
    parser.add_argument('--original-swf', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check and (args.comic_bundle or args.novel_texts or args.original_swf):
        parser.error('--check does not import')
    if args.original_swf:
        data = args.original_swf.read_bytes()
        if digest(data) != ORIGINAL_HASH or len(data) != 935674:
            raise ValueError('expected the supplied, unchanged Crazy Flasher 1 movie')
        ORIGINAL.parent.mkdir(parents=True, exist_ok=True)
        ORIGINAL.write_bytes(data)
        (SOURCE / 'crazy-flasher-1-import.json').write_bytes(encoded({
            'sourceFile': args.original_swf.name, 'file': ORIGINAL.relative_to(ROOT).as_posix(),
            'sha256': ORIGINAL_HASH, 'bytes': len(data), 'encoding': 'original SWF 5 AVM1; copied unchanged'}))
    original_import = json.loads((SOURCE / 'crazy-flasher-1-import.json').read_text(encoding='utf-8'))
    original_data = ORIGINAL.read_bytes()
    if (original_import['file'] != ORIGINAL.relative_to(ROOT).as_posix()
            or original_import['sha256'] != ORIGINAL_HASH or digest(original_data) != ORIGINAL_HASH
            or original_import['bytes'] != len(original_data)):
        raise ValueError('original movie integrity mismatch')
    if args.novel_texts:
        for name in NOVEL_FILES:
            dest = SOURCE / 'sail-twins' / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes((args.novel_texts / name).read_bytes())
    if args.comic_bundle:
        with zipfile.ZipFile(args.comic_bundle) as archive:
            source = json.loads(archive.read('index.json'))
            comic_index(source)
            for name, expected in source['files'].items():
                if not safe_path(name):
                    raise ValueError('unsafe archive member')
                data = archive.read(name)
                if len(data) != expected['bytes'] or digest(data) != expected['sha256']:
                    raise ValueError('comic integrity mismatch: ' + name)
                dest = OUTPUT / 'guardian' / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
            SOURCE.mkdir(parents=True, exist_ok=True)
            (SOURCE / 'guardian-index.json').write_bytes(encoded(source))
            (SOURCE / 'guardian-import.json').write_bytes(encoded({
                'sourceArchive': args.comic_bundle.name, 'sha256': digest(args.comic_bundle.read_bytes()),
                'bytes': args.comic_bundle.stat().st_size, 'encoding': 'original AVIF/JPEG and AV1 frames; copied unchanged'}))
    source = json.loads((SOURCE / 'guardian-index.json').read_text(encoding='utf-8'))
    artifacts = {'catalog.json': encoded(json.loads((ROOT / 'data/books/catalog.json').read_text(encoding='utf-8-sig'))),
                 'guardian/index.json': encoded(comic_index(source)), 'sail-twins/index.json': encoded(novel())}
    files = {}
    for name, expected in source['files'].items():
        if not safe_path(name):
            raise ValueError('unsafe comic path')
        data = (OUTPUT / 'guardian' / name).read_bytes()
        if len(data) != expected['bytes'] or digest(data) != expected['sha256']:
            raise ValueError('comic asset differs: ' + name)
        files['guardian/' + name] = expected
    for name, data in artifacts.items():
        target = OUTPUT / name
        if args.check:
            if not target.is_file() or target.read_bytes() != data:
                raise ValueError('generated reading data differs: ' + name)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        files[name] = {'bytes': len(data), 'sha256': digest(data)}
    manifest = encoded({'schema': 'bookshelf-library.v1', 'files': files,
                        'totalBytes': sum(x['bytes'] for x in files.values()),
                        'comicImport': json.loads((SOURCE / 'guardian-import.json').read_text(encoding='utf-8')),
                        'originalMovie': original_import})
    path = OUTPUT / 'library-manifest.json'
    if args.check:
        if path.read_bytes() != manifest:
            raise ValueError('library manifest differs')
    else:
        path.write_bytes(manifest)
    actual = {p.relative_to(OUTPUT).as_posix() for folder in ['guardian', 'sail-twins']
              for p in (OUTPUT / folder).rglob('*') if p.is_file()}
    if actual != set(files) - {'catalog.json'}:
        raise ValueError('unexpected files in reading closure')
    print(f'bookshelf library: 1227 comic pages, 28 chapters, {len(files)} files, '
          f'{sum(x["bytes"] for x in files.values())} bytes; ' + ('verified' if args.check else 'imported'))


if __name__ == '__main__':
    main()
