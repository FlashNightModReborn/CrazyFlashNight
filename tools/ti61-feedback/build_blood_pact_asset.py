"""重建血浪战技：保留身体动作，纯时间轴血浪与单帧联弹分离。"""
from pathlib import Path
import hashlib
import json
import math
from lxml import etree as E
from xfl_asset_writer import AssetWriter

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'flashswf/arts/things0'
ICON_SOURCE = ROOT / 'flashswf/arts/new/Codex专用素材/LIBRARY'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
URI = NS['x']
PREFIX = 'Codex/Ti61-血剑战技/'
SKILL = PREFIX + '战技容器-猩红天秤'
ICON = PREFIX + '图标-猩红天秤'
TAIL = PREFIX + '特效-猩红天秤余波'
TAIL_FRAMES = 9
PARSER = E.XMLParser(strip_cdata=False, remove_blank_text=False)
BLOOD_SOURCE = ROOT / 'flashswf/arts/原版素材库-子弹/LIBRARY'
MIST_SOURCE = ROOT / 'flashswf/arts/new/雾人整合特效/LIBRARY'
WAVE_FRAMES = [26, 29, 32, 35, 38, 41, 44]
WAVE_CURTAIN = '1.特效文件夹/06.青蓝色系/深蓝裂地波/Symbol 105'
# 剥离三角幕后，源0取初生浪尖、源1–6取碎片主体的前缘（含供体内部矩阵）。
# 排除地影；按这个轮廓锚定area前沿，使晚段重击不会漂到实际范围之外。
WAVE_FRONTS = (73.62985611, 99.19446335, 136.09656450, 164.29090424,
               196.97150726, 204.45278702, 211.62409134)


def load(path):
    return E.parse(str(path), PARSER)


def identity(root, name, linkage=None):
    root.set('name', name)
    root.set('itemID', '61b10000-' + hashlib.sha256(name.encode()).hexdigest()[:8])
    for key in list(root.attrib):
        if key.startswith('linkage'):
            del root.attrib[key]
    if linkage:
        root.set('linkageExportForAS', 'true')
        root.set('linkageIdentifier', linkage)
    timeline = root.find('./x:timeline/x:DOMTimeline', NS)
    if timeline is not None:
        timeline.set('name', name.rsplit('/', 1)[-1])


def stage_symbol(document, name, pending):
    path = DEST / 'LIBRARY' / (name + '.xml')
    pending[path] = E.tostring(document, encoding='UTF-8', xml_declaration=True)
    return path


def element(tag, **attrs):
    return E.Element('{%s}%s' % (URI, tag), **{k: str(v) for k, v in attrs.items()})


def frame(index, duration, code=None):
    node = element('DOMFrame', index=index, duration=duration, keyMode=9728)
    if code:
        action = E.SubElement(node, '{%s}Actionscript' % URI)
        E.SubElement(action, '{%s}script' % URI).text = E.CDATA(code)
    E.SubElement(node, '{%s}elements' % URI)
    return node


def copy_blood_visuals(pending_symbols):
    roots = ['子弹-持续组/血爆炸', '子弹-持续组/血滴落/血滴落']
    names = {roots[0]: PREFIX + '血浪素材/血爆', roots[1]: PREFIX + '血浪素材/血滴'}
    pending, trees = roots[:], {}
    while pending:
        source = pending.pop()
        if source in trees:
            continue
        tree = load(BLOOD_SOURCE / (source + '.xml'))
        trees[source] = tree
        # 本地视觉副本不携带子弹area、寻主、移除和滤镜。播放统一由父Graphic推进。
        for node in tree.xpath('//x:Actionscript | //x:filters | //x:DOMSymbolInstance[@name="area"]', namespaces=NS):
            node.getparent().remove(node)
        tree.getroot().set('symbolType', 'graphic')
        for instance in tree.findall('.//x:DOMSymbolInstance', NS):
            child = instance.get('libraryItemName')
            names.setdefault(child, PREFIX + '血浪素材/' + hashlib.sha256(child.encode()).hexdigest()[:12])
            instance.set('symbolType', 'graphic')
            instance.set('loop', 'play once')
            instance.attrib.pop('name', None)
            pending.append(child)
    generated = []
    for source, tree in trees.items():
        identity(tree.getroot(), names[source])
        for instance in tree.findall('.//x:DOMSymbolInstance', NS):
            instance.set('libraryItemName', names[instance.get('libraryItemName')])
        generated.append(stage_symbol(tree, names[source], pending_symbols))
    return generated, [names[n] for n in roots]


