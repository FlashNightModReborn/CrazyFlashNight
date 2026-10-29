"""Initial additive installation of the reviewed candidate; preserves existing records."""
from pathlib import Path
import hashlib
import json
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = ROOT / 'tmp/unified61-assets'
BACKUP = CANDIDATE / 'before-install'


def append_xml(relative, entries, closing, marker):
    path = ROOT / relative
    raw = path.read_bytes()
    text = raw.decode('utf-8-sig')
    if marker in text:
        raise ValueError(f'Already installed; edit native authority in place: {relative}')
    backup = BACKUP / relative
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        backup.write_bytes(raw)
    newline = '\r\n' if b'\r\n' in raw else '\n'
    body = ''.join(E.tostring(e, encoding='utf-8', pretty_print=True).decode('utf-8') for e in entries)
    text = text.replace(closing, body.replace('\n', newline) + closing, 1)
    # Decoding above preserves existing CRLF; only the new fragment gets normalized.
    path.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'') + text.encode('utf-8'))


def main():
    items = E.parse(str(CANDIDATE / 'items.xml')).getroot()
    sets = E.parse(str(CANDIDATE / 'item_sets.xml')).getroot()
    plans = E.parse(str(CANDIDATE / 'armor-plan.xml')).getroot()
    append_xml('data/items/防具_40+级.xml', list(items), '</root>', '<name>统合61式胸甲</name>')
    append_xml('data/items/item_sets.xml', list(sets), '</itemSets>', '<id>unified_type_61_armor</id>')
    append_xml('tools/cf7-balance-tool/records/armor-balance-plan.xml', list(plans), '</records>', 'itemName="统合61式胸甲"')
    path = ROOT / 'data/crafting/进阶防具.json'
    raw = path.read_bytes()
    existing = json.loads(raw.decode('utf-8-sig'))
    recipes = json.loads((CANDIDATE / 'crafting.json').read_text('utf-8'))
    current = {r.get('recipeId') for r in existing}
    if any(r['recipeId'] in current for r in recipes):
        raise ValueError('Recipe already installed')
    backup = BACKUP / 'data/crafting/进阶防具.json'
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        backup.write_bytes(raw)
    existing.extend(recipes)
    path.write_text(json.dumps(existing, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    manifest = {str(p.relative_to(BACKUP)).replace('\\', '/'): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in BACKUP.rglob('*') if p.is_file()}
    (BACKUP / 'SHA256.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Installed five items, one set, five recipes and five balance inputs; previous records backed up.')


if __name__ == '__main__':
    main()
