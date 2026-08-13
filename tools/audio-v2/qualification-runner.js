#!/usr/bin/env node
"use strict";

// Audio Platform v2 qualification trust root.
//
// The H2 validator replays this file from the exact release-source commit in an
// isolated directory. This runner therefore accepts only tracked, canonical
// inputs and never infers success from filenames, extensions, a process exit,
// graph meters, or pre-written "passed" flags alone.

const crypto = require("crypto");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");
const qualificationObserver = require("./qualification-observer.js");

const RUNNER_PATH = "tools/audio-v2/qualification-runner.js";
const DEPENDENCY_MANIFEST_PATH = "config/audio-v2/qualification-runner-dependencies.v1.json";
const CAPTURE_TOOL_PATH = "tools/audio-v2/capture-endpoint.ps1";
const OBSERVER_CLIENT_PATH = "tools/audio-v2/qualification-observer-client.ps1";
const OBSERVER_COLLECTOR_PATH = "tools/audio-v2/qualification-observer.js";
const OFFLINE_PROBE_SOURCE_PATH = "tools/audio-v2/qualification-offline-probe.c";
const AUDIO_ABI_HEADER_PATH = "launcher/native/audio_bridge_v2.h";
const AUDIO_NATIVE_SOURCE_PATH = "launcher/native/miniaudio_bridge.c";
const LIVE_OBSERVATION_ARG = "--bound-live-observation-deflate-base64-v1";
const TOOLCHAIN_ENV = "CF7_AUDIO_V2_TOOLCHAIN_B64";
const NODE_EXE_ENV = "CF7_NODE_EXE";
const MEASUREMENT_UNIT = "cf7.audio-v2.recomputed-observation-sha256.v1";
const MAX_JSON_BYTES = 16 * 1024 * 1024;
const MAX_INPUT_BYTES = 512 * 1024 * 1024;
const MAX_CAPTURE_BYTES = 1024 * 1024;
const MAX_ENV_BYTES = 4 * 1024 * 1024;
const INTERNAL_TIMEOUT_MS = 25 * 60 * 1000;

const ENDPOINT_REPORTS = new Set([
    "exact_candidate_bgm_endpoint_e2e",
    "exact_candidate_sfx_endpoint_e2e",
    "device_recovery_endpoint_e2e"
]);

const SOURCE_PROBE_REPORTS = new Set([
    "native_abi_decoder_lifecycle",
    "production_backend_device_fault_injection",
    "csharp_capability_catalog_bridge",
    "as2_wire_publish",
    "launcher_affected_regression"
]);

const EXPECTED_V2_EXPORTS = Object.freeze([
    "cf7_audio_bridge_v2_initialize",
    "cf7_audio_bridge_v2_probe_offline_qualification",
    "cf7_audio_bridge_v2_probe_runtime_compatibility",
    "cf7_audio_bridge_v2_query_bgm_source",
    "cf7_audio_bridge_v2_query_capability",
    "cf7_audio_bridge_v2_query_meter",
    "cf7_audio_bridge_v2_query_runtime",
    "cf7_audio_bridge_v2_query_sfx_counters",
    "cf7_audio_bridge_v2_rebuild_sfx_catalog",
    "cf7_audio_bridge_v2_set_gain",
    "cf7_audio_bridge_v2_shutdown",
    "cf7_audio_bridge_v2_submit_bgm",
    "cf7_audio_bridge_v2_submit_sfx_batch"
].sort());

const REPORT_CASES = Object.freeze({
    asset_offline_eof_qualification: [
        "shipped_corpus_all_files", "vorbis_fixture", "aac_mp4_fixture",
        "opus_fixture", "malformed_and_silent_fixtures"
    ],
    native_abi_decoder_lifecycle: [
        "abi_version_and_struct_size", "decoder_registration_and_capabilities",
        "runtime_bounded_probe", "offline_eof_probe",
        "start_seek_stop_result_propagation", "shutdown_and_concurrency"
    ],
    production_backend_device_fault_injection: [
        "null_backend_excluded", "wasapi_device_started",
        "fallback_after_device_init_failure", "no_output_degraded_policy",
        "default_device_recovery"
    ],
    csharp_capability_catalog_bridge: [
        "abi_negotiation", "capability_snapshot", "catalog_completeness",
        "preload_readiness", "generation_stale_zero_side_effect"
    ],
    as2_wire_publish: [
        "strict_v2_parse", "request_result_correlation",
        "stale_generation_handling", "bgm_and_sfx_commands",
        "asloader_publish_smoke"
    ],
    launcher_affected_regression: [
        "launcher_dotnet_tests", "jukebox_harness", "audio_hud_state",
        "shutdown_smoke"
    ],
    exact_candidate_bgm_endpoint_e2e: [
        "bgm_playback", "bgm_seek", "bgm_crossfade", "format_vorbis",
        "format_aac_mp4", "format_opus"
    ],
    exact_candidate_sfx_endpoint_e2e: [
        "sfx_playback", "dense_overlap_throttle", "bgm_sfx_mix",
        "gain_zero_and_default_max"
    ],
    device_recovery_endpoint_e2e: [
        "default_device_switch", "physical_route_bluetooth_or_hdmi",
        "sleep_resume", "no_stale_sfx_after_recovery"
    ]
});

const REPORT_INPUT_ROLES = Object.freeze({
    asset_offline_eof_qualification: [
        "candidate_core", "candidate_miniaudio", "candidate_runtime_manifest",
        "decoder_fixture_inventory", "decoder_lock_or_capability_manifest",
        "shipped_audio_corpus_inventory"
    ],
    native_abi_decoder_lifecycle: [
        "candidate_core", "candidate_miniaudio", "candidate_runtime_manifest",
        "decoder_dependency_lock", "native_abi_contract", "native_lifecycle_test_plan"
    ],
    production_backend_device_fault_injection: [
        "backend_policy_source", "candidate_core", "candidate_miniaudio",
        "candidate_runtime_manifest", "device_fault_injection_plan",
        "no_output_product_policy"
    ],
    csharp_capability_catalog_bridge: [
        "bridge_protocol_contract", "candidate_core", "candidate_miniaudio",
        "candidate_runtime_manifest", "catalog_contract", "csharp_audio_source_closure"
    ],
    as2_wire_publish: [
        "as2_audio_source_closure", "as2_publish_plan", "candidate_core",
        "candidate_miniaudio", "candidate_runtime_manifest", "wire_protocol_contract"
    ],
    launcher_affected_regression: [
        "candidate_core", "candidate_miniaudio", "candidate_runtime_manifest",
        "jukebox_harness_source", "launcher_test_manifest", "shutdown_test_plan"
    ],
    exact_candidate_bgm_endpoint_e2e: [
        "bgm_endpoint_run_plan", "bgm_fixture_inventory", "candidate_core",
        "candidate_execution_contract", "candidate_miniaudio", "candidate_runtime_manifest"
    ],
    exact_candidate_sfx_endpoint_e2e: [
        "candidate_core", "candidate_execution_contract", "candidate_miniaudio",
        "candidate_runtime_manifest", "sfx_endpoint_run_plan", "sfx_fixture_inventory"
    ],
    device_recovery_endpoint_e2e: [
        "candidate_core", "candidate_execution_contract", "candidate_miniaudio",
        "candidate_runtime_manifest", "device_recovery_run_plan", "device_route_contract"
    ]
});

const CASE_CHECKS = Object.freeze({
    asset_offline_eof_qualification: {
        shipped_corpus_all_files: ["complete_git_inventory", "content_sniffed", "decoded_to_eof", "signal_classified"],
        vorbis_fixture: ["content_sniff_correct", "decoded_frames_positive", "decoded_to_eof", "nonzero_pcm"],
        aac_mp4_fixture: ["content_sniff_correct", "decoded_frames_positive", "decoded_to_eof", "nonzero_pcm"],
        opus_fixture: ["content_sniff_correct", "decoded_frames_positive", "decoded_to_eof", "nonzero_pcm"],
        malformed_and_silent_fixtures: ["malformed_category_exact", "silent_pcm_detected", "truncated_category_exact"]
    },
    native_abi_decoder_lifecycle: {
        abi_version_and_struct_size: ["abi_major_exact", "struct_prefix_and_size_valid"],
        decoder_registration_and_capabilities: ["capability_rows_match_registered_decoders", "decoder_registration_success"],
        runtime_bounded_probe: ["bounded_read_enforced", "timeout_is_inconclusive"],
        offline_eof_probe: ["decode_to_eof_enforced", "qualification_timeout_fails"],
        start_seek_stop_result_propagation: ["seek_failure_propagated", "start_failure_propagated", "stop_result_propagated"],
        shutdown_and_concurrency: ["owner_queue_serialized", "shutdown_drains_and_rejects_new_work"]
    },
    production_backend_device_fault_injection: {
        null_backend_excluded: ["production_binary_has_no_null_backend", "unknown_backend_fails_qualification"],
        wasapi_device_started: ["device_started", "selected_backend_wasapi"],
        fallback_after_device_init_failure: ["fallback_reaches_real_started_device", "failed_backend_recorded"],
        no_output_degraded_policy: ["audio_ready_false", "launcher_continues_controls_disabled"],
        default_device_recovery: ["device_generation_advanced", "new_real_device_started"]
    },
    csharp_capability_catalog_bridge: {
        abi_negotiation: ["abi_mismatch_fails_closed", "abi_v2_accepted"],
        capability_snapshot: ["build_and_runtime_fields_complete", "snapshot_single_epoch"],
        catalog_completeness: ["bgm_and_sfx_catalog_complete", "unknown_id_explicit"],
        preload_readiness: ["preload_in_ready_barrier", "ready_after_complete_snapshot"],
        generation_stale_zero_side_effect: ["current_epoch_returned", "stale_request_zero_side_effect"]
    },
    as2_wire_publish: {
        strict_v2_parse: ["extra_or_missing_fields_rejected", "wire_revision_v2_required"],
        request_result_correlation: ["request_id_round_trip", "result_category_exact"],
        stale_generation_handling: ["stale_bgm_not_started", "stale_sfx_dropped_not_replayed"],
        bgm_and_sfx_commands: ["bgm_operations_round_trip", "sfx_batch_round_trip"],
        asloader_publish_smoke: ["fresh_trace_present", "published_swf_identity_recorded"]
    },
    launcher_affected_regression: {
        launcher_dotnet_tests: ["affected_test_suite_passed", "no_unexpected_skips"],
        jukebox_harness: ["control_and_stopped_state_passed", "real_host_boundary_not_overclaimed"],
        audio_hud_state: ["audio_unavailable_state_passed", "meter_not_used_as_audibility_proof"],
        shutdown_smoke: ["native_shutdown_complete", "process_exit_clean"]
    },
    exact_candidate_bgm_endpoint_e2e: {
        bgm_playback: ["endpoint_nonzero_pcm", "request_started_on_exact_candidate"],
        bgm_seek: ["post_seek_endpoint_pcm", "seek_result_ok"],
        bgm_crossfade: ["crossfade_no_unbounded_gap", "endpoint_mix_observed"],
        format_vorbis: ["exact_candidate_vorbis_endpoint_pcm", "vorbis_decoder_reported"],
        format_aac_mp4: ["aac_decoder_reported", "exact_candidate_aac_endpoint_pcm"],
        format_opus: ["exact_candidate_opus_endpoint_pcm", "opus_decoder_reported"]
    },
    exact_candidate_sfx_endpoint_e2e: {
        sfx_playback: ["endpoint_nonzero_pcm", "played_counter_advanced"],
        dense_overlap_throttle: ["bounded_voice_count", "throttle_counter_exact"],
        bgm_sfx_mix: ["both_sources_present", "endpoint_mix_nonzero"],
        gain_zero_and_default_max: ["default_gain_audible", "zero_gain_silent_by_command"]
    },
    device_recovery_endpoint_e2e: {
        default_device_switch: ["new_device_identity_published", "post_switch_endpoint_pcm"],
        physical_route_bluetooth_or_hdmi: ["physical_route_identity_recorded", "routed_endpoint_pcm"],
        sleep_resume: ["post_resume_endpoint_pcm", "recovery_bounded"],
        no_stale_sfx_after_recovery: ["stale_generation_drop_counter_exact", "stale_sfx_absent_after_recovery"]
    }
});

const CASE_CAPTURES = Object.freeze({
    exact_candidate_bgm_endpoint_e2e: {
        bgm_playback: ["bgm_playback"], bgm_seek: ["bgm_playback"],
        bgm_crossfade: ["bgm_playback"], format_vorbis: ["bgm_playback"],
        format_aac_mp4: ["bgm_playback"], format_opus: ["bgm_playback"]
    },
    exact_candidate_sfx_endpoint_e2e: {
        sfx_playback: ["sfx_playback"], dense_overlap_throttle: ["sfx_playback"],
        bgm_sfx_mix: ["bgm_sfx_mix"], gain_zero_and_default_max: ["sfx_playback"]
    },
    device_recovery_endpoint_e2e: {
        default_device_switch: ["device_recovery"],
        physical_route_bluetooth_or_hdmi: ["device_recovery"],
        sleep_resume: ["device_recovery"],
        no_stale_sfx_after_recovery: ["device_recovery"]
    }
});

const EXPECTED_CANDIDATE_INPUTS = Object.freeze({
    "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll": "candidate_core",
    "runtime/cf7-runtime-manifest.tsv": "candidate_runtime_manifest",
    "runtime/miniaudio.dll": "candidate_miniaudio"
});

class QualificationError extends Error {
    constructor(code, message) {
        super(message);
        this.name = "QualificationError";
        this.code = code;
    }
}

function fail(code, message) {
    throw new QualificationError(code, message);
}

function expect(condition, message) {
    if (!condition) fail("VALIDATION_FAILED", message);
}

function sortedClone(value) {
    if (Array.isArray(value)) return value.map(sortedClone);
    if (value && typeof value === "object") {
        const result = {};
        Object.keys(value).sort().forEach((key) => { result[key] = sortedClone(value[key]); });
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

function gitBlobOid(bytes, length) {
    const algorithm = length === 64 ? "sha256" : "sha1";
    const header = Buffer.from("blob " + bytes.length + "\0", "utf8");
    return crypto.createHash(algorithm).update(header).update(bytes).digest("hex");
}

function exactKeys(value, keys, label) {
    expect(value && typeof value === "object" && !Array.isArray(value), label + " must be an object");
    const actual = Object.keys(value).sort();
    const expected = keys.slice().sort();
    expect(JSON.stringify(actual) === JSON.stringify(expected), label + " keys differ");
}

function expectNonEmptyString(value, label, maxLength) {
    expect(typeof value === "string" && value.length > 0, label + " must be a non-empty string");
    if (maxLength) expect(value.length <= maxLength, label + " is too long");
}

function expectSha(value, label) {
    expect(typeof value === "string" && /^[A-F0-9]{64}$/.test(value), label + " must be uppercase SHA-256");
}

function expectBlobOid(value, label) {
    expect(typeof value === "string" && /^[0-9a-f]{40}(?:[0-9a-f]{24})?$/.test(value), label + " must be a lowercase Git object ID");
}

function expectRfc3339Utc(value, label) {
    expect(typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value), label + " must be RFC3339 UTC");
    const parsed = Date.parse(value);
    expect(Number.isFinite(parsed) && new Date(parsed).toISOString().slice(0, 19) === value.slice(0, 19), label + " is not a real UTC timestamp");
}

function safeRepoPath(value, label) {
    expectNonEmptyString(value, label, 4096);
    expect(!value.includes("\\") && !value.includes("\0") && !path.posix.isAbsolute(value), label + " must be a canonical repo-relative path");
    expect(path.posix.normalize(value) === value && !value.split("/").some((part) => part === "" || part === "." || part === ".."), label + " contains an unsafe segment");
    return value;
}

function sameFilesystemPath(left, right) {
    const a = path.resolve(left);
    const b = path.resolve(right);
    return process.platform === "win32" ? a.toLowerCase() === b.toLowerCase() : a === b;
}

function containedPath(root, relative, label) {
    safeRepoPath(relative, label);
    const absolute = path.resolve(root, relative.split("/").join(path.sep));
    const prefix = path.resolve(root) + path.sep;
    const comparable = process.platform === "win32" ? absolute.toLowerCase() : absolute;
    const comparablePrefix = process.platform === "win32" ? prefix.toLowerCase() : prefix;
    expect(comparable.startsWith(comparablePrefix), label + " escapes the replay root");
    return absolute;
}

function readRegularFile(file, label, maximumBytes) {
    expect(path.isAbsolute(file), label + " path must be absolute");
    let stat;
    try {
        stat = fs.lstatSync(file);
    } catch (error) {
        fail("VALIDATION_FAILED", label + " is unavailable: " + error.message);
    }
    expect(stat.isFile() && !stat.isSymbolicLink(), label + " must be a regular non-link file");
    expect(stat.size > 0 && stat.size <= maximumBytes, label + " byte size is outside the allowed bound");
    const real = fs.realpathSync.native(file);
    expect(sameFilesystemPath(file, real), label + " must use its canonical real path");
    const bytes = fs.readFileSync(real);
    expect(bytes.length === stat.size, label + " changed while being read");
    return bytes;
}

function parseCanonicalJson(file, label, maximumBytes) {
    const bytes = readRegularFile(file, label, maximumBytes || MAX_JSON_BYTES);
    let value;
    try {
        value = JSON.parse(bytes.toString("utf8"));
    } catch (error) {
        fail("VALIDATION_FAILED", label + " is not valid UTF-8 JSON: " + error.message);
    }
    expect(bytes.equals(canonicalBytes(value)), label + " is not canonical sorted JSON with two-space indent and terminal LF");
    return { bytes, value };
}

function validateReleaseSource(value, label) {
    exactKeys(value, ["commit", "treeOid"], label);
    expect(typeof value.commit === "string" && /^[0-9a-f]{40}$/.test(value.commit), label + ".commit invalid");
    expectBlobOid(value.treeOid, label + ".treeOid");
}

function validateArtifactDescriptor(value, expectedSchema, label) {
    exactKeys(value, ["blobOid", "bytes", "kind", "path", "schema", "sha256"], label);
    expect(value.kind === "tracked_blob", label + " must be tracked_blob");
    expectBlobOid(value.blobOid, label + ".blobOid");
    expect(Number.isInteger(value.bytes) && value.bytes > 0, label + ".bytes invalid");
    safeRepoPath(value.path, label + ".path");
    expect(value.schema === expectedSchema, label + ".schema mismatch");
    expectSha(value.sha256, label + ".sha256");
}

function verifyTrackedArtifact(value, expectedSchema, replayRoot, label) {
    validateArtifactDescriptor(value, expectedSchema, label);
    const file = containedPath(replayRoot, value.path, label + ".path");
    const bytes = readRegularFile(file, label, MAX_INPUT_BYTES);
    expect(bytes.length === value.bytes, label + " byte count mismatch");
    expect(sha256(bytes) === value.sha256, label + " SHA-256 mismatch");
    expect(gitBlobOid(bytes, value.blobOid.length) === value.blobOid, label + " Git blob OID mismatch");
    return bytes;
}

function validateMeasurement(measurement, label) {
    exactKeys(measurement, ["kind", "unit", "value"], label);
    expectNonEmptyString(measurement.unit, label + ".unit", 128);
    if (measurement.kind === "boolean") {
        expect(measurement.value === true, label + " passed boolean must be true");
    } else if (measurement.kind === "counter") {
        expect(Number.isSafeInteger(measurement.value) && measurement.value >= 0, label + " counter invalid");
    } else if (measurement.kind === "duration_ms") {
        expect(typeof measurement.value === "number" && Number.isFinite(measurement.value) && measurement.value >= 0, label + " duration invalid");
    } else if (measurement.kind === "ratio") {
        expect(typeof measurement.value === "number" && Number.isFinite(measurement.value) && measurement.value >= 0 && measurement.value <= 1, label + " ratio invalid");
    } else if (measurement.kind === "digest") {
        expectSha(measurement.value, label + ".value");
    } else if (measurement.kind === "identity" || measurement.kind === "text") {
        expectNonEmptyString(measurement.value, label + ".value", 4096);
    } else {
        fail("VALIDATION_FAILED", label + " has unknown measurement kind");
    }
}

function validateConfiguration(configuration, reportId) {
    exactKeys(configuration, ["argv", "environment", "reportId", "schema", "workingDirectory"], "configuration");
    expect(configuration.schema === "cf7.audio-v2.automated-report-configuration.v1", "configuration schema mismatch");
    expect(configuration.reportId === reportId, "configuration reportId mismatch");
    expect(configuration.workingDirectory === "release_source_root", "configuration working directory mismatch");
    expect(Array.isArray(configuration.argv) && configuration.argv.length >= 6 && configuration.argv.length <= 32, "configuration argv invalid");
    configuration.argv.forEach((entry) => expectNonEmptyString(entry, "configuration argv entry", 4096));
    expect(path.isAbsolute(configuration.argv[0]), "configuration Node executable must be absolute");
    const boundNode = configurationEnvironmentValue(configuration, NODE_EXE_ENV, true);
    expect(path.isAbsolute(boundNode) && sameFilesystemPath(configuration.argv[0], boundNode), "configuration Node executable differs from CF7_NODE_EXE");
    expect(JSON.stringify(configuration.argv.slice(1, 5)) === JSON.stringify([RUNNER_PATH, "--report-id", reportId, LIVE_OBSERVATION_ARG]), "configuration must bind the exact runner, reportId, and recoverable live observation carrier");
    const decodedCarrier = decodeConfigurationLiveObservation(configuration);
    if (ENDPOINT_REPORTS.has(reportId)) {
        const archived = qualificationObserver.validateJournalCarrier(decodedCarrier);
        expect(archived.observation.reportId === reportId, "candidate journal carrier reportId mismatch");
    }
    expect(Array.isArray(configuration.environment), "configuration environment invalid");
    const names = [];
    configuration.environment.forEach((entry, index) => {
        exactKeys(entry, ["name", "valueSha256"], "configuration environment " + index);
        expect(typeof entry.name === "string" && /^[A-Za-z_][A-Za-z0-9_]*$/.test(entry.name), "configuration environment name invalid");
        expectSha(entry.valueSha256, "configuration environment SHA");
        expect(!names.includes(entry.name), "configuration environment name duplicated");
        names.push(entry.name);
    });
    expect(!names.some((name) => name.indexOf("CF7_AUDIO_V2_LIVE_OBSERVATION") === 0), "live observation must be recoverable from tracked configuration bytes, not process environment");
    expect(JSON.stringify(names) === JSON.stringify(names.slice().sort()), "configuration environment names are not sorted");
}

function encodeLiveObservationArguments(value) {
    const bytes = canonicalBytes(value);
    expect(bytes.length > 0 && bytes.length <= MAX_ENV_BYTES, "live observation canonical bytes are outside the bound");
    const encoded = zlib.deflateRawSync(bytes, { level: 9 }).toString("base64");
    expect(encoded.length > 0 && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded), "live observation compression did not produce canonical base64");
    const chunks = [];
    for (let offset = 0; offset < encoded.length; offset += 4000) chunks.push(encoded.slice(offset, offset + 4000));
    expect(chunks.length > 0 && chunks.length <= 27, "compressed live observation does not fit the tracked configuration argv bound");
    return [LIVE_OBSERVATION_ARG].concat(chunks);
}

