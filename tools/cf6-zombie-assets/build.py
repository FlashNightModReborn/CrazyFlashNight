"""Deterministic native XFL generator for CF6 male zombie (R5) and female zombie (R2).

Reads canonical archived SVG/JSON inputs from:
  flashswf/arts/new/Antigravity素材源稿/CF6普通男僵尸-R5
  flashswf/arts/new/Antigravity素材源稿/CF6女僵尸-R2
and builds the author-isolated XFL library:
  flashswf/arts/new/Antigravity专用素材
with zero bitmaps (no DOMBitmapInstance, no BitmapFill) and zero duplicate limb/head art.
"""
import argparse
import copy
import hashlib
import importlib.util
import io
import json
import pathlib
import re
import sys
import xml.etree.ElementTree as SE
from lxml import etree as E

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
_audio_spec=importlib.util.spec_from_file_location('cf6_audio_native',ROOT/'tools/cf6-audio/build.py')
audio=importlib.util.module_from_spec(_audio_spec)
_audio_spec.loader.exec_module(audio)
ARCHIVE = ROOT / 'flashswf/arts/new/Antigravity素材源稿'
MALE_ARCHIVE = ARCHIVE / 'CF6普通男僵尸-R5'
FEMALE_ARCHIVE = ARCHIVE / 'CF6女僵尸-R2'
OWNER = ROOT / 'flashswf/arts/new/Antigravity专用素材'
THINGS1 = ROOT / 'flashswf/arts/things1/LIBRARY'
MANIFEST_SCHEMA = 'cf6-zombie-redraw.native-import.v2'
PROJECT_FILES = ('DOMDocument.xml', 'Antigravity专用素材.xfl', 'MobileSettings.xml', 'PublishSettings.xml')

sys.path.insert(0, str(ROOT / 'tools/tesla-map-assets/native_vector'))
import svg_to_xfl_legacy as base  # noqa: E402

XFL_NS = 'http://ns.adobe.com/xfl/2008/'
XSI_NS = 'http://www.w3.org/2001/XMLSchema-instance'
NS = {'x': XFL_NS}
PARSER = E.XMLParser(remove_blank_text=False)

SHARED_HELPERS = {
    'Symbol 32': 'Antigravity/共用/人物文字信息',
    'Symbol 26': 'Antigravity/共用/血条组件26',
    'Symbol 21': 'Antigravity/共用/血条组件21',
    'Symbol 24': 'Antigravity/共用/血条组件24',
    'Symbol 23': 'Antigravity/共用/血条组件23',
    'Symbol 19': 'Antigravity/共用/area框',
    'Symbol 18': 'Antigravity/共用/area框图形',
    '思考标签': 'Antigravity/共用/思考标签',
    'Symbol 16': 'Antigravity/共用/思考标签图形',
    'Symbol 15': 'Antigravity/共用/控制块',
    'Symbol 113': 'Antigravity/共用/被投旋转area',
    'Symbol 195': 'Antigravity/共用/攻击点',
    'Symbol 99': 'Antigravity/共用/玩家控制停止器',
    'Symbol 2': 'Antigravity/共用/接地阴影',
}

MALE_PART_LABELS = {
    393: '393-脚靴',
    394: '394-小腿',
    395: '395-大腿',
    396: '396-髋部',
    397: '397-上臂',
    398: '398-张爪手',
    399: '399-前臂',
    400: '400-躯干',
    401: '401-头部',
    402: '402-垂指手',
}

FEMALE_PART_LABELS = {
    1619: '1619-脚靴',
    1620: '1620-小腿',
    1621: '1621-大腿',
    1622: '1622-髋部',
    1623: '1623-上臂',
    1624: '1624-张爪手',
    1625: '1625-前臂',
    1626: '1626-躯干',
    1627: '1627-头部',
    1628: '1628-垂指手',
}

CF6_HELPERS = {281, 290, 299, 311}

ATTACK_MOVE_FUNC_SCRIPT = """function 攻击时移动(慢速度, 快速度)
{
   if(_parent.方向 == "右")
   {
      if(Key.isDown(_root.右键) == true)
      {
         _parent.移动("右",快速度);
      }
      else
      {
         _parent.移动("右",慢速度);
      }
   }
   else if(_parent.方向 == "左")
   {
      if(Key.isDown(_root.左键) == true)
      {
         _parent.移动("左",快速度);
      }
      else
      {
         _parent.移动("左",慢速度);
      }
   }
}
"""

ATTACK_HITBOX_SCRIPT = """onClipEvent(load){
   声音 = "";
   霰弹值 = 1;
   子弹散射度 = 0;
   发射效果 = "";
   子弹种类 = "近战子弹";
   子弹威力 = _parent._parent.空手攻击力;
   子弹速度 = 0;
   击中地图效果 = "";
   Z轴攻击范围 = 30;
   击倒率 = 10;
   击中后子弹的效果 = "空手攻击火花";
   if(_parent._parent.是否为敌人 == true)
   {
      子弹敌我属性 = false;
   }
   else
   {
      子弹敌我属性 = true;
   }
   var myPoint = {x:this._x,y:this._y};
   _parent.localToGlobal(myPoint);
   _root.gameworld.globalToLocal(myPoint);
   shootX = myPoint.x;
   shootY = myPoint.y;
   _root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,_parent._parent._name,shootX,shootY,_parent._parent.Z轴坐标,子弹敌我属性,击倒率,击中后子弹的效果);
}
"""

PLAYER_STOP_SCRIPT = """onClipEvent(load){
   if(_root.控制目标 == _parent._parent._name)
   {
      stop();
   }
}
"""

SHADOW_LOAD_SCRIPT = """onClipEvent(load){
   if(_root.是否阴影 == true)
   {
      this._visible = 1;
   }
   else
   {
      this._visible = 0;
   }
}
"""


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def item_id(name: str, prefix: str = '6af00000') -> str:
    return f'{prefix}-' + hashlib.sha1(name.encode('utf-8')).hexdigest()[:8]


def num(value: float) -> str:
    if abs(value) < 1e-9:
        value = 0.0
    text = f'{value:.6f}'.rstrip('0').rstrip('.')
    return text or '0'


def set_matrix(parent, m):
    a, b, c, d, tx, ty = m
    attrs = {}
    if abs(a - 1) > 1e-6:
        attrs['a'] = num(a)
    if abs(b) > 1e-6:
        attrs['b'] = num(b)
    if abs(c) > 1e-6:
        attrs['c'] = num(c)
    if abs(d - 1) > 1e-6:
        attrs['d'] = num(d)
    if abs(tx) > 1e-6:
        attrs['tx'] = num(tx)
    if abs(ty) > 1e-6:
        attrs['ty'] = num(ty)
    mx = E.SubElement(parent, f'{{{XFL_NS}}}matrix')
    E.SubElement(mx, f'{{{XFL_NS}}}Matrix', **attrs)


