#!/usr/bin/env node
"use strict";

const assert = require("assert");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const runner = require("./qualification-runner.js");
const dependencyGenerator = require("./update-qualification-dependencies.js");
const RUNNER_REL = "tools/audio-v2/qualification-runner.js";
const OBSERVER_REL = "tools/audio-v2/qualification-observer.js";
const DEPENDENCY_REL = "config/audio-v2/qualification-runner-dependencies.v1.json";
const DECODER_FIXTURE_REL = "tools/audio-v2/qualification-decoder-fixtures.v1.json";
const TOOLCHAIN_ENV = "CF7_AUDIO_V2_TOOLCHAIN_B64";
const NODE_EXE_ENV = "CF7_NODE_EXE";

const EXPECTED_EXPORTS = [
    "cf7_audio_bridge_v2_initialize", "cf7_audio_bridge_v2_probe_offline_qualification",
    "cf7_audio_bridge_v2_probe_runtime_compatibility", "cf7_audio_bridge_v2_query_bgm_source",
    "cf7_audio_bridge_v2_query_capability", "cf7_audio_bridge_v2_query_meter",
    "cf7_audio_bridge_v2_query_runtime", "cf7_audio_bridge_v2_query_sfx_counters",
    "cf7_audio_bridge_v2_rebuild_sfx_catalog", "cf7_audio_bridge_v2_set_gain",
    "cf7_audio_bridge_v2_shutdown", "cf7_audio_bridge_v2_submit_bgm",
    "cf7_audio_bridge_v2_submit_sfx_batch"
].sort();

function makeExportPe(exports) {
    const bytes = Buffer.alloc(0x3000);
    bytes.writeUInt16LE(0x5A4D, 0);
    bytes.writeUInt32LE(0x80, 0x3C);
    bytes.write("PE\0\0", 0x80, "ascii");
    bytes.writeUInt16LE(0x8664, 0x84);
    bytes.writeUInt16LE(1, 0x86);
    bytes.writeUInt16LE(0xF0, 0x94);
    const optional = 0x98;
    bytes.writeUInt16LE(0x20B, optional);
    bytes.writeUInt32LE(0x1000, optional + 112);
    bytes.writeUInt32LE(0x1000, optional + 116);
    const section = optional + 0xF0;
    bytes.write(".rdata", section, "ascii");
    bytes.writeUInt32LE(0x2000, section + 8);
    bytes.writeUInt32LE(0x1000, section + 12);
    bytes.writeUInt32LE(0x2000, section + 16);
    bytes.writeUInt32LE(0x200, section + 20);
    const directory = 0x200;
    bytes.writeUInt32LE(exports.length, directory + 24);
    bytes.writeUInt32LE(0x1040, directory + 32);
    let nameRva = 0x1100;
    exports.forEach((name, index) => {
        bytes.writeUInt32LE(nameRva, 0x240 + index * 4);
        const offset = 0x200 + nameRva - 0x1000;
        bytes.write(name + "\0", offset, "ascii");
        nameRva += Buffer.byteLength(name, "ascii") + 1;
    });
    return bytes;
}

function fakeToolchainValue() {
    const descriptor = { path: path.resolve(process.execPath), sha256: runner.sha256(fs.readFileSync(process.execPath)) };
    return {
        cl: descriptor, cmd: descriptor, dotnet: descriptor,
        msvcToolsVersion: "14.0-test", node: descriptor,
        nodeVersion: process.version, powershell: descriptor,
        schema: "cf7.audio-v2.qualification-toolchain.v1", vcvars64: descriptor,
        windowsSdkVersion: "10.0-test"
    };
}

function makePcmWave(nonzero) {
    const frames = 8000;
    const bytes = Buffer.alloc(44 + frames * 2);
    bytes.write("RIFF", 0, "ascii"); bytes.writeUInt32LE(36 + frames * 2, 4); bytes.write("WAVE", 8, "ascii");
    bytes.write("fmt ", 12, "ascii"); bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22);
    bytes.writeUInt32LE(8000, 24); bytes.writeUInt32LE(16000, 28); bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34);
    bytes.write("data", 36, "ascii"); bytes.writeUInt32LE(frames * 2, 40);
    if (nonzero) for (let index = 0; index < frames; index++) bytes.writeInt16LE(index % 2 ? 1024 : -1024, 44 + index * 2);
    return bytes;
}

function writeBytes(root, relative, bytes) {
    const destination = path.join(root, relative.split("/").join(path.sep));
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, bytes);
    return destination;
}

function writeJson(root, relative, value) {
    return writeBytes(root, relative, runner.canonicalBytes(value));
}

function artifact(root, relative, schema) {
    const bytes = fs.readFileSync(path.join(root, relative.split("/").join(path.sep)));
    return {
        blobOid: runner.gitBlobOid(bytes, 40),
        bytes: bytes.length,
        kind: "tracked_blob",
        path: relative,
        schema,
        sha256: runner.sha256(bytes)
    };
}

function addFixtureDependency(state, relative, bytes) {
    writeBytes(state.root, relative, bytes);
    const dependencyPath = path.join(state.root, DEPENDENCY_REL.split("/").join(path.sep));
    const manifest = JSON.parse(fs.readFileSync(dependencyPath, "utf8"));
    manifest.dependencies.push({
        blobOid: runner.gitBlobOid(bytes, 40),
        bytes: bytes.length,
        path: relative,
        sha256: runner.sha256(bytes)
    });
    manifest.dependencies.sort((left, right) => left.path < right.path ? -1 : (left.path > right.path ? 1 : 0));
    manifest.closureSha256 = runner.sha256(runner.canonicalBytes(manifest.dependencies));
    writeJson(state.root, DEPENDENCY_REL, manifest);
    state.report.provenance.producerDependencyManifestArtifact = artifact(
        state.root, DEPENDENCY_REL, "cf7.audio-v2.qualification-runner-dependencies.v1");
}

function trackedInput(root, relative, role) {
    const bytes = fs.readFileSync(path.join(root, relative.split("/").join(path.sep)));
    return {
        blobOid: runner.gitBlobOid(bytes, 40),
        bytes: bytes.length,
        kind: "release_source_blob",
        path: relative,
        role,
        sha256: runner.sha256(bytes)
    };
}

function candidateInput(root, relative, role) {
    const bytes = fs.readFileSync(path.join(root, relative.split("/").join(path.sep)));
    return {
        bytes: bytes.length,
        kind: "candidate_artifact",
        path: relative,
        role,
        sha256: runner.sha256(bytes)
    };
}

