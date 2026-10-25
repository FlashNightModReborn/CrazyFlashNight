"""Register only the 25 new exports, preserving every existing source-map entry."""
from pathlib import Path
import html
import json
import re
from xml.sax.saxutils import quoteattr
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
MAP = ROOT / 'data/items/asset_source_map.xml'
SWF = 'flashswf/arts/new/Codex专用素材.swf'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}


def main():
    report = json.loads((Path(__file__).with_name('native-manifest.json')).read_text('utf-8'))
    exports = {}
    for path in (OWNER / 'LIBRARY/Codex/统合61式').rglob('*.xml'):
        root = E.parse(str(path)).getroot()
        identifier = root.get('linkageIdentifier')
        if identifier:
            if identifier in exports:
                raise ValueError('Duplicate new export: ' + identifier)
            exports[identifier] = root.get('name')
    assert set(exports) == set(report['exports']) and len(exports) == 25
    raw = MAP.read_bytes()
    original = E.fromstring(raw)
    old_entries = {e.get('id'): E.tostring(e, with_tail=False) for e in original if isinstance(e.tag, str)}
    source = raw.decode('utf-8-sig')
    newline = '\r\n' if b'\r\n' in raw else '\n'
    for identifier, symbol in sorted(exports.items()):
        existing = original.xpath('./*[@id=$identifier]', identifier=identifier)
        if existing:
            if len(existing) != 1 or existing[0].tag != 'asset' or existing[0].get('swf') != SWF or existing[0].get('symbolName') != symbol:
                raise ValueError('Conflicting linkage owner: ' + identifier)
            continue
        row = '  <asset id=' + quoteattr(identifier) + ' swf=' + quoteattr(SWF) + ' symbolName=' + quoteattr(symbol) + ' />' + newline
        after = [m for m in re.finditer(r'^  <asset id="([^"]+)"[^\r\n]*\r?\n', source, re.M) if html.unescape(m[1]) > identifier]
        if after:
            at = after[0].start()
        else:
            at = source.rfind('</' + original.tag + '>')
        source = source[:at] + row + source[at:]
    updated = source.encode('utf-8')
    parsed = E.fromstring(updated)
    for identifier, old in old_entries.items():
        match = parsed.xpath('./*[@id=$identifier]', identifier=identifier)
        if len(match) != 1 or E.tostring(match[0], with_tail=False) != old:
            raise ValueError('Unrelated source-map entry changed: ' + str(identifier))
    if updated != raw:
        backup = ROOT / 'tmp/unified61-assets/before-install/asset_source_map.xml'
        if not backup.exists():
            backup.write_bytes(raw)
        MAP.write_bytes(updated)
    print('Registered 25 exports; every pre-existing source-map entry unchanged.')


if __name__ == '__main__':
    main()