def instance(library_name: str, matrix=base.I, symbol_type='graphic', name=None,
             script=None, alpha_mult=None, add_adjust_filter=False):
    attrs = {'libraryItemName': library_name}
    if name:
        attrs['name'] = name
    if symbol_type == 'graphic':
        attrs['symbolType'] = 'graphic'
        attrs['loop'] = 'loop'
    inst = E.Element(f'{{{XFL_NS}}}DOMSymbolInstance', **attrs)
    set_matrix(inst, matrix)
    tp = E.SubElement(inst, f'{{{XFL_NS}}}transformationPoint')
    E.SubElement(tp, f'{{{XFL_NS}}}Point')
    if script:
        asc = E.SubElement(inst, f'{{{XFL_NS}}}Actionscript')
        sc = E.SubElement(asc, f'{{{XFL_NS}}}script')
        sc.text = E.CDATA(script)
    if alpha_mult is not None:
        col = E.SubElement(inst, f'{{{XFL_NS}}}color')
        E.SubElement(col, f'{{{XFL_NS}}}Color', alphaMultiplier=num(alpha_mult))
    if add_adjust_filter:
        flt = E.SubElement(inst, f'{{{XFL_NS}}}filters')
        E.SubElement(flt, f'{{{XFL_NS}}}AdjustColorFilter')
    return inst


def frame(index=0, duration=1, elements=(), name=None, label_type=None, script=None):
    attrs = {'index': str(index), 'keyMode': '9728'}
    if duration > 1:
        attrs['duration'] = str(duration)
    if name:
        attrs['name'] = name
    if label_type:
        attrs['labelType'] = label_type
    fr = E.Element(f'{{{XFL_NS}}}DOMFrame', **attrs)
    if script:
        asc = E.SubElement(fr, f'{{{XFL_NS}}}Actionscript')
        sc = E.SubElement(asc, f'{{{XFL_NS}}}script')
        sc.text = E.CDATA(script)
    elems = E.SubElement(fr, f'{{{XFL_NS}}}elements')
    for el in elements:
        elems.append(el)
    return fr


def layer(name: str, frames, **extra):
    attrs = {'name': name, 'color': '#4FFF4F', **extra}
    ly = E.Element(f'{{{XFL_NS}}}DOMLayer', **attrs)
    frs = E.SubElement(ly, f'{{{XFL_NS}}}frames')
    for fr in frames:
        frs.append(fr)
    return ly


def symbol(name: str, layers, symbol_type='graphic', linkage=None, export_first_frame=False, export_rs=False, url=None):
    attrs = {'name': name, 'itemID': item_id(name)}
    if symbol_type == 'graphic':
        attrs['symbolType'] = 'graphic'
    if linkage:
        attrs['linkageExportForAS'] = 'true'
        if export_rs:
            attrs['linkageExportForRS'] = 'true'
        if export_first_frame:
            attrs['linkageExportInFirstFrame'] = 'true'
        attrs['linkageIdentifier'] = linkage
        if url:
            attrs['linkageURL'] = url
    root = E.Element(f'{{{XFL_NS}}}DOMSymbolItem', nsmap={None: XFL_NS, 'xsi': XSI_NS}, **attrs)
    tl_wrap = E.SubElement(root, f'{{{XFL_NS}}}timeline')
    tl = E.SubElement(tl_wrap, f'{{{XFL_NS}}}DOMTimeline', name=name.rsplit('/', 1)[-1])
    lys = E.SubElement(tl, f'{{{XFL_NS}}}layers')
    for ly in layers:
        lys.append(ly)
    return root


def xml_bytes(root):
    for script in root.findall('.//x:script', NS):
        source = script.text or ''
        lines = [re.sub(r'^[ \t]+', lambda m: m[0].expandtabs(4), line.rstrip(' \t'))
                 for line in source.splitlines()]
        normalized = '\n'.join(lines) + ('\n' if source.endswith('\n') else '')
        script.text = E.CDATA(normalized)
    tree = E.ElementTree(root)
    E.indent(tree, space='  ')
    return E.tostring(root, encoding='utf-8', xml_declaration=True, pretty_print=True)


class NativePart:
    """Converts an SVG (with optional clipPath / shared atlas references) into native XFL Graphic symbols."""

    def __init__(self, svg_source, name: str, male_fill_map=None, female_head_master=None):
        if isinstance(svg_source, pathlib.Path):
            self.writer = base.Writer(str(svg_source))
        else:
            self.writer = base.Writer(io.StringIO(svg_source))
        self.svg = self.writer.root
        self.name = name
        self.by_id = {e.get('id'): e for e in self.svg.iter() if e.get('id')}
        self.symbols = {}
        self.masks = 0
        self.male_fill_map = male_fill_map or {}
        self.female_head_master = female_head_master

    def paint_shape(self, el, attrs, matrix):
        sh = self.writer.shape(copy.deepcopy(el), dict(attrs), matrix)
        if sh is None:
            return None
        sh.attrib.pop('isFloating', None)
        sh.set('isDrawingObject', 'true')
        return E.fromstring(SE.tostring(sh))

    @staticmethod
    def _has_female_head_silhouette(el) -> bool:
        for child in el:
            if base.tag(child) == 'defs':
                for sub in child:
                    cid = sub.get('id', '')
                    if base.tag(sub) == 'clipPath' and cid.endswith('femaleHeadSourceSilhouette'):
                        return True
        return False

    def contents(self, el, inherited=None, matrix=base.I, active_clip_id=None):
        attrs = base.style(el, inherited)
        attrs.pop('clip-path', None)
        m = base.mul(matrix, base.transform(el.get('transform')))
        kind = base.tag(el)
        if kind in ('defs', 'title', 'desc', 'metadata', 'clipPath', 'linearGradient'):
            return []
        if kind == 'use':
            href = el.get('href') or el.get('{http://www.w3.org/1999/xlink}href') or ''
            if href.endswith('_atlas392') and active_clip_id in self.male_fill_map:
                part_sym, atlas_offset = self.male_fill_map[active_clip_id]
                return [instance(part_sym, matrix=base.mul(m, atlas_offset))]
            raise ValueError(f'Unsupported <use href="{href}"> in {self.name} (clip={active_clip_id})')
        if kind not in ('svg', 'g'):
            sh = self.paint_shape(el, attrs, m)
            return [sh] if sh is not None else []
        if self.female_head_master and kind == 'g' and self._has_female_head_silhouette(el):
            return [instance(self.female_head_master, matrix=m)]
        result = []
        for child in el:
            raw = child.get('clip-path')
            if not raw:
                result.extend(self.contents(child, attrs, m, active_clip_id=active_clip_id))
                continue
            match = re.fullmatch(r'url\(#([^)]*)\)', raw)
            if not match:
                raise ValueError('Unsupported clip: ' + raw)
            clip_id = match[1]
            clip = self.by_id[clip_id]
            if clip.get('clipPathUnits', 'userSpaceOnUse') != 'userSpaceOnUse':
                raise ValueError('Only user-space clips are expected')
            child_matrix = base.mul(m, base.transform(child.get('transform')))
            clip_matrix = base.mul(child_matrix, base.transform(clip.get('transform')))
            mask_shapes = []
            for mask in clip:
                a = base.style(mask)
                a.update(fill='#FFFFFF', stroke='none')
                mask_matrix = base.mul(clip_matrix, base.transform(mask.get('transform')))
                sh = self.paint_shape(mask, a, mask_matrix)
                if sh is not None:
                    mask_shapes.append(sh)
            helper = f'{self.name}-遮罩{self.masks}'
            self.masks += 1
            drawn = self.contents(child, attrs, m, active_clip_id=clip_id)
            self.symbols[helper] = symbol(helper, [
                layer('轮廓遮罩', [frame(elements=mask_shapes)], layerType='mask', locked='true'),
                layer('原生矢量内容', [frame(elements=drawn)], parentLayerIndex='0', locked='true'),
            ])
            result.append(instance(helper))
        return result

    def build(self):
        drawing = self.contents(self.svg, matrix=base.I)
        self.symbols[self.name] = symbol(self.name, [layer('原生矢量层', [frame(elements=drawing)])])
        return self.symbols, {
            'shapes': self.writer.shape_count,
            'segments': self.writer.segment_count,
            'masks': self.masks,
        }