function makeFixture(mutator) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-runner-test-"));
    const candidateRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-runner-candidate-"));
    const reportId = "csharp_capability_catalog_bridge";
    const artifactSourceHash = "1".repeat(64);
    const producerRecipeHash = "2".repeat(64);
    const toolchainLockHash = "3".repeat(64);
    const identity = runner.runtimeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash);
    const releaseSource = { commit: "c".repeat(40), treeOid: "d".repeat(40) };
    const sourceRunner = fs.readFileSync(path.join(__dirname, "qualification-runner.js"));
    const sourceObserver = fs.readFileSync(path.join(__dirname, "qualification-observer.js"));
    writeBytes(root, RUNNER_REL, sourceRunner);
    writeBytes(root, OBSERVER_REL, sourceObserver);

    const payload = [
        ["CRAZYFLASHER7MercenaryEmpire.exe", Buffer.from("candidate-bootstrap", "utf8")],
        ["runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", Buffer.from("candidate-core", "utf8")],
        ["runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", Buffer.from("candidate-core-exe", "utf8")],
        ["runtime/miniaudio.dll", makeExportPe(EXPECTED_EXPORTS)]
    ];
    payload.forEach(([relative, bytes]) => writeBytes(candidateRoot, relative, bytes));
    const payloadRows = payload.map(([relative, bytes]) => ({ bytes: bytes.length, path: relative, sha256: runner.sha256(bytes) })).sort((left, right) => left.path < right.path ? -1 : (left.path > right.path ? 1 : 0));
    const closure = runner.runtimePayloadClosureHash(payloadRows);
    const manifestText = [
        "cf7-runtime-manifest-v2", "publishMode\tframework-dependent",
        "artifactSourceHash\t" + artifactSourceHash, "producerRecipeHash\t" + producerRecipeHash,
        "toolchainLockHash\t" + toolchainLockHash, "toolchainBaseline\ttest-locked",
        "buildIdentityHash\t" + identity, "payloadClosureHash\t" + closure
    ].concat(payloadRows.map((row) => "file\t" + row.path + "\t" + row.bytes + "\t" + row.sha256)).join("\n") + "\n";
    writeBytes(candidateRoot, "runtime/cf7-runtime-manifest.tsv", Buffer.from(manifestText, "utf8"));

    const runnerDependency = {
        blobOid: runner.gitBlobOid(sourceRunner, 40),
        bytes: sourceRunner.length,
        path: RUNNER_REL,
        sha256: runner.sha256(sourceRunner)
    };
    const observerDependency = {
        blobOid: runner.gitBlobOid(sourceObserver, 40),
        bytes: sourceObserver.length,
        path: OBSERVER_REL,
        sha256: runner.sha256(sourceObserver)
    };
    const fixtureDependencies = [observerDependency, runnerDependency].sort((left, right) => left.path.localeCompare(right.path));
    const dependencyManifest = {
        closureSha256: runner.sha256(runner.canonicalBytes(fixtureDependencies)),
        dependencies: fixtureDependencies,
        runnerPath: RUNNER_REL,
        schema: "cf7.audio-v2.qualification-runner-dependencies.v1"
    };
    writeJson(root, DEPENDENCY_REL, dependencyManifest);

    const configurationPath = "docs/evidence/audio-v2/config/" + reportId + ".json";
    const toolchainEncoded = runner.canonicalBytes(fakeToolchainValue()).toString("base64");
    const environmentValues = {
        [NODE_EXE_ENV]: path.resolve(process.execPath),
        [TOOLCHAIN_ENV]: toolchainEncoded,
        NUGET_PACKAGES: path.join(root, "nuget"),
        SystemRoot: process.env.SystemRoot || path.parse(process.execPath).root,
        TEMP: os.tmpdir(),
        TMP: os.tmpdir()
    };
    const configuration = {
        argv: [environmentValues[NODE_EXE_ENV], RUNNER_REL, "--report-id", reportId],
        environment: Object.keys(environmentValues).sort().map((name) => ({
            name,
            valueSha256: runner.sha256(Buffer.from(environmentValues[name], "utf8"))
        })),
        reportId,
        schema: "cf7.audio-v2.automated-report-configuration.v1",
        workingDirectory: "release_source_root"
    };

    const sourceRoles = ["bridge_protocol_contract", "catalog_contract", "csharp_audio_source_closure"];
    sourceRoles.forEach((role) => writeJson(root, "tools/audio-v2/inputs/" + reportId + "/" + role + ".json", {
        reportId,
        role,
        schema: "cf7.audio-v2.test-input.v1"
    }));
    const inputs = [
        candidateInput(candidateRoot, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", "candidate_core"),
        candidateInput(candidateRoot, "runtime/cf7-runtime-manifest.tsv", "candidate_runtime_manifest"),
        candidateInput(candidateRoot, "runtime/miniaudio.dll", "candidate_miniaudio")
    ];
    sourceRoles.forEach((role) => inputs.push(trackedInput(root, "tools/audio-v2/inputs/" + reportId + "/" + role + ".json", role)));
    inputs.sort((left, right) => {
        const a = left.kind + ":" + left.path;
        const b = right.kind + ":" + right.path;
        return a < b ? -1 : (a > b ? 1 : 0);
    });
    const inputPath = "docs/evidence/audio-v2/inputs/" + reportId + ".json";
    const inputManifest = {
        candidateBuildIdentity: identity,
        candidatePayloadClosure: closure,
        closureSha256: runner.sha256(runner.canonicalBytes(inputs)),
        inputs,
        releaseSource,
        reportId,
        schema: "cf7.audio-v2.automated-report-input-manifest.v1"
    };
    writeJson(root, inputPath, inputManifest);
    const inputArtifact = artifact(root, inputPath, "cf7.audio-v2.automated-report-input-manifest.v1");

    const producerSha = runner.sha256(sourceRunner);
    const producerBlob = runner.gitBlobOid(sourceRunner, 40);
    const candidateSnapshot = runner.validateCandidateBinary(candidateRoot, identity, closure);
    const sourceProbe = { assertionCount: 150, profile: "csharp_audio_focused_dotnet_v1", skippedCount: 0 };
    const toolchainSha256 = runner.sha256(runner.canonicalBytes(fakeToolchainValue()));
    const observation = {
        candidateBuildIdentity: identity,
        candidatePayloadClosure: closure,
        candidateProcess: null,
        caseFacts: runner.REPORT_CASES[reportId].map((caseId) => ({ caseId, facts: { assertionIds: runner.CASE_CHECKS[reportId][caseId] } })),
        generatedAtUtc: "2026-08-09T00:00:00Z",
        releaseSource,
        reportId,
        runId: "unit-source-probe-001",
        schema: "cf7.audio-v2.live-observation.v2",
        session: { executionKind: "recomputed_bound_source_probe", toolchainSha256 }
    };
    configuration.argv = [environmentValues[NODE_EXE_ENV], RUNNER_REL, "--report-id", reportId].concat(runner.encodeLiveObservationArguments(observation));
    writeJson(root, configurationPath, configuration);
    const configurationArtifact = artifact(root, configurationPath, "cf7.audio-v2.automated-report-configuration.v1");
    const semanticSnapshot = { candidate: candidateSnapshot, live: { probe: sourceProbe, toolchainSha256 } };
    const caseResults = runner.REPORT_CASES[reportId].map((caseId) => {
        const casePath = "docs/evidence/audio-v2/cases/" + reportId + "/" + caseId + ".json";
        const evidence = {
            candidateBuildIdentity: identity,
            candidatePayloadClosure: closure,
            captureIds: [],
            caseId,
            checks: runner.CASE_CHECKS[reportId][caseId].map((checkId) => ({
                checkId,
                measurement: {
                    kind: "digest",
                    unit: "cf7.audio-v2.recomputed-observation-sha256.v1",
                    value: runner.sha256(runner.canonicalBytes({
                        candidate: semanticSnapshot.candidate,
                        caseId,
                        checkId,
                        facts: observation.caseFacts.find((entry) => entry.caseId === caseId).facts,
                        live: semanticSnapshot.live,
                        releaseSource,
                        reportId,
                        runId: observation.runId,
                        session: observation.session
                    }))
                },
                result: "passed"
            })),
            configurationSha256: configurationArtifact.sha256,
            generatedAtUtc: "2026-08-09T00:00:00Z",
            inputClosureSha256: inputManifest.closureSha256,
            producerBlobOid: producerBlob,
            producerSha256: producerSha,
            releaseSource,
            reportId,
            result: "passed",
            schema: "cf7.audio-v2.automated-case-evidence.v1"
        };
        writeJson(root, casePath, evidence);
        return { caseId, evidenceArtifact: artifact(root, casePath, "cf7.audio-v2.automated-case-evidence.v1"), result: "passed" };
    });

    const reportPath = "docs/evidence/audio-v2/reports/" + reportId + ".json";
    const report = {
        candidateBuildIdentity: identity,
        candidatePayloadClosure: closure,
        caseResults,
        caseResultsSha256: runner.sha256(runner.canonicalBytes(caseResults)),
        generatedAtUtc: "2026-08-09T00:00:00Z",
        provenance: {
            configurationArtifact,
            inputClosureSha256: inputManifest.closureSha256,
            inputManifestArtifact: inputArtifact,
            producerBlobOid: producerBlob,
            producerDependencyManifestArtifact: artifact(root, DEPENDENCY_REL, "cf7.audio-v2.qualification-runner-dependencies.v1"),
            producerPath: RUNNER_REL,
            producerSha256: producerSha
        },
        releaseSource,
        reportId,
        result: "passed",
        schema: "cf7.audio-v2.automated-report.v1",
        summary: { failed: 0, passed: caseResults.length, total: caseResults.length }
    };

    const state = { candidateRoot, candidateSnapshot, configuration, configurationPath, environmentValues, inputManifest, inputPath, observation, report, reportId, reportPath, root, sourceProbe, toolchainEncoded };
    if (mutator) mutator(state);
    if (!fs.existsSync(path.join(root, reportPath.split("/").join(path.sep)))) writeJson(root, reportPath, report);
    return state;
}

