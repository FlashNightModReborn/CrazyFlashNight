#!/usr/bin/env node
"use strict";

// Deterministic A5 inventory producer. This file describes tracked physical
// audio bytes and current discovery ownership; it does not rename assets,
// repair references, infer audibility, or claim decode-to-EOF qualification.

const cp = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..", "..");
const OUTPUT_REL = "config/audio-v2/shipped-audio-assets.v1.json";
const PRODUCER_REL = "tools/audio-v2/generate-shipped-audio-assets.js";
const INVENTORY_EXTENSIONS = Object.freeze([".flac", ".m4a", ".mp3", ".mp4", ".ogg", ".opus", ".wav", ".waz"]);
const CATALOG_EXTENSIONS = Object.freeze([
    ".aac", ".adts", ".flac", ".m4a", ".mp3", ".mp4", ".ogg", ".opus", ".wav"
]);
const SFX_PACKS = Object.freeze(["武器", "特效", "人物"]);
const RECOVERY_PREFIX = "sounds/恢复_音效-武器/LIBRARY/";
const SOURCE_PATHS = Object.freeze({
    bgmRegistration: "sounds/bgm_list.xml",
    configEolPolicy: "config/audio-v2/.gitattributes",
    latentSfxDefinition: "scripts/逻辑/装备函数/双面雷神.as",
    latentSfxItem: "data/items/武器_长枪_特殊.xml",
    musicCatalog: "launcher/src/Audio/MusicCatalog.cs",
    preloadObservation: "docs/evidence/audio-v2/research-ready-preload-observation.json",
    recoveryXfl: "sounds/恢复_音效-武器/DOMDocument.xml",
    sfxPreload: "launcher/src/Audio/AudioCoordinator.cs",
    toolsEolPolicy: "tools/audio-v2/.gitattributes"
});
const EXPECTED = Object.freeze({
    catalogDiscovered: 4,
    catalogRegistered: 86,
    codec: Object.freeze({ aac_lc_or_he_aac: 11, mpeg_audio_layer_iii: 756, pcm_s16le: 60 }),
    container: Object.freeze({ iso_bmff: 11, mpeg_audio: 756, riff_wave: 60 }),
    extension: Object.freeze({ ".m4a": 11, ".mp3": 215, ".wav": 599, ".waz": 2 }),
    missingLatentReferences: 1,
    missingRegisteredReferences: 1,
    outside: Object.freeze({ musicRoot: 29, obsolete: 0, ownedException: 29, runtimeReachable: 0, soundsRecoveryLibrary: 32, sourceOnly: 32, total: 61 }),
    preloadSfx: 676,
    total: 827
});

class InventoryError extends Error {
    constructor(message) {
        super(message);
        this.name = "InventoryError";
    }
}

function fail(message) {
    throw new InventoryError(message);
}

function expect(condition, message) {
    if (!condition) fail(message);
}

function compareText(left, right) {
    return left < right ? -1 : (left > right ? 1 : 0);
}

function sortedClone(value) {
    if (Array.isArray(value)) return value.map(sortedClone);
    if (value && typeof value === "object") {
        const result = {};
        Object.keys(value).sort(compareText).forEach((key) => { result[key] = sortedClone(value[key]); });
        return result;
    }
    return value;
}

function canonicalBytes(value) {
    return Buffer.from(JSON.stringify(sortedClone(value), null, 2) + "\n", "utf8");
}

function sha256(bytes) {
    return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
}

function gitBlobOid(bytes, objectFormat) {
    const algorithm = objectFormat === "sha256" ? "sha256" : "sha1";
    return crypto.createHash(algorithm)
        .update(Buffer.from("blob " + bytes.length + "\0", "utf8"))
        .update(bytes)
        .digest("hex");
}

function safeRepoPath(relative, label) {
    expect(typeof relative === "string" && relative.length > 0 && relative.length <= 4096, label + " is empty or too long");
    expect(!relative.includes("\\") && !relative.includes("\0") && !path.posix.isAbsolute(relative), label + " is not repo-relative POSIX");
    expect(path.posix.normalize(relative) === relative && !relative.split("/").some((part) => !part || part === "." || part === ".."), label + " has an unsafe segment");
    return relative;
}

function samePath(left, right) {
    const a = path.resolve(left);
    const b = path.resolve(right);
    return process.platform === "win32" ? a.toLowerCase() === b.toLowerCase() : a === b;
}

