#!/usr/bin/env node
"use strict";

// Qualification-only Audio v2 observer client and journal collector.
//
// This tool never issues an audio command. begin_case/end_case only annotate the
// candidate-owned journal, snapshot only reads coordinator-owned observations,
// and collect-report derives endpoint facts from AS2-ingress journal events.

const cp = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const PROTOCOL = "cf7.audio-v2.qualification-pipe.v1";
const RESPONSE_SCHEMA = "cf7.audio-v2.qualification-response.v1";
const JOURNAL_CARRIER_SCHEMA = "cf7.audio-v2.candidate-journal-carrier.v1";
const CLIENT_PATH = "tools/audio-v2/qualification-observer-client.ps1";
const MAX_REQUEST_BYTES = 65536;
const MAX_RESPONSE_BYTES = 16 * 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 5000;
const ZERO_SHA256 = "0".repeat(64);

const ENDPOINT_REPORT_CASES = Object.freeze({
    exact_candidate_bgm_endpoint_e2e: Object.freeze([
        "bgm_playback", "bgm_seek", "bgm_crossfade", "format_vorbis",
        "format_aac_mp4", "format_opus"
    ]),
    exact_candidate_sfx_endpoint_e2e: Object.freeze([
        "sfx_playback", "dense_overlap_throttle", "bgm_sfx_mix",
        "gain_zero_and_default_max"
    ]),
    device_recovery_endpoint_e2e: Object.freeze([
        "default_device_switch", "physical_route_bluetooth_or_hdmi",
        "sleep_resume", "no_stale_sfx_after_recovery"
    ])
});

const ENDPOINT_CASES = Object.freeze(Object.values(ENDPOINT_REPORT_CASES).reduce(
    (result, entries) => result.concat(entries), []));
const ENDPOINT_CASE_SET = new Set(ENDPOINT_CASES);
const CASE_INGRESS_GRAMMAR = Object.freeze({
    bgm_playback: { bgm: ["play"], sfxBatches: 0 },
    bgm_seek: { bgm: ["seek"], sfxBatches: 0 },
    bgm_crossfade: { bgm: ["play"], sfxBatches: 0 },
    format_vorbis: { bgm: ["play"], sfxBatches: 0 },
    format_aac_mp4: { bgm: ["play"], sfxBatches: 0 },
    format_opus: { bgm: ["play"], sfxBatches: 0 },
    sfx_playback: { bgm: [], sfxBatches: 1 },
    dense_overlap_throttle: { bgm: [], sfxBatches: 1 },
    bgm_sfx_mix: { bgm: [], sfxBatches: 1 },
    gain_zero_and_default_max: { bgm: ["set_gain", "set_gain"], sfxBatches: 0 },
    default_device_switch: { bgm: [], sfxBatches: 0 },
    physical_route_bluetooth_or_hdmi: { bgm: [], sfxBatches: 0 },
    sleep_resume: { bgm: [], sfxBatches: 0 },
    no_stale_sfx_after_recovery: { bgm: [], sfxBatches: 1 }
});

const EVENT_KINDS = new Set([
    "case_begin", "case_end", "as2_bgm_request", "as2_bgm_result",
    "as2_sfx_batch", "coordinator_snapshot", "coordinator_recovery",
    "qualification_snapshot"
]);
const EVENT_SOURCES = new Set([
    "as2_ingress", "audio_coordinator", "qualification_observer"
]);
const RESULT_CATEGORIES = new Set([
    "ok", "missing", "unsupported_container", "unsupported_codec",
    "malformed", "truncated", "io_error", "abi_mismatch", "not_ready",
    "stale_generation", "unknown_id", "throttled", "start_failed",
    "seek_failed", "device_unavailable", "device_lost", "superseded",
    "internal_error"
]);
const COMPLETION_STATES = new Set([
    "accepted_deferred", "started", "stopped", "superseded", "failed"
]);
const RESULT_STAGES = new Set([
    "none", "validate_abi", "validate_capacity", "validate_session",
    "validate_path", "admission", "context_initialize", "device_initialize",
    "device_start", "decoder_initialize", "source_initialize", "native_start",
    "seek", "probe_input", "probe_decode", "shutdown"
]);
const DECODER_BACKENDS = new Set([
    "none", "builtin", "libvorbis", "media_foundation", "libopus"
]);
const OPERATIONS = new Set([
    "play", "stop", "pause", "resume", "seek", "set_loop", "set_gain"
]);
const RUNTIME_STATUSES = new Set([
    "initializing", "ready", "recovering", "unavailable", "shutdown"
]);
const BACKENDS = new Set([
    "none", "wasapi", "directsound", "winmm", "test_only_null"
]);
const SAMPLE_FORMATS = new Set(["unknown", "f32", "s16", "s24", "s32"]);
const CONTAINERS = new Set([
    "none", "riff_wave", "mpeg_audio", "native_flac", "ogg", "mpeg4", "adts"
]);
const CODECS = new Set([
    "none", "pcm_or_ieee_float", "mpeg_audio_layer_iii", "flac", "vorbis",
    "aac_lc_or_he_aac", "opus"
]);

class QualificationObserverError extends Error {
    constructor(code, message) {
        super(message);
        this.name = "QualificationObserverError";
        this.code = code;
    }
}

function fail(code, message) { throw new QualificationObserverError(code, message); }
function expect(condition, message, code) {
    if (!condition) fail(code || "VALIDATION_FAILED", message);
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
    return Buffer.from(JSON.stringify(sortedClone(value)), "utf8");
}

function sha256(bytes) {
    return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
}

function exactKeys(value, expected, label) {
    expect(value && typeof value === "object" && !Array.isArray(value), label + " must be an object");
    const actual = Object.keys(value).sort();
    const wanted = expected.slice().sort();
    expect(JSON.stringify(actual) === JSON.stringify(wanted), label + " keys mismatch");
}

function expectString(value, label, maximum) {
    expect(typeof value === "string" && value.length > 0 && value.length <= (maximum || 4096), label + " invalid");
}

function expectNullableString(value, label, maximum) {
    if (value !== null) expectString(value, label, maximum);
}

function expectUint(value, label, minimum) {
    expect(Number.isSafeInteger(value) && value >= (minimum || 0), label + " must be a safe unsigned integer");
}

function expectFinite(value, label, minimum, maximum) {
    expect(typeof value === "number" && Number.isFinite(value), label + " must be finite");
    if (minimum !== undefined) expect(value >= minimum, label + " is below the minimum");
    if (maximum !== undefined) expect(value <= maximum, label + " exceeds the maximum");
}

function expectSha(value, label) {
    expect(typeof value === "string" && /^[A-F0-9]{64}$/.test(value), label + " must be uppercase SHA-256");
}

function expectRunId(value, label) {
    expect(typeof value === "string" && /^[0-9a-f]{32}$/.test(value), label + " must be 32 lowercase hex");
}

function expectRfc3339Utc(value, label) {
    expect(typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$/.test(value), label + " must be RFC3339 UTC");
    expect(Number.isFinite(Date.parse(value)), label + " is not a real timestamp");
}

function expectWireDecimal(value, label) {
    expect(typeof value === "number" && Number.isFinite(value) && value >= 0 && value < 1e21 && !Object.is(value, -0), label + " must be a finite nonnegative non-exponent decimal");
    const fixed = value.toFixed(6).replace(/(?:\.0+|(?:(\.\d*?)0+))$/, "$1");
    expect(Number(fixed) === value, label + " must be quantized to 1e-6");
}

function validateMeter(value, label) {
    exactKeys(value, [
        "clipCount", "frameCount", "peakLeft", "peakRight", "rmsLeft",
        "rmsRight", "underrunCount"
    ], label);
    ["clipCount", "frameCount", "underrunCount"].forEach((key) => expectUint(value[key], label + "." + key));
    ["peakLeft", "peakRight", "rmsLeft", "rmsRight"].forEach((key) => expectWireDecimal(value[key], label + "." + key));
    return value;
}

function validateCounters(value, label) {
    const keys = [
        "playedCount", "preReadyDrops", "recoveryDrops", "staleGenerationDrops",
        "startFailureCount", "throttledCount", "unknownIdCount"
    ];
    exactKeys(value, keys, label);
    keys.forEach((key) => expectUint(value[key], label + "." + key));
    return value;
}

function validateRuntime(value, label) {
    exactKeys(value, [
        "audioReadyGeneration", "audioSessionId", "backend", "channels",
        "deviceGeneration", "deviceIdDigest", "deviceName", "sampleFormat",
        "sampleRate", "status"
    ], label);
    expectUint(value.audioReadyGeneration, label + ".audioReadyGeneration");
    expectString(value.audioSessionId, label + ".audioSessionId", 128);
    expect(BACKENDS.has(value.backend), label + ".backend invalid");
    expectUint(value.channels, label + ".channels");
    expectUint(value.deviceGeneration, label + ".deviceGeneration");
    expectSha(value.deviceIdDigest, label + ".deviceIdDigest");
    expectString(value.deviceName, label + ".deviceName", 1024);
    expect(SAMPLE_FORMATS.has(value.sampleFormat), label + ".sampleFormat invalid");
    expectUint(value.sampleRate, label + ".sampleRate");
    expect(RUNTIME_STATUSES.has(value.status), label + ".status invalid");
    return value;
}

