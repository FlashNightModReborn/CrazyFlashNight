import re, subprocess, os, glob
from html import unescape

THINGS_DIR = 'flashswf/arts/things'
SYMBOL_RE = re.compile(
    r'<DOMSymbolItem\b[^>]*?\bname="([^"]+)"[^>]*?'
    r'linkageExportForAS="true"[^>]*?'
    r'linkageIdentifier="([^"]+)"'
)

result = subprocess.check_output(
    ['git', 'status', '--short', '--porcelain', 'flashswf/arts/things/LIBRARY/'],
    encoding='utf-8'
)

old_to_new = {}
for line in result.strip().split('\n'):
    if line.startswith(' D '):
        path = line[3:].strip().strip('"')
        git_path = path.replace('\\', '/')
        try:
            content = subprocess.check_output(
                ['git', 'show', f'HEAD:{git_path}'],
                encoding='utf-8',
                stderr=subprocess.DEVNULL
            )
            m = SYMBOL_RE.search(content)
            if m:
                old_raw = m.group(1)
                lid = unescape(m.group(2))
                old_to_new[old_raw] = lid
        except Exception:
            pass

print(f'Reconstructed {len(old_to_new)} mappings from git HEAD')

remaining = 0
for xml_file in glob.glob(os.path.join(THINGS_DIR, '**', '*.xml'), recursive=True):
    with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    for old_raw in old_to_new:
        if f'libraryItemName="{old_raw}"' in content:
            remaining += 1
            if remaining <= 10:
                print(f'REMAINING: {old_raw} in {xml_file}')

print(f'Total remaining libraryItemName references: {remaining}')
