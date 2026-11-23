"""Build the CF6 elite/instructor tactical motion timeline directly from authored Alter art."""
from pathlib import Path
import copy
import json
from lxml import etree as E
import art_revision

NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{'+NS['x']+'}'
ROOT = Path(__file__).resolve().parents[2]
PROFILE = Path(__file__).with_name('elite-motion-profile.json')
SIDEARM_ITEM = ROOT/'data/items/武器_手枪_大威力手枪.xml'
SIDEARM_ART = ROOT/'flashswf/arts/new/偷吃屑鱼坟头贡品/LIBRARY/枪-手枪-FR506.xml'
SIDEARM_HOLDER_SCALE = 0.2
RIFLE_HOLDER_SCALE = 0.8
PREFIX = 'Codex/特种兵/精英/'
LINKAGES = ('敌人-CF6特种精英', '敌人-CF6持盾特种精英')
TOTAL_FRAMES = 216


def input_paths():
    return [Path(__file__), Path(__file__).with_name('EliteAI.as'),
            PROFILE, SIDEARM_ITEM, SIDEARM_ART]


def load_profile():
    return json.loads(PROFILE.read_text(encoding='utf-8'))


def as2_literal(value):
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return '['+','.join(as2_literal(item) for item in value)+']'
    if isinstance(value, dict):
        return '{'+','.join(str(key)+':'+as2_literal(item) for key,item in value.items())+'}'
    raise TypeError(type(value))


def motion_frames():
    """Assemble 216 authored frames: f1-89 retreat, f90-180 charge+slide, f181 handoff, f182-216 rifle reload."""
    alter = art_revision.load_alter()['长枪点射与装填']['poses']
    standing_ready = art_revision.load()['长枪点射与装填'][0]
    poses = []

    # f1-89 (alter f61-149): dual-pistol backward retreat with rifle slung on back.
    # f1-14 and f76-89 skip waist-holster preview pistols because part 489 renders live holsters.
    for idx, raw in enumerate(alter[60:149]):
        local_f = idx + 1
        pose = {}
        for row in raw:
            part = row['part']
            if part.endswith('/可配置长枪'):
                pid = 'slungRifle'
            elif part.endswith('/教官_可配置副手枪'):
                if not (15 <= local_f <= 75):
                    continue
                if row['layer'] == '手枪1':
                    pid = 'primaryPistol'
                elif row['layer'] == '手枪2':
                    pid = 506
                else:
                    raise ValueError('Unexpected retreat pistol layer: ' + str(row['layer']))
            elif '/分件/' in part:
                pid = int(part.rsplit('/', 1)[-1])
            else:
                continue
            pose[str(row['depth'])] = {
                'id': pid,
                'matrix': row['matrix'],
                'firstFrame': 0,
                'colorMult': [v * 2.56 for v in row['colorMult']],
                'colorAdd': row['colorAdd'],
            }
        assert pose, f'Empty retreat pose at local frame {local_f}'
        poses.append(pose)

    # f90-180 (alter f151-241): forward sprint-shoot loop (f100-124) + low slide with smoke17 & 速度线 + stand-up.
    # Skip 489-parented waist preview pistols; 489 owns live holsters.
    for idx, raw in enumerate(alter[150:241]):
        local_f = 90 + idx
        pose = {}
        for row in raw:
            part = row['part']
            if part.endswith('/教官_可配置副手枪'):
                continue
            elif part.endswith('/可配置长枪'):
                pid = 492
                first_frame = 0
            elif part == 'smoke17':
                pid = 'smoke17'
                first_frame = int(row.get('firstFrame', 0))
            elif part == '速度线':
                pid = 'speedLines'
                first_frame = 0
            elif '/分件/' in part:
                pid = int(part.rsplit('/', 1)[-1])
                first_frame = 0
            else:
                continue
            pose[str(row['depth'])] = {
                'id': pid,
                'matrix': row['matrix'],
                'firstFrame': first_frame,
                'colorMult': [v * 2.56 for v in row['colorMult']],
                'colorAdd': row['colorAdd'],
            }
        assert pose, f'Empty slide pose at local frame {local_f}'
        poses.append(pose)

    # f181 (run-to-stand handoff) + f182-216 (35-frame standard standing rifle reload).
    for _ in range(36):
        pose = {}
        for depth, row in standing_ready.items():
            pose[depth] = {
                'id': row['id'],
                'matrix': list(row['matrix']),
                'firstFrame': 0,
                'colorMult': list(row.get('colorMult', [256] * 4)),
                'colorAdd': list(row.get('colorAdd', [0] * 4)),
            }
        poses.append(pose)

    assert len(poses) == TOTAL_FRAMES, len(poses)
    return poses