function validateSource(value, label) {
    exactKeys(value, [
        "codec", "container", "cursorFrames", "decoderBackend", "lengthFrames",
        "playing", "requestId", "startCategory"
    ], label);
    expect(CODECS.has(value.codec), label + ".codec invalid");
    expect(CONTAINERS.has(value.container), label + ".container invalid");
    expectUint(value.cursorFrames, label + ".cursorFrames");
    expect(DECODER_BACKENDS.has(value.decoderBackend), label + ".decoderBackend invalid");
    expectUint(value.lengthFrames, label + ".lengthFrames");
    expect(typeof value.playing === "boolean", label + ".playing must be boolean");
    expectNullableString(value.requestId, label + ".requestId", 128);
    expect(RESULT_CATEGORIES.has(value.startCategory), label + ".startCategory invalid");
    return value;
}

function validateSnapshot(value, label) {
    exactKeys(value, ["bgmMeter", "counters", "runtime", "sfxMeter", "source"], label);
    validateMeter(value.bgmMeter, label + ".bgmMeter");
    validateCounters(value.counters, label + ".counters");
    validateRuntime(value.runtime, label + ".runtime");
    validateMeter(value.sfxMeter, label + ".sfxMeter");
    validateSource(value.source, label + ".source");
    return value;
}

function validateSession(value, label) {
    exactKeys(value, [
        "audioReadyGeneration", "audioSessionId", "deviceGeneration", "ready",
        "status"
    ], label);
    expectUint(value.audioReadyGeneration, label + ".audioReadyGeneration");
    expectString(value.audioSessionId, label + ".audioSessionId", 128);
    expectUint(value.deviceGeneration, label + ".deviceGeneration");
    expect(typeof value.ready === "boolean", label + ".ready must be boolean");
    expect(RUNTIME_STATUSES.has(value.status), label + ".status invalid");
    return value;
}

function validateBgmRequestPayload(value, label) {
    exactKeys(value, [
        "audioReadyGeneration", "audioSessionId", "fadeSeconds", "loop",
        "operation", "path", "requestId", "seekSeconds", "volume", "wireRevision"
    ], label);
    expectUint(value.audioReadyGeneration, label + ".audioReadyGeneration");
    expectString(value.audioSessionId, label + ".audioSessionId", 128);
    ["fadeSeconds", "seekSeconds", "volume"].forEach((key) => {
        if (value[key] !== null) expectWireDecimal(value[key], label + "." + key);
    });
    expect(value.loop === null || typeof value.loop === "boolean", label + ".loop invalid");
    expect(OPERATIONS.has(value.operation), label + ".operation invalid");
    expectNullableString(value.path, label + ".path", 32767);
    expectString(value.requestId, label + ".requestId", 128);
    expect(value.wireRevision === 2, label + ".wireRevision must be 2");
}

function validateBgmResultPayload(value, label) {
    exactKeys(value, [
        "audioReadyGeneration", "audioSessionId", "category", "completionState",
        "decoderBackend", "deviceGeneration", "hresult", "messageKey",
        "nativeCode", "operation", "requestId", "stage"
    ], label);
    expectUint(value.audioReadyGeneration, label + ".audioReadyGeneration");
    expectString(value.audioSessionId, label + ".audioSessionId", 128);
    expect(RESULT_CATEGORIES.has(value.category), label + ".category invalid");
    expect(COMPLETION_STATES.has(value.completionState), label + ".completionState invalid");
    expect(DECODER_BACKENDS.has(value.decoderBackend), label + ".decoderBackend invalid");
    expectUint(value.deviceGeneration, label + ".deviceGeneration");
    expect(Number.isSafeInteger(value.hresult), label + ".hresult invalid");
    expectString(value.messageKey, label + ".messageKey", 256);
    expect(Number.isSafeInteger(value.nativeCode), label + ".nativeCode invalid");
    expect(OPERATIONS.has(value.operation), label + ".operation invalid");
    expectString(value.requestId, label + ".requestId", 128);
    expect(RESULT_STAGES.has(value.stage), label + ".stage invalid");
}

function validateSfxBatchPayload(value, label) {
    exactKeys(value, [
        "audioReadyGeneration", "audioSessionId", "batchSequence", "linkageIds",
        "wireRevision"
    ], label);
    expectUint(value.audioReadyGeneration, label + ".audioReadyGeneration");
    expectString(value.audioSessionId, label + ".audioSessionId", 128);
    expectUint(value.batchSequence, label + ".batchSequence", 1);
    expect(Array.isArray(value.linkageIds) && value.linkageIds.length >= 1 && value.linkageIds.length <= 64, label + ".linkageIds invalid");
    value.linkageIds.forEach((entry, index) => expectString(entry, label + ".linkageIds[" + index + "]", 255));
    expect(value.wireRevision === 2, label + ".wireRevision must be 2");
}

function validateEvent(value, expectedRunId, label) {
    exactKeys(value, [
        "caseId", "kind", "monotonicTicks", "observedAtUtc", "payload",
        "previousSha256", "runId", "sequence", "sha256", "source"
    ], label);
    expect(ENDPOINT_CASE_SET.has(value.caseId), label + ".caseId invalid");
    expect(EVENT_KINDS.has(value.kind), label + ".kind invalid");
    expectUint(value.monotonicTicks, label + ".monotonicTicks", 1);
    expectRfc3339Utc(value.observedAtUtc, label + ".observedAtUtc");
    expectSha(value.previousSha256, label + ".previousSha256");
    expect(value.runId === expectedRunId, label + ".runId mismatch");
    expectUint(value.sequence, label + ".sequence", 1);
    expectSha(value.sha256, label + ".sha256");
    expect(EVENT_SOURCES.has(value.source), label + ".source invalid");

    if (value.kind === "case_begin" || value.kind === "case_end") {
        expect(value.source === "qualification_observer", label + " marker source mismatch");
        if (value.kind === "case_begin" && value.caseId === "physical_route_bluetooth_or_hdmi") {
            exactKeys(value.payload, ["routeKind"], label + ".payload");
            expect(["bluetooth", "hdmi"].includes(value.payload.routeKind), label + ".payload.routeKind invalid");
        } else exactKeys(value.payload, [], label + ".payload");
    } else if (value.kind === "as2_bgm_request") {
        expect(value.source === "as2_ingress", label + " BGM request did not enter through AS2");
        validateBgmRequestPayload(value.payload, label + ".payload");
    } else if (value.kind === "as2_bgm_result") {
        expect(value.source === "audio_coordinator", label + " BGM result was not emitted by the coordinator");
        validateBgmResultPayload(value.payload, label + ".payload");
    } else if (value.kind === "as2_sfx_batch") {
        expect(value.source === "as2_ingress", label + " SFX batch did not enter through AS2");
        validateSfxBatchPayload(value.payload, label + ".payload");
    } else {
        const expectedSource = value.kind === "qualification_snapshot"
            ? "qualification_observer" : "audio_coordinator";
        expect(value.source === expectedSource, label + " snapshot source mismatch");
        validateSnapshot(value.payload, label + ".payload");
    }

    const unhashed = Object.assign({}, value);
    delete unhashed.sha256;
    expect(sha256(canonicalBytes(unhashed)) === value.sha256, label + " event SHA-256 mismatch");
    return value;
}

function validateCandidate(value, expected, label) {
    exactKeys(value, [
        "buildIdentity", "executablePath", "executableSha256", "payloadClosure",
        "pid", "processStartUtc"
    ], label);
    expectSha(value.buildIdentity, label + ".buildIdentity");
    expect(path.isAbsolute(value.executablePath), label + ".executablePath must be absolute");
    expectSha(value.executableSha256, label + ".executableSha256");
    expectSha(value.payloadClosure, label + ".payloadClosure");
    expectUint(value.pid, label + ".pid", 1);
    expectRfc3339Utc(value.processStartUtc, label + ".processStartUtc");
    expect(value.buildIdentity === expected.buildIdentity, label + " build identity mismatch");
    expect(value.payloadClosure === expected.payloadClosure, label + " payload closure mismatch");
    expect(value.executableSha256 === expected.executableSha256, label + " executable SHA mismatch");
    expect(value.pid === expected.pid, label + " PID mismatch");
    expect(Date.parse(value.processStartUtc) === Date.parse(expected.processStartUtc), label + " process start mismatch");
    const normalize = (candidate) => path.resolve(candidate).replace(/[\\/]+/g, path.sep).toLowerCase();
    expect(normalize(value.executablePath) === normalize(expected.executablePath), label + " executable path mismatch");
    return value;
}

function responseKeys(command) {
    const common = [
        "candidate", "command", "protocol", "requestId", "result", "runId",
        "schema"
    ];
    if (command === "journal") return common.concat("journal");
    if (command === "snapshot") return common.concat(["event", "session", "snapshot"]);
    return common.concat("event");
}

