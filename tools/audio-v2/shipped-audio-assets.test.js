#!/usr/bin/env node
"use strict";

const assert = require("assert");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const inventory = require("./generate-shipped-audio-assets.js");
const manifestPath = path.join(inventory.ROOT, inventory.OUTPUT_REL.split("/").join(path.sep));
const schemaPath = path.join(inventory.ROOT, "docs", "contracts", "audio-v2", "shipped-audio-assets.schema.v1.json");
const generated = inventory.buildInventory(inventory.ROOT);
let passed = 0;

function test(name, body) {
    body();
    passed++;
    process.stdout.write("ok " + passed + " - " + name + "\n");
}

function countBy(items, key) {
    const result = {};
    items.forEach((item) => { result[item[key]] = (result[item[key]] || 0) + 1; });
    return result;
}

test("schema and checked-in manifest use canonical LF JSON", () => {
    const schemaBytes = fs.readFileSync(schemaPath);
    const schema = JSON.parse(schemaBytes.toString("utf8"));
    assert.ok(schemaBytes.equals(inventory.canonicalBytes(schema)));
    assert.strictEqual(schema.$id, "cf7.audio-v2.shipped-audio-assets.schema.v1");
    assert.strictEqual(schema.properties.assets.minItems, 827);
    assert.strictEqual(schema.properties.assets.maxItems, 827);
    assert.strictEqual(schema.properties.qualificationScope.properties.h2CompleteGitInventoryTotal.const, 795);
    const manifestBytes = fs.readFileSync(manifestPath);
    const manifest = JSON.parse(manifestBytes.toString("utf8"));
    assert.ok(manifestBytes.equals(inventory.canonicalBytes(manifest)));
    assert.ok(manifestBytes.equals(inventory.canonicalBytes(generated)));
});

test("physical denominator closes exactly as 827 equals 795 tracked plus 32 ignored source-only", () => {
    assert.strictEqual(generated.assets.length, 827);
    assert.deepStrictEqual(countBy(generated.assets, "repositoryState"), { ignored_source: 32, tracked: 795 });
    assert.strictEqual(generated.qualificationScope.h2CompleteGitInventoryTotal, 795);
    assert.strictEqual(generated.qualificationScope.ignoredSourceOnlyExcluded, 32);
    assert.strictEqual(generated.qualificationScope.outsideDiscoveryExceptionsAreDecodeOrSignalWaivers, false);
    assert.strictEqual(generated.qualificationScope.physicalCorpusTotal, 827);
    assert.match(generated.qualificationScope.rule, /^only_repositoryState_tracked_enters_H2_/);
    assert.strictEqual(
        generated.qualificationScope.trackedShippedAssetClosureSha256,
        inventory.sha256(inventory.canonicalBytes(generated.assets.filter((asset) => asset.repositoryState === "tracked")))
    );
});

test("all 827 assets have exact unique path and byte identity", () => {
    const paths = generated.assets.map((asset) => asset.path);
    assert.deepStrictEqual(paths, paths.slice().sort());
    assert.strictEqual(new Set(paths.map((entry) => entry.toLowerCase())).size, 827);
    generated.assets.forEach((asset) => {
        const bytes = fs.readFileSync(path.join(inventory.ROOT, asset.path.split("/").join(path.sep)));
        assert.strictEqual(asset.bytes, bytes.length, asset.path);
        assert.strictEqual(asset.sha256, inventory.sha256(bytes), asset.path);
        assert.strictEqual(asset.blobOid, inventory.gitBlobOid(bytes, "sha1"), asset.path);
        assert.ok(asset.nextAction && asset.owner && asset.reason && asset.referenceEvidence.length > 0, asset.path);
    });
    assert.strictEqual(generated.assetClosureSha256, inventory.sha256(inventory.canonicalBytes(generated.assets)));
});

