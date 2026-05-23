import os, re
from html import unescape

SYMBOL_RE = re.compile(
    r'<DOMSymbolItem\b[^>]*?\bname="([^"]+)"[^>]*?'
    r'linkageExportForAS="true"[^>]*?'
    r'linkageIdentifier="([^"]+)"'
)

base = 'flashswf/arts/things/LIBRARY'

# Step 1: collect all A-class symbols
a_class = []
for root, dirs, files in os.walk(base):
    for fname in files:
        if not fname.endswith('.xml'):
            continue
        xml_file = os.path.join(root, fname)
        with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read(2000)
        m = SYMBOL_RE.search(content)
        if m:
            sym = unescape(m.group(1))
            lid = unescape(m.group(2))
            if 'Symbol' in sym and sym != lid:
                a_class.append({
                    'file': xml_file,
                    'name': sym,
                    'lid': lid
                })

print(f'Total A-class: {len(a_class)}')

# Step 2: build set of existing filenames per folder
existing = {}
for root, dirs, files in os.walk(base):
    rel = os.path.relpath(root, base).replace('\\', '/')
    existing[rel] = set(files)

# Step 3: find conflicts
conflicts = []
for item in a_class:
    folder = item['name'].rsplit('/', 1)[0] if '/' in item['name'] else '.'
    target_fname = item['lid'] + '.xml'
    if target_fname in existing.get(folder, set()):
        target_file = os.path.join(base, folder, target_fname)
        with open(target_file, 'r', encoding='utf-8', errors='replace') as f:
            target_content = f.read(2000)
        tm = SYMBOL_RE.search(target_content)
        if tm:
            target_sym = unescape(tm.group(1))
            target_lid = unescape(tm.group(2))
            conflicts.append({
                'old_file': os.path.relpath(item['file'], base).replace('\\', '/'),
                'old_name': item['name'],
                'old_linkage': item['lid'],
                'target_file': os.path.relpath(target_file, base).replace('\\', '/'),
                'target_name': target_sym,
                'target_linkage': target_lid
            })

print(f'Found {len(conflicts)} conflicts')
for c in conflicts:
    print()
    print('[旧 A 类文件]')
    print('  文件:', c['old_file'])
    print('  name (库中路径):', c['old_name'])
    print('  linkageIdentifier (AS链接名):', c['old_linkage'])
    print('[目标文件已存在]')
    print('  文件:', c['target_file'])
    print('  name (库中路径):', c['target_name'])
    print('  linkageIdentifier (AS链接名):', c['target_linkage'])