function validateResponse(value, request, expectedCandidate) {
    exactKeys(value, responseKeys(request.command), "qualification response");
    expect(value.command === request.command, "qualification response command mismatch");
    expect(value.protocol === PROTOCOL, "qualification response protocol mismatch");
    expect(value.requestId === request.requestId, "qualification response requestId mismatch");
    expect(value.result === "ok", "qualification response result is not ok");
    expect(value.runId === request.runId, "qualification response runId mismatch");
    expect(value.schema === RESPONSE_SCHEMA, "qualification response schema mismatch");
    validateCandidate(value.candidate, expectedCandidate, "qualification response candidate");

    if (request.command === "snapshot") {
        validateEvent(value.event, request.runId, "qualification snapshot event");
        expect(value.event.kind === "qualification_snapshot", "snapshot response event kind mismatch");
        expect(value.event.caseId === request.caseId, "snapshot response case mismatch");
        validateSession(value.session, "qualification response session");
        validateSnapshot(value.snapshot, "qualification response snapshot");
        expect(JSON.stringify(value.event.payload) === JSON.stringify(value.snapshot), "snapshot response/event payload mismatch");
        const runtime = value.snapshot.runtime;
        expect(value.session.audioReadyGeneration === runtime.audioReadyGeneration &&
            value.session.audioSessionId === runtime.audioSessionId &&
            value.session.deviceGeneration === runtime.deviceGeneration &&
            value.session.status === runtime.status &&
            value.session.ready === (runtime.status === "ready"), "snapshot session/runtime tuple mismatch");
    } else if (request.command === "begin_case" || request.command === "end_case") {
        validateEvent(value.event, request.runId, "qualification marker event");
        expect(value.event.kind === (request.command === "begin_case" ? "case_begin" : "case_end"), "marker event kind mismatch");
        expect(value.event.caseId === request.caseId, "marker event case mismatch");
    } else {
        validateJournal(value.journal, request.runId);
    }
    return value;
}

function validateJournal(value, runId) {
    exactKeys(value, ["events", "firstSequence", "lastSequence", "sha256"], "qualification journal");
    expect(Array.isArray(value.events) && value.events.length > 0, "qualification journal events missing");
    expectUint(value.firstSequence, "qualification journal firstSequence", 1);
    expectUint(value.lastSequence, "qualification journal lastSequence", 1);
    expectSha(value.sha256, "qualification journal sha256");
    value.events.forEach((entry, index) => validateEvent(entry, runId, "qualification journal event " + index));
    expect(value.firstSequence === value.events[0].sequence && value.lastSequence === value.events[value.events.length - 1].sequence, "qualification journal sequence envelope mismatch");
    expect(value.firstSequence === 1 && value.lastSequence === value.events.length, "qualification journal is partial or has a sequence gap");
    value.events.forEach((entry, index) => {
        expect(entry.sequence === index + 1, "qualification journal sequence drift at event " + index);
        expect(entry.previousSha256 === (index === 0 ? ZERO_SHA256 : value.events[index - 1].sha256), "qualification journal hash-chain drift at event " + index);
        if (index > 0) {
            expect(entry.monotonicTicks > value.events[index - 1].monotonicTicks, "qualification journal monotonic order drift at event " + index);
            expect(Date.parse(entry.observedAtUtc) >= Date.parse(value.events[index - 1].observedAtUtc), "qualification journal UTC order drift at event " + index);
        }
    });
    expect(sha256(canonicalBytes(value.events)) === value.sha256, "qualification journal aggregate SHA-256 mismatch");
    return value;
}

function validateCompletedJournal(journal) {
    const ranges = {};
    const sessionIds = new Set();
    let expectedCaseIndex = 0;
    let active = null;
    journal.events.forEach((event) => {
        if (event.kind === "case_begin") {
            expect(active === null, "qualification journal contains nested cases");
            expect(expectedCaseIndex < ENDPOINT_CASES.length && event.caseId === ENDPOINT_CASES[expectedCaseIndex], "qualification case begin order drift");
            expect(!Object.prototype.hasOwnProperty.call(ranges, event.caseId), "qualification run repeats a case");
            active = { begin: event, events: [] };
            ranges[event.caseId] = active;
        } else if (event.kind === "case_end") {
            expect(active !== null && event.caseId === ENDPOINT_CASES[expectedCaseIndex], "qualification case end order drift");
            active.end = event;
            active = null;
            expectedCaseIndex++;
        } else {
            expect(active !== null, "qualification journal event exists outside a case marker interval");
            expect(event.caseId === ENDPOINT_CASES[expectedCaseIndex], "qualification journal event case differs from active marker");
            active.events.push(event);
            const sessionId = event.kind === "as2_bgm_request" || event.kind === "as2_bgm_result" || event.kind === "as2_sfx_batch"
                ? event.payload.audioSessionId
                : event.payload && event.payload.runtime && event.payload.runtime.audioSessionId;
            if (sessionId) sessionIds.add(sessionId);
        }
    });
    expect(active === null, "qualification journal ends with an open case");
    expect(expectedCaseIndex === ENDPOINT_CASES.length, "qualification journal does not contain exactly one completed 14-case run");
    ENDPOINT_CASES.forEach((caseId) => {
        const range = ranges[caseId];
        expect(range && range.begin && range.end && range.events.length > 0, "qualification case has no observer/audio events: " + caseId);
        expect(range.events.some((event) =>
            event.kind === "as2_bgm_request" || event.kind === "as2_bgm_result" || event.kind === "as2_sfx_batch" ||
            (event.payload && event.payload.runtime && event.payload.runtime.audioSessionId)),
        "qualification case has no audio-session telemetry: " + caseId);
    });
    expect(sessionIds.size === 1, "qualification journal spans more than one audio session");
    return ranges;
}

function validateJournalCarrier(value, expectedCandidate) {
    exactKeys(value, ["candidate", "journal", "observation", "schema"], "candidate journal carrier");
    expect(value.schema === JOURNAL_CARRIER_SCHEMA, "candidate journal carrier schema mismatch");
    expect(value.candidate && value.journal && value.observation, "candidate journal carrier is incomplete");
    validateCandidate(value.candidate, expectedCandidate || value.candidate, "candidate journal carrier candidate");
    const observation = value.observation;
    exactKeys(observation, [
        "candidateBuildIdentity", "candidatePayloadClosure", "caseFacts", "candidateProcess",
        "generatedAtUtc", "releaseSource", "reportId", "runId", "schema", "session"
    ], "candidate journal carrier observation");
    expect(observation.schema === "cf7.audio-v2.live-observation.v1", "candidate journal carrier observation schema mismatch");
    expect(ENDPOINT_REPORT_CASES[observation.reportId], "candidate journal carrier report is not an endpoint report");
    expectRunId(observation.runId, "candidate journal carrier runId");
    expectRfc3339Utc(observation.generatedAtUtc, "candidate journal carrier generatedAtUtc");
    exactKeys(observation.releaseSource, ["commit", "treeOid"], "candidate journal carrier release source");
    expect(/^[a-f0-9]{40,64}$/.test(observation.releaseSource.commit) && /^[a-f0-9]{40,64}$/.test(observation.releaseSource.treeOid), "candidate journal carrier release source invalid");
    const reportCases = ENDPOINT_REPORT_CASES[observation.reportId];
    expect(Array.isArray(observation.caseFacts) && observation.caseFacts.length === reportCases.length, "candidate journal carrier caseFacts count mismatch");
    observation.caseFacts.forEach((entry, index) => {
        exactKeys(entry, ["caseId", "facts"], "candidate journal carrier case " + index);
        expect(entry.caseId === reportCases[index] && entry.facts && typeof entry.facts === "object" && !Array.isArray(entry.facts), "candidate journal carrier case order/facts invalid");
    });
    exactKeys(observation.session, ["audioReadyGeneration", "audioSessionId", "backend", "channels", "deviceGeneration", "deviceIdDigest", "sampleFormat", "sampleRate"], "candidate journal carrier session");
    expectUint(observation.session.audioReadyGeneration, "candidate journal carrier session audioReadyGeneration", 1);
    expectUint(observation.session.deviceGeneration, "candidate journal carrier session deviceGeneration", 1);
    expectUint(observation.session.channels, "candidate journal carrier session channels", 1);
    expectUint(observation.session.sampleRate, "candidate journal carrier session sampleRate", 8000);
    expect(["wasapi", "directsound", "winmm"].includes(observation.session.backend) && observation.session.sampleFormat === "f32", "candidate journal carrier session is not a physical f32 runtime");
    expectSha(observation.session.deviceIdDigest, "candidate journal carrier session device digest");
    exactKeys(observation.candidateProcess, ["executableSha256", "observedAtUtc", "pid", "processStartUtc"], "candidate journal carrier process");
    expectRfc3339Utc(observation.candidateProcess.observedAtUtc, "candidate journal carrier process observedAtUtc");
    expectRfc3339Utc(observation.candidateProcess.processStartUtc, "candidate journal carrier process processStartUtc");
    expectSha(observation.candidateProcess.executableSha256, "candidate journal carrier process executable SHA");
    expectUint(observation.candidateProcess.pid, "candidate journal carrier process PID", 1);
    expect(observation.candidateBuildIdentity === value.candidate.buildIdentity &&
        observation.candidatePayloadClosure === value.candidate.payloadClosure &&
        observation.candidateProcess.executableSha256 === value.candidate.executableSha256 &&
        observation.candidateProcess.pid === value.candidate.pid &&
        Date.parse(observation.candidateProcess.processStartUtc) === Date.parse(value.candidate.processStartUtc),
    "candidate journal carrier observation/candidate identity mismatch");
    validateJournal(value.journal, observation.runId);
    const ranges = validateCompletedJournal(value.journal);
    ENDPOINT_CASES.forEach((caseId) => expectCaseIngressGrammar(caseId, ranges[caseId]));
    const lastCase = ranges[reportCases[reportCases.length - 1]];
    expect(observation.generatedAtUtc === lastCase.end.observedAtUtc &&
        observation.candidateProcess.observedAtUtc === observation.generatedAtUtc,
    "candidate journal carrier observation time is not journal-derived");
    return { candidate: value.candidate, journal: value.journal, observation, ranges };
}

