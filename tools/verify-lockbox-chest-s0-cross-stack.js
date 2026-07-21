#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const PREFIX = "[DevLockboxS0] ";
const CURSOR_SCHEMA = "cf7/chest-s0-launcher-log-cursor/v1";
const REPORT_SCHEMA = "cf7/chest-s0-actual-cross-stack-evidence/v1";
const DEFAULT_MAX_CURSOR_AGE_MS = 2 * 60 * 60 * 1000;

const EVENT_SCHEMAS = Object.freeze({
    socket_ready: req("gen"),
    socket_disconnected: req("gen"),
    arm_issued: req("gen", "pid", "epoch", "capDigest"),
    web_armed: req("gen", "pid", "epoch", "capDigest"),
    as2_bootstrap_sent: req("gen", "capDigest", "resumeActive"),
    reconnect_bootstrap_sent: req("gen", "pid", "epoch", "capDigest", "resumeActive", "delivered"),
    as2_bootstrap_ack: req("gen", "pid", "epoch", "capDigest", "resumeActive"),
    begin_received: req("origin", "gen", "pid", "pauseAcquired"),
    capability_consumed: req("capDigest"),
    open_reserved: req("flowDigest", "requestDigest", "panelDigest", "sessionDigest", "epoch"),
    pause_acquire: req("delivered", "gen", "panelDigest"),
    open_enqueued: req("flowDigest", "requestDigest"),
    open_execute_recheck: req("allowed", "gen", "pid", "epoch"),
    panel_post: req("delivered", "host", "transport", "panelDigest"),
    tracked_open_stale: req("markedBindUnknown", "panelDigest"),
    process_replacement_recovery: req("reason", "panelDigest"),
    bind_unknown: req("panelDigest"),
    bind_query_reply: req("accepted", "binding", "panelDigest"),
    web_bind: opt(req("accepted"), "panelDigest"),
    result_forward: opt(req("flowCallId", "result", "delivered"), "reason"),
    result_unknown: opt(req("flowCallId"), "origin", "accepted"),
    query_forward: opt(req("unknownFlowCallId", "delivered"), "reason"),
    query_reply: req("flowCallId", "watermark", "disposition", "state", "terminal", "panelDigest"),
    authority_ack: req("watermark", "state", "terminal", "panelDigest"),
    web_close_ack: req("accepted", "panelDigest"),
    close_query: req("panelDigest"),
    panel_exact_close: req("closed", "reason", "panelDigest"),
    close_proof: req("recorded", "origin", "reason", "panelDigest"),
    native_close_proof: req("recorded", "reason", "panelDigest"),
    runtime_open_rejected: req("accepted", "code", "panelDigest"),
    document_navigation_start: req("navigationId", "active"),
    document_navigation_failed: req("navigationId", "success", "loadedNewDocument", "active"),
    document_epoch_advance: req("navigationId", "old", "new", "active"),
    old_document_teardown: req("proved", "panelDigest"),
    document_recovery: opt(req("path", "state"), "unknownFlowCallId", "delivered"),
    causal_query: req("unknownFlowCallId", "reason", "delivered"),
    reconcile_tick: req("state", "panelDigest"),
    authority_projection_retry: req("cmd", "panelDigest"),
    panel_host_idle: req("panel", "instanceDigest"),
    panel_queue_idle: req("pauseHeld"),
    generic_unpause: req("delivered", "gen"),
    generic_unpause_blocked: req("reason"),
    pause_release_generation_retry: req("oldGen", "newGen"),
    reconnect_bootstrap_superseded: req("gen"),
    telemetry_dropped: req("code"),
    pause_release: req("terminal", "domClosed", "nativeClosed", "panelDigest"),
    gate_rejected: opt(req("code", "origin"), "gen", "reason")
});

const DIGEST_KEYS = new Set([
    "capDigest", "flowDigest", "requestDigest", "panelDigest", "sessionDigest", "instanceDigest"
]);
const INTEGER_KEYS = new Set([
    "gen", "pid", "epoch", "flowCallId", "unknownFlowCallId", "watermark", "old", "new", "navigationId",
    "oldGen", "newGen"
]);
const BOOLEAN_KEYS = new Set([
    "allowed", "delivered", "accepted", "closed", "recorded", "active", "proved", "terminal", "domClosed",
    "nativeClosed", "resumeActive", "success", "loadedNewDocument", "pauseAcquired", "pauseHeld",
    "markedBindUnknown"
]);
const SAFE_REJECTIONS = new Set([
    "busy", "panel_orchestration_busy", "other_panel_blocked", "web_rejection_mismatch",
    "web_post_not_delivered", "pause_release_failed", "web_arm_ack_timeout",
    "as2_bootstrap_ack_timeout", "web_arm_rejected", "stale_socket_ready"
]);

const RECONCILE_STATES = new Set([
    "idle", "openqueued", "openbindunknown", "panelbound", "revokepending",
    "resultpending", "resultapplied", "reconcilerequired", "knownterminal"
]);
const AUTHORITY_PROJECTION_COMMANDS = new Set([
    "result_ack", "reconcile_reply", "authority_terminal"
]);
const AUTHORITY_STATES = new Set([
    "LOCK_PENDING", "OPENING_ANIMATION", "COMPLETED_NO_REWARD", "REVOKED", "EXPIRED"
]);
const TERMINAL_STATES = new Set(["COMPLETED_NO_REWARD", "REVOKED", "EXPIRED"]);

function req(...required) {
    return { required, optional: [] };
}

function opt(schema, ...optional) {
    return { required: schema.required, optional };
}

function invariant(condition, message) {
    if (!condition) throw new Error(message);
}

function sha256(buffer) {
    return crypto.createHash("sha256").update(buffer).digest("hex");
}

function parseStructuredEvents(text) {
    invariant(typeof text === "string", "evidence must be text");
    invariant(!/browser-host-shim|actualCrossStack\s*[:=]\s*false|selfAttestedCrossStack\s*[:=]\s*true/i.test(text),
        "browser/page self-attestation cannot be used as actual cross-stack evidence");

    const events = [];
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i += 1) {
        const marker = lines[i].indexOf(PREFIX);
        if (marker < 0) continue;
        const body = lines[i].slice(marker + PREFIX.length).trim();
        const tokens = body ? body.split(/\s+/) : [];
        invariant(tokens.length > 0 && /^event=[a-z0-9_]+$/.test(tokens[0]),
            `line ${i + 1}: unstructured DevLockboxS0 output is not admissible evidence`);
        const name = tokens[0].slice("event=".length);
        const schema = EVENT_SCHEMAS[name];
        invariant(schema, `line ${i + 1}: unknown DevLockboxS0 event '${name}'`);

        const fields = Object.create(null);
        for (let j = 1; j < tokens.length; j += 1) {
            const match = /^([A-Za-z][A-Za-z0-9]*)=([^\s=]+)$/.exec(tokens[j]);
            invariant(match, `line ${i + 1}: malformed structured field '${tokens[j]}'`);
            invariant(!Object.prototype.hasOwnProperty.call(fields, match[1]),
                `line ${i + 1}: duplicate field '${match[1]}'`);
            fields[match[1]] = match[2];
        }
        const allowed = new Set(schema.required.concat(schema.optional));
        for (const key of Object.keys(fields)) {
            invariant(allowed.has(key), `line ${i + 1}: unexpected or sensitive field '${key}' on ${name}`);
        }
        for (const key of schema.required) {
            invariant(Object.prototype.hasOwnProperty.call(fields, key),
                `line ${i + 1}: ${name} is missing '${key}'`);
        }
        validateFieldValues(name, fields, i + 1);
        events.push({ name, fields, line: i + 1, ordinal: events.length });
    }
    invariant(events.length > 0, "no structured DevLockboxS0 Host events were found");
    validateSocketGenerationSequence(events);
    return events;
}

