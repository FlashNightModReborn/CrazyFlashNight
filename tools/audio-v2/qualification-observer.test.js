#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const observer = require("./qualification-observer.js");
const runner = require("./qualification-runner.js");

const RUN_ID = "1".repeat(32);
const BUILD_IDENTITY = "A".repeat(64);
const PAYLOAD_CLOSURE = "B".repeat(64);
const DEVICE_DIGEST = "C".repeat(64);
const AUDIO_SESSION_ID = "01234567-89ab-4cde-8fab-0123456789ab";

function snapshot(overrides) {
    const result = {
        bgmMeter: { clipCount: 0, frameCount: 1000, peakLeft: 0.25, peakRight: 0.25, rmsLeft: 0.1, rmsRight: 0.1, underrunCount: 0 },
        counters: { playedCount: 0, preReadyDrops: 0, recoveryDrops: 0, staleGenerationDrops: 0, startFailureCount: 0, throttledCount: 0, unknownIdCount: 0 },
        runtime: {
            audioReadyGeneration: 1,
            audioSessionId: AUDIO_SESSION_ID,
            backend: "wasapi",
            channels: 2,
            deviceGeneration: 1,
            deviceIdDigest: DEVICE_DIGEST,
            deviceName: "Test Endpoint",
            sampleFormat: "f32",
            sampleRate: 48000,
            status: "ready"
        },
        sfxMeter: { clipCount: 0, frameCount: 1000, peakLeft: 0.25, peakRight: 0.25, rmsLeft: 0.1, rmsRight: 0.1, underrunCount: 0 },
        source: {
            codec: "vorbis",
            container: "ogg",
            cursorFrames: 100,
            decoderBackend: "libvorbis",
            lengthFrames: 480000,
            playing: true,
            requestId: "bgm-request",
            startCategory: "ok"
        }
    };
    Object.keys(overrides || {}).forEach((section) => {
        result[section] = Object.assign({}, result[section], overrides[section]);
    });
    return result;
}

function appendEvent(events, caseId, kind, source, payload) {
    const sequence = events.length + 1;
    const value = {
        caseId,
        kind,
        monotonicTicks: sequence,
        observedAtUtc: new Date(Date.UTC(2026, 7, 9, 0, 0, 0, sequence * 100)).toISOString(),
        payload,
        previousSha256: sequence === 1 ? "0".repeat(64) : events[events.length - 1].sha256,
        runId: RUN_ID,
        sequence,
        source
    };
    value.sha256 = observer.sha256(observer.canonicalBytes(value));
    events.push(value);
    return value;
}

function makeJournal(cases) {
    const events = [];
    (cases || observer.ENDPOINT_CASES).forEach((caseId) => {
        appendEvent(events, caseId, "case_begin", "qualification_observer",
            caseId === "physical_route_bluetooth_or_hdmi" ? { routeKind: "hdmi" } : {});
        appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot());
        appendEvent(events, caseId, "case_end", "qualification_observer", {});
    });
    return {
        events,
        firstSequence: 1,
        lastSequence: events.length,
        sha256: observer.sha256(observer.canonicalBytes(events))
    };
}

function bgmRequest(operation, requestId, overrides) {
    return Object.assign({
        audioReadyGeneration: 1,
        audioSessionId: AUDIO_SESSION_ID,
        fadeSeconds: null,
        loop: null,
        operation,
        path: null,
        requestId,
        seekSeconds: null,
        volume: null,
        wireRevision: 2
    }, overrides || {});
}

function bgmResult(operation, requestId, decoderBackend, stage) {
    return {
        audioReadyGeneration: 1,
        audioSessionId: AUDIO_SESSION_ID,
        category: "ok",
        completionState: "started",
        decoderBackend,
        deviceGeneration: 1,
        hresult: 0,
        messageKey: "audio.bgm.started",
        nativeCode: 0,
        operation,
        requestId,
        stage
    };
}

function sfxBatch(batchSequence, linkageIds) {
    return {
        audioReadyGeneration: 1,
        audioSessionId: AUDIO_SESSION_ID,
        batchSequence,
        linkageIds,
        wireRevision: 2
    };
}