function buildRequest(command, runId, caseId, requestId, routeKind) {
    expect(["snapshot", "journal", "begin_case", "end_case"].includes(command), "qualification command invalid");
    expectRunId(runId, "qualification request runId");
    expectRunId(requestId, "qualification request requestId");
    const value = { command, protocol: PROTOCOL, requestId, runId };
    if (command !== "journal") {
        expect(ENDPOINT_CASE_SET.has(caseId), "qualification request caseId invalid");
        value.caseId = caseId;
    }
    if (command === "begin_case" && caseId === "physical_route_bluetooth_or_hdmi") {
        expect(["bluetooth", "hdmi"].includes(routeKind), "physical route begin_case requires routeKind annotation");
        value.routeKind = routeKind;
    } else expect(routeKind === undefined || routeKind === null, "routeKind annotation is forbidden for this request");
    return value;
}

function requestPipe(options, command, caseId) {
    expect(options && typeof options === "object", "qualification pipe options missing");
    const expected = options.expectedCandidate;
    expect(expected && typeof expected === "object", "expected candidate binding missing");
    expectUint(expected.pid, "expected candidate PID", 1);
    expectRunId(options.runId, "qualification pipe runId");
    const requestId = options.requestId || crypto.randomBytes(16).toString("hex");
    const request = buildRequest(command, options.runId, caseId, requestId, options.routeKind);
    const requestBytes = canonicalBytes(request);
    expect(requestBytes.length <= MAX_REQUEST_BYTES, "qualification request exceeds 65536 bytes");
    const clientPath = path.resolve(options.clientPath);
    const powershell = path.resolve(options.powershell);
    expect(fs.lstatSync(clientPath).isFile(), "qualification observer client is missing");
    expect(fs.lstatSync(powershell).isFile(), "bound PowerShell executable is missing");
    const pipeName = "cf7-audio-v2-qualification-" + expected.pid + "-" + options.runId;
    const args = [
        "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", clientPath,
        "-PipeName", pipeName,
        "-ExpectedServerPid", String(expected.pid),
        "-RequestFromStdin",
        "-TimeoutMilliseconds", String(options.timeoutMs || DEFAULT_TIMEOUT_MS)
    ];
    const executed = (options.spawnSync || cp.spawnSync)(powershell, args, {
        encoding: null,
        env: options.env || {},
        input: requestBytes,
        maxBuffer: MAX_RESPONSE_BYTES + 65536,
        timeout: (options.timeoutMs || DEFAULT_TIMEOUT_MS) + 2000,
        windowsHide: true
    });
    if (executed.error || executed.status !== 0) {
        const detail = Buffer.isBuffer(executed.stderr) ? executed.stderr.toString("utf8") : String(executed.stderr || "");
        fail("PREREQUISITE_MISSING", "qualification pipe request failed: " + detail.replace(/[\r\n]+/g, " ").slice(0, 1000));
    }
    const stderr = Buffer.isBuffer(executed.stderr) ? executed.stderr : Buffer.from(executed.stderr || "", "utf8");
    expect(stderr.length === 0, "qualification pipe client produced unexpected stderr");
    const stdout = Buffer.isBuffer(executed.stdout) ? executed.stdout : Buffer.from(executed.stdout || "", "utf8");
    expect(stdout.length >= 2 && stdout.length <= MAX_RESPONSE_BYTES, "qualification pipe response is outside the byte bound");
    expect(!stdout.includes(0x0A) && !stdout.includes(0x0D), "qualification pipe stdout must be exactly one JSON record without framing bytes");
    let response;
    try { response = JSON.parse(stdout.toString("utf8")); }
    catch (error) { fail("VALIDATION_FAILED", "qualification pipe response is not strict UTF-8 JSON"); }
    const canonical = canonicalBytes(response);
    expect(canonical.equals(stdout), "qualification pipe response is not canonical JSON");
    return validateResponse(response, request, expected);
}

function queryCompletedJournal(options) {
    const response = requestPipe(options, "journal", null);
    return { candidate: response.candidate, journal: response.journal, ranges: validateCompletedJournal(response.journal) };
}

function eventSnapshots(range, minimum) {
    const events = range.events.filter((entry) => entry.kind === "qualification_snapshot");
    expect(events.length >= minimum, "qualification case has too few explicit snapshots: " + range.begin.caseId);
    return events;
}

function counterDelta(before, after, key, label) {
    expectUint(before[key], label + " before");
    expectUint(after[key], label + " after");
    expect(after[key] >= before[key], label + " counter regressed");
    return after[key] - before[key];
}

function peakAbsPcm16(meter) {
    const normalized = Math.max(Math.abs(meter.peakLeft), Math.abs(meter.peakRight));
    return Math.min(32767, Math.round(normalized * 32767));
}

function utcDeltaMs(before, after, label) {
    const result = Date.parse(after.observedAtUtc) - Date.parse(before.observedAtUtc);
    expect(Number.isSafeInteger(result) && result >= 0, label + " UTC duration invalid");
    return result;
}

function bgmPairs(range, operation, expectedCount) {
    const requests = range.events.filter((entry) => entry.kind === "as2_bgm_request" && entry.payload.operation === operation);
    expect(requests.length === expectedCount, range.begin.caseId + " AS2 " + operation + " request count mismatch");
    return requests.map((request) => {
        const results = range.events.filter((entry) => entry.kind === "as2_bgm_result" && entry.payload.requestId === request.payload.requestId);
        expect(results.length === 1, range.begin.caseId + " AS2 BGM result is missing or duplicated");
        const result = results[0];
        expect(result.sequence > request.sequence && result.payload.operation === request.payload.operation, range.begin.caseId + " AS2 BGM correlation/order mismatch");
        expect(result.payload.category === "ok", range.begin.caseId + " AS2 BGM result is not ok");
        return { request, result };
    });
}

function sfxRequests(range) {
    const events = range.events.filter((entry) => entry.kind === "as2_sfx_batch");
    expect(events.length > 0, range.begin.caseId + " has no AS2 SFX batch");
    for (let index = 1; index < events.length; index++) {
        expect(events[index].payload.batchSequence > events[index - 1].payload.batchSequence, range.begin.caseId + " SFX batchSequence did not increase");
    }
    return {
        events,
        requestedVoices: events.reduce((total, entry) => total + entry.payload.linkageIds.length, 0)
    };
}

function expectCaseIngressGrammar(caseId, range) {
    const grammar = CASE_INGRESS_GRAMMAR[caseId];
    expect(grammar, "qualification ingress grammar missing for " + caseId);
    const requests = range.events.filter((entry) => entry.kind === "as2_bgm_request");
    const results = range.events.filter((entry) => entry.kind === "as2_bgm_result");
    const sfx = range.events.filter((entry) => entry.kind === "as2_sfx_batch");
    expect(JSON.stringify(requests.map((entry) => entry.payload.operation)) === JSON.stringify(grammar.bgm), caseId + " BGM ingress operation/count grammar mismatch");
    expect(results.length === requests.length, caseId + " BGM result count grammar mismatch");
    const requestIds = new Set();
    requests.forEach((request) => {
        expect(request.source === "as2_ingress", caseId + " BGM request source grammar mismatch");
        expect(!requestIds.has(request.payload.requestId), caseId + " BGM requestId repeats");
        requestIds.add(request.payload.requestId);
        const matching = results.filter((result) => result.payload.requestId === request.payload.requestId);
        expect(matching.length === 1 && matching[0].source === "audio_coordinator" &&
            matching[0].payload.operation === request.payload.operation && matching[0].sequence > request.sequence,
        caseId + " BGM request/result grammar mismatch");
    });
    expect(sfx.length === grammar.sfxBatches, caseId + " SFX ingress count grammar mismatch");
    sfx.forEach((entry) => expect(entry.source === "as2_ingress", caseId + " SFX source grammar mismatch"));
}

function expectSameAudioSession(snapshots, label) {
    const sessionId = snapshots[0].payload.runtime.audioSessionId;
    snapshots.forEach((entry) => expect(entry.payload.runtime.audioSessionId === sessionId, label + " audio session changed"));
}

function expectReadyPhysicalRuntime(runtime, label) {
    expect(runtime.status === "ready", label + " runtime is not ready");
    expect(["wasapi", "directsound", "winmm"].includes(runtime.backend), label + " runtime backend is not physical");
    expect(runtime.sampleFormat === "f32" && runtime.sampleRate >= 8000 && runtime.channels >= 1, label + " runtime format is not ready f32");
    expectSha(runtime.deviceIdDigest, label + " runtime device digest");
}

