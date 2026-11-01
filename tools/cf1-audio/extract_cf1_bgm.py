# -*- coding: utf-8 -*-
"""Extract the four native BGM streams from the bundled CF1 SWF.

The original Flash 5 SWF stores background music as SoundStreamBlock tags inside
the music sprites. No FFDec/JRE is required: this walks the SWF tag stream and
concatenates each sprite's blocks into a standalone MP3 under
tools/cf1-audio/original. The runtime copies in sounds/cf1 are normalized to
44.1 kHz so the native decoder can play them.

Usage:
    python tools/cf1-audio/extract_cf1_bgm.py
    python tools/cf1-audio/extract_cf1_bgm.py --check
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "flashswf" / "originals" / "crazy-flasher-1.swf"
# Original extraction is kept outside sounds/ because the playable copies in
# sounds/cf1 are normalized to 44.1 kHz for the native audio decoder.
OUTPUT_DIR = ROOT / "tools" / "cf1-audio" / "original"
MANIFEST = OUTPUT_DIR / "manifest.json"


def read_swf(path: Path) -> bytes:
    data = path.read_bytes()
    signature = data[:3]
    if signature == b"CWS":
        return data[:8] + zlib.decompress(data[8:])
    if signature == b"ZWS":
        raise ValueError("LZMA-compressed SWF is not supported")
    if signature != b"FWS":
        raise ValueError("not a SWF file: " + str(path))
    return data


def mp3_stats(data: bytes) -> dict:
    bitrates = {
        1: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
        2: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    }
    sample_rates = {3: [44100, 48000, 32000], 2: [22050, 24000, 16000], 0: [11025, 12000, 8000]}
    offset = 0
    frames = 0
    duration_ms = 0.0
    sample_rate = None
    bitrate = None
    layer = None
    while offset + 4 <= len(data):
        if data[offset] != 0xFF or (data[offset + 1] & 0xE0) != 0xE0:
            offset += 1
            continue
        b1 = data[offset + 1]
        version = (b1 >> 3) & 3
        layer = (b1 >> 1) & 3
        if version == 1 or layer == 0:
            offset += 1
            continue
        b2 = data[offset + 2]
        rate_index = (b2 >> 4) & 15
        sample_index = (b2 >> 2) & 3
        if rate_index in (0, 15) or sample_index == 3:
            offset += 1
            continue
        table = bitrates[1] if version == 3 else bitrates[2]
        if rate_index >= len(table):
            offset += 1
            continue
        bitrate = table[rate_index]
        sample_rate = sample_rates.get(version, sample_rates[3])[sample_index]
        if layer == 3:
            frame_len = int(12 * bitrate * 1000 / sample_rate + (b2 & 2) / 2) * 4
        else:
            frame_len = int(144 * bitrate * 1000 / sample_rate) + ((b2 & 2) >> 1)
        if frame_len <= 4 or offset + frame_len > len(data):
            break
        frames += 1
        samples_per_frame = 1152 if layer == 1 else 576
        duration_ms += samples_per_frame * 1000.0 / sample_rate
        offset += frame_len
    return {
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "mp3Frames": frames,
        "durationSeconds": round(duration_ms / 1000.0, 3),
        "sampleRate": sample_rate,
        "bitrateKbps": bitrate,
    }


def parse_streams(raw: bytes) -> dict:
    pos = 8
    nbits = raw[pos] >> 3
    pos += (5 + 4 * nbits + 7) // 8 + 4
    streams: dict[str, dict] = {}

    def walk(start: int, end: int, sprite: str | None = None) -> None:
        p = start
        head = None
        blocks: list[bytes] = []
        while p + 2 <= end:
            header = raw[p] | (raw[p + 1] << 8)
            p += 2
            code = header >> 6
            length = header & 0x3F
            if length == 0x3F:
                length = struct.unpack_from("<I", raw, p)[0]
                p += 4
            body = p
            p += length
            if code == 0:
                break
            if code == 18:
                stream_flags = raw[body + 1]
                head = {
                    "soundFormat": (stream_flags >> 4) & 0x0F,
                    "soundRate": (stream_flags >> 2) & 0x03,
                    "soundSize": (stream_flags >> 1) & 0x01,
                    "soundType": stream_flags & 0x01,
                    "sampleCount": struct.unpack_from("<H", raw, body + 2)[0],
                }
                blocks = []
            elif code == 19:
                blocks.append(raw[body:body + length])
            elif code == 39:
                child_id = struct.unpack_from("<H", raw, body)[0]
                walk(body + 4, body + length, "sprite" + str(child_id))
        if head is not None and blocks and sprite is not None:
            data = b"".join(blocks)
            for i in range(min(len(data) - 1, 32)):
                if data[i] == 0xFF and (data[i + 1] & 0xE0) == 0xE0:
                    if i:
                        data = data[i:]
                    break
            streams[sprite] = {"head": head, "data": data}

    walk(pos, len(raw))
    return streams


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify outputs are current")
    args = parser.parse_args()
    if not SOURCE.is_file():
        print("missing " + str(SOURCE), file=sys.stderr)
        return 1
    raw = read_swf(SOURCE)
    streams = parse_streams(raw)
    ordered = sorted(streams.items(), key=lambda item: int(item[0][6:]))
    if not ordered:
        print("no SoundStreamBlock streams found", file=sys.stderr)
        return 1

    source_sha = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    tracks = []
    outputs: list[tuple[Path, bytes]] = []
    for index, (sprite, stream) in enumerate(ordered, 1):
        title = "CF1-BGM-" + str(index)
        filename = "cf1-bgm-" + str(index) + ".mp3"
        stats = mp3_stats(stream["data"])
        tracks.append({
            "title": title,
            "file": filename,
            "sourceSprite": sprite,
            "sourceSoundFormat": stream["head"]["soundFormat"],
            **stats,
        })
        outputs.append((OUTPUT_DIR / filename, stream["data"]))
    manifest = {
        "schema": "cf1-bgm-extraction.v1",
        "source": "flashswf/originals/crazy-flasher-1.swf",
        "sourceSha256": source_sha,
        "tracks": tracks,
    }
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    outputs.append((MANIFEST, manifest_bytes))

    stale = []
    for path, content in outputs:
        if args.check:
            if not path.is_file() or path.read_bytes() != content:
                stale.append(path)
        else:
            path.write_bytes(content)
    if stale:
        for path in stale:
            print("stale: " + str(path.relative_to(ROOT)), file=sys.stderr)
        return 1
    print("CF1 BGM: %d tracks%s" % (
        len(tracks), " verified" if args.check else " extracted"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
