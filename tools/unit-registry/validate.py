"""Read-only unit identity and authored-reference audit. No Flash or player state."""
import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from unit_registry import UnitRegistry, normalize_book_units


def validate_registry_delta(registry, baseline):
    old = UnitRegistry(baseline)
    for identity, entry in old.by_id.items():
        current = registry.by_id.get(identity)
        if current is None:
            raise ValueError('Registered unit id must not be removed: ' + str(identity))
        if 'key' in entry and current.get('key') != entry['key']:
            raise ValueError('Stable unit key changed: ' + str(identity))
    for identity, entry in registry.by_id.items():
        if identity not in old.by_id:
            if identity <= max(old.by_id):
                raise ValueError('New unit must not reuse an old id gap: ' + str(identity))
            if 'key' not in entry:
                raise ValueError('New unit requires a semantic key: ' + str(identity))


def type_references(node):
    if node is None:
        return []
    if not len(node):
        value = node.text or ''
        return [value] if value.strip() else []
    # Audit all literal CaseSwitch alternatives, without evaluating expressions.
    return [case.text or '' for case in node.iter('Case')
            if not len(case)]


def audit(root, baseline_ref=None, require_all=False):
    registry = UnitRegistry.load(root)
    if require_all and len(registry.by_key) != len(registry.by_id):
        raise ValueError('Semantic coverage incomplete: ' + str(len(registry.by_key)) + '/' + str(len(registry.by_id)))
    if baseline_ref:
        raw = subprocess.check_output(['git', 'show', baseline_ref + ':data/units/units.json'], cwd=root)
        validate_registry_delta(registry, json.loads(raw.decode('utf-8-sig')))
    counts = Counter()
    for path in sorted((root / 'data/stages').rglob('*.xml')):
        if path.name == '__list__.xml':
            continue
        tree = ET.parse(path).getroot()
        for parent in tree.iter():
            if parent.tag not in ('Enemy', 'SubDialogue', 'Dialogue'):
                continue
            types = parent.findall('Type')
            if parent.tag != 'Dialogue' and len(types) > 1:
                raise ValueError(path.relative_to(root).as_posix() + ': duplicate direct Type')
            if not types and parent.tag == 'Enemy':
                counts['inline_or_empty_enemy_nodes'] += 1
            for node in types:
                references = type_references(node)
                if len(node):
                    counts['dynamic_type_nodes'] += 1
                elif parent.tag == 'Enemy' and not references:
                    counts['inline_or_empty_enemy_nodes'] += 1
                for reference in references:
                    registry.resolve_type(reference, path.relative_to(root).as_posix() + ': ' + parent.tag + '.Type')
                    counts['legacy_references' if reference.startswith('兵种') else 'semantic_references'] += 1
    if require_all and counts['legacy_references']:
        raise ValueError('Legacy references remain: ' + str(counts['legacy_references']))
    for path in sorted((root / 'data/stages/books').glob('*.json')):
        data = json.loads(path.read_text('utf-8-sig'))
        if isinstance(data, dict) and data.get('schema') == 'playable-book.v1':
            normalize_book_units(data, registry)
            counts['book_files'] += 1
    return dict(unit_count=len(registry.by_id), semantic_key_count=len(registry.by_key),
                legacy_only_count=len(registry.by_id) - len(registry.by_key), **counts)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--baseline-ref', default='HEAD', help='Git comparison base for stable ids/keys; does not change Git state')
    parser.add_argument('--require-all', action='store_true', help='Optional final-migration coverage gate')
    args = parser.parse_args()
    try:
        result = audit(ROOT, args.baseline_ref, args.require_all)
    except (ValueError, ET.ParseError) as error:
        raise SystemExit(str(error))
    print(json.dumps(dict(ok=True, **result), ensure_ascii=False))
