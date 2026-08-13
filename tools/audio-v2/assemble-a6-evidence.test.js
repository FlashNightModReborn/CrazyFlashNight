"use strict";

const assert = require("assert/strict");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");

const assembler = require("./assemble-a6-evidence.js");
const runner = require("./qualification-runner.js");

const RUNNER_PATH = "tools/audio-v2/qualification-runner.js";
const ASSEMBLER_PATH = "tools/audio-v2/assemble-a6-evidence.js";
const ENDPOINT_ENUMERATOR_PATH = "tools/audio-v2/list-playback-endpoints.ps1";
const SUITE_PATH = "scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeV2Test.as";

function execute(file, args, cwd) {
    const value = cp.spawnSync(file, args, { cwd, encoding: "utf8", maxBuffer: 16 * 1024 * 1024, windowsHide: true });
    if (value.error || value.status !== 0) throw new Error((value.error && value.error.message) || value.stderr || (file + " failed"));
    return value.stdout.trim();
}

function write(root, relative, bytes) {
    const target = path.join(root, ...relative.split("/"));
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, bytes);
    return target;
}

function writeCanonical(root, relative, value) {
    return write(root, relative, runner.canonicalBytes(value));
}

function copyCurrent(root, relative) {
    // __dirname is tools/audio-v2, so paths outside tools require the checkout root.
    const checkoutRoot = path.resolve(__dirname, "..", "..");
    const actual = path.join(checkoutRoot, ...relative.split("/"));
    return write(root, relative, fs.readFileSync(actual));
}

function descriptor(root, relative) {
    const bytes = fs.readFileSync(path.join(root, ...relative.split("/")));
    return {
        blobOid: runner.gitBlobOid(bytes, 40),
        bytes: bytes.length,
        path: relative,
        sha256: runner.sha256(bytes)
    };
}

