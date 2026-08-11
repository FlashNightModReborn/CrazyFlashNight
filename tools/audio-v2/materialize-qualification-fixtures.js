#!/usr/bin/env node
"use strict";

// Materialize the three positive decoder fixtures used by the qualification-only
// AS2 stimulus surface.  The files live under ignored tmp/ state, never enter the
// shipped-audio inventory, and are accepted only when their bytes match the
// tracked fixture inventory exactly.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const INVENTORY_PATH = "tools/audio-v2/qualification-decoder-fixtures.v1.json";
const SHIPPED_INVENTORY_PATH = "config/audio-v2/shipped-audio-assets.v1.json";
const OUTPUT_SCHEMA = "cf7.audio-v2.materialized-qualification-fixtures.v1";
const QUALIFIED_LONG_SFX_MIN_DURATION_MS = 3000;
const MPEG1_LAYER3_BITRATES_KBPS = Object.freeze([
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320
]);
const MPEG2_LAYER3_BITRATES_KBPS = Object.freeze([
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160
]);
const POSITIVE_FIXTURES = Object.freeze({
    "aac-lc-mp4-tone-48000-mono": "format-aac.m4a",
    "opus-ogg-tone-48000-mono": "format-opus.opus",
    "vorbis-ogg-tone-48000-mono": "format-vorbis.ogg"
});

function fail(message) {
    throw new Error(message);
}

function sha256(bytes) {
    return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
}

function sortedClone(value) {
    if (Array.isArray(value)) return value.map(sortedClone);
    if (!value || typeof value !== "object") return value;
    const result = {};
    Object.keys(value).sort().forEach((key) => { result[key] = sortedClone(value[key]); });
    return result;
}

function canonicalBytes(value) {
    return Buffer.from(JSON.stringify(sortedClone(value), null, 2) + "\n", "utf8");
}

function expectLowerHex32(value, label) {
    if (!/^[0-9a-f]{32}$/.test(value || "")) fail(label + " must be 32 lowercase hex characters");
}

function ensureRealDirectory(directory, allowedRoot) {
    const root = path.resolve(allowedRoot);
    const target = path.resolve(directory);
    const relative = path.relative(root, target);
    if (relative.startsWith("..") || path.isAbsolute(relative)) fail("fixture directory escapes project root");

    const missing = [];
    let cursor = target;
    while (!fs.existsSync(cursor)) {
        missing.push(cursor);
        const parent = path.dirname(cursor);
        if (parent === cursor) fail("fixture directory ancestry is invalid");
        cursor = parent;
    }
    for (let current = cursor; ; current = path.dirname(current)) {
        const stat = fs.lstatSync(current);
        if (!stat.isDirectory() || stat.isSymbolicLink()) fail("fixture directory ancestry contains a reparse/symlink: " + current);
        if (path.resolve(current) === root) break;
        const parent = path.dirname(current);
        if (parent === current) fail("fixture directory ancestry does not reach project root");
    }
    missing.reverse().forEach((current) => fs.mkdirSync(current));
}

function readInventory(projectRoot) {
    const inventoryPath = path.join(projectRoot, ...INVENTORY_PATH.split("/"));
    const bytes = fs.readFileSync(inventoryPath);
    let value;
    try { value = JSON.parse(bytes.toString("utf8")); }
    catch (error) { fail("decoder fixture inventory is not JSON: " + error.message); }
    if (!bytes.equals(canonicalBytes(value))) fail("decoder fixture inventory is not canonical JSON");
    if (value.schema !== "cf7.audio-v2.decoder-fixture-inventory.v1" || !Array.isArray(value.fixtures)) {
        fail("decoder fixture inventory schema is invalid");
    }
    return { bytes, value };
}

function readCanonicalJson(projectRoot, relative, schema) {
    const absolute = path.join(projectRoot, ...relative.split("/"));
    const bytes = fs.readFileSync(absolute);
    let value;
    try { value = JSON.parse(bytes.toString("utf8")); }
    catch (error) { fail(relative + " is not JSON: " + error.message); }
    if (!bytes.equals(canonicalBytes(value))) fail(relative + " is not canonical JSON");
    if (value.schema !== schema) fail(relative + " schema is invalid");
    return { bytes, value };
}

