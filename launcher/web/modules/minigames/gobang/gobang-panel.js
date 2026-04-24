var GobangPanel = (function() {
    "use strict";

    var _el;
    var _refs = {};
    var _state = null;
    var _panelOpen = false;
    var _sessionId = null;
    var _sessionSequence = 0;
    var _sessionRequested = null;
    var _pendingAi = null;
    var _callSeq = 0;
    var _aiStub = null;

    var DEFAULT_INIT = {
        mode: "dev",
        source: "runtime",
        ruleset: "casual",
        difficulty: "normal",
        playerRole: 1,
        aiEnabled: true,
        debug: true
    };

    if (typeof Panels !== "undefined") {
        Panels.register("gobang", {
            create: createDOM,
            onOpen: onOpen,
            onRequestClose: function() { closePanel(); },
            onForceClose: cleanup
        });
    }

    if (typeof Bridge !== "undefined" && Bridge.on) {
        Bridge.on("panel_resp", function(data) {
            if (!data || data.panel !== "gobang" || data.cmd !== "gomoku_eval") return;
            handleAiResponse(data.callId, data);
        });
    }

    function createDOM() {
        _el = document.createElement("div");
        _el.className = "minigame-panel gobang-panel";
        _el.innerHTML = [
            '<div class="minigame-header">',
                '<div>',
                    '<div class="minigame-kicker">// GOBANG ENGINE BOARD //</div>',
                    '<div class="minigame-title">五子棋对弈台</div>',
                "</div>",
                '<div class="minigame-header-right">',
                    '<label class="gobang-select-label">规则<select data-gb-control="ruleset">',
                        '<option value="casual">休闲</option>',
                        '<option value="renju">竞技</option>',
                    "</select></label>",
                    '<label class="gobang-select-label">难度<select data-gb-control="difficulty">',
                        '<option value="fast">快速</option>',
                        '<option value="normal">普通</option>',
                        '<option value="hard">困难</option>',
                        '<option value="master">大师</option>',
                    "</select></label>",
                    '<label class="gobang-select-label">执棋<select data-gb-control="playerRole">',
                        '<option value="1">黑</option>',
                        '<option value="-1">白</option>',
                    "</select></label>",
                    '<label class="gobang-select-label">对手<select data-gb-control="opponent">',
                        '<option value="ai">AI</option>',
                        '<option value="local">双人</option>',
                    "</select></label>",
                    '<div class="minigame-phase-badge" data-gb-phase>INIT</div>',
                    '<button class="minigame-close-btn" type="button" data-action="close">×</button>',
                "</div>",
            "</div>",
            '<div class="minigame-main gobang-main">',
                '<div class="minigame-grid-pane gobang-board-pane">',
                    '<div class="gobang-toolbar">',
                        '<button class="minigame-chrome-btn" type="button" data-action="new">新局</button>',
                        '<button class="minigame-chrome-btn" type="button" data-action="undo">悔棋</button>',
                        '<button class="minigame-chrome-btn" type="button" data-action="retry-ai">重试AI</button>',
                        '<button class="minigame-chrome-btn" type="button" data-action="export">导出</button>',
                        '<span class="gobang-readout" data-gb-readout></span>',
                    "</div>",
                    '<div class="gobang-board-shell">',
                        '<div class="gobang-coordinate-row" data-gb-col-labels></div>',
                        '<div class="gobang-board-frame">',
                            '<div class="gobang-coordinate-col" data-gb-row-labels></div>',
                            '<div class="gobang-board" data-gb-board></div>',
                        "</div>",
                    "</div>",
                "</div>",
                '<div class="minigame-side-pane gobang-side-pane">',
                    '<section class="minigame-side-section gobang-status-card">',
                        '<div class="minigame-side-title">局面</div>',
                        '<div class="gobang-status-line" data-gb-status></div>',
                        '<div class="gobang-kv" data-gb-kv></div>',
                    "</section>",
                    '<section class="minigame-side-section">',
                        '<div class="minigame-side-title">引擎</div>',
                        '<div class="gobang-engine" data-gb-engine></div>',
                    "</section>",
                    '<section class="minigame-side-section gobang-export-wrap">',
                        '<div class="minigame-side-title">导出</div>',
                        '<pre class="gobang-export" data-gb-export></pre>',
                    "</section>",
                "</div>",
            "</div>"
        ].join("");
        bindRefs();
        bindEvents();
        buildBoardCells();
        return _el;
    }

    function bindRefs() {
        _refs.board = _el.querySelector("[data-gb-board]");
        _refs.phase = _el.querySelector("[data-gb-phase]");
        _refs.readout = _el.querySelector("[data-gb-readout]");
        _refs.status = _el.querySelector("[data-gb-status]");
        _refs.kv = _el.querySelector("[data-gb-kv]");
        _refs.engine = _el.querySelector("[data-gb-engine]");
        _refs.export = _el.querySelector("[data-gb-export]");
        _refs.ruleset = _el.querySelector('[data-gb-control="ruleset"]');
        _refs.difficulty = _el.querySelector('[data-gb-control="difficulty"]');
        _refs.playerRole = _el.querySelector('[data-gb-control="playerRole"]');
        _refs.opponent = _el.querySelector('[data-gb-control="opponent"]');
        _refs.colLabels = _el.querySelector("[data-gb-col-labels]");
        _refs.rowLabels = _el.querySelector("[data-gb-row-labels]");
    }

    function bindEvents() {
        _el.addEventListener("click", function(event) {
            var actionEl = event.target.closest("[data-action]");
            if (actionEl) {
                handleAction(actionEl.getAttribute("data-action"));
                return;
            }
            var cellEl = event.target.closest(".gobang-cell");
            if (cellEl) {
                handleCellClick(parseInt(cellEl.getAttribute("data-row"), 10), parseInt(cellEl.getAttribute("data-col"), 10));
            }
        });

        var controls = _el.querySelectorAll("[data-gb-control]");
        var i;
        for (i = 0; i < controls.length; i += 1) {
            controls[i].addEventListener("change", function() {
                startNewGame(readControls());
            });
        }
    }

    function buildBoardCells() {
        var cols = [];
        var rows = [];
        var cells = [];
        var i;
        for (i = 0; i < GobangCore.SIZE; i += 1) {
            cols.push('<span>' + columnLabel(i) + "</span>");
            rows.push('<span>' + (i + 1) + "</span>");
        }
        for (i = 0; i < GobangCore.SIZE * GobangCore.SIZE; i += 1) {
            var row = Math.floor(i / GobangCore.SIZE);
            var col = i % GobangCore.SIZE;
            cells.push(
                '<button type="button" class="gobang-cell" data-row="' + row + '" data-col="' + col + '" title="' +
                columnLabel(col) + (row + 1) + '"><span class="gobang-stone"></span><span class="gobang-order"></span></button>'
            );
        }
        _refs.colLabels.innerHTML = cols.join("");
        _refs.rowLabels.innerHTML = rows.join("");
        _refs.board.innerHTML = cells.join("");
    }

    function onOpen(el, initData) {
        _panelOpen = true;
        _sessionSequence += 1;
        _sessionId = "gobang-" + _sessionSequence + "-" + (Date.now() >>> 0);
        startNewGame(merge(DEFAULT_INIT, initData || {}), true);
    }

    function readControls() {
        return {
            mode: "dev",
            source: "runtime",
            ruleset: _refs.ruleset.value,
            difficulty: _refs.difficulty.value,
            playerRole: parseInt(_refs.playerRole.value, 10),
            aiEnabled: _refs.opponent.value !== "local",
            debug: true
        };
    }

    function syncControls(opts) {
        _refs.ruleset.value = GobangCore.normalizeRuleset(opts.ruleset);
        _refs.difficulty.value = GobangCore.normalizeDifficulty(opts.difficulty);
        _refs.playerRole.value = String(opts.playerRole === -1 ? -1 : 1);
        _refs.opponent.value = opts.aiEnabled === false ? "local" : "ai";
    }

    function startNewGame(options, reportOpen) {
        var opts = merge(DEFAULT_INIT, options || {});
        opts.ruleset = GobangCore.normalizeRuleset(opts.ruleset);
        opts.difficulty = GobangCore.normalizeDifficulty(opts.difficulty);
        opts.playerRole = opts.playerRole === -1 ? -1 : 1;
        opts.aiEnabled = opts.aiEnabled !== false;
        syncControls(opts);
        _sessionRequested = cloneJson(opts);
        _pendingAi = null;
        _state = GobangCore.createState(opts);
        _state.aiEnabled = opts.aiEnabled;
        render();
        if (reportOpen) {
            notifyHost("open", { requested: _sessionRequested, resolved: null, metrics: null });
        }
        notifyHost("ready", buildSessionPayload());
        if (_state.aiEnabled && _state.currentRole === _state.aiRole) {
            setTimeout(startAiTurn, 80);
        }
    }

    function handleAction(action) {
        if (action === "close") closePanel();
        else if (action === "new") startNewGame(readControls());
        else if (action === "undo") undoMove();
        else if (action === "retry-ai") startAiTurn();
        else if (action === "export") exportSession();
    }

    function handleCellClick(row, col) {
        if (!_state || _pendingAi || _state.status !== "playing") return;
        if (_state.aiEnabled && _state.currentRole !== _state.playerRole) return;
        var result = GobangCore.applyMove(_state, row, col, _state.currentRole, _state.aiEnabled ? "player" : "local");
        if (!result.valid) {
            _state.forbidden = result;
            render();
            return;
        }
        notifyHost("turn", buildSessionPayload({ move: result.move }));
        render();
        if (_state.status !== "playing") {
            finishGame();
            return;
        }
        if (_state.aiEnabled) startAiTurn();
    }

    function startAiTurn() {
        if (!_state || !_state.aiEnabled || _pendingAi || _state.status !== "playing") return;
        if (_state.currentRole !== _state.aiRole) return;
        var callId = nextCallId();
        var payload = {
            moves: GobangCore.toEngineMoves(_state),
            timeLimit: _state.timeLimit,
            ruleset: _state.ruleset
        };
        _pendingAi = {
            callId: callId,
            startedAt: Date.now(),
            payload: payload
        };
        _state.aiError = "";
        render();

        var stub = _aiStub || window.GobangAiStub;
        if (typeof stub === "function") {
            Promise.resolve().then(function() {
                return stub(payload, GobangCore.cloneState(_state));
            }).then(function(resp) {
                handleAiResponse(callId, normalizeAiStubResponse(resp));
            })["catch"](function(err) {
                handleAiResponse(callId, { success: false, error: err && err.message ? err.message : String(err) });
            });
            return;
        }

        Bridge.send({
            type: "panel",
            panel: "gobang",
            cmd: "gomoku_eval",
            callId: callId,
            payload: payload
        });
    }

    function handleAiResponse(callId, response) {
        if (!_pendingAi || _pendingAi.callId !== callId || !_state) return;
        _pendingAi = null;
        if (!response || !response.success || !response.result) {
            _state.aiError = response && response.error ? response.error : "AI 引擎未返回结果";
            render();
            return;
        }

        var x = parseInt(response.result.x, 10);
        var y = parseInt(response.result.y, 10);
        var result = GobangCore.applyMove(_state, x, y, _state.aiRole, "ai");
        if (!result.valid) {
            _state.aiError = "AI 返回非法点 " + formatCoord(x, y) + "：" + GobangCore.forbiddenLabel(result.reason);
            render();
            return;
        }
        _state.aiError = "";
        _state.lastEngine = {
            x: x,
            y: y,
            score: response.result.score || 0,
            depth: response.result.depth || 0,
            pv: response.result.pv || "",
            elapsedMs: response.elapsedMs || null
        };
        notifyHost("turn", buildSessionPayload({ move: result.move, engine: _state.lastEngine }));
        render();
        if (_state.status !== "playing") finishGame();
    }

    function normalizeAiStubResponse(resp) {
        if (resp && resp.result) return resp;
        if (resp && typeof resp.x === "number" && typeof resp.y === "number") {
            return { success: true, result: resp };
        }
        return resp || { success: false, error: "empty stub response" };
    }

    function undoMove() {
        if (!_state || _pendingAi) return;
        var count = _state.aiEnabled ? 2 : 1;
        GobangCore.undo(_state, count);
        render();
        notifyHost("turn", buildSessionPayload({ undo: count }));
        if (_state.aiEnabled && _state.currentRole === _state.aiRole) startAiTurn();
    }

    function finishGame() {
        render();
        notifyHost("result", buildSessionPayload({ result: buildResultPayload() }));
    }

    function exportSession() {
        if (!_state) return null;
        var exported = GobangCore.buildSessionExport(_state);
        _refs.export.textContent = JSON.stringify(exported, null, 2);
        notifyHost("export", buildSessionPayload({ export: exported }));
        return exported;
    }

    function render() {
        if (!_state || !_refs.board) return;
        var cells = _refs.board.querySelectorAll(".gobang-cell");
        var orderByKey = {};
        var i;
        for (i = 0; i < _state.moves.length; i += 1) {
            orderByKey[_state.moves[i].row + ":" + _state.moves[i].col] = i + 1;
        }
        for (i = 0; i < cells.length; i += 1) {
            var row = parseInt(cells[i].getAttribute("data-row"), 10);
            var col = parseInt(cells[i].getAttribute("data-col"), 10);
            var role = GobangCore.getCell(_state.board, row, col);
            var key = row + ":" + col;
            var last = _state.lastMove && _state.lastMove.row === row && _state.lastMove.col === col;
            cells[i].className = "gobang-cell " + GobangCore.roleClass(role) + (last ? " last" : "");
            cells[i].querySelector(".gobang-order").textContent = orderByKey[key] || "";
        }

        _el.setAttribute("data-status", _state.status);
        _el.setAttribute("data-pending-ai", _pendingAi ? "1" : "0");
        _refs.phase.textContent = phaseText();
        _refs.readout.textContent = readoutText();
        _refs.status.textContent = statusText();
        _refs.kv.innerHTML = renderKv();
        _refs.engine.innerHTML = renderEngine();
    }

    function phaseText() {
        if (!_state) return "INIT";
        if (_pendingAi) return "AI";
        if (_state.status === "win") return "胜负";
        if (_state.status === "draw") return "平局";
        return GobangCore.roleName(_state.currentRole);
    }

    function readoutText() {
        if (!_state) return "";
        return "第 " + (_state.moves.length + 1) + " 手 · " + GobangCore.roleName(_state.currentRole);
    }

    function statusText() {
        if (!_state) return "";
        if (_state.aiError) return _state.aiError;
        if (_state.forbidden && !_state.forbidden.valid) return GobangCore.forbiddenLabel(_state.forbidden.reason);
        if (_pendingAi) return "AI 思考中 " + _state.timeLimit + "ms";
        if (_state.status === "win") return GobangCore.roleName(_state.winner) + "获胜";
        if (_state.status === "draw") return "平局";
        if (_state.aiEnabled && _state.currentRole === _state.playerRole) return "轮到你落子";
        if (_state.aiEnabled) return "等待 AI";
        return GobangCore.roleName(_state.currentRole) + "落子";
    }

    function renderKv() {
        var rules = GobangCore.RULESETS[_state.ruleset];
        var diff = GobangCore.DIFFICULTIES[_state.difficulty];
        return [
            kv("规则", rules ? rules.title : _state.ruleset),
            kv("难度", diff ? diff.title + " / " + diff.timeLimit + "ms" : _state.difficulty),
            kv("执棋", _state.aiEnabled ? GobangCore.roleName(_state.playerRole) : "本地双人"),
            kv("手数", String(_state.moves.length))
        ].join("");
    }

    function renderEngine() {
        if (_pendingAi) {
            return '<div class="gobang-engine-line active">call ' + escapeHtml(_pendingAi.callId) + " · " + _pendingAi.payload.timeLimit + "ms</div>";
        }
        if (_state.aiError) {
            return '<div class="gobang-engine-line error">' + escapeHtml(_state.aiError) + "</div>";
        }
        if (_state.lastEngine) {
            return [
                '<div class="gobang-engine-line">落点 ' + escapeHtml(formatCoord(_state.lastEngine.x, _state.lastEngine.y)) + "</div>",
                '<div class="gobang-engine-line">深度 ' + escapeHtml(String(_state.lastEngine.depth)) + " · 分值 " + escapeHtml(String(_state.lastEngine.score)) + "</div>",
                '<div class="gobang-engine-line dim">' + escapeHtml(_state.lastEngine.pv || "PV --") + "</div>"
            ].join("");
        }
        return '<div class="gobang-engine-line dim">等待首个引擎回合</div>';
    }

    function kv(key, value) {
        return '<div class="gobang-kv-row"><span>' + escapeHtml(key) + '</span><b>' + escapeHtml(value) + "</b></div>";
    }

    function buildSessionPayload(extra) {
        var payload = {
            sessionId: _sessionId,
            requested: _sessionRequested ? cloneJson(_sessionRequested) : null,
            resolved: _state ? {
                ruleset: _state.ruleset,
                difficulty: _state.difficulty,
                playerRole: _state.playerRole,
                aiRole: _state.aiRole,
                aiEnabled: !!_state.aiEnabled,
                timeLimit: _state.timeLimit
            } : null,
            metrics: _state ? GobangCore.getMetrics(_state) : null,
            phase: _pendingAi ? "ai_thinking" : (_state ? _state.status : "closed")
        };
        extra = extra || {};
        var key;
        for (key in extra) payload[key] = extra[key];
        return payload;
    }

    function buildResultPayload() {
        if (!_state) return null;
        return {
            status: _state.status,
            winner: _state.winner,
            moves: _state.moves.length,
            ruleset: _state.ruleset,
            difficulty: _state.difficulty
        };
    }

    function notifyHost(kind, data) {
        if (!_panelOpen && kind !== "close") return false;
        if (typeof MinigameHostBridge !== "undefined" && MinigameHostBridge.sendSession) {
            return MinigameHostBridge.sendSession("gobang", kind, data || {});
        }
        if (typeof Bridge !== "undefined" && Bridge.send) {
            Bridge.send({ type: "panel", cmd: "minigame_session", payload: { game: "gobang", kind: kind, data: data || {} } });
            return true;
        }
        return false;
    }

    function closePanel() {
        notifyHost("close", buildSessionPayload({ result: buildResultPayload() }));
        cleanup();
        if (typeof Panels !== "undefined" && Panels.close) Panels.close();
        Bridge.send({ type: "panel", cmd: "close", panel: "gobang" });
    }

    function cleanup() {
        _panelOpen = false;
        _pendingAi = null;
    }

    function nextCallId() {
        _callSeq += 1;
        return "gobang-" + _callSeq + "-" + (Date.now() >>> 0);
    }

    function columnLabel(col) {
        return String.fromCharCode(65 + col);
    }

    function formatCoord(row, col) {
        if (isNaN(row) || isNaN(col)) return "--";
        return columnLabel(col) + String(row + 1);
    }

    function merge(base, extra) {
        var out = cloneJson(base || {});
        var key;
        for (key in (extra || {})) out[key] = extra[key];
        return out;
    }

    function cloneJson(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function escapeHtml(text) {
        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }

    return {
        _debugBoot: function(init) {
            if (!_el && typeof Panels !== "undefined") Panels.open("gobang", init || {});
            else onOpen(_el, init || {});
        },
        _debugGetState: function() { return _state ? GobangCore.cloneState(_state) : null; },
        _debugClick: function(row, col) { handleCellClick(row, col); },
        _debugUndo: undoMove,
        _debugExport: exportSession,
        _debugSetAiStub: function(fn) { _aiStub = fn; },
        _debugResolveAi: function(row, col) {
            if (!_pendingAi) return false;
            handleAiResponse(_pendingAi.callId, { success: true, result: { x: row, y: col, score: 0, depth: 1, pv: "" } });
            return true;
        }
    };
})();
