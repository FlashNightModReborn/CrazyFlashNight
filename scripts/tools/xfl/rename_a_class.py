# encoding: utf-8
"""
Rename A-class symbols still named "Symbol NNN" → their linkageIdentifier.

  python scripts/tools/xfl/rename_a_class.py <xfl_root> [--dry-run]

For each LIBRARY/<folder>/Symbol NNN.xml with linkageExportForAS="true":
  - Compute new_name = <folder>/<linkageIdentifier>
  - Skip if target file already exists (CONFLICT — manual fix in CS6 needed)
  - Update DOMSymbolItem name= and DOMTimeline name= in that file
  - Move the file to its new path
  - Globally replace libraryItemName="<old>" → libraryItemName="<new>"
    in every XML under the XFL root
  - Remove empty directories

Exit 0 on success; non-zero if conflicts skipped or new-name collisions.
"""
import os, re, sys
import xml.sax.saxutils
from html import unescape

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import (
    resolve_xfl_root, iter_library_xml, iter_all_xml, read_text, write_text,
    SYMBOL_NAME_RE, LID_RE, LEAF_RE, SYMBOL_NUM_RE,
)

# DOMSymbolItem name="..." attribute, with the actual encoded string captured
DSI_NAME_RAW_RE = re.compile(r'(<DOMSymbolItem\b[^>]*?\bname=")([^"]+)(")')


def main(argv):
    if len(argv) < 2 or argv[1] in ('-h', '--help'):
        print(__doc__); return 0
    dry = '--dry-run' in argv

    xfl = resolve_xfl_root(argv[1])
    library = os.path.join(xfl, 'LIBRARY')

    # Step 1: find candidates + check conflicts
    mappings = {}   # old_name -> new_name (decoded)
    old_raw  = {}   # old_name -> as-it-appears-in-XML
    paths    = {}   # old_name -> file path
    skipped  = []

    for path in iter_library_xml(library):
        head = read_text(path, 4000)
        m_name = SYMBOL_NAME_RE.search(head)
        m_lid  = LID_RE.search(head)
        if not (m_name and m_lid and LEAF_RE.search(head)):
            continue
        name = unescape(m_name.group(1))
        lid  = unescape(m_lid.group(1))
        leaf = name.rsplit('/', 1)[-1]
        if not SYMBOL_NUM_RE.match(leaf):
            continue
        folder = name.rsplit('/', 1)[0] if '/' in name else ''
        new_name = (folder + '/' + lid) if folder else lid
        new_file = os.path.join(library, new_name.replace('/', os.sep) + '.xml')
        if os.path.exists(new_file) and os.path.abspath(new_file) != os.path.abspath(path):
            skipped.append((name, new_name, path))
            continue
        if new_name in mappings.values():
            print(f'COLLISION: two old names map to {new_name}')
            return 2
        mappings[name] = new_name
        old_raw[name]  = m_name.group(1)
        paths[name]    = path

    print(f'Candidates: {len(mappings)}')
    print(f'Skipped (target file exists — fix in CS6 first): {len(skipped)}')
    for n, t, p in skipped:
        print(f'  SKIP {n}  ->  {t}')
    if dry:
        print('--dry-run: no files modified.')
        return 1 if skipped else 0
    if not mappings:
        return 1 if skipped else 0

    new_raw = {k: xml.sax.saxutils.escape(v) for k, v in mappings.items()}

    # Step 2: rewrite + move each symbol XML
    for old_name, new_name in mappings.items():
        path = paths[old_name]
        old_basename = old_name.rsplit('/', 1)[-1]
        new_basename = new_name.rsplit('/', 1)[-1]
        content = read_text(path)
        # 2a: DOMSymbolItem name
        content = re.sub(
            r'(<DOMSymbolItem\b[^>]*?\bname=")' + re.escape(old_raw[old_name]) + r'(")',
            lambda m: m.group(1) + new_raw[old_name] + m.group(2),
            content, count=1,
        )
        # 2b: DOMTimeline name (basename only)
        content = re.sub(
            r'(<DOMTimeline\b[^>]*?\bname=")' + re.escape(old_basename) + r'(")',
            lambda m: m.group(1) + xml.sax.saxutils.escape(new_basename) + m.group(2),
            content, count=1,
        )
        # 2c: move file
        new_file = os.path.join(library, new_name.replace('/', os.sep) + '.xml')
        os.makedirs(os.path.dirname(new_file), exist_ok=True)
        write_text(new_file, content)
        os.remove(path)
    print(f'Renamed {len(mappings)} files.')

    # Step 3: global libraryItemName replacement across XFL root
    raw_map = {old_raw[k]: new_raw[k] for k in mappings}
    pat = re.compile(
        r'libraryItemName="(' + '|'.join(re.escape(k) for k in raw_map) + r')"'
    )
    repl = lambda m: f'libraryItemName="{raw_map[m.group(1)]}"'
    modified = 0
    for f in iter_all_xml(xfl):
        c = read_text(f)
        nc = pat.sub(repl, c)
        if nc != c:
            write_text(f, nc)
            modified += 1
    print(f'Updated libraryItemName in {modified} files.')

    # Step 4: remove empty dirs
    emptied = 0
    for root, dirs, files in os.walk(library, topdown=False):
        if root != library and not dirs and not files:
            try: os.rmdir(root); emptied += 1
            except OSError: pass
    print(f'Removed {emptied} empty directories.')

    return 1 if skipped else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