function validateSocketGenerationSequence(events) {
    let highestReadyGeneration = 0;
    for (const event of events) {
        if (event.name === "socket_ready") {
            const generation = Number(event.fields.gen);
            invariant(generation >= highestReadyGeneration,
                `line ${event.line}: accepted socket_ready generation regressed`);
            highestReadyGeneration = generation;
            continue;
        }
        if (event.name !== "gate_rejected" || event.fields.code !== "stale_socket_ready") continue;
        const staleGeneration = Number(event.fields.gen);
        invariant(highestReadyGeneration > staleGeneration,
            `line ${event.line}: stale socket-ready evidence requires an earlier strictly higher adopted generation`);
    }
}

function validateFieldValues(name, fields, line) {
    for (const [key, value] of Object.entries(fields)) {
        if (DIGEST_KEYS.has(key)) {
            invariant(/^[0-9a-f]{12}$/.test(value), `line ${line}: ${key} must be 12 lowercase hex`);
        } else if (INTEGER_KEYS.has(key)) {
            invariant(/^(0|[1-9][0-9]*)$/.test(value), `line ${line}: ${key} must be an integer`);
            const parsed = Number(value);
            invariant(Number.isSafeInteger(parsed), `line ${line}: ${key} exceeds the safe integer range`);
            if (key !== "watermark") invariant(parsed > 0, `line ${line}: ${key} must be positive`);
        } else if (BOOLEAN_KEYS.has(key)) {
            invariant(value === "true" || value === "false", `line ${line}: ${key} must be true/false`);
        } else {
            invariant(/^[A-Za-z0-9_.-]+$/.test(value), `line ${line}: unsafe value for ${key}`);
        }
    }
    if (name === "panel_post") {
        invariant(fields.host === "PanelHostController" && fields.transport === "WebView2",
            `line ${line}: panel_post must name the real PanelHostController/WebView2 transport`);
    }
    if (name === "begin_received") {
        invariant(fields.origin === "trusted_as2_socket" && fields.pauseAcquired === "true",
            `line ${line}: begin evidence requires trusted AS2 origin and synchronous pause lease`);
    }
    if (name === "result_forward") {
        invariant(fields.flowCallId === "1", `line ${line}: S0 flowCallId domain is exactly {1}`);
        invariant(["success", "cancel", "failure"].includes(fields.result),
            `line ${line}: invalid limited result`);
        if (fields.reason !== undefined) {
            invariant(fields.result === "failure"
                && ["post_not_delivered", "web_bind_rejected", "pre_execution_rejected"]
                    .includes(fields.reason),
            `line ${line}: invalid result-forward failure reason`);
        }
    }
    if (name === "result_unknown") {
        invariant(fields.flowCallId === "1", `line ${line}: unknown call must be 1`);
        if (fields.origin === undefined) {
            invariant(fields.accepted === undefined,
                `line ${line}: result-unknown acceptance requires a Web timeout origin`);
        } else {
            invariant(fields.origin === "web_ack_timeout" && fields.accepted !== undefined,
                `line ${line}: invalid externally observed result-unknown evidence`);
        }
    }
    if (name === "query_forward") invariant(fields.unknownFlowCallId === "1", `line ${line}: query call must be 1`);
    if (name === "query_forward" && fields.reason !== undefined) {
        invariant(fields.reason === "reconnect", `line ${line}: invalid query reason`);
    }
    if (name === "close_proof") {
        invariant(fields.origin === "web_dom"
            && ["force_close", "runtime_rejected"].includes(fields.reason),
            `line ${line}: close proof must be an exact Web DOM teardown acknowledgement`);
    }
    if (name === "runtime_open_rejected") {
        invariant(["dom_bind_not_committed", "panel_open_exception", "arm_mismatch",
            "same_name_rebind_rejected"].includes(fields.code),
            `line ${line}: invalid runtime open rejection`);
    }
    if (name === "document_recovery") {
        if (fields.path === "pre_result") {
            invariant(fields.state === "revoke_pending"
                && fields.unknownFlowCallId === undefined && fields.delivered === undefined,
                `line ${line}: invalid pre-result document recovery`);
        } else {
            invariant(fields.path === "post_result" && fields.state === "reconcile_required"
                && fields.unknownFlowCallId === "1" && fields.delivered !== undefined,
                `line ${line}: invalid post-result document recovery`);
        }
    }
    if (name === "document_navigation_failed") {
        invariant(fields.success === "false" || fields.loadedNewDocument === "false",
            `line ${line}: a completed new document cannot be logged as failed navigation`);
    }
    if (name === "document_epoch_advance") {
        invariant(Number(fields.new) === Number(fields.old) + 1,
            `line ${line}: document epoch must advance by exactly one`);
    }
    if (name === "causal_query") {
        invariant(fields.unknownFlowCallId === "1"
            && ["web_request", "host_detected_unknown", "timer_reconcile", "terminal_poll",
                "reconnect", "document_teardown"].includes(fields.reason),
            `line ${line}: invalid causal query`);
    }
    if (name === "bind_query_reply") {
        invariant(["bound", "unbound"].includes(fields.binding), `line ${line}: invalid bind conclusion`);
    }
    if (name === "process_replacement_recovery") {
        invariant(["tracked_open_process_replaced", "reconnect_process_mismatch"].includes(fields.reason),
            `line ${line}: invalid process-replacement recovery reason`);
    }
    if (name === "query_reply") {
        invariant(["unknown", "success", "cancel", "failure", "not_applied"].includes(fields.disposition),
            `line ${line}: invalid causal disposition`);
        invariant(fields.flowCallId === "1", `line ${line}: query reply call must be 1`);
        invariant(fields.watermark === "0" || fields.watermark === "1",
            `line ${line}: query watermark must stay in the S0 {0,1} domain`);
        invariant(AUTHORITY_STATES.has(fields.state), `line ${line}: invalid query authority state`);
        invariant((fields.terminal === "true") === TERMINAL_STATES.has(fields.state),
            `line ${line}: terminal flag disagrees with query authority state`);
        if (fields.disposition === "success") {
            invariant(["OPENING_ANIMATION", "COMPLETED_NO_REWARD", "EXPIRED"].includes(fields.state),
                `line ${line}: success disposition disagrees with authority state`);
        } else if (["cancel", "failure", "not_applied"].includes(fields.disposition)) {
            invariant(fields.state === "REVOKED",
                `line ${line}: non-success disposition disagrees with authority state`);
        }
    }
    if (name === "authority_ack") {
        invariant(AUTHORITY_STATES.has(fields.state)
            && ((fields.terminal === "true") === TERMINAL_STATES.has(fields.state)),
            `line ${line}: authority terminal flag disagrees with state`);
        invariant(fields.state !== "LOCK_PENDING",
            `line ${line}: LOCK_PENDING cannot be acknowledged as authority progress`);
        invariant(fields.state === "EXPIRED"
            ? fields.watermark === "0" || fields.watermark === "1"
            : fields.watermark === "1",
        `line ${line}: authority watermark exceeds the S0 single-call domain`);
    }
    if (name === "reconcile_tick") {
        invariant(RECONCILE_STATES.has(fields.state), `line ${line}: invalid reconcile state`);
    }
    if (name === "authority_projection_retry") {
        invariant(AUTHORITY_PROJECTION_COMMANDS.has(fields.cmd),
            `line ${line}: invalid authority projection retry`);
    }
    if (name === "gate_rejected") {
        invariant(["socket", "web_control", "web_business", "panel_host"].includes(fields.origin),
            `line ${line}: invalid rejection origin`);
        invariant(fields.reason === undefined || fields.code === "web_arm_rejected"
            || fields.code === "pause_release_failed",
        `line ${line}: only a rejected Web arm or pause release may carry a reason`);
        invariant(fields.gen === undefined || fields.code === "pause_release_failed"
            || fields.code === "stale_socket_ready",
        `line ${line}: only an exact-generation pause-release failure or stale socket-ready may carry gen`);
        if (fields.code === "pause_release_failed") {
            invariant(fields.origin === "socket" && fields.gen !== undefined
                && ["connection_changed", "callback_false", "generation_churn"].includes(fields.reason),
            `line ${line}: invalid exact-generation pause-release failure evidence`);
        }
        if (fields.code === "stale_socket_ready") {
            invariant(fields.origin === "socket" && fields.gen !== undefined
                && fields.reason === undefined,
            `line ${line}: stale socket-ready rejection requires only a positive socket generation`);
        }
    }
    if (name === "reconnect_bootstrap_sent") {
        invariant(fields.resumeActive === "true",
            `line ${line}: reconnect bootstrap must reserve active-authority semantics`);
    }
    if (name === "generic_unpause_blocked") {
        invariant(fields.reason === "s0_active",
            `line ${line}: generic unpause block reason must identify the S0 lease`);
    }
    if (name === "pause_release_generation_retry") {
        invariant(Number(fields.newGen) > Number(fields.oldGen),
            `line ${line}: pause release generation retry requires a strictly increasing generation`);
    }
    if (name === "telemetry_dropped") {
        invariant(fields.code === "non_allowlisted_minigame_session",
            `line ${line}: invalid telemetry-drop category`);
    }
    if (name === "pause_release") {
        invariant(fields.terminal === "true" && fields.domClosed === "true"
            && fields.nativeClosed === "true",
        `line ${line}: pause release requires all three independent proofs`);
    }
}