def interpolate(keys, at):
    if at <= keys[0][0]:
        return keys[0][1]
    for (left, a), (right, b) in zip(keys, keys[1:]):
        if at <= right:
            return a + (b - a) * (at - left) / (right - left)
    return keys[-1][1]


def copy_mist_visuals(pending_symbols):
    """只复制已选的原生矢量闭包；用填充色替代供体的调色、发光和模糊。"""
    sources = {
        '起剑斩光': '1.特效文件夹/03.赤橙色系/赤橙横斩/赤橙横斩',
        '落剑喷溅': '1.特效文件夹/04.猩红色系/猩红攻势/猩红下砸/猩红下砸',
        '碎裂血浪': '1.特效文件夹/06.青蓝色系/深蓝裂地波/深蓝裂地波',
        '触地气环': '1.特效文件夹/01.白净色系/圆状气爆/圆状气爆',
        '破浪冲击': '1.特效文件夹/03.赤橙色系/破坏之狼/破坏之狼',
    }
    palette = {
        '#640E00': '#560505', '#FB9C1A': '#EC160D', '#FEFFE1': '#FF3828',
        '#FF0000': '#B80A08', '#FF6633': '#F52A16',
        '#FFFF00': '#E9160B', '#FFFFFF': '#FF3828', '#FF6600': '#750505',
        '#66FFFF': '#E9160B', '#A4FFFF': '#F52A16', '#BBFFFF': '#FA3020',
        '#FFFFC0': '#FC3424', '#D1FFFF': '#FD3626', '#FFFF80': '#F52A16',
        '#E8FFFF': '#FF3828', '#FFFF40': '#E9160B', '#33CCFF': '#B80A08',
    }
    names = {source: PREFIX + '雾人血浪素材/' + role for role, source in sources.items()}
    pending, trees = list(sources.values()), {}
    while pending:
        source = pending.pop()
        if source in trees:
            continue
        tree = load(MIST_SOURCE / (source + '.xml'))
        trees[source] = tree
        # 保留层次、原取帧、渐变和透明度。只去掉寻主、随机、音效、移除与攻击判定。
        for node in tree.xpath('//x:Actionscript | //x:filters | //x:DOMSymbolInstance[@name="area"]', namespaces=NS):
            node.getparent().remove(node)
        # 加色与hardlight会把已染红的多层交叠重新冲成粉白；地影multiply保留。
        for node in tree.xpath('//*[@blendMode]'):
            if node.get('blendMode').lower() in ('add', 'screen', 'hardlight'):
                del node.attrib['blendMode']
        # 裂地波的整片渐变三角幕比碎片多活四帧，血浪中会留下几何帐篷。
        # 只剥离该副本子件，保留初生浪尖、碎片层、地影和原遮罩索引。
        for node in tree.xpath('//x:DOMSymbolInstance[@libraryItemName=$curtain]',
                               namespaces=NS, curtain=WAVE_CURTAIN):
            node.getparent().remove(node)
        assert not tree.findall('.//x:DOMBitmapInstance', NS), source
        assert not tree.findall('.//x:BitmapFill', NS), source
        tree.getroot().set('symbolType', 'graphic')
        for node in tree.xpath('//x:GradientEntry | //x:SolidColor', namespaces=NS):
            color = node.get('color', '').upper()
            if '/赤橙横斩/' in source and color in ('#FEFFE1', '#FFFFFF'):
                # 只有短促的起剑刃光保留少量浅暖高光。
                node.set('color', '#FFD3AE')
            elif color in palette:
                node.set('color', palette[color])
            elif color.startswith('#') and len(color) == 7:
                # 冲击闭包含不同原色的火焰/速度线；在源填充上统一亮度层次。
                r, g, b = (int(color[i:i+2], 16) for i in (1,3,5))
                if max(r,g,b)-min(r,g,b) > 12 or max(r,g,b) >= 190:
                    light = (.2126*r + .7152*g + .0722*b) / 255
                    stops = [(0,(50,3,3)),(.32,(114,5,5)),(.63,(194,11,8)),
                             (.82,(237,28,16)),(1,(255,56,40))]
                    rgb = [round(interpolate([(at,rgb[c]) for at,rgb in stops],light)) for c in range(3)]
                    node.set('color', '#' + ''.join('%02X' % v for v in rgb))
        for color in tree.findall('.//x:Color', NS):
            # 原横斩RGB偏移、冲击件的色相变换不能再覆盖已统一的填充色。
            for key in list(color.attrib):
                if not key.startswith('alpha'):
                    del color.attrib[key]
        for instance in tree.findall('.//x:DOMSymbolInstance', NS):
            child = instance.get('libraryItemName')
            names.setdefault(child, PREFIX + '雾人血浪素材/' + hashlib.sha256(child.encode()).hexdigest()[:12])
            instance.set('symbolType', 'graphic')
            instance.set('loop', 'play once')
            instance.attrib.pop('name', None)
            pending.append(child)
    generated = []
    for source, tree in trees.items():
        identity(tree.getroot(), names[source])
        for instance in tree.findall('.//x:DOMSymbolInstance', NS):
            instance.set('libraryItemName', names[instance.get('libraryItemName')])
        generated.append(stage_symbol(tree, names[source], pending_symbols))
    return generated, {role: names[source] for role, source in sources.items()}


