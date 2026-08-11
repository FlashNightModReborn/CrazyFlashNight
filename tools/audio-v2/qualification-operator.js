#!/usr/bin/env node
"use strict";

// Human-gated Audio v2 qualification operator.
//
// The automated lane is deliberately limited to the first ten cases whose
// stimuli can enter through the real AS2 -> XMLSocket -> AudioTask path.  The
// remaining device-switch, route, sleep and recovery actions are marker-only
// human steps.  This tool never changes the OS default endpoint, sleeps the
// machine, signs evidence, or authorizes promotion.

const cp = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const observer = require("./qualification-observer.js");
const fixtures = require("./materialize-qualification-fixtures.js");

const STIMULUS_PROTOCOL = "cf7.audio-v2.qualification-stimulus-pipe.v1";
const STIMULUS_RESPONSE_SCHEMA = "cf7.audio-v2.qualification-stimulus-response.v1";
const STIMULUS_CLIENT = "tools/audio-v2/qualification-stimulus-client.ps1";
const CAPTURE_TOOL = "tools/audio-v2/capture-endpoint.ps1";
const MAX_STIMULUS_RESPONSE_BYTES = 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 5000;
const CAPTURE_READY_TOKEN = "CF7_AUDIO_V2_CAPTURE_READY_V1\n";
const AUTOMATED_CASES = Object.freeze([
    "bgm_playback",
    "bgm_seek",
    "bgm_crossfade",
    "format_vorbis",
    "format_aac_mp4",
    "format_opus",
    "sfx_playback",
    "dense_overlap_throttle",
    "bgm_sfx_mix",
    "gain_zero_and_default_max"
]);
const MANUAL_CASES = Object.freeze([
    "default_device_switch",
    "physical_route_bluetooth_or_hdmi",
    "sleep_resume",
    "no_stale_sfx_after_recovery"
]);
const CAPTURE_CASES = Object.freeze({
    bgm_playback: "bgm_playback",
    bgm_sfx_mix: "bgm_sfx_mix",
    sfx_playback: "sfx_playback"
});

class QualificationOperatorError extends Error {
    constructor(code, message) {
        super(message);
        this.name = "QualificationOperatorError";
        this.code = code;
    }
}

function fail(code, message) {
    throw new QualificationOperatorError(code, message);
}

function expect(condition, message, code) {
    if (!condition) fail(code || "VALIDATION_FAILED", message);
}

function exactKeys(value, expected, label) {
    expect(value && typeof value === "object" && !Array.isArray(value), label + " must be an object");
    expect(JSON.stringify(Object.keys(value).sort()) === JSON.stringify(expected.slice().sort()), label + " keys mismatch");
}

function expectSha(value, label) {
    expect(typeof value === "string" && /^[A-F0-9]{64}$/.test(value), label + " must be uppercase SHA-256");
}

function expectRunId(value, label) {
    expect(typeof value === "string" && /^[0-9a-f]{32}$/.test(value), label + " must be 32 lowercase hex");
}

function expectRequestId(value, label) {
    expectRunId(value, label);
}

function expectFinite(value, label, minimum, maximum) {
    expect(typeof value === "number" && Number.isFinite(value), label + " must be finite");
    if (minimum !== undefined) expect(value >= minimum, label + " is below its minimum");
    if (maximum !== undefined) expect(value <= maximum, label + " exceeds its maximum");
}

function sha256(bytes) {
    return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
}

function canonicalBytes(value) {
    return observer.canonicalBytes(value);
}

function trackedArtifactSortedClone(value) {
    if (Array.isArray(value)) return value.map(trackedArtifactSortedClone);
    if (value && typeof value === "object") {
        const result = {};
        Object.keys(value).sort().forEach((key) => {
            result[key] = trackedArtifactSortedClone(value[key]);
        });
        return result;
    }
    return value;
}

function trackedArtifactCanonicalBytes(value) {
    return Buffer.from(JSON.stringify(trackedArtifactSortedClone(value), null, 2) + "\n", "utf8");
}