function sameTuple(fields, arm) {
    return fields.gen === arm.gen && fields.pid === arm.pid && fields.epoch === arm.epoch;
}

function findAfter(events, start, name, predicate) {
    for (let i = start; i < events.length; i += 1) {
        if (events[i].name === name && (!predicate || predicate(events[i].fields))) return i;
    }
    return -1;
}

function findLastBefore(events, end, name, predicate) {
    for (let i = end - 1; i >= 0; i -= 1) {
        if (events[i].name === name && (!predicate || predicate(events[i].fields))) return i;
    }
    return -1;
}

function splitArmSegments(events) {
    const starts = [];
    for (let i = 0; i < events.length; i += 1) if (events[i].name === "arm_issued") starts.push(i);
    return starts.map((start, index) => ({
        start,
        end: index + 1 < starts.length ? starts[index + 1] : events.length,
        events: events.slice(start, index + 1 < starts.length ? starts[index + 1] : events.length)
    }));
}

function proveThroughEnqueue(allEvents, segment) {
    const events = segment.events;
    const arm = events[0].fields;
    let lastReady = -1;
    let lastDisconnect = -1;
    for (let i = 0; i < segment.start; i += 1) {
        if (allEvents[i].name === "socket_ready" && allEvents[i].fields.gen === arm.gen) lastReady = i;
        if (allEvents[i].name === "socket_disconnected" && allEvents[i].fields.gen === arm.gen) {
            lastDisconnect = i;
        }
    }
    if (lastReady < 0 || lastDisconnect > lastReady) return null;

    let at = 1;
    const webArmed = findAfter(events, at, "web_armed", fields => sameTuple(fields, arm)
        && fields.capDigest === arm.capDigest);
    if (webArmed < 0) return null;
    at = webArmed + 1;
    const sent = findAfter(events, at, "as2_bootstrap_sent", fields => fields.gen === arm.gen
        && fields.capDigest === arm.capDigest && fields.resumeActive === "false");
    if (sent < 0) return null;
    at = sent + 1;
    const ack = findAfter(events, at, "as2_bootstrap_ack", fields => sameTuple(fields, arm)
        && fields.capDigest === arm.capDigest && fields.resumeActive === "false");
    if (ack < 0) return null;
    at = ack + 1;
    const begin = findAfter(events, at, "begin_received", fields => fields.gen === arm.gen
        && fields.pid === arm.pid && fields.origin === "trusted_as2_socket"
        && fields.pauseAcquired === "true");
    if (begin < 0) return null;
    at = begin + 1;
    const consumed = findAfter(events, at, "capability_consumed",
        fields => fields.capDigest === arm.capDigest);
    if (consumed < 0) return null;
    at = consumed + 1;
    const reserved = findAfter(events, at, "open_reserved", fields => fields.epoch === arm.epoch);
    if (reserved < 0) return null;
    const identity = events[reserved].fields;
    at = reserved + 1;
    const pauseAcquire = findAfter(events, at, "pause_acquire", fields =>
        fields.delivered === "true" && fields.gen === arm.gen
            && fields.panelDigest === identity.panelDigest);
    if (pauseAcquire < 0) return null;
    at = pauseAcquire + 1;
    const enqueued = findAfter(events, at, "open_enqueued", fields => fields.flowDigest === identity.flowDigest
        && fields.requestDigest === identity.requestDigest);
    if (enqueued < 0) return null;
    return { arm, identity, at: enqueued + 1, enqueued, events, segment };
}

function proveBound(allEvents, segment) {
    const proof = proveThroughEnqueue(allEvents, segment);
    if (!proof) return null;
    let at = proof.at;
    const recheck = findAfter(proof.events, at, "open_execute_recheck", fields => fields.allowed === "true"
        && sameTuple(fields, proof.arm));
    if (recheck < 0) return null;
    at = recheck + 1;
    const posted = findAfter(proof.events, at, "panel_post", fields => fields.delivered === "true"
        && fields.host === "PanelHostController" && fields.transport === "WebView2"
        && fields.panelDigest === proof.identity.panelDigest);
    if (posted < 0) return null;
    at = posted + 1;
    let bound = findAfter(proof.events, at, "web_bind", fields => fields.accepted === "true"
        && fields.panelDigest === proof.identity.panelDigest);
    const queriedBound = findAfter(proof.events, at, "bind_query_reply", fields =>
        fields.accepted === "true" && fields.binding === "bound"
            && fields.panelDigest === proof.identity.panelDigest);
    if (bound < 0 || (queriedBound >= 0 && queriedBound < bound)) bound = queriedBound;
    if (bound < 0) return null;
    proof.at = bound + 1;
    proof.bound = bound;
    return proof;
}

function acceptedReasons(reason) {
    return Array.isArray(reason) ? reason : [reason];
}

function proveNativeCloseAndRelease(events, start, panelDigest, reason, domProof, terminal) {
    const reasons = acceptedReasons(reason);
    const panelClose = findAfter(events, start, "panel_exact_close", fields => fields.closed === "true"
        && reasons.includes(fields.reason) && fields.panelDigest === panelDigest);
    if (panelClose < 0) return null;
    const nativeClose = findAfter(events, panelClose + 1, "native_close_proof",
        fields => fields.recorded === "true" && reasons.includes(fields.reason)
            && fields.panelDigest === panelDigest);
    if (nativeClose < 0) return null;
    const release = findAfter(events, Math.max(domProof, terminal, nativeClose) + 1, "pause_release",
        fields => fields.terminal === "true" && fields.domClosed === "true"
            && fields.nativeClosed === "true" && fields.panelDigest === panelDigest);
    return release < 0 ? null : { panelClose, nativeClose, release };
}

function findTerminalEvidence(events, start, acceptedStates, minimumWatermark, panelDigest) {
    const minimum = minimumWatermark === undefined ? 1 : minimumWatermark;
    for (let i = start; i < events.length; i += 1) {
        const event = events[i];
        if (!acceptedStates.includes(event.fields.state)
            || Number(event.fields.watermark) < minimum) continue;
        if (event.fields.panelDigest !== panelDigest) continue;
        if (event.name === "authority_ack" && event.fields.terminal === "true") return i;
        if (event.name === "query_reply" && event.fields.disposition !== "unknown"
            && event.fields.terminal !== "false") return i;
    }
    return -1;
}

function proveCloseAfterTerminal(proof, terminal) {
    const events = proof.events;
    const webClose = findAfter(events, terminal + 1, "web_close_ack", fields => fields.accepted === "true"
        && fields.panelDigest === proof.identity.panelDigest);
    if (webClose < 0) return null;
    const native = proveNativeCloseAndRelease(events, webClose + 1, proof.identity.panelDigest,
        ["web_close_ack", "reconcile_terminal"], webClose, terminal);
    return native ? { terminal, webClose, panelClose: native.panelClose,
        nativeClose: native.nativeClose, release: native.release } : null;
}

