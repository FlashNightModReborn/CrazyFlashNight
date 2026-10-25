"""Read-only checks of the set's actual data, native art, exported SWF and RSL consumer."""
from pathlib import Path
import hashlib
import json
import struct
import zlib
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材'
X = {'x': 'http://ns.adobe.com/xfl/2008/'}


def swf_links(path):
    raw = path.read_bytes()
    data = zlib.decompress(raw[8:]) if raw[:3] == b'CWS' else raw[8:]
    offset = (5 + 4*(data[0] >> 3) + 7)//8 + 4
    exports, imports = {}, []
    while offset + 2 <= len(data):
        head = struct.unpack_from('<H', data, offset)[0]
        offset += 2
        code, size = head >> 6, head & 63
        if size == 63:
            size = struct.unpack_from('<I', data, offset)[0]
            offset += 4
        payload = data[offset:offset+size]
        offset += size
        if code not in (56, 57, 71):
            continue
        pos = 0
        url = None
        if code != 56:
            end = payload.index(0)
            url = payload[:end].decode('utf-8')
            pos = end + 1 + (2 if code == 71 else 0)
        count = struct.unpack_from('<H', payload, pos)[0]
        pos += 2
        for _ in range(count):
            identifier = struct.unpack_from('<H', payload, pos)[0]
            pos += 2
            end = payload.index(0, pos)
            name = payload[pos:end].decode('utf-8')
            pos = end + 1
            if code == 56:
                exports[name] = identifier
            else:
                imports.append({'url': url, 'name': name})
    return exports, imports


