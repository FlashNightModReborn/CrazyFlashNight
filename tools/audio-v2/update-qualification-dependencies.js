#!/usr/bin/env node
"use strict";

// Mechanical maintainer for the source-reviewed Audio v2 qualification replay
// closure. The runner never executes this generator; H2 consumes only the
// canonical, byte-addressed manifest it writes.

const cp = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..", "..");
const output = "config/audio-v2/qualification-runner-dependencies.v1.json";
const FIXED_DEPENDENCIES = Object.freeze([
    "automation/start.ps1",
    "global.json",
    "launcher/CRAZYFLASHER7MercenaryEmpire.csproj",
    "launcher/Directory.Packages.props",
    "launcher/src/AssemblyInfo.cs",
    "launcher/THIRD-PARTY-NOTICES.txt",
    "launcher/app.ico",
    "launcher/app.manifest",
    "launcher/contracts/panel-contracts.v2.json",
    "launcher/native/audio_backend_policy.c",
    "launcher/native/audio_backend_policy.h",
    "launcher/native/audio_bridge_v2.h",
    "launcher/native/miniaudio_bridge.c",
    "launcher/native/tests/audio_backend_policy_contract.c",
    "launcher/native/tests/audio_bridge_v2_runtime_contract.c",
    "launcher/packages.lock.json",
    "launcher/tests/Launcher.Tests.csproj",
    "launcher/tests/xunit.runner.json",
    "scripts/asLoader.swf",
    "scripts/run-audio-v2-tests.ps1",
    "scripts/test-runners/audio-v2/TestLoader.as.template",
    "scripts/展现/UI交互/UI交互_lsy_UI管理.as",
    "scripts/类定义/org/flashNight/arki/audio/AudioBridge.as",
    "scripts/类定义/org/flashNight/arki/audio/AudioQualificationStimulus.as",
    "scripts/类定义/org/flashNight/arki/audio/SoundEffectManager.as",
    "scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeV2Test.as",
    "scripts/类定义/org/flashNight/neur/Server/ServerManager.as",
    "tools/audio-v2/assemble-a6-evidence.js",
    "tools/audio-v2/assemble-a6-evidence.test.js",
    "tools/audio-v2/capture-endpoint.ps1",
    "tools/audio-v2/capture-endpoint.tests.ps1",
    "tools/audio-v2/list-playback-endpoints.ps1",
    "tools/audio-v2/list-playback-endpoints.tests.ps1",
    "tools/audio-v2/materialize-qualification-fixtures.js",
    "tools/audio-v2/materialize-qualification-fixtures.test.js",
    "tools/audio-v2/qualification-decoder-fixtures.v1.json",
    "tools/audio-v2/qualification-observer-client.ps1",
    "tools/audio-v2/qualification-observer-client.tests.ps1",
    "tools/audio-v2/qualification-observer.js",
    "tools/audio-v2/qualification-observer.test.js",
    "tools/audio-v2/qualification-offline-probe.c",
    "tools/audio-v2/qualification-operator.js",
    "tools/audio-v2/qualification-operator.test.js",
    "tools/audio-v2/qualification-runner.js",
    "tools/audio-v2/qualification-runner.test.js",
    "tools/audio-v2/qualification-stimulus-client.ps1",
    "tools/audio-v2/qualification-stimulus-client.tests.ps1",
    "tools/audio-v2/update-qualification-dependencies.js",
    "tools/audio-v2/update-qualification-dependencies.test.js",
    "tools/audio-v2/write-qualification-toolchain.ps1",
    "tools/audio-v2/write-qualification-toolchain.tests.ps1"
]);

const DEFAULT_WALKS = Object.freeze([
    Object.freeze({
        relative: "launcher",
        select: (relative) => relative.endsWith(".cs")
    }),
    Object.freeze({
        relative: "launcher/src/Guardian/Hud/PlayerInfo/Assets",
        select: (relative) => /\.(json|svg)$/.test(relative)
    }),
    Object.freeze({
        relative: "launcher/tests/Fixtures",
        select: (relative) => relative.endsWith(".json")
    })
]);

function expect(condition, message) {
    if (!condition) throw new Error(message);
}

function safeRelative(relative) {
    expect(typeof relative === "string" && relative.length > 0,
        "qualification dependency path is empty");
    expect(relative === relative.replace(/\\/g, "/") &&
        !path.posix.isAbsolute(relative) &&
        !relative.split("/").some((part) => !part || part === "." || part === ".."),
    "unsafe qualification dependency path: " + relative);
    return relative;
}

function walk(projectRoot, relative, select) {
    const directory = path.join(projectRoot, ...safeRelative(relative).split("/"));
    const result = [];
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
        if (["bin", "obj", ".vs", "node_modules"].includes(entry.name)) return;
        if (["native", "packages", "scripts"].includes(entry.name) && relative === "launcher") return;
        const child = relative + "/" + entry.name;
        if (entry.isDirectory()) result.push(...walk(projectRoot, child, select));
        else if (entry.isFile() && select(child)) result.push(child);
    });
    return result;
}

function sha256(bytes) {
    return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
}

function gitBlobOid(bytes, oidLength) {
    const algorithm = oidLength === 40 ? "sha1" : oidLength === 64 ? "sha256" : null;
    expect(algorithm, "unsupported Git object id length: " + oidLength);
    return crypto.createHash(algorithm)
        .update(Buffer.from("blob " + bytes.length + "\0", "utf8"))
        .update(bytes)
        .digest("hex");
}

function canonical(value) {
    if (Array.isArray(value)) return value.map(canonical);
    if (value && typeof value === "object") {
        const result = {};
        Object.keys(value).sort().forEach((key) => { result[key] = canonical(value[key]); });
        return result;
    }
    return value;
}

