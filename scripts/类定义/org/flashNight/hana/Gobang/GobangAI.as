import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangMinmax;
import org.flashNight.hana.Gobang.GobangConfig;
import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangBook;

class org.flashNight.hana.Gobang.GobangAI {
    private var _board:GobangBoard;
    private var _eval:GobangEval;
    private var _minmax:GobangMinmax;
    private var _aiRole:Number;
    private var _difficulty:Number;  // 0-100，100=最强

    private var _openingMove:Object;
    private var _asyncParams:Object;

    // 难度映射表 [difficulty 下限, searchDepth, pointsLimit, 最优走法概率(%), enableVCT]
    private static var DIFFICULTY_TABLE:Array = [
        [0,   2,  5,  30, false],
        [21,  2,  8,  50, false],
        [41,  2,  12, 70, false],
        [61,  4,  14, 90, true],
        [81,  8,  18, 100, true]
    ];
    // 搜索分超过此阈值时跳过 refine（TSS/VCF 必胜 >= 2M，正常 eval < 100K）
    private static var REFINE_SKIP_SCORE:Number = 1000000;
    private static var STRATEGIC_REFINE_MIN_HISTORY:Number = 10;
    private static var STRATEGIC_REFINE_MARGIN:Number = 48;
    private static var STRATEGIC_BRIDGE_MIN_SCORE:Number = 18;
    private static var STRATEGIC_BRIDGE_WEIGHT:Number = 2;
    private static var STRATEGIC_BLOCK_BRIDGE_WEIGHT:Number = 3;
    private static var STRATEGIC_FUTURE_WEIGHT:Number = 4;
    private static var STRATEGIC_FUTURE_DEF_WEIGHT:Number = 3;
    private static var THREAT_REFINE_MIN_HISTORY:Number = 6;
    private static var THREAT_REFINE_MARGIN:Number = 24;
    private static var THREAT_REFINE_PLY:Number = 5;
    private static var THREAT_REFINE_DEEP_PLY:Number = 7;
    private static var THREAT_TRIGGER_PROBE_BUDGET_MS:Number = 4;
    private static var THREAT_REFINE_PROBE_BUDGET_MS:Number = 6;
    private static var THREAT_REFINE_FORCE_LOSS_PENALTY:Number = 4000000;
    private static var THREAT_REFINE_FOUR_PENALTY:Number = 250000;
    private static var THREAT_REFINE_THREE_PENALTY:Number = 24000;
    private static var THREAT_REFINE_FOUR_BONUS:Number = 16;
    private static var THREAT_REFINE_THREE_BONUS:Number = 8;
    private static var THREAT_REFINE_DEF_BRIDGE_WEIGHT:Number = 4;
    private static var THREAT_REFINE_OWN_BRIDGE_WEIGHT:Number = 4;
    private static var THREAT_REFINE_OPP_BRIDGE_WEIGHT:Number = 24;
    private static var THREAT_REFINE_OPP_BRIDGE_SECOND_WEIGHT:Number = 12;
    private static var THREAT_REFINE_DANGEROUS_BRIDGE_SCORE:Number = 32;
    private static var THREAT_REFINE_DANGEROUS_BRIDGE_PENALTY:Number = 120000;
    private static var THREAT_REFINE_MULTI_BRIDGE_PENALTY:Number = 60000;
    private static var THREAT_REFINE_MAJOR_THREAT_PENALTY:Number = 36000;
    private static var THREAT_REFINE_MULTI_THREAT_PENALTY:Number = 90000;

    public function GobangAI(aiRole:Number, difficulty:Number) {
        if (aiRole === undefined) aiRole = -1;
        if (difficulty === undefined) difficulty = 100;
        _aiRole = aiRole;
        _difficulty = difficulty;
        reset();
    }

    public function reset():Void {
        _board = new GobangBoard(15, 1);
        _eval = new GobangEval(15);
        _minmax = new GobangMinmax(_board, _eval);
        _openingMove = null;
        _asyncParams = null;
    }

    public function setDifficulty(d:Number):Void {
        _difficulty = d;
    }

    public function getDifficulty():Number {
        return _difficulty;
    }