function inspectCandidate(options, spawnSync) {
    expect(options && typeof options === "object", "candidate options missing");
    expect(path.isAbsolute(options.candidateRoot) && fs.lstatSync(options.candidateRoot).isDirectory(), "candidate root invalid");
    expectSha(options.candidateBuildIdentity, "candidate build identity");
    expectSha(options.candidatePayloadClosure, "candidate payload closure");
    expect(Number.isSafeInteger(options.candidatePid) && options.candidatePid > 0, "candidate PID invalid");
    expect(path.isAbsolute(options.powershell) && fs.lstatSync(options.powershell).isFile(), "PowerShell path invalid");

    const script = "$ErrorActionPreference='Stop';$p=Get-Process -Id " + options.candidatePid + " -ErrorAction Stop;" +
        "[ordered]@{id=$p.Id;path=$p.Path;startUtc=$p.StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')}|ConvertTo-Json -Compress";
    const executed = (spawnSync || cp.spawnSync)(options.powershell, [
        "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script
    ], {
        encoding: "utf8",
        maxBuffer: 1024 * 1024,
        timeout: 15000,
        windowsHide: true
    });
    if (executed.error || executed.status !== 0) fail("PREREQUISITE_MISSING", "candidate process is not inspectable");
    let processValue;
    try { processValue = JSON.parse(executed.stdout); }
    catch (error) { fail("VALIDATION_FAILED", "candidate process inspection returned invalid JSON"); }

    const expectedExecutable = fs.realpathSync.native(path.join(
        options.candidateRoot,
        "runtime",
        "CRAZYFLASHER7MercenaryEmpire.Core.exe"));
    const actualExecutable = fs.realpathSync.native(processValue.path);
    expect(processValue.id === options.candidatePid &&
        actualExecutable.toLowerCase() === expectedExecutable.toLowerCase(),
    "candidate process image differs from the exact candidate root");
    expect(typeof processValue.startUtc === "string" &&
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$/.test(processValue.startUtc),
    "candidate process start time is not canonical UTC");
    return {
        buildIdentity: options.candidateBuildIdentity,
        executablePath: actualExecutable,
        executableSha256: sha256(fs.readFileSync(expectedExecutable)),
        payloadClosure: options.candidatePayloadClosure,
        pid: options.candidatePid,
        processStartUtc: processValue.startUtc
    };
}

function validateCandidate(value, expected, label) {
    exactKeys(value, [
        "buildIdentity", "executablePath", "executableSha256",
        "payloadClosure", "pid", "processStartUtc"
    ], label);
    expect(value.buildIdentity === expected.buildIdentity &&
        value.executablePath.toLowerCase() === expected.executablePath.toLowerCase() &&
        value.executableSha256 === expected.executableSha256 &&
        value.payloadClosure === expected.payloadClosure &&
        value.pid === expected.pid &&
        Date.parse(value.processStartUtc) === Date.parse(expected.processStartUtc),
    label + " differs from the exact candidate");
    return value;
}

function qualificationPath(runId, relativePath) {
    expectRunId(runId, "stimulus runId");
    expect(typeof relativePath === "string" && relativePath.length <= 1024 &&
        /^[a-z0-9._\/-]+$/.test(relativePath) &&
        relativePath.startsWith("tmp/audio-v2-qualification/" + runId + "/") &&
        !relativePath.includes("//") &&
        !relativePath.split("/").includes(".") &&
        !relativePath.split("/").includes(".."),
    "stimulus path is outside the qualification-only run root");
    return relativePath;
}

