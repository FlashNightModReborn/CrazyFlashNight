# encoding: utf-8
"""
Pre-flight / post-flight audit for an XFL directory.

  python scripts/tools/xfl/audit.py <xfl_root>

Checks (read-only, exits 0 if clean, 1 if any issue found):
  1. A-class symbols still named "Symbol NNN" (compiler will accept but the
     name is meaningless — fix with rename_a_class.py).
  2. Duplicate symbol names (multiple files claim the same name attribute).
  3. Duplicate linkageIdentifier (AS attachMovie can't distinguish them).
  4. <Include href=...> in DOMDocument.xml pointing at missing files.
  5. <Include href=...> whose itemID resolves to a *different* file
     (DOMDocument out of sync — fix with fix_includes.py).
  6. libraryItemName="..." references that don't resolve to any symbol.
  7. LIBRARY/*.xml files NOT included in DOMDocument.xml (orphans —
     not packed into the SWF; informational, not a failure).

Designed for agent use: positional arg, deterministic stdout, exit code
reflects "issues found".
"""
import os, sys
from html import unescape

# allow `python scripts/tools/xfl/audit.py ...` from project root
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import (
    resolve_xfl_root, index_library, iter_all_xml, read_text,
    LIB_REF_RE, INCLUDE_RE,
)


def main(argv):
    if len(argv) < 2 or argv[1] in ('-h', '--help'):
        print(__doc__)
        return 0

    xfl = resolve_xfl_root(argv[1])
    library = os.path.join(xfl, 'LIBRARY')
    dom_path = os.path.join(xfl, 'DOMDocument.xml')

    print(f'== XFL audit: {xfl} ==')

    idx = index_library(library)
    name_to_file   = idx['name_to_file']
    itemid_to_file = idx['itemid_to_file']

    print(f'  symbols indexed: {len(name_to_file)}')
    print(f'  A-class (linkageExportForAS): {len(idx["lid_to_name"])}')

    issues = 0

    # 1. Still "Symbol NNN"
    print(f'\n[1] A-class still named "Symbol NNN": {len(idx["still_symbol"])}')
    if idx['still_symbol']:
        issues += 1
        for n, l, p in idx['still_symbol'][:20]:
            print(f'    {n}   linkageId={l}')
        if len(idx['still_symbol']) > 20:
            print(f'    ...{len(idx["still_symbol"]) - 20} more')

    # 2. Duplicate names
    print(f'\n[2] Duplicate symbol names: {len(idx["dup_names"])}')
    if idx['dup_names']:
        issues += 1
        for n, a, b in idx['dup_names'][:20]:
            print(f'    {n}: {a} <-> {b}')

    # 3. Duplicate linkageIdentifiers
    print(f'\n[3] Duplicate linkageIdentifier (AS attachMovie ambiguity): {len(idx["dup_lids"])}')
    if idx['dup_lids']:
        issues += 1
        for l, a, b in idx['dup_lids'][:20]:
            print(f'    "{l}":  {a}  <->  {b}')

    # 4 + 5. DOMDocument Include audit
    dom = read_text(dom_path)
    includes = INCLUDE_RE.findall(dom)
    missing, mismatched = [], []
    for href, itemid in includes:
        href_dec = unescape(href)
        full = os.path.join(library, href_dec.replace('/', os.sep))
        if not os.path.exists(full):
            missing.append((href_dec, itemid))
            continue
        if itemid and itemid in itemid_to_file and itemid_to_file[itemid] != href_dec:
            mismatched.append((href_dec, itemid, itemid_to_file[itemid]))

    print(f'\n[4] DOMDocument Includes (total={len(includes)}) with missing file: {len(missing)}')
    if missing:
        issues += 1
        for h, i in missing[:20]:
            print(f'    MISSING href={h}  itemID={i}')

    print(f'\n[5] DOMDocument Include href out-of-sync with itemID: {len(mismatched)}')
    if mismatched:
        issues += 1
        for h, i, e in mismatched[:20]:
            print(f'    MISMATCH href={h}  itemID={i}  actual={e}')

    # 6. libraryItemName cross-check
    unique_libref = set()
    libref_count = 0
    for f in iter_all_xml(xfl):
        for m in LIB_REF_RE.finditer(read_text(f)):
            libref_count += 1
            unique_libref.add(unescape(m.group(1)))
    libref_miss = [r for r in unique_libref if r not in name_to_file]

    print(f'\n[6] libraryItemName references: {libref_count} occurrences, '
          f'{len(unique_libref)} unique, broken={len(libref_miss)}')
    if libref_miss:
        issues += 1
        for r in sorted(libref_miss)[:30]:
            print(f'    NO MATCH: {r}')

    # 7. Orphan files (informational)
    included_set = set(unescape(h) for h, _ in includes)
    orphans = []
    for root, _, files in os.walk(library):
        for fn in files:
            if not fn.endswith('.xml'): continue
            rel = os.path.relpath(os.path.join(root, fn), library).replace(os.sep, '/')
            if rel not in included_set:
                orphans.append(rel)

    print(f'\n[7] LIBRARY files not in DOMDocument.xml (orphans, not packed): {len(orphans)}')
    for o in orphans[:20]:
        print(f'    {o}')
    if len(orphans) > 20:
        print(f'    ...{len(orphans) - 20} more')

    print(f'\n=== {"CLEAN" if issues == 0 else f"{issues} issue category(s)"} ===')
    return 0 if issues == 0 else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