function expectStableRuntimeTuple(snapshots, label) {
    expectSameAudioSession(snapshots, label);
    const runtime = snapshots[0].payload.runtime;
    expectReadyPhysicalRuntime(runtime, label);
    snapshots.forEach((entry) => {
        expectReadyPhysicalRuntime(entry.payload.runtime, label);
        expect(
            entry.payload.runtime.audioReadyGeneration === runtime.audioReadyGeneration &&
            entry.payload.runtime.deviceGeneration === runtime.deviceGeneration &&
            entry.payload.runtime.backend === runtime.backend &&
            entry.payload.runtime.deviceIdDigest === runtime.deviceIdDigest &&
            entry.payload.runtime.sampleFormat === runtime.sampleFormat &&
            entry.payload.runtime.sampleRate === runtime.sampleRate &&
            entry.payload.runtime.channels === runtime.channels,
        label + " ready/device generation or physical runtime tuple changed outside recovery");
    });
    return runtime;
}

function expectMeterWindow(beforeEvent, afterEvent, meterName, minimumFrames, label) {
    expect(afterEvent.sequence > beforeEvent.sequence, label + " snapshot window is out of order");
    const before = beforeEvent.payload[meterName];
    const after = afterEvent.payload[meterName];
    expect(after.frameCount - before.frameCount >= minimumFrames, label + " meter frame window did not advance");
    expect(peakAbsPcm16(after) >= 64, label + " meter window has no qualified signal");
}

function expectAnyBusMeterWindow(beforeEvent, afterEvent, minimumFrames, label) {
    expect(afterEvent.sequence > beforeEvent.sequence, label + " snapshot window is out of order");
    const advanced = ["bgmMeter", "sfxMeter"].some((meterName) =>
        afterEvent.payload[meterName].frameCount - beforeEvent.payload[meterName].frameCount >= minimumFrames);
    const signalled = ["bgmMeter", "sfxMeter"].some((meterName) => peakAbsPcm16(afterEvent.payload[meterName]) >= 64);
    expect(advanced && signalled, label + " endpoint meter window did not advance with signal");
}

function expectBgmTuple(pairs, runtime, label) {
    pairs.forEach((pair) => {
        expect(pair.request.payload.audioSessionId === runtime.audioSessionId &&
            pair.request.payload.audioReadyGeneration === runtime.audioReadyGeneration,
        label + " BGM request tuple differs from the case runtime");
        expect(pair.result.payload.audioSessionId === runtime.audioSessionId &&
            pair.result.payload.audioReadyGeneration === runtime.audioReadyGeneration &&
            pair.result.payload.deviceGeneration === runtime.deviceGeneration,
        label + " BGM result tuple differs from the case runtime");
    });
}

function expectSfxTuple(request, runtime, label) {
    request.events.forEach((entry) => expect(
        entry.payload.audioSessionId === runtime.audioSessionId &&
        entry.payload.audioReadyGeneration === runtime.audioReadyGeneration,
        label + " SFX batch tuple differs from the case runtime"));
}

function expectStartedBgmPair(pair, label, expectedStage) {
    expect(pair.result.payload.completionState === "started", label + " BGM result did not start playback");
    if (expectedStage) expect(pair.result.payload.stage === expectedStage, label + " BGM result stage mismatch");
}

function expectRecoveryBarrier(range, beforeEvent, afterEvent, label) {
    const recovering = range.events.find((entry) =>
        entry.kind === "coordinator_recovery" &&
        entry.sequence > beforeEvent.sequence &&
        entry.sequence < afterEvent.sequence &&
        entry.payload.runtime.status === "recovering");
    expect(recovering, label + " recovering owner snapshot is missing or out of order");
    const before = beforeEvent.payload.runtime;
    const during = recovering.payload.runtime;
    const after = afterEvent.payload.runtime;
    expect(before.status === "ready" && after.status === "ready", label + " explicit recovery boundaries are not ready");
    expect(during.audioSessionId === before.audioSessionId && after.audioSessionId === before.audioSessionId, label + " changed audio session during recovery");
    expect(during.audioReadyGeneration > before.audioReadyGeneration && after.audioReadyGeneration === during.audioReadyGeneration, label + " ready-generation barrier drifted");
    expect(after.deviceGeneration > before.deviceGeneration, label + " device generation did not advance");
    return recovering;
}

function snapshotAfter(range, sequence, label) {
    const candidates = range.events.filter((entry) => entry.kind === "qualification_snapshot" && entry.sequence > sequence);
    expect(candidates.length > 0, label + " has no following qualification snapshot");
    return candidates[0];
}

function snapshotBefore(range, sequence, label) {
    const candidates = range.events.filter((entry) => entry.kind === "qualification_snapshot" && entry.sequence < sequence);
    expect(candidates.length > 0, label + " has no preceding qualification snapshot");
    return candidates[candidates.length - 1];
}

