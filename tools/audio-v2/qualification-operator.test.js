#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

const operator = require("./qualification-operator.js");

const RUN_ID = "1".repeat(32);
const SHA_A = "A".repeat(64);
const SHA_B = "B".repeat(64);
const SHA_C = "C".repeat(64);
let passed = 0;

async function test(name, body) {
    await body();
    passed++;
    process.stdout.write("[PASS] " + name + "\n");
}

function expectThrow(body, pattern) {
    assert.throws(body, pattern);
}

function candidate() {
    return {
        buildIdentity: SHA_A,
        executablePath: "C:\\candidate\\runtime\\CRAZYFLASHER7MercenaryEmpire.Core.exe",
        executableSha256: SHA_B,
        payloadClosure: SHA_C,
        pid: 1234,
        processStartUtc: "2026-08-09T12:34:56.1234567Z"
    };
}

function qualifiedSfxPlan() {
    const sfx = Array.from({ length: 6 }, (_, index) => {
        const sourceFrameCount = index === 4 ? 146 : 114;
        const sourceSampleRate = 44100;
        const sourceTotalSamples = sourceFrameCount * 1152;
        return {
            linkageId: "sfx_" + index + ".wav",
            sourceBytes: index === 4 ? 60882 : 119016 + index,
            sourceDurationMs: Math.floor(sourceTotalSamples * 1000 / sourceSampleRate),
            sourceFrameCount,
            sourceSampleRate,
            sourceSha256: String(index + 1).repeat(64),
            sourceTotalSamples
        };
    });
    return {
        qualifiedLongSfx: {
            linkageId: sfx[4].linkageId,
            minimumDurationMs: 3000,
            sourceBytes: sfx[4].sourceBytes,
            sourceDurationMs: sfx[4].sourceDurationMs,
            sourceFrameCount: sfx[4].sourceFrameCount,
            sourceSampleRate: sfx[4].sourceSampleRate,
            sourceSha256: sfx[4].sourceSha256,
            sourceTotalSamples: sfx[4].sourceTotalSamples
        },
        sfx
    };
}

function responseFor(request) {
    const armed = request.command === "arm_recovery_sfx";
    return {
        candidate: candidate(),
        caseId: request.caseId,
        command: request.command,
        operation: request.operation,
        protocol: operator.STIMULUS_PROTOCOL,
        requestId: request.requestId,
        result: armed ? "armed" : "ok",
        runId: request.runId,
        schema: operator.STIMULUS_RESPONSE_SCHEMA,
        sent: !armed
    };
}

function request(caseId, operation, fields, digit) {
    return operator.buildStimulusRequest(RUN_ID, caseId, operation, fields, digit.repeat(32));
}

function readyRuntime() {
    return {
        audioReadyGeneration: 1,
        audioSessionId: "123e4567-e89b-42d3-a456-426614174000",
        backend: "wasapi",
        channels: 2,
        deviceGeneration: 1,
        deviceIdDigest: SHA_A,
        sampleFormat: "f32",
        sampleRate: 48000,
        status: "ready"
    };
}

function realCaptureConfiguration(runtime, captureId) {
    return {
        candidateBuildIdentity: SHA_A,
        candidatePayloadClosure: SHA_C,
        captureBytes: 384044,
        captureId,
        captureSha256: SHA_B,
        caseId: captureId,
        channels: runtime.channels,
        deviceIdDigest: runtime.deviceIdDigest,
        durationSeconds: 2,
        format: "pcm_s16le",
        recordedAtUtc: "2026-08-11T12:34:56.1234567Z",
        runId: RUN_ID,
        sampleRate: runtime.sampleRate,
        schema: "cf7.audio-v2.endpoint-capture-configuration.v1",
        selectedBackend: runtime.backend,
        tool: {
            blobOid: "a".repeat(40),
            path: "tools/audio-v2/capture-endpoint.ps1",
            sha256: SHA_C
        }
    };
}

function runAutomatedCliArgs(projectRoot, runId, captureOutputRoot) {
    return [
        "run-automated",
        "--project-root", projectRoot,
        "--run-id", runId,
        "--candidate-build-identity", SHA_A,
        "--candidate-payload-closure", SHA_C,
        "--candidate-pid", "1234",
        "--candidate-root", projectRoot,
        "--powershell", process.execPath,
        "--capture-backend", "wasapi",
        "--capture-device-digest", SHA_A,
        "--capture-endpoint-id", "test-endpoint",
        "--capture-output-root", captureOutputRoot
    ];
}