function readBoundFile(root, relative, label) {
    safeRepoPath(relative, label + " path");
    const rootReal = fs.realpathSync.native(root);
    const file = path.resolve(root, relative.split("/").join(path.sep));
    const rootPrefix = path.resolve(root) + path.sep;
    const comparableFile = process.platform === "win32" ? file.toLowerCase() : file;
    const comparablePrefix = process.platform === "win32" ? rootPrefix.toLowerCase() : rootPrefix;
    expect(comparableFile.startsWith(comparablePrefix), label + " escapes repository root");
    const stat = fs.lstatSync(file);
    expect(stat.isFile() && !stat.isSymbolicLink(), label + " is not a regular non-link file: " + relative);
    const real = fs.realpathSync.native(file);
    const realPrefix = rootReal + path.sep;
    const comparableReal = process.platform === "win32" ? real.toLowerCase() : real;
    const comparableRealPrefix = process.platform === "win32" ? realPrefix.toLowerCase() : realPrefix;
    expect(comparableReal.startsWith(comparableRealPrefix), label + " resolves outside repository root: " + relative);
    const bytes = fs.readFileSync(real);
    expect(bytes.length === stat.size && bytes.length > 0, label + " changed while being read or is empty: " + relative);
    return bytes;
}

function canonicalTextBytes(bytes, label, allowBom, requireTerminalLf) {
    let text = bytes.toString("utf8");
    expect(Buffer.from(text, "utf8").equals(bytes), label + " is not strict UTF-8");
    if (!allowBom) expect(text.charCodeAt(0) !== 0xFEFF, label + " must not contain a UTF-8 BOM");
    text = text.replace(/\r\n/g, "\n");
    expect(!text.includes("\r"), label + " contains a bare CR");
    if (requireTerminalLf !== false) expect(text.endsWith("\n"), label + " must end with LF");
    return Buffer.from(text, "utf8");
}

function objectFormat(root) {
    const result = cp.spawnSync("git", ["rev-parse", "--show-object-format"], { cwd: root, encoding: "utf8" });
    expect(result.status === 0, "cannot determine Git object format: " + String(result.stderr || "").trim());
    const format = result.stdout.trim();
    expect(format === "sha1" || format === "sha256", "unsupported Git object format: " + format);
    return format;
}

function inventoryAudioPaths(root) {
    const result = cp.spawnSync("git", ["ls-files", "-z", "--", "sounds", "music"], { cwd: root, encoding: null, maxBuffer: 16 * 1024 * 1024 });
    expect(result.status === 0, "git ls-files failed for audio roots");
    const paths = result.stdout.toString("utf8").split("\0").filter(Boolean).map((entry) => entry.replace(/\\/g, "/"));
    const tracked = paths.filter((entry) => INVENTORY_EXTENSIONS.includes(path.posix.extname(entry).toLowerCase())).sort(compareText);
    expect(tracked.length === 795, "tracked audio denominator drifted: expected 795, got " + tracked.length);
    const recoveryDirectory = path.join(root, RECOVERY_PREFIX.split("/").join(path.sep));
    const ignored = fs.readdirSync(recoveryDirectory, { withFileTypes: true })
        .filter((entry) => entry.isFile() && INVENTORY_EXTENSIONS.includes(path.extname(entry.name).toLowerCase()))
        .map((entry) => RECOVERY_PREFIX + entry.name)
        .sort(compareText);
    expect(ignored.length === EXPECTED.outside.soundsRecoveryLibrary, "ignored recovery-source audio count drifted: " + ignored.length);
    const ignoredCheck = cp.spawnSync("git", ["check-ignore", "-z", "--stdin"], {
        cwd: root,
        encoding: null,
        input: Buffer.from(ignored.join("\0") + "\0", "utf8"),
        maxBuffer: 1024 * 1024
    });
    expect(ignoredCheck.status === 0, "recovery-source assets are no longer uniformly ignored; repository-state policy requires review");
    const ignoredReported = ignoredCheck.stdout.toString("utf8").split("\0").filter(Boolean).map((entry) => entry.replace(/\\/g, "/")).sort(compareText);
    expect(JSON.stringify(ignoredReported) === JSON.stringify(ignored), "git check-ignore did not return the exact recovery-source set");
    const selected = tracked.map((entry) => ({ path: entry, repositoryState: "tracked" }))
        .concat(ignored.map((entry) => ({ path: entry, repositoryState: "ignored_source" })))
        .sort((left, right) => compareText(left.path, right.path));
    const lower = new Set();
    selected.forEach((entry) => {
        safeRepoPath(entry.path, "audio inventory path");
        const folded = entry.path.toLowerCase();
        expect(!lower.has(folded), "audio inventory path is duplicated or case-colliding: " + entry.path);
        lower.add(folded);
    });
    expect(selected.length === EXPECTED.total, "physical audio denominator drifted: expected " + EXPECTED.total + ", got " + selected.length);
    return selected;
}