function makeBgmQualificationJournal() {
    const events = [];
    observer.ENDPOINT_CASES.forEach((caseId) => {
        appendEvent(events, caseId, "case_begin", "qualification_observer",
            caseId === "physical_route_bluetooth_or_hdmi" ? { routeKind: "hdmi" } : {});
        if (caseId === "bgm_playback") {
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 1000 },
                source: { codec: "none", container: "none", cursorFrames: 0, decoderBackend: "none", lengthFrames: 0, playing: false, requestId: null, startCategory: "not_ready" }
            }));
            appendEvent(events, caseId, "as2_bgm_request", "as2_ingress", bgmRequest("play", "bgm-play", {
                fadeSeconds: 0, loop: true, path: "music.ogg", volume: 1
            }));
            appendEvent(events, caseId, "as2_bgm_result", "audio_coordinator", bgmResult("play", "bgm-play", "libvorbis", "native_start"));
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 4000 }, source: { cursorFrames: 4800, requestId: "bgm-play" }
            }));
        } else if (caseId === "bgm_seek") {
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 1000 }, source: { cursorFrames: 300000, requestId: "bgm-play" }
            }));
            appendEvent(events, caseId, "as2_bgm_request", "as2_ingress", bgmRequest("seek", "bgm-seek", { seekSeconds: 2 }));
            appendEvent(events, caseId, "as2_bgm_result", "audio_coordinator", bgmResult("seek", "bgm-seek", "libvorbis", "seek"));
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 4000 }, source: { cursorFrames: 100000, requestId: "bgm-play" }
            }));
        } else if (caseId === "bgm_crossfade") {
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 1000 }, source: { cursorFrames: 200, requestId: "old-source" }
            }));
            appendEvent(events, caseId, "as2_bgm_request", "as2_ingress", bgmRequest("play", "crossfade-source", {
                fadeSeconds: 1, loop: true, path: "next.ogg", volume: 1
            }));
            appendEvent(events, caseId, "as2_bgm_result", "audio_coordinator", bgmResult("play", "crossfade-source", "libvorbis", "native_start"));
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 2000 }, source: { cursorFrames: 400, requestId: "old-source" }
            }));
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 3000 }, source: { cursorFrames: 100, requestId: "crossfade-source" }
            }));
        } else if (["format_vorbis", "format_aac_mp4", "format_opus"].includes(caseId)) {
            const expected = {
                format_vorbis: { codec: "vorbis", container: "ogg", decoderBackend: "libvorbis", path: "format.ogg" },
                format_aac_mp4: { codec: "aac_lc_or_he_aac", container: "mpeg4", decoderBackend: "media_foundation", path: "format.m4a" },
                format_opus: { codec: "opus", container: "ogg", decoderBackend: "libopus", path: "format.opus" }
            }[caseId];
            const requestId = caseId + "-request";
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 1000 },
                source: { codec: "none", container: "none", cursorFrames: 0, decoderBackend: "none", lengthFrames: 0, playing: false, requestId: null, startCategory: "not_ready" }
            }));
            appendEvent(events, caseId, "as2_bgm_request", "as2_ingress", bgmRequest("play", requestId, {
                fadeSeconds: null, loop: true, path: expected.path, volume: 1
            }));
            appendEvent(events, caseId, "as2_bgm_result", "audio_coordinator", bgmResult("play", requestId, expected.decoderBackend, "native_start"));
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot({
                bgmMeter: { frameCount: 4000 },
                source: { codec: expected.codec, container: expected.container, cursorFrames: 4800, decoderBackend: expected.decoderBackend, requestId }
            }));
        } else if (["sfx_playback", "dense_overlap_throttle", "bgm_sfx_mix"].includes(caseId)) {
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot());
            appendEvent(events, caseId, "as2_sfx_batch", "as2_ingress", sfxBatch(1,
                caseId === "dense_overlap_throttle" ? ["a", "a", "a", "a", "a", "a"] : ["a"]));
        } else if (caseId === "gain_zero_and_default_max") {
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot());
            appendEvent(events, caseId, "as2_bgm_request", "as2_ingress", bgmRequest("set_gain", "gain-default", { volume: 1 }));
            appendEvent(events, caseId, "as2_bgm_result", "audio_coordinator", bgmResult("set_gain", "gain-default", "libvorbis", "native_start"));
            appendEvent(events, caseId, "as2_bgm_request", "as2_ingress", bgmRequest("set_gain", "gain-zero", { volume: 0 }));
            appendEvent(events, caseId, "as2_bgm_result", "audio_coordinator", bgmResult("set_gain", "gain-zero", "libvorbis", "native_start"));
        } else if (caseId === "no_stale_sfx_after_recovery") {
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot());
            appendEvent(events, caseId, "as2_sfx_batch", "as2_ingress", sfxBatch(2, ["stale"]));
        } else {
            appendEvent(events, caseId, "qualification_snapshot", "qualification_observer", snapshot());
        }
        appendEvent(events, caseId, "case_end", "qualification_observer", {});
    });
    return {
        events,
        firstSequence: 1,
        lastSequence: events.length,
        sha256: observer.sha256(observer.canonicalBytes(events))
    };
}

function rehashJournal(journal) {
    journal.events.forEach((entry, index) => {
        entry.sequence = index + 1;
        entry.monotonicTicks = index + 1;
        entry.previousSha256 = index === 0 ? "0".repeat(64) : journal.events[index - 1].sha256;
        const unhashed = Object.assign({}, entry);
        delete unhashed.sha256;
        entry.sha256 = observer.sha256(observer.canonicalBytes(unhashed));
    });
    journal.firstSequence = journal.events[0].sequence;
    journal.lastSequence = journal.events[journal.events.length - 1].sequence;
    journal.sha256 = observer.sha256(observer.canonicalBytes(journal.events));
    return journal;
}

function candidate() {
    return {
        buildIdentity: BUILD_IDENTITY,
        executablePath: path.resolve(process.execPath),
        executableSha256: observer.sha256(fs.readFileSync(process.execPath)),
        payloadClosure: PAYLOAD_CLOSURE,
        pid: process.pid,
        processStartUtc: "2026-08-09T00:00:00Z"
    };
}

let passed = 0;
function test(name, body) {
    body();
    passed++;
    process.stdout.write("ok " + passed + " - " + name + "\n");
}

test("wire canonical JSON is compact sorted UTF-8 without framing", () => {
    assert.strictEqual(observer.canonicalBytes({ z: 1, a: { y: 2, b: 3 } }).toString("utf8"), '{"a":{"b":3,"y":2},"z":1}');
});

test("the completed journal is exactly one ordered fourteen-case run", () => {
    const journal = makeJournal();
    observer.validateJournal(journal, RUN_ID);
    const ranges = observer.validateCompletedJournal(journal);
    assert.strictEqual(Object.keys(ranges).length, 14);
    assert.deepStrictEqual(Object.keys(ranges), observer.ENDPOINT_CASES);
});

test("missing and duplicate case runs fail closed", () => {
    const missing = makeJournal(observer.ENDPOINT_CASES.slice(0, -1));
    observer.validateJournal(missing, RUN_ID);
    assert.throws(() => observer.validateCompletedJournal(missing), /exactly one completed 14-case run/);

    const duplicateCases = observer.ENDPOINT_CASES.slice();
    duplicateCases[1] = duplicateCases[0];
    const duplicate = makeJournal(duplicateCases);
    observer.validateJournal(duplicate, RUN_ID);
    assert.throws(() => observer.validateCompletedJournal(duplicate), /order drift|repeats/);
});