test("registered discovered preload and outside discovery sets are disjoint and exact", () => {
    assert.deepStrictEqual(countBy(generated.assets, "discoveryClass"), {
        catalog_discovered: 4,
        catalog_registered: 86,
        outside_both: 61,
        sfx_preload: 676
    });
    const discovered = generated.assets.filter((asset) => asset.discoveryClass === "catalog_discovered").map((asset) => asset.path);
    assert.deepStrictEqual(discovered, [
        "sounds/PTXOA馆长/darkbass.mp3",
        "sounds/PTXOA馆长/gnf.mp3",
        "sounds/PTXOA馆长/低暗阴沉.mp3",
        "sounds/劳埃德music/Rose at eclipse.mp3"
    ]);
    generated.assets.filter((asset) => asset.discoveryClass !== "outside_both").forEach((asset) => assert.strictEqual(asset.outsideClassification, null));
});

test("outside classifications preserve uncertainty and XFL source ownership", () => {
    const outside = generated.assets.filter((asset) => asset.discoveryClass === "outside_both");
    assert.deepStrictEqual(countBy(outside, "outsideClassification"), { owned_exception: 29, source_only: 32 });
    const sourceOnly = outside.filter((asset) => asset.outsideClassification === "source_only");
    assert.ok(sourceOnly.every((asset) => asset.repositoryState === "ignored_source" && asset.path.startsWith("sounds/恢复_音效-武器/LIBRARY/")));
    assert.ok(sourceOnly.every((asset) => asset.referenceEvidence.length === 1 && asset.referenceEvidence[0].kind === "xfl_library_href"));
    const owned = outside.filter((asset) => asset.outsideClassification === "owned_exception");
    assert.strictEqual(owned.length, 29);
    assert.ok(owned.every((asset) => asset.repositoryState === "tracked" && asset.owner === "audio_maintainers"));
    assert.ok(owned.every((asset) => asset.nextAction === "human_owner_must_classify_runtime_reachable_source_only_or_obsolete_before_removal"));
    assert.strictEqual(owned.filter((asset) => asset.referenceEvidence.some((entry) => entry.kind === "byte_identical_active_asset")).length, 3);
});

test("content sniffing records codec/container reality rather than filename extension", () => {
    assert.deepStrictEqual(generated.summary.byExtension, { ".m4a": 11, ".mp3": 215, ".wav": 599, ".waz": 2 });
    assert.deepStrictEqual(generated.summary.byContainer, { iso_bmff: 11, mpeg_audio: 756, riff_wave: 60 });
    assert.deepStrictEqual(generated.summary.byCodec, { aac_lc_or_he_aac: 11, mpeg_audio_layer_iii: 756, pcm_s16le: 60 });
    const canonicalMp4 = generated.assets.filter((asset) => asset.extension === ".m4a" && asset.container === "iso_bmff");
    assert.strictEqual(canonicalMp4.length, 11);
    const disguisedMp4 = generated.assets.filter((asset) => asset.extension === ".wav" && asset.container === "iso_bmff");
    assert.strictEqual(disguisedMp4.length, 0);
    const disguisedMp3 = generated.assets.filter((asset) => asset.extension === ".wav" && asset.container === "mpeg_audio");
    assert.strictEqual(disguisedMp3.length, 539);
    const waz = generated.assets.filter((asset) => asset.extension === ".waz");
    assert.ok(waz.every((asset) => asset.codec === "mpeg_audio_layer_iii" && asset.container === "mpeg_audio"));
});

test("missing registered BGM is explicit and not counted as a physical asset", () => {
    assert.strictEqual(generated.missingRegisteredReferences.length, 1);
    assert.strictEqual(generated.missingRegisteredReferences[0].path, "sounds/劳埃德music/Zenitsu Theme V3 (Godlike Speed).mp3");
    assert.strictEqual(generated.missingRegisteredReferences[0].reason, "registered_bgm_url_has_no_physical_asset");
    assert.strictEqual(generated.missingRegisteredReferences[0].nextAction, "retain_disabled_missing_diagnostic_until_owner_restores_asset_or_marks_registration_obsolete");
    assert.ok(!generated.assets.some((asset) => asset.path === generated.missingRegisteredReferences[0].path));
});