retarget_frames = motion_frames


def install(symbols, native, base_prefix, ordinary, shield):
    name = PREFIX+'动作/CF6战术长枪'
    pistol_name = PREFIX+'武器/可配置主手枪'
    sidearm_name = PREFIX+'武器/可配置副手枪'
    slung_name = PREFIX+'武器/背负长枪'
    mount = base_prefix+'武器/长枪挂点'

    for symbol, slot in ((pistol_name, '手枪'), (sidearm_name, '手枪2')):
        script = ('onClipEvent(load){var unit:MovieClip=_parent._parent._parent;'
                  '_root.装备引用配置.配置装扮(this,unit.'+slot+'_装扮,"装扮","'+slot+'_引用");}')
        symbols[symbol] = native.symbol(symbol, [native.layer('标准手枪引用', [native.frame(
            script='stop();', elements=[native.instance(mount, symbol_type='movie clip', name='枪',
                matrix=(SIDEARM_HOLDER_SCALE, 0, 0, SIDEARM_HOLDER_SCALE, 0, 0), script=script)])])],
            symbol_type='movie clip')

    # Read-only back-mounted rifle visual during retreat so man.枪 stays exclusive to primaryPistol.
    slung_script = ('onClipEvent(load){var unit:MovieClip=_parent._parent._parent;'
                    '_root.装备引用配置.配置装扮(this,unit.长枪_装扮,"装扮","长枪_背负_引用");}')
    symbols[slung_name] = native.symbol(slung_name, [native.layer('背负长枪引用', [native.frame(
        script='stop();', elements=[native.instance(mount, symbol_type='movie clip', name='枪',
            matrix=(RIFLE_HOLDER_SCALE, 0, 0, RIFLE_HOLDER_SCALE, 0, 0), script=slung_script)])])],
        symbol_type='movie clip')

    poses = motion_frames()
    layers = []
    for depth in sorted({int(value) for pose in poses for value in pose}, reverse=True):
        frames = []
        start = 0
        while start < len(poses):
            row = poses[start].get(str(depth))
            end = start + 1
            while end < len(poses) and poses[end].get(str(depth)) == row:
                end += 1
            elements = []
            if row is not None:
                pid = row['id']
                if pid == 492:
                    part = base_prefix+'武器/可配置长枪'; instance_name = '枪'
                elif pid == 'slungRifle':
                    part = slung_name; instance_name = '背枪'
                elif pid == 'primaryPistol':
                    part = pistol_name; instance_name = '枪'
                elif pid == 506:
                    part = sidearm_name; instance_name = '枪2'
                elif pid == 'smoke17':
                    part = base_prefix+'特效/smoke17'; instance_name = None
                elif pid == 'speedLines':
                    part = base_prefix+'特效/速度线'; instance_name = None
                elif pid == 489:
                    part = base_prefix+'分件/489'; instance_name = '腰挂'
                elif pid == 484:
                    part = base_prefix+'装备/腿挂匕首'; instance_name = '腿挂匕首'
                else:
                    part = base_prefix+'分件/'+str(pid); instance_name = None
                options = {'symbol_type': 'movie clip'} if (instance_name or pid == 'speedLines') else {}
                if pid == 484:
                    options['script'] = 'onClipEvent(load){_visible=_parent._parent.soldierIsInstructor===true;}'
                if instance_name:
                    options['name'] = instance_name
                inst = native.instance(part, matrix=row['matrix'], **options)
                if pid == 'speedLines':
                    E.SubElement(E.SubElement(inst, N+'filters'), N+'BlurFilter', blurX='50', blurY='0')
                if inst.get('symbolType') == 'graphic':
                    inst.set('loop', 'single frame')
                    inst.set('firstFrame', str(row.get('firstFrame', 0)))
                mult, add = row.get('colorMult', [256]*4), row.get('colorAdd', [0]*4)
                if mult != [256]*4 or add != [0]*4:
                    color = E.SubElement(E.SubElement(inst, N+'color'), N+'Color')
                    for ci, channel in enumerate(('red', 'green', 'blue', 'alpha')):
                        color.set(channel+'Multiplier', native.num(mult[ci]/256))
                        color.set(channel+'Offset', native.num(add[ci]))
                elements = [inst]
            frames.append(native.frame(start, end-start, elements))
            start = end
        layers.append(native.layer('CF6分件_'+str(depth), frames))

    lifecycle = {
        0: {'script': 'stop();_parent.eliteBeginAttack(this);'},
        27: {'name': '后撤循环开始', 'label_type': 'name'},
        50: {'name': '后撤循环结束', 'label_type': 'name'},
        89: {'name': '冲锋滑铲', 'label_type': 'name'},
        99: {'name': '冲锋循环开始', 'label_type': 'name'},
        123: {'name': '冲锋循环结束', 'label_type': 'name'},
        180: {'name': '停步射击', 'label_type': 'name'},
        181: {'name': '换弹匣', 'label_type': 'name', 'script': '_parent.eliteReloadStart(this);'},
        201: {'script': '_parent.eliteReloadGate(this);'},
        213: {'script': '_parent.eliteReloadCommit(this);'},
        215: {'script': '_parent.eliteReloadEnd(this);'},
    }
    permission = native.instance(mount, symbol_type='movie clip', name='射击许可标签')
    symbols[name] = native.symbol(name, [
        native.make_sparse_layer('标准生命周期', TOTAL_FRAMES, lifecycle),
        native.make_sparse_layer('标准射击许可', TOTAL_FRAMES, {0: {'duration': 181, 'elements': [permission]}}),
        *layers,
    ], symbol_type='movie clip')

    elite_source = ('var eliteMotionConfig:Object = '+as2_literal(load_profile())+';\n'
                    + Path(__file__).with_name('EliteAI.as').read_text(encoding='utf-8-sig'))
    for original, link in zip((ordinary, shield), LINKAGES):
        full = base_prefix+link
        root = native.symbol(full, copy.deepcopy(list(symbols[base_prefix+original].find('x:timeline/x:DOMTimeline/x:layers', NS))),
                             symbol_type='movie clip', linkage=link, export_first_frame=True)
        root.find('x:timeline/x:DOMTimeline', NS).set('name', link)
        script = root.find('.//x:DOMLayer[@name="初始化与消失"]//x:script', NS)
        script.text = script.text.replace('初始化敌人模板=_root.初始化敌人模板;',
            'if(手枪==undefined)手枪="FR506";if(手枪2==undefined)手枪2="FR506";\n'
            '_root.主角函数.初始化掉落物.call(this);\n'
            '初始化敌人模板=_root.初始化敌人模板;')
        script.text = E.CDATA(script.text.replace('soldierInitializePhase();', elite_source+'\nsoldierInitializePhase();eliteInitialize();'))
        body = root.find('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame[@index="41"]/x:elements/x:DOMSymbolInstance', NS)
        body.set('libraryItemName', name)
        symbols[full] = root
    return {
        'linkages': list(LINKAGES),
        'motionSource': 'CF6特种兵-美术Alter native Animate 2024 samples; no 3XF retargeting',
        'importedDonorArtSymbols': 0,
        'legacyScriptsImported': 0,
        'actions': ['retreat', 'run', 'slide'],
        'panelAuthority': '466/467 inherited panel; explicit toughness exception in elite-tuning.json',
        'hitboxAuthority': 'unchanged CF6 receiver',
        'extraWeapons': {'secondary': 'FR506', 'secondary2': 'FR506', 'externalSlots': ['手枪', '手枪2'], 'actions': ['retreat']},
        'grenades': 'cooldown-gated charge slide',
        'extraArmor': False,
    }
