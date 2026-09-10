"""Build owned blood-pact symbols; preserve donor animation and shared dependencies."""
from pathlib import Path
import hashlib
import json
import re
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'flashswf/arts/things0'
ICON_SOURCE = ROOT / 'flashswf/arts/new/Codex专用素材/LIBRARY'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
URI = NS['x']
PREFIX = 'Codex/Ti61-血剑战技/'
SKILL = PREFIX + '战技容器-猩红天秤'
ICON = PREFIX + '图标-猩红天秤'
PARSER = E.XMLParser(strip_cdata=False, remove_blank_text=False)


def load(path):
    return E.parse(str(path), PARSER)


def identity(root, name, linkage=None):
    root.set('name', name)
    root.set('itemID', '61b10000-' + hashlib.sha256(name.encode()).hexdigest()[:8])
    for key in list(root.attrib):
        if key.startswith('linkage'):
            del root.attrib[key]
    if linkage:
        root.set('linkageExportForAS', 'true')
        root.set('linkageIdentifier', linkage)
    timeline = root.find('./x:timeline/x:DOMTimeline', NS)
    if timeline is not None:
        timeline.set('name', name.rsplit('/', 1)[-1])


def write_symbol(document, name):
    path = DEST / 'LIBRARY' / (name + '.xml')
    path.parent.mkdir(parents=True, exist_ok=True)
    document.write(str(path), encoding='utf-8', xml_declaration=True)
    return path


def build():
    donor = DEST / 'LIBRARY/容器/战技容器/战技容器-撼地烈狱.xml'
    document = load(donor)
    identity(document.getroot(), SKILL, '战技容器-猩红天秤')
    retained = 0
    for action in document.findall('.//x:Actionscript', NS):
        code = ''.join(action.itertext())
        if '子弹' in code or 'shoot' in code:
            unit = '自机' if '自机 =' in code else '_parent'
            props = '子弹参数' if '子弹参数.子弹威力' in code else '子弹属性'
            power = f'{unit}.__titaniumType61.getBloodPulsePower()'
            code, count = re.subn(re.escape(props) + r'\.子弹威力 = [^;]+;',
                          f'{props}.子弹威力 = {power};\n'
                          f'{props}.hitBehavior = {{type:"titaniumBloodPact",directPower:{props}.子弹威力}};', code)
            assert count == 1
            code = re.sub(re.escape(props) + r'\.霰弹值 = \d+;', f'{props}.霰弹值 = 1;', code)
            code = re.sub(re.escape(props) + r'\.伤害类型 = "[^"]+";', f'{props}.伤害类型 = "物理";', code)
            code = re.sub(re.escape(props) + r'\.击倒率 = \d+;', f'{props}.击倒率 = 0.1;', code)
            action.find('x:script', NS).text = E.CDATA(code)
            retained += 1
    actions = document.xpath('//x:DOMLayer[@name="as"]/x:frames', namespaces=NS)[0]
    start = actions[0]
    start.set('duration', '25')
    start_code = start.find('x:Actionscript/x:script', NS)
    start_code.text = E.CDATA(start_code.text + '\n'
        '__ti61BloodRuntime = _parent.__titaniumType61;\n'
        'if (!__ti61BloodRuntime || !__ti61BloodRuntime.bindBloodPactAnimation(this)) 无敌标签 = false;')
    slam = E.Element('{%s}DOMFrame' % URI, index='25', duration='20', keyMode='9728')
    script = E.SubElement(E.SubElement(slam, '{%s}Actionscript' % URI), '{%s}script' % URI)
    script.text = E.CDATA('if (__ti61BloodRuntime) __ti61BloodRuntime.grantBloodPactBonus(this);')
    E.SubElement(slam, '{%s}elements' % URI)
    actions.insert(1, slam)
    end = actions[-1].find('x:Actionscript/x:script', NS)
    end.text = E.CDATA('if (__ti61BloodRuntime) __ti61BloodRuntime.finishBloodPact(this, __ti61BloodCastId);\n_root.战技路由.动画完毕(this,_parent);')

    # 第1至20帧保护支付和上升；身体最高点为第21帧，到达当帧撤除标签。
    invulnerability = document.xpath('//x:DOMLayer[@name="无敌标签"]/x:frames', namespaces=NS)[0]
    protected = invulnerability[0]
    protected.set('duration', '20')
    elements = protected.find('x:elements', NS)
    assert len(elements) == 0
    E.SubElement(elements, '{%s}DOMSymbolInstance' % URI,
                 libraryItemName='属性标签标志元件/无敌标签', name='无敌标签')
    exposed = E.SubElement(invulnerability, '{%s}DOMFrame' % URI,
                           index='20', duration='26', keyMode='9728')
    E.SubElement(exposed, '{%s}elements' % URI)
    tinted = 0
    for instance in document.findall('.//x:DOMSymbolInstance', NS):
        reference = instance.get('libraryItemName', '')
        if reference.startswith(('主角肢体素材/', '属性标签标志元件/', '怪物通用模板/')):
            continue
        old = instance.find('x:color', NS)
        alpha = old.find('x:Color', NS).get('alphaMultiplier') if old is not None else None
        if old is not None:
            instance.remove(old)
        color = E.SubElement(instance, '{%s}color' % URI)
        values = dict(redMultiplier='1', greenMultiplier='0.10', blueMultiplier='0.22', redOffset='25')
        if alpha is not None:
            values['alphaMultiplier'] = alpha
        E.SubElement(color, '{%s}Color' % URI, **values)
        tinted += 1
    generated = [write_symbol(document, SKILL)]

    # The small existing sword-icon closure supplies the skill icon without new raster art.
    origin = 'Codex/Ti61-血剑/图标-Codex-血色光剑天秤'
    pending, mapping, trees = [origin], {origin: ICON}, {}
    while pending:
        name = pending.pop()
        if name in trees:
            continue
        tree = load(ICON_SOURCE / (name + '.xml'))
        trees[name] = tree
        for instance in tree.findall('.//x:DOMSymbolInstance', NS):
            child = instance.get('libraryItemName')
            mapping.setdefault(child, PREFIX + '图标素材/' + hashlib.sha256(child.encode()).hexdigest()[:12])
            pending.append(child)
    for name, tree in trees.items():
        identity(tree.getroot(), mapping[name], '图标-猩红天秤' if name == origin else None)
        for instance in tree.findall('.//x:DOMSymbolInstance', NS):
            instance.set('libraryItemName', mapping[instance.get('libraryItemName')])
        generated.append(write_symbol(tree, mapping[name]))

    dom_path = DEST / 'DOMDocument.xml'
    dom = load(dom_path)
    symbols = dom.find('x:symbols', NS)
    for path in generated:
        href = path.relative_to(DEST / 'LIBRARY').as_posix()
        matches = symbols.xpath('x:Include[@href=$href]', namespaces=NS, href=href)
        if not matches:
            E.SubElement(symbols, '{%s}Include' % URI, href=href, itemID=load(path).getroot().get('itemID'))
    dom.write(str(dom_path), encoding='utf-8', xml_declaration=True)
    assert retained == 9
    print(json.dumps({'symbols': len(generated), 'combatScriptsRetained': retained,
                      'effectInstancesTinted': tinted, 'skillFrames': 46,
                      'invulnerabilityFrames': [1, 20], 'apexFrame': 21,
                      'bonusFrame': 26}, ensure_ascii=False))


if __name__ == '__main__':
    build()