function sourceFixture() {
    const outer = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-a6-assembler-test-"));
    const sourceRoot = path.join(outer, "source");
    const candidateRoot = path.join(outer, "candidate");
    const externalRoot = path.join(outer, "external");
    fs.mkdirSync(sourceRoot);
    fs.mkdirSync(candidateRoot);
    fs.mkdirSync(externalRoot);
    execute("git", ["init", "--quiet"], sourceRoot);
    execute("git", ["config", "core.autocrlf", "false"], sourceRoot);
    execute("git", ["config", "user.name", "Audio V2 Assembler Test"], sourceRoot);
    execute("git", ["config", "user.email", "audio-v2-test@example.invalid"], sourceRoot);

    const sourcePaths = new Set([
        ASSEMBLER_PATH,
        ENDPOINT_ENUMERATOR_PATH,
        RUNNER_PATH,
        "tools/audio-v2/qualification-observer.js",
        "tools/audio-v2/qualification-observer-client.ps1",
        SUITE_PATH,
        "config/build/runtime-inputs.v2.json",
        assembler.DEPENDENCY_MANIFEST_PATH,
        "docs/evidence/audio-v2/.keep",
        "fixture-domain/artifact.txt",
        "fixture-domain/producer.txt",
        "fixture-domain/toolchain.txt"
    ]);
    Object.values(assembler.ROLE_PATHS).forEach((roles) => Object.values(roles).forEach((relative) => sourcePaths.add(relative)));
    assembler.REQUIRED_QUALIFICATION_DEPENDENCIES.forEach((relative) => sourcePaths.add(relative));
    sourcePaths.forEach((relative) => {
        if ([ASSEMBLER_PATH, ENDPOINT_ENUMERATOR_PATH, RUNNER_PATH].includes(relative)) copyCurrent(sourceRoot, relative);
        else write(sourceRoot, relative, Buffer.from("fixture source: " + relative + "\n", "utf8"));
    });

    const assetCases = runner.REPORT_CASES.asset_offline_eof_qualification;
    writeCanonical(sourceRoot, assembler.ROLE_PATHS.asset_offline_eof_qualification.decoder_fixture_inventory, {
        fixtures: assetCases.slice(1).map((caseId, index) => ({ caseId, fixtureId: "fixture-" + String(index).padStart(2, "0") })),
        schema: "cf7.audio-v2.decoder-fixture-inventory.v1"
    });
    writeCanonical(sourceRoot, assembler.ROLE_PATHS.asset_offline_eof_qualification.shipped_audio_corpus_inventory, {
        assets: [
            { path: "music/test-a.wav", repositoryState: "tracked" },
            { path: "sounds/test-b.wav", repositoryState: "tracked" }
        ],
        schema: "cf7.audio-v2.shipped-audio-assets.v1"
    });

    const assertionNames = Array.from({ length: 80 }, (_, index) => "assembler_assertion_" + String(index).padStart(3, "0"));
    write(sourceRoot, SUITE_PATH, Buffer.from(assertionNames.map((name) => "assertTrue(\"" + name + "\");").join("\n") + "\n", "utf8"));
    write(sourceRoot, "scripts/asLoader.swf", Buffer.from("FWS-fixture-published-swf", "ascii"));

    writeCanonical(sourceRoot, "config/build/runtime-inputs.v2.json", {
        domains: {
            artifactSource: { fixedFiles: ["fixture-domain/artifact.txt"], trees: [] },
            producerRecipe: { fixedFiles: ["fixture-domain/producer.txt"], trees: [] },
            toolchainLock: { fixedFiles: ["fixture-domain/toolchain.txt"], trees: [] }
        },
        schema: "cf7-runtime-inputs.v2"
    });

    const dependencyPaths = Array.from(new Set([
        RUNNER_PATH,
        "tools/audio-v2/qualification-observer.js",
        "tools/audio-v2/qualification-observer-client.ps1"
    ].concat(assembler.REQUIRED_QUALIFICATION_DEPENDENCIES))).sort();
    const dependencies = dependencyPaths.map((relative) => descriptor(sourceRoot, relative));
    writeCanonical(sourceRoot, assembler.DEPENDENCY_MANIFEST_PATH, {
        closureSha256: runner.sha256(runner.canonicalBytes(dependencies)),
        dependencies,
        runnerPath: RUNNER_PATH,
        schema: "cf7.audio-v2.qualification-runner-dependencies.v1"
    });

    execute("git", ["add", "--all"], sourceRoot);
    execute("git", ["commit", "--quiet", "-m", "assembler fixture"], sourceRoot);
    const sourceCommit = execute("git", ["rev-parse", "HEAD"], sourceRoot);
    const sourceTree = execute("git", ["rev-parse", "HEAD^{tree}"], sourceRoot);
    const sourceDomains = assembler.runtimeSourceDomainHashes(sourceRoot, sourceCommit);

    const runtimeRoot = path.join(candidateRoot, "runtime");
    fs.mkdirSync(runtimeRoot);
    write(candidateRoot, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", Buffer.from("fixture Core DLL", "utf8"));
    write(candidateRoot, "runtime/miniaudio.dll", Buffer.from("fixture miniaudio DLL", "utf8"));
    const payloadFiles = [
        descriptor(candidateRoot, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll"),
        descriptor(candidateRoot, "runtime/miniaudio.dll")
    ].map(({ bytes, path: relative, sha256 }) => ({ bytes, path: relative, sha256 }));
    const payloadClosure = runner.runtimePayloadClosureHash(payloadFiles);
    const buildIdentity = runner.runtimeBuildIdentityHash(sourceDomains.artifactSourceHash, sourceDomains.producerRecipeHash, sourceDomains.toolchainLockHash);
    const manifestLines = [
        "cf7-runtime-manifest-v2",
        "artifactSourceHash\t" + sourceDomains.artifactSourceHash,
        "buildIdentityHash\t" + buildIdentity,
        "payloadClosureHash\t" + payloadClosure,
        "producerRecipeHash\t" + sourceDomains.producerRecipeHash,
        "publishMode\tframework-dependent",
        "toolchainBaseline\tassembler-test",
        "toolchainLockHash\t" + sourceDomains.toolchainLockHash
    ].concat(payloadFiles.map((entry) => ["file", entry.path, entry.bytes, entry.sha256].join("\t")));
    write(candidateRoot, "runtime/cf7-runtime-manifest.tsv", Buffer.from(manifestLines.join("\n") + "\n", "utf8"));
    const candidate = assembler.inspectCandidate(candidateRoot, sourceDomains).candidate;

    const toolDescriptors = {};
    ["cl", "cmd", "dotnet", "powershell", "vcvars64"].forEach((name) => {
        const file = write(externalRoot, "tools/" + name + ".bin", Buffer.from("tool " + name + "\n", "utf8"));
        const real = fs.realpathSync.native(file);
        toolDescriptors[name] = { path: real, sha256: runner.sha256(fs.readFileSync(real)) };
    });
    const nodePath = fs.realpathSync.native(process.execPath);
    toolDescriptors.node = {
        path: nodePath,
        sha256: runner.sha256(fs.readFileSync(nodePath))
    };
    const toolchainJson = writeCanonical(externalRoot, "toolchain.json", {
        cl: toolDescriptors.cl,
        cmd: toolDescriptors.cmd,
        dotnet: toolDescriptors.dotnet,
        msvcToolsVersion: "test-msvc",
        node: toolDescriptors.node,
        nodeVersion: process.version,
        powershell: toolDescriptors.powershell,
        schema: "cf7.audio-v2.qualification-toolchain.v1",
        vcvars64: toolDescriptors.vcvars64,
        windowsSdkVersion: "test-sdk"
    });

    const nowMs = Date.now();
    const trace = assertionNames.map((name) => "[PASS] " + name).concat([
        "AudioBridgeV2Test Tests Passed: " + assertionNames.length,
        "AudioBridgeV2Test Tests Failed: 0"
    ]).join("\n") + "\n";
    const as2FreshTrace = write(externalRoot, "fresh-as2-trace.log", Buffer.from(trace, "utf8"));
    fs.utimesSync(as2FreshTrace, new Date(nowMs), new Date(nowMs));

    const endpointArgv = {};
    assembler.ENDPOINT_REPORT_IDS.forEach((reportId) => {
        endpointArgv[reportId] = write(externalRoot, reportId + ".argv.json", runner.canonicalBytes([]));
    });
    const runId = "0123456789abcdef0123456789abcdef";
    const releaseSource = { commit: sourceCommit, treeOid: sourceTree };
    const journal = { events: [], firstSequence: 0, lastSequence: 0, sha256: "A".repeat(64) };
    function endpointCarrier(reportId) {
        const caseFacts = runner.REPORT_CASES[reportId].map((caseId) => ({
            caseId,
            facts: caseId === "default_device_switch" ? {
                deviceGenerationAfter: 3,
                deviceGenerationBefore: 2,
                newDeviceIdDigest: "B".repeat(64),
                oldDeviceIdDigest: "C".repeat(64)
            } : {}
        }));
        return {
            candidate: { buildIdentity: candidate.buildIdentity, payloadClosure: candidate.payloadClosure },
            journal,
            observation: {
                candidateBuildIdentity: candidate.buildIdentity,
                candidatePayloadClosure: candidate.payloadClosure,
                candidateProcess: { executableSha256: "D".repeat(64), observedAtUtc: new Date(nowMs).toISOString(), pid: 42, processStartUtc: new Date(nowMs - 1000).toISOString() },
                caseFacts,
                generatedAtUtc: new Date(nowMs).toISOString(),
                releaseSource,
                reportId,
                runId,
                schema: "cf7.audio-v2.live-observation.v2",
                session: {
                    audioReadyGeneration: 3,
                    audioSessionId: "assembler-test-session",
                    backend: "wasapi",
                    channels: 2,
                    deviceGeneration: 3,
                    deviceIdDigest: "B".repeat(64),
                    sampleFormat: "f32",
                    sampleRate: 48000
                }
            },
            schema: "cf7.audio-v2.candidate-journal-carrier.v2"
        };
    }
    function loadEndpointArgv(reportId, _file, _candidate, _source, boundNodeExe) {
        const carrier = endpointCarrier(reportId);
        return {
            argv: [boundNodeExe, RUNNER_PATH, "--report-id", reportId].concat(runner.encodeLiveObservationArguments(carrier)),
            carrier
        };
    }
    const environment = {
        NUGET_PACKAGES: path.join(externalRoot, "nuget"),
        SystemRoot: process.env.SystemRoot || "C:\\Windows",
        TEMP: path.join(externalRoot, "temp"),
        TMP: path.join(externalRoot, "tmp")
    };
    const options = {
        as2FreshTrace: fs.realpathSync.native(as2FreshTrace),
        candidateRoot: fs.realpathSync.native(candidateRoot),
        endpointArgv: Object.fromEntries(Object.entries(endpointArgv).map(([key, value]) => [key, fs.realpathSync.native(value)])),
        environment,
        nowMs,
        outputRoot: fs.realpathSync.native(sourceRoot),
        runId,
        sourceCommit,
        sourceTree,
        toolchainJson: fs.realpathSync.native(toolchainJson)
    };
    const dependencyOverrides = {
        allowNonCwd: true,
        endpointCarrierValidator(value) { return value; },
        loadEndpointArgv
    };
    return { candidate, dependencyOverrides, endpointCarrier, options, outer, releaseSource, runId, sourceRoot, toolDescriptors };
}

function removeFixture(fixture) {
    assert.ok(fixture.outer.startsWith(path.resolve(os.tmpdir()) + path.sep));
    fs.rmSync(fixture.outer, { recursive: true, force: true });
}

function allFiles(root) {
    const result = [];
    function walk(directory, base) {
        fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
            const relative = base ? base + "/" + entry.name : entry.name;
            if (entry.isDirectory()) walk(path.join(directory, entry.name), relative);
            else result.push(relative);
        });
    }
    walk(root, "");
    return result.sort();
}