function runFixture(state) {
    const executable = path.join(state.root, RUNNER_REL.split("/").join(path.sep));
    return cp.spawnSync(process.execPath, [
        executable,
        "--verify-audio-v2-report",
        "--report", path.join(state.root, state.reportPath.split("/").join(path.sep)),
        "--configuration", path.join(state.root, state.configurationPath.split("/").join(path.sep)),
        "--input-manifest", path.join(state.root, state.inputPath.split("/").join(path.sep)),
        "--candidate-root", state.candidateRoot
    ], { cwd: state.root, encoding: "utf8", env: state.environmentValues, timeout: 15000 });
}

function runFixtureDirect(state, overrides) {
    const previous = {};
    Object.keys(state.environmentValues).forEach((name) => {
        previous[name] = process.env[name];
        process.env[name] = state.environmentValues[name];
    });
    try {
        const context = runner.validateInvocation({
            candidateRoot: state.candidateRoot,
            configurationPath: path.join(state.root, state.configurationPath.split("/").join(path.sep)),
            deadlineEpochMs: Date.now() + 30000,
            inputManifestPath: path.join(state.root, state.inputPath.split("/").join(path.sep)),
            replayRoot: state.root,
            reportPath: path.join(state.root, state.reportPath.split("/").join(path.sep))
        });
        return runner.runLiveVerifier(context, Object.assign({
            candidateSnapshot: state.candidateSnapshot,
            observation: state.observation,
            sourceProbe: () => state.sourceProbe,
            toolchain: { cl: process.execPath, cmd: process.execPath, dotnet: process.execPath, node: process.execPath, nodeVersion: process.version, powershell: process.execPath, vcvars64: process.execPath }
        }, overrides || {}));
    } finally {
        Object.keys(previous).forEach((name) => {
            if (previous[name] === undefined) delete process.env[name];
            else process.env[name] = previous[name];
        });
    }
}

function cleanup(state) {
    fs.rmSync(state.root, { force: true, recursive: true });
    fs.rmSync(state.candidateRoot, { force: true, recursive: true });
}

function withFixture(mutator, assertion) {
    const state = makeFixture(mutator);
    try {
        assertion(state);
    } finally {
        cleanup(state);
    }
}

let passed = 0;
function test(name, body) {
    body();
    passed++;
    process.stdout.write("ok " + passed + " - " + name + "\n");
}

test("frozen matrix is exactly nine reports and forty-four cases", () => {
    assert.strictEqual(Object.keys(runner.REPORT_CASES).length, 9);
    assert.strictEqual(Object.values(runner.REPORT_CASES).reduce((sum, entries) => sum + entries.length, 0), 44);
    Object.keys(runner.REPORT_CASES).forEach((reportId) => {
        assert.ok(runner.REPORT_INPUT_ROLES[reportId]);
        runner.REPORT_CASES[reportId].forEach((caseId) => assert.ok(runner.CASE_CHECKS[reportId][caseId]));
    });
});

test("canonical JSON recursively sorts keys and terminates with one LF", () => {
    assert.strictEqual(runner.canonicalBytes({ z: 1, a: { y: 2, b: 3 } }).toString("utf8"), "{\n  \"a\": {\n    \"b\": 3,\n    \"y\": 2\n  },\n  \"z\": 1\n}\n");
});

test("dependency replay accepts exact root global.json", () => {
    withFixture((state) => addFixtureDependency(
        state, "global.json", Buffer.from("{\"sdk\":{\"version\":\"10.0.300\"}}\n", "utf8")),
    (state) => assert.doesNotThrow(() => runFixtureDirect(state)));
});

test("dependency replay rejects every other root file", () => {
    withFixture((state) => addFixtureDependency(
        state, "package.json", Buffer.from("{\"private\":true}\n", "utf8")),
    (state) => assert.throws(() => runFixtureDirect(state), /dependency path prefix invalid/));
});