test("event hash sequence and aggregate journal drift fail closed", () => {
    const eventDrift = makeJournal();
    eventDrift.events.find((entry) => entry.kind === "qualification_snapshot").payload.runtime.sampleRate = 44100;
    assert.throws(() => observer.validateJournal(eventDrift, RUN_ID), /event SHA-256 mismatch/);

    const sequenceDrift = makeJournal();
    sequenceDrift.events[4].sequence = 99;
    assert.throws(() => observer.validateJournal(sequenceDrift, RUN_ID), /sequence envelope|sequence drift|event SHA/);

    const aggregateDrift = makeJournal();
    aggregateDrift.sha256 = "F".repeat(64);
    assert.throws(() => observer.validateJournal(aggregateDrift, RUN_ID), /aggregate SHA-256 mismatch/);
});

test("all fourteen cases are bound to one audio session", () => {
    const journal = makeJournal();
    const foreign = journal.events.find((entry) => entry.caseId === "sfx_playback" && entry.kind === "qualification_snapshot");
    foreign.payload.runtime.audioSessionId = "11234567-89ab-4cde-8fab-0123456789ab";
    rehashJournal(journal);
    observer.validateJournal(journal, RUN_ID);
    assert.throws(() => observer.validateCompletedJournal(journal), /more than one audio session/);
});

test("diagnostic decimals are canonical non-exponent 1e-6 values", () => {
    const events = [];
    const value = snapshot({
        bgmMeter: { peakLeft: 0.00001, peakRight: 0.000089, rmsLeft: 0.00001, rmsRight: 0.000089 }
    });
    const event = appendEvent(events, "bgm_playback", "qualification_snapshot", "qualification_observer", value);
    assert.strictEqual(observer.validateEvent(event, RUN_ID, "quantized meter"), event);
    const raw = observer.canonicalBytes(event).toString("utf8");
    assert.ok(raw.includes('"peakLeft":0.00001') && raw.includes('"peakRight":0.000089'));
    value.bgmMeter.peakLeft = 0.0000001;
    const unhashed = Object.assign({}, event); delete unhashed.sha256;
    event.sha256 = observer.sha256(observer.canonicalBytes(unhashed));
    assert.throws(() => observer.validateEvent(event, RUN_ID, "sub-quantum meter"), /quantized to 1e-6/);
});

test("BGM requests and SFX batches must be AS2 ingress while results are coordinator events", () => {
    const journal = makeJournal();
    const range = journal.events.findIndex((entry) => entry.caseId === "bgm_playback" && entry.kind === "qualification_snapshot");
    journal.events[range] = Object.assign({}, journal.events[range], {
        kind: "as2_bgm_request",
        payload: {
            audioReadyGeneration: 1, audioSessionId: AUDIO_SESSION_ID,
            fadeSeconds: 0, loop: true, operation: "play", path: "music.ogg",
            requestId: "request-1", seekSeconds: 0, volume: 1, wireRevision: 2
        },
        source: "audio_coordinator"
    });
    rehashJournal(journal);
    assert.throws(() => observer.validateJournal(journal, RUN_ID), /did not enter through AS2/);
});

test("real started and failed BGM result vocabularies use string stages", () => {
    const events = [];
    const common = {
        audioReadyGeneration: 1,
        audioSessionId: AUDIO_SESSION_ID,
        decoderBackend: "libvorbis",
        deviceGeneration: 1,
        hresult: 0,
        messageKey: "audio.bgm.completed",
        nativeCode: 0,
        operation: "play",
        requestId: "request-started",
        stage: "native_start"
    };
    const started = appendEvent(events, "bgm_playback", "as2_bgm_result", "audio_coordinator", Object.assign({}, common, {
        category: "ok", completionState: "started"
    }));
    assert.strictEqual(observer.validateEvent(started, RUN_ID, "started result"), started);

    const failedPayload = Object.assign({}, common, {
        category: "device_lost",
        completionState: "failed",
        decoderBackend: "none",
        messageKey: "audio.device_lost",
        requestId: "request-failed",
        stage: "device_start"
    });
    const failed = appendEvent(events, "bgm_playback", "as2_bgm_result", "audio_coordinator", failedPayload);
    assert.strictEqual(observer.validateEvent(failed, RUN_ID, "failed result"), failed);

    failed.payload.stage = 10;
    const unhashed = Object.assign({}, failed); delete unhashed.sha256;
    failed.sha256 = observer.sha256(observer.canonicalBytes(unhashed));
    assert.throws(() => observer.validateEvent(failed, RUN_ID, "numeric stage"), /stage invalid/);
});

test("routeKind annotation is accepted only on the physical-route begin marker", () => {
    const journal = makeJournal();
    observer.validateJournal(journal, RUN_ID);
    const firstBegin = journal.events.find((entry) => entry.kind === "case_begin");
    firstBegin.payload = { routeKind: "hdmi" };
    rehashJournal(journal);
    assert.throws(() => observer.validateJournal(journal, RUN_ID), /keys mismatch/);
    assert.throws(() => observer.buildRequest("begin_case", RUN_ID, "physical_route_bluetooth_or_hdmi", "2".repeat(32)), /requires routeKind/);
    assert.deepStrictEqual(
        observer.buildRequest("begin_case", RUN_ID, "physical_route_bluetooth_or_hdmi", "2".repeat(32), "bluetooth"),
        { caseId: "physical_route_bluetooth_or_hdmi", command: "begin_case", protocol: observer.PROTOCOL, requestId: "2".repeat(32), routeKind: "bluetooth", runId: RUN_ID }
    );
});

