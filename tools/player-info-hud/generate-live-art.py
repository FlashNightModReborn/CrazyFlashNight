"""Generate semantic HUD artwork from authored keyframes with the existing XFL exporter."""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json
import math
import copy
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
EXPORTER = ROOT / "tools/xfl-ui-svg/xfl_to_svg.py"
OUTPUT = ROOT / "launcher/src/Guardian/Hud/PlayerInfo/PlayerHudArt.Generated.cs"
MANIFEST = ROOT / "tools/player-info-hud/live-art.manifest.json"
UI = "flashswf/UI/玩家信息界面/LIBRARY"
BUFF = "flashswf/arts/新版人物文字信息/LIBRARY"
RECIPES = [
    # The full-width chassis lives inside the XP symbol, not in the root HUD.
    ("bottom-panel", UI, "sprite/Symbol 1859", 0, ["大背景"]),
    ("bottom-ornaments", UI, "sprite/Symbol 1859", 0, ["装饰性"]),
    ("level-label", UI, "sprite/Symbol 1859", 0, ["LV 矢量图"]),
    ("slot", UI, "UI重构/快捷道具格子", 0, None),
    ("slot-detail", UI, "UI重构/快捷道具格子", 0, ["图层 2"]),
    ("drug-hover", UI, "sprite/物品栏/物品满级框", 0, None),
    ("weapon", UI, "sprite/战技图标", 0, None),
    ("buff", BUFF, "素材-buff详细图标/buff边框", 0, None),
    ("buff-panel", "CRAZYFLASHER7MercenaryEmpire/LIBRARY", "玩家buff界面素材/玩家buff界面边框", 0, None),
    ("skill-panel", UI, "sprite/快捷技能界面", 0, ["边框"]),
    ("drug-panel", UI, "sprite/快捷药剂界面", 1, ["装饰"]),
    ("name-background", UI, "UI重构/姓名动画", 0, ["边框", "遮罩", "背景"]),
    ("name-grid", UI, "UI重构/血槽相关/姓名动画-网格背景", 0, None),
    ("bank-0", UI, "sprite/药剂组切换图标", 0, None),
    ("bank-1", UI, "sprite/药剂组切换图标", 1, None),
    ("weapon-panel", UI, "sprite/玩家必要信息界面", 1, ["战技文字 矢量化", "战技背景", "空战技"]),
    ("unequip", UI, "sprite/Symbol 1792", 0, None),
    ("cooldown-cover", UI, "shape/Symbol 861", 0, None),
    ("buff-opening", BUFF, "素材-buff详细图标/buff开启动画", 1, ["图层 1"]),
] + [(f"mode-{i}", UI, "sprite/玩家必要信息界面", frame,
      ["战斗模式文字 矢量化", "图标", "背景"])
     for i, frame in enumerate([1, 6, 12, 17, 22, 27, 32, 37])]

# These authored 0.1-unit decorative strokes become subpixel alpha in native
# rasterization. Compensate only the live frame/detail recipes, not B0 or motion.
HAIRLINE_RECIPES = {'slot', 'slot-detail', 'bottom-ornaments', 'skill-panel', 'drug-panel', 'weapon-panel'}
LIVE_HAIRLINE_WIDTH = 0.6


def sha(data):
    return hashlib.sha256(data).hexdigest()