test("runtime payload closure matches the independent .NET ordinal oracle", () => {
    const rows = [
        { bytes: 55, path: "runtime/libHarfBuzzSharp.dll", sha256: "E".repeat(64) },
        { bytes: 33, path: "runtime/ClearScript.Core.dll", sha256: "C".repeat(64) },
        { bytes: 11, path: "CRAZYFLASHER7MercenaryEmpire.exe", sha256: "A".repeat(64) },
        { bytes: 66, path: "runtime/miniaudio.dll", sha256: "F".repeat(64) },
        { bytes: 44, path: "runtime/THIRD-PARTY-NOTICES.txt", sha256: "D".repeat(64) },
        { bytes: 22, path: "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", sha256: "B".repeat(64) }
    ];
    const expectedOrdinalPaths = [
        "CRAZYFLASHER7MercenaryEmpire.exe",
        "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll",
        "runtime/ClearScript.Core.dll",
        "runtime/THIRD-PARTY-NOTICES.txt",
        "runtime/libHarfBuzzSharp.dll",
        "runtime/miniaudio.dll"
    ];
    const ordinalClosure = "E6E6F5527FF8175EDEF69D1F942B37CB0FA1665A4E7399B487D1B83AAC981202";
    const zhCnLocaleClosure = "11C334EB971A61FD1403C6F8639EE31C9EB31CCF15A45BD715BAFA2B20B7BE9B";
    const byPath = new Map(rows.map((row) => [row.path, row]));
    const ordinalCanonical = expectedOrdinalPaths.map((relative) => {
        const row = byPath.get(relative);
        return row.path + "\t" + row.bytes + "\t" + row.sha256;
    }).join("\n") + "\n";
    assert.strictEqual(runner.sha256(Buffer.from(ordinalCanonical, "utf8")), ordinalClosure);
    assert.strictEqual(runner.runtimePayloadClosureHash(rows), ordinalClosure);
    assert.strictEqual(runner.runtimePayloadClosureHash(rows.slice().reverse()), ordinalClosure);

    const localeRows = rows.slice().sort((left, right) => left.path.localeCompare(right.path, "zh-CN"));
    assert.notDeepStrictEqual(localeRows.map((row) => row.path), expectedOrdinalPaths);
    const localeCanonical = localeRows.map((row) => row.path + "\t" + row.bytes + "\t" + row.sha256).join("\n") + "\n";
    assert.strictEqual(runner.sha256(Buffer.from(localeCanonical, "utf8")), zhCnLocaleClosure);
    assert.notStrictEqual(ordinalClosure, zhCnLocaleClosure);
});

test("qualification toolchain binds exact Node path hash version and PATH-free child environment", () => {
    withFixture(null, (state) => {
        const previous = {};
        Object.keys(state.environmentValues).forEach((name) => {
            previous[name] = process.env[name];
            process.env[name] = state.environmentValues[name];
        });
        try {
            assert.doesNotThrow(() => runner.validateConfiguration(state.configuration, state.reportId));
            const toolchain = runner.validateToolchain(state.configuration);
            assert.strictEqual(toolchain.node, path.resolve(process.execPath));
            assert.strictEqual(toolchain.nodeVersion, process.version);
            const child = runner.childEnvironment({
                configurationBinding: { value: state.configuration },
                report: { reportId: state.reportId }
            }, toolchain);
            assert.strictEqual(child[NODE_EXE_ENV], path.resolve(process.execPath));
            assert.ok(!Object.prototype.hasOwnProperty.call(child, "PATH"));

            const bare = JSON.parse(JSON.stringify(state.configuration));
            bare.argv[0] = "node";
            assert.throws(() => runner.validateConfiguration(bare, state.reportId), /must be absolute/);

            const relativeEnvironment = JSON.parse(JSON.stringify(state.configuration));
            relativeEnvironment.argv[0] = "node";
            relativeEnvironment.environment.find((entry) => entry.name === NODE_EXE_ENV).valueSha256 =
                runner.sha256(Buffer.from("node", "utf8"));
            process.env[NODE_EXE_ENV] = "node";
            assert.throws(() => runner.validateConfiguration(relativeEnvironment, state.reportId), /must be absolute/);
            process.env[NODE_EXE_ENV] = state.environmentValues[NODE_EXE_ENV];

            const wrongVersion = fakeToolchainValue();
            wrongVersion.nodeVersion = "v0.0.0";
            const wrongVersionEncoded = runner.canonicalBytes(wrongVersion).toString("base64");
            const wrongVersionConfiguration = JSON.parse(JSON.stringify(state.configuration));
            wrongVersionConfiguration.environment.find((entry) => entry.name === TOOLCHAIN_ENV).valueSha256 =
                runner.sha256(Buffer.from(wrongVersionEncoded, "utf8"));
            process.env[TOOLCHAIN_ENV] = wrongVersionEncoded;
            assert.throws(() => runner.validateToolchain(wrongVersionConfiguration), /Node version differs/);

            const wrongHash = fakeToolchainValue();
            wrongHash.node = Object.assign({}, wrongHash.node, { sha256: "A".repeat(64) });
            const wrongHashEncoded = runner.canonicalBytes(wrongHash).toString("base64");
            const wrongHashConfiguration = JSON.parse(JSON.stringify(state.configuration));
            wrongHashConfiguration.environment.find((entry) => entry.name === TOOLCHAIN_ENV).valueSha256 =
                runner.sha256(Buffer.from(wrongHashEncoded, "utf8"));
            process.env[TOOLCHAIN_ENV] = wrongHashEncoded;
            assert.throws(() => runner.validateToolchain(wrongHashConfiguration), /SHA mismatch/);
        } finally {
            Object.keys(previous).forEach((name) => {
                if (previous[name] === undefined) delete process.env[name];
                else process.env[name] = previous[name];
            });
        }
    });
});

test("checked-in decoder fixtures are canonical, byte-bound, and semantically fixed", () => {
    const repositoryRoot = path.resolve(__dirname, "..", "..");
    const fixturePath = path.join(repositoryRoot, DECODER_FIXTURE_REL.split("/").join(path.sep));
    const fixtureBytes = fs.readFileSync(fixturePath);
    const fixtureValue = JSON.parse(fixtureBytes.toString("utf8"));
    assert.ok(fixtureBytes.equals(runner.canonicalBytes(fixtureValue)));
    const fixtures = runner.validateDecoderFixtureInventory({
        input: { inputs: [{ kind: "release_source_blob", path: DECODER_FIXTURE_REL, role: "decoder_fixture_inventory" }] },
        replayRoot: repositoryRoot
    });
    assert.strictEqual(fixtures.length, 6);
    assert.deepStrictEqual(fixtures.map((fixture) => fixture.expectedCategory), [0, 4, 0, 0, 5, 0]);
    const complete = fixtures.find((fixture) => fixture.fixtureId === "vorbis-ogg-tone-48000-mono")._bytes;
    const truncated = fixtures.find((fixture) => fixture.fixtureId === "truncated-ogg-vorbis-packet")._bytes;
    assert.ok(truncated.length < complete.length && complete.subarray(0, truncated.length).equals(truncated));
});

test("a relabelled malformed fixture cannot redefine the expected native category", () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-fixture-contract-"));
    try {
        const source = JSON.parse(fs.readFileSync(path.join(__dirname, "qualification-decoder-fixtures.v1.json"), "utf8"));
        source.fixtures.find((fixture) => fixture.signalClass === "truncated").expectedCategory = 4;
        writeJson(root, "fixture.json", source);
        assert.throws(() => runner.validateDecoderFixtureInventory({
            input: { inputs: [{ kind: "release_source_blob", path: "fixture.json", role: "decoder_fixture_inventory" }] },
            replayRoot: root
        }), /semantics drifted/);
    } finally {
        fs.rmSync(root, { force: true, recursive: true });
    }
});