    private function getDifficultyParams(frameBudgetMs:Number):Object {
        if (frameBudgetMs === undefined) frameBudgetMs = 9999;
        var row:Array = DIFFICULTY_TABLE[0];
        for (var i:Number = DIFFICULTY_TABLE.length - 1; i >= 0; i--) {
            if (_difficulty >= DIFFICULTY_TABLE[i][0]) {
                row = DIFFICULTY_TABLE[i];
                break;
            }
        }

        var depth:Number = row[1];
        var pl:Number = row[2];
        var enableVCT:Boolean = row[4];
        var pieces:Number = _board.history.length;
        var urgentFourMoves:Array = null;
        var urgentThreeMoves:Array = null;
        if (pieces >= 5) {
            var hasForcedThreat:Boolean = _minmax.probeTSSWithBudget(-_aiRole, THREAT_REFINE_PLY,
                THREAT_TRIGGER_PROBE_BUDGET_MS);
            var opponentThreatMoves:Array = _eval.getThreatMoves(-_aiRole, 3, 2);
            if (hasForcedThreat) {
                urgentFourMoves = _eval.getMoves(_aiRole, 0, false, true);
            } else {
                urgentFourMoves = [];
            }
            if (opponentThreatMoves.length > 0) {
                urgentThreeMoves = _eval.getMoves(_aiRole, 0, true, false);
            } else {
                urgentThreeMoves = [];
            }
        }

        // 候选数限制（按棋局阶段）
        if (pieces < 4) {
            if (pl > 8) pl = 8;
        } else if (pieces < 10) {
            if (pl > 10) pl = 10;
        } else if (pieces < 18 && pl > 12) {
            pl = 12;
        }

        // 帧预算：常态 depth=6（看 3 步己方走法，识别冲四陷阱），战术加深到 8
        if (frameBudgetMs <= 8) {
            if (depth > 6) depth = 6;
            if (pl > 8) pl = 8;
            // 战术条件加深到 8
            if (urgentFourMoves !== null && urgentFourMoves.length > 0 && urgentFourMoves.length <= 4) {
                depth = 8;
                if (pl > 4) pl = 4;
                if (pieces >= 8) enableVCT = true;
            } else if (urgentThreeMoves !== null && urgentThreeMoves.length > 0 && urgentThreeMoves.length <= 6) {
                depth = 8;
                if (pl > 4) pl = 4;
            }
        } else if (frameBudgetMs <= 16) {
            if (depth > 6) depth = 6;
            if (pl > 10) pl = 10;
            if (urgentFourMoves !== null && urgentFourMoves.length > 0 && urgentFourMoves.length <= 6) {
                depth = 8;
                if (pl > 4) pl = 4;
                if (pieces >= 8) enableVCT = true;
            } else if (urgentThreeMoves !== null && urgentThreeMoves.length > 0 && urgentThreeMoves.length <= 8) {
                depth = 6;
                if (pl > 6) pl = 6;
            }
        }

        return {
            searchDepth: depth,
            pointsLimit: pl,
            bestProb: row[3],
            enableVCT: enableVCT
        };
    }

    public function playerMove(x:Number, y:Number):Boolean {
        var role:Number = _board.role;
        if (role === _aiRole) return false;
        if (!_board.put(x, y, role)) return false;
        _eval.move(x, y, role);
        return true;
    }

    private function _pickAlternativeMove(bestX:Number, bestY:Number):Object {
        var moves:Array = _eval.getMoves(_aiRole, 0, false, false);
        var options:Array = [];
        for (var i:Number = 0; i < moves.length && options.length < 3; i++) {
            if (moves[i][0] === bestX && moves[i][1] === bestY) continue;
            options.push(moves[i]);
        }
        if (!options.length) return null;
        var pickIdx:Number = Math.floor(Math.random() * options.length);
        return {x: options[pickIdx][0], y: options[pickIdx][1]};
    }

    private function _applyDifficultyDrop(params:Object, bestX:Number, bestY:Number, score:Number):Object {
        var finalX:Number = bestX;
        var finalY:Number = bestY;
        if (params.bestProb < 100 && score < GobangShape.FIVE_SCORE) {
            var roll:Number = Math.random() * 100;
            if (roll >= params.bestProb) {
                var alt:Object = _pickAlternativeMove(bestX, bestY);
                if (alt !== null) {
                    finalX = alt.x;
                    finalY = alt.y;
                }
            }
        }
        return {x: finalX, y: finalY};
    }

