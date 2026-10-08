"""Register independent sheriff items with explicitly provisional donor stats."""
from pathlib import Path
import copy, json
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
ITEMS = ROOT / 'data/items'
SET = 'heavy_duty_sheriff'
SPECS = [
    ('重装特勤头盔', '防具_20-39级.xml', '特战队员头部装备', '变装-Codex-重装特勤头盔', '全封闭防护外壳与透视目镜构成的特勤头盔。'),
    ('重装特勤背心', '防具_20-39级.xml', '特战队员战术背心', '变装-Codex-重装特勤', '以环抱式侧围固定的重装背心，配有通讯器、弹药与勤务附件。'),
    ('重装特勤手套', '防具_20-39级.xml', '特战队员手套', '变装-Codex-重装特勤', '护腕延伸至前臂甲片内侧的特勤防护手套。'),
    ('重装特勤战术裤', '防具_20-39级.xml', '特战队员战术裤', '变装-Codex-重装特勤', '配有护裆、髋部护片、腿甲及靴筒的重装战术裤。'),
    ('重装特勤战靴', '防具_20-39级.xml', '特战队员鞋子', '变装-Codex-重装特勤战靴', '重装特勤使用的高帮战术靴，软质踝部衔接胫甲。'),
    ('特勤警棍', '武器_刀_短兵.xml', '美式警棍', '刀-Codex-特勤警棍', '前治安官使用的加厚侧柄警棍。'),
    ('特勤霰弹枪', '武器_长枪_霰弹枪.xml', 'XM1014', '枪-长枪-Codex-特勤霰弹枪', '前治安官使用的 M1014 特勤型霰弹枪。'),
    ('特勤沙鹰', '武器_手枪_大威力手枪.xml', 'Desert Eagle改装版', '枪-手枪-Codex-特勤沙鹰', '采用深色表面处理的特勤型沙漠之鹰。'),
]

def append(path, element, key, value):
    raw = path.read_bytes()
    root = E.fromstring(raw)
    if any(e.findtext(key) == value for e in root):
        raise ValueError('Already registered; edit the existing item rather than reset its stats: ' + value)
    E.indent(element, space='  ')
    text = E.tostring(element, encoding='utf-8').strip()
    closing = ('</' + root.tag + '>').encode()
    assert raw.count(closing) == 1
    newline = b'\r\n' if b'\r\n' in raw else b'\n'
    text = text.replace(b'\n', newline)
    path.write_bytes(raw.replace(closing, b'  '+text+newline+closing))

def main():
    report = []
    for name, filename, donor, dressup, description in SPECS:
        path = ITEMS / filename
        root = E.parse(str(path)).getroot()
        donor_root = E.parse(str(ITEMS/'防具_0-19级.xml')).getroot() if filename == '防具_20-39级.xml' else root
        item = copy.deepcopy(next(e for e in donor_root if e.findtext('name') == donor))
        # No borrowed skill/lifecycle/set bonuses are silently installed.
        for child in list(item):
            if child.tag in ('skill', 'lifecycle', 'setId', 'equipskill') or (isinstance(child.tag, str) and child.tag.startswith('data_')):
                item.remove(child)
        item.find('name').text = name
        item.find('displayname').text = name
        item.find('icon').text = 'Codex-' + name
        item.find('description').text = description
        item.find('data/dressup').text = dressup
        if item.findtext('type') == '防具':
            item.find('data/level').text = '21'
            E.SubElement(item, 'setId').text = SET
        existing = next((e for e in root if e.findtext('name') == name), None)
        if existing is None:
            append(path, item, 'name', name)
        else:
            assert existing.findtext('data/dressup') == dressup
            item = existing  # A later balance edit must never be overwritten.
        report.append({'name': name, 'file': 'data/items/' + filename, 'placeholderFrom': donor,
                       'level': item.findtext('data/level'), 'dressup': dressup})
    sets = E.parse(str(ITEMS/'item_sets.xml')).getroot()
    setnode = E.Element('set')
    for key, value in [('id', SET), ('name', '重装特勤套装'), ('order', str(max(int(e.findtext('order')) for e in sets.findall('set'))+10))]:
        E.SubElement(setnode, key).text = value
    if not any(e.findtext('id') == SET for e in sets):
        append(ITEMS/'item_sets.xml', setnode, 'id', SET)
    hairs = E.parse(str(ITEMS/'hairstyle.xml')).getroot()
    existing_hair = next((e for e in hairs.findall('Hair') if e.findtext('Identifier') == '发型-男式-Codex-治安官'), None)
    hair_id = int(existing_hair.get('id')) if existing_hair is not None else max(int(e.get('id')) for e in hairs.findall('Hair'))+1
    hair = E.Element('Hair', id=str(hair_id))
    for key, value in [('Identifier', '发型-男式-Codex-治安官'), ('Name', '发型-男式-治安官短发'), ('Price', '0')]:
        E.SubElement(hair, key).text = value
    if existing_hair is None:
        append(ITEMS/'hairstyle.xml', hair, 'Identifier', '发型-男式-Codex-治安官')
    report = {'items': report, 'hairId': hair_id, 'hairIdentifier': '发型-男式-Codex-治安官',
              'deferred': ['final balance and price', 'shield transformation', 'cutting-blade mode', 'new skills and effects', 'acquisition sources'],
              'noInventoryGrant': True,
              'armorDesignBrief': {'status': 'stats_and_acquisition_pending', 'level': 21,
                'series': ['防暴', '特战', '重装特勤'], 'weightLayers': 2, 'priceLayers': 1,
                'budget': {'highPrice': 1, 'crafting': 1},
                'rule': 'tools/cf7-balance-tool/docs/armor-balance-rulebook.md',
                'note': '2026-10-08 用户指定定位；当前仅等级落地，属性与价格沿用特战占位，配方和购买入口未启用。正式标定时接入 armor-balance-plan.xml。'}}
    out = ROOT/'tools/former-sheriff-assets/registration.json'
    if out.exists():
        previous = json.loads(out.read_text('utf8'))
        previous_items = {i['name']: i for i in previous.get('items', [])}
        for item in report['items']:
            if 'artDonor' in previous_items.get(item['name'], {}):
                item['artDonor'] = item.pop('placeholderFrom')
        current_items = report['items']
        report.update(previous)  # Preserve later balance and feature decisions.
        report['items'] = current_items
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf8')
    print('Registered 8 independent items and hairstyle', hair_id)

if __name__ == '__main__':
    main()
