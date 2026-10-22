"""Retarget the player's articulated wolf-leap onto Manman's own native parts."""
import copy
import math
from pathlib import Path
from lxml import etree as E

NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{' + NS['x'] + '}'
PREFIX = 'Codex/蛮蛮/'
TOTAL = 48
REFERENCE = Path(__file__).resolve().parents[2] / 'flashswf/arts/things0/LIBRARY/容器/战技容器/战技容器-狼跳.xml'
IDENTITY = (1, 0, 0, 1, 0, 0)


def multiply(l, r):
    a,b,c,d,x,y = l
    e,f,g,h,u,v = r
    return a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y


def matrix(instance):
    m = instance.find('x:matrix/x:Matrix', NS)
    return tuple(float(m.get(k, IDENTITY[i])) for i,k in enumerate(('a','b','c','d','tx','ty')))


def interpolate(l, r, progress):
    """Interpolate joint rotation, never collapse a limb through a linear matrix blend."""
    def decompose(m):
        a,b,c,d,x,y = m
        return math.atan2(b,a),math.hypot(a,b),math.hypot(c,d),x,y
    la,lsx,lsy,lx,ly = decompose(l)
    ra,rsx,rsy,rx,ry = decompose(r)
    delta = (ra-la+math.pi) % math.tau-math.pi
    angle = la+delta*progress
    sx,sy = lsx+(rsx-lsx)*progress,lsy+(rsy-lsy)*progress
    return math.cos(angle)*sx,math.sin(angle)*sx,-math.sin(angle)*sy,math.cos(angle)*sy,lx+(rx-lx)*progress,ly+(ry-ly)*progress


# Registration conversions fit the approved parts to the reference joints.
# The forearm's elbow-to-wrist vector is diagonal in the CF6 drawing; the axe
# points along +X, whereas the player's blade points along +Y. These rotations
# are essential to retain connected wrists and an actual two-handed grip.
PARTS = {
    '上臂': (635,(.40,0,0,.40,0,0)),
    '左手臂': (637,(.235,.186,-.186,.235,0,0)),
    '左下臂': (637,(.235,.186,-.186,.235,0,0)),
    '左手': (643,(.32,0,0,.32,-6.5,-9)),
    '右手': (636,(.28,-.28,.28,.28,0,0)),
    '左大腿': (632,(.30,0,0,.30,0,0)),
    '右大腿': (632,(.30,0,0,.30,0,0)),
    '小腿': (634,(.34,0,0,.34,0,0)),
    '脚': (633,(.32,0,0,.32,0,0)),
    '身体': (638,(.36,0,0,.45,0,30)),
    '头': (646,(.23,0,0,.23,0,0)),
    '屁股': (639,(.24,0,0,.24,0,0)),
    '刀-主手': (642,(0,2.35,-2.35,0,0,45)),
}


def reference_poses():
    source = E.parse(str(REFERENCE))
    layer = source.find('.//x:DOMLayer[@name="图层 15"]', NS)
    result = []
    for frame in layer.findall('x:frames/x:DOMFrame', NS):
        rows = []
        counts = {}
        for inst in frame.findall('x:elements/x:DOMSymbolInstance', NS):
            name = inst.get('libraryItemName').rsplit('/',1)[-1]
            if name not in PARTS:
                continue
            counts[name] = counts.get(name,0)+1
            key = name+str(counts[name])
            part,calibration = PARTS[name]
            if name == '头':
                rows.append(('颈部',640,multiply(matrix(inst),(.30,0,0,.30,-2,28))))
            rows.append((key,part,multiply(matrix(inst),calibration)))
        result.append(rows)
    if len(result) != 27 or any(len(rows) != 17 for rows in result):
        raise ValueError('Player wolf-leap anatomy changed; review the retarget mapping')
    return result


def sample(poses, frame):
    index = frame-1
    left,right = poses[int(index)],poses[min(int(index)+1,len(poses)-1)]
    if [row[:2] for row in left] != [row[:2] for row in right]:
        raise ValueError('Reference joint order changed')
    return [(key,part,interpolate(m,right[i][2],index-int(index))) for i,(key,part,m) in enumerate(left)]


