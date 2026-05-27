# encoding: utf-8
"""
Scan all XFL directories and FLA files under flashswf/ for linkage exports.
Produces:
  1. data/items/asset_source_map.xml  — linkageId → source SWF mapping
  2. Console report with conflict detection

Usage:
  python tools/linkage_scanner/scan_linkage.py [--include-all] [--xml-only]
"""
import struct, zlib, re, os, sys, glob, xml.sax.saxutils
from html import unescape as html_unescape

sys.stdout.reconfigure(encoding='utf-8')

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(TOOL_DIR))
BASE = os.path.join(PROJECT_ROOT, 'flashswf')
OUTPUT_XML = os.path.join(PROJECT_ROOT, 'data', 'items', 'asset_source_map.xml')
# Captures: group(1)=symbol name, group(2)=linkageIdentifier
# DOMSymbolItem always has name as the first attribute.
SYMBOL_RE = re.compile(
    r'<DOMSymbolItem\b[^>]*?\bname="([^"]+)"[^>]*?'
    r'linkageExportForAS="true"[^>]*?'
    r'linkageIdentifier="([^"]+)"'
)
# Captures: group(1)=href (relative to LIBRARY/, forward-slash separated)
# Used to determine which LIBRARY/*.xml are registered in the .fla's manifest;
# any XML present in LIBRARY/ but not referenced here is an orphan
# (Flash IDE library panel won't show it, but SWF compile still picks up linkage).
INCLUDE_RE = re.compile(r'<Include\s+[^/]*?\bhref="([^"]+)"')

results = {}       # linkageId -> set((swf_rel, symbol_name, is_orphan))
source_counts = {}  # swf_rel -> count
INCLUDE_ALL = '--include-all' in sys.argv
XML_ONLY = '--xml-only' in sys.argv

# Directories excluded by default (archive/reference, never part of production builds).
# Use --include-all to scan them as well.
SKIP_DIRS = ('/unused/', '/renew/')


def xml_attr_unescape(s):
    """Decode XML attribute entity references (e.g. &amp; → &, &lt; → <)."""
    return html_unescape(s)


def rel_swf(path):
    """Convert source path to relative .swf path from project root."""
    r = os.path.relpath(path, PROJECT_ROOT).replace(os.sep, '/')
    return r


def should_skip(swf_rel):
    """Skip archive/reference directories unless --include-all is set."""
    if INCLUDE_ALL:
        return False
    for d in SKIP_DIRS:
        if d in swf_rel:
            return True
    return False


def parse_include_set(dom_doc_content):
    """Extract the set of href values from DOMDocument.xml's <Include> manifest.

    Hrefs are stored as forward-slash paths relative to LIBRARY/, e.g.
    '1.枪械相关/长枪/图标-Sniper.xml'.  Any XML present in LIBRARY/ but absent
    from this set is an orphan (Flash IDE won't display it in the library
    panel; .swf compile may or may not pick it up).
    """
    hrefs = set()
    for m in INCLUDE_RE.finditer(dom_doc_content):
        hrefs.add(xml_attr_unescape(m.group(1)).replace('\\', '/'))
    return hrefs


def scan_xfl(xfl_dir):
    lib_dir = os.path.join(xfl_dir, 'LIBRARY')
    if not os.path.isdir(lib_dir):
        return
    swf_rel = rel_swf(xfl_dir) + '.swf'
    if should_skip(swf_rel):
        return

    # Build Include manifest (orphan filter) from DOMDocument.xml
    dom_doc = os.path.join(xfl_dir, 'DOMDocument.xml')
    if os.path.isfile(dom_doc):
        with open(dom_doc, 'r', encoding='utf-8', errors='replace') as f:
            include_set = parse_include_set(f.read())
    else:
        include_set = None  # cannot determine; treat all as non-orphan

    seen_in_source = set()
    for xml_file in glob.glob(os.path.join(lib_dir, '**', '*.xml'), recursive=True):
        with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read(2000)
        m = SYMBOL_RE.search(content)
        if m:
            sym_name = xml_attr_unescape(m.group(1))
            lid = xml_attr_unescape(m.group(2))
            rel_href = os.path.relpath(xml_file, lib_dir).replace(os.sep, '/')
            is_orphan = (include_set is not None and rel_href not in include_set)
            results.setdefault(lid, set()).add((swf_rel, sym_name, is_orphan))
            seen_in_source.add(lid)
    if seen_in_source:
        source_counts[swf_rel] = len(seen_in_source)


