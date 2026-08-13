#!/usr/bin/env node
"use strict";

// Audio Platform v2 A6 evidence preparation helper.
//
// This tool deliberately stops before E1.  It prepares the nine recoverable
// runner configurations/input manifests and HUMAN_REQUIRED drafts only.  The
// frozen final schemas require positive human/candidate verdicts, so this tool
// never writes those schemas, never writes a passed listening result, and never
// authorizes promotion.

const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const runner = require("./qualification-runner.js");
const observer = require("./qualification-observer.js");

const RUNNER_PATH = "tools/audio-v2/qualification-runner.js";
const ASSEMBLER_PATH = "tools/audio-v2/assemble-a6-evidence.js";
const ENDPOINT_ENUMERATOR_PATH = "tools/audio-v2/list-playback-endpoints.ps1";
const DEPENDENCY_MANIFEST_PATH = "config/audio-v2/qualification-runner-dependencies.v1.json";
const AS2_SUITE_PATH = "scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeV2Test.as";
const PREPARED_ROOT = "docs/evidence/audio-v2/a6-prepared";
const TOOLCHAIN_ENV = "CF7_AUDIO_V2_TOOLCHAIN_B64";
const NODE_EXE_ENV = "CF7_NODE_EXE";
const MAX_FILE_BYTES = 512 * 1024 * 1024;
const MAX_JSON_BYTES = 16 * 1024 * 1024;
const MAX_TRACE_AGE_MS = 15 * 60 * 1000;

const REPORT_IDS = Object.freeze([
    "asset_offline_eof_qualification",
    "native_abi_decoder_lifecycle",
    "production_backend_device_fault_injection",
    "csharp_capability_catalog_bridge",
    "as2_wire_publish",
    "launcher_affected_regression",
    "exact_candidate_bgm_endpoint_e2e",
    "exact_candidate_sfx_endpoint_e2e",
    "device_recovery_endpoint_e2e"
]);

const SOURCE_REPORT_IDS = new Set(REPORT_IDS.slice(0, 6));
const ENDPOINT_REPORT_IDS = Object.freeze(REPORT_IDS.slice(6));
const CANDIDATE_INPUTS = Object.freeze({
    "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll": "candidate_core",
    "runtime/cf7-runtime-manifest.tsv": "candidate_runtime_manifest",
    "runtime/miniaudio.dll": "candidate_miniaudio"
});

// These are execution/fixture/qualification-only sources which must be inside
// the runner's reviewed replay closure before preparation is allowed.  The
// dependency generator remains the sole owner of that manifest; this assembler
// only verifies the exact-S manifest and records the bound source descriptors.
const REQUIRED_QUALIFICATION_DEPENDENCIES = Object.freeze([
    "launcher/src/Audio/AudioQualificationStimulusV1.cs",
    "launcher/tests/Audio/AudioQualificationStimulusV1Tests.cs",
    "scripts/类定义/org/flashNight/arki/audio/AudioQualificationStimulus.as",
    "tools/audio-v2/materialize-qualification-fixtures.js",
    "tools/audio-v2/materialize-qualification-fixtures.test.js",
    "tools/audio-v2/qualification-operator.js",
    "tools/audio-v2/qualification-operator.test.js",
    "tools/audio-v2/qualification-stimulus-client.ps1",
    "tools/audio-v2/qualification-stimulus-client.tests.ps1",
    "tools/audio-v2/write-qualification-toolchain.ps1",
    "tools/audio-v2/write-qualification-toolchain.tests.ps1"
]);

// Each role is bound to one real S blob.  The runner consumes three of these
// blobs directly; the remaining rows are provenance anchors for the exact
// implementation/test plan named by the accepted R2 role matrix.
const ROLE_PATHS = Object.freeze({
    asset_offline_eof_qualification: Object.freeze({
        decoder_fixture_inventory: "tools/audio-v2/qualification-decoder-fixtures.v1.json",
        decoder_lock_or_capability_manifest: "launcher/native/decoder-dependencies.lock.v1.json",
        shipped_audio_corpus_inventory: "config/audio-v2/shipped-audio-assets.v1.json"
    }),
    native_abi_decoder_lifecycle: Object.freeze({
        decoder_dependency_lock: "launcher/native/decoder-dependencies.lock.v1.json",
        native_abi_contract: "launcher/native/audio_bridge_v2.h",
        native_lifecycle_test_plan: "launcher/native/tests/audio_bridge_v2_runtime_contract.c"
    }),
    production_backend_device_fault_injection: Object.freeze({
        backend_policy_source: "launcher/native/audio_backend_policy.c",
        device_fault_injection_plan: "launcher/native/tests/audio_backend_policy_contract.c",
        no_output_product_policy: "launcher/src/Audio/AudioCoordinator.cs"
    }),
    csharp_capability_catalog_bridge: Object.freeze({
        bridge_protocol_contract: "launcher/src/Audio/AudioWireV2.cs",
        catalog_contract: "launcher/src/Audio/MusicCatalog.cs",
        csharp_audio_source_closure: "config/audio-v2/qualification-runner-dependencies.v1.json"
    }),
    as2_wire_publish: Object.freeze({
        as2_audio_source_closure: "scripts/run-audio-v2-tests.ps1",
        as2_publish_plan: "scripts/asLoader.swf",
        wire_protocol_contract: "scripts/类定义/org/flashNight/arki/audio/AudioBridge.as"
    }),
    launcher_affected_regression: Object.freeze({
        jukebox_harness_source: "tools/run-jukebox-harness.js",
        launcher_test_manifest: "launcher/tests/Launcher.Tests.csproj",
        shutdown_test_plan: "launcher/tests/Audio/AudioCoordinatorTests.cs"
    }),
    exact_candidate_bgm_endpoint_e2e: Object.freeze({
        bgm_endpoint_run_plan: "tools/audio-v2/qualification-operator.js",
        bgm_fixture_inventory: "tools/audio-v2/qualification-decoder-fixtures.v1.json",
        candidate_execution_contract: "automation/start.ps1"
    }),
    exact_candidate_sfx_endpoint_e2e: Object.freeze({
        candidate_execution_contract: "automation/start.ps1",
        sfx_endpoint_run_plan: "tools/audio-v2/qualification-operator.js",
        sfx_fixture_inventory: "config/audio-v2/shipped-audio-assets.v1.json"
    }),
    device_recovery_endpoint_e2e: Object.freeze({
        candidate_execution_contract: "automation/start.ps1",
        device_recovery_run_plan: "tools/audio-v2/qualification-operator.js",
        device_route_contract: "launcher/src/Audio/AudioQualificationDiagnosticsV1.cs"
    })
});

const LISTENING_CAPTURE_IDS = Object.freeze({
    formats_shipped_and_new: ["bgm_playback"],
    bgm_transport_and_crossfade: ["bgm_playback"],
    dense_sfx_overlap_and_throttle: ["sfx_playback"],
    bgm_sfx_simultaneous: ["bgm_sfx_mix"],
    gain_zero_default_max: ["bgm_playback", "sfx_playback"],
    default_device_switch: ["device_recovery"],
    physical_route_bluetooth_or_hdmi: ["device_recovery"],
    sleep_resume: ["device_recovery"],
    quality_pop_latency_channel_loudness: ["bgm_playback", "bgm_sfx_mix", "device_recovery", "sfx_playback"],
    no_stale_sfx_after_recovery: ["device_recovery"]
});

class A6AssemblerError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
    }
}

function fail(code, message) {
    throw new A6AssemblerError(code, message);
}

function expect(condition, message, code) {
    if (!condition) fail(code || "VALIDATION_FAILED", message);
}

function exactKeys(value, keys, label) {
    expect(value && typeof value === "object" && !Array.isArray(value), label + " must be an object");
    expect(JSON.stringify(Object.keys(value).sort()) === JSON.stringify(keys.slice().sort()), label + " keys differ");
}

function samePath(left, right) {
    const a = path.resolve(left);
    const b = path.resolve(right);
    return process.platform === "win32" ? a.toLowerCase() === b.toLowerCase() : a === b;
}

function openRealDirectory(value, label) {
    expect(path.isAbsolute(value), label + " must be absolute");
    const resolved = path.resolve(value);
    const stat = fs.lstatSync(resolved);
    expect(stat.isDirectory() && !stat.isSymbolicLink(), label + " must be a real directory");
    const real = fs.realpathSync.native(resolved);
    expect(samePath(real, resolved), label + " must use its canonical real path");
    return real;
}