function proveTerminalClose(proof, start, acceptedStates, minimumWatermark) {
    const events = proof.events;
    const terminal = findTerminalEvidence(events, start, acceptedStates, minimumWatermark,
        proof.identity.panelDigest);
    if (terminal < 0) return null;
    return proveCloseAfterTerminal(proof, terminal);
}

function proveRecoveredNativeCloseFailures(events) {
    const failures = events.filter(event => event.name === "panel_exact_close"
        && event.fields.closed === "false");
    for (const failure of failures) {
        const panelDigest = failure.fields.panelDigest;
        invariant(panelDigest,
            `line ${failure.line}: an exact native close failure without panel identity is unrecoverable`);
        const success = findAfter(events, failure.ordinal + 1, "panel_exact_close", fields =>
            fields.closed === "true" && fields.panelDigest === panelDigest);
        invariant(success >= 0,
            `line ${failure.line}: an exact native close failure was not retried to success`);
        const native = findAfter(events, success + 1, "native_close_proof", fields =>
            fields.recorded === "true" && fields.panelDigest === panelDigest);
        invariant(native >= 0,
            `line ${failure.line}: a retried exact native close lacks its Host proof`);
        invariant(!events.slice(failure.ordinal + 1, native).some(event => event.name === "pause_release"),
            `line ${failure.line}: pause released before native close retry converged`);
    }
    return failures;
}

function proveRecoveredWebPostFailures(events, segments) {
    const failures = events.filter(event => event.name === "gate_rejected"
        && event.fields.code === "web_post_not_delivered");
    for (const failure of failures) {
        const segment = segments.find(item => item.start < failure.ordinal && failure.ordinal < item.end);
        invariant(segment, `line ${failure.line}: Web post loss has no active attempt identity`);
        const reserved = findLastBefore(events, failure.ordinal, "open_reserved");
        invariant(reserved >= segment.start, `line ${failure.line}: Web post loss predates its active open`);
        const panelDigest = events[reserved].fields.panelDigest;
        const localStart = failure.ordinal - segment.start + 1;
        const tick = findAfter(segment.events, localStart, "reconcile_tick", fields =>
            fields.panelDigest === panelDigest);
        invariant(tick >= 0, `line ${failure.line}: Web post loss did not schedule a state-driven reconcile tick`);
        const recovery = segment.events.findIndex((event, index) => index > tick
            && ((event.name === "authority_projection_retry" && event.fields.panelDigest === panelDigest)
                || (event.name === "close_query" && event.fields.panelDigest === panelDigest)
                || (event.name === "bind_query_reply" && event.fields.accepted === "true"
                    && event.fields.panelDigest === panelDigest)));
        invariant(recovery >= 0, `line ${failure.line}: Web post loss has no later exact retry evidence`);
    }
    return failures;
}

function proveRecoveredPauseReleaseFailures(events, segments) {
    const failures = events.filter(event => event.name === "gate_rejected"
        && event.fields.code === "pause_release_failed");
    for (const failure of failures) {
        const segment = segments.find(item => item.start < failure.ordinal && failure.ordinal < item.end);
        invariant(segment, `line ${failure.line}: pause release failure has no active attempt`);
        const reserved = findLastBefore(events, failure.ordinal, "open_reserved");
        invariant(reserved >= segment.start,
            `line ${failure.line}: pause release failure predates its active attempt`);
        const panelDigest = events[reserved].fields.panelDigest;
        const localStart = failure.ordinal - segment.start + 1;
        const tick = findAfter(segment.events, localStart, "reconcile_tick", fields =>
            fields.state === "knownterminal" && fields.panelDigest === panelDigest);
        invariant(tick >= 0,
            `line ${failure.line}: pause release failure did not retain KnownTerminal for retry`);
        const release = findAfter(segment.events, tick + 1, "pause_release", fields =>
            fields.terminal === "true" && fields.domClosed === "true"
                && fields.nativeClosed === "true" && fields.panelDigest === panelDigest);
        invariant(release >= 0,
            `line ${failure.line}: pause release callback never converged after retry`);
        invariant(!segment.events.slice(localStart, release).some(event =>
            event.name === "arm_issued" || event.name === "web_armed"),
        `line ${failure.line}: fresh arm was issued before pause release callback succeeded`);
    }
    return failures;
}