test("dense overlap facts close only over AS2 batch and candidate counters", () => {
    const before = snapshot();
    const after = snapshot({ counters: { playedCount: 2, throttledCount: 4 } });
    const range = {
        begin: { caseId: "dense_overlap_throttle" },
        events: [
            { kind: "qualification_snapshot", payload: before, sequence: 2 },
            {
                kind: "as2_sfx_batch", sequence: 3, source: "as2_ingress",
                payload: {
                    audioReadyGeneration: 1,
                    audioSessionId: AUDIO_SESSION_ID,
                    batchSequence: 1,
                    linkageIds: ["a", "a", "a", "a", "a", "a"]
                }
            },
            { kind: "qualification_snapshot", payload: after, sequence: 4 }
        ]
    };
    assert.deepStrictEqual(observer.deriveCaseFacts("dense_overlap_throttle", range, { sfxPerEntryVoiceCap: 4 }), {
        captureId: "sfx_playback", configuredPerEntryVoiceCap: 4,
        playedAfter: 2, playedBefore: 0, requestedVoices: 6,
        throttledAfter: 4, throttledBefore: 0
    });
    range.events[2].payload.counters.throttledCount = 3;
    assert.throws(() => observer.deriveCaseFacts("dense_overlap_throttle", range, { sfxPerEntryVoiceCap: 4 }), /do not close/);
    range.events[2].payload.counters.throttledCount = 4;
    range.events[1].payload.linkageIds[5] = "b";
    assert.throws(() => observer.deriveCaseFacts("dense_overlap_throttle", range, { sfxPerEntryVoiceCap: 4 }), /must be identical/);
    range.events[1].payload.linkageIds[5] = "a";
    [
        "preReadyDrops", "recoveryDrops", "staleGenerationDrops",
        "startFailureCount", "unknownIdCount"
    ].forEach((key) => {
        range.events[2].payload.counters[key] = 1;
        assert.throws(
            () => observer.deriveCaseFacts("dense_overlap_throttle", range, { sfxPerEntryVoiceCap: 4 }),
            new RegExp("unexpected outcome counter advanced: " + key));
        range.events[2].payload.counters[key] = 0;
    });
});

test("SFX playback requires its own advancing nonzero meter window", () => {
    const before = snapshot({
        bgmMeter: { frameCount: 1000, peakLeft: 0, peakRight: 0, rmsLeft: 0, rmsRight: 0 },
        sfxMeter: { frameCount: 1000 }
    });
    const after = snapshot({ counters: { playedCount: 2 }, sfxMeter: { frameCount: 1100 } });
    const range = {
        begin: { caseId: "sfx_playback" },
        events: [
            { kind: "qualification_snapshot", payload: before, sequence: 2 },
            {
                kind: "as2_sfx_batch", sequence: 3, source: "as2_ingress",
                payload: { audioReadyGeneration: 1, audioSessionId: AUDIO_SESSION_ID, batchSequence: 1, linkageIds: ["a", "b"] }
            },
            { kind: "qualification_snapshot", payload: after, sequence: 4 }
        ]
    };
    assert.strictEqual(observer.deriveCaseFacts("sfx_playback", range, {}).requestedVoices, 2);
    after.sfxMeter.frameCount = 1000;
    assert.throws(() => observer.deriveCaseFacts("sfx_playback", range, {}), /meter frame window did not advance/);
    after.sfxMeter.frameCount = 1100;
    after.sfxMeter.peakLeft = 0;
    after.sfxMeter.peakRight = 0;
    assert.throws(() => observer.deriveCaseFacts("sfx_playback", range, {}), /meter window has no qualified signal/);
    after.sfxMeter.peakLeft = 0.25;
    after.sfxMeter.peakRight = 0.25;
    before.bgmMeter.peakLeft = 0.25;
    assert.throws(() => observer.deriveCaseFacts("sfx_playback", range, {}), /contaminated by audible BGM/);
});

test("BGM/SFX mix accepts loop wrap or full-loop cursor equality and rejects bad meter/bounds", () => {
    const before = snapshot({
        bgmMeter: { frameCount: 1000 },
        sfxMeter: { frameCount: 1000, peakLeft: 0, peakRight: 0, rmsLeft: 0, rmsRight: 0 },
        source: { cursorFrames: 18240, lengthFrames: 24000, requestId: "looping-opus" }
    });
    const after = snapshot({
        bgmMeter: { frameCount: 2000 },
        counters: { playedCount: 1 },
        sfxMeter: { frameCount: 2000 },
        source: { cursorFrames: 14880, lengthFrames: 24000, requestId: "looping-opus" }
    });
    const range = {
        begin: { caseId: "bgm_sfx_mix" },
        events: [
            { kind: "qualification_snapshot", payload: before, sequence: 2 },
            {
                kind: "as2_sfx_batch", sequence: 3, source: "as2_ingress",
                payload: sfxBatch(1, ["long.wav"])
            },
            { kind: "qualification_snapshot", payload: after, sequence: 4 }
        ]
    };
    assert.deepStrictEqual(observer.deriveCaseFacts("bgm_sfx_mix", range, {}), {
        bgmFrames: 1000,
        captureId: "bgm_sfx_mix",
        sfxPlayedAfter: 1,
        sfxPlayedBefore: 0
    });

    before.sfxMeter.peakLeft = 0.25;
    assert.throws(() => observer.deriveCaseFacts("bgm_sfx_mix", range, {}), /contaminated by residual SFX/);
    before.sfxMeter.peakLeft = 0;
    after.source.cursorFrames = before.source.cursorFrames;
    assert.strictEqual(observer.deriveCaseFacts("bgm_sfx_mix", range, {}).bgmFrames, 1000);
    after.source.cursorFrames = after.source.lengthFrames;
    assert.throws(() => observer.deriveCaseFacts("bgm_sfx_mix", range, {}), /outside a stable nonempty loop boundary/);
    after.source.cursorFrames = 14880;
    after.bgmMeter.frameCount = before.bgmMeter.frameCount;
    assert.throws(() => observer.deriveCaseFacts("bgm_sfx_mix", range, {}), /BGM meter frame window did not advance/);
    after.bgmMeter.frameCount = 2000;
    after.bgmMeter.peakLeft = 0;
    after.bgmMeter.peakRight = 0;
    assert.throws(() => observer.deriveCaseFacts("bgm_sfx_mix", range, {}), /BGM meter window has no qualified signal/);
    after.bgmMeter.peakLeft = 0.25;
    after.bgmMeter.peakRight = 0.25;
    after.sfxMeter.frameCount = before.sfxMeter.frameCount;
    assert.throws(() => observer.deriveCaseFacts("bgm_sfx_mix", range, {}), /SFX meter frame window did not advance/);
    after.sfxMeter.frameCount = 2000;
    after.sfxMeter.peakLeft = 0;
    after.sfxMeter.peakRight = 0;
    assert.throws(() => observer.deriveCaseFacts("bgm_sfx_mix", range, {}), /SFX meter window has no qualified signal/);
});

