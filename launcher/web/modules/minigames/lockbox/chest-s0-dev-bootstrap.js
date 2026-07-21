(function(root) {
    "use strict";

    var CONTROL_TYPE = "lockbox_chest_s0_control";
    var ADAPTER_SCRIPT = "modules/minigames/lockbox/chest-s0-adapter.js";
    var ACTUAL_WIRE_SCRIPT = "modules/minigames/lockbox/chest-s0-actual-wire.js";
    var SOURCE = "as2-chest-s0";
    var FIXTURE = "insurance-safe-s0-v1";
    var ARM_KEYS = [
        "protocolVersion",
        "capability",
        "connectionGeneration",
        "gameProcessId",
        "documentEpoch",
        "source",
        "fixture"
    ];
    var MAX_SAFE_INTEGER = 9007199254740991;
    var state = "DORMANT";
    var wire = null;
    var invalidArmCount = 0;
    var loadAttempted = false;
    var modulesLoaded = false;

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

    function isOpaqueId(value) {
        return typeof value === "string" && value.length >= 1 && value.length <= 256
            && value === value.replace(/^\s+|\s+$/g, "")
            && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function isIntegerInRange(value, min, max) {
        return typeof value === "number" && isFinite(value)
            && Math.floor(value) === value && value >= min && value <= max;
    }

    function validateArm(value) {
        return hasExactKeys(value, ARM_KEYS)
            && value.protocolVersion === 1
            && isOpaqueId(value.capability)
            && isIntegerInRange(value.connectionGeneration, 1, MAX_SAFE_INTEGER)
            && isIntegerInRange(value.gameProcessId, 1, 2147483647)
            && isIntegerInRange(value.documentEpoch, 1, 2147483647)
            && value.source === SOURCE
            && value.fixture === FIXTURE;
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

    function isExactProductionOverlayLocation(locationValue) {
        return !!locationValue
            && locationValue.protocol === "https:"
            && locationValue.hostname === "overlay.local"
            && (locationValue.port === "" || locationValue.port === undefined)
            && locationValue.pathname === "/overlay.html"
            && (locationValue.search === "" || locationValue.search === undefined)
            && (locationValue.hash === "" || locationValue.hash === undefined);
    }

    function hasWebViewTransport() {
        return !!(root.chrome && root.chrome.webview
            && typeof root.chrome.webview.postMessage === "function"
            && typeof root.chrome.webview.addEventListener === "function");
    }

    function sendControl(cmd, payload) {
        if (typeof Bridge === "undefined" || !Bridge || typeof Bridge.send !== "function") return false;
        return Bridge.send({
            type: CONTROL_TYPE,
            cmd: cmd,
            payload: payload
        }) !== false;
    }

    function sendArmed(arm) {
        state = "ARMED";
        return sendControl("armed", cloneArm(arm));
    }

    function sendRejected(arm, code) {
        var payload = cloneArm(arm);
        payload.code = code;
        state = "REJECTED";
        return sendControl("rejected", payload);
    }

    function sendRejectedPreservingState(arm, code) {
        var payload = cloneArm(arm);
        payload.code = code;
        return sendControl("rejected", payload);
    }

    function sendInstallRejected(arm, code) {
        if (code !== "panel_orchestration_busy") return sendRejected(arm, code);
        var payload = cloneArm(arm);
        payload.code = code;
        // The modules are valid but another panel won the orchestration slot.  Keep the
        // bootstrap eligible for the Host's next fresh one-shot arm after that panel closes.
        state = "DORMANT";
        return sendControl("rejected", payload);
    }

    function installLoadedWire(arm) {
        if (!root.LockboxChestS0ActualWire || !root.LockboxChestS0Adapter) {
            sendRejected(arm, "actual_wire_module_missing");
            return;
        }
        var installed = root.LockboxChestS0ActualWire.install({
            arm: arm,
            bridge: Bridge,
            panels: Panels,
            onConsume: function() { state = "CONSUMED"; },
            onRejected: function(payload) {
                state = "REJECTED";
                return sendControl("rejected", payload);
            },
            onRuntimeRejected: function(payload) {
                state = "CONSUMED";
                return sendControl("runtime_rejected", payload);
            },
            onTeardown: function(payload, context) {
                var delivered = sendControl("teardown_ack", payload);
                // A bounded proof for an old, already-settled flow may be queried while a
                // fresh flow is armed or active.  Replaying that proof must not overwrite
                // the fresh bootstrap state.
                if (context && context.replay && !context.pending) return delivered;
                state = delivered ? "IDLE" : "TEARDOWN_UNKNOWN";
                return delivered;
            }
        });
        if (!installed || !installed.ok) {
            sendInstallRejected(arm, installed && installed.code || "actual_wire_install_failed");
            return;
        }
        wire = installed;
        root.__lockboxChestS0ActualWireEvidence = installed.getEvidence;
        sendArmed(arm);
    }

    function handleArm(message) {
        if (!hasExactKeys(message, ["type", "cmd", "payload"])
                || message.type !== CONTROL_TYPE || message.cmd !== "arm") return;
        var arm = message.payload;
        if (!validateArm(arm)) {
            invalidArmCount += 1;
            return;
        }
        arm = cloneArm(arm);
        if (!isExactProductionOverlayLocation(root.location)) {
            sendRejected(arm, "page_not_allowlisted");
            return;
        }
        if (!hasWebViewTransport()) {
            sendRejected(arm, "webview_transport_unavailable");
            return;
        }
        if (wire) {
            var rearmed = wire.rearm(arm);
            if (!rearmed.ok) {
                sendRejected(arm, rearmed.code);
                return;
            }
            sendArmed(arm);
            return;
        }
        if (state !== "DORMANT") {
            // The first arm owns the single in-flight module load. A Host ack-timeout may
            // deliver a fresh arm before that Promise settles; acknowledge that retry
            // without stealing the load owner's state. Once installed, the actual wire can
            // supersede the unused owner through its normal one-shot rearm path.
            if (state === "LOADING") {
                sendRejectedPreservingState(arm, "wire_loading");
                return;
            }
            sendRejected(arm, "wire_not_dormant");
            return;
        }
        if (modulesLoaded) {
            installLoadedWire(arm);
            return;
        }
        if (typeof LazyLoader === "undefined" || !LazyLoader || typeof LazyLoader.load !== "function") {
            sendRejected(arm, "lazy_loader_unavailable");
            return;
        }
        state = "LOADING";
        loadAttempted = true;
        LazyLoader.load([ADAPTER_SCRIPT, ACTUAL_WIRE_SCRIPT]).then(function() {
            modulesLoaded = true;
            installLoadedWire(arm);
        })["catch"](function() {
            sendRejected(arm, "actual_wire_load_failed");
        });
    }

    if (typeof Bridge !== "undefined" && Bridge && typeof Bridge.on === "function") {
        Bridge.on(CONTROL_TYPE, handleArm);
    }

    root.LockboxChestS0DevBootstrap = {
        CONTROL_TYPE: CONTROL_TYPE,
        EXECUTION_MODE: "actual-webview2-dev-wire",
        isExactProductionOverlayLocation: isExactProductionOverlayLocation,
        getSnapshot: function() {
            return {
                state: state,
                executionMode: "actual-webview2-dev-wire",
                hostEvidenceRequired: true,
                actualWireLoaded: !!wire,
                loadAttempted: loadAttempted,
                invalidArmCount: invalidArmCount,
                sourceUrl: root.location ? String(root.location.href || "") : ""
            };
        }
    };
})(typeof globalThis !== "undefined" ? globalThis : this);
