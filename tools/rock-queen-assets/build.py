"""将已验收 R01/R02/R03 转为 things0 可换装战技；原始包是不可变输入。"""
from pathlib import Path
from zipfile import ZipFile
import argparse
import copy
import hashlib
import json
import sys
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'flashswf/arts/things0'
SOURCE = ROOT / 'flashswf/arts/new/Codex素材源稿/摇滚女皇/humanoid-rock-queens-r03-source.zip'
SOURCE_SHA = 'fa06b259e6b0225ceebfd75772f6b8d56555c3d5fedbf2ed35aa853613ece792'
PREFIX = 'Codex/摇滚女皇/'
URI = 'http://ns.adobe.com/xfl/2008/'
NS = {'x': URI}
PARSER = E.XMLParser(strip_cdata=False, remove_blank_text=True)
sys.path.insert(0, str(ROOT / 'tools/ti61-feedback'))
from xfl_asset_writer import AssetWriter
from timing import retime


class RockWriter(AssetWriter):
    OWNED_PREFIX = Path('LIBRARY/Codex/摇滚女皇')


def element(tag, **attrs):
    return E.Element('{' + URI + '}' + tag, **{k: str(v) for k, v in attrs.items()})


def identity(node, name, linkage=None):
    node.set('name', name)
    node.set('itemID', '71340000-' + hashlib.sha256(name.encode()).hexdigest()[:8])
    for k in list(node.attrib):
        if k.startswith('linkage') or k in ('lastModified', 'lastUniqueIdentifier'):
            del node.attrib[k]
    node.attrib.pop('symbolType', None)
    if linkage:
        node.set('linkageExportForAS', 'true')
        node.set('linkageIdentifier', linkage)
    node.find('./x:timeline/x:DOMTimeline', NS).set('name', name.rsplit('/', 1)[-1])


def symbol(name, linkage=None):
    node = E.Element('{' + URI + '}DOMSymbolItem', nsmap={None: URI})
    timeline = E.SubElement(E.SubElement(node, '{' + URI + '}timeline'), '{' + URI + '}DOMTimeline')
    E.SubElement(timeline, '{' + URI + '}layers')
    identity(node, name, linkage)
    return node


def layer(node, name):
    layers = node.find('./x:timeline/x:DOMTimeline/x:layers', NS)
    lay = element('DOMLayer', name=name, color='#A84FFF')
    layers.append(lay)
    return E.SubElement(lay, '{' + URI + '}frames')


def frame(frames, index=0, duration=1, code=None):
    fr = element('DOMFrame', index=index, duration=duration, keyMode=9728)
    frames.append(fr)
    if code:
        E.SubElement(E.SubElement(fr, '{' + URI + '}Actionscript'), '{' + URI + '}script').text = E.CDATA(code)
    return E.SubElement(fr, '{' + URI + '}elements')


def instance(name, slot=None, tx=0, ty=0):
    node = element('DOMSymbolInstance', libraryItemName=name)
    if slot:
        node.set('name', slot)
    E.SubElement(node, '{' + URI + '}matrix').append(element('Matrix', tx=tx, ty=ty))
    return node


