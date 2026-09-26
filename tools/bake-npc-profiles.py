#!/usr/bin/env python3
"""从已核对的共享肖像生成缺失 NPC 小头像；不重写既有手工头像。

随玩家性别换图的角色（见 GENDER_VARIANT_NAMES）不在此派生——它们没有单一同名头像，
只由覆盖门按「变体两图齐」判定。
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, __version__ as PILLOW_VERSION

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / 'tools/npc-profiles/sources.json'
OUTPUT = ROOT / 'flashswf/portraits/profiles'

# 随玩家性别换图的角色：没有单一同名头像文件，只有两个性别变体（变体图由美术另行
# 提供，本工具不生成、只登记覆盖口径）。消费端本轮不做性别路由，认不出同名图时走
# 各自既有兜底（web → 无头像.png / C# → 名字首字 / AS2 任务栏 → 留空）。
# 覆盖门（任务/地图登记人物都必须有头像）对这些名字按「变体两图齐」判定，而不是
# 找 室友.png —— 该合成图已退役（两人叠在一张头像上，2026-09-26 删除）。
GENDER_VARIANT_NAMES = {
    '室友': ('男室友', '女室友'),
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def resolve_source(source: dict) -> Path:
    path = (ROOT / source['path']).resolve()
    if not path.is_relative_to(ROOT) or not path.is_file():
        raise ValueError('头像源必须是项目内的既有文件: ' + source['path'])
    if digest(path.read_bytes()) != source['sha256']:
        raise ValueError('头像源已变化，请先复核构图: ' + source['path'])
    return path


def render(entry: dict, size: int) -> bytes:
    sources = [resolve_source(s) for s in entry['sources']]
    if entry['mode'] == 'copy':
        return sources[0].read_bytes()
    canvas = Image.new('RGBA', (size, size))
    if entry['mode'] == 'paired-role':
        if len(sources) != 2:
            raise ValueError('组合角色头像必须有两个明确来源')
        for index, path in enumerate(sources):
            with Image.open(path) as raw:
                face = raw.convert('RGBA').resize((280, 280), Image.Resampling.LANCZOS)
            canvas.alpha_composite(face, (index * 120, index * 120))
    elif entry['mode'] == 'crop':
        with Image.open(sources[0]) as raw:
            image = raw.convert('RGBA')
        x0, y0, x1, y1 = entry['sources'][0]['crop']
        if not (0 <= x0 < x1 <= image.width and 0 <= y0 < y1 <= image.height):
            raise ValueError('头像裁图超出真实源范围: ' + entry['name'])
        image = image.crop((x0, y0, x1, y1))
        if image.getbbox() is None:
            raise ValueError('拒绝空白头像: ' + entry['name'])
        image.thumbnail((size - 16, size - 16), Image.Resampling.LANCZOS)
        # 小尺寸源也按同一画布布局；metadata 保留实际源裁图分辨率。
        factor = min((size - 16) / image.width, (size - 16) / image.height)
        target = (round(image.width * factor), round(image.height * factor))
        image = image.resize(target, Image.Resampling.LANCZOS)
        canvas.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
    else:
        raise ValueError('不支持的头像派生模式: ' + entry['mode'])
    output = io.BytesIO()
    canvas.save(output, format='PNG', optimize=True)
    return output.getvalue()


def coverage(directory: Path) -> dict:
    tasks = []
    for file in ET.parse(ROOT / 'data/task/list.xml').getroot():
        tasks.extend(json.loads((ROOT / 'data/task' / file.text).read_text(encoding='utf-8-sig'))['tasks'])
    definition = json.loads((ROOT / 'data/map/map_definition.json').read_text(encoding='utf-8-sig'))
    task_names = {t['finish_npc'] for t in tasks if t.get('finish_npc')}
    map_names = {n['label'] for n in definition['npcs'].values()}
    files = {p.stem.casefold(): p for p in OUTPUT.glob('*.png')}
    files.update({p.stem.casefold(): p for p in directory.glob('*.png')})
    missing, blank = [], []
    for name in sorted(task_names | map_names):
        variants = GENDER_VARIANT_NAMES.get(name)
        if variants:
            # 性别变体角色：两个变体文件齐 = 覆盖（缺任一张按缺图报，报出变体名便于定位）。
            paths = [files.get(variant.casefold()) for variant in variants]
            absent = [variant for variant, path in zip(variants, paths) if path is None]
            if absent:
                missing.append(name + '（缺 ' + '/'.join(absent) + '）')
                continue
        else:
            path = files.get(name.casefold())
            if path is None:
                missing.append(name)
                continue
            paths = [path]
        for path in paths:
            with Image.open(path) as raw:
                if raw.convert('RGBA').getbbox() is None:
                    blank.append(path.stem)
    return {'taskDefinitions': len(tasks), 'taskNpcNames': len(task_names),
            'mapNpcNames': len(map_names), 'missing': missing, 'blank': blank,
            'scope': '静态注册人物覆盖，不代表当前剧情可达或头像人验通过'}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='只重建比较，不写文件')
    parser.add_argument('--output-dir', type=Path, default=OUTPUT)
    args = parser.parse_args()
    spec = json.loads(SPEC.read_text(encoding='utf-8-sig'))
    assert spec['schema'] == 'cf7-npc-profile-sources-v1' and spec['size'] == 400
    names = [entry['name'] for entry in spec['entries']]
    assert len(names) == len({name.casefold() for name in names})
    assert all(name and not any(c in name for c in '/\\:*?"<>|') and name not in ('.', '..') for name in names)
    output_dir = args.output_dir.resolve()
    previous = output_dir / 'generated-manifest.json'
    owned = set()
    if previous.exists():
        owned = {e['name'] for e in json.loads(previous.read_text(encoding='utf-8'))['entries']}
    prepared = []
    for entry in spec['entries']:
        data = render(entry, spec['size'])
        with Image.open(io.BytesIO(data)) as image:
            assert image.size == (400, 400) and image.convert('RGBA').getbbox() is not None
        assert len(data) <= 512 * 1024
        path = output_dir / (entry['name'] + '.png')
        if not args.check and path.exists() and entry['name'] not in owned:
            raise ValueError('拒绝覆盖未归本生成器维护的头像: ' + str(path))
        prepared.append((path, data, {'name': entry['name'], 'uri': path.name,
                                     'sha256': digest(data), 'bytes': len(data),
                                     'mode': entry['mode'], 'sources': entry['sources'], 'note': entry['note']}))
    total = sum(len(data) for _, data, _ in prepared)
    assert total <= 8 * 1024 * 1024
    manifest = {'schema': 'cf7-generated-npc-profiles-v1', 'size': 400, 'pillow': PILLOW_VERSION,
                'generatorSha256': digest(Path(__file__).read_bytes()),
                'recipeSha256': digest(SPEC.read_bytes()), 'totalBytes': total,
                'entries': [entry for _, _, entry in prepared]}
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if args.check:
        for path, data, _ in prepared:
            if not path.exists() or path.read_bytes() != data:
                raise ValueError('头像缺失或与配方不符: ' + str(path))
        if not previous.exists() or previous.read_bytes() != manifest_bytes:
            raise ValueError('头像 manifest 与当前来源/生成器环境不符')
    else:
        output_dir.mkdir(parents=True, exist_ok=True)
        for path, data, _ in prepared:
            path.write_bytes(data)
        previous.write_bytes(manifest_bytes)
    result = coverage(output_dir)
    assert not result['missing'] and not result['blank'], result
    print(json.dumps({'success': True, 'check': args.check, 'generated': len(prepared),
                      'bytes': total, 'coverage': result}, ensure_ascii=False))


if __name__ == '__main__':
    main()
