#!/usr/bin/env node

"use strict";

var crypto = require("crypto");
var cp = require("child_process");
var fs = require("fs");
var os = require("os");
var path = require("path");

var ROOT = path.resolve(__dirname, "../..");
var ADR_PATH = "docs/原生音频平台-v2-格式能力桥接契约与可观测性-ADR-2026-08-09.md";
var MEMO_PATH = "docs/原生音频引擎-资源兼容性与静音故障只读调研备忘-2026-08-09.md";
var MANIFEST_PATH = "docs/contracts/audio-v2/h1-decision-manifest.v2.json";
var MANIFEST_SCHEMA_PATH = "docs/contracts/audio-v2/h1-decision-manifest.schema.v2.json";
var H1_SCHEMA_PATH = "docs/contracts/audio-v2/h1-implementation-acceptance.schema.v2.json";
var AUTOMATED_REPORT_SCHEMA_PATH = "docs/contracts/audio-v2/automated-report-envelope.schema.v1.json";
var AUTOMATED_REPORT_CONFIGURATION_SCHEMA_PATH = "docs/contracts/audio-v2/automated-report-configuration.schema.v1.json";
var AUTOMATED_REPORT_INPUT_SCHEMA_PATH = "docs/contracts/audio-v2/automated-report-input-manifest.schema.v1.json";
var AUTOMATED_CASE_EVIDENCE_SCHEMA_PATH = "docs/contracts/audio-v2/automated-case-evidence.schema.v1.json";
var ASSET_EOF_RESULTS_SCHEMA_PATH = "docs/contracts/audio-v2/asset-eof-results.schema.v1.json";
var ASSET_WAIVER_SCHEMA_PATH = "docs/contracts/audio-v2/asset-qualification-waivers.schema.v1.json";
var ASSET_WAIVER_PATH = "config/audio-v2/asset-qualification-waivers.v1.json";
var CANDIDATE_VERIFICATION_SCHEMA_PATH = "docs/contracts/audio-v2/candidate-verification.schema.v1.json";
var ENDPOINT_CAPTURE_CONFIGURATION_SCHEMA_PATH = "docs/contracts/audio-v2/endpoint-capture-configuration.schema.v1.json";
var PRODUCER_VERIFICATION_SCHEMA_PATH = "docs/contracts/audio-v2/producer-verification.schema.v1.json";
var RUNNER_DEPENDENCY_SCHEMA_PATH = "docs/contracts/audio-v2/qualification-runner-dependencies.schema.v1.json";
var RUNNER_DEPENDENCY_PATH = "config/audio-v2/qualification-runner-dependencies.v1.json";
var A6_SCHEMA_PATH = "docs/contracts/audio-v2/a6-evidence-manifest.schema.v1.json";
var LISTENING_SCHEMA_PATH = "docs/contracts/audio-v2/human-listening-matrix.schema.v1.json";
var H2_SCHEMA_PATH = "docs/contracts/audio-v2/h2-promotion-acceptance.schema.v2.json";
var H1_RECEIPT_PATH = "docs/evidence/audio-v2/h1-implementation-acceptance.json";
var H2_RECEIPT_PATH = "docs/evidence/audio-v2/h2-promotion-acceptance.json";
var VALIDATOR_PATH = "tools/audio-v2/validate-contract.js";
var TEST_PATH = "tools/audio-v2/contract.test.js";
var GITATTRIBUTES_PATH = ".gitattributes";
var TEMP_REVIEW_PATHS = ["docs/codex.md", "docs/kimi.md"];
var EXPECTED_MANIFEST_SHA256 = "518D1B5EA83960300B79D5C6DFB3CCDDAD3FFF1094C5950537E5C4FA9918469E";
var FROZEN_CONTRACT_PATHS = [GITATTRIBUTES_PATH, MANIFEST_PATH, MANIFEST_SCHEMA_PATH, H1_SCHEMA_PATH, AUTOMATED_REPORT_SCHEMA_PATH, AUTOMATED_REPORT_CONFIGURATION_SCHEMA_PATH, AUTOMATED_REPORT_INPUT_SCHEMA_PATH, AUTOMATED_CASE_EVIDENCE_SCHEMA_PATH, ASSET_EOF_RESULTS_SCHEMA_PATH, ASSET_WAIVER_SCHEMA_PATH, CANDIDATE_VERIFICATION_SCHEMA_PATH, ENDPOINT_CAPTURE_CONFIGURATION_SCHEMA_PATH, PRODUCER_VERIFICATION_SCHEMA_PATH, RUNNER_DEPENDENCY_SCHEMA_PATH, A6_SCHEMA_PATH, LISTENING_SCHEMA_PATH, H2_SCHEMA_PATH, VALIDATOR_PATH, TEST_PATH];
var QUALIFICATION_RUNNER_PATH = "tools/audio-v2/qualification-runner.js";
var ENDPOINT_CAPTURE_TOOL_PATH = "tools/audio-v2/capture-endpoint.ps1";
var PRODUCER_REPLAY_TIMEOUT_MILLISECONDS = 1800000;
var REQUIRED_AUTOMATED_REPORT_IDS = [
    "asset_offline_eof_qualification", "native_abi_decoder_lifecycle",
    "production_backend_device_fault_injection", "csharp_capability_catalog_bridge",
    "as2_wire_publish", "launcher_affected_regression",
    "exact_candidate_bgm_endpoint_e2e", "exact_candidate_sfx_endpoint_e2e",
    "device_recovery_endpoint_e2e"
];
var REQUIRED_ENDPOINT_CASE_IDS = ["bgm_playback", "sfx_playback", "bgm_sfx_mix", "device_recovery"];
var REQUIRED_CASE_CAPTURE_IDS = {
    exact_candidate_bgm_endpoint_e2e: {
        bgm_crossfade: ["bgm_playback"], bgm_playback: ["bgm_playback"], bgm_seek: ["bgm_playback"],
        format_aac_mp4: ["bgm_playback"], format_opus: ["bgm_playback"], format_vorbis: ["bgm_playback"]
    },
    exact_candidate_sfx_endpoint_e2e: {
        bgm_sfx_mix: ["bgm_sfx_mix"], dense_overlap_throttle: ["sfx_playback"],
        gain_zero_and_default_max: ["sfx_playback"], sfx_playback: ["sfx_playback"]
    },
    device_recovery_endpoint_e2e: {
        default_device_switch: ["device_recovery"], no_stale_sfx_after_recovery: ["device_recovery"],
        physical_route_bluetooth_or_hdmi: ["device_recovery"], sleep_resume: ["device_recovery"]
    }
};
var REQUIRED_LISTENING_CAPTURE_IDS = {
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
};
var REQUIRED_AUTOMATED_REPORT_CASES = {
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
};
var REQUIRED_REPORT_INPUT_ROLES = {
    asset_offline_eof_qualification: ["candidate_core", "candidate_miniaudio", "candidate_runtime_manifest", "decoder_fixture_inventory", "decoder_lock_or_capability_manifest", "shipped_audio_corpus_inventory"],
    native_abi_decoder_lifecycle: ["candidate_core", "candidate_miniaudio", "candidate_runtime_manifest", "decoder_dependency_lock", "native_abi_contract", "native_lifecycle_test_plan"],
    production_backend_device_fault_injection: ["backend_policy_source", "candidate_core", "candidate_miniaudio", "candidate_runtime_manifest", "device_fault_injection_plan", "no_output_product_policy"],
    csharp_capability_catalog_bridge: ["bridge_protocol_contract", "candidate_core", "candidate_miniaudio", "candidate_runtime_manifest", "catalog_contract", "csharp_audio_source_closure"],
    as2_wire_publish: ["as2_audio_source_closure", "as2_publish_plan", "candidate_core", "candidate_miniaudio", "candidate_runtime_manifest", "wire_protocol_contract"],
    launcher_affected_regression: ["candidate_core", "candidate_miniaudio", "candidate_runtime_manifest", "jukebox_harness_source", "launcher_test_manifest", "shutdown_test_plan"],
    exact_candidate_bgm_endpoint_e2e: ["bgm_endpoint_run_plan", "bgm_fixture_inventory", "candidate_core", "candidate_execution_contract", "candidate_miniaudio", "candidate_runtime_manifest"],
    exact_candidate_sfx_endpoint_e2e: ["candidate_core", "candidate_execution_contract", "candidate_miniaudio", "candidate_runtime_manifest", "sfx_endpoint_run_plan", "sfx_fixture_inventory"],
    device_recovery_endpoint_e2e: ["candidate_core", "candidate_execution_contract", "candidate_miniaudio", "candidate_runtime_manifest", "device_recovery_run_plan", "device_route_contract"]
};
var REQUIRED_CASE_CHECKS = {
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
        gain_zero_and_default_max: ["default_gain_audible", "zero_gain_silent_by_command" ]
    },
    device_recovery_endpoint_e2e: {
        default_device_switch: ["new_device_identity_published", "post_switch_endpoint_pcm"],
        physical_route_bluetooth_or_hdmi: ["physical_route_identity_recorded", "routed_endpoint_pcm"],
        sleep_resume: ["post_resume_endpoint_pcm", "recovery_bounded"],
        no_stale_sfx_after_recovery: ["recovery_drop_counter_exact", "stale_sfx_absent_after_recovery"]
    }
};
var ASSET_INVENTORY_EXTENSIONS = [".flac", ".m4a", ".mp3", ".mp4", ".ogg", ".opus", ".wav", ".waz"];

var ADR_RECOVERY_STATES = {
    proposal: {
        markers: ["H1_STATE=pending", "H2_STATE=not_applicable_before_A6"],
        state: "PROPOSED / HUMAN_ACCEPTANCE_REQUIRED / IMPLEMENTATION_BLOCKED / NOT_DEPLOYED"
    },
    h1: {
        markers: ["H1_STATE=accepted", "H2_STATE=not_applicable_before_A6"],
        state: "ACCEPTED / IMPLEMENTATION_AUTHORIZED_A1_A6 / PROMOTION_BLOCKED / NOT_DEPLOYED"
    },
    e1: {
        markers: ["H1_STATE=accepted", "H2_STATE=pending_exact_human_acceptance", "E1_STATE=evidence_ready"],
        state: "ACCEPTED / E2E_VERIFIED / HUMAN_PROMOTION_ACCEPTANCE_REQUIRED / NOT_DEPLOYED"
    },
    h2: {
        markers: ["H1_STATE=accepted", "H2_STATE=accepted", "E1_STATE=evidence_ready"],
        state: "ACCEPTED / E2E_VERIFIED / PROMOTION_AUTHORIZED / NOT_DEPLOYED"
    }
};

var MEMO_RECOVERY_STATES = {
    proposal: {
        markers: ["H1_STATE=pending"],
        state: "READ_ONLY_RESEARCH_COMPLETE / IMPLEMENTATION_NOT_AUTHORIZED / NOT_DEPLOYED"
    },
    h1: {
        markers: ["H1_STATE=accepted"],
        state: "READ_ONLY_RESEARCH_COMPLETE / IMPLEMENTATION_AUTHORIZED_A1_A6 / NOT_DEPLOYED"
    }
};

function fail(message) {
    throw new Error(message);
}

function expect(condition, message) {
    if (!condition) fail(message);
}