test("AS2 source probe derives the complete named assertion inventory", () => {
    const repositoryRoot = path.resolve(__dirname, "..", "..");
    const paths = [
        "scripts/类定义/org/flashNight/arki/audio/AudioBridge.as",
        "scripts/类定义/org/flashNight/arki/audio/SoundEffectManager.as",
        "scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeV2Test.as",
        "scripts/类定义/org/flashNight/neur/Server/ServerManager.as",
        "launcher/src/Bus/MessageRouter.cs"
    ];
    const probe = runner.recomputeAs2AudioProbe({
        dependencies: { dependencies: paths.map((entry) => ({ path: entry })) },
        replayRoot: repositoryRoot
    });
    assert.ok(probe.assertionCount >= 80);
    assert.strictEqual(probe.assertionCount, probe.assertionNames.length);
    assert.strictEqual(new Set(probe.assertionNames).size, probe.assertionCount);
    assert.strictEqual(probe.assertionNamesSha256, runner.sha256(runner.canonicalBytes(probe.assertionNames)));
});

test("reviewed source probe derives every measurement from recomputed evidence", () => {
    withFixture(null, (state) => {
        const result = runFixtureDirect(state);
        assert.strictEqual(result.observation.runId, state.observation.runId);
        assert.strictEqual(result.semanticSnapshot.live.probe.assertionCount, 150);
    });
});

test("noncanonical report bytes fail before the live gate", () => {
    withFixture((state) => {
        const destination = writeJson(state.root, state.reportPath, state.report);
        fs.appendFileSync(destination, " ");
    }, (state) => {
        const result = runFixture(state);
        assert.strictEqual(result.status, 3);
        assert.match(result.stderr, /not canonical/);
        assert.doesNotMatch(result.stderr, /LIVE_PHASE_NOT_IMPLEMENTED/);
    });
});

test("fixed case matrix rejects a shortened all-green report", () => {
    withFixture((state) => {
        state.report.caseResults.pop();
        state.report.summary.passed--;
        state.report.summary.total--;
        state.report.caseResultsSha256 = runner.sha256(runner.canonicalBytes(state.report.caseResults));
        writeJson(state.root, state.reportPath, state.report);
    }, (state) => {
        const result = runFixture(state);
        assert.strictEqual(result.status, 3);
        assert.match(result.stderr, /fixed case matrix|case count/);
    });
});

test("typed measurements reject a string disguised as a counter", () => {
    withFixture((state) => {
        const first = state.report.caseResults[0];
        const evidenceFile = path.join(state.root, first.evidenceArtifact.path.split("/").join(path.sep));
        const evidence = JSON.parse(fs.readFileSync(evidenceFile, "utf8"));
        evidence.checks[0].measurement = { kind: "counter", unit: "count", value: "1" };
        writeJson(state.root, first.evidenceArtifact.path, evidence);
        first.evidenceArtifact = artifact(state.root, first.evidenceArtifact.path, "cf7.audio-v2.automated-case-evidence.v1");
        state.report.caseResultsSha256 = runner.sha256(runner.canonicalBytes(state.report.caseResults));
        writeJson(state.root, state.reportPath, state.report);
    }, (state) => {
        const result = runFixture(state);
        assert.strictEqual(result.status, 3);
        assert.match(result.stderr, /counter invalid/);
    });
});

test("input closure tampering is rejected", () => {
    withFixture((state) => {
        state.inputManifest.closureSha256 = "F".repeat(64);
        writeJson(state.root, state.inputPath, state.inputManifest);
        state.report.provenance.inputManifestArtifact = artifact(state.root, state.inputPath, "cf7.audio-v2.automated-report-input-manifest.v1");
        state.report.provenance.inputClosureSha256 = state.inputManifest.closureSha256;
        writeJson(state.root, state.reportPath, state.report);
    }, (state) => {
        const result = runFixture(state);
        assert.strictEqual(result.status, 3);
        assert.match(result.stderr, /input closure mismatch/);
    });
});

test("candidate artifact byte drift is rejected", () => {
    withFixture(null, (state) => {
        fs.appendFileSync(path.join(state.candidateRoot, "runtime", "miniaudio.dll"), "tamper");
        const result = runFixture(state);
        assert.strictEqual(result.status, 3);
        assert.match(result.stderr, /input bytes\/SHA mismatch/);
    });
});

test("a dummy non-PE producer DLL is rejected before any claimed check", () => {
    assert.throws(() => runner.parsePeExports(Buffer.from("dummy producer", "utf8")), /not a PE image/);
});

test("forged all-green booleans cannot replace recomputed digest measurements", () => {
    withFixture(null, (state) => {
        const first = state.report.caseResults[0];
        const evidenceFile = path.join(state.root, first.evidenceArtifact.path.split("/").join(path.sep));
        const evidence = JSON.parse(fs.readFileSync(evidenceFile, "utf8"));
        evidence.checks.forEach((check) => { check.measurement = { kind: "boolean", unit: "pass", value: true }; });
        writeJson(state.root, first.evidenceArtifact.path, evidence);
        first.evidenceArtifact = artifact(state.root, first.evidenceArtifact.path, "cf7.audio-v2.automated-case-evidence.v1");
        state.report.caseResultsSha256 = runner.sha256(runner.canonicalBytes(state.report.caseResults));
        writeJson(state.root, state.reportPath, state.report);
        assert.throws(() => runFixtureDirect(state), /not derived from recomputed live evidence/);
    });
});

test("pre-written passed verdicts are forbidden in raw live facts", () => {
    withFixture(null, (state) => {
        state.observation.caseFacts[0].facts.passed = true;
        assert.throws(() => runFixtureDirect(state), /forbidden verdict field/);
    });
});

test("a forged source-probe summary changes every bound measurement and is rejected", () => {
    withFixture(null, (state) => {
        assert.throws(() => runFixtureDirect(state, {
            sourceProbe: () => ({ assertionCount: 999999, profile: "dummy_echo", skippedCount: 0 })
        }), /not derived from recomputed live evidence/);
    });
});

test("silent PCM is measurable as zero and cannot satisfy the endpoint threshold", () => {
    const pcm = runner.parsePcm16Wave(makePcmWave(false), "silent fixture");
    assert.strictEqual(pcm.peakAbs, 0);
    assert.strictEqual(pcm.nonZeroSampleRatio, 0);
    assert.ok(!(pcm.peakAbs >= 64 && pcm.nonZeroSampleRatio >= 0.001));
});

