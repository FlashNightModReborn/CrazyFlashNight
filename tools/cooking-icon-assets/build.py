#!/usr/bin/env python3
"""Deterministic XFL asset builder, SWF verifier, and WebP icon baker
for CrazyFlashNight's 62 cooking ingredients & dishes icons.

Usage:
    python -B -X utf8 tools/cooking-icon-assets/build.py --build-xfl
    python -B -X utf8 tools/cooking-icon-assets/build.py --bake-web
    python -B -X utf8 tools/cooking-icon-assets/build.py --check
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TOOL_DIR = Path(__file__).resolve().parent
MANIFEST_PATH = TOOL_DIR / "manifest.json"
FRAMES_DIR = TOOL_DIR / "frames"

FOOD_XML_PATH = ROOT / "data" / "items" / "消耗品_药剂_食品.xml"
POTION_AUDIT_PATH = ROOT / "tools" / "cf7-balance-tool" / "records" / "potion-balance-audit.xml"
WEB_ICONS_DIR = ROOT / "launcher" / "web" / "icons"
WEB_MANIFEST_PATH = WEB_ICONS_DIR / "manifest.json"


def _load_module(name: str, path: Path):
    parent = str(path.parent)
    if parent not in sys.path:
        sys.path.insert(0, parent)
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load module: {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def load_manifest() -> dict[str, Any]:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def encode_cs6_dat(rgba_image: Image.Image) -> bytes:
    """Encode a 128x128 RGBA image into Adobe Flash CS6 03/05 premultiplied ARGB .dat."""
    im = rgba_image.convert("RGBA")
    w, h = im.size
    if (w, h) != (128, 128):
        raise ValueError(f"Expected 128x128 image, got {w}x{h}")
    stride = w * 4
    header = (
        b"\x03\x05"
        + struct.pack("<3H4I", stride, w, h, 0, w * 20, 0, h * 20)
        + b"\x01\x01"
    )
    raw_bytes = im.tobytes()
    argb = bytearray(len(raw_bytes))
    for i in range(0, len(raw_bytes), 4):
        r, g, b, a = raw_bytes[i : i + 4]
        if a == 0:
            argb[i : i + 4] = b"\x00\x00\x00\x00"
        elif a == 255:
            argb[i] = 255
            argb[i + 1] = r
            argb[i + 2] = g
            argb[i + 3] = b
        else:
            rp = (r * a + 127) // 255
            gp = (g * a + 127) // 255
            bp = (b * a + 127) // 255
            argb[i] = a
            argb[i + 1] = min(a, rp)
            argb[i + 2] = min(a, gp)
            argb[i + 3] = min(a, bp)
    packed = zlib.compress(bytes(argb), 9)
    chunks = [packed[i : i + 2048] for i in range(0, len(packed), 2048)]
    return header + b"".join(struct.pack("<H", len(c)) + c for c in chunks) + b"\x00\x00"


def update_food_xml_and_audit(manifest: dict[str, Any], write: bool) -> dict[str, int]:
    """Update <icon> and <sourceDigest> for the 4 appliance dishes in XML and audit ledger."""
    rebind_items = [it for it in manifest["items"] if it.get("rebind_xml_icon")]
    target_names = {it["name"]: it["icon_key"] for it in rebind_items}

    food_raw = FOOD_XML_PATH.read_text(encoding="utf-8")
    new_digests: dict[str, str] = {}

    def replace_item(match: re.Match[str]) -> str:
        block = match.group(0)
        nm_m = re.search(r"<name>([\s\S]*?)</name>", block)
        if not nm_m:
            return block
        name = nm_m.group(1).strip()
        if name not in target_names:
            return block
        new_icon = target_names[name]
        updated = re.sub(
            r"(<icon>)[\s\S]*?(</icon>)",
            lambda m: f"{m.group(1)}{new_icon}{m.group(2)}",
            block,
            count=1,
        )
        clean = re.sub(r"\r?\n[ \t]*<balance>[\s\S]*?</balance>", "", updated)
        digest = "sha256:" + hashlib.sha256(clean.replace("\r\n", "\n").strip().encode("utf-8")).hexdigest()
        new_digests[name] = digest
        updated = re.sub(
            r"(<sourceDigest>)[\s\S]*?(</sourceDigest>)",
            lambda m: f"{m.group(1)}{digest}{m.group(2)}",
            updated,
            count=1,
        )
        return updated

    food_next = re.sub(r"^[ \t]*<item(?:\s[^>]*)?>[\s\S]*?^[ \t]*</item>", replace_item, food_raw, flags=re.M)
    if set(new_digests.keys()) != set(target_names.keys()):
        missing = sorted(set(target_names.keys()) - set(new_digests.keys()))
        raise RuntimeError(f"Missing items in {FOOD_XML_PATH}: {missing}")

    audit_raw = POTION_AUDIT_PATH.read_text(encoding="utf-8")
    audit_seen: set[str] = set()

    def replace_record(match: re.Match[str]) -> str:
        rec = match.group(0)
        nm_m = re.search(r"<itemName>([\s\S]*?)</itemName>", rec)
        if not nm_m:
            return rec
        name = nm_m.group(1).strip()
        if name not in new_digests:
            return rec
        audit_seen.add(name)
        return re.sub(
            r"(<sourceDigest>)[\s\S]*?(</sourceDigest>)",
            lambda m: f"{m.group(1)}{new_digests[name]}{m.group(2)}",
            rec,
            count=1,
        )

    audit_next = re.sub(r"^[ \t]*<record>[\s\S]*?^[ \t]*</record>", replace_record, audit_raw, flags=re.M)
    if audit_seen != set(new_digests.keys()):
        missing = sorted(set(new_digests.keys()) - audit_seen)
        raise RuntimeError(f"Missing audit records in {POTION_AUDIT_PATH}: {missing}")

    drifts = 0
    for path, before, after in (
        (FOOD_XML_PATH, food_raw, food_next),
        (POTION_AUDIT_PATH, audit_raw, audit_next),
    ):
        if before != after:
            drifts += 1
            if write:
                path.write_bytes(after.encode("utf-8"))
    return {"xml_drifts": drifts}


def build_wrapper_xml(row: dict[str, Any]) -> bytes:
    """Build deterministic 4-layer 2-frame icon wrapper XML."""
    sym_name = row["symbol_name"]
    leaf_name = row["linkage"]
    item_id = row["wrapper_item_id"]
    bmp_name = row["bitmap_lib_name"]
    text = (
        f'<DOMSymbolItem xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        f'xmlns="http://ns.adobe.com/xfl/2008/" name="{sym_name}" itemID="{item_id}" '
        f'linkageExportForAS="true" linkageIdentifier="{leaf_name}" '
        f'lastModified="1795539600" lastUniqueIdentifier="4">\n'
        f'  <timeline>\n'
        f'    <DOMTimeline name="{leaf_name}" currentFrame="0">\n'
        f'      <layers>\n'
        f'        <DOMLayer name="图层_3" color="#FF800A">\n'
        f'          <frames>\n'
        f'            <DOMFrame index="0" keyMode="9728">\n'
        f'              <Actionscript>\n'
        f'                <script><![CDATA[stop();]]></script>\n'
        f'              </Actionscript>\n'
        f'              <elements/>\n'
        f'            </DOMFrame>\n'
        f'          </frames>\n'
        f'        </DOMLayer>\n'
        f'        <DOMLayer name="Layer_1" color="#05F390">\n'
        f'          <frames>\n'
        f'            <DOMFrame index="0" keyMode="9728">\n'
        f'              <elements>\n'
        f'                <DOMSymbolInstance libraryItemName="无AS链接/材料红框" symbolType="graphic" loop="loop">\n'
        f'                  <transformationPoint>\n'
        f'                    <Point/>\n'
        f'                  </transformationPoint>\n'
        f'                </DOMSymbolInstance>\n'
        f'              </elements>\n'
        f'            </DOMFrame>\n'
        f'          </frames>\n'
        f'        </DOMLayer>\n'
        f'        <DOMLayer name="Layer_2" color="#BCAAE0" current="true" isSelected="true">\n'
        f'          <frames>\n'
        f'            <DOMFrame index="0" keyMode="9728">\n'
        f'              <elements>\n'
        f'                <DOMBitmapInstance libraryItemName="{bmp_name}">\n'
        f'                  <matrix>\n'
        f'                    <Matrix a="0.1953125" d="0.1953125" tx="-12.5" ty="-12.5"/>\n'
        f'                  </matrix>\n'
        f'                  <transformationPoint>\n'
        f'                    <Point x="64" y="64"/>\n'
        f'                  </transformationPoint>\n'
        f'                </DOMBitmapInstance>\n'
        f'              </elements>\n'
        f'            </DOMFrame>\n'
        f'            <DOMFrame index="1" keyMode="9728">\n'
        f'              <elements>\n'
        f'                <DOMBitmapInstance libraryItemName="{bmp_name}">\n'
        f'                  <matrix>\n'
        f'                    <Matrix a="0.1953125" d="0.1953125" tx="-12.5" ty="-12.5"/>\n'
        f'                  </matrix>\n'
        f'                  <transformationPoint>\n'
        f'                    <Point x="64" y="64"/>\n'
        f'                  </transformationPoint>\n'
        f'                </DOMBitmapInstance>\n'
        f'              </elements>\n'
        f'            </DOMFrame>\n'
        f'          </frames>\n'
        f'        </DOMLayer>\n'
        f'        <DOMLayer name="Layer_3" color="#63D255">\n'
        f'          <frames>\n'
        f'            <DOMFrame index="0" keyMode="9728">\n'
        f'              <elements>\n'
        f'                <DOMSymbolInstance libraryItemName="无AS链接/材料黑底" symbolType="graphic" loop="loop">\n'
        f'                  <transformationPoint>\n'
        f'                    <Point/>\n'
        f'                  </transformationPoint>\n'
        f'                </DOMSymbolInstance>\n'
        f'              </elements>\n'
        f'            </DOMFrame>\n'
        f'          </frames>\n'
        f'        </DOMLayer>\n'
        f'      </layers>\n'
        f'    </DOMTimeline>\n'
        f'  </timeline>\n'
        f'</DOMSymbolItem>'
    )
    return text.encode("utf-8")


def update_dom_document(manifest: dict[str, Any], dom_text: str) -> str:
    """Idempotently add folder, 62 DOMBitmapItem media entries, and 4 new symbol Includes."""
    folder_name = manifest["folder_name"]
    folder_id = manifest["folder_item_id"]
    ts = manifest["source_last_imported"]

    # 1. Folder
    folder_tag = f'          <DOMFolderItem name="{folder_name}" itemID="{folder_id}"/>'
    if f'name="{folder_name}"' not in dom_text:
        assert dom_text.count("</folders>") == 1
        dom_text = re.sub(
            r"^[ \t]*</folders>",
            lambda m: f"{folder_tag}\n{m.group(0)}",
            dom_text,
            count=1,
            flags=re.M,
        )

    # 2. Media entries
    media_lines = []
    for row in manifest["items"]:
        bname = row["bitmap_lib_name"]
        bid = row["bitmap_item_id"]
        crc = row["png_crc32"]
        sz = row["png_bytes"]
        dat = row["dat_name"]
        attrs = (
            f'<DOMBitmapItem name="{bname}" itemID="{bid}" '
            f'sourceExternalFilepath="../素材库-物品技能图标/LIBRARY/{bname}" '
            f'sourceLastImported="{ts}" externalFileCRC32="{crc}" externalFileSize="{sz}" '
            f'allowSmoothing="true" useImportedJPEGData="false" compressionType="lossless" '
            f'originalCompressionType="lossless" quality="50" href="{bname}" '
            f'bitmapDataHRef="{dat}" frameRight="2560" frameBottom="2560"/>'
        )
        pattern = re.compile(rf'^([ \t]*)<DOMBitmapItem\b[^>]*name="{re.escape(bname)}"[^>]*/>\r?\n?', re.M)
        m = pattern.search(dom_text)
        if m:
            dom_text = dom_text[: m.start()] + f"{m.group(1)}{attrs}\n" + dom_text[m.end() :]
        else:
            media_lines.append(f"          {attrs}")

    if media_lines:
        assert dom_text.count("</media>") == 1
        block = "\n".join(media_lines)
        dom_text = re.sub(
            r"^[ \t]*</media>",
            lambda m: f"{block}\n{m.group(0)}",
            dom_text,
            count=1,
            flags=re.M,
        )

    # 3. Symbols Include for new dishes
    inc_lines = []
    for row in manifest["items"]:
        href = f"{row['symbol_name']}.xml"
        if f'href="{href}"' not in dom_text:
            inc_lines.append(
                f'          <Include href="{href}" loadImmediate="false" itemID="{row["wrapper_item_id"]}" lastModified="{ts}"/>'
            )
    if inc_lines:
        assert dom_text.count("</symbols>") == 1
        block = "\n".join(inc_lines)
        dom_text = re.sub(
            r"^[ \t]*</symbols>",
            lambda m: f"{block}\n{m.group(0)}",
            dom_text,
            count=1,
            flags=re.M,
        )

    return dom_text


def build_or_check_xfl(manifest: dict[str, Any], write: bool) -> dict[str, Any]:
    bitmap_mod = _load_module("cf2_bitmap", ROOT / "tools" / "cf2-boss-assets" / "bitmap.py")
    xfl_dir = ROOT / manifest["xfl_dir"]
    drifts: list[str] = []

    for row in manifest["items"]:
        png_path = xfl_dir / "LIBRARY" / row["bitmap_lib_name"]
        if not png_path.exists():
            raise FileNotFoundError(f"Missing PNG: {png_path}")
        png_bytes = png_path.read_bytes()
        if sha256_bytes(png_bytes) != row["png_sha256"]:
            raise RuntimeError(f"PNG sha256 mismatch for {png_path}")

        im = Image.open(png_path).convert("RGBA")
        dat_bytes = encode_cs6_dat(im)
        # Verify roundtrip decode with cf2-boss-assets/bitmap.py
        decoded = bitmap_mod.decode(dat_bytes, 128, 128)
        if decoded.size != (128, 128):
            raise RuntimeError(f"Decoded size mismatch for {row['dat_name']}")

        dat_path = xfl_dir / "bin" / row["dat_name"]
        if not dat_path.exists() or dat_path.read_bytes() != dat_bytes:
            drifts.append(str(dat_path.relative_to(ROOT)))
            if write:
                dat_path.parent.mkdir(parents=True, exist_ok=True)
                dat_path.write_bytes(dat_bytes)

        sym_path = xfl_dir / "LIBRARY" / f"{row['symbol_name']}.xml"
        sym_bytes = build_wrapper_xml(row)
        if not sym_path.exists() or sym_path.read_bytes() != sym_bytes:
            drifts.append(str(sym_path.relative_to(ROOT)))
            if write:
                sym_path.parent.mkdir(parents=True, exist_ok=True)
                sym_path.write_bytes(sym_bytes)

    dom_path = xfl_dir / "DOMDocument.xml"
    dom_before = dom_path.read_text(encoding="utf-8")
    dom_after = update_dom_document(manifest, dom_before)
    if dom_before != dom_after:
        drifts.append(str(dom_path.relative_to(ROOT)))
        if write:
            dom_path.write_bytes(dom_after.encode("utf-8"))

    xml_res = update_food_xml_and_audit(manifest, write=write)
    return {"xfl_drifts": drifts, **xml_res}


# ---- SWF Binary Reader (Tag 56 ExportAssets + Tag 39 DefineSprite + Tag 2/22/32/83 DefineShape + Tag 36 DefineBitsLossless2) ----

def _parse_swf_tags(raw: bytes) -> list[tuple[int, bytes]]:
    sig = raw[:3].decode("ascii")
    if sig not in ("FWS", "CWS"):
        raise ValueError(f"Unsupported SWF signature: {sig}")
    body = zlib.decompress(raw[8:]) if sig == "CWS" else raw[8:]
    nbits = body[0] >> 3
    rect_bytes = (5 + 4 * nbits + 7) // 8
    pos = rect_bytes + 4
    tags: list[tuple[int, bytes]] = []
    while pos + 2 <= len(body):
        cl = struct.unpack_from("<H", body, pos)[0]
        pos += 2
        code = cl >> 6
        length = cl & 0x3F
        if length == 0x3F:
            length = struct.unpack_from("<I", body, pos)[0]
            pos += 4
        tags.append((code, body[pos : pos + length]))
        pos += length
        if code == 0:
            break
    return tags


def _read_rect_bytes(data: bytes, pos: int) -> int:
    nbits = data[pos] >> 3
    return (5 + 4 * nbits + 7) // 8


def _read_matrix_bytes(data: bytes, pos: int) -> int:
    bit_pos = 0

    def read_bits(n: int) -> int:
        nonlocal bit_pos
        val = 0
        for _ in range(n):
            b = data[pos + (bit_pos >> 3)]
            bit = (b >> (7 - (bit_pos & 7))) & 1
            val = (val << 1) | bit
            bit_pos += 1
        return val

    if read_bits(1):
        nb = read_bits(5)
        read_bits(2 * nb)
    if read_bits(1):
        nb = read_bits(5)
        read_bits(2 * nb)
    nb_t = read_bits(5)
    read_bits(2 * nb_t)
    return (bit_pos + 7) // 8


def _shape_bitmap_ids(code: int, payload: bytes) -> list[int]:
    p = 2 + _read_rect_bytes(payload, 2)
    if code == 83:
        p += _read_rect_bytes(payload, p) + 1
    cnt = payload[p]
    p += 1
    if cnt == 0xFF and code in (22, 32, 83):
        cnt = struct.unpack_from("<H", payload, p)[0]
        p += 2
    bmps: list[int] = []
    for _ in range(cnt):
        ftype = payload[p]
        p += 1
        if ftype == 0x00:
            p += 4 if code in (32, 83) else 3
        elif ftype in (0x10, 0x12, 0x13):
            p += _read_matrix_bytes(payload, p)
            n_recs = payload[p] & 0x0F
            p += 1 + n_recs * (5 if code in (32, 83) else 4)
            if ftype == 0x13:
                p += 2
        elif ftype in (0x40, 0x41, 0x42, 0x43):
            bid = struct.unpack_from("<H", payload, p)[0]
            p += 2
            p += _read_matrix_bytes(payload, p)
            if bid != 0xFFFF:
                bmps.append(bid)
        else:
            break
    return bmps


def _sprite_children_by_frame(payload: bytes) -> list[list[int]]:
    """Return active display-list characterIds on each ShowFrame (0-indexed)."""
    pos = 4
    display: dict[int, int] = {}
    frames: list[list[int]] = []
    while pos + 2 <= len(payload):
        cl = struct.unpack_from("<H", payload, pos)[0]
        pos += 2
        code = cl >> 6
        length = cl & 0x3F
        if length == 0x3F:
            length = struct.unpack_from("<I", payload, pos)[0]
            pos += 4
        sub = payload[pos : pos + length]
        pos += length
        if code == 1:  # ShowFrame
            frames.append([display[d] for d in sorted(display)])
        elif code == 26:  # PlaceObject2
            flags = sub[0]
            depth = struct.unpack_from("<H", sub, 1)[0]
            if flags & 0x02:
                display[depth] = struct.unpack_from("<H", sub, 3)[0]
        elif code == 70:  # PlaceObject3
            flags1, flags2 = sub[0], sub[1]
            depth = struct.unpack_from("<H", sub, 2)[0]
            if flags1 & 0x02:
                sp = 4
                if flags2 & 0x08:
                    sp = sub.index(0, sp) + 1
                display[depth] = struct.unpack_from("<H", sub, sp)[0]
        elif code == 28:  # RemoveObject2
            depth = struct.unpack_from("<H", sub, 0)[0]
            display.pop(depth, None)
        elif code == 5:  # RemoveObject
            depth = struct.unpack_from("<H", sub, 2)[0]
            display.pop(depth, None)
        elif code == 0:
            break
    return frames


def _decode_lossless2(payload: bytes) -> Image.Image:
    cid, fmt, w, h = struct.unpack_from("<HBHH", payload, 0)
    if fmt != 5:
        raise ValueError(f"Expected 32-bit ARGB DefineBitsLossless2 (fmt=5) for cid={cid}, got fmt={fmt}")
    raw = zlib.decompress(payload[7:])
    if len(raw) != w * h * 4:
        raise ValueError(f"Pixel length mismatch for cid={cid}: {len(raw)} vs {w*h*4}")
    rgba = bytearray(len(raw))
    for i in range(0, len(raw), 4):
        a, r, g, b = raw[i : i + 4]
        if a == 0:
            rgba[i : i + 4] = b"\x00\x00\x00\x00"
        elif a == 255:
            rgba[i] = r
            rgba[i + 1] = g
            rgba[i + 2] = b
            rgba[i + 3] = 255
        else:
            rgba[i] = min(255, (r * 255 + a // 2) // a)
            rgba[i + 1] = min(255, (g * 255 + a // 2) // a)
            rgba[i + 2] = min(255, (b * 255 + a // 2) // a)
            rgba[i + 3] = a
    return Image.frombytes("RGBA", (w, h), bytes(rgba))


def verify_swf_and_extract_bitmaps(manifest: dict[str, Any]) -> dict[str, Image.Image]:
    """Verify all 62 linkage exports and 128x128 DefineBitsLossless2 bitmaps inside SWF."""
    bitmap_mod = _load_module("cf2_bitmap", ROOT / "tools" / "cf2-boss-assets" / "bitmap.py")
    swf_path = ROOT / manifest["swf_path"]
    xfl_dir = ROOT / manifest["xfl_dir"]
    tags = _parse_swf_tags(swf_path.read_bytes())

    exports: dict[str, int] = {}
    sprites: dict[int, list[list[int]]] = {}
    shapes: dict[int, list[int]] = {}
    lossless2: dict[int, bytes] = {}

    for code, pl in tags:
        if code == 56:
            cnt = struct.unpack_from("<H", pl, 0)[0]
            p = 2
            for _ in range(cnt):
                cid = struct.unpack_from("<H", pl, p)[0]
                p += 2
                end = pl.index(0, p)
                nm = pl[p:end].decode("utf-8")
                p = end + 1
                exports[nm] = cid
        elif code == 39:
            sid = struct.unpack_from("<H", pl, 0)[0]
            sprites[sid] = _sprite_children_by_frame(pl)
        elif code in (2, 22, 32, 83):
            shid = struct.unpack_from("<H", pl, 0)[0]
            shapes[shid] = _shape_bitmap_ids(code, pl)
        elif code == 36:
            cid = struct.unpack_from("<H", pl, 0)[0]
            lossless2[cid] = pl

    extracted: dict[str, Image.Image] = {}
    for row in manifest["items"]:
        lid = row["linkage"]
        if lid not in exports:
            raise RuntimeError(f"SWF missing ExportAssets symbol: {lid}")
        sid = exports[lid]
        frames = sprites.get(sid)
        if not frames or len(frames) != 2 or len(frames[0]) != 3 or len(frames[1]) != 1:
            raise RuntimeError(f"SWF sprite {lid} (sid={sid}) unexpected frame structure: {frames}")

        # Find bitmap IDs in frame 1 and frame 2
        def frame_bitmaps(cids: list[int]) -> list[int]:
            out: list[int] = []
            for c in cids:
                out.extend(shapes.get(c, []))
                if c in lossless2:
                    out.append(c)
            return [b for b in out if b in lossless2]

        b_f1 = frame_bitmaps(frames[0])
        b_f2 = frame_bitmaps(frames[1])
        if len(b_f1) != 1 or b_f1 != b_f2:
            raise RuntimeError(f"SWF sprite {lid} bitmap ref mismatch f1={b_f1}, f2={b_f2}")

        swf_im = _decode_lossless2(lossless2[b_f1[0]])
        if swf_im.size != (128, 128):
            raise RuntimeError(f"SWF bitmap {lid} expected 128x128, got {swf_im.size}")

        # Verify pixel identity against the XFL .dat decoded RGBA
        dat_bytes = (xfl_dir / "bin" / row["dat_name"]).read_bytes()
        dat_im = bitmap_mod.decode(dat_bytes, 128, 128)
        if swf_im.tobytes() != dat_im.tobytes():
            raise RuntimeError(f"SWF bitmap pixels differ from XFL .dat for {lid}")

        extracted[row["icon_key"]] = swf_im
    return extracted


def bake_or_check_web(manifest: dict[str, Any], swf_bitmaps: dict[str, Image.Image], write: bool) -> dict[str, Any]:
    bake_mod = _load_module("bake_icons_offline", ROOT / "tools" / "bake-icons-offline.py")
    bake_mod.ICON_SIZE = 128

    bg_path = FRAMES_DIR / "food_bg.png"
    bd_path = FRAMES_DIR / "food_border.png"
    if sha256_bytes(bg_path.read_bytes()) != manifest["food_bg_sha256"]:
        raise RuntimeError("food_bg.png sha256 mismatch")
    if sha256_bytes(bd_path.read_bytes()) != manifest["food_border_sha256"]:
        raise RuntimeError("food_border.png sha256 mismatch")

    food_bg = Image.open(bg_path).convert("RGBA")
    food_border = Image.open(bd_path).convert("RGBA")

    import io
    web_manifest_before = WEB_MANIFEST_PATH.read_text(encoding="utf-8")
    web_manifest = json.loads(web_manifest_before)
    drifts: list[str] = []

    for row in manifest["items"]:
        key = row["icon_key"]
        crc = row["web_crc"]
        subj = swf_bitmaps[key]

        # Frame 1: food_bg + 128x128 subject + food_border
        f1_im = food_bg.copy()
        f1_im.alpha_composite(subj)
        f1_im.alpha_composite(food_border)

        # Frame 2: normalized via bake-icons-offline.normalize_icon_image
        f2_im = bake_mod.normalize_icon_image(subj, canvas_size=128)

        for suffix, im in ((f"{crc}_1.webp", f1_im), (f"{crc}_2.webp", f2_im)):
            buf = io.BytesIO()
            im.save(buf, format="WEBP", lossless=True, method=6)
            webp_bytes = buf.getvalue()
            out_p = WEB_ICONS_DIR / suffix
            if not out_p.exists() or out_p.read_bytes() != webp_bytes:
                drifts.append(str(out_p.relative_to(ROOT)))
                if write:
                    out_p.write_bytes(webp_bytes)

        web_manifest[key] = {"f1": f"{crc}_1.webp", "f2": f"{crc}_2.webp"}

    # Preserve CRLF if file originally used CRLF
    nl = "\r\n" if "\r\n" in web_manifest_before else "\n"
    serialized = json.dumps(web_manifest, ensure_ascii=False, indent=2) + "\n"
    if nl == "\r\n":
        serialized = serialized.replace("\n", "\r\n")
    if serialized != web_manifest_before:
        drifts.append(str(WEB_MANIFEST_PATH.relative_to(ROOT)))
        if write:
            WEB_MANIFEST_PATH.write_bytes(serialized.encode("utf-8"))

    return {"web_drifts": drifts}


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--build-xfl", action="store_true", help="Write XML, .dat caches, DOMDocument, and wrapper XMLs.")
    mode.add_argument("--bake-web", action="store_true", help="Verify compiled SWF and derive WebP icons + manifest.")
    mode.add_argument("--check", action="store_true", help="Read-only check across XFL, XML, compiled SWF, and Web icons.")
    args = parser.parse_args()

    manifest = load_manifest()
    if len(manifest["items"]) != 62:
        raise RuntimeError(f"Expected 62 items, got {len(manifest['items'])}")

    if args.build_xfl:
        res = build_or_check_xfl(manifest, write=True)
        print(json.dumps({"mode": "build-xfl", "count": 62, **res}, ensure_ascii=False))
        return 0

    if args.bake_web:
        swf_bitmaps = verify_swf_and_extract_bitmaps(manifest)
        res = bake_or_check_web(manifest, swf_bitmaps, write=True)
        print(json.dumps({"mode": "bake-web", "verified_swf_icons": len(swf_bitmaps), **res}, ensure_ascii=False))
        return 0

    if args.check:
        xfl_res = build_or_check_xfl(manifest, write=False)
        swf_bitmaps = verify_swf_and_extract_bitmaps(manifest)
        web_res = bake_or_check_web(manifest, swf_bitmaps, write=False)
        all_drifts = xfl_res["xfl_drifts"] + web_res["web_drifts"]
        if xfl_res["xml_drifts"] or all_drifts:
            print(json.dumps({"mode": "check", "status": "DRIFT", "xfl": xfl_res, "web": web_res}, ensure_ascii=False, indent=2))
            return 1
        print(json.dumps({"mode": "check", "status": "OK", "count": 62, "verified_swf_icons": len(swf_bitmaps)}, ensure_ascii=False))
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