test("sleep resume closes recovering to a later owner/qualification ready snapshot", () => {
    const before = snapshot({ runtime: { deviceGeneration: 1, status: "ready" } });
    const recovering = snapshot({ runtime: { audioReadyGeneration: 2, deviceGeneration: 1, status: "recovering" } });
    const ready = snapshot({
        bgmMeter: { frameCount: 2000 },
        runtime: { audioReadyGeneration: 2, deviceGeneration: 2, status: "ready" }
    });
    const range = {
        begin: { caseId: "sleep_resume" },
        events: [
            { kind: "qualification_snapshot", observedAtUtc: "2026-08-09T00:00:00.000Z", payload: before, sequence: 2 },
            { kind: "coordinator_recovery", observedAtUtc: "2026-08-09T00:00:01.000Z", payload: recovering, sequence: 3 },
            { kind: "coordinator_snapshot", observedAtUtc: "2026-08-09T00:00:02.250Z", payload: ready, sequence: 4 },
            { kind: "qualification_snapshot", observedAtUtc: "2026-08-09T00:00:02.300Z", payload: ready, sequence: 5 }
        ]
    };
    assert.deepStrictEqual(observer.deriveCaseFacts("sleep_resume", range, {}), {
        captureId: "device_recovery",
        deviceGenerationAfter: 2,
        deviceGenerationBefore: 1,
        maxRecoveryMs: 15000,
        recoveryMs: 1250
    });

    ready.runtime.audioReadyGeneration = 1;
    assert.throws(() => observer.deriveCaseFacts("sleep_resume", range, {}), /ready-generation barrier drifted/);
    ready.runtime.audioReadyGeneration = 2;
    ready.runtime.deviceIdDigest = "D".repeat(64);
    assert.throws(() => observer.deriveCaseFacts("sleep_resume", range, {}), /changed the qualified endpoint digest/);
    ready.runtime.deviceIdDigest = DEVICE_DIGEST;

    range.events.splice(2, 1);
    range.events[2].payload = recovering;
    assert.throws(() => observer.deriveCaseFacts("sleep_resume", range, {}), /transition missing|out of order/);
});

function crossfadeRange(samples) {
    const request = {
        kind: "as2_bgm_request", sequence: 3, source: "as2_ingress",
        payload: {
            audioReadyGeneration: 1,
            audioSessionId: AUDIO_SESSION_ID,
            fadeSeconds: 1,
            operation: "play",
            requestId: "new-request"
        }
    };
    const result = {
        kind: "as2_bgm_result", sequence: 4, source: "audio_coordinator",
        payload: {
            audioReadyGeneration: 1,
            audioSessionId: AUDIO_SESSION_ID,
            category: "ok",
            completionState: "started",
            deviceGeneration: 1,
            operation: "play",
            requestId: "new-request",
            stage: "native_start"
        }
    };
    const snapshotEvents = samples.map((sample, index) => ({
        kind: "qualification_snapshot",
        observedAtUtc: "2026-08-09T00:00:00." + String(sample.milliseconds).padStart(3, "0") + "Z",
        payload: snapshot({
            bgmMeter: { frameCount: sample.frameCount },
            source: {
                cursorFrames: sample.requestId === "new-request" ? 50 + index : 200 + index,
                requestId: sample.requestId
            }
        }),
        sequence: index === 0 ? 2 : index + 4
    }));
    return {
        begin: { caseId: "bgm_crossfade" },
        events: [snapshotEvents[0], request, result].concat(snapshotEvents.slice(1))
    };
}

test("crossfade permits short cached reads while bounding distinct frame progress", () => {
    const range = crossfadeRange([
        { frameCount: 1000, milliseconds: 0, requestId: "old-request" },
        { frameCount: 1000, milliseconds: 3, requestId: "old-request" },
        { frameCount: 1100, milliseconds: 100, requestId: "old-request" },
        { frameCount: 1100, milliseconds: 103, requestId: "old-request" },
        { frameCount: 1200, milliseconds: 200, requestId: "new-request" },
        { frameCount: 1200, milliseconds: 203, requestId: "new-request" }
    ]);
    const facts = observer.deriveCaseFacts("bgm_crossfade", range, {});
    assert.strictEqual(facts.gapMs, 100);
    assert.strictEqual(facts.maxGapMs, 500);
    const finalSnapshot = range.events[range.events.length - 1].payload;
    finalSnapshot.runtime.deviceGeneration = 2;
    assert.throws(() => observer.deriveCaseFacts("bgm_crossfade", range, {}), /tuple changed outside recovery/);
    finalSnapshot.runtime.deviceGeneration = 1;
});

test("crossfade rejects a no-progress plateau longer than 500ms including trailing duplicates", () => {
    const range = crossfadeRange([
        { frameCount: 1000, milliseconds: 0, requestId: "old-request" },
        { frameCount: 1100, milliseconds: 100, requestId: "old-request" },
        { frameCount: 1200, milliseconds: 200, requestId: "new-request" },
        { frameCount: 1200, milliseconds: 701, requestId: "new-request" }
    ]);
    assert.throws(() => observer.deriveCaseFacts("bgm_crossfade", range, {}), /no-progress window exceeds 500ms/);
});

