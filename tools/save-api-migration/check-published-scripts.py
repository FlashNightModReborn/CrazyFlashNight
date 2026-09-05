"""Compare a fresh FFDec script export with reachable XFL save callsites.

Usage: python -X utf8 tools/save-api-migration/check-published-scripts.py SWF EXPORT_DIR
The export must come from the named SWF; compilation/hash freshness is checked by
compile_test.ps1 and the caller. This tool does not publish or patch SWF files.
"""
from collections import Counter, deque
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def reachable_symbols(xfl):
    """Local timeline/export roots; runtime shared imports own no local frame scripts."""
    symbols = {}
    files = {}
    roots = set()
    imported = {}
    for file in (xfl / 'LIBRARY').rglob('*.xml'):
        element = ET.parse(file).getroot()
        if element.tag.rsplit('}', 1)[-1] != 'DOMSymbolItem':
            continue
        name = element.get('name')
        symbols[name] = element
        files[name] = file.resolve()
        if element.get('linkageImportForRS') == 'true':
            imported[file.resolve()] = element.get('linkageURL')
        if element.get('linkageExportForAS') == 'true' or element.get('linkageExportForRS') == 'true':
            roots.add(name)
    document = ET.parse(xfl / 'DOMDocument.xml').getroot()
    roots.update(e.get('libraryItemName') for e in document.iter() if e.get('libraryItemName'))
    queue = deque(roots)
    visited = set()
    while queue:
        name = queue.popleft()
        if name in visited or name not in symbols:
            continue
        visited.add(name)
        if files[name] in imported:
            continue
        queue.extend(e.get('libraryItemName') for e in symbols[name].iter() if e.get('libraryItemName'))
    return {files[name] for name in visited if files[name] not in imported}, imported


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    swf = Path(sys.argv[1]).resolve().relative_to(ROOT).as_posix()
    export = Path(sys.argv[2])
    manifest = json.loads((ROOT / 'tools/save-api-migration/callsites.v1.json').read_text(encoding='utf-8-sig'))
    records = [c for c in manifest['callsites'] if c['expectedSwf'] == swf and c['layer'] != 'scripts']
    if not records:
        raise SystemExit('No XFL callsites registered for ' + swf)
    xfl = ROOT / records[0]['sourcePath'].split('/LIBRARY/')[0]
    reachable, imported = reachable_symbols(xfl)
    expected = Counter()
    compiled, source_only = [], []
    source_only_details = {}
    for record in records:
        if (ROOT / record['sourcePath']).resolve() not in reachable:
            source_only.append(record['physicalId'])
            shared_swf = imported.get((ROOT / record['sourcePath']).resolve())
            source_only_details[record['physicalId']] = (
                {'reason':'runtime_shared_import', 'swf':shared_swf} if shared_swf
                else {'reason':'not_reachable_from_timeline_or_export'})
            continue
        api = record['targetApi']
        if api == 'markDirty+requestSave':
            api = 'requestSave'
        reason = '' if api == 'markDirty' else record['reasonId'][0]
        expected[(api, reason)] += 1
        compiled.append(record['physicalId'])
    files = list(export.rglob('*.as'))
    if not files:
        raise SystemExit('FFDec export contains no scripts: ' + str(export))
    observed = Counter()
    legacy = []
    cart_calls = 0
    pattern = re.compile(r'_root\.存档系统\.(markDirty|requestSave|flushDurableNow|flushBeforeTransition)\s*\(\s*(?:"([^"]*)")?\s*\)')
    for file in files:
        source = file.read_text(encoding='utf-8-sig')
        cart_calls += len(re.findall(r'_root\.保存购物车\s*\(\s*\)', source))
        for match in pattern.finditer(source):
            observed[(match[1], match[2] or '')] += 1
        if re.search(r'_root\.(?:强制存盘|自动存盘|本地存盘)\s*\(', source):
            legacy.append(str(file.relative_to(export)))
    errors = []
    expected_cart_calls = sum(1 for c in manifest['outOfScope']['xflSaveShopCart']
                              if (ROOT / c['sourcePath']).resolve() in reachable)
    if cart_calls != expected_cart_calls:
        errors.append({'partialCartCalls':cart_calls, 'expectedPartialCartCalls':expected_cart_calls})
    if expected != observed:
        errors.append({'missing':[(a, r, n) for (a, r), n in (expected - observed).items()],
                       'unexpected':[(a, r, n) for (a, r), n in (observed - expected).items()]})
    if legacy:
        errors.append({'legacyCalls':legacy})
    result = {'ok':not errors, 'swf':swf, 'exportedScripts':len(files),
              'compiledCallsites':compiled, 'sourceOnlyCallsites':source_only,
              'sourceOnlyDetails':source_only_details,
              'sourceOnlyMeaning':'Unused library or runtime shared import; retained source, not a live/dead gameplay verdict.',
              'calls':[(a, r, n) for (a, r), n in sorted(observed.items())], 'errors':errors}
    result['partialCartCalls'] = cart_calls
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
