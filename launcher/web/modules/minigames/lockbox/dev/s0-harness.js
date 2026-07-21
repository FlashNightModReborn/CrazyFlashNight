(function() {
    "use strict";

    var S0 = window.LockboxChestS0Adapter;
    var transport = window.__lockboxS0BrowserTransport;
    var CONTROL_TYPE = "lockbox_chest_s0_control";
    var HARNESS_TYPE = "lockbox_chest_s0_harness";
    var PANEL_SCRIPT = "modules/minigames/lockbox/lockbox-panel.js";

    if (!S0) throw new Error("LockboxChestS0Adapter is required");
    if (!transport || transport.kind !== "browser-host-shim") {
        throw new Error("dev-only browser Host transport is required");
    }

    function clone(value) {
        if (value === undefined) return null;
        return JSON.parse(JSON.stringify(value));
    }

    function hasOwn(value, key) {
        return Object.prototype.hasOwnProperty.call(value, key);
    }

    function identityPayload(value) {
        return {
            flowHandle: value.flowHandle,
            panelInstanceId: value.panelInstanceId,
            documentEpoch: value.documentEpoch,
            source: value.source,
            fixture: value.fixture
        };
    }

    function sameIdentity(left, right) {
        return !!left && !!right
            && left.flowHandle === right.flowHandle
            && left.panelInstanceId === right.panelInstanceId
            && left.documentEpoch === right.documentEpoch
            && left.source === right.source
            && left.fixture === right.fixture;
    }

    function extendIdentity(value, extra) {
        var out = identityPayload(value);
        var key;
        for (key in extra) {
            if (hasOwn(extra, key)) out[key] = extra[key];
        }
        return out;
    }

    function buildInit(seed, value) {
        return {
            mode: "dev",
            profile: "standard",
            source: "runtime",
            familySeed: seed >>> 0,
            variantIndex: 0,
            debug: false,
            __lockboxChestS0: {
                identity: identityPayload(value),
                harness: "browser-host-shim"
            }
        };
    }

    function createBrowserHostShim() {
        var sequence = 0;
        var controlSequence = 0;
        var current = null;
        var flows = [];
        var events = [];
        var pendingControls = {};
        var counters = {
            openAttempts: 0,
            requestTokens: 0,
            identityAllocations: 0,
            mappings: 0,
            onOpen: 0,
            onRebind: 0,
            ready: 0,
            harnessTeardowns: 0
        };
        var boot = {
            lockboxPanelDefined: typeof window.LockboxPanel !== "undefined",
            lockboxPanelLazyLoaded: LazyLoader.isLoaded(PANEL_SCRIPT),
            requiredAssetsReady: Panels.requiredAssetsReady()
        };

        function record(kind, data) {
            sequence += 1;
            var entry = {
                sequence: sequence,
                kind: kind,
                data: clone(data || {})
            };
            events.push(entry);
            return entry;
        }

        function flowSummary(flow) {
            if (!flow) return null;
            return {
                requestToken: flow.requestToken,
                identity: identityPayload(flow.identity),
                state: flow.state,
                dropBindAck: flow.dropBindAck,
                domActiveSequence: flow.domActiveSequence || null,
                bindSendSequence: flow.bindSendSequence || null,
                readySequence: flow.readySequence || null,
                resultSequence: flow.resultSequence || null,
                closeAckSequence: flow.closeAckSequence || null,
                coreResultCount: flow.coreResultCount || 0,
                s0ResultCount: flow.s0ResultCount || 0,
                readyCount: flow.readyCount || 0,
                authorityReleased: flow.authorityReleased === true
            };
        }

        function snapshot() {
            var summaries = [];
            for (var i = 0; i < flows.length; i += 1) summaries.push(flowSummary(flows[i]));
            return {
                kind: "browser-host-shim",
                actualCrossStack: false,
                productionHost: false,
                usesProductionPanelsLazyRegistry: true,
                boot: clone(boot),
                counters: clone(counters),
                current: flowSummary(current),
                flows: summaries,
                events: clone(events)
            };
        }

        function resolveControl(message) {
            var payload = message.payload || {};
            var requestId = payload.requestId;
            var pending = requestId && pendingControls[requestId];
            record("web.control_result", payload);
            if (!pending) return;
            delete pendingControls[requestId];
            clearTimeout(pending.timer);
            pending.resolve(payload);
        }

        function handleObservation(message) {
            var payload = message.payload || {};
            var entry = record("web." + String(payload.kind || "observation"), payload);
            if (payload.kind === "on_open_enter") {
                counters.onOpen += 1;
            } else if (payload.kind === "on_rebind") {
                counters.onRebind += 1;
            } else if (payload.kind === "dom_active" && current
                    && sameIdentity(current.identity, payload.identity)) {
                current.domActiveSequence = entry.sequence;
            }
        }

        function routeCoreResult(flow, data) {
            if (!flow || flow.coreRouteStarted) return;
            flow.coreRouteStarted = true;
            flow.coreRoutePromise = sendControl("core_result", {
                identity: identityPayload(flow.identity),
                coreOutcome: data && data.result ? data.result.outcome : null
            }).then(function(reply) {
                flow.coreRouteReply = reply;
                if (!reply.outcome || !reply.outcome.ok) {
                    throw new Error("core result route rejected: "
                        + (reply.outcome && reply.outcome.code || "missing_outcome"));
                }
                return reply;
            });
        }

        function handleMinigameSession(message) {
            var envelope = message.payload || {};
            if (envelope.game !== "lockbox") return;
            var kind = envelope.kind;
            var sessionData = envelope.data || {};
            var entry = record("lockbox.session." + kind, {
                sessionId: sessionData.sessionId || null,
                phase: sessionData.phase || null,
                outcome: sessionData.result ? sessionData.result.outcome : null
            });
            var flow = current;
            if (!flow) return;
            if (kind === "ready") {
                counters.ready += 1;
                flow.readyCount += 1;
                if (!flow.readySequence) flow.readySequence = entry.sequence;
            } else if (kind === "result") {
                flow.coreResultCount += 1;
                flow.resultSequence = entry.sequence;
                routeCoreResult(flow, envelope.data || {});
            }
        }

        function handleS0Message(message) {
            var payload = message.payload || {};
            var flow = current;
            var exact = flow && sameIdentity(flow.identity, payload);
            var entry = record("s0." + String(message.cmd || "unknown"), {
                exact: !!exact,
                payload: payload
            });
            if (!exact) return;

            if (message.cmd === "bind") {
                flow.bindSendSequence = entry.sequence;
                if (flow.dropBindAck) {
                    flow.state = "BIND_ACK_MISSING";
                    record("host.bind_ack_intentionally_dropped", {
                        identity: flow.identity
                    });
                } else {
                    flow.state = "ACTIVE";
                    flow.bindAcceptedSequence = entry.sequence;
                }
            } else if (message.cmd === "bind_query_result") {
                flow.bindQueryResult = payload.binding;
                if (payload.binding === "bound") flow.state = "ACTIVE";
            } else if (message.cmd === "result") {
                flow.s0ResultCount += 1;
                flow.pendingResult = clone(payload);
                flow.state = "RESULT_PENDING";
            } else if (message.cmd === "close_ack") {
                flow.closeAckSequence = entry.sequence;
                flow.state = "CLOSED";
                flow.authorityReleased = true;
                if (current === flow) current = null;
            }
        }

        function receiveFromWeb(message) {
            if (!message || !message.type) return;
            if (message.type === HARNESS_TYPE) {
                if (message.cmd === "control_result") resolveControl(message);
                else if (message.cmd === "observation") handleObservation(message);
                return;
            }
            if (message.type === "panel" && message.cmd === "minigame_session") {
                handleMinigameSession(message);
                return;
            }
            if (message.type === S0.MESSAGE_TYPE) {
                handleS0Message(message);
                return;
            }
            record("web.other", message);
        }

        function sendControl(command, payload) {
            controlSequence += 1;
            var requestId = "browser-host-shim.control." + controlSequence;
            return new Promise(function(resolve, reject) {
                var timer = setTimeout(function() {
                    delete pendingControls[requestId];
                    reject(new Error("timeout waiting for control response: " + command));
                }, 4000);
                pendingControls[requestId] = {
                    resolve: resolve,
                    reject: reject,
                    timer: timer
                };
                record("host.control_dispatch", {
                    requestId: requestId,
                    command: command,
                    payload: payload
                });
                transport.dispatchToWeb({
                    type: CONTROL_TYPE,
                    requestId: requestId,
                    cmd: command,
                    payload: clone(payload || {})
                });
            });
        }

        function requestOpen(seed, options) {
            options = options || {};
            counters.openAttempts += 1;
            record("host.open_request", {
                seed: seed >>> 0,
                documentEpoch: options.documentEpoch || 1
            });
            if (current) {
                record("host.open_busy_before_allocation", {
                    activeIdentity: current.identity,
                    requestTokens: counters.requestTokens,
                    identityAllocations: counters.identityAllocations,
                    mappings: counters.mappings
                });
                return {
                    ok: false,
                    code: "busy",
                    current: flowSummary(current)
                };
            }

            counters.requestTokens += 1;
            counters.identityAllocations += 1;
            counters.mappings += 1;
            var ordinal = counters.identityAllocations;
            var value = {
                flowHandle: "s0.browser.host.flow." + ordinal,
                panelInstanceId: "s0.browser.host.panel." + ordinal,
                documentEpoch: options.documentEpoch || 1,
                source: S0.SOURCE,
                fixture: S0.FIXTURE
            };
            var flow = {
                requestToken: "s0.browser.host.request." + counters.requestTokens,
                identity: value,
                state: "OPEN_QUEUED",
                dropBindAck: options.dropBindAck === true,
                readyCount: 0,
                coreResultCount: 0,
                s0ResultCount: 0,
                authorityReleased: false
            };
            current = flow;
            flows.push(flow);
            record("host.identity_and_mapping_allocated", {
                requestToken: flow.requestToken,
                identity: value
            });
            transport.dispatchToWeb({
                type: "panel_cmd",
                cmd: "open",
                panel: "lockbox",
                initData: buildInit(seed, value)
            });
            record("host.panel_open_dispatched", {
                requestToken: flow.requestToken,
                identity: value
            });
            return { ok: true, code: "queued", flow: flow };
        }

        function simulateBindTimeout(flow) {
            return sendControl("bind_timeout", identityPayload(flow.identity));
        }

        function queryBinding(flow) {
            return sendControl("bind_query", identityPayload(flow.identity));
        }

        function requestUserCancel(flow) {
            return sendControl("user_cancel", {
                identity: identityPayload(flow.identity)
            });
        }

        function settleResult(flow) {
            if (!flow || !flow.pendingResult) {
                return Promise.reject(new Error("Host has no pending S0 result"));
            }
            var result = flow.pendingResult.result;
            var authorityTerminal = result !== "success";
            return sendControl("result_ack", extendIdentity(flow.identity, {
                flowCallId: flow.pendingResult.flowCallId,
                result: result,
                applied: true,
                authorityTerminal: authorityTerminal
            })).then(function(reply) {
                if (!reply.outcome || !reply.outcome.ok) {
                    throw new Error("result ack rejected: "
                        + (reply.outcome && reply.outcome.code || "missing_outcome"));
                }
                if (authorityTerminal) return reply;
                return sendControl("authority_terminal", extendIdentity(flow.identity, {
                    flowCallId: flow.pendingResult.flowCallId,
                    terminal: S0.AUTHORITY_TERMINAL
                })).then(function(terminalReply) {
                    if (!terminalReply.outcome || !terminalReply.outcome.ok) {
                        throw new Error("authority terminal rejected: "
                            + (terminalReply.outcome && terminalReply.outcome.code || "missing_outcome"));
                    }
                    return terminalReply;
                });
            }).then(function() {
                return sendControl("close_request", identityPayload(flow.identity));
            }).then(function(closeReply) {
                if (!closeReply.outcome || !closeReply.outcome.ok) {
                    throw new Error("exact close rejected: "
                        + (closeReply.outcome && closeReply.outcome.code || "missing_outcome"));
                }
                return flow;
            });
        }

        function harnessTeardown() {
            if (!current) return Promise.resolve(null);
            var flow = current;
            return sendControl("harness_teardown", {
                harnessOnly: true,
                identity: identityPayload(flow.identity)
            }).then(function(reply) {
                if (!reply.outcome || !reply.outcome.ok
                        || reply.outcome.code !== "harness_teardown_only") {
                    throw new Error("isolated harness teardown failed");
                }
                counters.harnessTeardowns += 1;
                flow.state = "HARNESS_TEARDOWN_ONLY";
                flow.authorityReleased = false;
                current = null;
                record("host.harness_teardown_archived_without_authority_release", {
                    identity: flow.identity
                });
                return reply;
            });
        }

        transport.installHost(receiveFromWeb);

        return {
            requestOpen: requestOpen,
            sendControl: sendControl,
            simulateBindTimeout: simulateBindTimeout,
            queryBinding: queryBinding,
            requestUserCancel: requestUserCancel,
            settleResult: settleResult,
            harnessTeardown: harnessTeardown,
            getCurrent: function() { return current; },
            getCounters: function() { return clone(counters); },
            getBoot: function() { return clone(boot); },
            snapshot: snapshot
        };
    }

    function createWebCoordinator() {
        var current = null;
        var originalRegister = Panels.register;

        function sendHarness(command, payload) {
            if (Bridge.send({
                type: HARNESS_TYPE,
                cmd: command,
                payload: payload || {}
            }) === false) {
                throw new Error("browser Host shim transport rejected harness message");
            }
        }

        function observe(kind, data) {
            var payload = clone(data || {});
            payload.kind = kind;
            sendHarness("observation", payload);
        }

        function reportControl(message, outcome) {
            sendHarness("control_result", {
                requestId: message.requestId,
                command: message.cmd,
                outcome: clone(outcome),
                snapshot: current ? current.adapter.getSnapshot() : null
            });
        }

        function requireExact(payload) {
            var value = payload && payload.identity ? payload.identity : payload;
            return current && sameIdentity(current.identity, value);
        }

        function wrapLockboxSpec(spec) {
            if (spec.__s0BrowserHarnessWrapped) return spec;
            var wrapped = {};
            var key;
            for (key in spec) {
                if (hasOwn(spec, key)) wrapped[key] = spec[key];
            }
            var originalOnOpen = spec.onOpen;
            var originalOnRebind = spec.onRebind;
            wrapped.__s0BrowserHarnessWrapped = true;
            wrapped.onOpen = function(el, initData) {
                var envelope = initData && initData.__lockboxChestS0;
                if (!envelope || envelope.harness !== "browser-host-shim" || !envelope.identity) {
                    throw new Error("S0 Browser open is missing its exact dev-only identity");
                }
                var adapter = S0.createAdapter({
                    enabled: true,
                    send: function(message) { return Bridge.send(message); }
                });
                var initialized = adapter.initialize(identityPayload(envelope.identity));
                if (!initialized.ok) {
                    throw new Error("S0 adapter initialize failed: " + initialized.code);
                }
                current = {
                    identity: identityPayload(envelope.identity),
                    adapter: adapter,
                    panel: el,
                    bindPromise: null
                };
                observe("on_open_enter", { identity: current.identity });
                observe("adapter_initialized", {
                    identity: current.identity,
                    state: adapter.getSnapshot().state
                });

                /* Queue before Lockbox onOpen queues puzzle generation. The callback itself
                   runs after Panels commits _active, so bind cannot be confused with ready. */
                current.bindPromise = Promise.resolve().then(function() {
                    var panel = document.querySelector(".lockbox-panel");
                    if (Panels.getActive() !== "lockbox" || panel !== el || !el.isConnected) {
                        throw new Error("exact DOM bind point was not committed");
                    }
                    observe("dom_active", { identity: current.identity });
                    var bound = adapter.bind();
                    observe("bind_local_outcome", {
                        identity: current.identity,
                        outcome: bound
                    });
                    if (!bound.ok) throw new Error("exact bind failed: " + bound.code);
                    return bound;
                });
                current.bindPromise["catch"](function(error) {
                    console.error("[S0 Browser harness] bind hook failed:", error);
                });

                var result = originalOnOpen ? originalOnOpen.apply(this, arguments) : undefined;
                observe("on_open_return", { identity: current.identity });
                return result;
            };
            if (typeof originalOnRebind === "function") {
                wrapped.onRebind = function() {
                    observe("on_rebind", {
                        identity: current ? current.identity : null
                    });
                    return originalOnRebind.apply(this, arguments);
                };
            }
            return wrapped;
        }

        Panels.register = function(id, spec) {
            if (id === "lockbox") spec = wrapLockboxSpec(spec);
            return originalRegister.call(Panels, id, spec);
        };

        Bridge.on(CONTROL_TYPE, function(message) {
            var payload = message.payload || {};
            var outcome;
            try {
                if (message.cmd === "bind_timeout") {
                    outcome = requireExact(payload)
                        ? current.adapter.markBindUnknown()
                        : { ok: false, code: "stale_identity" };
                } else if (message.cmd === "bind_query") {
                    outcome = current
                        ? current.adapter.answerBindQuery(payload)
                        : { ok: false, code: "stale_identity" };
                } else if (message.cmd === "core_result") {
                    outcome = requireExact(payload)
                        ? current.adapter.submitCoreOutcome(payload.coreOutcome)
                        : { ok: false, code: "stale_identity" };
                } else if (message.cmd === "user_cancel") {
                    outcome = requireExact(payload)
                        ? current.adapter.submitUserCancel()
                        : { ok: false, code: "stale_identity" };
                } else if (message.cmd === "result_ack") {
                    outcome = current
                        ? current.adapter.handleResultAck(payload)
                        : { ok: false, code: "stale_identity" };
                } else if (message.cmd === "authority_terminal") {
                    outcome = current
                        ? current.adapter.handleAuthorityTerminal(payload)
                        : { ok: false, code: "stale_identity" };
                } else if (message.cmd === "close_request") {
                    var accepted = current
                        ? current.adapter.acceptExactClose(payload)
                        : { ok: false, code: "stale_identity" };
                    if (accepted.ok) {
                        Panels.close();
                        var completed = current.adapter.completeClose();
                        outcome = {
                            ok: completed.ok,
                            code: completed.code,
                            acceptedCode: accepted.code,
                            visualClosed: Panels.getActive() === null
                        };
                    } else {
                        outcome = accepted;
                    }
                } else if (message.cmd === "document_epoch") {
                    outcome = requireExact(payload)
                        ? current.adapter.observeDocumentEpoch(payload.observedEpoch)
                        : { ok: false, code: "stale_identity" };
                } else if (message.cmd === "harness_teardown") {
                    if (payload.harnessOnly !== true || !requireExact(payload)) {
                        outcome = { ok: false, code: "invalid_harness_teardown" };
                    } else {
                        var before = current.adapter.getSnapshot();
                        if (Panels.isOpen()) Panels.close();
                        outcome = {
                            ok: true,
                            code: "harness_teardown_only",
                            adapterStatePreserved: current.adapter.getSnapshot().state === before.state,
                            authorityReleased: false,
                            visualClosed: Panels.getActive() === null
                        };
                    }
                } else {
                    outcome = { ok: false, code: "unsupported_control" };
                }
                reportControl(message, outcome);
            } catch (error) {
                reportControl(message, {
                    ok: false,
                    code: "control_exception",
                    error: error && error.message ? error.message : String(error)
                });
                console.error("[S0 Browser harness] control route failed:", error);
            }
        });

        return {
            getCurrentSnapshot: function() {
                return current ? current.adapter.getSnapshot() : null;
            }
        };
    }

    var host = createBrowserHostShim();
    var webCoordinator = createWebCoordinator();

    function openThroughHost(api, seed, options) {
        var request = host.requestOpen(seed, options || {});
        api.assert(request.ok, "browser Host shim rejected initial open: " + request.code);
        var flow = request.flow;
        return api.waitFor(function() {
            var panel = document.querySelector(".lockbox-panel");
            return flow.domActiveSequence && flow.bindSendSequence
                    && Panels.getActive() === "lockbox" && panel && panel.isConnected
                ? panel : null;
        }, 6000, "lazy real Lockbox DOM and exact bind").then(function(panel) {
            api.assert(flow.domActiveSequence < flow.bindSendSequence,
                "exact bind did not follow committed real DOM");
            return {
                flow: flow,
                panel: panel
            };
        });
    }

    function waitForPuzzleReady(api, opened) {
        return api.waitFor(function() {
            return opened.flow.readySequence || null;
        }, 5000, "real Lockbox puzzle ready").then(function() {
            api.assert(opened.flow.bindSendSequence < opened.flow.readySequence,
                "puzzle ready was incorrectly used as the DOM bind point");
            return opened;
        });
    }

    function runCanonicalCore(api) {
        var state = LockboxPanel._debugGetState();
        api.assert(!!state, "missing real Lockbox state");
        var resultCount = api.getSessionEvents("result").length;
        LockboxPanel._debugStart();
        var path = state.report.canonicalFullPath || state.report.canonicalMainPath;
        api.assert(path && path.length, "missing canonical Lockbox path");
        for (var i = 0; i < path.length; i += 1) {
            LockboxPanel._debugTapCell(path[i].r, path[i].c);
        }
        state = LockboxPanel._debugGetState();
        if (state && state.phase === "MAIN_READY") LockboxPanel._debugSubmit();
        return api.waitFor(function() {
            var currentState = LockboxPanel._debugGetState();
            return currentState && (currentState.phase === "FINISHER" || currentState.result)
                ? currentState : null;
        }, 3000, "real Lockbox result/finisher").then(function(currentState) {
            if (currentState.phase === "FINISHER") {
                api.assert(LockboxPanel._debugResolveFinisher(900), "finisher did not resolve");
            }
            return api.waitForNextSessionEvent("result", resultCount, 3000);
        }).then(function(event) {
            api.assert(event.payload && event.payload.data && event.payload.data.result,
                "real Lockbox did not emit a result payload");
            return event.payload.data.result;
        });
    }

    function waitForPendingResult(api, flow) {
        return api.waitFor(function() {
            return flow.pendingResult && (!flow.coreRouteStarted || flow.coreRouteReply)
                ? flow.pendingResult : null;
        }, 4000, "causally routed S0 result");
    }

    function waitForClosed(api, flow) {
        return api.waitFor(function() {
            return flow.state === "CLOSED" && flow.closeAckSequence ? flow : null;
        }, 4000, "exact close ack");
    }

    function assertLazyProductionPath(api) {
        var boot = host.getBoot();
        api.assert(!boot.lockboxPanelDefined, "Lockbox panel was preloaded before the Browser suite");
        api.assert(!boot.lockboxPanelLazyLoaded, "Lockbox panel script was preloaded before the Browser suite");
        api.assert(typeof LockboxPanel !== "undefined", "production lazy registry did not load LockboxPanel");
        api.assert(LazyLoader.isLoaded(PANEL_SCRIPT), "production LazyLoader did not own lockbox-panel.js");
        api.assert(Panels.requiredAssetsReady(), "production required-assets gate did not complete");
        api.assert(typeof Icons !== "undefined" && typeof AssetTimeline !== "undefined",
            "production required icon assets are unavailable");
    }

    function runW04(api) {
        var first;
        return openThroughHost(api, 0x54040001, { documentEpoch: 1 }).then(function(opened) {
            first = opened;
            return waitForPuzzleReady(api, opened);
        }).then(function() {
            assertLazyProductionPath(api);
            api.assertEqual(first.flow.state, "ACTIVE", "Host exact bind state");
            return runCanonicalCore(api);
        }).then(function(coreResult) {
            api.assertEqual(coreResult.outcome, "success", "real core result");
            return waitForPendingResult(api, first.flow);
        }).then(function() {
            api.assertEqual(first.flow.coreResultCount, 1, "real core result emission count");
            api.assertEqual(first.flow.s0ResultCount, 1, "S0 mapped result emission count");
            api.assertEqual(first.flow.pendingResult.flowCallId, 1, "S0 flowCallId");
            api.assertEqual(first.flow.pendingResult.result, "success", "finite result mapping");
            return host.settleResult(first.flow);
        }).then(function() {
            return waitForClosed(api, first.flow);
        }).then(function() {
            api.assert(Panels.getActive() === null, "known terminal exact close left panel active");
            return openThroughHost(api, 0x54040002, {
                documentEpoch: 1,
                dropBindAck: true
            });
        }).then(function(second) {
            api.assertEqual(second.flow.state, "BIND_ACK_MISSING",
                "Browser Host shim did not drop the accepted bind ack");
            return host.simulateBindTimeout(second.flow).then(function(timeoutReply) {
                api.assert(timeoutReply.outcome && timeoutReply.outcome.ok,
                    "markBindUnknown was not reached through inbound dispatch");
                api.assertEqual(timeoutReply.outcome.code, "bind_unknown", "bind timeout state");
                api.assertEqual(timeoutReply.snapshot.state, S0.STATES.OPEN_BIND_UNKNOWN,
                    "adapter did not enter OPEN_BIND_UNKNOWN");
                api.assert(second.panel.isConnected && Panels.getActive() === "lockbox",
                    "DOM was removed while bind acknowledgement was unknown");
                return host.queryBinding(second.flow);
            }).then(function(queryReply) {
                api.assert(queryReply.outcome && queryReply.outcome.ok,
                    "exact bind query route failed");
                api.assertEqual(queryReply.outcome.binding, "bound", "exact bind query disposition");
                api.assertEqual(queryReply.snapshot.state, S0.STATES.ACTIVE,
                    "exact bind query did not restore ACTIVE");
                api.assertEqual(second.flow.state, "ACTIVE", "Host mapping did not recover exact bind");
                return waitForPuzzleReady(api, second);
            }).then(function() {
                return host.requestUserCancel(second.flow);
            }).then(function(cancelReply) {
                api.assert(cancelReply.outcome && cancelReply.outcome.ok,
                    "cleanup cancel did not use inbound control route");
                return waitForPendingResult(api, second.flow);
            }).then(function() {
                return host.settleResult(second.flow);
            }).then(function() {
                return waitForClosed(api, second.flow);
            }).then(function() {
                return "browser-host-shim (not actual cross-stack): lazy DOM bind precedes ready; accepted bind timeout recovered by exact inbound query";
            });
        });
    }

    function runW05(api) {
        var old;
        var oldIdentity;
        var oldPanel;
        return openThroughHost(api, 0x55050001, { documentEpoch: 1 }).then(function(opened) {
            old = opened;
            oldIdentity = identityPayload(opened.flow.identity);
            oldPanel = opened.panel;
            return waitForPuzzleReady(api, opened);
        }).then(function() {
            assertLazyProductionPath(api);
            var before = host.getCounters();
            var busy = host.requestOpen(0x5505ffff, { documentEpoch: 1 });
            api.assert(!busy.ok && busy.code === "busy",
                "same-name request was not rejected by the Browser Host shim");
            return api.wait(160).then(function() {
                var after = host.getCounters();
                api.assertEqual(after.requestTokens, before.requestTokens,
                    "busy open allocated a request token");
                api.assertEqual(after.identityAllocations, before.identityAllocations,
                    "busy open allocated a new identity");
                api.assertEqual(after.mappings, before.mappings,
                    "busy open replaced the exact mapping");
                api.assertEqual(after.onOpen, before.onOpen,
                    "busy open reached Lockbox onOpen");
                api.assertEqual(after.onRebind, before.onRebind,
                    "busy open reached Lockbox onRebind");
                api.assertEqual(after.ready, before.ready,
                    "busy open emitted a second puzzle ready");
                api.assert(Panels.getActive() === "lockbox"
                        && document.querySelector(".lockbox-panel") === oldPanel,
                    "Host busy rejection replaced the active real DOM");
                api.assert(sameIdentity(host.getCurrent().identity, oldIdentity),
                    "Host busy rejection replaced the active exact identity");
                return host.requestUserCancel(old.flow);
            });
        }).then(function(cancelReply) {
            api.assert(cancelReply.outcome && cancelReply.outcome.ok,
                "old flow cleanup cancel failed");
            return waitForPendingResult(api, old.flow);
        }).then(function() {
            return host.settleResult(old.flow);
        }).then(function() {
            return waitForClosed(api, old.flow);
        }).then(function() {
            return openThroughHost(api, 0x55050002, { documentEpoch: 2 });
        }).then(function(current) {
            api.assert(current.panel === oldPanel, "exact reopen did not reuse the real DOM shell");
            return waitForPuzzleReady(api, current).then(function() {
                return host.sendControl("result_ack", extendIdentity(oldIdentity, {
                    flowCallId: 1,
                    result: "cancel",
                    applied: true,
                    authorityTerminal: true
                }));
            }).then(function(staleAck) {
                api.assertEqual(staleAck.outcome.code, "stale_identity", "old result ack isolation");
                return host.sendControl("bind_query", oldIdentity);
            }).then(function(staleQuery) {
                api.assertEqual(staleQuery.outcome.code, "stale_identity", "old bind query isolation");
                return host.sendControl("close_request", oldIdentity);
            }).then(function(staleClose) {
                api.assertEqual(staleClose.outcome.code, "stale_identity", "old close isolation");
                api.assertEqual(staleClose.snapshot.state, S0.STATES.ACTIVE,
                    "stale traffic changed the new flow");
                api.assert(Panels.getActive() === "lockbox" && current.panel.isConnected,
                    "stale traffic changed the current real DOM");
                return host.sendControl("document_epoch", {
                    identity: identityPayload(current.flow.identity),
                    observedEpoch: 3
                });
            }).then(function(changed) {
                api.assertEqual(changed.outcome.code, "document_epoch_changed", "document epoch change");
                api.assert(changed.snapshot.bound && changed.snapshot.requiresReconcile
                        && !changed.snapshot.canReleasePause,
                    "new document was treated as unbound/terminal evidence");
                return host.sendControl("document_epoch", {
                    identity: identityPayload(current.flow.identity),
                    observedEpoch: 1
                });
            }).then(function(staleEpoch) {
                api.assertEqual(staleEpoch.outcome.code, "stale_document_epoch",
                    "older document epoch was not rejected");
                return host.sendControl("close_request", identityPayload(current.flow.identity));
            }).then(function(rejectedClose) {
                api.assertEqual(rejectedClose.outcome.code, "close_not_allowed",
                    "reconcile-required flow accepted production close");
                api.assert(rejectedClose.snapshot.requiresReconcile
                        && !rejectedClose.snapshot.canReleasePause,
                    "rejected close released reconcile/pause eligibility");
                api.assert(Panels.getActive() === "lockbox" && current.panel.isConnected,
                    "reconcile-required production close removed the DOM");
                return "browser-host-shim (not actual cross-stack): busy rejected before allocation; stale inbound traffic and epoch reconcile preserved active DOM";
            });
        });
    }

    function runSuite(api, caseId) {
        var cases = [
            { id: "W04", title: "lazy real DOM bind/result and exact bind-timeout query", run: runW04 },
            { id: "W05", title: "Host-shim busy-before-allocation, stale flow, and document epoch", run: runW05 }
        ];
        if (caseId) cases = cases.filter(function(item) { return item.id === caseId; });
        var results = [];
        var flow = Promise.resolve();
        cases.forEach(function(item) {
            flow = flow.then(function() {
                return api.runCase(item.id, item.title, function() { return item.run(api); });
            }).then(function(result) {
                results.push(result);
            });
        });
        return flow.then(function() {
            return host.harnessTeardown();
        }).then(function() {
            api.setDump("s0Evidence", host.snapshot());
            return MinigameHarness.normalizeBundle(results);
        });
    }

    var harness = MinigameHarness.create({
        panelId: "lockbox",
        title: "Lockbox Chest S0 Browser QA",
        openPanel: function() {},
        runSuite: runSuite,
        collectDump: function() {
            return {
                evidenceKind: "browser-host-shim",
                actualCrossStack: false,
                activePanel: Panels.getActive(),
                adapter: webCoordinator.getCurrentSnapshot(),
                lockboxState: typeof LockboxPanel !== "undefined"
                    ? LockboxPanel._debugGetState() : null,
                host: host.snapshot()
            };
        }
    });

    window.addEventListener("load", function() {
        harness.boot();
    });
})();
