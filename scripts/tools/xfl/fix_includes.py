# encoding: utf-8
"""
Repair DOMDocument.xml <Include href="..."> after manual file moves in CS6.

  python scripts/tools/xfl/fix_includes.py <xfl_root> [--dry-run]

Strategy: every LIBRARY/*.xml has a stable itemID. We index itemID -> current
file path. For each <Include href="X" itemID="Y"> in DOMDocument.xml where X
does not exist on disk, replace href with the file holding itemID Y.

Exit 0 if nothing to fix or all fixes applied. Non-zero if any broken include
has an itemID not present anywhere in LIBRARY/ (likely a stale entry — manual
look needed).
"""
import os, sys
import xml.sax.saxutils
from html import unescape

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import (
    resolve_xfl_root, iter_library_xml, read_text, write_text,
    ITEMID_RE, INCLUDE_RE,
)


def main(argv):
    if len(argv) < 2 or argv[1] in ('-h', '--help'):
        print(__doc__); return 0
    dry = '--dry-run' in argv

    xfl = resolve_xfl_root(argv[1])
    library = os.path.join(xfl, 'LIBRARY')
    dom_path = os.path.join(xfl, 'DOMDocument.xml')

    # itemID -> rel file
    itemid_to_file = {}
    for path in iter_library_xml(library):
        head = read_text(path, 500)
        m = ITEMID_RE.search(head)
        if m:
            itemid_to_file[m.group(1)] = os.path.relpath(path, library).replace(os.sep, '/')
    print(f'Indexed {len(itemid_to_file)} LIBRARY items by itemID.')

    dom = read_text(dom_path)
    broken = fixed = orphan = 0

    def repl(m):
        nonlocal broken, fixed, orphan
        href_raw, itemid = m.group(1), m.group(2)
        href = unescape(href_raw)
        if os.path.exists(os.path.join(library, href.replace('/', os.sep))):
            return m.group(0)
        broken += 1
        if itemid and itemid in itemid_to_file:
            new_href = xml.sax.saxutils.escape(itemid_to_file[itemid])
            fixed += 1
            return m.group(0).replace(f'href="{href_raw}"', f'href="{new_href}"')
        orphan += 1
        print(f'  ORPHAN: href={href} itemID={itemid} (not found anywhere)')
        return m.group(0)

    new_dom = INCLUDE_RE.sub(repl, dom)

    print(f'Broken: {broken}  Fixed: {fixed}  Orphan: {orphan}')
    if dry:
        print('--dry-run: DOMDocument.xml not written.')
    elif fixed > 0:
        write_text(dom_path, new_dom)
        print('DOMDocument.xml updated.')

    return 1 if orphan else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