    private function _scoreStrategicCandidate(x:Number, y:Number):Number {
        _board.put(x, y, _aiRole);
        _eval.move(x, y, _aiRole);

        var score:Number = _eval.evaluate(_aiRole);
        var own:Array = _eval.getBridgeMoves(_aiRole, 1, true);
        if (own.length > 0) {
            score += own[0][2] * STRATEGIC_FUTURE_WEIGHT;
        }
        var opp:Array = _eval.getBridgeMoves(-_aiRole, 1, true);
        if (opp.length > 0) {
            score -= opp[0][2] * STRATEGIC_FUTURE_DEF_WEIGHT;
        }

        _eval.undo(x, y);
        _board.undo();
        return score;
    }

    private function _appendStrategicCandidate(candidates:Array, x:Number, y:Number, bonus:Number):Void {
        if (x < 0 || y < 0) return;
        for (var i:Number = 0; i < candidates.length; i++) {
            if (candidates[i][0] === x && candidates[i][1] === y) {
                if (bonus > candidates[i][2]) candidates[i][2] = bonus;
                return;
            }
        }
        candidates[candidates.length] = [x, y, bonus];
    }

    private function _refineStrategicMove(params:Object, result:Object):Object {
        if (params === null || result === null || result.x < 0) return result;
        if (result.score >= REFINE_SKIP_SCORE) return result;
        if (params.searchDepth > 6 || params.enableVCT || _board.history.length < STRATEGIC_REFINE_MIN_HISTORY) {
            return result;
        }

        var candidates:Array = [];
        var atk:Array = _eval.getBridgeMoves(_aiRole, 3, true);
        var def:Array = _eval.getBridgeMoves(-_aiRole, 4, true);
        for (var ai:Number = 0; ai < atk.length; ai++) {
            if (atk[ai][2] >= STRATEGIC_BRIDGE_MIN_SCORE) {
                _appendStrategicCandidate(candidates, atk[ai][0], atk[ai][1], atk[ai][2] * STRATEGIC_BRIDGE_WEIGHT);
            }
        }
        for (var di:Number = 0; di < def.length; di++) {
            if (def[di][2] >= STRATEGIC_BRIDGE_MIN_SCORE) {
                _appendStrategicCandidate(candidates, def[di][0], def[di][1], def[di][2] * STRATEGIC_BLOCK_BRIDGE_WEIGHT);
            }
        }
        if (!candidates.length) return result;

        var bestX:Number = result.x;
        var bestY:Number = result.y;
        var bestSearchScore:Number = result.score;
        var bestStrategicScore:Number = _scoreStrategicCandidate(bestX, bestY);
        var changed:Boolean = false;

        for (var i:Number = 0; i < candidates.length; i++) {
            var bx:Number = candidates[i][0];
            var by:Number = candidates[i][1];
            if (bx === bestX && by === bestY) continue;

            var strategicScore:Number = _scoreStrategicCandidate(bx, by) + candidates[i][2];
            if (strategicScore > bestStrategicScore + STRATEGIC_REFINE_MARGIN) {
                bestStrategicScore = strategicScore;
                bestX = bx;
                bestY = by;
                bestSearchScore = strategicScore;
                changed = true;
            }
        }

        if (!changed) return result;
        var refined:Object = {};
        for (var k:String in result) {
            refined[k] = result[k];
        }
        refined.x = bestX;
        refined.y = bestY;
        refined.score = bestSearchScore;
        if (result.phaseLabel !== undefined) {
            refined.phaseLabel = String(result.phaseLabel) + "_bridge";
        }
        return refined;
    }

