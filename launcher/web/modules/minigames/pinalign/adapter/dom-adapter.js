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
            laneLayer: root.querySelector("[data-pa-lane-layer]"),
            instrumentStrip: root.querySelector("[data-pa-instrument-strip]"),
            flightLayer: root.querySelector("[data-pa-flight-layer]"),
            previewLayer: root.querySelector("[data-pa-preview-layer]"),
            phaseBadge: root.querySelector("[data-pa-phase]"),
            seed: root.querySelector("[data-pa-seed]"),
            alert: root.querySelector("[data-pa-alert]"),
            clamp: root.querySelector("[data-pa-clamp]"),
            moves: root.querySelector("[data-pa-moves]"),
            stageNote: root.querySelector("[data-pa-stage-note]"),
            pinsAria: root.querySelector("[data-pa-pins-aria]"),
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
        renderLaneOverlay(refs.laneLayer, state, viewModel);
        renderHud(refs, state);
        renderProbes(refs.instrumentStrip, state, viewModel);
        renderPinsAria(refs.pinsAria, state);
        renderEvents(refs.events, viewModel.lastResult);
        renderExport(refs.export, viewModel.lastReplay);
        renderCollapsible(refs, viewModel);
        renderDebug(refs, state, viewModel, layoutInfo);
        renderPreview(refs, state, viewModel);
        renderFlight(refs, viewModel);
        setStageNote(refs, viewModel.toast || "");
    }

    var FLIGHT_EVENT_STAGGER = 240;
    var FLIGHT_EFFECT_DELAY = 180;

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
            var base = e * FLIGHT_EVENT_STAGGER;
            var hasEffect = event.effectTiles && event.effectTiles.length > 0;
            for (s = 0; s < event.signalTiles.length; s += 1) {
                frag += buildFlightCell(event.signalTiles[s], "is-signal", base);
            }
            if (hasEffect) {
                for (s = 0; s < event.effectTiles.length; s += 1) {
                    frag += buildFlightCell(event.effectTiles[s], "is-effect", base + FLIGHT_EFFECT_DELAY);
                }
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

    function renderLaneOverlay(container, state, viewModel) {
        if (!container) return;
        var cols = state.spec.cols;
        var preview = previewForHoveredCandidate(state, viewModel);
        var tier = computeLaneTier(state, viewModel, preview);
        var contribById = {};
        if (preview) {
            var k;
            for (k = 0; k < preview.pinContributions.length; k += 1) {
                contribById[preview.pinContributions[k].pinId] = preview.pinContributions[k];
            }
        }
        var html = "";
        var c;
        for (c = 0; c < cols; c += 1) {
            var owner = pickLaneOwner(state, c);
            if (!owner) {
                html += '<div class="pinalign-lane-col" data-col="' + c + '"></div>';
                continue;
            }
            var pin = owner.pin;
            var pinIndex = owner.pinIndex;
            var role = owner.distance === 0 ? "main" : "neighbor";
            var highlight = computeLaneHighlight(tier, viewModel, preview, contribById[pin.id], pin, c, state.spec);
            var color = pinColor(pinIndex);
            html += [
                '<div class="pinalign-lane-col is-', role,
                ' highlight-', highlight,
                ' state-', pin.state,
                '" data-col="', c,
                '" data-pin="', escapeHtml(pin.id),
                '" style="--pa-lane-color:', color, ';">',
                '<i class="pinalign-lane-line"></i>',
                '</div>'
            ].join("");
        }
        container.innerHTML = html;
    }

    function pickLaneOwner(state, col) {
        var best = null;
        var p;
        for (p = 0; p < state.pins.length; p += 1) {
            var pin = state.pins[p];
            var w = getLaneWeight(state.spec, pin, col);
            if (w <= 0) continue;
            var distance = Math.abs(pin.centerCol - col);
            if (!best || w > best.weight || (w === best.weight && distance < best.distance)) {
                best = { pin: pin, pinIndex: p, weight: w, distance: distance };
            }
        }
        return best;
    }

    function computeLaneTier(state, viewModel, preview) {
        if (preview && preview.valid) return "hovered";
        if (viewModel && viewModel.selected && state.status === "ongoing") return "selected";
        return "default";
    }

    function computeLaneHighlight(tier, viewModel, preview, contrib, pin, col, spec) {
        if (pin.state === "locked") return "locked";
        if (pin.state === "jammed") return "jammed";
        if (tier === "hovered" && preview) {
            if (contrib && contrib.weight > 0) {
                if (contrib.wouldOvershoot) return "overshoot";
                if (contrib.guardedByClamp) return "guarded";
                if (contrib.wouldAdvance) return "advance";
                return "neutral";
            }
            return "default";
        }
        if (tier === "selected" && viewModel && viewModel.selected) {
            if (getLaneWeight(spec, pin, viewModel.selected.col) > 0) return "selected";
            return "default";
        }
        return "default";
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
            frag += buildPreviewMarker(state, r, c, preview, viewModel.hoveredCandidate);
        }
        refs.previewLayer.innerHTML = frag;
    }

    function buildPreviewMarker(state, row, col, preview, hovered) {
        var summary = summarizePreview(preview);
        var hoveredCls = (hovered && hovered.row === row && hovered.col === col) ? " is-hovered" : "";
        return [
            '<div class="pinalign-preview-cell ', summary.modifier, hoveredCls,
            '" data-row="', row, '" data-col="', col,
            '" style="grid-column:', (col + 1),
            '; grid-row:', (row + 1), ';">',
                '<span class="pinalign-preview-badge">', escapeHtml(summary.badge), "</span>",
                '<span class="pinalign-preview-note">', escapeHtml(summary.detail), "</span>",
            "</div>"
        ].join("");
    }

    function summarizePreview(preview) {
        if (!preview) return { modifier: "is-invalid", badge: "不能交换", detail: "当前没有候选" };
        if (!preview.valid) {
            return { modifier: "is-invalid", badge: "不能交换", detail: describeRejectReason(preview.reason) };
        }
        var advancers = [];
        var overshooters = [];
        var guarded = [];
        var i;
        for (i = 0; i < preview.pinContributions.length; i += 1) {
            var c = preview.pinContributions[i];
            var short = describePinShort(c.pinId);
            if (c.wouldOvershoot) overshooters.push(short);
            else if (c.wouldAdvance) advancers.push(short);
            else if (c.guardedByClamp) guarded.push(short);
        }
        var parts = [];
        if (overshooters.length) parts.push(overshooters.join("") + "⚠");
        if (advancers.length) parts.push(advancers.join("") + "↑");
        if (guarded.length) parts.push(guarded.join("") + "⛨");
        var modifier;
        var badge;
        var detail;
        if (overshooters.length) {
            modifier = "is-warn";
            badge = parts.join(" ");
            detail = describeOvershootDetail(preview) + ((advancers.length || guarded.length) ? "；" + describeAdvanceDetail(preview, true) : "");
        } else if (advancers.length) {
            modifier = "is-advance";
            badge = parts.join(" ");
            detail = describeAdvanceDetail(preview, false);
        } else if (guarded.length) {
            modifier = "is-guarded";
            badge = parts.join(" ");
            detail = describeGuardedDetail(preview);
        } else {
            modifier = "is-neutral";
            badge = "无推进";
            detail = "形成匹配，但未达到任何锁针阈值，仅清盘不抬针。";
        }
        return { modifier: modifier, badge: badge, detail: detail };
    }

    function describeOvershootDetail(preview) {
        var victims = [];
        var i;
        for (i = 0; i < preview.pinContributions.length; i += 1) {
            if (preview.pinContributions[i].wouldOvershoot) {
                victims.push(describePinId(preview.pinContributions[i].pinId));
            }
        }
        return victims.join("/") + " 已待锁，这步过调 −1 警报 + 卡死到下一手";
    }

    function describeGuardedDetail(preview) {
        var guarded = [];
        var i;
        for (i = 0; i < preview.pinContributions.length; i += 1) {
            if (preview.pinContributions[i].guardedByClamp) {
                guarded.push(describePinId(preview.pinContributions[i].pinId));
            }
        }
        return guarded.join("/") + " 本会过调，夹具保护；本手结束时 set→locked";
    }

    function describeAdvanceDetail(preview, asSuffix) {
        var rows = [];
        var i;
        for (i = 0; i < preview.pinContributions.length; i += 1) {
            var c = preview.pinContributions[i];
            if (c.wouldAdvance) {
                rows.push(describePinId(c.pinId) + " 抬升 +1（信号 " + formatScore(c.weight) + "/阈值 " + formatScore(preview.threshold) + "）");
            } else if (c.guardedByClamp && !asSuffix) {
                rows.push(describePinId(c.pinId) + " 夹具保护（仍耗 −1 警报）");
            }
        }
        if (!rows.length) return "这步不推进任何锁针";
        return rows.join("；");
    }

    function describeRejectReason(reason) {
        if (reason === "non_adjacent") return "只能交换相邻格";
        if (reason === "out_of_bounds") return "位置越界";
        if (reason === "immovable") return "障碍格不能交换";
        if (reason === "no_match") return "交换后没有形成直接匹配";
        if (reason === "status") return "当前不是可操作状态";
        return reason || "未知原因";
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

        var instrumentReserve = 86;
        var shellWidth = Math.max(0, refs.boardShell.clientWidth - 16);
        var shellHeight = Math.max(0, refs.boardShell.clientHeight - 16 - instrumentReserve);
        var fallbackHeight = Math.floor(rootHeight * (stacked ? 0.48 : 0.62));
        var heightBudget = shellHeight > 220 ? shellHeight : fallbackHeight;
        var size = Math.floor(Math.min(shellWidth, heightBudget, 520));
        if (size < 260) size = Math.min(shellWidth, 260);
        size = clamp(size, 260, 520);

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
                    btn.addEventListener("click", bindTileCallback(viewModel.onTileClick, row, col));
                }
                if (viewModel.onTileHover) {
                    btn.addEventListener("mouseenter", bindTileCallback(viewModel.onTileHover, row, col));
                    btn.addEventListener("focus", bindTileCallback(viewModel.onTileHover, row, col));
                }
                if (viewModel.onTileLeave) {
                    btn.addEventListener("mouseleave", bindTileCallback(viewModel.onTileLeave, row, col));
                    btn.addEventListener("blur", bindTileCallback(viewModel.onTileLeave, row, col));
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

    function bindTileCallback(handler, row, col) {
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

    function renderProbes(container, state, viewModel) {
        if (!container) return;
        var overshootIds = collectTransitionIds(viewModel.lastResult, "overshoot");
        var guardedHitIds = collectTransitionIds(viewModel.lastResult, "guarded_overshoot");
        var advancedIds = collectTransitionIds(viewModel.lastResult, "signal");
        var lockedIds = (viewModel.lastResult && viewModel.lastResult.committedLocks) || [];
        var unjammedIds = state.lastMoveUnjammed || [];
        var preview = previewForHoveredCandidate(state, viewModel);
        var contribById = {};
        var guardedPreviewIds = [];
        var advancePreviewIds = [];
        var overshootPreviewIds = [];
        if (preview && preview.valid) {
            var k;
            for (k = 0; k < preview.pinContributions.length; k += 1) {
                var c = preview.pinContributions[k];
                contribById[c.pinId] = c;
                if (c.guardedByClamp) guardedPreviewIds.push(c.pinId);
                else if (c.wouldOvershoot) overshootPreviewIds.push(c.pinId);
                else if (c.wouldAdvance) advancePreviewIds.push(c.pinId);
            }
        }
        var activeCols = collectActiveCols(viewModel);
        var threshold = state.spec.lane.threshold;
        var token = computeProbeToken(state, viewModel, guardedPreviewIds, advancePreviewIds, overshootPreviewIds, activeCols);
        if (container.dataset.probeToken === token) return;
        container.dataset.probeToken = token;
        container.style.gridTemplateRows = "auto" + new Array(state.pins.length + 1).join(" 11px");
        var cols = state.spec.cols;
        var frag = "";
        var p;
        for (p = 0; p < state.pins.length; p += 1) {
            var pin = state.pins[p];
            var centerCol = Math.max(0, Math.min(cols - 1, pin.centerCol || 0));
            var currentPct = pin.targetHeight > 0
                ? Math.max(0, Math.min(100, (pin.currentHeight / pin.targetHeight) * 100))
                : 0;
            var contrib = contribById[pin.id] || null;
            var ghostPct = computeGhostPct(pin, contrib);
            var showGhost = contrib && contrib.weight > 0 && pin.state !== "locked" && pin.state !== "jammed";
            var classes = ["pinalign-probe", "state-" + pin.state];
            if (overshootIds.indexOf(pin.id) !== -1) classes.push("just-overshoot");
            if (lockedIds.indexOf(pin.id) !== -1) classes.push("just-locked");
            if (unjammedIds.indexOf(pin.id) !== -1) classes.push("just-unjammed");
            if (advancedIds.indexOf(pin.id) !== -1) classes.push("just-advanced");
            if (guardedHitIds.indexOf(pin.id) !== -1) classes.push("just-guarded");
            if (guardedPreviewIds.indexOf(pin.id) !== -1) classes.push("is-guarded-preview");
            if (advancePreviewIds.indexOf(pin.id) !== -1) classes.push("is-advance-preview");
            if (overshootPreviewIds.indexOf(pin.id) !== -1) classes.push("is-overshoot-preview");
            if (showGhost) classes.push("has-ghost");
            var color = pinColor(p);
            var idLabel = describePinId(pin.id);
            var shortLabel = describePinShort(pin.id);
            var readout = String(pin.currentHeight) + "/" + String(pin.targetHeight);
            var stateTag = describePinState(pin.state);
            var title = idLabel + "：主列 " + (centerCol + 1)
                + "，高度 " + readout + "，" + stateTag;
            var pred = buildPredChip(pin, contrib, shortLabel, threshold);
            frag += [
                '<div class="', classes.join(" "),
                '" style="grid-column:', (centerCol + 1),
                '; grid-row: 1',
                '; --pa-probe-color:', color, ';"',
                ' data-pin="', escapeHtml(pin.id), '"',
                ' title="', escapeHtml(title), '"',
                ' aria-label="', escapeHtml(title), '">',
                    '<div class="pinalign-probe-rail">',
                        '<i class="pinalign-probe-tick tick-base" aria-hidden="true"></i>',
                        '<i class="pinalign-probe-tick tick-mid" aria-hidden="true"></i>',
                        '<i class="pinalign-probe-tick tick-target" aria-hidden="true"></i>',
                        (showGhost ? '<i class="pinalign-probe-marker is-ghost" style="bottom:' + ghostPct.toFixed(1) + '%;" aria-hidden="true"></i>' : ''),
                        '<i class="pinalign-probe-marker" style="bottom:', currentPct.toFixed(1), '%;" aria-hidden="true"></i>',
                    '</div>',
                    '<div class="pinalign-probe-info" aria-hidden="true">',
                        '<span class="pinalign-probe-title">', escapeHtml(shortLabel), '</span>',
                        '<span class="pinalign-probe-lamp"></span>',
                        '<span class="pinalign-probe-readout">', escapeHtml(readout), '</span>',
                    '</div>',
                    (pred ? '<span class="pinalign-probe-pred ' + pred.modifier + '" aria-hidden="true">' + escapeHtml(pred.text) + '</span>' : ''),
                    '<span class="pinalign-probe-clamp" aria-hidden="true">⛨</span>',
                    '<span class="pinalign-probe-stamp" aria-hidden="true">锁</span>',
                '</div>'
            ].join("");
        }
        for (p = 0; p < state.pins.length; p += 1) {
            frag += buildCoverageRow(state.spec, state.pins[p], p, activeCols, 2 + p);
        }
        container.innerHTML = frag;
    }

    function computeGhostPct(pin, contrib) {
        if (!contrib || pin.targetHeight <= 0) return 0;
        var height = pin.currentHeight;
        if (contrib.wouldAdvance) height = pin.currentHeight + 1;
        else if (contrib.wouldOvershoot) height = Math.max(0, pin.targetHeight - 1);
        return Math.max(0, Math.min(100, (height / pin.targetHeight) * 100));
    }

    function buildPredChip(pin, contrib, shortLabel, threshold) {
        if (!contrib || contrib.weight <= 0) return null;
        if (pin.state === "locked" || pin.state === "jammed") return null;
        if (contrib.wouldOvershoot) {
            return { modifier: "is-warn", text: shortLabel + "⚠" };
        }
        if (contrib.guardedByClamp) {
            return { modifier: "is-guarded", text: shortLabel + "⛨" };
        }
        if (contrib.wouldAdvance) {
            return { modifier: "is-advance", text: shortLabel + "↑" };
        }
        return { modifier: "is-neutral", text: "+" + formatScore(contrib.weight) + "/" + formatScore(threshold) };
    }

    function formatScore(value) {
        if (value == null) return "0";
        if (Math.abs(value - Math.round(value)) < 0.05) return String(Math.round(value));
        return value.toFixed(1);
    }

    function buildCoverageRow(spec, pin, pinIndex, activeCols, rowIndex) {
        var color = pinColor(pinIndex);
        var out = [
            '<div class="pinalign-probe-coverage state-', pin.state,
            '" style="grid-column: 1 / -1; grid-row:', rowIndex,
            '; --pa-probe-color:', color, ';"',
            ' data-pin="', escapeHtml(pin.id), '"',
            ' aria-hidden="true">'
        ];
        var c;
        for (c = 0; c < spec.cols; c += 1) {
            var weight = getLaneWeight(spec, pin, c);
            var cellClass = "pinalign-coverage-cell";
            if (weight >= 2) cellClass += " tier-main";
            else if (weight >= 1) cellClass += " tier-neighbor";
            else cellClass += " tier-empty";
            if (activeCols.indexOf(c) !== -1 && weight > 0) cellClass += " is-active";
            out.push('<div class="', cellClass, '" data-col="', c, '"></div>');
        }
        out.push('</div>');
        return out.join("");
    }

    function collectActiveCols(viewModel) {
        var cols = [];
        if (viewModel) {
            if (viewModel.selected) cols.push(viewModel.selected.col);
            if (viewModel.hoveredCandidate && cols.indexOf(viewModel.hoveredCandidate.col) === -1) {
                cols.push(viewModel.hoveredCandidate.col);
            }
        }
        return cols;
    }

    function computeProbeToken(state, viewModel, guardedPreviewIds, advancePreviewIds, overshootPreviewIds, activeCols) {
        var parts = [state.moveIndex];
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            parts.push(state.pins[i].state + ":" + state.pins[i].currentHeight);
        }
        parts.push(viewModel.flightToken || "0");
        parts.push((state.lastMoveUnjammed || []).join("/"));
        parts.push(guardedPreviewIds.join("/"));
        parts.push((advancePreviewIds || []).join("/"));
        parts.push((overshootPreviewIds || []).join("/"));
        parts.push((activeCols || []).join(","));
        parts.push(state.clampArmed ? "arm" : "dis");
        return parts.join("|");
    }

    function renderPinsAria(container, state) {
        if (!container) return;
        var lines = [];
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            var pin = state.pins[i];
            lines.push(describePinId(pin.id) + "：" + describePinState(pin.state)
                + "，" + describePinLane(state.spec, pin)
                + "，高度 " + pin.currentHeight + "/" + pin.targetHeight);
        }
        container.textContent = lines.join("；");
    }

    function collectTransitionIds(result, reason) {
        var out = [];
        if (!result || !result.events) return out;
        var e;
        var t;
        for (e = 0; e < result.events.length; e += 1) {
            var trs = result.events[e].pinTransitions || [];
            for (t = 0; t < trs.length; t += 1) {
                if (trs[t].reason === reason) {
                    if (out.indexOf(trs[t].pinId) === -1) out.push(trs[t].pinId);
                }
            }
        }
        return out;
    }

    function previewForHoveredCandidate(state, viewModel) {
        if (!viewModel || !viewModel.selected || !viewModel.hoveredCandidate) return null;
        if (state.status !== "ongoing") return null;
        if (typeof PinAlignCore === "undefined" || !PinAlignCore.previewSwap) return null;
        var sel = viewModel.selected;
        var tgt = viewModel.hoveredCandidate;
        if (Math.abs(sel.row - tgt.row) + Math.abs(sel.col - tgt.col) !== 1) return null;
        return PinAlignCore.previewSwap(state, sel, { row: tgt.row, col: tgt.col });
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
        var weights = spec.lane && spec.lane.weightsByDistance;
        if (weights && distance < weights.length) return weights[distance];
        return 0;
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
        setStageNote: setStageNote,
        summarizePreview: summarizePreview
    };
});