def shift(inst):
    m = inst.find('./x:matrix/x:Matrix', NS)
    if m is None:
        m = E.SubElement(E.SubElement(inst, '{' + URI + '}matrix'), '{' + URI + '}Matrix')
    m.set('ty', str(round(float(m.get('ty', 0)) + 233.05, 7)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='只核对确定性生成物，不写文件')
    args = parser.parse_args()
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == SOURCE_SHA, 'accepted archive changed'
    archive = ZipFile(SOURCE)
    pending = {}
    imported = {}
    report = {'sourceSha256': SOURCE_SHA, 'groundOffset': 233.05, 'clips': []}
    # R02 为避地把整个喷流压到 36%；只解除纵向射程压缩，保留已验收的竖向轮廓。
    # 以实际枪口为中心伸展，身体、双手和武器尺寸不变。
    report['flameRange'] = {'source': 'accepted-r02 flameFloorFactor',
                            'axis': 'horizontal about calibrated muzzle', 'vertical': 'preserved'}

    def read(base, name):
        return E.fromstring(archive.read(base + 'native-source/LIBRARY/' + name + '.xml'), PARSER)

    def stage(node):
        name = node.get('name')
        pending[name] = node
        return name

    def import_visual(base, name):
        key = (base, name)
        if key in imported:
            return imported[key]
        new = PREFIX + '特效/' + hashlib.sha256((base + name).encode()).hexdigest()[:16]
        imported[key] = new
        node = read(base, name)
        identity(node, new)
        node.set('symbolType', 'graphic')
        for action in node.findall('.//x:Actionscript', NS):
            action.getparent().remove(action)
        for inst in node.findall('.//x:DOMSymbolInstance', NS):
            inst.set('libraryItemName', import_visual(base, inst.get('libraryItemName')))
            inst.attrib.pop('name', None)
        stage(node)
        return new

    # 配置装扮要求 placement -> 肢体 -> man -> unit，保持标准三层归属。
    empty = symbol(PREFIX + '空挂点')
    frame(layer(empty, '挂点'))
    stage(empty)
    holder = symbol(PREFIX + '武器挂点')
    inst = instance(empty.get('name'), 'placement')
    action = E.SubElement(E.SubElement(inst, '{' + URI + '}Actionscript'), '{' + URI + '}script')
    action.text = E.CDATA('onClipEvent (load) {\n    _root.摇滚女皇战技.bindWeapon(this);\n}')
    frame(layer(holder, '动态装扮')).append(inst)
    stage(holder)
    # 10x10 判定基准；运行时按当前可见特效的范围放置，不复制 Boss 伤害脚本。
    area = symbol(PREFIX + '判定区域')
    shape = element('DOMShape')
    fills = E.SubElement(shape, '{' + URI + '}fills')
    fill = E.SubElement(fills, '{' + URI + '}FillStyle', index='1')
    fill.append(element('SolidColor', color='#FF0000'))
    E.SubElement(shape, '{' + URI + '}edges').append(element('Edge', fillStyle1='1', edges='!0 0|200 0|200 200|0 200|0 0'))
    frame(layer(area, '范围')).append(shape)
    stage(area)

    names = {
        'vocal': '主唱突刺', 'keyboard': '旋镰横掠', 'guitar': '吉他震地',
        'guitar-gun': '吉他机枪扫射', 'guitar-flame': '吉他持续喷火',
        'keyboard-jump': '跳跃镰刀斩', 'keyboard-arc': '弹射弧光斩',
        'vocal-wide': '主唱广域裂空斩', 'vocal-draw': '主唱拔刀裂空斩',
        'vocal-cross': '主唱横向裂空斩', 'guitar-combo': '吉他导弹烈炎炮',
        'guitar-missile': '吉他导弹炮', 'guitar-wide': '吉他广域喷火', 'guitar-cannon': '吉他烈炎炮'}
    sources = []
    vocal = json.loads(archive.read('accepted-r02/accepted-vocal/migration-manifest.json'))
    sources.append(('accepted-r02/accepted-vocal/', 'vocal', vocal['records'],
                    '预览/主唱突刺-人形-身体', '预览/主唱突刺-人形-特效'))
    for base in ('accepted-r02/', ''):
        for clip in json.loads(archive.read(base + 'migration-manifest.json'))['clips']:
            cid = clip['id']
            sources.append((base, cid, clip['records'], '预览/' + cid + '/body', '预览/' + cid + '/full'))

    for base, cid, records, body_name, full_name in sources:
        total = len(records)
        body = read(base, body_name)
        title = names[cid]
        identity(body, PREFIX + '战技容器-' + title, '战技容器-' + title)
        layers = body.find('./x:timeline/x:DOMTimeline/x:layers', NS)
        for lay in list(layers):
            if '边界' in lay.get('name', ''):
                layers.remove(lay)
                continue
            for inst in lay.findall('.//x:DOMSymbolInstance', NS):
                old = inst.get('libraryItemName')
                if '主角肢体素材/' in old:
                    inst.set('libraryItemName', '主角肢体素材/' + old.split('主角肢体素材/', 1)[1])
                else:
                    inst.set('libraryItemName', holder.get('name'))
                    inst.set('name', 'rockWeapon')
                for key in ('symbolType', 'loop', 'firstFrame'):
                    inst.attrib.pop(key, None)
                shift(inst)
        # 从 full 提取 FX 层：不携预览边界、静态裸模、离线飞行弹体。
        full = read(base, full_name)
        fx = symbol(PREFIX + '演出/' + cid)
        fx_layers = fx.find('./x:timeline/x:DOMTimeline/x:layers', NS)
        for lay in full.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS):
            if '边界' in lay.get('name', '') or '离线' in lay.get('name', ''):
                continue
            chosen = copy.deepcopy(lay)
            any_fx = False
            for elements in chosen.findall('./x:frames/x:DOMFrame/x:elements', NS):
                for inst in list(elements):
                    old = inst.get('libraryItemName', '')
                    slot = inst.get('name', '')
                    if ('主角肢体素材/' in old or '玩家' in old or '/weapon/' in old
                            or '边界' in old or '离线' in slot or 'projectile/' in old):
                        elements.remove(inst)
                        continue
                    if E.QName(inst).localname != 'DOMSymbolInstance':
                        elements.remove(inst)
                        continue
                    inst.set('libraryItemName', import_visual(base, old))
                    inst.attrib.pop('name', None)
                    if cid == 'guitar-flame':
                        rec = records[int(elements.getparent().get('index', '0'))]
                        factor = float(rec['flameFloorFactor'])
                        assert 0 < factor < 1
                        m = inst.find('./x:matrix/x:Matrix', NS)
                        mouth = float(rec['muzzle'][0])
                        for key, default in (('a', 1), ('c', 0)):
                            m.set(key, str(float(m.get(key, default)) / factor))
                        m.set('tx', str(mouth + (float(m.get('tx', 0)) - mouth) / factor))
                    any_fx = True
            if any_fx:
                fx_layers.append(chosen)
        records, timing = retime(body, fx, records, cid, DEST / 'LIBRARY')
        total = len(records)
        # FX 自己保持预览原点，只在容器挂载时统一移到生产地面。
        frame(layer(fx, '停止自主播放'), 0, total, 'stop();')
        stage(fx)
        fx_frame = layer(body, '演出')
        frame(fx_frame, 0, total).append(instance(fx.get('name'), 'rockFX', ty=233.05))
        fx_layer = fx_frame.getparent()
        layers.remove(fx_layer)
        layers.insert(0, fx_layer)
        controls = layer(body, '战技协议')
        for at, rec in enumerate(records):
            source_frame = rec.get('sourceFrame', rec.get('frame', at + 68))
            player_frame = rec.get('playerFrame', 15)
            code = '_root.摇滚女皇战技.frame(this, "%s", %d, %d, %d);' % (cid, at + 1, source_frame, player_frame)
            if at == total - 1:
                code += '\n_root.摇滚女皇战技.finish(this);'
            frame(controls, at, 1, code)
        frame(layer(body, '命中范围'), 0, total).append(instance(area.get('name'), 'rockArea'))
        # 沿用标准技能的地面投影与空中高度修正，覆盖入库的全部十四段动作。
        shadow_source = E.parse(str(DEST / 'LIBRARY/容器/战技容器/战技容器-瞬步斩.xml'), PARSER)
        shadow = copy.deepcopy(shadow_source.find('.//x:DOMSymbolInstance[@libraryItemName="主角肢体素材/Symbol 3"]', NS))
        shadow.set('name', 'rockShadow')
        frame(layer(body, '地面影子'), 0, total).append(shadow)
        stage(body)
        report['clips'].append({'id': cid, 'title': title, 'frames': total,
                                'linkage': '战技容器-' + title, 'source': base + body_name,
                                'timing': timing,
                                'sourceFrames': [r.get('sourceFrame', r.get('frame', i+68)) for i, r in enumerate(records)]})

    writer = RockWriter(DEST, 'LIBRARY/Codex/摇滚女皇')
    expected = {}
    dom_path = DEST / 'DOMDocument.xml'
    # 保留现役 DOMDocument 格式与其他作者内容，不全库重排。
    dom = E.parse(str(dom_path), E.XMLParser(strip_cdata=False))
    symbols = dom.find('./x:symbols', NS)
    for inc in list(symbols):
        if inc.get('href', '').startswith(PREFIX):
            symbols.remove(inc)
    for name, node in sorted(pending.items()):
        path = DEST / 'LIBRARY' / (name + '.xml')
        expected[path] = E.tostring(node, encoding='utf-8', xml_declaration=True, pretty_print=True)
        symbols.append(element('Include', href=name + '.xml', itemID=node.get('itemID')))
    expected[dom_path] = E.tostring(dom, encoding='utf-8', xml_declaration=True)
    report['symbols'] = len(pending)
    report['totalFrames'] = sum(c['frames'] for c in report['clips'])
    manifest = Path(__file__).parent / 'manifest.json'
    manifest_bytes = (json.dumps(report, ensure_ascii=False, indent=2)+'\n').encode('utf-8')
    if args.check:
        mismatches = [str(p.relative_to(ROOT)) for p, data in expected.items() if not p.exists() or p.read_bytes() != data]
        if not manifest.exists() or manifest.read_bytes() != manifest_bytes:
            mismatches.append(str(manifest.relative_to(ROOT)))
        if mismatches:
            raise SystemExit('stale generated files: '+', '.join(mismatches))
    else:
        for path, data in expected.items():
            writer.add(path, data)
        writer.commit()
        manifest.write_bytes(manifest_bytes)
    print(json.dumps({k: v for k, v in report.items() if k != 'clips'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
