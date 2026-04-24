(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.GobangCore = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var SIZE = 15;
    var BLACK = 1;
    var WHITE = -1;
    var EMPTY = 0;
    var DIRECTIONS = [
        { dr: 0, dc: 1 },
        { dr: 1, dc: 0 },
        { dr: 1, dc: 1 },
        { dr: 1, dc: -1 }
    ];

    var RULESETS = {
        casual: {
            id: "casual",
            title: "休闲",
            blackForbidden: false,
            blackOverlineWins: true,
            whiteOverlineWins: true
        },
        renju: {
            id: "renju",
            title: "竞技",
            blackForbidden: true,
            blackOverlineWins: false,
            whiteOverlineWins: true
        }
    };

    var DIFFICULTIES = {
        fast: { id: "fast", title: "快速", timeLimit: 300 },
        normal: { id: "normal", title: "普通", timeLimit: 1000 },
        hard: { id: "hard", title: "困难", timeLimit: 3000 },
        master: { id: "master", title: "大师", timeLimit: 5000 }
    };

    function cloneJson(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function normalizeRuleset(id) {
        return RULESETS[id] ? id : "casual";
    }

    function normalizeDifficulty(id) {
        return DIFFICULTIES[id] ? id : "normal";
    }

    function normalizeRole(role, fallback) {
        return role === WHITE ? WHITE : (role === BLACK ? BLACK : fallback);
    }

    function idx(row, col) {
        return row * SIZE + col;
    }

    function inBounds(row, col) {
        return row >= 0 && row < SIZE && col >= 0 && col < SIZE;
    }

    function roleName(role) {
        return role === BLACK ? "黑棋" : "白棋";
    }

    function roleClass(role) {
        return role === BLACK ? "black" : (role === WHITE ? "white" : "empty");
    }

    function otherRole(role) {
        return role === BLACK ? WHITE : BLACK;
    }

    function createEmptyBoard() {
        var out = new Array(SIZE * SIZE);
        var i;
        for (i = 0; i < out.length; i += 1) out[i] = EMPTY;
        return out;
    }

    function createState(options) {
        var opts = options || {};
        var ruleset = normalizeRuleset(opts.ruleset || "casual");
        var difficulty = normalizeDifficulty(opts.difficulty || "normal");
        var playerRole = normalizeRole(opts.playerRole, BLACK);
        var aiEnabled = opts.aiEnabled !== false;
        var state = {
            size: SIZE,
            board: createEmptyBoard(),
            moves: [],
            currentRole: BLACK,
            playerRole: playerRole,
            aiRole: otherRole(playerRole),
            aiEnabled: aiEnabled,
            ruleset: ruleset,
            difficulty: difficulty,
            timeLimit: DIFFICULTIES[difficulty].timeLimit,
            status: "playing",
            winner: 0,
            lastMove: null,
            forbidden: null,
            aiError: "",
            createdAt: Date.now()
        };
        return state;
    }

    function cloneState(state) {
        return cloneJson(state);
    }

    function getCell(board, row, col) {
        if (!inBounds(row, col)) return null;
        return board[idx(row, col)];
    }

    function setCell(board, row, col, role) {
        board[idx(row, col)] = role;
    }

    function countInDirection(board, row, col, role, dr, dc) {
        var count = 0;
        var r = row + dr;
        var c = col + dc;
        while (inBounds(r, c) && getCell(board, r, c) === role) {
            count += 1;
            r += dr;
            c += dc;
        }
        return count;
    }

    function lineLength(board, row, col, role, dir) {
        return 1
            + countInDirection(board, row, col, role, dir.dr, dir.dc)
            + countInDirection(board, row, col, role, -dir.dr, -dir.dc);
    }

    function maxLineLength(board, row, col, role) {
        var best = 1;
        var i;
        for (i = 0; i < DIRECTIONS.length; i += 1) {
            best = Math.max(best, lineLength(board, row, col, role, DIRECTIONS[i]));
        }
        return best;
    }

    function hasAnyFive(board, row, col, role, rulesetId) {
        var rules = RULESETS[normalizeRuleset(rulesetId)];
        var i;
        for (i = 0; i < DIRECTIONS.length; i += 1) {
            var len = lineLength(board, row, col, role, DIRECTIONS[i]);
            if (role === BLACK && rules.blackForbidden && !rules.blackOverlineWins) {
                if (len === 5) return true;
            } else if (len >= 5) {
                return true;
            }
        }
        return false;
    }

    function createsExactFive(board, row, col, role) {
        var i;
        for (i = 0; i < DIRECTIONS.length; i += 1) {
            if (lineLength(board, row, col, role, DIRECTIONS[i]) === 5) return true;
        }
        return false;
    }

    function isOverline(board, row, col, role) {
        var i;
        for (i = 0; i < DIRECTIONS.length; i += 1) {
            if (lineLength(board, row, col, role, DIRECTIONS[i]) > 5) return true;
        }
        return false;
    }

    function lineSlots(row, col, dir, radius) {
        var out = [];
        var k;
        for (k = -radius; k <= radius; k += 1) {
            out.push({ row: row + dir.dr * k, col: col + dir.dc * k });
        }
        return out;
    }

    function getLinearValue(board, row, col) {
        if (!inBounds(row, col)) return 2;
        return getCell(board, row, col);
    }

    function hasStraightOpenFourInDirection(board, row, col, role, dir) {
        var slots = lineSlots(row, col, dir, 5);
        var values = [];
        var i;
        for (i = 0; i < slots.length; i += 1) {
            values.push(getLinearValue(board, slots[i].row, slots[i].col));
        }
        for (i = 0; i <= values.length - 6; i += 1) {
            if (values[i] !== EMPTY || values[i + 5] !== EMPTY) continue;
            if (
                values[i + 1] === role &&
                values[i + 2] === role &&
                values[i + 3] === role &&
                values[i + 4] === role
            ) {
                return true;
            }
        }
        return false;
    }

    function directionHasFourThreat(board, row, col, role, dir) {
        var k;
        for (k = -4; k <= 4; k += 1) {
            if (k === 0) continue;
            var r = row + dir.dr * k;
            var c = col + dir.dc * k;
            if (!inBounds(r, c) || getCell(board, r, c) !== EMPTY) continue;
            setCell(board, r, c, role);
            var makesFive = createsExactFive(board, r, c, role);
            setCell(board, r, c, EMPTY);
            if (makesFive) return true;
        }
        return false;
    }

    function directionHasOpenThreeThreat(board, row, col, role, dir) {
        var k;
        for (k = -4; k <= 4; k += 1) {
            if (k === 0) continue;
            var r = row + dir.dr * k;
            var c = col + dir.dc * k;
            if (!inBounds(r, c) || getCell(board, r, c) !== EMPTY) continue;
            setCell(board, r, c, role);
            var hasOpenFour = hasStraightOpenFourInDirection(board, r, c, role, dir);
            setCell(board, r, c, EMPTY);
            if (hasOpenFour) return true;
        }
        return false;
    }

    function countThreatDirections(board, row, col, role, kind) {
        var count = 0;
        var i;
        for (i = 0; i < DIRECTIONS.length; i += 1) {
            var ok = kind === "four"
                ? directionHasFourThreat(board, row, col, role, DIRECTIONS[i])
                : directionHasOpenThreeThreat(board, row, col, role, DIRECTIONS[i]);
            if (ok) count += 1;
        }
        return count;
    }

    function inspectForbiddenAfterMove(board, row, col, role, rulesetId) {
        if (normalizeRuleset(rulesetId) !== "renju" || role !== BLACK) {
            return { forbidden: false, reason: "" };
        }
        if (hasAnyFive(board, row, col, role, "renju")) {
            return { forbidden: false, reason: "" };
        }
        if (isOverline(board, row, col, role)) {
            return { forbidden: true, reason: "overline" };
        }
        var fourDirs = countThreatDirections(board, row, col, role, "four");
        if (fourDirs >= 2) {
            return { forbidden: true, reason: "double_four", count: fourDirs };
        }
        var threeDirs = countThreatDirections(board, row, col, role, "three");
        if (threeDirs >= 2) {
            return { forbidden: true, reason: "double_three", count: threeDirs };
        }
        return { forbidden: false, reason: "" };
    }

    function validateMove(state, row, col, role) {
        if (!state || !state.board) return { valid: false, reason: "state" };
        if (state.status !== "playing") return { valid: false, reason: "status" };
        if (!inBounds(row, col)) return { valid: false, reason: "bounds" };
        if (getCell(state.board, row, col) !== EMPTY) return { valid: false, reason: "occupied" };
        var nextRole = normalizeRole(role, state.currentRole);
        var board = state.board.slice();
        setCell(board, row, col, nextRole);
        var forbidden = inspectForbiddenAfterMove(board, row, col, nextRole, state.ruleset);
        if (forbidden.forbidden) {
            return { valid: false, reason: forbidden.reason, forbidden: forbidden };
        }
        return { valid: true, role: nextRole };
    }

    function applyMove(state, row, col, role, source) {
        var check = validateMove(state, row, col, role);
        if (!check.valid) return check;
        var moveRole = check.role;
        setCell(state.board, row, col, moveRole);
        var move = {
            row: row,
            col: col,
            role: moveRole,
            source: source || "player",
            moveNumber: state.moves.length + 1
        };
        state.moves.push(move);
        state.lastMove = move;
        state.forbidden = null;
        state.aiError = "";

        if (hasAnyFive(state.board, row, col, moveRole, state.ruleset)) {
            state.status = "win";
            state.winner = moveRole;
        } else if (state.moves.length >= SIZE * SIZE) {
            state.status = "draw";
            state.winner = 0;
        } else {
            state.currentRole = otherRole(moveRole);
        }
        return { valid: true, move: move, status: state.status, winner: state.winner };
    }

    function undo(state, count) {
        var n = Math.max(1, count || 1);
        var removed = [];
        while (n > 0 && state.moves.length > 0) {
            var move = state.moves.pop();
            setCell(state.board, move.row, move.col, EMPTY);
            removed.push(move);
            n -= 1;
        }
        state.status = "playing";
        state.winner = 0;
        state.forbidden = null;
        state.aiError = "";
        state.lastMove = state.moves.length ? state.moves[state.moves.length - 1] : null;
        state.currentRole = state.moves.length ? otherRole(state.lastMove.role) : BLACK;
        return removed;
    }

    function toEngineMoves(state) {
        var out = [];
        var i;
        for (i = 0; i < state.moves.length; i += 1) {
            out.push([state.moves[i].row, state.moves[i].col, state.moves[i].role]);
        }
        return out;
    }

    function getMetrics(state) {
        return {
            size: SIZE,
            moves: state.moves.length,
            status: state.status,
            winner: state.winner,
            ruleset: state.ruleset,
            difficulty: state.difficulty,
            timeLimit: state.timeLimit,
            aiEnabled: !!state.aiEnabled
        };
    }

    function serialize(state) {
        return {
            version: 1,
            size: SIZE,
            ruleset: state.ruleset,
            difficulty: state.difficulty,
            playerRole: state.playerRole,
            aiEnabled: !!state.aiEnabled,
            currentRole: state.currentRole,
            status: state.status,
            winner: state.winner,
            moves: cloneJson(state.moves)
        };
    }

    function buildSessionExport(state) {
        return {
            Meta: {
                game: "gobang",
                version: 1,
                exportedAt: new Date().toISOString()
            },
            Session: serialize(state),
            Metrics: getMetrics(state)
        };
    }

    function forbiddenLabel(reason) {
        if (reason === "overline") return "长连禁手";
        if (reason === "double_four") return "双四禁手";
        if (reason === "double_three") return "双三禁手";
        if (reason === "occupied") return "已有棋子";
        if (reason === "bounds") return "越界";
        if (reason === "status") return "棋局已结束";
        return "非法落子";
    }

    return {
        SIZE: SIZE,
        BLACK: BLACK,
        WHITE: WHITE,
        EMPTY: EMPTY,
        RULESETS: cloneJson(RULESETS),
        DIFFICULTIES: cloneJson(DIFFICULTIES),
        createState: createState,
        cloneState: cloneState,
        getCell: getCell,
        idx: idx,
        inBounds: inBounds,
        roleName: roleName,
        roleClass: roleClass,
        otherRole: otherRole,
        normalizeRuleset: normalizeRuleset,
        normalizeDifficulty: normalizeDifficulty,
        validateMove: validateMove,
        applyMove: applyMove,
        undo: undo,
        toEngineMoves: toEngineMoves,
        getMetrics: getMetrics,
        serialize: serialize,
        buildSessionExport: buildSessionExport,
        forbiddenLabel: forbiddenLabel,
        inspectForbiddenAfterMove: inspectForbiddenAfterMove,
        maxLineLength: maxLineLength
    };
});