test("CLI is explicit, fail-closed, and separates prepare-only inputs", () => {
    assert.throws(() => assembler.parseCli([]), /first argument/);
    assert.throws(() => assembler.parseCli(["prepare"]), /missing required flag/);
    assert.throws(() => assembler.parseCli(["validate", "--source-commit", "a".repeat(40), "--source-tree", "b".repeat(40), "--candidate-root", "relative", "--output-root", "relative", "--toolchain-json", "relative"]), /must be absolute/);
    assert.throws(() => assembler.parseCli(["validate", "--source-commit", "a".repeat(40), "--source-tree", "b".repeat(40), "--candidate-root", path.resolve("candidate"), "--output-root", path.resolve("source"), "--toolchain-json", path.resolve("toolchain"), "--run-id", "0".repeat(32)]), /prepare-only flags/);
    assert.doesNotThrow(() => assembler.validateRoleMatrix());
    assembler.ENDPOINT_REPORT_IDS.forEach((reportId) => assert.equal(assembler.ROLE_PATHS[reportId][reportId === "exact_candidate_bgm_endpoint_e2e" ? "bgm_endpoint_run_plan" : reportId === "exact_candidate_sfx_endpoint_e2e" ? "sfx_endpoint_run_plan" : "device_recovery_run_plan"], "tools/audio-v2/qualification-operator.js"));
});

