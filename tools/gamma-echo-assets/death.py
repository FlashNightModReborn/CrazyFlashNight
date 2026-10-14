"""Native death artwork: torn limb ends, shoulder cavity and small physical debris.

The accepted living parts remain shared XFL art. This one-time assembly recipe adds
native masks and tissue drawings; later native edits are protected by build.py.
"""
import copy
import io
import math
import xml.etree.ElementTree as SE


def shapes(api, content, origin=(0, 0)):
    svg = '<svg xmlns="http://www.w3.org/2000/svg">' + content + '</svg>'
    writer = api['base'].Writer(io.StringIO(svg))
    drawn = writer.walk(writer.root, parent_matrix=(1, 0, 0, 1, -origin[0], -origin[1]))
    return [api['E'].fromstring(SE.tostring(s)) for s in drawn]


def cut_surface(cx, cy, width, height, downward=False):
    """Irregular muscle rim, darker cavity, split bone and a few tendon strands."""
    sy = -1 if downward else 1
    return f'''<g transform="translate({cx} {cy}) scale({width/38} {height/14*sy})"
      stroke="#321013" stroke-width="1.2" stroke-linejoin="round">
      <path fill="#792328" d="M-19 0 L-16 -5 L-11 -4 L-6 -8 L0 -5 L5 -8 L10 -4 L17 -5 L20 0 L16 5 L10 4 L5 8 L0 5 L-7 7 L-12 3 L-17 4 Z"/>
      <path fill="#3c0f16" d="M-14 -1 Q-8 -5 -2 -3 L3 -5 Q10 -4 14 0 L9 3 L3 4 L-3 2 L-8 4 L-13 2 Z"/>
      <path fill="#b94348" stroke="none" d="M-16 -2 L-11 -4 L-8 -1 L-12 1 Z M-8 -5 L-4 -6 L-2 -2 L-4 0 Z M6 -5 L10 -3 L8 -1 L4 -2 Z M11 1 L15 0 L15 3 L10 4 Z M-10 3 L-5 2 L-4 5 L-8 5 Z"/>
      <path fill="#e4cbb0" d="M-3 -2 L-4 -7 L-1 -10 L2 -8 L4 -9 L5 -4 L3 0 L1 2 L-2 1 Z"/>
      <path fill="#f8e9d1" stroke="none" d="M-1 -8 L1 -7 L2 -3 L0 -1 L-2 -2 Z"/>
      <path fill="#72332f" stroke="none" d="M-2 -1 L1 -3 L3 -1 L1 1 Z"/>
      <path fill="none" stroke="#d6796b" stroke-width="1" d="M-13 0 L-10 2 M-6 -4 L-5 -1 M9 -2 L12 -1 M5 4 L4 2"/>
      <path fill="#87232b" stroke-width="0.7" d="M-12 4 Q-11 9 -14 12 L-11 12 Q-7 9 -8 5 Z M9 4 Q14 9 12 13 L15 11 Q16 7 13 4 Z"/>
    </g>'''


def create_parts(api, prefix, live, origins, full_power):
    symbol, layer, frame, instance = (api[k] for k in ('symbol', 'layer', 'frame', 'instance'))
    result, names = {}, {}

    def wounded(key, ident, mask, tissue):
        name = prefix + '碎尸分件/' + key
        layers = [layer('破口与肌肉骨茬', [frame(elements=shapes(api, tissue, origins[ident]))])]
        if mask:
            layers += [layer('保留皮肤轮廓', [frame(elements=shapes(api, mask, origins[ident]))],
                             layerType='mask', locked='true'),
                       layer('共用活体原生皮肤', [frame(elements=[instance(live[ident])])],
                             parentLayerIndex='1', locked='true')]
        else:
            layers += [layer('共用活体原生皮肤', [frame(elements=[instance(live[ident])])])]
        result[name] = symbol(name, layers)
        names[key] = name

    wounded('小腿断件', 263,
            '<path fill="#fff" d="M-20 13 L10 13 L18 9 L24 13 L31 8 L37 12 L70 13 L70 130 L-20 130 Z"/>',
            cut_surface(28, 13, 30, 12))
    wounded('大腿残段', 265,
            '<path fill="#fff" d="M-20 -20 L75 -20 L75 98 L44 98 L37 103 L31 99 L25 105 L19 100 L10 103 L-20 98 Z"/>',
            cut_surface(29, 101, 35, 13, downward=True))
    wounded('断臂上段', 262,
            '<path fill="#fff" d="M-20 29 L8 29 L16 25 L23 28 L29 23 L36 28 L43 25 L70 29 L70 130 L-20 130 Z"/>',
            cut_surface(29, 28, 39, 15))
    wounded('肩部裂口', 266, None, '''
      <g stroke="#311014" stroke-width="1.8" stroke-linejoin="round">
       <path fill="#72212a" d="M19 54 L27 58 L34 53 L40 61 L42 71 L48 79 L41 89 L36 98 L28 93 L21 97 L19 86 L13 80 L18 69 L14 62 Z"/>
       <path fill="#2d1017" d="M25 63 Q34 59 37 68 L41 78 L35 90 L25 86 L20 76 Z"/>
       <path fill="#b14b50" stroke="none" d="M19 62 L25 66 L22 74 L18 77 L18 68 Z M39 72 L44 79 L39 85 L36 83 Z M26 87 L33 89 L34 94 L28 90 Z"/>
       <path fill="#dcc4a8" d="M27 66 L29 61 L33 64 L35 68 L33 75 L29 77 L26 73 Z"/>
       <path fill="#f4e2c6" stroke="none" d="M29 65 L31 64 L33 69 L31 73 L28 72 Z"/>
       <path fill="none" stroke="#d38474" stroke-width="1" d="M22 67 L23 63 M37 79 L40 79 M24 81 L26 86"/>
       <path fill="#76202a" stroke-width="1" d="M24 91 Q27 105 23 112 L27 109 L29 97 Z M34 95 L35 106 L38 110 L39 107 L37 94 Z"/>
      </g>''')
    skin = '#844a49' if full_power else '#4c4242'
    for key, content in [
        ('碎肉', f'''<g stroke="#301215" stroke-width="1.3" stroke-linejoin="round">
          <path fill="{skin}" d="M-13 -4 L-8 -10 L0 -8 L8 -11 L14 -2 L10 7 L1 10 L-8 6 Z"/>
          <path fill="#8e3038" d="M-12 -1 L-6 -5 L1 -3 L8 -6 L11 1 L7 6 L-2 7 L-8 4 Z"/>
          <path fill="#cb5a59" stroke="none" d="M-6 -3 L-2 -2 L-3 3 L-7 2 Z M3 -2 L6 -3 L8 2 L4 4 Z"/>
          <path fill="#e4bf9f" stroke-width=".8" d="M-2 -2 L1 -4 L4 -1 L2 2 L-1 2 Z"/>
        </g>'''),
        ('骨片', '''<g stroke="#43352f" stroke-width="1.1" stroke-linejoin="round">
          <path fill="#d3c8b4" d="M-15 2 L-11 -4 L-6 -2 L4 -5 L11 -8 L15 -4 L10 0 L7 5 L0 3 L-7 7 L-12 5 Z"/>
          <path fill="#f5ebd9" stroke="none" d="M-11 1 L-7 -1 L-3 0 L7 -4 L10 -5 L8 -1 L1 1 L-6 4 Z"/>
          <path fill="#8d3c37" stroke="none" d="M-15 2 L-11 -3 L-8 -1 L-10 4 Z"/>
        </g>''')]:
        name = prefix + '碎尸分件/' + key
        result[name] = symbol(name, [layer('原生碎片绘制', [frame(elements=shapes(api, content))])])
        names[key] = name
    return result, names