def _find_data_descriptor(data, offset):
    """Find comp_size and uncomp_size from a data descriptor after file data.

    When the general-purpose bit flag bit 3 is set, the local header's
    comp_size/uncomp_size are 0; the real values follow the file data in a
    data descriptor.  We scan forward for either:
      - PK\\x07\\x08 + crc32 + comp_size + uncomp_size  (with signature, 16 bytes)
      - or the next PK\\x03\\x04 / PK\\x01\\x02 and back-calculate.
    Returns (comp_size, descriptor_len) or None on failure.
    """
    # Scan for the optional data descriptor signature PK\x07\x08
    sig = b'PK\x07\x08'
    pos = data.find(sig, offset)
    if pos != -1 and pos - offset < 0x10000000:  # sanity bound
        comp_size = pos - offset
        return comp_size, comp_size + 16  # 4 sig + 4 crc + 4 comp + 4 uncomp

    # Fallback: scan for next local header or central directory
    search_pos = offset
    while search_pos < len(data) - 4:
        pk = data.find(b'PK', search_pos)
        if pk < 0:
            break
        marker = data[pk:pk + 4]
        if marker == b'PK\x03\x04' or marker == b'PK\x01\x02':
            comp_size = pk - offset
            return comp_size, comp_size  # no descriptor to skip past data
        search_pos = pk + 1

    return None


def scan_fla(fla_path):
    swf_rel = rel_swf(fla_path)
    swf_rel = swf_rel[:-4] + '.swf'  # .fla -> .swf
    if should_skip(swf_rel):
        return

    # Skip if XFL directory exists (already scanned)
    xfl_dir = fla_path[:-4]
    if os.path.exists(os.path.join(xfl_dir, 'DOMDocument.xml')):
        return

    with open(fla_path, 'rb') as f:
        data = f.read()

    seen_in_source = set()
    # Two-pass via single scan + buffering: zip member order isn't guaranteed,
    # so we collect LIBRARY entries first, parse DOMDocument.xml for the
    # Include manifest, then mark orphans.
    pending = []   # list of (sym_name, lid, rel_href_under_LIBRARY)
    include_set = None  # populated when DOMDocument.xml is encountered
    offset = 0
    while offset < len(data) - 4:
        if data[offset:offset + 4] != b'PK\x03\x04':
            # Try to find next local header (skip central directory etc.)
            next_pk = data.find(b'PK\x03\x04', offset + 1)
            if next_pk < 0:
                break
            offset = next_pk
            continue

        flags = struct.unpack_from('<H', data, offset + 6)[0]
        comp_method = struct.unpack_from('<H', data, offset + 8)[0]
        comp_size = struct.unpack_from('<I', data, offset + 18)[0]
        fname_len = struct.unpack_from('<H', data, offset + 26)[0]
        extra_len = struct.unpack_from('<H', data, offset + 28)[0]
        fname_raw = data[offset + 30:offset + 30 + fname_len]
        file_data_start = offset + 30 + fname_len + extra_len
        has_descriptor = bool(flags & 0x08)

        # When bit 3 is set, comp_size in local header is 0 — find real size
        if has_descriptor or comp_size == 0:
            dd = _find_data_descriptor(data, file_data_start)
            if dd is None:
                break
            comp_size, skip_total = dd
            file_data = data[file_data_start:file_data_start + comp_size]
            next_offset = file_data_start + skip_total
        else:
            file_data = data[file_data_start:file_data_start + comp_size]
            next_offset = file_data_start + comp_size

        try:
            fname = fname_raw.decode('utf-8')
        except UnicodeDecodeError:
            offset = next_offset
            continue

        # Decompress on demand; both DOMDocument.xml (root) and LIBRARY/*.xml are needed
        is_dom_doc = (fname == 'DOMDocument.xml')
        is_library_xml = (fname.startswith('LIBRARY/') and fname.endswith('.xml'))

        if is_dom_doc or is_library_xml:
            if comp_method == 8:  # deflate
                try:
                    content = zlib.decompress(file_data, -15).decode('utf-8')
                except Exception:
                    content = ''
            elif comp_method == 0:  # store
                content = file_data.decode('utf-8', errors='replace')
            else:
                content = ''
        else:
            content = None

        if is_dom_doc and content:
            include_set = parse_include_set(content)
        elif is_library_xml and content:
            m = SYMBOL_RE.search(content)
            if m:
                sym_name = xml_attr_unescape(m.group(1))
                lid = xml_attr_unescape(m.group(2))
                rel_href = fname[len('LIBRARY/'):]  # path under LIBRARY/, forward-slash
                pending.append((sym_name, lid, rel_href))

        offset = next_offset

    # Commit pending entries with orphan classification
    for sym_name, lid, rel_href in pending:
        is_orphan = (include_set is not None and rel_href not in include_set)
        results.setdefault(lid, set()).add((swf_rel, sym_name, is_orphan))
        seen_in_source.add(lid)

    if seen_in_source:
        source_counts[swf_rel] = len(seen_in_source)


