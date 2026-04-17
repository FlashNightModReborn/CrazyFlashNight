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

    var DEFAULT_STAGE_NOTE = "先选一格，再点相邻格交换。只有直接三消会推进锁针，连带清除不算。";

    Panels.register("pinalign", {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: function() { closePanel(); },
        onForceClose: cleanup
    });

    function createDOM() {
        _el = document.createElement("div");
        _el.className = "lockbox-panel pinalign-panel";
        _el.innerHTML = [
            '<div class="lockbox-header">',
                '<div>',
                    '<div class="lockbox-kicker">// LOCK CORE CALIBRATION //</div>',
                    '<div class="lockbox-title">锁芯矩阵校准</div>',
                "</div>",
                '<div class="lockbox-header-right">',
                    '<div class="lockbox-phase-badge" data-pa-phase>观察中</div>',
                    '<button class="lockbox-chrome-btn" type="button" data-action="mute">静音</button>',
                    '<button class="lockbox-close-btn" type="button" data-action="close">×</button>',
                "</div>",
            "</div>",
            '<div class="lockbox-main">',
                '<div class="lockbox-grid-pane">',
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
                                '<div class="pinalign-bezel-outer"></div>',
                                '<div class="pinalign-bezel-ring"></div>',
                                '<div class="pinalign-bezel-ticks"></div>',
                                '<div class="pinalign-bezel-rivet rivet-tl"></div>',
                                '<div class="pinalign-bezel-rivet rivet-tr"></div>',
                                '<div class="pinalign-bezel-rivet rivet-bl"></div>',
                                '<div class="pinalign-bezel-rivet rivet-br"></div>',
                            "</div>",
                            '<div class="pinalign-board" data-pa-board></div>',
                            '<div class="pinalign-flight-layer" data-pa-flight-layer aria-hidden="true"></div>',
                            '<div class="pinalign-preview-layer" data-pa-preview-layer aria-hidden="true"></div>',
                        "</div>",
                        '<div class="pinalign-lane-belt" data-pa-lane-belt aria-hidden="true"></div>',
                    "</div>",
                "</div>",
                '<div class="lockbox-side-pane">',
                    '<section class="lockbox-side-section pinalign-pins-section">',
                        '<div class="lockbox-side-title">锁针状态</div>',
                        '<div data-pa-pins></div>',
                    "</section>",
                    '<section class="lockbox-side-section pinalign-rules-section">',
                        '<div class="lockbox-side-title">规则速览</div>',
                        '<div class="pinalign-side-copy">',
                            '<div class="pinalign-step"><b>1.</b> 每根锁针有主列和邻列，棋盘底部色带显示哪列属于谁、影响多大。</div>',
                            '<div class="pinalign-step"><b>2.</b> 直接三消格子 = Signal，本手累计够阈值，锁针才抬 1 格。</div>',
                            '<div class="pinalign-step"><b>3.</b> 特殊块和波及清除 = Effect，只清盘，不推进锁针。</div>',
                            '<div class="pinalign-step"><b>4.</b> 抬到目标先变“待锁定”，本手末才正式锁定；同手再吃信号会过调卡死。</div>',
                        "</div>",
                    "</section>",
                    '<section class="lockbox-side-section pinalign-console-section">',
                        '<div class="lockbox-side-title">控制台</div>',
                        '<div class="pinalign-console-grid">',
                            '<button class="lockbox-chrome-btn" type="button" data-action="hint">提示</button>',
                            '<button class="lockbox-chrome-btn" type="button" data-action="clamp">夹具</button>',
                            '<button class="lockbox-chrome-btn" type="button" data-action="reset">重开</button>',
                            '<button class="lockbox-chrome-btn" type="button" data-action="reroll">换种</button>',
                            '<button class="lockbox-chrome-btn" type="button" data-action="export">导出</button>',
                        "</div>",
                    "</section>",
                    '<section class="lockbox-side-section pinalign-events-section">',
                        '<button class="lockbox-side-title lockbox-side-title-toggle" type="button" data-action="toggle-events" data-pa-events-toggle>最近结算 ▸</button>',
                        '<div class="pinalign-collapsible" data-pa-events-body hidden>',
                            '<div data-pa-events></div>',
                        "</div>",
                    "</section>",
                    '<section class="lockbox-side-section pinalign-export-section">',
                        '<button class="lockbox-side-title lockbox-side-title-toggle" type="button" data-action="toggle-export" data-pa-export-toggle>回放导出 ▸</button>',
                        '<div class="pinalign-collapsible" data-pa-export-body hidden>',
                            '<pre data-pa-export></pre>',
                        "</div>",
                    "</section>",
                    '<section class="lockbox-side-section pinalign-debug-section" data-pa-debug-wrap>',
                        '<div class="lockbox-side-title">调试</div>',
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
        boot(data);
        notifyHost("open", {
            specId: _spec.id,
            masterSeed: _seed
        });
        if (typeof window.requestAnimationFrame === "function") {
            window.requestAnimationFrame(function() { render(); });
        }
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
    }

    function closePanel() {
        var status = _state ? _state.status : "unknown";
        cleanup();
        if (typeof Panels !== "undefined" && Panels.close) Panels.close();
        Bridge.send({ type: "panel", cmd: "close", panel: "pinalign" });
        notifyHost("close", {
            status: status
        });
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
            boot({ specId: _spec.id, masterSeed: _seed });
            return;
        }
        if (action === "reroll") {
            boot({ specId: _spec.id, masterSeed: "seed-" + Date.now() });
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
            _toast = "已取消当前选中。";
            render();
            return;
        }
        if (Math.abs(_selected.row - pos.row) + Math.abs(_selected.col - pos.col) !== 1) {
            _selected = pos;
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
            notifyHost("turn", {
                status: _state.status,
                moveIndex: _state.moveIndex,
                alertRemaining: _state.alertRemaining,
                replayHash: result.stateHash || PinAlignCore.computeStateHash(_state)
            });
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
            var preview = PinAlignCore.previewSwap(_state, _selected, _hoveredCandidate);
            var summary = PinAlignDomAdapter.summarizePreview(preview);
            if (summary) return "悬停预览：" + summary.badge + " — " + summary.detail;
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
        notifyHost("export", {
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

    function notifyHost(kind, payload) {
        Bridge.send({
            type: "panel",
            cmd: "pinalign_session",
            payload: {
                kind: kind,
                data: payload || {}
            }
        });
    }

    return {
        _debugBoot: boot
    };
})();
