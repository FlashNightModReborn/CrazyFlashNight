"""Project the two instructor-authored attacks into the existing combat timelines."""
from pathlib import Path

from lxml import etree as E

import instructor_melee_source as source


KNIFE = '匕首刺击'
SHIELD = '持盾匕首刺击'
KNIFE_IMPACT = 14
BASH_IMPACT = 17

# Local drawing coordinates on the R9 knife blade (below its guard) and the
# striking corner of the shield. Project these through the authored contact
# pose so moving the hand or shield in the editable source also moves its hit.
BLADE = ((-7.55, 34.2), (9.45, 36.2), (9.6, 44.2), (-2.55, 189.2))
SHIELD_RIM = ((-9.95, 47.05), (17.5, 44.55), (20, 43.55), (21.7, 42.2),
              (24.6, 38.3), (26.9, 19.8))

# The artist's bare timeline uses the original Flash layer numbers. Keep
# their order, but show the anatomical role on the generated CS6 timeline.
KNIFE_LAYER_NAMES = {
    '原始深度_26': '右下臂', '原始深度_25': '右手', '原始深度_24': '右上臂',
    '原始深度_22': '长枪', '原始深度_21': '右小腿', '原始深度_20': '右脚',
    '原始深度_19': '左小腿', '原始深度_18': '左脚', '原始深度_17': '右大腿',
    '原始深度_16': '腰胯', '原始深度_15': '头', '原始深度_14': '身体',
    '原始深度_11': '左下臂', '原始深度_10': '左手', '原始深度_3': '左上臂',
    '原始深度_2': '左大腿及拔刀变体', '原始深度_1': '军刺',
}


def input_paths():
    return [Path(__file__), *source.input_paths()]


def contact(b, pose, part_id, outline, callback):
    placements = [row for row in pose.values() if row['id'] == part_id]
    if len(placements) != 1:
        raise ValueError(f'Expected one contact part {part_id}, found {len(placements)}')
    xx, yx, xy, yy, tx, ty = placements[0]['matrix']
    xs = [xx*x + xy*y + tx for x, y in outline]
    ys = [yx*x + yy*y + ty for x, y in outline]
    left, right, top, bottom = min(xs), max(xs), min(ys), max(ys)
    # Symbol 195 owns a centered 25x25 "area" consumed by the melee queue.
    matrix = ((right-left)/25, 0, 0, (bottom-top)/25, (left+right)/2, (top+bottom)/2)
    return b.native.instance(b.H['Symbol 195'], matrix=matrix, symbol_type='movie clip',
        name='攻击点', alpha_mult=0,
        script='onClipEvent(load){_parent._parent.'+callback+'(_parent,this);}')


def install(b, symbols, prefix, parts):
    poses = source.load_poses()
    names = source.layer_names()
    native = b.native
    knife, bash = poses[KNIFE], poses[SHIELD]
    source_parts = {row['id'] for sequence in (knife, bash) for pose in sequence for row in pose.values()}
    if missing := source_parts.difference(parts):
        raise ValueError(f'Unmapped instructor artwork: {sorted(missing)}')
    knife_names = {key: KNIFE_LAYER_NAMES.get(name, name) for key, name in names[KNIFE].items()}
    bash_names = {key: '盾牌' if name == '图层_18' else name for key, name in names[SHIELD].items()}
    path = 'x:timeline/x:DOMTimeline/x:layers'
    end_attack = '_parent.soldierFinishAttack(this);'

    bare = symbols[prefix+'动作/'+KNIFE].find(path, b.NS)
    bare[:] = [
        native.make_sparse_layer('攻击生命周期', len(knife), {
            0: {'script': '_parent.soldierBeginAttack(this,"knife");'},
            len(knife)-1: {'script': end_attack},
        }),
        native.make_sparse_layer('真实近战判定', len(knife), {
            KNIFE_IMPACT-1: {'elements': [contact(b, knife[KNIFE_IMPACT-1], 484, BLADE, 'soldierStab')]},
        }),
        *b.depth_layers(knife, parts, knife_names),
    ]

    shield = symbols[prefix+'动作/'+SHIELD].find(path, b.NS)
    lifecycle = shield.find('x:DOMLayer[@name="攻击生命周期"]', b.NS)
    branch = lifecycle.find('x:frames/x:DOMFrame[@name="挥盾"]', b.NS)
    offset = int(branch.get('index'))
    total = offset + len(bash)
    # The prefix is the existing shielded knife, including its invisible hit
    # and original finish. End every old picture layer before the new branch.
    for layer in list(shield):
        frames = layer.find('x:frames', b.NS)
        for frame in list(frames):
            start = int(frame.get('index'))
            if start >= offset:
                frames.remove(frame)
            elif start + int(frame.get('duration', '1')) > offset:
                frame.set('duration', str(offset-start))
        if layer.get('name').startswith('原始深度_'):
            if not frames.findall('.//x:DOMSymbolInstance', b.NS):
                shield.remove(layer)
                continue
            frames.append(native.frame(offset, len(bash)))

    # The shared selector reserves 34 frames on entry for the original stab.
    # Reserve the full authored bash even if a hit interrupts its recovery.
    begin = lifecycle.find('x:frames/x:DOMFrame[@index="0"]//x:script', b.NS)
    begin.text = E.CDATA(begin.text + '''
var owner:Object = _parent.soldierAttackOwner;
if (owner.bash && owner.token === this.soldierToken) {
    _parent.soldierNextMeleeAt = _parent.soldierClock + '''+str(len(bash))+''' + _parent.soldierTuning.meleeRestFrames;
}''')
    lifecycle_frames = lifecycle.find('x:frames', b.NS)
    lifecycle_frames.append(native.frame(offset, len(bash)-1, name='挥盾', label_type='name'))
    lifecycle_frames.append(native.frame(total-1, script=end_attack))

    hits = shield.find('x:DOMLayer[@name="真实近战判定"]/x:frames', b.NS)
    index = BASH_IMPACT-1
    hits.append(native.frame(offset, index))
    hits.append(native.frame(offset+index, elements=[contact(b, bash[index], 561, SHIELD_RIM, 'soldierMeleeHit')]))
    hits.append(native.frame(offset+index+1, len(bash)-index-1))
    for layer in b.depth_layers(bash, parts, bash_names):
        frames = layer.find('x:frames', b.NS)
        for frame in frames:
            frame.set('index', str(offset+int(frame.get('index'))))
        frames.insert(0, native.frame(0, offset))
        shield.append(layer)