(async () => {
    await test("builds exact play seek gain and SFX request grammars", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        assert.deepStrictEqual(Object.keys(request("bgm_playback", "play", {
            fadeSeconds: 0,
            loop: true,
            path: root + "bgm-primary.mp3",
            volume: 1
        }, "2")), [
            "caseId", "command", "fadeSeconds", "loop", "operation", "path",
            "protocol", "requestId", "runId", "volume"
        ]);
        assert.strictEqual(request("bgm_seek", "seek", { seekSeconds: 0.25 }, "3").seekSeconds, 0.25);
        assert.strictEqual(request("gain_zero_and_default_max", "set_gain", { volume: 0 }, "4").volume, 0);
        assert.strictEqual(request("sfx_playback", "sfx", { linkageIds: ["one"] }, "5").command, "dispatch");
        const armed = request("no_stale_sfx_after_recovery", "sfx", { linkageIds: ["one"] }, "6");
        assert.strictEqual(armed.command, "arm_recovery_sfx");
        const restore = request("post_gain_restore", "set_gain", { volume: 1 }, "7");
        assert.strictEqual(restore.command, "post_gain_restore");
        assert.strictEqual(request("pre_sfx_bgm_mute", "set_gain", { volume: 0 }, "8").command, "pre_sfx_bgm_mute");
        assert.strictEqual(request("pre_mix_bgm_restore", "set_gain", { volume: 1 }, "9").command, "pre_mix_bgm_restore");
    });

    await test("rejects path escape non-identical dense IDs and case grammar drift", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        expectThrow(() => request("bgm_playback", "play", {
            fadeSeconds: 0, loop: true, path: root + "Upper.MP3", volume: 1
        }, "2"), /qualification-only run root/);
        expectThrow(() => request("bgm_playback", "play", {
            fadeSeconds: 0, loop: true, path: root + "./bgm-primary.mp3", volume: 1
        }, "2"), /qualification-only run root/);
        expectThrow(() => request("dense_overlap_throttle", "sfx", {
            linkageIds: ["a", "a", "a", "a", "a", "b"]
        }, "3"), /frozen case grammar/);
        assert.deepStrictEqual(request("dense_overlap_throttle", "sfx", {
            linkageIds: ["a", "a", "a", "a", "a", "a"]
        }, "4").linkageIds, ["a", "a", "a", "a", "a", "a"]);
        expectThrow(() => request("sfx_playback", "sfx", {
            linkageIds: ["bad/path"]
        }, "3"), /linkageId invalid/);
        expectThrow(() => request("format_vorbis", "play", {
            fadeSeconds: 1, loop: true, path: root + "format-vorbis.ogg", volume: 1
        }, "4"), /frozen case grammar/);
        expectThrow(() => request("pre_sfx_bgm_mute", "set_gain", { volume: 1 }, "5"), /frozen case grammar/);
        expectThrow(() => request("pre_mix_bgm_restore", "set_gain", { volume: 0 }, "6"), /frozen case grammar/);
    });

    await test("validates exact normal and recovery-arm response semantics", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        const play = request("bgm_playback", "play", {
            fadeSeconds: 0, loop: true, path: root + "bgm-primary.mp3", volume: 1
        }, "2");
        assert.strictEqual(operator.validateStimulusResponse(responseFor(play), play, candidate()).sent, true);
        const armed = request("no_stale_sfx_after_recovery", "sfx", { linkageIds: ["one"] }, "3");
        assert.strictEqual(operator.validateStimulusResponse(responseFor(armed), armed, candidate()).result, "armed");
        const bad = responseFor(play);
        bad.sent = false;
        expectThrow(() => operator.validateStimulusResponse(bad, play, candidate()), /result\/sent/);
        const wrongCandidate = responseFor(play);
        wrongCandidate.candidate.pid++;
        expectThrow(() => operator.validateStimulusResponse(wrongCandidate, play, candidate()), /exact candidate/);
    });

    await test("stimulus transport binds exact pipe PID request bytes and canonical response", async () => {
        const root = path.resolve(__dirname, "..", "..");
        const built = request("sfx_playback", "sfx", { linkageIds: ["one"] }, "7");
        const result = operator.requestStimulus({
            expectedCandidate: candidate(),
            powershell: "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
            projectRoot: root,
            runId: RUN_ID,
            spawnSync(executable, args, options) {
                assert.strictEqual(executable.toLowerCase().endsWith("powershell.exe"), true);
                assert.ok(args.includes("cf7-audio-v2-qualification-stimulus-1234-" + RUN_ID));
                assert.deepStrictEqual(options.input, operator.canonicalBytes(built));
                return {
                    status: 0,
                    stdout: operator.canonicalBytes(responseFor(built)),
                    stderr: Buffer.alloc(0)
                };
            }
        }, built);
        assert.strictEqual(result.result, "ok");
    });

    await test("capture configuration accepts only tracked pretty artifact canonical bytes", async () => {
        const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-operator-capture-"));
        const configurationPath = path.join(temporaryRoot, "bgm_playback.configuration.v1.json");
        const runtime = readyRuntime();
        const value = realCaptureConfiguration(runtime, "bgm_playback");
        const pretty = operator.trackedArtifactCanonicalBytes(value);
        try {
            fs.writeFileSync(configurationPath, pretty);
            assert.deepStrictEqual(
                operator.readCaptureConfiguration({ configuration: configurationPath }),
                value);
            assert.strictEqual(pretty.toString("utf8").endsWith("\n"), true);
            assert.strictEqual(pretty.toString("utf8").includes("\n  \"candidateBuildIdentity\""), true);
            assert.strictEqual(operator.canonicalBytes(value).includes(0x0a), false);

            fs.writeFileSync(configurationPath, operator.canonicalBytes(value));
            expectThrow(
                () => operator.readCaptureConfiguration({ configuration: configurationPath }),
                /canonical sorted JSON with two-space indent and terminal LF/);

            fs.writeFileSync(configurationPath, Buffer.from(pretty.toString("utf8").replace(/\n/g, "\r\n"), "utf8"));
            expectThrow(
                () => operator.readCaptureConfiguration({ configuration: configurationPath }),
                /canonical sorted JSON with two-space indent and terminal LF/);

            const reversed = {};
            Object.keys(value).reverse().forEach((key) => { reversed[key] = value[key]; });
            fs.writeFileSync(configurationPath, Buffer.from(JSON.stringify(reversed, null, 2) + "\n", "utf8"));
            expectThrow(
                () => operator.readCaptureConfiguration({ configuration: configurationPath }),
                /canonical sorted JSON with two-space indent and terminal LF/);

            const tampered = Object.assign({}, value, { channels: 1 });
            fs.writeFileSync(configurationPath, operator.trackedArtifactCanonicalBytes(tampered));
            expectThrow(
                () => operator.validateCaptureRuntimeBinding(
                    { configuration: configurationPath }, runtime, "bgm_playback"),
                /does not bind its ready runtime tuple/);
        } finally {
            fs.rmSync(temporaryRoot, { force: true, recursive: true });
        }
    });

    await test("automated capture binding consumes the real pretty configuration artifact", async () => {
        const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-operator-lane-"));
        const configurationPath = path.join(temporaryRoot, "bgm_playback.configuration.v1.json");
        const fixtureRoot = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        const runtime = readyRuntime();
        const plan = Object.assign({
            bgm: {
                crossfade: { relativePath: fixtureRoot + "bgm-crossfade.mp3" },
                primary: { relativePath: fixtureRoot + "bgm-primary.mp3" }
            },
            fixtures: []
        }, qualifiedSfxPlan());
        fs.writeFileSync(
            configurationPath,
            operator.trackedArtifactCanonicalBytes(realCaptureConfiguration(runtime, "bgm_playback")));
        try {
            const transcript = await operator.runAutomatedCase({
                runId: RUN_ID,
                timing: { playObservationMs: 0 },
                observe(command, caseId) {
                    return command === "snapshot"
                        ? { command, caseId, snapshot: { bgmMeter: { peakLeft: 0.25, peakRight: 0.25 }, runtime } }
                        : { command, caseId };
                },
                requestStimulus: responseFor,
                sleep() { return Promise.resolve(); },
                startCapture(caseId, captureId) {
                    return {
                        captureId,
                        ready: Promise.resolve(),
                        completion: Promise.resolve({ captureId, configuration: configurationPath })
                    };
                }
            }, plan, "bgm_playback");
            assert.strictEqual(transcript.captures.length, 1);
            assert.strictEqual(transcript.captures[0].configuration, configurationPath);
        } finally {
            fs.rmSync(temporaryRoot, { force: true, recursive: true });
        }
    });

    await test("all ten automated cases use markers snapshots exact stimuli and three captures", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        const plan = Object.assign({
            bgm: {
                crossfade: { relativePath: root + "bgm-crossfade.mp3" },
                primary: { relativePath: root + "bgm-primary.mp3" }
            },
            fixtures: [
                { fixtureId: "aac-lc-mp4-tone-48000-mono", relativePath: root + "format-aac.m4a" },
                { fixtureId: "opus-ogg-tone-48000-mono", relativePath: root + "format-opus.opus" },
                { fixtureId: "vorbis-ogg-tone-48000-mono", relativePath: root + "format-vorbis.ogg" }
            ]
        }, qualifiedSfxPlan());
        const observations = [];
        const stimuli = [];
        const captures = [];
        const timeline = [];
        const waits = [];
        const runtime = {
            audioReadyGeneration: 1,
            audioSessionId: "123e4567-e89b-42d3-a456-426614174000",
            backend: "wasapi",
            channels: 2,
            deviceGeneration: 1,
            deviceIdDigest: SHA_A,
            sampleFormat: "f32",
            sampleRate: 48000,
            status: "ready"
        };
        const options = {
            runId: RUN_ID,
            timing: {
                betweenCaseControlDrainMs: 0,
                controlObservationMs: 0,
                crossfadeSampleMs: 0,
                formatObservationMs: 0,
                playObservationMs: 0,
                postGainRestoreDrainMs: 0,
                seekPreconditionMs: 0,
                sfxSampleMs: 0
            },
            observe(command, caseId) {
                observations.push(command + ":" + caseId);
                timeline.push("observe:" + command + ":" + caseId);
                return command === "snapshot"
                    ? {
                        command,
                        caseId,
                        snapshot: {
                            bgmMeter: { peakLeft: caseId === "sfx_playback" ? 0 : 0.25, peakRight: caseId === "sfx_playback" ? 0 : 0.25 },
                            sfxMeter: { peakLeft: 0, peakRight: 0 },
                            runtime: Object.assign({}, runtime)
                        }
                    }
                    : { command, caseId };
            },
            requestStimulus(value) {
                stimuli.push(value);
                timeline.push("stimulus:" + value.caseId);
                return responseFor(value);
            },
            startCapture(caseId, captureId) {
                captures.push(caseId + ":" + captureId);
                return {
                    captureId,
                    ready: Promise.resolve(),
                    completion: Promise.resolve({
                        captureId,
                        configurationValue: {
                            captureId,
                            caseId: captureId,
                            channels: runtime.channels,
                            deviceIdDigest: runtime.deviceIdDigest,
                            format: "pcm_s16le",
                            sampleRate: runtime.sampleRate,
                            selectedBackend: runtime.backend
                        }
                    })
                };
            },
            sleep(milliseconds) {
                waits.push(milliseconds);
                timeline.push("wait:" + milliseconds);
                return Promise.resolve();
            }
        };
        const lane = await operator.runAutomatedLane(options, plan);
        assert.strictEqual(lane.cases.length, operator.AUTOMATED_CASES.length);
        assert.strictEqual(observations[observations.length - 1], "end_case:gain_zero_and_default_max");
        assert.strictEqual(stimuli.length, 14);
        assert.deepStrictEqual(stimuli.filter((entry) => entry.command.startsWith("pre_")).map((entry) => entry.command), [
            "pre_sfx_bgm_mute", "pre_mix_bgm_restore"
        ]);
        assert.deepStrictEqual(captures, [
            "bgm_playback:bgm_playback",
            "sfx_playback:sfx_playback",
            "bgm_sfx_mix:bgm_sfx_mix"
        ]);
        assert.deepStrictEqual(
            stimuli.find((entry) => entry.caseId === "dense_overlap_throttle").linkageIds,
            ["sfx_4.wav", "sfx_4.wav", "sfx_4.wav", "sfx_4.wav", "sfx_4.wav", "sfx_4.wav"]);
        assert.deepStrictEqual(
            ["sfx_playback", "bgm_sfx_mix"].map((caseId) =>
                stimuli.find((entry) => entry.caseId === caseId).linkageIds),
            [["sfx_4.wav"], ["sfx_4.wav"]]);
        assert.ok(observations.includes("snapshot:gain_zero_and_default_max"));
        assert.ok(waits.length >= 10);
        assert.strictEqual(operator.qualifiedSfxDrainMs(plan), 4063);
        const restoreIndex = timeline.indexOf("stimulus:pre_mix_bgm_restore");
        assert.deepStrictEqual(timeline.slice(restoreIndex, restoreIndex + 3), [
            "stimulus:pre_mix_bgm_restore",
            "wait:4063",
            "observe:begin_case:bgm_sfx_mix"
        ]);
    });

    await test("mix refuses a residual-SFX baseline before capture or fresh dispatch", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        const plan = Object.assign({
            bgm: { crossfade: { relativePath: root + "b.mp3" }, primary: { relativePath: root + "a.mp3" } },
            fixtures: []
        }, qualifiedSfxPlan());
        const runtime = readyRuntime();
        let dispatched = 0;
        await assert.rejects(() => operator.runAutomatedCase({
            runId: RUN_ID,
            timing: { sfxSampleMs: 0 },
            observe(command, caseId) {
                return command === "snapshot" ? {
                    caseId,
                    command,
                    snapshot: {
                        bgmMeter: { peakLeft: 0.25, peakRight: 0.25 },
                        runtime,
                        sfxMeter: { peakLeft: 0.25, peakRight: 0.25 }
                    }
                } : { caseId, command };
            },
            requestStimulus() { dispatched++; },
            startCapture() { throw new Error("capture must not start on residual SFX"); }
        }, plan, "bgm_sfx_mix"), /residual SFX remains audible/);
        assert.strictEqual(dispatched, 0);
    });

    await test("capture cases require readiness and exact runtime tuple binding", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        const plan = Object.assign({
            bgm: { crossfade: { relativePath: root + "b.mp3" }, primary: { relativePath: root + "a.mp3" } },
            fixtures: []
        }, qualifiedSfxPlan());
        const runtime = {
            audioReadyGeneration: 1,
            audioSessionId: "123e4567-e89b-42d3-a456-426614174000",
            backend: "wasapi",
            channels: 2,
            deviceGeneration: 1,
            deviceIdDigest: SHA_A,
            sampleFormat: "f32",
            sampleRate: 48000,
            status: "ready"
        };
        const base = {
            runId: RUN_ID,
            timing: { playObservationMs: 0 },
            observe(command, caseId) {
                return command === "snapshot"
                    ? { command, caseId, snapshot: { bgmMeter: { peakLeft: 0.25, peakRight: 0.25 }, runtime } }
                    : { command, caseId };
            },
            requestStimulus: responseFor,
            sleep() { return Promise.resolve(); }
        };
        await assert.rejects(
            () => operator.runAutomatedCase(Object.assign({}, base, {
                startCapture() { return { completion: Promise.resolve({}) }; }
            }), plan, "bgm_playback"),
            /readiness handshake/);
        await assert.rejects(
            () => operator.runAutomatedCase(Object.assign({}, base, {
                startCapture(caseId, captureId) {
                    return {
                        ready: Promise.resolve(),
                        completion: Promise.resolve({
                            configurationValue: {
                                captureId,
                                caseId: captureId,
                                channels: 1,
                                deviceIdDigest: runtime.deviceIdDigest,
                                format: "pcm_s16le",
                                sampleRate: runtime.sampleRate,
                                selectedBackend: runtime.backend
                            }
                        })
                    };
                }
            }), plan, "bgm_playback"),
            /does not bind its ready runtime tuple/);
    });

    await test("prepare and run-automated bind one exclusive canonical capture directory", async () => {
        const projectRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-operator-prepare-"));
        try {
            const captureDirectory = operator.prepareCaptureDirectory(projectRoot, RUN_ID);
            assert.strictEqual(captureDirectory, path.join(
                projectRoot, "tmp", "audio-v2-qualification", RUN_ID, "captures"));
            assert.deepStrictEqual(fs.readdirSync(captureDirectory), []);
            const parsed = operator.parseCli(runAutomatedCliArgs(projectRoot, RUN_ID, captureDirectory));
            assert.strictEqual(parsed.capture.outputRoot, captureDirectory);
            expectThrow(() => operator.prepareCaptureDirectory(projectRoot, RUN_ID), /run root already exists/);

            const publishedCapture = path.join(captureDirectory, "bgm_playback.wav");
            fs.writeFileSync(publishedCapture, "do not touch", { encoding: "utf8", flag: "wx" });
            expectThrow(() => operator.prepareCaptureDirectory(projectRoot, RUN_ID), /run root already exists/);
            expectThrow(() => operator.parseCli(runAutomatedCliArgs(projectRoot, RUN_ID, captureDirectory)),
                /must be initially empty/);
            await assert.rejects(() => operator.runAutomatedLane({
                capture: { outputRoot: captureDirectory },
                projectRoot,
                runId: RUN_ID
            }, { bgm: {}, fixtures: [], sfx: [] }), /must be initially empty/);
            assert.strictEqual(operator.validateCaptureDirectory(projectRoot, RUN_ID, captureDirectory, false),
                captureDirectory);
            assert.strictEqual(fs.readFileSync(publishedCapture, "utf8"), "do not touch");

            const oldRunId = "2".repeat(32);
            const oldRunRoot = path.join(projectRoot, "tmp", "audio-v2-qualification", oldRunId);
            fs.mkdirSync(oldRunRoot);
            const oldMarker = path.join(oldRunRoot, "marker.txt");
            fs.writeFileSync(oldMarker, "old", { encoding: "utf8", flag: "wx" });
            expectThrow(() => operator.prepareCaptureDirectory(projectRoot, oldRunId), /run root already exists/);
            assert.strictEqual(fs.readFileSync(oldMarker, "utf8"), "old");
            assert.ok(!fs.existsSync(path.join(oldRunRoot, "captures")));
            expectThrow(() => operator.parseCli(runAutomatedCliArgs(projectRoot, oldRunId, captureDirectory)),
                /exact qualification run captures directory/);

            const wrongDirectory = path.join(projectRoot, "wrong-captures");
            fs.mkdirSync(wrongDirectory);
            expectThrow(() => operator.parseCli(runAutomatedCliArgs(projectRoot, RUN_ID, wrongDirectory)),
                /exact qualification run captures directory/);

            const linkedRunId = "3".repeat(32);
            const linkedRunRoot = path.join(projectRoot, "tmp", "audio-v2-qualification", linkedRunId);
            const linkTarget = path.join(projectRoot, "capture-link-target");
            fs.mkdirSync(linkedRunRoot);
            fs.mkdirSync(linkTarget);
            const linkedCaptureDirectory = path.join(linkedRunRoot, "captures");
            fs.symlinkSync(linkTarget, linkedCaptureDirectory, process.platform === "win32" ? "junction" : "dir");
            expectThrow(() => operator.parseCli(runAutomatedCliArgs(
                projectRoot, linkedRunId, linkedCaptureDirectory)), /reparse\/symlink|canonical real storage/);
        } finally {
            fs.rmSync(projectRoot, { force: true, recursive: true });
        }
    });

    await test("qualified long SFX binding rejects plan tamper and all-short fixture sets", async () => {
        const valid = qualifiedSfxPlan();
        assert.strictEqual(operator.validateQualifiedLongSfx(valid).linkageId, "sfx_4.wav");

        const tampered = qualifiedSfxPlan();
        tampered.qualifiedLongSfx.sourceDurationMs++;
        expectThrow(() => operator.validateQualifiedLongSfx(tampered), /differs from deterministic materializer selection/);

        const short = qualifiedSfxPlan();
        short.sfx[4].sourceFrameCount = 114;
        short.sfx[4].sourceTotalSamples = 114 * 1152;
        short.sfx[4].sourceDurationMs = Math.floor(short.sfx[4].sourceTotalSamples * 1000 / 44100);
        expectThrow(() => operator.validateQualifiedLongSfx(short), /no qualified long sample/);
    });

    await test("CLI keeps preparation separate from candidate execution and human gate", async () => {
        const root = path.resolve(__dirname, "..", "..");
        const prepared = operator.parseCli(["prepare", "--project-root", root, "--run-id", RUN_ID]);
        assert.strictEqual(prepared.command, "prepare");
        expectThrow(() => operator.parseCli([
            "prepare", "--project-root", root, "--run-id", RUN_ID,
            "--candidate-pid", "1"
        ]), /prepare accepts only/);
        assert.deepStrictEqual(operator.MANUAL_CASES, [
            "default_device_switch",
            "physical_route_bluetooth_or_hdmi",
            "sleep_resume",
            "no_stale_sfx_after_recovery"
        ]);
    });

    process.stdout.write("qualification operator tests passed: " + passed + "\n");
})().catch((error) => {
    process.stderr.write((error && error.stack ? error.stack : String(error)) + "\n");
    process.exitCode = 1;
});
