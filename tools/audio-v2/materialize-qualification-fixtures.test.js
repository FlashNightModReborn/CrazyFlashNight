#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const subject = require("./materialize-qualification-fixtures.js");

let passed = 0;
function test(name, body) {
    body();
    passed++;
    process.stdout.write("[PASS] " + name + "\n");
}

const repositoryRoot = path.resolve(__dirname, "..", "..");
const runId = "0123456789abcdef0123456789abcdef";
const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-fixture-materializer-"));

const MPEG1_LAYER3_BITRATES_KBPS = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320
];

function makeSyntheticMp3(frameCount, bitrateIndex) {
    const selectedBitrateIndex = bitrateIndex === undefined ? 9 : bitrateIndex;
    const bitrate = MPEG1_LAYER3_BITRATES_KBPS[selectedBitrateIndex] * 1000;
    assert.ok(frameCount > 0 && bitrate > 0);
    const frameBytes = Math.floor(144 * bitrate / 44100);
    const frames = [];
    for (let index = 0; index < frameCount; index++) {
        // MPEG-1 Layer III, 44.1 kHz, mono.  Zero side-info/main-data encodes
        // an empty (silent) granule while each frame remains structurally exact.
        const frame = Buffer.from(new Uint8Array(frameBytes));
        frame[0] = 0xff;
        frame[1] = 0xfb;
        frame[2] = selectedBitrateIndex << 4;
        frame[3] = 0xc0;
        frames.push(frame);
    }
    return Buffer.concat(frames);
}

function parsedSfxRow(linkageId, frameCount, bitrateIndex, shaDigit) {
    const bytes = makeSyntheticMp3(frameCount, bitrateIndex);
    return Object.assign({
        linkageId,
        sourceBytes: bytes.length,
        sourceSha256: String(shaDigit).repeat(64)
    }, subject.parseStrictMp3Frames(bytes, linkageId));
}

