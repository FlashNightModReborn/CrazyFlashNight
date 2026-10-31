"""Refresh the Huofeng library owner with the canonical scanner and writer."""
from pathlib import Path
import argparse
import importlib.util
import tempfile
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[2]
OWNER = 'flashswf/arts/new/Codex专用素材.swf'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('huofeng_linkage_scanner', ROOT / 'tools/linkage_scanner/scan_linkage.py')
    scanner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(scanner)
    path = ROOT / 'data/items/asset_source_map.xml'
    original = path.read_bytes()
    tree = E.fromstring(original)
    for row in tree:
        if row.tag == 'asset':
            sources = [row]
        elif row.tag in ('duplicate', 'conflict'):
            sources = list(row)
        else:
            raise ValueError('Unknown source-map entry: ' + row.tag)
        lid = row.get('id')
        for source in sources:
            swf = source.get('swf')
            if swf != OWNER:
                scanner.results.setdefault(lid, set()).add((swf, source.get('symbolName', lid), source.get('orphan') == 'true'))
    library = ROOT / 'flashswf/arts/new/Codex专用素材'
    expected = {}
    for source in (library / 'LIBRARY/Codex/火凤套装').rglob('*.xml'):
        symbol = E.parse(source).getroot()
        lid = symbol.get('linkageIdentifier')
        if lid:
            expected[lid] = symbol.get('name')
    assert expected, 'Huofeng native symbols are not installed'
    scanner.scan_xfl(str(library))
    for lid, symbol in expected.items():
        assert scanner.results[lid] == {(OWNER, symbol, False)}, ('Conflicting or orphan export', lid)
    with tempfile.TemporaryDirectory(prefix='cf7-huofeng-map-') as temp:
        scanner.OUTPUT_XML = str(Path(temp) / 'map.xml')
        scanner.write_xml()
        generated = Path(scanner.OUTPUT_XML).read_bytes()
    def semantic(row, linkage=None):
        linkage = row.get('id', linkage)
        attrs = dict(row.attrib)
        # Upstream tools may spell out the scanner's default symbolName.
        # Compare its meaning before letting the canonical writer normalize it.
        if attrs.get('symbolName') == linkage:
            del attrs['symbolName']
        return (row.tag, sorted(attrs.items()), [semantic(child, linkage) for child in row])
    old = {}
    for row in tree:
        lid = row.get('id')
        value = semantic(row)
        assert lid not in old or old[lid] == value, ('Conflicting repeated source-map ID', lid)
        old[lid] = value
    new = {r.get('id'): semantic(r) for r in E.fromstring(generated)}
    for lid, raw in old.items():
        if lid not in expected:
            assert new.get(lid) == raw, ('Unrelated mapping drift', lid, raw, new.get(lid))
    assert set(new) - set(old) <= set(expected), 'Unexpected new export outside Huofeng'
    assert path.read_bytes() == original, 'Concurrent source-map edit'
    if args.check:
        assert original == generated, 'Regenerate Huofeng source map'
    elif original != generated:
        path.write_bytes(generated)
    print('Huofeng source map:', len(expected), 'exports; unrelated mappings preserved')


if __name__ == '__main__':
    main()
