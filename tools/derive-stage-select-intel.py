"""Derive read-only stage intelligence from registered stages and unit definitions."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'launcher/web/modules/stage-select/stage-select-intel-data.js'


def generate():
    inputs = {}
    def read(path):
        raw = path.read_bytes()
        inputs[path.relative_to(ROOT).as_posix()] = hashlib.sha256(raw).hexdigest()
        return raw
    units = {str(u['id']): u for u in json.loads(read(ROOT / 'data/units/units.json'))}
    properties = {}
    enemy_root = ROOT / 'data/enemy_properties'
    for item in ET.fromstring(read(enemy_root / 'list.xml')).findall('items'):
        for node in ET.fromstring(read(enemy_root / item.text)):
            properties[node.tag] = node.findtext('displayname') or node.tag.removeprefix('敌人-')
    stages = {}
    for index in sorted((ROOT / 'data/stages').glob('*/__list__.xml')):
        for info in ET.fromstring(read(index)).findall('StageInfo'):
            name = info.findtext('Name')
            source = index.parent / ((name or '') + '.xml')
            if not name or not source.is_file():
                continue
            tree = ET.fromstring(read(source))
            if tree.tag != 'GameStage':
                continue
            if name in stages:
                raise ValueError('Duplicate registered stage: ' + name)
            rewards = []
            for reward in tree.findall('./Rewards/Reward'):
                item = reward.findtext('Name')
                if item and item not in rewards:
                    rewards.append(item)
            enemies = {}
            # 只公开固定波次的敌对单位，不递归扫描剧情、事件或条件分支里的秘密出场。
            for enemy in tree.findall('./SubStage/Wave/SubWave/EnemyGroup/Enemy'):
                key = enemy.findtext('Type') or ''
                match = re.fullmatch(r'兵种(\d+)', key)
                unit = units.get(match.group(1)) if match else None
                if not unit or unit.get('is_hostile') is not True:
                    continue
                # 自定义属性可能改变身份/阵营，不把模板名当作该实例的情报。
                if enemy.find('Attribute') is not None or enemy.find('CaseSwitch') is not None:
                    continue
                sprite = unit.get('spritename', '')
                label = properties.get(sprite) or unit.get('name')
                if label:
                    enemies[sprite] = dict(name=label, portraitRef=sprite)
            stages[name] = dict(rewards=rewards, enemies=sorted(enemies.values(), key=lambda e: e['name']))
    data = dict(version=1, sourceHash=hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest(), stages=stages)
    return ('// 由 tools/derive-stage-select-intel.py 生成；玩家可见性由真实通关记录裁决。\n'
            'var StageSelectIntelData = ' + json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';\n').encode()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = generate()
    if args.check:
        assert OUTPUT.read_bytes() == data, 'Stage intelligence catalog is stale'
    else:
        OUTPUT.write_bytes(data)
    print(json.dumps(dict(ok=True, bytes=len(data))))