function deriveCaseFacts(caseId, range, options) {
    expectCaseIngressGrammar(caseId, range);
    if (caseId === "bgm_playback") {
        const snapshots = eventSnapshots(range, 2);
        const runtime = expectStableRuntimeTuple(snapshots, caseId);
        const pair = bgmPairs(range, "play", 1)[0];
        expectBgmTuple([pair], runtime, caseId);
        expectStartedBgmPair(pair, caseId);
        expectMeterWindow(snapshots[0], snapshots[snapshots.length - 1], "bgmMeter", 1, caseId);
        const after = snapshots[snapshots.length - 1].payload;
        expect(after.source.requestId === pair.request.payload.requestId, "bgm_playback source requestId mismatch");
        expect(after.source.startCategory === pair.result.payload.category, "bgm_playback source/result category mismatch");
        expect(after.source.playing && after.source.cursorFrames > 0, "bgm_playback source did not advance");
        expect(peakAbsPcm16(after.bgmMeter) >= 64, "bgm_playback BGM meter has no qualified signal");
        return {
            captureId: "bgm_playback",
            cursorFrames: after.source.cursorFrames,
            playing: after.source.playing ? 1 : 0,
            requestId: pair.request.payload.requestId,
            startCategory: 0
        };
    }
    if (caseId === "bgm_seek") {
        const snapshots = eventSnapshots(range, 2);
        const runtime = expectStableRuntimeTuple(snapshots, caseId);
        const pair = bgmPairs(range, "seek", 1)[0];
        expectBgmTuple([pair], runtime, caseId);
        expectStartedBgmPair(pair, caseId, "seek");
        const beforeEvent = snapshotBefore(range, pair.request.sequence, "bgm_seek request");
        const afterEvent = snapshotAfter(range, pair.result.sequence, "bgm_seek result");
        const before = beforeEvent.payload;
        const after = afterEvent.payload;
        expectFinite(pair.request.payload.seekSeconds, "bgm_seek seekSeconds", 0);
        const targetFrames = Math.round(pair.request.payload.seekSeconds * after.runtime.sampleRate);
        const minimumBackwardFrames = after.runtime.sampleRate * 2;
        const elapsedMs = utcDeltaMs(pair.result, afterEvent, "bgm_seek result-to-snapshot");
        const upperBound = targetFrames + Math.ceil(elapsedMs * after.runtime.sampleRate / 1000) + Math.ceil(after.runtime.sampleRate / 4);
        expect(targetFrames > 0 && before.source.cursorFrames > targetFrames + minimumBackwardFrames, "bgm_seek request is not a clearly backward seek");
        expect(after.source.cursorFrames >= targetFrames && after.source.cursorFrames <= upperBound && after.source.cursorFrames < before.source.cursorFrames - minimumBackwardFrames, "bgm_seek cursor is outside the target/elapsed telemetry window");
        expectMeterWindow(beforeEvent, afterEvent, "bgmMeter", 1, caseId);
        return {
            captureId: "bgm_playback",
            cursorAfterFrames: after.source.cursorFrames,
            cursorBeforeFrames: before.source.cursorFrames,
            requestId: pair.request.payload.requestId,
            seekCategory: 0,
            targetFrames
        };
    }
    if (caseId === "bgm_crossfade") {
        const snapshots = eventSnapshots(range, 3);
        const runtime = expectStableRuntimeTuple(snapshots, caseId);
        const pair = bgmPairs(range, "play", 1)[0];
        expectBgmTuple([pair], runtime, caseId);
        expectStartedBgmPair(pair, caseId);
        expectFinite(pair.request.payload.fadeSeconds, "bgm_crossfade fadeSeconds", 0.001, 60);
        const before = snapshots[0].payload;
        const after = snapshots[snapshots.length - 1].payload;
        expect(before.source.playing && after.source.playing, "bgm_crossfade source was not playing at both boundaries");
        expect(before.source.requestId && after.source.requestId === pair.request.payload.requestId && before.source.requestId !== after.source.requestId, "bgm_crossfade did not replace the source through AS2");
        snapshots.forEach((entry) => expect(peakAbsPcm16(entry.payload.bgmMeter) >= 64, "bgm_crossfade sampled a silent endpoint window"));
        let maximumSpacing = 0;
        for (let index = 1; index < snapshots.length; index++) {
            maximumSpacing = Math.max(maximumSpacing, utcDeltaMs(snapshots[index - 1], snapshots[index], "bgm_crossfade sample gap"));
            expect(snapshots[index].payload.bgmMeter.frameCount > snapshots[index - 1].payload.bgmMeter.frameCount, "bgm_crossfade reused a cached meter snapshot");
        }
        const maximumAllowed = 500;
        expect(maximumSpacing <= maximumAllowed, "bgm_crossfade observation cadence cannot bound an audio gap");
        return {
            captureId: "bgm_playback",
            gapMs: maximumSpacing,
            maxGapMs: maximumAllowed,
            newSourceFrames: after.source.cursorFrames,
            oldSourceFrames: before.source.cursorFrames
        };
    }
    if (["format_vorbis", "format_aac_mp4", "format_opus"].includes(caseId)) {
        const snapshots = eventSnapshots(range, 2);
        const runtime = expectStableRuntimeTuple(snapshots, caseId);
        const pair = bgmPairs(range, "play", 1)[0];
        expectBgmTuple([pair], runtime, caseId);
        expectStartedBgmPair(pair, caseId);
        const before = snapshots[0].payload;
        const source = snapshots[snapshots.length - 1].payload.source;
        const post = snapshots[snapshots.length - 1].payload;
        const postEvent = snapshots[snapshots.length - 1];
        expect(pair.request.payload.fadeSeconds === null || pair.request.payload.fadeSeconds === 0, caseId + " format play must not rely on an old-source fade");
        expect(utcDeltaMs(pair.result, postEvent, caseId + " result-to-post window") >= 100, caseId + " post-result observation window is too short");
        expect(source.requestId === pair.request.payload.requestId && source.playing && source.cursorFrames > 0, caseId + " source did not advance");
        expectMeterWindow(snapshots[0], postEvent, "bgmMeter", Math.ceil(post.runtime.sampleRate * 0.05), caseId + " post-source");
        const expected = {
            format_vorbis: { codec: "vorbis", container: "ogg", decoderBackend: "libvorbis" },
            format_aac_mp4: { codec: "aac_lc_or_he_aac", container: "mpeg4", decoderBackend: "media_foundation" },
            format_opus: { codec: "opus", container: "ogg", decoderBackend: "libopus" }
        }[caseId];
        expect(source.codec === expected.codec && source.container === expected.container && source.decoderBackend === expected.decoderBackend, caseId + " decoder telemetry mismatch");
        return {
            captureId: "bgm_playback",
            codec: caseId === "format_aac_mp4" ? "aac" : source.codec,
            container: caseId === "format_aac_mp4" ? "iso_bmff" : source.container,
            decodedFrames: source.cursorFrames,
            decoderBackend: source.decoderBackend
        };
    }
    if (caseId === "sfx_playback") {
        const snapshots = eventSnapshots(range, 2);
        const runtime = expectStableRuntimeTuple(snapshots, caseId);
        const request = sfxRequests(range);
        expectSfxTuple(request, runtime, caseId);
        const before = snapshots[0].payload.counters;
        const after = snapshots[snapshots.length - 1].payload.counters;
        const played = counterDelta(before, after, "playedCount", caseId);
        expect(played === request.requestedVoices, "sfx_playback played counter differs from AS2 requests");
        expectMeterWindow(snapshots[0], snapshots[snapshots.length - 1], "sfxMeter", 1, caseId);
        return {
            captureId: "sfx_playback",
            playedAfter: after.playedCount,
            playedBefore: before.playedCount,
            requestedVoices: request.requestedVoices
        };
    }
    if (caseId === "dense_overlap_throttle") {
        const snapshots = eventSnapshots(range, 2);
        const runtime = expectStableRuntimeTuple(snapshots, caseId);
        const request = sfxRequests(range);
        expectSfxTuple(request, runtime, caseId);
        const before = snapshots[0].payload.counters;
        const after = snapshots[snapshots.length - 1].payload.counters;
        const played = counterDelta(before, after, "playedCount", caseId);
        const throttled = counterDelta(before, after, "throttledCount", caseId);
        expectUint(options.sfxVoiceLimit, "exact source SFX voice limit", 1);
        expect(request.requestedVoices > options.sfxVoiceLimit && played > 0 && played <= options.sfxVoiceLimit && throttled > 0 && played + throttled === request.requestedVoices, "dense SFX counter deltas do not close over the bounded AS2 batch");
        return {
            captureId: "sfx_playback",
            configuredVoiceLimit: options.sfxVoiceLimit,
            playedAfter: after.playedCount,
            playedBefore: before.playedCount,
            requestedVoices: request.requestedVoices,
            throttledAfter: after.throttledCount,
            throttledBefore: before.throttledCount
        };
    }
    if (caseId === "bgm_sfx_mix") {
        const snapshots = eventSnapshots(range, 2);
        const runtime = expectStableRuntimeTuple(snapshots, caseId);
        const request = sfxRequests(range);
        expectSfxTuple(request, runtime, caseId);
        const before = snapshots[0].payload;
        const after = snapshots[snapshots.length - 1].payload;
        const played = counterDelta(before.counters, after.counters, "playedCount", caseId);
        expect(played > 0 && played <= request.requestedVoices, "bgm_sfx_mix has no SFX contribution");
        expect(after.source.playing && after.source.cursorFrames > before.source.cursorFrames, "bgm_sfx_mix BGM cursor did not advance");
        expect(peakAbsPcm16(after.bgmMeter) >= 64 && peakAbsPcm16(after.sfxMeter) >= 64, "bgm_sfx_mix bus meters have no qualified signal");
        expect(after.bgmMeter.frameCount > before.bgmMeter.frameCount && after.sfxMeter.frameCount > before.sfxMeter.frameCount, "bgm_sfx_mix reused a cached meter snapshot");
        return {
            bgmFrames: after.source.cursorFrames - before.source.cursorFrames,
            captureId: "bgm_sfx_mix",
            sfxPlayedAfter: after.counters.playedCount,
            sfxPlayedBefore: before.counters.playedCount
        };
    }
    if (caseId === "gain_zero_and_default_max") {
        const snapshots = eventSnapshots(range, 3);
        const runtime = expectStableRuntimeTuple(snapshots, caseId);
        const pairs = bgmPairs(range, "set_gain", 2);
        expectBgmTuple(pairs, runtime, caseId);
        expect(pairs[0].request.payload.volume === 1 && pairs[1].request.payload.volume === 0, "gain case must enter default then zero through AS2");
        const defaultEvent = snapshotAfter(range, pairs[0].result.sequence, "default gain");
        const zeroEvent = snapshotAfter(range, pairs[1].result.sequence, "zero gain");
        expect(zeroEvent.sequence > defaultEvent.sequence, "gain snapshots are out of order");
        const defaultPeak = peakAbsPcm16(defaultEvent.payload.bgmMeter);
        const zeroPeak = peakAbsPcm16(zeroEvent.payload.bgmMeter);
        expect(defaultPeak >= 64 && zeroPeak <= 1, "gain endpoint meters do not show default signal and zero silence");
        expect(zeroEvent.payload.bgmMeter.frameCount > defaultEvent.payload.bgmMeter.frameCount, "zero gain observation has no frame window");
        return {
            captureId: "sfx_playback",
            defaultPeakAbs: defaultPeak,
            defaultRequestedGain: 1,
            zeroPeakAbs: zeroPeak,
            zeroRequestedGain: 0,
            zeroWindowFrames: zeroEvent.payload.bgmMeter.frameCount - defaultEvent.payload.bgmMeter.frameCount
        };
    }
    if (caseId === "default_device_switch") {
        const snapshots = eventSnapshots(range, 2);
        expectSameAudioSession(snapshots, caseId);
        const beforeEvent = snapshots[0];
        const afterEvent = snapshots[snapshots.length - 1];
        expectRecoveryBarrier(range, beforeEvent, afterEvent, caseId);
        const before = beforeEvent.payload.runtime;
        const after = afterEvent.payload.runtime;
        expect(after.deviceIdDigest !== before.deviceIdDigest, "default device switch did not change device digest");
        return {
            captureId: "device_recovery",
            deviceGenerationAfter: after.deviceGeneration,
            deviceGenerationBefore: before.deviceGeneration,
            newDeviceIdDigest: after.deviceIdDigest,
            oldDeviceIdDigest: before.deviceIdDigest
        };
    }
    if (caseId === "physical_route_bluetooth_or_hdmi") {
        const snapshots = eventSnapshots(range, 2);
        const runtimeTuple = expectStableRuntimeTuple(snapshots, caseId);
        const beforeEvent = snapshots[0];
        const afterEvent = snapshots[snapshots.length - 1];
        const before = beforeEvent.payload.runtime;
        const runtime = afterEvent.payload.runtime;
        const routeKind = range.begin.payload.routeKind;
        expect(["bluetooth", "hdmi"].includes(routeKind) && runtime.deviceIdDigest === before.deviceIdDigest && runtime.deviceIdDigest === runtimeTuple.deviceIdDigest, "physical route annotation/runtime tuple invalid");
        expectAnyBusMeterWindow(beforeEvent, afterEvent, 1, caseId);
        return { captureId: "device_recovery", deviceIdDigest: runtime.deviceIdDigest, routeKind };
    }
    if (caseId === "sleep_resume") {
        const snapshots = eventSnapshots(range, 2);
        expectSameAudioSession(snapshots, caseId);
        const before = snapshots[0].payload.runtime;
        const post = snapshots[snapshots.length - 1].payload.runtime;
        const recovering = range.events.find((entry) => entry.kind === "coordinator_recovery" && entry.payload.runtime.status === "recovering");
        const ready = range.events.find((entry) =>
            recovering && entry.sequence > recovering.sequence &&
            (entry.kind === "coordinator_snapshot" || entry.kind === "qualification_snapshot") &&
            entry.payload.runtime.status === "ready");
        expect(recovering && ready, "sleep_resume recovery transition missing or out of order");
        expectReadyPhysicalRuntime(before, caseId + " pre");
        expectReadyPhysicalRuntime(post, caseId + " post");
        expect(before.status === "ready" && post.status === "ready" && recovering.payload.runtime.audioSessionId === before.audioSessionId && ready.payload.runtime.audioSessionId === before.audioSessionId, "sleep_resume changed audio session during recovery");
        expect(recovering.payload.runtime.audioReadyGeneration > before.audioReadyGeneration && ready.payload.runtime.audioReadyGeneration === recovering.payload.runtime.audioReadyGeneration && post.audioReadyGeneration === ready.payload.runtime.audioReadyGeneration, "sleep_resume ready-generation barrier drifted");
        const recoveryMs = utcDeltaMs(recovering, ready, "sleep_resume recovery");
        const maximumAllowed = 15000;
        expect(recoveryMs <= maximumAllowed && ready.payload.runtime.deviceGeneration > before.deviceGeneration && post.deviceGeneration === ready.payload.runtime.deviceGeneration, "sleep_resume recovery is unbounded or did not advance device generation");
        expect(post.deviceIdDigest === before.deviceIdDigest && ready.payload.runtime.deviceIdDigest === before.deviceIdDigest, "sleep_resume changed the qualified endpoint digest");
        expectAnyBusMeterWindow(snapshots[0], snapshots[snapshots.length - 1], 1, caseId + " post-resume");
        return {
            captureId: "device_recovery",
            deviceGenerationAfter: ready.payload.runtime.deviceGeneration,
            deviceGenerationBefore: before.deviceGeneration,
            maxRecoveryMs: maximumAllowed,
            recoveryMs
        };
    }
    if (caseId === "no_stale_sfx_after_recovery") {
        const snapshots = eventSnapshots(range, 2);
        expectSameAudioSession(snapshots, caseId);
        const pre = snapshots[0].payload.runtime;
        const post = snapshots[snapshots.length - 1].payload.runtime;
        const request = sfxRequests(range);
        const beforeEvent = range.events.find((entry) => entry.kind === "coordinator_recovery" && entry.payload.runtime.status === "recovering");
        const afterEvent = range.events.find((entry) =>
            beforeEvent && entry.sequence > beforeEvent.sequence &&
            (entry.kind === "coordinator_snapshot" || entry.kind === "qualification_snapshot") &&
            entry.payload.runtime.status === "ready" && entry.sequence < snapshots[snapshots.length - 1].sequence);
        expect(beforeEvent && afterEvent, "stale SFX recovery boundary snapshots missing or out of order");
        expect(pre.status === "ready" && post.status === "ready" && beforeEvent.payload.runtime.audioSessionId === pre.audioSessionId && afterEvent.payload.runtime.audioSessionId === pre.audioSessionId, "stale SFX recovery changed audio session");
        expect(beforeEvent.payload.runtime.audioReadyGeneration > pre.audioReadyGeneration && afterEvent.payload.runtime.audioReadyGeneration === beforeEvent.payload.runtime.audioReadyGeneration && post.audioReadyGeneration === afterEvent.payload.runtime.audioReadyGeneration, "stale SFX ready-generation barrier drifted");
        expect(afterEvent.payload.runtime.deviceGeneration > pre.deviceGeneration && post.deviceGeneration === afterEvent.payload.runtime.deviceGeneration, "stale SFX device generation did not advance");
        request.events.forEach((entry) => expect(entry.payload.audioSessionId === pre.audioSessionId && entry.payload.audioReadyGeneration === pre.audioReadyGeneration, "stale SFX batch did not carry the pre-recovery tuple"));
        request.events.forEach((entry) => expect(entry.sequence > beforeEvent.sequence && entry.sequence < afterEvent.sequence, "stale SFX batch was not sent during recovery"));
        const before = beforeEvent.payload.counters;
        const readyCounters = afterEvent.payload.counters;
        const after = snapshots[snapshots.length - 1].payload.counters;
        expect(counterDelta(before, readyCounters, "recoveryDrops", caseId) === request.requestedVoices, "stale SFX recovery drop delta mismatch");
        Object.keys(readyCounters).forEach((key) => {
            if (key === "recoveryDrops") return;
            expect(readyCounters[key] === before[key], "stale SFX counters changed before ready: " + key);
        });
        Object.keys(after).forEach((key) => expect(after[key] === readyCounters[key], "stale SFX counters changed after ready: " + key));
        expectAnyBusMeterWindow(afterEvent, snapshots[snapshots.length - 1], 1, caseId + " post-ready");
        return {
            captureId: "device_recovery",
            playedAfter: after.playedCount,
            playedBefore: before.playedCount,
            recoveryDropsAfter: after.recoveryDrops,
            recoveryDropsBefore: before.recoveryDrops,
            staleBatchSize: request.requestedVoices
        };
    }
    fail("VALIDATION_FAILED", "endpoint case derivation is not implemented: " + caseId);
}

