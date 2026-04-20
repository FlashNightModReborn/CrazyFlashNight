(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.MinigameHarness = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    function parseQuery(search) {
        var out = {};
        var source = String(search || "").replace(/^\?/, "");
        if (!source) return out;
        var pairs = source.split("&");
        var i;
        for (i = 0; i < pairs.length; i += 1) {
            if (!pairs[i]) continue;
            var part = pairs[i].split("=");
            var key = decodeURIComponent(part[0] || "");
            if (!key) continue;
            var value = part.length > 1 ? decodeURIComponent(part.slice(1).join("=")) : "1";
            out[key] = value;
        }
        return out;
    }

    function escapeHtml(text) {
        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    function nowMs() {
        return typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
    }

    function wait(ms) {
        return new Promise(function(resolve) {
            setTimeout(resolve, Math.max(0, ms || 0));
        });
    }

    function normalizeBundle(results) {
        var bundle = {
            results: results || [],
            passed: 0,
            failed: 0,
            total: 0
        };
        var i;
        for (i = 0; i < bundle.results.length; i += 1) {
            if (bundle.results[i].pass) bundle.passed += 1;
            else bundle.failed += 1;
        }
        bundle.total = bundle.results.length;
        return bundle;
    }

    function ensureUi(title) {
        var qaPanel = document.getElementById("qa-panel");
        if (!qaPanel) {
            qaPanel = document.createElement("div");
            qaPanel.id = "qa-panel";
            qaPanel.hidden = true;
            qaPanel.innerHTML = [
                '<div class="qa-head">',
                    '<span class="qa-title">', escapeHtml(title || "Harness QA"), '</span>',
                    '<button type="button" id="qa-run">Run All</button>',
                    '<span id="qa-summary"></span>',
                "</div>",
                '<ol id="qa-list"></ol>'
            ].join("");
            document.body.appendChild(qaPanel);
        }
        var debugEl = document.getElementById("debug-log");
        if (!debugEl) {
            debugEl = document.createElement("pre");
            debugEl.id = "debug-log";
            debugEl.textContent = "booting...";
            document.body.appendChild(debugEl);
        }
        return {
            qaPanel: qaPanel,
            qaRun: document.getElementById("qa-run"),
            qaSummary: document.getElementById("qa-summary"),
            qaList: document.getElementById("qa-list"),
            debugEl: debugEl
        };
    }

    function create(config) {
        var query = parseQuery(root.location && root.location.search);
        var ui = ensureUi(config && config.title);
        var events = [];
        var logs = [];
        var dumps = {};
        var api = {};
        var originalSend = root.Bridge && root.Bridge.send;

        function syncResultState(bundle) {
            root.__qaResult = {
                panelId: api.panelId,
                query: query,
                events: events.slice(),
                logs: logs.slice(),
                qa: bundle || null,
                dumps: shallowClone(dumps)
            };
        }

        function shallowClone(obj) {
            var out = {};
            var key;
            for (key in obj) out[key] = obj[key];
            return out;
        }

        function log(value) {
            var text = typeof value === "string" ? value : JSON.stringify(value, null, 2);
            logs.push(text);
            ui.debugEl.textContent = text;
            syncResultState(api._bundle || null);
            return text;
        }

        function recordBridgeSend() {
            if (!root.Bridge || !root.Bridge.send || root.Bridge.__qaWrapped) return;
            originalSend = root.Bridge.send;
            root.Bridge.send = function(payload) {
                events.push(payload);
                log(payload);
                if (originalSend) return originalSend.apply(this, arguments);
                return undefined;
            };
            root.Bridge.__qaWrapped = true;
        }

        function renderBundle(bundle) {
            ui.qaPanel.hidden = false;
            ui.qaList.innerHTML = "";
            ui.qaSummary.textContent = bundle.passed + "/" + bundle.total + " passed";
            ui.qaSummary.style.color = bundle.failed ? "#ff8fa3" : "#8de8ab";
            var i;
            for (i = 0; i < bundle.results.length; i += 1) {
                var item = bundle.results[i];
                var li = document.createElement("li");
                li.className = item.pass ? "pass" : "fail";
                li.innerHTML = (item.pass ? "✓ " : "✗ ") +
                    escapeHtml(item.id + " / " + item.title) +
                    ' <span class="detail">(' + item.durationMs + 'ms)</span>' +
                    (item.detail ? '<br><span class="detail">' + escapeHtml(item.detail) + "</span>" : "");
                ui.qaList.appendChild(li);
            }
            api._bundle = bundle;
            syncResultState(bundle);
            return bundle;
        }

        function runCase(id, title, fn) {
            var started = nowMs();
            return Promise.resolve().then(fn).then(function(detail) {
                return {
                    id: id,
                    title: title,
                    pass: true,
                    detail: detail || "",
                    durationMs: Math.round((nowMs() - started) * 100) / 100
                };
            }).catch(function(err) {
                return {
                    id: id,
                    title: title,
                    pass: false,
                    detail: err && err.message ? err.message : String(err),
                    durationMs: Math.round((nowMs() - started) * 100) / 100
                };
            });
        }

        api.panelId = config.panelId;
        api.query = query;
        api.events = events;
        api.logs = logs;
        api.log = log;
        api.wait = wait;
        api.runCase = runCase;
        api.assert = function(condition, detail) {
            if (!condition) throw new Error(detail || "assertion failed");
            return detail || "ok";
        };
        api.assertEqual = function(actual, expected, detail) {
            if (actual !== expected) {
                throw new Error((detail || "values differ") + ": expected " + expected + ", got " + actual);
            }
            return detail || (expected + " == " + actual);
        };
        api.waitFor = function(predicate, timeoutMs, label) {
            var deadline = Date.now() + (timeoutMs || 2000);
            return new Promise(function(resolve, reject) {
                function poll() {
                    var value;
                    try {
                        value = predicate();
                    } catch (err) {
                        reject(err);
                        return;
                    }
                    if (value) {
                        resolve(value);
                        return;
                    }
                    if (Date.now() >= deadline) {
                        reject(new Error("timeout waiting for " + (label || "condition")));
                        return;
                    }
                    setTimeout(poll, 40);
                }
                poll();
            });
        };
        api.getSessionEvents = function(kind) {
            var out = [];
            var i;
            for (i = 0; i < events.length; i += 1) {
                if (!events[i] || events[i].cmd !== "minigame_session") continue;
                if (events[i].payload && events[i].payload.game !== api.panelId) continue;
                if (kind && (!events[i].payload || events[i].payload.kind !== kind)) continue;
                out.push(events[i]);
            }
            return out;
        };
        api.waitForSessionEvent = function(kind, timeoutMs) {
            return api.waitFor(function() {
                var list = api.getSessionEvents(kind);
                return list.length ? list[list.length - 1] : null;
            }, timeoutMs || 2500, "session event " + kind);
        };
        api.waitForNextSessionEvent = function(kind, seenCount, timeoutMs) {
            return api.waitFor(function() {
                var list = api.getSessionEvents(kind);
                return list.length > seenCount ? list[list.length - 1] : null;
            }, timeoutMs || 2500, "next session event " + kind);
        };
        api.captureLayout = function(options) {
            var cfg = options || {};
            var main = document.querySelector(cfg.main || ".minigame-main");
            var side = document.querySelector(cfg.side || ".minigame-side-pane");
            var panel = document.querySelector(cfg.panel || ".minigame-panel");
            function snapshot(node) {
                if (!node) return null;
                var style = root.getComputedStyle(node);
                var rect = node.getBoundingClientRect();
                return {
                    width: Math.round(rect.width),
                    height: Math.round(rect.height),
                    gap: style.gap,
                    padding: [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft].join(" "),
                    gridTemplateColumns: style.gridTemplateColumns,
                    overflow: style.overflow,
                    overflowY: style.overflowY
                };
            }
            var result = {
                panel: snapshot(panel),
                main: snapshot(main),
                side: snapshot(side),
                viewport: {
                    width: root.innerWidth || 0,
                    height: root.innerHeight || 0,
                    dpr: root.devicePixelRatio || 1
                }
            };
            dumps.layout = result;
            syncResultState(api._bundle || null);
            return result;
        };
        api.setDump = function(key, value) {
            dumps[key] = value;
            syncResultState(api._bundle || null);
            return value;
        };
        api.openQaPanel = function() {
            ui.qaPanel.hidden = false;
        };
        api.runBundle = function(resultsPromise) {
            return Promise.resolve(resultsPromise).then(function(results) {
                var bundle = normalizeBundle(results);
                return renderBundle(bundle);
            });
        };
        api.boot = function() {
            recordBridgeSend();
            if (typeof Panels !== "undefined" && Panels.init) Panels.init();
            var flow = Promise.resolve().then(function() {
                return config.openPanel(api);
            }).then(function() {
                return wait(80);
            });

            if (query.scenario && config.runScenario) {
                flow = flow.then(function() {
                    return config.runScenario(api, query.scenario);
                });
            }

            if ((query.qa === "1" || query["case"]) && config.runSuite) {
                flow = flow.then(function() {
                    api.openQaPanel();
                    return config.runSuite(api, query["case"] || null).then(renderBundle);
                });
            }

            if (query.dump === "1" && config.collectDump) {
                flow = flow.then(function() {
                    return Promise.resolve(config.collectDump(api)).then(function(value) {
                        api.setDump("dump", value);
                        return value;
                    });
                });
            }

            return flow["catch"](function(err) {
                log({ error: err && err.message ? err.message : String(err) });
                throw err;
            });
        };

        if (ui.qaRun && config.runSuite) {
            ui.qaRun.addEventListener("click", function() {
                api.openQaPanel();
                config.runSuite(api, null).then(renderBundle);
            });
        }

        syncResultState(null);
        return api;
    }

    return {
        create: create,
        parseQuery: parseQuery,
        normalizeBundle: normalizeBundle,
        wait: wait
    };
});