def main():
    design = json.loads((HERE / 'design.json').read_text('utf-8'))
    source_manifest = json.loads((HERE / 'source/source-manifest.json').read_text('utf-8'))
    for entry in source_manifest['files']:
        raw = (HERE / 'source' / entry['path']).read_bytes()
        assert len(raw) == entry['bytes']
        assert hashlib.sha256(raw).hexdigest() == entry['sha256'], entry['path']
    item_names = set()
    mod_tags = set()
    for path in (ROOT / 'data/items').rglob('*.xml'):
        root = E.parse(str(path)).getroot()
        item_names.update(n.text for n in root.findall('.//item/name') if n.text)
        if path.parent.name == 'equipment_mods':
            mod_tags.update(n.text for n in root.findall('.//tag') if n.text)
    blocked = set(design['blockedTags'].split(','))
    assert blocked <= mod_tags, blocked - mod_tags
    assert '强化辅材' in blocked and '等级校正' not in blocked
    recipes = json.loads((ROOT / 'data/crafting/进阶防具.json').read_text('utf-8-sig'))
    items = {it.findtext('name'): it for it in E.parse(str(ROOT / 'data/items/防具_40+级.xml')).getroot().findall('item')}
    checked = []
    for spec in design['items']:
        item = items[spec['name']]
        assert item.findtext('setId') == design['setId']
        assert item.findtext('blockedTags') == design['blockedTags']
        assert item.findtext('allowedModTags') == design['allowedModTags']
        assert '电力' in item.findtext('inherentTags').split(',')
        assert item.findtext('data/modslot') == '1'
        assert item.findtext('use') == spec['slot']
        if spec['slot'] == '上装装备':
            cannon = item.find('lifecycle/attr_统合61/bullet/bullet_0')
            assert cannon.findtext('diffusion') == '5'
            assert cannon.findtext('split') == '12'
        assert int(item.findtext('data/level')) == design['level']
        assert int(item.findtext('price')) == design['marketPrice']
        recipe_id = 'craft.unified61.' + spec['component'].split('_')[0]
        selected = [r for r in recipes if r.get('recipeId') == recipe_id]
        assert len(selected) == 1, recipe_id
        recipe = selected[0]
        assert recipe['name'] == spec['name']
        assert recipe['price'] == design['craftGold'] and recipe['kprice'] == design['craftKpoints']
        expected_materials = [spec['source'] + '#1', '高耐力橡胶#2', '传感器#2']
        if spec['slot'] == '头部装备':
            expected_materials.append('红外夜视仪#1')
        assert recipe['materials'] == expected_materials
        for material in recipe['materials']:
            name, count = material.rsplit('#', 1)
            assert name in item_names and int(count) > 0, material
        for key in ('weight', 'hp', 'mp', 'damage', 'defence'):
            assert float(item.findtext('data/' + key)) == spec[key], (spec['name'], key)
        assert item.findtext('balance/weightLayers') == '3'
        current = float(item.findtext('balance/currentScore'))
        budget = float(item.findtext('balance/weightedScore'))
        assert abs(current/budget-1) <= .05
        checked.append({'name': spec['name'], 'currentScore': current, 'weightedScore': budget})
    catalog = E.parse(str(ROOT / 'data/items/item_sets.xml')).getroot()
    sets = [s for s in catalog.findall('set') if s.findtext('id') == design['setId']]
    assert len(sets) == 1
    names = sets[0].findall('effects/effect_0/authorizedWeapons/weapon')
    assert [n.text for n in names] == design['authorizedWeapons']
    assert '血色光剑天秤' not in [n.text for n in names]
    native = {}
    for path in (OWNER / 'LIBRARY/Codex/统合61式').rglob('*.xml'):
        root = E.parse(str(path)).getroot()
        assert root.get('name') not in native
        native[root.get('name')] = root
    exported = {r.get('linkageIdentifier'): n for n, r in native.items() if r.get('linkageIdentifier')}
    assert len(exported) == 25
    for root in native.values():
        for element in root.xpath('.//*[@libraryItemName]'):
            assert element.get('libraryItemName') in native, element.get('libraryItemName')
    def check_static_icon(name, seen):
        if name in seen:
            return
        seen.add(name)
        root = native[name]
        frames = root.findall('.//x:DOMFrame', X)
        assert max(int(f.get('index', 0)) + int(f.get('duration', 1)) for f in frames) == 1, name
        for child in root.xpath('.//*[@libraryItemName]'):
            check_static_icon(child.get('libraryItemName'), seen)
    def check_mask_depth(name, depth, seen):
        assert depth < 2, 'Nested icon mask: ' + name
        if (name, depth) in seen:
            return
        seen.add((name, depth))
        layers = native[name].findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', X)
        for layer in layers:
            parent = layer.get('parentLayerIndex')
            masked = parent is not None and layers[int(parent)].get('layerType') == 'mask'
            assert depth + int(masked) < 2, 'Nested icon mask content: ' + name
            for child in layer.xpath('.//*[@libraryItemName]'):
                check_mask_depth(child.get('libraryItemName'), depth + int(masked), seen)
    for identifier, name in exported.items():
        if identifier.startswith('图标-Codex-统合61式'):
            icon_layers = native[name].findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', X)
            shadow_layers = 0
            for layer in icon_layers:
                first = layer.find('x:frames/x:DOMFrame[@index="0"]/x:elements', X)
                second = layer.find('x:frames/x:DOMFrame[@index="1"]/x:elements', X)
                assert first is not None and second is not None, (name, layer.get('name'))
                if layer.get('name') == '钛合金同源底影':
                    assert len(first) == 1 and len(second) == 0, name
                    shadow_layers += 1
                else:
                    assert E.tostring(first, method='c14n') == E.tostring(second, method='c14n'), (name, layer.get('name'))
            assert shadow_layers == 1, name
            for child in native[name].xpath('.//*[@libraryItemName]'):
                check_static_icon(child.get('libraryItemName'), set())
            check_mask_depth(name, 0, set())
    swf = ROOT / 'flashswf/arts/new/Codex专用素材.swf'
    binary, _ = swf_links(swf)
    assert set(exported) <= set(binary), set(exported) - set(binary)
    _, imports = swf_links(ROOT / 'flashswf/arts/things-new.swf')
    assert any(i['name'] == 'Codex专用素材' and 'Codex' in i['url'] for i in imports)
    source_map = E.parse(str(ROOT / 'data/items/asset_source_map.xml')).getroot()
    for identifier, name in exported.items():
        rows = source_map.xpath('./asset[@id=$identifier]', identifier=identifier)
        assert len(rows) == 1 and rows[0].get('symbolName') == name
        assert rows[0].get('swf') == 'flashswf/arts/new/Codex专用素材.swf'
    result = {'items': checked, 'nativeSymbols': len(native), 'exportsVerifiedInSwf': len(exported),
              'consumer': 'things-new -> Codex专用素材', 'swfSha256': hashlib.sha256(swf.read_bytes()).hexdigest(),
              'recipesValidated': len(checked), 'archiveFilesVerified': len(source_manifest['files']),
              'blockedModTagsVerified': sorted(blocked), 'sourceMapEntriesVerified': len(exported),
              'iconsUseStaticClosedGraphics': True,
              'iconMaskDepthAtMostOne': True,
              'dropFramesDifferOnlyByBackgroundShadow': True,
              'gameplayAcceptance': 'pending'}
    out = ROOT / 'tmp/unified61-assets/validation.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