def grounded(rows):
    # Feet remain planted during charge; remove only the reference's baked
    # vertical displacement. The unit controller owns the actual jump height.
    foot_max = max(m[1]*x+m[3]*y+m[5] for key,part,m in rows if key.startswith('脚')
        for x in (-58.05,219.15) for y in (-10.65,168.3))
    return [(key,part,multiply((.45,0,0,.45,-8,75-.45*foot_max),m)) for key,part,m in rows]


def resting_pose(standing, order):
    names = {'上臂1':6,'左手臂1':3,'左手1':4,'左大腿1':19,'身体1':10,
        '颈部':7,'头1':2,'屁股1':9,'脚1':15,'小腿1':14,'右大腿1':18,
        '脚2':17,'小腿2':16,'刀-主手1':5,'上臂2':13,'左下臂1':11,'右手1':12}
    rows = {}
    for key,number in names.items():
        inst = standing.find('.//x:DOMLayer[@name="Layer '+str(number)+'"]/x:frames/x:DOMFrame[@index="0"]/x:elements/x:DOMSymbolInstance',NS)
        rows[key] = multiply((1,0,0,1,-25.5,5.65),matrix(inst))
    # The old near arm is mirrored. Fit its drawn shoulder/elbow/wrist vector
    # with a positive rotation so recovery never squashes through a reflection.
    for bone,end,vector in [('上臂2','左下臂1',(-50,236)),('左下臂1','右手1',(191,241))]:
        m=rows[bone]; tip=rows[end]
        dx,dy=tip[4]-m[4],tip[5]-m[5]
        angle=math.atan2(dy,dx)-math.atan2(vector[1],vector[0])
        scale=math.hypot(dx,dy)/math.hypot(*vector)
        rows[bone]=(math.cos(angle)*scale,math.sin(angle)*scale,-math.sin(angle)*scale,math.cos(angle)*scale,m[4],m[5])
    return [(key,part,rows[key]) for key,part,m in order]


def articulated_poses(native, standing):
    reference = reference_poses()
    rest = resting_pose(standing, reference[0])
    result = []
    for frame in range(1,TOTAL+1):
        if frame <= 18:
            source_frame = 1+(frame-1)*11/17
            rows = grounded(sample(reference,source_frame))
            if frame <= 4:
                progress=(frame-1)/3
                rows=[(key,part,interpolate(rest[i][2],m,progress)) for i,(key,part,m) in enumerate(rows)]
        elif frame <= 30:
            source_frame = 12+(frame-18)*10/12
            rows = sample(reference,source_frame)
            pelvis = next(m for key,part,m in rows if part == 639)
            rows = [(key,part,multiply((.45,0,0,.45,-8,-32-.45*pelvis[5]),m)) for key,part,m in rows]
        else:
            source_frame = min(27,23+(frame-31)*.65)
            rows = grounded(sample(reference,source_frame))
            if frame >= 39:
                progress = (frame-38)/10
                progress = progress*progress*(3-2*progress)
                rows = [(key,part,interpolate(m,rest[i][2],progress)) for i,(key,part,m) in enumerate(rows)]
        result.append(native.frame(index=frame-1,elements=[native.instance(PREFIX+'分件/'+str(part),matrix=m) for key,part,m in rows]))
    return result


def replace_interval(layer, start, end, replacement):
    """Split a stopped root-state interval without moving any existing state label."""
    frames = layer.find('x:frames', NS)
    output = []
    for original in frames:
        index = int(original.get('index'))
        limit = index + int(original.get('duration', '1'))
        if limit <= start or index >= end:
            output.append(original)
            continue
        if index < start:
            left = copy.deepcopy(original)
            left.set('duration', str(start - index))
            output.append(left)
        if limit > end:
            right = copy.deepcopy(original)
            right.set('index', str(end))
            right.set('duration', str(limit - end))
            for key in ('name', 'labelType'):
                right.attrib.pop(key, None)
            output.append(right)
    output.append(replacement)
    frames[:] = sorted(output, key=lambda frame: int(frame.get('index')))