function decodeConfigurationLiveObservation(configuration) {
    expect(Array.isArray(configuration.argv) && configuration.argv[4] === LIVE_OBSERVATION_ARG, "configuration live observation carrier missing");
    expect(configuration.argv.filter((entry) => entry === LIVE_OBSERVATION_ARG).length === 1, "configuration live observation carrier must be unique");
    const chunks = configuration.argv.slice(5);
    expect(chunks.length > 0 && chunks.length <= 27, "compressed live observation chunk count is outside the bound");
    chunks.forEach((chunk) => expectNonEmptyString(chunk, "compressed live observation chunk", 4000));
    const encoded = chunks.join("");
    expect(encoded.length > 0 && encoded.length <= 27 * 4000, "compressed live observation is outside the configuration bound");
    expect(/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded), "compressed live observation is not canonical base64");
    const compressed = Buffer.from(encoded, "base64");
    expect(compressed.length > 0 && compressed.toString("base64") === encoded, "compressed live observation base64 round-trip mismatch");
    let bytes;
    try { bytes = zlib.inflateRawSync(compressed, { maxOutputLength: MAX_ENV_BYTES }); }
    catch (error) { fail("VALIDATION_FAILED", "compressed live observation cannot be decoded: " + error.message); }
    expect(bytes.length > 0 && bytes.length <= MAX_ENV_BYTES, "live observation decoded bytes are outside the bound");
    expect(zlib.deflateRawSync(bytes, { level: 9 }).equals(compressed), "compressed live observation is not the canonical deflate encoding or has trailing bytes");
    let value;
    try { value = JSON.parse(bytes.toString("utf8")); }
    catch (error) { fail("VALIDATION_FAILED", "live observation is not UTF-8 JSON: " + error.message); }
    expect(bytes.equals(canonicalBytes(value)), "live observation JSON is not canonical");
    return value;
}

function openCandidateRoot(candidateRoot) {
    expect(path.isAbsolute(candidateRoot), "candidate root must be absolute");
    const stat = fs.lstatSync(candidateRoot);
    expect(stat.isDirectory() && !stat.isSymbolicLink(), "candidate root must be a real directory");
    const real = fs.realpathSync.native(candidateRoot);
    expect(sameFilesystemPath(candidateRoot, real), "candidate root must use its canonical real path");
    return real;
}

function validateInputManifest(input, report, candidateRoot, replayRoot) {
    exactKeys(input, ["candidateBuildIdentity", "candidatePayloadClosure", "closureSha256", "inputs", "releaseSource", "reportId", "schema"], "input manifest");
    expect(input.schema === "cf7.audio-v2.automated-report-input-manifest.v1", "input manifest schema mismatch");
    expect(input.reportId === report.reportId, "input manifest reportId mismatch");
    expect(input.candidateBuildIdentity === report.candidateBuildIdentity && input.candidatePayloadClosure === report.candidatePayloadClosure, "input manifest candidate mismatch");
    validateReleaseSource(input.releaseSource, "input manifest release source");
    expect(JSON.stringify(input.releaseSource) === JSON.stringify(report.releaseSource), "input manifest release source mismatch");
    expectSha(input.closureSha256, "input manifest closureSha256");
    const requiredRoles = REPORT_INPUT_ROLES[report.reportId];
    expect(Array.isArray(input.inputs) && input.inputs.length === requiredRoles.length, "input manifest role count mismatch");
    const roles = [];
    const order = [];
    const candidatePaths = [];
    let sourceCount = 0;
    input.inputs.forEach((entry, index) => {
        expect(entry && typeof entry === "object" && !Array.isArray(entry), "input entry must be object");
        const tracked = entry.kind === "release_source_blob";
        exactKeys(entry, tracked ? ["blobOid", "bytes", "kind", "path", "role", "sha256"] : ["bytes", "kind", "path", "role", "sha256"], "input entry " + index);
        expect(entry.kind === "candidate_artifact" || tracked, "input kind must be candidate_artifact or release_source_blob");
        safeRepoPath(entry.path, "input path");
        expectNonEmptyString(entry.role, "input role", 256);
        expect(Number.isInteger(entry.bytes) && entry.bytes > 0 && entry.bytes <= MAX_INPUT_BYTES, "input bytes invalid");
        expectSha(entry.sha256, "input SHA");
        expect(!roles.includes(entry.role), "duplicate input role");
        roles.push(entry.role);
        const orderKey = entry.kind + ":" + entry.path;
        expect(!order.includes(orderKey), "duplicate input path");
        order.push(orderKey);
        let bytes;
        if (entry.kind === "candidate_artifact") {
            expect(EXPECTED_CANDIDATE_INPUTS[entry.path] === entry.role, "unexpected candidate input");
            const candidateFile = containedPath(candidateRoot, entry.path, "candidate input");
            bytes = readRegularFile(candidateFile, "candidate input " + entry.path, MAX_INPUT_BYTES);
            candidatePaths.push(entry.path);
        } else {
            expectBlobOid(entry.blobOid, "release-source input blobOid");
            const sourceFile = containedPath(replayRoot, entry.path, "release-source input");
            bytes = readRegularFile(sourceFile, "release-source input " + entry.path, MAX_INPUT_BYTES);
            expect(gitBlobOid(bytes, entry.blobOid.length) === entry.blobOid, "release-source input blobOid mismatch");
            sourceCount++;
        }
        expect(bytes.length === entry.bytes && sha256(bytes) === entry.sha256, "input bytes/SHA mismatch for " + entry.path);
    });
    expect(JSON.stringify(order) === JSON.stringify(order.slice().sort()), "input entries are not sorted by kind:path");
    expect(JSON.stringify(roles.slice().sort()) === JSON.stringify(requiredRoles.slice().sort()), "input role coverage mismatch");
    expect(JSON.stringify(candidatePaths.slice().sort()) === JSON.stringify(Object.keys(EXPECTED_CANDIDATE_INPUTS).sort()), "candidate input set mismatch");
    expect(sourceCount > 0, "input manifest has no release-source input");
    expect(sha256(canonicalBytes(input.inputs)) === input.closureSha256, "input closure mismatch");
}

function runtimeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash) {
    [artifactSourceHash, producerRecipeHash, toolchainLockHash].forEach((value) => expectSha(value, "runtime build identity component"));
    return sha256(Buffer.from(
        "artifactSourceHash\t" + artifactSourceHash + "\n" +
        "producerRecipeHash\t" + producerRecipeHash + "\n" +
        "toolchainLockHash\t" + toolchainLockHash + "\n",
        "utf8"
    ));
}

function runtimePayloadClosureHash(files) {
    expect(Array.isArray(files) && files.length > 0, "candidate payload file set must not be empty");
    const lowerPaths = [];
    const canonical = files.slice().sort((left, right) => left.path.localeCompare(right.path)).map((row) => {
        safeRepoPath(row.path, "candidate payload path");
        expect(!/[\t\r\n:*?"<>|]/.test(row.path), "candidate payload path contains a forbidden character");
        expect(Number.isSafeInteger(row.bytes) && row.bytes >= 0, "candidate payload byte count invalid");
        expectSha(row.sha256, "candidate payload SHA");
        const lower = row.path.toLowerCase();
        expect(!lowerPaths.includes(lower), "candidate payload path is duplicated or case-colliding");
        lowerPaths.push(lower);
        return row.path + "\t" + row.bytes + "\t" + row.sha256;
    }).join("\n") + "\n";
    return sha256(Buffer.from(canonical, "utf8"));
}

function readCandidateFile(candidateRoot, relative, label, maximumBytes) {
    const file = containedPath(candidateRoot, relative, label + " path");
    const components = relative.split("/");
    let cursor = candidateRoot;
    components.slice(0, -1).forEach((component) => {
        cursor = path.join(cursor, component);
        const stat = fs.lstatSync(cursor);
        expect(stat.isDirectory() && !stat.isSymbolicLink(), label + " traverses a link/reparse directory");
    });
    const bytes = readRegularFile(file, label, maximumBytes || MAX_INPUT_BYTES);
    const comparable = process.platform === "win32" ? fs.realpathSync.native(file).toLowerCase() : fs.realpathSync.native(file);
    const rootPrefix = (process.platform === "win32" ? candidateRoot.toLowerCase() : candidateRoot) + path.sep;
    expect(comparable.startsWith(rootPrefix), label + " resolves outside the candidate root");
    return bytes;
}

function validateCandidateManifest(candidateRoot, identity, closure) {
    const manifestBytes = readCandidateFile(candidateRoot, "runtime/cf7-runtime-manifest.tsv", "candidate runtime manifest", MAX_INPUT_BYTES);
    expect(!manifestBytes.includes(0x0D), "candidate runtime manifest must use LF, not CRLF");
    const lines = manifestBytes.toString("utf8").split("\n");
    expect(lines.pop() === "", "candidate runtime manifest must end with one LF");
    expect(lines[0] === "cf7-runtime-manifest-v2", "candidate runtime manifest header must be v2");
    const fields = {};
    const files = [];
    const allowed = ["artifactSourceHash", "buildIdentityHash", "payloadClosureHash", "producerRecipeHash", "publishMode", "toolchainBaseline", "toolchainLockHash"];
    lines.slice(1).forEach((line, index) => {
        const columns = line.split("\t");
        if (columns[0] === "file") {
            expect(columns.length === 4 && /^[0-9]+$/.test(columns[2]) && /^[A-F0-9]{64}$/.test(columns[3]), "invalid candidate manifest file row at line " + (index + 2));
            files.push({ bytes: Number(columns[2]), path: columns[1], sha256: columns[3] });
        } else {
            expect(columns.length === 2 && allowed.includes(columns[0]) && columns[1], "invalid candidate manifest field at line " + (index + 2));
            expect(!Object.prototype.hasOwnProperty.call(fields, columns[0]), "duplicate candidate manifest field " + columns[0]);
            fields[columns[0]] = columns[1];
        }
    });
    expect(JSON.stringify(Object.keys(fields).sort()) === JSON.stringify(allowed.slice().sort()), "candidate runtime manifest metadata set is incomplete");
    ["artifactSourceHash", "buildIdentityHash", "payloadClosureHash", "producerRecipeHash", "toolchainLockHash"].forEach((key) => expectSha(fields[key], "candidate runtime manifest " + key));
    expect(fields.publishMode === "framework-dependent" && fields.toolchainBaseline.length > 0, "candidate runtime manifest publish/toolchain metadata invalid");
    expect(runtimeBuildIdentityHash(fields.artifactSourceHash, fields.producerRecipeHash, fields.toolchainLockHash) === fields.buildIdentityHash, "candidate build identity is not recomputable");
    expect(runtimePayloadClosureHash(files) === fields.payloadClosureHash, "candidate payload closure is not recomputable");
    expect(fields.buildIdentityHash === identity && fields.payloadClosureHash === closure, "candidate manifest identity/closure differs from report");
    const sortedPaths = files.map((entry) => entry.path);
    expect(JSON.stringify(sortedPaths) === JSON.stringify(sortedPaths.slice().sort()), "candidate runtime manifest file rows are not sorted");

    const excluded = new Set([
        "runtime/cf7-runtime-manifest.tsv",
        "runtime/runtime-build-attestation.json",
        "runtime/runtime-release-consensus.json"
    ]);
    const actualPaths = [];
    const bootstrap = path.join(candidateRoot, "CRAZYFLASHER7MercenaryEmpire.exe");
    if (fs.existsSync(bootstrap)) actualPaths.push("CRAZYFLASHER7MercenaryEmpire.exe");
    const runtimeRoot = path.join(candidateRoot, "runtime");
    expect(fs.existsSync(runtimeRoot) && fs.lstatSync(runtimeRoot).isDirectory(), "candidate runtime directory missing");
    function walk(directory, relativeBase) {
        fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
            const full = path.join(directory, entry.name);
            const relative = relativeBase ? relativeBase + "/" + entry.name : "runtime/" + entry.name;
            const stat = fs.lstatSync(full);
            expect(!entry.isSymbolicLink() && !stat.isSymbolicLink(), "candidate payload contains a link/reparse entry " + relative);
            if (entry.isDirectory() && stat.isDirectory()) walk(full, relative);
            else {
                expect(entry.isFile() && stat.isFile(), "candidate payload contains a non-regular entry " + relative);
                if (!excluded.has(relative) && !relative.startsWith("runtime/attestations/")) actualPaths.push(relative);
            }
        });
    }
    walk(runtimeRoot, "");
    const actualFiles = actualPaths.sort().map((relative) => {
        const bytes = readCandidateFile(candidateRoot, relative, "candidate payload " + relative, MAX_INPUT_BYTES);
        return { bytes: bytes.length, path: relative, sha256: sha256(bytes) };
    });
    expect(JSON.stringify(actualFiles) === JSON.stringify(files), "candidate manifest differs from the exact full candidate payload");
    return { fields, files, manifestSha256: sha256(manifestBytes) };
}

function readPeAsciiZ(bytes, offset, label) {
    expect(Number.isInteger(offset) && offset >= 0 && offset < bytes.length, label + " offset invalid");
    let end = offset;
    while (end < bytes.length && bytes[end] !== 0 && end - offset <= 256) end++;
    expect(end < bytes.length && end > offset && end - offset <= 256, label + " is not a bounded zero-terminated name");
    const value = bytes.toString("ascii", offset, end);
    expect(/^[A-Za-z0-9_]+$/.test(value), label + " contains non-ASCII export characters");
    return value;
}

function parsePeExports(bytes) {
    expect(bytes.length >= 512 && bytes.readUInt16LE(0) === 0x5A4D, "candidate miniaudio is not a PE image");
    const peOffset = bytes.readUInt32LE(0x3C);
    expect(peOffset >= 0x40 && peOffset + 24 <= bytes.length && bytes.toString("ascii", peOffset, peOffset + 4) === "PE\0\0", "candidate miniaudio PE header invalid");
    expect(bytes.readUInt16LE(peOffset + 4) === 0x8664, "candidate miniaudio must be x64 PE");
    const sectionCount = bytes.readUInt16LE(peOffset + 6);
    const optionalSize = bytes.readUInt16LE(peOffset + 20);
    const optional = peOffset + 24;
    expect(sectionCount > 0 && sectionCount <= 96 && optional + optionalSize <= bytes.length, "candidate miniaudio PE section table invalid");
    expect(bytes.readUInt16LE(optional) === 0x20B && optionalSize >= 120, "candidate miniaudio must use PE32+ optional header");
    const exportRva = bytes.readUInt32LE(optional + 112);
    const exportSize = bytes.readUInt32LE(optional + 116);
    expect(exportRva > 0 && exportSize >= 40, "candidate miniaudio PE has no export directory");
    const sectionTable = optional + optionalSize;
    expect(sectionTable + sectionCount * 40 <= bytes.length, "candidate miniaudio PE section headers truncated");
    const sections = [];
    for (let index = 0; index < sectionCount; index++) {
        const offset = sectionTable + index * 40;
        sections.push({
            rawOffset: bytes.readUInt32LE(offset + 20),
            rawSize: bytes.readUInt32LE(offset + 16),
            virtualAddress: bytes.readUInt32LE(offset + 12),
            virtualSize: bytes.readUInt32LE(offset + 8)
        });
    }
    function rvaToOffset(rva, length, label) {
        const section = sections.find((entry) => rva >= entry.virtualAddress && rva + length <= entry.virtualAddress + Math.max(entry.virtualSize, entry.rawSize));
        expect(section, label + " RVA is outside PE sections");
        const offset = section.rawOffset + (rva - section.virtualAddress);
        expect(offset >= 0 && offset + length <= bytes.length && offset + length <= section.rawOffset + section.rawSize, label + " RVA maps outside raw bytes");
        return offset;
    }
    const directory = rvaToOffset(exportRva, 40, "export directory");
    const nameCount = bytes.readUInt32LE(directory + 24);
    const namesRva = bytes.readUInt32LE(directory + 32);
    expect(nameCount > 0 && nameCount <= 4096, "candidate miniaudio export count invalid");
    const namesOffset = rvaToOffset(namesRva, nameCount * 4, "export name table");
    const names = [];
    for (let index = 0; index < nameCount; index++) {
        const nameRva = bytes.readUInt32LE(namesOffset + index * 4);
        names.push(readPeAsciiZ(bytes, rvaToOffset(nameRva, 1, "export name"), "export name"));
    }
    expect(new Set(names).size === names.length, "candidate miniaudio has duplicate export names");
    return names.sort();
}

function validateCandidateBinary(candidateRoot, identity, closure) {
    const manifest = validateCandidateManifest(candidateRoot, identity, closure);
    const miniaudioBytes = readCandidateFile(candidateRoot, "runtime/miniaudio.dll", "candidate miniaudio DLL", MAX_INPUT_BYTES);
    const exports = parsePeExports(miniaudioBytes);
    expect(JSON.stringify(exports) === JSON.stringify(EXPECTED_V2_EXPORTS), "candidate miniaudio export set differs from the exact Audio v2 ABI");
    return {
        exportSetSha256: sha256(canonicalBytes(exports)),
        manifestSha256: manifest.manifestSha256,
        miniaudioSha256: sha256(miniaudioBytes)
    };
}

