#!/usr/bin/env python3
"""Generate the fixed, synthetic Audio v2 qualification decoder corpus.

This maintainer-only helper is deliberately not executed by the qualification
runner.  It requires the exact PyAV 16.0.1 wheel (FFmpeg 8.0 libraries) and
emits only a deterministic 440 Hz mono signal, an intentional silent WAV, and
two deliberately damaged inputs.  The emitted JSON embeds every byte so H2
does not download, decode, or trust this generator at replay time.
"""

from __future__ import annotations

import argparse
import array
import base64
import hashlib
import json
import math
import struct
from fractions import Fraction
from pathlib import Path

import av


SAMPLE_RATE = 48_000
FRAME_COUNT = 24_000
AMPLITUDE = 0.25
PYAV_VERSION = "16.0.1"


def canonical(value):
    if isinstance(value, dict):
        return {key: canonical(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [canonical(item) for item in value]
    return value


def tone_s16() -> bytes:
    samples = array.array(
        "h",
        (
            round(32767 * AMPLITUDE * math.sin(2 * math.pi * 440 * index / SAMPLE_RATE))
            for index in range(FRAME_COUNT)
        ),
    )
    if struct.pack("=H", 1) != struct.pack("<H", 1):
        samples.byteswap()
    return samples.tobytes()


def wave_bytes(pcm: bytes) -> bytes:
    return b"".join(
        (
            b"RIFF",
            struct.pack("<I", 36 + len(pcm)),
            b"WAVEfmt ",
            struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16),
            b"data",
            struct.pack("<I", len(pcm)),
            pcm,
        )
    )


def ogg_crc(page: bytes) -> int:
    crc = 0
    for value in page:
        crc ^= value << 24
        for _ in range(8):
            crc = ((crc << 1) ^ (0x04C11DB7 if crc & 0x80000000 else 0)) & 0xFFFFFFFF
    return crc


def normalize_ogg_serial(raw: bytes, serial: int) -> bytes:
    normalized = bytearray(raw)
    offset = 0
    page_count = 0
    while offset < len(normalized):
        if normalized[offset : offset + 4] != b"OggS" or offset + 27 > len(normalized):
            raise ValueError("invalid generated Ogg page")
        segment_count = normalized[offset + 26]
        header_end = offset + 27 + segment_count
        if header_end > len(normalized):
            raise ValueError("truncated generated Ogg lacing table")
        page_end = header_end + sum(normalized[offset + 27 : header_end])
        if page_end > len(normalized):
            raise ValueError("truncated generated Ogg payload")
        normalized[offset + 14 : offset + 18] = struct.pack("<I", serial)
        normalized[offset + 22 : offset + 26] = bytes(4)
        normalized[offset + 22 : offset + 26] = struct.pack(
            "<I", ogg_crc(bytes(normalized[offset:page_end]))
        )
        offset = page_end
        page_count += 1
    if page_count == 0:
        raise ValueError("generated Ogg has no pages")
    return bytes(normalized)


def encode(path: Path, container_name: str, codec_name: str, pcm: bytes) -> bytes:
    with av.open(str(path), mode="w", format=container_name) as container:
        stream = container.add_stream(codec_name, rate=SAMPLE_RATE)
        stream.layout = "mono"
        stream.bit_rate = 64_000
        input_frame = av.AudioFrame(format="s16", layout="mono", samples=FRAME_COUNT)
        input_frame.sample_rate = SAMPLE_RATE
        input_frame.time_base = Fraction(1, SAMPLE_RATE)
        input_frame.pts = 0
        input_frame.planes[0].update(pcm)
        resampler = av.AudioResampler(
            format=stream.codec_context.format.name,
            layout="mono",
            rate=SAMPLE_RATE,
        )
        for frame in resampler.resample(input_frame):
            for packet in stream.encode(frame):
                container.mux(packet)
        for frame in resampler.resample(None):
            for packet in stream.encode(frame):
                container.mux(packet)
        for packet in stream.encode(None):
            container.mux(packet)
    return path.read_bytes()


def fixture(case_id, codec, container, expected_category, fixture_id, raw, signal_class):
    return {
        "bytesBase64": base64.b64encode(raw).decode("ascii"),
        "caseId": case_id,
        "codec": codec,
        "container": container,
        "expectedCategory": expected_category,
        "fixtureId": fixture_id,
        "sha256": hashlib.sha256(raw).hexdigest().upper(),
        "signalClass": signal_class,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    if av.__version__ != PYAV_VERSION:
        raise SystemExit(f"expected PyAV {PYAV_VERSION}, got {av.__version__}")

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    work = arguments.output.parent / ".qualification-fixture-generation"
    work.mkdir(exist_ok=False)
    try:
        pcm = tone_s16()
        aac = encode(work / "tone.m4a", "ipod", "aac", pcm)
        opus = normalize_ogg_serial(
            encode(work / "tone.opus", "ogg", "libopus", pcm), 0x4346374F
        )
        vorbis = normalize_ogg_serial(
            encode(work / "tone.ogg", "ogg", "libvorbis", pcm), 0x43463756
        )
        silent = wave_bytes(bytes(FRAME_COUNT * 2))

        # Both damaged inputs retain a supported content signature.  The
        # malformed fixture is an invalid Ogg page; the truncated fixture is a
        # real Vorbis stream cut inside its final packet rather than a renamed
        # or extension-only dummy.
        malformed = b"OggS\x00\x02" + bytes(20) + b"\x01" + b"\x10" + b"\x01vorbis" + bytes(9)
        truncated = vorbis[: max(64, len(vorbis) * 3 // 4)]

        fixtures = [
            fixture("aac_mp4_fixture", "AAC-LC", "MPEG-4", 0, "aac-lc-mp4-tone-48000-mono", aac, "nonzero_pcm"),
            fixture("malformed_and_silent_fixtures", "Vorbis", "Ogg", 4, "malformed-ogg-vorbis-page", malformed, "malformed"),
            fixture("opus_fixture", "Opus", "Ogg", 0, "opus-ogg-tone-48000-mono", opus, "nonzero_pcm"),
            fixture("malformed_and_silent_fixtures", "PCM16", "RIFF/WAVE", 0, "silent-pcm16-wave-48000-mono", silent, "intentional_silence"),
            fixture("malformed_and_silent_fixtures", "Vorbis", "Ogg", 5, "truncated-ogg-vorbis-packet", truncated, "truncated"),
            fixture("vorbis_fixture", "Vorbis", "Ogg", 0, "vorbis-ogg-tone-48000-mono", vorbis, "nonzero_pcm"),
        ]
        fixtures.sort(key=lambda item: item["fixtureId"])
        result = canonical(
            {
                "fixtures": fixtures,
                "schema": "cf7.audio-v2.decoder-fixture-inventory.v1",
            }
        )
        arguments.output.write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
    finally:
        for child in work.iterdir():
            child.unlink()
        work.rmdir()


if __name__ == "__main__":
    main()