import math  # noqa: E402


def clone_shared_helpers():
    symbols = {}
    for src_name, dst_name in SHARED_HELPERS.items():
        src_path = THINGS1 / f'{src_name}.xml'
        root = E.parse(str(src_path), PARSER).getroot()
        root.set('name', dst_name)
        root.set('itemID', item_id(dst_name))
        for k in ('lastModified', 'lastUniqueIdentifier', 'linkageExportForAS', 'linkageExportInFirstFrame',
                  'linkageIdentifier', 'linkageImportForRS', 'linkageExportForRS', 'linkageURL', 'linkageClassName'):
            root.attrib.pop(k, None)
        tl = root.find('x:timeline/x:DOMTimeline', NS)
        tl.set('name', dst_name.rsplit('/', 1)[-1])
        for el in root.iter():
            ref = el.get('libraryItemName')
            if ref in SHARED_HELPERS:
                el.set('libraryItemName', SHARED_HELPERS[ref])
        symbols[dst_name] = root
    return symbols


def build_depth_layers(frames_list, part_map, shift=(0.0, 0.0)):
    """Converts a list of per-frame depth dicts into XFL DOMLayers (top depth first)."""
    sx, sy = shift
    depths = sorted({
        int(d)
        for fr in frames_list
        for d, v in fr.items()
        if v['id'] not in CF6_HELPERS
    }, reverse=True)

    layers = []
    total = len(frames_list)
    for d in depths:
        ds = str(d)
        states = []
        for fr in frames_list:
            v = fr.get(ds)
            if v is None or v['id'] in CF6_HELPERS:
                states.append(None)
            else:
                m = list(v['matrix'])
                m[4] += sx
                m[5] += sy
                states.append((v['id'], tuple(m)))
        dom_frames = []
        idx = 0
        while idx < total:
            cur = states[idx]
            end = idx + 1
            while end < total and states[end] == cur:
                end += 1
            dur = end - idx
            if cur is None:
                dom_frames.append(frame(index=idx, duration=dur))
            else:
                cid, mat = cur
                dom_frames.append(frame(index=idx, duration=dur, elements=[
                    instance(part_map[cid], matrix=mat, symbol_type='graphic')
                ]))
            idx = end
        layers.append(layer(f'深度_{d}', dom_frames))
    return layers


def make_sparse_layer(name: str, total_frames: int, keyframes_dict, **extra):
    """Creates a DOMLayer with sparse keyframes at 0-based indices in keyframes_dict."""
    # keyframes_dict: {start_idx: {'duration': int, 'name': str, 'label_type': str, 'script': str, 'elements': list}}
    dom_frames = []
    cur = 0
    for idx in sorted(keyframes_dict):
        if idx > cur:
            dom_frames.append(frame(index=cur, duration=idx - cur))
        spec = keyframes_dict[idx]
        dur = spec.get('duration', 1)
        dom_frames.append(frame(
            index=idx,
            duration=dur,
            elements=spec.get('elements', ()),
            name=spec.get('name'),
            label_type=spec.get('label_type'),
            script=spec.get('script'),
        ))
        cur = idx + dur
    if cur < total_frames:
        dom_frames.append(frame(index=cur, duration=total_frames - cur))
    return layer(name, dom_frames, **extra)


