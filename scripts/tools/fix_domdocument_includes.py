import os, re
from html import unescape as html_unescape, escape as html_escape

LIBRARY_DIR = 'flashswf/arts/things/LIBRARY'
DOM_PATH = 'flashswf/arts/things/DOMDocument.xml'

# Step 1: Build itemID -> current file path mapping
itemid_to_file = {}
for root, dirs, files in os.walk(LIBRARY_DIR):
    for fname in files:
        if not fname.endswith('.xml'):
            continue
        filepath = os.path.join(root, fname)
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read(500)
        m = re.search(r'<DOMSymbolItem\b[^>]*?itemID="([^"]+)"', content)
        if m:
            itemid = m.group(1)
            rel_path = os.path.relpath(filepath, LIBRARY_DIR).replace('\\', '/')
            itemid_to_file[itemid] = rel_path

print(f'Indexed {len(itemid_to_file)} XML files by itemID')

# Step 2: Read DOMDocument.xml and find broken includes
INCLUDE_RE = re.compile(r'<Include\s+href="([^"]+)"\s+itemID="([^"]+)"')

with open(DOM_PATH, 'r', encoding='utf-8', errors='replace') as f:
    dom_content = f.read()

updates = 0
broken = 0

def replace_include(m):
    global updates, broken
    href = html_unescape(m.group(1))
    itemid = m.group(2)
    
    # Check if the referenced file exists
    full_path = os.path.join(LIBRARY_DIR, href)
    if os.path.exists(full_path):
        return m.group(0)  # no change needed
    
    broken += 1
    
    # Look up the current file by itemID
    if itemid in itemid_to_file:
        new_href = itemid_to_file[itemid]
        # HTML escape special chars for XML attribute
        new_href_escaped = html_escape(new_href)
        updates += 1
        return m.group(0).replace(f'href="{m.group(1)}"', f'href="{new_href_escaped}"')
    else:
        print(f'WARNING: itemID {itemid} not found in LIBRARY (href: {href})')
        return m.group(0)

new_dom = INCLUDE_RE.sub(replace_include, dom_content)

print(f'Broken includes: {broken}')
print(f'Fixed includes: {updates}')

# Step 3: Write updated DOMDocument.xml
with open(DOM_PATH, 'w', encoding='utf-8') as f:
    f.write(new_dom)

print('DOMDocument.xml updated.')