    private function _scoreThreatDefenseCandidate(x:Number, y:Number, bonus:Number,
            probePly:Number, probeBudgetMs:Number):Object {
        _board.put(x, y, _aiRole);
        _eval.move(x, y, _aiRole);

        var actualProbePly:Number = probePly;
        var score:Number = _eval.evaluate(_aiRole) + bonus;
        var ownBridge:Array = _eval.getBridgeMoves(_aiRole, 1, true);
        if (ownBridge.length > 0) {
            score += ownBridge[0][2] * THREAT_REFINE_OWN_BRIDGE_WEIGHT;
        }
        var oppBridge:Array = _eval.getBridgeMoves(-_aiRole, 2, true);
        if (oppBridge.length > 0) {
            score -= oppBridge[0][2] * THREAT_REFINE_OPP_BRIDGE_WEIGHT;
            if (oppBridge[0][2] >= THREAT_REFINE_DANGEROUS_BRIDGE_SCORE) {
                score -= THREAT_REFINE_DANGEROUS_BRIDGE_PENALTY;
                actualProbePly = THREAT_REFINE_DEEP_PLY;
            }
            if (oppBridge.length > 1) {
                score -= oppBridge[1][2] * THREAT_REFINE_OPP_BRIDGE_SECOND_WEIGHT;
                if (oppBridge[1][2] >= THREAT_REFINE_DANGEROUS_BRIDGE_SCORE) {
                    score -= THREAT_REFINE_MULTI_BRIDGE_PENALTY;
                    actualProbePly = THREAT_REFINE_DEEP_PLY;
                }
            }
        }

        var oppThreatMoves:Array = _eval.getThreatMoves(-_aiRole, 3, 4);
        if (oppThreatMoves.length > 0) {
            score -= oppThreatMoves.length * THREAT_REFINE_MAJOR_THREAT_PENALTY;
            if (oppThreatMoves.length >= 2) {
                score -= THREAT_REFINE_MULTI_THREAT_PENALTY;
                actualProbePly = THREAT_REFINE_DEEP_PLY;
            }
        }

        var oppOnlyFour:Array = _eval.getMoves(-_aiRole, 0, false, true);
        if (oppOnlyFour.length > 0) {
            score -= THREAT_REFINE_FOUR_PENALTY + oppOnlyFour.length * 512;
            actualProbePly = THREAT_REFINE_DEEP_PLY;
        } else {
            var oppOnlyThree:Array = _eval.getMoves(-_aiRole, 0, true, false);
            if (oppOnlyThree.length > 0 && oppOnlyThree.length <= 6) {
                score -= oppOnlyThree.length * THREAT_REFINE_THREE_PENALTY;
            }
        }

        var forcedLoss:Boolean = _minmax.probeTSSWithBudget(-_aiRole, actualProbePly, probeBudgetMs);
        if (forcedLoss) {
            score -= THREAT_REFINE_FORCE_LOSS_PENALTY;
        }

        _eval.undo(x, y);
        _board.undo();
        return {score: score, forcedLoss: forcedLoss};
    }