def build_action_clips(prefix: str, part_map: dict, live_tl: dict, death_frames: list, cfg: dict):
    """Builds the 8 action MovieClips (站立, 行走, 攻击, 被击, 击倒, 倒地, 被投, 血腥死) and Root Enemy MovieClip."""
    symbols = {}
    act_prefix = f'{prefix}/动作'

    # 1. 站立
    stand_frames = live_tl[cfg['stand_id']]
    stand_name = f'{act_prefix}/站立'
    stand_layers = [
        make_sparse_layer('Script Layer', len(stand_frames), {
            4: {'script': 'if(躲闪 == true)\n{\n   _parent.动画完毕();\n}\n'}
        }),
        *build_depth_layers(stand_frames, part_map),
    ]
    symbols[stand_name] = symbol(stand_name, stand_layers, symbol_type='movie clip')

    # 2. 行走 (reused for 空手行走 & 空手跑)
    walk_frames = live_tl[cfg['walk_id']]
    walk_name = f'{act_prefix}/行走'
    walk_layers = build_depth_layers(walk_frames, part_map)
    symbols[walk_name] = symbol(walk_name, walk_layers, symbol_type='movie clip')

    # 3. 攻击
    atk_frames = live_tl[cfg['attack_id']]
    atk_name = f'{act_prefix}/攻击'
    atk_layers = [
        make_sparse_layer('Script Layer', len(atk_frames), {
            0: {'script': ATTACK_MOVE_FUNC_SCRIPT},
            34: {'script': '_parent.动画完毕();\n'},
        }),
        make_sparse_layer('判定与移动层', len(atk_frames), {
            5: {
                'duration': 2,
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 19'],
                        matrix=(0.32000732421875, 0, 0, 0.32000732421875, -28.45, -52.35),
                        symbol_type='movie clip',
                        script='onClipEvent(load){\n   _parent.攻击时移动(5,25);\n}\n',
                    )
                ],
            },
            8: {
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 195'],
                        matrix=(0.526702880859375, 0, 0, 0.516220092773438, 9.45, -25.4),
                        symbol_type='movie clip',
                        name='攻击点',
                        script=ATTACK_HITBOX_SCRIPT,
                        alpha_mult=0.0,
                    )
                ],
            },
            10: {
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 195'],
                        matrix=(0.526702880859375, 0, 0, 0.516220092773438, 47.4, -31.7),
                        symbol_type='movie clip',
                        name='攻击点',
                        script=ATTACK_HITBOX_SCRIPT,
                        alpha_mult=0.0,
                    )
                ],
            },
        }),
        *build_depth_layers(atk_frames, part_map),
    ]
    symbols[atk_name] = symbol(atk_name, atk_layers, symbol_type='movie clip')

    # 4. 被击
    hit_frames = live_tl[cfg['hit_id']]
    hit_name = f'{act_prefix}/被击'
    hit_end_a0, hit_end_a1 = cfg['hit_callbacks']
    hit_layers = [
        make_sparse_layer('Labels Layer', len(hit_frames), {
            0: {'name': 'a0', 'label_type': 'name'},
            22: {'name': 'a1', 'label_type': 'name'},
        }),
        make_sparse_layer('Script Layer', len(hit_frames), {
            hit_end_a0: {'script': '_parent.动画完毕();\n'},
            hit_end_a1: {'script': '_parent.动画完毕();\n'},
        }),
        *build_depth_layers(hit_frames, part_map),
    ]
    symbols[hit_name] = symbol(hit_name, hit_layers, symbol_type='movie clip')

    # 5. 击倒 (119 frames holding airborne pose)
    kd_source_frame = live_tl[cfg['down_id']][cfg['knockdown_pose_index']]
    kd_frames = [kd_source_frame] * 119
    kd_name = f'{act_prefix}/击倒'
    kd_labels = {
        0: {'name': '空手', 'label_type': 'name'},
        17: {'name': '长枪', 'label_type': 'name'},
        34: {'name': '手枪', 'label_type': 'name'},
        51: {'name': '手枪2', 'label_type': 'name'},
        68: {'name': '双枪', 'label_type': 'name'},
        85: {'name': '手雷', 'label_type': 'name'},
        102: {'name': '兵器', 'label_type': 'name'},
    }
    kd_scripts = {
        5: {'script': 'if(_parent.已加经验值 != true)\n{\n   _root.播放音效("僵尸0" + (random(6) + 1) + ".wav");\n}\n'},
    }
    for stop_idx in (16, 33, 50, 67, 84, 101, 118):
        kd_scripts[stop_idx] = {'script': 'stop();\n'}
    kd_layers = [
        make_sparse_layer('Labels Layer', 119, kd_labels),
        make_sparse_layer('Script Layer', 119, kd_scripts),
        *build_depth_layers(kd_frames, part_map),
    ]
    symbols[kd_name] = symbol(kd_name, kd_layers, symbol_type='movie clip')

    # 6. 倒地
    down_start, down_end = cfg['down_slice']
    down_frames = live_tl[cfg['down_id']][down_start:down_end]
    down_name = f'{act_prefix}/倒地'
    down_layers = [
        make_sparse_layer('Script Layer', len(down_frames), {
            8: {'script': '_parent.死亡检测();'},
            12: {'script': '_parent.死亡检测();'},
            len(down_frames) - 1: {'script': '_parent.动画完毕();\n'},
        }),
        make_sparse_layer('控制层', len(down_frames), {
            8: {
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 99'],
                        matrix=(0.444442749023438, 0, 0, 0.444442749023438, 0, 0),
                        symbol_type='movie clip',
                        script=PLAYER_STOP_SCRIPT,
                    )
                ]
            }
        }),
        *build_depth_layers(down_frames, part_map),
    ]
    symbols[down_name] = symbol(down_name, down_layers, symbol_type='movie clip')

    # 7. 被投 (shifted by standing root offset so rotation pivot is at root (0,0))
    grab_name = f'{act_prefix}/被投'
    grab_layers = [
        make_sparse_layer('Labels Layer', len(hit_frames), {
            0: {'name': 'a0', 'label_type': 'name'},
            22: {'name': 'a1', 'label_type': 'name'},
        }),
        make_sparse_layer('Script Layer', len(hit_frames), {
            hit_end_a0: {'script': '_parent.动画完毕();\n'},
            hit_end_a1: {'script': '_parent.动画完毕();\n'},
        }),
        *build_depth_layers(hit_frames, part_map, shift=cfg['offsets']['hit']),
    ]
    symbols[grab_name] = symbol(grab_name, grab_layers, symbol_type='movie clip')

    # 8. 血腥死
    death_name = f'{act_prefix}/血腥死'
    d_a0, d_a1, d_a2 = cfg['death_labels']
    d_c0, d_c1, d_c2 = cfg['death_callbacks']
    death_layers = [
        make_sparse_layer('Labels Layer', len(death_frames), {
            d_a0: {'name': 'a0', 'label_type': 'name'},
            d_a1: {'name': 'a1', 'label_type': 'name'},
            d_a2: {'name': 'a2', 'label_type': 'name'},
        }),
        make_sparse_layer('Script Layer', len(death_frames), {
            d_c0: {'script': '_parent.死亡检测();'},
            d_c1: {'script': '_parent.死亡检测();'},
            d_c2: {'script': '_parent.死亡检测();'},
        }),
        make_sparse_layer('控制层', len(death_frames), {
            idx: {
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 99'],
                        matrix=(1, 0, 0, 1, 0, 0),
                        symbol_type='movie clip',
                        script=PLAYER_STOP_SCRIPT,
                    )
                ]
            }
            for idx in (d_c0, d_c1, d_c2)
        }),
        *build_depth_layers(death_frames, part_map),
    ]
    symbols[death_name] = symbol(death_name, death_layers, symbol_type='movie clip')

    # 9. Root Enemy MovieClip (127 frames matching 敌人-光头军人僵尸1.xml)
    linkage = cfg['linkage']
    root_name = f'{prefix}/{linkage}'
    off = cfg['offsets']
    root_layers = [
        make_sparse_layer('Labels Layer', 127, {
            1: {'name': '空手站立', 'label_type': 'name'},
            9: {'name': '空手行走', 'label_type': 'name'},
            19: {'name': '空手跑', 'label_type': 'name'},
            29: {'name': '空手跳', 'label_type': 'name'},
            41: {'name': '空手攻击', 'label_type': 'name'},
            51: {'name': '拾取', 'label_type': 'name'},
            61: {'name': '躲闪', 'label_type': 'name'},
            71: {'name': '被击', 'label_type': 'name'},
            79: {'duration': 9, 'name': '击倒', 'label_type': 'name'},
            88: {'duration': 7, 'name': '倒地', 'label_type': 'name'},
            95: {'name': '被投', 'label_type': 'name'},
            104: {'name': '血腥死', 'label_type': 'name'},
            120: {'name': '消失', 'label_type': 'name'},
        }),
        make_sparse_layer('Script Layer', 127, {
            0: {'script': '初始化敌人模板 = _root.初始化敌人模板;\n初始化敌人模板();\nif(this.配置音效)\n{\n   this.配置音效("僵尸", this);\n}\n'},
            1: {'script': 'this.swapDepths(this._y);\n'},
            120: {'script': 'hp = 0;\n'},
        }),
        make_sparse_layer('文字信息层', 127, {
            0: {
                'duration': 120,
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 32'],
                        matrix=(1, 0, 0, 1, 1, -170.8),
                        symbol_type='movie clip',
                        name='人物文字信息',
                    )
                ],
            }
        }, locked='true'),
        make_sparse_layer('碰撞箱area层', 127, {
            0: {
                'duration': 88,
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 19'],
                        matrix=(2.11715698242188, 0, 0, 5.48248291015625, -26.45, -126.5),
                        symbol_type='movie clip',
                        name='area',
                    )
                ],
            },
            88: {
                'duration': 7,
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 19'],
                        matrix=(5.72386169433594, 0, 0, 1.68096923828125, -63.6, -31.65),
                        symbol_type='movie clip',
                        name='area',
                    )
                ],
            },
        }, outline='true', useOutlineView='true'),
        make_sparse_layer('思考标签层', 127, {
            0: {
                'duration': 29,
                'elements': [
                    instance(
                        SHARED_HELPERS['思考标签'],
                        matrix=(1, 0, 0, 1, -36, 16.35),
                        symbol_type='movie clip',
                    )
                ],
            }
        }),
        make_sparse_layer('行走控制块层', 127, {
            0: {
                'duration': 29,
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 15'],
                        matrix=(0.01446533203125, 0, 0, 0.0158538818359375, -31.5, -21),
                        symbol_type='movie clip',
                        name='控制块',
                        script='onClipEvent(enterFrame){\n   _parent.行走();\n}\n',
                        alpha_mult=0.0,
                    )
                ],
            }
        }),
        make_sparse_layer('被投area层', 127, {
            95: {
                'duration': 9,
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 113'],
                        matrix=(2.11715698242188, 0, 0, 5.48651123046875, 0, 0),
                        symbol_type='movie clip',
                        name='area',
                        script='onClipEvent(enterFrame){\n   this._rotation = _parent.man._rotation;\n}\n',
                    )
                ],
            }
        }),
        make_sparse_layer('动作man层', 127, {
            0: {
                'duration': 9,
                'elements': [
                    instance(
                        stand_name,
                        matrix=(1, 0, 0, 1, *off['stand']),
                        symbol_type='movie clip',
                        name='man',
                        script='onClipEvent(load){\n   gotoAndPlay(random(15));\n}\n',
                        add_adjust_filter=True,
                    )
                ],
            },
            9: {
                'duration': 10,
                'elements': [
                    instance(
                        walk_name,
                        matrix=(1, 0, 0, 1, *off['walk']),
                        symbol_type='movie clip',
                        name='man',
                        add_adjust_filter=True,
                    )
                ],
            },
            19: {
                'duration': 10,
                'elements': [
                    instance(
                        walk_name,
                        matrix=(1, 0, 0, 1, *off['walk']),
                        symbol_type='movie clip',
                        name='man',
                        add_adjust_filter=True,
                    )
                ],
            },
            41: {
                'duration': 10,
                'elements': [
                    instance(
                        atk_name,
                        matrix=(1, 0, 0, 1, *off['attack']),
                        symbol_type='movie clip',
                        name='man',
                        add_adjust_filter=True,
                    )
                ],
            },
            61: {
                'duration': 10,
                'elements': [
                    instance(
                        stand_name,
                        matrix=(1, 0, 0, 1, *off['stand']),
                        symbol_type='movie clip',
                        name='man',
                        script='onClipEvent(load){\n   gotoAndPlay(random(15));\n   躲闪 = true;\n}\nonClipEvent(unload){\n   躲闪 = false;\n}\n',
                        add_adjust_filter=True,
                    )
                ],
            },
            71: {
                'duration': 8,
                'elements': [
                    instance(
                        hit_name,
                        matrix=(1, 0, 0, 1, *off['hit']),
                        symbol_type='movie clip',
                        name='man',
                        script='onClipEvent(load){\n   gotoAndPlay("a" + random(2));\n}\n',
                        add_adjust_filter=True,
                    )
                ],
            },
            79: {
                'duration': 9,
                'elements': [
                    instance(
                        kd_name,
                        matrix=(1, 0, 0, 1, *off['down']),
                        symbol_type='movie clip',
                        name='man',
                        script='onClipEvent (load) {\n\t_parent.击飞浮空();\n}\n',
                        add_adjust_filter=True,
                    )
                ],
            },
            88: {
                'duration': 7,
                'elements': [
                    instance(
                        down_name,
                        matrix=(1, 0, 0, 1, *off['down']),
                        symbol_type='movie clip',
                        name='man',
                        script='onClipEvent (load) {\n\t_parent.击飞倒地();\n}',
                        add_adjust_filter=True,
                    )
                ],
            },
            95: {
                'duration': 9,
                'elements': [
                    instance(
                        grab_name,
                        matrix=(1, 0, 0, 1, 0, 0),
                        symbol_type='movie clip',
                        name='man',
                        script='onClipEvent(load){\n   gotoAndStop("a" + random(2));\n}\n',
                        add_adjust_filter=True,
                    )
                ],
            },
            104: {
                'duration': 16,
                'elements': [
                    instance(
                        death_name,
                        matrix=(1, 0, 0, 1, *off['death']),
                        symbol_type='movie clip',
                        name='man',
                        script='onClipEvent(load){\n   _root.播放音效("僵尸0" + (random(6) + 1) + ".wav");\n   gotoAndPlay("a" + random(3));\n}\n',
                        add_adjust_filter=True,
                    )
                ],
            },
        }),
        make_sparse_layer('接地阴影层', 127, {
            0: {
                'duration': 79,
                'elements': [
                    instance(
                        SHARED_HELPERS['Symbol 2'],
                        matrix=(0.319610595703125, 0, 0, 0.130126953125, -3.5, -0.35),
                        symbol_type='movie clip',
                        script=SHADOW_LOAD_SCRIPT,
                        add_adjust_filter=True,
                    )
                ],
            }
        }),
    ]
    symbols[root_name] = symbol(
        root_name,
        root_layers,
        symbol_type='movie clip',
        linkage=linkage,
        export_first_frame=True,
    )
    return symbols, root_name