function buildStimulusRequest(runId, caseId, operation, fields, requestId) {
    expectRunId(runId, "stimulus runId");
    expectRequestId(requestId, "stimulus requestId");
    expect(AUTOMATED_CASES.includes(caseId) ||
        caseId === "no_stale_sfx_after_recovery" ||
        caseId === "post_gain_restore" ||
        caseId === "pre_sfx_bgm_mute" ||
        caseId === "pre_mix_bgm_restore", "stimulus case is not dispatchable");
    expect(fields && typeof fields === "object" && !Array.isArray(fields), "stimulus fields missing");

    let request;
    if (operation === "play") {
        exactKeys(fields, ["fadeSeconds", "loop", "path", "volume"], "play stimulus fields");
        expectFinite(fields.fadeSeconds, "play fadeSeconds", 0, 60);
        expect(typeof fields.loop === "boolean", "play loop must be boolean");
        qualificationPath(runId, fields.path);
        expectFinite(fields.volume, "play volume", 0, 1);
        request = {
            caseId,
            command: "dispatch",
            fadeSeconds: fields.fadeSeconds,
            loop: fields.loop,
            operation,
            path: fields.path,
            protocol: STIMULUS_PROTOCOL,
            requestId,
            runId,
            volume: fields.volume
        };
    } else if (operation === "seek") {
        exactKeys(fields, ["seekSeconds"], "seek stimulus fields");
        expectFinite(fields.seekSeconds, "seekSeconds", 0.001, 86400);
        request = {
            caseId,
            command: "dispatch",
            operation,
            protocol: STIMULUS_PROTOCOL,
            requestId,
            runId,
            seekSeconds: fields.seekSeconds
        };
    } else if (operation === "set_gain") {
        exactKeys(fields, ["volume"], "gain stimulus fields");
        expectFinite(fields.volume, "gain volume", 0, 1);
        request = {
            caseId,
            command: ["post_gain_restore", "pre_sfx_bgm_mute", "pre_mix_bgm_restore"].includes(caseId)
                ? caseId : "dispatch",
            operation,
            protocol: STIMULUS_PROTOCOL,
            requestId,
            runId,
            volume: fields.volume
        };
    } else if (operation === "sfx") {
        exactKeys(fields, ["linkageIds"], "SFX stimulus fields");
        expect(Array.isArray(fields.linkageIds) && fields.linkageIds.length >= 1 && fields.linkageIds.length <= 64,
            "SFX linkageIds count invalid");
        fields.linkageIds.forEach((entry) => expect(typeof entry === "string" &&
            entry.length >= 1 && entry.length <= 128 && entry.trim().length > 0 &&
            !entry.includes("|") && !entry.includes("/") && !entry.includes("\\") &&
            entry !== "." && entry !== ".." &&
            !Array.from(entry).some((character) => /\p{Cc}/u.test(character)),
        "SFX linkageId invalid"));
        request = {
            caseId,
            command: caseId === "no_stale_sfx_after_recovery" ? "arm_recovery_sfx" : "dispatch",
            linkageIds: fields.linkageIds.slice(),
            operation,
            protocol: STIMULUS_PROTOCOL,
            requestId,
            runId
        };
    } else fail("VALIDATION_FAILED", "unknown qualification stimulus operation");

    const grammar = {
        bgm_playback: () => operation === "play" && request.fadeSeconds === 0 && request.loop && request.volume === 1,
        bgm_seek: () => operation === "seek" && request.seekSeconds > 0,
        bgm_crossfade: () => operation === "play" && request.fadeSeconds > 0 && request.loop && request.volume === 1,
        format_vorbis: () => operation === "play" && request.fadeSeconds === 0 && request.loop && request.volume === 1,
        format_aac_mp4: () => operation === "play" && request.fadeSeconds === 0 && request.loop && request.volume === 1,
        format_opus: () => operation === "play" && request.fadeSeconds === 0 && request.loop && request.volume === 1,
        sfx_playback: () => operation === "sfx" && request.linkageIds.length === 1,
        dense_overlap_throttle: () => operation === "sfx" && request.linkageIds.length === 6 && new Set(request.linkageIds).size === 6,
        bgm_sfx_mix: () => operation === "sfx" && request.linkageIds.length === 1,
        gain_zero_and_default_max: () => operation === "set_gain" && (request.volume === 0 || request.volume === 1),
        no_stale_sfx_after_recovery: () => operation === "sfx" && request.linkageIds.length === 1,
        post_gain_restore: () => operation === "set_gain" && request.volume === 1 && request.command === "post_gain_restore",
        pre_sfx_bgm_mute: () => operation === "set_gain" && request.volume === 0 && request.command === "pre_sfx_bgm_mute",
        pre_mix_bgm_restore: () => operation === "set_gain" && request.volume === 1 && request.command === "pre_mix_bgm_restore"
    };
    expect(grammar[caseId](), "stimulus request differs from the frozen case grammar");
    expect(canonicalBytes(request).length <= 65536, "stimulus request exceeds the pipe byte bound");
    return request;
}

function validateStimulusResponse(value, request, expectedCandidate) {
    exactKeys(value, [
        "candidate", "caseId", "command", "operation", "protocol",
        "requestId", "result", "runId", "schema", "sent"
    ], "stimulus response");
    expect(value.caseId === request.caseId && value.command === request.command &&
        value.operation === request.operation && value.protocol === STIMULUS_PROTOCOL &&
        value.requestId === request.requestId && value.runId === request.runId &&
        value.schema === STIMULUS_RESPONSE_SCHEMA,
    "stimulus response correlation differs from its request");
    const armed = request.command === "arm_recovery_sfx";
    expect(value.result === (armed ? "armed" : "ok") && value.sent === !armed,
        "stimulus response result/sent state invalid");
    validateCandidate(value.candidate, expectedCandidate, "stimulus response candidate");
    return value;
}

