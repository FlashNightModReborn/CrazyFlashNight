"""Read-only wardrobe attachments that the native equipment lifecycle places behind the body.

This projects static placement only. It does not run equipment routines, buffs,
animation lag, or gameplay. Huofeng's hair matrix is read from its AS2 authority.
"""
from pathlib import Path
import json
import math
import re

HAIR_PROFILE = 'scripts/类定义/org/flashNight/arki/unit/Action/Huofeng/HuofengHairProfile.as'


def presentation_input_paths(root: Path):
    return [p for p in ('tools/dressup_attachments.py', HAIR_PROFILE) if (root / p).is_file()]


def attach_equipment_presentation(root, items, skin_keys, add_skin):
    head = items.get('火凤头部装备')
    if not head or head.get('dressup') != 'HF8/Hair/Front':
        return
    source = (root / HAIR_PROFILE).read_text('utf-8-sig')
    def literal(name):
        match = re.search(r'\b' + name + r'\s*:\s*("[^"]*"|\[[^\]]*\])', source)
        if not match:
            raise ValueError('Missing Huofeng native hair field: ' + name)
        return json.loads(match[1])
    matrix = literal('backToHead')
    if len(matrix) != 6 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in matrix):
        raise ValueError('Invalid Huofeng native hair matrix')
    head['rearAttachments'] = [
        {'skinKey': literal(part), 'anchorField': '面具',
         'requiredKeys': {'面具': literal('helmet')},
         'matrix': dict(zip(('a', 'b', 'c', 'd', 'tx', 'ty'), matrix))}
        for part in ('tail', 'upper')
    ]
    # Native HuofengVisual places the skirt at the hip reference only while the
    # five-piece controller is active. Do not add it to partial-set previews.
    lower = items.get('火凤下装')
    full_names = ('火凤头部装备', '火凤胸甲', '火凤下装', '火凤手甲', '火凤战靴')
    if lower and all(name in items for name in full_names):
        lower['rearAttachments'] = []
        for gender in ('男', '女'):
            required = {}
            for name in full_names:
                required.update(items[name]['fieldsByGender'][gender])
            lower['rearAttachments'].append({
                'skinKey': '火凤套装_后披摆', 'anchorField': '屁股',
                'requiredKeys': required,
                'matrix': {'a': 1, 'b': 0, 'c': 0, 'd': 1, 'tx': 0, 'ty': 0},
            })
    for name in ('火凤头部装备', '火凤下装'):
        item = items.get(name, {})
        keys = sorted({part['skinKey'] for part in item.get('rearAttachments', [])})
        if keys:
            item['auxiliarySkinKeys'] = keys
            for key in keys:
                add_skin(skin_keys, key, 'rear-attachment', name, HAIR_PROFILE)