test("crossfade rejects frame regression and fewer than three distinct advancing samples", () => {
    const regression = crossfadeRange([
        { frameCount: 1000, milliseconds: 0, requestId: "old-request" },
        { frameCount: 1100, milliseconds: 100, requestId: "old-request" },
        { frameCount: 1050, milliseconds: 200, requestId: "old-request" },
        { frameCount: 1200, milliseconds: 300, requestId: "new-request" }
    ]);
    assert.throws(() => observer.deriveCaseFacts("bgm_crossfade", regression, {}), /frameCount regressed/);

    const insufficient = crossfadeRange([
        { frameCount: 1000, milliseconds: 0, requestId: "old-request" },
        { frameCount: 1000, milliseconds: 100, requestId: "old-request" },
        { frameCount: 1100, milliseconds: 200, requestId: "new-request" },
        { frameCount: 1100, milliseconds: 300, requestId: "new-request" }
    ]);
    assert.throws(() => observer.deriveCaseFacts("bgm_crossfade", insufficient, {}), /at least three distinct advancing meter samples/);
});

test("backward seek binds a started seek result to an elapsed cursor and meter window", () => {
    const before = snapshot({ source: { cursorFrames: 300000 } });
    const after = snapshot({ bgmMeter: { frameCount: 1100 }, source: { cursorFrames: 100000 } });
    const request = {
        kind: "as2_bgm_request",
        observedAtUtc: "2026-08-09T00:00:00.900Z",
        payload: {
            audioReadyGeneration: 1,
            audioSessionId: AUDIO_SESSION_ID,
            operation: "seek",
            requestId: "seek-request",
            seekSeconds: 2
        },
        sequence: 3,
        source: "as2_ingress"
    };
    const result = {
        kind: "as2_bgm_result",
        observedAtUtc: "2026-08-09T00:00:01.000Z",
        payload: {
            audioReadyGeneration: 1,
            audioSessionId: AUDIO_SESSION_ID,
            category: "ok",
            completionState: "started",
            deviceGeneration: 1,
            operation: "seek",
            requestId: "seek-request",
            stage: "seek"
        },
        sequence: 4,
        source: "audio_coordinator"
    };
    const range = {
        begin: { caseId: "bgm_seek" },
        events: [
            { kind: "qualification_snapshot", observedAtUtc: "2026-08-09T00:00:00.000Z", payload: before, sequence: 2 },
            request,
            result,
            { kind: "qualification_snapshot", observedAtUtc: "2026-08-09T00:00:01.100Z", payload: after, sequence: 5 }
        ]
    };
    const facts = observer.deriveCaseFacts("bgm_seek", range, {});
    assert.strictEqual(facts.cursorBeforeFrames, 300000);
    assert.strictEqual(facts.cursorAfterFrames, 100000);
    assert.strictEqual(facts.targetFrames, 96000);

    result.payload.completionState = "failed";
    assert.throws(() => observer.deriveCaseFacts("bgm_seek", range, {}), /did not start playback/);
    result.payload.completionState = "started";
    result.payload.stage = "native_start";
    assert.throws(() => observer.deriveCaseFacts("bgm_seek", range, {}), /stage mismatch/);
    result.payload.stage = "seek";
    after.source.cursorFrames = 310000;
    assert.throws(() => observer.deriveCaseFacts("bgm_seek", range, {}), /outside the target\/elapsed telemetry window/);
    after.source.cursorFrames = 100000;
    request.payload.audioReadyGeneration = 2;
    assert.throws(() => observer.deriveCaseFacts("bgm_seek", range, {}), /request tuple differs/);
    request.payload.audioReadyGeneration = 1;
    after.bgmMeter.frameCount = 1000;
    assert.throws(() => observer.deriveCaseFacts("bgm_seek", range, {}), /meter frame window did not advance/);
    after.bgmMeter.frameCount = 1100;
    range.events.push({
        kind: "as2_bgm_request", payload: { operation: "play", requestId: "undeclared-play" }, sequence: 6, source: "as2_ingress"
    }, {
        kind: "as2_bgm_result", payload: { operation: "play", requestId: "undeclared-play" }, sequence: 7, source: "audio_coordinator"
    });
    assert.throws(() => observer.deriveCaseFacts("bgm_seek", range, {}), /BGM ingress operation\/count grammar mismatch/);
});

test("format playback requires a started result and an advancing nonzero source meter", () => {
    const before = snapshot({ bgmMeter: { frameCount: 1000 }, source: { cursorFrames: 0, playing: false, requestId: null } });
    const after = snapshot({ bgmMeter: { frameCount: 4000 }, source: { cursorFrames: 4800, requestId: "format-request" } });
    const request = {
        kind: "as2_bgm_request", sequence: 3, source: "as2_ingress",
        payload: { audioReadyGeneration: 1, audioSessionId: AUDIO_SESSION_ID, fadeSeconds: null, operation: "play", requestId: "format-request" }
    };
    const result = {
        kind: "as2_bgm_result", observedAtUtc: "2026-08-09T00:00:01.000Z", sequence: 4, source: "audio_coordinator",
        payload: {
            audioReadyGeneration: 1, audioSessionId: AUDIO_SESSION_ID, category: "ok",
            completionState: "started", deviceGeneration: 1, operation: "play",
            requestId: "format-request", stage: "native_start"
        }
    };
    const range = {
        begin: { caseId: "format_vorbis" },
        events: [
            { kind: "qualification_snapshot", payload: before, sequence: 2 },
            request,
            result,
            { kind: "qualification_snapshot", observedAtUtc: "2026-08-09T00:00:01.100Z", payload: after, sequence: 5 }
        ]
    };
    assert.strictEqual(observer.deriveCaseFacts("format_vorbis", range, {}).decodedFrames, 4800);
    request.payload.fadeSeconds = 1;
    assert.throws(() => observer.deriveCaseFacts("format_vorbis", range, {}), /must not rely on an old-source fade/);
    request.payload.fadeSeconds = null;
    range.events[3].observedAtUtc = "2026-08-09T00:00:01.050Z";
    assert.throws(() => observer.deriveCaseFacts("format_vorbis", range, {}), /window is too short/);
    range.events[3].observedAtUtc = "2026-08-09T00:00:01.100Z";
    after.bgmMeter.peakLeft = 0;
    after.bgmMeter.peakRight = 0;
    assert.throws(() => observer.deriveCaseFacts("format_vorbis", range, {}), /meter window has no qualified signal/);
    after.bgmMeter.peakLeft = 0.25;
    after.bgmMeter.peakRight = 0.25;
    after.bgmMeter.frameCount = 1000;
    assert.throws(() => observer.deriveCaseFacts("format_vorbis", range, {}), /meter frame window did not advance/);
});

