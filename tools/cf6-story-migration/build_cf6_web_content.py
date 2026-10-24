#!/usr/bin/env python3
import argparse
import copy
import hashlib
import html
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parents[2]
TOOLS = REPO / "tools" / "cf6-story-migration"
FRAGMENT = TOOLS / "generated" / "comic-story.fragment.json"
INDEX = TOOLS / "generated" / "cf6-story-index.extracted.json"
ASSETS = REPO / "flashswf" / "arts" / "new" / "Codex素材源稿" / "CF6漫画过场"
ASSET_MANIFEST = ASSETS / "MANIFEST.json"
MIRROR = REPO / "launcher" / "web" / "assets" / "book-comic" / "cf6"
CONTENT_JS = REPO / "launcher" / "web" / "modules" / "book-comic-cf6-content.js"
CONTENT_JSON = TOOLS / "generated" / "cf6-web-content.json"
SEGMENT_IDS = [f"cf6-s{i}" for i in range(1, 8)]
SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
FFDEC = "https://www.free-decompiler.com/flash"
ET.register_namespace("", SVG)
ET.register_namespace("xlink", XLINK)
ET.register_namespace("ffdec", FFDEC)


class BuildError(RuntimeError):
    pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def rel_path(path):
    return path.relative_to(REPO).as_posix()