test("RIFF/WAVE content sniff derives the exact shipped PCM16 codec from fmt", () => {
    const pcm16 = Buffer.from(
        "524946462600000057415645666D74201000000001000100401F0000803E00000200100064617461020000000100",
        "hex");
    assert.strictEqual(pcm16.length, 46);
    assert.strictEqual(runner.sha256(pcm16), "A488871A54ADAC2B93D8575538BD79F94C2B99ED58CC874A7FB054BFFB9A3C5E");
    assert.deepStrictEqual(runner.sniffAudio(pcm16), {
        codec: "pcm_s16le",
        container: "riff_wave"
    });

    const float32 = Buffer.from(pcm16);
    float32.writeUInt16LE(3, 20);
    float32.writeUInt16LE(32, 34);
    assert.deepStrictEqual(runner.sniffAudio(float32), {
        codec: "unknown_riff_wave_codec",
        container: "riff_wave"
    });

    const truncatedFmt = pcm16.subarray(0, 24);
    assert.deepStrictEqual(runner.sniffAudio(truncatedFmt), {
        codec: "unknown_riff_wave_codec",
        container: "riff_wave"
    });

    const duplicateFmt = Buffer.concat([
        pcm16.subarray(0, 36),
        pcm16.subarray(12, 36),
        pcm16.subarray(36)
    ]);
    duplicateFmt.writeUInt32LE(duplicateFmt.length - 8, 4);
    assert.deepStrictEqual(runner.sniffAudio(duplicateFmt), {
        codec: "unknown_riff_wave_codec",
        container: "riff_wave"
    });

    const shortDeclaredRiff = Buffer.from(pcm16);
    shortDeclaredRiff.writeUInt32LE(12, 4);
    assert.deepStrictEqual(runner.sniffAudio(shortDeclaredRiff), {
        codec: "unknown_riff_wave_codec",
        container: "riff_wave"
    });
});

test("ISO BMFF content sniff requires a bounded mp4a sample entry", () => {
    const aac = Buffer.from(
        "000000106674797069736f6d00000000000000406d6f6f76000000387472616b000000306d646961000000286d696e66000000207374626c00000018737473640000000000000001000000086d703461",
        "hex");
    assert.strictEqual(aac.length, 80);
    assert.strictEqual(runner.sha256(aac), "14790867C11845D38415866ECC805FF3BFDCC983C6C2AAF3488AEC2A96645F8C");
    assert.deepStrictEqual(runner.sniffAudio(aac), {
        codec: "aac_lc_or_he_aac",
        container: "iso_bmff"
    });

    const nonFtyp = Buffer.from(aac);
    nonFtyp.write("free", 4, "ascii");
    assert.deepStrictEqual(runner.sniffAudio(nonFtyp), {
        codec: "unknown",
        container: "unknown"
    });

    const noMp4a = Buffer.from(aac);
    noMp4a.write("enca", noMp4a.length - 4, "ascii");
    assert.deepStrictEqual(runner.sniffAudio(noMp4a), {
        codec: "unknown_iso_bmff_codec",
        container: "iso_bmff"
    });

    const topLevelStsd = Buffer.from(
        "000000106674797069736f6d0000000000000018737473640000000000000001000000086d703461",
        "hex");
    assert.strictEqual(topLevelStsd.length, 40);
    assert.strictEqual(runner.sha256(topLevelStsd), "956413BCA52F6701F5153B2F5C403DC34966E4F5763D4DB58D012C2637FB4A78");
    assert.deepStrictEqual(runner.sniffAudio(topLevelStsd), {
        codec: "unknown_iso_bmff_codec",
        container: "iso_bmff"
    });

    const truncated = aac.subarray(0, aac.length - 1);
    assert.deepStrictEqual(runner.sniffAudio(truncated), {
        codec: "unknown_iso_bmff_codec",
        container: "iso_bmff"
    });
});

