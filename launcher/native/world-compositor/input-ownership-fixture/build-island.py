"""Assemble a closed C1-I asset subset; never edits the authoring sources or SWFs."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / 'flashswf/levels/基地场景合集/LIBRARY'
OUT = HERE / 'island'
BOOT = HERE / 'bootstrap'
NS = 'http://ns.adobe.com/xfl/2008/'
ET.register_namespace('', NS)
ET.register_namespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance')
SEEDS = {'sprite/Symbol 2952': 'C1SurgeryOpener', 'sprite/主角/男变装-裸体身体': 'C1Body',
         'sprite/主角/男变装-基本脸型': 'C1Face'}

def sha(data): return hashlib.sha256(data).hexdigest()

def assemble():
    roots, sources = {}, []
    def visit(name):
        if name in roots: return
        path = (SOURCE / (name + '.xml')).resolve()
        if not path.is_relative_to(SOURCE.resolve()): raise ValueError('Asset escapes source library')
        data = path.read_bytes(); doc = ET.fromstring(data)
        if doc.attrib.get('name') != name: raise ValueError('Library identity mismatch: ' + name)
        for node in doc.iter():
            if node.tag.rsplit('}', 1)[-1] == 'script' and node.text and not re.fullmatch(r'\s*stop\(\);\s*', node.text):
                raise ValueError('Unreviewed executable asset: ' + name)
            if node.tag.endswith('DOMBitmapInstance'): raise ValueError('Bitmap dependency needs explicit source: ' + name)
        roots[name] = doc
        sources.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(data)})
        for node in doc.iter():
            if 'libraryItemName' in node.attrib: visit(node.attrib['libraryItemName'])
    for name in SEEDS: visit(name)
    names = {name: 'C1/' + str(index) for index, name in enumerate(sorted(roots))}
    generated = {}
    for name, doc in roots.items():
        doc.set('name', names[name])
        for key in list(doc.attrib):
            if key.startswith('linkage') or key in ('itemID', 'lastModified'): del doc.attrib[key]
        if name in SEEDS:
            doc.set('linkageExportForAS', 'true'); doc.set('linkageExportInFirstFrame', 'true'); doc.set('linkageIdentifier', SEEDS[name])
        for node in doc.iter():
            if 'libraryItemName' in node.attrib: node.set('libraryItemName', names[node.attrib['libraryItemName']])
        generated['LIBRARY/' + names[name] + '.xml'] = ET.tostring(doc, encoding='utf-8')
    base = ROOT / 'launcher/native/world-compositor/flash-hover-fixture/cooperative'
    document = ET.fromstring((base / 'DOMDocument.xml').read_bytes())
    document.find('.//{' + NS + '}script').text = '#include "C1Island.as"'
    for child in list(document):
        if child.tag.endswith('publishHistory'): document.remove(child)
    symbols = ET.Element('{' + NS + '}symbols')
    for name in sorted(names): ET.SubElement(symbols, '{' + NS + '}Include', {'href': names[name] + '.xml'})
    document.insert(0, symbols)
    generated['DOMDocument.xml'] = ET.tostring(document, encoding='utf-8')
    settings = (base / 'PublishSettings.xml').read_text(encoding='utf-8-sig').replace('CooperativeProbe', 'C1Island')
    # CS6 resolves AS2 paths relative to the XFL document's parent directory
    # (the publish location), as in scripts/TestLoader -> scripts/类定义.
    settings = settings.replace('<PackagePaths>类定义;</PackagePaths>', '<PackagePaths>../../../../scripts/类定义;</PackagePaths>')
    generated['PublishSettings.xml'] = settings.encode('utf-8')
    generated['C1Island.xfl'] = b'PROXY-CS5'
    manifest = {'kind': 'C1-I passive asset assembly; not runtime acceptance', 'sources': sorted(sources, key=lambda row: row['path']),
                'symbols': names, 'allowedAssetActions': ['stop();'], 'outputs': {path: sha(data) for path, data in sorted(generated.items())}}
    generated['asset-closure.json'] = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    return generated

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--check', action='store_true'); args = parser.parse_args()
    generated = assemble()
    for relative, data in generated.items():
        path = OUT / relative
        if args.check:
            if not path.is_file() or path.read_bytes() != data: raise SystemExit('Stale island asset: ' + relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    actual = {path.relative_to(OUT).as_posix() for path in (OUT / 'LIBRARY').rglob('*.xml')}
    expected = {name for name in generated if name.startswith('LIBRARY/')}
    if actual != expected: raise SystemExit('Unexpected executable/library assets in island')
    # No classpath/imports or library in this first module: its frame sets the
    # capability before the allowlisted game module can run DoInitAction.
    doc = ET.fromstring(generated['DOMDocument.xml'])
    doc.remove(doc.find('{' + NS + '}symbols'))
    doc.find('.//{' + NS + '}script').text = '#include "C1Bootstrap.as"'
    bootstrap = {
        'DOMDocument.xml': ET.tostring(doc, encoding='utf-8'),
        'PublishSettings.xml': generated['PublishSettings.xml'].replace(b'C1Island', b'C1Bootstrap'),
        'C1Bootstrap.xfl': b'PROXY-CS5',
    }
    for name, data in bootstrap.items():
        path = BOOT / name
        if args.check:
            if not path.is_file() or path.read_bytes() != data: raise SystemExit('Stale bootstrap: ' + name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    # CS6 resolves #include ../macros relative to the XFL directory, separately
    # from its classpath. Copy canonical bytes/BOMs, never patch macro bodies.
    macro_manifest = []
    for source in sorted((ROOT / 'scripts/macros').rglob('*.as')):
        relative = source.relative_to(ROOT / 'scripts/macros')
        destination = HERE / 'macros' / relative
        data = source.read_bytes()
        macro_manifest.append({'source':source.relative_to(ROOT).as_posix(), 'output':destination.relative_to(HERE).as_posix(), 'sha256':sha(data)})
        if args.check:
            if not destination.is_file() or destination.read_bytes() != data: raise SystemExit('Stale compile macro: ' + str(relative))
        else:
            destination.parent.mkdir(parents=True, exist_ok=True); destination.write_bytes(data)
    macro_bytes = (json.dumps(macro_manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    macro_index = HERE / 'macro-closure.json'
    if args.check:
        if not macro_index.is_file() or macro_index.read_bytes() != macro_bytes: raise SystemExit('Stale macro closure')
    else: macro_index.write_bytes(macro_bytes)
    print(f'Closed passive asset subset verified: {len(expected)} symbols; source art unchanged')

if __name__ == '__main__': main()