def generate_male_zombie():
    prefix = 'Antigravity/CF6普通男僵尸'
    all_symbols = {}
    part_map = {}
    stats = []

    # 1. Live parts 393..402
    for cid, label in sorted(MALE_PART_LABELS.items()):
        sym_name = f'{prefix}/分件/{label}'
        part_map[cid] = sym_name
        svg_path = MALE_ARCHIVE / f'inputs/live/{cid}.svg'
        converted, rep = NativePart(svg_path, sym_name).build()
        all_symbols.update(converted)
        stats.append({'id': cid, 'name': sym_name, **rep})

    # 2. Build death-mapping lookup for 392 atlas fills -> single live part symbol + atlas offset
    shape_manifest = {
        s['id']: s
        for s in json.loads((MALE_ARCHIVE / 'inputs/death-reference/shape-manifest.json').read_text(encoding='utf-8'))
    }
    atlas_offsets = {}
    for cid in MALE_PART_LABELS:
        m = shape_manifest[cid]['fills'][0]['matrix']
        atlas_offsets[cid] = (1.0, 0.0, 0.0, 1.0, -float(m[4]), -float(m[5]))

    death_mapping = json.loads((MALE_ARCHIVE / 'death-mapping.json').read_text(encoding='utf-8'))
    fill_lookup_by_shape = {}
    for entry in death_mapping['shapes']:
        sid = entry['id']
        fmap = {}
        for bf in entry.get('bitmapFillsReplaced', []):
            live_id = bf['mappedLiveParts'][0]['liveId']
            fmap[f'd{sid}_fill{bf["fillIndex"]}'] = (part_map[live_id], atlas_offsets[live_id])
        fill_lookup_by_shape[sid] = fmap

    # 3. Death parts 409..475
    for cid in range(409, 476):
        sym_name = f'{prefix}/碎尸/{cid}'
        part_map[cid] = sym_name
        svg_path = MALE_ARCHIVE / f'death-parts/{cid}.svg'
        converted, rep = NativePart(svg_path, sym_name, male_fill_map=fill_lookup_by_shape.get(cid, {})).build()
        all_symbols.update(converted)
        stats.append({'id': cid, 'name': sym_name, **rep})

    # 4. Action & Death timelines
    live_tl = json.loads((MALE_ARCHIVE / 'inputs/live-timelines.json').read_text(encoding='utf-8'))
    death_tl_raw = json.loads((MALE_ARCHIVE / 'inputs/death-reference/death-timeline.json').read_text(encoding='utf-8'))
    death_frames = [f['instances'] for f in death_tl_raw['frames']]

    cfg = {
        'linkage': '敌人-CF6普通男僵尸',
        'stand_id': '403',
        'walk_id': '404',
        'attack_id': '405',
        'hit_id': '406',
        'down_id': '408',
        'hit_callbacks': (14, 36),
        'knockdown_pose_index': 0,
        'down_slice': (6, 79),
        'death_labels': (0, 77, 130),
        'death_callbacks': (76, 129, 172),
        'offsets': {
            'stand': (-19.05, -57.85),
            'walk': (-19.05, -57.85),
            'attack': (4.95, -63.8),
            'hit': (10.25, -60.3),
            'down': (5.7, -60.45),
            'death': (7.3, -60.6),
        },
    }
    act_symbols, root_name = build_action_clips(prefix, part_map, live_tl, death_frames, cfg)
    all_symbols.update(act_symbols)
    return all_symbols, {
        'character': 'CF6普通男僵尸',
        'linkage': cfg['linkage'],
        'root': root_name,
        'partCount': len(stats),
        'totalSymbols': len(all_symbols),
    }


