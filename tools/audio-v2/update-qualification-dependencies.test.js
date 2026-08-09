#!/usr/bin/env node
"use strict";

const assert = require("assert");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");

const updater = require("./update-qualification-dependencies.js");

function git(root, args, input) {
    const executed = cp.spawnSync("git", args, {
        cwd: root,
        encoding: "utf8",
        input,
        windowsHide: true
    });
    if (executed.error || executed.status !== 0) {
        throw new Error(String(executed.stderr || executed.error || "git failed").trim());
    }
    return executed.stdout.trim();
}

function fixture() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-deps-"));
    git(root, ["init", "--quiet"]);
    git(root, ["config", "core.autocrlf", "true"]);
    fs.writeFileSync(path.join(root, ".gitattributes"), "*.txt text eol=lf\n*.bin text=auto\n", "utf8");
    fs.writeFileSync(path.join(root, "runner.txt"), Buffer.from("first\r\nsecond\r\n", "utf8"));
    fs.writeFileSync(path.join(root, "音频.txt"), Buffer.from("左\r\n右\r\n", "utf8"));
    fs.writeFileSync(path.join(root, "opaque.bin"), Buffer.from([0, 13, 10, 255]));
    return root;
}

function noWalks() { return []; }

test("Git clean-filter bytes, not raw Windows worktree bytes, define descriptors", () => {
    const root = fixture();
    try {
        const raw = fs.readFileSync(path.join(root, "runner.txt"));
        const expectedBytes = Buffer.from("first\nsecond\n", "utf8");
        const expectedOid = git(root,
            ["hash-object", "--path=runner.txt", "--stdin"], raw);
        assert.notEqual(updater.gitBlobOid(raw, expectedOid.length), expectedOid);

        const binding = updater.gitCleanBlob(root, "runner.txt");
        assert.equal(binding.blobOid, expectedOid);
        assert.deepEqual(binding.bytes, expectedBytes);
        assert.equal(updater.gitBlobOid(binding.bytes, expectedOid.length), expectedOid);

        const objectProbe = cp.spawnSync("git", ["cat-file", "-e", expectedOid], {
            cwd: root, encoding: "utf8", windowsHide: true
        });
        assert.notEqual(objectProbe.status, 0,
            "clean-filter hashing must not write a loose Git object");

        const binary = updater.gitCleanBlob(root, "opaque.bin");
        assert.deepEqual(binary.bytes, Buffer.from([0, 13, 10, 255]));

        const unicode = updater.gitCleanBlob(root, "音频.txt");
        assert.deepEqual(unicode.bytes, Buffer.from("左\n右\n", "utf8"));
        assert.equal(updater.gitBlobOid(unicode.bytes, unicode.blobOid.length),
            unicode.blobOid);
    } finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test("manifest generation is canonical and byte-deterministic", () => {
    const root = fixture();
    try {
        const fixed = ["opaque.bin", "runner.txt"];
        const first = updater.buildManifest(root, fixed, noWalks());
        const second = updater.buildManifest(root, fixed, noWalks());
        assert.deepEqual(second, first);
        assert.deepEqual(first.dependencies.map((entry) => entry.path), fixed);
        assert.deepEqual(updater.canonicalBytes(first), updater.canonicalBytes(second));
        assert.equal(first.closureSha256,
            updater.sha256(updater.canonicalBytes(first.dependencies)));
    } finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test("missing and duplicate dependency paths fail closed", () => {
    const root = fixture();
    try {
        assert.throws(() => updater.buildManifest(root, ["missing.txt"], noWalks()),
            /missing qualification dependency/);
        assert.throws(() => updater.buildManifest(root,
            ["runner.txt", "runner.txt"], noWalks()),
        /duplicate fixed qualification dependency/);
        assert.throws(() => updater.buildManifest(root, ["../runner.txt"], noWalks()),
            /unsafe qualification dependency path/);
    } finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test("--check rejects stale or extra rows without rewriting output", () => {
    const root = fixture();
    try {
        const output = "dependencies.json";
        const options = { fixed: ["runner.txt"], walks: noWalks() };
        updater.update(root, output, options);
        assert.doesNotThrow(() => updater.update(root, output,
            Object.assign({ check: true }, options)));

        const destination = path.join(root, output);
        const stale = JSON.parse(fs.readFileSync(destination, "utf8"));
        stale.dependencies.push({
            blobOid: "0".repeat(40), bytes: 1, path: "extra.txt", sha256: "0".repeat(64)
        });
        const staleBytes = updater.canonicalBytes(stale);
        fs.writeFileSync(destination, staleBytes);
        assert.throws(() => updater.update(root, output,
            Object.assign({ check: true }, options)), /manifest is stale/);
        assert.deepEqual(fs.readFileSync(destination), staleBytes,
            "check mode must not repair or rewrite stale bytes");
    } finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test("CLI is closed and fixed replay paths cover the complete qualification chain", () => {
    assert.deepEqual(updater.parseArgs([]), { check: false });
    assert.deepEqual(updater.parseArgs(["--check"]), { check: true });
    assert.throws(() => updater.parseArgs(["--write"]), /usage/);

    const required = [
        "automation/start.ps1",
        "global.json",
        "launcher/Directory.Packages.props",
        "scripts/asLoader.swf",
        "scripts/run-audio-v2-tests.ps1",
        "scripts/test-runners/audio-v2/TestLoader.as.template",
        "scripts/展现/UI交互/UI交互_lsy_UI管理.as",
        "scripts/类定义/org/flashNight/arki/audio/AudioQualificationStimulus.as",
        "tools/audio-v2/assemble-a6-evidence.js",
        "tools/audio-v2/assemble-a6-evidence.test.js",
        "tools/audio-v2/capture-endpoint.ps1",
        "tools/audio-v2/capture-endpoint.tests.ps1",
        "tools/audio-v2/list-playback-endpoints.ps1",
        "tools/audio-v2/list-playback-endpoints.tests.ps1",
        "tools/audio-v2/materialize-qualification-fixtures.js",
        "tools/audio-v2/materialize-qualification-fixtures.test.js",
        "tools/audio-v2/qualification-observer-client.tests.ps1",
        "tools/audio-v2/qualification-observer.test.js",
        "tools/audio-v2/qualification-operator.js",
        "tools/audio-v2/qualification-operator.test.js",
        "tools/audio-v2/qualification-runner.test.js",
        "tools/audio-v2/qualification-stimulus-client.ps1",
        "tools/audio-v2/qualification-stimulus-client.tests.ps1",
        "tools/audio-v2/update-qualification-dependencies.js",
        "tools/audio-v2/update-qualification-dependencies.test.js",
        "tools/audio-v2/write-qualification-toolchain.ps1",
        "tools/audio-v2/write-qualification-toolchain.tests.ps1"
    ];
    required.forEach((relative) => assert.ok(
        updater.FIXED_DEPENDENCIES.includes(relative),
        "fixed qualification closure misses " + relative));
    assert.equal(new Set(updater.FIXED_DEPENDENCIES).size,
        updater.FIXED_DEPENDENCIES.length);
});
