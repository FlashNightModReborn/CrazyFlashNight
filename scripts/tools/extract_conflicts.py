import os, re, glob, json
from html import unescape

SYMBOL_RE = re.compile(
    r'<DOMSymbolItem\b[^>]*?\bname="([^"]+)"[^>]*?'
    r'linkageExportForAS="true"[^>]*?'
    r'linkageIdentifier="([^"]+)"'
)

base = 'flashswf/arts/things/LIBRARY'
conflicts = []
for xml_file in glob.glob(os.path.join(base, '**', '*.xml'), recursive=True):
    with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read(2000)
    m = SYMBOL_RE.search(content)
    if m:
        sym = unescape(m.group(1))
        lid = unescape(m.group(2))
        if 'Symbol' in sym and sym != lid:
            folder = sym.rsplit('/', 1)[0] if '/' in sym else ''
            new_name = (folder + '/' + lid) if folder else lid
            target_file = os.path.join(base, new_name.replace('/', os.sep) + '.xml')
            if os.path.exists(target_file):
                with open(target_file, 'r', encoding='utf-8', errors='replace') as f:
                    target_content = f.read(2000)
                tm = SYMBOL_RE.search(target_content)
                if tm:
                    target_sym = unescape(tm.group(1))
                    target_lid = unescape(tm.group(2))
                    conflicts.append({
                        'old_file': os.path.relpath(xml_file, base).replace('\\', '/'),
                        'old_name': sym,
                        'old_linkage': lid,
                        'target_file': os.path.relpath(target_file, base).replace('\\', '/'),
                        'target_name': target_sym,
                        'target_linkage': target_lid
                    })

with open('things_conflict_report.json', 'w', encoding='utf-8') as f:
    json.dump(conflicts, f, ensure_ascii=False, indent=2)
print(f'Wrote {len(conflicts)} conflicts to things_conflict_report.json')
