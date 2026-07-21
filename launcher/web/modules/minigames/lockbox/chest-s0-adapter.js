(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.LockboxChestS0Adapter = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var SOURCE = "as2-chest-s0";
    var FIXTURE = "insurance-safe-s0-v1";
    var MAX_INT32 = 2147483647;
    var MESSAGE_TYPE = "lockbox_chest_s0";
    var AUTHORITY_TERMINAL = "COMPLETED_NO_REWARD";
    var AUTHORITY_TERMINALS = {
        COMPLETED_NO_REWARD: true,
        EXPIRED: true
    };

    var STATES = Object.freeze({
        DISABLED: "DISABLED",
        REJECTED: "REJECTED",
        UNBOUND: "UNBOUND",
        ACTIVE: "ACTIVE",
        OPEN_BIND_UNKNOWN: "OPEN_BIND_UNKNOWN",
        RESULT_PENDING: "RESULT_PENDING",
        RESULT_APPLIED: "RESULT_APPLIED",
        RECONCILE_REQUIRED: "RECONCILE_REQUIRED",
        TERMINAL_KNOWN: "TERMINAL_KNOWN",
        CLOSE_PENDING: "CLOSE_PENDING",
        CLOSE_UNKNOWN: "CLOSE_UNKNOWN",
        CLOSED: "CLOSED"
    });

    var IDENTITY_KEYS = [
        "flowHandle",
        "panelInstanceId",
        "documentEpoch",
        "source",
        "fixture"
    ];

    var FORBIDDEN_CAPABILITIES = [
        "reroll",
        "profile",
        "hint",
        "debug",
        "export"
    ];

    var RESULT_VALUES = {
        success: true,
        cancel: true,
        failure: true
    };

    var TELEMETRY_EVENTS = {
        bind: true,
        result: true,
        reconcile: true,
        close: true,
        error: true,
        unknown: true
    };

    var TELEMETRY_RESULTS = {
        success: true,
        cancel: true,
        failure: true,
        unknown: true,
        none: true
    };

    var TELEMETRY_ERRORS = {
        none: true,
        transport: true,
        timeout: true,
        protocol: true,
        stale: true,
        disabled: true,
        unknown: true
    };

    function hasOwn(value, key) {
        return Object.prototype.hasOwnProperty.call(value, key);
    }

    function isRecord(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function isIntegerInRange(value, min, max) {
        return typeof value === "number" && isFinite(value) && Math.floor(value) === value && value >= min && value <= max;
    }

    function isValidFlowCallId(value) {
        return isIntegerInRange(value, 1, MAX_INT32);
    }

    function isValidDocumentEpoch(value) {
        return isIntegerInRange(value, 1, MAX_INT32);
    }

    function isOpaqueId(value) {
        if (typeof value !== "string" || value.length < 1 || value.length > 256) return false;
        if (value !== value.replace(/^\s+|\s+$/g, "")) return false;
        return !/[\u0000-\u001f\u007f]/.test(value);
    }

    function hasExactKeys(value, requiredKeys, extraKeys) {
        if (!isRecord(value)) return false;
        var allowed = {};
        var i;
        for (i = 0; i < requiredKeys.length; i += 1) allowed[requiredKeys[i]] = true;
        for (i = 0; extraKeys && i < extraKeys.length; i += 1) allowed[extraKeys[i]] = true;
        var keys = Object.keys(value);
        if (keys.length !== requiredKeys.length + (extraKeys ? extraKeys.length : 0)) return false;
        for (i = 0; i < keys.length; i += 1) {
            if (!hasOwn(allowed, keys[i])) return false;
        }
        for (i = 0; i < requiredKeys.length; i += 1) {
            if (!hasOwn(value, requiredKeys[i])) return false;
        }
        for (i = 0; extraKeys && i < extraKeys.length; i += 1) {
            if (!hasOwn(value, extraKeys[i])) return false;
        }
        return true;
    }

    function identityPayload(identity) {
        return {
            flowHandle: identity.flowHandle,
            panelInstanceId: identity.panelInstanceId,
            documentEpoch: identity.documentEpoch,
            source: identity.source,
            fixture: identity.fixture
        };
    }

    function validateIdentity(value) {
        if (!hasExactKeys(value, IDENTITY_KEYS)) {
            return { ok: false, code: "identity_schema_mismatch" };
        }
        if (!isOpaqueId(value.flowHandle)) {
            return { ok: false, code: "invalid_flow_handle" };
        }
        if (!isOpaqueId(value.panelInstanceId)) {
            return { ok: false, code: "invalid_panel_instance" };
        }
        if (!isValidDocumentEpoch(value.documentEpoch)) {
            return { ok: false, code: "invalid_document_epoch" };
        }
        if (value.source !== SOURCE) {
            return { ok: false, code: "source_mismatch" };
        }
        if (value.fixture !== FIXTURE) {
            return { ok: false, code: "fixture_mismatch" };
        }
        return { ok: true, identity: identityPayload(value) };
    }

    function sameIdentity(identity, value, extraKeys) {
        if (!identity || !hasExactKeys(value, IDENTITY_KEYS, extraKeys)) return false;
        return value.flowHandle === identity.flowHandle &&
            value.panelInstanceId === identity.panelInstanceId &&
            value.documentEpoch === identity.documentEpoch &&
            value.source === identity.source &&
            value.fixture === identity.fixture;
    }

    function extendIdentity(identity, extra) {
        var payload = identityPayload(identity);
        var key;
        for (key in extra) {
            if (hasOwn(extra, key)) payload[key] = extra[key];
        }
        return payload;
    }

    function mapCoreOutcome(outcome) {
        if (outcome === "success" || outcome === "partial_success") return "success";
        if (outcome === "fail") return "failure";
        return null;
    }

    function pickCategory(value, allowed, fallback) {
        return typeof value === "string" && hasOwn(allowed, value) ? value : fallback;
    }

    function durationBucket(durationMs) {
        if (typeof durationMs !== "number" || !isFinite(durationMs) || durationMs < 0) return "unknown";
        if (durationMs < 1000) return "lt_1s";
        if (durationMs < 5000) return "1_5s";
        if (durationMs < 30000) return "5_30s";
        return "gte_30s";
    }

    function buildTelemetry(input) {
        input = isRecord(input) ? input : {};
        return {
            eventCategory: pickCategory(input.eventCategory, TELEMETRY_EVENTS, "unknown"),
            resultCategory: pickCategory(input.resultCategory, TELEMETRY_RESULTS, "unknown"),
            durationBucket: durationBucket(input.durationMs),
            errorCategory: pickCategory(input.errorCategory, TELEMETRY_ERRORS, "unknown")
        };
    }

    function createAdapter(options) {
        options = isRecord(options) ? options : {};
        var enabled = options.enabled === true && typeof options.send === "function";
        var send = typeof options.send === "function" ? options.send : null;
        var state = STATES.DISABLED;
        var identity = null;
        var bound = false;
        var resultSubmitted = false;
        var pendingResult = null;
        var pendingCallId = 0;
        var unknownCallId = 0;
        var epochChanged = false;
        var currentDocumentEpoch = 0;
        var lastCode = enabled ? "not_initialized" : "disabled";

        function outcome(ok, code, extra) {
            var value = {
                ok: ok,
                code: code,
                state: state
            };
            var key;
            for (key in extra) {
                if (hasOwn(extra, key)) value[key] = extra[key];
            }
            return value;
        }

        function emit(cmd, payload) {
            if (!enabled || !send) return false;
            try {
                return send({
                    type: MESSAGE_TYPE,
                    cmd: cmd,
                    payload: payload
                }) !== false;
            } catch (error) {
                return false;
            }
        }

        function reject(code) {
            lastCode = code;
            return outcome(false, code);
        }

        function initialize(initData) {
            if (!enabled) return reject("disabled");
            if (identity && state !== STATES.CLOSED && state !== STATES.REJECTED) {
                return reject("flow_busy");
            }
            var checked = validateIdentity(initData);
            if (!checked.ok) {
                state = STATES.REJECTED;
                return reject(checked.code);
            }
            identity = checked.identity;
            state = STATES.UNBOUND;
            bound = false;
            resultSubmitted = false;
            pendingResult = null;
            pendingCallId = 0;
            unknownCallId = 0;
            epochChanged = false;
            currentDocumentEpoch = identity.documentEpoch;
            lastCode = "initialized";
            return outcome(true, "initialized");
        }

        function bind() {
            if (state !== STATES.UNBOUND || !identity) return reject("bind_not_allowed");
            bound = true;
            var delivered = emit("bind", identityPayload(identity));
            if (!delivered) {
                state = STATES.OPEN_BIND_UNKNOWN;
                return reject("bind_delivery_unknown");
            }
            state = STATES.ACTIVE;
            lastCode = "bound";
            return outcome(true, "bound");
        }

        function markBindUnknown() {
            if (state !== STATES.ACTIVE && state !== STATES.OPEN_BIND_UNKNOWN) {
                return reject("bind_unknown_not_allowed");
            }
            state = STATES.OPEN_BIND_UNKNOWN;
            lastCode = "bind_unknown";
            return outcome(true, "bind_unknown");
        }

        function answerBindQuery(query) {
            if (!sameIdentity(identity, query)) return reject("stale_identity");
            if (epochChanged || state === STATES.RECONCILE_REQUIRED || state === STATES.CLOSE_UNKNOWN) {
                return reject("reconcile_required");
            }
            var binding;
            if (state === STATES.CLOSED) binding = "closed";
            else if (bound) binding = "bound";
            else if (state === STATES.UNBOUND) binding = "unbound";
            else binding = "unknown";
            var delivered = emit("bind_query_result", extendIdentity(identity, { binding: binding }));
            if (!delivered) return reject("query_delivery_unknown");
            if (binding === "bound" && state === STATES.OPEN_BIND_UNKNOWN) state = STATES.ACTIVE;
            lastCode = "bind_query_answered";
            return outcome(true, "bind_query_answered", { binding: binding });
        }

        function submitLimitedResult(result) {
            if (state !== STATES.ACTIVE) return reject("result_not_allowed");
            if (resultSubmitted) return reject("result_already_submitted");
            if (!hasOwn(RESULT_VALUES, result)) return reject("unsupported_result");
            pendingCallId = 1;
            if (!isValidFlowCallId(pendingCallId)) return reject("flow_call_id_exhausted");
            resultSubmitted = true;
            pendingResult = result;
            state = STATES.RESULT_PENDING;
            var delivered = emit("result", extendIdentity(identity, {
                flowCallId: pendingCallId,
                result: result
            }));
            if (!delivered) {
                unknownCallId = pendingCallId;
                state = STATES.RECONCILE_REQUIRED;
                return reject("result_delivery_unknown");
            }
            lastCode = "result_pending";
            return outcome(true, "result_pending", { flowCallId: pendingCallId });
        }

        function submitCoreOutcome(coreOutcome) {
            var mapped = mapCoreOutcome(coreOutcome);
            if (!mapped) return reject("unsupported_core_outcome");
            return submitLimitedResult(mapped);
        }

        function submitUserCancel() {
            return submitLimitedResult("cancel");
        }

        function handleResultAck(ack) {
            var extras = ["flowCallId", "result", "applied", "authorityTerminal"];
            if (!sameIdentity(identity, ack, extras)) return reject("stale_identity");
            if (epochChanged) return reject("reconcile_required");
            if (!isValidFlowCallId(ack.flowCallId) || ack.flowCallId !== pendingCallId) {
                return reject("stale_flow_call");
            }
            if (typeof ack.authorityTerminal !== "boolean") {
                return reject("invalid_authority_terminal");
            }
            if (ack.applied !== true || ack.result !== pendingResult) {
                return reject("ack_mismatch");
            }
            if (state !== STATES.RESULT_PENDING && state !== STATES.RECONCILE_REQUIRED) {
                return reject("result_ack_not_allowed");
            }
            if (ack.result !== "success" && ack.authorityTerminal !== true) {
                return reject("authority_terminal_required");
            }
            state = ack.authorityTerminal ? STATES.TERMINAL_KNOWN : STATES.RESULT_APPLIED;
            unknownCallId = 0;
            lastCode = ack.authorityTerminal ? "result_terminal" : "result_applied";
            return outcome(true, lastCode);
        }

        function markResultUnknown() {
            if (state !== STATES.RESULT_PENDING) return reject("result_unknown_not_allowed");
            unknownCallId = pendingCallId;
            state = STATES.RECONCILE_REQUIRED;
            lastCode = "result_unknown";
            return outcome(true, "result_unknown");
        }

        function requestResultQuery() {
            if (state !== STATES.RECONCILE_REQUIRED || !isValidFlowCallId(unknownCallId) || epochChanged) {
                return reject("result_query_not_allowed");
            }
            var delivered = emit("result_query", extendIdentity(identity, {
                unknownFlowCallId: unknownCallId
            }));
            if (!delivered) return reject("query_delivery_unknown");
            lastCode = "result_query_pending";
            return outcome(true, "result_query_pending");
        }

        function handleReconcileReply(reply) {
            var extras = ["flowCallId", "observedCallWatermark", "disposition", "authorityTerminal"];
            if (!sameIdentity(identity, reply, extras)) return reject("stale_identity");
            if (state !== STATES.RECONCILE_REQUIRED || epochChanged) {
                return reject("reconcile_not_allowed");
            }
            if (!isValidFlowCallId(reply.flowCallId) || reply.flowCallId !== unknownCallId) {
                return reject("stale_flow_call");
            }
            if (!isValidFlowCallId(reply.observedCallWatermark) || reply.observedCallWatermark < unknownCallId) {
                return reject("stale_watermark");
            }
            if (reply.disposition !== "not_applied" && !hasOwn(RESULT_VALUES, reply.disposition)) {
                return reject("unsupported_disposition");
            }
            if (reply.disposition !== "not_applied" && reply.disposition !== pendingResult) {
                return reject("disposition_mismatch");
            }
            if (typeof reply.authorityTerminal !== "boolean") {
                return reject("invalid_authority_terminal");
            }
            if (reply.disposition !== "success" && reply.authorityTerminal !== true) {
                return reject("authority_terminal_required");
            }
            state = reply.authorityTerminal ? STATES.TERMINAL_KNOWN : STATES.RESULT_APPLIED;
            unknownCallId = 0;
            lastCode = reply.authorityTerminal ? "reconciled_terminal" : "reconciled_applied";
            return outcome(true, lastCode, { disposition: reply.disposition });
        }

        function handleAuthorityTerminal(authorityAck) {
            var extras = ["flowCallId", "terminal"];
            if (!sameIdentity(identity, authorityAck, extras)) return reject("stale_identity");
            if (epochChanged) return reject("reconcile_required");
            if (!isValidFlowCallId(authorityAck.flowCallId)) {
                return reject("stale_flow_call");
            }
            if (typeof authorityAck.terminal !== "string" || !hasOwn(AUTHORITY_TERMINALS, authorityAck.terminal)) {
                return reject("unsupported_authority_terminal");
            }
            // AS2 may expire/revoke a bound session before Web has submitted flowCallId=1
            // (scene unload, target invalidation, or known open failure).  This is a legitimate
            // zero-write terminal and must still drive the exact close handshake.  A completed
            // authority, in contrast, always requires the submitted success result.
            if (authorityAck.terminal === "EXPIRED" && !resultSubmitted
                    && authorityAck.flowCallId === 1
                    && state !== STATES.CLOSED && state !== STATES.CLOSE_PENDING
                    && state !== STATES.CLOSE_UNKNOWN && state !== STATES.REJECTED) {
                state = STATES.TERMINAL_KNOWN;
                unknownCallId = 0;
                lastCode = "authority_expired_without_write";
                return outcome(true, lastCode);
            }
            if (authorityAck.flowCallId !== pendingCallId) return reject("stale_flow_call");
            if (state !== STATES.RESULT_APPLIED) {
                return reject("authority_terminal_not_allowed");
            }
            state = STATES.TERMINAL_KNOWN;
            lastCode = "authority_terminal_known";
            return outcome(true, "authority_terminal_known");
        }

        function acceptExactClose(closeRequest) {
            if (!sameIdentity(identity, closeRequest)) return reject("stale_identity");
            if (state !== STATES.TERMINAL_KNOWN) return reject("close_not_allowed");
            state = STATES.CLOSE_PENDING;
            lastCode = "close_accepted";
            return outcome(true, "close_accepted");
        }

        function completeClose() {
            if (state !== STATES.CLOSE_PENDING) return reject("close_complete_not_allowed");
            bound = false;
            var delivered = emit("close_ack", identityPayload(identity));
            if (!delivered) {
                state = STATES.CLOSE_UNKNOWN;
                return reject("close_delivery_unknown");
            }
            state = STATES.CLOSED;
            lastCode = "closed";
            return outcome(true, "closed");
        }

        function retryCloseAck() {
            if (state !== STATES.CLOSE_UNKNOWN) return reject("close_retry_not_allowed");
            var delivered = emit("close_ack", identityPayload(identity));
            if (!delivered) return reject("close_delivery_unknown");
            state = STATES.CLOSED;
            lastCode = "closed_after_retry";
            return outcome(true, "closed_after_retry");
        }

        // postMessage=true 只表示同步入队成功，不证明 Host 已观测。CLOSED adapter 因此
        // 继续充当有界 exact-proof tombstone，matching close_query 可幂等重放。
        function replayCloseAck() {
            if (state !== STATES.CLOSED || !identity) return reject("close_replay_not_allowed");
            var delivered = emit("close_ack", identityPayload(identity));
            if (!delivered) return reject("close_replay_delivery_unknown");
            lastCode = "closed_replayed";
            return outcome(true, "closed_replayed");
        }

        function observeDocumentEpoch(documentEpoch) {
            if (!isValidDocumentEpoch(documentEpoch)) return reject("invalid_document_epoch");
            if (!identity) return reject("not_initialized");
            if (documentEpoch < currentDocumentEpoch) return reject("stale_document_epoch");
            if (documentEpoch === currentDocumentEpoch) return outcome(true, "same_document_epoch");
            currentDocumentEpoch = documentEpoch;
            epochChanged = true;
            state = STATES.RECONCILE_REQUIRED;
            lastCode = "document_epoch_changed";
            return outcome(false, "document_epoch_changed");
        }

        function isCapabilityAllowed(name) {
            var i;
            for (i = 0; i < FORBIDDEN_CAPABILITIES.length; i += 1) {
                if (FORBIDDEN_CAPABILITIES[i] === name) return false;
            }
            return false;
        }

        function getSnapshot() {
            return {
                enabled: enabled,
                state: state,
                initialized: !!identity,
                bound: bound,
                resultSubmitted: resultSubmitted,
                pendingFlowCallId: pendingCallId || null,
                canClose: state === STATES.TERMINAL_KNOWN,
                canReleasePause: state === STATES.CLOSED,
                requiresReconcile: state === STATES.RECONCILE_REQUIRED || state === STATES.OPEN_BIND_UNKNOWN || state === STATES.CLOSE_UNKNOWN,
                lastCode: lastCode
            };
        }

        return {
            initialize: initialize,
            bind: bind,
            markBindUnknown: markBindUnknown,
            answerBindQuery: answerBindQuery,
            submitCoreOutcome: submitCoreOutcome,
            submitUserCancel: submitUserCancel,
            handleResultAck: handleResultAck,
            handleAuthorityTerminal: handleAuthorityTerminal,
            markResultUnknown: markResultUnknown,
            requestResultQuery: requestResultQuery,
            handleReconcileReply: handleReconcileReply,
            acceptExactClose: acceptExactClose,
            completeClose: completeClose,
            retryCloseAck: retryCloseAck,
            replayCloseAck: replayCloseAck,
            observeDocumentEpoch: observeDocumentEpoch,
            isCapabilityAllowed: isCapabilityAllowed,
            getSnapshot: getSnapshot
        };
    }

    return {
        SOURCE: SOURCE,
        FIXTURE: FIXTURE,
        MAX_INT32: MAX_INT32,
        MESSAGE_TYPE: MESSAGE_TYPE,
        AUTHORITY_TERMINAL: AUTHORITY_TERMINAL,
        AUTHORITY_TERMINALS: ["COMPLETED_NO_REWARD", "EXPIRED"],
        STATES: STATES,
        FORBIDDEN_CAPABILITIES: FORBIDDEN_CAPABILITIES.slice(),
        createAdapter: createAdapter,
        validateIdentity: validateIdentity,
        isValidFlowCallId: isValidFlowCallId,
        isValidDocumentEpoch: isValidDocumentEpoch,
        mapCoreOutcome: mapCoreOutcome,
        buildTelemetry: buildTelemetry
    };
});