try {
    fs.mkdirSync(path.join(temporaryRoot, "tools", "audio-v2"), { recursive: true });
    fs.copyFileSync(
        path.join(repositoryRoot, "tools", "audio-v2", "qualification-decoder-fixtures.v1.json"),
        path.join(temporaryRoot, "tools", "audio-v2", "qualification-decoder-fixtures.v1.json"));
    fs.mkdirSync(path.join(temporaryRoot, "config", "audio-v2"), { recursive: true });
    const shippedRows = [];
    function addShipped(relative, discoveryClass, bytes) {
        const target = path.join(temporaryRoot, ...relative.split("/"));
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, bytes);
        shippedRows.push({
            blobOid: "a".repeat(40),
            bytes: bytes.length,
            codec: "mpeg_audio_layer_iii",
            container: "mpeg_audio",
            discoveryClass,
            path: relative,
            repositoryState: "tracked",
            sha256: subject.sha256(bytes)
        });
    }
    addShipped("sounds/a.mp3", "catalog_registered", Buffer.alloc(1024 * 1024, 1));
    addShipped("sounds/b.mp3", "catalog_registered", Buffer.alloc(1024 * 1024, 2));
    const sfxFrames = [100, 14, 9, 12, 146, 24];
    for (let index = 0; index < 6; index++) {
        addShipped(
            "sounds/export/人物/sfx" + index + ".wav",
            "sfx_preload",
            makeSyntheticMp3(sfxFrames[index], index === 0 ? 14 : 9));
    }
    fs.writeFileSync(
        path.join(temporaryRoot, "config", "audio-v2", "shipped-audio-assets.v1.json"),
        subject.canonicalBytes({ assets: shippedRows, schema: "cf7.audio-v2.shipped-audio-assets.v1" }));

    test("materializes exact three positive fixtures", () => {
        const result = subject.materializeFixtures(temporaryRoot, runId);
        assert.strictEqual(result.fixtures.length, 3);
        assert.strictEqual(result.sfx.length, 6);
        assert.deepStrictEqual(
            result.sfx.map((entry) => entry.linkageId),
            ["sfx0.wav", "sfx1.wav", "sfx2.wav", "sfx3.wav", "sfx4.wav", "sfx5.wav"]);
        assert.deepStrictEqual(result.qualifiedLongSfx, {
            linkageId: "sfx4.wav",
            minimumDurationMs: subject.QUALIFIED_LONG_SFX_MIN_DURATION_MS,
            sourceBytes: 60882,
            sourceDurationMs: 3813,
            sourceFrameCount: 146,
            sourceSampleRate: 44100,
            sourceSha256: result.sfx[4].sourceSha256,
            sourceTotalSamples: 168192
        });
        assert.ok(result.sfx[0].sourceBytes > result.qualifiedLongSfx.sourceBytes);
        assert.ok(result.sfx[0].sourceDurationMs < result.qualifiedLongSfx.minimumDurationMs);
        result.sfx.forEach((entry) => {
            assert.strictEqual(entry.linkageId, path.posix.basename(entry.sourcePath));
            assert.ok(Number.isSafeInteger(entry.sourceBytes) && entry.sourceBytes > 0);
            assert.strictEqual(entry.sourceDurationMs,
                Math.floor(entry.sourceTotalSamples * 1000 / entry.sourceSampleRate));
            assert.notStrictEqual(entry.linkageId, path.posix.basename(
                entry.sourcePath,
                path.posix.extname(entry.sourcePath)));
        });
        assert.ok(result.bgm.primary.relativePath.startsWith("tmp/audio-v2-qualification/"));
        result.fixtures.forEach((entry) => {
            const absolute = path.join(temporaryRoot, ...entry.relativePath.split("/"));
            assert.strictEqual(subject.sha256(fs.readFileSync(absolute)), entry.sha256);
        });
    });

    test("second materialization is byte-identical", () => {
        const first = subject.canonicalBytes(subject.materializeFixtures(temporaryRoot, runId));
        const second = subject.canonicalBytes(subject.materializeFixtures(temporaryRoot, runId));
        assert.ok(first.equals(second));
    });

    test("rejects tracked SFX source byte drift before trusting its inventory hash", () => {
        const result = subject.materializeFixtures(temporaryRoot, runId);
        const target = path.join(temporaryRoot, ...result.sfx[4].sourcePath.split("/"));
        const original = fs.readFileSync(target);
        const drifted = Buffer.from(original);
        drifted[0] ^= 0xff;
        try {
            fs.writeFileSync(target, drifted);
            assert.throws(() => subject.materializeFixtures(temporaryRoot, runId), /stimulus source bytes drifted/);
        } finally {
            fs.writeFileSync(target, original);
        }
    });

    test("rejects existing fixture byte drift", () => {
        const result = subject.materializeFixtures(temporaryRoot, runId);
        const target = path.join(temporaryRoot, ...result.fixtures[0].relativePath.split("/"));
        fs.writeFileSync(target, Buffer.from("drift", "utf8"));
        assert.throws(() => subject.materializeFixtures(temporaryRoot, runId), /bytes drifted/);
    });

    test("rejects noncanonical run id", () => {
        assert.throws(() => subject.materializeFixtures(temporaryRoot, runId.toUpperCase()), /lowercase hex/);
    });

    test("rejects malformed non-MP3 truncated and trailing frame bytes", () => {
        assert.throws(() => subject.parseStrictMp3Frames(Buffer.from("not-mp3", "ascii"), "bad"),
            /malformed or non-MP3/);
        const valid = makeSyntheticMp3(2);
        assert.throws(() => subject.parseStrictMp3Frames(valid.subarray(0, valid.length - 1), "truncated"),
            /truncated MP3 frame/);
        assert.throws(() => subject.parseStrictMp3Frames(Buffer.concat([valid, Buffer.from([0])]), "trailing"),
            /trailing bytes/);
    });

    test("rejects an SFX set with no hash-bound sample of at least three seconds", () => {
        const shortRows = Array.from({ length: 6 }, (_, index) =>
            parsedSfxRow("short" + index + ".wav", 114, index === 0 ? 14 : 9, index + 1));
        assert.ok(shortRows[0].sourceBytes > 100000);
        assert.throws(() => subject.selectQualifiedLongSfx(shortRows), /no qualified long sample/);
    });

    test("long SFX selection is duration-first with bytes and linkage-id tie breaking", () => {
        const rows = [
            parsedSfxRow("z.wav", 120, 14, "A"),
            parsedSfxRow("b.wav", 146, 9, "B"),
            parsedSfxRow("a.wav", 146, 9, "C")
        ];
        assert.strictEqual(subject.selectQualifiedLongSfx(rows).linkageId, "a.wav");
    });
} finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

process.stdout.write("materialize qualification fixtures tests passed: " + passed + "\n");