def add_visual(layers, name, symbol, samples, foreground=False, total_frames=46):
    """在制作期烘焙矩阵与取帧；运行时没有粒子循环、滤镜或额外子弹。"""
    layer = element('DOMLayer', name=name, color='#CC2244')
    frames = E.SubElement(layer, '{%s}frames' % URI)
    start, end = min(samples), max(samples)
    if start > 1:
        frames.append(frame(0, start - 1))
    for at, pose in sorted(samples.items()):
        shown = frame(at - 1, 1)
        # 原血爆前三帧为空；显式取帧使第26帧砸地即出现主爆发。
        instance = element('DOMSymbolInstance', libraryItemName=symbol,
                           symbolType='graphic', loop='single frame', firstFrame=pose.get('source', 0))
        sx, sy = pose.get('sx', 1), pose.get('sy', 1)
        angle = math.radians(pose.get('angle', 0))
        matrix = E.SubElement(instance, '{%s}matrix' % URI)
        values = dict(a=sx * math.cos(angle), b=sx * math.sin(angle),
                      c=-sy * math.sin(angle) + pose.get('shear', 0), d=sy * math.cos(angle),
                      tx=pose.get('x', 0), ty=pose.get('y', 233))
        matrix.append(element('Matrix', **{k: round(v, 5) for k, v in values.items()}))
        color = E.SubElement(instance, '{%s}color' % URI)
        rgb = pose.get('rgb', (1, 1, 1))
        color.append(element('Color', alphaMultiplier=round(pose.get('alpha', 1), 4),
                             redMultiplier=rgb[0], greenMultiplier=rgb[1], blueMultiplier=rgb[2]))
        shown.find('x:elements', NS).append(instance)
        frames.append(shown)
    if end < total_frames:
        frames.append(frame(end, total_frames - end))
    if foreground:
        layers.insert(0, layer)
    else:
        layers.append(layer)
    return {'name': name, 'start': start, 'end': end, 'foreground': foreground}