function requestStimulus(options, request) {
    const clientPath = path.resolve(options.projectRoot, ...STIMULUS_CLIENT.split("/"));
    expect(fs.lstatSync(clientPath).isFile(), "qualification stimulus client missing");
    const requestBytes = canonicalBytes(request);
    const args = [
        "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", clientPath,
        "-PipeName", "cf7-audio-v2-qualification-stimulus-" + options.expectedCandidate.pid + "-" + options.runId,
        "-ExpectedServerPid", String(options.expectedCandidate.pid),
        "-RequestFromStdin",
        "-TimeoutMilliseconds", String(options.timeoutMs || DEFAULT_TIMEOUT_MS)
    ];
    const executed = (options.spawnSync || cp.spawnSync)(options.powershell, args, {
        encoding: null,
        input: requestBytes,
        maxBuffer: MAX_STIMULUS_RESPONSE_BYTES + 65536,
        timeout: (options.timeoutMs || DEFAULT_TIMEOUT_MS) + 2000,
        windowsHide: true
    });
    if (executed.error || executed.status !== 0) {
        const detail = Buffer.isBuffer(executed.stderr) ? executed.stderr.toString("utf8") : String(executed.stderr || "");
        fail("PREREQUISITE_MISSING", "stimulus pipe request failed: " + detail.replace(/[\r\n]+/g, " ").slice(0, 1000));
    }
    const stderr = Buffer.isBuffer(executed.stderr) ? executed.stderr : Buffer.from(executed.stderr || "", "utf8");
    const stdout = Buffer.isBuffer(executed.stdout) ? executed.stdout : Buffer.from(executed.stdout || "", "utf8");
    expect(stderr.length === 0, "stimulus pipe client produced stderr");
    expect(stdout.length >= 2 && stdout.length <= MAX_STIMULUS_RESPONSE_BYTES &&
        !stdout.includes(0x0a) && !stdout.includes(0x0d), "stimulus pipe stdout framing invalid");
    let response;
    try { response = JSON.parse(stdout.toString("utf8")); }
    catch (error) { fail("VALIDATION_FAILED", "stimulus pipe response is not JSON"); }
    expect(canonicalBytes(response).equals(stdout), "stimulus pipe response is not canonical JSON");
    return validateStimulusResponse(response, request, options.expectedCandidate);
}