def generate_female_zombie():
    prefix = 'Antigravity/CF6女僵尸'
    all_symbols = {}
    part_map = {}
    stats = []

    # 1. Shared uncropped head master symbol in 1618 atlas coordinates
    core_art = json.loads((FEMALE_ARCHIVE / 'source/core-art.json').read_text(encoding='utf-8'))
    head_master_name = f'{prefix}/分件/1627-头部母版'
    head_master_svg = f'<svg xmlns="http://www.w3.org/2000/svg">{core_art["1627"]["body"]}</svg>'
    converted, rep = NativePart(head_master_svg, head_master_name).build()
    all_symbols.update(converted)
    stats.append({'id': '1627-master', 'name': head_master_name, **rep})

    # 2. Live parts 1619..1628
    for cid, label in sorted(FEMALE_PART_LABELS.items()):
        sym_name = f'{prefix}/分件/{label}'
        part_map[cid] = sym_name
        svg_path = FEMALE_ARCHIVE / f'parts/{cid}.svg'
        converted, rep = NativePart(svg_path, sym_name, female_head_master=head_master_name).build()
        all_symbols.update(converted)
        stats.append({'id': cid, 'name': sym_name, **rep})

    # 3. Death parts 1635..1692
    for cid in range(1635, 1693):
        sym_name = f'{prefix}/碎尸/{cid}'
        part_map[cid] = sym_name
        svg_path = FEMALE_ARCHIVE / f'death-parts/{cid}.svg'
        converted, rep = NativePart(svg_path, sym_name, female_head_master=head_master_name).build()
        all_symbols.update(converted)
        stats.append({'id': cid, 'name': sym_name, **rep})

    # 4. Action & Death timelines
    timelines = json.loads((FEMALE_ARCHIVE / 'reference/timelines.json').read_text(encoding='utf-8'))
    death_frames = timelines['1693']

    cfg = {
        'linkage': '敌人-CF6女僵尸',
        'stand_id': '1629',
        'walk_id': '1630',
        'attack_id': '1631',
        'hit_id': '1632',
        'down_id': '1634',
        'hit_callbacks': (18, 40),
        'knockdown_pose_index': 5,
        'down_slice': (9, 89),
        'death_labels': (0, 79, 148),
        'death_callbacks': (78, 147, 190),
        'offsets': {
            'stand': (7.5, -59.55),
            'walk': (5.85, -60.55),
            'attack': (4.25, -63.55),
            'hit': (8.95, -59.95),
            'down': (5.5, -59.0),
            'death': (7.0, -60.15),
        },
    }
    act_symbols, root_name = build_action_clips(prefix, part_map, timelines, death_frames, cfg)
    all_symbols.update(act_symbols)
    return all_symbols, {
        'character': 'CF6女僵尸',
        'linkage': cfg['linkage'],
        'root': root_name,
        'partCount': len(stats),
        'totalSymbols': len(all_symbols),
    }


def write_workspace(generated_symbols: dict, root_symbols: list):
    OWNER.mkdir(parents=True, exist_ok=True)
    lib_dir = OWNER / 'LIBRARY'
    lib_dir.mkdir(parents=True, exist_ok=True)

    # 1. Anchor symbol Antigravity专用素材.xml
    anchor_name = 'Antigravity专用素材'
    anchor_elements = [
        instance(r, matrix=(1, 0, 0, 1, 180 + i * 160, 240), symbol_type='movie clip')
        for i, r in enumerate(root_symbols)
    ]
    anchor_sym = symbol(
        anchor_name,
        [
            layer('停止层', [frame(index=0, script='stop();')]),
            layer('导出引用层', [frame(index=0, elements=anchor_elements)]),
        ],
        symbol_type='movie clip',
        linkage=anchor_name,
        export_rs=True,
        url='flashswf/arts/new/Antigravity专用素材.swf',
    )
    all_symbols = {**generated_symbols, anchor_name: anchor_sym}

    # Write all symbol XMLs
    rows = []
    for name, tree in sorted(all_symbols.items()):
        rel = f'LIBRARY/{name}.xml'
        path = OWNER / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        data = xml_bytes(tree)
        path.write_bytes(data)
        rows.append({'path': rel, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})

    # Collect all folder paths
    folders = set()
    for name in all_symbols:
        parts = name.split('/')[:-1]
        for i in range(1, len(parts) + 1):
            folders.add('/'.join(parts[:i]))

    # Write DOMDocument.xml
    doc = E.Element(
        f'{{{XFL_NS}}}DOMDocument',
        nsmap={None: XFL_NS, 'xsi': XSI_NS},
        backgroundColor='#E5E3DF',
        width='550',
        height='400',
        frameRate='24',
        xflVersion='2.2',
        creatorInfo='Adobe Flash Professional CS6',
        platform='Windows',
        versionInfo='Saved by Adobe Flash Windows 12.0 build 481',
        majorVersion='12',
        buildNumber='481',
        nextSceneIdentifier='2',
    )
    folders_el = E.SubElement(doc, f'{{{XFL_NS}}}folders')
    for folder in sorted(folders):
        E.SubElement(folders_el, f'{{{XFL_NS}}}DOMFolderItem', name=folder, itemID=item_id(folder, '6af10000'))
    symbols_el = E.SubElement(doc, f'{{{XFL_NS}}}symbols')
    for name in sorted(all_symbols):
        E.SubElement(
            symbols_el,
            f'{{{XFL_NS}}}Include',
            href=f'{name}.xml',
            itemID=item_id(name),
            loadImmediate='false',
        )
    E.SubElement(doc, f'{{{XFL_NS}}}media')
    timelines_el = E.SubElement(doc, f'{{{XFL_NS}}}timelines')
    scene_tl = E.SubElement(timelines_el, f'{{{XFL_NS}}}DOMTimeline', name='场景 1')
    scene_layers = E.SubElement(scene_tl, f'{{{XFL_NS}}}layers')
    scene_layers.append(
        layer('共享导出锚点', [
            frame(
                index=0,
                script='stop();',
                elements=[instance(anchor_name, symbol_type='movie clip')],
            )
        ])
    )
    (OWNER / 'DOMDocument.xml').write_bytes(xml_bytes(doc))

    # Write Antigravity专用素材.xfl, MobileSettings.xml, PublishSettings.xml
    (OWNER / 'Antigravity专用素材.xfl').write_text('PROXY-CS5\n', encoding='utf-8')
    (OWNER / 'MobileSettings.xml').write_text('', encoding='utf-8')

    pub_template = (ROOT / 'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml').read_text(encoding='utf-8')
    pub_text = pub_template.replace('Codex黑仔素材.swf', 'Antigravity专用素材.swf').replace('Codex黑仔素材', 'Antigravity专用素材')
    (OWNER / 'PublishSettings.xml').write_text(pub_text, encoding='utf-8')
    return rows