# XML 1.0 legal characters: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
_XML_ILLEGAL_RE = re.compile(
    '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x84\x86-\x9f\ud800-\udfff\ufdd0-\ufddf\ufffe\uffff]'
)


def xml_safe(s):
    """Escape for XML attribute and strip XML 1.0 illegal characters."""
    s = _XML_ILLEGAL_RE.sub('', s)
    return xml.sax.saxutils.escape(s)


def classify_results():
    """Classify all linkageIds into categories.

    Entries are (swf, sym, is_orphan).  Orphans are XMLs in the .fla LIBRARY/
    but not referenced by DOMDocument.xml's <Include> manifest — i.e. invisible
    in Flash IDE library panel, dead linkage left over from element deletion.

    Returns (unique, duplicates, conflicts, orphans):
      unique:     lid -> (swf, sym, is_orphan)        — single live entry
      duplicates: lid -> [(swf, sym, is_orphan), ...] — multiple entries, same SWF
      conflicts:  lid -> [(swf, sym, is_orphan), ...] — entries from 2+ distinct SWFs
                                                       (excluding any orphan-only
                                                        sources from conflict count)
      orphans:    lid -> [(swf, sym, True), ...]      — entries flagged as orphan
                                                       (subset for separate reporting)
    """
    unique = {}
    duplicates = {}
    conflicts = {}
    orphans = {}
    for lid in sorted(results.keys()):
        entries = sorted(results[lid])
        # Collect orphan entries for separate reporting (regardless of category)
        orphan_entries = [e for e in entries if e[2]]
        if orphan_entries:
            orphans[lid] = orphan_entries

        # "Live" entries = non-orphan; conflicts are determined by live SWF count
        live_entries = [e for e in entries if not e[2]]
        if len(entries) == 1:
            unique[lid] = entries[0]
        else:
            live_swfs = set(swf for swf, _, orph in entries if not orph)
            if len(live_swfs) > 1:
                conflicts[lid] = entries
            else:
                # All from one live SWF (rest are orphans) OR all-orphan group
                duplicates[lid] = entries
    return unique, duplicates, conflicts, orphans


def _src_attr(swf, sym, lid, is_orphan):
    """Build attribute string for one source entry."""
    attr = f'swf="{xml_safe(swf)}"'
    if sym != lid:
        attr += f' symbolName="{xml_safe(sym)}"'
    if is_orphan:
        attr += ' orphan="true"'
    return attr