test("stale SFX facts use automatic recovery owner boundaries", () => {
    const pre = snapshot({ runtime: { audioReadyGeneration: 1, deviceGeneration: 1, status: "ready" } });
    const recovering = snapshot({ runtime: { audioReadyGeneration: 2, deviceGeneration: 1, status: "recovering" } });
    const ready = snapshot({
        counters: { recoveryDrops: 2 },
        runtime: { audioReadyGeneration: 2, deviceGeneration: 2, status: "ready" }
    });
    const post = snapshot({
        bgmMeter: { frameCount: 1200 },
        counters: { recoveryDrops: 2 },
        runtime: { audioReadyGeneration: 2, deviceGeneration: 2, status: "ready" }
    });
    const batch = {
        kind: "as2_sfx_batch", sequence: 4, source: "as2_ingress",
        payload: {
            audioReadyGeneration: 1,
            audioSessionId: AUDIO_SESSION_ID,
            batchSequence: 9,
            linkageIds: ["stale-a", "stale-b"]
        }
    };
    const range = {
        begin: { caseId: "no_stale_sfx_after_recovery" },
        events: [
            { kind: "qualification_snapshot", payload: pre, sequence: 2 },
            { kind: "coordinator_recovery", payload: recovering, sequence: 3 },
            batch,
            { kind: "coordinator_snapshot", payload: ready, sequence: 5 },
            { kind: "qualification_snapshot", payload: post, sequence: 6 }
        ]
    };
    assert.deepStrictEqual(observer.deriveCaseFacts("no_stale_sfx_after_recovery", range, {}), {
        captureId: "device_recovery",
        playedAfter: 0,
        playedBefore: 0,
        recoveryDropsAfter: 2,
        recoveryDropsBefore: 0,
        staleBatchSize: 2
    });
    batch.payload.audioReadyGeneration = 2;
    assert.throws(() => observer.deriveCaseFacts("no_stale_sfx_after_recovery", range, {}), /pre-recovery tuple/);
    batch.payload.audioReadyGeneration = 1;
    ready.counters.throttledCount = 1;
    post.counters.throttledCount = 1;
    assert.throws(() => observer.deriveCaseFacts("no_stale_sfx_after_recovery", range, {}), /counters changed before ready/);
    ready.counters.throttledCount = 0;
    post.counters.throttledCount = 0;
    post.counters.playedCount = 1;
    assert.throws(() => observer.deriveCaseFacts("no_stale_sfx_after_recovery", range, {}), /counters changed after ready/);
    post.counters.playedCount = 0;
    post.bgmMeter.frameCount = ready.bgmMeter.frameCount;
    assert.throws(() => observer.deriveCaseFacts("no_stale_sfx_after_recovery", range, {}), /endpoint meter window did not advance/);
    post.bgmMeter.frameCount = 1200;
    batch.sequence = 2;
    assert.throws(() => observer.deriveCaseFacts("no_stale_sfx_after_recovery", range, {}), /not sent during recovery/);
});

test("physical route annotation observes the already-switched captured endpoint", () => {
    const before = snapshot({ bgmMeter: { frameCount: 1000 } });
    const after = snapshot({ bgmMeter: { frameCount: 1100 } });
    const range = {
        begin: { caseId: "physical_route_bluetooth_or_hdmi", payload: { routeKind: "hdmi" } },
        events: [
            { kind: "qualification_snapshot", payload: before, sequence: 2 },
            { kind: "qualification_snapshot", payload: after, sequence: 3 }
        ]
    };
    assert.deepStrictEqual(observer.deriveCaseFacts("physical_route_bluetooth_or_hdmi", range, {}), {
        captureId: "device_recovery", deviceIdDigest: DEVICE_DIGEST, routeKind: "hdmi"
    });
    after.runtime.deviceGeneration = 2;
    assert.throws(() => observer.deriveCaseFacts("physical_route_bluetooth_or_hdmi", range, {}), /tuple changed outside recovery/);
});

test("requestPipe opens a fresh connection and rejects noncanonical stdout", () => {
    const expectedCandidate = candidate();
    let calls = 0;
    function spawnSync(_executable, args, spawnOptions) {
        calls++;
        assert.ok(args.includes("-RequestFromStdin"));
        const requestBytes = spawnOptions.input;
        assert.ok(requestBytes.length <= observer.MAX_REQUEST_BYTES);
        assert.ok(!requestBytes.includes(0x0A) && !requestBytes.includes(0x0D));
        const request = JSON.parse(requestBytes.toString("utf8"));
        const response = {
            candidate: expectedCandidate,
            command: request.command,
            journal: makeJournal(),
            protocol: observer.PROTOCOL,
            requestId: request.requestId,
            result: "ok",
            runId: RUN_ID,
            schema: "cf7.audio-v2.qualification-response.v1"
        };
        return { status: 0, stderr: Buffer.alloc(0), stdout: observer.canonicalBytes(response) };
    }
    const options = {
        clientPath: path.join(__dirname, "qualification-observer-client.ps1"),
        expectedCandidate,
        powershell: process.execPath,
        runId: RUN_ID,
        spawnSync
    };
    observer.requestPipe(options, "journal");
    observer.requestPipe(options, "journal");
    observer.requestPipe(options, "journal");
    assert.strictEqual(calls, 3, "each replay must make a new pipe connection");

    options.spawnSync = function (_executable, args, spawnOptions) {
        const request = JSON.parse(spawnOptions.input.toString("utf8"));
        const response = { candidate: expectedCandidate, command: "journal", journal: makeJournal(), protocol: observer.PROTOCOL, requestId: request.requestId, result: "ok", runId: RUN_ID, schema: "cf7.audio-v2.qualification-response.v1" };
        return { status: 0, stderr: Buffer.alloc(0), stdout: Buffer.from(JSON.stringify(response, null, 2), "utf8") };
    };
    assert.throws(() => observer.requestPipe(options, "journal"), /one JSON record|canonical/);
});

