#!/usr/bin/env node
"use strict";

const assert = require("assert");
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

    await test("rejects path escape duplicate dense IDs and case grammar drift", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        expectThrow(() => request("bgm_playback", "play", {
            fadeSeconds: 0, loop: true, path: root + "Upper.MP3", volume: 1
        }, "2"), /qualification-only run root/);
        expectThrow(() => request("bgm_playback", "play", {
            fadeSeconds: 0, loop: true, path: root + "./bgm-primary.mp3", volume: 1
        }, "2"), /qualification-only run root/);
        expectThrow(() => request("dense_overlap_throttle", "sfx", {
            linkageIds: ["a", "b", "c", "d", "e", "e"]
        }, "3"), /frozen case grammar/);
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

    await test("all ten automated cases use markers snapshots exact stimuli and three captures", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        const plan = {
            bgm: {
                crossfade: { relativePath: root + "bgm-crossfade.mp3" },
                primary: { relativePath: root + "bgm-primary.mp3" }
            },
            fixtures: [
                { fixtureId: "aac-lc-mp4-tone-48000-mono", relativePath: root + "format-aac.m4a" },
                { fixtureId: "opus-ogg-tone-48000-mono", relativePath: root + "format-opus.opus" },
                { fixtureId: "vorbis-ogg-tone-48000-mono", relativePath: root + "format-vorbis.ogg" }
            ],
            sfx: Array.from({ length: 6 }, (_, index) => ({ linkageId: "sfx_" + index }))
        };
        const observations = [];
        const stimuli = [];
        const captures = [];
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
                return command === "snapshot"
                    ? {
                        command,
                        caseId,
                        snapshot: {
                            bgmMeter: { peakLeft: caseId === "sfx_playback" ? 0 : 0.25, peakRight: caseId === "sfx_playback" ? 0 : 0.25 },
                            runtime: Object.assign({}, runtime)
                        }
                    }
                    : { command, caseId };
            },
            requestStimulus(value) {
                stimuli.push(value);
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
            sleep(milliseconds) { waits.push(milliseconds); return Promise.resolve(); }
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
        assert.ok(observations.includes("snapshot:gain_zero_and_default_max"));
        assert.ok(waits.length >= 10);
    });

    await test("capture cases require readiness and exact runtime tuple binding", async () => {
        const root = "tmp/audio-v2-qualification/" + RUN_ID + "/fixtures/";
        const plan = {
            bgm: { crossfade: { relativePath: root + "b.mp3" }, primary: { relativePath: root + "a.mp3" } },
            fixtures: [],
            sfx: Array.from({ length: 6 }, (_, index) => ({ linkageId: "sfx_" + index }))
        };
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