test("toolchain requires exact Node path hash and version", () => {
    const fixture = sourceFixture();
    try {
        const accepted = assembler.validateToolchain(fixture.options.toolchainJson);
        assert.equal(accepted.value.node.path, fs.realpathSync.native(process.execPath));
        assert.equal(accepted.value.nodeVersion, process.version);

        function rejected(name, mutate, pattern) {
            const value = JSON.parse(fs.readFileSync(fixture.options.toolchainJson, "utf8"));
            mutate(value);
            const file = writeCanonical(path.dirname(fixture.options.toolchainJson), name, value);
            assert.throws(() => assembler.validateToolchain(fs.realpathSync.native(file)), pattern);
        }
        rejected("toolchain-missing-node.json", (value) => { delete value.node; }, /keys differ/);
        rejected("toolchain-relative-node.json", (value) => { value.node.path = "node"; }, /descriptor invalid/);
        rejected("toolchain-node-hash-drift.json", (value) => { value.node.sha256 = "A".repeat(64); }, /SHA drift/);
        rejected("toolchain-node-version-drift.json", (value) => { value.nodeVersion = "v0.0.0"; }, /version output drifted/);
    } finally {
        removeFixture(fixture);
    }
});

test("prepare atomically creates nine source/candidate-bound configurations and HUMAN_REQUIRED drafts", () => {
    const fixture = sourceFixture();
    try {
        const driftedEndpoints = Object.fromEntries(assembler.ENDPOINT_REPORT_IDS.map((reportId) => [reportId, { argv: [], carrier: fixture.endpointCarrier(reportId) }]));
        driftedEndpoints.exact_candidate_sfx_endpoint_e2e.carrier.observation.session.sampleRate = 44100;
        assert.throws(() => assembler.validateEndpointSet(driftedEndpoints, fixture.candidate, fixture.releaseSource, fixture.runId), /physical runtime tuple drift/);
        const result = assembler.prepareArtifacts(fixture.options, fixture.dependencyOverrides);
        assert.equal(result.result, "prepared_HUMAN_REQUIRED");
        assert.equal(result.promotionAuthorized, false);
        const prepared = path.join(fixture.sourceRoot, ...assembler.PREPARED_ROOT.split("/"));
        assert.equal(allFiles(prepared).length, 21);
        assert.deepEqual(allFiles(prepared).filter((entry) => entry.startsWith("config/")).length, 9);
        assert.deepEqual(allFiles(prepared).filter((entry) => entry.startsWith("inputs/")).length, 9);
        assert.equal(fs.existsSync(path.join(fixture.sourceRoot, "docs", "evidence", "audio-v2", "reports")), false);
        assert.equal(fs.existsSync(path.join(fixture.sourceRoot, "docs", "evidence", "audio-v2", "cases")), false);

        assembler.REPORT_IDS.forEach((reportId) => {
            const configuration = JSON.parse(fs.readFileSync(path.join(prepared, "config", reportId + ".json"), "utf8"));
            const input = JSON.parse(fs.readFileSync(path.join(prepared, "inputs", reportId + ".json"), "utf8"));
            assert.equal(configuration.reportId, reportId);
            assert.equal(configuration.argv[0], fs.realpathSync.native(process.execPath));
            assert.ok(configuration.environment.some((entry) => entry.name === "CF7_NODE_EXE" && entry.valueSha256 === runner.sha256(Buffer.from(configuration.argv[0], "utf8"))));
            assert.deepEqual(input.inputs.map((entry) => entry.kind + ":" + entry.path), input.inputs.map((entry) => entry.kind + ":" + entry.path).slice().sort());
            assert.deepEqual(input.inputs.map((entry) => entry.role).sort(), runner.REPORT_INPUT_ROLES[reportId].slice().sort());
            const decoded = runner.decodeConfigurationLiveObservation(configuration);
            if (assembler.ENDPOINT_REPORT_IDS.includes(reportId)) {
                assert.equal(decoded.schema, "cf7.audio-v2.candidate-journal-carrier.v2");
                assert.deepEqual(decoded.journal, fixture.endpointCarrier(reportId).journal);
            } else {
                assert.equal(decoded.reportId, reportId);
                assert.equal(decoded.candidateProcess, null);
            }
        });

        const draft = JSON.parse(fs.readFileSync(path.join(prepared, "drafts", "a6-evidence-manifest.HUMAN_REQUIRED.json"), "utf8"));
        assert.equal(draft.schema, "cf7.audio-v2.a6-evidence-manifest-draft.v1");
        assert.equal(draft.status, "HUMAN_REQUIRED");
        assert.equal(draft.promotionAuthorized, false);
        assert.equal(draft.device.audioDeviceQualified, false);
        assert.equal(draft.listeningMatrix.allPassed, false);
        assert.deepEqual(draft.qualificationDependencies.requiredSources.map((entry) => entry.path), assembler.REQUIRED_QUALIFICATION_DEPENDENCIES);
        assert.equal(draft.qualificationPreparation.assembler.path, ASSEMBLER_PATH);
        assert.equal(draft.qualificationPreparation.endpointEnumerator.path, ENDPOINT_ENUMERATOR_PATH);
        const serializedDrafts = fs.readFileSync(path.join(prepared, "drafts", "candidate-verification.HUMAN_REQUIRED.json"), "utf8") +
            fs.readFileSync(path.join(prepared, "drafts", "human-listening-matrix.HUMAN_REQUIRED.json"), "utf8") + JSON.stringify(draft);
        assert.doesNotMatch(serializedDrafts, /"result":"(?:passed|ok|success)"/i);

        const validation = assembler.validatePrepared(fixture.options, fixture.dependencyOverrides);
        assert.equal(validation.result, "validated_HUMAN_REQUIRED");
        const plan = assembler.runnerCommandPlan(fixture.options, fixture.dependencyOverrides);
        assert.equal(plan.commands.length, 9);
        assert.equal(plan.promotionAuthorized, false);
        assert.ok(plan.commands.every((entry) => entry.stopOnNonzeroExit === true && entry.argv[0] === fs.realpathSync.native(process.execPath) && entry.argv[1] === RUNNER_PATH));
        assert.equal(plan.environment.CF7_NODE_EXE, fs.realpathSync.native(process.execPath));
        assert.ok(!Object.prototype.hasOwnProperty.call(plan.environment, "PATH"));
        assert.deepEqual(fs.readdirSync(path.join(fixture.sourceRoot, "docs", "evidence", "audio-v2")).sort(), [".keep", "a6-prepared"]);

        draft.status = "ACCEPTED";
        fs.writeFileSync(path.join(prepared, "drafts", "a6-evidence-manifest.HUMAN_REQUIRED.json"), runner.canonicalBytes(draft));
        assert.throws(() => assembler.validatePrepared(fixture.options, fixture.dependencyOverrides), /draft can be mistaken|HUMAN_REQUIRED/);
    } finally {
        removeFixture(fixture);
    }
});

