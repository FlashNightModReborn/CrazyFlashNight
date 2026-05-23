# encoding: utf-8
"""
Rename A-class symbols in things.xfl:
  Old name pattern: contains "Symbol" and has linkageExportForAS
  New name pattern: keep folder path, replace basename with linkageIdentifier

Also updates all libraryItemName references and renames filesystem paths.
Skips items where the target file already exists (collision with non-A-class).
"""
import os, re, glob, xml.sax.saxutils
from html import unescape as html_unescape

THINGS_DIR = 'flashswf/arts/things'
LIBRARY_DIR = os.path.join(THINGS_DIR, 'LIBRARY')

# Step 1: Collect mappings
SYMBOL_RE = re.compile(
    r'<DOMSymbolItem\b[^>]*?\bname="([^"]+)"[^>]*?'
    r'linkageExportForAS="true"[^>]*?'
    r'linkageIdentifier="([^"]+)"'
)

mappings = {}       # old_name (decoded) -> new_name (decoded)
old_raw_map = {}    # old_name (decoded) -> old_name_raw (from XML)
xml_files = {}      # old_name (decoded) -> xml file path
skipped = []

for xml_file in glob.glob(os.path.join(LIBRARY_DIR, '**', '*.xml'), recursive=True):
    with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read(2000)
    m = SYMBOL_RE.search(content)
    if m:
        old_name_raw = m.group(1)
        old_name = html_unescape(old_name_raw)
        lid = html_unescape(m.group(2))
        if 'Symbol' in old_name and old_name != lid:
            folder = old_name.rsplit('/', 1)[0] if '/' in old_name else ''
            new_name = (folder + '/' + lid) if folder else lid
            new_file = os.path.join(LIBRARY_DIR, new_name.replace('/', os.sep) + '.xml')
            if os.path.exists(new_file) and new_file != xml_file:
                skipped.append({
                    'old_file': xml_file,
                    'new_file': new_file,
                    'old_name': old_name,
                    'new_name': new_name,
                    'linkage_id': lid
                })
                continue
            mappings[old_name] = new_name
            old_raw_map[old_name] = old_name_raw
            xml_files[old_name] = xml_file

print(f"A-class symbols to rename: {len(mappings)}")
print(f"Skipped (target file already exists): {len(skipped)}")
for s in skipped:
    print(f"  SKIP: {s['old_name']} -> {s['new_name']}")

# Verify no collisions in new names
if len(set(mappings.values())) != len(mappings):
    seen = set()
    for old, new in mappings.items():
        if new in seen:
            print(f"COLLISION: {new}")
        seen.add(new)
    raise RuntimeError("New name collisions detected")

# Precompute escaped versions
new_raw_map = {}
for old_name, new_name in mappings.items():
    new_raw_map[old_name] = xml.sax.saxutils.escape(new_name)

# Step 2: Process each A-class symbol XML file
for old_name, new_name in mappings.items():
    old_file = xml_files[old_name]
    old_name_raw = old_raw_map[old_name]
    new_name_raw = new_raw_map[old_name]
    old_basename = old_name.rsplit('/', 1)[-1]
    new_basename = new_name.rsplit('/', 1)[-1]

    with open(old_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    # 2a: Replace DOMSymbolItem name
    content = re.sub(
        r'(<DOMSymbolItem\b[^>]*?\bname=")' + re.escape(old_name_raw) + r'(")',
        lambda m: m.group(1) + new_name_raw + m.group(2),
        content,
        count=1
    )

    # 2b: Replace DOMTimeline name (basename only, usually 1 occurrence)
    content = re.sub(
        r'(<DOMTimeline\b[^>]*?\bname=")' + re.escape(old_basename) + r'(")',
        lambda m: m.group(1) + new_basename + m.group(2),
        content,
        count=1
    )

    # 2c: Compute new file path
    new_rel = new_name.replace('/', os.sep) + '.xml'
    new_file = os.path.join(LIBRARY_DIR, new_rel)

    os.makedirs(os.path.dirname(new_file), exist_ok=True)
    with open(new_file, 'w', encoding='utf-8') as f:
        f.write(content)

    os.remove(old_file)

print(f"File renames done.")

# Step 3: Global libraryItemName replacement across all XML files in things/
# Build a single regex for all replacements
old_to_new_raw = {old_raw_map[k]: new_raw_map[k] for k in mappings}
escaped_keys = [re.escape(k) for k in old_to_new_raw.keys()]
if escaped_keys:
    lib_pattern = re.compile(r'libraryItemName="(' + '|'.join(escaped_keys) + r')"')
    def repl_lib(m):
        return f'libraryItemName="{old_to_new_raw[m.group(1)]}"'

    all_xml_files = list(glob.glob(os.path.join(THINGS_DIR, '**', '*.xml'), recursive=True))
    modified = 0
    for xml_file in all_xml_files:
        with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        new_content = lib_pattern.sub(repl_lib, content)
        if new_content != content:
            with open(xml_file, 'w', encoding='utf-8') as f:
                f.write(new_content)
            modified += 1
    print(f"Modified {modified} files for libraryItemName references.")

# Step 4: Remove empty directories
emptied = 0
for root, dirs, files in os.walk(LIBRARY_DIR, topdown=False):
    if root != LIBRARY_DIR and not dirs and not files:
        try:
            os.rmdir(root)
            emptied += 1
        except OSError:
            pass
print(f"Removed {emptied} empty directories.")

# Step 5: Verification - check for remaining references
remaining = 0
for xml_file in glob.glob(os.path.join(THINGS_DIR, '**', '*.xml'), recursive=True):
    with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    for old_name in mappings:
        old_raw = old_raw_map[old_name]
        if f'libraryItemName="{old_raw}"' in content:
            remaining += 1
            print(f"REMAINING REF: {old_name} in {xml_file}")
        if re.search(r'<DOMSymbolItem\b[^>]*?\bname="' + re.escape(old_raw) + r'"', content):
            remaining += 1
            print(f"REMAINING SYMBOL: {old_name} in {xml_file}")

print(f"\nDone. Processed: {len(mappings)}, Skipped: {len(skipped)}, Remaining old references: {remaining}")
