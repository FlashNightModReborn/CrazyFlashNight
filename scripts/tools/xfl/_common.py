# encoding: utf-8
"""Shared XFL parsing helpers for the audit / rename / fix-includes tools."""
import os, re, sys, glob
from html import unescape

SYMBOL_NAME_RE = re.compile(r'<DOMSymbolItem\b[^>]*?\bname="([^"]+)"')
LID_RE         = re.compile(r'\blinkageIdentifier="([^"]+)"')
LEAF_RE        = re.compile(r'\blinkageExportForAS="true"')
ITEMID_RE      = re.compile(r'<DOMSymbolItem\b[^>]*?\bitemID="([^"]+)"')
LIB_REF_RE     = re.compile(r'libraryItemName="([^"]+)"')
INCLUDE_RE     = re.compile(r'<Include\s+href="([^"]+)"(?:\s+itemID="([^"]+)")?')
SYMBOL_NUM_RE  = re.compile(r'^Symbol\s+\d+$')


def resolve_xfl_root(arg):
    """Accept either `flashswf/arts/things` (the XFL dir itself) or anything
    ending in DOMDocument.xml / LIBRARY/. Always return the XFL dir."""
    if not arg:
        sys.exit('error: missing XFL root argument. usage: <tool> <xfl_root>')
    p = os.path.normpath(arg)
    if p.endswith('DOMDocument.xml'):
        p = os.path.dirname(p)
    elif os.path.basename(p) == 'LIBRARY':
        p = os.path.dirname(p)
    if not os.path.isdir(os.path.join(p, 'LIBRARY')):
        sys.exit(f'error: {p} does not look like an XFL root (no LIBRARY/ inside)')
    if not os.path.isfile(os.path.join(p, 'DOMDocument.xml')):
        sys.exit(f'error: {p} has no DOMDocument.xml')
    return p


def iter_library_xml(library_dir):
    """Yield every .xml under LIBRARY/, sorted for stable output."""
    for root, _, files in os.walk(library_dir):
        for fname in sorted(files):
            if fname.endswith('.xml'):
                yield os.path.join(root, fname)


def iter_all_xml(xfl_root):
    """Yield every .xml under the XFL root (DOMDocument + LIBRARY/**)."""
    return glob.iglob(os.path.join(xfl_root, '**', '*.xml'), recursive=True)


def read_text(path, limit=None):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return f.read(limit) if limit else f.read()


def write_text(path, content):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)


def index_library(library_dir):
    """Single pass over LIBRARY/. Returns dict with:
      name_to_file:     symbol_name -> rel xml path
      lid_to_name:      linkageIdentifier -> symbol_name (A-class only)
      itemid_to_file:   itemID -> rel xml path
      still_symbol:     [(name, lid, rel)] A-class still named Symbol NNN
      dup_names:        [(name, a, b)] name collisions
      dup_lids:         [(lid, a, b)] linkageId collisions (AS attachMovie ambiguity)
    """
    name_to_file = {}
    lid_to_name = {}
    itemid_to_file = {}
    still_symbol = []
    dup_names = []
    dup_lids = []

    for path in iter_library_xml(library_dir):
        rel = os.path.relpath(path, library_dir).replace(os.sep, '/')
        head = read_text(path, 4000)

        m_name = SYMBOL_NAME_RE.search(head)
        if not m_name:
            continue
        name = unescape(m_name.group(1))
        if name in name_to_file:
            dup_names.append((name, name_to_file[name], rel))
        name_to_file[name] = rel

        m_id = ITEMID_RE.search(head)
        if m_id:
            itemid_to_file[m_id.group(1)] = rel

        if LEAF_RE.search(head):
            m_lid = LID_RE.search(head)
            if m_lid:
                lid = unescape(m_lid.group(1))
                if lid in lid_to_name:
                    dup_lids.append((lid, lid_to_name[lid], name))
                lid_to_name[lid] = name
                leaf = name.rsplit('/', 1)[-1]
                if SYMBOL_NUM_RE.match(leaf):
                    still_symbol.append((name, lid, rel))

    return {
        'name_to_file': name_to_file,
        'lid_to_name': lid_to_name,
        'itemid_to_file': itemid_to_file,
        'still_symbol': still_symbol,
        'dup_names': dup_names,
        'dup_lids': dup_lids,
    }
