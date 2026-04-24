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
                '<div class="gobang-title-block">',
                    buildEmblemSvg(),
                    '<div>',
                        '<div class="minigame-kicker">// 旧世遗线 · 铁枪会入侵协议 //</div>',
                        '<div class="minigame-title">虚渊隔离节点接入台</div>',
                    "</div>",
                "</div>",
                '<div class="minigame-header-right">',
                    '<label class="gobang-select-label">协议<select data-gb-control="ruleset">',
                        '<option value="casual">侦查</option>',
                        '<option value="renju">绞杀</option>',
                    "</select></label>",
                    '<label class="gobang-select-label">烈度<select data-gb-control="difficulty">',
                        '<option value="fast">速击</option>',
                        '<option value="normal">标准</option>',
                        '<option value="hard">深渗</option>',
                        '<option value="master">铁枪</option>',
                    "</select></label>",
                    '<label class="gobang-select-label">阵营<select data-gb-control="playerRole">',
                        '<option value="1">铁枪</option>',
                        '<option value="-1">尸解仙</option>',
                    "</select></label>",
                    '<label class="gobang-select-label">对局<select data-gb-control="opponent">',
                        '<option value="ai">引擎</option>',
                        '<option value="local">双侧</option>',
                    "</select></label>",
                    '<div class="minigame-phase-badge" data-gb-phase>INIT</div>',
                    '<button class="minigame-close-btn" type="button" data-action="close">×</button>',
                "</div>",
            "</div>",
            '<div class="minigame-main gobang-main">',
                '<div class="minigame-grid-pane gobang-board-pane">',
                    '<div class="gobang-toolbar">',
                        '<button class="minigame-chrome-btn" type="button" data-action="new">启动遗线</button>',
                        '<button class="minigame-chrome-btn" type="button" data-action="undo">信号回溯</button>',
                        '<button class="minigame-chrome-btn" type="button" data-action="retry-ai">重载引擎</button>',
                        '<button class="minigame-chrome-btn" type="button" data-action="export">作战日志</button>',
                        '<button class="gobang-audio-toggle" type="button" data-action="audio" data-gb-audio title="信号音轨开关">♪ 音轨</button>',
                        '<span class="gobang-readout" data-gb-readout></span>',
                    "</div>",
                    '<div class="gobang-board-shell">',
                        '<div class="gobang-coordinate-row" data-gb-col-labels></div>',
                        '<div class="gobang-coordinate-col" data-gb-row-labels></div>',
                        '<div class="gobang-board" data-gb-board></div>',
                        '<div class="gobang-scanlines" aria-hidden="true"></div>',
                        '<div class="gobang-sweep" aria-hidden="true"></div>',
                    "</div>",
                "</div>",
                '<div class="minigame-side-pane gobang-side-pane">',
                    '<section class="minigame-side-section gobang-status-card">',
                        '<div class="minigame-side-title">局面 · Tactical</div>',
                        '<div class="gobang-status-line" data-gb-status></div>',
                        '<div class="gobang-kv" data-gb-kv></div>',
                    "</section>",
                    '<section class="minigame-side-section">',
                        '<div class="minigame-side-title">黑铁剑引擎 · Rapfi</div>',
                        '<div class="gobang-engine" data-gb-engine></div>',
                    "</section>",
                    '<section class="minigame-side-section gobang-export-wrap">',
                        '<div class="minigame-side-title">作战日志</div>',
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
        _refs.audioToggle = _el.querySelector("[data-gb-audio]");
        syncAudioToggle();
    }

    function audio() {
        return (typeof GobangAudio !== "undefined") ? GobangAudio : null;
    }

    function syncAudioToggle() {
        if (!_refs.audioToggle) return;
        var a = audio();
        var muted = a ? a.isMuted() : true;
        _refs.audioToggle.setAttribute("data-muted", muted ? "1" : "0");
        _refs.audioToggle.textContent = muted ? "♪ 静音" : "♪ 音轨";
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
            rows.push('<span>' + rowLabel(i) + "</span>");
        }
        for (i = 0; i < GobangCore.SIZE * GobangCore.SIZE; i += 1) {
            var row = Math.floor(i / GobangCore.SIZE);
            var col = i % GobangCore.SIZE;
            cells.push(
                '<button type="button" class="gobang-cell" data-row="' + row + '" data-col="' + col + '" title="' +
                formatCoord(row, col) + '"><span class="gobang-stone"></span><span class="gobang-order"></span></button>'
            );
        }
        _refs.colLabels.innerHTML = cols.join("");
        _refs.rowLabels.innerHTML = rows.join("");
        _refs.board.innerHTML = cells.join("");
    }

    function buildEmblemSvg() {
        // 铁枪会图腾简化版：菱形底 + 中央橙红准星 + 交叉枪管 + 电蓝弧 + 上下矛尖
        return [
            '<svg class="gobang-emblem" viewBox="0 0 64 72" role="img" aria-label="铁枪会图腾">',
                '<defs>',
                    '<linearGradient id="gb-emb-frame" x1="0" y1="0" x2="0" y2="1">',
                        '<stop offset="0%" stop-color="#b9bad4"/>',
                        '<stop offset="100%" stop-color="#8b8fae"/>',
                    '</linearGradient>',
                '</defs>',
                // 菱形底
                '<path d="M32 6 L56 36 L32 66 L8 36 Z" fill="url(#gb-emb-frame)" stroke="#2b3144" stroke-width="1.4"/>',
                // 电蓝弧（左右对称）
                '<path d="M22 22 Q28 30 20 38 Q16 44 24 50" fill="none" stroke="#78d6ff" stroke-width="1.6" stroke-linecap="round" opacity="0.85"/>',
                '<path d="M42 22 Q36 30 44 38 Q48 44 40 50" fill="none" stroke="#78d6ff" stroke-width="1.6" stroke-linecap="round" opacity="0.85"/>',
                // 上矛尖
                '<path d="M32 2 L36 12 L32 10 L28 12 Z" fill="#1f2738" stroke="#78d6ff" stroke-width="0.8"/>',
                // 下矛尖
                '<path d="M32 70 L36 60 L32 62 L28 60 Z" fill="#1f2738" stroke="#78d6ff" stroke-width="0.8"/>',
                // 交叉枪管
                '<path d="M14 52 L30 38 M50 52 L34 38" stroke="#1a2130" stroke-width="5" stroke-linecap="round"/>',
                '<path d="M14 52 L30 38 M50 52 L34 38" stroke="#3a4864" stroke-width="2.2" stroke-linecap="round"/>',
                // 中央准星
                '<circle cx="32" cy="34" r="10" fill="#141a28" stroke="#ff6a2a" stroke-width="1.4"/>',
                '<circle cx="32" cy="34" r="6.5" fill="none" stroke="#ff6a2a" stroke-width="1.1"/>',
                '<circle cx="32" cy="34" r="1.6" fill="#ffd2a6"/>',
                '<line x1="32" y1="23" x2="32" y2="28" stroke="#ff6a2a" stroke-width="1.2"/>',
                '<line x1="32" y1="40" x2="32" y2="45" stroke="#ff6a2a" stroke-width="1.2"/>',
                '<line x1="21" y1="34" x2="26" y2="34" stroke="#ff6a2a" stroke-width="1.2"/>',
                '<line x1="38" y1="34" x2="43" y2="34" stroke="#ff6a2a" stroke-width="1.2"/>',
            '</svg>'
        ].join("");
    }

    function onOpen(el, initData) {
        _panelOpen = true;
        _sessionSequence += 1;
        _sessionId = "gobang-" + _sessionSequence + "-" + (Date.now() >>> 0);
        var a = audio();
        if (a) { a.unlock(); a.sessionOpen(); }
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
        var a = audio();
        if (a) a.unlock();
        if (action === "close") closePanel();
        else if (action === "new") { if (a) a.uiTick(); startNewGame(readControls()); }
        else if (action === "undo") { if (a) a.uiTick(); undoMove(); }
        else if (action === "retry-ai") { if (a) a.uiTick(); startAiTurn(); }
        else if (action === "export") { if (a) a.uiTick(); exportSession(); }
        else if (action === "audio") {
            if (a) { a.unlock(); a.toggleMuted(); if (!a.isMuted()) a.uiTick(); }
            syncAudioToggle();
        }
    }

    function handleCellClick(row, col) {
        if (!_state || _pendingAi || _state.status !== "playing") return;
        if (_state.aiEnabled && _state.currentRole !== _state.playerRole) return;
        var a = audio();
        if (a) a.unlock();
        var placingRole = _state.currentRole;
        var result = GobangCore.applyMove(_state, row, col, placingRole, _state.aiEnabled ? "player" : "local");
        if (!result.valid) {
            _state.forbidden = result;
            if (a) a.illegal();
            render();
            return;
        }
        if (a) {
            if (placingRole === 1) a.playerPlace();
            else a.aiPlace();
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
        var aStart = audio();
        if (aStart) aStart.aiStart();
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
            _state.aiError = "AI 返回非法点 " + formatCoord(x, y) + "：" + forbiddenLabelThematic(result.reason);
            var aErr = audio();
            if (aErr) aErr.illegal();
            render();
            return;
        }
        var aAi = audio();
        if (aAi) {
            if (_state.aiRole === 1) aAi.playerPlace();
            else aAi.aiPlace();
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
        var a = audio();
        if (a) {
            if (_state.status === "win") {
                var humanWon = !_state.aiEnabled || _state.winner === _state.playerRole;
                if (humanWon) a.win();
                else a.lose();
            }
        }
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

    function actorName(role) {
        if (role === 1) return "铁枪会锚点";
        if (role === -1) return "尸解仙模因";
        return "未识别";
    }

    function actorShort(role) {
        if (role === 1) return "铁枪";
        if (role === -1) return "尸解仙";
        return "--";
    }

    function phaseText() {
        if (!_state) return "INIT";
        if (_pendingAi) return "模因反制";
        if (_state.status === "win") return _state.winner === 1 ? "信号贯穿" : "虚渊封闭";
        if (_state.status === "draw") return "僵持";
        return actorShort(_state.currentRole) + " · 部署";
    }

    function readoutText() {
        if (!_state) return "";
        return "第 " + (_state.moves.length + 1) + " 手 · " + actorName(_state.currentRole);
    }

    function forbiddenLabelThematic(reason) {
        if (reason === "overline") return "模因过载 · 长连失控";
        if (reason === "double_four") return "防护超限 · 双四退相干";
        if (reason === "double_three") return "防护超限 · 双三退相干";
        if (reason === "occupied") return "节点已占用";
        if (reason === "bounds") return "坐标越界";
        if (reason === "status") return "会话已结束";
        return "非法部署";
    }

    function statusText() {
        if (!_state) return "";
        if (_state.aiError) return _state.aiError;
        if (_state.forbidden && !_state.forbidden.valid) return forbiddenLabelThematic(_state.forbidden.reason);
        if (_pendingAi) return "尸解仙模因反制中 · 超时 " + _state.timeLimit + "ms";
        if (_state.status === "win") {
            if (_state.winner === 1) return "信号链路贯穿 · 虚渊隔离突破";
            return "防护模因完全化 · 虚渊重新封闭";
        }
        if (_state.status === "draw") return "信号僵持 · 双方拓扑锁死";
        if (_state.aiEnabled && _state.currentRole === _state.playerRole) {
            return "待你部署 " + actorName(_state.playerRole);
        }
        if (_state.aiEnabled) return "等待模因反制";
        return actorName(_state.currentRole) + " · 部署中";
    }

    function renderKv() {
        var rules = GobangCore.RULESETS[_state.ruleset];
        var diff = GobangCore.DIFFICULTIES[_state.difficulty];
        var rulesLabel = _state.ruleset === "renju" ? "绞杀 · 禁手判定" : "侦查 · 无禁手";
        var diffLabel = diff ? diff.title + " / " + diff.timeLimit + "ms" : _state.difficulty;
        var sideLabel = _state.aiEnabled ? actorName(_state.playerRole) : "本地双侧";
        return [
            kv("协议", rulesLabel),
            kv("烈度", diffLabel),
            kv("阵营", sideLabel),
            kv("手数", String(_state.moves.length)),
            kv("最近落点", _state.lastMove ? formatCoord(_state.lastMove.row, _state.lastMove.col) : "--")
        ].join("");
    }

    function renderEngine() {
        if (_pendingAi) {
            return '<div class="gobang-engine-line active">call ' + escapeHtml(_pendingAi.callId) + " · " + _pendingAi.payload.timeLimit + "ms · 模因反制中</div>";
        }
        if (_state.aiError) {
            return '<div class="gobang-engine-line error">' + escapeHtml(_state.aiError) + "</div>";
        }
        if (_state.lastEngine) {
            return [
                '<div class="gobang-engine-line">反制落点 ' + escapeHtml(formatCoord(_state.lastEngine.x, _state.lastEngine.y)) + "</div>",
                '<div class="gobang-engine-line">深度 ' + escapeHtml(String(_state.lastEngine.depth)) + " · 评估 " + escapeHtml(String(_state.lastEngine.score)) + "</div>",
                '<div class="gobang-engine-line dim">PV ' + escapeHtml(_state.lastEngine.pv || "--") + "</div>"
            ].join("");
        }
        return '<div class="gobang-engine-line dim">等待首次模因应激</div>';
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
        return "CH-" + String.fromCharCode(65 + col);
    }

    function rowLabel(row) {
        var n = row + 1;
        return n < 10 ? "00" + n : "0" + n;
    }

    function formatCoord(row, col) {
        if (isNaN(row) || isNaN(col)) return "--";
        return columnLabel(col) + "·" + rowLabel(row);
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