function mpegLayerThreeFrame(bytes, offset) {
    if (offset < 0 || offset + 4 > bytes.length || bytes[offset] !== 0xFF || (bytes[offset + 1] & 0xE0) !== 0xE0) return null;
    const version = (bytes[offset + 1] >> 3) & 0x03;
    const layer = (bytes[offset + 1] >> 1) & 0x03;
    const bitrateIndex = (bytes[offset + 2] >> 4) & 0x0F;
    const sampleRateIndex = (bytes[offset + 2] >> 2) & 0x03;
    const padding = (bytes[offset + 2] >> 1) & 0x01;
    if (version === 1 || layer !== 1 || bitrateIndex === 0 || bitrateIndex === 15 || sampleRateIndex === 3) return null;
    const mpeg1Bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0];
    const mpeg2Bitrates = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0];
    const sampleRates = {
        0: [11025, 12000, 8000],
        2: [22050, 24000, 16000],
        3: [44100, 48000, 32000]
    };
    const bitrateKbps = (version === 3 ? mpeg1Bitrates : mpeg2Bitrates)[bitrateIndex];
    const sampleRate = sampleRates[version][sampleRateIndex];
    const coefficient = version === 3 ? 144 : 72;
    const frameLength = Math.floor(coefficient * bitrateKbps * 1000 / sampleRate) + padding;
    return frameLength >= 24 ? { frameLength, version } : null;
}

function findMpegLayerThreeFrame(bytes, start, limit) {
    const end = Math.min(bytes.length - 4, limit);
    for (let offset = Math.max(0, start); offset <= end; offset++) {
        const first = mpegLayerThreeFrame(bytes, offset);
        if (!first) continue;
        const second = mpegLayerThreeFrame(bytes, offset + first.frameLength);
        if (second && second.version === first.version) return offset;
    }
    return -1;
}

function parseWaveCodec(bytes, relative) {
    let offset = 12;
    let format = null;
    while (offset + 8 <= bytes.length) {
        const id = bytes.toString("ascii", offset, offset + 4);
        const size = bytes.readUInt32LE(offset + 4);
        const start = offset + 8;
        const end = start + size;
        expect(end <= bytes.length, "truncated RIFF chunk in " + relative);
        if (id === "fmt ") {
            expect(size >= 16, "short RIFF fmt chunk in " + relative);
            format = { bits: bytes.readUInt16LE(start + 14), tag: bytes.readUInt16LE(start) };
            break;
        }
        offset = end + (size & 1);
    }
    expect(format, "RIFF/WAVE has no fmt chunk: " + relative);
    if (format.tag === 1 && format.bits === 16) return "pcm_s16le";
    if (format.tag === 0x55) return "mpeg_audio_layer_iii";
    fail("unsupported RIFF/WAVE codec tag " + format.tag + "/" + format.bits + " in " + relative);
}

function sniffAudio(bytes, relative) {
    expect(Buffer.isBuffer(bytes) && bytes.length >= 4, "audio file is too short: " + relative);
    if (bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WAVE") {
        return { codec: parseWaveCodec(bytes, relative), container: "riff_wave" };
    }
    if (bytes.toString("ascii", 0, 4) === "fLaC") return { codec: "flac", container: "flac" };
    if (bytes.toString("ascii", 0, 4) === "OggS") {
        const header = bytes.subarray(0, Math.min(bytes.length, 65536));
        if (header.indexOf(Buffer.from("OpusHead", "ascii")) >= 0) return { codec: "opus", container: "ogg" };
        if (header.indexOf(Buffer.from("vorbis", "ascii")) >= 0) return { codec: "vorbis", container: "ogg" };
        fail("Ogg container has no recognized codec marker: " + relative);
    }
    if (bytes.length >= 12 && bytes.toString("ascii", 4, 8) === "ftyp") {
        expect(bytes.indexOf(Buffer.from("mp4a", "ascii")) >= 0, "ISO BMFF has no mp4a sample entry: " + relative);
        return { codec: "aac_lc_or_he_aac", container: "iso_bmff" };
    }
    const asf = Buffer.from("3026b2758e66cf11a6d900aa0062ce6c", "hex");
    if (bytes.subarray(0, asf.length).equals(asf)) return { codec: "wma", container: "asf" };
    if (bytes[0] === 0xFF && (bytes[1] & 0xF6) === 0xF0) return { codec: "aac_lc_or_he_aac", container: "adts" };
    let frameStart = 0;
    if (bytes.toString("ascii", 0, 3) === "ID3") {
        expect(bytes.length >= 10 && !(bytes[6] & 0x80) && !(bytes[7] & 0x80) && !(bytes[8] & 0x80) && !(bytes[9] & 0x80), "invalid ID3 header: " + relative);
        const tagSize = ((bytes[6] & 0x7F) << 21) | ((bytes[7] & 0x7F) << 14) | ((bytes[8] & 0x7F) << 7) | (bytes[9] & 0x7F);
        frameStart = 10 + tagSize;
        expect(frameStart < bytes.length, "ID3 tag consumes the file: " + relative);
    }
    const frame = findMpegLayerThreeFrame(bytes, frameStart, frameStart + 131072);
    if (frame >= 0) return { codec: "mpeg_audio_layer_iii", container: "mpeg_audio" };
    fail("unrecognized audio content: " + relative);
}