def workspace_identity_failures(manifest: dict) -> list[str]:
    """Protect everything reimport replaces, including the library's exact file set."""
    if manifest.get('schema') != MANIFEST_SCHEMA:
        return ['native-manifest.json: missing v2 project-file baseline']
    outputs = manifest.get('outputs', [])
    project_files = manifest.get('projectFiles', [])
    if {entry['path'] for entry in project_files} != set(PROJECT_FILES):
        return ['native-manifest.json: incomplete project-file baseline']
    if not outputs or len(outputs) != manifest.get('nativeSymbolCount'):
        return ['native-manifest.json: incomplete library baseline']

    failures = []
    expected = set()
    for entry in outputs + project_files:
        rel = entry['path']
        path = pathlib.PurePosixPath(rel)
        if path.is_absolute() or '..' in path.parts or '\\' in rel or ':' in rel:
            return ['native-manifest.json: invalid relative path ' + rel]
        if rel in expected:
            return ['native-manifest.json: duplicate path ' + rel]
        expected.add(rel)
        target = OWNER / rel
        if not target.is_file():
            failures.append(rel + ': missing file')
        elif sha(target) != entry['sha256']:
            failures.append(rel + ': sha256 drift from native-manifest.json')

    expected_library = {entry['path'] for entry in outputs}
    if any(not rel.startswith('LIBRARY/') for rel in expected_library):
        return ['native-manifest.json: library output outside LIBRARY/']
    actual_library = {
        path.relative_to(OWNER).as_posix()
        for path in (OWNER / 'LIBRARY').rglob('*') if path.is_file()
    }
    failures.extend(rel + ': added library file' for rel in sorted(actual_library - expected_library))
    return failures


def guard_overwrite_allowed(force: bool = False):
    manifest_path = HERE / 'native-manifest.json'
    if force:
        return
    if not manifest_path.is_file():
        if not OWNER.exists() or not any(path.is_file() for path in OWNER.rglob('*')):
            return
        failures = ['native-manifest.json: no baseline for an existing native workspace']
    else:
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        failures = workspace_identity_failures(manifest)
    if failures:
        raise RuntimeError(
            'Refusing to overwrite native XFL changes without --force:\n  ' + '\n  '.join(failures[:20])
        )


def ensure_things_new_fla():
    import zipfile

    fla_path = ROOT / 'flashswf/arts/things-new.fla'
    antigravity_symbol_xml = (
        '<DOMSymbolItem xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xmlns="http://ns.adobe.com/xfl/2008/" name="Antigravity专用素材" '
        'itemID="6af00000-00000001" linkageImportForRS="true" '
        'linkageExportInFirstFrame="false" linkageIdentifier="Antigravity专用素材" '
        'linkageURL="flashswf/arts/new/Antigravity专用素材.swf">\r\n'
        '  <timeline>\r\n'
        '    <DOMTimeline name="Antigravity专用素材">\r\n'
        '      <layers>\r\n'
        '        <DOMLayer name="图层 1" color="#4FFF4F" current="true" isSelected="true">\r\n'
        '          <frames>\r\n'
        '            <DOMFrame index="0" keyMode="9728">\r\n'
        '              <elements>\r\n'
        '                </elements>\r\n'
        '            </DOMFrame>\r\n'
        '          </frames>\r\n'
        '        </DOMLayer>\r\n'
        '      </layers>\r\n'
        '    </DOMTimeline>\r\n'
        '  </timeline>\r\n'
        '</DOMSymbolItem>'
    )
    with zipfile.ZipFile(fla_path, 'r') as zin:
        items = [(info, zin.read(info.filename)) for info in zin.infolist()]
        has_sym = any(info.filename == 'LIBRARY/Antigravity专用素材.xml' for info, _ in items)
        doc_text = dict((info.filename, d.decode('utf-8', errors='ignore')) for info, d in items if info.filename in ('DOMDocument.xml', 'LIBRARY/things-new.xml'))
        if (
            has_sym
            and 'Antigravity专用素材.xml' in doc_text.get('DOMDocument.xml', '')
            and 'libraryItemName="Antigravity专用素材"' in doc_text.get('LIBRARY/things-new.xml', '')
        ):
            return False

    tmp_path = fla_path.with_suffix('.fla.tmp')
    with zipfile.ZipFile(tmp_path, 'w') as zout:
        has_ag = False
        for info, data in items:
            if info.filename == 'LIBRARY/Antigravity专用素材.xml':
                has_ag = True
                zout.writestr(info, antigravity_symbol_xml.encode('utf-8'))
            elif info.filename == 'DOMDocument.xml':
                text = data.decode('utf-8')
                inc = '<Include href="Antigravity专用素材.xml" itemID="6af00000-00000001" loadImmediate="false"/>'
                if 'Antigravity专用素材.xml' not in text:
                    text = text.replace('</symbols>', '     ' + inc + '</symbols>', 1)
                zout.writestr(info, text.encode('utf-8'))
            elif info.filename == 'LIBRARY/things-new.xml':
                text = data.decode('utf-8')
                nl = '\r\n' if '\r\n' in text else '\n'
                inst = (
                    f'              <DOMSymbolInstance libraryItemName="Antigravity专用素材">{nl}'
                    f'                  <matrix>{nl}'
                    f'                    <Matrix tx="1600" ty="500"/>{nl}'
                    f'                  </matrix>{nl}'
                    f'                  <transformationPoint>{nl}'
                    f'                    <Point/>{nl}'
                    f'                  </transformationPoint>{nl}'
                    f'                </DOMSymbolInstance>{nl}'
                )
                if 'libraryItemName="Antigravity专用素材"' not in text:
                    idx = text.find('<DOMSymbolInstance libraryItemName="Codex黑仔素材">')
                    if idx < 0:
                        raise RuntimeError('Codex黑仔素材 anchor not found in LIBRARY/things-new.xml')
                    end_tag = '</DOMSymbolInstance>'
                    end_idx = text.find(end_tag, idx)
                    insert_pos = end_idx + len(end_tag)
                    if text[insert_pos:insert_pos + 2] == '\r\n':
                        insert_pos += 2
                    elif text[insert_pos:insert_pos + 1] == '\n':
                        insert_pos += 1
                    text = text[:insert_pos] + inst + text[insert_pos:]
                zout.writestr(info, text.encode('utf-8'))
            else:
                zout.writestr(info, data)
        if not has_ag:
            zi = zipfile.ZipInfo('LIBRARY/Antigravity专用素材.xml')
            zi.compress_type = zipfile.ZIP_DEFLATED
            zout.writestr(zi, antigravity_symbol_xml.encode('utf-8'))
    tmp_path.replace(fla_path)
    return True