function sleep(milliseconds) {
    return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function readPlan(projectRoot, runId) {
    const planPath = path.join(projectRoot, "tmp", "audio-v2-qualification", runId, "fixtures", "stimulus-plan.v1.json");
    const bytes = fs.readFileSync(planPath);
    let value;
    try { value = JSON.parse(bytes.toString("utf8")); }
    catch (error) { fail("VALIDATION_FAILED", "stimulus plan is not JSON"); }
    expect(fixtures.canonicalBytes(value).equals(bytes), "stimulus plan is not canonical JSON");
    const recomputed = fixtures.materializeFixtures(projectRoot, runId);
    delete recomputed.planRelativePath;
    expect(fixtures.canonicalBytes(recomputed).equals(bytes),
        "stimulus plan differs from the exact materializer/source inventories");
    return value;
}

function observerOptions(options) {
    return {
        clientPath: path.resolve(options.projectRoot, "tools", "audio-v2", "qualification-observer-client.ps1"),
        env: process.env,
        expectedCandidate: options.expectedCandidate,
        powershell: options.powershell,
        runId: options.runId,
        timeoutMs: options.timeoutMs || DEFAULT_TIMEOUT_MS
    };
}

function observe(options, command, caseId, routeKind) {
    if (options.observe) return options.observe(command, caseId, routeKind);
    const requestOptions = observerOptions(options);
    requestOptions.routeKind = routeKind;
    return observer.requestPipe(requestOptions, command, caseId || null);
}

function readyRuntimeFromObservation(value, label) {
    expect(value && value.snapshot && value.snapshot.runtime, label + " has no runtime snapshot");
    const runtime = value.snapshot.runtime;
    expect(runtime.status === "ready" &&
        ["wasapi", "directsound", "winmm"].includes(runtime.backend) &&
        runtime.sampleFormat === "f32" &&
        typeof runtime.audioSessionId === "string" && runtime.audioSessionId.length > 0 &&
        Number.isSafeInteger(runtime.audioReadyGeneration) && runtime.audioReadyGeneration >= 1 &&
        Number.isSafeInteger(runtime.deviceGeneration) && runtime.deviceGeneration >= 1 &&
        typeof runtime.deviceIdDigest === "string" && /^[A-F0-9]{64}$/.test(runtime.deviceIdDigest) &&
        Number.isSafeInteger(runtime.sampleRate) && runtime.sampleRate >= 8000 &&
        Number.isSafeInteger(runtime.channels) && runtime.channels >= 1,
    label + " is not a ready physical runtime tuple");
    return runtime;
}

function readCaptureConfiguration(result) {
    if (result.configurationValue) return result.configurationValue;
    expect(typeof result.configuration === "string" && fs.existsSync(result.configuration),
        "endpoint capture configuration is missing");
    const bytes = fs.readFileSync(result.configuration);
    let value;
    try { value = JSON.parse(bytes.toString("utf8")); }
    catch (error) { fail("VALIDATION_FAILED", "endpoint capture configuration is not JSON"); }
    expect(trackedArtifactCanonicalBytes(value).equals(bytes),
        "endpoint capture configuration is not canonical sorted JSON with two-space indent and terminal LF");
    return value;
}

function validateCaptureRuntimeBinding(result, runtime, caseId) {
    const value = readCaptureConfiguration(result);
    expect(value.captureId === CAPTURE_CASES[caseId] && value.caseId === CAPTURE_CASES[caseId] &&
        value.selectedBackend === runtime.backend &&
        value.deviceIdDigest === runtime.deviceIdDigest &&
        value.sampleRate === runtime.sampleRate &&
        value.channels === runtime.channels &&
        value.format === "pcm_s16le",
    caseId + " capture does not bind its ready runtime tuple");
    return value;
}

function expectSameRuntimeTuple(left, right, label) {
    expect(left.audioSessionId === right.audioSessionId &&
        left.audioReadyGeneration === right.audioReadyGeneration &&
        left.deviceGeneration === right.deviceGeneration &&
        left.backend === right.backend &&
        left.deviceIdDigest === right.deviceIdDigest &&
        left.sampleFormat === right.sampleFormat &&
        left.sampleRate === right.sampleRate &&
        left.channels === right.channels,
    label + " runtime tuple changed during capture");
}

function startCapture(options, caseId, runtime) {
    const captureId = CAPTURE_CASES[caseId];
    if (!captureId) return null;
    if (options.startCapture) return options.startCapture(caseId, captureId, runtime);
    expect(options.capture && typeof options.capture === "object", caseId + " requires endpoint capture options");
    expect(path.isAbsolute(options.capture.outputRoot), "capture output root must be absolute");
    expect(fs.existsSync(options.capture.outputRoot) && fs.lstatSync(options.capture.outputRoot).isDirectory(), "capture output root is missing");
    expect(["wasapi", "directsound", "winmm"].includes(options.capture.backend), "capture backend invalid");
    expectSha(options.capture.deviceIdDigest, "capture device digest");
    expect(typeof options.capture.endpointId === "string" && options.capture.endpointId.length >= 1 && options.capture.endpointId.length <= 4096,
        "capture endpoint ID invalid");
    expect(options.capture.backend === runtime.backend && options.capture.deviceIdDigest === runtime.deviceIdDigest,
        caseId + " requested capture tuple differs from the candidate runtime");

    const captureTool = path.resolve(options.projectRoot, ...CAPTURE_TOOL.split("/"));
    const wav = path.join(options.capture.outputRoot, captureId + ".wav");
    const config = path.join(options.capture.outputRoot, captureId + ".configuration.v1.json");
    const readySignal = path.join(options.capture.outputRoot, "." + captureId + "." + options.runId + ".ready");
    expect(!fs.existsSync(readySignal), "endpoint capture ready signal already exists");
    const args = [
        "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", captureTool,
        "-CaptureId", captureId,
        "-CaseId", captureId,
        "-CandidateRoot", options.candidateRoot,
        "-CandidateBuildIdentity", options.candidateBuildIdentity,
        "-CandidatePayloadClosure", options.candidatePayloadClosure,
        "-CandidateProcessId", String(options.candidatePid),
        "-SelectedBackend", options.capture.backend,
        "-EndpointId", options.capture.endpointId,
        "-DeviceIdDigest", options.capture.deviceIdDigest,
        "-DurationSeconds", "2",
        "-RunId", options.runId,
        "-OutputWav", wav,
        "-OutputConfiguration", config,
        "-ReadySignalPath", readySignal
    ];
    const child = (options.spawn || cp.spawn)(options.powershell, args, {
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = Buffer.alloc(0);
    let stderr = Buffer.alloc(0);
    child.stdout.on("data", (chunk) => { stdout = Buffer.concat([stdout, chunk]); });
    child.stderr.on("data", (chunk) => { stderr = Buffer.concat([stderr, chunk]); });
    let readySettled = false;
    let readyTimer = null;
    let rejectReady = null;
    const ready = new Promise((resolve, reject) => {
        rejectReady = reject;
        const startedAt = Date.now();
        const poll = () => {
            if (readySettled) return;
            if (fs.existsSync(readySignal)) {
                try {
                    const signal = fs.readFileSync(readySignal, "utf8");
                    expect(signal === CAPTURE_READY_TOKEN, "endpoint capture ready signal bytes drifted");
                    readySettled = true;
                    resolve();
                } catch (error) {
                    readySettled = true;
                    reject(error);
                }
                return;
            }
            if (Date.now() - startedAt >= 15000) {
                readySettled = true;
                try { child.kill(); } catch { }
                reject(new QualificationOperatorError("PREREQUISITE_MISSING", "endpoint capture did not become ready"));
                return;
            }
            readyTimer = setTimeout(poll, 10);
        };
        poll();
    });
    const completion = new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
            try { child.kill(); } catch { }
            reject(new QualificationOperatorError("PREREQUISITE_MISSING", "endpoint capture timed out"));
        }, 30000);
        child.once("error", (error) => {
            clearTimeout(timeout);
            if (!readySettled) {
                readySettled = true;
                if (readyTimer) clearTimeout(readyTimer);
                rejectReady(new QualificationOperatorError("PREREQUISITE_MISSING", "endpoint capture could not start: " + error.message));
            }
            reject(new QualificationOperatorError("PREREQUISITE_MISSING", "endpoint capture could not start: " + error.message));
        });
        child.once("close", (code) => {
            clearTimeout(timeout);
            if (!readySettled) {
                readySettled = true;
                if (readyTimer) clearTimeout(readyTimer);
                rejectReady(new QualificationOperatorError(
                    "PREREQUISITE_MISSING",
                    code === 0 ? "endpoint capture exited before its ready handshake" : "endpoint capture failed before its ready handshake"));
            }
            if (code !== 0) {
                reject(new QualificationOperatorError(
                    "VALIDATION_FAILED",
                    "endpoint capture failed: " + stderr.toString("utf8").replace(/[\r\n]+/g, " ").slice(0, 1000)));
                return;
            }
            try {
                expect(fs.existsSync(wav) && fs.existsSync(config), "endpoint capture did not publish both artifacts");
                resolve({ captureId, configuration: config, stdout: stdout.toString("utf8"), wav });
            } catch (error) {
                reject(error);
            }
        });
    });
    return { captureId, completion, ready };
}

