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

    // 对局决策日志 — 每步 AI 决策的关键信息，gameOver 时输出
    private var _moveLog:Array;
    private var _moveNodes:Array;  // 并行数组：每步节点数，undo 时同步弹出
    private var _totalNodesAllMoves:Number;

    // 难度映射表 [difficulty 下限, searchDepth, pointsLimit, 最优走法概率(%), enableVCT]
    // 2026-03-26: 一维化后节点吞吐提升，d=8 每手仅 ~50 nodes，提升高难度档深度
    private static var DIFFICULTY_TABLE:Array = [
        [0,   2,  5,  30, false],
        [21,  2,  8,  50, false],
        [41,  4,  12, 70, false],
        [61,  6,  16, 90, true],
        [81,  10, 25, 100, true] // R11: pl 20→25 扩大候选
    ];
    // 搜索分超过此阈值时跳过 refine — refine 的静态惩罚系统不能推翻搜索的战术结论
    // 50000 ≈ THREE_THREE_SCORE：双活三以上的战术优势由搜索树确认，不允许覆盖
    // 覆盖范围：THREE_THREE(50K)、FOUR(100K)、TSS必杀(2M)、FIVE(10M)
    private static var REFINE_SKIP_SCORE:Number = 50000;
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

    // TSS 验证: TSS 声称必杀时，用禁 TSS 的浅层搜索确认
    private static var TSS_VERIFY_DEPTH:Number = 4;    // 验证搜索深度
    private static var TSS_SCORE_MIN:Number = 1500000;  // TSS 分数下界
    private static var TSS_SCORE_MAX:Number = 5000000;  // TSS 分数上界（低于 FIVE_SCORE）
    private static var TSS_VERIFY_THRESHOLD:Number = -200; // 对手浅搜分 > 此值则 TSS 可疑
    // P4 校准: 预搜索强制防守走法(P4a/P4b)的分数虚高(≈FIVE_SCORE)，需校准为真实评估
    private static var P4_CALIBRATE_DEPTH:Number = 4;  // 校准搜索深度
    private static var P4_MULTI_REVIEW_DEPTH:Number = 8;
    private static var P4_MULTI_REVIEW_MARGIN:Number = 8;
    private static var P4_MULTI_REVIEW_ROOT_LIMIT:Number = 5;
    private static var P4_MULTI_REVIEW_TIE_DEPTH:Number = 10;
    private static var THREAT_TRIGGER_PROBE_BUDGET_MS:Number = 4;
    private static var THREAT_REFINE_PROBE_BUDGET_MS:Number = 6;
    private static var THREAT_REFINE_FORCE_LOSS_PENALTY:Number = 4000000;
    private static var THREAT_REFINE_FOUR_PENALTY:Number = 250000;
    private static var THREAT_REFINE_THREE_PENALTY:Number = 24000;
    private static var THREAT_REFINE_FOUR_BONUS:Number = 16;
    private static var THREAT_REFINE_THREE_BONUS:Number = 8;
    private static var THREAT_REFINE_BLOCK_THREE_DIR_BONUS:Number = 600;
    private static var THREAT_REFINE_BLOCK_TWO_DIR_BONUS:Number = 280;
    private static var THREAT_REFINE_MULTI_BLOCK_DIR_BONUS:Number = 220;
    private static var THREAT_REFINE_DEF_BRIDGE_WEIGHT:Number = 4;
    private static var THREAT_REFINE_OWN_BRIDGE_WEIGHT:Number = 4;
    private static var THREAT_REFINE_OPP_BRIDGE_WEIGHT:Number = 24;
    private static var THREAT_REFINE_OPP_BRIDGE_SECOND_WEIGHT:Number = 12;
    private static var THREAT_REFINE_DANGEROUS_BRIDGE_SCORE:Number = 32;
    private static var THREAT_REFINE_DANGEROUS_BRIDGE_PENALTY:Number = 120000;
    private static var THREAT_REFINE_MULTI_BRIDGE_PENALTY:Number = 60000;
    private static var THREAT_REFINE_MAJOR_THREAT_PENALTY:Number = 36000;
    private static var THREAT_REFINE_MULTI_THREAT_PENALTY:Number = 90000;
    private static var THREAT_SOURCE_RESULT:Number = 1;
    private static var THREAT_SOURCE_URGENT_FOUR:Number = 2;
    private static var THREAT_SOURCE_URGENT_THREE:Number = 4;
    private static var THREAT_SOURCE_DEF_BRIDGE:Number = 8;
    private static var THREAT_SOURCE_ROOT:Number = 16;
    private static var PIVOT_REFINE_MIN_HISTORY:Number = 8;
    private static var PIVOT_REFINE_MAX_HISTORY:Number = 12;
    private static var PIVOT_REFINE_ROOT_LIMIT:Number = 20;
    private static var PIVOT_REFINE_DEPTH:Number = 6;
    private static var PIVOT_REFINE_MARGIN:Number = 24;

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
        _moveLog = [];
        _moveNodes = [];
        _totalNodesAllMoves = 0;
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

        // 帧预算动态深度（2026-03-26 一维化后实测：d=8 每手 ~50 nodes，8ms 完全够用）
        if (frameBudgetMs <= 8) {
            if (depth > 8) depth = 8;
            if (pl > 10) pl = 10;
            // 战术条件加深到 10
            if (urgentFourMoves !== null && urgentFourMoves.length > 0 && urgentFourMoves.length <= 4) {
                depth = 10;
                if (pl > 6) pl = 6;
                if (pieces >= 8) enableVCT = true;
            } else if (urgentThreeMoves !== null && urgentThreeMoves.length > 0 && urgentThreeMoves.length <= 6) {
                depth = 10;
                if (pl > 6) pl = 6;
            }
        } else if (frameBudgetMs <= 16) {
            if (depth > 8) depth = 8;
            if (pl > 12) pl = 12;
            if (urgentFourMoves !== null && urgentFourMoves.length > 0 && urgentFourMoves.length <= 6) {
                depth = 10;
                if (pl > 6) pl = 6;
                if (pieces >= 8) enableVCT = true;
            } else if (urgentThreeMoves !== null && urgentThreeMoves.length > 0 && urgentThreeMoves.length <= 8) {
                depth = 8;
                if (pl > 8) pl = 8;
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

    // 难度降级安全阈值：与 REFINE_SKIP_SCORE 对齐
    // |score| >= 50K = 搜索确认的战术优势（THREE_THREE/FOUR/TSS/FIVE），不允许 drop
    private static var DROP_PROTECT_THRESHOLD:Number = 50000;
    // 劣势保护阈值：score <= -DROP_LOSING_THRESHOLD 时禁止 drop
    // 已经明显劣势的局面下随机换着只会加速失败
    private static var DROP_LOSING_THRESHOLD:Number = 1500;

    private function _applyDifficultyDrop(params:Object, bestX:Number, bestY:Number, score:Number):Object {
        var finalX:Number = bestX;
        var finalY:Number = bestY;
        var absScore:Number = score >= 0 ? score : -score;
        // 保护条件：战术局面(|score|>=50K)或已明显劣势(score<=-1500)时不 drop
        if (params.bestProb < 100 && absScore < DROP_PROTECT_THRESHOLD
            && score > -DROP_LOSING_THRESHOLD) {
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

    private function _appendStrategicCandidate(candidates:Array, x:Number, y:Number, bonus:Number, sourceMask:Number):Void {
        if (x < 0 || y < 0) return;
        if (sourceMask === undefined) sourceMask = 0;
        for (var i:Number = 0; i < candidates.length; i++) {
            if (candidates[i][0] === x && candidates[i][1] === y) {
                if (bonus > candidates[i][2]) candidates[i][2] = bonus;
                candidates[i][3] |= sourceMask;
                return;
            }
        }
        candidates[candidates.length] = [x, y, bonus, sourceMask];
    }

    // 检测对手是否有紧急 THREE+ 威胁（有任何 frontier 位置在任意方向有 THREE/FOUR/FIVE）
    private function _opponentHasUrgentThreat():Boolean {
        var oppRole:Number = -_aiRole;
        var ori:Number = oppRole === 1 ? 0 : 1;
        var sc:Array = _eval.shapeCache;
        var oriBase:Number = ori * 900;
        var brd:Array = _eval.board;
        var sz:Number = _eval.size;
        var frontier:Array = _eval._frontierList;
        var top:Number = _eval._frontierTop;
        for (var fi:Number = 0; fi < top; fi++) {
            var fp:Number = frontier[fi];
            var cx:Number = (fp / sz) | 0;
            var cy:Number = fp - cx * sz;
            if (brd[(cx + 1) * 17 + (cy + 1)] !== 0) continue;
            var cxy:Number = cx * 15 + cy;
            // THREE=3, FOUR=4, FIVE=5, BLOCK_FOUR=40, BLOCK_FIVE=50
            var v0:Number = sc[oriBase + cxy];
            if (v0 === 3 || v0 === 4 || v0 === 5 || v0 === 40 || v0 === 50) return true;
            var v1:Number = sc[oriBase + 225 + cxy];
            if (v1 === 3 || v1 === 4 || v1 === 5 || v1 === 40 || v1 === 50) return true;
            var v2:Number = sc[oriBase + 450 + cxy];
            if (v2 === 3 || v2 === 4 || v2 === 5 || v2 === 40 || v2 === 50) return true;
            var v3:Number = sc[oriBase + 675 + cxy];
            if (v3 === 3 || v3 === 4 || v3 === 5 || v3 === 40 || v3 === 50) return true;
        }
        return false;
    }

    /**
     * TSS 验证: 当搜索返回 TSS 级别分数时，用禁 TSS 的浅层搜索验证。
     * 原理: TSS 假设对手总是响应威胁，但对手可以走反威胁打断序列。
     *       验证搜索从对手视角评估——如果对手不觉得自己在输，TSS 是虚假的。
     */
    private function _verifyTSSResult(result:Object):Object {
        if (result === null || result.x < 0) return result;
        var s:Number = result.score;
        // 只验证 TSS 范围的正分（AI 认为自己赢）
        if (s < TSS_SCORE_MIN || s > TSS_SCORE_MAX) return result;

        // 临时走这一手
        _board.put(result.x, result.y, _aiRole);
        _eval.move(result.x, result.y, _aiRole);

        // 从对手角度搜索（禁用 VCT/TSS 以避免递归误判）
        var opp:Number = -_aiRole;
        var verifyResult:Object = _minmax.search(opp, TSS_VERIFY_DEPTH, false);

        // 撤销临时走子
        _eval.undo(result.x, result.y);
        _board.undo();

        // 判定: 对手浅搜的分数（从对手视角）如果 > 阈值，说明对手有好的应手
        // verifyResult.score 是对手视角的分数（正=对手好）
        var oppScore:Number = verifyResult.score;

        if (oppScore > TSS_VERIFY_THRESHOLD) {
            // TSS 虚假正向！对手有好的反击手段
            // 降级分数: 用验证搜索的评估替代 TSS 虚假分数
            var degraded:Number = -oppScore; // 翻转为 AI 视角
            trace("[TSS_VERIFY] REJECTED: move=(" + result.x + "," + result.y
                + ") tss_score=" + s + " opp_score=" + oppScore
                + " degraded=" + degraded);
            result.score = degraded;
            result.phaseLabel = result.phaseLabel + "_tssRejected";
        } else {
            trace("[TSS_VERIFY] CONFIRMED: move=(" + result.x + "," + result.y
                + ") tss_score=" + s + " opp_score=" + oppScore);
        }
        return result;
    }

    private function _scoreReviewedP4Candidate(x:Number, y:Number):Object {
        _board.put(x, y, _aiRole);
        _eval.move(x, y, _aiRole);

        var ownThreats:Array = _eval.getThreatMoves(_aiRole, 3, 8);
        var oppThreats:Array = _eval.getThreatMoves(-_aiRole, 3, 8);
        var oppFourMoves:Array = _eval.getMoves(-_aiRole, 0, false, true);
        var verifyResult:Object = _minmax.search(-_aiRole, P4_MULTI_REVIEW_DEPTH, false);
        var score:Number = -verifyResult.score;
        var phase:String = verifyResult.phaseLabel;

        _eval.undo(x, y);
        _board.undo();
        return {
            score: score,
            phase: phase,
            ownThreats: ownThreats.length,
            oppThreats: oppThreats.length,
            oppFourMoves: oppFourMoves.length
        };
    }

    private function _scoreReviewedP4CandidateTieBreak(x:Number, y:Number):Object {
        _board.put(x, y, _aiRole);
        _eval.move(x, y, _aiRole);
        var verifyResult:Object = _minmax.search(-_aiRole, P4_MULTI_REVIEW_TIE_DEPTH, true);
        _eval.undo(x, y);
        _board.undo();
        return {
            score: -verifyResult.score,
            phase: verifyResult.phaseLabel
        };
    }

    private function _reviewMultiBlockFourMove(result:Object):Object {
        if (result === null || result.x < 0) return result;

        var tag:String = result.phaseLabel;
        if (tag === undefined) tag = result.tag;
        if (tag === undefined || tag.indexOf("P4a_blockFour(") !== 0) {
            return result;
        }

        var liveFourCount:Number = (result.liveFourCount !== undefined)
            ? Number(result.liveFourCount)
            : 0;
        if (liveFourCount < 2) return result;

        var bestX:Number = result.x;
        var bestY:Number = result.y;
        var reviewCandidates:Array = result.candidates;
        if (reviewCandidates != undefined && reviewCandidates.length > 0) {
            var candidateStr:String = "";
            for (var ci:Number = 0; ci < reviewCandidates.length; ci++) {
                if (ci > 0) candidateStr += "|";
                candidateStr += "(" + reviewCandidates[ci][0] + "," + reviewCandidates[ci][1] + ")";
            }
            trace("[P4_REVIEW] " + tag + " options=" + candidateStr);
        }
        var bestInfo:Object = _scoreReviewedP4Candidate(bestX, bestY);
        trace("[P4_REVIEW] " + tag + " candidate=(" + bestX + "," + bestY
            + ") score=" + bestInfo.score + " opp=" + bestInfo.phase
            + " ownT=" + bestInfo.ownThreats
            + " oppT=" + bestInfo.oppThreats
            + " opp4=" + bestInfo.oppFourMoves);
        var oppPhase:String = bestInfo.phase;
        if (oppPhase === undefined
            || (oppPhase.indexOf("P4a_blockFour") !== 0
                && oppPhase.indexOf("P4combo") !== 0
                && oppPhase.indexOf("P2_blockFive") !== 0)) {
            return result;
        }

        var rootMoves:Array = _minmax.collectRootMoves(_aiRole, P4_MULTI_REVIEW_ROOT_LIMIT);
        var chosenX:Number = bestX;
        var chosenY:Number = bestY;
        var chosenScore:Number = bestInfo.score;
        var chosenPhase:String = bestInfo.phase;
        var chosenTie:Object = null;
        for (var ri:Number = 0; ri < rootMoves.length; ri++) {
            var mv:Array = rootMoves[ri];
            var altX:Number = mv[0];
            var altY:Number = mv[1];
            if (altX === bestX && altY === bestY) continue;

            var altInfo:Object = _scoreReviewedP4Candidate(altX, altY);
            trace("[P4_REVIEW] " + tag + " alt=(" + altX + "," + altY
                + ") score=" + altInfo.score + " opp=" + altInfo.phase
                + " ownT=" + altInfo.ownThreats
                + " oppT=" + altInfo.oppThreats
                + " opp4=" + altInfo.oppFourMoves);
            var clearlyBetter:Boolean = altInfo.score > chosenScore + P4_MULTI_REVIEW_MARGIN;
            var tieBetter:Boolean = (altInfo.score >= chosenScore - P4_MULTI_REVIEW_MARGIN
                && altInfo.oppFourMoves < bestInfo.oppFourMoves);
            if (!tieBetter && altInfo.score >= chosenScore - P4_MULTI_REVIEW_MARGIN
                    && altInfo.oppFourMoves === bestInfo.oppFourMoves) {
                if (altInfo.oppThreats < bestInfo.oppThreats) {
                    tieBetter = true;
                } else if (altInfo.oppThreats === bestInfo.oppThreats
                        && altInfo.ownThreats > bestInfo.ownThreats) {
                    tieBetter = true;
                }
            }
            if (!clearlyBetter && !tieBetter
                    && altInfo.score >= chosenScore - P4_MULTI_REVIEW_MARGIN
                    && altInfo.oppFourMoves === bestInfo.oppFourMoves
                    && altInfo.oppThreats === bestInfo.oppThreats
                    && altInfo.ownThreats === bestInfo.ownThreats) {
                if (chosenTie == null) {
                    chosenTie = _scoreReviewedP4CandidateTieBreak(chosenX, chosenY);
                    trace("[P4_REVIEW] " + tag + " deep=(" + chosenX + "," + chosenY
                        + ") score=" + chosenTie.score + " opp=" + chosenTie.phase);
                }
                var altTie:Object = _scoreReviewedP4CandidateTieBreak(altX, altY);
                trace("[P4_REVIEW] " + tag + " deep=(" + altX + "," + altY
                    + ") score=" + altTie.score + " opp=" + altTie.phase);
                if (altTie.score > chosenTie.score) {
                    tieBetter = true;
                    chosenTie = altTie;
                } else if (altTie.score === chosenTie.score) {
                    tieBetter = true;
                    chosenTie = altTie;
                }
            }
            if (clearlyBetter || tieBetter) {
                chosenX = altX;
                chosenY = altY;
                chosenScore = altInfo.score;
                chosenPhase = altInfo.phase;
                bestInfo = altInfo;
            }
        }

        if (chosenX === bestX && chosenY === bestY) {
            return result;
        }

        trace("[P4_REVIEW] " + tag + " move=(" + result.x + "," + result.y
            + ") -> (" + chosenX + "," + chosenY + ") score=" + chosenScore
            + " opp=" + chosenPhase);
        result.x = chosenX;
        result.y = chosenY;
        result.score = chosenScore;
        result.phaseLabel = tag + "_review";
        return result;
    }

    /**
     * 防守校准: P2/P4a/P4b 返回 ≈FIVE_SCORE 的虚假高分，
     * 但这只是被迫防守，不代表局面好。做浅层搜索获取真实位置评估。
     * 走法本身不变（强制的），只修正分数供日志和 mismatch 检测使用。
     */
    private function _calibratePreSearchScore(result:Object):Object {
        if (result === null || result.x < 0) return result;
        var tag:String = result.phaseLabel;
        if (tag === undefined) tag = result.tag;
        if (tag === undefined) return result;
        // 校准所有防守性预搜索走法（P2/P4a/P4b）
        // P1_myFive（赢棋）和 P3_myFour（己方活四→必赢）分数合理，不需要校准
        var isDefensive:Boolean = (tag.indexOf("P2_blockFive") === 0
            || tag.indexOf("P4a_blockFour") === 0
            || tag.indexOf("P4combo") === 0);
        if (!isDefensive) return result;

        // 走这手强制防守，然后从对手视角搜索评估真实局面
        _board.put(result.x, result.y, _aiRole);
        _eval.move(result.x, result.y, _aiRole);
        var opp:Number = -_aiRole;
        var verifyResult:Object = _minmax.search(opp, P4_CALIBRATE_DEPTH, false);
        _eval.undo(result.x, result.y);
        _board.undo();

        // 对手视角分数翻转为 AI 视角
        var realScore:Number = -verifyResult.score;
        trace("[DEF_CALIBRATE] " + tag + " move=(" + result.x + "," + result.y
            + ") raw=" + result.score + " calibrated=" + realScore);
        result.score = realScore;
        result.phaseLabel = tag + "_cal";
        return result;
    }

    private function _refineStrategicMove(params:Object, result:Object):Object {
        if (params === null || result === null || result.x < 0) return result;
        var absScore:Number = result.score >= 0 ? result.score : -result.score;
        if (absScore >= REFINE_SKIP_SCORE) return result;
        // 对手有 THREE+ 威胁时，信任搜索的防守判断，不覆盖
        if (_opponentHasUrgentThreat()) return result;
        if (params.searchDepth >= 6 || params.enableVCT || _board.history.length < STRATEGIC_REFINE_MIN_HISTORY) {
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
        trace("[REFINE_STRATEGIC] search=" + result.x + "," + result.y + " score=" + result.score
            + " -> refined=" + bestX + "," + bestY + " score=" + bestSearchScore);
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

    private function _getThreatBlockProfile(x:Number, y:Number):Object {
        var idx:Number = x * 15 + y;
        var sc:Array = _eval.shapeCache;
        var oppBase:Number = (_aiRole === 1) ? 900 : 0;
        var blockThreeDirs:Number = 0;
        var blockTwoDirs:Number = 0;
        var s0:Number = sc[oppBase + idx];
        var s1:Number = sc[oppBase + 225 + idx];
        var s2:Number = sc[oppBase + 450 + idx];
        var s3:Number = sc[oppBase + 675 + idx];
        if (s0 === 3 || s0 === 30 || s0 === 4 || s0 === 40) blockThreeDirs++;
        else if (s0 === 2 || s0 === 22) blockTwoDirs++;
        if (s1 === 3 || s1 === 30 || s1 === 4 || s1 === 40) blockThreeDirs++;
        else if (s1 === 2 || s1 === 22) blockTwoDirs++;
        if (s2 === 3 || s2 === 30 || s2 === 4 || s2 === 40) blockThreeDirs++;
        else if (s2 === 2 || s2 === 22) blockTwoDirs++;
        if (s3 === 3 || s3 === 30 || s3 === 4 || s3 === 40) blockThreeDirs++;
        else if (s3 === 2 || s3 === 22) blockTwoDirs++;
        return {blockThreeDirs: blockThreeDirs, blockTwoDirs: blockTwoDirs};
    }

    private function _isThreatDefenseAnchor(sourceMask:Number, blockInfo:Object):Boolean {
        if ((sourceMask & (THREAT_SOURCE_URGENT_FOUR | THREAT_SOURCE_URGENT_THREE | THREAT_SOURCE_DEF_BRIDGE)) !== 0) {
            return true;
        }
        return (blockInfo.blockThreeDirs > 0 || blockInfo.blockTwoDirs >= 2);
    }

    private function _scoreThreatDefenseCandidate(x:Number, y:Number, bonus:Number,
            probePly:Number, probeBudgetMs:Number):Object {
        var blockInfo:Object = _getThreatBlockProfile(x, y);
        var blockThreeDirs:Number = blockInfo.blockThreeDirs;
        var blockTwoDirs:Number = blockInfo.blockTwoDirs;

        _board.put(x, y, _aiRole);
        _eval.move(x, y, _aiRole);

        var actualProbePly:Number = probePly;
        var score:Number = _eval.evaluate(_aiRole) + bonus;
        score += blockThreeDirs * THREAT_REFINE_BLOCK_THREE_DIR_BONUS;
        score += blockTwoDirs * THREAT_REFINE_BLOCK_TWO_DIR_BONUS;
        if (blockThreeDirs + blockTwoDirs >= 3) {
            score += THREAT_REFINE_MULTI_BLOCK_DIR_BONUS;
        }
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

        var oppThreatMoves:Array = _eval.getThreatMoves(-_aiRole, 3, 6);
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

    private function _getRootCandidateProfile(x:Number, y:Number):Object {
        var idx:Number = x * 15 + y;
        var sc:Array = _eval.shapeCache;
        var atkBase:Number = (_aiRole === 1) ? 0 : 900;
        var defBase:Number = (_aiRole === 1) ? 900 : 0;
        var a0:Number = sc[atkBase + idx];
        var a1:Number = sc[atkBase + 225 + idx];
        var a2:Number = sc[atkBase + 450 + idx];
        var a3:Number = sc[atkBase + 675 + idx];
        var d0:Number = sc[defBase + idx];
        var d1:Number = sc[defBase + 225 + idx];
        var d2:Number = sc[defBase + 450 + idx];
        var d3:Number = sc[defBase + 675 + idx];
        var attackMax:Number = a0;
        if (a1 > attackMax) attackMax = a1;
        if (a2 > attackMax) attackMax = a2;
        if (a3 > attackMax) attackMax = a3;
        var defendMax:Number = d0;
        if (d1 > defendMax) defendMax = d1;
        if (d2 > defendMax) defendMax = d2;
        if (d3 > defendMax) defendMax = d3;
        return {attackMax: attackMax, defendMax: defendMax};
    }

    private function _getPivotPressureTier(oppPhase:String):Number {
        if (oppPhase == undefined) return 0;
        if (oppPhase.indexOf("P2_blockFive") === 0) return 5;
        if (oppPhase.indexOf("P4a_blockFour(2)") === 0) return 4;
        if (oppPhase.indexOf("P4combo") === 0) return 4;
        if (oppPhase.indexOf("P4a_blockFour(1)") === 0) return 3;
        if (oppPhase.indexOf("P1_myFive") === 0) return -5;
        if (oppPhase.indexOf("P3_myFour") === 0) return -4;
        if (oppPhase.indexOf("minmax_win") === 0 || oppPhase.indexOf("vct_win") === 0) return -6;
        return 0;
    }

    private function _scorePivotCandidate(x:Number, y:Number):Object {
        var strategic:Number = _scoreStrategicCandidate(x, y);
        _board.put(x, y, _aiRole);
        _eval.move(x, y, _aiRole);
        var verify:Object = _minmax.search(-_aiRole, PIVOT_REFINE_DEPTH, false);
        _eval.undo(x, y);
        _board.undo();
        var verifyScore:Number = -verify.score;
        var oppPhase:String = verify.phaseLabel;
        return {
            strategic: strategic,
            verifyScore: verifyScore,
            oppPhase: oppPhase,
            pressureTier: _getPivotPressureTier(oppPhase)
        };
    }

    private function _refinePivotMove(params:Object, result:Object):Object {
        if (params == null || result == null || result.x < 0) return result;
        var tag:String = result.phaseLabel;
        if (tag == undefined || tag.indexOf("minmax_d8") !== 0) return result;
        if (_board.history.length < PIVOT_REFINE_MIN_HISTORY
                || _board.history.length > PIVOT_REFINE_MAX_HISTORY) {
            return result;
        }

        var currentProfile:Object = _getRootCandidateProfile(result.x, result.y);
        if (currentProfile.attackMax < 3 || currentProfile.defendMax < 3) {
            return result;
        }

        var rootMoves:Array = _minmax.collectExpandedRootMoves(_aiRole, PIVOT_REFINE_ROOT_LIMIT);
        var bestX:Number = result.x;
        var bestY:Number = result.y;
        var bestInfo:Object = _scorePivotCandidate(bestX, bestY);
        var changed:Boolean = false;

        for (var i:Number = 0; i < rootMoves.length; i++) {
            var cx:Number = rootMoves[i][0];
            var cy:Number = rootMoves[i][1];
            if (cx === bestX && cy === bestY) continue;

            var profile:Object = _getRootCandidateProfile(cx, cy);
            if (profile.attackMax !== 3 || profile.defendMax !== 0) continue;

            var info:Object = _scorePivotCandidate(cx, cy);
            var betterTier:Boolean = (info.pressureTier > bestInfo.pressureTier);
            var betterScore:Boolean = (info.pressureTier === bestInfo.pressureTier
                && info.verifyScore > bestInfo.verifyScore + PIVOT_REFINE_MARGIN);
            var betterStrategic:Boolean = (info.pressureTier === bestInfo.pressureTier
                && info.verifyScore >= bestInfo.verifyScore - PIVOT_REFINE_MARGIN
                && info.strategic > bestInfo.strategic + PIVOT_REFINE_MARGIN);
            if (!betterTier && !betterScore && !betterStrategic) continue;

            bestX = cx;
            bestY = cy;
            bestInfo = info;
            changed = true;
        }

        if (!changed || (bestX === result.x && bestY === result.y)) return result;
        trace("[REFINE_PIVOT] search=" + result.x + "," + result.y + " score=" + result.score
            + " -> refined=" + bestX + "," + bestY + " d" + PIVOT_REFINE_DEPTH
            + "=" + bestInfo.verifyScore + " opp=" + bestInfo.oppPhase);
        var refined:Object = {};
        for (var k:String in result) {
            refined[k] = result[k];
        }
        refined.x = bestX;
        refined.y = bestY;
        refined.score = bestInfo.verifyScore;
        refined.phaseLabel = String(result.phaseLabel) + "_pivot";
        return refined;
    }

    private function _refineThreatDefenseMove(params:Object, result:Object):Object {
        if (params === null || result === null || result.x < 0) return result;
        var absScore2:Number = result.score >= 0 ? result.score : -result.score;
        if (absScore2 >= REFINE_SKIP_SCORE) return result;
        var tag:String = result.phaseLabel;
        if (tag == undefined) tag = result.tag;
        var isPreSearchDefense:Boolean = (tag != undefined
            && (tag.indexOf("P2_blockFive") === 0
                || tag.indexOf("P4a_blockFour") === 0
                || tag.indexOf("P4combo") === 0));
        var hasBoardUrgentThreat:Boolean = _opponentHasUrgentThreat();
        var allowDeepThreatRefine:Boolean = (params.searchDepth >= 10
            && hasBoardUrgentThreat && !isPreSearchDefense);
        // 预搜索强制手保持优先；深搜(minmax_d*)结果允许再做一次局部防守确认
        if (hasBoardUrgentThreat && (isPreSearchDefense || params.searchDepth < 6)) return result;
        if (_board.history.length < THREAT_REFINE_MIN_HISTORY) return result;
        if (params.searchDepth >= 6 && !allowDeepThreatRefine) return result;

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
        var hasStrongDefBridge:Boolean = false;
        for (var bi:Number = 0; bi < defBridge.length; bi++) {
            if (defBridge[bi][2] >= STRATEGIC_BRIDGE_MIN_SCORE) {
                hasDefBridge = true;
            }
            if (defBridge[bi][2] >= THREAT_REFINE_DANGEROUS_BRIDGE_SCORE) {
                hasStrongDefBridge = true;
            }
        }
        if (!hasUrgentFour && !hasUrgentThree && !hasDefBridge) {
            return result;
        }
        var candidates:Array = [];
        _appendStrategicCandidate(candidates, result.x, result.y, 0, THREAT_SOURCE_RESULT);

        if (hasUrgentFour) {
            for (var fi:Number = 0; fi < urgentFour.length && fi < 3; fi++) {
                _appendStrategicCandidate(candidates, urgentFour[fi][0], urgentFour[fi][1],
                    THREAT_REFINE_FOUR_BONUS, THREAT_SOURCE_URGENT_FOUR);
            }
        }
        if (hasUrgentThree && !hasDefBridge) {
            for (var ti:Number = 0; ti < urgentThree.length && ti < 2; ti++) {
                _appendStrategicCandidate(candidates, urgentThree[ti][0], urgentThree[ti][1],
                    THREAT_REFINE_THREE_BONUS, THREAT_SOURCE_URGENT_THREE);
            }
        }
        if (hasDefBridge) {
            for (var di:Number = 0; di < defBridge.length; di++) {
                if (defBridge[di][2] < STRATEGIC_BRIDGE_MIN_SCORE) continue;
                _appendStrategicCandidate(candidates, defBridge[di][0], defBridge[di][1],
                    defBridge[di][2] * THREAT_REFINE_DEF_BRIDGE_WEIGHT, THREAT_SOURCE_DEF_BRIDGE);
            }
        }
        if (allowDeepThreatRefine || hasUrgentFour || hasUrgentThree || hasStrongDefBridge || candidates.length < 2) {
            var rootMoves:Array = _minmax.collectRootMoves(_aiRole, 5);
            for (var ri:Number = 0; ri < rootMoves.length; ri++) {
                _appendStrategicCandidate(candidates, rootMoves[ri][0], rootMoves[ri][1], 0, THREAT_SOURCE_ROOT);
            }
        }
        if (candidates.length < 2) return result;

        var probePly:Number = hasUrgentFour ? THREAT_REFINE_DEEP_PLY : THREAT_REFINE_PLY;
        var bestX:Number = result.x;
        var bestY:Number = result.y;
        var bestBlockInfo:Object = _getThreatBlockProfile(bestX, bestY);
        var bestIsAnchor:Boolean = _isThreatDefenseAnchor(THREAT_SOURCE_RESULT, bestBlockInfo);
        var bestInfo:Object = _scoreThreatDefenseCandidate(bestX, bestY, candidates[0][2],
            probePly, THREAT_REFINE_PROBE_BUDGET_MS);
        var changed:Boolean = false;

        for (var i:Number = 0; i < candidates.length; i++) {
            var cx:Number = candidates[i][0];
            var cy:Number = candidates[i][1];
            if (cx === bestX && cy === bestY) continue;
            var sourceMask:Number = candidates[i][3];
            var candidateBlockInfo:Object = _getThreatBlockProfile(cx, cy);
            var isAnchorCandidate:Boolean = _isThreatDefenseAnchor(sourceMask, candidateBlockInfo);
            var isRootOnly:Boolean = ((sourceMask & THREAT_SOURCE_ROOT) !== 0
                && (sourceMask & (THREAT_SOURCE_RESULT | THREAT_SOURCE_URGENT_FOUR
                    | THREAT_SOURCE_URGENT_THREE | THREAT_SOURCE_DEF_BRIDGE)) === 0);
            if (isRootOnly) {
                if (!isAnchorCandidate) {
                    continue;
                }
            }

            var info:Object = _scoreThreatDefenseCandidate(cx, cy, candidates[i][2],
                probePly, THREAT_REFINE_PROBE_BUDGET_MS);
            if (!bestIsAnchor && isAnchorCandidate) {
                bestInfo = info;
                bestX = cx;
                bestY = cy;
                bestIsAnchor = true;
                changed = true;
                continue;
            }
            if (bestIsAnchor && !isAnchorCandidate) {
                continue;
            }
            if (bestInfo.forcedLoss && !info.forcedLoss) {
                bestInfo = info;
                bestX = cx;
                bestY = cy;
                bestIsAnchor = isAnchorCandidate;
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
                bestIsAnchor = isAnchorCandidate;
                changed = true;
            }
        }

        if (!changed) return result;
        trace("[REFINE_THREAT] search=" + result.x + "," + result.y + " score=" + result.score
            + " -> refined=" + bestX + "," + bestY + " score=" + bestInfo.score);
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

        result = _verifyTSSResult(result);
        result = _reviewMultiBlockFourMove(result);
        result = _calibratePreSearchScore(result);
        result = _refinePivotMove(params, result);
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
        // 如果撤销的是 AI 的棋，同步回退日志和累积节点
        if (last.role === _aiRole && _moveLog.length > 0) {
            var idx:Number = _moveLog.length - 1;
            _totalNodesAllMoves -= _moveNodes[idx];
            _moveLog.length = idx;
            _moveNodes.length = idx;
        }
        _eval.undo(last.i, last.j);
        _board.undo();
        return true;
    }

    public function getBoard():Array {
        return _board.board;
    }

    public function getBoardRef():GobangBoard { return _board; }
    public function getEvalRef():GobangEval { return _eval; }
    public function getMinmaxRef():GobangMinmax { return _minmax; }

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
                if (nx >= 0 && nx < _board.size && ny >= 0 && ny < _board.size && _board.board[nx * 15 + ny] === 0) {
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

        // TSS 验证: 如果搜索返回 TSS 级别分数，验证是否为虚假正向
        stepResult = _verifyTSSResult(stepResult);
        stepResult = _reviewMultiBlockFourMove(stepResult);
        // P4 校准: 强制防守走法的分数膨胀修正
        stepResult = _calibratePreSearchScore(stepResult);
        stepResult = _refinePivotMove(_asyncParams, stepResult);

        stepResult = _refineStrategicMove(_asyncParams, stepResult);
        stepResult = _refineThreatDefenseMove(_asyncParams, stepResult);

        var move:Object = _applyDifficultyDrop(_asyncParams, stepResult.x, stepResult.y, stepResult.score);
        _board.put(move.x, move.y, _aiRole);
        _eval.move(move.x, move.y, _aiRole);
        GobangConfig.pointsLimit = origPL;

        // 记录决策日志
        var moveNum:Number = _board.history.length;
        var threatBlocked:Boolean = _opponentHasUrgentThreat();
        var cDepth:Number = _minmax.getCompletedDepth();
        var logEntry:String = "#" + moveNum
            + " (" + move.x + "," + move.y + ")"
            + " s=" + stepResult.score
            + " d=" + cDepth
            + " " + stepResult.phaseLabel
            + " n=" + stepResult.nodes;
        // top2（标记继承来源：inherited = 来自上一轮迭代加深，非本轮搜索）
        if (stepResult.secondX !== undefined && stepResult.secondX >= 0) {
            logEntry += " top2=(" + stepResult.secondX + "," + stepResult.secondY
                + "," + stepResult.secondScore + ")";
            if (stepResult.secondInherited === true) logEntry += "[inherited]";
        } else {
            logEntry += " top2=none";
        }
        // 难度降级标注
        if (move.x !== stepResult.x || move.y !== stepResult.y) {
            logEntry += " [drop:(" + stepResult.x + "," + stepResult.y + ")]";
        }
        if (threatBlocked) logEntry += " [refine_blocked]";
        _moveLog[_moveLog.length] = logEntry;
        _moveNodes[_moveNodes.length] = stepResult.nodes;
        _totalNodesAllMoves += stepResult.nodes;

        _asyncParams = null;

        return {done: true, x: move.x, y: move.y, score: stepResult.score,
                phaseLabel: stepResult.phaseLabel, nodes: stepResult.nodes,
                rootIdx: stepResult.rootIdx, rootTotal: stepResult.rootTotal,
                secondX: stepResult.secondX, secondY: stepResult.secondY,
                secondScore: stepResult.secondScore,
                secondInherited: stepResult.secondInherited};
    }

    // 输出完整对局决策日志（在 gameOver 时调用）
    public function dumpMoveLog():Void {
        trace("=== AI Decision Log (" + _moveLog.length + " moves) ===");
        for (var i:Number = 0; i < _moveLog.length; i++) {
            trace(_moveLog[i]);
        }
        // 统计摘要
        var st:Object = _minmax.getStats();
        var avgNodes:Number = 0;
        if (_moveLog.length > 0 && _totalNodesAllMoves > 0) {
            avgNodes = Math.round(_totalNodesAllMoves / _moveLog.length);
        }
        trace("=== AI Stats ===");
        trace("TT: hits=" + st.ttHits + " miss_flag=" + st.ttMissFlag + " shallow=" + st.ttShallow);
        trace("VCF: probes=" + st.vcfProbes + " hits=" + st.vcfHits + " skipped=" + st.vcfSkipped);
        trace("PreSearch: " + st.preSearch);
        trace("Moves: " + _moveLog.length + ", Avg nodes: " + avgNodes);
        trace("=== End Stats ===");
    }
}