function configurationEnvironmentValue(configuration, name, required) {
    const binding = configuration.environment.find((entry) => entry.name === name);
    if (!binding) {
        if (required) fail("PREREQUISITE_MISSING", "configuration does not bind required environment " + name);
        return null;
    }
    const value = process.env[name];
    if (typeof value !== "string") fail("PREREQUISITE_MISSING", "required environment value is unavailable: " + name);
    expect(sha256(Buffer.from(value, "utf8")) === binding.valueSha256, "environment value drift: " + name);
    return value;
}

function decodeCanonicalEnvironmentJson(configuration, name, required) {
    const encoded = configurationEnvironmentValue(configuration, name, required);
    if (encoded === null) return null;
    expect(encoded.length > 0 && encoded.length <= Math.ceil(MAX_ENV_BYTES / 3) * 4, name + " encoded value is outside the bound");
    expect(/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded), name + " is not canonical base64");
    const bytes = Buffer.from(encoded, "base64");
    expect(bytes.length > 0 && bytes.length <= MAX_ENV_BYTES && bytes.toString("base64") === encoded, name + " base64 round-trip mismatch");
    let value;
    try { value = JSON.parse(bytes.toString("utf8")); } catch (error) { fail("VALIDATION_FAILED", name + " is not UTF-8 JSON: " + error.message); }
    expect(bytes.equals(canonicalBytes(value)), name + " JSON is not canonical");
    return value;
}

function validateNoVerdictFields(value, label) {
    if (Array.isArray(value)) {
        value.forEach((entry, index) => validateNoVerdictFields(entry, label + "[" + index + "]"));
        return;
    }
    if (!value || typeof value !== "object") {
        expect(value !== "passed" && value !== "success" && value !== "ok", label + " contains a pre-written verdict");
        return;
    }
    Object.keys(value).forEach((key) => {
        expect(!["passed", "result", "success", "ok", "allGreen"].includes(key), label + " contains forbidden verdict field " + key);
        validateNoVerdictFields(value[key], label + "." + key);
    });
}

function validateToolDescriptor(value, label) {
    exactKeys(value, ["path", "sha256"], label);
    expect(path.isAbsolute(value.path), label + ".path must be absolute");
    expectSha(value.sha256, label + ".sha256");
    const bytes = readRegularFile(path.resolve(value.path), label, MAX_INPUT_BYTES);
    expect(sha256(bytes) === value.sha256, label + " executable/script SHA mismatch");
    return path.resolve(value.path);
}

function validateToolchain(configuration) {
    const value = decodeCanonicalEnvironmentJson(configuration, TOOLCHAIN_ENV, true);
    exactKeys(value, ["cl", "cmd", "dotnet", "msvcToolsVersion", "node", "nodeVersion", "powershell", "schema", "vcvars64", "windowsSdkVersion"], "toolchain");
    expect(value.schema === "cf7.audio-v2.qualification-toolchain.v1", "toolchain schema mismatch");
    expectNonEmptyString(value.msvcToolsVersion, "toolchain msvcToolsVersion", 64);
    expect(typeof value.nodeVersion === "string" && /^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$/.test(value.nodeVersion), "toolchain nodeVersion invalid");
    expectNonEmptyString(value.windowsSdkVersion, "toolchain windowsSdkVersion", 64);
    const node = validateToolDescriptor(value.node, "toolchain node");
    const boundNode = configurationEnvironmentValue(configuration, NODE_EXE_ENV, true);
    expect(path.isAbsolute(boundNode) && sameFilesystemPath(boundNode, node), "toolchain node differs from CF7_NODE_EXE");
    expect(sameFilesystemPath(process.execPath, node), "qualification runner was not launched by the bound Node executable");
    expect(process.version === value.nodeVersion, "qualification runner Node version differs from the bound toolchain");
    const observedVersion = cp.spawnSync(node, ["--version"], {
        encoding: "utf8", env: {}, maxBuffer: 1024 * 1024, timeout: 15000, windowsHide: true
    });
    expect(!observedVersion.error && observedVersion.status === 0, "bound Node executable version probe failed");
    expect(String(observedVersion.stdout || "").trim() === value.nodeVersion && !String(observedVersion.stderr || "").trim(), "bound Node executable version output drifted");
    return {
        cl: validateToolDescriptor(value.cl, "toolchain cl"),
        cmd: validateToolDescriptor(value.cmd, "toolchain cmd"),
        dotnet: validateToolDescriptor(value.dotnet, "toolchain dotnet"),
        msvcToolsVersion: value.msvcToolsVersion,
        node,
        nodeVersion: value.nodeVersion,
        powershell: validateToolDescriptor(value.powershell, "toolchain powershell"),
        vcvars64: validateToolDescriptor(value.vcvars64, "toolchain vcvars64"),
        windowsSdkVersion: value.windowsSdkVersion
    };
}

function validateLiveObservation(context) {
    const decodedCarrier = decodeConfigurationLiveObservation(context.configurationBinding.value);
    const value = ENDPOINT_REPORTS.has(context.report.reportId)
        ? qualificationObserver.validateJournalCarrier(decodedCarrier).observation
        : decodedCarrier;
    exactKeys(value, [
        "candidateBuildIdentity", "candidatePayloadClosure", "caseFacts", "candidateProcess",
        "generatedAtUtc", "releaseSource", "reportId", "runId", "schema", "session"
    ], "live observation");
    expect(value.schema === "cf7.audio-v2.live-observation.v2", "live observation schema mismatch");
    expect(value.reportId === context.report.reportId, "live observation reportId mismatch");
    expect(value.candidateBuildIdentity === context.report.candidateBuildIdentity && value.candidatePayloadClosure === context.report.candidatePayloadClosure, "live observation candidate mismatch");
    expect(JSON.stringify(value.releaseSource) === JSON.stringify(context.report.releaseSource), "live observation release source mismatch");
    expectRfc3339Utc(value.generatedAtUtc, "live observation generatedAtUtc");
    expect(value.generatedAtUtc === context.report.generatedAtUtc, "live observation/report timestamp mismatch");
    expectNonEmptyString(value.runId, "live observation runId", 128);
    expect(typeof value.session === "object" && value.session && !Array.isArray(value.session), "live observation session missing");
    validateNoVerdictFields(value.session, "live observation session");
    expect(Array.isArray(value.caseFacts) && value.caseFacts.length === REPORT_CASES[value.reportId].length, "live observation caseFacts count mismatch");
    value.caseFacts.forEach((entry, index) => {
        exactKeys(entry, ["caseId", "facts"], "live observation case " + index);
        expect(entry.caseId === REPORT_CASES[value.reportId][index], "live observation case order mismatch");
        expect(entry.facts && typeof entry.facts === "object" && !Array.isArray(entry.facts), "live observation facts must be an object");
        validateNoVerdictFields(entry.facts, "live observation facts " + entry.caseId);
    });
    if (ENDPOINT_REPORTS.has(value.reportId)) expect(value.candidateProcess && typeof value.candidateProcess === "object", "endpoint report requires an exact candidate process observation");
    else expect(value.candidateProcess === null, "non-endpoint report must not claim an unverified candidate process");
    return value;
}