function stimulusOptions(options) {
    return {
        expectedCandidate: options.expectedCandidate,
        powershell: options.powershell,
        projectRoot: options.projectRoot,
        runId: options.runId,
        spawnSync: options.spawnSync,
        timeoutMs: options.timeoutMs || DEFAULT_TIMEOUT_MS
    };
}

function dispatch(options, caseId, operation, fields) {
    const request = buildStimulusRequest(
        options.runId,
        caseId,
        operation,
        fields,
        (options.randomBytes || crypto.randomBytes)(16).toString("hex"));
    if (options.requestStimulus) return options.requestStimulus(request);
    return requestStimulus(stimulusOptions(options), request);
}

async function waitFor(options, milliseconds) {
    return (options.sleep || sleep)(milliseconds);
}

async function runAutomatedCase(options, plan, caseId) {
    expect(AUTOMATED_CASES.includes(caseId), "case is not in the automated qualification lane");
    const transcript = { caseId, captures: [], observations: [], stimuli: [] };
    transcript.observations.push(observe(options, "begin_case", caseId));

    if (caseId === "bgm_seek") await waitFor(options, options.timing.seekPreconditionMs);
    const initialObservation = observe(options, "snapshot", caseId);
    transcript.observations.push(initialObservation);
    const initialRuntime = CAPTURE_CASES[caseId]
        ? readyRuntimeFromObservation(initialObservation, caseId + " initial observation") : null;
    if (caseId === "sfx_playback") {
        const meter = initialObservation.snapshot.bgmMeter;
        expect(meter && Math.max(Math.abs(meter.peakLeft), Math.abs(meter.peakRight)) * 32767 < 64,
            "sfx_playback cannot start capture while BGM remains audible");
    }
    const capture = startCapture(options, caseId, initialRuntime);
    if (capture) {
        expect(capture.ready && typeof capture.ready.then === "function", caseId + " capture has no readiness handshake");
        try { await capture.ready; }
        catch (error) {
            try { await capture.completion; } catch { }
            throw error;
        }
    }
    let hasPostStimulusSnapshot = false;

    if (caseId === "bgm_playback") {
        transcript.stimuli.push(dispatch(options, caseId, "play", {
            fadeSeconds: 0, loop: true, path: plan.bgm.primary.relativePath, volume: 1
        }));
        await waitFor(options, options.timing.playObservationMs);
    } else if (caseId === "bgm_seek") {
        transcript.stimuli.push(dispatch(options, caseId, "seek", { seekSeconds: 0.25 }));
        await waitFor(options, options.timing.controlObservationMs);
    } else if (caseId === "bgm_crossfade") {
        transcript.stimuli.push(dispatch(options, caseId, "play", {
            fadeSeconds: 1, loop: true, path: plan.bgm.crossfade.relativePath, volume: 1
        }));
        for (let sample = 0; sample < 3; sample++) {
            await waitFor(options, options.timing.crossfadeSampleMs);
            transcript.observations.push(observe(options, "snapshot", caseId));
        }
        hasPostStimulusSnapshot = true;
    } else if (["format_vorbis", "format_aac_mp4", "format_opus"].includes(caseId)) {
        const fixtureId = {
            format_vorbis: "vorbis-ogg-tone-48000-mono",
            format_aac_mp4: "aac-lc-mp4-tone-48000-mono",
            format_opus: "opus-ogg-tone-48000-mono"
        }[caseId];
        const fixture = plan.fixtures.find((entry) => entry.fixtureId === fixtureId);
        expect(fixture, "materialized format fixture missing: " + fixtureId);
        transcript.stimuli.push(dispatch(options, caseId, "play", {
            fadeSeconds: 0, loop: true, path: fixture.relativePath, volume: 1
        }));
        await waitFor(options, options.timing.formatObservationMs);
    } else if (caseId === "sfx_playback") {
        transcript.stimuli.push(dispatch(options, caseId, "sfx", { linkageIds: [plan.sfx[0].linkageId] }));
        for (let sample = 0; sample < 2; sample++) {
            await waitFor(options, options.timing.sfxSampleMs);
            transcript.observations.push(observe(options, "snapshot", caseId));
        }
        hasPostStimulusSnapshot = true;
    } else if (caseId === "dense_overlap_throttle") {
        transcript.stimuli.push(dispatch(options, caseId, "sfx", { linkageIds: plan.sfx.map((entry) => entry.linkageId) }));
        await waitFor(options, options.timing.sfxSampleMs);
    } else if (caseId === "bgm_sfx_mix") {
        transcript.stimuli.push(dispatch(options, caseId, "sfx", { linkageIds: [plan.sfx[1].linkageId] }));
        for (let sample = 0; sample < 2; sample++) {
            await waitFor(options, options.timing.sfxSampleMs);
            transcript.observations.push(observe(options, "snapshot", caseId));
        }
        hasPostStimulusSnapshot = true;
    } else if (caseId === "gain_zero_and_default_max") {
        transcript.stimuli.push(dispatch(options, caseId, "set_gain", { volume: 1 }));
        await waitFor(options, options.timing.controlObservationMs);
        transcript.observations.push(observe(options, "snapshot", caseId));
        transcript.stimuli.push(dispatch(options, caseId, "set_gain", { volume: 0 }));
        await waitFor(options, options.timing.controlObservationMs);
    }

    if (!hasPostStimulusSnapshot) transcript.observations.push(observe(options, "snapshot", caseId));
    const finalRuntime = capture
        ? readyRuntimeFromObservation(transcript.observations[transcript.observations.length - 1], caseId + " final observation")
        : null;
    if (capture) {
        expectSameRuntimeTuple(initialRuntime, finalRuntime, caseId);
        const captured = await capture.completion;
        validateCaptureRuntimeBinding(captured, finalRuntime, caseId);
        transcript.captures.push(captured);
    }
    transcript.observations.push(observe(options, "end_case", caseId));
    return transcript;
}

