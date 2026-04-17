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
            boardArea: root.querySelector(".pinalign-board-area"),
            laneBelt: root.querySelector("[data-pa-lane-belt]"),
            flightLayer: root.querySelector("[data-pa-flight-layer]"),
            previewLayer: root.querySelector("[data-pa-preview-layer]"),
            phaseBadge: root.querySelector("[data-pa-phase]"),
            seed: root.querySelector("[data-pa-seed]"),
            alert: root.querySelector("[data-pa-alert]"),
            clamp: root.querySelector("[data-pa-clamp]"),
            moves: root.querySelector("[data-pa-moves]"),
            stageNote: root.querySelector("[data-pa-stage-note]"),
            pins: root.querySelector("[data-pa-pins]"),
            events: root.querySelector("[data-pa-events]"),
            eventsToggle: root.querySelector("[data-pa-events-toggle]"),
            eventsBody: root.querySelector("[data-pa-events-body]"),
            export: root.querySelector("[data-pa-export]"),
            exportToggle: root.querySelector("[data-pa-export-toggle]"),
            exportBody: root.querySelector("[data-pa-export-body]"),
            debug: root.querySelector("[data-pa-debug]"),
            debugWrap: root.querySelector("[data-pa-debug-wrap]"),
            muteButton: root.querySelector('[data-action="mute"]')
        };
    }

    var PIN_COLORS = ["#4ed7ff", "#fcd34d", "#c084fc", "#f472b6", "#34d399"];

    function pinColor(index) {
        return PIN_COLORS[index % PIN_COLORS.length];
    }

    function sync(refs, state, viewModel) {
        var layoutInfo = fitBoard(refs);
        renderBoard(refs.board, state, viewModel);
        renderLaneBelt(refs.laneBelt, state);
        renderHud(refs, state);
        renderPins(refs.pins, state, viewModel);
        renderEvents(refs.events, viewModel.lastResult);
        renderExport(refs.export, viewModel.lastReplay);
        renderCollapsible(refs, viewModel);
        renderDebug(refs, state, viewModel, layoutInfo);
        renderPreview(refs, state, viewModel);
        renderFlight(refs, viewModel);
        setStageNote(refs, viewModel.toast || "");
    }

    function renderFlight(refs, viewModel) {
        if (!refs.flightLayer) return;
        refs.flightLayer.innerHTML = "";
        var result = viewModel.lastResult;
        if (!result || !result.valid || !result.events || !result.events.length) return;
        if (viewModel.flightToken === refs.flightLayer.dataset.token) return;
        refs.flightLayer.dataset.token = viewModel.flightToken || String(Date.now());
        var frag = "";
        var e;
        var s;
        for (e = 0; e < result.events.length; e += 1) {
            var event = result.events[e];
            for (s = 0; s < event.signalTiles.length; s += 1) {
                frag += buildFlightCell(event.signalTiles[s], "is-signal", e * 40);
            }
            for (s = 0; s < event.effectTiles.length; s += 1) {
                frag += buildFlightCell(event.effectTiles[s], "is-effect", e * 40 + 80);
            }
        }
        refs.flightLayer.innerHTML = frag;
    }

    function buildFlightCell(tile, modifier, delayMs) {
        if (!tile) return "";
        return [
            '<div class="pinalign-flight-cell ', modifier,
            '" style="grid-column:', (tile.col + 1),
            '; grid-row:', (tile.row + 1),
            '; animation-delay:', (delayMs || 0), 'ms;"></div>'
        ].join("");
    }

    function renderLaneBelt(container, state) {
        if (!container) return;
        var cols = state.spec.cols;
        var html = "";
        var c;
        var p;
        for (c = 0; c < cols; c += 1) {
            html += '<div class="pinalign-belt-col" data-col="' + c + '">';
            for (p = 0; p < state.pins.length; p += 1) {
                var pin = state.pins[p];
                var w = getLaneWeight(state.spec, pin, c);
                if (w > 0) {
                    var classes = ["pinalign-belt-cell", "state-" + pin.state];
                    var style;
                    var tip = describePinId(pin.id) + " 权重 " + w.toFixed(2) + "（列 " + (c + 1) + "）";
                    if (pin.state === "locked") {
                        classes.push("is-sealed");
                        style = "";
                        tip += " · 已锁定，此列为保险区";
                    } else {
                        var alpha = Math.max(0.14, Math.min(1, w));
                        style = "background:" + pinColor(p) + "; opacity:" + alpha.toFixed(2) + ";";
                    }
                    html += [
                        '<div class="', classes.join(" "),
                        '" style="', style,
                        '" title="', escapeHtml(tip),
                        '"></div>'
                    ].join("");
                } else {
                    html += '<div class="pinalign-belt-cell is-empty"></div>';
                }
            }
            html += "</div>";
        }
        container.innerHTML = html;
    }

    function renderPreview(refs, state, viewModel) {
        if (!refs.previewLayer) return;
        refs.previewLayer.innerHTML = "";
        if (!viewModel.selected || state.status !== "ongoing") return;
        if (typeof PinAlignCore === "undefined" || !PinAlignCore.previewSwap) return;
        var sel = viewModel.selected;
        var deltas = [[-1, 0], [1, 0], [0, -1], [0, 1]];
        var i;
        var frag = "";
        for (i = 0; i < deltas.length; i += 1) {
            var r = sel.row + deltas[i][0];
            var c = sel.col + deltas[i][1];
            if (r < 0 || c < 0 || r >= state.spec.rows || c >= state.spec.cols) continue;
            var preview = PinAlignCore.previewSwap(state, sel, { row: r, col: c });
            frag += buildPreviewMarker(state, r, c, preview);
        }
        refs.previewLayer.innerHTML = frag;
    }

    function buildPreviewMarker(state, row, col, preview) {
        var modifier = "is-valid";
        var badge = "";
        var note = "";
        if (!preview.valid) {
            modifier = "is-invalid";
            badge = "✕";
        } else if (preview.wouldOvershoot) {
            modifier = "is-warn";
            badge = "⚠";
            note = describeOvershootWarning(state, preview);
        } else if (preview.wouldAdvance) {
            modifier = "is-advance";
            badge = "+" + preview.signalTiles.length;
        } else {
            modifier = "is-neutral";
            badge = "~" + preview.signalTiles.length;
        }
        var noteHtml = note
            ? '<span class="pinalign-preview-note">' + escapeHtml(note) + "</span>"
            : "";
        return [
            '<div class="pinalign-preview-cell ', modifier,
            '" style="grid-column:', (col + 1),
            '; grid-row:', (row + 1), ';">',
                '<span class="pinalign-preview-badge">', escapeHtml(badge), "</span>",
                noteHtml,
            "</div>"
        ].join("");
    }

    function describeOvershootWarning(state, preview) {
        if (!preview || !preview.pinContributions) return "过调";
        var i;
        var risky = [];
        for (i = 0; i < preview.pinContributions.length; i += 1) {
            var c = preview.pinContributions[i];
            if (c.wouldOvershoot) risky.push(describePinShort(c.pinId));
        }
        if (!risky.length) return "过调：−1 警报 + 卡死到下一手";
        return risky.join("/") + " 已待锁，过调 −1 警报";
    }

    function describePinShort(id) {
        return String(id || "").replace("pin-", "").replace("-", "").toUpperCase();
    }

    function fitBoard(refs) {
        var rootWidth = refs.root ? Math.max(refs.root.clientWidth || 0, 0) : 0;
        var rootHeight = refs.root ? Math.max(refs.root.clientHeight || 0, 0) : 0;
        var viewportWidth = window.innerWidth || rootWidth || 1280;
        var viewportHeight = window.innerHeight || rootHeight || 800;
        if (!rootWidth) rootWidth = viewportWidth;
        if (!rootHeight) rootHeight = viewportHeight;

        var stacked = rootWidth < 920;
        if (refs.root) {
            refs.root.classList.toggle("is-stacked", stacked);
            refs.root.setAttribute("data-layout", stacked ? "stacked" : "wide");
        }

        if (!refs.board || !refs.boardShell) {
            return {
                rootWidth: rootWidth,
                rootHeight: rootHeight,
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight,
                boardShellWidth: 0,
                boardSize: 0,
                stacked: stacked
            };
        }

        var shellWidth = Math.max(0, refs.boardShell.clientWidth - 16);
        var beltReserve = 30;
        var shellHeight = Math.max(0, refs.boardShell.clientHeight - 16 - beltReserve);
        var fallbackHeight = Math.floor(rootHeight * (stacked ? 0.52 : 0.68));
        var heightBudget = shellHeight > 220 ? shellHeight : fallbackHeight;
        var size = Math.floor(Math.min(shellWidth, heightBudget, 560));
        if (size < 260) size = Math.min(shellWidth, 260);
        size = clamp(size, 260, 560);

        refs.root.style.setProperty("--pa-board-size", size + "px");
        refs.root.style.setProperty("--pa-board-gap", size < 320 ? "6px" : (size < 430 ? "8px" : "10px"));
        refs.board.style.width = size + "px";
        refs.board.style.height = size + "px";

        return {
            rootWidth: rootWidth,
            rootHeight: rootHeight,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            boardShellWidth: shellWidth,
            boardSize: size,
            stacked: stacked
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

    function renderHud(refs, state) {
        if (refs.seed) refs.seed.textContent = state.masterSeed;
        if (refs.alert) refs.alert.textContent = String(state.alertRemaining);
        if (refs.clamp) refs.clamp.textContent = String(state.clampCharge) + "%";
        if (refs.moves) refs.moves.textContent = String(state.moveIndex || 0);
    }

    function renderPins(container, state, viewModel) {
        if (!container) return;
        var structuralToken = computePinStructuralToken(state, viewModel);
        if (container.dataset.pinToken === structuralToken) {
            refreshPinAccumulators(container, state, viewModel);
            return;
        }
        container.dataset.pinToken = structuralToken;
        container.innerHTML = "";
        var preview = bestPreviewForSelection(state, viewModel);
        var overshootIds = collectOvershootPinIds(viewModel.lastResult);
        var lockedIds = (viewModel.lastResult && viewModel.lastResult.committedLocks) || [];
        var unjammedIds = state.lastMoveUnjammed || [];
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            var pin = state.pins[i];
            var ratio = pin.targetHeight > 0 ? (pin.currentHeight / pin.targetHeight) * 100 : 0;
            var card = document.createElement("div");
            var cardClasses = ["pinalign-pin-card", "state-" + pin.state];
            if (overshootIds.indexOf(pin.id) !== -1) cardClasses.push("just-overshoot");
            if (lockedIds.indexOf(pin.id) !== -1) cardClasses.push("just-locked");
            if (unjammedIds.indexOf(pin.id) !== -1) cardClasses.push("just-unjammed");
            card.className = cardClasses.join(" ");
            card.style.borderLeft = "3px solid " + pinColor(i);
            var contrib = preview ? findPinContribution(preview, pin.id) : null;
            var lockStampHtml = pin.state === "locked"
                ? '<span class="pinalign-pin-stamp">已锁定</span>'
                : "";
            card.innerHTML = [
                '<div class="pinalign-pin-head">',
                    '<span class="pinalign-pin-id" style="color:', pinColor(i), ';">', escapeHtml(describePinId(pin.id)), "</span>",
                    '<span class="pinalign-pin-state">', escapeHtml(describePinState(pin.state)), "</span>",
                "</div>",
                '<div class="pinalign-pin-bar"><span style="width:', Math.round(ratio), '%; background:', pinColor(i), ';"></span></div>',
                '<div class="pinalign-pin-meta">', escapeHtml(describePinLane(state.spec, pin)), " | 高度 ", String(pin.currentHeight), "/", String(pin.targetHeight), "</div>",
                '<div class="pinalign-pin-accum-slot">', buildPinAccumulator(state.spec, pin, contrib), "</div>",
                lockStampHtml
            ].join("");
            container.appendChild(card);
        }
    }

    function computePinStructuralToken(state, viewModel) {
        var parts = [state.moveIndex];
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            parts.push(state.pins[i].state + ":" + state.pins[i].currentHeight);
        }
        parts.push(viewModel.flightToken || "0");
        parts.push((state.lastMoveUnjammed || []).join("/"));
        return parts.join("|");
    }

    function refreshPinAccumulators(container, state, viewModel) {
        var preview = bestPreviewForSelection(state, viewModel);
        var cards = container.querySelectorAll(".pinalign-pin-card");
        var i;
        for (i = 0; i < cards.length && i < state.pins.length; i += 1) {
            var slot = cards[i].querySelector(".pinalign-pin-accum-slot");
            if (!slot) continue;
            var contrib = preview ? findPinContribution(preview, state.pins[i].id) : null;
            slot.innerHTML = buildPinAccumulator(state.spec, state.pins[i], contrib);
        }
    }

    function collectOvershootPinIds(result) {
        var out = [];
        if (!result || !result.events) return out;
        var e;
        var t;
        for (e = 0; e < result.events.length; e += 1) {
            var trs = result.events[e].pinTransitions || [];
            for (t = 0; t < trs.length; t += 1) {
                if (trs[t].reason === "overshoot") {
                    if (out.indexOf(trs[t].pinId) === -1) out.push(trs[t].pinId);
                }
            }
        }
        return out;
    }

    function buildPinAccumulator(spec, pin, contrib) {
        var threshold = spec.lane.threshold;
        var step = 0.5;
        var dots = Math.max(3, Math.ceil(threshold / step));
        var weight = contrib ? contrib.weight : 0;
        var filled = Math.min(dots, Math.round(weight / step));
        var cls = "pinalign-pin-accum";
        var label = contrib ? ("预览贡献 " + weight.toFixed(2) + " / " + threshold.toFixed(2)) : "本手尚无信号";
        var tone = "";
        if (contrib && contrib.wouldOvershoot) { cls += " is-warn"; tone = "（过调风险）"; }
        else if (contrib && contrib.guardedByClamp) { cls += " is-guarded"; tone = "（夹具保护）"; }
        else if (contrib && contrib.wouldAdvance) { cls += " is-advance"; tone = "（将抬 1 格）"; }
        var out = ['<div class="', cls, '">'];
        out.push('<div class="pinalign-pin-accum-label">', escapeHtml(label + tone), "</div>");
        out.push('<div class="pinalign-pin-accum-dots">');
        var d;
        for (d = 0; d < dots; d += 1) {
            var state = d < filled ? "on" : "off";
            out.push('<span class="pa-dot pa-dot-', state, '"></span>');
        }
        out.push("</div></div>");
        return out.join("");
    }

    function findPinContribution(preview, pinId) {
        if (!preview || !preview.pinContributions) return null;
        var i;
        for (i = 0; i < preview.pinContributions.length; i += 1) {
            if (preview.pinContributions[i].pinId === pinId) return preview.pinContributions[i];
        }
        return null;
    }

    function bestPreviewForSelection(state, viewModel) {
        if (!viewModel || !viewModel.selected) return null;
        if (state.status !== "ongoing") return null;
        if (typeof PinAlignCore === "undefined" || !PinAlignCore.previewSwap) return null;
        var sel = viewModel.selected;
        var deltas = [[-1, 0], [1, 0], [0, -1], [0, 1]];
        var best = null;
        var i;
        for (i = 0; i < deltas.length; i += 1) {
            var r = sel.row + deltas[i][0];
            var c = sel.col + deltas[i][1];
            if (r < 0 || c < 0 || r >= state.spec.rows || c >= state.spec.cols) continue;
            var p = PinAlignCore.previewSwap(state, sel, { row: r, col: c });
            if (!p.valid) continue;
            if (!best) { best = p; continue; }
            if (scorePreview(p) > scorePreview(best)) best = p;
        }
        return best;
    }

    function scorePreview(p) {
        var s = 0;
        if (p.wouldAdvance) s += 10;
        if (p.wouldOvershoot) s -= 5;
        s += p.signalTiles.length;
        return s;
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

    function renderCollapsible(refs, viewModel) {
        if (refs.eventsBody) {
            refs.eventsBody.hidden = !viewModel.eventsExpanded;
        }
        if (refs.eventsToggle) {
            refs.eventsToggle.textContent = "最近结算 " + (viewModel.eventsExpanded ? "▾" : "▸");
            refs.eventsToggle.classList.toggle("is-open", !!viewModel.eventsExpanded);
        }
        if (refs.exportBody) {
            refs.exportBody.hidden = !viewModel.exportExpanded;
        }
        if (refs.exportToggle) {
            refs.exportToggle.textContent = "回放导出 " + (viewModel.exportExpanded ? "▾" : "▸");
            refs.exportToggle.classList.toggle("is-open", !!viewModel.exportExpanded);
        }
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
            "布局 " + (layoutInfo.stacked ? "单列" : "双列"),
            "状态 " + state.status,
            "手数 " + state.moveIndex,
            "有效/合法 " + state.telemetry.productiveSwaps + "/" + state.telemetry.legalSwaps,
            "卡针 " + state.telemetry.jamCount
        ].join(" | ");
    }

    function setStageNote(refs, text) {
        if (!refs.stageNote) return;
        refs.stageNote.textContent = text || "";
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

    function describePinLane(spec, pin) {
        var cols = [];
        var col;
        for (col = 0; col < spec.cols; col += 1) {
            if (getLaneWeight(spec, pin, col) > 0) cols.push(col + 1);
        }
        if (!cols.length) return "主列 " + String(pin.centerCol + 1);
        return "影响列 " + cols[0] + "-" + cols[cols.length - 1] + " | 主列 " + String(pin.centerCol + 1);
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

    function escapeHtml(text) {
        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    return {
        indexRefs: indexRefs,
        sync: sync,
        setStageNote: setStageNote
    };
});