function runtimeSession(runtime) {
    expect(runtime.status === "ready", "endpoint capture runtime is not ready");
    expect(["wasapi", "directsound", "winmm"].includes(runtime.backend), "endpoint capture runtime backend is not physical");
    expect(runtime.sampleFormat === "f32", "endpoint runtime sampleFormat is not f32");
    expect(runtime.audioReadyGeneration >= 1 && runtime.deviceGeneration >= 1 && runtime.sampleRate >= 8000 && runtime.channels >= 1, "endpoint runtime tuple is not ready");
    expect(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(runtime.audioSessionId), "endpoint runtime audioSessionId is not UUIDv4");
    return {
        audioReadyGeneration: runtime.audioReadyGeneration,
        audioSessionId: runtime.audioSessionId,
        backend: runtime.backend,
        channels: runtime.channels,
        deviceGeneration: runtime.deviceGeneration,
        deviceIdDigest: runtime.deviceIdDigest,
        sampleFormat: runtime.sampleFormat,
        sampleRate: runtime.sampleRate
    };
}

function deriveLiveObservation(options, collected) {
    expect(options && typeof options === "object", "live observation derivation options missing");
    const cases = ENDPOINT_REPORT_CASES[options.reportId];
    expect(cases, "live observation report is not an endpoint report");
    expect(collected && collected.candidate && collected.journal && collected.ranges, "completed candidate journal missing");
    expectSha(options.candidateBuildIdentity, "live observation candidateBuildIdentity");
    expectSha(options.candidatePayloadClosure, "live observation candidatePayloadClosure");
    expect(collected.candidate.buildIdentity === options.candidateBuildIdentity && collected.candidate.payloadClosure === options.candidatePayloadClosure, "journal candidate differs from report candidate");
    exactKeys(options.releaseSource, ["commit", "treeOid"], "live observation releaseSource");
    expect(typeof options.releaseSource.commit === "string" && /^[a-f0-9]{40,64}$/.test(options.releaseSource.commit), "release source commit invalid");
    expect(typeof options.releaseSource.treeOid === "string" && /^[a-f0-9]{40,64}$/.test(options.releaseSource.treeOid), "release source tree invalid");

    const caseFacts = cases.map((caseId) => ({
        caseId,
        facts: deriveCaseFacts(caseId, collected.ranges[caseId], options)
    }));
    const captureCase = {
        exact_candidate_bgm_endpoint_e2e: "bgm_playback",
        exact_candidate_sfx_endpoint_e2e: "sfx_playback",
        device_recovery_endpoint_e2e: "default_device_switch"
    }[options.reportId];
    const captureSnapshots = eventSnapshots(collected.ranges[captureCase], 2);
    const captureRuntime = captureSnapshots[captureSnapshots.length - 1].payload.runtime;
    const lastCase = collected.ranges[cases[cases.length - 1]];
    const generatedAtUtc = lastCase.end.observedAtUtc;
    const observation = {
        candidateBuildIdentity: options.candidateBuildIdentity,
        candidatePayloadClosure: options.candidatePayloadClosure,
        candidateProcess: {
            executableSha256: collected.candidate.executableSha256,
            observedAtUtc: generatedAtUtc,
            pid: collected.candidate.pid,
            processStartUtc: collected.candidate.processStartUtc
        },
        caseFacts,
        generatedAtUtc,
        releaseSource: options.releaseSource,
        reportId: options.reportId,
        runId: collected.journal.events[0].runId,
        schema: "cf7.audio-v2.live-observation.v1",
        session: runtimeSession(captureRuntime)
    };
    const carrier = {
        candidate: collected.candidate,
        journal: collected.journal,
        observation,
        schema: JOURNAL_CARRIER_SCHEMA
    };
    return {
        carrier,
        captureRuntime,
        journalBinding: {
            firstSequence: collected.journal.firstSequence,
            lastSequence: collected.journal.lastSequence,
            sha256: collected.journal.sha256
        },
        observation,
        ranges: collected.ranges
    };
}

function trackedCanonicalBytes(value) {
    return Buffer.from(JSON.stringify(sortedClone(value), null, 2) + "\n", "utf8");
}