function decodeXml(value) {
    return value
        .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
        .replace(/&#([0-9]+);/g, (_, decimal) => String.fromCodePoint(parseInt(decimal, 10)))
        .replace(/&quot;/g, "\"")
        .replace(/&apos;/g, "'")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&amp;/g, "&");
}

function childText(block, tag) {
    const match = new RegExp("<" + tag + ">([\\s\\S]*?)</" + tag + ">", "i").exec(block);
    return match ? decodeXml(match[1].trim()) : "";
}

function parseBgmRegistrations(text) {
    const rows = [];
    const expression = /<music>([\s\S]*?)<\/music>/gi;
    let match;
    while ((match = expression.exec(text)) !== null) {
        const title = childText(match[1], "title");
        const url = childText(match[1], "url").replace(/\\/g, "/");
        if (!title || !url || title === "stop") continue;
        safeRepoPath(url, "registered BGM URL");
        rows.push({ title, url });
    }
    expect(rows.length === 88, "non-stop BGM registration row count drifted: " + rows.length);
    const byUrl = new Map();
    rows.forEach((row) => {
        const key = row.url.toLowerCase();
        if (!byUrl.has(key)) byUrl.set(key, { titles: [], url: row.url });
        byUrl.get(key).titles.push(row.title);
    });
    byUrl.forEach((entry) => entry.titles.sort(compareText));
    expect(byUrl.size === 87, "unique BGM registration URL count drifted: " + byUrl.size);
    return byUrl;
}

function parseAttributes(tag) {
    const result = {};
    const expression = /([A-Za-z_:][A-Za-z0-9_.:-]*)="([^"]*)"/g;
    let match;
    while ((match = expression.exec(tag)) !== null) result[match[1]] = decodeXml(match[2]);
    return result;
}

function parseRecoveryItems(text) {
    const byHref = new Map();
    const tags = text.match(/<DOMSoundItem\b[^>]*>/g) || [];
    tags.forEach((tag) => {
        const attributes = parseAttributes(tag);
        if (!attributes.href) return;
        expect(!byHref.has(attributes.href.toLowerCase()), "duplicate recovery XFL href: " + attributes.href);
        byHref.set(attributes.href.toLowerCase(), attributes);
    });
    expect(byHref.size >= EXPECTED.outside.soundsRecoveryLibrary, "recovery XFL has fewer sound items than the tracked recovery library");
    return byHref;
}

function sourceDescriptor(root, relative, role, format, repositoryState) {
    const raw = readBoundFile(root, relative, "source evidence " + role);
    const bytes = repositoryState === "ignored_source"
        ? raw
        : canonicalTextBytes(raw, "source evidence " + relative, true, false);
    return {
        blobOid: gitBlobOid(bytes, format),
        bytes: bytes.length,
        path: relative,
        repositoryState: repositoryState || "tracked",
        role,
        sha256: sha256(bytes)
    };
}

function assertEolPolicies(root) {
    const tools = canonicalTextBytes(readBoundFile(root, SOURCE_PATHS.toolsEolPolicy, "tools audio-v2 EOL policy"), SOURCE_PATHS.toolsEolPolicy).toString("utf8");
    const config = canonicalTextBytes(readBoundFile(root, SOURCE_PATHS.configEolPolicy, "config audio-v2 EOL policy"), SOURCE_PATHS.configEolPolicy).toString("utf8");
    expect(tools === "*.c text eol=lf\n*.js text eol=lf\n*.json text eol=lf\n*.ps1 text eol=lf\n*.py text eol=lf\n", "tools/audio-v2 EOL policy drifted");
    expect(config === "*.json text eol=lf\n", "config/audio-v2 EOL policy drifted");
}