def compose_wave(layers, symbols, mist):
    tracks = []
    def add(name, symbol, samples, front=False):
        tracks.append(add_visual(layers, name, symbol, samples, front))
    # 补偿人物容器27.69%；所有位置是身体容器局部坐标，脚底约y=233。
    # 同一血浪使用三次错开取帧的撕裂动作，而不是让一个放大的轮廓平移到底。
    advance = lambda f: min(960, max(0, (f - 26) * 160 / 3))
    add('蓄势血池', symbols[1], {f: dict(source=2, sx=2.4-(f-2)*.17, sy=.22,
        x=-120-(2.4-(f-2)*.17)*130, y=227, alpha=(f-1)/10) for f in range(2,9)})
    add('起剑斩光', mist['起剑斩光'], {f: dict(source=[0,0,1,1,2,3,3][f-9],
        sx=5.0, sy=4.5, x=-440, y=interpolate([(9,100),(11,-430),(15,-850)],f),
        alpha=interpolate([(9,1),(12,1),(15,0)],f)) for f in range(9,16)}, True)
    add('起剑血丝', symbols[0], {f: dict(source=min(16,3+(f-9)), sx=1.6, sy=1.8,
        angle=-24, x=-210, y=190-(f-9)*26,
        alpha=interpolate([(9,.85),(13,.65),(18,0)],f)) for f in range(9,19)})
    add('落剑喷溅', mist['落剑喷溅'], {f: dict(source=[0,0,2,4,4,6,8][f-23],
        sx=3.444 if f < 26 else 4.2, sy=4.2,
        # 源第3帧竖直刀痕中心x=155.249；绕落点缩窄，避免刀口横漂。
        x=-650+(4.2-3.444)*155.249 if f < 26 else -650,
        y=interpolate([(23,-160),(25,0),(29,0)],f),
        alpha=interpolate([(23,.8),(25,1),(27,1),(29,0)],f)) for f in range(23,30)}, True)
    add('触地气环', mist['触地气环'], {f: dict(source=min(12,(f-26)*2),
        sx=interpolate([(26,2),(28,4.8),(33,6.5)],f), sy=.65+(f-26)*.15,
        x=-90, y=230, alpha=interpolate([(26,.9),(28,.7),(33,0)],f)) for f in range(26,34)}, True)
    # 主爆发峰值多驻留三帧，再把视觉重音交给仍在结算的后半段波锋。
    add('破浪冲击', mist['破浪冲击'], {f: dict(
        source=[0,1,2,3,4,5,6,6,7,7,8,9,10][f-26], sx=2.7, sy=3.6,
        x=120+max(0,advance(f)-advance(30))*.2, y=220,
        alpha=interpolate([(26,1),(35,1),(36,.8),(37,.45),(38,0)],f)) for f in range(26,39)})
    for name, start, sources, sx, sy, strength in [
        ('第一层碎浪',28,[0,1,2,3,4,5,6],5.5,5.6,.95),
        ('第二层碎浪',35,[0,1,2,3,3,4,5,6],4.9,5.2,.95),
        ('末端碎浪',40,[0,1,2,3,3,6],5.0,5.4,1)]:
        end = start+len(sources)-1
        add(name, mist['碎裂血浪'], {f: dict(source=sources[f-start],
            sx=sx, sy=sy, x=420+advance(f)-sx*WAVE_FRONTS[sources[f-start]], y=230,
            alpha=strength if f < end else .3)
            for f in range(start, min(end,43)+1)})
    # 同一条血爆后沿稍慢取帧并压暗，在白芯后保留血液主体，不另开粒子。
    add('血浪后沿', symbols[0], {f: dict(source=min(16,3+int((f-29)*.75)), sx=2.3, sy=3.2,
        x=-180+advance(f), y=290, shear=-.9, rgb=(.72,.7,.8),
        alpha=interpolate([(29,.9),(35,.8),(43,0)],f)) for f in range(29,44)})
    add('贴地血沫', symbols[1], {f: dict(source=min(18,2+int((f-26)*.55)),
        sx=5.4, sy=.8, x=-630+advance(f), y=215,
        alpha=interpolate([(26,.9),(37,.7),(44,.45),(45,0)],f)) for f in range(26,44)}, True)
    return tracks