def generate():
    spec = importlib.util.spec_from_file_location("player_hud_xfl_export", EXPORTER)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    sources = {EXPORTER, Path(__file__).resolve()}
    recipes = []
    cases = []
    rectangles = []
    original_renderer = module.Renderer

    class HudRenderer(original_renderer):
        """Select named authored layers; retain layer indices so masks keep their owners."""
        def _mask_index_of(self, layers, index):
            # HUD timelines also parent ordinary layers to folders, which are not masks.
            visited = set()
            while layers[index].get('parentLayerIndex') is not None:
                index = int(layers[index].get('parentLayerIndex'))
                if index in visited:
                    raise ValueError('Cyclic authored layer hierarchy')
                visited.add(index)
                if layers[index].get('layerType') == 'mask':
                    return index
            return None

        def load(self, name):
            if name in self.cache:
                return self.cache[name]
            tree = copy.deepcopy(super().load(name))
            self.cache[name] = tree
            if name == symbol and selected is not None:
                layers = tree.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', module.NS)
                kept = {i for i, layer in enumerate(layers) if layer.get('name') in selected}
                for i in list(kept):
                    parent = layers[i].get('parentLayerIndex')
                    while parent is not None:
                        kept.add(int(parent))
                        parent = layers[int(parent)].get('parentLayerIndex')
                for i, layer in enumerate(layers):
                    if i not in kept:
                        frames = layer.find('x:frames', module.NS)
                        if frames is not None:
                            frames.clear()
            # CS6 uses isVisible for instances; hidden instances have no authored pixels.
            for parent in tree.iter():
                for child in list(parent):
                    if child.get('isVisible') == 'false':
                        parent.remove(child)
                    elif child.get('isEnabled') == 'false':
                        parent.remove(child)
                    elif name in ('sprite/玩家必要信息界面', 'shape/Symbol 1814') and child.tag.endswith('}DOMShape') and child.find('.//x:BitmapFill', module.NS) is not None:
                        # The exact 6x9/7x9 pixels are separate source-bound ammo assets.
                        paths = {v.get('bitmapPath') for v in child.findall('.//x:BitmapFill', module.NS)}
                        if not paths or not paths.issubset({'image/bitmap1804.png', 'image/bitmap1805.png'}):
                            raise ValueError('Unaccounted HUD bitmap fill')
                        parent.remove(child)
            return tree

    module.Renderer = HudRenderer
    with tempfile.TemporaryDirectory(prefix="cf7-player-hud-art-") as temporary:
        for key, library, symbol, frame, selected in RECIPES:
            renderer, svg, label = module.export(
                str(ROOT / library), symbol, frame, (128, 128), Path(temporary), [], {})
            if renderer.unsupported:
                raise ValueError(f"Unsupported authored art: {symbol}: {renderer.unsupported}")
            bounds = renderer.symbol_bbox(symbol, frame)
            if bounds is None:
                raise ValueError(f"Empty authored art: {symbol}")
            # Crop to the authored geometry with one logical pixel for its stroke.
            left, top, right, bottom = bounds
            pad = 14 if key == 'drug-hover' else 4 if key == 'buff-panel' else 1
            view = [left - pad, top - pad, right - left + pad * 2, bottom - top + pad * 2]
            document = ET.fromstring(svg)
            document.set("viewBox", " ".join(format(v, ".8g") for v in view))
            document.set("width", str(math.ceil(view[2])))
            document.set("height", str(math.ceil(view[3])))
            document.set("preserveAspectRatio", "none")
            compensated = 0
            if key in HAIRLINE_RECIPES:
                for element in document.iter():
                    width = float(element.get('stroke-width', '0'))
                    if 0 < width <= 0.100001:
                        element.set('stroke-width', str(LIVE_HAIRLINE_WIDTH))
                        compensated += 1
            # Provenance stays in the manifest; the runtime consumes the strict SVG profile.
            for element in document.iter():
                for attribute in list(element.attrib):
                    if attribute.startswith("data-"):
                        del element.attrib[attribute]
            # The existing strict runtime profile represents fill alpha on a group.
            # Exported paths have no stroke; do not broaden the renderer's allowed features.
            for parent in list(document.iter()):
                for index, child in enumerate(list(parent)):
                    opacity = child.attrib.pop("fill-opacity", None)
                    if opacity is None:
                        continue
                    if child.get("stroke") not in (None, "none"):
                        raise ValueError("A stroked path needs separate fill/stroke ownership")
                    wrapper = ET.Element("{http://www.w3.org/2000/svg}g", {"opacity": opacity})
                    parent.remove(child)
                    wrapper.append(child)
                    parent.insert(index, wrapper)
            data = ET.tostring(document, encoding="utf-8")
            sources.update(renderer.sources)
            if key == 'drug-hover':
                sources.add(ROOT / UI / 'sprite/物品栏/物品互动提示.xml')
            recipes.append({"id": key, "library": library, "symbol": symbol, "frame": frame,
                            "layers": selected,
                            "viewBox": view, "svgSha256": sha(data), "bytes": len(data),
                            "textFields": renderer.fields,
                            "hairlineCompensation": {"count": compensated, "maximumSourceWidth": 0.1, "liveWidth": LIVE_HAIRLINE_WIDTH} if compensated else None})
            encoded = base64.b64encode(data).decode("ascii")
            cases.append(f'        "{key}" => Convert.FromBase64String("{encoded}"),')
            rectangles.append(f'        "{key}" => new({", ".join(format(v, ".8g") + "f" for v in view)}),')
    symbols_path = ROOT / 'tools/player-info-hud/live-symbols.provenance.json'
    # Both live resource bars use the authored MP cells, including their tilt
    # and spacing. Keep the frozen B0 artwork and its manifest unchanged.
    mp_fill_path = ROOT / 'launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/fill.svg'
    gauge_manifest = ROOT / 'launcher/src/Guardian/Hud/PlayerInfo/Assets/player-info.manifest.json'
    sources.update([mp_fill_path,gauge_manifest])
    mp_tree = ET.parse(mp_fill_path)
    parents = {child:parent for parent in mp_tree.iter() for child in parent}
    bar = next(e for e in mp_tree.iter() if e.get('id') == 'mp-fill-path-0003')
    def affine(text):
        return [float(v) for v in text.removeprefix('matrix(').removesuffix(')').split()]
    ancestry=[]; ancestor=bar
    while ancestor in parents:
        ancestor=parents[ancestor]
        if ancestor.get('transform'): ancestry.append(affine(ancestor.get('transform')))
    gauge = json.loads(gauge_manifest.read_text(encoding='utf-8-sig'))['gauges']['mp']
    cells=[]
    for contour in bar.get('d').split('M')[1:]:
        assert not re.search('[A-KN-Yac-z]',contour), 'MP cells must remain line-only polygons'
        values = [float(v) for v in re.findall(r'-?\d+(?:\.\d+)?',contour)]
        assert len(values)==10 and values[:2]==values[-2:]
        points=[]
        for i in range(0,8,2):
            point=(values[i],values[i+1])
            for matrix in ancestry: point=module.transform_point(matrix,point)
            point=module.transform_point(gauge['stageMatrix'],point)
            points.append((point[0],point[1]+512))
        cells.append(points)
    cells.sort(key=lambda c:min(p[0] for p in c))
    assert len(cells)==10
    bx=min(p[0] for c in cells for p in c);by=min(p[1] for c in cells for p in c)
    bw=max(p[0] for c in cells for p in c)-bx;bh=max(p[1] for c in cells for p in c)-by
    number=lambda v:format(v,'.12g')+'f'
    bar_code=('\ninternal static class PlayerHudBarArtData\n{\n'
      + '    internal static readonly RectangleF MpBounds = new('+', '.join(number(v) for v in [bx,by,bw,bh])+');\n'
      + '    internal static readonly PointF[][] Cells = [\n'
      + ',\n'.join('        ['+', '.join('new('+number(x)+', '+number(y)+')' for x,y in c)+']' for c in cells)
      + '\n    ];\n}\n')
    # Live-only decomposition of the accepted rim. B0's eight SVGs remain untouched.
    rim_path = ROOT / 'launcher/src/Guardian/Hud/PlayerInfo/Assets/hp/rim.svg'
    sources.add(rim_path)
    rim = ET.fromstring(rim_path.read_bytes())
    svg_ns = {'s':'http://www.w3.org/2000/svg'}
    for key, kept in [('hp-motion-base', {'hp-rim-layer-0001','hp-rim-static-bevel-expanded'}),
                      ('hp-motion-center', {'hp-rim-layer-0017'})]:
        doc = copy.deepcopy(rim)
        body = doc.find('s:g', svg_ns)
        for child in list(body):
            if child.get('id') not in kept: body.remove(child)
        data = ET.tostring(doc, encoding='utf-8')
        view = [float(v) for v in doc.get('viewBox').split()]
        cases.append(f'        "{key}" => Convert.FromBase64String("{base64.b64encode(data).decode("ascii")}"),')
        rectangles.append(f'        "{key}" => new({", ".join(format(v,".8g")+"f" for v in view)}),')
        recipes.append({'id':key,'canonicalSvg':rim_path.relative_to(ROOT).as_posix(),'retainedGroups':sorted(kept),'viewBox':view,'svgSha256':sha(data),'bytes':len(data)})

    def path_at(path_id):
        return next(e.get('d') for e in rim.iter() if e.get('id') == path_id)
    def matrix_at(group_id):
        text = next(e.get('transform') for e in rim.iter() if e.get('id') == group_id)
        return [float(v) for v in text.removeprefix('matrix(').removesuffix(')').split()]
    motion_root = ROOT / UI / 'UI重构/血槽相关'
    grid_path = motion_root/'血槽内动画-网格背景.xml'
    light_path = motion_root/'血槽光效.xml'
    tween_path = motion_root/'血槽内动画.xml'
    sources.update([grid_path,light_path,tween_path])
    separator_source = ROOT / UI / '横线.xml'
    hp_source = ROOT / UI / 'sprite/主角hp显示界面.xml'
    sources.update([separator_source,hp_source])
    # The authored "line" also contains a small fixed percent mark (fillStyle1).
    # Live text owns its percent sign, so extract just the original rule edges.
    rule_edges = ET.parse(separator_source).findall('.//x:Edge',module.NS)
    rule_edges = [e for e in rule_edges if e.get('fillStyle0') == '1']
    assert len(rule_edges) == 1
    separator_path = ''.join(module.segments_to_d(module.edge_segments(e.get('edges'))) for e in rule_edges)
    separator_instance = next(e for e in ET.parse(hp_source).findall('.//x:DOMSymbolInstance',module.NS) if e.get('libraryItemName') == '横线')
    separator_matrix = module.parse_matrix(separator_instance.find('x:matrix/x:Matrix',module.NS))
    def shape_path(frame):
        return ''.join(module.segments_to_d(module.edge_segments(e.get('edges')))
                       for e in frame.findall('.//x:Edge',module.NS) if e.get('edges'))
    grid_frames = [f for f in ET.parse(grid_path).findall('.//x:DOMFrame',module.NS) if f.find('x:elements/x:DOMShape',module.NS) is not None]
    assert [int(f.get('index')) for f in grid_frames] == list(range(11))
    light_frames = [f for f in ET.parse(light_path).findall('.//x:DOMFrame',module.NS) if f.find('.//x:RadialGradient',module.NS) is not None]
    assert [int(f.get('index')) for f in light_frames] == list(range(49,150))
    centers=[]
    for frame in light_frames:
        gradient = frame.find('.//x:RadialGradient',module.NS)
        matrix = module.parse_matrix(gradient.find('x:matrix/x:Matrix',module.NS))
        assert matrix[:4] == (0.059112548828125,0,0,0.059112548828125)
        assert [(float(s.get('alpha','1')),float(s.get('ratio'))) for s in gradient.findall('x:GradientEntry',module.NS)] == [(0,.474509803921569),(.6,.776470588235294),(0,1)]
        centers.append(matrix[4:])
    def floats(values): return ', '.join(format(v,'.12g')+'f' for v in values)
    def strings(values): return ',\n        '.join(json.dumps(v) for v in values)
    tween = ET.parse(tween_path)
    def motion_pose(layer_name):
        layer = next(l for l in tween.findall('.//x:DOMLayer',module.NS) if l.get('name') == layer_name)
        inst = [f.find('x:elements/x:DOMSymbolInstance',module.NS) for f in layer.findall('x:frames/x:DOMFrame',module.NS)]
        assert len(inst) == 2
        pivot = inst[0].find('x:transformationPoint/x:Point',module.NS)
        px,py = float(pivot.get('x','0')),float(pivot.get('y','0'))
        values=[px,py]
        for el in inst:
            m=module.parse_matrix(el.find('x:matrix/x:Matrix',module.NS))
            values += [math.degrees(math.atan2(m[1],m[0])),math.hypot(m[0],m[1]),*module.transform_point(m,(px,py))]
        return values
    motion_code = ('\ninternal static class PlayerHudHpMotionData\n{\n'
        + '    internal const string SeparatorPath = '+json.dumps(separator_path)+';\n'
        + '    internal static readonly float[] SeparatorMatrix = ['+floats(separator_matrix)+'];\n'
        + '    internal const string MotifA = '+json.dumps(path_at('hp-rim-path-0013'))+';\n'
        + '    internal const string MotifB = '+json.dumps(path_at('hp-rim-path-0016'))+';\n'
        + '    internal static readonly float[] MatrixA = ['+floats(matrix_at('hp-rim-shape-0012'))+'];\n'
        + '    internal static readonly float[] MatrixB = ['+floats(matrix_at('hp-rim-shape-0015'))+'];\n'
        + '    internal static readonly float[] PoseA = ['+floats(motion_pose('图层 1'))+'];\n'
        + '    internal static readonly float[] PoseB = ['+floats(motion_pose('图层 2'))+'];\n'
        + '    internal static readonly string[] GridPaths = [\n        '+strings(shape_path(f) for f in grid_frames)+'\n    ];\n'
        + '    internal static readonly string[] LightPaths = [\n        '+strings(shape_path(f) for f in light_frames)+'\n    ];\n'
        + '    internal static readonly float[] LightCenters = ['+floats([v for pair in centers for v in pair])+'];\n}\n')
    symbols = json.loads(symbols_path.read_text(encoding='utf-8'))
    sources.add(symbols_path)
    for asset in symbols['assets']:
        path = ROOT / asset['path']; data = path.read_bytes(); key = asset['id']
        if sha(data).upper() != asset['sha256']:
            raise ValueError(f'Source-bound HUD asset drift: {key}')
        sources.add(path)
        document = ET.fromstring(data)
        view = [float(v) for v in document.get('viewBox').split()]
        cases.append(f'        "{key}" => Convert.FromBase64String("{base64.b64encode(data).decode("ascii")}"),')
        rectangles.append(f'        "{key}" => new({", ".join(format(v, ".8g") + "f" for v in view)}),')
        recipes.append({'id':key, 'canonicalSvg':asset['path'], 'viewBox':view, 'svgSha256':sha(data), 'bytes':len(data)})
    code = ("// Generated by tools/player-info-hud/generate-live-art.py. Do not edit.\n"
            "using System;\nusing System.Drawing;\nnamespace CF7Launcher.Guardian.Hud.PlayerInfo;\n"
            "internal static class PlayerHudArtData\n{\n"
            "    internal static byte[] Get(string id) => id switch\n    {\n" +
            "\n".join(cases) + "\n        _ => throw new ArgumentException(\"Unknown HUD art\", nameof(id))\n    };\n"
            "    internal static RectangleF Bounds(string id) => id switch\n    {\n" +
            "\n".join(rectangles) + "\n        _ => throw new ArgumentException(\"Unknown HUD art\", nameof(id))\n    };\n"
            '    internal static readonly string[] Ids = [' + ', '.join(json.dumps(r['id']) for r in recipes) + '];\n}\n' + motion_code + bar_code)
    manifest = {"version": 1, "recipes": recipes,
                "liveBarGeometry":{"source":"mp-fill-path-0003","cells":len(cells),"nativeBounds":[bx,by,bw,bh]},
                "hpMotion":{"motifFrames":100,"gridFrames":11,"lightLoopFrames":216,"lightActiveFrames":[49,149],"pathsAreSourceKeyframesNotBakedImages":True,"liveSeparatorExcludesFixedPercent":True},
                "sources": [{"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p.read_bytes())}
                            for p in sorted(sources, key=lambda p: p.as_posix())],
                "output": {"path": OUTPUT.relative_to(ROOT).as_posix(), "sha256": sha(code.encode("utf-8"))}}
    return code, json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    code, manifest = generate()
    for path, content in [(OUTPUT, code), (MANIFEST, manifest)]:
        if args.check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                raise SystemExit(f"Stale generated HUD art: {path.relative_to(ROOT)}")
        else:
            path.write_text(content, encoding="utf-8", newline="\n")
    print(f"Live HUD art {'checked' if args.check else 'generated'}: {len(json.loads(manifest)['recipes'])} authored assets")


if __name__ == "__main__":
    main()