function evidence(kind, source, locator) {
    return { kind, locator, sourcePath: source.path, sourceSha256: source.sha256 };
}

function assetDescriptor(root, relative, repositoryState, format) {
    const bytes = readBoundFile(root, relative, "audio asset");
    const content = sniffAudio(bytes, relative);
    return {
        blobOid: gitBlobOid(bytes, format),
        bytes: bytes.length,
        codec: content.codec,
        container: content.container,
        discoveryClass: null,
        extension: path.posix.extname(relative).toLowerCase(),
        nextAction: null,
        outsideClassification: null,
        owner: null,
        path: relative,
        reason: null,
        referenceEvidence: null,
        repositoryState,
        sha256: sha256(bytes)
    };
}

function isCatalogPhysical(relative) {
    const parts = relative.split("/");
    return parts.length === 3 && parts[0] === "sounds" && parts[1].toLowerCase() !== "export" && CATALOG_EXTENSIONS.includes(path.posix.extname(relative).toLowerCase());
}

function isPreloadSfx(relative) {
    const parts = relative.split("/");
    return parts.length === 4 && parts[0] === "sounds" && parts[1].toLowerCase() === "export" && SFX_PACKS.includes(parts[2]);
}

function countBy(items, key) {
    const result = {};
    items.forEach((item) => { result[item[key]] = (result[item[key]] || 0) + 1; });
    return result;
}

