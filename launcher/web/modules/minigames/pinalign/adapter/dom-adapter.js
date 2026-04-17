(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.PinAlignDomAdapter = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    function indexRefs(root) {
        return {
            root: root,
            board: root.querySelector("[data-pa-board]"),
            boardShell: root.querySelector("[data-pa-board-shell]"),
            laneOverlay: root.querySelector("[data-pa-lane-overlay]"),
            shellSummary: root.querySelector("[data-pa-shell-summary]"),
            shellGuide: root.querySelector("[data-pa-shell-guide]"),
            shellPins: root.querySelector("[data-pa-shell-pins]"),
            phaseBadge: root.querySelector("[data-pa-phase]"),
            helpPanel: root.querySelector("[data-pa-help-panel]"),
            seed: root.querySelector("[data-pa-seed]"),
            alert: root.querySelector("[data-pa-alert]"),
            clamp: root.querySelector("[data-pa-clamp]"),
            status: root.querySelector("[data-pa-status]"),
            hint: root.querySelector("[data-pa-hint]"),
            toast: root.querySelector("[data-pa-toast]"),
            pins: root.querySelector("[data-pa-pins]"),
            events: root.querySelector("[data-pa-events]"),
            resolution: root.querySelector("[data-pa-resolution]"),
            meta: root.querySelector("[data-pa-meta]"),
            export: root.querySelector("[data-pa-export]"),
            debug: root.querySelector("[data-pa-debug]"),
            debugWrap: root.querySelector("[data-pa-debug-wrap]"),
            muteButton: root.querySelector('[data-action="mute"]'),
            sideToggle: root.querySelector('[data-action="toggle-side"]'),
            stageStatus: root.querySelector("[data-pa-stage-status]"),
            stageHint: root.querySelector("[data-pa-stage-hint]"),
            seedNote: root.querySelector("[data-pa-seed-note]")
        };
    }

    function sync(refs, state, viewModel) {
        var layoutInfo = fitBoard(refs, viewModel);
        renderBoard(refs.board, state, viewModel);
        renderLaneOverlay(refs.laneOverlay, state);
        renderHud(refs, state, viewModel, layoutInfo);
        renderShellSummary(refs, state, viewModel);
        renderShellPins(refs.shellPins, state);
        renderPins(refs.pins, state);
        renderResolution(refs.resolution, state, viewModel.lastResult);
        renderEvents(refs.events, viewModel.lastResult);
        renderExport(refs.export, viewModel.lastReplay);
        renderButtons(refs, viewModel);
        renderDebug(refs, state, viewModel, layoutInfo);
        setToast(refs, viewModel.toast || "");
    }

    function fitBoard(refs, viewModel) {
        var rootWidth = refs.root ? Math.max(refs.root.clientWidth || 0, 0) : 0;
        var rootHeight = refs.root ? Math.max(refs.root.clientHeight || 0, 0) : 0;
        var viewportWidth = window.innerWidth || rootWidth || 1280;
        var viewportHeight = window.innerHeight || rootHeight || 800;
        if (!rootWidth) rootWidth = viewportWidth;
        if (!rootHeight) rootHeight = viewportHeight;

        var stacked = rootWidth < 920;
        var tight = rootWidth < 1180;
        var phone = rootWidth < 760;
        var sideCollapsed = !!viewModel.sideCollapsed;

        if (refs.root) {
            refs.root.classList.toggle("is-stacked", stacked);
            refs.root.classList.toggle("is-tight", tight && !stacked);
            refs.root.classList.toggle("is-phone", phone);
            refs.root.classList.toggle("is-side-collapsed", sideCollapsed);
            refs.root.setAttribute("data-layout", stacked ? "stacked" : (tight ? "tight" : "wide"));
            refs.root.setAttribute("data-side", sideCollapsed ? "collapsed" : "open");
        }

        if (!refs.board || !refs.boardShell) {
            return {
                rootWidth: rootWidth,
                rootHeight: rootHeight,
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight,
                boardShellWidth: 0,
                boardSize: 0,
                stacked: stacked,
                tight: tight,
                phone: phone,
                sideCollapsed: sideCollapsed
            };
        }

        var shellWidth = Math.max(0, refs.boardShell.clientWidth - (phone ? 12 : 18));
        var shortHeight = rootHeight < 620;
        var sizeByWidth = stacked ? 620 : (sideCollapsed ? 620 : (tight ? 520 : 600));
        var rootRect = refs.root.getBoundingClientRect ? refs.root.getBoundingClientRect() : null;
        var shellRect = refs.boardShell.getBoundingClientRect ? refs.boardShell.getBoundingClientRect() : null;
        var topOffset = rootRect && shellRect ? Math.max(0, shellRect.top - rootRect.top) : 0;
        var footerReserve = measureBlockHeight(refs.hint) + measureBlockHeight(refs.meta) + 12;
        var derivedHeight = Math.max(0, rootHeight - topOffset - footerReserve);
        var ratioHeight = Math.floor(rootHeight * (stacked ? (shortHeight ? 0.58 : 0.64) : (sideCollapsed ? (shortHeight ? 0.76 : 0.84) : (shortHeight ? 0.68 : 0.76))));
        var viewportHeightCap = Math.floor(viewportHeight * (stacked ? (shortHeight ? 0.64 : 0.72) : (sideCollapsed ? (shortHeight ? 0.8 : 0.9) : (shortHeight ? 0.72 : 0.82))));
        var sizeByHeight = Math.floor(Math.min(Math.max(derivedHeight, ratioHeight), viewportHeightCap));
        var size = Math.floor(Math.min(shellWidth, sizeByWidth, sizeByHeight));

        if (!size || size < 260) {
            size = Math.floor(Math.min(Math.max(shellWidth, 260), sizeByWidth));
        }
        size = clamp(size, 260, 620);

        refs.root.style.setProperty("--pa-board-size", size + "px");
        refs.root.style.setProperty("--pa-board-gap", size < 320 ? "6px" : (size < 430 ? "8px" : "10px"));
        refs.board.style.width = size + "px";
        refs.board.style.height = size + "px";
        refs.boardShell.style.minHeight = (size + 18) + "px";

        return {
            rootWidth: rootWidth,
            rootHeight: rootHeight,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            boardShellWidth: shellWidth,
            boardSize: size,
            stacked: stacked,
            tight: tight,
            phone: phone,
            sideCollapsed: sideCollapsed
        };
    }

    function renderBoard(container, state, viewModel) {
        if (!container) return;
        container.innerHTML = "";
        var row;
        var col;
        for (row = 0; row < state.spec.rows; row += 1) {
            for (col = 0; col < state.spec.cols; col += 1) {
                var tile = state.board[row][col];
                var btn = document.createElement("button");
                btn.type = "button";
                btn.className = buildTileClass(tile, viewModel, row, col);
                btn.setAttribute("data-row", row);
                btn.setAttribute("data-col", col);
                btn.disabled = !tile || tile.kind === "obstacle";
                btn.innerHTML = buildTileInner(tile);
                if (viewModel.onTileClick) {
                    btn.addEventListener("click", bindTileClick(viewModel.onTileClick, row, col));
                }
                container.appendChild(btn);
            }
        }
    }

    function renderLaneOverlay(container, state) {
        if (!container) return;
        container.innerHTML = "";
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            container.insertAdjacentHTML("beforeend", buildLaneGuide(state.spec, state.pins[i]));
        }
    }

    function buildTileClass(tile, viewModel, row, col) {
        var className = "pinalign-tile";
        if (!tile) return className + " is-empty";
        className += " kind-" + tile.kind;
        if (tile.kind === "gem" || tile.kind === "special") className += " color-" + tile.color;
        if (tile.kind === "special" && tile.specialType) className += " special-" + tile.specialType;
        if (tile.kind === "obstacle" && tile.obstacleType) className += " obstacle-" + tile.obstacleType;
        if (viewModel.selected && viewModel.selected.row === row && viewModel.selected.col === col) className += " is-selected";
        if (viewModel.hint && isHintCell(viewModel.hint, row, col)) className += " is-hint";
        return className;
    }

    function buildTileInner(tile) {
        if (!tile) return "";
        if (tile.kind === "obstacle") {
            return '<span class="pinalign-tile-label">' + escapeHtml(describeObstacle(tile.obstacleType || "obstacle")) + "</span>";
        }
        if (tile.kind === "special") {
            return '<span class="pinalign-tile-badge">' + escapeHtml(shortSpecial(tile.specialType)) + "</span>";
        }
        return '<span class="pinalign-tile-gem"></span>';
    }

    function bindTileClick(handler, row, col) {
        return function() {
            handler({ row: row, col: col });
        };
    }

    function isHintCell(hint, row, col) {
        if (!hint) return false;
        return (hint.from.row === row && hint.from.col === col) || (hint.to.row === row && hint.to.col === col);
    }

    function renderHud(refs, state, viewModel, layoutInfo) {
        if (refs.seed) refs.seed.textContent = state.masterSeed;
        if (refs.alert) refs.alert.textContent = String(state.alertRemaining);
        if (refs.clamp) refs.clamp.textContent = String(state.clampCharge) + "%";
        if (refs.status) refs.status.textContent = describeStatus(state);
        if (refs.hint) refs.hint.textContent = describeHint(viewModel.hint);
        if (refs.meta) {
            refs.meta.textContent = [
                "第 " + state.moveIndex + " 手",
                "有效推进 " + state.telemetry.productiveSwaps + "/" + state.telemetry.legalSwaps,
                "卡针 " + state.telemetry.jamCount,
                "布局 " + describeLayout(layoutInfo)
            ].join(" | ");
        }
        if (refs.stageStatus) refs.stageStatus.textContent = describeStageStatus(state, viewModel.lastResult);
        if (refs.stageHint) refs.stageHint.textContent = describeStageHint(state, viewModel.hint, layoutInfo);
        if (refs.seedNote) refs.seedNote.setAttribute("data-summary", "种子 " + state.masterSeed + " | 警报 " + state.alertRemaining + " | 夹具 " + state.clampCharge + "% | 状态 " + describeStatus(state));
    }

    function renderPins(container, state) {
        if (!container) return;
        container.innerHTML = "";
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            var pin = state.pins[i];
            var ratio = pin.targetHeight > 0 ? (pin.currentHeight / pin.targetHeight) * 100 : 0;
            var card = document.createElement("div");
            card.className = "pinalign-pin-card state-" + pin.state;
            card.innerHTML = [
                '<div class="pinalign-pin-head">',
                    '<span class="pinalign-pin-id">', escapeHtml(describePinId(pin.id)), "</span>",
                    '<span class="pinalign-pin-state">', escapeHtml(describePinState(pin.state)), "</span>",
                "</div>",
                '<div class="pinalign-pin-bar"><span style="width:', Math.round(ratio), '%"></span></div>',
                '<div class="pinalign-pin-meta">', escapeHtml(describePinLane(state.spec, pin)), " | 高度 ", String(pin.currentHeight), "/", String(pin.targetHeight), "</div>"
            ].join("");
            container.appendChild(card);
        }
    }

    function renderShellSummary(refs, state, viewModel) {
        if (refs.shellSummary) {
            refs.shellSummary.innerHTML = [
                buildShellMetric("种子", state.masterSeed),
                buildShellMetric("警报", String(state.alertRemaining)),
                buildShellMetric("夹具", String(state.clampCharge) + "%"),
                buildShellMetric("状态", describeStatus(state))
            ].join("");
        }

        if (refs.shellGuide) {
            refs.shellGuide.innerHTML = [
                buildShellLine("下一步", describeGuideStep(state, viewModel)),
                buildShellLine("锁针规则", "棋盘竖色带就是影响列；主列强、邻列弱，同一步累计够才推进 1 格。"),
                buildShellLine("当前提示", describeHint(viewModel.hint))
            ].join("");
        }
    }

    function renderShellPins(container, state) {
        if (!container) return;
        container.innerHTML = "";
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            container.insertAdjacentHTML("beforeend", buildShellPin(state.spec, state.pins[i]));
        }
    }

    function renderResolution(container, state, lastResult) {
        if (!container) return;
        container.innerHTML = describeResolution(state, lastResult);
    }

    function renderEvents(container, lastResult) {
        if (!container) return;
        container.innerHTML = "";
        if (!lastResult || !lastResult.events || !lastResult.events.length) {
            container.innerHTML = '<div class="pinalign-event-empty">还没有结算记录。</div>';
            return;
        }
        var recent = lastResult.events.slice(-4);
        var i;
        for (i = 0; i < recent.length; i += 1) {
            var event = recent[i];
            var item = document.createElement("div");
            item.className = "pinalign-event-card";
            item.innerHTML = [
                '<div class="pinalign-event-head">事件 ', String(lastResult.events.length - recent.length + i + 1), "</div>",
                '<div class="pinalign-event-line">Signal ', String(event.signalTiles.length), " | Effect ", String(event.effectTiles.length), "</div>",
                '<div class="pinalign-event-line">生成特殊块：', describeSpecialList(event.generatedSpecials), "</div>",
                '<div class="pinalign-event-line">锁针变化：', describeTransitions(event.pinTransitions), "</div>"
            ].join("");
            container.appendChild(item);
        }
    }

    function renderExport(container, lastReplay) {
        if (!container) return;
        if (!lastReplay) {
            container.textContent = "还没有导出回放。";
            return;
        }
        var text = JSON.stringify(lastReplay, null, 2);
        container.textContent = text.length > 600 ? text.slice(0, 600) + "\n..." : text;
    }

    function renderButtons(refs, viewModel) {
        if (refs.muteButton) refs.muteButton.textContent = viewModel.muted ? "开音" : "静音";
        if (refs.sideToggle) refs.sideToggle.textContent = viewModel.sideCollapsed ? "信息" : "收起信息";
    }

    function renderDebug(refs, state, viewModel, layoutInfo) {
        if (refs.debugWrap) refs.debugWrap.style.display = viewModel.debug ? "" : "none";
        if (!refs.debug || !viewModel.debug) return;
        refs.debug.textContent = [
            "视口 " + layoutInfo.viewportWidth + "x" + layoutInfo.viewportHeight,
            "面板 " + layoutInfo.rootWidth + "x" + layoutInfo.rootHeight,
            "棋盘壳 " + layoutInfo.boardShellWidth + "px",
            "棋盘 " + layoutInfo.boardSize + "px",
            "DPR " + formatNumber(window.devicePixelRatio || 1),
            "布局 " + describeLayout(layoutInfo),
            "状态 " + state.status
        ].join(" | ");
    }

    function setToast(refs, text) {
        if (!refs.toast) return;
        refs.toast.textContent = text || "";
        refs.toast.style.opacity = text ? "1" : "0.55";
    }

    function describeStatus(state) {
        if (state.status === "win") return "全部锁针已锁定";
        if (state.status === "fail") return "校准失败";
        if (state.clampArmed) return "夹具待命";
        if (state.clampActiveThisMove) return "夹具生效中";
        return "等待操作";
    }

    function describeStageStatus(state, lastResult) {
        if (state.status === "win") return "目标完成：全部锁针已经锁定。";
        if (state.status === "fail") return "目标失败：警报耗尽或盘面不可继续。";
        if (lastResult && lastResult.valid && lastResult.productive) return "刚刚的直接匹配已经打进锁针，可以继续观察待锁定和锁定时序。";
        return "目标：用直接三消给锁针送入足够 Signal，让它们依次进入“已锁定”。";
    }

    function describeStageHint(state, hint, layoutInfo) {
        if (state.clampArmed) return "夹具已待命，只会影响下一次合法交换；它不会让连带清除变成锁针信号。";
        if (layoutInfo.sideCollapsed) return "棋盘上的竖色带就是锁针影响范围；两侧卡片会同步显示主列和本手建议。";
        if (!hint) return "当前没有缓存提示，可以先试一次非法交换，确认只有合法直接匹配才会消耗警报。";
        return "先做一次提示交换，观察“本手说明”里 Signal、Effect 和锁针变化是怎么对应起来的。";
    }

    function describeGuideStep(state, viewModel) {
        if (state.status === "win") return "全部锁针已经锁定，现在可以导出回放做复现。";
        if (state.status === "fail") return "本轮校准失败，建议重开后先做一次提示交换。";
        if (state.clampArmed) return "夹具已待命，下一次合法交换会保护本手锁定，但不会把 Effect 变成 Signal。";
        if (viewModel.lastResult && viewModel.lastResult.valid && !viewModel.lastResult.productive) return "刚才形成了匹配，但没有任何锁针累计够阈值；继续找更贴近主列的直接匹配。";
        if (!viewModel.hint) return "当前没有缓存提示，可以先手动试一次非法交换。";
        return "先执行一次提示交换，再看“本手说明”里哪根锁针吃到了这次 Signal。";
    }

    function describeHint(hint) {
        if (!hint) return "操作提示：先点一个格子，再点相邻格交换。";
        return "建议交换：(" + (hint.from.row + 1) + "," + (hint.from.col + 1) + ") -> (" + (hint.to.row + 1) + "," + (hint.to.col + 1) + ")，评分 " + hint.score;
    }

    function describeTransitions(transitions) {
        if (!transitions || !transitions.length) return "无";
        var out = [];
        var i;
        for (i = 0; i < transitions.length; i += 1) {
            out.push(describePinId(transitions[i].pinId) + "：" + describePinState(transitions[i].fromState) + "→" + describePinState(transitions[i].toState));
        }
        return out.join("，");
    }

    function describeSpecialList(items) {
        if (!items || !items.length) return "无";
        var out = [];
        var i;
        for (i = 0; i < items.length; i += 1) out.push(describeSpecialType(items[i].specialType));
        return out.join("，");
    }

    function describeResolution(state, lastResult) {
        if (!lastResult) {
            return [
                buildShellLine("核心规则", "直接匹配格子才算 Signal；主列强、邻列弱，要同一步累计够阈值才抬针。"),
                buildShellLine("再确认", "特殊块和连带清除都是 Effect，只改盘面，不推进锁针。"),
                buildShellLine("推荐起手", "先点“提示”，做一次推荐交换，再对照锁针状态看谁被推进。")
            ].join("");
        }
        if (!lastResult.valid) {
            return [
                buildShellLine("交换结果", "这次交换无效：" + describeSwapReason(lastResult.reason) + "。"),
                buildShellLine("规则提醒", "非法交换不扣警报，也不会产生 Signal。"),
                buildShellLine("下一步", "继续找能形成直接三消的相邻交换。")
            ].join("");
        }

        var totalSignal = 0;
        var totalEffect = 0;
        var transitions = [];
        var generated = [];
        var i;
        for (i = 0; i < lastResult.events.length; i += 1) {
            totalSignal += lastResult.events[i].signalTiles.length;
            totalEffect += lastResult.events[i].effectTiles.length;
            transitions = transitions.concat(lastResult.events[i].pinTransitions || []);
            generated = generated.concat(lastResult.events[i].generatedSpecials || []);
        }

        return [
            buildShellLine("直接信号", "这一步产生了 " + totalSignal + " 个 Signal 格，只有它们会参与锁针累计。"),
            buildShellLine("锁针结果", describeResolutionTransitions(transitions)),
            buildShellLine("盘面波及", totalEffect ? ("还有 " + totalEffect + " 个 Effect 格只清盘，不推进锁针。") : "这一步没有额外的 Effect 波及。"),
            buildShellLine("生成块", generated.length ? ("生成了 " + describeSpecialList(generated) + "。") : "这一步没有生成特殊块。")
        ].join("");
    }

    function describeResolutionTransitions(transitions) {
        if (!transitions || !transitions.length) return "没有任何锁针累计够阈值，所以这次只是清盘，没有推进。";
        var out = [];
        var i;
        for (i = 0; i < transitions.length; i += 1) {
            var transition = transitions[i];
            if (transition.reason === "overshoot") {
                out.push(describePinId(transition.pinId) + " 过调卡死，额外扣 1 点警报");
            } else if (transition.reason === "guarded_overshoot") {
                out.push(describePinId(transition.pinId) + " 本来会过调，但被夹具保护住了");
            } else {
                out.push(describePinId(transition.pinId) + " " + describePinState(transition.fromState) + "→" + describePinState(transition.toState) + "（高度 " + transition.toHeight + "）");
            }
        }
        return out.join("；");
    }

    function describePinLane(spec, pin) {
        var cols = [];
        var col;
        for (col = 0; col < spec.cols; col += 1) {
            if (getLaneWeight(spec, pin, col) > 0) cols.push(col + 1);
        }
        if (!cols.length) return "主列 " + String(pin.centerCol + 1);
        return "影响列 " + cols[0] + "-" + cols[cols.length - 1] + " | 主列 " + String(pin.centerCol + 1);
    }

    function describeSwapReason(reason) {
        if (reason === "non_adjacent") return "只能交换相邻格子";
        if (reason === "out_of_bounds") return "位置越界";
        if (reason === "immovable") return "障碍格不能交换";
        if (reason === "no_match") return "交换后没有形成直接匹配";
        return reason || "未知原因";
    }

    function getLaneWeight(spec, pin, col) {
        if (typeof PinAlignCore !== "undefined" && PinAlignCore && PinAlignCore.laneWeight) {
            return PinAlignCore.laneWeight(spec, pin, col);
        }
        var distance = Math.abs(pin.centerCol - col);
        var raw = 1 - (distance / spec.lane.radius);
        if (raw <= 0) return 0;
        return raw * raw;
    }

    function buildShellMetric(label, value) {
        return [
            '<div class="pinalign-shell-metric">',
                '<div class="pinalign-shell-metric-label">', escapeHtml(label), "</div>",
                '<div class="pinalign-shell-metric-value">', escapeHtml(value), "</div>",
            "</div>"
        ].join("");
    }

    function buildShellLine(label, text) {
        return [
            '<div class="pinalign-shell-line">',
                '<span class="pinalign-shell-line-label">', escapeHtml(label), "：</span>",
                '<span>', escapeHtml(text), "</span>",
            "</div>"
        ].join("");
    }

    function buildShellPin(spec, pin) {
        var ratio = pin.targetHeight > 0 ? (pin.currentHeight / pin.targetHeight) * 100 : 0;
        return [
            '<div class="pinalign-shell-pin state-', escapeHtml(pin.state), '">',
                '<div class="pinalign-shell-pin-head">',
                    '<span>', escapeHtml(describePinId(pin.id)), "</span>",
                    '<b>', escapeHtml(describePinState(pin.state)), "</b>",
                "</div>",
                '<div class="pinalign-shell-pin-bar"><span style="width:', Math.round(ratio), '%"></span></div>',
                '<div class="pinalign-shell-pin-meta">', escapeHtml(describePinLane(spec, pin)), ' | 高度 ', String(pin.currentHeight), '/', String(pin.targetHeight), "</div>",
            "</div>"
        ].join("");
    }

    function buildLaneGuide(spec, pin) {
        var range = getLaneRange(spec, pin);
        var left = percent(range.start, spec.cols);
        var width = percent(range.end - range.start + 1, spec.cols);
        var center = (((pin.centerCol - range.start) + 0.5) / (range.end - range.start + 1)) * 100;
        return [
            '<div class="pinalign-lane-guide state-', escapeHtml(pin.state), '" style="left:', left, '%; width:', width, '%;">',
                '<div class="pinalign-lane-band"></div>',
                '<div class="pinalign-lane-center" style="left:', center.toFixed(3), '%;"></div>',
                '<div class="pinalign-lane-tag" style="left:', center.toFixed(3), '%;">',
                    '<b>', escapeHtml(describePinShort(pin.id)), "</b>",
                    '<span>', escapeHtml(describeRangeShort(range, spec, pin)), "</span>",
                "</div>",
            "</div>"
        ].join("");
    }

    function getLaneRange(spec, pin) {
        var start = pin.centerCol;
        var end = pin.centerCol;
        var col;
        for (col = 0; col < spec.cols; col += 1) {
            if (getLaneWeight(spec, pin, col) > 0) {
                if (col < start) start = col;
                if (col > end) end = col;
            }
        }
        return { start: start, end: end };
    }

    function describeRangeShort(range, spec, pin) {
        var start = range.start + 1;
        var end = range.end + 1;
        var center = pin.centerCol + 1;
        if (start === end) return "主" + center;
        return start + "-" + end + " / 主" + center;
    }

    function describePinShort(id) {
        return String(id || "").replace("pin-", "").replace("-", "").toUpperCase();
    }

    function percent(value, total) {
        return total ? ((value / total) * 100).toFixed(3) : "0";
    }

    function describeLayout(layoutInfo) {
        var layoutWord = layoutInfo.stacked ? "单列" : (layoutInfo.tight ? "紧凑双列" : "宽屏双列");
        return layoutWord + (layoutInfo.sideCollapsed ? " / 信息收起" : " / 信息展开");
    }

    function shortSpecial(type) {
        if (type === "shimH") return "横垫";
        if (type === "shimV") return "纵垫";
        if (type === "brace") return "卡箍";
        if (type === "calibrator") return "校准";
        return "特殊";
    }

    function describeObstacle(type) {
        if (type === "debris") return "碎屑";
        if (type === "clip") return "卡扣";
        return type;
    }

    function describePinState(state) {
        if (state === "normal") return "正常";
        if (state === "set") return "待锁定";
        if (state === "jammed") return "卡死";
        if (state === "locked") return "已锁定";
        return state;
    }

    function describePinId(id) {
        return "锁针" + String(id || "").replace("pin-", "").replace("-", "").toUpperCase();
    }

    function describeSpecialType(type) {
        if (type === "shimH") return "横向垫片";
        if (type === "shimV") return "纵向垫片";
        if (type === "brace") return "卡箍";
        if (type === "calibrator") return "校准器";
        return type;
    }

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function formatNumber(value) {
        return Math.round(value * 100) / 100;
    }

    function measureBlockHeight(el) {
        if (!el || !el.getBoundingClientRect) return 0;
        return Math.ceil(el.getBoundingClientRect().height || 0);
    }

    function escapeHtml(text) {
        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    return {
        indexRefs: indexRefs,
        sync: sync,
        setToast: setToast
    };
});