def write_xml():
    """Write asset_source_map.xml with all linkage → source mappings."""
    os.makedirs(os.path.dirname(OUTPUT_XML), exist_ok=True)
    unique, duplicates, conflicts, orphans = classify_results()

    lines = ['<?xml version="1.0" encoding="UTF-8"?>']
    lines.append('<assetSourceMap>')
    lines.append('  <!-- Auto-generated by tools/linkage_scanner/scan_linkage.py -->')
    lines.append('  <!-- DO NOT EDIT MANUALLY -->')
    lines.append('  <!-- orphan="true" = XML present in LIBRARY/ but not in DOMDocument <Include>; ')
    lines.append('       Flash IDE library panel cannot see it but .swf compile may still expose linkage -->')

    # Write unique entries
    lines.append('')
    lines.append(f'  <!-- {len(unique)} unique assets -->')
    for lid, (src, sym, orph) in sorted(unique.items()):
        attr = f'id="{xml_safe(lid)}" ' + _src_attr(src, sym, lid, orph)
        lines.append(f'  <asset {attr} />')

    # Write same-SWF duplicates (multiple symbolNames for one linkageId within one SWF)
    if duplicates:
        lines.append('')
        lines.append(f'  <!-- {len(duplicates)} DUPLICATES: same ID, same SWF, multiple symbolNames -->')
        for lid, entries in sorted(duplicates.items()):
            lines.append(f'  <duplicate id="{xml_safe(lid)}">')
            for swf, sym, orph in entries:
                lines.append(f'    <source {_src_attr(swf, sym, lid, orph)} />')
            lines.append('  </duplicate>')

    # Write cross-SWF conflicts
    if conflicts:
        lines.append('')
        lines.append(f'  <!-- {len(conflicts)} CONFLICTS: same ID in multiple SWFs (live sources >= 2) -->')
        for lid, entries in sorted(conflicts.items()):
            lines.append(f'  <conflict id="{xml_safe(lid)}">')
            for swf, sym, orph in entries:
                lines.append(f'    <source {_src_attr(swf, sym, lid, orph)} />')
            lines.append('  </conflict>')

    lines.append('</assetSourceMap>')
    lines.append('')

    with open(OUTPUT_XML, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f'Written: {os.path.relpath(OUTPUT_XML, PROJECT_ROOT)}')


def main():
    # 1. Scan all XFL directories
    for dom in glob.glob(os.path.join(BASE, '**', 'DOMDocument.xml'), recursive=True):
        scan_xfl(os.path.dirname(dom))

    # 2. Scan all FLA files (skip those with existing XFL)
    for fla in glob.glob(os.path.join(BASE, '**', '*.fla'), recursive=True):
        scan_fla(fla)

    # Write XML output
    write_xml()

    if XML_ONLY:
        return

    # Console report — reuse the same classification as XML
    unique, duplicates, conflicts, orphans = classify_results()

    print(f'\n=== Total: {len(results)} unique linkageIdentifiers from {len(source_counts)} sources ===')
    print(f'  unique: {len(unique)}, same-SWF duplicates: {len(duplicates)}, '
          f'cross-SWF conflicts: {len(conflicts)}, orphans: {len(orphans)}')
    if not INCLUDE_ALL:
        print(f'  (skipped: {", ".join(SKIP_DIRS)}  — use --include-all to include)')
    print()

    def fmt_entry(swf, sym, orph, lid):
        suffix = f'  (symbolName: {sym})' if sym != lid else ''
        if orph:
            suffix += '  [ORPHAN: not in DOMDocument <Include>]'
        return f'    - {swf}{suffix}'

    if duplicates:
        print(f'=== DUPLICATES (same ID, same SWF, multiple symbolNames): {len(duplicates)} ===')
        for lid, entries in sorted(duplicates.items()):
            print(f'  {lid}:')
            for swf, sym, orph in entries:
                print(fmt_entry(swf, sym, orph, lid))
        print()

    if orphans:
        print(f'=== ORPHANS (linkage exported from XML invisible to Flash IDE): {len(orphans)} ===')
        print(f'  These are dead .fla zip residues — IDE library panel cannot delete them.')
        print(f'  Use tools/linkage_scanner/strip_orphan_linkage.py to clean.')
        for lid, entries in sorted(orphans.items()):
            print(f'  {lid}:')
            for swf, sym, orph in entries:
                print(fmt_entry(swf, sym, orph, lid))
        print()

    print(f'=== CONFLICTS (same ID in multiple SWFs, live sources >= 2): {len(conflicts)} ===')
    for lid, entries in sorted(conflicts.items()):
        print(f'  {lid}:')
        for swf, sym, orph in entries:
            print(fmt_entry(swf, sym, orph, lid))

    print()
    print('=== Exports per source ===')
    for src, cnt in sorted(source_counts.items(), key=lambda x: -x[1]):
        print(f'  {cnt:4d}  {src}')


if __name__ == '__main__':
    main()