def import_assets(force: bool = False):
    guard_overwrite_allowed(force=force)
    shared = clone_shared_helpers()
    male_symbols, male_report = generate_male_zombie()
    female_symbols, female_report = generate_female_zombie()

    combined = {**shared, **male_symbols, **female_symbols}
    # Generation can take time; recheck before the first write to the native workspace.
    guard_overwrite_allowed(force=force)
    audio_receipt=audio.apply(combined,OWNER,make_sparse_layer)
    rows = write_workspace(combined, [male_report['root'], female_report['root']])
    ensure_things_new_fla()

    manifest = {
        'schema': MANIFEST_SCHEMA,
        'owner': str(OWNER.relative_to(ROOT).as_posix()),
        'approvedInput': str(ARCHIVE.relative_to(ROOT).as_posix()),
        'sharedHelperCount': len(shared),
        'characters': [male_report, female_report],
        'nativeSymbolCount': len(rows),
        'outputs': rows,
        'projectFiles': [
            {'path': rel, 'sha256': sha(OWNER / rel), 'bytes': (OWNER / rel).stat().st_size}
            for rel in PROJECT_FILES
        ],
    }
    manifest['audio']=audio_receipt
    (HERE / 'native-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({
        'importedSymbols': len(rows),
        'characters': [male_report['linkage'], female_report['linkage']],
    }, ensure_ascii=False))


def verify_compiled_swf(swf_path: pathlib.Path) -> dict:
    import struct
    import zlib

    raw = swf_path.read_bytes()
    sig = raw[:3].decode('ascii')
    body = zlib.decompress(raw[8:]) if sig == 'CWS' else raw[8:]
    nbits = body[0] >> 3
    pos = (5 + nbits * 4 + 7) // 8 + 4
    tags = {}
    exports = []
    bitmap_tags = {6, 20, 21, 35, 36, 90}
    shape_tags = {2, 22, 32, 83}
    while pos < len(body):
        hdr = struct.unpack_from('<H', body, pos)[0]
        pos += 2
        code = hdr >> 6
        length = hdr & 0x3F
        if length == 0x3F:
            length = struct.unpack_from('<I', body, pos)[0]
            pos += 4
        payload = body[pos : pos + length]
        pos += length
        tags[code] = tags.get(code, 0) + 1
        if code == 56:
            cnt = struct.unpack_from('<H', payload, 0)[0]
            p = 2
            for _ in range(cnt):
                tid = struct.unpack_from('<H', payload, p)[0]
                p += 2
                end = payload.index(0, p)
                exports.append(payload[p:end].decode('utf-8'))
                p = end + 1
        if code == 0:
            break
    bitmap_count = sum(tags.get(t, 0) for t in bitmap_tags)
    shape_count = sum(tags.get(t, 0) for t in shape_tags)
    expected_exports = {'Antigravity专用素材', '敌人-CF6普通男僵尸', '敌人-CF6女僵尸'}
    if bitmap_count != 0:
        raise ValueError(f'{swf_path}: expected 0 bitmap tags, got {bitmap_count}')
    if not expected_exports.issubset(set(exports)):
        raise ValueError(f'{swf_path}: missing exports {expected_exports - set(exports)}')
    return {
        'swfBytes': len(raw),
        'swfSha256': hashlib.sha256(raw).hexdigest(),
        'shapeTags': shape_count,
        'spriteTags': tags.get(39, 0),
        'bitmapTags': bitmap_count,
        'exports': sorted(exports),
    }


def _layer_bbox(root_el):
    xs, ys = [], []
    for edge in root_el.findall('.//x:Edge', NS):
        nums = [float(x) / 20.0 for x in re.findall(r'[-+]?\d+(?:\.\d+)?', edge.get('edges', ''))]
        xs.extend(nums[0::2])
        ys.extend(nums[1::2])
    for inst in root_el.findall('.//x:DOMSymbolInstance', NS):
        ref = inst.get('libraryItemName')
        mat = inst.find('x:matrix/x:Matrix', NS)
        a = float(mat.get('a', 1)) if mat is not None else 1.0
        b = float(mat.get('b', 0)) if mat is not None else 0.0
        c = float(mat.get('c', 0)) if mat is not None else 0.0
        d = float(mat.get('d', 1)) if mat is not None else 0.0
        tx = float(mat.get('tx', 0)) if mat is not None else 0.0
        ty = float(mat.get('ty', 0)) if mat is not None else 0.0
        sub_path = OWNER / 'LIBRARY' / f'{ref}.xml'
        if sub_path.is_file():
            sb = _layer_bbox(E.parse(str(sub_path), PARSER).getroot())
            if sb:
                for px in (sb[0], sb[1]):
                    for py in (sb[2], sb[3]):
                        xs.append(a * px + c * py + tx)
                        ys.append(b * px + d * py + ty)
    if not xs:
        return None
    return (min(xs), max(xs), min(ys), max(ys))


def check():
    manifest = json.loads((HERE / 'native-manifest.json').read_text(encoding='utf-8'))
    audio.check(manifest,OWNER)
    failures = workspace_identity_failures(manifest)
    mask_symbols_checked = 0
    for entry in manifest['outputs']:
        path = OWNER / entry['path']
        if not path.is_file():
            failures.append(entry['path'] + ': missing file')
            continue
        root = E.parse(str(path), PARSER).getroot()
        if root.findall('.//x:DOMBitmapInstance', NS) or root.findall('.//x:BitmapFill', NS):
            failures.append(entry['path'] + ': bitmap found')
        tl = root.find('x:timeline/x:DOMTimeline', NS)
        if tl is not None and tl.get('name') != root.get('name', '').rsplit('/', 1)[-1]:
            failures.append(entry['path'] + ': DOMTimeline.name is not leaf name')
        for e in root.iter():
            ref = e.get('libraryItemName')
            if ref and not (OWNER / 'LIBRARY' / f'{ref}.xml').is_file():
                failures.append(entry['path'] + ': unresolved ' + ref)
        layers = root.findall('.//x:DOMLayer', NS)
        if len(layers) == 2 and layers[0].get('layerType') == 'mask':
            mask_symbols_checked += 1
            mb = _layer_bbox(layers[0])
            cb = _layer_bbox(layers[1])
            if not mb or not cb:
                failures.append(entry['path'] + f': empty mask/content bbox ({mb} vs {cb})')
            else:
                ox = min(mb[1], cb[1]) - max(mb[0], cb[0])
                oy = min(mb[3], cb[3]) - max(mb[2], cb[2])
                if ox <= 0 or oy <= 0:
                    failures.append(entry['path'] + f': disjoint mask/content bbox ({mb} vs {cb})')
    if failures:
        raise ValueError('\n'.join(failures))
    report = {
        'nativeSymbolsChecked': len(manifest['outputs']),
        'projectFilesChecked': len(manifest['projectFiles']),
        'maskSymbolsChecked': mask_symbols_checked,
        'missingReferences': 0,
        'bitmapInstances': 0,
    }
    swf_path = ROOT / 'flashswf/arts/new/Antigravity专用素材.swf'
    if swf_path.is_file():
        report['compiledSwf'] = verify_compiled_swf(swf_path)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--import-approved', action='store_true')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    if args.import_approved:
        import_assets(force=args.force)
    check()