def compose_tail(symbols, mist):
    """原44帧波锋与地沫接续退散；保持根部矩阵，不按逐帧轮廓重定位。"""
    root = E.Element('{%s}DOMSymbolItem' % URI, nsmap={None: URI})
    timeline = E.SubElement(E.SubElement(root, '{%s}timeline' % URI), '{%s}DOMTimeline' % URI)
    layers = E.SubElement(timeline, '{%s}layers' % URI)
    identity(root, TAIL, '特效-猩红天秤余波')
    tracks = []
    tracks.append(add_visual(layers, '末端碎浪余波', mist['碎裂血浪'], {
        f: dict(source=[3,4,5,6,6,6,6,6][f-1], sx=5.0, sy=5.4,
                x=420+960-5.0*WAVE_FRONTS[3], y=230,
                alpha=[1,.75,.52,.32,.18,.09,.04,.01][f-1])
        for f in range(1,9)}, total_frames=TAIL_FRAMES))
    tracks.append(add_visual(layers, '贴地血沫余迹', symbols[1], {
        f: dict(source=10+f, sx=5.4, sy=.8, x=-630+960, y=215,
                alpha=[.45,.38,.30,.23,.17,.11,.06,.025][f-1])
        for f in range(1,9)}, foreground=True, total_frames=TAIL_FRAMES))
    action_layer = element('DOMLayer', name='as', color='#FF0000')
    codes = E.SubElement(action_layer, '{%s}frames' % URI)
    codes.append(frame(0,TAIL_FRAMES-1,
        'this.effectType="特效-猩红天秤余波";\nthis._alpha=100;\nthis._visible=true;'))
    codes.append(frame(TAIL_FRAMES-1,1,'this.stop();\nthis.removeMovieClip();'))
    layers.insert(0, action_layer)
    return E.ElementTree(root), tracks


