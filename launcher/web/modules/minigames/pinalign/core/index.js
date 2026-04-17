(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.PinAlignCore = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var STREAM_NAMES = [
        "initBoard",
        "obstacle",
        "refill",
        "reshuffle",
        "pity",
        "specialTarget",
        "cosmeticFx",
        "cosmeticAudio"
    ];

    var SPECIAL_TYPES = ["shimH", "shimV", "brace", "calibrator"];
    var OBSTACLE_TYPES = ["debris", "clip"];

    var DEFAULT_SPEC = {
        id: "mvp-3pin-v1",
        rows: 8,
        cols: 8,
        colorCount: 5,
        pinCount: 3,
        pinTargetHeightMin: 2,
        pinTargetHeightMax: 3,
        pins: [
            { id: "pin-a", centerCol: 1, targetHeight: null },
            { id: "pin-b", centerCol: 3, targetHeight: null },
            { id: "pin-c", centerCol: 6, targetHeight: null }
        ],
        lane: {
            radius: 1.85,
            threshold: 1.75,
            margin: 0.2
        },
        alert: {
            initial: 16
        },
        obstacles: {
            debris: 3,
            clip: 3
        },
        clamp: {
            initialCharge: 44,
            maxCharge: 100,
            cost: 100,
            chargePerEvent: 4,
            chargePerSignal: 10,
            chargePerSpecial: 14
        },
        pity: {
            hintAfter: 4,
            biasAfter: 6,
            helperAfter: 8
        },
        generation: {
            maxInitAttempts: 120,
            maxReshuffleAttempts: 56,
            minProductiveMoves: 2,
            minLaneCoverage: 1.15
        },
        simulation: {
            iterations: 120,
            maxTurns: 24,
            badSeedLimit: 25
        }
    };

    function cloneJson(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function mergeObject(base, extra) {
        var out = cloneJson(base);
        if (!extra) return out;
        var key;
        for (key in extra) {
            if (!Object.prototype.hasOwnProperty.call(extra, key)) continue;
            if (extra[key] && typeof extra[key] === "object" && !Array.isArray(extra[key]) && out[key] && typeof out[key] === "object" && !Array.isArray(out[key])) {
                out[key] = mergeObject(out[key], extra[key]);
            } else {
                out[key] = cloneJson(extra[key]);
            }
        }
        return out;
    }

    function normalizeSpec(spec) {
        var merged = mergeObject(DEFAULT_SPEC, spec || {});
        merged.rows = merged.rows | 0;
        merged.cols = merged.cols | 0;
        merged.colorCount = merged.colorCount | 0;
        merged.pinCount = merged.pinCount | 0;
        if (!merged.pins || !merged.pins.length) {
            merged.pins = cloneJson(DEFAULT_SPEC.pins);
        }
        while (merged.pins.length < merged.pinCount) {
            merged.pins.push({
                id: "pin-" + (merged.pins.length + 1),
                centerCol: merged.pins.length * 2 + 1,
                targetHeight: null
            });
        }
        merged.pins = merged.pins.slice(0, merged.pinCount);
        var i;
        for (i = 0; i < merged.pins.length; i += 1) {
            if (merged.pins[i].id == null) merged.pins[i].id = "pin-" + (i + 1);
            if (merged.pins[i].centerCol == null) merged.pins[i].centerCol = Math.min(merged.cols - 1, i * 2 + 1);
        }
        return merged;
    }

    function createTelemetry(spec) {
        return {
            specId: spec.id,
            movesAttempted: 0,
            legalSwaps: 0,
            invalidSwaps: 0,
            productiveSwaps: 0,
            unproductiveSwaps: 0,
            totalEvents: 0,
            totalSignals: 0,
            totalEffectTiles: 0,
            generatedSpecials: 0,
            jamCount: 0,
            overshootCount: 0,
            pityTriggers: 0,
            pityHints: 0,
            pityBiases: 0,
            helperInjections: 0,
            reshuffles: 0,
            clampUses: 0,
            productiveMoveSamples: 0,
            productiveMoveTotal: 0,
            lastOutcome: "ongoing"
        };
    }

    function xmur3(str) {
        var h = 1779033703 ^ str.length;
        var i;
        for (i = 0; i < str.length; i += 1) {
            h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
            h = (h << 13) | (h >>> 19);
        }
        return function() {
            h = Math.imul(h ^ (h >>> 16), 2246822507);
            h = Math.imul(h ^ (h >>> 13), 3266489909);
            h = (h ^ (h >>> 16)) >>> 0;
            return h;
        };
    }

    function createStream(masterSeed, name) {
        var seed = xmur3(String(masterSeed) + "::" + name);
        return {
            a: seed(),
            b: seed(),
            c: seed(),
            d: seed(),
            calls: 0
        };
    }

    function createSeededRngPipeline(masterSeed) {
        var pipeline = {
            masterSeed: String(masterSeed || "seed"),
            streams: {}
        };
        var i;
        for (i = 0; i < STREAM_NAMES.length; i += 1) {
            pipeline.streams[STREAM_NAMES[i]] = createStream(pipeline.masterSeed, STREAM_NAMES[i]);
        }
        return pipeline;
    }

    function nextFloat(rng, streamName) {
        var s = rng.streams[streamName];
        if (!s) {
            s = createStream(rng.masterSeed, streamName);
            rng.streams[streamName] = s;
        }
        var t = (s.a + s.b) | 0;
        s.a = s.b ^ (s.b >>> 9);
        s.b = (s.c + (s.c << 3)) | 0;
        s.c = (s.c << 21) | (s.c >>> 11);
        s.d = (s.d + 1) | 0;
        t = (t + s.d) | 0;
        s.c = (s.c + t) | 0;
        s.calls += 1;
        return (t >>> 0) / 4294967296;
    }

    function nextInt(rng, streamName, maxExclusive) {
        if (maxExclusive <= 0) return 0;
        return Math.floor(nextFloat(rng, streamName) * maxExclusive);
    }

    function chooseWeighted(weights, rng, streamName) {
        var total = 0;
        var i;
        for (i = 0; i < weights.length; i += 1) total += weights[i].weight;
        if (total <= 0) return weights[0].value;
        var roll = nextFloat(rng, streamName) * total;
        var cursor = 0;
        for (i = 0; i < weights.length; i += 1) {
            cursor += weights[i].weight;
            if (roll <= cursor) return weights[i].value;
        }
        return weights[weights.length - 1].value;
    }

    function shuffleInPlace(arr, rng, streamName) {
        var i;
        for (i = arr.length - 1; i > 0; i -= 1) {
            var j = nextInt(rng, streamName, i + 1);
            var temp = arr[i];
            arr[i] = arr[j];
            arr[j] = temp;
        }
        return arr;
    }

    function coordKey(row, col) {
        return row + "," + col;
    }

    function parseCoordKey(key) {
        var parts = key.split(",");
        return { row: parseInt(parts[0], 10), col: parseInt(parts[1], 10) };
    }

    function clampNumber(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function isInside(state, row, col) {
        return row >= 0 && row < state.spec.rows && col >= 0 && col < state.spec.cols;
    }

    function isMovableTile(tile) {
        return !!tile && tile.kind !== "obstacle";
    }

    function isMatchableTile(tile) {
        return !!tile && (tile.kind === "gem" || tile.kind === "special");
    }

    function snapshotTile(tile) {
        if (!tile) return null;
        return {
            id: tile.id,
            kind: tile.kind,
            color: tile.color,
            specialType: tile.specialType || null,
            obstacleType: tile.obstacleType || null,
            row: tile.row,
            col: tile.col
        };
    }

    function snapshotBoard(board) {
        var rows = [];
        var r;
        for (r = 0; r < board.length; r += 1) {
            var row = [];
            var c;
            for (c = 0; c < board[r].length; c += 1) {
                row.push(snapshotTile(board[r][c]));
            }
            rows.push(row);
        }
        return rows;
    }

    function snapshotPins(pins) {
        var out = [];
        var i;
        for (i = 0; i < pins.length; i += 1) {
            out.push({
                id: pins[i].id,
                centerCol: pins[i].centerCol,
                targetHeight: pins[i].targetHeight,
                currentHeight: pins[i].currentHeight,
                state: pins[i].state,
                guardThisMove: !!pins[i].guardThisMove
            });
        }
        return out;
    }

    function snapshotState(state) {
        return cloneJson(state);
    }

    function makeEmptyBoard(rows, cols) {
        var board = [];
        var r;
        for (r = 0; r < rows; r += 1) {
            var row = [];
            var c;
            for (c = 0; c < cols; c += 1) row.push(null);
            board.push(row);
        }
        return board;
    }

    function createTile(state, row, col, color, kind, extraType) {
        state.nextTileId += 1;
        return {
            id: "t" + state.nextTileId,
            row: row,
            col: col,
            kind: kind || "gem",
            color: color,
            specialType: kind === "special" ? extraType : null,
            obstacleType: kind === "obstacle" ? extraType : null
        };
    }

    function laneWeight(spec, pin, col) {
        var distance = Math.abs(pin.centerCol - col);
        var radius = spec.lane.radius;
        var raw = 1 - (distance / radius);
        if (raw <= 0) return 0;
        return Number((raw * raw).toFixed(3));
    }

    function allPinsLocked(state) {
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            if (state.pins[i].state !== "locked") return false;
        }
        return true;
    }

    function hasSetPin(state) {
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            if (state.pins[i].state === "set") return true;
        }
        return false;
    }

    function selectMostNeedyPin(state, colHint, eventContext) {
        var best = null;
        var bestScore = -999999;
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            var pin = state.pins[i];
            if (pin.state === "locked") continue;
            if (eventContext && eventContext.eventPinTouched && eventContext.eventPinTouched[pin.id]) {
                continue;
            }
            var deficit = pin.targetHeight - pin.currentHeight;
            var guardBoost = pin.state === "set" ? 100 : 0;
            var laneScore = laneWeight(state.spec, pin, colHint);
            var score = guardBoost + deficit * 10 + laneScore;
            if (score > bestScore) {
                bestScore = score;
                best = pin;
            }
        }
        if (best) return best;
        for (i = 0; i < state.pins.length; i += 1) {
            if (state.pins[i].state !== "locked") return state.pins[i];
        }
        return state.pins[0] || null;
    }

    function createPins(state) {
        var pins = [];
        var i;
        for (i = 0; i < state.spec.pins.length; i += 1) {
            var source = state.spec.pins[i];
            var targetHeight = source.targetHeight;
            if (targetHeight == null) {
                var span = state.spec.pinTargetHeightMax - state.spec.pinTargetHeightMin + 1;
                targetHeight = state.spec.pinTargetHeightMin + nextInt(state.rng, "initBoard", span);
            }
            pins.push({
                id: source.id,
                centerCol: clampNumber(source.centerCol, 0, state.spec.cols - 1),
                targetHeight: targetHeight,
                currentHeight: 0,
                state: "normal",
                guardThisMove: false
            });
        }
        return pins;
    }

    function createState(spec, masterSeed) {
        var normalizedSpec = normalizeSpec(spec);
        var state = {
            spec: normalizedSpec,
            masterSeed: String(masterSeed || "seed"),
            rng: createSeededRngPipeline(masterSeed || "seed"),
            board: makeEmptyBoard(normalizedSpec.rows, normalizedSpec.cols),
            pins: [],
            moveIndex: 0,
            status: "ongoing",
            alertRemaining: normalizedSpec.alert.initial,
            clampCharge: normalizedSpec.clamp.initialCharge,
            clampArmed: false,
            clampActiveThisMove: false,
            movePrepared: false,
            stagnationMoves: 0,
            pityStage: 0,
            reshuffleCount: 0,
            nextTileId: 0,
            actionLog: [],
            telemetry: createTelemetry(normalizedSpec),
            lastHint: null,
            lastResolution: null,
            lastMoveUnjammed: []
        };
        state.pins = createPins(state);
        buildInitialBoard(state);
        state.lastHint = getHint(state);
        state.telemetry.productiveMoveSamples += 1;
        state.telemetry.productiveMoveTotal += countProductiveMoves(state);
        return state;
    }

    function buildInitialBoard(state) {
        var attempt;
        var success = false;
        for (attempt = 0; attempt < state.spec.generation.maxInitAttempts; attempt += 1) {
            state.board = makeEmptyBoard(state.spec.rows, state.spec.cols);
            state.pins = createPins(state);
            placeInitialObstacles(state);
            fillBoardWithoutAutoMatches(state, "initBoard");
            if (hasAutoMatches(state.board)) continue;
            if (!hasLaneCoverage(state)) continue;
            if (countProductiveMoves(state) < state.spec.generation.minProductiveMoves) continue;
            success = true;
            break;
        }
        if (!success) {
            state.board = makeEmptyBoard(state.spec.rows, state.spec.cols);
            state.pins = createPins(state);
            placeInitialObstacles(state);
            fillBoardWithoutAutoMatches(state, "initBoard");
            injectHelper(state, "fallback_init");
            if (countProductiveMoves(state) === 0) {
                biasBoardTowardsProductiveMove(state, "fallback_init");
            }
        }
    }

    function hasLaneCoverage(state) {
        var row;
        var col;
        for (row = 0; row < state.spec.rows; row += 1) {
            for (col = 0; col < state.spec.cols; col += 1) {
                var tile = state.board[row][col];
                if (!isMovableTile(tile)) continue;
                var p;
                for (p = 0; p < state.pins.length; p += 1) {
                    if (laneWeight(state.spec, state.pins[p], col) >= state.spec.generation.minLaneCoverage) return true;
                }
            }
        }
        return false;
    }

    function placeInitialObstacles(state) {
        var candidates = [];
        var row;
        var col;
        for (row = 1; row < state.spec.rows - 1; row += 1) {
            for (col = 0; col < state.spec.cols; col += 1) {
                if (isPinCenterColumn(state, col)) continue;
                candidates.push({ row: row, col: col });
            }
        }
        shuffleInPlace(candidates, state.rng, "obstacle");
        placeObstacleKind(state, candidates, "debris", state.spec.obstacles.debris);
        placeObstacleKind(state, candidates, "clip", state.spec.obstacles.clip);
    }

    function isPinCenterColumn(state, col) {
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            if (state.pins[i].centerCol === col) return true;
        }
        return false;
    }

    function placeObstacleKind(state, candidates, kind, count) {
        var placed = 0;
        while (placed < count && candidates.length) {
            var slot = candidates.shift();
            if (state.board[slot.row][slot.col]) continue;
            if (touchesObstacle(state, slot.row, slot.col)) continue;
            state.board[slot.row][slot.col] = createTile(state, slot.row, slot.col, null, "obstacle", kind);
            placed += 1;
        }
    }

    function touchesObstacle(state, row, col) {
        var deltas = [[1, 0], [-1, 0], [0, 1], [0, -1]];
        var i;
        for (i = 0; i < deltas.length; i += 1) {
            var nr = row + deltas[i][0];
            var nc = col + deltas[i][1];
            if (!isInside(state, nr, nc)) continue;
            var tile = state.board[nr][nc];
            if (tile && tile.kind === "obstacle") return true;
        }
        return false;
    }

    function fillBoardWithoutAutoMatches(state, streamName) {
        var row;
        var col;
        for (row = 0; row < state.spec.rows; row += 1) {
            for (col = 0; col < state.spec.cols; col += 1) {
                if (state.board[row][col] && state.board[row][col].kind === "obstacle") continue;
                var color = pickBiasedColor(state, row, col, streamName, true);
                state.board[row][col] = createTile(state, row, col, color, "gem", null);
            }
        }
    }

    function pickBiasedColor(state, row, col, streamName, strictAvoidMatch) {
        var weights = [];
        var color;
        for (color = 0; color < state.spec.colorCount; color += 1) {
            var weight = 1;
            var left = getColor(state.board, row, col - 1);
            var left2 = getColor(state.board, row, col - 2);
            var up = getColor(state.board, row - 1, col);
            var up2 = getColor(state.board, row - 2, col);
            if (strictAvoidMatch && left === color && left2 === color) weight = 0;
            if (strictAvoidMatch && up === color && up2 === color) weight = 0;
            if (weight === 0) {
                weights.push({ value: color, weight: 0 });
                continue;
            }
            var laneBoost = 0;
            var i;
            for (i = 0; i < state.pins.length; i += 1) {
                var pin = state.pins[i];
                var lane = laneWeight(state.spec, pin, col);
                if (pin.state === "locked") continue;
                laneBoost += lane * (pin.state === "set" ? 0.6 : 0.35);
            }
            if (left === color) weight += laneBoost;
            if (up === color) weight += laneBoost * 0.85;
            if (col > 0 && getColor(state.board, row, col - 1) !== null && getColor(state.board, row, col - 1) !== color) weight += 0.15;
            weights.push({ value: color, weight: weight });
        }
        return chooseWeighted(weights, state.rng, streamName);
    }

    function getColor(board, row, col) {
        if (row < 0 || col < 0 || row >= board.length || col >= board[0].length) return null;
        var tile = board[row][col];
        return tile && isMatchableTile(tile) ? tile.color : null;
    }

    function beginPlayerMove(state) {
        if (state.status !== "ongoing") return state;
        if (state.movePrepared) return state;
        state.movePrepared = true;
        state.moveIndex += 1;
        state.clampActiveThisMove = !!state.clampArmed;
        state.clampArmed = false;
        state.lastMoveUnjammed = [];
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            if (state.pins[i].state === "jammed") {
                state.lastMoveUnjammed.push(state.pins[i].id);
                state.pins[i].state = "normal";
            }
            state.pins[i].guardThisMove = false;
        }
        return state;
    }

    function armClamp(state) {
        if (state.status !== "ongoing") {
            return { ok: false, reason: "status" };
        }
        if (state.clampArmed || state.clampActiveThisMove) {
            return { ok: false, reason: "already_armed" };
        }
        if (state.clampCharge < state.spec.clamp.cost) {
            return { ok: false, reason: "charge" };
        }
        state.clampCharge -= state.spec.clamp.cost;
        state.clampArmed = true;
        state.telemetry.clampUses += 1;
        state.actionLog.push({
            type: "armClamp",
            atMove: state.moveIndex,
            clampChargeAfter: state.clampCharge
        });
        return { ok: true, clampChargeAfter: state.clampCharge };
    }

    function trySwap(state, from, to, options) {
        return internalTrySwap(state, from, to, options || {});
    }

    function previewSwap(state, from, to) {
        var empty = {
            valid: false,
            reason: null,
            signalTiles: [],
            pinContributions: [],
            threshold: state && state.spec ? state.spec.lane.threshold : 0,
            margin: state && state.spec ? state.spec.lane.margin : 0,
            wouldAdvance: false,
            wouldOvershoot: false,
            clampArmed: state ? !!state.clampArmed : false
        };
        if (!state || state.status !== "ongoing") {
            empty.reason = "status";
            return empty;
        }
        if (!areAdjacent(from, to)) { empty.reason = "non_adjacent"; return empty; }
        if (!isInside(state, from.row, from.col) || !isInside(state, to.row, to.col)) {
            empty.reason = "out_of_bounds";
            return empty;
        }
        var a = state.board[from.row][from.col];
        var b = state.board[to.row][to.col];
        if (!isMovableTile(a) || !isMovableTile(b)) { empty.reason = "immovable"; return empty; }

        swapTiles(state, from, to);
        var matches = findMatches(state.board);
        var signalPositions = matches.signalTiles.slice();
        swapTiles(state, from, to);

        if (!signalPositions.length) {
            empty.reason = "no_match";
            return empty;
        }

        var contributions = [];
        var wouldAdvance = false;
        var wouldOvershoot = false;
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            var pin = state.pins[i];
            if (pin.state === "locked" || pin.state === "jammed") {
                contributions.push({
                    pinId: pin.id,
                    state: pin.state,
                    weight: 0,
                    wouldAdvance: false,
                    wouldOvershoot: false,
                    crossThreshold: false,
                    guardedByClamp: false
                });
                continue;
            }
            var weight = 0;
            var s;
            for (s = 0; s < signalPositions.length; s += 1) {
                weight += laneWeight(state.spec, pin, signalPositions[s].col);
            }
            var crosses = (weight + state.spec.lane.margin) >= state.spec.lane.threshold;
            var overshoot = crosses && pin.state === "set" && !state.clampArmed;
            var advance = crosses && pin.state !== "set";
            if (advance) wouldAdvance = true;
            if (overshoot) wouldOvershoot = true;
            contributions.push({
                pinId: pin.id,
                state: pin.state,
                weight: Number(weight.toFixed(3)),
                wouldAdvance: advance,
                wouldOvershoot: overshoot,
                crossThreshold: crosses,
                guardedByClamp: crosses && pin.state === "set" && !!state.clampArmed
            });
        }

        return {
            valid: true,
            reason: "match",
            signalTiles: signalPositions,
            pinContributions: contributions,
            threshold: state.spec.lane.threshold,
            margin: state.spec.lane.margin,
            wouldAdvance: wouldAdvance,
            wouldOvershoot: wouldOvershoot,
            clampArmed: !!state.clampArmed
        };
    }

    function internalTrySwap(state, from, to, options) {
        var preview = !!options.preview;
        if (state.status !== "ongoing") {
            return makeSwapResult(false, false, "status", state);
        }
        beginPlayerMove(state);
        if (!areAdjacent(from, to)) {
            if (!preview) state.telemetry.invalidSwaps += 1;
            return makeSwapResult(false, false, "non_adjacent", state);
        }
        if (!isInside(state, from.row, from.col) || !isInside(state, to.row, to.col)) {
            if (!preview) state.telemetry.invalidSwaps += 1;
            return makeSwapResult(false, false, "out_of_bounds", state);
        }
        var a = state.board[from.row][from.col];
        var b = state.board[to.row][to.col];
        if (!isMovableTile(a) || !isMovableTile(b)) {
            if (!preview) state.telemetry.invalidSwaps += 1;
            return makeSwapResult(false, false, "immovable", state);
        }

        swapTiles(state, from, to);
        var matches = findMatches(state.board);
        if (!matches.groups.length) {
            swapTiles(state, from, to);
            if (!preview) state.telemetry.invalidSwaps += 1;
            return makeSwapResult(false, false, "no_match", state);
        }

        var moveAlertBefore = state.alertRemaining;
        state.alertRemaining = Math.max(0, state.alertRemaining - 1);
        if (!preview) {
            state.telemetry.movesAttempted += 1;
            state.telemetry.legalSwaps += 1;
            state.actionLog.push({
                type: "swap",
                moveIndex: state.moveIndex,
                from: { row: from.row, col: from.col },
                to: { row: to.row, col: to.col }
            });
        }

        var result = {
            accepted: true,
            valid: true,
            consumedMove: true,
            reason: "match",
            alertBefore: moveAlertBefore,
            alertAfter: state.alertRemaining,
            moveIndex: state.moveIndex,
            events: [],
            pityActions: [],
            productive: false,
            boardBefore: preview ? null : snapshotBoard(state.board),
            boardAfter: null,
            pinsAfter: null,
            outcome: { status: state.status, reason: null },
            hint: null
        };

        while (matches.groups.length) {
            var event = resolveSettlementEvent(state, matches, { from: from, to: to });
            result.events.push(event);
            if (event.pinTransitions.length || event.generatedSpecials.length) {
                result.productive = true;
            }
            if (!preview) {
                state.telemetry.totalEvents += 1;
                state.telemetry.totalSignals += event.signalTiles.length;
                state.telemetry.totalEffectTiles += event.effectTiles.length;
                state.telemetry.generatedSpecials += event.generatedSpecials.length;
            }
            if (state.status !== "ongoing") break;
            matches = findMatches(state.board);
        }

        commitPinsAtMoveEnd(state, result);
        if (state.status === "ongoing" && state.alertRemaining <= 0) {
            state.status = "fail";
            result.outcome = { status: "fail", reason: "alert_depleted" };
        }

        if (!preview) {
            if (result.productive) state.telemetry.productiveSwaps += 1;
            else state.telemetry.unproductiveSwaps += 1;
            postMoveMaintenance(state, result);
            result.alertAfter = state.alertRemaining;
            result.boardAfter = snapshotBoard(state.board);
            result.pinsAfter = snapshotPins(state.pins);
            result.hint = getHint(state);
            result.stateHash = computeStateHash(state);
            state.telemetry.lastOutcome = state.status;
            state.lastHint = result.hint;
            state.lastResolution = {
                moveIndex: result.moveIndex,
                outcome: cloneJson(result.outcome),
                alertAfter: result.alertAfter,
                hash: result.stateHash
            };
        }

        state.movePrepared = false;
        state.clampActiveThisMove = false;
        clearPinMoveFlags(state);

        return result;
    }

    function makeSwapResult(accepted, valid, reason, state) {
        return {
            accepted: accepted,
            valid: valid,
            consumedMove: false,
            reason: reason,
            alertBefore: state.alertRemaining,
            alertAfter: state.alertRemaining,
            moveIndex: state.moveIndex,
            events: [],
            pityActions: [],
            productive: false,
            boardAfter: snapshotBoard(state.board),
            pinsAfter: snapshotPins(state.pins),
            outcome: { status: state.status, reason: reason },
            hint: state.lastHint
        };
    }

    function clearPinMoveFlags(state) {
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            state.pins[i].guardThisMove = false;
        }
    }

    function areAdjacent(a, b) {
        var dr = Math.abs(a.row - b.row);
        var dc = Math.abs(a.col - b.col);
        return (dr + dc) === 1;
    }

    function swapTiles(state, a, b) {
        var temp = state.board[a.row][a.col];
        state.board[a.row][a.col] = state.board[b.row][b.col];
        state.board[b.row][b.col] = temp;
        if (state.board[a.row][a.col]) {
            state.board[a.row][a.col].row = a.row;
            state.board[a.row][a.col].col = a.col;
        }
        if (state.board[b.row][b.col]) {
            state.board[b.row][b.col].row = b.row;
            state.board[b.row][b.col].col = b.col;
        }
    }

    function findMatches(board) {
        var groups = [];
        var signalMap = {};
        var rows = board.length;
        var cols = board[0].length;
        var row;
        var col;

        for (row = 0; row < rows; row += 1) {
            col = 0;
            while (col < cols) {
                var tile = board[row][col];
                if (!isMatchableTile(tile)) {
                    col += 1;
                    continue;
                }
                var color = tile.color;
                var run = [{ row: row, col: col }];
                var scan = col + 1;
                while (scan < cols && isMatchableTile(board[row][scan]) && board[row][scan].color === color) {
                    run.push({ row: row, col: scan });
                    scan += 1;
                }
                if (run.length >= 3) {
                    groups.push({ kind: "line", axis: "h", color: color, positions: run });
                    addSignalPositions(signalMap, run);
                }
                col = scan;
            }
        }

        for (col = 0; col < cols; col += 1) {
            row = 0;
            while (row < rows) {
                var tileV = board[row][col];
                if (!isMatchableTile(tileV)) {
                    row += 1;
                    continue;
                }
                var colorV = tileV.color;
                var runV = [{ row: row, col: col }];
                var scanV = row + 1;
                while (scanV < rows && isMatchableTile(board[scanV][col]) && board[scanV][col].color === colorV) {
                    runV.push({ row: scanV, col: col });
                    scanV += 1;
                }
                if (runV.length >= 3) {
                    groups.push({ kind: "line", axis: "v", color: colorV, positions: runV });
                    addSignalPositions(signalMap, runV);
                }
                row = scanV;
            }
        }

        for (row = 0; row < rows - 1; row += 1) {
            for (col = 0; col < cols - 1; col += 1) {
                var t1 = board[row][col];
                var t2 = board[row][col + 1];
                var t3 = board[row + 1][col];
                var t4 = board[row + 1][col + 1];
                if (!isMatchableTile(t1) || !isMatchableTile(t2) || !isMatchableTile(t3) || !isMatchableTile(t4)) continue;
                if (t1.color === t2.color && t1.color === t3.color && t1.color === t4.color) {
                    var square = [
                        { row: row, col: col },
                        { row: row, col: col + 1 },
                        { row: row + 1, col: col },
                        { row: row + 1, col: col + 1 }
                    ];
                    groups.push({ kind: "square", axis: "box", color: t1.color, positions: square });
                    addSignalPositions(signalMap, square);
                }
            }
        }

        var signalKeys = Object.keys(signalMap);
        var signalTiles = [];
        var i;
        for (i = 0; i < signalKeys.length; i += 1) {
            signalTiles.push(signalMap[signalKeys[i]]);
        }
        sortPositions(signalTiles);
        return { groups: groups, signalTiles: signalTiles };
    }

    function addSignalPositions(signalMap, positions) {
        var i;
        for (i = 0; i < positions.length; i += 1) {
            signalMap[coordKey(positions[i].row, positions[i].col)] = {
                row: positions[i].row,
                col: positions[i].col
            };
        }
    }

    function sortPositions(arr) {
        arr.sort(function(a, b) {
            if (a.row !== b.row) return a.row - b.row;
            return a.col - b.col;
        });
    }

    function resolveSettlementEvent(state, matches, swapMeta) {
        var event = {
            index: 0,
            signalTiles: [],
            effectTiles: [],
            generatedSpecials: [],
            pinTransitions: [],
            alertBefore: state.alertRemaining,
            alertAfter: state.alertRemaining,
            outcome: { status: state.status, reason: null },
            boardBefore: snapshotBoard(state.board),
            boardAfter: null
        };

        var signalPositions = matches.signalTiles;
        var eventContext = {
            eventPinTouched: {}
        };
        var signalMap = {};
        var i;
        for (i = 0; i < signalPositions.length; i += 1) {
            var currentTile = state.board[signalPositions[i].row][signalPositions[i].col];
            signalMap[coordKey(signalPositions[i].row, signalPositions[i].col)] = true;
            event.signalTiles.push(snapshotTile(currentTile) || {
                row: signalPositions[i].row,
                col: signalPositions[i].col,
                kind: "empty",
                color: null
            });
        }

        applySignalToPins(state, event.signalTiles, event.pinTransitions, eventContext);

        var effectMap = {};
        activateMatchedSpecials(state, event.signalTiles, event.pinTransitions, effectMap, eventContext);

        var generatedMap = planGeneratedSpecials(state, matches.groups, swapMeta);
        event.generatedSpecials = generatedMap.generatedSpecials;

        collectObstacleCollateral(state, signalMap, effectMap);

        var removeSignalKeys = Object.keys(signalMap);
        for (i = 0; i < removeSignalKeys.length; i += 1) {
            if (generatedMap.anchorMap[removeSignalKeys[i]]) continue;
            removeBoardCell(state, parseCoordKey(removeSignalKeys[i]));
        }

        var effectKeys = Object.keys(effectMap);
        for (i = 0; i < effectKeys.length; i += 1) {
            var effectPos = parseCoordKey(effectKeys[i]);
            if (generatedMap.anchorMap[effectKeys[i]]) continue;
            var effectTile = state.board[effectPos.row][effectPos.col];
            event.effectTiles.push(snapshotTile(effectTile) || {
                row: effectPos.row,
                col: effectPos.col,
                kind: "empty",
                color: null
            });
            removeBoardCell(state, effectPos);
        }

        for (i = 0; i < generatedMap.generatedSpecials.length; i += 1) {
            var specInfo = generatedMap.generatedSpecials[i];
            state.board[specInfo.row][specInfo.col] = createTile(state, specInfo.row, specInfo.col, specInfo.color, "special", specInfo.specialType);
        }

        applyGravityAndRefill(state);
        chargeClampFromEvent(state, event);

        event.alertAfter = state.alertRemaining;
        event.outcome = { status: state.status, reason: null };
        event.boardAfter = snapshotBoard(state.board);
        return event;
    }

    function applySignalToPins(state, signalTiles, transitions, eventContext) {
        var i;
        for (i = 0; i < state.pins.length; i += 1) {
            var pin = state.pins[i];
            if (pin.state === "locked" || pin.state === "jammed") continue;
            var weightSum = 0;
            var s;
            for (s = 0; s < signalTiles.length; s += 1) {
                weightSum += laneWeight(state.spec, pin, signalTiles[s].col);
            }
            if (weightSum + state.spec.lane.margin < state.spec.lane.threshold) continue;
            if (eventContext.eventPinTouched[pin.id]) continue;
            eventContext.eventPinTouched[pin.id] = true;
            if (pin.state === "set") {
                if (pin.guardThisMove || state.clampActiveThisMove) {
                    transitions.push({
                        pinId: pin.id,
                        fromState: "set",
                        toState: "set",
                        fromHeight: pin.currentHeight,
                        toHeight: pin.currentHeight,
                        reason: "guarded_overshoot"
                    });
                    continue;
                }
                var beforeAlert = state.alertRemaining;
                pin.currentHeight = Math.max(0, pin.targetHeight - 1);
                pin.state = "jammed";
                state.alertRemaining = Math.max(0, state.alertRemaining - 1);
                state.telemetry.jamCount += 1;
                state.telemetry.overshootCount += 1;
                transitions.push({
                    pinId: pin.id,
                    fromState: "set",
                    toState: "jammed",
                    fromHeight: pin.targetHeight,
                    toHeight: pin.currentHeight,
                    alertBefore: beforeAlert,
                    alertAfter: state.alertRemaining,
                    reason: "overshoot"
                });
                continue;
            }
            var beforeHeight = pin.currentHeight;
            var beforeState = pin.state;
            pin.currentHeight = Math.min(pin.targetHeight, pin.currentHeight + 1);
            if (pin.currentHeight >= pin.targetHeight) pin.state = "set";
            transitions.push({
                pinId: pin.id,
                fromState: beforeState,
                toState: pin.state,
                fromHeight: beforeHeight,
                toHeight: pin.currentHeight,
                weight: Number(weightSum.toFixed(3)),
                reason: "signal"
            });
        }
    }

    function activateMatchedSpecials(state, signalTiles, transitions, effectMap, eventContext) {
        var i;
        for (i = 0; i < signalTiles.length; i += 1) {
            var tile = state.board[signalTiles[i].row][signalTiles[i].col];
            if (!tile || tile.kind !== "special") continue;
            if (tile.specialType === "shimH") {
                markLineEffect(state, effectMap, tile.row, tile.col - 2, tile.row, tile.col + 2);
            } else if (tile.specialType === "shimV") {
                markLineEffect(state, effectMap, tile.row - 2, tile.col, tile.row + 2, tile.col);
            } else if (tile.specialType === "brace") {
                var guardPin = selectMostNeedyPin(state, tile.col, null);
                if (guardPin) guardPin.guardThisMove = true;
                markAreaEffect(state, effectMap, tile.row, tile.col, 1);
            } else if (tile.specialType === "calibrator") {
                var targetPin = selectMostNeedyPin(state, tile.col, eventContext);
                if (targetPin) {
                    safeLiftPin(state, targetPin, transitions, eventContext, "calibrator");
                }
                markAreaEffect(state, effectMap, tile.row, tile.col, 0);
            }
        }
    }

    function markLineEffect(state, effectMap, rowA, colA, rowB, colB) {
        if (rowA === rowB) {
            var c;
            for (c = Math.min(colA, colB); c <= Math.max(colA, colB); c += 1) {
                if (isInside(state, rowA, c)) effectMap[coordKey(rowA, c)] = true;
            }
        } else {
            var r;
            for (r = Math.min(rowA, rowB); r <= Math.max(rowA, rowB); r += 1) {
                if (isInside(state, r, colA)) effectMap[coordKey(r, colA)] = true;
            }
        }
    }

    function markAreaEffect(state, effectMap, row, col, radius) {
        var r;
        var c;
        for (r = row - radius; r <= row + radius; r += 1) {
            for (c = col - radius; c <= col + radius; c += 1) {
                if (isInside(state, r, c)) effectMap[coordKey(r, c)] = true;
            }
        }
    }

    function safeLiftPin(state, pin, transitions, eventContext, reason) {
        if (pin.state === "locked" || pin.state === "jammed") return;
        if (eventContext.eventPinTouched[pin.id]) return;
        eventContext.eventPinTouched[pin.id] = true;
        var beforeHeight = pin.currentHeight;
        var beforeState = pin.state;
        pin.currentHeight = Math.min(pin.targetHeight, pin.currentHeight + 1);
        if (pin.currentHeight >= pin.targetHeight) pin.state = "set";
        transitions.push({
            pinId: pin.id,
            fromState: beforeState,
            toState: pin.state,
            fromHeight: beforeHeight,
            toHeight: pin.currentHeight,
            reason: reason
        });
    }

    function planGeneratedSpecials(state, groups, swapMeta) {
        var anchorMap = {};
        var generatedSpecials = [];
        var i;
        var orderedGroups = groups.slice();
        orderedGroups.sort(function(a, b) {
            var pa = specialPriorityForGroup(a);
            var pb = specialPriorityForGroup(b);
            if (pb !== pa) return pb - pa;
            return b.positions.length - a.positions.length;
        });
        for (i = 0; i < orderedGroups.length; i += 1) {
            var specialType = specialTypeForGroup(orderedGroups[i]);
            if (!specialType) continue;
            var anchor = chooseGroupAnchor(orderedGroups[i], swapMeta);
            var key = coordKey(anchor.row, anchor.col);
            if (anchorMap[key]) continue;
            var sourceTile = state.board[anchor.row][anchor.col];
            if (!sourceTile || !isMatchableTile(sourceTile)) continue;
            anchorMap[key] = true;
            generatedSpecials.push({
                row: anchor.row,
                col: anchor.col,
                color: sourceTile.color,
                specialType: specialType
            });
        }
        return {
            anchorMap: anchorMap,
            generatedSpecials: generatedSpecials
        };
    }

    function specialPriorityForGroup(group) {
        if (group.kind === "square") return 5;
        if (group.positions.length >= 5) return 4;
        if (group.axis === "v") return 3;
        return 2;
    }

    function specialTypeForGroup(group) {
        if (group.kind === "square") return "brace";
        if (group.positions.length >= 5) return "calibrator";
        if (group.positions.length === 4 && group.axis === "h") return "shimH";
        if (group.positions.length === 4 && group.axis === "v") return "shimV";
        return null;
    }

    function chooseGroupAnchor(group, swapMeta) {
        var positions = group.positions.slice();
        sortPositions(positions);
        if (swapMeta) {
            var i;
            for (i = 0; i < positions.length; i += 1) {
                if (positions[i].row === swapMeta.to.row && positions[i].col === swapMeta.to.col) return positions[i];
            }
            for (i = 0; i < positions.length; i += 1) {
                if (positions[i].row === swapMeta.from.row && positions[i].col === swapMeta.from.col) return positions[i];
            }
        }
        return positions[Math.floor((positions.length - 1) / 2)];
    }

    function collectObstacleCollateral(state, signalMap, effectMap) {
        var combinedKeys = Object.keys(signalMap).concat(Object.keys(effectMap));
        var i;
        for (i = 0; i < combinedKeys.length; i += 1) {
            var pos = parseCoordKey(combinedKeys[i]);
            var deltas = [[1, 0], [-1, 0], [0, 1], [0, -1]];
            var d;
            for (d = 0; d < deltas.length; d += 1) {
                var nr = pos.row + deltas[d][0];
                var nc = pos.col + deltas[d][1];
                if (!isInside(state, nr, nc)) continue;
                var tile = state.board[nr][nc];
                if (tile && tile.kind === "obstacle") effectMap[coordKey(nr, nc)] = true;
            }
        }
    }

    function removeBoardCell(state, pos) {
        if (!isInside(state, pos.row, pos.col)) return;
        state.board[pos.row][pos.col] = null;
    }

    function applyGravityAndRefill(state) {
        var col;
        for (col = 0; col < state.spec.cols; col += 1) {
            settleColumnSegmented(state, col);
        }
    }

    function settleColumnSegmented(state, col) {
        var row = state.spec.rows - 1;
        while (row >= 0) {
            if (state.board[row][col] && state.board[row][col].kind === "obstacle") {
                row -= 1;
                continue;
            }
            var segmentEnd = row;
            while (row >= 0 && !(state.board[row][col] && state.board[row][col].kind === "obstacle")) {
                row -= 1;
            }
            var segmentStart = row + 1;
            var survivors = [];
            var scan;
            for (scan = segmentEnd; scan >= segmentStart; scan -= 1) {
                if (state.board[scan][col]) survivors.push(state.board[scan][col]);
            }
            var write = segmentEnd;
            var i;
            for (i = 0; i < survivors.length; i += 1) {
                state.board[write][col] = survivors[i];
                state.board[write][col].row = write;
                state.board[write][col].col = col;
                write -= 1;
            }
            while (write >= segmentStart) {
                state.board[write][col] = createTile(state, write, col, pickBiasedColor(state, write, col, "refill", false), "gem", null);
                write -= 1;
            }
        }
    }

    function chargeClampFromEvent(state, event) {
        var delta = state.spec.clamp.chargePerEvent;
        var signalGain = 0;
        var i;
        for (i = 0; i < event.pinTransitions.length; i += 1) {
            if (event.pinTransitions[i].reason === "signal" || event.pinTransitions[i].reason === "calibrator") {
                signalGain += state.spec.clamp.chargePerSignal;
            }
        }
        delta += signalGain;
        delta += event.generatedSpecials.length * state.spec.clamp.chargePerSpecial;
        state.clampCharge = clampNumber(state.clampCharge + delta, 0, state.spec.clamp.maxCharge);
    }

    function commitPinsAtMoveEnd(state, result) {
        var i;
        var lockedAny = false;
        result.committedLocks = [];
        for (i = 0; i < state.pins.length; i += 1) {
            var pin = state.pins[i];
            if (pin.state === "set") {
                pin.state = "locked";
                result.committedLocks.push(pin.id);
                lockedAny = true;
            }
        }
        if (allPinsLocked(state)) {
            state.status = "win";
            result.outcome = { status: "win", reason: lockedAny ? "commit_locked" : "already_locked" };
            return;
        }
        if (state.alertRemaining <= 0) {
            state.status = "fail";
            result.outcome = { status: "fail", reason: "alert_depleted" };
            return;
        }
        result.outcome = { status: state.status, reason: lockedAny ? "commit" : "ongoing" };
    }

    function postMoveMaintenance(state, result) {
        var productiveMoves = listProductiveMoves(state);
        state.telemetry.productiveMoveSamples += 1;
        state.telemetry.productiveMoveTotal += productiveMoves.length;
        if (result.productive) {
            state.stagnationMoves = 0;
            state.pityStage = 0;
        } else {
            state.stagnationMoves += 1;
        }

        if (state.status !== "ongoing") return;

        if (state.stagnationMoves >= state.spec.pity.hintAfter) {
            state.telemetry.pityHints += 1;
            state.telemetry.pityTriggers += 1;
            result.pityActions.push({
                type: "hint",
                hint: productiveMoves[0] || null
            });
        }

        if (!productiveMoves.length) {
            if (reshuffleBoard(state, "dead_board")) {
                productiveMoves = listProductiveMoves(state);
                result.pityActions.push({ type: "reshuffle" });
                state.telemetry.reshuffles += 1;
                state.telemetry.pityTriggers += 1;
            }
        }

        if (!productiveMoves.length || state.stagnationMoves >= state.spec.pity.biasAfter) {
            var biasResult = biasBoardTowardsProductiveMove(state, "stagnation");
            if (biasResult) {
                productiveMoves = listProductiveMoves(state);
                result.pityActions.push(biasResult);
                state.telemetry.pityBiases += 1;
                state.telemetry.pityTriggers += 1;
            }
        }

        if (!productiveMoves.length || state.stagnationMoves >= state.spec.pity.helperAfter) {
            var helper = injectHelper(state, "pity_helper");
            if (helper) {
                productiveMoves = listProductiveMoves(state);
                result.pityActions.push(helper);
                state.telemetry.helperInjections += 1;
                state.telemetry.pityTriggers += 1;
            }
        }

        if (!productiveMoves.length) {
            reshuffleBoard(state, "final_dead_board");
            productiveMoves = listProductiveMoves(state);
        }

        result.hint = productiveMoves[0] || null;
        if (!productiveMoves.length && !listLegalMoves(state).length) {
            state.status = "fail";
            result.outcome = { status: "fail", reason: "no_legal_moves" };
        } else if (state.alertRemaining <= 0 && state.status === "ongoing") {
            state.status = "fail";
            result.outcome = { status: "fail", reason: "alert_depleted" };
        }
    }

    function listSwapMoves(state, mode) {
        var moves = [];
        var row;
        var col;
        for (row = 0; row < state.spec.rows; row += 1) {
            for (col = 0; col < state.spec.cols; col += 1) {
                var here = state.board[row][col];
                if (!isMovableTile(here)) continue;
                if (col + 1 < state.spec.cols && isMovableTile(state.board[row][col + 1])) {
                    appendPreviewMove(state, moves, { row: row, col: col }, { row: row, col: col + 1 }, mode);
                }
                if (row + 1 < state.spec.rows && isMovableTile(state.board[row + 1][col])) {
                    appendPreviewMove(state, moves, { row: row, col: col }, { row: row + 1, col: col }, mode);
                }
            }
        }
        moves.sort(function(a, b) {
            if (b.score !== a.score) return b.score - a.score;
            if (a.from.row !== b.from.row) return a.from.row - b.from.row;
            if (a.from.col !== b.from.col) return a.from.col - b.from.col;
            if (a.to.row !== b.to.row) return a.to.row - b.to.row;
            return a.to.col - b.to.col;
        });
        return moves;
    }

    function appendPreviewMove(state, moves, from, to, mode) {
        var clone = snapshotState(state);
        clone.movePrepared = false;
        var result = internalTrySwap(clone, from, to, { preview: true });
        if (!result.valid) return;
        var score = previewMoveScore(result);
        if (mode === "productive" && !isPreviewProductive(result)) return;
        moves.push({
            from: { row: from.row, col: from.col },
            to: { row: to.row, col: to.col },
            score: score,
            productive: isPreviewProductive(result),
            specialCount: previewSpecialCount(result),
            pinGain: previewPinGain(result)
        });
    }

    function previewMoveScore(result) {
        return previewPinGain(result) * 100 + previewSpecialCount(result) * 25 + result.events.length;
    }

    function previewPinGain(result) {
        var gain = 0;
        var e;
        var p;
        for (e = 0; e < result.events.length; e += 1) {
            for (p = 0; p < result.events[e].pinTransitions.length; p += 1) {
                var transition = result.events[e].pinTransitions[p];
                if (transition.reason === "signal" || transition.reason === "calibrator") gain += 1;
            }
        }
        return gain;
    }

    function previewSpecialCount(result) {
        var total = 0;
        var e;
        for (e = 0; e < result.events.length; e += 1) {
            total += result.events[e].generatedSpecials.length;
        }
        return total;
    }

    function isPreviewProductive(result) {
        return previewPinGain(result) > 0 || previewSpecialCount(result) > 0;
    }

    function listProductiveMoves(state) {
        return listSwapMoves(state, "productive");
    }

    function listLegalMoves(state) {
        return listSwapMoves(state, "legal");
    }

    function countProductiveMoves(state) {
        return listProductiveMoves(state).length;
    }

    function getHint(state) {
        var moves = listProductiveMoves(state);
        return moves.length ? moves[0] : null;
    }

    function reshuffleBoard(state, reason) {
        var movable = [];
        var row;
        var col;
        for (row = 0; row < state.spec.rows; row += 1) {
            for (col = 0; col < state.spec.cols; col += 1) {
                if (isMovableTile(state.board[row][col])) {
                    movable.push(snapshotTile(state.board[row][col]));
                }
            }
        }
        var attempt;
        for (attempt = 0; attempt < state.spec.generation.maxReshuffleAttempts; attempt += 1) {
            var pool = cloneJson(movable);
            shuffleInPlace(pool, state.rng, "reshuffle");
            var idx = 0;
            for (row = 0; row < state.spec.rows; row += 1) {
                for (col = 0; col < state.spec.cols; col += 1) {
                    if (!isMovableTile(state.board[row][col])) continue;
                    var source = pool[idx];
                    idx += 1;
                    state.board[row][col] = createTileFromSnapshot(state, source, row, col);
                }
            }
            if (hasAutoMatches(state.board)) continue;
            if (countProductiveMoves(state) > 0) {
                state.reshuffleCount += 1;
                return {
                    type: "reshuffle",
                    reason: reason,
                    attempts: attempt + 1
                };
            }
        }
        return null;
    }

    function createTileFromSnapshot(state, snapshot, row, col) {
        if (!snapshot) return null;
        if (snapshot.kind === "special") {
            return createTile(state, row, col, snapshot.color, "special", snapshot.specialType);
        }
        return createTile(state, row, col, snapshot.color, snapshot.kind || "gem", snapshot.obstacleType || null);
    }

    function biasBoardTowardsProductiveMove(state, reason) {
        var baseCount = countProductiveMoves(state);
        var bestPin = selectMostNeedyPin(state, Math.floor(state.spec.cols / 2), null);
        if (!bestPin) return null;
        var candidates = [];
        var row;
        var col;
        for (row = 0; row < state.spec.rows; row += 1) {
            for (col = 0; col < state.spec.cols; col += 1) {
                var tile = state.board[row][col];
                if (!tile || tile.kind !== "gem") continue;
                candidates.push({
                    row: row,
                    col: col,
                    distance: Math.abs(bestPin.centerCol - col)
                });
            }
        }
        candidates.sort(function(a, b) {
            if (a.distance !== b.distance) return a.distance - b.distance;
            if (a.row !== b.row) return a.row - b.row;
            return a.col - b.col;
        });

        var ci;
        for (ci = 0; ci < candidates.length; ci += 1) {
            var pos = candidates[ci];
            var original = state.board[pos.row][pos.col].color;
            var color;
            for (color = 0; color < state.spec.colorCount; color += 1) {
                if (color === original) continue;
                state.board[pos.row][pos.col].color = color;
                if (hasAutoMatches(state.board)) continue;
                if (countProductiveMoves(state) > baseCount) {
                    return {
                        type: "bias",
                        reason: reason,
                        row: pos.row,
                        col: pos.col,
                        color: color
                    };
                }
            }
            state.board[pos.row][pos.col].color = original;
        }
        return null;
    }

    function injectHelper(state, reason) {
        var pin = selectMostNeedyPin(state, Math.floor(state.spec.cols / 2), null);
        if (!pin) return null;
        var targetPos = findHelperSlot(state, pin.centerCol);
        if (!targetPos) return null;
        var helperType = nextFloat(state.rng, "pity") > 0.5 ? "brace" : "calibrator";
        var color = pickHelperColor(state, targetPos.row, targetPos.col);
        state.board[targetPos.row][targetPos.col] = createTile(state, targetPos.row, targetPos.col, color, "special", helperType);
        return {
            type: "helper",
            reason: reason,
            helperType: helperType,
            row: targetPos.row,
            col: targetPos.col,
            pinId: pin.id
        };
    }

    function findHelperSlot(state, centerCol) {
        var row;
        var col;
        var slots = [];
        for (row = 1; row < state.spec.rows - 1; row += 1) {
            for (col = 0; col < state.spec.cols; col += 1) {
                var tile = state.board[row][col];
                if (!tile || tile.kind !== "gem") continue;
                slots.push({
                    row: row,
                    col: col,
                    score: laneWeight(state.spec, { centerCol: centerCol }, col)
                });
            }
        }
        slots.sort(function(a, b) {
            if (b.score !== a.score) return b.score - a.score;
            if (a.row !== b.row) return a.row - b.row;
            return a.col - b.col;
        });
        return slots.length ? slots[0] : null;
    }

    function pickHelperColor(state, row, col) {
        var left = getColor(state.board, row, Math.max(0, col - 1));
        var right = getColor(state.board, row, Math.min(state.spec.cols - 1, col + 1));
        var up = getColor(state.board, Math.max(0, row - 1), col);
        if (left !== null && left === right) return left;
        if (left !== null) return left;
        if (up !== null) return up;
        return nextInt(state.rng, "pity", state.spec.colorCount);
    }

    function hasAutoMatches(board) {
        return findMatches(board).groups.length > 0;
    }

    function serializeReplay(state) {
        return {
            specId: state.spec.id,
            masterSeed: state.masterSeed,
            actions: cloneJson(state.actionLog)
        };
    }

    function replayFromLog(spec, seed, log) {
        var state = createState(spec, seed);
        var actions = log && log.actions ? log.actions : log || [];
        var i;
        for (i = 0; i < actions.length; i += 1) {
            var action = actions[i];
            if (action.type === "armClamp") {
                armClamp(state);
            } else if (action.type === "swap") {
                internalTrySwap(state, action.from, action.to, {});
            }
            if (state.status !== "ongoing") break;
        }
        return state;
    }

    function computeStateHash(state) {
        var payload = JSON.stringify({
            board: snapshotBoard(state.board),
            pins: snapshotPins(state.pins),
            alertRemaining: state.alertRemaining,
            clampCharge: state.clampCharge,
            clampArmed: state.clampArmed,
            status: state.status,
            moveIndex: state.moveIndex,
            reshuffleCount: state.reshuffleCount,
            telemetry: state.telemetry
        });
        return fnv1a(payload);
    }

    function fnv1a(str) {
        var hash = 2166136261;
        var i;
        for (i = 0; i < str.length; i += 1) {
            hash ^= str.charCodeAt(i);
            hash = Math.imul(hash, 16777619);
        }
        return (hash >>> 0).toString(16);
    }

    function chooseSimulationMove(state, policy) {
        var productive = listProductiveMoves(state);
        if (productive.length) {
            if (policy === "random") {
                return productive[nextInt(state.rng, "cosmeticFx", productive.length)];
            }
            return productive[0];
        }
        var legal = listLegalMoves(state);
        if (!legal.length) return null;
        if (policy === "random") {
            return legal[nextInt(state.rng, "cosmeticFx", legal.length)];
        }
        return legal[0];
    }

    function runSimulation(spec, options) {
        var normalized = normalizeSpec(spec);
        var simOptions = mergeObject(normalized.simulation, options || {});
        var wins = 0;
        var totalAlert = 0;
        var totalJam = 0;
        var totalDensity = 0;
        var totalPityRate = 0;
        var badSeeds = [];
        var index;
        for (index = 0; index < simOptions.iterations; index += 1) {
            var seed = String(simOptions.masterSeedPrefix || normalized.id) + "-" + index;
            var state = createState(normalized, seed);
            var turns = 0;
            while (state.status === "ongoing" && turns < simOptions.maxTurns) {
                var move = chooseSimulationMove(state, simOptions.policy || "greedy");
                if (!move) break;
                if (state.clampCharge >= state.spec.clamp.cost && hasSetPin(state)) {
                    armClamp(state);
                }
                internalTrySwap(state, move.from, move.to, {});
                turns += 1;
            }
            if (state.status === "win") wins += 1;
            totalAlert += state.alertRemaining;
            totalJam += state.telemetry.jamCount;
            totalDensity += state.telemetry.legalSwaps ? (state.telemetry.productiveSwaps / state.telemetry.legalSwaps) : 0;
            totalPityRate += turns ? (state.telemetry.pityTriggers / turns) : 0;
            if (state.status !== "win" && badSeeds.length < simOptions.badSeedLimit) {
                badSeeds.push({
                    seed: seed,
                    finalStatus: state.status,
                    alertRemaining: state.alertRemaining,
                    jamCount: state.telemetry.jamCount,
                    productiveDensity: state.telemetry.legalSwaps ? (state.telemetry.productiveSwaps / state.telemetry.legalSwaps) : 0
                });
            }
        }

        return {
            specId: normalized.id,
            iterations: simOptions.iterations,
            policy: simOptions.policy || "greedy",
            winRate: Number((wins / simOptions.iterations).toFixed(4)),
            avgAlertRemaining: Number((totalAlert / simOptions.iterations).toFixed(3)),
            avgJamCount: Number((totalJam / simOptions.iterations).toFixed(3)),
            productiveMoveDensity: Number((totalDensity / simOptions.iterations).toFixed(4)),
            pityTriggerRate: Number((totalPityRate / simOptions.iterations).toFixed(4)),
            badSeeds: badSeeds
        };
    }

    return {
        STREAM_NAMES: STREAM_NAMES,
        SPECIAL_TYPES: SPECIAL_TYPES,
        OBSTACLE_TYPES: OBSTACLE_TYPES,
        DEFAULT_SPEC: DEFAULT_SPEC,
        normalizeSpec: normalizeSpec,
        createSeededRngPipeline: createSeededRngPipeline,
        laneWeight: laneWeight,
        createState: createState,
        beginPlayerMove: beginPlayerMove,
        armClamp: armClamp,
        trySwap: trySwap,
        previewSwap: previewSwap,
        countProductiveMoves: countProductiveMoves,
        getHint: getHint,
        runSimulation: runSimulation,
        serializeReplay: serializeReplay,
        replayFromLog: replayFromLog,
        snapshotState: snapshotState,
        snapshotBoard: snapshotBoard,
        snapshotPins: snapshotPins,
        computeStateHash: computeStateHash,
        hasAutoMatches: hasAutoMatches,
        reshuffleOrPity: postMoveMaintenance,
        listProductiveMoves: listProductiveMoves
    };
});