function verifyActualCrossStack(events) {
    const rejected = events.filter(event => event.name === "gate_rejected");
    const unsafeRejections = rejected.filter(event => !SAFE_REJECTIONS.has(event.fields.code));
    invariant(unsafeRejections.length === 0,
        `unexpected gate rejection(s): ${unsafeRejections.map(item => `${item.fields.code}@${item.line}`).join(", ")}`);
    const failedCloseProofs = events.filter(event => event.name === "close_proof"
        && event.fields.recorded !== "true");
    invariant(failedCloseProofs.length === 0, "an exact Web DOM teardown acknowledgement was rejected");
    const failedNativeCloseProofs = events.filter(event => event.name === "native_close_proof"
        && event.fields.recorded !== "true");
    invariant(failedNativeCloseProofs.length === 0, "an exact native PanelHost close was not recorded");

    const segments = splitArmSegments(events);
    invariant(segments.length > 0, "no Launcher-issued arm attempt was observed");
    proveRecoveredNativeCloseFailures(events);
    for (const segment of segments) {
        const reservations = segment.events.filter(event => event.name === "open_reserved");
        invariant(reservations.length <= 1,
            `line ${segment.events[0].line}: one arm segment reserved more than one attempt`);
        const releases = segment.events.filter(event => event.name === "pause_release");
        const pauseAcquires = segment.events.filter(event => event.name === "pause_acquire");
        if (reservations.length === 0) {
            invariant(releases.length === 0,
                `line ${segment.events[0].line}: pause release has no reserved attempt`);
            invariant(pauseAcquires.length === 0,
                `line ${segment.events[0].line}: pause acquisition has no reserved attempt`);
            continue;
        }
        const panelDigest = reservations[0].fields.panelDigest;
        const reservedAt = segment.events.indexOf(reservations[0]);
        const acquiredAt = pauseAcquires.length === 1 ? segment.events.indexOf(pauseAcquires[0]) : -1;
        const enqueuedAt = segment.events.findIndex(event => event.name === "open_enqueued");
        const releasedAt = releases.length === 1 ? segment.events.indexOf(releases[0]) : -1;
        invariant(pauseAcquires.length === 1 && pauseAcquires[0].fields.delivered === "true"
            && pauseAcquires[0].fields.gen === segment.events[0].fields.gen
            && pauseAcquires[0].fields.panelDigest === panelDigest,
        `line ${reservations[0].line}: reserved attempt lacks one exact successful pause acquisition`);
        invariant(reservedAt < acquiredAt && acquiredAt < enqueuedAt,
            `line ${reservations[0].line}: pause acquisition must occur between reservation and enqueue`);
        const mismatched = segment.events.filter(event => event.fields.panelDigest !== undefined
            && event.fields.panelDigest !== panelDigest);
        invariant(mismatched.length === 0,
            `line ${mismatched.length ? mismatched[0].line : segment.events[0].line}: attempt evidence crossed panel identity`);
        invariant(releases.length === 1 && releases[0].fields.panelDigest === panelDigest,
            `line ${reservations[0].line}: reserved attempt did not converge to exactly one matching pause release`);
        invariant(enqueuedAt < releasedAt,
            `line ${reservations[0].line}: pause release cannot precede reservation acquisition and enqueue`);
    }
    const rejectedTeardowns = events.filter(event => event.name === "old_document_teardown"
        && event.fields.proved !== "true");
    invariant(rejectedTeardowns.length === 0,
        "a rejected old-document teardown cannot coexist with clean cross-stack evidence");
    const advances = events.filter(event => event.name === "document_epoch_advance");
    for (const advance of advances) {
        const start = findLastBefore(events, advance.ordinal, "document_navigation_start", fields =>
            fields.navigationId === advance.fields.navigationId);
        invariant(start >= 0 && events[start].fields.active === advance.fields.active,
            `line ${advance.line}: document epoch advance lacks its matching navigation start`);
        const failed = events.slice(start + 1, advance.ordinal).some(event =>
            event.name === "document_navigation_failed"
                && event.fields.navigationId === advance.fields.navigationId);
        invariant(!failed,
            `line ${advance.line}: failed navigation cannot advance the document epoch`);
    }
    proveRecoveredWebPostFailures(events, segments);
    proveRecoveredPauseReleaseFailures(events, segments);
    const armDigests = segments.map(segment => segment.events[0].fields.capDigest);
    invariant(new Set(armDigests).size === armDigests.length,
        "Launcher capability digest was reused across attempts");
    const reconnectDigests = events.filter(event => event.name === "reconnect_bootstrap_sent")
        .map(event => event.fields.capDigest);
    invariant(new Set(armDigests.concat(reconnectDigests)).size === armDigests.length + reconnectDigests.length,
        "Launcher capability digest was reused by an arm or reconnect bootstrap");
    const reservedEvents = events.filter(event => event.name === "open_reserved");
    for (const key of ["flowDigest", "requestDigest", "panelDigest", "sessionDigest"]) {
        const values = reservedEvents.map(event => event.fields[key]);
        invariant(new Set(values).size === values.length, `${key} was reused across attempts`);
    }
    const boundProofs = segments.map(segment => proveBound(events, segment)).filter(Boolean);

    let bindQueryRetry = null;
    for (const segment of segments) {
        const proof = proveThroughEnqueue(events, segment);
        if (!proof) continue;
        const recheck = findAfter(proof.events, proof.at, "open_execute_recheck", fields =>
            fields.allowed === "true" && sameTuple(fields, proof.arm));
        if (recheck < 0) continue;
        const posted = findAfter(proof.events, recheck + 1, "panel_post", fields =>
            fields.delivered === "true" && fields.panelDigest === proof.identity.panelDigest);
        if (posted < 0) continue;
        const unknown = findAfter(proof.events, posted + 1, "bind_unknown", fields =>
            fields.panelDigest === proof.identity.panelDigest);
        if (unknown < 0) continue;
        const firstQuery = findAfter(proof.events, unknown + 1, "close_query", fields =>
            fields.panelDigest === proof.identity.panelDigest);
        if (firstQuery < 0) continue;
        const tick = findAfter(proof.events, firstQuery + 1, "reconcile_tick", fields =>
            fields.state === "openbindunknown" && fields.panelDigest === proof.identity.panelDigest);
        if (tick < 0) continue;
        const retryQuery = findAfter(proof.events, tick + 1, "close_query", fields =>
            fields.panelDigest === proof.identity.panelDigest);
        if (retryQuery < 0) continue;
        const reply = findAfter(proof.events, retryQuery + 1, "bind_query_reply", fields =>
            fields.accepted === "true" && fields.binding === "bound"
                && fields.panelDigest === proof.identity.panelDigest);
        if (reply < 0) continue;
        bindQueryRetry = { proof, recheck, posted, unknown, firstQuery, tick, retryQuery, reply };
        break;
    }
    invariant(bindQueryRetry,
        "X02 missing: lost bind observation must be retried by OpenBindUnknown tick until one exact bound reply");

    let happy = null;
    for (const proof of boundProofs) {
        const result = findAfter(proof.events, proof.at, "result_forward",
            fields => fields.result === "success" && fields.delivered === "true");
        if (result < 0) continue;
        const opening = findAfter(proof.events, result + 1, "authority_ack",
            fields => fields.state === "OPENING_ANIMATION" && fields.terminal === "false"
                && fields.watermark === "1"
                && fields.panelDigest === proof.identity.panelDigest);
        if (opening < 0) continue;
        const terminalTick = findAfter(proof.events, opening + 1, "reconcile_tick", fields =>
            fields.state === "resultapplied" && fields.panelDigest === proof.identity.panelDigest);
        if (terminalTick < 0) continue;
        const resultProjection = findAfter(proof.events, terminalTick + 1,
            "authority_projection_retry", fields => fields.cmd === "result_ack"
                && fields.panelDigest === proof.identity.panelDigest);
        if (resultProjection < 0) continue;
        const terminalPoll = findAfter(proof.events, resultProjection + 1, "causal_query", fields =>
            fields.reason === "terminal_poll" && fields.unknownFlowCallId === "1"
                && fields.delivered === "true");
        if (terminalPoll < 0) continue;
        const closed = proveTerminalClose(proof, terminalPoll + 1, ["COMPLETED_NO_REWARD"]);
        if (closed && !proof.events.slice(result + 1, closed.terminal)
            .some(event => event.name === "result_forward")) {
            happy = { proof, result, opening, terminalTick, resultProjection, terminalPoll, closed };
            break;
        }
    }
    invariant(happy,
        "X01 missing: trusted socket success must reach AS2 terminal by read-only ResultApplied polling without write replay");
    const lostProjection = findAfter(happy.proof.events, happy.closed.terminal + 1,
        "gate_rejected", fields => fields.code === "web_post_not_delivered"
            && fields.origin === "web_business");
    const knownTick = findAfter(happy.proof.events, lostProjection + 1, "reconcile_tick", fields =>
        fields.state === "knownterminal" && fields.panelDigest === happy.proof.identity.panelDigest);
    const projectionRetry = findAfter(happy.proof.events, knownTick + 1,
        "authority_projection_retry", fields => fields.cmd === "authority_terminal"
            && fields.panelDigest === happy.proof.identity.panelDigest);
    const happyCloseRetry = findAfter(happy.proof.events, projectionRetry + 1,
        "close_query", fields => fields.panelDigest === happy.proof.identity.panelDigest);
    invariant(lostProjection >= 0 && knownTick > lostProjection && projectionRetry > knownTick
        && happyCloseRetry > projectionRetry && happyCloseRetry < happy.closed.webClose,
    "X01 missing: lost terminal projection/close ack must recover by KnownTerminal projection replay then exact Host close_query");
    const failedNative = findAfter(happy.proof.events, happy.closed.webClose + 1,
        "panel_exact_close", fields => fields.closed === "false"
            && fields.panelDigest === happy.proof.identity.panelDigest);
    const nativeRetryTick = findAfter(happy.proof.events, failedNative + 1, "reconcile_tick", fields =>
        fields.state === "knownterminal" && fields.panelDigest === happy.proof.identity.panelDigest);
    invariant(failedNative >= 0 && nativeRetryTick > failedNative
        && nativeRetryTick < happy.closed.panelClose,
        "X01 missing: first native exact-close failure must converge only after a KnownTerminal retry tick");

    let nonSuccess = null;
    for (const proof of boundProofs) {
        const result = findAfter(proof.events, proof.at, "result_forward",
            fields => (fields.result === "cancel" || fields.result === "failure") && fields.delivered === "true");
        if (result < 0) continue;
        const closed = proveTerminalClose(proof, result + 1, ["REVOKED", "EXPIRED"]);
        if (closed) { nonSuccess = { proof, result, closed }; break; }
    }
    invariant(nonSuccess, "X02 missing: cancel/failure authority revocation and exact close");
    const retry = segments.map(segment => proveThroughEnqueue(events, segment)).find(proof => proof
        && proof.segment.start > nonSuccess.proof.segment.start
        && proof.arm.capDigest !== nonSuccess.proof.arm.capDigest
        && proof.identity.flowDigest !== nonSuccess.proof.identity.flowDigest
        && proof.identity.requestDigest !== nonSuccess.proof.identity.requestDigest
        && proof.identity.panelDigest !== nonSuccess.proof.identity.panelDigest
        && proof.identity.sessionDigest !== nonSuccess.proof.identity.sessionDigest);
    invariant(retry, "X02 missing: a revoked attempt must retry with fresh cap/flow/request/panel/session identities");

    const negativeRecheck = segments.map(segment => proveThroughEnqueue(events, segment)).find(proof => {
        if (!proof) return false;
        const denied = findAfter(proof.events, proof.at, "open_execute_recheck", fields => fields.allowed === "false");
        if (denied < 0) return false;
        return findAfter(proof.events, denied + 1, "panel_post", fields => fields.delivered === "false") >= 0;
    });
    invariant(negativeRecheck, "X02 missing: request token must be denied by execution-time recheck before a DOM post");
    invariant(rejected.some(event => event.fields.code === "busy" && event.fields.origin === "socket"),
        "X02 missing: same-flow/same-name socket begin is not rejected busy");
    invariant(rejected.some(event => event.fields.code === "other_panel_blocked"
        && event.fields.origin === "panel_host"), "X02 missing: global panel serialization rejection");
    invariant(events.some(event => event.name === "generic_unpause_blocked"
        && event.fields.reason === "s0_active"), "X02 missing: active S0 flow did not block generic unpause");

    let preResultExpired = null;
    for (const proof of boundProofs) {
        const closed = proveTerminalClose(proof, proof.at, ["EXPIRED"], 0);
        if (!closed || proof.events[closed.terminal].fields.watermark !== "0") continue;
        if (proof.events.slice(proof.at, closed.terminal)
            .some(event => event.name === "result_forward")) continue;
        preResultExpired = { proof, closed };
        break;
    }
    invariant(preResultExpired,
        "X02 missing: legal pre-result zero-watermark EXPIRED must reach Web terminal, exact close ack, native close, and release");

    let runtimeRejection = null;
    for (const segment of segments) {
        const proof = proveThroughEnqueue(events, segment);
        if (!proof) continue;
        const recheck = findAfter(proof.events, proof.at, "open_execute_recheck",
            fields => fields.allowed === "true" && sameTuple(fields, proof.arm));
        if (recheck < 0) continue;
        const posted = findAfter(proof.events, recheck + 1, "panel_post", fields =>
            fields.delivered === "true" && fields.panelDigest === proof.identity.panelDigest);
        if (posted < 0) continue;
        const staleBootstrapRejection = findAfter(proof.events, posted + 1, "gate_rejected",
            fields => fields.code === "web_rejection_mismatch" && fields.origin === "web_control");
        if (staleBootstrapRejection < 0) continue;
        const rejectedOpen = findAfter(proof.events, staleBootstrapRejection + 1,
            "runtime_open_rejected", fields => fields.accepted === "true"
                && fields.panelDigest === proof.identity.panelDigest);
        if (rejectedOpen < 0) continue;
        if (proof.events.slice(posted + 1, rejectedOpen)
            .some(event => event.name === "web_bind" && event.fields.accepted === "true")) continue;
        const result = findAfter(proof.events, rejectedOpen + 1, "result_forward", fields =>
            fields.result === "failure" && fields.reason === "web_bind_rejected"
                && fields.delivered === "true");
        if (result < 0) continue;
        const retryTick = findAfter(proof.events, result + 1, "reconcile_tick", fields =>
            fields.state === "revokepending" && fields.panelDigest === proof.identity.panelDigest);
        if (retryTick < 0) continue;
        const resultRetry = findAfter(proof.events, retryTick + 1, "result_forward", fields =>
            fields.result === "failure" && fields.reason === "web_bind_rejected"
                && fields.delivered === "true");
        if (resultRetry < 0) continue;
        const closeQuery = findAfter(proof.events, resultRetry + 1, "close_query", fields =>
            fields.panelDigest === proof.identity.panelDigest);
        if (closeQuery < 0) continue;
        const domClose = findAfter(proof.events, closeQuery + 1, "close_proof", fields =>
            fields.recorded === "true" && fields.origin === "web_dom"
                && fields.reason === "runtime_rejected"
                && fields.panelDigest === proof.identity.panelDigest);
        if (domClose < 0) continue;
        const terminal = findAfter(proof.events, result + 1, "authority_ack", fields =>
            fields.terminal === "true" && fields.state === "REVOKED"
                && fields.panelDigest === proof.identity.panelDigest);
        if (terminal < 0) continue;
        const native = proveNativeCloseAndRelease(proof.events, result + 1,
            proof.identity.panelDigest, ["runtime_rejected", "reconcile_revoke", "reconcile_terminal"],
            domClose, terminal);
        if (!native) continue;
        runtimeRejection = { proof, staleBootstrapRejection, rejectedOpen, result, retryTick,
            resultRetry, closeQuery, domClose, terminal, native };
        break;
    }
    const rejectionMismatches = rejected.filter(event => event.fields.code === "web_rejection_mismatch");
    invariant(runtimeRejection && rejectionMismatches.length === 1,
        "X02 missing: runtime rejection must retain the consumed binding, retry revocation/close from RevokePending, then independently prove Web/native close and authority terminal");

    let panelBusyRearm = null;
    for (let i = 0; i < events.length; i += 1) {
        if (events[i].name !== "gate_rejected"
            || events[i].fields.code !== "panel_orchestration_busy"
            || events[i].fields.origin !== "socket") continue;
        const priorArm = findLastBefore(events, i, "arm_issued");
        if (priorArm < 0) continue;
        const consumed = findAfter(events, priorArm + 1, "capability_consumed",
            fields => fields.capDigest === events[priorArm].fields.capDigest);
        if (consumed < 0 || consumed > i) continue;
        const idle = findAfter(events, i + 1, "panel_host_idle");
        if (idle < 0 || events.slice(i + 1, idle).some(event => event.name === "arm_issued")) continue;
        const freshArm = findAfter(events, idle + 1, "arm_issued", fields =>
            fields.capDigest !== events[priorArm].fields.capDigest);
        if (freshArm < 0) continue;
        panelBusyRearm = { rejected: i, priorArm, consumed, idle, freshArm };
        break;
    }
    invariant(panelBusyRearm,
        "X02 missing: panel-busy consumed arm must wait for PanelHost idle before one fresh capability re-arm");

    let reconciled = null;
    for (const proof of boundProofs) {
        const result = findAfter(proof.events, proof.at, "result_forward", fields => fields.delivered === "false");
        if (result < 0) continue;
        const unknown = findAfter(proof.events, result + 1, "result_unknown", fields => fields.flowCallId === "1");
        if (unknown < 0) continue;
        const directQuery = findAfter(proof.events, unknown + 1, "causal_query", fields =>
            fields.unknownFlowCallId === "1" && fields.reason === "host_detected_unknown"
                && fields.delivered === "true");
        if (directQuery < 0) continue;
        const tick = findAfter(proof.events, directQuery + 1, "reconcile_tick", fields =>
            fields.state === "reconcilerequired" && fields.panelDigest === proof.identity.panelDigest);
        if (tick < 0) continue;
        const retryQuery = findAfter(proof.events, tick + 1, "causal_query", fields =>
            fields.unknownFlowCallId === "1" && fields.reason === "timer_reconcile"
                && fields.delivered === "true");
        if (retryQuery < 0) continue;
        if (proof.events.slice(unknown + 1, retryQuery).some(event =>
            event.name === "result_forward" || event.name === "query_forward")) continue;
        const reply = findAfter(proof.events, retryQuery + 1, "query_reply",
            fields => fields.disposition !== "unknown" && fields.flowCallId === "1"
                && Number(fields.watermark) >= 1
                && fields.panelDigest === proof.identity.panelDigest);
        if (reply < 0) continue;
        if (proof.events.slice(result + 1, reply).some(event => event.name === "result_forward")) continue;
        const closed = ["COMPLETED_NO_REWARD", "REVOKED", "EXPIRED"]
            .includes(proof.events[reply].fields.state)
            ? proveCloseAfterTerminal(proof, reply)
            : proveTerminalClose(proof, reply + 1, ["COMPLETED_NO_REWARD", "REVOKED", "EXPIRED"]);
        if (closed) {
            reconciled = { proof, result, unknown, directQuery, tick, retryQuery, reply, closed };
            break;
        }
    }
    invariant(reconciled,
        "X03 missing: unknown write delivery must query AS2 directly, retry from ReconcileRequired without Web query or write replay, then close exactly");

    let preResultNavigation = null;
    for (let i = 0; i < events.length; i += 1) {
        if (events[i].name !== "document_epoch_advance" || events[i].fields.active !== "true"
            || Number(events[i].fields.new) <= Number(events[i].fields.old)) continue;
        const navigationStart = findLastBefore(events, i, "document_navigation_start",
            fields => fields.active === "true"
                && fields.navigationId === events[i].fields.navigationId);
        if (navigationStart < 0 || events.slice(navigationStart + 1, i).some(event =>
            event.name === "document_navigation_failed"
                && event.fields.navigationId === events[navigationStart].fields.navigationId)) continue;
        const reserved = findLastBefore(events, i, "open_reserved");
        if (reserved < 0 || events.slice(reserved + 1, i)
            .some(event => event.name === "result_forward")) continue;
        const teardown = findAfter(events, i + 1, "old_document_teardown", fields => fields.proved === "true");
        if (teardown < 0) continue;
        const digest = events[teardown].fields.panelDigest;
        if (digest !== events[reserved].fields.panelDigest) continue;
        const recovery = findAfter(events, teardown + 1, "document_recovery", fields =>
            fields.path === "pre_result" && fields.state === "revoke_pending");
        if (recovery < 0) continue;
        const result = findAfter(events, recovery + 1, "result_forward", fields =>
            fields.result === "failure" && fields.reason === "web_bind_rejected"
                && fields.delivered === "true");
        if (result < 0) continue;
        const terminal = findAfter(events, result + 1, "authority_ack", fields =>
            fields.terminal === "true" && fields.state === "REVOKED"
                && fields.panelDigest === digest);
        if (terminal < 0) continue;
        const native = proveNativeCloseAndRelease(events, teardown + 1, digest,
            ["document_teardown", "reconcile_revoke", "reconcile_terminal"], teardown, terminal);
        if (!native) continue;
        if (events.slice(i + 1, native.release)
            .some(event => event.name === "arm_issued" || event.name === "web_armed")) {
            continue;
        }
        preResultNavigation = { navigationStart, advance: i, reserved, teardown, recovery,
            result, terminal, native };
        break;
    }
    invariant(preResultNavigation,
        "X04 missing: pre-result active document epoch teardown must reconcile AS2 authority before native-close pause release");

    let postResultNavigation = null;
    for (let i = 0; i < events.length; i += 1) {
        if (events[i].name !== "document_epoch_advance" || events[i].fields.active !== "true"
            || Number(events[i].fields.new) <= Number(events[i].fields.old)) continue;
        const navigationStart = findLastBefore(events, i, "document_navigation_start",
            fields => fields.active === "true"
                && fields.navigationId === events[i].fields.navigationId);
        if (navigationStart < 0 || events.slice(navigationStart + 1, i).some(event =>
            event.name === "document_navigation_failed"
                && event.fields.navigationId === events[navigationStart].fields.navigationId)) continue;
        const reserved = findLastBefore(events, i, "open_reserved");
        if (reserved < 0) continue;
        const submitted = findAfter(events, reserved + 1, "result_forward",
            fields => fields.flowCallId === "1" && fields.delivered === "true");
        if (submitted < 0 || submitted > i) continue;
        const teardown = findAfter(events, i + 1, "old_document_teardown", fields =>
            fields.proved === "true" && fields.panelDigest === events[reserved].fields.panelDigest);
        if (teardown < 0) continue;
        const causal = findAfter(events, teardown + 1, "causal_query", fields =>
            fields.unknownFlowCallId === "1" && fields.reason === "document_teardown"
                && fields.delivered === "true");
        if (causal < 0) continue;
        const recovery = findAfter(events, causal + 1, "document_recovery", fields =>
            fields.path === "post_result" && fields.state === "reconcile_required"
                && fields.unknownFlowCallId === "1" && fields.delivered === "true");
        if (recovery < 0) continue;
        if (events.slice(i + 1, recovery).some(event => event.name === "result_forward")) continue;
        const reply = findAfter(events, recovery + 1, "query_reply", fields =>
            fields.disposition !== "unknown" && fields.flowCallId === "1"
                && Number(fields.watermark) >= 1
                && fields.panelDigest === events[reserved].fields.panelDigest);
        if (reply < 0) continue;
        let terminal = reply;
        if (!["COMPLETED_NO_REWARD", "REVOKED", "EXPIRED"].includes(events[reply].fields.state)) {
            terminal = findAfter(events, reply + 1, "authority_ack", fields =>
                fields.terminal === "true"
                    && fields.panelDigest === events[reserved].fields.panelDigest);
        }
        if (terminal < 0) continue;
        const digest = events[teardown].fields.panelDigest;
        const native = proveNativeCloseAndRelease(events, teardown + 1, digest,
            ["document_teardown", "reconcile_revoke", "reconcile_terminal"], teardown, terminal);
        if (!native) continue;
        if (events.slice(i + 1, native.release)
            .some(event => event.name === "arm_issued" || event.name === "web_armed")) continue;
        if (events.slice(i + 1, reply).some(event => event.name === "result_forward")) continue;
        postResultNavigation = { navigationStart, advance: i, reserved, submitted, teardown, causal,
            recovery, reply, terminal, native };
        break;
    }
    invariant(postResultNavigation,
        "X04 missing: post-result active navigation must issue one causal query without write replay, converge authority, prove native close, and release");

    let reconnectProof = null;
    for (let i = 0; i < events.length; i += 1) {
        if (events[i].name !== "socket_disconnected") continue;
        const oldGen = Number(events[i].fields.gen);
        const activeArm = findLastBefore(events, i, "arm_issued");
        const reserved = findLastBefore(events, i, "open_reserved");
        if (activeArm < 0 || reserved < 0) continue;
        const panelDigest = events[reserved].fields.panelDigest;
        const unknown = findAfter(events, i + 1, "result_unknown", fields => fields.flowCallId === "1");
        if (unknown < 0) continue;
        const domClose = findAfter(events, i + 1, "close_proof", fields => fields.recorded === "true"
            && fields.origin === "web_dom" && fields.reason === "force_close"
            && fields.panelDigest === panelDigest);
        if (domClose < 0) continue;
        const ready = findAfter(events, i + 1, "socket_ready", fields => Number(fields.gen) > oldGen);
        if (ready < 0) continue;
        const newGen = events[ready].fields.gen;
        const socketBootstrap = findAfter(events, ready + 1, "as2_bootstrap_sent",
            fields => fields.gen === newGen && fields.resumeActive === "true");
        if (socketBootstrap < 0) continue;
        const reconnect = findAfter(events, socketBootstrap + 1, "reconnect_bootstrap_sent", fields =>
            fields.gen === newGen && fields.pid === events[activeArm].fields.pid
            && fields.epoch === events[activeArm].fields.epoch
            && fields.capDigest === events[socketBootstrap].fields.capDigest
            && fields.resumeActive === "true"
            && fields.delivered === "true");
        if (reconnect < 0) continue;
        const ack = findAfter(events, reconnect + 1, "as2_bootstrap_ack", fields =>
            fields.gen === newGen && fields.pid === events[reconnect].fields.pid
            && fields.epoch === events[reconnect].fields.epoch
            && fields.capDigest === events[reconnect].fields.capDigest
            && fields.resumeActive === "true");
        if (ack < 0) continue;
        const causal = findAfter(events, ack + 1, "causal_query", fields =>
            fields.unknownFlowCallId === "1" && fields.delivered === "true"
                && fields.reason === "reconnect");
        if (causal < 0) continue;
        const query = findAfter(events, causal + 1, "query_forward", fields =>
            fields.unknownFlowCallId === "1" && fields.delivered === "true" && fields.reason === "reconnect");
        if (query < 0) continue;
        if (events.slice(reconnect + 1, query).some(event => event.name === "begin_received"
            || event.name === "capability_consumed" || event.name === "open_reserved"
            || event.name === "open_enqueued")) continue;
        const reply = findAfter(events, query + 1, "query_reply", fields =>
            fields.disposition !== "unknown" && fields.flowCallId === "1"
                && Number(fields.watermark) >= 1 && fields.panelDigest === panelDigest);
        if (reply < 0) continue;
        let terminal = reply;
        if (!["COMPLETED_NO_REWARD", "REVOKED", "EXPIRED"].includes(events[reply].fields.state)) {
            terminal = findAfter(events, reply + 1, "authority_ack", fields =>
                fields.terminal === "true" && fields.panelDigest === panelDigest);
        }
        if (terminal < 0) continue;
        const native = proveNativeCloseAndRelease(events, i + 1, panelDigest,
            ["socket_disconnected", "reconcile_terminal"], domClose, terminal);
        if (!native) continue;
        const forbiddenWindow = events.slice(i + 1, native.release);
        if (forbiddenWindow.some(event => event.name === "arm_issued" || event.name === "web_armed")) continue;
        if (events.slice(i + 1, query).some(event => event.name === "result_forward")) continue;
        if (events.slice(i + 1, native.release).some(event => event.name === "pause_release")) continue;
        reconnectProof = { disconnected: i, reserved, unknown, domClose, ready, socketBootstrap,
            reconnect, ack, causal, query, reply, terminal, native };
        break;
    }
    invariant(reconnectProof, "X04 missing: disconnect/reconnect must independently prove Web force-close and native PanelHost close, reserve resumeActive capability for authority reconciliation only, query without replay/Web re-arm, then release");

    const tuple = happy.proof.arm;
    return {
        schema: REPORT_SCHEMA,
        evidenceKind: "launcher-structured-host-log",
        executionMode: "actual-webview2-dev-wire",
        actualCrossStack: true,
        productionHost: true,
        isolatedDevCandidateRequired: true,
        realPanelHost: true,
        realWebView2: true,
        browserShim: false,
        runtimePromotionAuthorized: false,
        trustedTuple: { gen: Number(tuple.gen), pid: Number(tuple.pid), epoch: Number(tuple.epoch), capDigest: tuple.capDigest },
        cases: [
            { id: "X01", passed: true, description: "read-only terminal poll, projection/close retry, and native exact-close retry" },
            { id: "X02", passed: true, description: "bind/revoke state retries, tracked recheck, zero-watermark expiry, panel-busy rearm, and serialization" },
            { id: "X03", passed: true, description: "Host-direct AS2 query plus timer retry without Web query or write replay" },
            { id: "X04", passed: true, description: "matching navigation teardown and resumeActive socket reconnect reconciliation" }
        ],
        eventCount: events.length
    };
}