async function runAutomatedLane(options, plan) {
    expect(plan && plan.bgm && Array.isArray(plan.fixtures) && Array.isArray(plan.sfx),
        "automated lane requires a validated stimulus plan");
    const transcript = [];
    for (const caseId of AUTOMATED_CASES) {
        transcript.push(await runAutomatedCase(options, plan, caseId));
        if (caseId === "format_opus") {
            dispatch(options, "pre_sfx_bgm_mute", "set_gain", { volume: 0 });
            await waitFor(options, options.timing.betweenCaseControlDrainMs);
        } else if (caseId === "dense_overlap_throttle") {
            dispatch(options, "pre_mix_bgm_restore", "set_gain", { volume: 1 });
            await waitFor(options, options.timing.betweenCaseControlDrainMs);
        }
    }
    const postGainRestore = dispatch(
        options,
        "post_gain_restore",
        "set_gain",
        { volume: 1 });
    // The stimulus response proves exact-generation delivery to Flash, not the
    // asynchronous AS2/C# result.  Keep the observer between cases for a bounded
    // drain window; any late request/result that still crosses case 11 will be
    // recorded there and make the frozen ingress grammar fail closed.
    await waitFor(options, options.timing.postGainRestoreDrainMs);
    return {
        cases: transcript,
        humanGate: {
            nextCase: "default_device_switch",
            promotionAuthorized: false,
            requiredCases: MANUAL_CASES.slice(),
            status: "HUMAN_PHYSICAL_ACTIONS_REQUIRED"
        },
        postGainRestore,
        runId: options.runId,
        schema: "cf7.audio-v2.qualification-operator-result.v1"
    };
}