function trackedObservationArguments(observation) {
    const compressed = zlib.deflateRawSync(trackedCanonicalBytes(observation), { level: 9 }).toString("base64");
    const result = ["--bound-live-observation-deflate-base64-v1"];
    for (let offset = 0; offset < compressed.length; offset += 4000) result.push(compressed.slice(offset, offset + 4000));
    expect(result.length >= 2 && result.length <= 28, "candidate-derived observation does not fit the tracked configuration argv bound");
    return result;
}

function parseCli(argv) {
    if (argv.length === 1 && argv[0] === "--help") return { help: true };
    expect(argv.length > 0 && (argv[0] === "--pipe-command" || argv[0] === "--collect-report"), "first argument must be --pipe-command or --collect-report");
    const result = { mode: argv[0] === "--pipe-command" ? "pipe" : "collect" };
    let index = 1;
    if (result.mode === "pipe") {
        expect(index < argv.length, "--pipe-command requires a command");
        result.command = argv[index++];
    } else {
        expect(index < argv.length, "--collect-report requires a reportId");
        result.reportId = argv[index++];
    }
    const valueFlags = new Set([
        "--candidate-build-identity", "--candidate-payload-closure",
        "--candidate-pid", "--candidate-root", "--case-id", "--powershell",
        "--release-source-commit", "--release-source-tree", "--route-kind",
        "--run-id"
    ]);
    const values = {};
    while (index < argv.length) {
        const flag = argv[index++];
        if (flag === "--emit-configuration-argv") {
            expect(!result.emitConfigurationArgv, "duplicate --emit-configuration-argv");
            result.emitConfigurationArgv = true;
            continue;
        }
        expect(valueFlags.has(flag) && !Object.prototype.hasOwnProperty.call(values, flag), "unknown or duplicate observer flag " + flag);
        expect(index < argv.length, flag + " requires a value");
        values[flag] = argv[index++];
    }
    [
        "--candidate-build-identity", "--candidate-payload-closure",
        "--candidate-pid", "--candidate-root", "--powershell", "--run-id"
    ].forEach((flag) => expect(values[flag], "missing observer flag " + flag));
    result.candidateBuildIdentity = values["--candidate-build-identity"];
    result.candidatePayloadClosure = values["--candidate-payload-closure"];
    result.candidatePid = Number(values["--candidate-pid"]);
    result.candidateRoot = path.resolve(values["--candidate-root"]);
    result.caseId = values["--case-id"];
    result.powershell = path.resolve(values["--powershell"]);
    result.releaseSourceCommit = values["--release-source-commit"];
    result.releaseSourceTree = values["--release-source-tree"];
    result.routeKind = values["--route-kind"];
    result.runId = values["--run-id"];
    if (result.mode === "pipe") {
        expect(["begin_case", "end_case", "snapshot", "journal"].includes(result.command), "pipe command invalid");
        expect(!result.emitConfigurationArgv && !result.releaseSourceCommit && !result.releaseSourceTree, "pipe command has collect-only flags");
        expect(result.command === "journal" ? !result.caseId : ENDPOINT_CASE_SET.has(result.caseId), "pipe command caseId binding invalid");
    } else {
        expect(ENDPOINT_REPORT_CASES[result.reportId], "collect-report is not an endpoint report");
        expect(result.releaseSourceCommit && result.releaseSourceTree, "collect-report requires release-source commit and tree");
        expect(!result.caseId && !result.routeKind, "collect-report has pipe-only flags");
    }
    expectRunId(result.runId, "observer CLI runId");
    expectSha(result.candidateBuildIdentity, "observer CLI candidate build identity");
    expectSha(result.candidatePayloadClosure, "observer CLI candidate payload closure");
    expectUint(result.candidatePid, "observer CLI candidate PID", 1);
    expect(path.isAbsolute(result.candidateRoot) && fs.lstatSync(result.candidateRoot).isDirectory(), "observer CLI candidate root invalid");
    expect(path.isAbsolute(result.powershell) && fs.lstatSync(result.powershell).isFile(), "observer CLI PowerShell invalid");
    return result;
}

function inspectCliCandidate(options) {
    const script = "$ErrorActionPreference='Stop';$p=Get-Process -Id " + options.candidatePid + " -ErrorAction Stop;" +
        "[ordered]@{id=$p.Id;path=$p.Path;startUtc=$p.StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')}|ConvertTo-Json -Compress";
    const executed = cp.spawnSync(options.powershell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script], {
        encoding: "utf8", maxBuffer: 1024 * 1024, timeout: 15000, windowsHide: true
    });
    if (executed.error || executed.status !== 0) fail("PREREQUISITE_MISSING", "candidate process is not inspectable");
    let processValue;
    try { processValue = JSON.parse(executed.stdout); }
    catch (error) { fail("VALIDATION_FAILED", "candidate process inspection returned invalid JSON"); }
    const expectedPath = fs.realpathSync.native(path.join(options.candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"));
    const actualPath = fs.realpathSync.native(processValue.path);
    expect(actualPath.toLowerCase() === expectedPath.toLowerCase() && processValue.id === options.candidatePid, "observed process is not the exact candidate Core executable");
    const executableBytes = fs.readFileSync(expectedPath);
    return {
        buildIdentity: options.candidateBuildIdentity,
        executablePath: actualPath,
        executableSha256: sha256(executableBytes),
        payloadClosure: options.candidatePayloadClosure,
        pid: options.candidatePid,
        processStartUtc: processValue.startUtc
    };
}

function parseCliVoiceLimit() {
    const source = fs.readFileSync(path.resolve(__dirname, "..", "..", "launcher", "native", "miniaudio_bridge.c"), "utf8");
    const matches = Array.from(source.matchAll(/^#define CF7_SFX_VOICES ([1-9][0-9]*)u$/gm));
    expect(matches.length === 1 && Number(matches[0][1]) === 4, "exact S CF7_SFX_VOICES must be uniquely bound to 4");
    return 4;
}

function cliMain(argv) {
    const parsed = parseCli(argv);
    if (parsed.help) {
        process.stdout.write(
            "Audio v2 qualification observer (qualification-only; never drives audio)\n" +
            "Common: --candidate-root <abs> --candidate-build-identity <SHA256> --candidate-payload-closure <SHA256> --candidate-pid <pid> --powershell <abs> --run-id <32-lower-hex>\n" +
            "Marker/read: --pipe-command begin_case|snapshot|end_case|journal [--case-id <frozen-case>] [--route-kind bluetooth|hdmi] <common>\n" +
            "Collect: --collect-report <endpoint-report-id> --release-source-commit <oid> --release-source-tree <oid> [--emit-configuration-argv] <common>\n" +
            "begin_case/end_case only mark the run; snapshot/journal only observe. Audio must enter through production AS2 AudioBridge -> XMLSocket -> AudioTask.\n");
        return;
    }
    const expectedCandidate = inspectCliCandidate(parsed);
    const pipeOptions = {
        clientPath: path.resolve(__dirname, "qualification-observer-client.ps1"),
        env: process.env,
        expectedCandidate,
        powershell: parsed.powershell,
        routeKind: parsed.routeKind,
        runId: parsed.runId
    };
    if (parsed.mode === "pipe") {
        const response = requestPipe(pipeOptions, parsed.command, parsed.caseId);
        process.stdout.write(canonicalBytes(response));
        process.stdout.write("\n");
        return;
    }
    const completed = queryCompletedJournal(pipeOptions);
    const derived = deriveLiveObservation({
        candidateBuildIdentity: parsed.candidateBuildIdentity,
        candidatePayloadClosure: parsed.candidatePayloadClosure,
        releaseSource: { commit: parsed.releaseSourceCommit, treeOid: parsed.releaseSourceTree },
        reportId: parsed.reportId,
        sfxVoiceLimit: parseCliVoiceLimit()
    }, completed);
    const output = parsed.emitConfigurationArgv
        ? ["node", "tools/audio-v2/qualification-runner.js", "--report-id", parsed.reportId].concat(trackedObservationArguments(derived.carrier))
        : derived.carrier;
    process.stdout.write(canonicalBytes(output));
    process.stdout.write("\n");
}

if (require.main === module) {
    try { cliMain(process.argv.slice(2)); }
    catch (error) {
        const code = error instanceof QualificationObserverError ? error.code : "INTERNAL_ERROR";
        const message = error && error.message ? error.message : String(error);
        process.stderr.write("audio-v2 qualification observer failed [" + code + "]: " + message.replace(/[\r\n]+/g, " ") + "\n");
        process.exitCode = 3;
    }
}

module.exports = Object.freeze({
    CLIENT_PATH,
    ENDPOINT_CASES,
    ENDPOINT_REPORT_CASES,
    JOURNAL_CARRIER_SCHEMA,
    MAX_REQUEST_BYTES,
    MAX_RESPONSE_BYTES,
    PROTOCOL,
    QualificationObserverError,
    buildRequest,
    canonicalBytes,
    cliMain,
    deriveLiveObservation,
    deriveCaseFacts,
    queryCompletedJournal,
    requestPipe,
    sha256,
    sortedClone,
    trackedObservationArguments,
    validateCompletedJournal,
    validateEvent,
    validateJournal,
    validateJournalCarrier,
    validateResponse,
    validateSnapshot
});