function readBoundAsset(projectRoot, row) {
    const source = path.join(projectRoot, ...row.path.split("/"));
    const sourceStat = fs.lstatSync(source);
    if (!sourceStat.isFile() || sourceStat.isSymbolicLink()) fail("stimulus source is not a regular file: " + row.path);
    const bytes = fs.readFileSync(source);
    if (bytes.length !== row.bytes || sha256(bytes) !== row.sha256) fail("stimulus source bytes drifted: " + row.path);
    return bytes;
}

function parseStrictMp3Frames(bytes, label) {
    if (!Buffer.isBuffer(bytes) || bytes.length < 4) fail(label + " is not a nonempty MPEG Layer III stream");
    let frameCount = 0;
    let offset = 0;
    let sampleRate = null;
    let totalSamples = 0;
    let versionBits = null;
    while (offset < bytes.length) {
        if (bytes.length - offset < 4) fail(label + " has trailing bytes after its final MP3 frame");
        const header = bytes.readUInt32BE(offset);
        if ((header >>> 21) !== 0x7ff) fail(label + " has a malformed or non-MP3 frame header");
        const currentVersionBits = (header >>> 19) & 0x3;
        const layerBits = (header >>> 17) & 0x3;
        const bitrateIndex = (header >>> 12) & 0xf;
        const sampleRateIndex = (header >>> 10) & 0x3;
        const padding = (header >>> 9) & 0x1;
        if (currentVersionBits === 1 || layerBits !== 1 || bitrateIndex === 0 || bitrateIndex === 15 || sampleRateIndex === 3) {
            fail(label + " contains an unsupported or malformed MPEG Layer III frame");
        }
        const rates = currentVersionBits === 3
            ? [44100, 48000, 32000]
            : (currentVersionBits === 2 ? [22050, 24000, 16000] : [11025, 12000, 8000]);
        const currentSampleRate = rates[sampleRateIndex];
        if (sampleRate === null) {
            sampleRate = currentSampleRate;
            versionBits = currentVersionBits;
        } else if (currentSampleRate !== sampleRate || currentVersionBits !== versionBits) {
            fail(label + " changes MPEG version or sample rate between frames");
        }
        const bitrates = currentVersionBits === 3 ? MPEG1_LAYER3_BITRATES_KBPS : MPEG2_LAYER3_BITRATES_KBPS;
        const bitrate = bitrates[bitrateIndex] * 1000;
        const samplesPerFrame = currentVersionBits === 3 ? 1152 : 576;
        const coefficient = currentVersionBits === 3 ? 144 : 72;
        const frameBytes = Math.floor(coefficient * bitrate / currentSampleRate) + padding;
        if (frameBytes < 4 || offset + frameBytes > bytes.length) fail(label + " has a truncated MP3 frame");
        offset += frameBytes;
        frameCount++;
        totalSamples += samplesPerFrame;
        if (!Number.isSafeInteger(totalSamples)) fail(label + " decoded sample count exceeds the safe integer bound");
    }
    if (frameCount === 0 || offset !== bytes.length) fail(label + " does not close over exact MP3 frame bytes");
    return {
        sourceDurationMs: Math.floor(totalSamples * 1000 / sampleRate),
        sourceFrameCount: frameCount,
        sourceSampleRate: sampleRate,
        sourceTotalSamples: totalSamples
    };
}

function copyBoundAsset(projectRoot, outputDirectory, row, fileName) {
    const bytes = readBoundAsset(projectRoot, row);
    const output = path.join(outputDirectory, fileName);
    if (fs.existsSync(output)) {
        const outputStat = fs.lstatSync(output);
        if (!outputStat.isFile() || outputStat.isSymbolicLink() || !fs.readFileSync(output).equals(bytes)) {
            fail("existing stimulus copy bytes drifted: " + output);
        }
    } else {
        const temporary = output + ".tmp-" + process.pid;
        fs.writeFileSync(temporary, bytes, { flag: "wx" });
        fs.renameSync(temporary, output);
    }
    return {
        bytes: bytes.length,
        relativePath: path.relative(projectRoot, output).split(path.sep).join("/"),
        sha256: row.sha256,
        sourceBlobOid: row.blobOid,
        sourcePath: row.path
    };
}