def safe_relative(value):
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        raise BuildError(f"illegal relative path: {value!r}")
    if any(ord(character) < 32 for character in value):
        raise BuildError(f"illegal relative path: {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute() or not pure.parts or pure.as_posix() != value or any(part in ("", ".", "..") for part in pure.parts):
        raise BuildError(f"illegal relative path: {value!r}")
    return pure


def contained(root, relative):
    target = (root / Path(*safe_relative(relative).parts)).resolve()
    try:
        target.relative_to(root.resolve())
    except ValueError as error:
        raise BuildError(f"path escapes authorized root: {target}") from error
    return target


def number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise BuildError(f"invalid number {label}: {value!r}")
    return float(value)


class EditTextParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.font = {}

    def handle_starttag(self, tag, attrs):
        if tag.lower() in ("sbr", "br"):
            self.parts.append("\n")
        if tag.lower() == "font" and not self.font:
            self.font = dict(attrs)

    def handle_endtag(self, tag):
        if tag.lower() == "p":
            self.parts.append("\n")

    def handle_data(self, data):
        self.parts.append(data)

    def lines(self):
        lines = "".join(self.parts).replace("\r", "").split("\n")
        while lines and not lines[-1]:
            lines.pop()
        return lines or [""]


def plain_text(record):
    return html.unescape(record.get("plainText") or "")


def parse_edit_text(record):
    parser = EditTextParser()
    parser.feed(record.get("htmlOriginal") or html.escape(record.get("plainText") or ""))
    parser.close()
    plain = plain_text(record)
    if not plain.strip():
        raise BuildError(f"missing original plainText for char {record.get('charId')}")
    lines = parser.lines()
    if re.sub(r"\s+", "", "".join(lines)) != re.sub(r"\s+", "", plain):
        raise BuildError(f"HTML/plain mismatch for char {record.get('charId')}")
    return lines, parser.font


def text_element(use, record):
    lines, font = parse_edit_text(record)
    group = ET.Element(f"{{{SVG}}}g", {"transform": use.get("transform", "")})
    size = number(float(font.get("size", 12)), "font size")
    attrs = {
        "x": "0", "y": "0", "fill": font.get("color", "#000000"),
        "font-family": font.get("face", "宋体") + ", SimSun, serif",
        "font-size": str(size), "dominant-baseline": "text-before-edge",
        "data-cf6-char-id": str(record["charId"]),
    }
    text = ET.SubElement(group, f"{{{SVG}}}text", attrs)
    text.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    for index, line in enumerate(lines):
        tspan = ET.SubElement(text, f"{{{SVG}}}tspan", {"x": "0"})
        if index:
            tspan.set("dy", "1.2em")
        tspan.text = line
    return group


class SvgAssembler:
    def __init__(self):
        self.root = None
        self.main = None
        self.defs = None
        self.interned = {}
        self.placements = set()

    def initialize(self, width, height):
        self.root = ET.Element(f"{{{SVG}}}svg", {
            "width": f"{width:g}px", "height": f"{height:g}px",
            "viewBox": f"0 0 {width:g} {height:g}",
        })
        self.main = ET.SubElement(self.root, f"{{{SVG}}}g")
        self.defs = ET.SubElement(self.root, f"{{{SVG}}}defs")

    def intern_def(self, page_defs, ref):
        if ref not in page_defs:
            raise BuildError(f"missing SVG definition #{ref}")
        original = page_defs[ref]
        signature = ET.tostring(original, encoding="utf-8")
        digest = sha(signature)
        new_id = "d" + digest[:20]
        if digest in self.interned:
            return new_id
        self.interned[digest] = new_id
        cloned = copy.deepcopy(original)
        id_map = {}
        for element in cloned.iter():
            old_id = element.get("id")
            if old_id:
                id_map[old_id] = new_id if element is cloned else f"{new_id}_{len(id_map)}"
        def resolve_ref(old):
            return id_map[old] if old in id_map else self.intern_def(page_defs, old)
        for element in cloned.iter():
            if element.get("id"):
                element.set("id", id_map[element.get("id")])
            for key, value in list(element.attrib.items()):
                if key == f"{{{XLINK}}}href" and value.startswith("#"):
                    old = value[1:]
                    element.set(key, "#" + resolve_ref(old))
                elif "url(#" in value:
                    def replace(match):
                        return "url(#" + resolve_ref(match.group(1)) + ")"
                    element.set(key, re.sub(r"url\(#([^\)]+)\)", replace, value))
        self.defs.append(cloned)
        return new_id

    def add_page(self, svg_path, width, height, texts_by_id):
        tree = ET.parse(svg_path)
        source = tree.getroot()
        number(float(source.get("width", "").removesuffix("px")), "SVG width")
        number(float(source.get("height", "").removesuffix("px")), "SVG height")
        if self.root is None:
            self.initialize(width, height)
        source_defs = source.find(f"{{{SVG}}}defs")
        page_defs = {element.get("id"): element for element in (list(source_defs) if source_defs is not None else [])}
        main = source.find(f"{{{SVG}}}g")
        if main is None:
            raise BuildError(f"missing SVG placement group: {svg_path}")
        background_found = any(
            use.tag == f"{{{SVG}}}use"
            and abs(float(use.get("width", "0")) - width) <= 0.01
            and abs(float(use.get("height", "0")) - height) <= 0.01
            for use in list(main)
        )
        if not background_found:
            raise BuildError(f"SVG has no original full-canvas background: {svg_path}")
        page_texts = []
        seen_page_texts = set()
        for use in list(main):
            if use.tag != f"{{{SVG}}}use":
                raise BuildError(f"unsupported SVG placement in {svg_path}: {use.tag}")
            char_id = int(use.get(f"{{{FFDEC}}}characterId", "0"))
            href = use.get(f"{{{XLINK}}}href", "")
            if char_id in texts_by_id or href.startswith("#text"):
                if char_id not in texts_by_id:
                    raise BuildError(f"missing DefineEditText {char_id} in {svg_path}")
                placed = text_element(use, texts_by_id[char_id])
                if char_id not in seen_page_texts:
                    page_texts.append({"charId": char_id, "text": plain_text(texts_by_id[char_id])})
                    seen_page_texts.add(char_id)
            else:
                if not href.startswith("#"):
                    raise BuildError(f"external SVG reference rejected: {href}")
                placed = copy.deepcopy(use)
                placed.set(f"{{{XLINK}}}href", "#" + self.intern_def(page_defs, href[1:]))
            signature = ET.tostring(placed, encoding="utf-8")
            if signature not in self.placements:
                self.placements.add(signature)
                self.main.append(placed)
        return page_texts

    def bytes(self):
        if self.root is None:
            raise BuildError("empty SVG")
        return ET.tostring(self.root, encoding="utf-8", xml_declaration=True)


class AssetReader:
    def __init__(self, manifest):
        self.manifest = manifest
        self.used = {}

    def read(self, relative):
        path = contained(ASSETS, relative)
        if not path.is_file():
            raise BuildError(f"missing source asset: {relative}")
        data = path.read_bytes()
        digest = sha(data)
        expected = self.manifest.get("files", {}).get(relative)
        if expected != digest:
            raise BuildError(f"source hash mismatch: {relative}")
        self.used[relative] = digest
        return data


def read_json(path):
    if not path.is_file():
        raise BuildError(f"missing input: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def timeline_duration(segment, page_index):
    original = segment["original"]
    advances = original["advance"]["stripFrames"]
    frames = original["stripFrames"]
    fps = number(original["fps"], "fps")
    if len(advances) != len(segment["pages"]) or frames <= 0 or fps <= 0:
        raise BuildError(f"invalid timeline: {segment['id']}")
    start = 0 if page_index == 0 else advances[page_index - 1]
    end = advances[page_index] if page_index < len(advances) - 1 else frames
    if end <= start:
        raise BuildError(f"invalid page frame range: {segment['id']} page {page_index + 1}")
    return round((end - start) / fps, 4)


def credits_svg(records):
    root = ET.Element(f"{{{SVG}}}svg", {"width": "1024px", "height": "384px", "viewBox": "0 0 1024 384"})
    ET.SubElement(root, f"{{{SVG}}}rect", {"width": "1024", "height": "384", "fill": "#050505"})
    for index, record in enumerate(records):
        raw = record.get("ffdecFormatted", "")
        value = html.unescape(raw[raw.rfind("]") + 1:].strip())
        if not value:
            raise BuildError(f"empty credits text: {record.get('charId')}")
        column = 0 if index < 10 else 1
        row = index if column == 0 else index - 10
        text = ET.SubElement(root, f"{{{SVG}}}text", {
            "x": str(48 + column * 500), "y": str(38 + row * 32),
            "fill": "#ffffff", "font-size": "20", "font-family": "Microsoft YaHei, SimSun, sans-serif",
            "data-cf6-char-id": str(record["charId"]),
        })
        text.text = value
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def build():
    fragment = read_json(FRAGMENT)
    index = read_json(INDEX)
    asset_manifest = read_json(ASSET_MANIFEST)
    if fragment.get("source", {}).get("sha256") != asset_manifest.get("sourceSwf", {}).get("sha256"):
        raise BuildError("fragment/asset manifest SWF identity mismatch")
    segments = {segment.get("id"): segment for segment in fragment.get("segments", [])}
    if set(segments) != set(SEGMENT_IDS):
        raise BuildError("fragment must contain exactly cf6-s1..cf6-s7")
    reader = AssetReader(asset_manifest)
    mirror = {}
    pages = []
    for segment_id in SEGMENT_IDS:
        segment = segments[segment_id]
        source_texts = json.loads(reader.read(f"{segment_id}/texts.json").decode("utf-8"))
        texts_by_id = {record["charId"]: record for record in source_texts}
        if len(texts_by_id) != len(source_texts):
            raise BuildError(f"duplicate text charId: {segment_id}")
        art = segment["original"].get("pageArtOriginal", {}).get("asset")
        if art:
            reader.read(art)
        assembler = SvgAssembler()
        panels = []
        seen_texts = set()
        for page_index, page in enumerate(segment.get("pages", [])):
            if page.get("index") != page_index + 1:
                raise BuildError(f"missing/reordered page: {segment_id} {page_index + 1}")
            canvas = page.get("canvasPx")
            if not isinstance(canvas, list) or len(canvas) != 2:
                raise BuildError(f"missing canvas: {segment_id} page {page_index + 1}")
            width, height = number(canvas[0], "canvas width"), number(canvas[1], "canvas height")
            rect = page.get("viewportRect")
            if not isinstance(rect, list) or len(rect) != 4:
                raise BuildError(f"missing viewportRect: {segment_id} page {page_index + 1}")
            rect = [number(value, "viewportRect") for value in rect]
            if not (0 <= rect[0] < 1 and 0 <= rect[1] < 1 and 0 < rect[2] <= 1 and 0 < rect[3] <= 1):
                raise BuildError(f"invalid viewportRect: {segment_id} page {page_index + 1}")
            visual = page.get("visual")
            svg_data = reader.read(visual)
            svg_path = contained(ASSETS, visual)
            page_texts = assembler.add_page(svg_path, width, height, texts_by_id)
            if not page_texts:
                raise BuildError(f"page has no original visible text: {segment_id} page {page_index + 1}")
            seen_texts.update(item["charId"] for item in page_texts)
            panels.append({
                "id": f"p{page_index + 1}", "label": f"page {page_index + 1}",
                "rect": rect, "duration": timeline_duration(segment, page_index),
                "fragmentDurationSec": number(page.get("durationSec"), "fragment duration"),
                "sourceVisual": visual, "sourcePanPx": page.get("panPx"),
                "transition": {"type": "smooth", "durationMs": 350},
                "lines": [{"speaker": "", "text": "", "camera": {"motion": "hold"}}],
                "texts": page_texts, "textTiming": "unknown",
            })
        if seen_texts != set(texts_by_id):
            raise BuildError(f"not all original texts are placed: {segment_id}")
        image_rel = f"{segment_id}/comic.svg"
        mirror[image_rel] = assembler.bytes()
        narration = segment["audio"]["narration"]["asset"]
        narration_bytes = reader.read(narration)
        mirror[narration] = narration_bytes
        music = segment["original"]["music"]["asset"]
        mirror[music] = reader.read(music)
        narration_start = number(segment["audio"]["narration"].get("startSec"), "narration start")
        if narration_start < 0 or narration_start >= sum(panel["duration"] for panel in panels):
            raise BuildError(f"narration start outside segment: {segment_id}")
        if segment["original"]["music"].get("loop") is not True:
            raise BuildError(f"original looping-music contract missing: {segment_id}")
        pages.append({
            "id": segment_id, "title": segment_id, "kind": "cf6-comic",
            "image": f"assets/book-comic/cf6/{image_rel}",
            "audio": {
                "narration": f"assets/book-comic/cf6/{narration}",
                "narrationStartSec": narration_start,
                "music": f"assets/book-comic/cf6/{music}", "musicVolume": 0.35,
                "musicLoop": True,
                "musicLoopPolicy": "continuous owned loop; original polling gap is not emulated",
                "synchronization": "original-frame-clock-with-narration-start-offset",
                "textTiming": "unknown", "originalMix": "unknown",
            },
            "timeline": {
                "fps": segment["original"]["fps"], "stripFrames": segment["original"]["stripFrames"],
                "advanceFrames": segment["original"]["advance"]["stripFrames"],
                "durationSec": round(sum(panel["duration"] for panel in panels), 4),
            },
            "panels": panels, "continueLabel": "继续",
        })
    end_records = [item for item in index.get("performances", []) if item.get("id") == "cf6-end"]
    if len(end_records) != 1:
        raise BuildError("cf6-end index entry missing")
    end = end_records[0]
    end_texts = json.loads(reader.read("cf6-end/texts.json").decode("utf-8"))
    if len(end_texts) != 19:
        raise BuildError("cf6-end must retain all 19 original texts")
    mirror["cf6-end/credits.svg"] = credits_svg(end_texts)
    end_music = f"music/{end.get('music')}.mp3"
    mirror[end_music] = reader.read(end_music)
    credit_texts = [{"charId": record["charId"], "text": record["ffdecFormatted"][record["ffdecFormatted"].rfind("]") + 1:].strip()} for record in end_texts]
    pages.append({
        "id": "cf6-end", "title": "cf6-end", "kind": "cf6-credits", "manual": True,
        "image": "assets/book-comic/cf6/cf6-end/credits.svg",
        "audio": {
            "narration": None, "music": f"assets/book-comic/cf6/{end_music}", "musicVolume": 0.35,
            "musicLoop": True,
            "synchronization": "manual-credits-no-original-duration", "textTiming": "unknown", "originalMix": "unknown",
        },
        "timeline": {"durationSec": None, "originalDuration": "unknown", "spriteFrames": end["spriteFrameCount"]},
        "panels": [{
            "id": "credits", "label": "credits", "rect": [0, 0, 1, 1], "duration": 0,
            "lines": [{"speaker": "", "text": "", "camera": {"motion": "hold"}}],
            "texts": credit_texts, "textTiming": "unknown",
        }],
        "continueLabel": "继续",
    })
    script_paths = [
        TOOLS / "cf6swf.py", TOOLS / "index_cf6_story.py", TOOLS / "extract_assets.py",
        TOOLS / "build_comic_story_fragment.py", Path(__file__).resolve(),
    ]
    binding = {
        "fragment": {"path": rel_path(FRAGMENT), "sha256": sha(FRAGMENT.read_bytes())},
        "index": {"path": rel_path(INDEX), "sha256": sha(INDEX.read_bytes())},
        "assetManifest": {"path": rel_path(ASSET_MANIFEST), "sha256": sha(ASSET_MANIFEST.read_bytes())},
        "originalSwfSha256": fragment["source"]["sha256"],
        "scripts": [{"path": rel_path(path), "sha256": sha(path.read_bytes())} for path in script_paths],
        "assets": [{"path": path, "sha256": digest} for path, digest in sorted(reader.used.items())],
    }
    binding_id = sha(json.dumps(binding, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))
    content = {
        "schema": "cf6-book-comic-web-content.v1", "sourceBindingSha256": binding_id,
        "vehicleAdaptation": "s4 precedes A07; only actual A07 vehicle-tail completion reaches s5 before A08; story routing grants no vehicle completion",
        "pages": pages,
    }
    manifest = {
        "schema": "cf6-book-comic-runtime-manifest.v1", "sourceBindingSha256": binding_id,
        "sourceBinding": binding,
        "files": [{"path": path, "sha256": sha(data), "bytes": len(data)} for path, data in sorted(mirror.items())],
        "fileCount": len(mirror), "totalBytes": sum(len(data) for data in mirror.values()),
    }
    outputs = {
        CONTENT_JSON: json_bytes(content),
        CONTENT_JS: b"window.BOOK_COMIC_CF6_CONTENT = " + json_bytes(content) + b";\n",
    }
    for relative, data in mirror.items():
        outputs[contained(MIRROR, relative)] = data
    outputs[MIRROR / "manifest.json"] = json_bytes(manifest)
    audit = {
        "schema": "cf6-book-comic-integrity-audit.v1", "sourceBindingSha256": binding_id,
        "runtimePayload": manifest["files"], "fileCount": manifest["fileCount"], "totalBytes": manifest["totalBytes"],
        "maxFileBytes": max(len(data) for data in mirror.values()),
        "byteExactCopies": [{"source": path, "mirror": path, "sha256": sha(data)} for path, data in sorted(mirror.items()) if path.endswith(".mp3")],
        "generatedOutputs": [{"path": rel_path(path), "sha256": sha(data), "bytes": len(data)} for path, data in sorted(outputs.items(), key=lambda item: rel_path(item[0]))],
        "audioPolicy": "MP3 bytes copied unchanged; no audio transcoding or audible validation",
    }
    outputs[MIRROR / "integrity-audit.json"] = json_bytes(audit)
    return outputs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        outputs = build()
        mismatches = []
        for path, data in outputs.items():
            if not path.is_file() or path.read_bytes() != data:
                mismatches.append(rel_path(path))
        if args.check:
            actual = {path for path in MIRROR.rglob("*") if path.is_file()} if MIRROR.exists() else set()
            expected = {path for path in outputs if MIRROR.resolve() in path.parents}
            for path in sorted(actual - expected):
                mismatches.append("unexpected:" + rel_path(path))
            if mismatches:
                print("CF6 web content check failed:\n" + "\n".join(mismatches), file=sys.stderr)
                return 1
            print(f"CF6 web content check OK: {len(outputs)} outputs, {len(SEGMENT_IDS)} comics + credits")
            return 0
        written = []
        for path, data in outputs.items():
            path = path.resolve()
            if path != MIRROR.resolve() and MIRROR.resolve() not in path.parents and path not in (CONTENT_JS.resolve(), CONTENT_JSON.resolve()):
                raise BuildError(f"write target outside authorized outputs: {path}")
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.is_file() or path.read_bytes() != data:
                path.write_bytes(data)
                written.append(rel_path(path))
        print(f"CF6 web content built: {len(outputs)} outputs; changed {len(written)}")
        return 0
    except (BuildError, KeyError, ValueError, ET.ParseError, json.JSONDecodeError) as error:
        print(f"CF6 web content build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