function beginCapture(logPath, cursorPath) {
    const resolvedLog = path.resolve(logPath);
    const resolvedCursor = path.resolve(cursorPath);
    invariant(fs.existsSync(resolvedLog), `launcher log does not exist: ${resolvedLog}`);
    const data = fs.readFileSync(resolvedLog);
    invariant(data.length === 0 || data[data.length - 1] === 0x0a,
        "launcher log must end at a complete line before capture begins");
    const prefixStart = Math.max(0, data.length - 4096);
    const cursor = {
        schema: CURSOR_SCHEMA,
        logPath: resolvedLog,
        startOffset: data.length,
        prefixStart,
        prefixSha256: sha256(data.subarray(prefixStart)),
        createdAtUtc: new Date().toISOString()
    };
    fs.mkdirSync(path.dirname(resolvedCursor), { recursive: true });
    fs.writeFileSync(resolvedCursor, JSON.stringify(cursor, null, 2) + "\n", { flag: "wx" });
    return cursor;
}

function verifyCapture(cursorPath, maxCursorAgeMs) {
    const resolvedCursor = path.resolve(cursorPath);
    invariant(fs.existsSync(resolvedCursor), `capture cursor does not exist: ${resolvedCursor}`);
    const cursor = JSON.parse(fs.readFileSync(resolvedCursor, "utf8"));
    invariant(cursor && cursor.schema === CURSOR_SCHEMA, "unsupported capture cursor schema");
    invariant(typeof cursor.logPath === "string" && path.isAbsolute(cursor.logPath), "cursor log path must be absolute");
    invariant(Number.isSafeInteger(cursor.startOffset) && cursor.startOffset >= 0, "invalid cursor start offset");
    invariant(Number.isSafeInteger(cursor.prefixStart) && cursor.prefixStart >= 0
        && cursor.prefixStart <= cursor.startOffset, "invalid cursor prefix boundary");
    invariant(/^[0-9a-f]{64}$/.test(cursor.prefixSha256), "invalid cursor prefix digest");
    const created = Date.parse(cursor.createdAtUtc);
    invariant(Number.isFinite(created), "invalid cursor creation time");
    invariant(Date.now() - created >= 0 && Date.now() - created <= (maxCursorAgeMs || DEFAULT_MAX_CURSOR_AGE_MS),
        "capture cursor is stale; begin a fresh actual-wire run");
    const data = fs.readFileSync(cursor.logPath);
    invariant(data.length >= cursor.startOffset, "launcher log was truncated or rotated after capture");
    invariant(data.length > cursor.startOffset, "launcher log has no new bytes after the capture boundary");
    const prefix = data.subarray(cursor.prefixStart, cursor.startOffset);
    invariant(sha256(prefix) === cursor.prefixSha256, "launcher log prefix changed after capture");
    const slice = data.subarray(cursor.startOffset).toString("utf8");
    const events = parseStructuredEvents(slice);
    const report = verifyActualCrossStack(events);
    report.cursorPath = resolvedCursor;
    report.logPath = cursor.logPath;
    report.startOffset = cursor.startOffset;
    report.capturedAtUtc = cursor.createdAtUtc;
    report.verifiedAtUtc = new Date().toISOString();
    report.sliceSha256 = sha256(data.subarray(cursor.startOffset));
    return report;
}

