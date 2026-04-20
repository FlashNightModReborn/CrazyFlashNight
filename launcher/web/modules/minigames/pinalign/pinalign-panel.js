var PinAlignPanel = (function() {
    "use strict";

    var _el = null;
    var _refs = null;
    var _state = null;
    var _spec = null;
    var _seed = "dev-default";
    var _selected = null;
    var _hint = null;
    var _toast = "";
    var _lastResult = null;
    var _lastReplay = null;
    var _audio = null;
    var _muted = false;
    var _resizeHandler = null;
    var _debugEnabled = false;
    var _eventsExpanded = false;
    var _exportExpanded = false;
    var _flightToken = 0;
    var _hoveredCandidate = null;
    var _sessionSequence = 0;
    var _sessionId = null;
    var _sessionRequested = null;

    var DEFAULT_STAGE_NOTE = "先选一格，再点相邻格交换。主列 +2 分，邻列 +1 分，累计 ≥ 4 才抬针。";

    var CODEX_ENTRIES = [
        { id: "debris", group: "obstacle", name: "碎屑", hint: "障碍。不能交换，不计入匹配。", svg: 'M4 12 L7 5 L10 10 L13 4 L16 8 L14 14 L9 13 L6 15 Z' },
        { id: "clip", group: "obstacle", name: "卡扣", hint: "障碍。外观不同但行为同碎屑。", svg: 'M5 5 Q5 2 9 2 L13 2 Q16 2 16 5 L16 11 Q16 14 13 14 L9 14 Q7 14 7 12 L7 8 Q7 6 9 6 L13 6 Q14 6 14 7 L14 11' },
        { id: "shimH", group: "special", name: "横垫片", hint: "特殊。直接匹配时全行 Effect 清盘。", svg: 'M2 7 L18 7 L18 11 L2 11 Z M4 8 L4 10 M8 8 L8 10 M12 8 L12 10 M16 8 L16 10' },
        { id: "shimV", group: "special", name: "纵垫片", hint: "特殊。直接匹配时全列 Effect 清盘。", svg: 'M7 2 L11 2 L11 18 L7 18 Z M8 4 L10 4 M8 8 L10 8 M8 12 L10 12 M8 16 L10 16' },
        { id: "brace", group: "special", name: "卡箍", hint: "特殊。直接匹配时周围 3×3 Effect 清盘。", svg: 'M9 2 A7 7 0 1 1 8.9 2 Z M9 6 A3 3 0 1 1 8.9 6 Z M3 9 L5 9 M14 9 L17 9 M9 3 L9 5 M9 14 L9 16' },
        { id: "calibrator", group: "special", name: "校准器", hint: "特殊。直接匹配时强制给最需要的锁针主列 +Signal。", svg: 'M10 2 L10 18 M2 10 L18 10 M10 4 A6 6 0 0 1 16 10 A6 6 0 0 1 10 16 A6 6 0 0 1 4 10 A6 6 0 0 1 10 4 Z' },
        { id: "pin-set", group: "state", name: "待锁定", hint: "黄灯。本手再吃信号会过调卡死。", svg: 'M10 2 L10 17 M7 3 L13 3 L12 8 L8 8 Z M7 17 L13 17' },
        { id: "pin-jammed", group: "state", name: "卡死", hint: "红灯。下一手开始会自动解除。", svg: 'M10 2 L10 17 M7 3 L13 3 L12 8 L8 8 Z M5 13 L15 13 M5 13 L13 5 M15 13 L7 5' },
        { id: "pin-locked", group: "state", name: "已锁定", hint: "绿灯。不再受后续信号影响。", svg: 'M10 2 L10 17 M7 3 L13 3 L12 8 L8 8 Z M5 13 L15 13 M6 11 L9 14 L15 8' },
        { id: "signal", group: "concept", name: "Signal", hint: "直接三消的格子，按列算分推进锁针。", svg: 'M10 3 L10 17 M3 10 L17 10 M10 6 A4 4 0 1 1 9.9 6 Z' },
        { id: "effect", group: "concept", name: "Effect", hint: "波及清除的格子，只清盘不算分。", svg: 'M10 10 m-6 0 A6 6 0 1 1 10 16 M10 10 m-3 0 A3 3 0 1 1 10 13' }
    ];

    function buildCodexHtml() {
        var groups = [
            { key: "obstacle", label: "障碍" },
            { key: "special", label: "特殊块" },
            { key: "state", label: "锁针状态" },
            { key: "concept", label: "术语" }
        ];
        var out = ['<div class="pinalign-codex">'];
        var g, i;
        for (g = 0; g < groups.length; g += 1) {
            var group = groups[g];
            out.push('<div class="pinalign-codex-group" data-group="', group.key, '">');
            out.push('<div class="pinalign-codex-group-label">', group.label, '</div>');
            out.push('<ul class="pinalign-codex-list">');
            for (i = 0; i < CODEX_ENTRIES.length; i += 1) {
                var e = CODEX_ENTRIES[i];
                if (e.group !== group.key) continue;
                out.push(
                    '<li class="pinalign-codex-entry" data-id="', e.id, '">',
                        '<span class="pinalign-codex-icon" aria-hidden="true">',
                            '<svg viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">',
                                '<path d="', e.svg, '" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" stroke-linecap="round"/>',
                            '</svg>',
                        '</span>',
                        '<span class="pinalign-codex-text">',
                            '<span class="pinalign-codex-name">', e.name, '</span>',
                            '<span class="pinalign-codex-hint">', e.hint, '</span>',
                        '</span>',
                    '</li>'
                );
            }
            out.push('</ul></div>');
        }
        out.push('</div>');
        return out.join("");
    }

    Panels.register("pinalign", {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: function() { closePanel(); },
        onForceClose: cleanup
    });

    function createDOM() {
        _el = document.createElement("div");
        _el.className = "minigame-panel pinalign-panel";
        _el.innerHTML = [
            '<div class="minigame-header">',
                '<div>',
                    '<div class="minigame-kicker">// LOCK CORE CALIBRATION //</div>',
                    '<div class="minigame-title">锁芯矩阵校准</div>',
                "</div>",
                '<div class="minigame-header-right">',
                    '<div class="pinalign-header-controls" role="group" aria-label="控制台">',
                        '<button class="minigame-chrome-btn pinalign-header-btn" type="button" data-action="hint" title="提示 (H)">提示</button>',
                        '<button class="minigame-chrome-btn pinalign-header-btn" type="button" data-action="clamp" title="夹具 (C)">夹具</button>',
                        '<button class="minigame-chrome-btn pinalign-header-btn" type="button" data-action="reset" title="重开">重开</button>',
                        '<button class="minigame-chrome-btn pinalign-header-btn" type="button" data-action="reroll" title="换种">换种</button>',
                        '<button class="minigame-chrome-btn pinalign-header-btn" type="button" data-action="export" title="导出回放">导出</button>',
                    "</div>",
                    '<div class="minigame-phase-badge" data-pa-phase>观察中</div>',
                    '<button class="minigame-chrome-btn" type="button" data-action="mute">静音</button>',
                    '<button class="minigame-close-btn" type="button" data-action="close">×</button>',
                "</div>",
            "</div>",
            '<div class="minigame-main">',
                '<div class="minigame-grid-pane lockbox-grid-pane">',
                    '<div class="lockbox-quickbar pinalign-toolbar-readout">',
                        '<span class="pinalign-toolbar-chip"><span class="pinalign-toolbar-label">种子</span><span data-pa-seed>dev-default</span></span>',
                        '<span class="pinalign-toolbar-chip"><span class="pinalign-toolbar-label">警报</span><span data-pa-alert>16</span></span>',
                        '<span class="pinalign-toolbar-chip"><span class="pinalign-toolbar-label">夹具</span><span data-pa-clamp>44%</span></span>',
                        '<span class="pinalign-toolbar-chip"><span class="pinalign-toolbar-label">手数</span><span data-pa-moves>0</span></span>',
                    "</div>",
                    '<div class="pinalign-stage-note" data-pa-stage-note>' + DEFAULT_STAGE_NOTE + "</div>",
                    '<div class="lockbox-grid-shell pinalign-grid-shell" data-pa-board-shell>',
                        '<div class="lockbox-trace-frame"></div>',
                        '<div class="pinalign-board-area">',
                            '<div class="pinalign-bezel" aria-hidden="true">',
                                '<div class="pinalign-bezel-face"></div>',
                                '<div class="pinalign-bezel-bevel"></div>',
                                '<div class="pinalign-bezel-rivet rivet-tl"></div>',
                                '<div class="pinalign-bezel-rivet rivet-tr"></div>',
                                '<div class="pinalign-bezel-rivet rivet-bl"></div>',
                                '<div class="pinalign-bezel-rivet rivet-br"></div>',
                                '<div class="pinalign-bezel-seam"></div>',
                            "</div>",
                            '<div class="pinalign-instrument-strip" data-pa-instrument-strip role="group" aria-label="锁针仪表"></div>',
                            '<div class="pinalign-board-stage">',
                                '<div class="pinalign-board" data-pa-board></div>',
                                '<div class="pinalign-lane-layer" data-pa-lane-layer aria-hidden="true"></div>',
                                '<div class="pinalign-flight-layer" data-pa-flight-layer aria-hidden="true"></div>',
                                '<div class="pinalign-preview-layer" data-pa-preview-layer aria-hidden="true"></div>',
                            "</div>",
                        "</div>",
                    "</div>",
                "</div>",
                '<div class="minigame-side-pane">',
                    '<div class="pa-visually-hidden" data-pa-pins-aria aria-live="polite"></div>',
                    '<section class="minigame-side-section pinalign-rules-section">',
                        '<div class="minigame-side-title">规则速览</div>',
                        '<div class="pinalign-side-copy">',
                            '<div class="pinalign-step"><b>1.</b> 探针下色带=归属图。主列每块 <b>+2</b>，邻列 <b>+1</b>，其他不算。</div>',
                            '<div class="pinalign-step"><b>2.</b> 本手直接三消格子 = Signal，累加 <b>≥ 4</b> 才抬针 1 格。</div>',
                            '<div class="pinalign-step"><b>3.</b> 特殊块/连带清除 = Effect，只清盘，不计分。</div>',
                            '<div class="pinalign-step"><b>4.</b> 抬到目标先变“待锁定”，本手末才正式锁定；同手再吃信号会过调卡死。</div>',
                        "</div>",
                    "</section>",
                    '<section class="minigame-side-section pinalign-codex-section">',
                        '<div class="minigame-side-title">图鉴</div>',
                        buildCodexHtml(),
                    "</section>",
                    '<section class="minigame-side-section pinalign-events-section">',
                        '<button class="minigame-side-title minigame-side-title-toggle" type="button" data-action="toggle-events" data-pa-events-toggle>最近结算 ▸</button>',
                        '<div class="pinalign-collapsible" data-pa-events-body hidden>',
                            '<div data-pa-events></div>',
                        "</div>",
                    "</section>",
                    '<section class="minigame-side-section pinalign-export-section">',
                        '<button class="minigame-side-title minigame-side-title-toggle" type="button" data-action="toggle-export" data-pa-export-toggle>回放导出 ▸</button>',
                        '<div class="pinalign-collapsible" data-pa-export-body hidden>',
                            '<pre data-pa-export></pre>',
                        "</div>",
                    "</section>",
                    '<section class="minigame-side-section pinalign-debug-section" data-pa-debug-wrap>',
                        '<div class="minigame-side-title">调试</div>',
                        '<div class="pinalign-debug-copy" data-pa-debug></div>',
                    "</section>",
                "</div>",
            "</div>"
        ].join("");
        _refs = PinAlignDomAdapter.indexRefs(_el);
        bindActions();
        return _el;
    }

    function bindActions() {
        var buttons = _el.querySelectorAll("[data-action]");
        var i;
        for (i = 0; i < buttons.length; i += 1) {
            buttons[i].addEventListener("click", onAction);
        }
    }

    function onOpen(el, initData) {
        var data = initData || {};
        _audio = PinAlignAudio && PinAlignAudio.create ? PinAlignAudio.create() : null;
        _debugEnabled = !!data.debug;
        _muted = false;
        _eventsExpanded = false;
        _exportExpanded = false;
        if (_audio && _audio.setMuted) _audio.setMuted(_muted);
        if (!_resizeHandler) {
            _resizeHandler = function() { render(); };
            window.addEventListener("resize", _resizeHandler);
        }
        bootSession(data);
        if (typeof window.requestAnimationFrame === "function") {
            window.requestAnimationFrame(function() { render(); });
        }
    }

    function bootSession(initData) {
        if (_sessionId) {
            notifyHost("close", buildResultPayload(), {
                phase: describePhaseToken(),
                reason: "reload"
            });
        }
        beginSessionRequest(initData);
        notifyHost("open", null, { phase: "INIT" });
        boot(initData);
        notifyHost("ready", null);
    }

    function boot(initData) {
        _spec = PinAlignLevels.getSpec((initData && initData.specId) || "mvp-3pin-v1");
        _seed = (initData && initData.masterSeed) || "dev-default";
        _state = PinAlignCore.createState(_spec, _seed);
        _selected = null;
        _hoveredCandidate = null;
        _hint = PinAlignCore.getHint(_state);
        _toast = DEFAULT_STAGE_NOTE;
        _lastResult = null;
        _lastReplay = null;
        render();
    }

    function cleanup() {
        detachResizeHandler();
        _selected = null;
        _hoveredCandidate = null;
        _hint = null;
        _toast = "";
        _lastResult = null;
        _lastReplay = null;
        _eventsExpanded = false;
        _exportExpanded = false;
        _state = null;
        _spec = null;
        _audio = null;
        _sessionId = null;
        _sessionRequested = null;
    }

    function closePanel() {
        notifyHost("close", buildResultPayload(), {
            phase: describePhaseToken()
        });
        cleanup();
        if (typeof Panels !== "undefined" && Panels.close) Panels.close();
        Bridge.send({ type: "panel", cmd: "close", panel: "pinalign" });
    }

    function detachResizeHandler() {
        if (_resizeHandler) {
            window.removeEventListener("resize", _resizeHandler);
            _resizeHandler = null;
        }
    }

    function onAction(event) {
        var action = event.currentTarget.getAttribute("data-action");
        if (action === "toggle-events") {
            _eventsExpanded = !_eventsExpanded;
            render();
            return;
        }
        if (action === "toggle-export") {
            _exportExpanded = !_exportExpanded;
            render();
            return;
        }
        if (action === "hint") {
            _hint = PinAlignCore.getHint(_state);
            _toast = _hint ? "已高亮推荐交换的两格，可以直接点击测试。" : "当前没有缓存的有效提示。";
            render();
            return;
        }
        if (action === "clamp") {
            var clamp = PinAlignCore.armClamp(_state);
            _toast = clamp.ok ? "夹具已就绪，只会作用于下一次合法交换。" : "夹具暂时不可用：" + describeClampBlock(clamp.reason);
            if (clamp.ok && _audio) _audio.tick();
            render();
            return;
        }
        if (action === "reset") {
            bootSession({
                specId: _spec.id,
                masterSeed: _seed,
                debug: _debugEnabled
            });
            return;
        }
        if (action === "reroll") {
            bootSession({
                specId: _spec.id,
                masterSeed: "seed-" + Date.now(),
                debug: _debugEnabled
            });
            return;
        }
        if (action === "export") {
            exportReplay();
            return;
        }
        if (action === "mute") {
            _muted = !_muted;
            if (_audio && _audio.setMuted) _audio.setMuted(_muted);
            _toast = _muted ? "音效已静音。" : "音效已恢复。";
            render();
            return;
        }
        if (action === "close") {
            closePanel();
        }
    }

    function onTileHover(pos) {
        if (!_state || _state.status !== "ongoing") return;
        if (!_selected) return;
        if (_selected.row === pos.row && _selected.col === pos.col) return;
        if (Math.abs(_selected.row - pos.row) + Math.abs(_selected.col - pos.col) !== 1) return;
        if (_hoveredCandidate && _hoveredCandidate.row === pos.row && _hoveredCandidate.col === pos.col) return;
        _hoveredCandidate = { row: pos.row, col: pos.col };
        render();
    }

    function onTileLeave(pos) {
        if (!_hoveredCandidate) return;
        if (_hoveredCandidate.row !== pos.row || _hoveredCandidate.col !== pos.col) return;
        _hoveredCandidate = null;
        render();
    }

    function onTileClick(pos) {
        if (!_state || _state.status !== "ongoing") return;
        if (!_selected) {
            _selected = pos;
            _hoveredCandidate = null;
            _hint = null;
            _toast = "已选中一个格子，悬停邻格查看结果，再点击完成交换。";
            render();
            return;
        }
        if (_selected.row === pos.row && _selected.col === pos.col) {
            _selected = null;
            _hoveredCandidate = null;
            _toast = "已取消当前选中。";
            render();
            return;
        }
        if (Math.abs(_selected.row - pos.row) + Math.abs(_selected.col - pos.col) !== 1) {
            _selected = pos;
            _hoveredCandidate = null;
            _toast = "已切换选中格子，请点它的相邻格。";
            render();
            return;
        }

        var result = PinAlignCore.trySwap(_state, _selected, pos);
        _lastResult = result;
        _hint = result.valid ? (result.hint || PinAlignCore.getHint(_state)) : _hint;
        _selected = null;
        _hoveredCandidate = null;
        if (result.valid) _flightToken += 1;
        if (!result.valid) {
            _toast = "非法交换：" + describeSwapBlock(result.reason);
            if (_audio) _audio.tick();
        } else {
            _toast = describeOutcome(result);
            if (_audio) {
                if (_state.status === "win") _audio.win();
                else if (_state.status === "fail") _audio.fail();
                else if (hasJam(result)) _audio.jam();
                else _audio.settle();
            }
            notifyHost("turn", buildResultPayload(), {
                status: _state.status,
                moveIndex: _state.moveIndex,
                alertRemaining: _state.alertRemaining,
                replayHash: result.stateHash || PinAlignCore.computeStateHash(_state)
            });
            if (_state.status !== "ongoing") {
                notifyHost("result", buildResultPayload(), {
                    replayHash: result.stateHash || PinAlignCore.computeStateHash(_state)
                });
            }
        }
        render();
    }

    function render() {
        if (!_refs || !_state) return;
        syncChrome();
        PinAlignDomAdapter.sync(_refs, _state, {
            selected: _selected,
            hoveredCandidate: _hoveredCandidate,
            hint: _hint,
            muted: _muted,
            toast: describeStageNote(),
            lastResult: _lastResult,
            lastReplay: _lastReplay,
            onTileClick: onTileClick,
            onTileHover: onTileHover,
            onTileLeave: onTileLeave,
            eventsExpanded: _eventsExpanded,
            exportExpanded: _exportExpanded,
            flightToken: String(_flightToken),
            debug: _debugEnabled
        });
    }

    function describeStageNote() {
        if (_selected && _hoveredCandidate && _state && _state.status === "ongoing") {
            var manhattan = Math.abs(_selected.row - _hoveredCandidate.row) + Math.abs(_selected.col - _hoveredCandidate.col);
            if (manhattan === 1) {
                var preview = PinAlignCore.previewSwap(_state, _selected, _hoveredCandidate);
                var summary = PinAlignDomAdapter.summarizePreview(preview);
                if (summary) return "悬停预览：" + summary.badge + " — " + summary.detail;
            }
        }
        return _toast || DEFAULT_STAGE_NOTE;
    }

    function syncChrome() {
        if (_refs.phaseBadge) _refs.phaseBadge.textContent = describePhaseLabel();
        if (_refs.root) {
            _refs.root.setAttribute("data-phase", describePhaseToken());
            _refs.root.setAttribute("data-trace-state", describeTraceToken());
            _refs.root.classList.toggle("is-debug", _debugEnabled);
        }
        if (_refs.muteButton) {
            _refs.muteButton.textContent = _muted ? "开音" : "静音";
            _refs.muteButton.classList.toggle("muted", _muted);
        }
    }

    function exportReplay() {
        _lastReplay = PinAlignCore.serializeReplay(_state);
        var text = JSON.stringify(_lastReplay, null, 2);
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text)["catch"](function() {});
        }
        _toast = "回放已导出到面板缓存" + (navigator.clipboard && navigator.clipboard.writeText ? "，并尝试复制到剪贴板。" : "。");
        notifyHost("export", buildResultPayload(), {
            status: _state.status,
            actions: _lastReplay.actions.length
        });
        render();
    }

    function hasJam(result) {
        if (!result || !result.events) return false;
        var e;
        var p;
        for (e = 0; e < result.events.length; e += 1) {
            for (p = 0; p < result.events[e].pinTransitions.length; p += 1) {
                if (result.events[e].pinTransitions[p].toState === "jammed") return true;
            }
        }
        return false;
    }

    function describeOutcome(result) {
        var unjam = (_state && _state.lastMoveUnjammed) || [];
        var prefix = unjam.length
            ? unjam.map(toPinLabel).join("/") + " 解除卡死。"
            : "";
        if (!result.valid) return prefix + "交换被拒绝。";
        if (_state.status === "win") return "全部锁针已锁定，保险箱开启。";
        if (_state.status === "fail") return "警报耗尽，本局校准失败。";
        var signalCount = 0;
        var effectCount = 0;
        var transitions = [];
        var e;
        for (e = 0; e < result.events.length; e += 1) {
            signalCount += result.events[e].signalTiles.length;
            effectCount += result.events[e].effectTiles.length;
            transitions = transitions.concat(result.events[e].pinTransitions || []);
        }
        var committed = result.committedLocks || [];
        if (committed.length) {
            var lockMsg = committed.map(toPinLabel).join(" / ") + " 锁定！";
            var sealInfo = describeSealedLanes(committed);
            var remaining = describeRemainingFocus();
            return prefix + lockMsg + sealInfo + remaining;
        }
        if (hasJam(result)) return prefix + "过调：本手 " + signalCount + " 个 Signal 命中已待锁的锁针，−1 警报，卡死到下一手。";
        if (transitions.length) return prefix + "本手 " + signalCount + " 个 Signal；" + describeTransitionToast(transitions) + (effectCount ? "。另外 " + effectCount + " 个 Effect 只清盘不抬针。" : "。");
        if (result.productive) return prefix + "这次交换产生了特殊块，但没有直接推进锁针。";
        return prefix + "交换合法，匹配成立，但 " + signalCount + " 个 Signal 未累计够阈值。";
    }

    function describeSealedLanes(lockedPinIds) {
        if (!_state || !lockedPinIds.length) return "";
        var cols = [];
        var i;
        var p;
        for (i = 0; i < lockedPinIds.length; i += 1) {
            var pin = findPin(lockedPinIds[i]);
            if (!pin) continue;
            for (var c = 0; c < _state.spec.cols; c += 1) {
                if (PinAlignCore.laneWeight(_state.spec, pin, c) > 0 && cols.indexOf(c + 1) === -1) cols.push(c + 1);
            }
        }
        if (!cols.length) return "";
        cols.sort(function(a, b) { return a - b; });
        return " 列 " + cols.join("/") + " 转为保险区。";
    }

    function describeRemainingFocus() {
        if (!_state) return "";
        var remaining = [];
        var i;
        for (i = 0; i < _state.pins.length; i += 1) {
            if (_state.pins[i].state !== "locked") remaining.push(toPinLabel(_state.pins[i].id));
        }
        if (!remaining.length) return "";
        return "继续推进 " + remaining.join(" / ") + "。";
    }

    function findPin(pinId) {
        if (!_state) return null;
        var i;
        for (i = 0; i < _state.pins.length; i += 1) {
            if (_state.pins[i].id === pinId) return _state.pins[i];
        }
        return null;
    }

    function describeTransitionToast(transitions) {
        var out = [];
        var i;
        for (i = 0; i < transitions.length; i += 1) {
            if (transitions[i].reason === "guarded_overshoot") {
                out.push(toPinLabel(transitions[i].pinId) + " 被夹具保护");
            } else {
                out.push(toPinLabel(transitions[i].pinId) + " " + toPinState(transitions[i].toState));
            }
        }
        return out.join("，");
    }

    function describeClampBlock(reason) {
        if (reason === "status") return "当前已不是可操作状态";
        if (reason === "already_armed") return "夹具已经处于待命状态";
        if (reason === "charge") return "夹具充能不足";
        return reason || "未知原因";
    }

    function describeSwapBlock(reason) {
        if (reason === "non_adjacent") return "只能交换相邻格子";
        if (reason === "out_of_bounds") return "交换位置越界";
        if (reason === "immovable") return "障碍格不能参与交换";
        if (reason === "no_match") return "交换后没有形成直接匹配";
        return reason || "未知原因";
    }

    function toPinLabel(pinId) {
        return "锁针" + String(pinId || "").replace("pin-", "").replace("-", "").toUpperCase();
    }

    function toPinState(state) {
        if (state === "normal") return "回到正常";
        if (state === "set") return "进入待锁定";
        if (state === "jammed") return "卡死";
        if (state === "locked") return "锁定";
        return state;
    }

    function describePhaseToken() {
        if (!_state) return "OBSERVE";
        if (_state.status === "win") return "RESULT";
        if (_state.status === "fail") return "FAIL";
        if (hasJam(_lastResult)) return "FINISHER";
        if (_state.clampArmed || _state.clampActiveThisMove) return "INJECTING";
        if (_state.telemetry.productiveSwaps > 0) return "MAIN_READY";
        return "OBSERVE";
    }

    function describePhaseLabel() {
        var token = describePhaseToken();
        if (token === "RESULT") return "已锁定";
        if (token === "FAIL") return "失败";
        if (token === "FINISHER") return "过调";
        if (token === "INJECTING") return "夹具";
        if (token === "MAIN_READY") return "推进中";
        return "观察中";
    }

    function describeTraceToken() {
        if (!_state) return "normal";
        if (_state.status === "fail") return "trace-fail";
        if (hasJam(_lastResult)) return "overload";
        if (_state.alertRemaining <= 3) return "terminal";
        if (_state.alertRemaining <= 5) return "critical";
        return "normal";
    }

    function nextSessionId() {
        _sessionSequence += 1;
        return "pinalign-" + _sessionSequence + "-" + (Date.now() >>> 0);
    }

    function beginSessionRequest(initData) {
        var data = initData || {};
        _sessionId = nextSessionId();
        _sessionRequested = {
            mode: data.mode || "dev",
            specId: data.specId || "mvp-3pin-v1",
            masterSeed: data.masterSeed || "dev-default",
            debug: !!data.debug
        };
    }

    function buildResolvedData() {
        if (!_state || !_spec) return null;
        return {
            specId: _spec.id,
            masterSeed: _seed,
            rows: _spec.rows,
            cols: _spec.cols,
            pinCount: _spec.pinCount
        };
    }

    function buildMetrics() {
        if (!_state) return null;
        return {
            status: _state.status,
            moveIndex: _state.moveIndex,
            alertRemaining: _state.alertRemaining,
            clampCharge: _state.clampCharge,
            productiveSwaps: _state.telemetry && _state.telemetry.productiveSwaps,
            invalidSwaps: _state.telemetry && _state.telemetry.invalidSwaps,
            jamCount: _state.telemetry && _state.telemetry.jamCount
        };
    }

    function buildResultPayload() {
        if (!_state || _state.status === "ongoing") return null;
        return {
            status: _state.status,
            alertRemaining: _state.alertRemaining,
            replayHash: PinAlignCore.computeStateHash(_state),
            lockedPins: _state.pins.filter(function(pin) { return pin.state === "locked"; }).map(function(pin) { return pin.id; })
        };
    }

    function buildSessionPayload(resultPayload, extraData) {
        var payload = {
            sessionId: _sessionId,
            phase: extraData && extraData.phase ? extraData.phase : describePhaseToken(),
            requested: _sessionRequested ? PinAlignCore.snapshotState(_sessionRequested) : null,
            resolved: buildResolvedData(),
            metrics: buildMetrics(),
            result: resultPayload !== undefined ? resultPayload : buildResultPayload()
        };
        var key;
        if (extraData) {
            for (key in extraData) {
                if (key === "phase") continue;
                payload[key] = extraData[key];
            }
        }
        return payload;
    }

    function notifyHost(kind, payload, extraData) {
        var sessionPayload = buildSessionPayload(payload, extraData);
        if (typeof MinigameHostBridge !== "undefined" && MinigameHostBridge.sendSession) {
            MinigameHostBridge.sendSession("pinalign", kind, sessionPayload);
            return;
        }
        Bridge.send({
            type: "panel",
            cmd: "minigame_session",
            payload: {
                game: "pinalign",
                kind: kind,
                data: sessionPayload
            }
        });
    }

    return {
        _debugBoot: bootSession,
        _debugGetState: function() {
            return _state ? PinAlignCore.snapshotState(_state) : null;
        },
        _debugGetSession: function() {
            return buildSessionPayload(undefined, null);
        },
        _debugGetHint: function() {
            return _state ? PinAlignCore.getHint(_state) : null;
        },
        _debugClickTile: function(pos) {
            onTileClick(pos);
        },
        _debugHoverTile: function(pos) {
            onTileHover(pos);
        },
        _debugLeaveTile: function(pos) {
            onTileLeave(pos);
        },
        _debugSwap: function(from, to) {
            return _state ? PinAlignCore.trySwap(_state, from, to) : null;
        },
        _debugExportReplay: function() {
            exportReplay();
            return _lastReplay;
        }
    };
})();
