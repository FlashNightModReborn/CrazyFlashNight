"""从 3XD 原生分件确定性装配四款变体图标和一个 JK 兼容图标。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'flashswf/arts/new/3XD的素材/LIBRARY'
DEST = ROOT / 'flashswf/arts/new/Codex专用素材'
PREFIX = 'Codex/JK变体图标/'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
WHITE = '4人物服饰外观/普通jk校服/jk白丝裙子'
BLACK = '4人物服饰外观/普通jk校服/jk黑丝裙子'
SHOE = '4人物服饰外观/武装jk套装/图标/图标-武装jk套装鞋子'
SHOE_BODY = '4人物服饰外观/武装jk套装/男变装-武装jk套装鞋子'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(name):
    return (SOURCE / (name + '.xml')).read_bytes().decode('utf-8-sig')


def build():
    def shoe_body(color):
        return f'4人物服饰外观/普通jk校服/jk{color}丝鞋子/男变装-武装jk套装{color}丝鞋子'

    plans = [
        (WHITE + '/图标-jk套装白丝裙子', '图标-Codex-jk套装白丝裙子', {}, shoe_body('白')),
        (WHITE + '/图标-jk套装白丝裙子', '图标-jk套装黑丝裙子',
         {WHITE + '/女变装-jk套装白丝屁股': BLACK + '/女变装-jk套装黑丝屁股'}, shoe_body('黑')),
    ]
    for color in ('白', '黑'):
        plans.append((SHOE, f'图标-jk套装{color}丝鞋子',
                      {SHOE_BODY: shoe_body(color)}, None))
    # 原库已将普通 JK 图标误导出为“图标-JK校服校服”，保留旧物品所需的链接。
    plans.append(('4人物服饰外观/普通jk校服/jk校服/图标/图标-武装jk套装校服',
                  '图标-JK校服', {}, None))
    nodes, inputs = {}, {}
    for source, linkage, overrides, cue in plans:
        text = read(source)
        inputs[source + '.xml'] = sha((SOURCE / (source + '.xml')).read_bytes())
        for old, new in overrides.items():
            assert old in text
            text = text.replace(old, new)
        if cue:
            # 同一遮罩内用原生鞋袜分件作小型外观提示；保留原作者裙摆取景。
            layer = re.search(r'<DOMLayer name="Layer_2"[^>]*>', text)
            assert layer
            cue_xml = f'''<DOMLayer name="袜色提示" color="#59D751" parentLayerIndex="0">
          <frames><DOMFrame index="0" keyMode="9728"><elements>
                <DOMSymbolInstance libraryItemName="{cue}" symbolType="graphic" loop="loop">
                  <matrix><Matrix a="0.145" d="0.145" tx="6.3" ty="6.1"/></matrix>
                  <transformationPoint><Point/></transformationPoint>
                </DOMSymbolInstance>
          </elements></DOMFrame></frames>
        </DOMLayer>
        '''
            text = text[:layer.start()] + cue_xml + text[layer.start():]
        nodes[PREFIX + linkage] = (source, linkage, text)
    queue = list(nodes)
    while queue:
        name = queue.pop()
        source, linkage, text = nodes[name]
        parsed = ET.fromstring(text)
        assert not parsed.findall('.//x:DOMBitmapInstance', NS), 'JK icons must remain pure vector'
        for instance in parsed.findall('.//x:DOMSymbolInstance', NS):
            dependency = instance.attrib['libraryItemName']
            target = PREFIX + '依赖/' + sha(dependency.encode('utf-8'))[:16]
            if target not in nodes:
                nodes[target] = (dependency, None, read(dependency))
                inputs[dependency + '.xml'] = sha((SOURCE / (dependency + '.xml')).read_bytes())
                queue.append(target)
    outputs, includes = {}, []
    for name, (source, linkage, text) in sorted(nodes.items()):
        parsed = ET.fromstring(text)
        root_match = re.search(r'<DOMSymbolItem\b[^>]*>', text)
        head = root_match[0]
        identity = sha(('jk-variant-icon:' + name).encode('utf-8'))
        item_id = identity[:8] + '-' + identity[8:16]
        head = re.sub(r'\bname="[^"]*"', lambda m: 'name="' + name + '"', head, count=1)
        head = re.sub(r'\bitemID="[^"]*"', 'itemID="' + item_id + '"', head, count=1)
        head = re.sub(r'\s+linkage\w+="[^"]*"', '', head)
        if linkage:
            head = head[:-1] + ' linkageExportForAS="true" linkageIdentifier="' + linkage + '">'
        text = text[:root_match.start()] + head + text[root_match.end():]
        text = re.sub(r'(<DOMTimeline\s+name=")[^"]*(")', lambda m: m[1] + name.rsplit('/', 1)[-1] + m[2], text, count=1)
        for dependency in {n.attrib['libraryItemName'] for n in parsed.findall('.//x:DOMSymbolInstance', NS)}:
            target = PREFIX + '依赖/' + sha(dependency.encode('utf-8'))[:16]
            text = text.replace('libraryItemName="' + dependency + '"', 'libraryItemName="' + target + '"')
        data = (text.replace('\r\n', '\n').rstrip() + '\n').encode('utf-8')
        ET.fromstring(data)
        relative = 'LIBRARY/' + name + '.xml'
        outputs[DEST / relative] = data
        includes.append((name + '.xml', item_id))
    dom_path = DEST / 'DOMDocument.xml'
    dom = dom_path.read_bytes().decode('utf-8')
    newline = '\r\n' if '\r\n' in dom else '\n'
    dom = re.sub(r'(?m)^[ \t]*<Include href="Codex/JK变体图标/[^"]*"[^>]*/>\r?\n', '', dom)
    dom = re.sub(r'(?m)^[ \t]*<DOMFolderItem name="Codex/JK变体图标(?:/依赖)?"[^>]*/>\r?\n', '', dom)
    folders = []
    for name in (PREFIX.rstrip('/'), PREFIX + '依赖'):
        identity = sha(('jk-variant-folder:' + name).encode('utf-8'))
        folders.append(f'          <DOMFolderItem name="{name}" itemID="{identity[:8]}-{identity[8:16]}"/>{newline}')
    assert len(re.findall(r'(?m)^[ \t]*</folders>', dom)) == 1
    dom = re.sub(r'(?m)^([ \t]*)</folders>', lambda m: ''.join(folders) + m[0], dom, count=1)
    addition = ''.join(f'          <Include href="{name}" itemID="{item_id}"/>{newline}' for name, item_id in includes)
    assert len(re.findall(r'(?m)^[ \t]*</symbols>', dom)) == 1
    dom = re.sub(r'(?m)^([ \t]*)</symbols>', lambda m: addition + m[0], dom, count=1)
    ET.fromstring(dom)
    outputs[dom_path] = dom.encode('utf-8')
    manifest = {'schema': 1, 'generator': 'tools/jk-variant-icons/assemble.py',
                'sourceRoot': SOURCE.relative_to(ROOT).as_posix(), 'sourceSha256': dict(sorted(inputs.items())),
                'outputs': {p.relative_to(ROOT).as_posix(): sha(b) for p, b in outputs.items() if p != dom_path},
                'linkages': [linkage for _, linkage, _, _ in plans]}
    outputs[Path(__file__).with_name('manifest.json')] = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    outputs = build()
    failures = []
    for path, data in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes() != data:
                failures.append(path.relative_to(ROOT).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    if failures:
        raise SystemExit('stale JK icon assembly: ' + ', '.join(failures))
    print(f'JK variant icons: {len(outputs)-2} vector symbols, {len(outputs)} files ' + ('checked' if args.check else 'assembled'))


if __name__ == '__main__':
    main()