function parseArgs(argv) {
    const result = { mode: "", log: "", cursor: "", out: "", maxAgeMinutes: 120 };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === "--begin" || arg === "--verify") result.mode = arg.slice(2);
        else if (arg === "--log") result.log = argv[++i] || "";
        else if (arg === "--cursor") result.cursor = argv[++i] || "";
        else if (arg === "--out") result.out = argv[++i] || "";
        else if (arg === "--max-age-minutes") result.maxAgeMinutes = Number(argv[++i]);
        else throw new Error(`unknown argument: ${arg}`);
    }
    return result;
}

function main(argv) {
    const args = parseArgs(argv);
    invariant(args.cursor, "usage: --begin --log <logs/launcher.log> --cursor <cursor.json> | --verify --cursor <cursor.json> [--out <report.json>]");
    if (args.mode === "begin") {
        invariant(args.log && !args.out, "--begin requires --log and does not accept --out");
        const cursor = beginCapture(args.log, args.cursor);
        process.stdout.write(`[ARMED] Chest S0 actual-wire capture offset=${cursor.startOffset} cursor=${path.resolve(args.cursor)}\n`);
        return;
    }
    invariant(args.mode === "verify" && !args.log, "--verify accepts --cursor, not --log");
    invariant(Number.isFinite(args.maxAgeMinutes) && args.maxAgeMinutes > 0 && args.maxAgeMinutes <= 1440,
        "--max-age-minutes must be in (0, 1440]");
    const report = verifyCapture(args.cursor, args.maxAgeMinutes * 60 * 1000);
    if (args.out) {
        const resolvedOut = path.resolve(args.out);
        fs.mkdirSync(path.dirname(resolvedOut), { recursive: true });
        fs.writeFileSync(resolvedOut, JSON.stringify(report, null, 2) + "\n", { flag: "wx" });
    }
    process.stdout.write(`[PASS] Chest S0 actual cross-stack: ${report.cases.length}/${report.cases.length} cases, ${report.eventCount} Host events\n`);
}

if (require.main === module) {
    try { main(process.argv.slice(2)); }
    catch (error) {
        process.stderr.write(`[FAIL] Chest S0 actual cross-stack: ${error.message}\n`);
        process.exitCode = 1;
    }
}

module.exports = {
    PREFIX,
    parseStructuredEvents,
    verifyActualCrossStack,
    beginCapture,
    verifyCapture
};
