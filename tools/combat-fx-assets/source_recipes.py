"""Reviewed, finite Flash adapters; source scripts are classified, never executed."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NS = '{http://ns.adobe.com/xfl/2008/}'
SOURCE_LIBRARIES = (
    {'key': 'stock', 'swf': 'flashswf/arts/原版素材库-子弹.swf',
     'libraryRoot': 'flashswf/arts/原版素材库-子弹/LIBRARY'},
    {'key': 'mist', 'swf': 'flashswf/arts/new/雾人整合特效.swf',
     'libraryRoot': 'flashswf/arts/new/雾人整合特效/LIBRARY'},
    {'key': 'fs', 'swf': 'flashswf/arts/new/fs配置素材.swf',
     'libraryRoot': 'flashswf/arts/new/fs配置素材/LIBRARY'},
)
LEGACY_MUZZLES = ('冲锋枪枪火', '反器材枪火', '发射器枪火', '巴雷特枪火', '战斗步枪枪火',
                  '枪火', '突击步枪枪火', '紧凑手枪枪火', '霰弹枪枪火', '马格南手枪枪火')
MUZZLES = LEGACY_MUZZLES + ('铁枪能量弹枪火',)
IMPACTS = ('火花', '击中金属', '无声火花', '拼刀火花', '战术巴雷特击中特效', '铁枪能量弹火花', '屎花')
EXTRA_STYLES = (
    ('mist', '1.特效文件夹/14.远程子弹/冰汽/冰汽', 'impact', 'sequence'),
    ('mist', '1.特效文件夹/14.远程子弹/烈焰火花/烈焰火花', 'impact', 'sequence'),
    ('mist', '1.特效文件夹/14.远程子弹/能量火花/能量火花', 'impact', 'sequence'),
    ('stock', '特效-击中效果组/空手攻击火花', 'impact', 'nested-spin'),
    ('fs', '长枪/铁枪/铁枪能量弹枪火', 'muzzle', 'sequence'),
    ('stock', '特效-血液组/飙血', 'impact', 'blood-impact'),
    ('stock', '特效-血液组/子弹碎片-飞血', 'blood', 'blood-static'),
)
REMOVALS = {'this.removeMovieClip();', 'stop();this.removeMovieClip();', 'this.removeMovieClip();stop();'}
METADATA_KEYS = ('sourceKey', 'sourceSymbol', 'adapter', 'variantSounds', 'soundAtBirth', 'nestedTransform',
                 'sourceNestedTransform', 'randomRotation', 'unitScaleXOnly')
BLOOD_CUES = ('blood1.mp3', 'blood2.wav', 'blood3.mp3', 'blood4.mp3',
              'blood5.wav', 'blood6.wav', 'blood7.wav')
# XFL sound item names are not runtime SFX ids. Bind their published SWF ids explicitly.
# All twenty reviewed event sounds start on their selected variant's first frame.
TIMELINE_SOUNDS = {
    '火花': ((1, 'sound298.mp3', 13), (30, 'sound303.mp3', 12),
             (43, 'sound309.mp3', 11), (57, 'sound315.mp3', 10), (82, 'sound321.mp3', 9)),
    '击中金属': ((1, 'sound645.wav', 8), (30, 'sound646.wav', 7),
                 (43, 'sound647.wav', 6), (57, 'sound648.wav', 5)),
    '拼刀火花': ((1, 'sound697.mp3', 530), (30, 'sound698.wav', 531),
                 (43, 'sound699.wav', 532), (57, 'sound700.wav', 533),
                 (82, 'sound701.wav', 534), (100, 'sound702.wav', 535)),
    '战术巴雷特击中特效': ((0, 'sound728.mp3', 454),),
    '屎花': ((1, 'sound376.wav', 4), (30, 'sound369.wav', 3),
             (43, 'sound341.wav', 2), (57, 'sound352.wav', 1)),
}
# A changed outer motion/RNG script must be reviewed with the AS2/native adapter.
BLOOD_OUTER_SCRIPTS_SHA256 = 'adc4a3906acbde94749846de85d698bb29bd77e5d3886ee923fd2c6f64afd62d'


def script_rows(root):
    return [(int(f.get('index', '0')), re.sub(r'\s+', '', ''.join(s.itertext())))
            for f in root.iter(NS + 'DOMFrame') for s in f.iter(NS + 'script')]


def sound_rows(root):
    return [(int(f.get('index', '0')),
             {k: v for k, v in f.attrib.items() if k.lower().startswith('sound')},
             [point.attrib for point in f.iter(NS + 'SoundEnvelopePoint')])
            for f in root.iter(NS + 'DOMFrame')
            if any(k.lower().startswith('sound') for k in f.attrib)
            or any(True for _ in f.iter(NS + 'SoundEnvelope'))]


def timeline_cues(root, name, variants):
    expected = []
    reviewed = TIMELINE_SOUNDS.get(name, ())
    for frame, item, _ in reviewed:
        attrs = {'soundName': '3.音效相关/' + item}
        if name == '火花': attrs['soundEffect'] = 'custom'
        level = '32769' if name == '火花' else '32768'
        expected.append((frame, attrs, [{'level0': level, 'level1': level}]))
    if sound_rows(root) != expected:
        raise ValueError('Unreviewed timeline sound: ' + name)
    if not reviewed: return []
    by_frame = {frame: 'cfnfx-stock-' + str(sound_id) + '.wav' for frame, _, sound_id in reviewed}
    # A common frame-zero cue applies to every selected variant. No delayed events
    # are silently folded into a birth cue.
    cues = [by_frame.get(v[0], by_frame.get(0)) for v in variants]
    if any(cue is None for cue in cues) or any(frame != 0 and frame not in {v[0] for v in variants}
                                              for frame in by_frame):
        raise ValueError('Timeline sound is not at variant birth: ' + name)
    return cues


def sequence(root, adapter):
    scripts = script_rows(root)
    labels = {f.get('name'): int(f.get('index', '0')) for f in root.iter(NS + 'DOMFrame') if f.get('name')}
    sounds = {}
    if adapter == 'blood-impact':
        remaining = []
        for index, text in scripts:
            cue = re.fullmatch(r'\{_root\.播放音效\("(blood[1-7]\.wav)"\);\}', text)
            if cue:
                if index in sounds: raise ValueError('Duplicate blood sound event')
                sounds[index] = cue.group(1)
            else: remaining.append((index, text))
        scripts = remaining
    removals = sorted({i for i, text in scripts if text in REMOVALS})
    skip_zero = False
    if any('random(' in text for _, text in scripts):
        selectors = [(i, text) for i, text in scripts if text not in REMOVALS]
        if len(selectors) != 1 or selectors[0][0] != 0:
            raise ValueError('Unknown random animation selector')
        selector = selectors[0][1]
        guard = 'if(this._y==0){this.removeMovieClip();}'
        if selector.startswith(guard):
            skip_zero = True; selector = selector[len(guard):]
        selected = (re.fullmatch(r'gotoAndPlay\("a"\+random\(([1-8])\)\);', selector)
                    or re.fullmatch(r'vara="a"\+random\(([1-8])\);gotoAndPlay\(a\);', selector))
        if selected is None: raise ValueError('Unknown random animation script')
        variants = []
        starts = [labels['a' + str(i)] for i in range(int(selected.group(1)))]
        for begin in starts:
            finish = min(i for i in removals if i > begin)
            variants.append(list(range(begin, finish)))
    else:
        if not removals or any(text not in REMOVALS for _, text in scripts):
            raise ValueError('Unknown effect behavior')
        starts = [0]; variants = [list(range(min(removals)))]
    if any(not v or len(v) > 60 for v in variants): raise ValueError('Invalid animation duration')
    variant_sounds = []
    if adapter == 'blood-impact':
        source_sounds = [sounds.get(start) for start in starts]
        if source_sounds != ['blood' + str(i) + '.wav' for i in range(1, 8)] or len(sounds) != 7:
            raise ValueError('Blood sound events must match their variant birth frames')
        variant_sounds = list(BLOOD_CUES)
    return variants, skip_zero, variant_sounds


def nested_instance(root, name):
    found = [node for node in root.iter(NS + 'DOMSymbolInstance') if node.get('name') == name]
    if len(found) != 1: raise ValueError('Expected one named visual child: ' + name)
    return found[0]


def recipe():
    files = set()
    roots_by_key = {s['key']: ROOT / s['libraryRoot'] for s in SOURCE_LIBRARIES}
    approved_scripts = set()
    approved_sounds = set()
    def read(path, library):
        path = path.resolve()
        if not path.is_relative_to(library.resolve()) or not path.is_file():
            raise ValueError('Missing or escaping source symbol: ' + str(path))
        root = ET.parse(path).getroot()
        if path not in files:
            files.add(path)
            for node in root.iter(NS + 'DOMSymbolInstance'):
                read(library / (node.get('libraryItemName') + '.xml'), library)
        return root
    stock = roots_by_key['stock']
    shells = sorted((stock / '弹壳').glob('*.xml'))
    if len(shells) != 18: raise ValueError('Review casing whitelist when its source set changes')
    entries = [('stock', p.relative_to(stock).with_suffix('').as_posix(), 'casing', 'static') for p in shells]
    entries += [('stock', '特效-枪火组/' + n, 'muzzle', 'sequence') for n in LEGACY_MUZZLES]
    entries += [('stock', '特效-击中效果组/' + n, 'impact', 'sequence') for n in IMPACTS]
    entries += list(EXTRA_STYLES)
    plans = []
    for key, symbol, kind, adapter in entries:
        library = roots_by_key[key]; path = library / (symbol + '.xml')
        root = read(path, library)
        name = root.get('linkageIdentifier')
        if root.get('linkageExportForAS') != 'true' or not name:
            raise ValueError('Source has no AS linkage: ' + str(path))
        approved_scripts.add(path.resolve())
        extra = {}
        if kind == 'casing':
            if script_rows(root) or any(int(f.get('index', '0')) or int(f.get('duration', '1')) != 1
                                       for f in root.iter(NS + 'DOMFrame')):
                raise ValueError('Casing is not static: ' + name)
            variants, skip_zero, sounds = [[0]], False, []
        elif adapter == 'blood-static':
            stamp = hashlib.sha256(json.dumps(script_rows(root), ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
            if stamp != BLOOD_OUTER_SCRIPTS_SHA256: raise ValueError('Unreviewed ordinary-blood motion script')
            instance = nested_instance(root, '飞血'); symbol = instance.get('libraryItemName')
            child = read(library / (symbol + '.xml'), library)
            if script_rows(child) or {int(f.get('index', '0')) for f in child.iter(NS + 'DOMFrame')} != set(range(5)):
                raise ValueError('Ordinary blood must have exactly five static frames')
            variants, skip_zero, sounds = [[i] for i in range(5)], False, []
            extra.update(renderChild='飞血', renderMode='child')
        elif adapter == 'nested-spin':
            expected = [(0, 'if(this._y==0){this.removeMovieClip();}this.火花.gotoAndPlay(1);'),
                        (3, 'stop();this.removeMovieClip();'),
                        (0, 'onClipEvent(load){this._rotation=random(360);}')]
            if script_rows(root) != expected: raise ValueError('Unreviewed unarmed outer behavior')
            instance = nested_instance(root, '火花'); symbol = instance.get('libraryItemName')
            child_path = library / (symbol + '.xml'); child = read(child_path, library)
            if script_rows(child) != [(3, 'stop();')]: raise ValueError('Unreviewed unarmed child behavior')
            approved_scripts.add(child_path.resolve())
            matrix = instance.find('.//' + NS + 'Matrix')
            transform = [float(matrix.get(k, default)) for k, default in
                         (('a', '1'), ('b', '0'), ('c', '0'), ('d', '1'), ('tx', '0'), ('ty', '0'))]
            if transform[:4] != [0.284439086914063, 0, 0, 0.284439086914063]:
                raise ValueError('Unreviewed unarmed nested matrix')
            filters = list(instance.iter(NS + 'GlowFilter'))
            if len(filters) != 1 or filters[0].attrib != {'color': '#FFFFCC'}:
                raise ValueError('Unreviewed unarmed filter')
            variants, skip_zero, sounds = [[0, 1, 2]], True, []
            extra.update(renderChild='火花', renderMode='nested-scaled', nestedTransform=[1, 0, 0, 1] + transform[4:],
                         sourceNestedTransform=transform, randomRotation=True, unitScaleXOnly=True)
        else:
            variants, skip_zero, sounds = sequence(root, adapter)
        timeline = timeline_cues(root, name, variants)
        if timeline:
            if sounds: raise ValueError('Multiple audio routes need explicit adaptation: ' + name)
            sounds = timeline; approved_sounds.add(path.resolve())
        plan = {'index': len(plans), 'linkage': name, 'kind': kind, 'variants': variants,
                'skipOriginYZero': skip_zero, 'worldLit': kind in ('casing', 'blood') or name in ('屎花', '飙血'),
                'sourceKey': key, 'sourceSymbol': symbol, 'adapter': adapter, 'variantSounds': sounds,
                'soundAtBirth': bool(sounds),
                'renderLinkage': name, 'renderChild': '', 'renderMode': 'legacy'}
        if name == '冰汽': plan['renderMode'] = 'padded'
        plan.update(extra); plans.append(plan)
    for path in files - approved_scripts:
        if any(True for _ in ET.parse(path).getroot().iter(NS + 'script')):
            raise ValueError('Nested behavior needs explicit adaptation: ' + str(path))
    for path in files - approved_sounds:
        if sound_rows(ET.parse(path).getroot()):
            raise ValueError('Nested sound needs explicit adaptation: ' + str(path))
    # The media table names each authored sound item, including seven items with
    # no AS linkage. The audio itself is always decoded from the published SWF.
    media_path = stock.parent / 'DOMDocument.xml'
    items = [n.get('name') for n in ET.parse(media_path).getroot().iter(NS + 'DOMSoundItem')]
    for rows in TIMELINE_SOUNDS.values():
        for _, item, _ in rows:
            if items.count('3.音效相关/' + item) != 1:
                raise ValueError('Missing or duplicate authored sound item: ' + item)
    return plans, sorted(files | {media_path.resolve()})