    private function _refineThreatDefenseMove(params:Object, result:Object):Object {
        if (params === null || result === null || result.x < 0) return result;
        if (result.score >= REFINE_SKIP_SCORE) return result;
        if (_board.history.length < THREAT_REFINE_MIN_HISTORY || params.searchDepth > 6) {
            return result;
        }

        var urgentFour:Array = [];
        if (_minmax.probeTSSWithBudget(-_aiRole, THREAT_REFINE_PLY, THREAT_TRIGGER_PROBE_BUDGET_MS)) {
            urgentFour = _eval.getMoves(_aiRole, 0, false, true);
        }
        var urgentThree:Array = [];
        if (_eval.getThreatMoves(-_aiRole, 3, 2).length > 0) {
            urgentThree = _eval.getMoves(_aiRole, 0, true, false);
        }
        var defBridge:Array = _eval.getBridgeMoves(-_aiRole, 3, true);
        var hasUrgentFour:Boolean = (urgentFour.length > 0 && urgentFour.length <= 6);
        var hasUrgentThree:Boolean = (urgentThree.length > 0 && urgentThree.length <= 6);
        var hasDefBridge:Boolean = false;
        for (var bi:Number = 0; bi < defBridge.length; bi++) {
            if (defBridge[bi][2] >= STRATEGIC_BRIDGE_MIN_SCORE) {
                hasDefBridge = true;
                break;
            }
        }
        if (!hasUrgentFour && !hasUrgentThree && !hasDefBridge) {
            return result;
        }

        var candidates:Array = [];
        _appendStrategicCandidate(candidates, result.x, result.y, 0);

        if (hasUrgentFour) {
            for (var fi:Number = 0; fi < urgentFour.length && fi < 3; fi++) {
                _appendStrategicCandidate(candidates, urgentFour[fi][0], urgentFour[fi][1], THREAT_REFINE_FOUR_BONUS);
            }
        }
        if (hasUrgentThree && !hasDefBridge) {
            for (var ti:Number = 0; ti < urgentThree.length && ti < 2; ti++) {
                _appendStrategicCandidate(candidates, urgentThree[ti][0], urgentThree[ti][1], THREAT_REFINE_THREE_BONUS);
            }
        }
        if (hasDefBridge) {
            for (var di:Number = 0; di < defBridge.length; di++) {
                if (defBridge[di][2] < STRATEGIC_BRIDGE_MIN_SCORE) continue;
                _appendStrategicCandidate(candidates, defBridge[di][0], defBridge[di][1],
                    defBridge[di][2] * THREAT_REFINE_DEF_BRIDGE_WEIGHT);
            }
        }
        if (candidates.length < 2) return result;

        var probePly:Number = hasUrgentFour ? THREAT_REFINE_DEEP_PLY : THREAT_REFINE_PLY;
        var bestX:Number = result.x;
        var bestY:Number = result.y;
        var bestInfo:Object = _scoreThreatDefenseCandidate(bestX, bestY, candidates[0][2],
            probePly, THREAT_REFINE_PROBE_BUDGET_MS);
        var changed:Boolean = false;

        for (var i:Number = 0; i < candidates.length; i++) {
            var cx:Number = candidates[i][0];
            var cy:Number = candidates[i][1];
            if (cx === bestX && cy === bestY) continue;

            var info:Object = _scoreThreatDefenseCandidate(cx, cy, candidates[i][2],
                probePly, THREAT_REFINE_PROBE_BUDGET_MS);
            if (bestInfo.forcedLoss && !info.forcedLoss) {
                bestInfo = info;
                bestX = cx;
                bestY = cy;
                changed = true;
                continue;
            }
            if (!bestInfo.forcedLoss && info.forcedLoss) {
                continue;
            }
            if (info.score > bestInfo.score + THREAT_REFINE_MARGIN) {
                bestInfo = info;
                bestX = cx;
                bestY = cy;
                changed = true;
            }
        }

        if (!changed) return result;
        var refined:Object = {};
        for (var k:String in result) {
            refined[k] = result[k];
        }
        refined.x = bestX;
        refined.y = bestY;
        refined.score = bestInfo.score;
        if (result.phaseLabel !== undefined) {
            refined.phaseLabel = String(result.phaseLabel) + "_threat";
        }
        return refined;
    }

    public function aiMove():Object {
        if (_board.role !== _aiRole) return null;
        if (_board.isGameOver()) return null;

        var opening:Object = _lookupOpening();
        if (opening !== null) {
            _board.put(opening.x, opening.y, _aiRole);
            _eval.move(opening.x, opening.y, _aiRole);
            return {x: opening.x, y: opening.y, score: 0};
        }

        var params:Object = getDifficultyParams();
        var origPL:Number = GobangConfig.pointsLimit;
        GobangConfig.pointsLimit = params.pointsLimit;

        var result:Object = _minmax.search(_aiRole, params.searchDepth, params.enableVCT);
        if (result.x < 0) {
            GobangConfig.pointsLimit = origPL;
            return null;
        }

        result = _refineStrategicMove(params, result);
        result = _refineThreatDefenseMove(params, result);

        var move:Object = _applyDifficultyDrop(params, result.x, result.y, result.score);
        GobangConfig.pointsLimit = origPL;

        _board.put(move.x, move.y, _aiRole);
        _eval.move(move.x, move.y, _aiRole);
        return {x: move.x, y: move.y, score: result.score};
    }

    public function undo():Boolean {
        if (_board.history.length === 0) return false;
        var last:Object = _board.history[_board.history.length - 1];
        _eval.undo(last.i, last.j);
        _board.undo();
        return true;
    }

    public function getBoard():Array {
        return _board.board;
    }

    public function getHistory():Array {
        return _board.history;
    }

    public function getHistoryLength():Number {
        return _board.history.length;
    }

    public function getCurrentRole():Number {
        return _board.role;
    }

    public function isGameOver():Boolean {
        return _board.isGameOver();
    }

    public function getWinner():Number {
        return _board.getWinner();
    }