def build():
    pending_symbols = {}
    donor = DEST / 'LIBRARY/容器/战技容器/战技容器-撼地烈狱.xml'
    document = load(donor)
    identity(document.getroot(), SKILL, '战技容器-猩红天秤')
    layers = document.find('.//x:DOMTimeline/x:layers', NS)
    # 删除供体攻击脚本与震荡、飞石等视觉，保留同一条身体动作及路由标签。
    for layer in list(layers):
        if layer.get('name') in ('子弹控制as', '攻击点'):
            layers.remove(layer)
    for instance in list(document.findall('.//x:DOMSymbolInstance', NS)):
        if not instance.get('libraryItemName', '').startswith(('主角肢体素材/', '属性标签标志元件/')):
            instance.getparent().remove(instance)
    # 刀装扮只替换内层，供体外层的黄色发光会继续作用于实际血剑。
    # 仅更换本战技刀实例的光色，保留原强度/半径曲线和全部身体矩阵。
    weapon_glows = []
    for instance in document.findall('.//x:DOMSymbolInstance', NS):
        if instance.get('name') == '刀' and instance.get('libraryItemName') == '主角肢体素材/刀-主手':
            for glow in instance.findall('x:filters/x:GlowFilter', NS):
                glow.set('color', '#FD0000')
                weapon_glows.append(glow)
    # 用有逐帧轮廓变化的斩光替换供体两层直接绘制的规整大弧。
    # 身体、武器纸娃娃、动作标签和脚本保持原样。
    for layer in layers:
        if layer.get('name') in ('图层 25', '图层 27'):
            for node in layer.findall('.//x:DOMShape', NS):
                node.getparent().remove(node)
    actions = document.xpath('//x:DOMLayer[@name="as"]/x:frames', namespaces=NS)[0]
    start_code = actions[0].find('x:Actionscript/x:script', NS).text + '\n' + (
        '__ti61BloodTailReleased = false;\n'
        '__ti61BloodRuntime = _parent.__titaniumType61;\n'
        'if (!__ti61BloodRuntime || !__ti61BloodRuntime.bindBloodPactAnimation(this)) 无敌标签 = false;')
    blade = '''var bladeProps = {Z轴攻击范围:30, 击倒率:0.1};
if (__ti61BloodRuntime && __ti61BloodRuntime.prepareBloodPactAttack(this, bladeProps)) {
    _parent.刀口位置生成子弹(_parent, bladeProps);
}'''
    wave = '''var waveProps = _root.子弹属性初始化(this.bloodWaveArea, "近战联弹", _parent);
waveProps.霰弹值 = 5;
waveProps.最小霰弹值 = 3;
waveProps.子弹散射度 = 0;
waveProps.子弹速度 = 0;
waveProps.Z轴攻击范围 = 80;
waveProps.击倒率 = 0.1;
waveProps.击中地图效果 = "";
waveProps.区域定位area = this.bloodWaveArea;
if (__ti61BloodRuntime && __ti61BloodRuntime.prepareBloodPactAttack(this, waveProps)) {
    _root.子弹区域shoot传递(waveProps);
}'''
    scripts = {1: start_code, 9: blade, 26: blade + '\n' + wave,
               46: 'if (__ti61BloodRuntime) __ti61BloodRuntime.finishBloodPact(this, __ti61BloodCastId);\n_root.战技路由.动画完毕(this,_parent);'}
    scripts.update({n: wave for n in WAVE_FRAMES[1:]})
    # 只在最后一波通过原攻击资格后移交余波；保护、攻击时点和46帧收招不变。
    release_tail = '''if (!__ti61BloodTailReleased) {
    __ti61BloodTailReleased = true;
    var waveLayer:MovieClip = _root.gameworld.效果;
    if (waveLayer) {
        var waveOrigin:Object = {x:0,y:0};
        var waveAxisX:Object = {x:1000,y:0};
        var waveAxisY:Object = {x:0,y:1000};
        this.localToGlobal(waveOrigin);
        this.localToGlobal(waveAxisX);
        this.localToGlobal(waveAxisY);
        var worldOrigin:Object = {x:waveOrigin.x,y:waveOrigin.y};
        _root.gameworld.globalToLocal(worldOrigin);
        waveLayer.globalToLocal(waveOrigin);
        waveLayer.globalToLocal(waveAxisX);
        waveLayer.globalToLocal(waveAxisY);
        var bloodTail:MovieClip = _root.效果("特效-猩红天秤余波",worldOrigin.x,worldOrigin.y,100,true);
        if (bloodTail) {
            bloodTail.transform.matrix = new flash.geom.Matrix(
                (waveAxisX.x-waveOrigin.x)/1000,(waveAxisX.y-waveOrigin.y)/1000,
                (waveAxisY.x-waveOrigin.x)/1000,(waveAxisY.y-waveOrigin.y)/1000,
                waveOrigin.x,waveOrigin.y);
        }
    }
}'''
    scripts[44] = wave.replace('    _root.子弹区域shoot传递(waveProps);',
                              '    _root.子弹区域shoot传递(waveProps);\n' + release_tail)
    for old in list(actions):
        actions.remove(old)
    starts = sorted(scripts)
    for i, start in enumerate(starts):
        next_frame = starts[i + 1] if i + 1 < len(starts) else 47
        actions.append(frame(start - 1, next_frame - start, scripts[start]))

    # 单帧有效的轴对齐判定。母体动作缩放后约180px宽，依次覆盖推进中的浪峰。
    area_name = PREFIX + '血浪判定区域'
    area = load(BLOOD_SOURCE / '子弹-持续组/血滴落/area.xml')
    identity(area.getroot(), area_name)
    generated = [stage_symbol(area, area_name, pending_symbols)]
    area_layer = element('DOMLayer', name='血浪判定', color='#FF00FF')
    area_frames = E.SubElement(area_layer, '{%s}frames' % URI)
    area_frames.append(frame(0, 25))
    for i, start in enumerate(WAVE_FRAMES):
        f = frame(start - 1, 1)
        instance = element('DOMSymbolInstance', libraryItemName=area_name, name='bloodWaveArea')
        matrix = E.SubElement(instance, '{%s}matrix' % URI)
        matrix.append(element('Matrix', a=26, d=26, tx=-230 + i * 160, ty=-430))
        f.find('x:elements', NS).append(instance)
        area_frames.append(f)
        area_frames.append(frame(start, 2))
    layers.insert(0, area_layer)

    blood_files, blood_symbols = copy_blood_visuals(pending_symbols)
    generated.extend(blood_files)
    mist_files, mist_symbols = copy_mist_visuals(pending_symbols)
    generated.extend(mist_files)
    visual_tracks = compose_wave(layers, blood_symbols, mist_symbols)
    tail, tail_tracks = compose_tail(blood_symbols, mist_symbols)
    generated.append(stage_symbol(tail, TAIL, pending_symbols))

    # 第1至20帧保护支付和上升；身体最高点为第21帧，到达当帧撤除标签。
    invulnerability = document.xpath('//x:DOMLayer[@name="无敌标签"]/x:frames', namespaces=NS)[0]
    protected = invulnerability[0]
    protected.set('duration', '20')
    elements = protected.find('x:elements', NS)
    assert len(elements) == 0
    E.SubElement(elements, '{%s}DOMSymbolInstance' % URI,
                 libraryItemName='属性标签标志元件/无敌标签', name='无敌标签')
    exposed = E.SubElement(invulnerability, '{%s}DOMFrame' % URI,
                           index='20', duration='26', keyMode='9728')
    E.SubElement(exposed, '{%s}elements' % URI)
    generated.append(stage_symbol(document, SKILL, pending_symbols))

    # The small existing sword-icon closure supplies the skill icon without new raster art.
    origin = 'Codex/Ti61-血剑/图标-Codex-血色光剑天秤'
    pending, mapping, trees = [origin], {origin: ICON}, {}
    while pending:
        name = pending.pop()
        if name in trees:
            continue
        tree = load(ICON_SOURCE / (name + '.xml'))
        trees[name] = tree
        for instance in tree.findall('.//x:DOMSymbolInstance', NS):
            child = instance.get('libraryItemName')
            mapping.setdefault(child, PREFIX + '图标素材/' + hashlib.sha256(child.encode()).hexdigest()[:12])
            pending.append(child)
    for name, tree in trees.items():
        identity(tree.getroot(), mapping[name], '图标-猩红天秤' if name == origin else None)
        for instance in tree.findall('.//x:DOMSymbolInstance', NS):
            instance.set('libraryItemName', mapping[instance.get('libraryItemName')])
        generated.append(stage_symbol(tree, mapping[name], pending_symbols))

    dom_path = DEST / 'DOMDocument.xml'
    dom = load(dom_path)
    symbols = dom.find('x:symbols', NS)
    # 仅退役本生成器拥有、路径固定的旧规则弧与三角幕子件。
    retired_names = [PREFIX + '血浪素材/卷浪血刃.xml',
                     PREFIX + '雾人血浪素材/' + hashlib.sha256(WAVE_CURTAIN.encode()).hexdigest()[:12] + '.xml']
    for retired in retired_names:
        for include in symbols.xpath('x:Include[@href=$href]', namespaces=NS, href=retired):
            symbols.remove(include)
    for path in generated:
        href = path.relative_to(DEST / 'LIBRARY').as_posix()
        matches = symbols.xpath('x:Include[@href=$href]', namespaces=NS, href=href)
        if not matches:
            E.SubElement(symbols, '{%s}Include' % URI, href=href,
                         itemID=E.fromstring(pending_symbols[path], PARSER).get('itemID'))

    # 先完成全部生成与依赖核对，缺源/错误不能留下半套生产素材。
    for path, data in pending_symbols.items():
        root = E.fromstring(data, PARSER)
        name = path.relative_to(DEST / 'LIBRARY').as_posix()[:-4]
        assert root.get('name') == name, path
        for instance in root.findall('.//x:DOMSymbolInstance', NS):
            child = instance.get('libraryItemName')
            target = DEST / 'LIBRARY' / (child + '.xml')
            assert target in pending_symbols or (not child.startswith(PREFIX) and target.is_file()), child
    writer = AssetWriter(DEST, 'LIBRARY/' + PREFIX.rstrip('/'))
    for path, data in pending_symbols.items():
        writer.add(path, data)
    for retired in retired_names:
        writer.retire(DEST / 'LIBRARY' / retired)
    writer.add(dom_path, E.tostring(dom, encoding='UTF-8', xml_declaration=True))
    writer.commit()
    print(json.dumps({'symbols': len(generated), 'bladeAttacks': 2, 'waveFrames': WAVE_FRAMES,
                      'waveScatter': 5, 'minimumScatter': 3, 'visualTracks': visual_tracks,
                      'tailTracks': tail_tracks, 'tailReleaseFrame': 44, 'tailFrames': TAIL_FRAMES,
                      'peakVisualInstances': max(
                          sum(t['start'] <= f <= t['end'] for t in visual_tracks)
                          + sum(t['start'] <= f-43 <= t['end'] for t in tail_tracks)
                          for f in range(1,44+TAIL_FRAMES)),
                      'visualInstances': len(visual_tracks)+len(tail_tracks), 'skillFrames': 46,
                      'weaponGlowColor': '#FD0000', 'weaponGlowInstances': len(weapon_glows),
                      'invulnerabilityFrames': [1, 20], 'apexFrame': 21,
                      'bonusFrame': 26}, ensure_ascii=False))


if __name__ == '__main__':
    build()