test("a failure after staging publishes no evidence residue", () => {
    const fixture = sourceFixture();
    try {
        const failing = Object.assign({}, fixture.dependencyOverrides, {
            endpointCarrierValidator() { throw new Error("injected staged carrier rejection"); }
        });
        assert.throws(() => assembler.prepareArtifacts(fixture.options, failing), /injected staged carrier rejection/);
        const evidenceRoot = path.join(fixture.sourceRoot, "docs", "evidence", "audio-v2");
        assert.deepEqual(fs.readdirSync(evidenceRoot), [".keep"]);
        assert.deepEqual(fs.readdirSync(fixture.sourceRoot).filter((entry) => entry.startsWith(".cf7-audio-v2-a6-staging-")), []);
    } finally {
        removeFixture(fixture);
    }
});

test("stale AS2 trace and candidate byte drift fail before publication", () => {
    const stale = sourceFixture();
    try {
        const old = new Date(stale.options.nowMs - (16 * 60 * 1000));
        fs.utimesSync(stale.options.as2FreshTrace, old, old);
        assert.throws(() => assembler.prepareArtifacts(stale.options, stale.dependencyOverrides), /older than 15 minutes/);
        assert.equal(fs.existsSync(path.join(stale.sourceRoot, ...assembler.PREPARED_ROOT.split("/"))), false);
    } finally {
        removeFixture(stale);
    }

    const tampered = sourceFixture();
    try {
        fs.appendFileSync(path.join(tampered.options.candidateRoot, "runtime", "miniaudio.dll"), "tampered");
        assert.throws(() => assembler.prepareArtifacts(tampered.options, tampered.dependencyOverrides), /manifest differs from exact full payload/);
        assert.equal(fs.existsSync(path.join(tampered.sourceRoot, ...assembler.PREPARED_ROOT.split("/"))), false);
    } finally {
        removeFixture(tampered);
    }
});