test("missing real endpoint process fails closed", () => {
    withFixture(null, (state) => {
        const powershell = path.join(process.env.SystemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        assert.throws(() => runner.inspectWindowsProcess(state.candidateRoot, {
            executableSha256: runner.sha256(fs.readFileSync(path.join(state.candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"))),
            observedAtUtc: new Date().toISOString(),
            pid: 2147483647,
            processStartUtc: "2026-08-09T00:00:00Z"
        }, { powershell }), (error) => error.code === "PREREQUISITE_MISSING");
    });
});

test("a live but wrong executable cannot impersonate the exact candidate process", () => {
    withFixture(null, (state) => {
        const powershell = path.join(process.env.SystemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        const startScript = "$p=Get-Process -Id " + process.pid + ";$p.StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')";
        const start = cp.execFileSync(powershell, ["-NoProfile", "-Command", startScript], { encoding: "utf8" }).trim();
        assert.throws(() => runner.inspectWindowsProcess(state.candidateRoot, {
            executableSha256: runner.sha256(fs.readFileSync(path.join(state.candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"))),
            observedAtUtc: new Date().toISOString(), pid: process.pid, processStartUtc: start
        }, { powershell }), /not the exact candidate Core executable/);
    });
});

test("expired internal deadline fails closed", () => {
    assert.throws(() => runner.assertWithinDeadline(0, "test deadline"), (error) => error.code === "TIMEOUT");
});

test("report generation without bound candidate/configuration inputs fails closed", () => {
    const result = cp.spawnSync(process.execPath, [path.join(__dirname, "qualification-runner.js"), "--report-id", "csharp_capability_catalog_bridge"], { encoding: "utf8" });
    assert.notStrictEqual(result.status, 0);
    assert.match(result.stderr, /generation|argument|flag|implemented/i);
    assert.strictEqual(result.stdout, "");
});

test("generation writes a complete five-case report and deterministic verification", () => {
    withFixture(null, (state) => {
        const oldCwd = process.cwd();
        const previousEnvironment = {};
        Object.keys(state.environmentValues).forEach((name) => {
            previousEnvironment[name] = process.env[name];
            process.env[name] = state.environmentValues[name];
        });
        process.chdir(state.root);
        try {
            const generated = runner.generateReport({
                candidateRoot: state.candidateRoot,
                configurationPath: path.join(state.root, state.configurationPath.split("/").join(path.sep)),
                inputManifestPath: path.join(state.root, state.inputPath.split("/").join(path.sep)),
                outputRoot: state.root,
                reportId: state.reportId
            }, {
                candidateSnapshot: state.candidateSnapshot,
                observation: state.observation,
                sourceProbe: () => state.sourceProbe,
                toolchain: { cl: process.execPath, cmd: process.execPath, dotnet: process.execPath, node: process.execPath, nodeVersion: process.version, powershell: process.execPath, vcvars64: process.execPath }
            });
            const report = JSON.parse(fs.readFileSync(path.join(state.root, generated.reportPath.split("/").join(path.sep)), "utf8"));
            const verificationBytes = fs.readFileSync(path.join(state.root, generated.verificationPath.split("/").join(path.sep)));
            const verification = JSON.parse(verificationBytes.toString("utf8"));
            assert.strictEqual(report.caseResults.length, 5);
            assert.strictEqual(report.summary.passed, 5);
            assert.strictEqual(verification.result, "passed");
            assert.ok(verificationBytes.equals(runner.canonicalBytes(verification)));
        } finally {
            process.chdir(oldCwd);
            Object.keys(previousEnvironment).forEach((name) => {
                if (previousEnvironment[name] === undefined) delete process.env[name];
                else process.env[name] = previousEnvironment[name];
            });
        }
    });
});

test("tracked configuration recovers a report-specific live observation without process environment", () => {
    withFixture(null, (state) => {
        const decoded = runner.decodeConfigurationLiveObservation(state.configuration);
        assert.deepStrictEqual(decoded, state.observation);
        assert.ok(!state.configuration.environment.some((entry) => entry.name.startsWith("CF7_AUDIO_V2_LIVE_OBSERVATION")));

        const swapped = JSON.parse(JSON.stringify(state.configuration));
        const other = JSON.parse(JSON.stringify(state.observation));
        other.reportId = "launcher_affected_regression";
        swapped.argv = [state.environmentValues[NODE_EXE_ENV], RUNNER_REL, "--report-id", state.reportId].concat(runner.encodeLiveObservationArguments(other));
        const oldCwd = process.cwd();
        const previousNode = process.env[NODE_EXE_ENV];
        process.env[NODE_EXE_ENV] = state.environmentValues[NODE_EXE_ENV];
        process.chdir(state.root);
        try {
            assert.throws(() => runner.generateReport({
                candidateRoot: state.candidateRoot,
                configurationPath: writeJson(state.root, state.configurationPath, swapped),
                inputManifestPath: path.join(state.root, state.inputPath.split("/").join(path.sep)),
                outputRoot: state.root,
                reportId: state.reportId
            }, {
                candidateSnapshot: state.candidateSnapshot,
                sourceProbe: () => state.sourceProbe,
                toolchain: { cl: process.execPath, cmd: process.execPath, dotnet: process.execPath, node: process.execPath, nodeVersion: process.version, powershell: process.execPath, vcvars64: process.execPath }
            }), /reportId mismatch/);
        } finally {
            process.chdir(oldCwd);
            if (previousNode === undefined) delete process.env[NODE_EXE_ENV];
            else process.env[NODE_EXE_ENV] = previousNode;
        }
    });
});

test("tracked observation carrier rejects dropped swapped and trailing chunks", () => {
    let state = 0x13579BDF;
    let payload = "";
    for (let index = 0; index < 60000; index++) {
        state ^= state << 13;
        state ^= state >>> 17;
        state ^= state << 5;
        payload += String.fromCharCode(33 + ((state >>> 0) % 94));
    }
    const value = { payload, schema: "cf7.audio-v2.carrier-mutation-fixture.v1" };
    const carrier = runner.encodeLiveObservationArguments(value);
    assert.ok(carrier.length > 2, "fixture must span multiple tracked argv chunks");
    const configuration = { argv: [process.execPath, RUNNER_REL, "--report-id", "fixture"].concat(carrier) };
    assert.deepStrictEqual(runner.decodeConfigurationLiveObservation(configuration), value);

    const dropped = JSON.parse(JSON.stringify(configuration));
    dropped.argv.pop();
    assert.throws(() => runner.decodeConfigurationLiveObservation(dropped), /decoded|canonical|invalid|outside|unexpected|cannot/i);

    const swapped = JSON.parse(JSON.stringify(configuration));
    const firstChunk = swapped.argv[5];
    swapped.argv[5] = swapped.argv[6];
    swapped.argv[6] = firstChunk;
    assert.throws(() => runner.decodeConfigurationLiveObservation(swapped), /decoded|canonical|invalid|cannot/i);

    const encoded = configuration.argv.slice(5).join("");
    const withTrailingByte = Buffer.concat([Buffer.from(encoded, "base64"), Buffer.from([0])]).toString("base64");
    const trailing = JSON.parse(JSON.stringify(configuration));
    trailing.argv = trailing.argv.slice(0, 5);
    for (let offset = 0; offset < withTrailingByte.length; offset += 4000) trailing.argv.push(withTrailingByte.slice(offset, offset + 4000));
    assert.throws(() => runner.decodeConfigurationLiveObservation(trailing), /canonical deflate encoding|trailing bytes/);
});

test("endpoint runtime format stays f32 while capture serialization remains PCM16", () => {
    const runtimeSession = {
        audioReadyGeneration: 1,
        audioSessionId: "01234567-89ab-4cde-8fab-0123456789ab",
        backend: "wasapi",
        channels: 2,
        deviceGeneration: 1,
        deviceIdDigest: "A".repeat(64),
        sampleFormat: "f32",
        sampleRate: 48000
    };
    assert.deepStrictEqual(runner.validateEndpointRuntimeSession(runtimeSession), runtimeSession);

    const captureFormatMasqueradingAsRuntime = Object.assign({}, runtimeSession, { sampleFormat: "s16" });
    assert.throws(
        () => runner.validateEndpointRuntimeSession(captureFormatMasqueradingAsRuntime),
        /runtime sample format must be f32/
    );

    const capture = {
        channels: 2,
        deviceIdDigest: "A".repeat(64),
        sampleRate: 48000,
        selectedBackend: "wasapi"
    };
    const candidateRuntime = Object.assign({}, runtimeSession, { status: "ready" });
    assert.strictEqual(runner.validateCaptureRuntimeTuple(capture, candidateRuntime, "physical route"), candidateRuntime);
    const wrongPhysicalTuple = Object.assign({}, candidateRuntime, { sampleRate: 44100 });
    assert.throws(
        () => runner.validateCaptureRuntimeTuple(capture, wrongPhysicalTuple, "physical route"),
        /backend\/device\/format differs/
    );
    const secondSwitchAfterCapture = Object.assign({}, candidateRuntime, {
        deviceGeneration: 3,
        deviceIdDigest: "B".repeat(64)
    });
    assert.throws(
        () => runner.validateCaptureRuntimeTuple(capture, secondSwitchAfterCapture, "default device switch terminal"),
        /backend\/device\/format differs/
    );
    const hiddenRecoveryOnSameEndpoint = Object.assign({}, candidateRuntime, {
        audioReadyGeneration: 2,
        deviceGeneration: 2
    });
    assert.strictEqual(
        runner.validateCaptureRuntimeTuple(capture, hiddenRecoveryOnSameEndpoint, "physical route"),
        hiddenRecoveryOnSameEndpoint,
        "physical capture tuple alone intentionally cannot detect a same-endpoint recovery");
    assert.throws(
        () => runner.validateStableGenerationTuple(hiddenRecoveryOnSameEndpoint, runtimeSession, "physical route"),
        /undeclared recovery\/generation transition/
    );
});

test("sleep resume facts bind the 15-second target, 30-second hard cap and R4 checks", () => {
    const captures = { device_recovery: {} };
    const validate = (value) => runner.validateEndpointCaseFacts(
        "device_recovery_endpoint_e2e", "sleep_resume", value, captures);
    const facts = {
        captureId: "device_recovery",
        deviceGenerationAfter: 3,
        deviceGenerationBefore: 1,
        maxRecoveryMs: 30000,
        recoveryMs: 15000,
        targetMiss: false,
        targetRecoveryMs: 15000
    };
    assert.doesNotThrow(() => validate(facts));
    assert.deepStrictEqual(
        runner.CASE_CHECKS.device_recovery_endpoint_e2e.sleep_resume,
        ["post_resume_endpoint_pcm_generation_scoped", "recovery_target_15s_hard_cap_30s"]);

    const targetMiss = Object.assign({}, facts, { recoveryMs: 15001, targetMiss: true });
    assert.doesNotThrow(() => validate(targetMiss));
    const hardBoundary = Object.assign({}, facts, { recoveryMs: 30000, targetMiss: true });
    assert.doesNotThrow(() => validate(hardBoundary));

    assert.throws(() => validate(Object.assign({}, facts, { recoveryMs: 30001, targetMiss: true })),
        /target\/hard-cap facts did not recompute exactly/);
    assert.throws(() => validate(Object.assign({}, targetMiss, { targetMiss: false })),
        /target\/hard-cap facts did not recompute exactly/);
});

test("stale recovery facts require exact arm, ordering, generation drop and unchanged counters", () => {
    const facts = {
        armResult: { result: "armed", sent: false },
        audioReadyGenerationAfter: 2, audioReadyGenerationBefore: 1,
        captureId: "device_recovery", closingReadySequence: 6, dispatchSequence: 5,
        playedAfter: 0, playedBefore: 0, preReadyDropsAfter: 0, preReadyDropsBefore: 0,
        recoveringSequence: 4, recoveryDropsAfter: 0, recoveryDropsBefore: 0,
        staleBatchSize: 1, staleGenerationDropsAfter: 1, staleGenerationDropsBefore: 0,
        startFailureCountAfter: 0, startFailureCountBefore: 0,
        throttledCountAfter: 0, throttledCountBefore: 0,
        unknownIdCountAfter: 0, unknownIdCountBefore: 0
    };
    const captures = { device_recovery: {} };
    const validate = (value) => runner.validateEndpointCaseFacts(
        "device_recovery_endpoint_e2e", "no_stale_sfx_after_recovery", value, captures);
    assert.doesNotThrow(() => validate(facts));
    assert.deepStrictEqual(
        runner.CASE_CHECKS.device_recovery_endpoint_e2e.no_stale_sfx_after_recovery,
        ["stale_generation_drop_counter_exact", "stale_sfx_absent_after_recovery"]);

    const wrongArm = JSON.parse(JSON.stringify(facts));
    wrongArm.armResult.sent = true;
    assert.throws(() => validate(wrongArm), /arm result is not exact/);
    const wrongOrder = JSON.parse(JSON.stringify(facts));
    wrongOrder.dispatchSequence = wrongOrder.recoveringSequence;
    assert.throws(() => validate(wrongOrder), /order drifted/);
    const wrongGenerationCounter = JSON.parse(JSON.stringify(facts));
    wrongGenerationCounter.staleGenerationDropsAfter = 0;
    assert.throws(() => validate(wrongGenerationCounter), /generation-drop counter delta drifted/);
    const wrongUnchangedCounter = JSON.parse(JSON.stringify(facts));
    wrongUnchangedCounter.recoveryDropsAfter = 1;
    assert.throws(() => validate(wrongUnchangedCounter), /unchanged counter advanced: recoveryDrops/);
});

test("checked-in dependency closure binds the exact runner bytes", () => {
    const dependencyPath = path.resolve(__dirname, "..", "..", DEPENDENCY_REL.split("/").join(path.sep));
    const dependencyBytes = fs.readFileSync(dependencyPath);
    const manifest = JSON.parse(dependencyBytes.toString("utf8"));
    const runnerBytes = fs.readFileSync(path.join(__dirname, "qualification-runner.js"));
    assert.ok(dependencyBytes.equals(runner.canonicalBytes(manifest)));
    assert.strictEqual(manifest.runnerPath, RUNNER_REL);
    assert.ok(manifest.dependencies.length >= 500);
    const paths = manifest.dependencies.map((entry) => entry.path);
    assert.deepStrictEqual(paths, paths.slice().sort());
    assert.ok(paths.includes("global.json"));
    paths.forEach((relative) => assert.ok(
        runner.isAllowedQualificationDependencyPath(relative),
        "real manifest dependency fails the replay prefix gate: " + relative));
    [
        RUNNER_REL,
        OBSERVER_REL,
        "tools/audio-v2/qualification-observer-client.ps1",
        "tools/audio-v2/qualification-offline-probe.c",
        "launcher/native/audio_bridge_v2.h",
        "launcher/native/miniaudio_bridge.c",
        "launcher/native/tests/audio_bridge_v2_runtime_contract.c",
        "launcher/native/tests/audio_backend_policy_contract.c",
        "launcher/tests/Launcher.Tests.csproj",
        "scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeV2Test.as"
    ].forEach((relative) => assert.ok(paths.includes(relative), "missing dependency " + relative));
    manifest.dependencies.forEach((entry) => {
        const binding = dependencyGenerator.gitCleanBlob(
            path.resolve(__dirname, "..", ".."),
            entry.path);
        assert.deepStrictEqual(entry, {
            blobOid: binding.blobOid,
            bytes: binding.bytes.length,
            path: entry.path,
            sha256: runner.sha256(binding.bytes)
        });
    });
    const runnerEntry = manifest.dependencies.find((entry) => entry.path === RUNNER_REL);
    assert.deepStrictEqual(runnerEntry, { blobOid: runner.gitBlobOid(runnerBytes, 40), bytes: runnerBytes.length, path: RUNNER_REL, sha256: runner.sha256(runnerBytes) });
    assert.strictEqual(manifest.closureSha256, runner.sha256(runner.canonicalBytes(manifest.dependencies)));
});

test("checked-in asset waiver registry is canonical and starts fail-closed empty", () => {
    const waiverPath = path.resolve(__dirname, "..", "..", "config", "audio-v2", "asset-qualification-waivers.v1.json");
    const waiverBytes = fs.readFileSync(waiverPath);
    const waiver = JSON.parse(waiverBytes.toString("utf8"));
    assert.ok(waiverBytes.equals(runner.canonicalBytes(waiver)));
    assert.deepStrictEqual(waiver, {
        schema: "cf7.audio-v2.asset-qualification-waivers.v1",
        waivers: []
    });
});

test("H2 asset qualification selects only the release-source tracked corpus", () => {
    const inventoryPath = path.resolve(__dirname, "..", "..", "config", "audio-v2", "shipped-audio-assets.v1.json");
    const inventory = JSON.parse(fs.readFileSync(inventoryPath, "utf8"));
    const selected = runner.selectTrackedQualificationAssets(inventory);
    assert.strictEqual(selected.tracked.length, 795);
    assert.strictEqual(selected.ignoredSource.length, 32);
    assert.ok(selected.tracked.every((asset) => asset.repositoryState === "tracked"));
    assert.ok(selected.ignoredSource.every((asset) => asset.repositoryState === "ignored_source" && asset.outsideClassification === "source_only"));
    assert.strictEqual(
        inventory.qualificationScope.trackedShippedAssetClosureSha256,
        runner.sha256(runner.canonicalBytes(selected.tracked))
    );

    const drifted = JSON.parse(JSON.stringify(inventory));
    drifted.qualificationScope.h2CompleteGitInventoryTotal++;
    assert.throws(() => runner.selectTrackedQualificationAssets(drifted), /tracked audio inventory count mismatch/);
});

process.stdout.write("qualification-runner tests passed: " + passed + "\n");