def add_action(symbols, root_name, native):
    pose_name = PREFIX + '动作/狼跳挥斧骨架'
    action_name = PREFIX + '动作/狼跳'
    hit_name = PREFIX + '动作/狼跳落地判定'
    # Copy motion data only. No player paper-doll symbols, frame scripts,
    # preliminary hitboxes, invulnerability or weapon power enter this resource.
    symbols[pose_name] = native.symbol(pose_name,[native.layer('分关节狼跳',articulated_poses(native,symbols[PREFIX+'CF7/Symbol 1110']))],symbol_type='graphic')

    # A single contiguous landing region. Multiple spatial samples must not
    # multiply the HP-cap crumble inherited by the principal axe impact.
    shape = E.Element(N + 'DOMShape', isFloating='true')
    fills = E.SubElement(shape, N + 'fills')
    E.SubElement(E.SubElement(fills, N + 'FillStyle', index='1'), N + 'SolidColor', color='#FF0000')
    edges = E.SubElement(shape, N + 'edges')
    E.SubElement(edges, N + 'Edge', fillStyle1='1', edges='!200 -1600|3400 -1600|3400 1000|200 1000|200 -1600')
    area = native.symbol(hit_name + '/area', [native.layer('判定', [native.frame(elements=[shape])])], symbol_type='movie clip')
    symbols[hit_name + '/area'] = area
    symbols[hit_name] = native.symbol(hit_name, [native.layer('区域', [native.frame(
        elements=[native.instance(hit_name + '/area', name='area', symbol_type='movie clip')],
        script='this._visible=false; stop();\n')])], symbol_type='movie clip')

    poses = []
    for index in range(TOTAL):
        body = native.instance(pose_name)
        body.set('loop', 'single frame')
        body.set('firstFrame', str(index))
        poses.append(native.frame(index=index, elements=[body]))
    scripts = native.make_sparse_layer('动作合同', TOTAL, {
        0: {'script': '_parent.manmanSyncWolfShadow(this);\n_root.播放音效("CF6_0654.mp3");\n'},
        30: {'script': '_parent.manmanWolfImpact(this);\n'},
        47: {'script': '_parent.manmanAnimationDone(this);\n'},
    })
    hit_instance = native.instance(hit_name,name='wolfHit',symbol_type='movie clip')
    # Declarative transparency also covers the first frame before load scripts.
    E.SubElement(E.SubElement(hit_instance,N+'color'),N+'Color',alphaMultiplier='0')
    hit = native.layer('落地判定',[native.frame(duration=TOTAL,elements=[hit_instance])])
    shadow = native.instance(PREFIX+'CF7/Symbol 2',matrix=(.319610595703125,0,0,.130126953125,-9.95,63.15),
        name='wolfShadow',symbol_type='movie clip')
    shadow_layer = native.layer('接地阴影',[native.frame(duration=TOTAL,elements=[shadow])])
    symbols[action_name] = native.symbol(action_name, [scripts, hit, native.layer('原生身体与巨斧', poses), shadow_layer], symbol_type='movie clip')

    root = symbols[root_name]
    root_layers = root.find('x:timeline/x:DOMTimeline/x:layers', NS)
    labels = root_layers.find('x:DOMLayer[@name="Labels Layer"]', NS)
    replace_interval(labels, 47, 51, native.frame(index=47, duration=4, name='狼跳', label_type='name'))
    body_layer = next(layer for layer in root_layers if layer.find('.//x:DOMSymbolInstance[@libraryItemName="' + PREFIX + 'CF7/Symbol 1117"]', NS) is not None)
    inst = native.instance(action_name, matrix=(1, 0, 0, 1, 6.45, -63.5), name='man', symbol_type='movie clip',
        script='onClipEvent(load){ _parent.manmanBeginAttack(this,"wolf"); }\n')
    replace_interval(body_layer, 47, 51, native.frame(index=47, duration=4, elements=[inst]))