function selectQualifiedLongSfx(rows) {
    if (!Array.isArray(rows)) fail("SFX stimulus rows are invalid");
    const candidates = rows.filter((entry) => entry &&
        Number.isSafeInteger(entry.sourceBytes) && entry.sourceBytes > 0 &&
        Number.isSafeInteger(entry.sourceDurationMs) && entry.sourceDurationMs >= QUALIFIED_LONG_SFX_MIN_DURATION_MS &&
        Number.isSafeInteger(entry.sourceFrameCount) && entry.sourceFrameCount > 0 &&
        Number.isSafeInteger(entry.sourceSampleRate) && entry.sourceSampleRate > 0 &&
        Number.isSafeInteger(entry.sourceTotalSamples) && entry.sourceTotalSamples > 0 &&
        entry.sourceDurationMs === Math.floor(entry.sourceTotalSamples * 1000 / entry.sourceSampleRate) &&
        typeof entry.linkageId === "string" && entry.linkageId.length > 0 &&
        /^[A-F0-9]{64}$/.test(entry.sourceSha256 || ""));
    if (candidates.length === 0) fail("tracked SFX stimulus set has no qualified long sample");
    return candidates.slice().sort((left, right) =>
        right.sourceDurationMs - left.sourceDurationMs ||
        right.sourceBytes - left.sourceBytes ||
        left.linkageId.localeCompare(right.linkageId, "en"))[0];
}

