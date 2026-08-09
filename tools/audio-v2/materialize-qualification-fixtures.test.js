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
            codec: discoveryClass === "sfx_preload" ? "pcm_or_ieee_float" : "mpeg_audio_layer_iii",
            discoveryClass,
            path: relative,
            repositoryState: "tracked",
            sha256: subject.sha256(bytes)
        });
    }
    addShipped("sounds/a.mp3", "catalog_registered", Buffer.alloc(1024 * 1024, 1));
    addShipped("sounds/b.mp3", "catalog_registered", Buffer.alloc(1024 * 1024, 2));
    for (let index = 0; index < 6; index++) {
        addShipped("sounds/export/人物/sfx" + index + ".wav", "sfx_preload", Buffer.alloc(32, index + 3));
    }
    fs.writeFileSync(
        path.join(temporaryRoot, "config", "audio-v2", "shipped-audio-assets.v1.json"),
        subject.canonicalBytes({ assets: shippedRows, schema: "cf7.audio-v2.shipped-audio-assets.v1" }));

    test("materializes exact three positive fixtures", () => {
        const result = subject.materializeFixtures(temporaryRoot, runId);
        assert.strictEqual(result.fixtures.length, 3);
        assert.strictEqual(result.sfx.length, 6);
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

    test("rejects existing fixture byte drift", () => {
        const result = subject.materializeFixtures(temporaryRoot, runId);
        const target = path.join(temporaryRoot, ...result.fixtures[0].relativePath.split("/"));
        fs.writeFileSync(target, Buffer.from("drift", "utf8"));
        assert.throws(() => subject.materializeFixtures(temporaryRoot, runId), /bytes drifted/);
    });

    test("rejects noncanonical run id", () => {
        assert.throws(() => subject.materializeFixtures(temporaryRoot, runId.toUpperCase()), /lowercase hex/);
    });
} finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

process.stdout.write("materialize qualification fixtures tests passed: " + passed + "\n");