function safeRelative(value, label) {
    expect(typeof value === "string" && value.length > 0 && value.length <= 4096, label + " invalid");
    const segments = value.split("/");
    expect(!path.isAbsolute(value) && !/[\\\0\t\r\n:*?"<>|]/.test(value) && segments.every((entry) => entry && entry !== "." && entry !== ".."), label + " unsafe");
    return value;
}

function containedPath(root, relative, label) {
    safeRelative(relative, label);
    const absolute = path.resolve(root, relative.split("/").join(path.sep));
    const prefix = path.resolve(root) + path.sep;
    const a = process.platform === "win32" ? absolute.toLowerCase() : absolute;
    const p = process.platform === "win32" ? prefix.toLowerCase() : prefix;
    expect(a.startsWith(p), label + " escapes root");
    return absolute;
}

function readRegularFile(file, label, maximumBytes) {
    expect(path.isAbsolute(file), label + " path must be absolute");
    const stat = fs.lstatSync(file);
    expect(stat.isFile() && !stat.isSymbolicLink(), label + " must be a regular non-link file");
    expect(stat.size > 0 && stat.size <= (maximumBytes || MAX_FILE_BYTES), label + " size outside bound");
    const real = fs.realpathSync.native(file);
    expect(samePath(real, file), label + " path must be canonical");
    const bytes = fs.readFileSync(real);
    expect(bytes.length === stat.size, label + " changed while being read");
    return { bytes, stat };
}

function parseCanonicalJsonFile(file, label) {
    const binding = readRegularFile(file, label, MAX_JSON_BYTES);
    let value;
    try { value = JSON.parse(binding.bytes.toString("utf8")); }
    catch (error) { fail("VALIDATION_FAILED", label + " is invalid UTF-8 JSON: " + error.message); }
    expect(binding.bytes.equals(runner.canonicalBytes(value)), label + " is not canonical sorted JSON");
    return { bytes: binding.bytes, stat: binding.stat, value };
}

function git(root, args, encoding) {
    const executed = cp.spawnSync("git", args, {
        cwd: root,
        encoding: encoding === null ? null : "utf8",
        maxBuffer: MAX_FILE_BYTES,
        windowsHide: true
    });
    if (executed.error || executed.status !== 0) {
        const detail = executed.error ? executed.error.message : Buffer.isBuffer(executed.stderr) ? executed.stderr.toString("utf8") : executed.stderr;
        fail("PREREQUISITE_MISSING", "git " + args.join(" ") + " failed: " + String(detail || "exit " + executed.status).trim());
    }
    return executed.stdout;
}

function gitObjectBinding(root, commit, relative) {
    safeRelative(relative, "Git source path");
    const bytes = git(root, ["show", commit + ":" + relative], null);
    expect(Buffer.isBuffer(bytes) && bytes.length > 0, "Git source blob is empty: " + relative);
    const blobOid = String(git(root, ["rev-parse", commit + ":" + relative])).trim();
    expect(/^[a-f0-9]{40,64}$/.test(blobOid), "Git blob OID invalid: " + relative);
    return { blobOid, bytes, path: relative, sha256: runner.sha256(bytes) };
}

function gitObjectBindings(root, commit, relatives) {
    expect(Array.isArray(relatives) && relatives.length > 0 && new Set(relatives).size === relatives.length, "Git batch paths must be a non-empty unique array");
    relatives.forEach((relative) => safeRelative(relative, "Git batch source path"));
    const executed = cp.spawnSync("git", ["cat-file", "--batch"], {
        cwd: root,
        encoding: null,
        input: Buffer.from(relatives.map((relative) => commit + ":" + relative).join("\n") + "\n", "utf8"),
        maxBuffer: MAX_FILE_BYTES,
        windowsHide: true
    });
    if (executed.error || executed.status !== 0) {
        const detail = executed.error ? executed.error.message : Buffer.from(executed.stderr || []).toString("utf8");
        fail("PREREQUISITE_MISSING", "git cat-file --batch failed: " + String(detail || "exit " + executed.status).trim());
    }
    const output = Buffer.from(executed.stdout || []);
    const result = {};
    let offset = 0;
    relatives.forEach((relative) => {
        const lineEnd = output.indexOf(0x0A, offset);
        expect(lineEnd > offset, "Git batch header missing for " + relative);
        const header = output.subarray(offset, lineEnd).toString("ascii");
        const match = /^([a-f0-9]{40,64}) blob ([0-9]+)$/.exec(header);
        expect(match, "Git batch object is absent or not a blob: " + relative);
        const size = Number(match[2]);
        expect(Number.isSafeInteger(size) && size > 0 && size <= MAX_FILE_BYTES, "Git batch blob size invalid: " + relative);
        const start = lineEnd + 1;
        const end = start + size;
        expect(end < output.length && output[end] === 0x0A, "Git batch blob framing invalid: " + relative);
        const bytes = Buffer.from(output.subarray(start, end));
        result[relative] = { blobOid: match[1], bytes, path: relative, sha256: runner.sha256(bytes) };
        offset = end + 1;
    });
    expect(offset === output.length, "Git batch returned trailing data");
    return result;
}

function validateReleaseSource(root, commit, tree, allowPrepared) {
    expect(/^[a-f0-9]{40}$/.test(commit), "source commit must be a full lowercase SHA-1 OID");
    expect(/^[a-f0-9]{40,64}$/.test(tree), "source tree OID invalid");
    const resolvedCommit = String(git(root, ["rev-parse", "--verify", commit + "^{commit}"])).trim();
    const resolvedTree = String(git(root, ["rev-parse", commit + "^{tree}"])).trim();
    const head = String(git(root, ["rev-parse", "HEAD"])).trim();
    expect(resolvedCommit === commit && head === commit, "working tree HEAD is not exact source commit");
    expect(resolvedTree === tree, "source tree OID mismatch");
    const status = String(git(root, ["status", "--porcelain=v1", "--untracked-files=all"]));
    const lines = status.split(/\r?\n/).filter(Boolean);
    if (allowPrepared) {
        lines.forEach((line) => {
            const value = line.slice(3).replace(/\\/g, "/");
            expect(value === PREPARED_ROOT || value.startsWith(PREPARED_ROOT + "/"), "non-prepared working-tree change present: " + value);
        });
    } else {
        expect(lines.length === 0, "prepare requires a clean exact-source working tree");
    }
    return { commit, treeOid: tree };
}

function validateOnlyStagingChanges(root, stageRoot) {
    const relativeStage = path.relative(root, stageRoot).split(path.sep).join("/");
    expect(relativeStage && !relativeStage.startsWith("../") && !path.isAbsolute(relativeStage), "staging directory escaped source root");
    const status = String(git(root, ["status", "--porcelain=v1", "--untracked-files=all"]));
    status.split(/\r?\n/).filter(Boolean).forEach((line) => {
        const value = line.slice(3).replace(/\\/g, "/");
        expect(value === relativeStage || value.startsWith(relativeStage + "/"), "source changed while A6 preparation was staged: " + value);
    });
}

function runtimeSourceDomainHashes(root, commit) {
    const configBinding = gitObjectBinding(root, commit, "config/build/runtime-inputs.v2.json");
    let config;
    try { config = JSON.parse(configBinding.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
    catch (error) { fail("VALIDATION_FAILED", "runtime-inputs.v2.json is invalid: " + error.message); }
    expect(config && config.schema === "cf7-runtime-inputs.v2" && config.domains, "runtime input config schema invalid");
    const hashes = {};
    ["artifactSource", "producerRecipe", "toolchainLock"].forEach((domain) => {
        const policy = config.domains[domain];
        expect(policy && Array.isArray(policy.fixedFiles) && Array.isArray(policy.trees), "runtime domain invalid: " + domain);
        let files = policy.fixedFiles.map((entry) => String(entry).replace(/\\/g, "/"));
        policy.trees.forEach((tree) => {
            const base = String(tree.path || "").replace(/\\/g, "/").replace(/\/$/, "");
            safeRelative(base, "runtime input tree");
            const listed = String(git(root, ["ls-tree", "-r", "--name-only", commit, "--", base])).trim();
            const extensions = (tree.includeExtensions || []).map((entry) => String(entry).toLowerCase());
            const excludePaths = (tree.excludePaths || []).map((entry) => String(entry).replace(/\\/g, "/"));
            const excludePrefixes = (tree.excludePrefixes || []).map((entry) => String(entry).replace(/\\/g, "/"));
            if (listed) listed.split(/\r?\n/).filter(Boolean).forEach((entry) => {
                const relative = entry.replace(/\\/g, "/");
                if (extensions.length && !extensions.includes(path.posix.extname(relative).toLowerCase())) return;
                if (excludePaths.includes(relative) || excludePrefixes.some((prefix) => relative.startsWith(prefix))) return;
                files.push(relative);
            });
        });
        files = Array.from(new Set(files)).sort();
        expect(files.length > 0, "runtime input domain empty: " + domain);
        const bindings = gitObjectBindings(root, commit, files);
        const rows = files.map((relative) => relative + "\t" + bindings[relative].blobOid).join("\n") + "\n";
        hashes[domain + "Hash"] = runner.sha256(Buffer.from(rows, "utf8"));
    });
    hashes.configBlobOid = configBinding.blobOid;
    hashes.configSha256 = configBinding.sha256;
    return hashes;
}

function readCandidateFile(candidateRoot, relative, label) {
    const absolute = containedPath(candidateRoot, relative, label);
    let cursor = candidateRoot;
    relative.split("/").slice(0, -1).forEach((part) => {
        cursor = path.join(cursor, part);
        const stat = fs.lstatSync(cursor);
        expect(stat.isDirectory() && !stat.isSymbolicLink(), label + " traverses link/reparse directory");
    });
    return readRegularFile(absolute, label, MAX_FILE_BYTES).bytes;
}

function inspectCandidate(candidateRoot, sourceDomains) {
    const root = openRealDirectory(candidateRoot, "candidate root");
    const manifestBytes = readCandidateFile(root, "runtime/cf7-runtime-manifest.tsv", "candidate manifest");
    expect(!manifestBytes.includes(0x0D), "candidate manifest must use LF");
    const lines = manifestBytes.toString("utf8").split("\n");
    expect(lines.pop() === "" && lines[0] === "cf7-runtime-manifest-v2", "candidate manifest framing invalid");
    const allowed = ["artifactSourceHash", "buildIdentityHash", "payloadClosureHash", "producerRecipeHash", "publishMode", "toolchainBaseline", "toolchainLockHash"];
    const fields = {};
    const files = [];
    lines.slice(1).forEach((line, index) => {
        const columns = line.split("\t");
        if (columns[0] === "file") {
            expect(columns.length === 4 && /^[0-9]+$/.test(columns[2]) && /^[A-F0-9]{64}$/.test(columns[3]), "candidate file row invalid at line " + (index + 2));
            files.push({ bytes: Number(columns[2]), path: columns[1], sha256: columns[3] });
        } else {
            expect(columns.length === 2 && allowed.includes(columns[0]) && columns[1] && !Object.prototype.hasOwnProperty.call(fields, columns[0]), "candidate field invalid at line " + (index + 2));
            fields[columns[0]] = columns[1];
        }
    });
    expect(JSON.stringify(Object.keys(fields).sort()) === JSON.stringify(allowed.slice().sort()), "candidate metadata set incomplete");
    expect(fields.publishMode === "framework-dependent" && fields.toolchainBaseline, "candidate publish metadata invalid");
    expect(runner.runtimeBuildIdentityHash(fields.artifactSourceHash, fields.producerRecipeHash, fields.toolchainLockHash) === fields.buildIdentityHash, "candidate build identity not recomputable");
    expect(runner.runtimePayloadClosureHash(files) === fields.payloadClosureHash, "candidate payload closure not recomputable");
    expect(fields.artifactSourceHash === sourceDomains.artifactSourceHash && fields.producerRecipeHash === sourceDomains.producerRecipeHash && fields.toolchainLockHash === sourceDomains.toolchainLockHash, "candidate domain hashes do not derive from exact source");
    expect(JSON.stringify(files.map((entry) => entry.path)) === JSON.stringify(files.map((entry) => entry.path).slice().sort()), "candidate file rows not sorted");

    const excluded = new Set(["runtime/cf7-runtime-manifest.tsv", "runtime/runtime-build-attestation.json", "runtime/runtime-release-consensus.json"]);
    const actualPaths = [];
    if (fs.existsSync(path.join(root, "CRAZYFLASHER7MercenaryEmpire.exe"))) actualPaths.push("CRAZYFLASHER7MercenaryEmpire.exe");
    const runtimeRoot = path.join(root, "runtime");
    expect(fs.existsSync(runtimeRoot) && fs.lstatSync(runtimeRoot).isDirectory(), "candidate runtime directory missing");
    function walk(directory, relativeBase) {
        fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
            const full = path.join(directory, entry.name);
            const relative = relativeBase ? relativeBase + "/" + entry.name : "runtime/" + entry.name;
            const stat = fs.lstatSync(full);
            expect(!entry.isSymbolicLink() && !stat.isSymbolicLink(), "candidate payload contains link/reparse: " + relative);
            if (entry.isDirectory() && stat.isDirectory()) walk(full, relative);
            else {
                expect(entry.isFile() && stat.isFile(), "candidate payload entry is not regular: " + relative);
                if (!excluded.has(relative) && !relative.startsWith("runtime/attestations/")) actualPaths.push(relative);
            }
        });
    }
    walk(runtimeRoot, "");
    const actualFiles = actualPaths.sort().map((relative) => {
        const bytes = readCandidateFile(root, relative, "candidate payload " + relative);
        return { bytes: bytes.length, path: relative, sha256: runner.sha256(bytes) };
    });
    expect(JSON.stringify(actualFiles) === JSON.stringify(files), "candidate manifest differs from exact full payload");

    const coreBytes = readCandidateFile(root, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", "candidate Core DLL");
    const miniaudioBytes = readCandidateFile(root, "runtime/miniaudio.dll", "candidate miniaudio DLL");
    return {
        candidate: {
            buildIdentity: fields.buildIdentityHash,
            coreBytes: coreBytes.length,
            coreSha256: runner.sha256(coreBytes),
            manifestBytes: manifestBytes.length,
            manifestSha256: runner.sha256(manifestBytes),
            miniaudioBytes: miniaudioBytes.length,
            miniaudioSha256: runner.sha256(miniaudioBytes),
            payloadClosure: fields.payloadClosureHash
        },
        fields,
        files,
        manifestBytes,
        root
    };
}

function validateRoleMatrix() {
    REPORT_IDS.forEach((reportId) => {
        const required = runner.REPORT_INPUT_ROLES[reportId].filter((role) => !Object.values(CANDIDATE_INPUTS).includes(role)).sort();
        const mapped = Object.keys(ROLE_PATHS[reportId] || {}).sort();
        expect(JSON.stringify(mapped) === JSON.stringify(required), "source role path matrix differs from runner for " + reportId);
        const paths = Object.values(ROLE_PATHS[reportId]);
        expect(new Set(paths).size === paths.length, "source role paths must be distinct within " + reportId);
    });
}

function validateToolchain(toolchainPath) {
    const parsed = parseCanonicalJsonFile(toolchainPath, "toolchain JSON");
    exactKeys(parsed.value, ["cl", "cmd", "dotnet", "msvcToolsVersion", "node", "nodeVersion", "powershell", "schema", "vcvars64", "windowsSdkVersion"], "toolchain");
    expect(parsed.value.schema === "cf7.audio-v2.qualification-toolchain.v1", "toolchain schema invalid");
    ["msvcToolsVersion", "windowsSdkVersion"].forEach((key) => expect(typeof parsed.value[key] === "string" && parsed.value[key].length > 0, "toolchain " + key + " invalid"));
    expect(typeof parsed.value.nodeVersion === "string" && /^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$/.test(parsed.value.nodeVersion), "toolchain nodeVersion invalid");
    ["cl", "cmd", "dotnet", "node", "powershell", "vcvars64"].forEach((key) => {
        exactKeys(parsed.value[key], ["path", "sha256"], "toolchain " + key);
        expect(path.isAbsolute(parsed.value[key].path) && /^[A-F0-9]{64}$/.test(parsed.value[key].sha256), "toolchain descriptor invalid: " + key);
        const bytes = readRegularFile(path.resolve(parsed.value[key].path), "toolchain " + key, MAX_FILE_BYTES).bytes;
        expect(runner.sha256(bytes) === parsed.value[key].sha256, "toolchain executable/script SHA drift: " + key);
    });
    const nodeVersion = cp.spawnSync(parsed.value.node.path, ["--version"], {
        encoding: "utf8", env: {}, maxBuffer: 1024 * 1024, timeout: 15000, windowsHide: true
    });
    expect(!nodeVersion.error && nodeVersion.status === 0, "toolchain Node version probe failed");
    expect(String(nodeVersion.stdout || "").trim() === parsed.value.nodeVersion && !String(nodeVersion.stderr || "").trim(), "toolchain Node version output drifted");
    return { encoded: parsed.bytes.toString("base64"), value: parsed.value };
}

function environmentValue(environment, name) {
    if (Object.prototype.hasOwnProperty.call(environment, name)) return environment[name];
    if (process.platform === "win32") {
        const actual = Object.keys(environment).find((entry) => entry.toLowerCase() === name.toLowerCase());
        if (actual) return environment[actual];
    }
    return undefined;
}

function boundEnvironment(reportId, environment, toolchainEncoded, nodeExe) {
    const values = {
        [TOOLCHAIN_ENV]: toolchainEncoded,
        [NODE_EXE_ENV]: nodeExe,
        SystemRoot: environmentValue(environment, "SystemRoot"),
        TEMP: environmentValue(environment, "TEMP"),
        TMP: environmentValue(environment, "TMP")
    };
    if (["csharp_capability_catalog_bridge", "launcher_affected_regression"].includes(reportId)) {
        values.NUGET_PACKAGES = environmentValue(environment, "NUGET_PACKAGES");
    }
    return Object.keys(values).sort().map((name) => {
        expect(typeof values[name] === "string" && values[name].length > 0, "required environment is unavailable: " + name);
        return { name, valueSha256: runner.sha256(Buffer.from(values[name], "utf8")) };
    });
}

function loadEndpointArgv(reportId, file, candidate, releaseSource, nodeExe) {
    const parsed = parseCanonicalJsonFile(file, "endpoint argv " + reportId);
    expect(Array.isArray(parsed.value), "endpoint argv must be a JSON array: " + reportId);
    expect(path.isAbsolute(parsed.value[0]) && samePath(parsed.value[0], nodeExe), "endpoint argv Node executable mismatch: " + reportId);
    const expectedPrefix = [RUNNER_PATH, "--report-id", reportId];
    expect(JSON.stringify(parsed.value.slice(1, 4)) === JSON.stringify(expectedPrefix), "endpoint argv prefix mismatch: " + reportId);
    const configuration = {
        argv: parsed.value,
        environment: [],
        reportId,
        schema: "cf7.audio-v2.automated-report-configuration.v1",
        workingDirectory: "release_source_root"
    };
    const carrier = runner.decodeConfigurationLiveObservation(configuration);
    const validated = observer.validateJournalCarrier(carrier);
    expect(validated.observation.reportId === reportId, "endpoint carrier report mismatch: " + reportId);
    expect(validated.observation.candidateBuildIdentity === candidate.buildIdentity && validated.observation.candidatePayloadClosure === candidate.payloadClosure, "endpoint carrier candidate mismatch: " + reportId);
    expect(JSON.stringify(validated.observation.releaseSource) === JSON.stringify(releaseSource), "endpoint carrier release source mismatch: " + reportId);
    return { argv: parsed.value, carrier: validated };
}

function validateEndpointSet(loaded, candidate, releaseSource, runId) {
    const first = loaded[ENDPOINT_REPORT_IDS[0]].carrier;
    const journalBytes = runner.canonicalBytes(first.journal);
    const candidateBytes = runner.canonicalBytes(first.candidate);
    const physicalKeys = ["backend", "channels", "deviceIdDigest", "sampleFormat", "sampleRate"];
    const physicalTuple = physicalKeys.map((key) => first.observation.session[key]);
    ENDPOINT_REPORT_IDS.forEach((reportId) => {
        const carrier = loaded[reportId].carrier;
        expect(carrier.candidate.buildIdentity === candidate.buildIdentity && carrier.candidate.payloadClosure === candidate.payloadClosure, "endpoint candidate identity drift: " + reportId);
        expect(runner.canonicalBytes(carrier.candidate).equals(candidateBytes), "endpoint reports do not bind one exact candidate process: " + reportId);
        expect(JSON.stringify(carrier.observation.releaseSource) === JSON.stringify(releaseSource), "endpoint source drift: " + reportId);
        expect(carrier.observation.runId === runId, "endpoint runId mismatch: " + reportId);
        expect(runner.canonicalBytes(carrier.journal).equals(journalBytes), "endpoint reports do not archive one exact journal");
        expect(JSON.stringify(physicalKeys.map((key) => carrier.observation.session[key])) === JSON.stringify(physicalTuple), "endpoint report physical runtime tuple drift: " + reportId);
    });
    return loaded;
}

function sourceJson(root, commit, relative, label) {
    const binding = gitObjectBinding(root, commit, relative);
    let value;
    try { value = JSON.parse(binding.bytes.toString("utf8")); }
    catch (error) { fail("VALIDATION_FAILED", label + " source JSON invalid: " + error.message); }
    return { binding, value };
}

function sourceDescriptor(binding, commit) {
    return {
        blobOid: binding.blobOid,
        bytes: binding.bytes.length,
        path: binding.path,
        sha256: binding.sha256,
        sourceCommit: commit
    };
}

function validateQualificationDependencyClosure(root, commit) {
    const parsed = sourceJson(root, commit, DEPENDENCY_MANIFEST_PATH, "qualification dependency manifest");
    const value = parsed.value;
    expect(parsed.binding.bytes.equals(runner.canonicalBytes(value)), "qualification dependency manifest is not canonical JSON");
    exactKeys(value, ["closureSha256", "dependencies", "runnerPath", "schema"], "qualification dependency manifest");
    expect(value.schema === "cf7.audio-v2.qualification-runner-dependencies.v1" && value.runnerPath === RUNNER_PATH, "qualification dependency manifest identity invalid");
    expect(Array.isArray(value.dependencies) && value.dependencies.length > 0, "qualification dependency manifest is empty");
    const paths = [];
    value.dependencies.forEach((entry, index) => {
        exactKeys(entry, ["blobOid", "bytes", "path", "sha256"], "qualification dependency " + index);
        safeRelative(entry.path, "qualification dependency path");
        expect(!paths.includes(entry.path), "duplicate qualification dependency path: " + entry.path);
        paths.push(entry.path);
    });
    expect(JSON.stringify(paths) === JSON.stringify(paths.slice().sort()), "qualification dependencies are not path-sorted");
    expect(value.closureSha256 === runner.sha256(runner.canonicalBytes(value.dependencies)), "qualification dependency closure SHA mismatch");
    const bindings = gitObjectBindings(root, commit, paths);
    const descriptors = {};
    value.dependencies.forEach((entry) => {
        const binding = bindings[entry.path];
        expect(entry.blobOid === binding.blobOid && entry.bytes === binding.bytes.length && entry.sha256 === binding.sha256, "qualification dependency differs from exact S: " + entry.path);
        descriptors[entry.path] = sourceDescriptor(binding, commit);
    });
    [RUNNER_PATH, "tools/audio-v2/qualification-observer.js", "tools/audio-v2/qualification-observer-client.ps1"]
        .concat(REQUIRED_QUALIFICATION_DEPENDENCIES)
        .forEach((relative) => expect(descriptors[relative], "required qualification dependency is absent: " + relative));
    return {
        closureSha256: value.closureSha256,
        manifest: sourceDescriptor(parsed.binding, commit),
        requiredSources: REQUIRED_QUALIFICATION_DEPENDENCIES.map((relative) => descriptors[relative])
    };
}

function validateAs2TraceBytes(root, commit, bytes, label) {
    expect(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 1024 * 1024, label + " byte size invalid");
    const suiteBinding = gitObjectBinding(root, commit, AS2_SUITE_PATH);
    const suite = suiteBinding.bytes.toString("utf8");
    const names = Array.from(suite.matchAll(/assert(?:True|False|Equal)\(\s*"([^"]+)"/g)).map((match) => match[1]);
    expect(names.length >= 80 && names.length <= 256 && new Set(names).size === names.length, "AS2 assertion inventory invalid");
    const text = bytes.toString("utf8");
    expect(Buffer.from(text, "utf8").equals(bytes), label + " is not valid UTF-8");
    const lines = text.replace(/\r\n/g, "\n").split("\n");
    expect(lines.includes("AudioBridgeV2Test Tests Passed: " + names.length) && lines.includes("AudioBridgeV2Test Tests Failed: 0"), "AS2 trace lacks exact summary");
    const passLines = lines.filter((line) => line.startsWith("[PASS] "));
    expect(passLines.length === names.length && !lines.some((line) => line.startsWith("[TEST_FAIL] ")), "AS2 trace pass/fail cardinality invalid");
    names.forEach((name) => {
        const prefix = "[PASS] " + name;
        expect(passLines.filter((line) => line === prefix || line.startsWith(prefix + " expected=")).length === 1, "AS2 trace missing/duplicating assertion: " + name);
    });
    return names;
}

function validateFreshAs2Trace(root, commit, tracePath, nowMs) {
    const trace = readRegularFile(tracePath, "fresh AS2 trace", 1024 * 1024);
    const age = nowMs - trace.stat.mtimeMs;
    expect(age >= -1000 && age <= MAX_TRACE_AGE_MS, "AS2 fresh trace is older than 15 minutes or from the future");
    validateAs2TraceBytes(root, commit, trace.bytes, "fresh AS2 trace");
    return {
        bytes: trace.bytes,
        observedAtUtc: new Date(trace.stat.mtimeMs).toISOString()
    };
}

function sourceObservationCommon(reportId, context) {
    return {
        candidateBuildIdentity: context.candidate.buildIdentity,
        candidatePayloadClosure: context.candidate.payloadClosure,
        candidateProcess: null,
        caseFacts: [],
        generatedAtUtc: context.generatedAtUtc,
        releaseSource: context.releaseSource,
        reportId,
        runId: context.runId,
        schema: "cf7.audio-v2.live-observation.v2",
        session: {}
    };
}

function buildSourceObservations(context) {
    const result = {};
    const fixtures = sourceJson(context.root, context.releaseSource.commit, ROLE_PATHS.asset_offline_eof_qualification.decoder_fixture_inventory, "decoder fixture inventory").value;
    const inventory = sourceJson(context.root, context.releaseSource.commit, ROLE_PATHS.asset_offline_eof_qualification.shipped_audio_corpus_inventory, "shipped inventory").value;
    expect(Array.isArray(fixtures.fixtures) && Array.isArray(inventory.assets), "asset inventories incomplete");

    const asset = sourceObservationCommon("asset_offline_eof_qualification", context);
    asset.session = { executionKind: "recomputed_bound_asset_probe", toolchainSha256: context.toolchainSha256 };
    asset.caseFacts = runner.REPORT_CASES[asset.reportId].map((caseId) => ({
        caseId,
        facts: caseId === "shipped_corpus_all_files"
            ? { inventoryEntryCount: inventory.assets.filter((entry) => entry.repositoryState === "tracked").length }
            : { fixtureIds: fixtures.fixtures.filter((entry) => entry.caseId === caseId).map((entry) => entry.fixtureId) }
    }));
    result[asset.reportId] = asset;

    ["native_abi_decoder_lifecycle", "csharp_capability_catalog_bridge", "launcher_affected_regression"].forEach((reportId) => {
        const value = sourceObservationCommon(reportId, context);
        value.session = { executionKind: "recomputed_bound_source_probe", toolchainSha256: context.toolchainSha256 };
        value.caseFacts = runner.REPORT_CASES[reportId].map((caseId) => ({ caseId, facts: { assertionIds: runner.CASE_CHECKS[reportId][caseId] } }));
        result[reportId] = value;
    });

    const deviceCarrier = context.endpoint.device_recovery_endpoint_e2e.carrier;
    const deviceSession = deviceCarrier.observation.session;
    expect(deviceSession.backend === "wasapi", "production backend source report requires endpoint carrier on WASAPI");
    const recovery = deviceCarrier.observation.caseFacts.find((entry) => entry.caseId === "default_device_switch");
    expect(recovery && recovery.facts && recovery.facts.newDeviceIdDigest === deviceSession.deviceIdDigest, "device recovery facts do not end on endpoint session");
    const production = sourceObservationCommon("production_backend_device_fault_injection", context);
    production.session = {
        backend: "wasapi",
        channels: deviceSession.channels,
        deviceGeneration: 1,
        deviceIdDigest: deviceSession.deviceIdDigest,
        executionKind: "recomputed_bound_source_and_device_probe",
        sampleRate: deviceSession.sampleRate,
        toolchainSha256: context.toolchainSha256
    };
    production.caseFacts = runner.REPORT_CASES[production.reportId].map((caseId) => {
        const facts = { assertionIds: runner.CASE_CHECKS[production.reportId][caseId] };
        if (caseId === "default_device_recovery") Object.assign(facts, {
            deviceGenerationAfter: recovery.facts.deviceGenerationAfter,
            deviceGenerationBefore: recovery.facts.deviceGenerationBefore,
            newDeviceIdDigest: recovery.facts.newDeviceIdDigest,
            oldDeviceIdDigest: recovery.facts.oldDeviceIdDigest
        });
        return { caseId, facts };
    });
    result[production.reportId] = production;

    const as2 = sourceObservationCommon("as2_wire_publish", context);
    as2.session = { executionKind: "recomputed_bound_source_probe", toolchainSha256: context.toolchainSha256 };
    const published = gitObjectBinding(context.root, context.releaseSource.commit, ROLE_PATHS.as2_wire_publish.as2_publish_plan);
    as2.caseFacts = runner.REPORT_CASES[as2.reportId].map((caseId) => {
        const facts = { assertionIds: runner.CASE_CHECKS[as2.reportId][caseId] };
        if (caseId === "asloader_publish_smoke") Object.assign(facts, {
            freshTraceBase64: context.as2Trace.bytes.toString("base64"),
            freshTraceSha256: runner.sha256(context.as2Trace.bytes),
            publishedSwfBytes: published.bytes.length,
            publishedSwfSha256: published.sha256,
            traceObservedAtUtc: context.as2Trace.observedAtUtc
        });
        return { caseId, facts };
    });
    result[as2.reportId] = as2;
    return result;
}

function candidateInput(candidateRoot, relative, role) {
    const bytes = readCandidateFile(candidateRoot, relative, "candidate input " + relative);
    return { bytes: bytes.length, kind: "candidate_artifact", path: relative, role, sha256: runner.sha256(bytes) };
}

function sourceInput(root, commit, relative, role) {
    const binding = gitObjectBinding(root, commit, relative);
    const working = readRegularFile(containedPath(root, relative, "working source input"), "working source input " + relative, MAX_FILE_BYTES).bytes;
    expect(working.equals(binding.bytes), "working source input differs from exact S: " + relative);
    return { blobOid: binding.blobOid, bytes: binding.bytes.length, kind: "release_source_blob", path: relative, role, sha256: binding.sha256 };
}

function buildInputManifest(reportId, context) {
    const inputs = Object.entries(CANDIDATE_INPUTS).map(([relative, role]) => candidateInput(context.candidateRoot, relative, role));
    Object.entries(ROLE_PATHS[reportId]).forEach(([role, relative]) => inputs.push(sourceInput(context.root, context.releaseSource.commit, relative, role)));
    inputs.sort((left, right) => {
        const a = left.kind + ":" + left.path;
        const b = right.kind + ":" + right.path;
        return a < b ? -1 : (a > b ? 1 : 0);
    });
    return {
        candidateBuildIdentity: context.candidate.buildIdentity,
        candidatePayloadClosure: context.candidate.payloadClosure,
        closureSha256: runner.sha256(runner.canonicalBytes(inputs)),
        inputs,
        releaseSource: context.releaseSource,
        reportId,
        schema: "cf7.audio-v2.automated-report-input-manifest.v1"
    };
}

function buildConfiguration(reportId, context, sourceObservations) {
    const argv = SOURCE_REPORT_IDS.has(reportId)
        ? [context.toolchainValue.node.path, RUNNER_PATH, "--report-id", reportId].concat(runner.encodeLiveObservationArguments(sourceObservations[reportId]))
        : context.endpoint[reportId].argv;
    return {
        argv,
        environment: boundEnvironment(reportId, context.environment, context.toolchainEncoded, context.toolchainValue.node.path),
        reportId,
        schema: "cf7.audio-v2.automated-report-configuration.v1",
        workingDirectory: "release_source_root"
    };
}

function draftDescriptor(relative, bytes, oidLength) {
    return {
        blobOidCandidate: runner.gitBlobOid(bytes, oidLength),
        bytes: bytes.length,
        path: relative,
        sha256: runner.sha256(bytes),
        state: "UNCOMMITTED_DRAFT"
    };
}

function buildDrafts(context, preparedBytes) {
    const base = PREPARED_ROOT + "/drafts";
    const candidatePath = base + "/candidate-verification.HUMAN_REQUIRED.json";
    const listeningPath = base + "/human-listening-matrix.HUMAN_REQUIRED.json";
    const manifestPath = base + "/a6-evidence-manifest.HUMAN_REQUIRED.json";
    const candidateDraft = {
        candidate: context.candidate,
        finalSchemaTarget: "cf7.audio-v2.candidate-verification.v1",
        fullPayloadRecomputedByAssembler: {
            buildIdentity: true,
            fileCount: context.candidateInspection.files.length,
            payloadClosure: true,
            runtimeInputsConfigBlobOid: context.sourceDomains.configBlobOid,
            runtimeInputsConfigSha256: context.sourceDomains.configSha256,
            sourceDomains: true
        },
        observedAtUtc: context.generatedAtUtc,
        observedRoot: context.candidateRoot,
        promotionAuthorized: false,
        result: "HUMAN_REQUIRED",
        runtimeManifestSnapshotRequired: true,
        schema: "cf7.audio-v2.candidate-verification-draft.v1",
        status: "HUMAN_REQUIRED"
    };
    const listeningDraft = {
        allPassed: false,
        candidateBuildIdentity: context.candidate.buildIdentity,
        candidatePayloadClosure: context.candidate.payloadClosure,
        cases: Object.keys(LISTENING_CAPTURE_IDS).map((caseId) => ({
            captureIds: LISTENING_CAPTURE_IDS[caseId],
            caseId,
            notes: "",
            result: "HUMAN_REQUIRED"
        })),
        finalSchemaTarget: "cf7.audio-v2.human-listening-matrix.v1",
        promotionAuthorized: false,
        recordedAtUtc: null,
        reviewer: null,
        schema: "cf7.audio-v2.human-listening-matrix-draft.v1",
        status: "HUMAN_REQUIRED"
    };
    const candidateBytes = runner.canonicalBytes(candidateDraft);
    const listeningBytes = runner.canonicalBytes(listeningDraft);
    preparedBytes[candidatePath] = candidateBytes;
    preparedBytes[listeningPath] = listeningBytes;

    const runnerBinding = gitObjectBinding(context.root, context.releaseSource.commit, RUNNER_PATH);
    const assemblerBinding = gitObjectBinding(context.root, context.releaseSource.commit, ASSEMBLER_PATH);
    const endpointEnumeratorBinding = gitObjectBinding(context.root, context.releaseSource.commit, ENDPOINT_ENUMERATOR_PATH);
    const reports = REPORT_IDS.map((reportId) => {
        const configurationPath = PREPARED_ROOT + "/config/" + reportId + ".json";
        const inputPath = PREPARED_ROOT + "/inputs/" + reportId + ".json";
        return {
            configuration: draftDescriptor(configurationPath, preparedBytes[configurationPath], context.releaseSource.commit.length),
            inputManifest: draftDescriptor(inputPath, preparedBytes[inputPath], context.releaseSource.commit.length),
            reportArtifact: null,
            reportId,
            status: "HUMAN_REQUIRED",
            verificationArtifact: null
        };
    });
    const device = context.endpoint.device_recovery_endpoint_e2e.carrier.observation.session;
    const manifestDraft = {
        automatedReports: reports,
        candidate: context.candidate,
        candidateVerification: {
            draftArtifact: draftDescriptor(candidatePath, candidateBytes, context.releaseSource.commit.length),
            finalArtifact: null,
            status: "HUMAN_REQUIRED"
        },
        device: {
            audioDeviceQualified: false,
            channels: device.channels,
            deviceIdDigest: device.deviceIdDigest,
            sampleFormat: device.sampleFormat,
            sampleRate: device.sampleRate,
            selectedBackend: device.backend,
            selectedDeviceName: "HUMAN_REQUIRED",
            status: "HUMAN_REQUIRED"
        },
        endpointCaptures: { items: [], status: "HUMAN_REQUIRED" },
        finalSchemaTarget: "cf7.audio-v2.a6-evidence-manifest.v1",
        listeningMatrix: {
            allPassed: false,
            draftArtifact: draftDescriptor(listeningPath, listeningBytes, context.releaseSource.commit.length),
            finalArtifact: null,
            status: "HUMAN_REQUIRED"
        },
        promotionAuthorized: false,
        qualificationDependencies: {
            closureSha256: context.qualificationDependencies.closureSha256,
            manifest: context.qualificationDependencies.manifest,
            requiredSources: context.qualificationDependencies.requiredSources
        },
        qualificationPreparation: {
            assembler: sourceDescriptor(assemblerBinding, context.releaseSource.commit),
            endpointEnumerator: sourceDescriptor(endpointEnumeratorBinding, context.releaseSource.commit)
        },
        qualificationRunner: {
            blobOid: runnerBinding.blobOid,
            bytes: runnerBinding.bytes.length,
            path: RUNNER_PATH,
            sha256: runnerBinding.sha256,
            sourceCommit: context.releaseSource.commit
        },
        releaseSource: context.releaseSource,
        schema: "cf7.audio-v2.a6-evidence-manifest-draft.v1",
        status: "HUMAN_REQUIRED"
    };
    preparedBytes[manifestPath] = runner.canonicalBytes(manifestDraft);
    return { candidatePath, listeningPath, manifestPath };
}

function validateConfigurationShape(configuration, reportId, context) {
    exactKeys(configuration, ["argv", "environment", "reportId", "schema", "workingDirectory"], "configuration " + reportId);
    expect(configuration.schema === "cf7.audio-v2.automated-report-configuration.v1" && configuration.reportId === reportId && configuration.workingDirectory === "release_source_root", "configuration binding invalid: " + reportId);
    expect(Array.isArray(configuration.argv) && configuration.argv.length >= 6 && configuration.argv.length <= 32, "configuration argv bound invalid: " + reportId);
    expect(path.isAbsolute(configuration.argv[0]) && samePath(configuration.argv[0], context.toolchainValue.node.path), "configuration Node executable invalid: " + reportId);
    expect(JSON.stringify(configuration.argv.slice(1, 4)) === JSON.stringify([RUNNER_PATH, "--report-id", reportId]), "configuration runner prefix invalid: " + reportId);
    runner.decodeConfigurationLiveObservation(configuration);
    expect(Array.isArray(configuration.environment), "configuration environment missing: " + reportId);
    const names = configuration.environment.map((entry) => entry.name);
    expect(JSON.stringify(names) === JSON.stringify(names.slice().sort()) && new Set(names).size === names.length, "configuration environment order/uniqueness invalid: " + reportId);
    configuration.environment.forEach((entry) => {
        exactKeys(entry, ["name", "valueSha256"], "configuration environment entry");
        expect(/^[A-F0-9]{64}$/.test(entry.valueSha256), "configuration environment SHA invalid");
    });
    const nodeBinding = configuration.environment.find((entry) => entry.name === NODE_EXE_ENV);
    expect(nodeBinding && nodeBinding.valueSha256 === runner.sha256(Buffer.from(context.toolchainValue.node.path, "utf8")), "configuration CF7_NODE_EXE binding invalid: " + reportId);
}

function validateInputShape(input, reportId, context) {
    exactKeys(input, ["candidateBuildIdentity", "candidatePayloadClosure", "closureSha256", "inputs", "releaseSource", "reportId", "schema"], "input manifest " + reportId);
    expect(input.schema === "cf7.audio-v2.automated-report-input-manifest.v1" && input.reportId === reportId, "input manifest binding invalid: " + reportId);
    expect(input.candidateBuildIdentity === context.candidate.buildIdentity && input.candidatePayloadClosure === context.candidate.payloadClosure, "input candidate mismatch: " + reportId);
    expect(JSON.stringify(input.releaseSource) === JSON.stringify(context.releaseSource), "input release source mismatch: " + reportId);
    const roles = input.inputs.map((entry) => entry.role).sort();
    expect(JSON.stringify(roles) === JSON.stringify(runner.REPORT_INPUT_ROLES[reportId].slice().sort()), "input role coverage mismatch: " + reportId);
    const order = input.inputs.map((entry) => entry.kind + ":" + entry.path);
    expect(JSON.stringify(order) === JSON.stringify(order.slice().sort()) && new Set(order).size === order.length, "input order/uniqueness invalid: " + reportId);
    expect(input.closureSha256 === runner.sha256(runner.canonicalBytes(input.inputs)), "input closure mismatch: " + reportId);
    const expectedCandidateInputs = {
        "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll": { bytes: context.candidate.coreBytes, sha256: context.candidate.coreSha256 },
        "runtime/cf7-runtime-manifest.tsv": { bytes: context.candidate.manifestBytes, sha256: context.candidate.manifestSha256 },
        "runtime/miniaudio.dll": { bytes: context.candidate.miniaudioBytes, sha256: context.candidate.miniaudioSha256 }
    };
    input.inputs.forEach((entry) => {
        const bytes = entry.kind === "candidate_artifact"
            ? readCandidateFile(context.candidateRoot, entry.path, "validated candidate input")
            : gitObjectBinding(context.root, context.releaseSource.commit, entry.path).bytes;
        expect(bytes.length === entry.bytes && runner.sha256(bytes) === entry.sha256, "input bytes/SHA drift: " + reportId + "/" + entry.role);
        if (entry.kind === "candidate_artifact") {
            const expected = expectedCandidateInputs[entry.path];
            expect(expected && expected.bytes === entry.bytes && expected.sha256 === entry.sha256, "input candidate artifact differs from inspected candidate: " + reportId + "/" + entry.role);
        }
        if (entry.kind === "release_source_blob") expect(runner.gitBlobOid(bytes, entry.blobOid.length) === entry.blobOid, "input blob OID drift: " + reportId + "/" + entry.role);
    });
}

function readPreparedJson(preparedRoot, relative, label) {
    return parseCanonicalJsonFile(containedPath(preparedRoot, relative, label), label).value;
}

function validatePreparedDirectory(preparedRoot, context) {
    const real = openRealDirectory(preparedRoot, "prepared A6 directory");
    const reinspection = context.candidateInspector(context.candidateRoot, context.sourceDomains);
    expect(JSON.stringify(reinspection.candidate) === JSON.stringify(context.candidate) && JSON.stringify(reinspection.files) === JSON.stringify(context.candidateInspection.files), "candidate payload changed during preparation/validation");
    const sourceObservations = {};
    const endpoint = {};
    let runId = null;
    let sourceGeneratedAtUtc = null;
    REPORT_IDS.forEach((reportId) => {
        const configuration = readPreparedJson(real, "config/" + reportId + ".json", "prepared configuration " + reportId);
        const input = readPreparedJson(real, "inputs/" + reportId + ".json", "prepared input " + reportId);
        validateConfigurationShape(configuration, reportId, context);
        validateInputShape(input, reportId, context);
        const decoded = runner.decodeConfigurationLiveObservation(configuration);
        let observation;
        if (SOURCE_REPORT_IDS.has(reportId)) {
            observation = decoded;
            expect(observation.reportId === reportId && observation.candidateProcess === null, "source observation invalid: " + reportId);
            sourceObservations[reportId] = observation;
            if (sourceGeneratedAtUtc === null) sourceGeneratedAtUtc = observation.generatedAtUtc;
            expect(observation.generatedAtUtc === sourceGeneratedAtUtc, "source observation generation time drifted: " + reportId);
        } else {
            const carrier = context.endpointCarrierValidator(decoded);
            expect(carrier.observation.reportId === reportId, "prepared endpoint carrier mismatch: " + reportId);
            endpoint[reportId] = { argv: configuration.argv, carrier };
            observation = carrier.observation;
        }
        expect(observation.candidateBuildIdentity === context.candidate.buildIdentity && observation.candidatePayloadClosure === context.candidate.payloadClosure, "prepared observation candidate drifted: " + reportId);
        expect(JSON.stringify(observation.releaseSource) === JSON.stringify(context.releaseSource), "prepared observation source drifted: " + reportId);
        expect(typeof observation.runId === "string" && /^[0-9a-f]{32}$/.test(observation.runId), "prepared observation runId invalid: " + reportId);
        if (runId === null) runId = observation.runId;
        expect(observation.runId === runId, "prepared observations do not share one runId: " + reportId);
    });
    context.runId = runId;
    context.endpoint = validateEndpointSet(endpoint, context.candidate, context.releaseSource, runId);
    context.generatedAtUtc = sourceGeneratedAtUtc;
    const as2Publish = sourceObservations.as2_wire_publish.caseFacts.find((entry) => entry.caseId === "asloader_publish_smoke");
    expect(as2Publish && as2Publish.facts && typeof as2Publish.facts.freshTraceBase64 === "string", "prepared AS2 trace carrier is missing");
    const traceBytes = Buffer.from(as2Publish.facts.freshTraceBase64, "base64");
    expect(traceBytes.toString("base64") === as2Publish.facts.freshTraceBase64 && runner.sha256(traceBytes) === as2Publish.facts.freshTraceSha256, "prepared AS2 trace byte binding drifted");
    const traceTime = Date.parse(as2Publish.facts.traceObservedAtUtc);
    const generatedTime = Date.parse(sourceGeneratedAtUtc);
    expect(Number.isFinite(traceTime) && Number.isFinite(generatedTime) && /Z$/.test(as2Publish.facts.traceObservedAtUtc) && /Z$/.test(sourceGeneratedAtUtc), "prepared AS2 trace timestamps invalid");
    expect(Math.abs(traceTime - generatedTime) <= MAX_TRACE_AGE_MS, "prepared AS2 trace is not within 15 minutes of preparation");
    validateAs2TraceBytes(context.root, context.releaseSource.commit, traceBytes, "prepared AS2 trace");
    context.as2Trace = { bytes: traceBytes, observedAtUtc: as2Publish.facts.traceObservedAtUtc };
    const expectedSourceObservations = buildSourceObservations(context);
    SOURCE_REPORT_IDS.forEach((reportId) => {
        expect(runner.canonicalBytes(sourceObservations[reportId]).equals(runner.canonicalBytes(expectedSourceObservations[reportId])), "prepared source observation is not exactly recomputable: " + reportId);
    });
    const candidate = readPreparedJson(real, "drafts/candidate-verification.HUMAN_REQUIRED.json", "candidate draft");
    const listening = readPreparedJson(real, "drafts/human-listening-matrix.HUMAN_REQUIRED.json", "listening draft");
    const manifest = readPreparedJson(real, "drafts/a6-evidence-manifest.HUMAN_REQUIRED.json", "manifest draft");
    [candidate, listening, manifest].forEach((value) => {
        expect(value.status === "HUMAN_REQUIRED" && value.promotionAuthorized === false, "draft can be mistaken for accepted evidence");
        expect(typeof value.schema === "string" && value.schema.endsWith("-draft.v1"), "draft schema guard invalid");
    });
    expect(candidate.result === "HUMAN_REQUIRED" && listening.allPassed === false && manifest.listeningMatrix.allPassed === false && manifest.device.audioDeviceQualified === false, "draft contains a positive verdict");
    expect(JSON.stringify(candidate.candidate) === JSON.stringify(context.candidate), "candidate draft identity drifted");
    expect(listening.candidateBuildIdentity === context.candidate.buildIdentity && listening.candidatePayloadClosure === context.candidate.payloadClosure, "listening draft candidate identity drifted");
    expect(JSON.stringify(manifest.candidate) === JSON.stringify(context.candidate) && JSON.stringify(manifest.releaseSource) === JSON.stringify(context.releaseSource), "manifest draft source/candidate identity drifted");
    expect(JSON.stringify(manifest.qualificationDependencies) === JSON.stringify(context.qualificationDependencies), "manifest draft qualification dependency binding drifted");
    const expectedPreparation = {
        assembler: sourceDescriptor(gitObjectBinding(context.root, context.releaseSource.commit, ASSEMBLER_PATH), context.releaseSource.commit),
        endpointEnumerator: sourceDescriptor(gitObjectBinding(context.root, context.releaseSource.commit, ENDPOINT_ENUMERATOR_PATH), context.releaseSource.commit)
    };
    expect(JSON.stringify(manifest.qualificationPreparation) === JSON.stringify(expectedPreparation), "manifest draft preparation source binding drifted");
    return { candidate, listening, manifest };
}

function createContext(options, dependencies, allowPrepared) {
    validateRoleMatrix();
    const root = openRealDirectory(options.outputRoot, "output root");
    expect(samePath(root, process.cwd()) || dependencies.allowNonCwd === true, "output root must be current exact source working directory");
    const releaseSource = validateReleaseSource(root, options.sourceCommit, options.sourceTree, allowPrepared);
    const sourceDomains = runtimeSourceDomainHashes(root, releaseSource.commit);
    const qualificationDependencies = validateQualificationDependencyClosure(root, releaseSource.commit);
    const candidateInspector = dependencies.inspectCandidate || inspectCandidate;
    const candidateInspection = candidateInspector(options.candidateRoot, sourceDomains);
    const candidate = candidateInspection.candidate;
    const toolchain = validateToolchain(options.toolchainJson);
    return {
        candidate,
        candidateInspector,
        candidateInspection,
        candidateRoot: candidateInspection.root,
        environment: options.environment || process.env,
        generatedAtUtc: new Date(options.nowMs === undefined ? Date.now() : options.nowMs).toISOString(),
        endpointCarrierValidator: dependencies.endpointCarrierValidator || observer.validateJournalCarrier,
        qualificationDependencies,
        releaseSource,
        root,
        sourceDomains,
        toolchainEncoded: toolchain.encoded,
        toolchainSha256: runner.sha256(runner.canonicalBytes(toolchain.value)),
        toolchainValue: toolchain.value
    };
}

function prepareArtifacts(options, dependencies) {
    dependencies = dependencies || {};
    expect(/^[0-9a-f]{32}$/.test(options.runId), "runId must be 32 lowercase hexadecimal characters");
    const context = createContext(options, dependencies, false);
    const nowMs = options.nowMs === undefined ? Date.now() : options.nowMs;
    context.runId = options.runId;
    context.as2Trace = validateFreshAs2Trace(context.root, context.releaseSource.commit, options.as2FreshTrace, nowMs);
    const endpoint = {};
    ENDPOINT_REPORT_IDS.forEach((reportId) => {
        const file = options.endpointArgv[reportId];
        expect(file && path.isAbsolute(file), "missing absolute endpoint argv for " + reportId);
        endpoint[reportId] = (dependencies.loadEndpointArgv || loadEndpointArgv)(reportId, path.resolve(file), context.candidate, context.releaseSource, context.toolchainValue.node.path);
    });
    context.endpoint = validateEndpointSet(endpoint, context.candidate, context.releaseSource, options.runId);
    const sourceObservations = buildSourceObservations(context);
    const preparedBytes = {};
    REPORT_IDS.forEach((reportId) => {
        const configurationPath = PREPARED_ROOT + "/config/" + reportId + ".json";
        const inputPath = PREPARED_ROOT + "/inputs/" + reportId + ".json";
        preparedBytes[configurationPath] = runner.canonicalBytes(buildConfiguration(reportId, context, sourceObservations));
        preparedBytes[inputPath] = runner.canonicalBytes(buildInputManifest(reportId, context));
    });
    const drafts = buildDrafts(context, preparedBytes);

    const targetParent = containedPath(context.root, "docs/evidence/audio-v2", "evidence parent");
    expect(fs.existsSync(targetParent) && fs.lstatSync(targetParent).isDirectory() && !fs.lstatSync(targetParent).isSymbolicLink(), "docs/evidence/audio-v2 must already be a real directory");
    const target = containedPath(context.root, PREPARED_ROOT, "prepared target");
    expect(!fs.existsSync(target), "prepared target already exists; validate or remove it explicitly instead of overwriting");
    const stageRoot = fs.mkdtempSync(path.join(context.root, ".cf7-audio-v2-a6-staging-"));
    const staged = path.join(stageRoot, "a6-prepared");
    try {
        Object.entries(preparedBytes).forEach(([relative, bytes]) => {
            const suffix = relative.slice((PREPARED_ROOT + "/").length);
            const destination = containedPath(staged, suffix, "staged prepared file");
            fs.mkdirSync(path.dirname(destination), { recursive: true });
            fs.writeFileSync(destination, bytes, { flag: "wx" });
        });
        validatePreparedDirectory(staged, context);
        validateOnlyStagingChanges(context.root, stageRoot);
        fs.renameSync(staged, target);
    } finally {
        fs.rmSync(stageRoot, { recursive: true, force: true });
    }
    return {
        candidateBuildIdentity: context.candidate.buildIdentity,
        candidatePayloadClosure: context.candidate.payloadClosure,
        draftManifestPath: drafts.manifestPath,
        preparedRoot: PREPARED_ROOT,
        promotionAuthorized: false,
        releaseSource: context.releaseSource,
        result: "prepared_HUMAN_REQUIRED",
        schema: "cf7.audio-v2.a6-prepare-result.v1"
    };
}

function validatePrepared(options, dependencies) {
    dependencies = dependencies || {};
    const context = createContext(options, dependencies, true);
    const target = containedPath(context.root, PREPARED_ROOT, "prepared target");
    const drafts = validatePreparedDirectory(target, context);
    return {
        candidateBuildIdentity: context.candidate.buildIdentity,
        candidatePayloadClosure: context.candidate.payloadClosure,
        draftManifestSha256: runner.sha256(runner.canonicalBytes(drafts.manifest)),
        preparedRoot: PREPARED_ROOT,
        promotionAuthorized: false,
        result: "validated_HUMAN_REQUIRED",
        schema: "cf7.audio-v2.a6-prepare-validation-result.v1"
    };
}

function runnerCommandPlan(options, dependencies) {
    dependencies = dependencies || {};
    const context = createContext(options, dependencies, true);
    validatePreparedDirectory(containedPath(context.root, PREPARED_ROOT, "prepared target"), context);
    const commands = REPORT_IDS.map((reportId) => ({
        argv: [
            context.toolchainValue.node.path, RUNNER_PATH,
            "--report-id", reportId,
            "--candidate-root", context.candidateRoot,
            "--configuration", containedPath(context.root, PREPARED_ROOT + "/config/" + reportId + ".json", "configuration command path"),
            "--input-manifest", containedPath(context.root, PREPARED_ROOT + "/inputs/" + reportId + ".json", "input command path"),
            "--output-root", context.root
        ],
        reportId,
        stopOnNonzeroExit: true
    }));
    const environment = {
        [TOOLCHAIN_ENV]: context.toolchainEncoded,
        [NODE_EXE_ENV]: context.toolchainValue.node.path,
        SystemRoot: environmentValue(context.environment, "SystemRoot"),
        TEMP: environmentValue(context.environment, "TEMP"),
        TMP: environmentValue(context.environment, "TMP")
    };
    const nuget = environmentValue(context.environment, "NUGET_PACKAGES");
    expect(typeof nuget === "string" && nuget.length > 0, "NUGET_PACKAGES unavailable for runner command plan");
    environment.NUGET_PACKAGES = nuget;
    return {
        commands,
        environment,
        promotionAuthorized: false,
        schema: "cf7.audio-v2.a6-runner-command-plan.v1",
        status: "HUMAN_REQUIRED",
        workingDirectory: context.root
    };
}

function parseCli(argv) {
    expect(argv.length > 0 && ["prepare", "validate", "print-runner-commands"].includes(argv[0]), "first argument must be prepare, validate, or print-runner-commands", "USAGE_ERROR");
    const mode = argv[0];
    const values = {};
    const endpointArgv = {};
    const allowed = new Set(["--source-commit", "--source-tree", "--candidate-root", "--output-root", "--run-id", "--toolchain-json", "--as2-fresh-trace", "--endpoint-argv"]);
    for (let index = 1; index < argv.length; index += 2) {
        const flag = argv[index];
        const value = argv[index + 1];
        expect(allowed.has(flag) && value !== undefined, "unknown flag or missing value: " + flag, "USAGE_ERROR");
        if (flag === "--endpoint-argv") {
            const separator = value.indexOf("=");
            expect(separator > 0, "--endpoint-argv must be reportId=absolutePath", "USAGE_ERROR");
            const reportId = value.slice(0, separator);
            const file = value.slice(separator + 1);
            expect(ENDPOINT_REPORT_IDS.includes(reportId) && !endpointArgv[reportId] && path.isAbsolute(file), "endpoint argv binding invalid or duplicated", "USAGE_ERROR");
            endpointArgv[reportId] = path.resolve(file);
        } else {
            expect(!Object.prototype.hasOwnProperty.call(values, flag), "duplicate flag: " + flag, "USAGE_ERROR");
            values[flag] = value;
        }
    }
    ["--source-commit", "--source-tree", "--candidate-root", "--output-root", "--toolchain-json"].forEach((flag) => expect(values[flag], "missing required flag " + flag, "USAGE_ERROR"));
    if (mode === "prepare") {
        expect(values["--run-id"] && values["--as2-fresh-trace"], "prepare requires --run-id and --as2-fresh-trace", "USAGE_ERROR");
        ENDPOINT_REPORT_IDS.forEach((reportId) => expect(endpointArgv[reportId], "prepare missing endpoint argv " + reportId, "USAGE_ERROR"));
    } else {
        expect(!values["--run-id"] && !values["--as2-fresh-trace"] && Object.keys(endpointArgv).length === 0, mode + " has prepare-only flags", "USAGE_ERROR");
    }
    ["--candidate-root", "--output-root", "--toolchain-json"].forEach((flag) => expect(path.isAbsolute(values[flag]), flag + " must be absolute", "USAGE_ERROR"));
    if (values["--as2-fresh-trace"]) expect(path.isAbsolute(values["--as2-fresh-trace"]), "--as2-fresh-trace must be absolute", "USAGE_ERROR");
    return {
        as2FreshTrace: values["--as2-fresh-trace"] ? path.resolve(values["--as2-fresh-trace"]) : null,
        candidateRoot: path.resolve(values["--candidate-root"]),
        endpointArgv,
        mode,
        outputRoot: path.resolve(values["--output-root"]),
        runId: values["--run-id"] || null,
        sourceCommit: values["--source-commit"],
        sourceTree: values["--source-tree"],
        toolchainJson: path.resolve(values["--toolchain-json"])
    };
}

function main(argv) {
    const options = parseCli(argv);
    const value = options.mode === "prepare"
        ? prepareArtifacts(options)
        : options.mode === "validate" ? validatePrepared(options) : runnerCommandPlan(options);
    process.stdout.write(runner.canonicalBytes(value));
}

if (require.main === module) {
    try { main(process.argv.slice(2)); }
    catch (error) {
        const code = error instanceof A6AssemblerError ? error.code : "INTERNAL_ERROR";
        const message = error && error.message ? error.message : String(error);
        process.stderr.write("audio-v2 A6 assembler failed [" + code + "]: " + message.replace(/[\r\n]+/g, " ") + "\n");
        process.exitCode = 3;
    }
}

module.exports = Object.freeze({
    A6AssemblerError,
    CANDIDATE_INPUTS,
    DEPENDENCY_MANIFEST_PATH,
    ENDPOINT_REPORT_IDS,
    LISTENING_CAPTURE_IDS,
    PREPARED_ROOT,
    REQUIRED_QUALIFICATION_DEPENDENCIES,
    REPORT_IDS,
    ROLE_PATHS,
    buildSourceObservations,
    inspectCandidate,
    main,
    parseCli,
    prepareArtifacts,
    runnerCommandPlan,
    runtimeSourceDomainHashes,
    validatePrepared,
    validatePreparedDirectory,
    validateEndpointSet,
    validateRoleMatrix,
    validateToolchain
});