function materializeFixtures(projectRoot, runId) {
    if (!path.isAbsolute(projectRoot)) fail("projectRoot must be absolute");
    const root = path.resolve(projectRoot);
    expectLowerHex32(runId, "runId");
    const inventory = readInventory(root);
    const shipped = readCanonicalJson(
        root,
        SHIPPED_INVENTORY_PATH,
        "cf7.audio-v2.shipped-audio-assets.v1");
    const outputDirectory = path.join(root, "tmp", "audio-v2-qualification", runId, "fixtures");
    ensureRealDirectory(outputDirectory, root);

    const selected = inventory.value.fixtures.filter((entry) =>
        Object.prototype.hasOwnProperty.call(POSITIVE_FIXTURES, entry.fixtureId));
    if (selected.length !== Object.keys(POSITIVE_FIXTURES).length) fail("positive decoder fixture set is incomplete");

    const rows = selected.map((entry) => {
        if (entry.expectedCategory !== 0 || entry.signalClass !== "nonzero_pcm" || !/^[A-F0-9]{64}$/.test(entry.sha256 || "")) {
            fail("positive decoder fixture metadata is invalid: " + entry.fixtureId);
        }
        const bytes = Buffer.from(entry.bytesBase64 || "", "base64");
        if (!bytes.length || bytes.toString("base64") !== entry.bytesBase64 || sha256(bytes) !== entry.sha256) {
            fail("positive decoder fixture bytes drifted: " + entry.fixtureId);
        }
        const fileName = POSITIVE_FIXTURES[entry.fixtureId];
        const absolute = path.join(outputDirectory, fileName);
        if (fs.existsSync(absolute)) {
            const stat = fs.lstatSync(absolute);
            if (!stat.isFile() || stat.isSymbolicLink()) fail("fixture output is not a regular file: " + absolute);
            if (!fs.readFileSync(absolute).equals(bytes)) fail("existing fixture output bytes drifted: " + absolute);
        } else {
            const temporary = absolute + ".tmp-" + process.pid;
            fs.writeFileSync(temporary, bytes, { flag: "wx" });
            fs.renameSync(temporary, absolute);
        }
        return {
            bytes: bytes.length,
            codec: entry.codec,
            container: entry.container,
            fixtureId: entry.fixtureId,
            relativePath: path.relative(root, absolute).split(path.sep).join("/"),
            sha256: entry.sha256
        };
    }).sort((left, right) => left.fixtureId.localeCompare(right.fixtureId, "en"));

    const bgmCandidates = shipped.value.assets.filter((entry) =>
        entry.repositoryState === "tracked" &&
        ["catalog_registered", "catalog_discovered"].includes(entry.discoveryClass) &&
        entry.codec === "mpeg_audio_layer_iii" && entry.bytes >= 1024 * 1024)
        .sort((left, right) => left.path.localeCompare(right.path, "en"));
    if (bgmCandidates.length < 2) fail("tracked MP3 BGM stimulus set is incomplete");
    const primaryBgm = copyBoundAsset(root, outputDirectory, bgmCandidates[0], "bgm-primary.mp3");
    const crossfadeBgm = copyBoundAsset(root, outputDirectory, bgmCandidates[1], "bgm-crossfade.mp3");

    const sfxRows = shipped.value.assets.filter((entry) =>
        entry.repositoryState === "tracked" && entry.discoveryClass === "sfx_preload");
    const byId = new Map();
    sfxRows.forEach((entry) => {
        // AudioCoordinator.ScanDefaultCatalog uses Path.GetFileName(), so the
        // production linkage key includes the extension.  Keep this byte-for-
        // byte contract here instead of deriving an extensionless fixture ID.
        const linkageId = path.posix.basename(entry.path);
        if (!byId.has(linkageId)) byId.set(linkageId, []);
        byId.get(linkageId).push(entry);
    });
    const sfx = Array.from(byId.entries())
        .filter((entry) => entry[1].length === 1 && entry[1][0].bytes > 0)
        .sort((left, right) => left[0].localeCompare(right[0], "en"))
        .slice(0, 6)
        .map((entry) => {
            const source = entry[1][0];
            if (source.codec !== "mpeg_audio_layer_iii" || source.container !== "mpeg_audio") {
                fail("tracked SFX stimulus codec/container metadata is invalid: " + source.path);
            }
            const parsed = parseStrictMp3Frames(readBoundAsset(root, source), source.path);
            return Object.assign({
                linkageId: entry[0],
                sourceBlobOid: source.blobOid,
                sourceBytes: source.bytes,
                sourcePath: source.path,
                sourceSha256: source.sha256
            }, parsed);
        });
    if (sfx.length !== 6) fail("unique tracked SFX stimulus set is incomplete");
    const longSfx = selectQualifiedLongSfx(sfx);

    const result = {
        bgm: { crossfade: crossfadeBgm, primary: primaryBgm },
        fixtures: rows,
        inventorySha256: sha256(inventory.bytes),
        qualifiedLongSfx: {
            linkageId: longSfx.linkageId,
            minimumDurationMs: QUALIFIED_LONG_SFX_MIN_DURATION_MS,
            sourceBytes: longSfx.sourceBytes,
            sourceDurationMs: longSfx.sourceDurationMs,
            sourceFrameCount: longSfx.sourceFrameCount,
            sourceSampleRate: longSfx.sourceSampleRate,
            sourceSha256: longSfx.sourceSha256,
            sourceTotalSamples: longSfx.sourceTotalSamples
        },
        runId,
        schema: OUTPUT_SCHEMA,
        shippedInventorySha256: sha256(shipped.bytes),
        sfx
    };
    const planPath = path.join(outputDirectory, "stimulus-plan.v1.json");
    const planBytes = canonicalBytes(result);
    if (fs.existsSync(planPath)) {
        const stat = fs.lstatSync(planPath);
        if (!stat.isFile() || stat.isSymbolicLink() || !fs.readFileSync(planPath).equals(planBytes)) {
            fail("existing stimulus plan bytes drifted");
        }
    } else fs.writeFileSync(planPath, planBytes, { flag: "wx" });
    result.planRelativePath = path.relative(root, planPath).split(path.sep).join("/");
    return result;
}

function parseArguments(argv) {
    if (argv.length !== 4 || argv[0] !== "--project-root" || argv[2] !== "--run-id") {
        fail("usage: materialize-qualification-fixtures.js --project-root <absolute> --run-id <32-lowercase-hex>");
    }
    return { projectRoot: argv[1], runId: argv[3] };
}

function main(argv) {
    const options = parseArguments(argv);
    process.stdout.write(canonicalBytes(materializeFixtures(options.projectRoot, options.runId)));
}

if (require.main === module) {
    try { main(process.argv.slice(2)); }
    catch (error) {
        process.stderr.write("audio-v2 fixture materialization failed: " + String(error.message || error).replace(/[\r\n]+/g, " ") + "\n");
        process.exitCode = 3;
    }
}

module.exports = Object.freeze({
    canonicalBytes,
    materializeFixtures,
    parseStrictMp3Frames,
    QUALIFIED_LONG_SFX_MIN_DURATION_MS,
    selectQualifiedLongSfx,
    sha256
});
