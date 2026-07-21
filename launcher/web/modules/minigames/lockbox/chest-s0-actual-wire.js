(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory(require("./chest-s0-adapter.js"));
    } else {
        root.LockboxChestS0ActualWire = factory(root.LockboxChestS0Adapter);
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function(S0) {
    "use strict";

    var CONTROL_TYPE = "lockbox_chest_s0_control";
    var EXECUTION_MODE = "actual-webview2-dev-wire";
    var PROTOCOL_VERSION = 1;
    var MAX_SAFE_INTEGER = 9007199254740991;
    var ARM_KEYS = [
        "protocolVersion",
        "capability",
        "connectionGeneration",
        "gameProcessId",
        "documentEpoch",
        "source",
        "fixture"
    ];
    var IDENTITY_KEYS = [
        "flowHandle",
        "panelInstanceId",
        "documentEpoch",
        "source",
        "fixture"
    ];
    var OPEN_KEYS = ARM_KEYS.concat(["flowHandle", "panelInstanceId"]);

    function hasOwn(value, key) {
        return Object.prototype.hasOwnProperty.call(value, key);
    }

    function isRecord(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function hasExactKeys(value, keys) {
        if (!isRecord(value)) return false;
        var actual = Object.keys(value);
        if (actual.length !== keys.length) return false;
        var allowed = {};
        var i;
        for (i = 0; i < keys.length; i += 1) allowed[keys[i]] = true;
        for (i = 0; i < actual.length; i += 1) {
            if (!hasOwn(allowed, actual[i])) return false;
        }
        for (i = 0; i < keys.length; i += 1) {
            if (!hasOwn(value, keys[i])) return false;
        }
        return true;
    }

    function isIntegerInRange(value, min, max) {
        return typeof value === "number" && isFinite(value)
            && Math.floor(value) === value && value >= min && value <= max;
    }

    function isOpaqueId(value) {
        return typeof value === "string" && value.length >= 1 && value.length <= 256
            && value === value.replace(/^\s+|\s+$/g, "")
            && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function cloneArm(value) {
        return {
            protocolVersion: value.protocolVersion,
            capability: value.capability,
            connectionGeneration: value.connectionGeneration,
            gameProcessId: value.gameProcessId,
            documentEpoch: value.documentEpoch,
            source: value.source,
            fixture: value.fixture
        };
    }

    function identityFromOpen(value) {
        return {
            flowHandle: value.flowHandle,
            panelInstanceId: value.panelInstanceId,
            documentEpoch: value.documentEpoch,
            source: value.source,
            fixture: value.fixture
        };
    }

    function validateArmPayload(value) {
        if (!hasExactKeys(value, ARM_KEYS)) return { ok: false, code: "arm_schema_mismatch" };
        if (value.protocolVersion !== PROTOCOL_VERSION) return { ok: false, code: "protocol_version_mismatch" };
        if (!isOpaqueId(value.capability)) return { ok: false, code: "invalid_capability" };
        if (!isIntegerInRange(value.connectionGeneration, 1, MAX_SAFE_INTEGER)) {
            return { ok: false, code: "invalid_connection_generation" };
        }
        if (!isIntegerInRange(value.gameProcessId, 1, 2147483647)) {
            return { ok: false, code: "invalid_game_process_id" };
        }
        if (!S0 || !S0.isValidDocumentEpoch(value.documentEpoch)) {
            return { ok: false, code: "invalid_document_epoch" };
        }
        if (value.source !== S0.SOURCE) return { ok: false, code: "source_mismatch" };
        if (value.fixture !== S0.FIXTURE) return { ok: false, code: "fixture_mismatch" };
        return { ok: true, arm: cloneArm(value) };
    }

    function validateOpenInitData(value, arm) {
        if (!hasExactKeys(value, OPEN_KEYS)) return { ok: false, code: "open_schema_mismatch" };
        var checked = validateArmPayload({
            protocolVersion: value.protocolVersion,
            capability: value.capability,
            connectionGeneration: value.connectionGeneration,
            gameProcessId: value.gameProcessId,
            documentEpoch: value.documentEpoch,
            source: value.source,
            fixture: value.fixture
        });
        if (!checked.ok) return checked;
        if (!arm || value.capability !== arm.capability
                || value.connectionGeneration !== arm.connectionGeneration
                || value.gameProcessId !== arm.gameProcessId
                || value.documentEpoch !== arm.documentEpoch
                || value.source !== arm.source || value.fixture !== arm.fixture) {
            return { ok: false, code: "arm_mismatch" };
        }
        if (!isOpaqueId(value.flowHandle)) return { ok: false, code: "invalid_flow_handle" };
        if (!isOpaqueId(value.panelInstanceId)) return { ok: false, code: "invalid_panel_instance" };
        return { ok: true, identity: identityFromOpen(value) };
    }

    function looksLikeS0Open(value) {
        if (!isRecord(value)) return false;
        // A dedicated S0 marker always remains fail-closed, even when the rest of its envelope
        // is malformed.  Without either marker, reserve only the complete Host protocol +
        // identity shape so ordinary fields such as panelInstanceId can evolve independently.
        if (value.source === S0.SOURCE || value.fixture === S0.FIXTURE) return true;
        for (var i = 0; i < OPEN_KEYS.length; i += 1) {
            if (!hasOwn(value, OPEN_KEYS[i])) return false;
        }
        return true;
    }

    function createRejectedPayload(arm, code) {
        var payload = cloneArm(arm);
        payload.code = code;
        return payload;
    }

    function createTeardownPayload(arm, reason) {
        var payload = cloneArm(arm);
        payload.reason = reason;
        return payload;
    }

    function armFromOpen(value) {
        if (!isRecord(value)) return null;
        var checked = validateArmPayload({
            protocolVersion: value.protocolVersion,
            capability: value.capability,
            connectionGeneration: value.connectionGeneration,
            gameProcessId: value.gameProcessId,
            documentEpoch: value.documentEpoch,
            source: value.source,
            fixture: value.fixture
        });
        return checked.ok ? checked.arm : null;
    }

    function snapshotAttribute(el, name) {
        var present = !!(el && el.hasAttribute && el.hasAttribute(name));
        return {
            present: present,
            value: present && el.getAttribute ? el.getAttribute(name) : null
        };
    }

    function restoreAttribute(el, name, snapshot) {
        if (!el || !snapshot) return;
        if (snapshot.present) el.setAttribute(name, snapshot.value === null ? "" : snapshot.value);
        else if (el.removeAttribute) el.removeAttribute(name);
    }

    function snapshotFlowElement(el) {
        return {
            el: el,
            pointerEvents: el && el.style ? el.style.pointerEvents : "",
            ariaBusy: snapshotAttribute(el, "aria-busy"),
            inert: snapshotAttribute(el, "inert"),
            flow: snapshotAttribute(el, "data-lockbox-s0-flow"),
            pending: snapshotAttribute(el, "data-lockbox-s0-pending")
        };
    }

    function install(options) {
        options = isRecord(options) ? options : {};
        var bridge = options.bridge;
        var panels = options.panels;
        var checkedArm = validateArmPayload(options.arm);
        if (!checkedArm.ok) return { ok: false, code: checkedArm.code };
        if (!bridge || typeof bridge.send !== "function" || typeof bridge.on !== "function"
                || typeof bridge.off !== "function") {
            return { ok: false, code: "bridge_unavailable" };
        }
        if (!panels || typeof panels.installRegistrationDecorator !== "function"
                || typeof panels.getActive !== "function" || typeof panels.close !== "function") {
            return { ok: false, code: "panels_decorator_unavailable" };
        }
        if (panels.getActive() !== null) return { ok: false, code: "panel_orchestration_busy" };

        var originalBridgeSend = bridge.send;
        var arm = checkedArm.arm;
        var state = "ARMED";
        var current = null;
        var lastFlow = null;
        var sequence = 0;
        var events = [];
        var usedCapabilities = Object.create(null);
        var closeCapture = null;
        var pendingTeardown = null;
        var teardownProof = null;
        var closedProof = null;
        var teardownRetryTimer = null;
        var forcedTeardownIdentity = null;
        var resultQueryRetryTimer = null;
        var resultAckTimer = null;
        var resultAckTimeoutMs = typeof options.resultAckTimeoutMs === "number"
                && isFinite(options.resultAckTimeoutMs)
                && Math.floor(options.resultAckTimeoutMs) === options.resultAckTimeoutMs
                && options.resultAckTimeoutMs >= 10
            ? options.resultAckTimeoutMs : 250;

        function record(event, code, evidenceIdentity) {
            var identity = evidenceIdentity || (current ? current.identity : null);
            sequence += 1;
            events.push({
                sequence: sequence,
                event: event,
                code: code || "none",
                flowHandle: identity ? identity.flowHandle : null,
                panelInstanceId: identity ? identity.panelInstanceId : null,
                documentEpoch: identity ? identity.documentEpoch : null
            });
            if (events.length > 80) events.shift();
        }

        function sendHost(message) {
            try {
                return originalBridgeSend(message) !== false;
            } catch (error) {
                return false;
            }
        }

        function reportRejected(code, rejectedArm) {
            record("rejected", code);
            var checked = validateArmPayload(rejectedArm || arm);
            if (checked.ok && typeof options.onRejected === "function") {
                options.onRejected(createRejectedPayload(checked.arm, code));
            }
        }

        function reportRuntimeRejected(code, rejectedArm) {
            record("runtime_rejected", code);
            var checked = validateArmPayload(rejectedArm || arm);
            if (checked.ok && typeof options.onRuntimeRejected === "function") {
                options.onRuntimeRejected(createRejectedPayload(checked.arm, code));
            }
        }

        function reportTeardown(reason, teardownArm, context) {
            var checked = validateArmPayload(teardownArm || arm);
            if (!checked.ok || typeof options.onTeardown !== "function") return false;
            return options.onTeardown(createTeardownPayload(checked.arm, reason), context) !== false;
        }

        function sameIdentity(identity, payload) {
            return identity && hasExactKeys(payload, IDENTITY_KEYS)
                && payload.flowHandle === identity.flowHandle
                && payload.panelInstanceId === identity.panelInstanceId
                && payload.documentEpoch === identity.documentEpoch
                && payload.source === identity.source
                && payload.fixture === identity.fixture;
        }

        function replayTeardownProof(proof) {
            if (!proof) return false;
            var wasPending = pendingTeardown === proof;
            var delivered = reportTeardown(proof.reason, proof.arm, {
                replay: true,
                pending: wasPending
            });
            record("teardown_ack_retry", delivered ? proof.reason : "delivery_unknown",
                proof.identity);
            if (!delivered) {
                if (wasPending) scheduleTeardownRetry();
                return false;
            }
            if (wasPending) {
                pendingTeardown = null;
                if (!current && state === "TEARDOWN_UNKNOWN") state = "IDLE";
                markEvidenceRoot(state);
                if (teardownRetryTimer !== null && typeof clearTimeout === "function") {
                    clearTimeout(teardownRetryTimer);
                    teardownRetryTimer = null;
                }
            }
            return true;
        }

        function finishPendingTeardown() {
            return pendingTeardown ? replayTeardownProof(pendingTeardown) : false;
        }

        function scheduleTeardownRetry() {
            if (!pendingTeardown || teardownRetryTimer !== null
                    || typeof setTimeout !== "function") return;
            teardownRetryTimer = setTimeout(function() {
                teardownRetryTimer = null;
                if (!finishPendingTeardown()) scheduleTeardownRetry();
            }, 250);
        }

        function stopResultQueryRetry() {
            if (resultQueryRetryTimer !== null && typeof clearTimeout === "function") {
                clearTimeout(resultQueryRetryTimer);
                resultQueryRetryTimer = null;
            }
        }

        function stopResultAckTimer() {
            if (resultAckTimer !== null && typeof clearTimeout === "function") {
                clearTimeout(resultAckTimer);
                resultAckTimer = null;
            }
        }

        function beginResultReconcileIfNeeded(flow) {
            if (!current || (flow && current !== flow)) return;
            var snapshot = current.adapter.getSnapshot();
            if (snapshot.state === S0.STATES.RESULT_PENDING) {
                // Duplicate result/cancel input never extends the first delivery deadline.
                if (resultAckTimer !== null) return;
                if (typeof setTimeout !== "function") return;
                var expectedFlow = current;
                resultAckTimer = setTimeout(function() {
                    resultAckTimer = null;
                    if (!current || current !== expectedFlow
                            || current.adapter.getSnapshot().state !== S0.STATES.RESULT_PENDING) return;
                    var unknown = current.adapter.markResultUnknown();
                    record("result_ack_timeout", unknown.code);
                    if (unknown.ok) beginResultReconcileIfNeeded(expectedFlow);
                }, resultAckTimeoutMs);
                return;
            }
            if (snapshot.state !== S0.STATES.RECONCILE_REQUIRED) return;
            stopResultAckTimer();
            var query = current.adapter.requestResultQuery();
            record("result_query", query.code);
            scheduleResultQueryRetry();
        }

        function scheduleResultQueryRetry() {
            if (!current || resultQueryRetryTimer !== null
                    || typeof setTimeout !== "function") return;
            if (current.adapter.getSnapshot().state !== S0.STATES.RECONCILE_REQUIRED) return;
            resultQueryRetryTimer = setTimeout(function() {
                resultQueryRetryTimer = null;
                if (!current
                        || current.adapter.getSnapshot().state !== S0.STATES.RECONCILE_REQUIRED) {
                    return;
                }
                var queried = current.adapter.requestResultQuery();
                record("result_query_retry", queried.code);
                scheduleResultQueryRetry();
            }, 250);
        }

        function markEvidenceRoot(status) {
            if (typeof document === "undefined" || !document.documentElement) return;
            document.documentElement.setAttribute("data-lockbox-s0-wire", EXECUTION_MODE);
            document.documentElement.setAttribute("data-lockbox-s0-wire-state", status.toLowerCase());
            document.documentElement.setAttribute("data-lockbox-s0-host-evidence-required", "true");
        }

        function disableForbiddenControls(el) {
            if (!el || !el.querySelectorAll) return [];
            var selectors = [
                '[data-action="reroll"]',
                '[data-action="export"]',
                '[data-action="hint"]',
                '[data-action="toggle-hud"]',
                "#lockbox-profile-switch",
                ".lockbox-hud"
            ];
            var nodes = el.querySelectorAll(selectors.join(","));
            var snapshots = [];
            for (var i = 0; i < nodes.length; i += 1) {
                snapshots.push({
                    node: nodes[i],
                    display: nodes[i].style.display,
                    disabled: "disabled" in nodes[i] ? nodes[i].disabled : undefined,
                    ariaHidden: nodes[i].getAttribute ? nodes[i].getAttribute("aria-hidden") : null
                });
                nodes[i].setAttribute("aria-hidden", "true");
                nodes[i].style.display = "none";
                if ("disabled" in nodes[i]) nodes[i].disabled = true;
            }
            el.setAttribute("data-lockbox-s0-flow", "active");
            return snapshots;
        }

        function restoreForbiddenControls(flow) {
            if (!flow || !flow.restrictions) return;
            for (var i = 0; i < flow.restrictions.length; i += 1) {
                var item = flow.restrictions[i];
                item.node.style.display = item.display;
                if (item.disabled !== undefined) item.node.disabled = item.disabled;
                if (item.node.setAttribute && item.node.removeAttribute) {
                    if (item.ariaHidden === null) item.node.removeAttribute("aria-hidden");
                    else item.node.setAttribute("aria-hidden", item.ariaHidden);
                }
            }
            flow.restrictions = [];
        }

        function freezeCurrentInteraction(reason) {
            if (!current || !current.el) return;
            current.el.style.pointerEvents = "none";
            current.el.setAttribute("aria-busy", "true");
            current.el.setAttribute("inert", "");
            current.el.setAttribute("data-lockbox-s0-pending", reason || "authority");
        }

        function unfreezeCurrentInteraction() {
            if (!current || !current.el || !current.rootSnapshot) return;
            current.el.style.pointerEvents = current.rootSnapshot.pointerEvents;
            restoreAttribute(current.el, "aria-busy", current.rootSnapshot.ariaBusy);
            restoreAttribute(current.el, "inert", current.rootSnapshot.inert);
            restoreAttribute(current.el, "data-lockbox-s0-pending", current.rootSnapshot.pending);
        }

        function restoreFlowElement(snapshot) {
            if (!snapshot || !snapshot.el) return;
            var el = snapshot.el;
            el.style.pointerEvents = snapshot.pointerEvents;
            restoreAttribute(el, "aria-busy", snapshot.ariaBusy);
            restoreAttribute(el, "inert", snapshot.inert);
            restoreAttribute(el, "data-lockbox-s0-flow", snapshot.flow);
            restoreAttribute(el, "data-lockbox-s0-pending", snapshot.pending);
        }

        function requestUserCancel() {
            if (!current) return { ok: false, code: "stale_identity" };
            var flow = current;
            var outcome = current.adapter.submitUserCancel();
            record("user_cancel", outcome.code);
            if (outcome.ok || current.adapter.getSnapshot().resultSubmitted) {
                freezeCurrentInteraction("cancel");
            }
            beginResultReconcileIfNeeded(flow);
            return outcome;
        }

        function installCloseCapture(el) {
            if (!el || typeof el.addEventListener !== "function") return;
            closeCapture = function(event) {
                var target = event && event.target;
                var closeButton = target && target.closest ? target.closest(".minigame-close-btn") : null;
                if (!closeButton || !el.contains(closeButton)) return;
                event.preventDefault();
                event.stopPropagation();
                if (event.stopImmediatePropagation) event.stopImmediatePropagation();
                requestUserCancel();
            };
            el.addEventListener("click", closeCapture, true);
        }

        function removeCloseCapture() {
            if (current && current.el && closeCapture) {
                current.el.removeEventListener("click", closeCapture, true);
            }
            closeCapture = null;
        }

        function sanitizedGameInit() {
            return {
                mode: "dev",
                profile: "standard",
                source: "runtime",
                familySeed: 1392508929,
                variantIndex: 0,
                hintMode: "off",
                debug: false
            };
        }

        function rejectArmedOpen(el, code, consume, rejectedArm, rejectedIdentity) {
            if (consume && arm) {
                usedCapabilities[arm.capability] = true;
                if (typeof options.onConsume === "function") options.onConsume();
                state = "REJECTED";
                markEvidenceRoot(state);
            }
            if (el && el.setAttribute) {
                el.setAttribute("data-lockbox-s0-flow", "rejected");
                el.setAttribute("inert", "");
            }
            if (consume) {
                forcedTeardownIdentity = rejectedIdentity || null;
                reportRuntimeRejected(code, rejectedArm);
                scheduleForcedTeardown("runtime_rejected");
            } else {
                reportRejected(code, rejectedArm);
            }
        }

        function completeForcedTeardown(reason) {
            var teardownArm = arm;
            var teardownIdentity = current ? current.identity : forcedTeardownIdentity;
            forcedTeardownIdentity = null;
            if (panels.getActive() === "lockbox") panels.close();
            if (panels.getActive() !== null) {
                record("teardown_blocked", "other_panel_active");
                return false;
            }
            if (current) {
                stopResultAckTimer();
                stopResultQueryRetry();
                removeCloseCapture();
                restoreForbiddenControls(current);
                lastFlow = current;
                current = null;
            }
            arm = null;
            teardownProof = {
                arm: teardownArm,
                identity: teardownIdentity,
                reason: reason
            };
            var reported = reportTeardown(reason, teardownArm, {
                replay: false,
                pending: false
            });
            if (reported) {
                pendingTeardown = null;
                state = "IDLE";
            } else {
                state = "TEARDOWN_UNKNOWN";
                pendingTeardown = teardownProof;
                scheduleTeardownRetry();
            }
            markEvidenceRoot(state);
            record("teardown_ack", reported ? reason : "delivery_unknown", teardownIdentity);
            return reported;
        }

        function scheduleForcedTeardown(reason) {
            Promise.resolve().then(function() { completeForcedTeardown(reason); });
        }

        function decorateLockboxSpec(spec) {
            if (!spec || spec.__lockboxChestS0ActualWireWrapped) return spec;
            var wrapped = {};
            var key;
            for (key in spec) {
                if (hasOwn(spec, key)) wrapped[key] = spec[key];
            }
            var originalOnOpen = spec.onOpen;
            var originalOnClose = spec.onClose;
            var originalOnForceClose = spec.onForceClose;
            var originalOnRequestClose = spec.onRequestClose;
            var decoratedElementSnapshot = null;
            var panelOpenSequence = 0;
            var rejectedOpenCloseToken = null;
            wrapped.__lockboxChestS0ActualWireWrapped = true;

            function restoreRejectedOpenElement() {
                restoreFlowElement(decoratedElementSnapshot);
                decoratedElementSnapshot = null;
            }

            function scheduleRejectedOpenClose(el, openSequence) {
                var token = { el: el, openSequence: openSequence };
                rejectedOpenCloseToken = token;
                Promise.resolve().then(function() {
                    if (rejectedOpenCloseToken !== token) return;
                    rejectedOpenCloseToken = null;
                    if (panelOpenSequence !== token.openSequence
                            || current
                            || panels.getActive() !== "lockbox"
                            || !decoratedElementSnapshot
                            || decoratedElementSnapshot.el !== token.el) return;
                    try {
                        // Local visual cleanup only.  This path never emits an exact close or
                        // teardown proof and never changes S0 authority state.
                        panels.close();
                    } catch (error) {
                        // Panels clears active before business onClose.  Swallow only a fixed
                        // category so cleanup failure cannot strand the rejected visual or leak.
                        record("panel_cleanup_exception", "rejected_open_local_close");
                    }
                });
            }

            wrapped.onOpen = function(el, initData) {
                panelOpenSequence += 1;
                var openSequence = panelOpenSequence;
                rejectedOpenCloseToken = null;
                var reserved = looksLikeS0Open(initData);
                if (state === "ARMED" && !reserved) {
                    restoreRejectedOpenElement();
                    return originalOnOpen ? originalOnOpen.apply(this, arguments) : undefined;
                }
                if (state !== "ARMED") {
                    if (reserved) {
                        decoratedElementSnapshot = snapshotFlowElement(el);
                        rejectArmedOpen(el, "wire_not_armed", false, armFromOpen(initData));
                        scheduleRejectedOpenClose(el, openSequence);
                        return;
                    }
                    restoreRejectedOpenElement();
                    return originalOnOpen ? originalOnOpen.apply(this, arguments) : undefined;
                }

                decoratedElementSnapshot = snapshotFlowElement(el);
                var checked = validateOpenInitData(initData, arm);
                if (!checked.ok) {
                    var projected = S0.validateIdentity(identityFromOpen(initData));
                    rejectArmedOpen(el, checked.code, reserved, null,
                        projected.ok ? projected.identity : null);
                    return;
                }

                usedCapabilities[arm.capability] = true;
                if (typeof options.onConsume === "function") options.onConsume();
                state = "CONSUMED";
                var adapter = S0.createAdapter({ enabled: true, send: sendHost });
                var initialized = adapter.initialize(checked.identity);
                if (!initialized.ok) {
                    rejectArmedOpen(el, initialized.code, false);
                    return;
                }
                current = {
                    identity: checked.identity,
                    adapter: adapter,
                    el: el,
                    rootSnapshot: decoratedElementSnapshot,
                    exactClose: false,
                    visualClosed: false,
                    openFailed: false
                };
                record("open_consumed", initialized.code);
                markEvidenceRoot(state);
                current.restrictions = disableForbiddenControls(el);
                installCloseCapture(el);

                Promise.resolve().then(function() {
                    if (!current || current.openFailed) return;
                    var exactDom = panels.getActive() === "lockbox"
                        && current.el === el && el.isConnected !== false;
                    if (!exactDom) {
                        current.openFailed = true;
                        freezeCurrentInteraction("bind");
                        state = "REJECTED";
                        markEvidenceRoot(state);
                        reportRuntimeRejected("dom_bind_not_committed");
                        scheduleForcedTeardown("runtime_rejected");
                        return;
                    }
                    var bound = current.adapter.bind();
                    record("bind", bound.code);
                    if (!bound.ok) freezeCurrentInteraction("bind");
                });

                try {
                    return originalOnOpen
                        ? originalOnOpen.call(this, el, sanitizedGameInit())
                        : undefined;
                } catch (error) {
                    current.openFailed = true;
                    state = "REJECTED";
                    markEvidenceRoot(state);
                    freezeCurrentInteraction("open");
                    reportRuntimeRejected("panel_open_exception");
                    scheduleForcedTeardown("runtime_rejected");
                    return undefined;
                }
            };

            wrapped.onRebind = function() {
                if (current) {
                    record("same_name_rebind_rejected", "flow_busy");
                    return;
                }
                var initData = arguments[1];
                if (looksLikeS0Open(initData)) {
                    if (state === "ARMED") {
                        var checked = validateOpenInitData(initData, arm);
                        rejectArmedOpen(null, checked.ok ? "same_name_rebind_rejected" : checked.code, true);
                    } else {
                        rejectArmedOpen(null, "wire_not_armed", false, armFromOpen(initData));
                    }
                    return;
                }
                panelOpenSequence += 1;
                rejectedOpenCloseToken = null;
                restoreRejectedOpenElement();
                if (typeof spec.onRebind === "function") return spec.onRebind.apply(this, arguments);
            };

            wrapped.onRequestClose = function() {
                if (current) return requestUserCancel();
                if (originalOnRequestClose) return originalOnRequestClose.apply(this, arguments);
            };

            wrapped.onClose = function() {
                var trackedClose = !!current;
                rejectedOpenCloseToken = null;
                if (current) {
                    removeCloseCapture();
                    restoreForbiddenControls(current);
                    current.visualClosed = true;
                    record(current.exactClose ? "exact_visual_close" : "unexpected_visual_close",
                        current.exactClose ? "none" : "pause_retained");
                }
                restoreFlowElement(decoratedElementSnapshot);
                decoratedElementSnapshot = null;
                if (!originalOnClose) return undefined;
                try {
                    return originalOnClose.apply(this, arguments);
                } catch (error) {
                    // Panels.close 已先隐藏 DOM 并清空 active；S0 不能让业务清理异常
                    // 卡住 CLOSE_PENDING。只保留固定类别，不记录 error/message/stack。
                    if (!trackedClose) throw error;
                    record("panel_cleanup_exception", "original_on_close");
                    return undefined;
                }
            };

            wrapped.onForceClose = function() {
                var trackedForceClose = !!current;
                var result;
                if (current) record("force_close", "teardown_pending");
                try {
                    if (originalOnForceClose) {
                        result = originalOnForceClose.apply(this, arguments);
                    }
                } catch (error) {
                    if (!trackedForceClose) throw error;
                    record("panel_cleanup_exception", "original_on_force_close");
                } finally {
                    // 业务 onForceClose 失败不能吞掉 Web DOM teardown proof。
                    if (trackedForceClose && current) completeForcedTeardown("force_close");
                }
                return result;
            };
            return wrapped;
        }

        function sameCurrentIdentity(payload, extraKeys) {
            return current && hasExactKeys(payload, IDENTITY_KEYS.concat(extraKeys || []))
                && payload.flowHandle === current.identity.flowHandle
                && payload.panelInstanceId === current.identity.panelInstanceId
                && payload.documentEpoch === current.identity.documentEpoch
                && payload.source === current.identity.source
                && payload.fixture === current.identity.fixture;
        }

        function finishExactClose(payload, allowInitialClose) {
            if (!sameCurrentIdentity(payload, [])) return { ok: false, code: "stale_identity" };
            var snapshot = current.adapter.getSnapshot();
            var completed;
            if (snapshot.state === S0.STATES.CLOSE_UNKNOWN) {
                completed = current.adapter.retryCloseAck();
            } else if (allowInitialClose && snapshot.state === S0.STATES.TERMINAL_KNOWN) {
                var accepted = current.adapter.acceptExactClose(payload);
                if (!accepted.ok) return accepted;
                current.exactClose = true;
                panels.close();
                completed = current.adapter.completeClose();
            } else {
                return { ok: false, code: "close_query_not_allowed" };
            }
            record("close_ack", completed.code);
            if (completed.ok) {
                stopResultAckTimer();
                stopResultQueryRetry();
                closedProof = {
                    identity: current.identity,
                    adapter: current.adapter
                };
                lastFlow = current;
                current = null;
                state = "IDLE";
                arm = null;
                markEvidenceRoot(state);
            }
            return completed;
        }

        function isLockboxSessionMessage(message) {
            return !!(message && message.type === "panel"
                && message.cmd === "minigame_session" && message.payload
                && message.payload.game === "lockbox");
        }

        function sendSanitizedSessionTelemetry(message) {
            var payload = message.payload || {};
            var data = isRecord(payload.data) ? payload.data : {};
            var result = isRecord(data.result) ? data.result : null;
            var metrics = isRecord(data.metrics) ? data.metrics : null;
            var durationMs;
            if (metrics && typeof metrics.observeMs === "number"
                    && typeof metrics.executeMs === "number") {
                durationMs = Math.max(0, metrics.observeMs) + Math.max(0, metrics.executeMs);
            }
            var eventCategory = payload.kind === "result" ? "result"
                : payload.kind === "close" ? "close"
                : payload.kind === "error" ? "error"
                : (payload.kind === "open" || payload.kind === "ready" || payload.kind === "start")
                    ? "bind" : "unknown";
            var mapped = result ? S0.mapCoreOutcome(result.outcome) : null;
            var telemetry = S0.buildTelemetry({
                eventCategory: eventCategory,
                resultCategory: payload.kind === "result" ? (mapped || "unknown") : "none",
                durationMs: durationMs,
                errorCategory: payload.kind === "error" ? "unknown" : "none"
            });
            return sendHost({
                type: "panel",
                cmd: "minigame_session",
                payload: {
                    game: "lockbox",
                    kind: "s0_telemetry",
                    data: telemetry
                }
            });
        }

        function handleControl(message) {
            if (!hasExactKeys(message, ["type", "cmd", "payload"])) return;
            if (message.type !== CONTROL_TYPE || message.cmd === "arm") return;
            var payload = message.payload;
            var outcome;
            if (message.cmd === "close_query" && closedProof
                    && sameIdentity(closedProof.identity, payload)) {
                outcome = closedProof.adapter.replayCloseAck();
                record("control_close_query", outcome.code, closedProof.identity);
                return;
            }
            if (message.cmd === "close_query" && teardownProof
                    && sameIdentity(teardownProof.identity, payload)) {
                outcome = replayTeardownProof(teardownProof)
                    ? { ok: true, code: "teardown_ack_replayed" }
                    : { ok: false, code: "teardown_delivery_unknown" };
                record("control_close_query", outcome.code, teardownProof.identity);
                return;
            }
            if (!current) {
                record("stale_control", "no_active_flow");
                return;
            }
            if (message.cmd === "bind_timeout") {
                outcome = sameCurrentIdentity(payload, [])
                    ? current.adapter.markBindUnknown()
                    : { ok: false, code: "stale_identity" };
                if (outcome.ok) freezeCurrentInteraction("bind");
            } else if (message.cmd === "bind_query") {
                outcome = current.adapter.answerBindQuery(payload);
                if (outcome.ok && current.adapter.getSnapshot().state === S0.STATES.ACTIVE) {
                    unfreezeCurrentInteraction();
                }
            } else if (message.cmd === "result_ack") {
                outcome = current.adapter.handleResultAck(payload);
                if (outcome.ok) {
                    stopResultAckTimer();
                    stopResultQueryRetry();
                }
            } else if (message.cmd === "authority_terminal") {
                outcome = current.adapter.handleAuthorityTerminal(payload);
                if (outcome.ok) {
                    stopResultAckTimer();
                    stopResultQueryRetry();
                }
            } else if (message.cmd === "result_unknown") {
                var pendingCallId = current.adapter.getSnapshot().pendingFlowCallId;
                outcome = sameCurrentIdentity(payload, ["flowCallId"])
                        && payload.flowCallId === pendingCallId
                    ? current.adapter.markResultUnknown()
                    : { ok: false, code: "stale_identity" };
                record("result_unknown", outcome.code);
                if (outcome.ok) {
                    stopResultAckTimer();
                    beginResultReconcileIfNeeded(current);
                }
            } else if (message.cmd === "reconcile_reply") {
                outcome = current.adapter.handleReconcileReply(payload);
                if (outcome.ok) {
                    stopResultAckTimer();
                    stopResultQueryRetry();
                }
            } else if (message.cmd === "document_epoch") {
                outcome = hasExactKeys(payload, [
                    "flowHandle", "panelInstanceId", "documentEpoch", "source", "fixture", "observedEpoch"
                ]) && sameCurrentIdentity(payload, ["observedEpoch"])
                    ? current.adapter.observeDocumentEpoch(payload.observedEpoch)
                    : { ok: false, code: "stale_identity" };
                if (outcome.code === "document_epoch_changed") {
                    freezeCurrentInteraction("epoch");
                    stopResultAckTimer();
                    // The old document identity is intentionally barred from querying the new
                    // epoch.  Host owns teardown reconciliation, so no impossible retry loop is
                    // scheduled in this document.
                    stopResultQueryRetry();
                }
            } else if (message.cmd === "close_request") {
                outcome = finishExactClose(payload, true);
            } else if (message.cmd === "close_query") {
                outcome = finishExactClose(payload, true);
            } else {
                record("unsupported_control", "unsupported_control");
                return;
            }
            record("control_" + message.cmd, outcome.code);
        }

        bridge.send = function(message) {
            if (current && isLockboxSessionMessage(message)) {
                var flow = current;
                if (message.payload.kind === "result") {
                    var result = message.payload.data && message.payload.data.result;
                    var routed = current.adapter.submitCoreOutcome(result && result.outcome);
                    record("result", routed.code);
                    if (routed.ok || current.adapter.getSnapshot().resultSubmitted) {
                        freezeCurrentInteraction("result");
                    }
                    beginResultReconcileIfNeeded(flow);
                }
                // S0 active 时完整 Lockbox session 永不越过 Host 边界；这里只发固定四字段观测。
                return sendSanitizedSessionTelemetry(message);
            }
            return sendHost(message);
        };

        bridge.on(CONTROL_TYPE, handleControl);
        if (!panels.installRegistrationDecorator("lockbox", decorateLockboxSpec)) {
            bridge.send = originalBridgeSend;
            bridge.off(CONTROL_TYPE, handleControl);
            return { ok: false, code: "decorator_install_failed" };
        }

        function rearm(nextArm) {
            var checked = validateArmPayload(nextArm);
            if (!checked.ok) return { ok: false, code: checked.code };
            var canSupersedeUnused = state === "ARMED" && !current
                && panels.getActive() === null && !!arm;
            if (canSupersedeUnused && (checked.arm.capability === arm.capability
                    || hasOwn(usedCapabilities, checked.arm.capability))) {
                return { ok: false, code: "capability_reused" };
            }
            if (!canSupersedeUnused && ((state !== "IDLE" && state !== "REJECTED")
                    || current || panels.getActive() !== null)) {
                return { ok: false, code: "wire_busy" };
            }
            if (hasOwn(usedCapabilities, checked.arm.capability)) {
                return { ok: false, code: "capability_reused" };
            }
            var supersededCapability = canSupersedeUnused ? arm.capability : null;
            if (supersededCapability !== null) usedCapabilities[supersededCapability] = true;
            arm = checked.arm;
            state = "ARMED";
            if (supersededCapability !== null) {
                record("arm_superseded", "fresh_capability_required");
            }
            markEvidenceRoot(state);
            record("rearmed", "armed");
            return { ok: true, code: "armed" };
        }

        function getEvidence() {
            var flow = current || lastFlow;
            return {
                evidenceKind: EXECUTION_MODE,
                executionMode: EXECUTION_MODE,
                hostEvidenceRequired: true,
                selfAttestedCrossStack: false,
                selfAttestedProductionHost: false,
                state: state,
                armConsumed: state !== "ARMED",
                flow: flow ? {
                    flowHandle: flow.identity.flowHandle,
                    panelInstanceId: flow.identity.panelInstanceId,
                    documentEpoch: flow.identity.documentEpoch,
                    source: flow.identity.source,
                    fixture: flow.identity.fixture,
                    adapter: flow.adapter.getSnapshot()
                } : null,
                events: events.slice()
            };
        }

        markEvidenceRoot(state);
        record("installed", "armed");
        return {
            ok: true,
            code: "armed",
            rearm: rearm,
            getEvidence: getEvidence
        };
    }

    return {
        CONTROL_TYPE: CONTROL_TYPE,
        EXECUTION_MODE: EXECUTION_MODE,
        PROTOCOL_VERSION: PROTOCOL_VERSION,
        ARM_KEYS: ARM_KEYS.slice(),
        OPEN_KEYS: OPEN_KEYS.slice(),
        validateArmPayload: validateArmPayload,
        validateOpenInitData: validateOpenInitData,
        install: install
    };
});