    // ===== 开局库 =====

    private function _lookupOpening():Object {
        var h:Array = _board.history;
        var n:Number = h.length;
        var c:Number = Math.floor(_board.size / 2);

        // 优先查开局库（8 折对称匹配）
        var bookMove:Object = GobangBook.lookup(h, n);
        if (bookMove !== null) return bookMove;

        if (n === 0) return {x: c, y: c};

        if (n === 1) {
            var ox:Number = h[0].i;
            var oy:Number = h[0].j;
            if (ox === c && oy === c) return {x: c + 1, y: c + 1};
            return {x: c, y: c};
        }

        if (n === 2) {
            var myX:Number;
            var myY:Number;
            var opX:Number;
            var opY:Number;
            if (h[0].role === _aiRole) {
                myX = h[0].i; myY = h[0].j;
                opX = h[1].i; opY = h[1].j;
            } else {
                opX = h[0].i; opY = h[0].j;
                myX = h[1].i; myY = h[1].j;
            }
            var dx:Number = opX - myX;
            var dy:Number = opY - myY;
            var adx:Number = dx < 0 ? -dx : dx;
            var ady:Number = dy < 0 ? -dy : dy;
            if (adx <= 1 && ady <= 1) {
                var nx:Number = myX - dx;
                var ny:Number = myY - dy;
                if (nx >= 0 && nx < _board.size && ny >= 0 && ny < _board.size && _board.board[nx][ny] === 0) {
                    return {x: nx, y: ny};
                }
            }
        }

        return null;
    }

    // ===== 异步 AI 接口 =====

    public function aiMoveStart(frameBudgetMs:Number):Boolean {
        if (frameBudgetMs === undefined) frameBudgetMs = 16;
        if (_board.role !== _aiRole) return false;
        if (_board.isGameOver()) return false;

        _openingMove = _lookupOpening();
        if (_openingMove !== null) {
            _asyncParams = null;
            return true;
        }

        _asyncParams = getDifficultyParams(frameBudgetMs);
        _minmax.searchStart(_aiRole, _asyncParams.searchDepth, _asyncParams.enableVCT);
        return true;
    }

    public function aiMoveStep(frameBudgetMs:Number):Object {
        if (frameBudgetMs === undefined) frameBudgetMs = 16;

        if (_openingMove !== null) {
            var ox:Number = _openingMove.x;
            var oy:Number = _openingMove.y;
            _openingMove = null;
            _board.put(ox, oy, _aiRole);
            _eval.move(ox, oy, _aiRole);
            return {done: true, x: ox, y: oy, score: 0, phaseLabel: "opening",
                    nodes: 0, rootIdx: 0, rootTotal: 0};
        }

        if (_asyncParams === null) {
            return {done: true, x: -1, y: -1, score: 0, phaseLabel: "no_move",
                    nodes: 0, rootIdx: 0, rootTotal: 0};
        }

        var origPL:Number = GobangConfig.pointsLimit;
        GobangConfig.pointsLimit = _asyncParams.pointsLimit;
        var stepResult:Object = _minmax.step(frameBudgetMs);

        if (!stepResult.done) {
            GobangConfig.pointsLimit = origPL;
            return stepResult;
        }

        if (stepResult.x < 0) {
            GobangConfig.pointsLimit = origPL;
            _asyncParams = null;
            return {done: true, x: -1, y: -1, score: 0, phaseLabel: "no_move",
                    nodes: stepResult.nodes, rootIdx: stepResult.rootIdx, rootTotal: stepResult.rootTotal};
        }

        stepResult = _refineStrategicMove(_asyncParams, stepResult);
        stepResult = _refineThreatDefenseMove(_asyncParams, stepResult);

        var move:Object = _applyDifficultyDrop(_asyncParams, stepResult.x, stepResult.y, stepResult.score);
        _board.put(move.x, move.y, _aiRole);
        _eval.move(move.x, move.y, _aiRole);
        GobangConfig.pointsLimit = origPL;
        _asyncParams = null;

        return {done: true, x: move.x, y: move.y, score: stepResult.score,
                phaseLabel: stepResult.phaseLabel, nodes: stepResult.nodes,
                rootIdx: stepResult.rootIdx, rootTotal: stepResult.rootTotal};
    }
}
