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

sys.stdout.reconfigure(encoding='utf-8')

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(TOOL_DIR))
BASE = os.path.join(PROJECT_ROOT, 'flashswf')
OUTPUT_XML = os.path.join(PROJECT_ROOT, 'data', 'items', 'asset_source_map.xml')
LINKAGE_RE = re.compile(r'linkageExportForAS="true".*?linkageIdentifier="([^"]+)"')

results = {}       # linkageId -> set(swf_rel_paths)  (deduplicated per source)
source_counts = {}  # swf_rel -> count
INCLUDE_ALL = '--include-all' in sys.argv
XML_ONLY = '--xml-only' in sys.argv

# Directories excluded by default (archive/reference, never part of production builds).
# Use --include-all to scan them as well.
SKIP_DIRS = ('/unused/', '/renew/')


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


def scan_xfl(xfl_dir):
    lib_dir = os.path.join(xfl_dir, 'LIBRARY')
    if not os.path.isdir(lib_dir):
        return
    swf_rel = rel_swf(xfl_dir) + '.swf'
    if should_skip(swf_rel):
        return
    seen_in_source = set()
    for xml_file in glob.glob(os.path.join(lib_dir, '**', '*.xml'), recursive=True):
        with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read(2000)
        m = LINKAGE_RE.search(content)
        if m:
            lid = m.group(1)
            results.setdefault(lid, set()).add(swf_rel)
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

        if fname.startswith('LIBRARY/') and fname.endswith('.xml'):
            if comp_method == 8:  # deflate
                try:
                    content = zlib.decompress(file_data, -15).decode('utf-8')
                except Exception:
                    content = ''
            elif comp_method == 0:  # store
                content = file_data.decode('utf-8', errors='replace')
            else:
                content = ''

            m = LINKAGE_RE.search(content)
            if m:
                lid = m.group(1)
                results.setdefault(lid, set()).add(swf_rel)
                seen_in_source.add(lid)

        offset = next_offset

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


def write_xml():
    """Write asset_source_map.xml with all linkage → source mappings."""
    os.makedirs(os.path.dirname(OUTPUT_XML), exist_ok=True)

    lines = ['<?xml version="1.0" encoding="UTF-8"?>']
    lines.append('<assetSourceMap>')
    lines.append('  <!-- Auto-generated by tools/linkage_scanner/scan_linkage.py -->')
    lines.append('  <!-- DO NOT EDIT MANUALLY -->')

    # Separate conflicts for easy visual identification
    conflicts = {}
    clean = {}
    for lid in sorted(results.keys()):
        sources = sorted(results[lid])
        if len(sources) > 1:
            conflicts[lid] = sources
        else:
            clean[lid] = sources[0]

    # Write clean entries
    lines.append('')
    lines.append(f'  <!-- {len(clean)} unique assets -->')
    for lid, src in sorted(clean.items()):
        lines.append(f'  <asset id="{xml_safe(lid)}" swf="{xml_safe(src)}" />')

    # Write conflicts in a separate section
    if conflicts:
        lines.append('')
        lines.append(f'  <!-- {len(conflicts)} CONFLICTS: same ID in multiple sources -->')
        for lid, sources in sorted(conflicts.items()):
            lines.append(f'  <conflict id="{xml_safe(lid)}">')
            for s in sources:
                lines.append(f'    <source swf="{xml_safe(s)}" />')
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

    # Console report
    total_unique = len(results)
    conflicts = {k: v for k, v in results.items() if len(v) > 1}

    print(f'\n=== Total: {total_unique} unique linkageIdentifiers from {len(source_counts)} sources ===')
    if not INCLUDE_ALL:
        print(f'  (skipped: {", ".join(SKIP_DIRS)}  — use --include-all to include)')
    print()

    print(f'=== CONFLICTS (same ID in multiple SWFs): {len(conflicts)} ===')
    for lid, sources in sorted(conflicts.items()):
        print(f'  {lid}:')
        for s in sorted(sources):
            print(f'    - {s}')

    print()
    print('=== Exports per source ===')
    for src, cnt in sorted(source_counts.items(), key=lambda x: -x[1]):
        print(f'  {cnt:4d}  {src}')


if __name__ == '__main__':
    main()