function inspectWindowsProcess(candidateRoot, observation, toolchain) {
    exactKeys(observation, ["executableSha256", "observedAtUtc", "pid", "processStartUtc"], "candidate process observation");
    expect(Number.isSafeInteger(observation.pid) && observation.pid > 0, "candidate process PID invalid");
    expectSha(observation.executableSha256, "candidate process executable SHA");
    expectRfc3339Utc(observation.observedAtUtc, "candidate process observedAtUtc");
    expectRfc3339Utc(observation.processStartUtc, "candidate process processStartUtc");
    const script = "$ErrorActionPreference='Stop';$p=Get-Process -Id " + observation.pid + " -ErrorAction Stop;" +
        "[ordered]@{id=$p.Id;path=$p.Path;startUtc=$p.StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')}|ConvertTo-Json -Compress";
    const executed = cp.spawnSync(toolchain.powershell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script], {
        encoding: "utf8", env: {}, maxBuffer: 1024 * 1024, timeout: 15000, windowsHide: true
    });
    if (executed.error || executed.status !== 0) fail("PREREQUISITE_MISSING", "exact candidate process is not inspectable/alive");
    let actual;
    try { actual = JSON.parse(executed.stdout); } catch (error) { fail("VALIDATION_FAILED", "candidate process inspection returned invalid JSON"); }
    expect(actual.id === observation.pid && typeof actual.path === "string" && typeof actual.startUtc === "string", "candidate process inspection fields invalid");
    const expectedPath = path.join(candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe");
    expect(sameFilesystemPath(actual.path, expectedPath), "observed process is not the exact candidate Core executable");
    const executableBytes = readCandidateFile(candidateRoot, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", "candidate Core executable", MAX_INPUT_BYTES);
    expect(sha256(executableBytes) === observation.executableSha256, "candidate process executable SHA mismatch");
    expect(Date.parse(actual.startUtc) === Date.parse(observation.processStartUtc), "candidate process start identity mismatch");
    expect(Date.parse(observation.observedAtUtc) >= Date.parse(observation.processStartUtc) && Date.parse(observation.observedAtUtc) <= Date.now() + 1000, "candidate process observation time invalid");
    return {
        executablePath: actual.path,
        executableSha256: observation.executableSha256,
        pid: observation.pid,
        processStartUtc: observation.processStartUtc
    };
}

function dependencyFile(context, relative, label) {
    expect(context.dependencies.dependencies.some((entry) => entry.path === relative), label + " is absent from the reviewed dependency closure");
    return containedPath(context.replayRoot, relative, label);
}

function exactSfxPerEntryVoiceCap(context) {
    const sourcePath = dependencyFile(context, AUDIO_NATIVE_SOURCE_PATH, "native per-entry SFX voice-cap source");
    const bytes = readRegularFile(sourcePath, "native per-entry SFX voice-cap source", MAX_INPUT_BYTES);
    const text = bytes.toString("utf8");
    const matches = Array.from(text.matchAll(/^#define CF7_SFX_VOICES ([1-9][0-9]*)u$/gm));
    expect(matches.length === 1, "exact S must define CF7_SFX_VOICES exactly once");
    const value = Number(matches[0][1]);
    expect(Number.isSafeInteger(value) && value === 4,
        "exact S per-entry CF7_SFX_VOICES cap differs from the accepted H1 value 4");
    return value;
}

function childEnvironment(context, toolchain) {
    const configuration = context.configurationBinding.value;
    const systemRoot = configurationEnvironmentValue(configuration, "SystemRoot", true);
    const temp = configurationEnvironmentValue(configuration, "TEMP", true);
    const tmp = configurationEnvironmentValue(configuration, "TMP", true);
    expect(path.isAbsolute(systemRoot) && path.isAbsolute(temp) && path.isAbsolute(tmp), "bound system/temp environment paths must be absolute");
    const node = configurationEnvironmentValue(configuration, NODE_EXE_ENV, true);
    expect(path.isAbsolute(node) && sameFilesystemPath(node, toolchain.node), "child Node executable differs from the bound toolchain");
    const env = {
        CF7_CL_EXE: toolchain.cl,
        CF7_MSVC_TOOLS_VERSION: toolchain.msvcToolsVersion,
        CF7_VCVARS64: toolchain.vcvars64,
        CF7_WINDOWS_SDK_VERSION: toolchain.windowsSdkVersion,
        ComSpec: toolchain.cmd,
        DOTNET_CLI_TELEMETRY_OPTOUT: "1",
        DOTNET_CLI_HOME: temp,
        DOTNET_MULTILEVEL_LOOKUP: "0",
        DOTNET_NOLOGO: "1",
        DOTNET_ROOT: path.dirname(toolchain.dotnet),
        [NODE_EXE_ENV]: node,
        LANG: "en_US.UTF-8",
        SystemRoot: systemRoot,
        TEMP: temp,
        TMP: tmp,
        WINDIR: systemRoot
    };
    const requiresNuget = ["csharp_capability_catalog_bridge", "launcher_affected_regression"].includes(context.report.reportId);
    const nuget = configurationEnvironmentValue(configuration, "NUGET_PACKAGES", requiresNuget);
    if (nuget !== null) {
        expect(path.isAbsolute(nuget), "NUGET_PACKAGES must be absolute");
        env.NUGET_PACKAGES = nuget;
    }
    return env;
}

function executeBound(context, executable, args, toolchain, timeoutMs) {
    assertWithinDeadline(context.deadlineEpochMs, "source probe");
    const remaining = Math.max(1, context.deadlineEpochMs - Date.now());
    const executed = cp.spawnSync(executable, args, {
        cwd: context.replayRoot,
        encoding: "utf8",
        env: childEnvironment(context, toolchain),
        maxBuffer: 8 * 1024 * 1024,
        timeout: Math.min(timeoutMs, remaining),
        windowsHide: true
    });
    if (executed.error) {
        if (executed.error.code === "ETIMEDOUT") fail("TIMEOUT", "source probe timed out");
        fail("PREREQUISITE_MISSING", "source probe could not execute: " + executed.error.message);
    }
    if (executed.status !== 0) {
        const diagnostic = String(executed.stderr || executed.stdout || "").replace(/[\r\n]+/g, " ").slice(0, 1000);
        fail("LIVE_PROBE_FAILED", "bound source probe exited " + executed.status + (diagnostic ? ": " + diagnostic : ""));
    }
    return String(executed.stdout || "") + "\n" + String(executed.stderr || "");
}

function parseDotnetSummary(output, label) {
    const matches = Array.from(output.matchAll(/Failed:\s*(\d+)\s*,\s*Passed:\s*(\d+)\s*,\s*Skipped:\s*(\d+)/g));
    expect(matches.length > 0, label + " did not emit a test summary");
    const totals = matches.reduce((accumulator, match) => ({
        failed: accumulator.failed + Number(match[1]),
        passed: accumulator.passed + Number(match[2]),
        skipped: accumulator.skipped + Number(match[3])
    }), { failed: 0, passed: 0, skipped: 0 });
    expect(totals.failed === 0 && totals.passed > 0 && totals.skipped === 0, label + " has failures, no tests, or skips");
    return totals;
}

function compileAndRunNativeRuntimeContract(context, toolchain) {
    const source = dependencyFile(context, "launcher/native/tests/audio_bridge_v2_runtime_contract.c", "native runtime contract source");
    const header = dependencyFile(context, AUDIO_ABI_HEADER_PATH, "Audio ABI header");
    const buildRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-runtime-contract-"));
    try {
        const object = path.join(buildRoot, "runtime-contract.obj");
        const executable = path.join(buildRoot, "runtime-contract.exe");
        [source, header, object, executable, toolchain.cl, toolchain.vcvars64].forEach((value) => expect(!value.includes('"'), "native contract path contains a quote"));
        const command = [
            "call \"" + toolchain.vcvars64 + "\" " + toolchain.windowsSdkVersion + " -vcvars_ver=" + toolchain.msvcToolsVersion + " >nul",
            "\"" + toolchain.cl + "\" /nologo /TC /std:c17 /W4 /WX /utf-8 /I\"" + path.dirname(header) + "\" /c \"" + source + "\" /Fo\"" + object + "\"",
            "\"" + toolchain.cl + "\" /nologo \"" + object + "\" bcrypt.lib /Fe:\"" + executable + "\""
        ].join(" && ");
        executeBound(context, toolchain.cmd, ["/d", "/s", "/c", command], toolchain, 2 * 60 * 1000);
        return executeBound(context, executable, [path.join(context.candidateRoot, "runtime", "miniaudio.dll"), context.replayRoot], toolchain, 10 * 60 * 1000);
    } finally { fs.rmSync(buildRoot, { recursive: true, force: true }); }
}

function compileAndRunBackendPolicyContract(context, toolchain) {
    const source = dependencyFile(context, "launcher/native/tests/audio_backend_policy_contract.c", "backend policy contract source");
    const policy = dependencyFile(context, "launcher/native/audio_backend_policy.c", "backend policy source");
    dependencyFile(context, "launcher/native/audio_backend_policy.h", "backend policy header");
    const buildRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-backend-contract-"));
    try {
        const sourceObject = path.join(buildRoot, "contract.obj");
        const policyObject = path.join(buildRoot, "policy.obj");
        const executable = path.join(buildRoot, "backend-contract.exe");
        const include = path.dirname(policy);
        [source, policy, sourceObject, policyObject, executable, include, toolchain.cl, toolchain.vcvars64].forEach((value) => expect(!value.includes('"'), "backend contract path contains a quote"));
        const command = [
            "call \"" + toolchain.vcvars64 + "\" " + toolchain.windowsSdkVersion + " -vcvars_ver=" + toolchain.msvcToolsVersion + " >nul",
            "\"" + toolchain.cl + "\" /nologo /TC /std:c17 /W4 /WX /utf-8 /I\"" + include + "\" /c \"" + source + "\" /Fo\"" + sourceObject + "\"",
            "\"" + toolchain.cl + "\" /nologo /TC /std:c17 /W4 /WX /utf-8 /I\"" + include + "\" /c \"" + policy + "\" /Fo\"" + policyObject + "\"",
            "\"" + toolchain.cl + "\" /nologo \"" + sourceObject + "\" \"" + policyObject + "\" /Fe:\"" + executable + "\""
        ].join(" && ");
        executeBound(context, toolchain.cmd, ["/d", "/s", "/c", command], toolchain, 2 * 60 * 1000);
        return executeBound(context, executable, [], toolchain, 60 * 1000);
    } finally { fs.rmSync(buildRoot, { recursive: true, force: true }); }
}

function recomputeAs2AudioProbe(context) {
    const bridge = fs.readFileSync(dependencyFile(context, "scripts/类定义/org/flashNight/arki/audio/AudioBridge.as", "AS2 AudioBridge source"), "utf8");
    const manager = fs.readFileSync(dependencyFile(context, "scripts/类定义/org/flashNight/arki/audio/SoundEffectManager.as", "AS2 SoundEffectManager source"), "utf8");
    const server = fs.readFileSync(dependencyFile(context, "scripts/类定义/org/flashNight/neur/Server/ServerManager.as", "AS2 ServerManager source"), "utf8");
    const router = fs.readFileSync(dependencyFile(context, "launcher/src/Bus/MessageRouter.cs", "C# MessageRouter source"), "utf8");
    const suite = fs.readFileSync(dependencyFile(context, "scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeV2Test.as", "AS2 Audio v2 suite"), "utf8");
    ["\"bgm_play\"", "\"bgm_stop\"", "\"bgm_vol\"", "\"bgm_loop\"", "\"master_vol\""].forEach((token) => expect(!bridge.includes(token) && !manager.includes(token), "AS2 source contains legacy wire token " + token));
    expect(/_sm\.sendTaskToNode\("audio", request, null\)/.test(bridge) && bridge.includes('"S2|"'), "AS2 source lacks strict v2 send/frame contract");
    expect(!/\bconnectionGeneration\s*[:=]/.test(bridge) && !/\bconnectionGeneration\s*[:=]/.test(manager), "AS2 source leaks transport generation into audio state");
    expect(router.includes("DuplicatePropertyNameHandling.Error"), "C# router does not reject duplicate JSON fields");
    expect(server.includes('taskType == "audio"') && server.includes("message[key] = payload[key]"), "ServerManager lacks audio-only flattened task fields");
    const assertionNames = Array.from(suite.matchAll(/assert(?:True|False|Equal)\(\s*"([^"]+)"/g)).map((match) => match[1]);
    expect(assertionNames.length >= 80 && assertionNames.length <= 256 && new Set(assertionNames).size === assertionNames.length, "AS2 Audio v2 assertion matrix/names drifted");
    return {
        assertionCount: assertionNames.length,
        assertionNames,
        assertionNamesSha256: sha256(canonicalBytes(assertionNames)),
        profile: "as2_audio_v2_static_and_fresh_trace_v1"
    };
}

function runDefaultSourceProbe(context, toolchain) {
    const reportId = context.report.reportId;
    if (reportId === "native_abi_decoder_lifecycle") {
        const output = compileAndRunNativeRuntimeContract(context, toolchain);
        const match = /audio bridge v2 runtime contract PASS checks=(\d+) initCategory=(\d+)/.exec(output);
        expect(match && Number(match[1]) >= 150, "native runtime contract did not prove the reviewed assertion matrix");
        return { assertionCount: Number(match[1]), deviceInitCategory: Number(match[2]), profile: "native_runtime_contract_v1" };
    }
    if (reportId === "production_backend_device_fault_injection") {
        const output = compileAndRunBackendPolicyContract(context, toolchain);
        expect(/audio backend policy contract PASS/.test(output), "backend policy contract marker missing");
        const source = fs.readFileSync(dependencyFile(context, "launcher/native/tests/audio_backend_policy_contract.c", "backend policy contract source"), "utf8");
        const assertionCount = (source.match(/\bCHECK\s*\(/g) || []).length;
        expect(assertionCount >= 20, "backend policy contract assertion matrix is unexpectedly small");
        return { assertionCount, profile: "production_backend_policy_contract_v1" };
    }
    if (reportId === "csharp_capability_catalog_bridge") {
        dependencyFile(context, "launcher/tests/Launcher.Tests.csproj", "C# test project");
        const output = executeBound(context, toolchain.dotnet, [
            "test", "launcher/tests/Launcher.Tests.csproj", "--configuration", "Release", "-p:RestoreLockedMode=true",
            "--filter", "FullyQualifiedName~Audio|FullyQualifiedName~MessageRouterStrictJson|FullyQualifiedName~XmlSocketAudioV2|FullyQualifiedName~AudioTaskV2",
            "--logger", "console;verbosity=minimal"
        ], toolchain, 12 * 60 * 1000);
        const totals = parseDotnetSummary(output, "C# Audio v2 suite");
        expect(totals.passed >= 100, "C# Audio v2 suite is below the reviewed affected-test floor");
        return { assertionCount: totals.passed, profile: "csharp_audio_focused_dotnet_v1", skippedCount: totals.skipped };
    }
    if (reportId === "as2_wire_publish") {
        return recomputeAs2AudioProbe(context);
    }
    if (reportId === "launcher_affected_regression") {
        dependencyFile(context, "launcher/tests/Launcher.Tests.csproj", "Launcher test project");
        const output = executeBound(context, toolchain.dotnet, [
            "test", "launcher/tests/Launcher.Tests.csproj", "--configuration", "Release", "-p:RestoreLockedMode=true",
            "--filter", "FullyQualifiedName~Audio|FullyQualifiedName~MessageRouterStrictJson|FullyQualifiedName~XmlSocketAudioV2|FullyQualifiedName~AudioTaskV2",
            "--logger", "console;verbosity=minimal"
        ], toolchain, 15 * 60 * 1000);
        const totals = parseDotnetSummary(output, "Launcher regression suite");
        expect(totals.passed >= 100, "Launcher affected regression suite is below the reviewed test floor");
        return { assertionCount: totals.passed, profile: "launcher_audio_affected_regression_v1", skippedCount: totals.skipped };
    }
    fail("VALIDATION_FAILED", "no bound source probe profile for " + reportId);
}

function validateSourceObservation(context, observation, sourceProbe, toolchain) {
    exactKeys(observation.session, ["executionKind", "toolchainSha256"], "source observation session");
    expect(observation.session.executionKind === "recomputed_bound_source_probe", "source observation execution kind mismatch");
    const toolchainValue = decodeCanonicalEnvironmentJson(context.configurationBinding.value, TOOLCHAIN_ENV, true);
    expect(observation.session.toolchainSha256 === sha256(canonicalBytes(toolchainValue)), "source observation toolchain binding mismatch");
    observation.caseFacts.forEach((entry) => {
        const checks = CASE_CHECKS[observation.reportId][entry.caseId];
        if (observation.reportId === "as2_wire_publish" && entry.caseId === "asloader_publish_smoke") {
            exactKeys(entry.facts, ["assertionIds", "freshTraceBase64", "freshTraceSha256", "publishedSwfBytes", "publishedSwfSha256", "traceObservedAtUtc"], "AS2 publish facts");
            expectSha(entry.facts.freshTraceSha256, "AS2 fresh trace SHA");
            expectSha(entry.facts.publishedSwfSha256, "AS2 published SWF SHA");
            expect(Number.isSafeInteger(entry.facts.publishedSwfBytes) && entry.facts.publishedSwfBytes > 0, "AS2 published SWF byte count invalid");
            expectRfc3339Utc(entry.facts.traceObservedAtUtc, "AS2 trace observed time");
            expect(Math.abs(Date.parse(entry.facts.traceObservedAtUtc) - Date.parse(observation.generatedAtUtc)) <= 15 * 60 * 1000, "AS2 trace is not fresh for this run");
            expect(typeof entry.facts.freshTraceBase64 === "string" && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(entry.facts.freshTraceBase64), "AS2 fresh trace base64 invalid");
            const traceBytes = Buffer.from(entry.facts.freshTraceBase64, "base64");
            expect(traceBytes.length > 0 && traceBytes.length <= 1024 * 1024 && traceBytes.toString("base64") === entry.facts.freshTraceBase64 && sha256(traceBytes) === entry.facts.freshTraceSha256, "AS2 fresh trace byte binding mismatch");
            const trace = traceBytes.toString("utf8");
            expect(Buffer.from(trace, "utf8").equals(traceBytes), "AS2 fresh trace is not valid UTF-8");
            expect(trace.split(/\r?\n/).includes("AudioBridgeV2Test Tests Passed: " + sourceProbe.assertionCount) && trace.split(/\r?\n/).includes("AudioBridgeV2Test Tests Failed: 0"), "AS2 fresh trace lacks the exact source-derived pass/fail markers");
            const passLines = trace.replace(/\r\n/g, "\n").split("\n").filter((line) => line.startsWith("[PASS] "));
            const failureLines = trace.replace(/\r\n/g, "\n").split("\n").filter((line) => line.startsWith("[TEST_FAIL] "));
            expect(sourceProbe.profile === "as2_audio_v2_static_and_fresh_trace_v1" && sourceProbe.assertionCount === sourceProbe.assertionNames.length && Array.isArray(sourceProbe.assertionNames) && sourceProbe.assertionNamesSha256 === sha256(canonicalBytes(sourceProbe.assertionNames)), "AS2 recomputed assertion inventory is invalid");
            expect(passLines.length === sourceProbe.assertionCount && failureLines.length === 0, "AS2 fresh trace must contain every source-derived PASS line and no failure lines");
            sourceProbe.assertionNames.forEach((name) => {
                const prefix = "[PASS] " + name;
                expect(passLines.filter((line) => line === prefix || line.startsWith(prefix + " expected=")).length === 1, "AS2 fresh trace is missing/duplicating assertion: " + name);
            });
            const published = inputByRole(context, "as2_publish_plan");
            const publishedBytes = readRegularFile(published.file, "AS2 published SWF input", MAX_INPUT_BYTES);
            expect(publishedBytes.length === entry.facts.publishedSwfBytes && sha256(publishedBytes) === entry.facts.publishedSwfSha256, "AS2 published SWF identity differs from source-bound input");
        } else {
            exactKeys(entry.facts, ["assertionIds"], "source case facts " + entry.caseId);
        }
        expect(JSON.stringify(entry.facts.assertionIds) === JSON.stringify(checks), "source case assertion mapping differs from frozen checks");
    });
    return {
        probe: sourceProbe,
        toolchainSha256: observation.session.toolchainSha256
    };
}

function endpointCaptureMap(context) {
    const result = {};
    const captureIds = new Set();
    Object.values(CASE_CAPTURES[context.report.reportId] || {}).forEach((ids) => ids.forEach((id) => captureIds.add(id)));
    Array.from(captureIds).sort().forEach((captureId) => {
        result[captureId] = validateCaptureConfiguration(captureId, context.report, context.replayRoot);
    });
    return result;
}

function requireInteger(value, label, minimum) {
    expect(Number.isSafeInteger(value) && value >= (minimum || 0), label + " must be an integer >= " + (minimum || 0));
}

function validateEndpointCaseFacts(reportId, caseId, facts, captures) {
    const captureIds = CASE_CAPTURES[reportId][caseId];
    const expectedCapture = captureIds[0];
    function bindCapture(value) {
        expect(value === expectedCapture && captures[value], "endpoint facts capture binding mismatch for " + caseId);
    }
    if (caseId === "bgm_playback") {
        exactKeys(facts, ["captureId", "cursorFrames", "playing", "requestId", "startCategory"], "bgm playback facts");
        bindCapture(facts.captureId); requireInteger(facts.cursorFrames, "bgm cursor", 1); expect(facts.playing === 1 && facts.startCategory === 0, "BGM did not start successfully"); expectNonEmptyString(facts.requestId, "BGM requestId", 128);
    } else if (caseId === "bgm_seek") {
        exactKeys(facts, ["captureId", "cursorAfterFrames", "cursorBeforeFrames", "requestId", "seekCategory", "targetFrames"], "bgm seek facts");
        bindCapture(facts.captureId); ["cursorAfterFrames", "cursorBeforeFrames", "targetFrames"].forEach((key) => requireInteger(facts[key], "bgm seek " + key, key === "cursorBeforeFrames" ? 0 : 1));
        expect(facts.seekCategory === 0 && facts.cursorAfterFrames >= facts.targetFrames && facts.cursorAfterFrames !== facts.cursorBeforeFrames, "BGM seek telemetry did not advance to target"); expectNonEmptyString(facts.requestId, "BGM seek requestId", 128);
    } else if (caseId === "bgm_crossfade") {
        exactKeys(facts, ["captureId", "gapMs", "maxGapMs", "newSourceFrames", "oldSourceFrames"], "BGM crossfade facts");
        bindCapture(facts.captureId); ["gapMs", "maxGapMs", "newSourceFrames", "oldSourceFrames"].forEach((key) => requireInteger(facts[key], "crossfade " + key, key.endsWith("Frames") ? 1 : 0));
        expect(facts.maxGapMs > 0 && facts.gapMs <= facts.maxGapMs, "BGM crossfade has an unbounded gap");
    } else if (["format_vorbis", "format_aac_mp4", "format_opus"].includes(caseId)) {
        exactKeys(facts, ["captureId", "codec", "container", "decodedFrames", "decoderBackend"], "format endpoint facts");
        bindCapture(facts.captureId); requireInteger(facts.decodedFrames, "format decoded frames", 1);
        const expected = {
            format_vorbis: ["vorbis", "ogg", "libvorbis"],
            format_aac_mp4: ["aac", "iso_bmff", "media_foundation"],
            format_opus: ["opus", "ogg", "libopus"]
        }[caseId];
        expect(JSON.stringify([facts.codec, facts.container, facts.decoderBackend]) === JSON.stringify(expected), "endpoint decoder telemetry mismatch for " + caseId);
    } else if (caseId === "sfx_playback") {
        exactKeys(facts, ["captureId", "playedAfter", "playedBefore", "requestedVoices"], "SFX playback facts");
        bindCapture(facts.captureId); ["playedAfter", "playedBefore", "requestedVoices"].forEach((key) => requireInteger(facts[key], "SFX " + key, key === "requestedVoices" ? 1 : 0));
        expect(facts.playedAfter - facts.playedBefore === facts.requestedVoices, "SFX played counter delta mismatch");
    } else if (caseId === "dense_overlap_throttle") {
        exactKeys(facts, ["captureId", "configuredPerEntryVoiceCap", "playedAfter", "playedBefore", "requestedVoices", "throttledAfter", "throttledBefore"], "SFX throttle facts");
        bindCapture(facts.captureId); Object.keys(facts).filter((key) => key !== "captureId").forEach((key) => requireInteger(facts[key], "SFX throttle " + key, key.includes("Voice") ? 1 : 0));
        const played = facts.playedAfter - facts.playedBefore;
        const throttled = facts.throttledAfter - facts.throttledBefore;
        expect(facts.configuredPerEntryVoiceCap === 4 &&
            facts.requestedVoices === 6 &&
            facts.requestedVoices > facts.configuredPerEntryVoiceCap,
        "SFX per-entry voice-cap source binding drifted");
        expect(played > 0 && played <= facts.configuredPerEntryVoiceCap &&
            throttled > 0 && played + throttled === facts.requestedVoices,
        "SFX played/throttled counters do not close over the per-entry bounded exact AS2 batch");
    } else if (caseId === "bgm_sfx_mix") {
        exactKeys(facts, ["bgmFrames", "captureId", "sfxPlayedAfter", "sfxPlayedBefore"], "BGM/SFX mix facts");
        bindCapture(facts.captureId); requireInteger(facts.bgmFrames, "mix BGM frames", 1); requireInteger(facts.sfxPlayedAfter, "mix SFX after", 1); requireInteger(facts.sfxPlayedBefore, "mix SFX before", 0); expect(facts.sfxPlayedAfter > facts.sfxPlayedBefore, "mix has no SFX contribution");
    } else if (caseId === "gain_zero_and_default_max") {
        exactKeys(facts, ["captureId", "defaultPeakAbs", "defaultRequestedGain", "zeroPeakAbs", "zeroRequestedGain", "zeroWindowFrames"], "gain facts");
        bindCapture(facts.captureId); expect(facts.defaultRequestedGain === 1 && facts.zeroRequestedGain === 0, "gain command values differ from default/max contract");
        requireInteger(facts.defaultPeakAbs, "default gain peak", 64); requireInteger(facts.zeroPeakAbs, "zero gain peak", 0); requireInteger(facts.zeroWindowFrames, "zero gain window", 1); expect(facts.zeroPeakAbs <= 1, "zero-gain command produced non-silent PCM");
    } else if (caseId === "default_device_switch") {
        exactKeys(facts, ["captureId", "deviceGenerationAfter", "deviceGenerationBefore", "newDeviceIdDigest", "oldDeviceIdDigest"], "device switch facts");
        bindCapture(facts.captureId); ["newDeviceIdDigest", "oldDeviceIdDigest"].forEach((key) => expectSha(facts[key], "device switch " + key)); requireInteger(facts.deviceGenerationAfter, "device generation after", 2); requireInteger(facts.deviceGenerationBefore, "device generation before", 1); expect(facts.deviceGenerationAfter > facts.deviceGenerationBefore && facts.newDeviceIdDigest !== facts.oldDeviceIdDigest, "default-device switch was not observed");
    } else if (caseId === "physical_route_bluetooth_or_hdmi") {
        exactKeys(facts, ["captureId", "deviceIdDigest", "routeKind"], "physical route facts"); bindCapture(facts.captureId); expectSha(facts.deviceIdDigest, "physical route device digest"); expect(["bluetooth", "hdmi"].includes(facts.routeKind), "physical route is neither Bluetooth nor HDMI"); expect(facts.deviceIdDigest === captures[facts.captureId].deviceIdDigest, "physical route digest differs from the shared device-recovery capture");
    } else if (caseId === "sleep_resume") {
        exactKeys(facts, ["captureId", "deviceGenerationAfter", "deviceGenerationBefore", "maxRecoveryMs", "recoveryMs"], "sleep/resume facts"); bindCapture(facts.captureId); ["deviceGenerationAfter", "deviceGenerationBefore", "maxRecoveryMs", "recoveryMs"].forEach((key) => requireInteger(facts[key], "sleep/resume " + key, 1)); expect(facts.deviceGenerationAfter > facts.deviceGenerationBefore && facts.recoveryMs <= facts.maxRecoveryMs, "sleep/resume recovery was not bounded");
    } else if (caseId === "no_stale_sfx_after_recovery") {
        exactKeys(facts, [
            "armResult", "audioReadyGenerationAfter", "audioReadyGenerationBefore", "captureId",
            "closingReadySequence", "dispatchSequence", "playedAfter", "playedBefore",
            "preReadyDropsAfter", "preReadyDropsBefore", "recoveringSequence",
            "recoveryDropsAfter", "recoveryDropsBefore", "staleBatchSize",
            "staleGenerationDropsAfter", "staleGenerationDropsBefore",
            "startFailureCountAfter", "startFailureCountBefore", "throttledCountAfter",
            "throttledCountBefore", "unknownIdCountAfter", "unknownIdCountBefore"
        ], "stale SFX recovery facts");
        bindCapture(facts.captureId);
        exactKeys(facts.armResult, ["result", "sent"], "stale SFX arm result");
        expect(facts.armResult.result === "armed" && facts.armResult.sent === false,
            "stale SFX arm result is not exact armed/not-sent");
        Object.keys(facts).filter((key) => key !== "captureId" && key !== "armResult")
            .forEach((key) => requireInteger(facts[key], "stale SFX " + key,
                key === "staleBatchSize" || key.endsWith("Sequence") || key.startsWith("audioReadyGeneration") ? 1 : 0));
        expect(facts.staleBatchSize === 1,
            "stale SFX batch size differs from the frozen one-item stimulus");
        expect(facts.recoveringSequence < facts.dispatchSequence &&
            facts.dispatchSequence < facts.closingReadySequence,
        "stale SFX recovery/dispatch/ready order drifted");
        expect(facts.audioReadyGenerationAfter > facts.audioReadyGenerationBefore,
            "stale SFX ready generation did not advance");
        expect(facts.staleGenerationDropsAfter - facts.staleGenerationDropsBefore === facts.staleBatchSize,
            "stale SFX generation-drop counter delta drifted");
        ["played", "preReadyDrops", "recoveryDrops", "unknownIdCount", "throttledCount", "startFailureCount"]
            .forEach((stem) => expect(facts[stem + "After"] === facts[stem + "Before"],
                "stale SFX unchanged counter advanced: " + stem));
    } else {
        fail("VALIDATION_FAILED", "unimplemented endpoint semantic case " + caseId);
    }
}

function validateEndpointRuntimeSession(session) {
    exactKeys(session, ["audioReadyGeneration", "audioSessionId", "backend", "channels", "deviceGeneration", "deviceIdDigest", "sampleFormat", "sampleRate"], "endpoint session");
    expect(typeof session.audioSessionId === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(session.audioSessionId), "endpoint audioSessionId must be UUIDv4");
    expect(["wasapi", "directsound", "winmm"].includes(session.backend), "endpoint backend is not real");
    expectSha(session.deviceIdDigest, "endpoint device digest");
    requireInteger(session.audioReadyGeneration, "audio ready generation", 1); requireInteger(session.deviceGeneration, "device generation", 1);
    requireInteger(session.channels, "endpoint channels", 1); requireInteger(session.sampleRate, "endpoint sample rate", 8000);
    expect(session.sampleFormat === "f32", "endpoint runtime sample format must be f32; capture serialization is independently pcm_s16le");
    return session;
}

function validateCaptureRuntimeTuple(capture, runtime, label) {
    expect(runtime.status === "ready" && runtime.sampleFormat === "f32", label + " runtime is not ready f32");
    expect(capture.selectedBackend === runtime.backend &&
        capture.deviceIdDigest === runtime.deviceIdDigest &&
        capture.sampleRate === runtime.sampleRate &&
        capture.channels === runtime.channels,
    label + " backend/device/format differs from the shared endpoint capture");
    return runtime;
}

function validateStableGenerationTuple(runtime, session, label) {
    expect(runtime.audioSessionId === session.audioSessionId &&
        runtime.audioReadyGeneration === session.audioReadyGeneration &&
        runtime.deviceGeneration === session.deviceGeneration,
    label + " performed an undeclared recovery/generation transition");
    return runtime;
}

function validateEndpointObservation(context, observation, processSnapshot, collected) {
    validateEndpointRuntimeSession(observation.session);
    expect(collected && collected.ranges && collected.journalBinding && collected.captureRuntime, "endpoint observation lacks candidate journal derivation");
    expect(JSON.stringify(observation.session) === JSON.stringify({
        audioReadyGeneration: collected.captureRuntime.audioReadyGeneration,
        audioSessionId: collected.captureRuntime.audioSessionId,
        backend: collected.captureRuntime.backend,
        channels: collected.captureRuntime.channels,
        deviceGeneration: collected.captureRuntime.deviceGeneration,
        deviceIdDigest: collected.captureRuntime.deviceIdDigest,
        sampleFormat: collected.captureRuntime.sampleFormat,
        sampleRate: collected.captureRuntime.sampleRate
    }), "endpoint session differs from the candidate capture-marker snapshot");
    const captures = endpointCaptureMap(context);
    const markerByCapture = {
        bgm_playback: "bgm_playback",
        bgm_sfx_mix: "bgm_sfx_mix",
        device_recovery: "default_device_switch",
        sfx_playback: "sfx_playback"
    };
    Object.values(captures).forEach((capture) => {
        expect(capture.runId === observation.runId, "endpoint capture is not bound to this live run");
        const recorded = Date.parse(capture.recordedAtUtc);
        const generated = Date.parse(observation.generatedAtUtc);
        const processStarted = Date.parse(processSnapshot.processStartUtc);
        expect(recorded >= processStarted && recorded <= generated + 1000 && generated - recorded <= 30 * 60 * 1000, "endpoint capture is not fresh/from the exact candidate process lifetime");
        const markerCase = markerByCapture[capture.captureId];
        const range = collected.ranges[markerCase];
        expect(range && recorded >= Date.parse(range.begin.observedAtUtc) && recorded <= Date.parse(range.end.observedAtUtc), "endpoint capture timestamp is outside its exact candidate marker interval: " + capture.captureId);
        const snapshots = range.events.filter((entry) => entry.kind === "qualification_snapshot" && Date.parse(entry.observedAtUtc) <= recorded);
        expect(snapshots.length > 0, "endpoint capture has no preceding candidate snapshot in its marker interval: " + capture.captureId);
        const runtime = snapshots[snapshots.length - 1].payload.runtime;
        validateCaptureRuntimeTuple(capture, runtime, "endpoint capture preceding");
        if (capture.captureId === "device_recovery") {
            const before = range.events.find((entry) => entry.kind === "qualification_snapshot");
            expect(before && runtime.deviceGeneration > before.payload.runtime.deviceGeneration && runtime.deviceIdDigest !== before.payload.runtime.deviceIdDigest, "device recovery capture was not taken after the new endpoint snapshot");
        }
    });
    if (observation.reportId === "device_recovery_endpoint_e2e") {
        const capture = captures.device_recovery;
        ["default_device_switch", "physical_route_bluetooth_or_hdmi", "sleep_resume"].forEach((caseId) => {
            const snapshots = collected.ranges[caseId].events.filter((entry) => entry.kind === "qualification_snapshot");
            expect(snapshots.length >= 2, caseId + " has too few explicit snapshots for capture binding");
            const runtime = validateCaptureRuntimeTuple(capture, snapshots[snapshots.length - 1].payload.runtime, caseId);
            if (caseId === "physical_route_bluetooth_or_hdmi") validateStableGenerationTuple(runtime, observation.session, caseId);
        });
    }
    observation.caseFacts.forEach((entry) => validateEndpointCaseFacts(observation.reportId, entry.caseId, entry.facts, captures));
    return { captures, journal: collected.journalBinding, process: processSnapshot };
}

function expectedCaseMeasurement(context, observation, semanticSnapshot, caseId, checkId, facts) {
    return {
        kind: "digest",
        unit: MEASUREMENT_UNIT,
        value: sha256(canonicalBytes({
            candidate: semanticSnapshot.candidate,
            caseId,
            checkId,
            facts,
            live: semanticSnapshot.live,
            releaseSource: context.report.releaseSource,
            reportId: context.report.reportId,
            runId: observation.runId,
            session: observation.session
        }))
    };
}

function inputByRole(context, role) {
    const entry = context.input.inputs.find((candidate) => candidate.role === role);
    expect(entry && entry.kind === "release_source_blob", "required release-source input role missing: " + role);
    return { entry, file: containedPath(context.replayRoot, entry.path, "input role " + role) };
}

function selectTrackedQualificationAssets(inventory) {
    expect(inventory && typeof inventory === "object" && !Array.isArray(inventory), "shipped audio corpus inventory missing");
    expect(Array.isArray(inventory.assets) && inventory.assets.length > 0, "shipped audio corpus inventory assets invalid");
    exactKeys(inventory.qualificationScope, [
        "h2CompleteGitInventoryTotal", "ignoredSourceOnlyExcluded",
        "outsideDiscoveryExceptionsAreDecodeOrSignalWaivers", "physicalCorpusTotal",
        "rule", "trackedShippedAssetClosureSha256"
    ], "shipped audio qualification scope");
    const tracked = [];
    const ignoredSource = [];
    const paths = new Set();
    inventory.assets.forEach((asset, index) => {
        expect(asset && typeof asset === "object" && !Array.isArray(asset), "shipped asset inventory row invalid at " + index);
        safeRepoPath(asset.path, "shipped asset inventory path");
        expect(!paths.has(asset.path), "duplicate shipped asset inventory path: " + asset.path);
        paths.add(asset.path);
        if (asset.repositoryState === "tracked") tracked.push(asset);
        else if (asset.repositoryState === "ignored_source") {
            expect(asset.outsideClassification === "source_only", "ignored audio inventory row is not source_only: " + asset.path);
            ignoredSource.push(asset);
        } else fail("VALIDATION_FAILED", "shipped asset has unknown repositoryState: " + asset.path);
    });
    const scope = inventory.qualificationScope;
    expect(scope.h2CompleteGitInventoryTotal === tracked.length, "H2 tracked audio inventory count mismatch");
    expect(scope.ignoredSourceOnlyExcluded === ignoredSource.length, "ignored source-only audio count mismatch");
    expect(scope.physicalCorpusTotal === inventory.assets.length && tracked.length + ignoredSource.length === inventory.assets.length, "physical audio corpus count mismatch");
    expect(scope.outsideDiscoveryExceptionsAreDecodeOrSignalWaivers === false, "outside-discovery ownership classifications must not become decode/signal waivers");
    expect(scope.rule === "only_repositoryState_tracked_enters_H2_complete_git_inventory_and_decode_to_EOF", "H2 audio qualification scope rule mismatch");
    expectSha(scope.trackedShippedAssetClosureSha256, "tracked shipped asset closure");
    expect(scope.trackedShippedAssetClosureSha256 === sha256(canonicalBytes(tracked)), "tracked shipped asset closure mismatch");
    return { ignoredSource, tracked };
}

function validateDecoderFixtureInventory(context) {
    const binding = inputByRole(context, "decoder_fixture_inventory");
    const parsed = parseCanonicalJson(binding.file, "decoder fixture inventory", MAX_JSON_BYTES).value;
    exactKeys(parsed, ["fixtures", "schema"], "decoder fixture inventory");
    expect(parsed.schema === "cf7.audio-v2.decoder-fixture-inventory.v1", "decoder fixture inventory schema mismatch");
    expect(Array.isArray(parsed.fixtures) && parsed.fixtures.length >= 6, "decoder fixture inventory is incomplete");
    const ids = [];
    const fixtureHashes = [];
    const expectedFixtures = {
        "aac-lc-mp4-tone-48000-mono": ["aac_mp4_fixture", "AAC-LC", "MPEG-4", 0, "nonzero_pcm"],
        "malformed-ogg-vorbis-page": ["malformed_and_silent_fixtures", "Vorbis", "Ogg", 4, "malformed"],
        "opus-ogg-tone-48000-mono": ["opus_fixture", "Opus", "Ogg", 0, "nonzero_pcm"],
        "silent-pcm16-wave-48000-mono": ["malformed_and_silent_fixtures", "PCM16", "RIFF/WAVE", 0, "intentional_silence"],
        "truncated-ogg-vorbis-packet": ["malformed_and_silent_fixtures", "Vorbis", "Ogg", 5, "truncated"],
        "vorbis-ogg-tone-48000-mono": ["vorbis_fixture", "Vorbis", "Ogg", 0, "nonzero_pcm"]
    };
    parsed.fixtures.forEach((fixture, index) => {
        exactKeys(fixture, ["bytesBase64", "caseId", "codec", "container", "expectedCategory", "fixtureId", "sha256", "signalClass"], "decoder fixture " + index);
        expect(REPORT_CASES.asset_offline_eof_qualification.slice(1).includes(fixture.caseId), "decoder fixture caseId invalid");
        expectNonEmptyString(fixture.fixtureId, "decoder fixtureId", 128);
        expect(!ids.includes(fixture.fixtureId), "duplicate decoder fixtureId"); ids.push(fixture.fixtureId);
        expect(Object.prototype.hasOwnProperty.call(expectedFixtures, fixture.fixtureId), "unknown decoder fixtureId");
        expect(JSON.stringify([fixture.caseId, fixture.codec, fixture.container, fixture.expectedCategory, fixture.signalClass]) === JSON.stringify(expectedFixtures[fixture.fixtureId]), "decoder fixture semantics drifted: " + fixture.fixtureId);
        expectNonEmptyString(fixture.codec, "decoder fixture codec", 64); expectNonEmptyString(fixture.container, "decoder fixture container", 64);
        expect(Number.isSafeInteger(fixture.expectedCategory) && fixture.expectedCategory >= 0 && fixture.expectedCategory <= 17, "decoder fixture expectedCategory invalid");
        expect(["nonzero_pcm", "intentional_silence", "malformed", "truncated"].includes(fixture.signalClass), "decoder fixture signalClass invalid");
        expectSha(fixture.sha256, "decoder fixture SHA");
        expect(typeof fixture.bytesBase64 === "string" && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(fixture.bytesBase64), "decoder fixture base64 invalid");
        const bytes = Buffer.from(fixture.bytesBase64, "base64");
        expect(bytes.length > 0 && bytes.length <= 8 * 1024 * 1024 && bytes.toString("base64") === fixture.bytesBase64 && sha256(bytes) === fixture.sha256, "decoder fixture byte binding mismatch");
        expect(!fixtureHashes.includes(fixture.sha256), "decoder fixtures reuse the same bytes"); fixtureHashes.push(fixture.sha256);
        if (fixture.container === "Ogg") {
            expect(bytes.length >= 32 && bytes.subarray(0, 4).toString("ascii") === "OggS", "Ogg decoder fixture lacks an Ogg page");
            if (fixture.codec === "Opus") expect(bytes.indexOf(Buffer.from("OpusHead", "ascii")) >= 0, "Opus decoder fixture lacks OpusHead");
            else expect(bytes.indexOf(Buffer.from("vorbis", "ascii")) >= 0, "Vorbis decoder fixture lacks a Vorbis signature");
        } else if (fixture.container === "MPEG-4") {
            expect(bytes.length >= 16 && bytes.subarray(4, 8).toString("ascii") === "ftyp" && bytes.indexOf(Buffer.from("mp4a", "ascii")) >= 0, "AAC fixture is not a sniffable MPEG-4 audio file");
        } else {
            const pcm = parsePcm16Wave(bytes, "intentional-silence fixture");
            expect(pcm.frames >= 8000 && pcm.peakAbs === 0 && pcm.nonZeroSampleRatio === 0, "intentional-silence fixture is not exact silent PCM16");
        }
        fixture._bytes = bytes;
    });
    expect(JSON.stringify(ids) === JSON.stringify(Object.keys(expectedFixtures).sort()), "decoder fixture inventory must contain the fixed six-fixture corpus");
    expect(JSON.stringify(ids) === JSON.stringify(ids.slice().sort()), "decoder fixtures are not fixtureId-sorted");
    ["vorbis_fixture", "aac_mp4_fixture", "opus_fixture"].forEach((caseId) => expect(parsed.fixtures.filter((fixture) => fixture.caseId === caseId && fixture.signalClass === "nonzero_pcm").length === 1, "decoder inventory must contain one nonzero fixture for " + caseId));
    const malformed = parsed.fixtures.filter((fixture) => fixture.caseId === "malformed_and_silent_fixtures");
    expect(malformed.filter((fixture) => fixture.signalClass === "malformed").length === 1 && malformed.filter((fixture) => fixture.signalClass === "truncated").length === 1 && malformed.filter((fixture) => fixture.signalClass === "intentional_silence").length === 1, "malformed/silent fixture family is incomplete");
    const fullVorbis = parsed.fixtures.find((fixture) => fixture.fixtureId === "vorbis-ogg-tone-48000-mono")._bytes;
    const truncatedVorbis = parsed.fixtures.find((fixture) => fixture.fixtureId === "truncated-ogg-vorbis-packet")._bytes;
    expect(truncatedVorbis.length < fullVorbis.length && fullVorbis.subarray(0, truncatedVorbis.length).equals(truncatedVorbis), "truncated fixture is not an exact prefix of the bound valid Vorbis stream");
    return parsed.fixtures;
}

function decoderFixtureLeaf(fixture) {
    const suffix = fixture.container === "MPEG-4" ? ".m4a" : (fixture.codec === "Opus" ? ".opus" : (fixture.container === "Ogg" ? ".ogg" : ".wav"));
    return fixture.fixtureId.replace(/[^A-Za-z0-9_.-]/g, "_") + suffix;
}

function compileOfflineProbe(context, toolchain, buildRoot) {
    const source = dependencyFile(context, OFFLINE_PROBE_SOURCE_PATH, "offline probe source");
    const header = dependencyFile(context, AUDIO_ABI_HEADER_PATH, "Audio ABI header");
    const executable = path.join(buildRoot, "qualification-offline-probe.exe");
    const object = path.join(buildRoot, "qualification-offline-probe.obj");
    [source, header, executable, object, toolchain.cl, toolchain.vcvars64].forEach((value) => expect(!value.includes('"'), "offline probe path contains a quote"));
    const command = [
        "call \"" + toolchain.vcvars64 + "\" " + toolchain.windowsSdkVersion + " -vcvars_ver=" + toolchain.msvcToolsVersion + " >nul",
        "\"" + toolchain.cl + "\" /nologo /TC /std:c17 /W4 /WX /utf-8 /D_CRT_SECURE_NO_WARNINGS /I\"" + path.dirname(header) + "\" /c \"" + source + "\" /Fo\"" + object + "\"",
        "\"" + toolchain.cl + "\" /nologo \"" + object + "\" /Fe:\"" + executable + "\""
    ].join(" && ");
    executeBound(context, toolchain.cmd, ["/d", "/s", "/c", command], toolchain, 2 * 60 * 1000);
    const bytes = readRegularFile(executable, "compiled offline probe", MAX_INPUT_BYTES);
    expect(bytes.length > 0, "compiled offline probe is empty");
    return executable;
}

function parseOfflineProbeOutput(output, expectedCount) {
    const lines = output.replace(/\r\n/g, "\n").trimEnd().split("\n");
    expect(lines[0] === "CF7_AUDIO_V2_OFFLINE_PROBE_V1", "offline probe header missing");
    const runtimeColumns = lines[1].split("\t");
    expect(runtimeColumns.length === 6 && runtimeColumns[0] === "runtime", "offline probe runtime row invalid");
    const runtime = {
        backend: Number(runtimeColumns[1]), deviceGeneration: Number(runtimeColumns[2]), sampleRate: Number(runtimeColumns[3]),
        channels: Number(runtimeColumns[4]), deviceIdDigest: runtimeColumns[5]
    };
    expect([1, 2, 3].includes(runtime.backend) && Number.isSafeInteger(runtime.deviceGeneration) && runtime.deviceGeneration >= 1 && Number.isSafeInteger(runtime.sampleRate) && runtime.sampleRate >= 8000 && Number.isSafeInteger(runtime.channels) && runtime.channels >= 1, "offline probe did not start a real output device");
    expectSha(runtime.deviceIdDigest, "offline probe device digest");
    const rows = [];
    for (let index = 0; index < expectedCount; index++) {
        const columns = (lines[index + 2] || "").split("\t");
        expect(columns.length === 14 && columns[0] === "asset" && Number(columns[1]) === index, "offline probe asset row invalid at " + index);
        const row = {
            category: Number(columns[2]), outcome: Number(columns[3]), eofState: Number(columns[4]), frames: Number(columns[5]),
            durationSeconds: Number(columns[6]), peak: Number(columns[7]), rms: Number(columns[8]),
            leadingSilenceFrames: Number(columns[9]), trailingSilenceFrames: Number(columns[10]), nonFiniteCount: Number(columns[11]),
            elapsedMs: Number(columns[12]), inputBytesRead: Number(columns[13])
        };
        Object.values(row).forEach((value) => expect(Number.isFinite(value) && value >= 0, "offline probe emitted an invalid numeric field"));
        ["category", "outcome", "eofState", "frames", "leadingSilenceFrames", "trailingSilenceFrames", "nonFiniteCount", "elapsedMs", "inputBytesRead"].forEach((key) => expect(Number.isSafeInteger(row[key]), "offline probe integer field invalid: " + key));
        rows.push(row);
    }
    expect(lines[expectedCount + 2] === "complete\t" + expectedCount && lines.length === expectedCount + 3, "offline probe completion row/count mismatch");
    return { rows, runtime };
}

function runOfflineAssetProbe(context, observation, toolchain) {
    const assetEvidence = context.caseEvidence.shipped_corpus_all_files;
    expect(assetEvidence && assetEvidence.schema === "cf7.audio-v2.asset-eof-results.v1", "shipped asset EOF evidence missing");
    const fixtures = validateDecoderFixtureInventory(context);
    const fixtureRoot = fs.mkdtempSync(path.join(context.replayRoot, ".cf7-audio-v2-fixtures-"));
    const buildRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-offline-probe-"));
    try {
        const targets = [];
        assetEvidence.entries.forEach((entry) => {
            if (entry.signalClass !== "excluded_non_audio") targets.push({ kind: "asset", path: entry.path, sha256: entry.sha256, value: entry });
        });
        fixtures.forEach((fixture) => {
            const leaf = decoderFixtureLeaf(fixture);
            const absolute = path.join(fixtureRoot, leaf);
            fs.writeFileSync(absolute, fixture._bytes);
            const relative = path.relative(context.replayRoot, absolute).split(path.sep).join("/");
            targets.push({ kind: "fixture", path: relative, sha256: fixture.sha256, value: fixture });
        });
        const inventoryPath = path.join(buildRoot, "inventory.tsv");
        fs.writeFileSync(inventoryPath, targets.map((entry) => entry.path + "\t" + entry.sha256).join("\n") + "\n", "utf8");
        const executable = compileOfflineProbe(context, toolchain, buildRoot);
        const output = executeBound(context, executable, [path.join(context.candidateRoot, "runtime", "miniaudio.dll"), context.replayRoot, inventoryPath], toolchain, 20 * 60 * 1000);
        const parsed = parseOfflineProbeOutput(output, targets.length);
        targets.forEach((target, index) => {
            const row = parsed.rows[index];
            if (target.kind === "asset") {
                if (target.value.signalClass === "nonzero_pcm") {
                    expect(row.category === 0 && row.outcome === 5 && row.eofState === 1 && row.frames === target.value.decodedFrames && row.frames > 0 && row.peak > 0 && row.rms > 0 && row.nonFiniteCount === 0, "shipped asset did not reproduce EOF/nonzero qualification: " + target.path);
                } else {
                    expect(target.value.signalClass === "intentional_silence" && row.category === 0 && row.outcome === 5 && row.eofState === 1 && row.frames === target.value.decodedFrames && row.peak === 0 && row.rms === 0 && row.nonFiniteCount === 0, "intentional-silence waiver did not reproduce exact silent EOF: " + target.path);
                }
            } else if (target.value.signalClass === "nonzero_pcm") {
                expect(row.category === target.value.expectedCategory && row.outcome === 5 && row.eofState === 1 && row.frames > 0 && row.peak > 0 && row.rms > 0 && row.nonFiniteCount === 0, "decoder fixture did not reproduce nonzero EOF: " + target.value.fixtureId);
            } else if (target.value.signalClass === "intentional_silence") {
                expect(row.category === target.value.expectedCategory && row.outcome === 5 && row.eofState === 1 && row.frames > 0 && row.peak === 0 && row.rms === 0 && row.nonFiniteCount === 0, "silent fixture was not detected as silent EOF");
            } else {
                expect(row.category === target.value.expectedCategory && row.outcome === 7 && row.eofState !== 1, "malformed/truncated fixture category drifted: " + target.value.fixtureId);
            }
        });
        observation.caseFacts.forEach((entry) => {
            if (entry.caseId === "shipped_corpus_all_files") {
                exactKeys(entry.facts, ["inventoryEntryCount"], "shipped inventory live facts");
                expect(entry.facts.inventoryEntryCount === assetEvidence.entries.length, "shipped inventory live count mismatch");
            } else {
                exactKeys(entry.facts, ["fixtureIds"], "fixture live facts " + entry.caseId);
                const expectedIds = fixtures.filter((fixture) => fixture.caseId === entry.caseId).map((fixture) => fixture.fixtureId);
                expect(JSON.stringify(entry.facts.fixtureIds) === JSON.stringify(expectedIds), "fixture live mapping mismatch for " + entry.caseId);
            }
        });
        return {
            fixtureProbeSha256: sha256(canonicalBytes(parsed.rows.slice(targets.length - fixtures.length))),
            runtime: parsed.runtime,
            shippedProbeSha256: sha256(canonicalBytes(parsed.rows.slice(0, targets.length - fixtures.length)))
        };
    } finally {
        fs.rmSync(fixtureRoot, { recursive: true, force: true });
        fs.rmSync(buildRoot, { recursive: true, force: true });
    }
}

function makeQualificationPcmWave() {
    const sampleRate = 8000;
    const frames = sampleRate;
    const dataBytes = frames * 2;
    const bytes = Buffer.alloc(44 + dataBytes);
    bytes.write("RIFF", 0, "ascii"); bytes.writeUInt32LE(36 + dataBytes, 4); bytes.write("WAVE", 8, "ascii");
    bytes.write("fmt ", 12, "ascii"); bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22);
    bytes.writeUInt32LE(sampleRate, 24); bytes.writeUInt32LE(sampleRate * 2, 28); bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34);
    bytes.write("data", 36, "ascii"); bytes.writeUInt32LE(dataBytes, 40);
    for (let index = 0; index < frames; index++) bytes.writeInt16LE(index % 32 < 16 ? 2048 : -2048, 44 + index * 2);
    return bytes;
}

function runRealDeviceSmoke(context, toolchain) {
    const fixtureRoot = fs.mkdtempSync(path.join(context.replayRoot, ".cf7-audio-v2-device-"));
    const buildRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-device-probe-"));
    try {
        const fixture = makeQualificationPcmWave();
        const fixturePath = path.join(fixtureRoot, "device-smoke.wav");
        fs.writeFileSync(fixturePath, fixture);
        const relative = path.relative(context.replayRoot, fixturePath).split(path.sep).join("/");
        const inventory = path.join(buildRoot, "inventory.tsv");
        fs.writeFileSync(inventory, relative + "\t" + sha256(fixture) + "\n", "utf8");
        const executable = compileOfflineProbe(context, toolchain, buildRoot);
        const output = executeBound(context, executable, [path.join(context.candidateRoot, "runtime", "miniaudio.dll"), context.replayRoot, inventory], toolchain, 3 * 60 * 1000);
        const parsed = parseOfflineProbeOutput(output, 1);
        const row = parsed.rows[0];
        expect(row.category === 0 && row.outcome === 5 && row.eofState === 1 && row.frames === 8000 && row.peak > 0 && row.rms > 0 && row.nonFiniteCount === 0, "real-device smoke did not decode the bound PCM fixture to nonzero EOF");
        return parsed.runtime;
    } finally {
        fs.rmSync(fixtureRoot, { recursive: true, force: true });
        fs.rmSync(buildRoot, { recursive: true, force: true });
    }
}

function executeOfflineTargets(context, toolchain, targets, fixtureRoot) {
    const buildRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-target-probe-"));
    try {
        const inventory = path.join(buildRoot, "inventory.tsv");
        fs.writeFileSync(inventory, targets.map((entry) => entry.path + "\t" + entry.sha256).join("\n") + "\n", "utf8");
        const executable = compileOfflineProbe(context, toolchain, buildRoot);
        const output = executeBound(context, executable, [path.join(context.candidateRoot, "runtime", "miniaudio.dll"), context.replayRoot, inventory], toolchain, 20 * 60 * 1000);
        return parseOfflineProbeOutput(output, targets.length);
    } finally {
        fs.rmSync(buildRoot, { recursive: true, force: true });
        if (fixtureRoot) fs.rmSync(fixtureRoot, { recursive: true, force: true });
    }
}

function generateAssetEvidence(context, observation, producerBytes, configurationSha256) {
    const inventoryBinding = inputByRole(context, "shipped_audio_corpus_inventory");
    const inventory = parseCanonicalJson(inventoryBinding.file, "shipped audio corpus inventory", MAX_INPUT_BYTES).value;
    expect(inventory.schema === "cf7.audio-v2.shipped-audio-assets.v1" && Array.isArray(inventory.assets) && inventory.assets.length > 0, "shipped audio corpus inventory schema/assets invalid");
    expect(JSON.stringify(inventory.inventoryRoots) === JSON.stringify(["sounds", "music"]), "shipped audio corpus roots mismatch");
    const extensions = [".flac", ".m4a", ".mp3", ".mp4", ".ogg", ".opus", ".wav", ".waz"];
    expect(JSON.stringify(inventory.inventoryExtensions) === JSON.stringify(extensions), "shipped audio corpus extensions mismatch");
    const qualificationAssets = selectTrackedQualificationAssets(inventory);
    const waiverPath = containedPath(context.replayRoot, "config/audio-v2/asset-qualification-waivers.v1.json", "asset waiver path");
    const waiverArtifact = trackedArtifactForFile(context.replayRoot, waiverPath, "cf7.audio-v2.asset-qualification-waivers.v1");
    const waivers = validateWaiverManifest(waiverArtifact, context.replayRoot);
    const waiverByPath = Object.fromEntries(waivers.waivers.map((entry) => [entry.path, entry]));
    const inventoryPaths = [];
    const assets = qualificationAssets.tracked.map((asset) => {
        safeRepoPath(asset.path, "shipped inventory asset path");
        expect(!inventoryPaths.includes(asset.path), "duplicate shipped inventory asset path"); inventoryPaths.push(asset.path);
        expectBlobOid(asset.blobOid, "shipped inventory asset blobOid"); expectSha(asset.sha256, "shipped inventory asset SHA");
        expect(Number.isSafeInteger(asset.bytes) && asset.bytes > 0, "shipped inventory asset bytes invalid");
        const bytes = readRegularFile(containedPath(context.replayRoot, asset.path, "shipped asset path"), "shipped asset " + asset.path, MAX_INPUT_BYTES);
        expect(bytes.length === asset.bytes && sha256(bytes) === asset.sha256 && gitBlobOid(bytes, asset.blobOid.length) === asset.blobOid, "shipped inventory asset byte binding mismatch");
        const sniffed = sniffAudio(bytes);
        expect(sniffed.codec === asset.codec && sniffed.container === asset.container, "shipped inventory content sniff mismatch: " + asset.path);
        return { asset, bytes, waiver: waiverByPath[asset.path] || null };
    });
    expect(JSON.stringify(inventoryPaths) === JSON.stringify(inventoryPaths.slice().sort()), "shipped inventory asset paths are not sorted");
    const discovered = [];
    ["sounds", "music"].forEach((rootName) => {
        const root = containedPath(context.replayRoot, rootName, "audio inventory root");
        function walk(directory, relative) {
            fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
                const nextRelative = relative ? relative + "/" + entry.name : rootName + "/" + entry.name;
                const full = path.join(directory, entry.name);
                const stat = fs.lstatSync(full);
                expect(!entry.isSymbolicLink() && !stat.isSymbolicLink(), "audio inventory contains a link/reparse entry");
                if (entry.isDirectory()) walk(full, nextRelative);
                else if (entry.isFile() && extensions.includes(path.extname(entry.name).toLowerCase())) discovered.push(nextRelative);
            });
        }
        walk(root, "");
    });
    discovered.sort();
    const classifiedPaths = new Set(inventory.assets.map((asset) => asset.path));
    const ignoredSourcePaths = new Set(qualificationAssets.ignoredSource.map((asset) => asset.path));
    expect(discovered.every((entry) => classifiedPaths.has(entry)), "audio roots contain an unclassified physical audio file");
    const trackedDiscovered = discovered.filter((entry) => !ignoredSourcePaths.has(entry));
    expect(JSON.stringify(trackedDiscovered) === JSON.stringify(inventoryPaths), "shipped inventory does not cover the complete Git-materialized audio corpus");

    const fixtures = validateDecoderFixtureInventory(context);
    const fixtureRoot = fs.mkdtempSync(path.join(context.replayRoot, ".cf7-audio-v2-generate-fixtures-"));
    const targets = [];
    assets.forEach((entry) => { if (!entry.waiver || entry.waiver.signalClass !== "excluded_non_audio") targets.push({ kind: "asset", path: entry.asset.path, sha256: entry.asset.sha256, value: entry }); });
    fixtures.forEach((fixture) => {
        const absolute = path.join(fixtureRoot, decoderFixtureLeaf(fixture));
        fs.writeFileSync(absolute, fixture._bytes);
        targets.push({ kind: "fixture", path: path.relative(context.replayRoot, absolute).split(path.sep).join("/"), sha256: fixture.sha256, value: fixture });
    });
    const toolchain = validateToolchain(context.configurationBinding.value);
    const parsed = executeOfflineTargets(context, toolchain, targets, fixtureRoot);
    const rowByAssetPath = {};
    const fixtureRows = [];
    targets.forEach((target, index) => {
        if (target.kind === "asset") rowByAssetPath[target.value.asset.path] = parsed.rows[index];
        else fixtureRows.push({ fixture: target.value, row: parsed.rows[index] });
    });
    const entries = assets.map((entry) => {
        const base = {
            blobOid: entry.asset.blobOid, bytes: entry.asset.bytes, codec: entry.asset.codec, container: entry.asset.container,
            path: entry.asset.path, sha256: entry.asset.sha256
        };
        if (entry.waiver && entry.waiver.signalClass === "excluded_non_audio") return Object.assign(base, { decodeToEof: false, decodedFrames: 0, exceptionId: entry.waiver.exceptionId, qualificationResult: "owned_exception", signalClass: "excluded_non_audio" });
        const row = rowByAssetPath[entry.asset.path];
        if (entry.waiver) {
            expect(entry.waiver.signalClass === "intentional_silence" && row.category === 0 && row.outcome === 5 && row.eofState === 1 && row.frames > 0 && row.peak === 0 && row.rms === 0 && row.nonFiniteCount === 0, "owned silent asset does not reproduce exact silent EOF: " + entry.asset.path);
            return Object.assign(base, { decodeToEof: true, decodedFrames: row.frames, exceptionId: entry.waiver.exceptionId, qualificationResult: "owned_exception", signalClass: "intentional_silence" });
        }
        expect(row.category === 0 && row.outcome === 5 && row.eofState === 1 && row.frames > 0 && row.peak > 0 && row.rms > 0 && row.nonFiniteCount === 0, "shipped asset failed live EOF/signal qualification: " + entry.asset.path);
        return Object.assign(base, { decodeToEof: true, decodedFrames: row.frames, exceptionId: null, qualificationResult: "passed", signalClass: "nonzero_pcm" });
    });
    fixtureRows.forEach(({ fixture, row }) => {
        if (fixture.signalClass === "nonzero_pcm") expect(row.category === fixture.expectedCategory && row.outcome === 5 && row.eofState === 1 && row.frames > 0 && row.peak > 0 && row.rms > 0 && row.nonFiniteCount === 0, "decoder fixture failed nonzero EOF: " + fixture.fixtureId);
        else if (fixture.signalClass === "intentional_silence") expect(row.category === fixture.expectedCategory && row.outcome === 5 && row.eofState === 1 && row.frames > 0 && row.peak === 0 && row.rms === 0, "silent decoder fixture classification drifted");
        else expect(row.category === fixture.expectedCategory && row.outcome === 7 && row.eofState !== 1, "malformed/truncated decoder fixture category drifted");
    });
    const summary = { excludedNonAudio: 0, intentionalSilence: 0, nonzeroPcm: 0, ownedExceptions: 0, passed: 0, total: entries.length };
    entries.forEach((entry) => {
        if (entry.qualificationResult === "passed") { summary.passed++; summary.nonzeroPcm++; }
        else { summary.ownedExceptions++; if (entry.signalClass === "intentional_silence") summary.intentionalSilence++; else summary.excludedNonAudio++; }
    });
    observation.caseFacts.forEach((entry) => {
        if (entry.caseId === "shipped_corpus_all_files") { exactKeys(entry.facts, ["inventoryEntryCount"], "shipped generation facts"); expect(entry.facts.inventoryEntryCount === entries.length, "shipped generation inventory count mismatch"); }
        else { exactKeys(entry.facts, ["fixtureIds"], "fixture generation facts"); expect(JSON.stringify(entry.facts.fixtureIds) === JSON.stringify(fixtures.filter((fixture) => fixture.caseId === entry.caseId).map((fixture) => fixture.fixtureId)), "fixture generation mapping mismatch"); }
    });
    const evidence = Object.assign(generatedCaseCommon(context, "shipped_corpus_all_files", producerBytes, configurationSha256), {
        entries,
        inventoryExtensions: extensions,
        inventoryRoots: ["sounds", "music"],
        schema: "cf7.audio-v2.asset-eof-results.v1",
        summary,
        waiverManifestArtifact: waiverArtifact
    });
    const live = {
        fixtureProbeSha256: sha256(canonicalBytes(fixtureRows.map((entry) => entry.row))),
        runtime: parsed.runtime,
        shippedProbeSha256: sha256(canonicalBytes(targets.filter((entry) => entry.kind === "asset").map((entry) => rowByAssetPath[entry.value.asset.path])))
    };
    return { evidence, live };
}

function validateProductionObservation(context, observation, sourceProbe, toolchain, deviceRuntime) {
    exactKeys(observation.session, ["backend", "channels", "deviceGeneration", "deviceIdDigest", "executionKind", "sampleRate", "toolchainSha256"], "production backend session");
    expect(observation.session.executionKind === "recomputed_bound_source_and_device_probe", "production backend execution kind mismatch");
    const toolchainValue = decodeCanonicalEnvironmentJson(context.configurationBinding.value, TOOLCHAIN_ENV, true);
    expect(observation.session.toolchainSha256 === sha256(canonicalBytes(toolchainValue)), "production backend toolchain binding mismatch");
    const backendName = { 1: "wasapi", 2: "directsound", 3: "winmm" }[deviceRuntime.backend];
    expect(backendName === "wasapi" && observation.session.backend === backendName, "production qualification requires WASAPI device start, not fallback-only output");
    expect(observation.session.channels === deviceRuntime.channels && observation.session.sampleRate === deviceRuntime.sampleRate && observation.session.deviceGeneration === deviceRuntime.deviceGeneration && observation.session.deviceIdDigest === deviceRuntime.deviceIdDigest, "production live device facts differ from candidate DLL probe");
    observation.caseFacts.forEach((entry) => {
        const expectedChecks = CASE_CHECKS[observation.reportId][entry.caseId];
        if (entry.caseId === "default_device_recovery") {
            exactKeys(entry.facts, ["assertionIds", "deviceGenerationAfter", "deviceGenerationBefore", "newDeviceIdDigest", "oldDeviceIdDigest"], "production recovery facts");
            requireInteger(entry.facts.deviceGenerationAfter, "production recovered device generation", 2); requireInteger(entry.facts.deviceGenerationBefore, "production prior device generation", 1);
            expectSha(entry.facts.newDeviceIdDigest, "production recovered device digest"); expectSha(entry.facts.oldDeviceIdDigest, "production prior device digest");
            expect(entry.facts.deviceGenerationAfter > entry.facts.deviceGenerationBefore && entry.facts.newDeviceIdDigest !== entry.facts.oldDeviceIdDigest, "production default-device recovery was not observed");
        } else exactKeys(entry.facts, ["assertionIds"], "production case facts " + entry.caseId);
        expect(JSON.stringify(entry.facts.assertionIds) === JSON.stringify(expectedChecks), "production case assertion mapping differs from frozen checks");
    });
    return { device: deviceRuntime, probe: sourceProbe, toolchainSha256: observation.session.toolchainSha256 };
}

function validateDependencyManifest(descriptor, replayRoot, producerBytes) {
    const bytes = verifyTrackedArtifact(descriptor, "cf7.audio-v2.qualification-runner-dependencies.v1", replayRoot, "dependency manifest artifact");
    const parsed = JSON.parse(bytes.toString("utf8"));
    expect(bytes.equals(canonicalBytes(parsed)), "dependency manifest is not canonical JSON");
    exactKeys(parsed, ["closureSha256", "dependencies", "runnerPath", "schema"], "dependency manifest");
    expect(parsed.schema === "cf7.audio-v2.qualification-runner-dependencies.v1", "dependency manifest schema mismatch");
    expect(parsed.runnerPath === RUNNER_PATH, "dependency manifest runnerPath mismatch");
    expect(Array.isArray(parsed.dependencies) && parsed.dependencies.length > 0, "dependency manifest is empty");
    const paths = [];
    let runnerFound = false;
    parsed.dependencies.forEach((entry, index) => {
        exactKeys(entry, ["blobOid", "bytes", "path", "sha256"], "dependency " + index);
        safeRepoPath(entry.path, "dependency path");
        expect(/^(tools|launcher|automation|scripts)\//.test(entry.path), "dependency path prefix invalid");
        expect(!paths.includes(entry.path), "duplicate dependency path");
        paths.push(entry.path);
        expectBlobOid(entry.blobOid, "dependency blobOid");
        expect(Number.isInteger(entry.bytes) && entry.bytes > 0 && entry.bytes <= MAX_INPUT_BYTES, "dependency bytes invalid");
        expectSha(entry.sha256, "dependency SHA");
        const dependencyBytes = readRegularFile(containedPath(replayRoot, entry.path, "dependency"), "dependency " + entry.path, MAX_INPUT_BYTES);
        expect(dependencyBytes.length === entry.bytes && sha256(dependencyBytes) === entry.sha256, "dependency bytes/SHA mismatch");
        expect(gitBlobOid(dependencyBytes, entry.blobOid.length) === entry.blobOid, "dependency blobOid mismatch");
        if (entry.path === RUNNER_PATH) {
            runnerFound = dependencyBytes.equals(producerBytes);
        }
    });
    expect(JSON.stringify(paths) === JSON.stringify(paths.slice().sort()), "dependency paths are not sorted");
    expect(runnerFound, "dependency closure does not contain this exact runner");
    expectSha(parsed.closureSha256, "dependency closureSha256");
    expect(sha256(canonicalBytes(parsed.dependencies)) === parsed.closureSha256, "dependency closure mismatch");
    return parsed;
}

function parsePcm16Wave(bytes, label) {
    expect(bytes.length >= 44 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WAVE", label + " is not RIFF/WAVE");
    let offset = 12;
    let format = null;
    let data = null;
    while (offset + 8 <= bytes.length) {
        const id = bytes.toString("ascii", offset, offset + 4);
        const size = bytes.readUInt32LE(offset + 4);
        const start = offset + 8;
        const end = start + size;
        expect(end <= bytes.length, label + " has a truncated chunk");
        if (id === "fmt ") {
            expect(size >= 16, label + " fmt chunk is short");
            format = {
                formatTag: bytes.readUInt16LE(start), channels: bytes.readUInt16LE(start + 2),
                sampleRate: bytes.readUInt32LE(start + 4), blockAlign: bytes.readUInt16LE(start + 12),
                bitsPerSample: bytes.readUInt16LE(start + 14)
            };
        } else if (id === "data") {
            expect(data === null, label + " has multiple data chunks");
            data = { start, size };
        }
        offset = end + (size & 1);
    }
    expect(format && data, label + " is missing fmt/data");
    expect(format.formatTag === 1 && format.bitsPerSample === 16 && format.channels >= 1 && format.sampleRate >= 8000, label + " must be PCM s16le");
    expect(format.blockAlign === format.channels * 2 && data.size % format.blockAlign === 0, label + " block alignment invalid");
    let peakAbs = 0;
    let nonZero = 0;
    const samples = data.size / 2;
    for (let position = data.start; position < data.start + data.size; position += 2) {
        const value = bytes.readInt16LE(position);
        const absolute = Math.abs(value);
        if (absolute > peakAbs) peakAbs = absolute;
        if (value !== 0) nonZero++;
    }
    return {
        channels: format.channels,
        durationSeconds: (data.size / format.blockAlign) / format.sampleRate,
        frames: data.size / format.blockAlign,
        nonZeroSampleRatio: samples === 0 ? 0 : nonZero / samples,
        peakAbs,
        sampleRate: format.sampleRate
    };
}

function validateCaptureConfiguration(captureId, report, replayRoot) {
    const capturePath = "docs/evidence/audio-v2/captures/" + captureId + ".wav";
    const configurationPath = "docs/evidence/audio-v2/capture-config/" + captureId + ".json";
    const captureBytes = readRegularFile(containedPath(replayRoot, capturePath, "capture path"), "capture " + captureId, MAX_CAPTURE_BYTES);
    const configurationBinding = parseCanonicalJson(containedPath(replayRoot, configurationPath, "capture configuration path"), "capture configuration " + captureId, MAX_JSON_BYTES);
    const configuration = configurationBinding.value;
    exactKeys(configuration, [
        "candidateBuildIdentity", "candidatePayloadClosure", "captureBytes", "captureId",
        "captureSha256", "caseId", "channels", "deviceIdDigest", "durationSeconds",
        "format", "recordedAtUtc", "runId", "sampleRate", "schema", "selectedBackend", "tool"
    ], "capture configuration");
    expect(configuration.schema === "cf7.audio-v2.endpoint-capture-configuration.v1", "capture configuration schema mismatch");
    expect(configuration.captureId === captureId && configuration.caseId === captureId, "capture ID/case binding mismatch");
    expect(configuration.candidateBuildIdentity === report.candidateBuildIdentity && configuration.candidatePayloadClosure === report.candidatePayloadClosure, "capture candidate mismatch");
    expect(Number.isInteger(configuration.captureBytes) && configuration.captureBytes === captureBytes.length, "capture byte count mismatch");
    expectSha(configuration.captureSha256, "capture SHA");
    expect(configuration.captureSha256 === sha256(captureBytes), "capture SHA mismatch");
    expectSha(configuration.deviceIdDigest, "capture deviceIdDigest");
    expect(typeof configuration.durationSeconds === "number" && Number.isFinite(configuration.durationSeconds) && configuration.durationSeconds >= 1, "capture duration invalid");
    expect(configuration.format === "pcm_s16le", "capture format mismatch");
    expectRfc3339Utc(configuration.recordedAtUtc, "capture recordedAtUtc");
    expectNonEmptyString(configuration.runId, "capture runId", 256);
    expect(["wasapi", "directsound", "winmm"].includes(configuration.selectedBackend), "capture selectedBackend invalid");
    exactKeys(configuration.tool, ["blobOid", "path", "sha256"], "capture tool binding");
    expect(configuration.tool.path === CAPTURE_TOOL_PATH, "capture tool path mismatch");
    expectBlobOid(configuration.tool.blobOid, "capture tool blobOid");
    expectSha(configuration.tool.sha256, "capture tool SHA");
    const toolBytes = readRegularFile(containedPath(replayRoot, CAPTURE_TOOL_PATH, "capture tool path"), "capture tool", MAX_INPUT_BYTES);
    expect(configuration.tool.sha256 === sha256(toolBytes) && configuration.tool.blobOid === gitBlobOid(toolBytes, configuration.tool.blobOid.length), "capture tool binding mismatch");
    const pcm = parsePcm16Wave(captureBytes, "capture " + captureId);
    expect(pcm.channels === configuration.channels && pcm.sampleRate === configuration.sampleRate, "capture PCM format differs from configuration");
    expect(Math.abs(pcm.durationSeconds - configuration.durationSeconds) <= 1 / pcm.sampleRate, "capture duration differs from configuration");
    expect(pcm.durationSeconds >= 1 && pcm.peakAbs >= 64 && pcm.nonZeroSampleRatio >= 0.001, "capture is silent or below qualification threshold");
    return {
        captureId,
        captureSha256: configuration.captureSha256,
        channels: configuration.channels,
        deviceIdDigest: configuration.deviceIdDigest,
        nonZeroSampleRatio: pcm.nonZeroSampleRatio,
        peakAbs: pcm.peakAbs,
        recordedAtUtc: configuration.recordedAtUtc,
        runId: configuration.runId,
        sampleRate: configuration.sampleRate,
        selectedBackend: configuration.selectedBackend
    };
}

function validateGenericCase(caseEvidence, report, caseResult, configurationSha, input, replayRoot) {
    exactKeys(caseEvidence, [
        "candidateBuildIdentity", "candidatePayloadClosure", "captureIds", "caseId", "checks",
        "configurationSha256", "generatedAtUtc", "inputClosureSha256", "producerBlobOid",
        "producerSha256", "releaseSource", "reportId", "result", "schema"
    ], "case evidence " + caseResult.caseId);
    expect(caseEvidence.schema === "cf7.audio-v2.automated-case-evidence.v1", "generic case evidence schema mismatch");
    validateCaseCommon(caseEvidence, report, caseResult, configurationSha, input);
    const expectedChecks = CASE_CHECKS[report.reportId][caseResult.caseId];
    expect(Array.isArray(caseEvidence.checks) && caseEvidence.checks.length === expectedChecks.length, "case check count mismatch");
    const expectedCaptures = (CASE_CAPTURES[report.reportId] && CASE_CAPTURES[report.reportId][caseResult.caseId]) || [];
    expect(Array.isArray(caseEvidence.captureIds) && JSON.stringify(caseEvidence.captureIds) === JSON.stringify(expectedCaptures), "case capture binding mismatch");
    caseEvidence.checks.forEach((check, index) => {
        exactKeys(check, ["checkId", "measurement", "result"], "case check " + index);
        expect(check.checkId === expectedChecks[index] && check.result === "passed", "case check ID/order/result mismatch");
        validateMeasurement(check.measurement, "case measurement " + check.checkId);
    });
    caseEvidence.captureIds.forEach((captureId) => validateCaptureConfiguration(captureId, report, replayRoot));
}

function validateCaseCommon(caseEvidence, report, caseResult, configurationSha, input) {
    expect(caseEvidence.candidateBuildIdentity === report.candidateBuildIdentity && caseEvidence.candidatePayloadClosure === report.candidatePayloadClosure, "case candidate mismatch");
    expect(caseEvidence.reportId === report.reportId && caseEvidence.caseId === caseResult.caseId && caseEvidence.result === "passed", "case report/case/result mismatch");
    expect(JSON.stringify(caseEvidence.releaseSource) === JSON.stringify(report.releaseSource), "case release source mismatch");
    expect(caseEvidence.configurationSha256 === configurationSha, "case configuration SHA mismatch");
    expect(caseEvidence.inputClosureSha256 === input.closureSha256, "case input closure mismatch");
    expect(caseEvidence.producerBlobOid === report.provenance.producerBlobOid && caseEvidence.producerSha256 === report.provenance.producerSha256, "case producer binding mismatch");
    expectRfc3339Utc(caseEvidence.generatedAtUtc, "case generatedAtUtc");
}

function sniffAudio(bytes) {
    if (bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WAVE") return { codec: "pcm_or_ieee_float", container: "riff_wave" };
    if (bytes.length >= 4 && bytes.toString("ascii", 0, 4) === "fLaC") return { codec: "flac", container: "flac" };
    if (bytes.length >= 12 && bytes.toString("ascii", 4, 8) === "ftyp") return { codec: "aac", container: "iso_bmff" };
    if (bytes.length >= 4 && bytes.toString("ascii", 0, 4) === "OggS") {
        const header = bytes.toString("latin1", 0, Math.min(bytes.length, 256));
        if (header.includes("OpusHead")) return { codec: "opus", container: "ogg" };
        if (header.includes("vorbis")) return { codec: "vorbis", container: "ogg" };
        return { codec: "unknown_ogg_codec", container: "ogg" };
    }
    if (bytes.length >= 3 && bytes.toString("ascii", 0, 3) === "ID3") return { codec: "mpeg_audio_layer_iii", container: "mpeg_audio" };
    if (bytes.length >= 2 && bytes[0] === 0xFF && (bytes[1] & 0xE0) === 0xE0) return { codec: "mpeg_audio_layer_iii", container: "mpeg_audio" };
    return { codec: "unknown", container: "unknown" };
}

function validateWaiverManifest(descriptor, replayRoot) {
    const bytes = verifyTrackedArtifact(descriptor, "cf7.audio-v2.asset-qualification-waivers.v1", replayRoot, "waiver manifest artifact");
    const value = JSON.parse(bytes.toString("utf8"));
    expect(bytes.equals(canonicalBytes(value)), "waiver manifest is not canonical JSON");
    exactKeys(value, ["schema", "waivers"], "waiver manifest");
    expect(value.schema === "cf7.audio-v2.asset-qualification-waivers.v1" && Array.isArray(value.waivers), "waiver manifest schema/array invalid");
    const paths = [];
    const ids = [];
    value.waivers.forEach((entry, index) => {
        exactKeys(entry, ["exceptionId", "owner", "path", "reason", "signalClass"], "waiver " + index);
        expectNonEmptyString(entry.exceptionId, "waiver exceptionId", 256);
        expectNonEmptyString(entry.owner, "waiver owner", 256);
        safeRepoPath(entry.path, "waiver path");
        expectNonEmptyString(entry.reason, "waiver reason", 4096);
        expect(["excluded_non_audio", "intentional_silence"].includes(entry.signalClass), "waiver signalClass invalid");
        expect(!paths.includes(entry.path) && !ids.includes(entry.exceptionId), "duplicate waiver path/ID");
        paths.push(entry.path);
        ids.push(entry.exceptionId);
    });
    expect(JSON.stringify(paths) === JSON.stringify(paths.slice().sort()), "waivers are not path-sorted");
    return value;
}

function validateAssetEofCase(value, report, caseResult, configurationSha, input, replayRoot) {
    exactKeys(value, [
        "candidateBuildIdentity", "candidatePayloadClosure", "caseId", "configurationSha256",
        "entries", "generatedAtUtc", "inputClosureSha256", "inventoryExtensions",
        "inventoryRoots", "producerBlobOid", "producerSha256", "releaseSource", "reportId",
        "result", "schema", "summary", "waiverManifestArtifact"
    ], "asset EOF evidence");
    expect(value.schema === "cf7.audio-v2.asset-eof-results.v1", "asset EOF schema mismatch");
    validateCaseCommon(value, report, caseResult, configurationSha, input);
    expect(value.caseId === "shipped_corpus_all_files" && value.reportId === "asset_offline_eof_qualification", "asset EOF case binding mismatch");
    const extensions = [".flac", ".m4a", ".mp3", ".mp4", ".ogg", ".opus", ".wav", ".waz"];
    expect(JSON.stringify(value.inventoryExtensions) === JSON.stringify(extensions), "asset EOF extensions mismatch");
    expect(JSON.stringify(value.inventoryRoots) === JSON.stringify(["sounds", "music"]), "asset EOF roots mismatch");
    const waivers = validateWaiverManifest(value.waiverManifestArtifact, replayRoot);
    const waiverByPath = Object.fromEntries(waivers.waivers.map((entry) => [entry.path, entry]));
    expect(Array.isArray(value.entries) && value.entries.length > 0, "asset EOF entries missing");
    const counts = { excludedNonAudio: 0, intentionalSilence: 0, nonzeroPcm: 0, ownedExceptions: 0, passed: 0, total: value.entries.length };
    const entryPaths = [];
    value.entries.forEach((entry, index) => {
        exactKeys(entry, ["blobOid", "bytes", "codec", "container", "decodeToEof", "decodedFrames", "exceptionId", "path", "qualificationResult", "sha256", "signalClass"], "asset EOF entry " + index);
        expectBlobOid(entry.blobOid, "asset blobOid");
        expect(Number.isInteger(entry.bytes) && entry.bytes > 0 && entry.bytes <= MAX_INPUT_BYTES, "asset bytes invalid");
        safeRepoPath(entry.path, "asset path");
        expect(!entryPaths.includes(entry.path), "duplicate asset path");
        entryPaths.push(entry.path);
        expectSha(entry.sha256, "asset SHA");
        expect(typeof entry.decodeToEof === "boolean" && Number.isSafeInteger(entry.decodedFrames) && entry.decodedFrames >= 0, "asset decode fields invalid");
        const bytes = readRegularFile(containedPath(replayRoot, entry.path, "asset path"), "asset " + entry.path, MAX_INPUT_BYTES);
        expect(bytes.length === entry.bytes && sha256(bytes) === entry.sha256 && gitBlobOid(bytes, entry.blobOid.length) === entry.blobOid, "asset byte binding mismatch");
        const sniffed = sniffAudio(bytes);
        expect(entry.codec === sniffed.codec && entry.container === sniffed.container, "asset content sniff mismatch");
        if (entry.qualificationResult === "passed") {
            expect(entry.exceptionId === null && entry.decodeToEof === true && entry.decodedFrames > 0 && entry.signalClass === "nonzero_pcm", "passed asset claims invalid qualification");
            expect(!waiverByPath[entry.path], "passed asset also has waiver");
            if (sniffed.container === "riff_wave") {
                const pcm = parsePcm16Wave(bytes, "asset " + entry.path);
                expect(pcm.frames === entry.decodedFrames && pcm.peakAbs >= 64 && pcm.nonZeroSampleRatio >= 0.001, "passed PCM asset is silent or frame count drifted");
            }
            counts.passed++;
            counts.nonzeroPcm++;
        } else {
            expect(entry.qualificationResult === "owned_exception" && typeof entry.exceptionId === "string", "asset exception invalid");
            const waiver = waiverByPath[entry.path];
            expect(waiver && waiver.exceptionId === entry.exceptionId && waiver.signalClass === entry.signalClass, "asset exception lacks exact waiver");
            counts.ownedExceptions++;
            if (entry.signalClass === "intentional_silence") counts.intentionalSilence++;
            else if (entry.signalClass === "excluded_non_audio") counts.excludedNonAudio++;
            else fail("VALIDATION_FAILED", "asset exception signalClass invalid");
        }
    });
    expect(JSON.stringify(entryPaths) === JSON.stringify(entryPaths.slice().sort()), "asset EOF entries are not path-sorted");
    exactKeys(value.summary, ["excludedNonAudio", "intentionalSilence", "nonzeroPcm", "ownedExceptions", "passed", "total"], "asset EOF summary");
    expect(JSON.stringify(value.summary) === JSON.stringify(counts), "asset EOF summary mismatch");
}

function validateReportEnvelope(report) {
    exactKeys(report, [
        "candidateBuildIdentity", "candidatePayloadClosure", "caseResults", "caseResultsSha256",
        "generatedAtUtc", "provenance", "releaseSource", "reportId", "result", "schema", "summary"
    ], "report");
    expect(report.schema === "cf7.audio-v2.automated-report.v1", "report schema mismatch");
    expect(Object.prototype.hasOwnProperty.call(REPORT_CASES, report.reportId), "unknown reportId");
    expect(report.result === "passed", "report is not passed");
    expectSha(report.candidateBuildIdentity, "candidate build identity");
    expectSha(report.candidatePayloadClosure, "candidate payload closure");
    validateReleaseSource(report.releaseSource, "report release source");
    expectRfc3339Utc(report.generatedAtUtc, "report generatedAtUtc");
    exactKeys(report.summary, ["failed", "passed", "total"], "report summary");
    const expectedCases = REPORT_CASES[report.reportId];
    expect(report.summary.failed === 0 && report.summary.passed === expectedCases.length && report.summary.total === expectedCases.length, "report summary does not match fixed case matrix");
    expect(Array.isArray(report.caseResults) && report.caseResults.length === expectedCases.length, "report case count mismatch");
    const paths = [];
    const blobs = [];
    const shas = [];
    report.caseResults.forEach((entry, index) => {
        exactKeys(entry, ["caseId", "evidenceArtifact", "result"], "report case result " + index);
        expect(entry.caseId === expectedCases[index] && entry.result === "passed", "report case order/result mismatch");
        const expectedSchema = report.reportId === "asset_offline_eof_qualification" && entry.caseId === "shipped_corpus_all_files"
            ? "cf7.audio-v2.asset-eof-results.v1"
            : "cf7.audio-v2.automated-case-evidence.v1";
        validateArtifactDescriptor(entry.evidenceArtifact, expectedSchema, "case artifact " + entry.caseId);
        expect(!paths.includes(entry.evidenceArtifact.path) && !blobs.includes(entry.evidenceArtifact.blobOid) && !shas.includes(entry.evidenceArtifact.sha256), "case evidence artifacts are not byte-distinct");
        paths.push(entry.evidenceArtifact.path);
        blobs.push(entry.evidenceArtifact.blobOid);
        shas.push(entry.evidenceArtifact.sha256);
    });
    expectSha(report.caseResultsSha256, "caseResultsSha256");
    expect(report.caseResultsSha256 === sha256(canonicalBytes(report.caseResults)), "caseResults closure mismatch");
    exactKeys(report.provenance, [
        "configurationArtifact", "inputClosureSha256", "inputManifestArtifact", "producerBlobOid",
        "producerDependencyManifestArtifact", "producerPath", "producerSha256"
    ], "report provenance");
    validateArtifactDescriptor(report.provenance.configurationArtifact, "cf7.audio-v2.automated-report-configuration.v1", "configuration artifact");
    validateArtifactDescriptor(report.provenance.inputManifestArtifact, "cf7.audio-v2.automated-report-input-manifest.v1", "input manifest artifact");
    validateArtifactDescriptor(report.provenance.producerDependencyManifestArtifact, "cf7.audio-v2.qualification-runner-dependencies.v1", "dependency manifest artifact");
    expect(report.provenance.producerDependencyManifestArtifact.path === DEPENDENCY_MANIFEST_PATH, "dependency manifest path mismatch");
    expect(report.provenance.producerPath === RUNNER_PATH, "producer path mismatch");
    expectBlobOid(report.provenance.producerBlobOid, "producer blobOid");
    expectSha(report.provenance.producerSha256, "producer SHA");
    expectSha(report.provenance.inputClosureSha256, "provenance input closure");
}

function caseEvidenceClosure(report) {
    const closure = report.caseResults.map((entry) => ({
        blobOid: entry.evidenceArtifact.blobOid,
        bytes: entry.evidenceArtifact.bytes,
        caseId: entry.caseId,
        path: entry.evidenceArtifact.path,
        schema: entry.evidenceArtifact.schema,
        sha256: entry.evidenceArtifact.sha256
    })).sort((left, right) => left.caseId.localeCompare(right.caseId));
    return sha256(canonicalBytes(closure));
}

function assertWithinDeadline(deadlineEpochMs, label) {
    if (Date.now() >= deadlineEpochMs) fail("TIMEOUT", label + " exceeded the fixed qualification deadline");
}

function validateInvocation(options) {
    const replayRoot = fs.realpathSync.native(options.replayRoot || process.cwd());
    const deadline = options.deadlineEpochMs || Date.now() + INTERNAL_TIMEOUT_MS;
    assertWithinDeadline(deadline, "qualification verification");
    const reportBinding = parseCanonicalJson(options.reportPath, "report", MAX_JSON_BYTES);
    const report = reportBinding.value;
    validateReportEnvelope(report);
    const configurationBinding = parseCanonicalJson(options.configurationPath, "configuration", MAX_JSON_BYTES);
    validateConfiguration(configurationBinding.value, report.reportId);
    const inputBinding = parseCanonicalJson(options.inputManifestPath, "input manifest", MAX_JSON_BYTES);
    const candidateRoot = openCandidateRoot(options.candidateRoot);
    validateInputManifest(inputBinding.value, report, candidateRoot, replayRoot);
    expect(report.provenance.inputClosureSha256 === inputBinding.value.closureSha256, "report/input closure mismatch");
    const configurationBytes = verifyTrackedArtifact(report.provenance.configurationArtifact, "cf7.audio-v2.automated-report-configuration.v1", replayRoot, "configuration artifact");
    expect(configurationBytes.equals(configurationBinding.bytes), "configuration CLI file differs from report artifact");
    const inputBytes = verifyTrackedArtifact(report.provenance.inputManifestArtifact, "cf7.audio-v2.automated-report-input-manifest.v1", replayRoot, "input manifest artifact");
    expect(inputBytes.equals(inputBinding.bytes), "input CLI file differs from report artifact");
    const producerBytes = readRegularFile(containedPath(replayRoot, RUNNER_PATH, "producer path"), "qualification runner", MAX_INPUT_BYTES);
    expect(report.provenance.producerSha256 === sha256(producerBytes), "report producer SHA mismatch");
    expect(report.provenance.producerBlobOid === gitBlobOid(producerBytes, report.provenance.producerBlobOid.length), "report producer blobOid mismatch");
    const dependencies = validateDependencyManifest(report.provenance.producerDependencyManifestArtifact, replayRoot, producerBytes);
    assertWithinDeadline(deadline, "qualification structure verification");
    const caseEvidence = {};
    report.caseResults.forEach((caseResult) => {
        const evidenceBytes = verifyTrackedArtifact(caseResult.evidenceArtifact, caseResult.evidenceArtifact.schema, replayRoot, "case evidence " + caseResult.caseId);
        const evidence = JSON.parse(evidenceBytes.toString("utf8"));
        expect(evidenceBytes.equals(canonicalBytes(evidence)), "case evidence is not canonical JSON");
        if (evidence.schema === "cf7.audio-v2.asset-eof-results.v1") {
            validateAssetEofCase(evidence, report, caseResult, sha256(configurationBinding.bytes), inputBinding.value, replayRoot);
        } else {
            validateGenericCase(evidence, report, caseResult, sha256(configurationBinding.bytes), inputBinding.value, replayRoot);
        }
        caseEvidence[caseResult.caseId] = evidence;
        assertWithinDeadline(deadline, "qualification case verification");
    });
    return {
        candidateRoot,
        caseEvidence,
        configurationBinding,
        deadlineEpochMs: deadline,
        dependencies,
        input: inputBinding.value,
        replayRoot,
        report,
        reportBytes: reportBinding.bytes
    };
}

function runLiveVerifier(context, options) {
    options = options || {};
    assertWithinDeadline(context.deadlineEpochMs, "live qualification");
    const candidate = options.candidateSnapshot || validateCandidateBinary(
        context.candidateRoot,
        context.report.candidateBuildIdentity,
        context.report.candidatePayloadClosure
    );
    let observation = options.observation || validateLiveObservation(context);
    if (options.observation) validateNoVerdictFields(observation, "injected live observation");
    let live;
    if (context.report.reportId === "asset_offline_eof_qualification") {
        const toolchain = options.toolchain || validateToolchain(context.configurationBinding.value);
        live = options.assetProbe ? options.assetProbe(context, observation, toolchain) : runOfflineAssetProbe(context, observation, toolchain);
    } else if (ENDPOINT_REPORTS.has(context.report.reportId)) {
        const toolchain = options.toolchain || validateToolchain(context.configurationBinding.value);
        const archivedCarrier = options.observation
            ? null
            : qualificationObserver.validateJournalCarrier(decodeConfigurationLiveObservation(context.configurationBinding.value));
        const processSnapshot = options.processInspector
            ? options.processInspector(context.candidateRoot, observation.candidateProcess, toolchain)
            : inspectWindowsProcess(context.candidateRoot, observation.candidateProcess, toolchain);
        dependencyFile(context, OBSERVER_COLLECTOR_PATH, "qualification observer collector");
        const clientPath = dependencyFile(context, OBSERVER_CLIENT_PATH, "qualification observer pipe client");
        const expectedCandidate = {
            buildIdentity: context.report.candidateBuildIdentity,
            executablePath: processSnapshot.executablePath || path.join(context.candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
            executableSha256: observation.candidateProcess.executableSha256,
            payloadClosure: context.report.candidatePayloadClosure,
            pid: observation.candidateProcess.pid,
            processStartUtc: observation.candidateProcess.processStartUtc
        };
        const observerOptions = {
            clientPath,
            env: childEnvironment(context, toolchain),
            expectedCandidate,
            powershell: toolchain.powershell,
            runId: observation.runId,
            timeoutMs: Math.max(100, Math.min(30000, context.deadlineEpochMs - Date.now()))
        };
        const sfxPerEntryVoiceCap = exactSfxPerEntryVoiceCap(context);
        const derivationOptions = {
            candidateBuildIdentity: context.report.candidateBuildIdentity,
            candidatePayloadClosure: context.report.candidatePayloadClosure,
            releaseSource: context.report.releaseSource,
            reportId: context.report.reportId,
            sfxPerEntryVoiceCap
        };
        if (archivedCarrier) {
            const archivedDerived = qualificationObserver.deriveLiveObservation(derivationOptions, archivedCarrier);
            expect(canonicalBytes(observation).equals(canonicalBytes(archivedDerived.observation)), "tracked observation differs from its archived exact-candidate journal derivation");
        }
        const completed = options.observerCollector
            ? options.observerCollector(observerOptions, context)
            : qualificationObserver.queryCompletedJournal(observerOptions);
        const derived = archivedCarrier
            ? reconcileEndpointJournalCarrier(archivedCarrier, completed, derivationOptions).derived
            : qualificationObserver.deriveLiveObservation(derivationOptions, completed);
        expect(canonicalBytes(observation).equals(canonicalBytes(derived.observation)), "tracked live observation differs from the exact candidate journal derivation");
        observation = derived.observation;
        live = validateEndpointObservation(context, observation, processSnapshot, derived);
    } else if (SOURCE_PROBE_REPORTS.has(context.report.reportId)) {
        const toolchain = options.toolchain || validateToolchain(context.configurationBinding.value);
        const sourceProbe = options.sourceProbe ? options.sourceProbe(context, toolchain) : runDefaultSourceProbe(context, toolchain);
        if (context.report.reportId === "production_backend_device_fault_injection") {
            const device = options.deviceProbe ? options.deviceProbe(context, toolchain) : runRealDeviceSmoke(context, toolchain);
            live = validateProductionObservation(context, observation, sourceProbe, toolchain, device);
        } else live = validateSourceObservation(context, observation, sourceProbe, toolchain);
    } else fail("VALIDATION_FAILED", "no live verifier implementation for " + context.report.reportId);

    const semanticSnapshot = { candidate, live };
    if (options.deriveOnly) return { observation, semanticSnapshot };
    REPORT_CASES[context.report.reportId].forEach((caseId) => {
        const evidence = context.caseEvidence[caseId];
        if (evidence.schema !== "cf7.audio-v2.automated-case-evidence.v1") return;
        const facts = observation.caseFacts.find((entry) => entry.caseId === caseId).facts;
        evidence.checks.forEach((check) => {
            const expected = expectedCaseMeasurement(context, observation, semanticSnapshot, caseId, check.checkId, facts);
            expect(JSON.stringify(check.measurement) === JSON.stringify(expected), "case measurement was not derived from recomputed live evidence: " + caseId + "/" + check.checkId);
        });
    });
    assertWithinDeadline(context.deadlineEpochMs, "live qualification");
    return { observation, semanticSnapshot };
}

function reconcileEndpointJournalCarrier(carrier, completed, derivationOptions) {
    const archived = qualificationObserver.validateJournalCarrier(carrier);
    const archivedDerived = qualificationObserver.deriveLiveObservation(derivationOptions, archived);
    expect(canonicalBytes(archived.observation).equals(canonicalBytes(archivedDerived.observation)), "tracked observation differs from its archived exact-candidate journal derivation");
    expect(completed && completed.candidate && completed.journal, "live candidate journal is missing");
    qualificationObserver.validateJournal(completed.journal, archived.observation.runId);
    const live = {
        candidate: completed.candidate,
        journal: completed.journal,
        ranges: qualificationObserver.validateCompletedJournal(completed.journal)
    };
    expect(canonicalBytes(live.candidate).equals(canonicalBytes(archived.candidate)), "live candidate differs from the tracked candidate journal carrier");
    expect(canonicalBytes(live.journal).equals(canonicalBytes(archived.journal)), "live journal differs from the tracked candidate journal carrier");
    const derived = qualificationObserver.deriveLiveObservation(derivationOptions, live);
    expect(canonicalBytes(archived.observation).equals(canonicalBytes(derived.observation)), "live journal derivation differs from the tracked observation");
    return { archived, derived };
}

function buildProducerVerification(context) {
    const report = context.report;
    return {
        candidateBuildIdentity: report.candidateBuildIdentity,
        candidatePayloadClosure: report.candidatePayloadClosure,
        caseEvidenceClosureSha256: caseEvidenceClosure(report),
        caseResultsSha256: report.caseResultsSha256,
        configurationSha256: sha256(context.configurationBinding.bytes),
        inputClosureSha256: context.input.closureSha256,
        producerBlobOid: report.provenance.producerBlobOid,
        producerDependencyClosureSha256: context.dependencies.closureSha256,
        producerPath: report.provenance.producerPath,
        producerSha256: report.provenance.producerSha256,
        releaseSource: report.releaseSource,
        reportId: report.reportId,
        reportSha256: sha256(context.reportBytes),
        result: "passed",
        schema: "cf7.audio-v2.producer-verification.v1"
    };
}

function repoRelativePath(root, absolute, label) {
    const relative = path.relative(root, path.resolve(absolute)).split(path.sep).join("/");
    safeRepoPath(relative, label);
    expect(sameFilesystemPath(containedPath(root, relative, label), absolute), label + " is outside output root");
    return relative;
}

function trackedArtifactForFile(root, absolute, schema) {
    const relative = repoRelativePath(root, absolute, "tracked artifact path");
    const bytes = readRegularFile(path.resolve(absolute), "tracked artifact " + relative, MAX_INPUT_BYTES);
    return { blobOid: gitBlobOid(bytes, 40), bytes: bytes.length, kind: "tracked_blob", path: relative, schema, sha256: sha256(bytes) };
}

function writeCanonicalFile(root, relative, value) {
    const absolute = containedPath(root, relative, "generated evidence path");
    fs.mkdirSync(path.dirname(absolute), { recursive: true });
    fs.writeFileSync(absolute, canonicalBytes(value));
    return absolute;
}

function parseGenerationArguments(argv) {
    expect(argv[0] === "--report-id" && argv.length === 10, "generation requires --report-id plus four absolute path flags");
    const reportId = argv[1];
    expect(Object.prototype.hasOwnProperty.call(REPORT_CASES, reportId), "unknown generation reportId");
    const expectedFlags = ["--candidate-root", "--configuration", "--input-manifest", "--output-root"];
    const values = {};
    for (let index = 2; index < argv.length; index += 2) {
        const flag = argv[index];
        expect(expectedFlags.includes(flag) && !Object.prototype.hasOwnProperty.call(values, flag), "unknown or duplicate generation flag " + flag);
        expect(path.isAbsolute(argv[index + 1]), flag + " must be absolute");
        values[flag] = path.resolve(argv[index + 1]);
    }
    expectedFlags.forEach((flag) => expect(values[flag], "missing generation flag " + flag));
    return {
        candidateRoot: values["--candidate-root"], configurationPath: values["--configuration"],
        inputManifestPath: values["--input-manifest"], outputRoot: values["--output-root"], reportId
    };
}

function generatedCaseCommon(context, caseId, producerBytes, configurationSha256) {
    return {
        candidateBuildIdentity: context.report.candidateBuildIdentity,
        candidatePayloadClosure: context.report.candidatePayloadClosure,
        caseId,
        configurationSha256,
        generatedAtUtc: context.report.generatedAtUtc,
        inputClosureSha256: context.input.closureSha256,
        producerBlobOid: gitBlobOid(producerBytes, 40),
        producerSha256: sha256(producerBytes),
        releaseSource: context.report.releaseSource,
        reportId: context.report.reportId,
        result: "passed"
    };
}

function generateReport(options, runtimeOptions) {
    runtimeOptions = runtimeOptions || {};
    const outputRoot = openCandidateRoot(options.outputRoot);
    expect(sameFilesystemPath(outputRoot, process.cwd()), "generation output root must be the canonical release-source working directory");
    const candidateRoot = openCandidateRoot(options.candidateRoot);
    const configurationBinding = parseCanonicalJson(options.configurationPath, "generation configuration", MAX_JSON_BYTES);
    validateConfiguration(configurationBinding.value, options.reportId);
    const inputBinding = parseCanonicalJson(options.inputManifestPath, "generation input manifest", MAX_JSON_BYTES);
    expect(inputBinding.value.reportId === options.reportId, "generation input reportId mismatch");
    const reportStub = {
        candidateBuildIdentity: inputBinding.value.candidateBuildIdentity,
        candidatePayloadClosure: inputBinding.value.candidatePayloadClosure,
        generatedAtUtc: "1970-01-01T00:00:00Z",
        releaseSource: inputBinding.value.releaseSource,
        reportId: options.reportId
    };
    validateInputManifest(inputBinding.value, reportStub, candidateRoot, outputRoot);
    const producerBytes = readRegularFile(containedPath(outputRoot, RUNNER_PATH, "producer path"), "qualification runner", MAX_INPUT_BYTES);
    const dependencyFilePath = containedPath(outputRoot, DEPENDENCY_MANIFEST_PATH, "dependency manifest path");
    const dependencyDescriptor = trackedArtifactForFile(outputRoot, dependencyFilePath, "cf7.audio-v2.qualification-runner-dependencies.v1");
    const dependencies = validateDependencyManifest(dependencyDescriptor, outputRoot, producerBytes);
    const rawCarrier = decodeConfigurationLiveObservation(configurationBinding.value);
    const rawObservation = ENDPOINT_REPORTS.has(options.reportId)
        ? qualificationObserver.validateJournalCarrier(rawCarrier).observation
        : rawCarrier;
    reportStub.generatedAtUtc = rawObservation.generatedAtUtc;
    const observationCarrier = { configurationBinding, report: reportStub };
    const observation = validateLiveObservation(observationCarrier);
    const context = {
        candidateRoot, caseEvidence: {}, configurationBinding, deadlineEpochMs: Date.now() + INTERNAL_TIMEOUT_MS,
        dependencies, input: inputBinding.value, replayRoot: outputRoot, report: reportStub
    };
    let derived;
    let generatedAsset = null;
    if (options.reportId === "asset_offline_eof_qualification") {
        generatedAsset = generateAssetEvidence(context, observation, producerBytes, sha256(configurationBinding.bytes));
        context.caseEvidence.shipped_corpus_all_files = generatedAsset.evidence;
        derived = { observation, semanticSnapshot: { candidate: validateCandidateBinary(candidateRoot, reportStub.candidateBuildIdentity, reportStub.candidatePayloadClosure), live: generatedAsset.live } };
    } else derived = runLiveVerifier(context, Object.assign({}, runtimeOptions, { deriveOnly: true }));

    const caseResults = REPORT_CASES[options.reportId].map((caseId) => {
        const relative = "docs/evidence/audio-v2/cases/" + options.reportId + "/" + caseId + ".json";
        let evidence;
        let schema;
        if (caseId === "shipped_corpus_all_files") {
            evidence = generatedAsset.evidence;
            schema = "cf7.audio-v2.asset-eof-results.v1";
        } else {
            const facts = observation.caseFacts.find((entry) => entry.caseId === caseId).facts;
            evidence = Object.assign(generatedCaseCommon(context, caseId, producerBytes, sha256(configurationBinding.bytes)), {
                captureIds: (CASE_CAPTURES[options.reportId] && CASE_CAPTURES[options.reportId][caseId]) || [],
                checks: CASE_CHECKS[options.reportId][caseId].map((checkId) => ({
                    checkId,
                    measurement: expectedCaseMeasurement(context, observation, derived.semanticSnapshot, caseId, checkId, facts),
                    result: "passed"
                })),
                schema: "cf7.audio-v2.automated-case-evidence.v1"
            });
            schema = evidence.schema;
        }
        const absolute = writeCanonicalFile(outputRoot, relative, evidence);
        return { caseId, evidenceArtifact: trackedArtifactForFile(outputRoot, absolute, schema), result: "passed" };
    });
    const configurationArtifact = trackedArtifactForFile(outputRoot, options.configurationPath, "cf7.audio-v2.automated-report-configuration.v1");
    const inputArtifact = trackedArtifactForFile(outputRoot, options.inputManifestPath, "cf7.audio-v2.automated-report-input-manifest.v1");
    const report = {
        candidateBuildIdentity: reportStub.candidateBuildIdentity,
        candidatePayloadClosure: reportStub.candidatePayloadClosure,
        caseResults,
        caseResultsSha256: sha256(canonicalBytes(caseResults)),
        generatedAtUtc: reportStub.generatedAtUtc,
        provenance: {
            configurationArtifact,
            inputClosureSha256: inputBinding.value.closureSha256,
            inputManifestArtifact: inputArtifact,
            producerBlobOid: gitBlobOid(producerBytes, 40),
            producerDependencyManifestArtifact: dependencyDescriptor,
            producerPath: RUNNER_PATH,
            producerSha256: sha256(producerBytes)
        },
        releaseSource: reportStub.releaseSource,
        reportId: options.reportId,
        result: "passed",
        schema: "cf7.audio-v2.automated-report.v1",
        summary: { failed: 0, passed: caseResults.length, total: caseResults.length }
    };
    const reportRelative = "docs/evidence/audio-v2/reports/" + options.reportId + ".json";
    const reportPath = writeCanonicalFile(outputRoot, reportRelative, report);
    const verifiedContext = validateInvocation({
        candidateRoot, configurationPath: options.configurationPath, deadlineEpochMs: Date.now() + INTERNAL_TIMEOUT_MS,
        inputManifestPath: options.inputManifestPath, replayRoot: outputRoot, reportPath
    });
    runLiveVerifier(verifiedContext, runtimeOptions);
    const verification = buildProducerVerification(verifiedContext);
    const verificationRelative = "docs/evidence/audio-v2/verifications/" + options.reportId + ".json";
    writeCanonicalFile(outputRoot, verificationRelative, verification);
    return { reportPath: reportRelative, verificationPath: verificationRelative };
}

function parseVerifyArguments(argv) {
    const expectedFlags = ["--report", "--configuration", "--input-manifest", "--candidate-root"];
    expect(argv[0] === "--verify-audio-v2-report", "first argument must be --verify-audio-v2-report");
    expect(argv.length === 9, "verification invocation must contain exactly four path flags");
    const result = {};
    for (let index = 1; index < argv.length; index += 2) {
        const flag = argv[index];
        const value = argv[index + 1];
        expect(expectedFlags.includes(flag) && !Object.prototype.hasOwnProperty.call(result, flag), "unknown or duplicate verification flag " + flag);
        expectNonEmptyString(value, flag, 32768);
        expect(path.isAbsolute(value), flag + " must be absolute");
        result[flag] = path.resolve(value);
    }
    expectedFlags.forEach((flag) => expect(Object.prototype.hasOwnProperty.call(result, flag), "missing " + flag));
    return {
        candidateRoot: result["--candidate-root"],
        configurationPath: result["--configuration"],
        inputManifestPath: result["--input-manifest"],
        reportPath: result["--report"]
    };
}

function main(argv) {
    if (argv[0] === "--report-id") {
        const generated = generateReport(parseGenerationArguments(argv));
        process.stdout.write(canonicalBytes({
            reportPath: generated.reportPath,
            result: "generated_and_live_verified",
            schema: "cf7.audio-v2.qualification-generation-result.v1",
            verificationPath: generated.verificationPath
        }));
        return;
    }
    const options = parseVerifyArguments(argv);
    options.replayRoot = process.cwd();
    options.deadlineEpochMs = Date.now() + INTERNAL_TIMEOUT_MS;
    const context = validateInvocation(options);
    runLiveVerifier(context);
    process.stdout.write(canonicalBytes(buildProducerVerification(context)));
}

if (require.main === module) {
    try {
        main(process.argv.slice(2));
    } catch (error) {
        const code = error instanceof QualificationError ? error.code : "INTERNAL_ERROR";
        const message = error && error.message ? error.message : String(error);
        process.stderr.write("audio-v2 qualification failed [" + code + "]: " + message.replace(/[\r\n]+/g, " ") + "\n");
        process.exitCode = code === "LIVE_PHASE_NOT_IMPLEMENTED" ? 4 : (code === "TIMEOUT" ? 5 : 3);
    }
}

module.exports = Object.freeze({
    CASE_CAPTURES,
    CASE_CHECKS,
    QualificationError,
    REPORT_CASES,
    REPORT_INPUT_ROLES,
    assertWithinDeadline,
    buildProducerVerification,
    canonicalBytes,
    caseEvidenceClosure,
    childEnvironment,
    decodeConfigurationLiveObservation,
    encodeLiveObservationArguments,
    expectedCaseMeasurement,
    generateReport,
    gitBlobOid,
    inspectWindowsProcess,
    parsePcm16Wave,
    parsePeExports,
    recomputeAs2AudioProbe,
    reconcileEndpointJournalCarrier,
    runLiveVerifier,
    runtimeBuildIdentityHash,
    runtimePayloadClosureHash,
    sha256,
    sortedClone,
    validateCandidateBinary,
    validateConfiguration,
    validateCaptureConfiguration,
    validateDecoderFixtureInventory,
    validateEndpointCaseFacts,
    validateInvocation,
    validateToolchain,
    validateEndpointRuntimeSession,
    validateCaptureRuntimeTuple,
    validateStableGenerationTuple,
    selectTrackedQualificationAssets
});
