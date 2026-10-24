"""Mount the A07 native library through the existing things-new FLA source."""
from pathlib import Path
import argparse
import hashlib
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
FAMILY = 'CF6Vehicle'
NAMES = [FAMILY] + [FAMILY + suffix for suffix in
    ('Player', 'ArmoredBoss', 'Road', 'Raider', 'Shield', 'Roadblock', 'Grenade', 'Bullet', 'Spark', 'Explosion')]
URL = 'flashswf/arts/new/CF6Vehicle.swf'
NS = 'http://ns.adobe.com/xfl/2008/'
ET.register_namespace('', NS)
ET.register_namespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance')


def tag(name):
    return '{' + NS + '}' + name


def identity(name):
    value = hashlib.sha256(('cf6-vehicle-shared:' + name).encode()).hexdigest()
    return value[:8] + '-' + value[8:16]


def declaration(name):
    item = ET.Element(tag('DOMSymbolItem'), {
        'name': name, 'itemID': identity(name), 'symbolType': 'movie clip',
        'linkageImportForRS': 'true', 'linkageIdentifier': name, 'linkageURL': URL,
        'linkageExportInFirstFrame': 'false' if name == FAMILY else 'true'})
    timeline = ET.SubElement(ET.SubElement(item, tag('timeline')), tag('DOMTimeline'), {'name': name})
    layer = ET.SubElement(ET.SubElement(timeline, tag('layers')), tag('DOMLayer'), {'name': 'RSL'})
    frame = ET.SubElement(ET.SubElement(layer, tag('frames')), tag('DOMFrame'), {'index': '0'})
    ET.SubElement(frame, tag('elements'))
    return ET.tostring(item, encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    library = ROOT/'flashswf/arts/new/CF6Vehicle'
    exports = {}
    for path in (library/'LIBRARY').rglob('*.xml'):
        symbol = ET.parse(path).getroot()
        if symbol.get('linkageExportForAS') == 'true':
            exports[symbol.get('linkageIdentifier')] = path
    missing = set(NAMES)-set(exports)
    if missing:
        raise ValueError('Native library exports missing: '+str(sorted(missing)))
    fla = ROOT/'flashswf/arts/things-new.fla'
    with zipfile.ZipFile(fla) as archive:
        entries = [(info, archive.read(info.filename)) for info in archive.infolist()]
    original = {info.filename: data for info, data in entries}
    document = original['DOMDocument.xml'].decode('utf-8-sig')
    timeline = ET.fromstring(original['LIBRARY/things-new.xml'])
    frames = timeline.findall('.//'+tag('DOMFrame')+'[@index="3"]/'+tag('elements'))
    if len(frames) != 1:
        raise ValueError('Expected exactly one things-new frame 4 mount')
    updates = {}
    for name in NAMES:
        member = 'LIBRARY/'+name+'.xml'
        if member in original:
            found = ET.fromstring(original[member])
            wanted = ET.fromstring(declaration(name))
            for key in ('name','linkageImportForRS','linkageIdentifier','linkageURL','linkageExportInFirstFrame'):
                if found.get(key) != wanted.get(key):
                    raise ValueError('Existing vehicle import differs: '+name+'/'+key)
        else:
            if args.check:
                raise ValueError('Vehicle shared import missing: '+name)
            updates[member] = declaration(name)
        doc = ET.fromstring(document)
        includes = doc.findall('./'+tag('symbols')+'/'+tag('Include')+'[@href="'+name+'.xml"]')
        if len(includes) > 1:
            raise ValueError('Duplicate vehicle include: '+name)
        if not includes:
            if args.check:
                raise ValueError('Vehicle include missing: '+name)
            if document.count('</symbols>') != 1:
                raise ValueError('Unexpected native symbols container')
            document = document.replace('</symbols>', '<Include href="'+name+'.xml" itemID="'+identity(name)+'" loadImmediate="false"/>\n</symbols>', 1)
    anchors = frames[0].findall('./'+tag('DOMSymbolInstance')+'[@libraryItemName="CF6Vehicle"]')
    if len(anchors) > 1:
        raise ValueError('Duplicate vehicle load anchor')
    if not anchors:
        if args.check:
            raise ValueError('Vehicle load anchor missing')
        instance = ET.SubElement(frames[0],tag('DOMSymbolInstance'), {'libraryItemName':FAMILY,'symbolType':'movie clip'})
        ET.SubElement(ET.SubElement(instance,tag('matrix')),tag('Matrix'),{'tx':'1800','ty':'500'})
        updates['LIBRARY/things-new.xml'] = ET.tostring(timeline,encoding='utf-8')
    for name in NAMES[1:]:
        instances = frames[0].findall('./'+tag('DOMSymbolInstance')+'[@libraryItemName="'+name+'"]')
        if len(instances)>1:
            raise ValueError('Duplicate public vehicle import instance: '+name)
        if instances:
            color=instances[0].find('./'+tag('color')+'/'+tag('Color'))
            if color is None or color.get('alphaMultiplier')!='0':
                raise ValueError('Vehicle import probe must stay invisible: '+name)
        else:
            if args.check:
                raise ValueError('Unused vehicle import would be omitted by CS6: '+name)
            instance=ET.SubElement(frames[0],tag('DOMSymbolInstance'),{'libraryItemName':name,'symbolType':'movie clip'})
            ET.SubElement(ET.SubElement(instance,tag('matrix')),tag('Matrix'),{'tx':'1800','ty':'500'})
            ET.SubElement(ET.SubElement(instance,tag('color')),tag('Color'),{'alphaMultiplier':'0'})
            updates['LIBRARY/things-new.xml']=ET.tostring(timeline,encoding='utf-8')
    if document.encode('utf-8') != original['DOMDocument.xml']:
        updates['DOMDocument.xml'] = document.encode('utf-8')
    if args.check:
        print('CF6Vehicle shared source: 11 exact imports, one empty anchor and 10 invisible native import instances')
        return
    if updates:
        temporary = fla.with_suffix('.cf6-vehicle.tmp')
        if temporary.exists():
            raise ValueError('Unresolved previous shared-library write')
        with zipfile.ZipFile(temporary,'w',zipfile.ZIP_DEFLATED) as archive:
            for info,data in entries:
                archive.writestr(info,updates.get(info.filename,data))
            for member,data in updates.items():
                if member not in original:
                    archive.writestr(member,data)
        with zipfile.ZipFile(temporary) as archive:
            for name,data in original.items():
                if name not in updates and archive.read(name) != data:
                    raise ValueError('Unrelated FLA member changed: '+name)
        temporary.replace(fla)
    print('CF6Vehicle shared source mounted; publish things-new.swf in CS6 and verify actual imports')


if __name__ == '__main__':
    main()