function canonicalBytes(value) {
    return Buffer.from(JSON.stringify(canonical(value), null, 2) + "\n", "utf8");
}

function normalizeCrlf(bytes) {
    let pairs = 0;
    for (let index = 0; index + 1 < bytes.length; index++) {
        if (bytes[index] === 13 && bytes[index + 1] === 10) {
            pairs++;
            index++;
        }
    }
    if (pairs === 0) return bytes;
    const result = Buffer.allocUnsafe(bytes.length - pairs);
    let outputIndex = 0;
    for (let index = 0; index < bytes.length; index++) {
        if (bytes[index] === 13 && index + 1 < bytes.length && bytes[index + 1] === 10) {
            result[outputIndex++] = 10;
            index++;
        } else {
            result[outputIndex++] = bytes[index];
        }
    }
    return result;
}

function gitFilteredOid(projectRoot, relative, rawBytes) {
    const executed = cp.spawnSync(
        "git",
        ["hash-object", "--path=" + relative, "--stdin"],
        {
            cwd: projectRoot,
            encoding: null,
            input: rawBytes,
            maxBuffer: 1024 * 1024,
            windowsHide: true
        });
    expect(!executed.error && executed.status === 0,
        "git clean-filter hash failed for " + relative + ": " +
        String(executed.stderr || executed.error || "unknown error").trim());
    const oid = executed.stdout.toString("ascii").trim();
    expect(/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(oid),
        "git clean-filter hash returned an invalid object id for " + relative);
    return oid;
}

// `git hash-object --path --stdin` applies the repository's exact clean filters
// without `-w`, so it does not add loose objects. Git does not expose those
// filtered bytes on stdout. The repository only permits identity or CRLF->LF
// clean transforms for this closure; select the byte candidate whose independently
// recomputed blob id equals Git's oracle and fail closed on any other filter.
function gitCleanBlob(projectRoot, relative) {
    const safe = safeRelative(relative);
    const file = path.join(projectRoot, ...safe.split("/"));
    expect(fs.existsSync(file) && fs.lstatSync(file).isFile(),
        "missing qualification dependency: " + safe);
    const rawBytes = fs.readFileSync(file);
    expect(rawBytes.length > 0, "empty qualification dependency: " + safe);
    const blobOid = gitFilteredOid(projectRoot, safe, rawBytes);
    let bytes = rawBytes;
    if (gitBlobOid(bytes, blobOid.length) !== blobOid) {
        bytes = normalizeCrlf(rawBytes);
        expect(bytes !== rawBytes && gitBlobOid(bytes, blobOid.length) === blobOid,
            "unsupported Git clean filter for qualification dependency: " + safe);
    }
    return { blobOid, bytes };
}

function dependencyPaths(projectRoot, fixed, walks) {
    const exact = fixed || FIXED_DEPENDENCIES;
    const duplicates = exact.filter((relative, index) => exact.indexOf(relative) !== index);
    expect(duplicates.length === 0,
        "duplicate fixed qualification dependency: " + (duplicates[0] || "unknown"));
    const selected = new Set(exact.map(safeRelative));
    (walks || DEFAULT_WALKS).forEach((spec) => {
        walk(projectRoot, spec.relative, spec.select).forEach((relative) => selected.add(relative));
    });
    return Array.from(selected).sort();
}

function buildManifest(projectRoot, fixed, walks) {
    const dependencies = dependencyPaths(projectRoot, fixed, walks).map((relative) => {
        const binding = gitCleanBlob(projectRoot, relative);
        return {
            blobOid: binding.blobOid,
            bytes: binding.bytes.length,
            path: relative,
            sha256: sha256(binding.bytes)
        };
    });
    return {
        closureSha256: sha256(canonicalBytes(dependencies)),
        dependencies,
        runnerPath: "tools/audio-v2/qualification-runner.js",
        schema: "cf7.audio-v2.qualification-runner-dependencies.v1"
    };
}

function parseArgs(argv) {
    if (argv.length === 0) return { check: false };
    if (argv.length === 1 && argv[0] === "--check") return { check: true };
    throw new Error("usage: update-qualification-dependencies.js [--check]");
}

function update(projectRoot, outputRelative, options) {
    const manifest = buildManifest(projectRoot,
        options && options.fixed, options && options.walks);
    const bytes = canonicalBytes(manifest);
    const destination = path.join(projectRoot, ...safeRelative(outputRelative).split("/"));
    if (options && options.check) {
        expect(fs.existsSync(destination) && fs.lstatSync(destination).isFile(),
            "qualification dependency manifest is missing: " + outputRelative);
        const current = fs.readFileSync(destination);
        expect(current.equals(bytes),
            "qualification dependency manifest is stale; run update-qualification-dependencies.js");
    } else {
        fs.writeFileSync(destination, bytes);
    }
    return { bytes, manifest };
}

function main(argv) {
    const options = parseArgs(argv);
    const result = update(root, output, options);
    process.stdout.write((options.check ? "checked " : "updated ") + output +
        " dependencies=" + result.manifest.dependencies.length +
        " closure=" + result.manifest.closureSha256 + "\n");
}

if (require.main === module) {
    try { main(process.argv.slice(2)); }
    catch (error) {
        process.stderr.write("audio-v2 dependency update failed: " +
            String(error && error.message || error).replace(/[\r\n]+/g, " ") + "\n");
        process.exitCode = 1;
    }
}

module.exports = Object.freeze({
    DEFAULT_WALKS,
    FIXED_DEPENDENCIES,
    buildManifest,
    canonicalBytes,
    dependencyPaths,
    gitBlobOid,
    gitCleanBlob,
    main,
    normalizeCrlf,
    parseArgs,
    sha256,
    update
});
