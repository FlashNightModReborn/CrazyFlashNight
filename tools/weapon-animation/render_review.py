"""从已发布 SWF 定位命名动画实例，导出真实帧并生成本地动作审阅页。"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import os
from pathlib import Path
import sys
import uuid
import xml.etree.ElementTree as ET

from PIL import Image, ImageOps
from xfl_recoil import ROOT, repo_path

sys.path.insert(0, str(ROOT / 'tools/asset-workbench'))
import core as workbench


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    profile = json.loads(repo_path(args.profile).read_text('utf-8-sig'))
    swf = repo_path(profile['swf'])
    output = repo_path(args.output_dir)
    if not output.is_relative_to((ROOT / 'tmp/weapon-animation').resolve()):
        raise ValueError('审阅输出只能写入 tmp/weapon-animation')
    output.mkdir(parents=True, exist_ok=True)
    # 每次导出到新子目录，避免读到中断或旧版本留下的帧，也不清理其他任务文件。
    raw = output / ('raw-' + uuid.uuid4().hex[:12])
    raw.mkdir()
    env, ffdec, environment = workbench.tool_environment()
    if not environment['ready']:
        raise ValueError('; '.join(environment['problems']))
    os.environ.update(env)  # 仅本次 CLI 进程及 FFDec 子进程。
    icons = workbench.module('bake-icons-offline')

    def run(arguments):
        result = icons.run_command([str(ffdec), *map(str, arguments)], ROOT, 120)
        with (output / 'export.log').open('a', encoding='utf-8') as stream:
            stream.write(result.stdout + '\n')
        if result.returncode:
            raise ValueError('FFDec 导出失败，见 export.log')

    xml = raw / 'published.xml'
    run(['-swf2xml', swf, xml])
    document = ET.parse(xml).getroot()
    exports = {}
    sprites = {}
    for element in document.iter():
        if element.get('type') == 'ExportAssetsTag':
            for name, character in zip(element.findall('./names/item'), element.findall('./tags/item')):
                exports[name.text] = int(character.text)
        if element.get('type') == 'DefineSpriteTag':
            sprites[int(element.get('spriteId'))] = element
    linkage = profile['runtime']['linkage']
    parent_id = exports[linkage]
    animation_id = parent_id
    mirror = False
    target = profile['runtime']['animationTarget']
    if target:
        matches = [item for item in sprites[parent_id].findall('./subTags/item')
                   if item.get('name') == target and item.get('placeFlagHasCharacter') == 'true']
        if len(matches) != 1:
            raise ValueError('发布 SWF 中命名动画实例不唯一或缺失')
        animation_id = int(matches[0].get('characterId'))
        matrix = matches[0].find('matrix')
        if matrix is not None:
            mirror = float(matrix.get('scaleX', '1')) < 0
    frame_count = int(sprites[animation_id].get('frameCount'))
    if frame_count != profile['frameCount']:
        raise ValueError('实际 SWF 动画帧数与 profile 不符')
    stops, cursor = [], 1
    for item in sprites[animation_id].findall('./subTags/item'):
        if item.get('type') == 'DoActionTag' and item.get('actionBytes') == '0700':
            stops.append(cursor)
        if item.get('type') == 'ShowFrameTag':
            cursor += 1
    if stops != [1, frame_count]:
        raise ValueError('实际 SWF 缺少待机/末帧 stop()')
    run(['-zoom', '2', '-format', 'sprite:png', '-selectid', animation_id, '-export', 'sprite', raw, swf])
    files = sorted(raw.rglob('*.png'), key=lambda path: int(path.stem))
    if len(files) != frame_count or [int(path.stem) for path in files] != list(range(1, frame_count + 1)):
        raise ValueError('实际 PNG 帧不完整')
    frames = [Image.open(path).convert('RGBA') for path in files]
    if any(frame.size != frames[0].size for frame in frames):
        raise ValueError('帧画布不一致，不能直接拼接动画')
    hashes = [hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames]
    if hashes[0] != hashes[profile['fireStartFrame'] - 1] or hashes[0] != hashes[-1] or len(set(hashes)) < 2:
        raise ValueError('待机/击发/回位不一致或动画未产生可见运动')

    # 图片均来自 FFDec；只做显示方向、背景与 GIF 编码，不修改原生美术源。
    display = []
    for frame in frames:
        if mirror:
            frame = ImageOps.mirror(frame)
        background = Image.new('RGBA', frame.size, '#dce3e7')
        background.alpha_composite(frame)
        background.thumbnail((1000, 500), Image.Resampling.LANCZOS)
        display.append(background.convert('RGB'))
    palette = display[0].quantize(colors=256)
    gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in display]
    durations = [650] + [int(round(100 * i / profile['fps']) * 10 - round(100 * (i - 1) / profile['fps']) * 10) for i in range(1, len(frames))]
    gif_frames[0].save(output / 'recoil.gif', save_all=True, append_images=gif_frames[1:], duration=durations, loop=0, disposal=2, optimize=False)
    display[0].save(output / 'idle.png')
    nominal_interval = profile.get('previewShotIntervalMs', frame_count * 1000 / profile['fps'] + 200)
    scheduled_frames = math.ceil(nominal_interval / (1000 / profile['fps']))
    scheduled_interval = scheduled_frames * 1000 / profile['fps']
    report = {'profile': args.profile, 'sourceSwf': profile['swf'], 'sourceSwfSha256': hashlib.sha256(swf.read_bytes()).hexdigest(),
              'linkage': linkage, 'parentCharacterId': parent_id, 'animationCharacterId': animation_id,
              'frameCount': frame_count, 'stopFrames': stops, 'uniqueRgbaFrames': len(set(hashes)),
              'frameRgbaSha256': hashes, 'width': frames[0].width, 'height': frames[0].height,
              'files': [path.relative_to(output).as_posix() for path in files], 'mirrorX': mirror,
              'nominalShotIntervalMs': nominal_interval, 'scheduledShotIntervalFrames': scheduled_frames,
              'scheduledShotIntervalMs': scheduled_interval,
              'scope': '实际 SWF 导出帧；审阅页不执行 AS2 生命周期，不等于游戏内体验验收'}
    (output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    data = {'frames': report['files'], 'labels': profile.get('phaseLabels', []), 'fps': profile['fps'],
            'fireStart': profile['fireStartFrame'], 'mirror': mirror,
            'nominalIntervalMs': nominal_interval, 'intervalMs': scheduled_interval}
    page = (Path(__file__).with_name('review.html')).read_text('utf-8')
    page = page.replace('__TITLE__', html.escape(profile['runtime']['item'])).replace('__DATA__', json.dumps(data, ensure_ascii=False).replace('<', '\\u003c'))
    (output / 'index.html').write_text(page, encoding='utf-8')
    print(json.dumps({'state': 'ready', 'frames': frame_count, 'uniqueFrames': len(set(hashes)), 'review': str(output / 'index.html'), 'gif': str(output / 'recoil.gif')}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