function absolute(rel, root) {
    return path.join(root || ROOT, rel.replace(/\//g, path.sep));
}

function sha256(buffer) {
    return crypto.createHash("sha256").update(buffer).digest("hex").toUpperCase();
}

function sortValue(value) {
    if (Array.isArray(value)) return value.map(sortValue);
    if (value && typeof value === "object") {
        var sorted = {};
        Object.keys(value).sort().forEach(function (key) {
            sorted[key] = sortValue(value[key]);
        });
        return sorted;
    }
    return value;
}

function canonicalBytes(value) {
    return Buffer.from(JSON.stringify(sortValue(value), null, 2) + "\n", "utf8");
}

function parseJsonBuffer(buffer, label) {
    expect(buffer.length >= 2, label + " is empty");
    expect(!(buffer[0] === 0xEF && buffer[1] === 0xBB && buffer[2] === 0xBF), label + " must not contain UTF-8 BOM");
    expect(buffer.indexOf(0x0D) === -1, label + " must use LF, not CRLF");
    try {
        return JSON.parse(buffer.toString("utf8"));
    } catch (error) {
        fail(label + " is invalid JSON: " + error.message);
    }
}

function readJson(rel, options) {
    var buffer = fs.readFileSync(absolute(rel, options && options.root));
    var value = parseJsonBuffer(buffer, rel);
    if (options && options.canonical) {
        expect(buffer.equals(canonicalBytes(value)), rel + " is not canonical sorted JSON with two-space indent and terminal LF");
    }
    return { buffer: buffer, value: value };
}

function exactKeys(value, keys, label) {
    expect(value && typeof value === "object" && !Array.isArray(value), label + " must be an object");
    var actual = Object.keys(value).sort();
    var expected = keys.slice().sort();
    expect(JSON.stringify(actual) === JSON.stringify(expected), label + " keys differ; expected " + expected.join(",") + " got " + actual.join(","));
}

function expectString(value, label) {
    expect(typeof value === "string" && value.length > 0, label + " must be a non-empty string");
}

function expectRfc3339Utc(value, label) {
    expect(typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value), label + " must be RFC3339 UTC");
    expect(!Number.isNaN(Date.parse(value)), label + " is not a real timestamp");
    expect(new Date(value).toISOString().slice(0, 19) === value.slice(0, 19), label + " contains an invalid calendar date/time");
}

function normalizeHumanVerbatim(value) {
    expectString(value, "human verbatim");
    var normalized = value.replace(/\r\n/g, "\n");
    if (normalized.endsWith("\n")) normalized = normalized.slice(0, -1);
    expect(!normalized.endsWith("\n"), "human verbatim has more than one trailing newline");
    expect(normalized.indexOf("\r") < 0, "human verbatim contains bare CR");
    return normalized;
}

function validateTopRecoveryState(text, expected, label) {
    expect(typeof text === "string", label + " must be text");
    var lines = text.replace(/\r\n/g, "\n").split("\n");
    var stateLines = lines.filter(function (line) { return line.indexOf("**状态**：") === 0; });
    var markerLines = lines.filter(function (line) { return line.indexOf("**机器恢复标记**：") === 0; });
    expect(stateLines.length === 1, label + " must contain exactly one top-level state line");
    expect(markerLines.length === 1, label + " must contain exactly one machine recovery marker line");
    var expectedStateLine = "**状态**：`" + expected.state + "`。";
    var expectedMarkerLine = "**机器恢复标记**：" + expected.markers.map(function (marker) { return "`" + marker + "`"; }).join("；") + "。";
    expect(stateLines[0] === expectedStateLine, label + " top-level state mismatch; expected: " + expectedStateLine);
    expect(markerLines[0] === expectedMarkerLine, label + " machine recovery markers mismatch; expected: " + expectedMarkerLine);
    return true;
}

function validateManifest(manifest) {
    exactKeys(manifest, [
        "abi", "assetContract", "authorization", "backend", "bridge",
        "buildAndDependency", "capability", "decisions", "decoderMatrix",
        "evidenceGates", "generation", "lifecycle", "nonGoals",
        "observability", "probePolicies", "release", "schema",
        "scopeRevision", "selectedAlternatives"
    ], "manifest");

    expect(manifest.schema === "cf7.audio-v2.h1-decision-manifest.v2", "unexpected manifest schema");
    expect(manifest.scopeRevision === "AUDIO-V2-H1-SWEET-SPOT-R2", "unexpected scope revision");
    exactKeys(manifest.authorization, ["deploymentState", "humanGate", "phases", "promotionAuthorized"], "authorization");
    expect(JSON.stringify(manifest.authorization.phases) === JSON.stringify(["A1", "A2", "A3", "A4", "A5", "A6"]), "H1 phases must be exactly A1-A6");
    expect(manifest.authorization.promotionAuthorized === false, "H1 must not authorize promotion");
    expect(manifest.authorization.deploymentState === "NOT_DEPLOYED", "H1 must remain NOT_DEPLOYED");

    var expectedIds = [];
    for (var index = 1; index <= 22; index++) expectedIds.push("AUDIO-V2-" + String(index).padStart(3, "0"));
    expect(Array.isArray(manifest.decisions), "decisions must be an array");
    var actualIds = manifest.decisions.map(function (decision, decisionIndex) {
        exactKeys(decision, ["id", "rule"], "decisions[" + decisionIndex + "]");
        expectString(decision.rule, "decisions[" + decisionIndex + "].rule");
        return decision.id;
    });
    expect(JSON.stringify(actualIds) === JSON.stringify(expectedIds), "decision IDs must be exactly AUDIO-V2-001..022 in order");

    expect(JSON.stringify(manifest.backend.compiledProductionBackends) === JSON.stringify(["wasapi", "directsound", "winmm"]), "production backend allowlist drift");
    expect(manifest.backend.nullBackend === "forbidden_in_production", "production Null backend must be forbidden");
    expect(manifest.backend.noOutputPolicy === "launcher_continues_with_audio_unavailable_and_disabled_controls", "no-output product policy drift");
    expect(manifest.backend.fallbackSuccessBoundary === "context_and_playback_device_both_started", "backend fallback must include device init");

    var decoderByCodec = {};
    manifest.decoderMatrix.forEach(function (row) { decoderByCodec[row.codec] = row; });
    ["pcm_or_ieee_float", "mpeg_audio_layer_iii", "flac", "vorbis", "aac_lc_or_he_aac", "opus", "wma"].forEach(function (codec) {
        expect(decoderByCodec[codec], "decoder matrix missing " + codec);
    });
    expect(decoderByCodec.vorbis.backend.indexOf("libvorbis") >= 0 && decoderByCodec.vorbis.status === "include", "Vorbis must select libvorbis route");
    expect(decoderByCodec.opus.status === "include", "Opus must be included in R2");
    expect(decoderByCodec.wma.status === "defer" && decoderByCodec.wma.public === false, "WMA must remain deferred");
    expect(manifest.selectedAlternatives.vorbis.rejected.implementation.indexOf("stb_vorbis") >= 0, "stb_vorbis trade-off must be recorded");

    exactKeys(manifest.generation, ["audioReadyGeneration", "audioSessionId", "connectionGeneration", "deviceGeneration", "jobRule", "overflowRule", "staleRule", "terminologyRule"], "generation");
    expect(manifest.generation.terminologyRule === "bare_generation_is_forbidden", "bare generation must be forbidden");
    expect(manifest.generation.connectionGeneration.ownership === "xmlsocket_transport_only", "connection generation must remain transport-only");
    expect(manifest.generation.staleRule.indexOf("zero_side_effect") >= 0, "stale generation must have zero side effects");
    expect(manifest.bridge.resultCategories.indexOf("stale_generation") >= 0, "stale_generation result category is required");

    expect(manifest.probePolicies.runtimeCompatibilityProbe.eofRequired === false, "runtime probe must not require EOF");
    expect(manifest.probePolicies.runtimeCompatibilityProbe.timeoutResult === "inconclusive_timeout_not_unsupported", "runtime timeout must be inconclusive");
    expect(manifest.probePolicies.offlineQualificationProbe.decode === "stream_to_eof", "offline qualification must decode to EOF");
    expect(manifest.probePolicies.offlineQualificationProbe.timeoutResult === "qualification_failed_timeout", "offline qualification timeout must fail qualification");

    expect(JSON.stringify(manifest.assetContract.proposalBaseline.inventoryRoots) === JSON.stringify(["sounds", "music"]), "proposal baseline inventory roots drift");
    expect(manifest.assetContract.proposalBaseline.totalMeaning === "native_audio_corpus_under_inventory_roots_not_entire_repository", "proposal baseline corpus meaning missing");
    expect(manifest.assetContract.proposalBaseline.totalPhysicalAudio === 827, "resource total drift");
    expect(manifest.assetContract.proposalBaseline.catalogPhysicalBgm === 90, "physical BGM count drift");
    expect(manifest.assetContract.proposalBaseline.preloadSfx.total === 676, "SFX preload count drift");
    expect(manifest.assetContract.proposalBaseline.outsideBothDiscoveryPaths.total === 61, "outside-discovery count drift");
    expect(manifest.assetContract.proposalBaseline.zeroShippedOggByExtensionAndMagic === true, "baseline zero Ogg fact missing");
    expect(manifest.assetContract.proposalBaseline.zeroShippedFlacByExtensionAndMagic === true, "baseline zero FLAC fact missing");

    expect(manifest.evidenceGates.H1.receiptSchema === H1_SCHEMA_PATH, "H1 receipt schema path drift");
    expect(manifest.evidenceGates.H1.canonicalCheckoutPolicy === "gitattributes_forces_LF_for_audio_v2_contract_JSON_evidence_JSON_and_validator_test_JS_on_all_hosts", "canonical checkout policy drift");
    expect(manifest.evidenceGates.H2.automatedReportSchema === AUTOMATED_REPORT_SCHEMA_PATH, "automated report schema path drift");
    expect(manifest.evidenceGates.H2.automatedCaseEvidenceSchema === AUTOMATED_CASE_EVIDENCE_SCHEMA_PATH, "automated case evidence schema path drift");
    expect(manifest.evidenceGates.H2.assetEofResultsSchema === ASSET_EOF_RESULTS_SCHEMA_PATH, "asset EOF results schema path drift");
    expect(manifest.evidenceGates.H2.assetQualificationWaiverPath === ASSET_WAIVER_PATH, "asset qualification waiver path drift");
    expect(manifest.evidenceGates.H2.assetQualificationWaiverSchema === ASSET_WAIVER_SCHEMA_PATH, "asset qualification waiver schema path drift");
    expect(manifest.evidenceGates.H2.automatedReportConfigurationSchema === AUTOMATED_REPORT_CONFIGURATION_SCHEMA_PATH, "automated report configuration schema path drift");
    expect(manifest.evidenceGates.H2.automatedReportInputManifestSchema === AUTOMATED_REPORT_INPUT_SCHEMA_PATH, "automated report input manifest schema path drift");
    expect(manifest.evidenceGates.H2.producerVerificationSchema === PRODUCER_VERIFICATION_SCHEMA_PATH, "producer verification schema path drift");
    expect(manifest.evidenceGates.H2.candidateVerificationSchema === CANDIDATE_VERIFICATION_SCHEMA_PATH, "candidate verification schema path drift");
    expect(manifest.evidenceGates.H2.endpointCaptureConfigurationSchema === ENDPOINT_CAPTURE_CONFIGURATION_SCHEMA_PATH, "endpoint capture configuration schema path drift");
    expect(manifest.evidenceGates.H2.evidenceManifestSchema === A6_SCHEMA_PATH, "A6 evidence schema path drift");
    expect(manifest.evidenceGates.H2.listeningMatrixSchema === LISTENING_SCHEMA_PATH, "listening schema path drift");
    expect(manifest.evidenceGates.H2.receiptSchema === H2_SCHEMA_PATH, "H2 receipt schema path drift");
    expect(JSON.stringify(manifest.evidenceGates.H2.requiredAutomatedReportIds) === JSON.stringify(REQUIRED_AUTOMATED_REPORT_IDS), "required automated report IDs drift");
    expect(JSON.stringify(sortValue(manifest.evidenceGates.H2.requiredAutomatedReportCases)) === JSON.stringify(sortValue(REQUIRED_AUTOMATED_REPORT_CASES)), "required automated report case matrix drift");
    expect(JSON.stringify(sortValue(manifest.evidenceGates.H2.requiredReportInputRoles)) === JSON.stringify(sortValue(REQUIRED_REPORT_INPUT_ROLES)), "required report input role matrix drift");
    expect(JSON.stringify(sortValue(manifest.evidenceGates.H2.requiredCaseChecks)) === JSON.stringify(sortValue(REQUIRED_CASE_CHECKS)), "required case check matrix drift");
    expect(JSON.stringify(sortValue(manifest.evidenceGates.H2.requiredCaseCaptureIds)) === JSON.stringify(sortValue(REQUIRED_CASE_CAPTURE_IDS)), "required case capture matrix drift");
    expect(JSON.stringify(sortValue(manifest.evidenceGates.H2.requiredListeningCaptureIds)) === JSON.stringify(sortValue(REQUIRED_LISTENING_CAPTURE_IDS)), "required listening capture matrix drift");
    expect(JSON.stringify(manifest.evidenceGates.H2.assetInventoryExtensions) === JSON.stringify(ASSET_INVENTORY_EXTENSIONS), "asset inventory extensions drift");
    expect(JSON.stringify(manifest.evidenceGates.H2.requiredEndpointCaseIds) === JSON.stringify(REQUIRED_ENDPOINT_CASE_IDS), "required endpoint case IDs drift");
    expect(JSON.stringify(manifest.evidenceGates.H2.humanMessageBinds) === JSON.stringify([
        "releaseSourceCommit", "releaseSourceTree", "buildIdentity", "payloadClosure",
        "evidenceCommit", "evidenceTree", "evidenceManifestPath", "evidenceManifestSha256",
        "candidateVerificationSha256", "endpointCaptureToolSha256", "endpointClosureSha256", "listeningMatrixSha256", "qualificationRunnerSha256",
        "audioDeviceQualified=true", "promotionAuthorized=true", "decision=accepted"
    ]), "H2 human message binding field order/coverage drift");
    expect(manifest.evidenceGates.H2.automatedReportProvenance === "release_source_tracked_runner_and_dependency_closure_plus_E1_tracked_configuration_input_case_evidence_and_producer_verification_closures", "automated report provenance policy drift");
    expect(manifest.evidenceGates.H2.qualificationRunnerPath === QUALIFICATION_RUNNER_PATH, "qualification runner path drift");
    expect(manifest.evidenceGates.H2.qualificationRunnerDependencyManifestPath === RUNNER_DEPENDENCY_PATH && manifest.evidenceGates.H2.qualificationRunnerDependencyManifestSchema === RUNNER_DEPENDENCY_SCHEMA_PATH, "qualification runner dependency policy drift");
    expect(manifest.evidenceGates.H2.qualificationRunnerTrustBoundary === "replay_proves_exact_reviewed_runner_bytes_and_bound_inputs_executed_but_cannot_mechanically_prove_runner_semantics_H2_human_source_review_and_SHA_binding_are_mandatory", "qualification runner trust-boundary drift");
    expect(manifest.evidenceGates.H2.producerReplayPolicy === "first_print_H2_materializes_exact_S_dependencies_and_E1_inputs_in_isolation_reruns_all_nine_reports_on_live_candidate_and_requires_canonical_stdout_equal_E1_verification_blob", "producer replay policy drift");
    expect(manifest.evidenceGates.H2.producerReplayTimeoutMilliseconds === PRODUCER_REPLAY_TIMEOUT_MILLISECONDS, "producer replay timeout drift");
    expect(manifest.evidenceGates.H2.caseEvidencePolicy === "fixed_case_check_and_capture_binding_matrix_with_typed_measurements_distinct_tracked_case_blobs_and_isolated_producer_replay", "case evidence policy drift");
    expect(manifest.evidenceGates.H2.assetSignalPolicy === "validator_recomputes_pcm_s16le_frames_peak_and_nonzero_ratio_compressed_formats_require_live_frozen_producer_decode_to_EOF", "asset signal policy drift");
    expect(manifest.evidenceGates.H2.assetExceptionPolicy === "only_exact_path_exceptionId_owner_reason_signalClass_entries_in_S_tracked_waiver_registry_are_allowed", "asset exception policy drift");
    expect(manifest.evidenceGates.H2.candidateArtifactVerification === "print_H2_requires_live_full_payload_file_set_identity_closure_and_release_source_domain_recomputation_then_E1_tracked_attestation_and_runtime_manifest_snapshot_support_root_independent_recovery", "candidate artifact verification policy drift");
    expect(manifest.evidenceGates.H2.endpointCaptureStorage.indexOf("tracked_blobs") >= 0, "H2 captures must be tracked blobs");
    expect(manifest.evidenceGates.H2.endpointCaptureCaseRule === "exactly_four_tracked_wavs_with_distinct_path_blob_and_sha_one_unique_required_case_per_item", "endpoint capture case rule drift");
    expect(manifest.evidenceGates.H2.endpointCaptureToolPath === ENDPOINT_CAPTURE_TOOL_PATH, "endpoint capture tool path drift");
    expect(manifest.evidenceGates.H2.endpointCaptureTrustBoundary === "validator_proves_exact_S_tool_E1_configuration_candidate_device_capture_bytes_signal_and_case_links_but_H2_human_must_review_tool_semantics_and_listen_to_bound_captures", "endpoint capture trust-boundary drift");
    expect(manifest.evidenceGates.H2.endpointCaptureMinimumDurationSeconds === 1, "H2 capture minimum duration drift");
    expect(manifest.evidenceGates.H2.endpointCaptureMinPeakAbsPcm16 === 64 && manifest.evidenceGates.H2.endpointCaptureMinNonZeroSampleRatio === 0.001, "H2 capture signal threshold drift");
    expect(manifest.evidenceGates.H2.frozenContractReleaseSourcePolicy === "every_frozen_contract_blob_in_release_source_S_must_equal_proposal_P_even_if_worktree_bytes_are_restored", "release-source frozen contract policy drift");
    expect(manifest.evidenceGates.H2.receiptTreeImmutabilityPolicy === "H1_receipt_must_match_H_S_E1_and_HEAD_H2_receipt_must_match_E2_and_HEAD", "receipt tree immutability policy drift");
    expect(manifest.release.runtimeRequestSchema === "existing_cf7_runtime_build_request_v2_unchanged", "runtime request schema must remain unchanged");
    expect(sha256(canonicalBytes(manifest)) === EXPECTED_MANIFEST_SHA256, "manifest semantic bytes differ from the R2 validator constant; raise scope revision and update validator/tests/ADR together");
    return manifest;
}

function validateSchemaSurfaces(root) {
    var manifestSchema = readJson(MANIFEST_SCHEMA_PATH, { canonical: true, root: root }).value;
    var h1Schema = readJson(H1_SCHEMA_PATH, { canonical: true, root: root }).value;
    var automatedReportSchema = readJson(AUTOMATED_REPORT_SCHEMA_PATH, { canonical: true, root: root }).value;
    var automatedReportConfigurationSchema = readJson(AUTOMATED_REPORT_CONFIGURATION_SCHEMA_PATH, { canonical: true, root: root }).value;
    var automatedReportInputSchema = readJson(AUTOMATED_REPORT_INPUT_SCHEMA_PATH, { canonical: true, root: root }).value;
    var automatedCaseEvidenceSchema = readJson(AUTOMATED_CASE_EVIDENCE_SCHEMA_PATH, { canonical: true, root: root }).value;
    var assetEofResultsSchema = readJson(ASSET_EOF_RESULTS_SCHEMA_PATH, { canonical: true, root: root }).value;
    var assetWaiverSchema = readJson(ASSET_WAIVER_SCHEMA_PATH, { canonical: true, root: root }).value;
    var candidateVerificationSchema = readJson(CANDIDATE_VERIFICATION_SCHEMA_PATH, { canonical: true, root: root }).value;
    var endpointCaptureConfigurationSchema = readJson(ENDPOINT_CAPTURE_CONFIGURATION_SCHEMA_PATH, { canonical: true, root: root }).value;
    var producerVerificationSchema = readJson(PRODUCER_VERIFICATION_SCHEMA_PATH, { canonical: true, root: root }).value;
    var runnerDependencySchema = readJson(RUNNER_DEPENDENCY_SCHEMA_PATH, { canonical: true, root: root }).value;
    var a6Schema = readJson(A6_SCHEMA_PATH, { canonical: true, root: root }).value;
    var listeningSchema = readJson(LISTENING_SCHEMA_PATH, { canonical: true, root: root }).value;
    var h2Schema = readJson(H2_SCHEMA_PATH, { canonical: true, root: root }).value;
    expect(manifestSchema.additionalProperties === false, "manifest schema must reject extra top-level keys");
    expect(h1Schema.additionalProperties === false, "H1 schema must reject extra top-level keys");
    expect(automatedReportSchema.additionalProperties === false, "automated report schema must reject extra top-level keys");
    expect(automatedReportConfigurationSchema.additionalProperties === false, "automated report configuration schema must reject extra top-level keys");
    expect(automatedReportInputSchema.additionalProperties === false, "automated report input schema must reject extra top-level keys");
    expect(automatedCaseEvidenceSchema.additionalProperties === false, "automated case evidence schema must reject extra top-level keys");
    expect(assetEofResultsSchema.additionalProperties === false, "asset EOF results schema must reject extra top-level keys");
    expect(assetWaiverSchema.additionalProperties === false, "asset waiver schema must reject extra top-level keys");
    expect(candidateVerificationSchema.additionalProperties === false, "candidate verification schema must reject extra top-level keys");
    expect(endpointCaptureConfigurationSchema.additionalProperties === false, "endpoint capture configuration schema must reject extra top-level keys");
    expect(producerVerificationSchema.additionalProperties === false, "producer verification schema must reject extra top-level keys");
    expect(runnerDependencySchema.additionalProperties === false, "qualification runner dependency schema must reject extra top-level keys");
    expect(a6Schema.additionalProperties === false, "A6 schema must reject extra top-level keys");
    expect(listeningSchema.additionalProperties === false, "listening schema must reject extra top-level keys");
    expect(h2Schema.additionalProperties === false, "H2 schema must reject extra top-level keys");
    expect(listeningSchema.properties.cases.minItems === 10 && listeningSchema.properties.cases.maxItems === 10, "listening matrix must contain exactly ten cases");
    expect(Array.isArray(listeningSchema.properties.cases.allOf) && listeningSchema.properties.cases.allOf.length === 10, "listening schema must require each case exactly once");
    expect(a6Schema.properties.automatedReports.minItems === 9 && a6Schema.properties.automatedReports.maxItems === 9, "A6 schema must require all nine automated reports");
    expect(automatedReportSchema.required.indexOf("caseResultsSha256") >= 0 && automatedReportSchema.required.indexOf("provenance") >= 0, "automated report schema must bind case closure and producer provenance");
    expect(automatedCaseEvidenceSchema.properties.checks.items.required.indexOf("measurement") >= 0 && automatedCaseEvidenceSchema.properties.checks.items.required.indexOf("observed") < 0, "case evidence schema must use typed measurements, not free-text observed values");
    expect(automatedCaseEvidenceSchema.required.indexOf("captureIds") >= 0, "case evidence schema must bind endpoint capture IDs explicitly");
    expect(assetEofResultsSchema.required.indexOf("waiverManifestArtifact") >= 0, "asset EOF schema must bind the S-tracked waiver registry");
    expect(a6Schema.properties.automatedReports.items.required.indexOf("verificationArtifact") >= 0, "A6 schema must bind a producer verification artifact per report");
    expect(a6Schema.required.indexOf("qualificationRunner") >= 0, "A6 schema must bind the reviewed qualification runner trust root");
    expect(a6Schema.properties.endpointCaptures.properties.items.minItems === 4 && a6Schema.properties.endpointCaptures.properties.items.maxItems === 4, "A6 schema must require four endpoint captures");
    expect(a6Schema.properties.endpointCaptures.properties.items.items.properties.caseIds.minItems === 1 && a6Schema.properties.endpointCaptures.properties.items.items.properties.caseIds.maxItems === 1, "each endpoint capture schema item must bind one case");
    expect(a6Schema.properties.endpointCaptures.properties.items.items.required.indexOf("configurationArtifact") >= 0 && a6Schema.properties.endpointCaptures.properties.items.items.required.indexOf("toolArtifact") >= 0, "endpoint captures must bind tracked configuration and source tool artifacts");
    expect(a6Schema.properties.endpointCaptures.properties.maxBytesEach.const === 1048576, "endpoint capture per-file bound drift");
    expect(a6Schema.properties.endpointCaptures.properties.maxBytesTotal.const === 4194304, "endpoint capture total bound drift");
    expect(listeningSchema.properties.cases.items.required.indexOf("captureIds") >= 0 && listeningSchema.properties.cases.items.required.indexOf("evidence") < 0, "listening cases must bind structured capture IDs, not free-text evidence");
}

function git(args, options) {
    return cp.execFileSync("git", ["-c", "core.quotePath=false"].concat(args), {
        cwd: (options && options.root) || ROOT,
        encoding: options && options.buffer ? null : "utf8",
        maxBuffer: 64 * 1024 * 1024,
        stdio: ["ignore", "pipe", "pipe"]
    });
}

function gitObjectBinding(commit, rel, root) {
    var line;
    try {
        line = git(["ls-tree", commit, "--", rel], { root: root }).trim();
    } catch (error) {
        fail("cannot resolve " + commit + ":" + rel);
    }
    expect(line.length > 0, rel + " is not tracked in proposal commit " + commit);
    var match = line.match(/^\d+\s+blob\s+([0-9a-f]+)\t/);
    expect(match, "unexpected git ls-tree output for " + rel);
    var bytes = git(["show", commit + ":" + rel], { root: root, buffer: true });
    return { blobOid: match[1], bytes: bytes, sha256: sha256(bytes) };
}

function gitParents(commit, root) {
    var parts = git(["rev-list", "--parents", "-n", "1", commit], { root: root }).trim().split(/\s+/);
    return { commit: parts[0], parents: parts.slice(1) };
}

function gitChangedPaths(commit, root) {
    var output = git(["diff-tree", "--no-commit-id", "--name-only", "--no-renames", "-r", commit], { root: root }).trim();
    return output ? output.split(/\r?\n/).filter(Boolean) : [];
}

function gitPathExists(commit, rel, root) {
    var result = cp.spawnSync("git", ["cat-file", "-e", commit + ":" + rel], { cwd: root || ROOT, stdio: "ignore" });
    return result.status === 0;
}

function runtimeSourceDomainHashes(commit, root) {
    var configBinding = gitObjectBinding(commit, "config/build/runtime-inputs.v2.json", root);
    var configText = configBinding.bytes.toString("utf8").replace(/^\uFEFF/, "");
    var config;
    try { config = JSON.parse(configText); } catch (error) { fail("release source runtime input config is invalid JSON: " + error.message); }
    expect(config && config.schema === "cf7-runtime-inputs.v2" && config.domains, "release source runtime input config schema is invalid");
    var hashes = {};
    ["artifactSource", "producerRecipe", "toolchainLock"].forEach(function (domain) {
        var policy = config.domains[domain];
        expect(policy && Array.isArray(policy.fixedFiles) && Array.isArray(policy.trees), "release source runtime input domain is invalid: " + domain);
        var files = policy.fixedFiles.map(function (rel) { return String(rel).replace(/\\/g, "/"); });
        policy.trees.forEach(function (tree) {
            var base = String(tree.path || "").replace(/\\/g, "/").replace(/\/$/, "");
            expect(base && base.indexOf("..") < 0 && !path.isAbsolute(base), "runtime input tree path is unsafe: " + base);
            var output = git(["ls-tree", "-r", "--name-only", commit, "--", base], { root: root }).trim();
            var extensions = (tree.includeExtensions || []).map(function (value) { return String(value).toLowerCase(); });
            var excludePaths = (tree.excludePaths || []).map(function (value) { return String(value).replace(/\\/g, "/"); });
            var excludePrefixes = (tree.excludePrefixes || []).map(function (value) { return String(value).replace(/\\/g, "/"); });
            if (output) output.split(/\r?\n/).filter(Boolean).forEach(function (rel) {
                rel = rel.replace(/\\/g, "/");
                if (extensions.length && extensions.indexOf(path.posix.extname(rel).toLowerCase()) < 0) return;
                if (excludePaths.indexOf(rel) >= 0 || excludePrefixes.some(function (prefix) { return rel.indexOf(prefix) === 0; })) return;
                files.push(rel);
            });
        });
        files = Array.from(new Set(files)).sort();
        expect(files.length > 0, "runtime input domain is empty: " + domain);
        var rows = files.map(function (rel) {
            expect(rel && rel.indexOf("..") < 0 && !path.isAbsolute(rel), "runtime input path is unsafe: " + rel);
            return rel + "\t" + gitObjectBinding(commit, rel, root).blobOid;
        }).join("\n") + "\n";
        hashes[domain + "Hash"] = sha256(Buffer.from(rows, "utf8"));
    });
    hashes.configBlobOid = configBinding.blobOid;
    hashes.configSha256 = configBinding.sha256;
    return hashes;
}

function validateCandidateSourceDomains(parsedManifest, sourceDomains) {
    expect(parsedManifest.fields.artifactSourceHash === sourceDomains.artifactSourceHash && parsedManifest.fields.producerRecipeHash === sourceDomains.producerRecipeHash && parsedManifest.fields.toolchainLockHash === sourceDomains.toolchainLockHash, "candidate manifest domain hashes do not derive from release source S");
    return true;
}

function validateProposalShape(commit, root) {
    var ancestry = gitParents(commit, root);
    expect(ancestry.parents.length === 1, "proposal P must be a single-parent commit");
    var exactAllowed = ["AGENTS.md", ADR_PATH, MEMO_PATH, "docs/evidence/audio-v2/research-ready-preload-observation.json"].concat(FROZEN_CONTRACT_PATHS);
    var changed = gitChangedPaths(commit, root);
    changed.forEach(function (rel) {
        expect(exactAllowed.indexOf(rel) >= 0, "proposal P contains non-A0 path: " + rel);
    });
    exactAllowed.forEach(function (rel) {
        expect(changed.indexOf(rel) >= 0, "proposal P did not introduce/update required A0 path: " + rel);
    });
    expect(changed.length === exactAllowed.length, "proposal P changed path count differs from exact A0 set");
    TEMP_REVIEW_PATHS.forEach(function (rel) { expect(!gitPathExists(commit, rel, root), "temporary review exists in proposal tree: " + rel); });
    return { parent: ancestry.parents[0], paths: changed };
}

function resolveProposal(commit, root) {
    var fullCommit = git(["rev-parse", commit + "^{commit}"], { root: root }).trim();
    var tree = git(["rev-parse", fullCommit + "^{tree}"], { root: root }).trim();
    var shape = validateProposalShape(fullCommit, root);
    var paths = [ADR_PATH].concat(FROZEN_CONTRACT_PATHS);
    var bindings = {};
    paths.forEach(function (rel) { bindings[rel] = gitObjectBinding(fullCommit, rel, root); });
    var proposalManifest = parseJsonBuffer(bindings[MANIFEST_PATH].bytes, commit + ":" + MANIFEST_PATH);
    expect(bindings[MANIFEST_PATH].bytes.equals(canonicalBytes(proposalManifest)), "proposal manifest bytes are not canonical");
    validateManifest(proposalManifest);
    expect(shape.parent === proposalManifest.assetContract.proposalBaseline.sourceCommit, "proposal P parent must equal manifest proposalBaseline.sourceCommit");
    expect(git(["rev-parse", shape.parent + "^{tree}"], { root: root }).trim() === proposalManifest.assetContract.proposalBaseline.sourceTreeOid, "proposal P parent tree must equal manifest proposalBaseline.sourceTreeOid");
    validateAdrDigest(bindings[ADR_PATH].bytes.toString("utf8"), bindings[MANIFEST_PATH].sha256);
    return { bindings: bindings, commit: fullCommit, manifest: proposalManifest, parent: shape.parent, tree: tree };
}

function validateAdrDigest(adrText, digest) {
    var match = adrText.match(/decision manifest SHA-256[^`]*`([A-F0-9]{64})`/);
    expect(match, "ADR is missing decision manifest SHA-256 marker");
    expect(match[1] === digest, "ADR decision manifest SHA-256 does not match canonical manifest bytes");
    expect(adrText.indexOf("AUDIO-V2-H1-SWEET-SPOT-R2") >= 0, "ADR is missing R2 scope revision");
    expect(adrText.indexOf(MANIFEST_PATH) >= 0, "ADR does not route to canonical decision manifest");
}

function validateReceiptBinding(receipt, proposal) {
    exactKeys(receipt, ["authorization", "contract", "decision", "recordedAtUtc", "reviewer", "schema", "scopeRevision"], "H1 receipt");
    exactKeys(receipt.authorization, ["deploymentState", "phases", "promotionAuthorized"], "H1 receipt authorization");
    exactKeys(receipt.contract, ["adrBlobOid", "adrPath", "manifestBlobOid", "manifestPath", "manifestSha256", "proposalCommit", "proposalTree", "testBlobOid", "testPath", "validatorBlobOid", "validatorPath"], "H1 receipt contract");
    exactKeys(receipt.reviewer, ["channel", "role", "verbatim"], "H1 receipt reviewer");
    expect(receipt.schema === "cf7.audio-v2.h1-implementation-acceptance.v2", "unexpected H1 receipt schema");
    expect(receipt.scopeRevision === proposal.manifest.scopeRevision, "H1 receipt scope revision mismatch");
    expect(receipt.decision === "accepted", "H1 receipt decision must be accepted");
    expect(receipt.authorization.promotionAuthorized === false, "H1 receipt cannot authorize promotion");
    expect(receipt.authorization.deploymentState === "NOT_DEPLOYED", "H1 receipt must stay NOT_DEPLOYED");
    expect(JSON.stringify(receipt.authorization.phases) === JSON.stringify(["A1", "A2", "A3", "A4", "A5", "A6"]), "H1 receipt phases mismatch");
    expect(receipt.contract.proposalCommit === proposal.commit, "H1 receipt proposal commit mismatch");
    expect(receipt.contract.proposalTree === proposal.tree, "H1 receipt proposal tree mismatch");
    expect(receipt.contract.manifestPath === MANIFEST_PATH, "H1 receipt manifest path mismatch");
    expect(receipt.contract.manifestSha256 === proposal.bindings[MANIFEST_PATH].sha256, "H1 receipt manifest SHA mismatch");
    expect(receipt.contract.manifestBlobOid === proposal.bindings[MANIFEST_PATH].blobOid, "H1 receipt manifest blob mismatch");
    expect(receipt.contract.adrPath === ADR_PATH && receipt.contract.adrBlobOid === proposal.bindings[ADR_PATH].blobOid, "H1 receipt ADR binding mismatch");
    expect(receipt.contract.validatorPath === VALIDATOR_PATH && receipt.contract.validatorBlobOid === proposal.bindings[VALIDATOR_PATH].blobOid, "H1 receipt validator binding mismatch");
    expect(receipt.contract.testPath === TEST_PATH && receipt.contract.testBlobOid === proposal.bindings[TEST_PATH].blobOid, "H1 receipt test binding mismatch");
    expect(receipt.reviewer.role === "human-maintainer", "H1 reviewer role invalid");
    expectString(receipt.reviewer.channel, "H1 reviewer channel");
    expectRfc3339Utc(receipt.recordedAtUtc, "H1 recordedAtUtc");
    expect(normalizeHumanVerbatim(receipt.reviewer.verbatim) === formatH1Proposal(proposal), "human H1 verbatim must equal the exact proposal formatter output");
    return true;
}

function validateArtifactDescriptor(artifact, label) {
    exactKeys(artifact, ["blobOid", "bytes", "kind", "path", "schema", "sha256"], label);
    expect(artifact.kind === "tracked_blob", label + " must be a tracked_blob");
    expect(/^[0-9a-f]{40,64}$/.test(artifact.blobOid), label + " blobOid invalid");
    expectString(artifact.path, label + ".path");
    expect(Number.isInteger(artifact.bytes) && artifact.bytes > 0, label + " bytes invalid");
    expectString(artifact.schema, label + ".schema");
    expect(/^[A-F0-9]{64}$/.test(artifact.sha256), label + " sha256 invalid");
}

function verifyTrackedArtifact(artifact, commit, root, label) {
    validateArtifactDescriptor(artifact, label);
    var binding = gitObjectBinding(commit, artifact.path, root);
    expect(binding.blobOid === artifact.blobOid, label + " blobOid does not match evidence commit");
    expect(binding.bytes.length === artifact.bytes, label + " byte count does not match evidence commit");
    expect(binding.sha256 === artifact.sha256, label + " SHA-256 does not match evidence commit");
    return binding;
}

function validateListeningMatrix(matrix, expectedIdentity, expectedClosure) {
    exactKeys(matrix, ["allPassed", "candidateBuildIdentity", "candidatePayloadClosure", "cases", "recordedAtUtc", "reviewer", "schema"], "listening matrix");
    expect(matrix.schema === "cf7.audio-v2.human-listening-matrix.v1", "unexpected listening matrix schema");
    expect(matrix.allPassed === true, "listening matrix must be allPassed");
    expect(matrix.candidateBuildIdentity === expectedIdentity, "listening matrix identity mismatch");
    expect(matrix.candidatePayloadClosure === expectedClosure, "listening matrix closure mismatch");
    expectRfc3339Utc(matrix.recordedAtUtc, "listening matrix recordedAtUtc");
    expectString(matrix.reviewer, "listening matrix reviewer");
    var expectedCases = [
        "formats_shipped_and_new", "bgm_transport_and_crossfade",
        "dense_sfx_overlap_and_throttle", "bgm_sfx_simultaneous",
        "gain_zero_default_max", "default_device_switch",
        "physical_route_bluetooth_or_hdmi", "sleep_resume",
        "quality_pop_latency_channel_loudness", "no_stale_sfx_after_recovery"
    ];
    expect(Array.isArray(matrix.cases), "listening matrix cases must be an array");
    var actualCases = matrix.cases.map(function (entry, index) {
        exactKeys(entry, ["captureIds", "caseId", "notes", "result"], "listening matrix case " + index);
        expect(entry.result === "passed", "listening case must pass: " + entry.caseId);
        var requiredCaptureIds = REQUIRED_LISTENING_CAPTURE_IDS[entry.caseId];
        expect(requiredCaptureIds, "unknown listening case: " + entry.caseId);
        expect(Array.isArray(entry.captureIds) && JSON.stringify(entry.captureIds) === JSON.stringify(requiredCaptureIds), "listening case capture binding mismatch: " + entry.caseId);
        expect(typeof entry.notes === "string", "listening case notes must be string");
        return entry.caseId;
    }).sort();
    expect(JSON.stringify(actualCases) === JSON.stringify(expectedCases.slice().sort()), "listening matrix must contain each required case exactly once");
    return true;
}

function validateAutomatedReport(report, expectedReportId, evidence) {
    exactKeys(report, ["candidateBuildIdentity", "candidatePayloadClosure", "caseResults", "caseResultsSha256", "generatedAtUtc", "provenance", "releaseSource", "reportId", "result", "schema", "summary"], "automated report " + expectedReportId);
    expect(report.schema === "cf7.audio-v2.automated-report.v1", "automated report schema mismatch: " + expectedReportId);
    expect(report.reportId === expectedReportId && report.result === "passed", "automated report ID/result mismatch: " + expectedReportId);
    expect(REQUIRED_AUTOMATED_REPORT_CASES[expectedReportId], "unknown automated report ID: " + expectedReportId);
    expect(report.candidateBuildIdentity === evidence.candidate.buildIdentity && report.candidatePayloadClosure === evidence.candidate.payloadClosure, "automated report identity/closure mismatch: " + expectedReportId);
    exactKeys(report.releaseSource, ["commit", "treeOid"], "automated report release source");
    expect(report.releaseSource.commit === evidence.releaseSource.commit && report.releaseSource.treeOid === evidence.releaseSource.treeOid, "automated report release source mismatch: " + expectedReportId);
    expectRfc3339Utc(report.generatedAtUtc, "automated report generatedAtUtc");
    exactKeys(report.summary, ["failed", "passed", "total"], "automated report summary");
    expect(Number.isInteger(report.summary.passed) && report.summary.passed > 0 && report.summary.failed === 0 && report.summary.total === report.summary.passed, "automated report summary must be all-pass: " + expectedReportId);
    expect(Array.isArray(report.caseResults) && report.caseResults.length === report.summary.total, "automated report case count mismatch: " + expectedReportId);
    var caseIds = [];
    var caseEvidencePaths = [];
    var caseEvidenceBlobs = [];
    var caseEvidenceShas = [];
    report.caseResults.forEach(function (entry, index) {
        exactKeys(entry, ["caseId", "evidenceArtifact", "result"], "automated report case " + index);
        expectString(entry.caseId, "automated report caseId");
        expect(caseIds.indexOf(entry.caseId) < 0, "duplicate automated report caseId: " + entry.caseId);
        caseIds.push(entry.caseId);
        validateArtifactDescriptor(entry.evidenceArtifact, "automated report case evidence " + entry.caseId);
        var expectedEvidenceSchema = expectedReportId === "asset_offline_eof_qualification" && entry.caseId === "shipped_corpus_all_files"
            ? "cf7.audio-v2.asset-eof-results.v1"
            : "cf7.audio-v2.automated-case-evidence.v1";
        expect(entry.evidenceArtifact.schema === expectedEvidenceSchema, "automated report case evidence schema mismatch: " + entry.caseId);
        expect(caseEvidencePaths.indexOf(entry.evidenceArtifact.path) < 0, "automated report case evidence paths must be distinct: " + entry.evidenceArtifact.path);
        expect(caseEvidenceBlobs.indexOf(entry.evidenceArtifact.blobOid) < 0 && caseEvidenceShas.indexOf(entry.evidenceArtifact.sha256) < 0, "automated report case evidence bytes must be distinct: " + entry.caseId);
        caseEvidencePaths.push(entry.evidenceArtifact.path);
        caseEvidenceBlobs.push(entry.evidenceArtifact.blobOid);
        caseEvidenceShas.push(entry.evidenceArtifact.sha256);
        expect(entry.result === "passed", "automated report case must pass: " + entry.caseId);
    });
    expect(JSON.stringify(caseIds.slice().sort()) === JSON.stringify(REQUIRED_AUTOMATED_REPORT_CASES[expectedReportId].slice().sort()), "automated report required case coverage mismatch: " + expectedReportId);
    expect(report.caseResultsSha256 === sha256(canonicalBytes(report.caseResults)), "automated report case-results closure mismatch: " + expectedReportId);
    exactKeys(report.provenance, ["configurationArtifact", "inputClosureSha256", "inputManifestArtifact", "producerBlobOid", "producerDependencyManifestArtifact", "producerPath", "producerSha256"], "automated report provenance " + expectedReportId);
    validateArtifactDescriptor(report.provenance.configurationArtifact, "automated report configuration artifact " + expectedReportId);
    validateArtifactDescriptor(report.provenance.inputManifestArtifact, "automated report input manifest artifact " + expectedReportId);
    validateArtifactDescriptor(report.provenance.producerDependencyManifestArtifact, "qualification runner dependency manifest artifact " + expectedReportId);
    expect(report.provenance.configurationArtifact.schema === "cf7.audio-v2.automated-report-configuration.v1", "automated report configuration artifact schema mismatch: " + expectedReportId);
    expect(report.provenance.inputManifestArtifact.schema === "cf7.audio-v2.automated-report-input-manifest.v1", "automated report input manifest artifact schema mismatch: " + expectedReportId);
    expect(report.provenance.producerDependencyManifestArtifact.schema === "cf7.audio-v2.qualification-runner-dependencies.v1", "qualification runner dependency manifest artifact schema mismatch: " + expectedReportId);
    expect(report.provenance.producerDependencyManifestArtifact.path === RUNNER_DEPENDENCY_PATH, "qualification runner dependency manifest path mismatch: " + expectedReportId);
    expect(/^[A-F0-9]{64}$/.test(report.provenance.inputClosureSha256), "automated report input closure invalid: " + expectedReportId);
    expect(/^[0-9a-f]{40,64}$/.test(report.provenance.producerBlobOid), "automated report producer blob invalid: " + expectedReportId);
    expect(/^[A-F0-9]{64}$/.test(report.provenance.producerSha256), "automated report producer SHA invalid: " + expectedReportId);
    expectString(report.provenance.producerPath, "automated report producer path");
    expect(report.provenance.producerPath === QUALIFICATION_RUNNER_PATH, "automated report producer must use the frozen qualification runner: " + expectedReportId);
    return true;
}

function endpointClosureDigest(endpointCaptures) {
    var closure = endpointCaptures.items.map(function (capture) {
        return {
            artifactSha256: capture.artifact.sha256,
            blobOid: capture.artifact.blobOid,
            bytes: capture.artifact.bytes,
            captureId: capture.captureId,
            caseIds: capture.caseIds.slice().sort(),
            channels: capture.channels,
            configurationArtifact: {
                blobOid: capture.configurationArtifact.blobOid,
                bytes: capture.configurationArtifact.bytes,
                path: capture.configurationArtifact.path,
                sha256: capture.configurationArtifact.sha256
            },
            durationSeconds: capture.durationSeconds,
            format: capture.format,
            path: capture.artifact.path,
            sampleRate: capture.sampleRate,
            toolArtifact: {
                blobOid: capture.toolArtifact.blobOid,
                bytes: capture.toolArtifact.bytes,
                path: capture.toolArtifact.path,
                sha256: capture.toolArtifact.sha256
            }
        };
    }).sort(function (left, right) { return left.captureId.localeCompare(right.captureId); });
    return sha256(canonicalBytes(closure));
}

function validateA6EvidenceManifest(evidence, listeningMatrix) {
    exactKeys(evidence, ["automatedReports", "candidate", "candidateVerification", "device", "endpointCaptures", "listeningMatrix", "qualificationRunner", "releaseSource", "schema"], "A6 evidence manifest");
    expect(evidence.schema === "cf7.audio-v2.a6-evidence-manifest.v1", "unexpected A6 evidence schema");
    exactKeys(evidence.releaseSource, ["commit", "treeOid"], "A6 release source");
    expect(/^[0-9a-f]{40}$/.test(evidence.releaseSource.commit), "A6 release source commit invalid");
    expect(/^[0-9a-f]{40,64}$/.test(evidence.releaseSource.treeOid), "A6 release source tree invalid");
    exactKeys(evidence.candidate, ["buildIdentity", "coreBytes", "coreSha256", "manifestBytes", "manifestSha256", "miniaudioBytes", "miniaudioSha256", "payloadClosure"], "A6 candidate");
    ["buildIdentity", "coreSha256", "manifestSha256", "miniaudioSha256", "payloadClosure"].forEach(function (key) {
        expect(/^[A-F0-9]{64}$/.test(evidence.candidate[key]), "A6 candidate " + key + " invalid");
    });
    ["coreBytes", "manifestBytes", "miniaudioBytes"].forEach(function (key) {
        expect(Number.isInteger(evidence.candidate[key]) && evidence.candidate[key] > 0, "A6 candidate " + key + " invalid");
    });
    exactKeys(evidence.candidateVerification, ["artifact"], "A6 candidate verification binding");
    validateArtifactDescriptor(evidence.candidateVerification.artifact, "candidate verification artifact");
    expect(evidence.candidateVerification.artifact.schema === "cf7.audio-v2.candidate-verification.v1", "candidate verification artifact schema mismatch");
    exactKeys(evidence.device, ["audioDeviceQualified", "channels", "deviceIdDigest", "sampleFormat", "sampleRate", "selectedBackend", "selectedDeviceName"], "A6 device");
    expect(evidence.device.audioDeviceQualified === true, "A6 device must be qualified");
    expect(["wasapi", "directsound", "winmm"].indexOf(evidence.device.selectedBackend) >= 0, "A6 backend must be real and allowlisted");
    expect(/^[A-F0-9]{64}$/.test(evidence.device.deviceIdDigest), "A6 device digest invalid");
    expect(Number.isInteger(evidence.device.channels) && evidence.device.channels > 0, "A6 device channels invalid");
    expect(Number.isInteger(evidence.device.sampleRate) && evidence.device.sampleRate >= 8000, "A6 device sampleRate invalid");
    expectString(evidence.device.sampleFormat, "A6 device sampleFormat");
    expectString(evidence.device.selectedDeviceName, "A6 selectedDeviceName");
    exactKeys(evidence.qualificationRunner, ["artifact"], "A6 qualification runner binding");
    validateArtifactDescriptor(evidence.qualificationRunner.artifact, "A6 qualification runner artifact");
    expect(evidence.qualificationRunner.artifact.path === QUALIFICATION_RUNNER_PATH && evidence.qualificationRunner.artifact.schema === "application/javascript", "A6 qualification runner must bind the fixed S-tracked JavaScript trust root");
    expect(Array.isArray(evidence.automatedReports) && evidence.automatedReports.length === REQUIRED_AUTOMATED_REPORT_IDS.length, "A6 must bind exactly nine automated reports");
    var reportPaths = [];
    var verificationPaths = [];
    var verificationBlobs = [];
    var verificationShas = [];
    var reportIds = evidence.automatedReports.map(function (report, index) {
        exactKeys(report, ["artifact", "reportId", "verificationArtifact"], "automatedReports[" + index + "]");
        validateArtifactDescriptor(report.artifact, "automatedReports[" + index + "].artifact");
        validateArtifactDescriptor(report.verificationArtifact, "automatedReports[" + index + "].verificationArtifact");
        expect(report.artifact.schema === "cf7.audio-v2.automated-report.v1", "automated report artifact schema mismatch");
        expect(report.verificationArtifact.schema === "cf7.audio-v2.producer-verification.v1", "producer verification artifact schema mismatch");
        expect(reportPaths.indexOf(report.artifact.path) < 0, "automated reports must use distinct paths");
        reportPaths.push(report.artifact.path);
        expect(verificationPaths.indexOf(report.verificationArtifact.path) < 0, "producer verifications must use distinct paths");
        expect(verificationBlobs.indexOf(report.verificationArtifact.blobOid) < 0 && verificationShas.indexOf(report.verificationArtifact.sha256) < 0, "producer verifications must use distinct bytes");
        verificationPaths.push(report.verificationArtifact.path);
        verificationBlobs.push(report.verificationArtifact.blobOid);
        verificationShas.push(report.verificationArtifact.sha256);
        return report.reportId;
    }).sort();
    expect(JSON.stringify(reportIds) === JSON.stringify(REQUIRED_AUTOMATED_REPORT_IDS.slice().sort()), "A6 must bind each required automated report exactly once");
    exactKeys(evidence.endpointCaptures, ["closureSha256", "items", "maxBytesEach", "maxBytesTotal"], "endpoint captures");
    expect(evidence.endpointCaptures.maxBytesEach === 1048576 && evidence.endpointCaptures.maxBytesTotal === 4194304, "endpoint capture size policy drift");
    expect(Array.isArray(evidence.endpointCaptures.items) && evidence.endpointCaptures.items.length === REQUIRED_ENDPOINT_CASE_IDS.length, "endpoint captures must contain exactly four case-specific WAVs");
    var captureIds = [];
    var capturePaths = [];
    var captureBlobs = [];
    var captureShas = [];
    var captureConfigurationPaths = [];
    var captureConfigurationBlobs = [];
    var captureConfigurationShas = [];
    var endpointCases = [];
    var endpointBytes = 0;
    evidence.endpointCaptures.items.forEach(function (capture, index) {
        exactKeys(capture, ["artifact", "captureId", "caseIds", "channels", "configurationArtifact", "durationSeconds", "format", "sampleRate", "toolArtifact"], "endpointCaptures.items[" + index + "]");
        validateArtifactDescriptor(capture.artifact, "endpointCaptures.items[" + index + "].artifact");
        validateArtifactDescriptor(capture.configurationArtifact, "endpointCaptures.items[" + index + "].configurationArtifact");
        validateArtifactDescriptor(capture.toolArtifact, "endpointCaptures.items[" + index + "].toolArtifact");
        expect(capture.artifact.schema === "audio/wav-pcm-s16le", "endpoint capture artifact schema mismatch");
        expect(capture.configurationArtifact.schema === "cf7.audio-v2.endpoint-capture-configuration.v1", "endpoint capture configuration artifact schema mismatch");
        expect(capture.toolArtifact.schema === "application/powershell" && capture.toolArtifact.path === ENDPOINT_CAPTURE_TOOL_PATH, "endpoint capture tool must bind the fixed S-tracked PowerShell trust root");
        expect(capturePaths.indexOf(capture.artifact.path) < 0, "endpoint captures must use distinct paths");
        capturePaths.push(capture.artifact.path);
        expect(captureBlobs.indexOf(capture.artifact.blobOid) < 0 && captureShas.indexOf(capture.artifact.sha256) < 0, "endpoint captures must use distinct audio bytes, not copied blobs");
        captureBlobs.push(capture.artifact.blobOid);
        captureShas.push(capture.artifact.sha256);
        expectString(capture.captureId, "endpoint captureId");
        expect(captureIds.indexOf(capture.captureId) < 0, "duplicate endpoint captureId: " + capture.captureId);
        captureIds.push(capture.captureId);
        expect(capture.artifact.path === "docs/evidence/audio-v2/captures/" + capture.captureId + ".wav", "endpoint capture path must be canonical for captureId: " + capture.captureId);
        expect(capture.configurationArtifact.path === "docs/evidence/audio-v2/capture-config/" + capture.captureId + ".json", "endpoint capture configuration path must be canonical for captureId: " + capture.captureId);
        expect(captureConfigurationPaths.indexOf(capture.configurationArtifact.path) < 0 && captureConfigurationBlobs.indexOf(capture.configurationArtifact.blobOid) < 0 && captureConfigurationShas.indexOf(capture.configurationArtifact.sha256) < 0, "endpoint captures must use distinct configuration artifacts");
        captureConfigurationPaths.push(capture.configurationArtifact.path);
        captureConfigurationBlobs.push(capture.configurationArtifact.blobOid);
        captureConfigurationShas.push(capture.configurationArtifact.sha256);
        expect(Array.isArray(capture.caseIds) && capture.caseIds.length === 1, "each endpoint capture must bind exactly one caseId");
        capture.caseIds.forEach(function (caseId) { expect(REQUIRED_ENDPOINT_CASE_IDS.indexOf(caseId) >= 0, "unknown endpoint caseId: " + caseId); endpointCases.push(caseId); });
        expect(capture.captureId === capture.caseIds[0], "endpoint captureId must equal its single caseId");
        expect(Number.isInteger(capture.channels) && capture.channels > 0, "endpoint channels invalid");
        expect(Number.isInteger(capture.sampleRate) && capture.sampleRate >= 8000, "endpoint sampleRate invalid");
        expect(typeof capture.durationSeconds === "number" && Number.isFinite(capture.durationSeconds) && capture.durationSeconds >= 1, "endpoint duration invalid");
        expectString(capture.format, "endpoint format");
        expect(capture.format === "pcm_s16le", "endpoint format must be pcm_s16le");
        expect(capture.artifact.bytes <= evidence.endpointCaptures.maxBytesEach, "endpoint capture exceeds per-file bound");
        endpointBytes += capture.artifact.bytes;
    });
    expect(endpointBytes <= evidence.endpointCaptures.maxBytesTotal, "endpoint captures exceed total byte bound");
    expect(JSON.stringify(endpointCases.slice().sort()) === JSON.stringify(REQUIRED_ENDPOINT_CASE_IDS.slice().sort()), "endpoint captures must cover each required endpoint case exactly once");
    expect(evidence.endpointCaptures.closureSha256 === endpointClosureDigest(evidence.endpointCaptures), "endpoint capture closure digest mismatch");
    exactKeys(evidence.listeningMatrix, ["allPassed", "artifact", "sha256"], "A6 listening matrix binding");
    expect(evidence.listeningMatrix.allPassed === true, "A6 listening matrix binding must pass");
    validateArtifactDescriptor(evidence.listeningMatrix.artifact, "listening matrix artifact");
    expect(evidence.listeningMatrix.artifact.schema === "cf7.audio-v2.human-listening-matrix.v1", "listening matrix artifact schema mismatch");
    expect(evidence.listeningMatrix.sha256 === evidence.listeningMatrix.artifact.sha256, "listening matrix SHA and artifact SHA mismatch");
    if (listeningMatrix) {
        validateListeningMatrix(listeningMatrix, evidence.candidate.buildIdentity, evidence.candidate.payloadClosure);
        expect(sha256(canonicalBytes(listeningMatrix)) === evidence.listeningMatrix.sha256, "listening matrix bytes mismatch A6 binding");
    }
    return true;
}

function validateH2ReceiptBinding(receipt, evidenceContext) {
    exactKeys(receipt, ["authorization", "decision", "evidence", "recordedAtUtc", "releaseSource", "reviewer", "schema"], "H2 receipt");
    exactKeys(receipt.authorization, ["promotionAuthorized"], "H2 authorization");
    exactKeys(receipt.evidence, ["audioDeviceQualified", "candidateVerificationSha256", "commit", "endpointCaptureToolSha256", "endpointClosureSha256", "listeningMatrixSha256", "manifestBlobOid", "manifestPath", "manifestSha256", "qualificationRunnerSha256", "treeOid"], "H2 evidence binding");
    exactKeys(receipt.releaseSource, ["buildIdentity", "commit", "payloadClosure", "treeOid"], "H2 release source");
    exactKeys(receipt.reviewer, ["channel", "role", "verbatim"], "H2 reviewer");
    expect(receipt.schema === "cf7.audio-v2.h2-promotion-acceptance.v2", "unexpected H2 receipt schema");
    expect(receipt.decision === "accepted" && receipt.authorization.promotionAuthorized === true, "H2 must explicitly authorize promotion");
    expect(receipt.evidence.audioDeviceQualified === true, "H2 must bind audioDeviceQualified=true");
    expect(receipt.evidence.commit === evidenceContext.commit && receipt.evidence.treeOid === evidenceContext.tree, "H2 evidence commit/tree mismatch");
    expect(receipt.evidence.manifestPath === evidenceContext.path, "H2 evidence path mismatch");
    expect(receipt.evidence.manifestBlobOid === evidenceContext.blobOid && receipt.evidence.manifestSha256 === evidenceContext.sha256, "H2 evidence blob/SHA mismatch");
    expect(receipt.evidence.candidateVerificationSha256 === evidenceContext.manifest.candidateVerification.artifact.sha256, "H2 candidate verification SHA mismatch");
    expect(receipt.releaseSource.commit === evidenceContext.manifest.releaseSource.commit && receipt.releaseSource.treeOid === evidenceContext.manifest.releaseSource.treeOid, "H2 release source mismatch");
    expect(receipt.releaseSource.buildIdentity === evidenceContext.manifest.candidate.buildIdentity && receipt.releaseSource.payloadClosure === evidenceContext.manifest.candidate.payloadClosure, "H2 identity/closure mismatch");
    expect(receipt.evidence.endpointClosureSha256 === evidenceContext.manifest.endpointCaptures.closureSha256, "H2 endpoint closure mismatch");
    expect(receipt.evidence.endpointCaptureToolSha256 === evidenceContext.manifest.endpointCaptures.items[0].toolArtifact.sha256, "H2 endpoint capture tool trust-root SHA mismatch");
    expect(receipt.evidence.listeningMatrixSha256 === evidenceContext.manifest.listeningMatrix.sha256, "H2 listening matrix mismatch");
    expect(receipt.evidence.qualificationRunnerSha256 === evidenceContext.manifest.qualificationRunner.artifact.sha256, "H2 qualification runner trust-root SHA mismatch");
    expect(receipt.reviewer.role === "human-maintainer", "H2 reviewer role invalid");
    expectString(receipt.reviewer.channel, "H2 reviewer channel");
    expectRfc3339Utc(receipt.recordedAtUtc, "H2 recordedAtUtc");
    expect(normalizeHumanVerbatim(receipt.reviewer.verbatim) === formatH2Proposal(evidenceContext), "human H2 verbatim must equal the exact evidence formatter output");
    return true;
}

function formatH1Proposal(proposal) {
    return [
        "H1_IMPLEMENTATION_ACCEPTANCE",
        "scopeRevision=" + proposal.manifest.scopeRevision,
        "proposalCommit=" + proposal.commit,
        "proposalTree=" + proposal.tree,
        "manifestPath=" + MANIFEST_PATH,
        "manifestSha256=" + proposal.bindings[MANIFEST_PATH].sha256,
        "promotionAuthorized=false",
        "decision=accepted"
    ].join("\n");
}

function formatH2Proposal(evidenceContext) {
    var evidence = evidenceContext.manifest;
    return [
        "H2_PROMOTION_ACCEPTANCE",
        "releaseSourceCommit=" + evidence.releaseSource.commit,
        "releaseSourceTree=" + evidence.releaseSource.treeOid,
        "buildIdentity=" + evidence.candidate.buildIdentity,
        "payloadClosure=" + evidence.candidate.payloadClosure,
        "evidenceCommit=" + evidenceContext.commit,
        "evidenceTree=" + evidenceContext.tree,
        "evidenceManifestPath=" + evidenceContext.path,
        "evidenceManifestSha256=" + evidenceContext.sha256,
        "candidateVerificationSha256=" + evidence.candidateVerification.artifact.sha256,
        "endpointCaptureToolSha256=" + evidence.endpointCaptures.items[0].toolArtifact.sha256,
        "endpointClosureSha256=" + evidence.endpointCaptures.closureSha256,
        "listeningMatrixSha256=" + evidence.listeningMatrix.sha256,
        "qualificationRunnerSha256=" + evidence.qualificationRunner.artifact.sha256,
        "audioDeviceQualified=true",
        "promotionAuthorized=true",
        "decision=accepted"
    ].join("\n");
}

function formatJsonFiles() {
    [MANIFEST_PATH, MANIFEST_SCHEMA_PATH, H1_SCHEMA_PATH, AUTOMATED_REPORT_SCHEMA_PATH, AUTOMATED_REPORT_CONFIGURATION_SCHEMA_PATH, AUTOMATED_REPORT_INPUT_SCHEMA_PATH, AUTOMATED_CASE_EVIDENCE_SCHEMA_PATH, ASSET_EOF_RESULTS_SCHEMA_PATH, ASSET_WAIVER_SCHEMA_PATH, CANDIDATE_VERIFICATION_SCHEMA_PATH, ENDPOINT_CAPTURE_CONFIGURATION_SCHEMA_PATH, PRODUCER_VERIFICATION_SCHEMA_PATH, RUNNER_DEPENDENCY_SCHEMA_PATH, A6_SCHEMA_PATH, LISTENING_SCHEMA_PATH, H2_SCHEMA_PATH, "docs/evidence/audio-v2/research-ready-preload-observation.json"].forEach(function (rel) {
        var parsed = readJson(rel).value;
        fs.writeFileSync(absolute(rel), canonicalBytes(parsed));
    });
}

function validateFrozenWorkingBytes(proposal) {
    FROZEN_CONTRACT_PATHS.forEach(function (rel) {
        var current = fs.readFileSync(absolute(rel));
        expect(current.equals(proposal.bindings[rel].bytes), "frozen contract path differs from proposal P; raise revision and obtain a new H1: " + rel);
    });
}

function validateReleaseSourceFreeze(proposal, releaseCommit, root) {
    FROZEN_CONTRACT_PATHS.forEach(function (rel) {
        var source = gitObjectBinding(releaseCommit, rel, root);
        var accepted = proposal.bindings[rel];
        expect(source.blobOid === accepted.blobOid && source.sha256 === accepted.sha256 && source.bytes.equals(accepted.bytes), "release source S changed frozen H1 contract bytes; raise revision and obtain a new H1: " + rel);
    });
    return true;
}

function trackedHeadText(rel, label, root) {
    var binding = gitObjectBinding("HEAD", rel, root);
    var working = fs.readFileSync(absolute(rel, root));
    expect(working.equals(binding.bytes), label + " working bytes differ from HEAD; commit the atomic recovery state before validation");
    return binding.bytes.toString("utf8");
}

function validateCanonicalCheckoutPolicy(root) {
    var text = fs.readFileSync(absolute(GITATTRIBUTES_PATH, root), "utf8").replace(/\r\n/g, "\n");
    [
        "/docs/contracts/audio-v2/*.json text eol=lf",
        "/docs/evidence/audio-v2/*.json text eol=lf",
        "/docs/evidence/audio-v2/**/*.json text eol=lf",
        "/tools/audio-v2/*.js text eol=lf"
    ].forEach(function (line) {
        expect(text.split("\n").indexOf(line) >= 0, "audio v2 canonical checkout rule missing from .gitattributes: " + line);
    });
    return true;
}

function introductionCommits(rel, head, root) {
    var output = git(["log", "--format=%H", "--diff-filter=A", head || "HEAD", "--", rel], { root: root }).trim();
    return output ? output.split(/\r?\n/).filter(Boolean) : [];
}

function introductionCommit(rel, head, root) {
    var commits = introductionCommits(rel, head, root);
    expect(commits.length === 1, rel + " must have exactly one introduction commit");
    return commits[0];
}

function expectDirectEvidenceCommit(commit, expectedParent, exactPaths, label, root) {
    var ancestry = gitParents(commit, root);
    expect(ancestry.parents.length === 1 && ancestry.parents[0] === expectedParent, label + " must be a direct single-parent child of " + expectedParent);
    var changed = gitChangedPaths(commit, root).sort();
    expect(JSON.stringify(changed) === JSON.stringify(exactPaths.slice().sort()), label + " changed paths must be exactly: " + exactPaths.join(", ") + "; got: " + changed.join(", "));
}

function validateH1Activation(proposal, receiptFile) {
    var activationCommit = introductionCommit(H1_RECEIPT_PATH, "HEAD");
    expectDirectEvidenceCommit(activationCommit, proposal.commit, [ADR_PATH, MEMO_PATH, H1_RECEIPT_PATH], "H1 activation commit");
    var receiptAtActivation = gitObjectBinding(activationCommit, H1_RECEIPT_PATH);
    expect(receiptAtActivation.bytes.equals(receiptFile.buffer), "H1 receipt changed after activation or differs from activation commit");
    var receiptAtHead = gitObjectBinding("HEAD", H1_RECEIPT_PATH);
    expect(receiptAtHead.blobOid === receiptAtActivation.blobOid && receiptAtHead.bytes.equals(receiptAtActivation.bytes), "H1 receipt changed after activation in the current HEAD tree");
    var adrAtActivation = gitObjectBinding(activationCommit, ADR_PATH).bytes.toString("utf8");
    var memoAtActivation = gitObjectBinding(activationCommit, MEMO_PATH).bytes.toString("utf8");
    validateTopRecoveryState(adrAtActivation, ADR_RECOVERY_STATES.h1, "H1 activation ADR");
    validateTopRecoveryState(memoAtActivation, MEMO_RECOVERY_STATES.h1, "H1 activation memo");
    [
        "| H1 | accepted |",
        "| A0 | completed_H1 |",
        "| A1 | authorized_pending |",
        "当前 H1 已有效"
    ].forEach(function (needle) { expect(adrAtActivation.indexOf(needle) >= 0, "H1 activation ADR is missing atomic recovery marker: " + needle); });
    [
        "当前 H1 已有效"
    ].forEach(function (needle) { expect(memoAtActivation.indexOf(needle) >= 0, "H1 activation memo is missing atomic recovery marker: " + needle); });
    return activationCommit;
}

function parseWavePcm(buffer, label) {
    expect(buffer.length >= 44, label + " WAV is too small");
    expect(buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WAVE", label + " is not RIFF/WAVE");
    var offset = 12;
    var format = null;
    var dataBytes = null;
    var dataStart = null;
    while (offset + 8 <= buffer.length) {
        var chunkId = buffer.toString("ascii", offset, offset + 4);
        var chunkBytes = buffer.readUInt32LE(offset + 4);
        var start = offset + 8;
        expect(start + chunkBytes <= buffer.length, label + " has truncated WAV chunk " + chunkId);
        if (chunkId === "fmt ") {
            expect(chunkBytes >= 16, label + " fmt chunk too small");
            format = {
                audioFormat: buffer.readUInt16LE(start),
                channels: buffer.readUInt16LE(start + 2),
                sampleRate: buffer.readUInt32LE(start + 4),
                bitsPerSample: buffer.readUInt16LE(start + 14)
            };
        } else if (chunkId === "data") {
            dataBytes = chunkBytes;
            dataStart = start;
        }
        offset = start + chunkBytes + (chunkBytes % 2);
    }
    expect(format && dataBytes !== null, label + " must contain fmt and data chunks");
    expect(format.audioFormat === 1 && format.bitsPerSample === 16, label + " must be PCM s16le");
    var bytesPerFrame = format.channels * 2;
    var nonZeroSamples = 0;
    var peakAbs = 0;
    var totalSamples = 0;
    for (var sampleOffset = dataStart; sampleOffset + 1 < dataStart + dataBytes; sampleOffset += 2) {
        var sample = buffer.readInt16LE(sampleOffset);
        var magnitude = Math.abs(sample);
        if (sample !== 0) nonZeroSamples++;
        if (magnitude > peakAbs) peakAbs = magnitude;
        totalSamples++;
    }
    return { channels: format.channels, durationSeconds: dataBytes / bytesPerFrame / format.sampleRate, frames: dataBytes / bytesPerFrame, nonZeroSampleRatio: totalSamples ? nonZeroSamples / totalSamples : 0, nonZeroSamples: nonZeroSamples, peakAbs: peakAbs, sampleRate: format.sampleRate };
}

function sameFilesystemPath(left, right) {
    var normalizedLeft = path.resolve(left).replace(/[\\/]+$/, "");
    var normalizedRight = path.resolve(right).replace(/[\\/]+$/, "");
    if (process.platform === "win32") {
        normalizedLeft = normalizedLeft.toLowerCase();
        normalizedRight = normalizedRight.toLowerCase();
    }
    return normalizedLeft === normalizedRight;
}

function readCandidateFile(candidateRoot, relativePath, label) {
    var resolvedRoot = fs.realpathSync.native(candidateRoot);
    var relativeParts = relativePath.split("/");
    var fullPath = path.resolve(candidateRoot, relativeParts.join(path.sep));
    var rootPrefix = path.resolve(candidateRoot) + path.sep;
    var comparableFull = process.platform === "win32" ? fullPath.toLowerCase() : fullPath;
    var comparablePrefix = process.platform === "win32" ? rootPrefix.toLowerCase() : rootPrefix;
    expect(comparableFull.indexOf(comparablePrefix) === 0, label + " escapes candidate root");
    var componentPath = candidateRoot;
    relativeParts.slice(0, -1).forEach(function (part) {
        componentPath = path.join(componentPath, part);
        var componentStat = fs.lstatSync(componentPath);
        expect(componentStat.isDirectory() && !componentStat.isSymbolicLink(), label + " traverses a link/reparse directory: " + part);
    });
    var stat = fs.lstatSync(fullPath);
    expect(stat.isFile() && !stat.isSymbolicLink(), label + " must be a regular non-link file");
    var realFile = fs.realpathSync.native(fullPath);
    var realPrefix = resolvedRoot + path.sep;
    var comparableRealFile = process.platform === "win32" ? realFile.toLowerCase() : realFile;
    var comparableRealPrefix = process.platform === "win32" ? realPrefix.toLowerCase() : realPrefix;
    expect(comparableRealFile.indexOf(comparableRealPrefix) === 0, label + " resolves outside candidate root");
    return fs.readFileSync(realFile);
}

function runtimeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash) {
    [artifactSourceHash, producerRecipeHash, toolchainLockHash].forEach(function (value) { expect(/^[A-F0-9]{64}$/.test(value), "runtime build identity component invalid"); });
    return sha256(Buffer.from(
        "artifactSourceHash\t" + artifactSourceHash + "\n" +
        "producerRecipeHash\t" + producerRecipeHash + "\n" +
        "toolchainLockHash\t" + toolchainLockHash + "\n",
        "utf8"
    ));
}

function runtimePayloadClosureHash(files) {
    expect(Array.isArray(files) && files.length > 0, "candidate payload file set must not be empty");
    var rows = files.slice().sort(function (left, right) { return left.path.localeCompare(right.path); });
    var lowerPaths = [];
    var canonical = rows.map(function (row) {
        expect(typeof row.path === "string" && row.path.length > 0 && !row.path.startsWith("/") && row.path.indexOf("\\") < 0 && !/(^|\/)\.\.(\/|$)/.test(row.path) && !/[\t\r\n:*?"<>|]/.test(row.path), "candidate payload path is unsafe: " + row.path);
        expect(Number.isSafeInteger(row.bytes) && row.bytes >= 0 && /^[A-F0-9]{64}$/.test(row.sha256), "candidate payload row is invalid: " + row.path);
        var lower = row.path.toLowerCase();
        expect(lowerPaths.indexOf(lower) < 0, "candidate payload path is duplicated or case-colliding: " + row.path);
        lowerPaths.push(lower);
        return row.path + "\t" + row.bytes + "\t" + row.sha256;
    }).join("\n") + "\n";
    return sha256(Buffer.from(canonical, "utf8"));
}

function validateCandidateManifestBytes(manifestBytes, candidate, candidateRoot) {
    expect(manifestBytes.length === candidate.manifestBytes, "candidate runtime manifest byte count mismatch");
    expect(sha256(manifestBytes) === candidate.manifestSha256, "candidate runtime manifest SHA mismatch");
    var manifestText = manifestBytes.toString("utf8").replace(/\r\n/g, "\n");
    var lines = manifestText.split("\n");
    expect(lines.pop() === "", "candidate runtime manifest must end with one newline");
    expect(lines[0] === "cf7-runtime-manifest-v2", "candidate runtime manifest header must be v2");
    var fields = {};
    var files = [];
    var allowedFields = ["artifactSourceHash", "buildIdentityHash", "payloadClosureHash", "producerRecipeHash", "publishMode", "toolchainBaseline", "toolchainLockHash"];
    lines.slice(1).forEach(function (line, index) {
        var columns = line.split("\t");
        if (columns[0] === "file") {
            expect(columns.length === 4 && /^[0-9]+$/.test(columns[2]) && /^[A-F0-9]{64}$/.test(columns[3]), "invalid candidate manifest file row at line " + (index + 2));
            files.push({ bytes: Number(columns[2]), path: columns[1], sha256: columns[3] });
        } else {
            expect(columns.length === 2 && allowedFields.indexOf(columns[0]) >= 0 && columns[1], "invalid or extra candidate manifest field at line " + (index + 2));
            expect(!Object.prototype.hasOwnProperty.call(fields, columns[0]), "duplicate candidate manifest field: " + columns[0]);
            fields[columns[0]] = columns[1];
        }
    });
    expect(JSON.stringify(Object.keys(fields).sort()) === JSON.stringify(allowedFields.slice().sort()), "candidate runtime manifest metadata set is incomplete");
    ["artifactSourceHash", "buildIdentityHash", "payloadClosureHash", "producerRecipeHash", "toolchainLockHash"].forEach(function (key) { expect(/^[A-F0-9]{64}$/.test(fields[key]), "candidate runtime manifest hash field invalid: " + key); });
    expect(fields.publishMode === "framework-dependent" && fields.toolchainBaseline.length > 0, "candidate runtime manifest publish/toolchain metadata invalid");
    expect(runtimeBuildIdentityHash(fields.artifactSourceHash, fields.producerRecipeHash, fields.toolchainLockHash) === fields.buildIdentityHash, "candidate runtime manifest build identity is not recomputable");
    expect(runtimePayloadClosureHash(files) === fields.payloadClosureHash, "candidate runtime manifest payload closure is not recomputable");
    expect(fields.buildIdentityHash === candidate.buildIdentity, "candidate manifest build identity mismatch");
    expect(fields.payloadClosureHash === candidate.payloadClosure, "candidate manifest payload closure mismatch");
    var filePaths = files.map(function (entry) { return entry.path; });
    expect(JSON.stringify(filePaths) === JSON.stringify(filePaths.slice().sort()), "candidate runtime manifest file rows are not in canonical order");
    var expectedFiles = {
        "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll": { bytes: candidate.coreBytes, sha256: candidate.coreSha256 },
        "runtime/miniaudio.dll": { bytes: candidate.miniaudioBytes, sha256: candidate.miniaudioSha256 }
    };
    Object.keys(expectedFiles).forEach(function (relativePath) {
        var row = files.filter(function (entry) { return entry.path === relativePath; })[0];
        expect(row, "candidate manifest is missing file row: " + relativePath);
        expect(row.bytes === expectedFiles[relativePath].bytes && row.sha256 === expectedFiles[relativePath].sha256, "candidate manifest file row mismatch: " + relativePath);
    });
    if (candidateRoot) {
        var excludedPaths = ["runtime/cf7-runtime-manifest.tsv", "runtime/runtime-build-attestation.json", "runtime/runtime-release-consensus.json"];
        var actualPaths = ["CRAZYFLASHER7MercenaryEmpire.exe"];
        var runtimeRoot = path.join(candidateRoot, "runtime");
        function walk(directory, relativeBase) {
            fs.readdirSync(directory, { withFileTypes: true }).forEach(function (entry) {
                var relative = relativeBase ? relativeBase + "/" + entry.name : "runtime/" + entry.name;
                var full = path.join(directory, entry.name);
                var stat = fs.lstatSync(full);
                expect(!entry.isSymbolicLink() && !stat.isSymbolicLink(), "candidate payload contains a link/reparse entry: " + relative);
                if (entry.isDirectory() && stat.isDirectory()) {
                    walk(full, relative);
                } else {
                    expect(entry.isFile() && stat.isFile(), "candidate payload contains a non-regular entry: " + relative);
                    if (excludedPaths.indexOf(relative) < 0 && relative.indexOf("runtime/attestations/") !== 0) actualPaths.push(relative);
                }
            });
        }
        walk(runtimeRoot, "");
        var actualFiles = actualPaths.sort().map(function (relativePath) {
            var bytes = readCandidateFile(candidateRoot, relativePath, "candidate payload " + relativePath);
            return { bytes: bytes.length, path: relativePath, sha256: sha256(bytes) };
        });
        expect(JSON.stringify(actualFiles) === JSON.stringify(files), "candidate runtime manifest differs from the exact full candidate payload file set");
    }
    return { fields: fields, files: files };
}

function verifyCandidate(candidate, candidateRoot) {
    expectString(candidateRoot, "live candidate root");
    expect(path.isAbsolute(candidateRoot), "live candidate root must be absolute");
    expect(fs.existsSync(candidateRoot), "live candidate root does not exist");
    var rootStat = fs.lstatSync(candidateRoot);
    expect(rootStat.isDirectory() && !rootStat.isSymbolicLink(), "A6 candidate root must be a real directory, not a link/reparse alias");
    var realRoot = fs.realpathSync.native(candidateRoot);
    expect(sameFilesystemPath(candidateRoot, realRoot), "live candidate root must use its canonical real path");

    var manifestBytes = readCandidateFile(realRoot, "runtime/cf7-runtime-manifest.tsv", "candidate runtime manifest");
    var coreBytes = readCandidateFile(realRoot, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", "candidate Core DLL");
    var miniaudioBytes = readCandidateFile(realRoot, "runtime/miniaudio.dll", "candidate miniaudio DLL");
    expect(coreBytes.length === candidate.coreBytes && sha256(coreBytes) === candidate.coreSha256, "candidate Core DLL SHA/bytes mismatch");
    expect(miniaudioBytes.length === candidate.miniaudioBytes && sha256(miniaudioBytes) === candidate.miniaudioSha256, "candidate miniaudio DLL SHA/bytes mismatch");
    var parsedManifest = validateCandidateManifestBytes(manifestBytes, candidate, realRoot);
    return { coreSha256: candidate.coreSha256, manifestSha256: candidate.manifestSha256, miniaudioSha256: candidate.miniaudioSha256, payloadFileCount: parsedManifest.files.length, root: realRoot };
}

function validateReportConfiguration(configuration, reportId, producerPath) {
    exactKeys(configuration, ["argv", "environment", "reportId", "schema", "workingDirectory"], "automated report configuration " + reportId);
    expect(configuration.schema === "cf7.audio-v2.automated-report-configuration.v1", "unexpected report configuration schema: " + reportId);
    expect(configuration.reportId === reportId, "report configuration ID mismatch: " + reportId);
    expect(configuration.workingDirectory === "release_source_root", "report configuration working directory must be release_source_root: " + reportId);
    expect(Array.isArray(configuration.argv) && configuration.argv.length > 0, "report configuration argv missing: " + reportId);
    configuration.argv.forEach(function (arg) { expectString(arg, "report configuration argv"); });
    expect(configuration.argv.indexOf(producerPath) >= 0, "report configuration argv must name the bound producer: " + reportId);
    expect(Array.isArray(configuration.environment), "report configuration environment must be an array: " + reportId);
    var environmentNames = [];
    configuration.environment.forEach(function (entry, index) {
        exactKeys(entry, ["name", "valueSha256"], "report environment " + reportId + "[" + index + "]");
        expectString(entry.name, "report environment name");
        expect(/^[A-F0-9]{64}$/.test(entry.valueSha256), "report environment value SHA invalid: " + reportId);
        expect(environmentNames.indexOf(entry.name) < 0, "duplicate report environment name: " + entry.name);
        environmentNames.push(entry.name);
    });
    expect(JSON.stringify(environmentNames) === JSON.stringify(environmentNames.slice().sort()), "report environment names must be sorted: " + reportId);
    return true;
}

function validateReportInputManifest(inputManifest, reportId, evidence, evidenceCommit, root) {
    exactKeys(inputManifest, ["candidateBuildIdentity", "candidatePayloadClosure", "closureSha256", "inputs", "releaseSource", "reportId", "schema"], "automated report input manifest " + reportId);
    expect(inputManifest.schema === "cf7.audio-v2.automated-report-input-manifest.v1", "unexpected report input manifest schema: " + reportId);
    expect(inputManifest.reportId === reportId, "report input manifest ID mismatch: " + reportId);
    expect(inputManifest.candidateBuildIdentity === evidence.candidate.buildIdentity && inputManifest.candidatePayloadClosure === evidence.candidate.payloadClosure, "report input manifest candidate mismatch: " + reportId);
    expect(JSON.stringify(inputManifest.releaseSource) === JSON.stringify(evidence.releaseSource), "report input manifest release source mismatch: " + reportId);
    var requiredRoles = REQUIRED_REPORT_INPUT_ROLES[reportId];
    expect(requiredRoles, "report input role policy missing: " + reportId);
    expect(Array.isArray(inputManifest.inputs) && inputManifest.inputs.length === requiredRoles.length, "report input manifest role count mismatch: " + reportId);
    var expectedCandidateArtifacts = {
        "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll": { bytes: evidence.candidate.coreBytes, role: "candidate_core", sha256: evidence.candidate.coreSha256 },
        "runtime/cf7-runtime-manifest.tsv": { bytes: evidence.candidate.manifestBytes, role: "candidate_runtime_manifest", sha256: evidence.candidate.manifestSha256 },
        "runtime/miniaudio.dll": { bytes: evidence.candidate.miniaudioBytes, role: "candidate_miniaudio", sha256: evidence.candidate.miniaudioSha256 }
    };
    var candidatePaths = [];
    var sourceCount = 0;
    var orderKeys = [];
    var roles = [];
    inputManifest.inputs.forEach(function (entry, index) {
        expect(entry && typeof entry === "object" && !Array.isArray(entry), "report input entry must be an object: " + reportId);
        expect(["candidate_artifact", "evidence_blob", "release_source_blob"].indexOf(entry.kind) >= 0, "report input kind invalid: " + reportId);
        expectString(entry.path, "report input path");
        expectString(entry.role, "report input role");
        expect(roles.indexOf(entry.role) < 0, "duplicate report input role: " + entry.role);
        roles.push(entry.role);
        expect(entry.path.indexOf("..") < 0 && !path.isAbsolute(entry.path), "report input path must be safe and relative: " + reportId);
        expect(Number.isInteger(entry.bytes) && entry.bytes > 0 && /^[A-F0-9]{64}$/.test(entry.sha256), "report input bytes/SHA invalid: " + reportId);
        var orderKey = entry.kind + ":" + entry.path;
        expect(orderKeys.indexOf(orderKey) < 0, "duplicate report input: " + orderKey);
        orderKeys.push(orderKey);
        if (entry.kind === "candidate_artifact") {
            exactKeys(entry, ["bytes", "kind", "path", "role", "sha256"], "candidate report input " + index);
            expect(expectedCandidateArtifacts[entry.path], "unexpected candidate artifact input: " + entry.path);
            expect(entry.role === expectedCandidateArtifacts[entry.path].role && entry.bytes === expectedCandidateArtifacts[entry.path].bytes && entry.sha256 === expectedCandidateArtifacts[entry.path].sha256, "candidate artifact input mismatch: " + entry.path);
            candidatePaths.push(entry.path);
        } else {
            exactKeys(entry, ["blobOid", "bytes", "kind", "path", "role", "sha256"], "tracked report input " + index);
            expect(entry.kind === "release_source_blob", "report-specific non-candidate inputs must be release-source blobs: " + entry.role);
            expect(/^[0-9a-f]{40,64}$/.test(entry.blobOid), "tracked report input blob invalid: " + entry.path);
            var bindingCommit = entry.kind === "release_source_blob" ? evidence.releaseSource.commit : evidenceCommit;
            if (entry.kind === "evidence_blob") expect(entry.path.indexOf("docs/evidence/audio-v2/") === 0, "evidence input must live under docs/evidence/audio-v2: " + entry.path);
            var tracked = gitObjectBinding(bindingCommit, entry.path, root);
            expect(tracked.blobOid === entry.blobOid && tracked.bytes.length === entry.bytes && tracked.sha256 === entry.sha256, "tracked report input mismatch: " + entry.path);
            if (entry.kind === "release_source_blob") sourceCount++;
        }
    });
    expect(JSON.stringify(orderKeys) === JSON.stringify(orderKeys.slice().sort()), "report inputs must be sorted by kind:path: " + reportId);
    expect(JSON.stringify(roles.slice().sort()) === JSON.stringify(requiredRoles.slice().sort()), "report input required role coverage mismatch: " + reportId);
    expect(JSON.stringify(candidatePaths.slice().sort()) === JSON.stringify(Object.keys(expectedCandidateArtifacts).sort()), "report input manifest must bind all three candidate artifacts: " + reportId);
    expect(sourceCount > 0, "report input manifest must bind at least one release-source blob: " + reportId);
    expect(inputManifest.closureSha256 === sha256(canonicalBytes(inputManifest.inputs)), "report input closure mismatch: " + reportId);
    return true;
}

function validateRunnerDependencyManifest(artifact, releaseCommit, producerBinding, root) {
    var manifestBinding = verifyTrackedArtifact(artifact, releaseCommit, root, "qualification runner dependency manifest");
    var dependencyManifest = parseJsonBuffer(manifestBinding.bytes, artifact.path);
    expect(manifestBinding.bytes.equals(canonicalBytes(dependencyManifest)), "qualification runner dependency manifest is not canonical JSON");
    exactKeys(dependencyManifest, ["closureSha256", "dependencies", "runnerPath", "schema"], "qualification runner dependency manifest");
    expect(dependencyManifest.schema === "cf7.audio-v2.qualification-runner-dependencies.v1", "unexpected qualification runner dependency schema");
    expect(dependencyManifest.runnerPath === QUALIFICATION_RUNNER_PATH, "qualification runner dependency manifest runner path drift");
    expect(Array.isArray(dependencyManifest.dependencies) && dependencyManifest.dependencies.length > 0, "qualification runner dependency manifest must not be empty");
    var paths = [];
    var bindings = {};
    dependencyManifest.dependencies.forEach(function (entry, index) {
        exactKeys(entry, ["blobOid", "bytes", "path", "sha256"], "qualification runner dependency " + index);
        expect(entry.path.indexOf("..") < 0 && !path.isAbsolute(entry.path) && /^(tools|launcher|automation|scripts)\//.test(entry.path), "qualification runner dependency path is unsafe: " + entry.path);
        expect(paths.indexOf(entry.path) < 0, "duplicate qualification runner dependency: " + entry.path);
        paths.push(entry.path);
        var binding = gitObjectBinding(releaseCommit, entry.path, root);
        expect(binding.blobOid === entry.blobOid && binding.bytes.length === entry.bytes && binding.sha256 === entry.sha256, "qualification runner dependency differs from release source S: " + entry.path);
        bindings[entry.path] = binding;
    });
    expect(JSON.stringify(paths) === JSON.stringify(paths.slice().sort()), "qualification runner dependencies must be path-sorted");
    expect(dependencyManifest.closureSha256 === sha256(canonicalBytes(dependencyManifest.dependencies)), "qualification runner dependency closure mismatch");
    expect(bindings[QUALIFICATION_RUNNER_PATH] && bindings[QUALIFICATION_RUNNER_PATH].blobOid === producerBinding.blobOid && bindings[QUALIFICATION_RUNNER_PATH].sha256 === producerBinding.sha256, "qualification runner itself is missing from its dependency closure");
    return { binding: manifestBinding, bindings: bindings, manifest: dependencyManifest };
}

function validateCaseEvidenceCommon(caseEvidence, report, caseResult, configurationBinding, inputManifest, evidence) {
    expect(caseEvidence.candidateBuildIdentity === evidence.candidate.buildIdentity && caseEvidence.candidatePayloadClosure === evidence.candidate.payloadClosure, "case evidence candidate mismatch: " + caseResult.caseId);
    expect(caseEvidence.reportId === report.reportId && caseEvidence.caseId === caseResult.caseId && caseEvidence.result === "passed", "case evidence report/case/result mismatch: " + caseResult.caseId);
    expect(JSON.stringify(caseEvidence.releaseSource) === JSON.stringify(evidence.releaseSource), "case evidence release source mismatch: " + caseResult.caseId);
    expect(caseEvidence.configurationSha256 === configurationBinding.sha256, "case evidence configuration SHA mismatch: " + caseResult.caseId);
    expect(caseEvidence.inputClosureSha256 === inputManifest.closureSha256, "case evidence input closure mismatch: " + caseResult.caseId);
    expect(caseEvidence.producerBlobOid === report.provenance.producerBlobOid && caseEvidence.producerSha256 === report.provenance.producerSha256, "case evidence producer mismatch: " + caseResult.caseId);
    expectRfc3339Utc(caseEvidence.generatedAtUtc, "case evidence generatedAtUtc");
}

function validateGenericCaseEvidence(caseEvidence, report, caseResult, configurationBinding, inputManifest, evidence) {
    exactKeys(caseEvidence, ["candidateBuildIdentity", "candidatePayloadClosure", "captureIds", "caseId", "checks", "configurationSha256", "generatedAtUtc", "inputClosureSha256", "producerBlobOid", "producerSha256", "releaseSource", "reportId", "result", "schema"], "automated case evidence " + caseResult.caseId);
    expect(caseEvidence.schema === "cf7.audio-v2.automated-case-evidence.v1", "unexpected automated case evidence schema: " + caseResult.caseId);
    validateCaseEvidenceCommon(caseEvidence, report, caseResult, configurationBinding, inputManifest, evidence);
    var requiredChecks = REQUIRED_CASE_CHECKS[report.reportId] && REQUIRED_CASE_CHECKS[report.reportId][caseResult.caseId];
    expect(requiredChecks, "required check policy missing for case: " + report.reportId + "/" + caseResult.caseId);
    expect(Array.isArray(caseEvidence.checks) && caseEvidence.checks.length === requiredChecks.length, "case evidence check count mismatch: " + caseResult.caseId);
    var requiredCaptureIds = (REQUIRED_CASE_CAPTURE_IDS[report.reportId] && REQUIRED_CASE_CAPTURE_IDS[report.reportId][caseResult.caseId]) || [];
    expect(Array.isArray(caseEvidence.captureIds) && JSON.stringify(caseEvidence.captureIds) === JSON.stringify(requiredCaptureIds), "case evidence capture binding mismatch: " + report.reportId + "/" + caseResult.caseId);
    var checkIds = [];
    caseEvidence.checks.forEach(function (check, index) {
        exactKeys(check, ["checkId", "measurement", "result"], "case check " + caseResult.caseId + "[" + index + "]");
        exactKeys(check.measurement, ["kind", "unit", "value"], "case measurement " + caseResult.caseId + "[" + index + "]");
        expectString(check.measurement.unit, "case measurement unit");
        if (check.measurement.kind === "boolean") {
            expect(check.measurement.value === true, "passed boolean measurement must be true: " + check.checkId);
        } else if (["counter", "duration_ms", "ratio"].indexOf(check.measurement.kind) >= 0) {
            expect(typeof check.measurement.value === "number" && Number.isFinite(check.measurement.value) && check.measurement.value >= 0, "numeric case measurement invalid: " + check.checkId);
            if (check.measurement.kind === "ratio") expect(check.measurement.value <= 1, "ratio case measurement exceeds one: " + check.checkId);
        } else if (check.measurement.kind === "digest") {
            expect(typeof check.measurement.value === "string" && /^[A-F0-9]{64}$/.test(check.measurement.value), "digest case measurement invalid: " + check.checkId);
        } else if (check.measurement.kind === "identity" || check.measurement.kind === "text") {
            expectString(check.measurement.value, "string case measurement");
        } else {
            fail("unknown case measurement kind: " + check.measurement.kind);
        }
        expect(check.result === "passed", "case check must pass: " + check.checkId);
        checkIds.push(check.checkId);
    });
    expect(JSON.stringify(checkIds) === JSON.stringify(requiredChecks), "case evidence required checks/order mismatch: " + caseResult.caseId);
    return true;
}

function validateEndpointCaptureConfiguration(configuration, capture, evidence, toolBinding) {
    exactKeys(configuration, ["candidateBuildIdentity", "candidatePayloadClosure", "captureBytes", "captureId", "captureSha256", "caseId", "channels", "deviceIdDigest", "durationSeconds", "format", "recordedAtUtc", "runId", "sampleRate", "schema", "selectedBackend", "tool"], "endpoint capture configuration " + capture.captureId);
    expect(configuration.schema === "cf7.audio-v2.endpoint-capture-configuration.v1", "unexpected endpoint capture configuration schema: " + capture.captureId);
    expect(configuration.candidateBuildIdentity === evidence.candidate.buildIdentity && configuration.candidatePayloadClosure === evidence.candidate.payloadClosure, "endpoint capture candidate mismatch: " + capture.captureId);
    expect(configuration.captureId === capture.captureId && configuration.caseId === capture.caseIds[0], "endpoint capture ID/case mismatch: " + capture.captureId);
    expect(configuration.captureBytes === capture.artifact.bytes && configuration.captureSha256 === capture.artifact.sha256, "endpoint capture bytes/SHA configuration mismatch: " + capture.captureId);
    expect(configuration.channels === capture.channels && configuration.sampleRate === capture.sampleRate && configuration.durationSeconds === capture.durationSeconds && configuration.format === capture.format, "endpoint capture media configuration mismatch: " + capture.captureId);
    expect(configuration.deviceIdDigest === evidence.device.deviceIdDigest && configuration.selectedBackend === evidence.device.selectedBackend, "endpoint capture device configuration mismatch: " + capture.captureId);
    expectRfc3339Utc(configuration.recordedAtUtc, "endpoint capture recordedAtUtc");
    expectString(configuration.runId, "endpoint capture runId");
    exactKeys(configuration.tool, ["blobOid", "path", "sha256"], "endpoint capture tool binding " + capture.captureId);
    expect(configuration.tool.path === ENDPOINT_CAPTURE_TOOL_PATH && configuration.tool.blobOid === toolBinding.blobOid && configuration.tool.sha256 === toolBinding.sha256, "endpoint capture tool configuration does not bind the S tool: " + capture.captureId);
    return true;
}

function releaseAudioInventoryPaths(releaseCommit, root) {
    var output = git(["ls-tree", "-r", "--name-only", releaseCommit, "--", "sounds", "music"], { root: root }).trim();
    if (!output) return [];
    return output.split(/\r?\n/).filter(function (rel) {
        return ASSET_INVENTORY_EXTENSIONS.indexOf(path.posix.extname(rel).toLowerCase()) >= 0;
    }).sort();
}

function sniffAudioContent(bytes) {
    if (bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WAVE") return { codec: "pcm_or_ieee_float", container: "riff_wave" };
    if (bytes.length >= 4 && bytes.toString("ascii", 0, 4) === "fLaC") return { codec: "flac", container: "flac" };
    if (bytes.length >= 12 && bytes.toString("ascii", 4, 8) === "ftyp") return { codec: "aac", container: "iso_bmff" };
    if (bytes.length >= 4 && bytes.toString("ascii", 0, 4) === "OggS") {
        var oggHeader = bytes.toString("latin1", 0, Math.min(bytes.length, 256));
        if (oggHeader.indexOf("OpusHead") >= 0) return { codec: "opus", container: "ogg" };
        if (oggHeader.indexOf("vorbis") >= 0) return { codec: "vorbis", container: "ogg" };
        return { codec: "unknown_ogg_codec", container: "ogg" };
    }
    if (bytes.length >= 3 && bytes.toString("ascii", 0, 3) === "ID3") return { codec: "mpeg_audio_layer_iii", container: "mpeg_audio" };
    if (bytes.length >= 2 && bytes[0] === 0xFF && (bytes[1] & 0xE0) === 0xE0) return { codec: "mpeg_audio_layer_iii", container: "mpeg_audio" };
    return { codec: "unknown", container: "unknown" };
}

function tryParsePcm16Wave(buffer, label) {
    try {
        return parseWavePcm(buffer, label);
    } catch (error) {
        if (/must be PCM s16le/.test(error.message)) return null;
        throw error;
    }
}

function validateAssetWaiverManifest(artifact, releaseCommit, root) {
    validateArtifactDescriptor(artifact, "asset qualification waiver artifact");
    expect(artifact.path === ASSET_WAIVER_PATH, "asset qualification waiver must use the fixed release-source path");
    expect(artifact.schema === "cf7.audio-v2.asset-qualification-waivers.v1", "asset qualification waiver artifact schema mismatch");
    var binding = verifyTrackedArtifact(artifact, releaseCommit, root, "asset qualification waiver registry");
    var manifest = parseJsonBuffer(binding.bytes, artifact.path);
    expect(binding.bytes.equals(canonicalBytes(manifest)), "asset qualification waiver registry is not canonical JSON");
    exactKeys(manifest, ["schema", "waivers"], "asset qualification waiver registry");
    expect(manifest.schema === "cf7.audio-v2.asset-qualification-waivers.v1", "unexpected asset qualification waiver schema");
    expect(Array.isArray(manifest.waivers), "asset qualification waivers must be an array");
    var ids = [];
    var paths = [];
    manifest.waivers.forEach(function (waiver, index) {
        exactKeys(waiver, ["exceptionId", "owner", "path", "reason", "signalClass"], "asset qualification waiver " + index);
        expectString(waiver.exceptionId, "asset waiver exceptionId");
        expectString(waiver.owner, "asset waiver owner");
        expectString(waiver.path, "asset waiver path");
        expectString(waiver.reason, "asset waiver reason");
        expect(["excluded_non_audio", "intentional_silence"].indexOf(waiver.signalClass) >= 0, "asset waiver signalClass invalid");
        expect(ids.indexOf(waiver.exceptionId) < 0 && paths.indexOf(waiver.path) < 0, "asset waivers must use unique exceptionId and path");
        ids.push(waiver.exceptionId);
        paths.push(waiver.path);
    });
    expect(JSON.stringify(paths) === JSON.stringify(paths.slice().sort()), "asset qualification waivers must be path-sorted");
    return manifest;
}

function validateAssetEofResults(assetResults, report, caseResult, configurationBinding, inputManifest, evidence, root) {
    exactKeys(assetResults, ["candidateBuildIdentity", "candidatePayloadClosure", "caseId", "configurationSha256", "entries", "generatedAtUtc", "inputClosureSha256", "inventoryExtensions", "inventoryRoots", "producerBlobOid", "producerSha256", "releaseSource", "reportId", "result", "schema", "summary", "waiverManifestArtifact"], "asset EOF results");
    expect(assetResults.schema === "cf7.audio-v2.asset-eof-results.v1", "unexpected asset EOF results schema");
    validateCaseEvidenceCommon(assetResults, report, caseResult, configurationBinding, inputManifest, evidence);
    expect(JSON.stringify(assetResults.inventoryRoots) === JSON.stringify(["sounds", "music"]), "asset EOF inventory roots drift");
    expect(JSON.stringify(assetResults.inventoryExtensions) === JSON.stringify(ASSET_INVENTORY_EXTENSIONS), "asset EOF inventory extensions drift");
    expect(Array.isArray(assetResults.entries) && assetResults.entries.length > 0, "asset EOF results must contain the shipped corpus");
    var waiverManifest = validateAssetWaiverManifest(assetResults.waiverManifestArtifact, evidence.releaseSource.commit, root);
    var waiverByPath = {};
    waiverManifest.waivers.forEach(function (waiver) { waiverByPath[waiver.path] = waiver; });
    var expectedPaths = releaseAudioInventoryPaths(evidence.releaseSource.commit, root);
    var actualPaths = [];
    var counts = { excludedNonAudio: 0, intentionalSilence: 0, nonzeroPcm: 0, ownedExceptions: 0, passed: 0, total: assetResults.entries.length };
    assetResults.entries.forEach(function (entry, index) {
        exactKeys(entry, ["blobOid", "bytes", "codec", "container", "decodeToEof", "decodedFrames", "exceptionId", "path", "qualificationResult", "sha256", "signalClass"], "asset EOF entry " + index);
        expectString(entry.codec, "asset EOF codec");
        expectString(entry.container, "asset EOF container");
        expect(Number.isInteger(entry.bytes) && entry.bytes > 0 && Number.isInteger(entry.decodedFrames) && entry.decodedFrames >= 0, "asset EOF bytes/frames invalid: " + entry.path);
        expect(/^[0-9a-f]{40,64}$/.test(entry.blobOid) && /^[A-F0-9]{64}$/.test(entry.sha256), "asset EOF blob/SHA invalid: " + entry.path);
        expect(actualPaths.indexOf(entry.path) < 0, "duplicate asset EOF path: " + entry.path);
        actualPaths.push(entry.path);
        var binding = gitObjectBinding(evidence.releaseSource.commit, entry.path, root);
        expect(binding.blobOid === entry.blobOid && binding.bytes.length === entry.bytes && binding.sha256 === entry.sha256, "asset EOF source binding mismatch: " + entry.path);
        var sniffed = sniffAudioContent(binding.bytes);
        expect(entry.container === sniffed.container && entry.codec === sniffed.codec, "asset EOF content-sniff classification mismatch: " + entry.path);
        var pcm = sniffed.container === "riff_wave" ? tryParsePcm16Wave(binding.bytes, "asset EOF " + entry.path) : null;
        if (entry.qualificationResult === "passed") {
            expect(sniffed.container !== "unknown" && sniffed.codec.indexOf("unknown") !== 0, "passed asset has unknown content: " + entry.path);
            expect(entry.exceptionId === null && entry.decodeToEof === true && entry.decodedFrames > 0 && entry.signalClass === "nonzero_pcm", "passed asset must decode to EOF with positive nonzero PCM: " + entry.path);
            if (pcm) {
                expect(entry.decodedFrames === pcm.frames, "asset EOF decoded frame count differs from PCM bytes: " + entry.path);
                expect(pcm.peakAbs >= 64 && pcm.nonZeroSampleRatio >= 0.001, "asset EOF PCM is silent but claims nonzero_pcm: " + entry.path);
            }
            expect(!waiverByPath[entry.path], "passed asset must not also carry a waiver: " + entry.path);
            counts.passed++;
            counts.nonzeroPcm++;
        } else {
            expect(entry.qualificationResult === "owned_exception" && typeof entry.exceptionId === "string" && entry.exceptionId.length > 0, "asset exception must be explicitly owned: " + entry.path);
            expect(entry.signalClass === "intentional_silence" || entry.signalClass === "excluded_non_audio", "owned asset exception signal class invalid: " + entry.path);
            var waiver = waiverByPath[entry.path];
            expect(waiver && waiver.exceptionId === entry.exceptionId && waiver.signalClass === entry.signalClass, "asset exception does not match the S-tracked waiver registry: " + entry.path);
            if (entry.signalClass === "excluded_non_audio") {
                expect(sniffed.container === "unknown" || sniffed.codec.indexOf("unknown") === 0, "excluded_non_audio exception contradicts content sniff: " + entry.path);
                expect(entry.decodeToEof === false && entry.decodedFrames === 0, "excluded_non_audio exception must not claim decoded frames: " + entry.path);
            } else {
                expect(sniffed.container !== "unknown" && sniffed.codec.indexOf("unknown") !== 0, "intentional_silence exception must be recognized audio: " + entry.path);
                expect(entry.decodeToEof === true && entry.decodedFrames > 0, "intentional_silence exception must decode to EOF: " + entry.path);
                if (pcm) {
                    expect(entry.decodedFrames === pcm.frames, "intentional_silence decoded frame count differs from PCM bytes: " + entry.path);
                    expect(pcm.peakAbs < 64 || pcm.nonZeroSampleRatio < 0.001, "intentional_silence waiver contradicts nonzero PCM: " + entry.path);
                }
            }
            counts.ownedExceptions++;
            if (entry.signalClass === "intentional_silence") counts.intentionalSilence++;
            if (entry.signalClass === "excluded_non_audio") counts.excludedNonAudio++;
        }
    });
    expect(JSON.stringify(actualPaths) === JSON.stringify(actualPaths.slice().sort()), "asset EOF entries must be path-sorted");
    expect(JSON.stringify(actualPaths) === JSON.stringify(expectedPaths), "asset EOF results do not exactly cover the release-source sounds/music corpus");
    exactKeys(assetResults.summary, ["excludedNonAudio", "intentionalSilence", "nonzeroPcm", "ownedExceptions", "passed", "total"], "asset EOF summary");
    expect(JSON.stringify(assetResults.summary) === JSON.stringify(counts), "asset EOF summary does not match entries");
    return true;
}

function caseEvidenceClosureDigest(report) {
    var closure = report.caseResults.map(function (entry) {
        return {
            blobOid: entry.evidenceArtifact.blobOid,
            bytes: entry.evidenceArtifact.bytes,
            caseId: entry.caseId,
            path: entry.evidenceArtifact.path,
            schema: entry.evidenceArtifact.schema,
            sha256: entry.evidenceArtifact.sha256
        };
    }).sort(function (left, right) { return left.caseId.localeCompare(right.caseId); });
    return sha256(canonicalBytes(closure));
}

function validateProducerVerification(verification, report, reportBinding, producerBinding, dependencyContext, configurationBinding, inputManifest, evidence) {
    exactKeys(verification, ["candidateBuildIdentity", "candidatePayloadClosure", "caseEvidenceClosureSha256", "caseResultsSha256", "configurationSha256", "inputClosureSha256", "producerBlobOid", "producerDependencyClosureSha256", "producerPath", "producerSha256", "releaseSource", "reportId", "reportSha256", "result", "schema"], "producer verification " + report.reportId);
    expect(verification.schema === "cf7.audio-v2.producer-verification.v1" && verification.result === "passed", "producer verification must be passed v1: " + report.reportId);
    expect(verification.reportId === report.reportId, "producer verification report ID mismatch: " + report.reportId);
    expect(JSON.stringify(verification.releaseSource) === JSON.stringify(evidence.releaseSource), "producer verification release source mismatch: " + report.reportId);
    expect(verification.candidateBuildIdentity === evidence.candidate.buildIdentity && verification.candidatePayloadClosure === evidence.candidate.payloadClosure, "producer verification candidate mismatch: " + report.reportId);
    expect(verification.producerPath === report.provenance.producerPath && verification.producerBlobOid === producerBinding.blobOid && verification.producerSha256 === producerBinding.sha256, "producer verification runner binding mismatch: " + report.reportId);
    expect(verification.producerDependencyClosureSha256 === dependencyContext.manifest.closureSha256, "producer verification dependency closure mismatch: " + report.reportId);
    expect(verification.configurationSha256 === configurationBinding.sha256, "producer verification configuration SHA mismatch: " + report.reportId);
    expect(verification.inputClosureSha256 === inputManifest.closureSha256, "producer verification input closure mismatch: " + report.reportId);
    expect(verification.reportSha256 === reportBinding.sha256, "producer verification report SHA mismatch: " + report.reportId);
    expect(verification.caseResultsSha256 === report.caseResultsSha256, "producer verification case-results closure mismatch: " + report.reportId);
    expect(verification.caseEvidenceClosureSha256 === caseEvidenceClosureDigest(report), "producer verification case-evidence closure mismatch: " + report.reportId);
    return true;
}

function replayProducerVerification(reportWrapper, report, reportBinding, producerBinding, dependencyContext, configuration, configurationBinding, inputManifest, inputBinding, evidence, evidenceCommit, root, liveCandidateRoot) {
    root = root || ROOT;
    var replayRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-replay-"));
    function materialize(rel, bytes) {
        expect(typeof rel === "string" && rel.length > 0 && !path.isAbsolute(rel) && rel.indexOf("..") < 0, "unsafe qualification replay path: " + rel);
        var destination = absolute(rel, replayRoot);
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.writeFileSync(destination, bytes);
    }
    Object.keys(dependencyContext.bindings).forEach(function (rel) { materialize(rel, dependencyContext.bindings[rel].bytes); });
    materialize(report.provenance.producerDependencyManifestArtifact.path, dependencyContext.binding.bytes);
    materialize(reportWrapper.artifact.path, reportBinding.bytes);
    materialize(report.provenance.configurationArtifact.path, configurationBinding.bytes);
    materialize(report.provenance.inputManifestArtifact.path, inputBinding.bytes);
    report.caseResults.forEach(function (entry) {
        var caseBinding = gitObjectBinding(evidenceCommit, entry.evidenceArtifact.path, root);
        materialize(entry.evidenceArtifact.path, caseBinding.bytes);
        var caseEvidence = parseJsonBuffer(caseBinding.bytes, "replay case evidence " + entry.caseId);
        if (caseEvidence.schema === "cf7.audio-v2.asset-eof-results.v1") {
            var waiverBinding = gitObjectBinding(evidence.releaseSource.commit, caseEvidence.waiverManifestArtifact.path, root);
            materialize(caseEvidence.waiverManifestArtifact.path, waiverBinding.bytes);
            caseEvidence.entries.forEach(function (asset) { materialize(asset.path, gitObjectBinding(evidence.releaseSource.commit, asset.path, root).bytes); });
        }
    });
    inputManifest.inputs.filter(function (entry) { return entry.kind === "release_source_blob"; }).forEach(function (entry) {
        materialize(entry.path, gitObjectBinding(evidence.releaseSource.commit, entry.path, root).bytes);
    });
    evidence.endpointCaptures.items.forEach(function (capture) {
        materialize(capture.artifact.path, gitObjectBinding(evidenceCommit, capture.artifact.path, root).bytes);
        materialize(capture.configurationArtifact.path, gitObjectBinding(evidenceCommit, capture.configurationArtifact.path, root).bytes);
        materialize(capture.toolArtifact.path, gitObjectBinding(evidence.releaseSource.commit, capture.toolArtifact.path, root).bytes);
    });
    var replayEnvironment = {};
    configuration.environment.forEach(function (entry) {
        var value = process.env[entry.name];
        expect(typeof value === "string", "qualification replay environment value is unavailable: " + entry.name);
        expect(sha256(Buffer.from(value, "utf8")) === entry.valueSha256, "qualification replay environment value drift: " + entry.name);
        replayEnvironment[entry.name] = value;
    });
    var producerFile = absolute(report.provenance.producerPath, replayRoot);
    var args = [
        producerFile,
        "--verify-audio-v2-report",
        "--report", absolute(reportWrapper.artifact.path, replayRoot),
        "--configuration", absolute(report.provenance.configurationArtifact.path, replayRoot),
        "--input-manifest", absolute(report.provenance.inputManifestArtifact.path, replayRoot),
        "--candidate-root", liveCandidateRoot
    ];
    var stdout;
    try {
        stdout = cp.execFileSync(process.execPath, args, {
            cwd: replayRoot,
            encoding: null,
            env: replayEnvironment,
            maxBuffer: 1048576,
            stdio: ["ignore", "pipe", "pipe"],
            timeout: PRODUCER_REPLAY_TIMEOUT_MILLISECONDS
        });
    } catch (error) {
        var stderr = error && error.stderr ? error.stderr.toString("utf8").trim() : "";
        fail("qualification runner replay failed for " + report.reportId + (stderr ? ": " + stderr : ""));
    } finally {
        fs.rmSync(replayRoot, { force: true, recursive: true });
    }
    var replayed = parseJsonBuffer(stdout, "qualification runner stdout " + report.reportId);
    expect(stdout.equals(canonicalBytes(replayed)), "qualification runner stdout must be one canonical JSON document: " + report.reportId);
    return { bytes: stdout, value: replayed };
}

function resolveCandidateVerification(evidence, evidenceCommit, changedPaths, root, liveCandidateRoot) {
    var descriptor = evidence.candidateVerification.artifact;
    expect(descriptor.path.indexOf("docs/evidence/audio-v2/candidate/") === 0 && descriptor.path.endsWith(".json"), "candidate verification must be tracked under docs/evidence/audio-v2/candidate");
    expect(changedPaths.indexOf(descriptor.path) >= 0, "E1 did not introduce/update candidate verification attestation");
    var binding = verifyTrackedArtifact(descriptor, evidenceCommit, root, "candidate verification attestation");
    var attestation = parseJsonBuffer(binding.bytes, descriptor.path);
    expect(binding.bytes.equals(canonicalBytes(attestation)), "candidate verification attestation is not canonical JSON");
    exactKeys(attestation, ["candidate", "fullPayload", "observedAtUtc", "observedRoot", "result", "runtimeManifestArtifact", "schema", "verifier"], "candidate verification attestation");
    expect(attestation.schema === "cf7.audio-v2.candidate-verification.v1" && attestation.result === "passed", "candidate verification attestation must be passed v1");
    expect(JSON.stringify(sortValue(attestation.candidate)) === JSON.stringify(sortValue(evidence.candidate)), "candidate verification attestation candidate mismatch");
    expectRfc3339Utc(attestation.observedAtUtc, "candidate verification observedAtUtc");
    expectString(attestation.observedRoot, "candidate verification observedRoot");
    validateArtifactDescriptor(attestation.runtimeManifestArtifact, "candidate runtime manifest snapshot");
    expect(attestation.runtimeManifestArtifact.schema === "cf7.runtime-manifest.v2.tsv", "candidate runtime manifest snapshot schema mismatch");
    expect(attestation.runtimeManifestArtifact.path.indexOf("docs/evidence/audio-v2/candidate/") === 0 && attestation.runtimeManifestArtifact.path.endsWith(".tsv"), "candidate runtime manifest snapshot path invalid");
    expect(changedPaths.indexOf(attestation.runtimeManifestArtifact.path) >= 0, "E1 did not introduce/update candidate runtime manifest snapshot");
    var manifestBinding = verifyTrackedArtifact(attestation.runtimeManifestArtifact, evidenceCommit, root, "candidate runtime manifest snapshot");
    var parsedSnapshot = validateCandidateManifestBytes(manifestBinding.bytes, evidence.candidate);
    var sourceDomains = runtimeSourceDomainHashes(evidence.releaseSource.commit, root);
    validateCandidateSourceDomains(parsedSnapshot, sourceDomains);
    exactKeys(attestation.fullPayload, ["buildIdentityRecomputed", "fileCount", "payloadClosureRecomputed", "runtimeInputsConfigBlobOid", "runtimeInputsConfigSha256", "sourceDomainsRecomputed", "verifier"], "candidate full-payload attestation");
    expect(attestation.fullPayload.buildIdentityRecomputed === true && attestation.fullPayload.payloadClosureRecomputed === true && attestation.fullPayload.sourceDomainsRecomputed === true, "candidate full-payload identity/closure/source-domain recomputation must pass");
    expect(attestation.fullPayload.runtimeInputsConfigBlobOid === sourceDomains.configBlobOid && attestation.fullPayload.runtimeInputsConfigSha256 === sourceDomains.configSha256, "candidate full-payload runtime input config binding mismatch");
    expect(attestation.fullPayload.verifier === "audio_v2_validator_mirror_cf7_runtime_v2_integrity", "candidate full-payload verifier mismatch");
    expect(attestation.fullPayload.fileCount === parsedSnapshot.files.length && attestation.fullPayload.fileCount >= 3, "candidate full-payload file count mismatch");
    exactKeys(attestation.verifier, ["blobOid", "path", "sha256"], "candidate verification verifier");
    expect(attestation.verifier.path === VALIDATOR_PATH, "candidate verification must bind the frozen validator");
    var verifierBinding = gitObjectBinding(evidence.releaseSource.commit, attestation.verifier.path, root);
    expect(verifierBinding.blobOid === attestation.verifier.blobOid && verifierBinding.sha256 === attestation.verifier.sha256, "candidate verification verifier binding mismatch");
    if (liveCandidateRoot) {
        expect(sameFilesystemPath(liveCandidateRoot, attestation.observedRoot), "live candidate root differs from E1 attestation observedRoot");
        var liveVerification = verifyCandidate(evidence.candidate, liveCandidateRoot);
        expect(liveVerification.payloadFileCount === attestation.fullPayload.fileCount, "live candidate payload file count differs from E1 attestation");
    }
    return { attestation: attestation, binding: binding, liveVerified: Boolean(liveCandidateRoot), runtimeManifestBinding: manifestBinding };
}

function resolveEvidence(commit, evidencePath, root, liveCandidateRoot) {
    expectString(evidencePath, "evidence manifest path");
    expect(evidencePath.indexOf("docs/evidence/audio-v2/") === 0 && evidencePath.endsWith(".json"), "A6 evidence manifest must be tracked under docs/evidence/audio-v2 as JSON");
    var fullCommit = git(["rev-parse", commit + "^{commit}"], { root: root }).trim();
    var tree = git(["rev-parse", fullCommit + "^{tree}"], { root: root }).trim();
    var binding = gitObjectBinding(fullCommit, evidencePath, root);
    var evidence = parseJsonBuffer(binding.bytes, fullCommit + ":" + evidencePath);
    expect(binding.bytes.equals(canonicalBytes(evidence)), "A6 evidence manifest is not canonical JSON");
    validateA6EvidenceManifest(evidence);
    var ancestry = gitParents(fullCommit, root);
    expect(ancestry.parents.length === 1 && ancestry.parents[0] === evidence.releaseSource.commit, "E1 must be a direct evidence-only child of release source S");
    var releaseTree = git(["rev-parse", evidence.releaseSource.commit + "^{tree}"], { root: root }).trim();
    expect(releaseTree === evidence.releaseSource.treeOid, "A6 evidence release source tree mismatch");
    var changedPaths = gitChangedPaths(fullCommit, root);
    changedPaths.forEach(function (rel) {
        expect(rel === ADR_PATH || rel.indexOf("docs/evidence/audio-v2/") === 0, "E1 contains non-evidence path: " + rel);
    });
    expect(changedPaths.indexOf(ADR_PATH) >= 0, "E1 must atomically update ADR recovery state");
    expect(changedPaths.indexOf(evidencePath) >= 0, "E1 did not introduce/update its evidence manifest");
    var e1Adr = gitObjectBinding(fullCommit, ADR_PATH, root).bytes.toString("utf8");
    validateTopRecoveryState(e1Adr, ADR_RECOVERY_STATES.e1, "E1 ADR");
    expect(e1Adr.indexOf("E1_EVIDENCE_READY") >= 0, "E1 ADR is missing the evidence-ready ledger marker");
    var candidateVerification = resolveCandidateVerification(evidence, fullCommit, changedPaths, root, liveCandidateRoot);
    var qualificationRunnerBinding = verifyTrackedArtifact(evidence.qualificationRunner.artifact, evidence.releaseSource.commit, root, "qualification runner trust root");
    expect(evidence.qualificationRunner.artifact.path === QUALIFICATION_RUNNER_PATH && evidence.qualificationRunner.artifact.schema === "application/javascript", "qualification runner trust root path/schema mismatch");

    var provenanceArtifactPaths = [];
    var caseEvidencePaths = [];
    var verificationArtifactPaths = [];
    evidence.automatedReports.forEach(function (report, index) {
        expect(report.artifact.path.endsWith(".json"), "automated report must be structured JSON: " + report.reportId);
        expect(changedPaths.indexOf(report.artifact.path) >= 0, "E1 did not introduce/update automated report: " + report.reportId);
        var reportBinding = verifyTrackedArtifact(report.artifact, fullCommit, root, "automated report " + report.reportId);
        var reportJson = parseJsonBuffer(reportBinding.bytes, report.artifact.path);
        expect(reportBinding.bytes.equals(canonicalBytes(reportJson)), "automated report is not canonical JSON: " + report.reportId);
        validateAutomatedReport(reportJson, report.reportId, evidence);
        var producerBinding = gitObjectBinding(evidence.releaseSource.commit, reportJson.provenance.producerPath, root);
        expect(producerBinding.blobOid === reportJson.provenance.producerBlobOid, "automated report producer blob mismatch: " + report.reportId);
        expect(producerBinding.sha256 === reportJson.provenance.producerSha256, "automated report producer SHA mismatch: " + report.reportId);
        expect(producerBinding.blobOid === qualificationRunnerBinding.blobOid && producerBinding.sha256 === qualificationRunnerBinding.sha256, "automated report does not use the H2-bound qualification runner trust root: " + report.reportId);
        var dependencyContext = validateRunnerDependencyManifest(reportJson.provenance.producerDependencyManifestArtifact, evidence.releaseSource.commit, producerBinding, root);
        [reportJson.provenance.configurationArtifact, reportJson.provenance.inputManifestArtifact].forEach(function (artifact) {
            expect(provenanceArtifactPaths.indexOf(artifact.path) < 0, "automated report provenance artifacts must use distinct paths: " + artifact.path);
            provenanceArtifactPaths.push(artifact.path);
            expect(changedPaths.indexOf(artifact.path) >= 0, "E1 did not introduce/update automated report provenance artifact: " + artifact.path);
        });
        var configurationBinding = verifyTrackedArtifact(reportJson.provenance.configurationArtifact, fullCommit, root, "automated report configuration " + report.reportId);
        var configuration = parseJsonBuffer(configurationBinding.bytes, reportJson.provenance.configurationArtifact.path);
        expect(configurationBinding.bytes.equals(canonicalBytes(configuration)), "automated report configuration is not canonical JSON: " + report.reportId);
        validateReportConfiguration(configuration, report.reportId, reportJson.provenance.producerPath);
        var inputBinding = verifyTrackedArtifact(reportJson.provenance.inputManifestArtifact, fullCommit, root, "automated report input manifest " + report.reportId);
        var inputManifest = parseJsonBuffer(inputBinding.bytes, reportJson.provenance.inputManifestArtifact.path);
        expect(inputBinding.bytes.equals(canonicalBytes(inputManifest)), "automated report input manifest is not canonical JSON: " + report.reportId);
        validateReportInputManifest(inputManifest, report.reportId, evidence, fullCommit, root);
        expect(reportJson.provenance.inputClosureSha256 === inputManifest.closureSha256, "automated report input closure binding mismatch: " + report.reportId);
        reportJson.caseResults.forEach(function (caseResult) {
            var artifact = caseResult.evidenceArtifact;
            expect(caseEvidencePaths.indexOf(artifact.path) < 0, "case evidence artifacts must use distinct paths: " + artifact.path);
            caseEvidencePaths.push(artifact.path);
            expect(artifact.path.indexOf("docs/evidence/audio-v2/cases/") === 0 && artifact.path.endsWith(".json"), "case evidence must be a tracked JSON under docs/evidence/audio-v2/cases");
            expect(changedPaths.indexOf(artifact.path) >= 0, "E1 did not introduce/update case evidence: " + report.reportId + "/" + caseResult.caseId);
            var caseBinding = verifyTrackedArtifact(artifact, fullCommit, root, "case evidence " + report.reportId + "/" + caseResult.caseId);
            var caseEvidence = parseJsonBuffer(caseBinding.bytes, artifact.path);
            expect(caseBinding.bytes.equals(canonicalBytes(caseEvidence)), "case evidence is not canonical JSON: " + artifact.path);
            if (report.reportId === "asset_offline_eof_qualification" && caseResult.caseId === "shipped_corpus_all_files") {
                validateAssetEofResults(caseEvidence, reportJson, caseResult, configurationBinding, inputManifest, evidence, root);
            } else {
                validateGenericCaseEvidence(caseEvidence, reportJson, caseResult, configurationBinding, inputManifest, evidence);
            }
        });
        expect(report.verificationArtifact.path.indexOf("docs/evidence/audio-v2/verifications/") === 0 && report.verificationArtifact.path.endsWith(".json"), "producer verification must be tracked under docs/evidence/audio-v2/verifications: " + report.reportId);
        expect(verificationArtifactPaths.indexOf(report.verificationArtifact.path) < 0, "producer verification paths must be distinct: " + report.verificationArtifact.path);
        verificationArtifactPaths.push(report.verificationArtifact.path);
        expect(changedPaths.indexOf(report.verificationArtifact.path) >= 0, "E1 did not introduce/update producer verification: " + report.reportId);
        var verificationBinding = verifyTrackedArtifact(report.verificationArtifact, fullCommit, root, "producer verification " + report.reportId);
        var verification = parseJsonBuffer(verificationBinding.bytes, report.verificationArtifact.path);
        expect(verificationBinding.bytes.equals(canonicalBytes(verification)), "producer verification is not canonical JSON: " + report.reportId);
        validateProducerVerification(verification, reportJson, reportBinding, producerBinding, dependencyContext, configurationBinding, inputManifest, evidence);
        if (liveCandidateRoot) {
            var replay = replayProducerVerification(report, reportJson, reportBinding, producerBinding, dependencyContext, configuration, configurationBinding, inputManifest, inputBinding, evidence, fullCommit, root, liveCandidateRoot);
            validateProducerVerification(replay.value, reportJson, reportBinding, producerBinding, dependencyContext, configurationBinding, inputManifest, evidence);
            expect(replay.bytes.equals(verificationBinding.bytes), "live qualification runner output differs from E1 producer verification: " + report.reportId);
        }
    });
    expect(changedPaths.indexOf(evidence.listeningMatrix.artifact.path) >= 0, "E1 did not introduce/update listening matrix");
    var listeningBinding = verifyTrackedArtifact(evidence.listeningMatrix.artifact, fullCommit, root, "listening matrix artifact");
    var listening = parseJsonBuffer(listeningBinding.bytes, evidence.listeningMatrix.artifact.path);
    expect(listeningBinding.bytes.equals(canonicalBytes(listening)), "listening matrix is not canonical JSON");
    validateListeningMatrix(listening, evidence.candidate.buildIdentity, evidence.candidate.payloadClosure);
    expect(listeningBinding.sha256 === evidence.listeningMatrix.sha256, "listening matrix SHA mismatch");
    evidence.endpointCaptures.items.forEach(function (capture) {
        expect(capture.artifact.path.indexOf("docs/evidence/audio-v2/captures/") === 0 && capture.artifact.path.toLowerCase().endsWith(".wav"), "endpoint capture must be a tracked WAV under docs/evidence/audio-v2/captures");
        expect(capture.artifact.schema === "audio/wav-pcm-s16le", "endpoint capture schema must be audio/wav-pcm-s16le");
        expect(changedPaths.indexOf(capture.artifact.path) >= 0, "E1 did not introduce/update endpoint capture: " + capture.captureId);
        var captureBinding = verifyTrackedArtifact(capture.artifact, fullCommit, root, "endpoint capture " + capture.captureId);
        expect(changedPaths.indexOf(capture.configurationArtifact.path) >= 0, "E1 did not introduce/update endpoint capture configuration: " + capture.captureId);
        var configurationBinding = verifyTrackedArtifact(capture.configurationArtifact, fullCommit, root, "endpoint capture configuration " + capture.captureId);
        var captureConfiguration = parseJsonBuffer(configurationBinding.bytes, capture.configurationArtifact.path);
        expect(configurationBinding.bytes.equals(canonicalBytes(captureConfiguration)), "endpoint capture configuration is not canonical JSON: " + capture.captureId);
        var toolBinding = verifyTrackedArtifact(capture.toolArtifact, evidence.releaseSource.commit, root, "endpoint capture tool " + capture.captureId);
        validateEndpointCaptureConfiguration(captureConfiguration, capture, evidence, toolBinding);
        var wave = parseWavePcm(captureBinding.bytes, "endpoint capture " + capture.captureId);
        expect(wave.channels === capture.channels && wave.sampleRate === capture.sampleRate, "endpoint capture WAV metadata mismatch: " + capture.captureId);
        expect(Math.abs(wave.durationSeconds - capture.durationSeconds) <= 0.001, "endpoint capture WAV duration mismatch: " + capture.captureId);
        expect(wave.peakAbs >= 64 && wave.nonZeroSampleRatio >= 0.001, "endpoint capture does not meet nonzero signal threshold: " + capture.captureId);
    });
    return { blobOid: binding.blobOid, candidateVerification: candidateVerification, commit: fullCommit, manifest: evidence, path: evidencePath, sha256: binding.sha256, tree: tree };
}

function validateH2Activation(evidenceContext, receiptPath, root) {
    receiptPath = receiptPath || H2_RECEIPT_PATH;
    var activationCommit = introductionCommit(receiptPath, "HEAD", root);
    expectDirectEvidenceCommit(activationCommit, evidenceContext.commit, [ADR_PATH, receiptPath], "H2 activation commit", root);
    var receiptAtActivation = gitObjectBinding(activationCommit, receiptPath, root);
    var receiptAtActivationValue = parseJsonBuffer(receiptAtActivation.bytes, activationCommit + ":" + receiptPath);
    expect(receiptAtActivation.bytes.equals(canonicalBytes(receiptAtActivationValue)), "H2 receipt at E2 is not canonical JSON");
    validateH2ReceiptBinding(receiptAtActivationValue, evidenceContext);
    var receiptAtHead = gitObjectBinding("HEAD", receiptPath, root);
    expect(receiptAtHead.blobOid === receiptAtActivation.blobOid && receiptAtHead.bytes.equals(receiptAtActivation.bytes), "H2 receipt changed after E2 in the current HEAD tree");
    if (fs.existsSync(absolute(receiptPath, root))) expect(fs.readFileSync(absolute(receiptPath, root)).equals(receiptAtActivation.bytes), "working H2 receipt differs from the immutable E2 receipt");
    var adrAtActivation = gitObjectBinding(activationCommit, ADR_PATH, root).bytes.toString("utf8");
    validateTopRecoveryState(adrAtActivation, ADR_RECOVERY_STATES.h2, "H2 activation ADR");
    [
        "| H2 | accepted |",
        "当前 H2 已有效"
    ].forEach(function (needle) { expect(adrAtActivation.indexOf(needle) >= 0, "H2 activation ADR is missing atomic recovery marker: " + needle); });
    return activationCommit;
}

function validateWorkspace(options) {
    TEMP_REVIEW_PATHS.forEach(function (rel) { expect(!fs.existsSync(absolute(rel)), "temporary review must be deleted: " + rel); });
    validateCanonicalCheckoutPolicy();
    var manifestFile = readJson(MANIFEST_PATH, { canonical: true });
    var manifest = validateManifest(manifestFile.value);
    validateSchemaSurfaces();
    var digest = sha256(manifestFile.buffer);
    var adrText = fs.readFileSync(absolute(ADR_PATH), "utf8");
    validateAdrDigest(adrText, digest);
    var proposal = null;
    var h1ActivationCommit = null;

    if (!options || !options.proposalCommit) {
        validateTopRecoveryState(adrText, ADR_RECOVERY_STATES.proposal, "proposal ADR");
        validateTopRecoveryState(fs.readFileSync(absolute(MEMO_PATH), "utf8"), MEMO_RECOVERY_STATES.proposal, "proposal memo");
    }

    if (options && options.proposalCommit) {
        proposal = resolveProposal(options.proposalCommit);
        validateFrozenWorkingBytes(proposal);
        var ancestor = cp.spawnSync("git", ["merge-base", "--is-ancestor", proposal.commit, "HEAD"], { cwd: ROOT });
        expect(ancestor.status === 0, "proposal commit is not an ancestor of HEAD");
        adrText = trackedHeadText(ADR_PATH, "current ADR");
        var committedMemoText = trackedHeadText(MEMO_PATH, "current memo");
        if (fs.existsSync(absolute(H1_RECEIPT_PATH))) {
            var receiptFile = readJson(H1_RECEIPT_PATH, { canonical: true });
            validateReceiptBinding(receiptFile.value, proposal);
            h1ActivationCommit = validateH1Activation(proposal, receiptFile);
            validateTopRecoveryState(committedMemoText, MEMO_RECOVERY_STATES.h1, "current memo after H1");
            if (!options.evidenceCommit) validateTopRecoveryState(adrText, ADR_RECOVERY_STATES.h1, "current ADR after H1");
        } else {
            expect(introductionCommits(H1_RECEIPT_PATH, "HEAD").length === 0, "H1 receipt was previously introduced but is now missing");
            validateTopRecoveryState(adrText, ADR_RECOVERY_STATES.proposal, "proposal ADR before H1");
            validateTopRecoveryState(committedMemoText, MEMO_RECOVERY_STATES.proposal, "proposal memo before H1");
        }
        if (options.printH1) process.stdout.write(formatH1Proposal(proposal) + "\n");
    }
    var evidenceContext = null;
    if (options && options.evidenceCommit) {
        expect(proposal, "evidence/H2 mode requires --proposal-commit");
        expect(fs.existsSync(absolute(H1_RECEIPT_PATH)) && h1ActivationCommit, "evidence/H2 mode requires a valid committed H1 receipt");
        expect(options.evidenceManifest, "--evidence-manifest is required with --evidence-commit");
        evidenceContext = resolveEvidence(options.evidenceCommit, options.evidenceManifest, null, options.candidateRoot);
        var hBeforeSource = cp.spawnSync("git", ["merge-base", "--is-ancestor", h1ActivationCommit, evidenceContext.manifest.releaseSource.commit], { cwd: ROOT });
        expect(hBeforeSource.status === 0, "H1 activation commit must be an ancestor of release source S");
        validateReleaseSourceFreeze(proposal, evidenceContext.manifest.releaseSource.commit);
        var h1ReceiptAtActivation = gitObjectBinding(h1ActivationCommit, H1_RECEIPT_PATH);
        var h1ReceiptAtSource = gitObjectBinding(evidenceContext.manifest.releaseSource.commit, H1_RECEIPT_PATH);
        expect(h1ReceiptAtSource.blobOid === h1ReceiptAtActivation.blobOid && h1ReceiptAtSource.bytes.equals(h1ReceiptAtActivation.bytes), "release source S changed or removed the accepted H1 receipt");
        var h1ReceiptAtEvidence = gitObjectBinding(evidenceContext.commit, H1_RECEIPT_PATH);
        expect(h1ReceiptAtEvidence.blobOid === h1ReceiptAtActivation.blobOid && h1ReceiptAtEvidence.bytes.equals(h1ReceiptAtActivation.bytes), "E1 changed or removed the accepted H1 receipt");
        if (options.printH2) {
            expect(options.candidateRoot && evidenceContext.candidateVerification.liveVerified, "--print-h2 requires --candidate-root and a fresh live candidate rehash");
            process.stdout.write(formatH2Proposal(evidenceContext) + "\n");
        }
        if (options.h2Receipt || fs.existsSync(absolute(H2_RECEIPT_PATH))) {
            expect(!options.h2Receipt || options.h2Receipt === H2_RECEIPT_PATH, "H2 receipt path is fixed to " + H2_RECEIPT_PATH);
            validateH2Activation(evidenceContext, options.h2Receipt || H2_RECEIPT_PATH);
            var currentAdrAfterH2 = trackedHeadText(ADR_PATH, "current ADR after H2");
            validateTopRecoveryState(currentAdrAfterH2, ADR_RECOVERY_STATES.h2, "current ADR after H2");
        } else {
            expect(introductionCommits(H2_RECEIPT_PATH, "HEAD").length === 0, "H2 receipt was previously introduced but is now missing");
            validateTopRecoveryState(adrText, ADR_RECOVERY_STATES.e1, "current ADR before H2");
        }
    }
    return { digest: digest, evidenceContext: evidenceContext, manifest: manifest };
}

function main() {
    var args = process.argv.slice(2);
    if (args.indexOf("--format-json") >= 0) {
        formatJsonFiles();
        console.log("audio-v2 canonical JSON formatting complete");
        return;
    }
    var proposalIndex = args.indexOf("--proposal-commit");
    var proposalCommit = proposalIndex >= 0 ? args[proposalIndex + 1] : null;
    expect(proposalIndex < 0 || proposalCommit, "--proposal-commit requires a git ref");
    var evidenceIndex = args.indexOf("--evidence-commit");
    var evidenceCommit = evidenceIndex >= 0 ? args[evidenceIndex + 1] : null;
    var evidenceManifestIndex = args.indexOf("--evidence-manifest");
    var evidenceManifest = evidenceManifestIndex >= 0 ? args[evidenceManifestIndex + 1] : null;
    var h2ReceiptIndex = args.indexOf("--h2-receipt");
    var h2Receipt = h2ReceiptIndex >= 0 ? args[h2ReceiptIndex + 1] : null;
    var candidateRootIndex = args.indexOf("--candidate-root");
    var candidateRoot = candidateRootIndex >= 0 ? args[candidateRootIndex + 1] : null;
    expect(evidenceIndex < 0 || evidenceCommit, "--evidence-commit requires a git ref");
    expect(evidenceManifestIndex < 0 || evidenceManifest, "--evidence-manifest requires a path");
    expect(h2ReceiptIndex < 0 || h2Receipt, "--h2-receipt requires a path");
    expect(candidateRootIndex < 0 || candidateRoot, "--candidate-root requires an absolute path");
    expect(args.indexOf("--print-h1") < 0 || proposalCommit, "--print-h1 requires --proposal-commit");
    expect(args.indexOf("--print-h2") < 0 || evidenceCommit, "--print-h2 requires --evidence-commit");
    expect(!h2Receipt || evidenceCommit, "--h2-receipt requires --evidence-commit");
    expect(!candidateRoot || evidenceCommit, "--candidate-root requires --evidence-commit");
    var result = validateWorkspace({
        evidenceCommit: evidenceCommit,
        evidenceManifest: evidenceManifest,
        candidateRoot: candidateRoot,
        h2Receipt: h2Receipt,
        printH1: args.indexOf("--print-h1") >= 0,
        printH2: args.indexOf("--print-h2") >= 0,
        proposalCommit: proposalCommit
    });
    console.log("audio-v2 contract validation passed; manifestSha256=" + result.digest + (proposalCommit ? "; proposal=" + proposalCommit : "; provenance=pending proposal commit") + (evidenceCommit ? "; evidence=" + evidenceCommit : ""));
}

if (require.main === module) {
    try {
        main();
    } catch (error) {
        console.error("audio-v2 contract validation failed: " + error.message);
        process.exit(1);
    }
}

module.exports = {
    ADR_PATH: ADR_PATH,
    EXPECTED_MANIFEST_SHA256: EXPECTED_MANIFEST_SHA256,
    FROZEN_CONTRACT_PATHS: FROZEN_CONTRACT_PATHS,
    MANIFEST_PATH: MANIFEST_PATH,
    REQUIRED_AUTOMATED_REPORT_CASES: REQUIRED_AUTOMATED_REPORT_CASES,
    REQUIRED_CASE_CAPTURE_IDS: REQUIRED_CASE_CAPTURE_IDS,
    REQUIRED_CASE_CHECKS: REQUIRED_CASE_CHECKS,
    REQUIRED_LISTENING_CAPTURE_IDS: REQUIRED_LISTENING_CAPTURE_IDS,
    REQUIRED_REPORT_INPUT_ROLES: REQUIRED_REPORT_INPUT_ROLES,
    canonicalBytes: canonicalBytes,
    endpointClosureDigest: endpointClosureDigest,
    formatH1Proposal: formatH1Proposal,
    formatH2Proposal: formatH2Proposal,
    gitObjectBinding: gitObjectBinding,
    parseJsonBuffer: parseJsonBuffer,
    parseWavePcm: parseWavePcm,
    resolveProposal: resolveProposal,
    resolveEvidence: resolveEvidence,
    runtimeBuildIdentityHash: runtimeBuildIdentityHash,
    runtimePayloadClosureHash: runtimePayloadClosureHash,
    runtimeSourceDomainHashes: runtimeSourceDomainHashes,
    sha256: sha256,
    sortValue: sortValue,
    validateManifest: validateManifest,
    validateA6EvidenceManifest: validateA6EvidenceManifest,
    validateAssetEofResults: validateAssetEofResults,
    validateAutomatedReport: validateAutomatedReport,
    validateArtifactDescriptor: validateArtifactDescriptor,
    validateCandidateManifestBytes: validateCandidateManifestBytes,
    validateCandidateSourceDomains: validateCandidateSourceDomains,
    validateEndpointCaptureConfiguration: validateEndpointCaptureConfiguration,
    validateH1Activation: validateH1Activation,
    validateH2Activation: validateH2Activation,
    validateH2ReceiptBinding: validateH2ReceiptBinding,
    validateListeningMatrix: validateListeningMatrix,
    validateReceiptBinding: validateReceiptBinding,
    validateReleaseSourceFreeze: validateReleaseSourceFreeze,
    validateReportInputManifest: validateReportInputManifest,
    validateTopRecoveryState: validateTopRecoveryState,
    verifyCandidate: verifyCandidate,
    validateWorkspace: validateWorkspace
};