test("latent SFX reference is explicit and cannot be hidden by a silent placeholder", () => {
    assert.strictEqual(generated.missingLatentReferences.length, 1);
    const latent = generated.missingLatentReferences[0];
    assert.strictEqual(latent.linkageId, "apwersound.wav");
    assert.strictEqual(latent.owner, "audio_sfx_maintainers");
    assert.strictEqual(latent.nextAction, "retain_owned_latent_diagnostic_until_owner_proves_consumer_or_removes_both_assignments");
    assert.match(latent.reason, /no_physical_inventory_asset_and_no_proven_consumer/);
    assert.deepStrictEqual(
        latent.referenceEvidence.map((entry) => entry.kind),
        ["latent_sfx_item_reference", "latent_sfx_default_assignment"]
    );
    assert.ok(!generated.assets.some((asset) => path.posix.basename(asset.path).toLowerCase() === latent.linkageId));
});

test("source evidence binds discovery policy observation and nested LF policies", () => {
    const roles = generated.sourceEvidence.map((entry) => entry.role);
    assert.deepStrictEqual(roles, roles.slice().sort());
    assert.deepStrictEqual(roles, [
        "bgm_registration",
        "config_eol_policy",
        "latent_sfx_definition",
        "latent_sfx_item",
        "music_catalog_discovery",
        "recovery_xfl_library",
        "sfx_preload_discovery",
        "sfx_preload_runtime_observation",
        "tools_eol_policy"
    ]);
    const observation = generated.sourceEvidence.find((entry) => entry.role === "sfx_preload_runtime_observation");
    assert.strictEqual(observation.path, "docs/evidence/audio-v2/research-ready-preload-observation.json");
    const recovery = generated.sourceEvidence.find((entry) => entry.role === "recovery_xfl_library");
    assert.strictEqual(recovery.repositoryState, "ignored_source");
    assert.ok(generated.sourceEvidence.filter((entry) => entry !== recovery).every((entry) => entry.repositoryState === "tracked"));
});

test("unknown and tag-only byte streams fail closed instead of receiving a codec", () => {
    assert.throws(() => inventory.sniffAudio(Buffer.from("not audio", "utf8"), "fixture.bin"), /unrecognized audio content/);
    const tagOnly = Buffer.concat([Buffer.from("49443304000000000000", "hex"), Buffer.alloc(64)]);
    assert.throws(() => inventory.sniffAudio(tagOnly, "tag-only.mp3"), /unrecognized audio content/);
    const loneFrameHeader = Buffer.from([0xFF, 0xFB, 0x90, 0x64]);
    const loneFrame = Buffer.concat([loneFrameHeader, Buffer.alloc(413)]);
    assert.throws(() => inventory.sniffAudio(loneFrame, "single-frame-sync.mp3"), /unrecognized audio content/);
});

test("checker rejects a noncanonical or tampered inventory", () => {
    const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-inventory-test-"));
    const temporaryManifest = path.join(temporaryRoot, "tampered.json");
    try {
        fs.writeFileSync(temporaryManifest, Buffer.concat([inventory.canonicalBytes(generated), Buffer.from(" ")]));
        assert.throws(() => inventory.checkManifest(temporaryManifest, inventory.ROOT), /stale, noncanonical/);
    } finally {
        const resolved = path.resolve(temporaryRoot);
        assert.ok(resolved.startsWith(path.resolve(os.tmpdir()) + path.sep));
        fs.rmSync(resolved, { force: true, recursive: true });
    }
});

test("standalone check entrypoint rejects arguments and accepts the exact manifest", () => {
    const checker = path.join(__dirname, "check-shipped-audio-assets.js");
    const accepted = cp.spawnSync(process.execPath, [checker], { cwd: inventory.ROOT, encoding: "utf8", timeout: 60000 });
    assert.strictEqual(accepted.status, 0, accepted.stderr);
    assert.match(accepted.stdout, /inventory check passed/);
    const rejected = cp.spawnSync(process.execPath, [checker, "--bypass"], { cwd: inventory.ROOT, encoding: "utf8", timeout: 60000 });
    assert.strictEqual(rejected.status, 1);
    assert.match(rejected.stderr, /accepts no arguments/);
});

process.stdout.write("shipped-audio-assets tests passed: " + passed + "\n");
