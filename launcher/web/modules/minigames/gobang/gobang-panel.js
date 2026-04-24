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
    var _manualOpen = false;
    var _manualTab = "rules";

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
                        '<button class="minigame-chrome-btn" type="button" data-action="manual">教程/规则</button>',
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
            "</div>",
            '<div class="gobang-manual" data-gb-manual aria-hidden="true">',
                '<div class="gobang-manual-card" role="dialog" aria-modal="true" aria-label="五子棋教程与棋谱">',
                    '<div class="gobang-manual-head">',
                        '<div>',
                            '<div class="gobang-manual-kicker">// FIELD MANUAL //</div>',
                            '<div class="gobang-manual-title">五子棋入门 · 规则 · 图谱</div>',
                        "</div>",
                        '<button class="gobang-manual-close" type="button" data-action="manual-close">×</button>',
                    "</div>",
                    '<div class="gobang-manual-tabs">',
                        '<button type="button" data-action="manual-tab" data-gb-manual-tab="rules">规则</button>',
                        '<button type="button" data-action="manual-tab" data-gb-manual-tab="books">棋谱</button>',
                        '<button type="button" data-action="manual-tab" data-gb-manual-tab="ai">AI 指引</button>',
                    "</div>",
                    '<div class="gobang-manual-body" data-gb-manual-body></div>',
                "</div>",
            "</div>"
        ].join("");
        bindRefs();
        bindEvents();
        buildBoardCells();
        renderManual();
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
        _refs.manual = _el.querySelector("[data-gb-manual]");
        _refs.manualBody = _el.querySelector("[data-gb-manual-body]");
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
                handleAction(actionEl.getAttribute("data-action"), actionEl);
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
                var a = audio();
                if (a) { a.unlock(); a.controlChange(); }
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

    function handleAction(action, actionEl) {
        var a = audio();
        if (a) a.unlock();
        if (action === "close") closePanel();
        else if (action === "new") { if (a) a.sessionOpen(); startNewGame(readControls()); }
        else if (action === "undo") { if (a) a.undo(); undoMove(); }
        else if (action === "retry-ai") { if (a) a.uiTick(); startAiTurn(); }
        else if (action === "manual") { if (a) a.uiTick(); openManual("rules"); }
        else if (action === "manual-close") { if (a) a.uiTick(); closeManual(); }
        else if (action === "manual-tab") {
            if (a) a.controlChange();
            switchManualTab(actionEl ? actionEl.getAttribute("data-gb-manual-tab") : "");
        }
        else if (action === "export") { if (a) a.exportLog(); exportSession(); }
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
        playPlacementAudio(a, placingRole, row, col);
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
        playPlacementAudio(aAi, _state.aiRole, x, y);
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

    function playPlacementAudio(a, role, row, col) {
        if (!a || !_state) return;
        if (role === 1) a.playerPlace();
        else a.aiPlace();
        if (a.threat) {
            var line = GobangCore.maxLineLength(_state.board, row, col, role);
            if (line >= 3 && _state.status === "playing") a.threat(role, line);
        }
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
            } else if (_state.status === "draw") {
                a.draw();
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
        renderManual();
    }

    function openManual(tab) {
        _manualOpen = true;
        if (tab) _manualTab = tab;
        renderManual();
    }

    function closeManual() {
        _manualOpen = false;
        renderManual();
    }

    function switchManualTab(tab) {
        if (!manualContent(tab)) return;
        _manualTab = tab;
        _manualOpen = true;
        renderManual();
    }

    function renderManual() {
        if (!_refs.manual || !_refs.manualBody) return;
        _refs.manual.setAttribute("data-open", _manualOpen ? "1" : "0");
        _refs.manual.setAttribute("aria-hidden", _manualOpen ? "false" : "true");
        var tabs = _refs.manual.querySelectorAll("[data-gb-manual-tab]");
        var i;
        for (i = 0; i < tabs.length; i += 1) {
            if (tabs[i].getAttribute("data-gb-manual-tab") === _manualTab) tabs[i].classList.add("active");
            else tabs[i].classList.remove("active");
        }
        _refs.manualBody.innerHTML = manualContent(_manualTab) || manualContent("rules");
    }

    function manualContent(tab) {
        if (tab === "rules") return [
            '<section class="gobang-manual-section">',
                "<h3>先看目标</h3>",
                "<p>把同色棋子连成一条线。横着、竖着、斜着都可以；刚好五颗最稳，白棋长连也算赢。</p>",
                '<div class="gobang-rule-demo">',
                    buildBookBoard([[7, 4, 1], [7, 5, 1], [7, 6, 1], [7, 7, 1], [7, 8, 1]], "黑棋横向五连示意"),
                    '<div><b>读法：</b>数字是落子顺序，颜色是阵营。图里黑棋 1 到 5 连成一条横线，所以黑方完成突破。</div>',
                "</div>",
            "</section>",
            '<section class="gobang-manual-section">',
                "<h3>两个协议</h3>",
                '<table><tbody>',
                    "<tr><th>侦查</th><td>入门模式。只要连成五颗或更多就赢，不需要先理解禁手。</td></tr>",
                    "<tr><th>绞杀</th><td>正式模式。黑棋不能下出长连、双三、双四；白棋不用受这些限制。</td></tr>",
                "</tbody></table>",
                "<p>如果刚开始学，建议先用侦查协议。等你能看出“快要连五”的形状，再切到绞杀协议。</p>",
            "</section>",
            '<section class="gobang-manual-section">',
                "<h3>三个入门动作</h3>",
                '<ul>',
                    "<li><b>先挡四：</b>对方已经有四颗连着时，先堵住它。</li>",
                    "<li><b>再看三：</b>对方有两头都能延伸的三颗连线时，要尽早处理。</li>",
                    "<li><b>别硬背：</b>看不懂就让 AI 继续下一手，观察它为什么堵那个点。</li>",
                "</ul>",
            "</section>"
        ].join("");
        if (tab === "books") return [
            '<section class="gobang-manual-section">',
                "<h3>先看图，再看坐标</h3>",
                "<p>下面每张都是中心局部放大图，不再压成整张小棋盘。读谱时按四步看：黑1在哪里；黑3往哪边伸；白4堵住哪条路；最后一手之后谁更容易连三或连四。</p>",
            "</section>",
            bookCard("星月应手 · 先学封延伸", [
                [7, 7, 1],
                [8, 8, -1],
                [6, 8, 1],
                [6, 7, -1]
            ], "白4贴在黑3旁边，把黑棋下沿的扩张先按住。入门时先记形状：黑棋从中心伸出去，白棋不要跟丢，先贴住它的延伸方向。", [
                "看黑1和黑3：它们正在中心附近做第二个支点。",
                "看白4：不是随便贴，而是挡住黑3继续向左连的路线。",
                "下一眼：如果黑棋继续在中心附近补点，先检查它会不会形成两头都能走的三。"
            ]),
            bookCard("花月 / 浦月先导 · 贴身切断", [
                [7, 7, 1],
                [8, 8, -1],
                [9, 8, 1],
                [6, 7, -1],
                [8, 9, 1],
                [9, 9, -1]
            ], "这不是完整花月全谱，而是先导图。它展示的是黑棋绕中心做连接，白棋用贴身点切断，不让黑棋轻松把两条方向合起来。", [
                "黑3把战场拉到中心下侧，黑5再回到右侧补连接。",
                "白4和白6都在贴身干扰，不追远点，先拆黑棋最近的结构。",
                "下一眼：黑棋如果能同时威胁两边，白棋就会很难只用一手挡住。"
            ]),
            bookCard("中心横向二连 · 马上堵端点", [
                [7, 7, 1],
                [8, 8, -1],
                [7, 8, 1],
                [7, 9, -1]
            ], "黑1和黑3已经在中心横向连起来。白4先堵右端，避免黑棋继续长成活三。", [
                "入门口诀：看到贴身二连，先问两端还能不能继续伸。",
                "这里白4堵的是右端；如果黑棋换到另一侧伸，防守点也要跟着对称移动。",
                "下一眼：如果黑棋再从左端补一手，白棋要立刻重新判断有没有活三。"
            ]),
            bookCard("中心对角扩展 · 看远一格", [
                [7, 7, 1],
                [8, 8, -1],
                [6, 6, 1],
                [8, 6, -1],
                [6, 5, 1]
            ], "这组更像真正打谱：黑棋没有只贴着中心下，而是把斜线和横向扩张连在一起。入门者看不懂时，先找黑棋哪两颗能在下一步变成三。", [
                "黑1和黑3形成斜向骨架，黑5再往左压出第二条路。",
                "白4站在下方切断，目标是让黑棋不能舒服地连续扩张。",
                "下一眼：检查黑棋在左侧和中心是否同时有下一手。"
            ])
        ].join("");
        if (tab === "ai") return [
            '<section class="gobang-manual-section">',
                "<h3>不会下时怎么用引擎</h3>",
                "<p>本小游戏不做自动打谱。想看下一手时，继续和 Rapfi 引擎对局，观察它把棋落在哪里。</p>",
                '<ul>',
                    "<li><b>想学防守：</b>让 AI 执白，看它怎样堵黑棋的连线。</li>",
                    "<li><b>想学进攻：</b>切换阵营，让 AI 执黑，看它怎样从中心向外连。</li>",
                    "<li><b>想慢慢看：</b>改成本地双侧，照着图谱手动摆一遍。</li>",
                    "<li><b>AI 卡住：</b>点“重载引擎”，只重试当前请求，不会替你乱落子。</li>",
                "</ul>",
            "</section>",
            '<section class="gobang-manual-section">',
                "<h3>一眼判断</h3>",
                "<p>每一步先问：对方有没有四颗快赢？有没有两边都能延伸的三颗？我的下一手能不能同时进攻和防守？</p>",
            "</section>"
        ].join("");
        return "";
    }

    function bookCard(title, moves, caption, notes) {
        return [
            '<section class="gobang-manual-section gobang-book-card">',
                '<div class="gobang-book-head">',
                    "<h3>" + escapeHtml(title) + "</h3>",
                    '<span>中心局部放大 · 数字 = 落子顺序</span>',
                "</div>",
                '<div class="gobang-book-visual">',
                    buildBookBoard(moves, title),
                    '<div class="gobang-book-side">',
                        '<ol class="gobang-book-steps">',
                            buildBookSteps(moves),
                        "</ol>",
                        buildBookNotes(notes),
                    "</div>",
                "</div>",
                '<p class="gobang-book-caption">' + escapeHtml(caption) + "</p>",
            "</section>"
        ].join("");
    }

    function buildBookNotes(notes) {
        if (!notes || !notes.length) return "";
        var out = ['<ul class="gobang-book-notes">'];
        var i;
        for (i = 0; i < notes.length; i += 1) {
            out.push("<li>" + escapeHtml(notes[i]) + "</li>");
        }
        out.push("</ul>");
        return out.join("");
    }

    function buildBookSteps(moves) {
        var out = [];
        var i;
        for (i = 0; i < moves.length; i += 1) {
            out.push(
                "<li><b>" + (moves[i][2] === 1 ? "黑" : "白") + (i + 1) + "</b> <code>" +
                formatCoord(moves[i][0], moves[i][1]) + "</code></li>"
            );
        }
        return out.join("");
    }

    function buildBookBoard(moves, label) {
        var moveByKey = {};
        var i;
        var view = bookViewForMoves(moves);
        for (i = 0; i < moves.length; i += 1) {
            moveByKey[moves[i][0] + ":" + moves[i][1]] = {
                role: moves[i][2],
                order: i + 1
            };
        }
        var cells = [];
        cells.push('<span class="gobang-book-corner">局部</span>');
        for (i = view.colMin; i <= view.colMax; i += 1) {
            cells.push('<span class="gobang-book-axis col" title="' + columnLabel(i) + '">' + shortColumnLabel(i) + "</span>");
        }
        for (var row = view.rowMin; row <= view.rowMax; row += 1) {
            cells.push('<span class="gobang-book-axis row" title="' + rowLabel(row) + '">' + rowLabel(row) + "</span>");
            for (var col = view.colMin; col <= view.colMax; col += 1) {
                var move = moveByKey[row + ":" + col];
                var cls = "gobang-book-cell" + (isBookStar(row, col) ? " star" : "");
                var body = "";
                if (move) {
                    cls += move.role === 1 ? " black" : " white";
                    if (move.order === moves.length) cls += " last";
                    body = "<span>" + move.order + "</span>";
                }
                cells.push('<span class="' + cls + '" title="' + formatCoord(row, col) + '">' + body + "</span>");
            }
        }
        return '<div class="gobang-book-board" aria-label="' + escapeHtml(label || "棋谱图示") + '">' + cells.join("") + "</div>";
    }

    function bookViewForMoves(moves) {
        var minRow = 7;
        var maxRow = 7;
        var minCol = 7;
        var maxCol = 7;
        var i;
        for (i = 0; i < moves.length; i += 1) {
            minRow = Math.min(minRow, moves[i][0]);
            maxRow = Math.max(maxRow, moves[i][0]);
            minCol = Math.min(minCol, moves[i][1]);
            maxCol = Math.max(maxCol, moves[i][1]);
        }
        var span = 9;
        var centerRow = Math.round((minRow + maxRow) / 2);
        var centerCol = Math.round((minCol + maxCol) / 2);
        centerRow = Math.max(4, Math.min(10, centerRow));
        centerCol = Math.max(4, Math.min(10, centerCol));
        return {
            rowMin: centerRow - 4,
            rowMax: centerRow + 4,
            colMin: centerCol - 4,
            colMax: centerCol + 4,
            span: span
        };
    }

    function shortColumnLabel(col) {
        return String.fromCharCode(65 + col);
    }

    function isBookStar(row, col) {
        var starRow = row === 3 || row === 7 || row === 11;
        var starCol = col === 3 || col === 7 || col === 11;
        return starRow && starCol;
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
        _manualOpen = false;
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
        _debugOpenManual: openManual,
        _debugCloseManual: closeManual,
        _debugSetAiStub: function(fn) { _aiStub = fn; },
        _debugResolveAi: function(row, col) {
            if (!_pendingAi) return false;
            handleAiResponse(_pendingAi.callId, { success: true, result: { x: row, y: col, score: 0, depth: 1, pv: "" } });
            return true;
        }
    };
})();