def apply_timeline(api, source, names):
    """Keep original 0/47/78 starts and 45/76/108 callbacks; swap injured parts only."""
    NS = api['NS']
    layers = source.find('x:timeline/x:DOMTimeline/x:layers', NS)
    snapshot = copy.deepcopy(source)

    def leftmost(ident, at):
        values = []
        for layer in snapshot.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS):
            for f in layer.findall('x:frames/x:DOMFrame', NS):
                start = int(f.get('index', '0'))
                if start <= at < start + int(f.get('duration', '1')):
                    for element in f.findall('x:elements/x:DOMSymbolInstance', NS):
                        if element.get('libraryItemName') == f'诺亚克隆兽/部件/Symbol {ident}':
                            values.append(float(element.find('x:matrix/x:Matrix', NS).get('tx', '0')))
                    break
        return min(values)

    changed = {'小腿断件': 0, '大腿残段': 0, '断臂上段': 0, '肩部裂口': 0}
    for f in source.findall('.//x:DOMFrame', NS):
        at = int(f.get('index', '0'))
        for element in f.findall('x:elements/x:DOMSymbolInstance', NS):
            original = element.get('libraryItemName')
            ident = int(original.rsplit('Symbol ', 1)[-1])
            key = None
            if 3 <= at < 46 and ident in (256, 258):
                tx = float(element.find('x:matrix/x:Matrix', NS).get('tx', '0'))
                if abs(tx - leftmost(ident, at)) < .001:
                    key = '小腿断件' if ident == 256 else '大腿残段'
            elif 52 <= at < 77:
                if ident == 259:
                    key = '肩部裂口'
                elif ident == 255:
                    tx = float(element.find('x:matrix/x:Matrix', NS).get('tx', '0'))
                    if abs(tx - leftmost(ident, at)) < .001:
                        key = '断臂上段'
            if key:
                element.set('libraryItemName', names[key])
                changed[key] += 1
    # Small additional pieces follow authored ballistic keyframes, not a runtime RNG/system.
    for branch, start, end, x0, y0 in [(0, 3, 46, -39, 23), (1, 52, 77, -27, -52)]:
        for index in range(5):
            frames = [api['frame'](0, start)]
            velocity_x = -(1.1 + index * .58)
            velocity_y = -(2.2 + (index % 3) * 1.1)
            ground = 72 - index % 2 * 2
            gravity = .6
            landing = (-velocity_y + math.sqrt(velocity_y**2 + 4*gravity*(ground-y0))) / (2*gravity)
            for at in range(start, end):
                t = at - start
                y = y0 + velocity_y * t + gravity * t * t
                if t > landing:
                    elapsed = t - landing
                    y = ground - 3.5 * math.sin(math.pi * min(elapsed, 5) / 5) * max(0, 1-elapsed/6)
                travel = min(t, landing + 4)
                x = x0 + velocity_x * travel
                angle = math.radians(index * 57 + travel * (13 if index % 2 else -11))
                scale = .19 + .02 * (index % 3)
                matrix = (scale*math.cos(angle), scale*math.sin(angle), -scale*math.sin(angle), scale*math.cos(angle), x, y)
                inst = api['instance'](names['骨片' if index in (1, 4) else '碎肉'], matrix)
                frames.append(api['frame'](at, elements=[inst]))
            if end < 109:
                frames.append(api['frame'](end, 109 - end))
            layers.insert(2, api['layer'](f'新增断面碎片-{branch}-{index}', frames))
    assert all(changed.values()), changed
    return changed