function expectCounts(actual, expected, label) {
    expect(JSON.stringify(sortedClone(actual)) === JSON.stringify(sortedClone(expected)), label + " drifted: expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
}

function buildInventory(root) {
    root = fs.realpathSync.native(root || ROOT);
    assertEolPolicies(root);
    const format = objectFormat(root);
    const sourceEvidence = [
        sourceDescriptor(root, SOURCE_PATHS.bgmRegistration, "bgm_registration", format, "tracked"),
        sourceDescriptor(root, SOURCE_PATHS.configEolPolicy, "config_eol_policy", format, "tracked"),
        sourceDescriptor(root, SOURCE_PATHS.latentSfxDefinition, "latent_sfx_definition", format, "tracked"),
        sourceDescriptor(root, SOURCE_PATHS.latentSfxItem, "latent_sfx_item", format, "tracked"),
        sourceDescriptor(root, SOURCE_PATHS.musicCatalog, "music_catalog_discovery", format, "tracked"),
        sourceDescriptor(root, SOURCE_PATHS.preloadObservation, "sfx_preload_runtime_observation", format, "tracked"),
        sourceDescriptor(root, SOURCE_PATHS.recoveryXfl, "recovery_xfl_library", format, "ignored_source"),
        sourceDescriptor(root, SOURCE_PATHS.sfxPreload, "sfx_preload_discovery", format, "tracked"),
        sourceDescriptor(root, SOURCE_PATHS.toolsEolPolicy, "tools_eol_policy", format, "tracked")
    ].sort((left, right) => compareText(left.role + ":" + left.path, right.role + ":" + right.path));
    const sources = Object.fromEntries(sourceEvidence.map((entry) => [entry.role, entry]));
    const registrationsText = canonicalTextBytes(readBoundFile(root, SOURCE_PATHS.bgmRegistration, "BGM registrations"), SOURCE_PATHS.bgmRegistration, true, false).toString("utf8");
    const registrations = parseBgmRegistrations(registrationsText);
    const latentDefinitionText = canonicalTextBytes(readBoundFile(root, SOURCE_PATHS.latentSfxDefinition, "latent SFX definition"), SOURCE_PATHS.latentSfxDefinition, true, false).toString("utf8");
    const latentItemText = canonicalTextBytes(readBoundFile(root, SOURCE_PATHS.latentSfxItem, "latent SFX item"), SOURCE_PATHS.latentSfxItem, true, false).toString("utf8");
    expect(latentDefinitionText.includes('ref.sniperSound = param.sound2 || "apwersound.wav";'), "latent SFX default assignment drifted");
    expect(/<sound2>\s*apwersound\.wav\s*<\/sound2>/.test(latentItemText), "latent SFX item reference drifted");
    const recoveryText = canonicalTextBytes(readBoundFile(root, SOURCE_PATHS.recoveryXfl, "recovery XFL source"), SOURCE_PATHS.recoveryXfl, true, false).toString("utf8");
    const recoveryItems = parseRecoveryItems(recoveryText);
    const assets = inventoryAudioPaths(root).map((entry) => assetDescriptor(root, entry.path, entry.repositoryState, format));
    const assetByFoldedPath = new Map(assets.map((asset) => [asset.path.toLowerCase(), asset]));
    const activeBySha = new Map();

    assets.forEach((asset) => {
        if (isCatalogPhysical(asset.path)) {
            const registration = registrations.get(asset.path.toLowerCase());
            if (registration) {
                asset.discoveryClass = "catalog_registered";
                asset.nextAction = "retain_and_qualify_tracked_asset";
                asset.owner = "audio_catalog_maintainers";
                asset.reason = "explicit_bgm_list_registration_resolves_to_physical_asset";
                asset.referenceEvidence = registration.titles.map((title) => evidence(
                    "bgm_registration",
                    sources.bgm_registration,
                    "title=" + title + ";url=" + registration.url
                ));
            } else {
                asset.discoveryClass = "catalog_discovered";
                asset.nextAction = "review_registration_then_retain_and_qualify_tracked_asset";
                asset.owner = "audio_catalog_maintainers";
                asset.reason = "current_music_catalog_filesystem_rule_discovers_unregistered_asset";
                asset.referenceEvidence = [evidence(
                    "music_catalog_discovery_rule",
                    sources.music_catalog_discovery,
                    "ScanFilesystem direct sounds child: " + asset.path
                )];
            }
        } else if (isPreloadSfx(asset.path)) {
            asset.discoveryClass = "sfx_preload";
            asset.nextAction = "retain_and_qualify_tracked_asset";
            asset.owner = "audio_sfx_maintainers";
            asset.reason = "current_audio_engine_preload_rule_scans_this_direct_pack_asset";
            asset.referenceEvidence = [evidence(
                "sfx_preload_discovery_rule",
                sources.sfx_preload_discovery,
                "SFX_PACK_ORDER/Directory.GetFiles direct asset: " + asset.path
            )];
        } else {
            asset.discoveryClass = "outside_both";
        }
        if (asset.discoveryClass !== "outside_both") {
            if (!activeBySha.has(asset.sha256)) activeBySha.set(asset.sha256, []);
            activeBySha.get(asset.sha256).push(asset);
        }
    });
    activeBySha.forEach((entries) => entries.sort((left, right) => compareText(left.path, right.path)));

    assets.filter((asset) => asset.discoveryClass === "outside_both").forEach((asset) => {
        if (asset.path.startsWith(RECOVERY_PREFIX)) {
            const fileName = path.posix.basename(asset.path);
            const item = recoveryItems.get(fileName.toLowerCase());
            expect(item && item.href === fileName, "recovery library asset lacks exact DOMSoundItem href: " + asset.path);
            asset.outsideClassification = "source_only";
            asset.nextAction = "retain_as_ignored_xfl_source_excluded_from_H2_complete_git_inventory";
            asset.owner = "flash_audio_maintainers";
            asset.reason = "xfl_dom_sound_item_references_this_library_source_asset";
            asset.referenceEvidence = [evidence(
                "xfl_library_href",
                sources.recovery_xfl_library,
                "DOMSoundItem name=" + (item.name || "") + ";href=" + item.href + ";linkageIdentifier=" + (item.linkageIdentifier || "")
            )];
            return;
        }
        expect(asset.path.startsWith("music/"), "unexpected asset outside both discovery paths: " + asset.path);
        const activeDuplicates = activeBySha.get(asset.sha256) || [];
        asset.outsideClassification = "owned_exception";
        asset.nextAction = "human_owner_must_classify_runtime_reachable_source_only_or_obsolete_before_removal";
        asset.owner = "audio_maintainers";
        const outsideEvidence = [
            evidence("outside_discovery_policy", sources.music_catalog_discovery, "music root is outside MusicCatalog sounds/* direct-file scan: " + asset.path),
            evidence("outside_discovery_policy", sources.sfx_preload_discovery, "music root is outside fixed sounds/export preload packs: " + asset.path)
        ];
        if (activeDuplicates.length > 0) {
            asset.reason = "outside_native_discovery_byte_identical_active_copy_but_runtime_reachability_not_proven";
            asset.referenceEvidence = activeDuplicates.map((duplicate) => ({
                kind: "byte_identical_active_asset",
                locator: "identical_sha256=" + asset.sha256,
                sourcePath: duplicate.path,
                sourceSha256: duplicate.sha256
            })).concat(outsideEvidence);
        } else {
            asset.reason = "outside_native_discovery_without_positive_runtime_or_source_classification_evidence_human_owner_required";
            asset.referenceEvidence = outsideEvidence;
        }
    });

    assets.forEach((asset) => {
        expect(asset.nextAction && asset.owner && asset.reason && Array.isArray(asset.referenceEvidence) && asset.referenceEvidence.length > 0, "asset ownership/evidence incomplete: " + asset.path);
    });

    const registered = assets.filter((asset) => asset.discoveryClass === "catalog_registered").length;
    const discovered = assets.filter((asset) => asset.discoveryClass === "catalog_discovered").length;
    const preload = assets.filter((asset) => asset.discoveryClass === "sfx_preload").length;
    const outsideAssets = assets.filter((asset) => asset.discoveryClass === "outside_both");
    const outsideCounts = countBy(outsideAssets, "outsideClassification");
    expect(registered === EXPECTED.catalogRegistered, "registered physical BGM count drifted: " + registered);
    expect(discovered === EXPECTED.catalogDiscovered, "auto-discovered physical BGM count drifted: " + discovered);
    expect(preload === EXPECTED.preloadSfx, "preload SFX count drifted: " + preload);
    expect(outsideAssets.length === EXPECTED.outside.total, "outside-both count drifted: " + outsideAssets.length);
    expect((outsideCounts.source_only || 0) === EXPECTED.outside.sourceOnly && (outsideCounts.obsolete || 0) === EXPECTED.outside.obsolete && (outsideCounts.owned_exception || 0) === EXPECTED.outside.ownedException && (outsideCounts.runtime_reachable || 0) === EXPECTED.outside.runtimeReachable, "outside classification counts drifted: " + JSON.stringify(outsideCounts));
    expect(outsideAssets.filter((asset) => asset.path.startsWith("music/")).length === EXPECTED.outside.musicRoot, "music-root outside count drifted");
    expect(outsideAssets.filter((asset) => asset.path.startsWith(RECOVERY_PREFIX)).length === EXPECTED.outside.soundsRecoveryLibrary, "recovery-library outside count drifted");
    expectCounts(countBy(assets, "extension"), EXPECTED.extension, "extension counts");
    expectCounts(countBy(assets, "container"), EXPECTED.container, "container counts");
    expectCounts(countBy(assets, "codec"), EXPECTED.codec, "codec counts");
    expectCounts(countBy(assets, "repositoryState"), { ignored_source: 32, tracked: 795 }, "repository-state counts");

    const missingRegisteredReferences = [];
    registrations.forEach((registration, key) => {
        if (assetByFoldedPath.has(key)) return;
        missingRegisteredReferences.push({
            nextAction: "retain_disabled_missing_diagnostic_until_owner_restores_asset_or_marks_registration_obsolete",
            owner: "audio_catalog_maintainers",
            path: registration.url,
            reason: "registered_bgm_url_has_no_physical_asset",
            referenceEvidence: registration.titles.map((title) => evidence("bgm_registration", sources.bgm_registration, "title=" + title + ";url=" + registration.url)),
            titles: registration.titles.slice()
        });
    });
    missingRegisteredReferences.sort((left, right) => compareText(left.path, right.path));
    expect(missingRegisteredReferences.length === EXPECTED.missingRegisteredReferences, "missing registered reference count drifted: " + missingRegisteredReferences.length);

    const missingLatentReferences = [{
        linkageId: "apwersound.wav",
        nextAction: "retain_owned_latent_diagnostic_until_owner_proves_consumer_or_removes_both_assignments",
        owner: "audio_sfx_maintainers",
        reason: "item_and_as2_default_assign_a_linkage_id_with_no_physical_inventory_asset_and_no_proven_consumer",
        referenceEvidence: [
            evidence("latent_sfx_item_reference", sources.latent_sfx_item, "sound2=apwersound.wav"),
            evidence("latent_sfx_default_assignment", sources.latent_sfx_definition, "ref.sniperSound default=apwersound.wav")
        ]
    }];
    expect(!assets.some((asset) => path.posix.basename(asset.path).toLowerCase() === "apwersound.wav"), "latent SFX unexpectedly resolves to a physical asset; classification requires review");
    expect(missingLatentReferences.length === EXPECTED.missingLatentReferences, "missing latent reference count drifted: " + missingLatentReferences.length);

    const producerBytes = canonicalTextBytes(readBoundFile(root, PRODUCER_REL, "inventory producer"), PRODUCER_REL);
    const manifest = {
        assetClosureSha256: sha256(canonicalBytes(assets)),
        assets,
        inventoryExtensions: INVENTORY_EXTENSIONS.slice(),
        inventoryRoots: ["sounds", "music"],
        missingLatentReferences,
        missingRegisteredReferences,
        producer: {
            blobOid: gitBlobOid(producerBytes, format),
            bytes: producerBytes.length,
            path: PRODUCER_REL,
            sha256: sha256(producerBytes)
        },
        qualificationScope: {
            h2CompleteGitInventoryTotal: 795,
            ignoredSourceOnlyExcluded: 32,
            outsideDiscoveryExceptionsAreDecodeOrSignalWaivers: false,
            physicalCorpusTotal: assets.length,
            rule: "only_repositoryState_tracked_enters_H2_complete_git_inventory_and_decode_to_EOF",
            trackedShippedAssetClosureSha256: sha256(canonicalBytes(assets.filter((asset) => asset.repositoryState === "tracked")))
        },
        schema: "cf7.audio-v2.shipped-audio-assets.v1",
        sourceEvidence,
        summary: {
            byCodec: EXPECTED.codec,
            byContainer: EXPECTED.container,
            byExtension: EXPECTED.extension,
            byRepositoryState: { ignoredSource: 32, tracked: 795 },
            catalogDiscovered: discovered,
            catalogRegistered: registered,
            missingLatentReferences: missingLatentReferences.length,
            missingRegisteredReferences: missingRegisteredReferences.length,
            outsideBothDiscoveryPaths: {
                byClassification: {
                    obsolete: outsideCounts.obsolete || 0,
                    ownedException: outsideCounts.owned_exception || 0,
                    runtimeReachable: outsideCounts.runtime_reachable || 0,
                    sourceOnly: outsideCounts.source_only || 0
                },
                musicRoot: EXPECTED.outside.musicRoot,
                soundsRecoveryLibrary: EXPECTED.outside.soundsRecoveryLibrary,
                total: outsideAssets.length
            },
            preloadSfx: preload,
            totalPhysicalAudio: assets.length
        }
    };
    return manifest;
}

function checkedManifestPath(root) {
    return path.join(root || ROOT, OUTPUT_REL.split("/").join(path.sep));
}

function checkManifest(file, root) {
    root = root || ROOT;
    file = file || checkedManifestPath(root);
    const expected = canonicalBytes(buildInventory(root));
    const actual = fs.readFileSync(file);
    expect(actual.equals(expected), OUTPUT_REL + " is stale, noncanonical, or does not bind current tracked bytes; run generator with --write");
    return { bytes: actual.length, sha256: sha256(actual) };
}

function writeManifest(root) {
    root = root || ROOT;
    const destination = checkedManifestPath(root);
    const parent = path.dirname(destination);
    expect(fs.existsSync(parent) && fs.lstatSync(parent).isDirectory(), "inventory output directory is missing");
    const bytes = canonicalBytes(buildInventory(root));
    const temporary = destination + ".tmp-" + process.pid;
    try {
        fs.writeFileSync(temporary, bytes, { flag: "wx" });
        fs.renameSync(temporary, destination);
    } finally {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
    }
    return { bytes: bytes.length, sha256: sha256(bytes) };
}

function main(argv) {
    expect(argv.length === 1 && ["--check", "--print", "--write"].includes(argv[0]), "usage: generate-shipped-audio-assets.js --check|--print|--write");
    if (argv[0] === "--print") {
        process.stdout.write(canonicalBytes(buildInventory(ROOT)));
        return;
    }
    const result = argv[0] === "--write" ? writeManifest(ROOT) : checkManifest(null, ROOT);
    process.stdout.write("shipped audio inventory " + (argv[0] === "--write" ? "written" : "verified") + "; bytes=" + result.bytes + "; sha256=" + result.sha256 + "\n");
}

if (require.main === module) {
    try {
        main(process.argv.slice(2));
    } catch (error) {
        process.stderr.write("shipped audio inventory failed: " + (error && error.message ? error.message : String(error)).replace(/[\r\n]+/g, " ") + "\n");
        process.exitCode = 1;
    }
}

module.exports = Object.freeze({
    EXPECTED,
    INVENTORY_EXTENSIONS,
    OUTPUT_REL,
    ROOT,
    InventoryError,
    buildInventory,
    canonicalBytes,
    checkManifest,
    gitBlobOid,
    main,
    sha256,
    sniffAudio,
    sortedClone,
    writeManifest
});