function parseCli(argv) {
    expect(argv.length >= 1, "missing operator command");
    const command = argv[0];
    expect(["prepare", "run-automated", "observe", "arm-stale"].includes(command), "unknown operator command");
    const valueFlags = new Set([
        "--candidate-build-identity", "--candidate-payload-closure", "--candidate-pid",
        "--candidate-root", "--capture-backend", "--capture-device-digest",
        "--capture-endpoint-id", "--capture-output-root", "--case-id", "--pipe-command",
        "--powershell", "--project-root", "--route-kind", "--run-id"
    ]);
    const values = {};
    for (let index = 1; index < argv.length; index += 2) {
        const flag = argv[index];
        expect(valueFlags.has(flag) && !Object.prototype.hasOwnProperty.call(values, flag), "unknown or duplicate operator flag " + flag);
        expect(index + 1 < argv.length, flag + " requires a value");
        values[flag] = argv[index + 1];
    }
    expect(values["--project-root"] && values["--run-id"], "operator requires --project-root and --run-id");
    const result = {
        command,
        projectRoot: path.resolve(values["--project-root"]),
        runId: values["--run-id"]
    };
    expectRunId(result.runId, "operator runId");
    expect(path.isAbsolute(result.projectRoot) && fs.lstatSync(result.projectRoot).isDirectory(), "operator project root invalid");
    if (command === "prepare") {
        expect(Object.keys(values).length === 2, "prepare accepts only project-root and run-id");
        return result;
    }
    [
        "--candidate-build-identity", "--candidate-payload-closure", "--candidate-pid",
        "--candidate-root", "--powershell"
    ].forEach((flag) => expect(values[flag], "operator missing " + flag));
    result.candidateBuildIdentity = values["--candidate-build-identity"];
    result.candidatePayloadClosure = values["--candidate-payload-closure"];
    result.candidatePid = Number(values["--candidate-pid"]);
    result.candidateRoot = path.resolve(values["--candidate-root"]);
    result.powershell = path.resolve(values["--powershell"]);
    if (command === "run-automated") {
        ["--capture-backend", "--capture-device-digest", "--capture-endpoint-id", "--capture-output-root"]
            .forEach((flag) => expect(values[flag], "run-automated missing " + flag));
        result.capture = {
            backend: values["--capture-backend"],
            deviceIdDigest: values["--capture-device-digest"],
            endpointId: values["--capture-endpoint-id"],
            outputRoot: path.resolve(values["--capture-output-root"])
        };
    } else if (command === "observe") {
        result.pipeCommand = values["--pipe-command"];
        result.caseId = values["--case-id"];
        result.routeKind = values["--route-kind"];
        expect(["begin_case", "snapshot", "end_case", "journal"].includes(result.pipeCommand), "observe pipe-command invalid");
        expect(result.pipeCommand === "journal" ? !result.caseId : observer.ENDPOINT_CASES.includes(result.caseId), "observe case binding invalid");
        expect(result.routeKind === undefined ||
            (result.pipeCommand === "begin_case" && result.caseId === "physical_route_bluetooth_or_hdmi" && ["bluetooth", "hdmi"].includes(result.routeKind)),
        "observe route-kind invalid");
    } else {
        expect(values["--case-id"] === "no_stale_sfx_after_recovery", "arm-stale requires the stale recovery case");
        result.caseId = values["--case-id"];
    }
    return result;
}

function runtimeOptions(parsed) {
    const expectedCandidate = inspectCandidate(parsed);
    return Object.assign({}, parsed, {
        expectedCandidate,
        timing: {
            betweenCaseControlDrainMs: 750,
            controlObservationMs: 350,
            crossfadeSampleMs: 200,
            formatObservationMs: 750,
            playObservationMs: 750,
            postGainRestoreDrainMs: 2000,
            seekPreconditionMs: 2500,
            sfxSampleMs: 80
        }
    });
}

async function main(argv) {
    const parsed = parseCli(argv);
    if (parsed.command === "prepare") {
        return fixtures.materializeFixtures(parsed.projectRoot, parsed.runId);
    }
    const options = runtimeOptions(parsed);
    if (parsed.command === "run-automated") return runAutomatedLane(options, readPlan(options.projectRoot, options.runId));
    if (parsed.command === "observe") return observe(options, parsed.pipeCommand, parsed.caseId, parsed.routeKind);
    const plan = readPlan(options.projectRoot, options.runId);
    return dispatch(options, "no_stale_sfx_after_recovery", "sfx", { linkageIds: [plan.sfx[2].linkageId] });
}

if (require.main === module) {
    main(process.argv.slice(2)).then((result) => {
        process.stdout.write(canonicalBytes(result));
        process.stdout.write("\n");
    }).catch((error) => {
        const code = error instanceof QualificationOperatorError ? error.code : "INTERNAL_ERROR";
        process.stderr.write("audio-v2 qualification operator failed [" + code + "]: " +
            String(error && error.message ? error.message : error).replace(/[\r\n]+/g, " ") + "\n");
        process.exitCode = 3;
    });
}

module.exports = Object.freeze({
    AUTOMATED_CASES,
    MANUAL_CASES,
    QualificationOperatorError,
    STIMULUS_PROTOCOL,
    STIMULUS_RESPONSE_SCHEMA,
    buildStimulusRequest,
    canonicalBytes,
    inspectCandidate,
    parseCli,
    qualificationPath,
    readCaptureConfiguration,
    requestStimulus,
    runAutomatedCase,
    runAutomatedLane,
    trackedArtifactCanonicalBytes,
    validateCaptureRuntimeBinding,
    validateStimulusResponse
});