test("collector carrier round-trips through the runner tracked argv decoder", () => {
    const observation = { a: 1, nested: { z: "candidate", b: true } };
    const argv = [process.execPath, "tools/audio-v2/qualification-runner.js", "--report-id", "fixture"].concat(observer.trackedObservationArguments(observation));
    assert.deepStrictEqual(runner.decodeConfigurationLiveObservation({ argv }), observation);
    const encoded = argv.slice(5).join("");
    const inflated = zlib.inflateRawSync(Buffer.from(encoded, "base64"));
    assert.ok(inflated.equals(runner.canonicalBytes(observation)));
});

test("tracked endpoint carrier archives the exact candidate journal and reconciles live replay", () => {
    const journal = makeBgmQualificationJournal();
    observer.validateJournal(journal, RUN_ID);
    const ranges = observer.validateCompletedJournal(journal);
    const exactCandidate = candidate();
    const derivationOptions = {
        candidateBuildIdentity: BUILD_IDENTITY,
        candidatePayloadClosure: PAYLOAD_CLOSURE,
        releaseSource: { commit: "a".repeat(40), treeOid: "b".repeat(40) },
        reportId: "exact_candidate_bgm_endpoint_e2e",
        sfxPerEntryVoiceCap: 4
    };
    const derived = observer.deriveLiveObservation(derivationOptions, { candidate: exactCandidate, journal, ranges });
    const archived = observer.validateJournalCarrier(derived.carrier);
    assert.strictEqual(archived.journal.sha256, journal.sha256);
    assert.strictEqual(archived.observation.reportId, derivationOptions.reportId);

    const argv = [process.execPath, "tools/audio-v2/qualification-runner.js", "--report-id", derivationOptions.reportId]
        .concat(observer.trackedObservationArguments(derived.carrier));
    assert.ok(argv.length <= 32, "realistic raw journal carrier exceeds the frozen argv bound");
    const decoded = runner.decodeConfigurationLiveObservation({ argv });
    assert.deepStrictEqual(decoded, derived.carrier, "archived carrier must parse without a live candidate process");
    assert.strictEqual(
        runner.reconcileEndpointJournalCarrier(derived.carrier, { candidate: exactCandidate, journal }, derivationOptions).derived.observation.reportId,
        derivationOptions.reportId);

    const hashTamper = JSON.parse(JSON.stringify(derived.carrier));
    hashTamper.journal.events[1].payload.runtime.deviceName = "tampered";
    assert.throws(() => observer.validateJournalCarrier(hashTamper), /event SHA-256 mismatch/);

    const observationTamper = JSON.parse(JSON.stringify(derived.carrier));
    observationTamper.observation.caseFacts[0].facts.cursorFrames++;
    assert.throws(
        () => runner.reconcileEndpointJournalCarrier(observationTamper, { candidate: exactCandidate, journal }, derivationOptions),
        /archived exact-candidate journal derivation/);

    const crossReport = JSON.parse(JSON.stringify(derived.carrier));
    crossReport.observation.reportId = "exact_candidate_sfx_endpoint_e2e";
    assert.throws(() => observer.validateJournalCarrier(crossReport), /caseFacts count mismatch|case order/);

    const extraGainCommand = JSON.parse(JSON.stringify(derived.carrier));
    const gainEndIndex = extraGainCommand.journal.events.findIndex((entry) =>
        entry.caseId === "gain_zero_and_default_max" && entry.kind === "case_end");
    const gainEnd = extraGainCommand.journal.events[gainEndIndex];
    const extraRequest = JSON.parse(JSON.stringify(extraGainCommand.journal.events.find((entry) =>
        entry.caseId === "gain_zero_and_default_max" && entry.kind === "as2_bgm_request")));
    const extraResult = JSON.parse(JSON.stringify(extraGainCommand.journal.events.find((entry) =>
        entry.caseId === "gain_zero_and_default_max" && entry.kind === "as2_bgm_result")));
    extraRequest.observedAtUtc = gainEnd.observedAtUtc;
    extraRequest.payload.operation = "stop";
    extraRequest.payload.requestId = "undeclared-stop";
    extraResult.observedAtUtc = gainEnd.observedAtUtc;
    extraResult.payload.operation = "stop";
    extraResult.payload.requestId = "undeclared-stop";
    extraGainCommand.journal.events.splice(gainEndIndex, 0, extraRequest, extraResult);
    rehashJournal(extraGainCommand.journal);
    assert.throws(() => observer.validateJournalCarrier(extraGainCommand), /BGM ingress operation\/count grammar mismatch/);

    const liveJournalDrift = JSON.parse(JSON.stringify(journal));
    const unrelated = liveJournalDrift.events.find((entry) => entry.caseId === "sfx_playback" && entry.kind === "qualification_snapshot");
    unrelated.payload.runtime.deviceName = "different-live-endpoint";
    rehashJournal(liveJournalDrift);
    assert.throws(
        () => runner.reconcileEndpointJournalCarrier(derived.carrier, { candidate: exactCandidate, journal: liveJournalDrift }, derivationOptions),
        /live journal differs/);
});

process.stdout.write("qualification-observer tests passed: " + passed + "\n");
