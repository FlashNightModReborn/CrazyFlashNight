import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangCache;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangMinmax {
    private static var MAX:Number = 1000000000;
    private static var ONLY_THREE_THRESHOLD:Number = 6;
    private static var DEFAULT_BUDGET_MS:Number = 3000;
    private static var TIME_CHECK_MASK:Number = 7;
    private static var LEAF_TSS_HINT_RADIUS:Number = 3;
    private static var LEAF_TSS_MAX_PLY:Number = 5;
    private static var LEAF_TSS_ATTACK_CAP:Number = 3;
    private static var LEAF_TSS_DEFENSE_CAP:Number = 4;
    private static var LEAF_TSS_DEFENSE_SCAN_LIMIT:Number = 6;
    private static var LEAF_TSS_NODE_CAP:Number = 40;
    private static var LEAF_TSS_SCORE:Number = 2000000;
    private static var BRIDGE_PROBE_MIN_HISTORY:Number = 10;
    private static var BRIDGE_PROBE_DEPTH:Number = 4;
    private static var BRIDGE_PROBE_POINTS_LIMIT:Number = 4;
    private static var BRIDGE_PROBE_DEEP_DEPTH:Number = 6;
    private static var BRIDGE_PROBE_DEEP_POINTS_LIMIT:Number = 3;
    private static var BRIDGE_PROBE_URGENT_FOUR_LIMIT:Number = 2;
    private static var BRIDGE_PROBE_URGENT_LIMIT:Number = 2;
    private static var BRIDGE_PROBE_MIN_SCORE:Number = 18;
    private static var BRIDGE_PROBE_ATTACK_WEIGHT:Number = 4;
    private static var BRIDGE_PROBE_DEF_WEIGHT:Number = 3;
    private static var BRIDGE_PROBE_DEEP_MIN_BIAS:Number = 80;
    private static var BRIDGE_PROBE_DEEP_MAX_MOVES:Number = 2;
    // TT bound type flags
    private static var TT_EXACT:Number = 0;
    private static var TT_LOWER:Number = 1;  // fail-high, 值是下界
    private static var TT_UPPER:Number = 2;  // fail-low, 值是上界
    // VCF 门控常量
    private static var VCF_TIME_RATIO:Number = 0.8; // 2026-03-26: 0.6→0.8，一维化后每节点更快，给VCF更多时间窗
    private static var VCF_BUDGET_BASE:Number = 8;
    private static var VCF_BUDGET_PER_DEPTH:Number = 4;
    private static var VCF_BUDGET_MAX:Number = 40;
    private static var VCF_PLY_BASE:Number = 3;
    private static var VCF_PLY_MAX:Number = 7;
    private var _board:GobangBoard;
    private var _eval:GobangEval;
    private var _cache:GobangCache;
    private var _nodeCount:Number;
    private var _startTime:Number;
    private var _timedOut:Boolean;
    private var _budgetMs:Number;

    // negamax 返回值 — 消除每节点 Array 分配
    private var _nmS:Number;
    private var _nmX:Number;
    private var _nmY:Number;

    // Killer move heuristic — 每深度2个槽位，存 flat index (x*15+y)
    private var _killers:Array;
    // History Heuristic — beta 截断成功计数，flat index = x*15+y
    private var _history:Array;
    // VCF 探针首手记录
    private var _vcfFirstX:Number;
    private var _vcfFirstY:Number;

    // 异步搜索状态
    private var _asyncPhase:Number;
    private var _asyncRole:Number;
    private var _asyncMaxDepth:Number;
    private var _asyncEnableVCT:Boolean;
    private var _asyncBestResult:Object;
    private var _asyncTotalNodes:Number;
    private var _asyncCurrentDepth:Number;
    private var _asyncDone:Boolean;
    private var _asyncVCTStartTime:Number;
    private var _asyncLastCompletedDepth:Number;
    private var _asyncMoves:Array;
    private var _asyncMoveIndex:Number;
    private var _asyncTargetDepth:Number;
    private var _asyncOnlyThree:Boolean;
    private var _asyncOnlyFour:Boolean;
    private var _asyncAlpha:Number;
    private var _asyncBeta:Number;
    private var _asyncWorkingBestScore:Number;
    private var _asyncWorkingBestRawScore:Number;
    private var _asyncWorkingBestX:Number;
    private var _asyncWorkingBestY:Number;
    private var _asyncBridgeBaseDepth:Number;
    private var _tssBudget:Number;

    // VCF 门控深度提示
    private var _vcfDepthHint:Number;

    // 统计计数器（整局累积，resetStats 重置）
    private var _statTTHits:Number;
    private var _statTTMissFlag:Number;
    private var _statVCFProbes:Number;
    private var _statVCFHits:Number;
    private var _statVCFSkipped:Number;
    private var _statPreSearch:Number;
    private var _statTTShallow:Number;

    // top2 追踪
    private var _asyncSecondRawScore:Number;
    private var _asyncSecondX:Number;
    private var _asyncSecondY:Number;

    // 根层进度追踪（1-based）
    private var _rootMoveIdx:Number;
    private var _rootMoveTotal:Number;

    public function GobangMinmax(board:GobangBoard, eval:GobangEval) {
        _board = board;
        _eval = eval;
        _cache = new GobangCache(60000);
        _nodeCount = 0;
        _timedOut = false;
        _budgetMs = DEFAULT_BUDGET_MS;
        _nmS = 0; _nmX = -1; _nmY = -1;
        _killers = new Array(24);
        _resetKillers();
        _history = new Array(225);
        _resetHistory();
        _asyncPhase = 0;
        _asyncDone = true;
        _asyncTotalNodes = 0;
        _asyncLastCompletedDepth = 0;
        _asyncMoves = null;
        _asyncMoveIndex = 0;
        _asyncTargetDepth = 0;
        _asyncOnlyThree = false;
        _asyncOnlyFour = false;
        _asyncAlpha = -MAX;
        _asyncBeta = MAX;
        _asyncWorkingBestScore = -MAX;
        _asyncWorkingBestRawScore = -MAX;
        _asyncWorkingBestX = -1;
        _asyncWorkingBestY = -1;
        _asyncBridgeBaseDepth = 0;
        _tssBudget = 0;
        _vcfDepthHint = 0;
        _asyncSecondRawScore = -MAX;
        _asyncSecondX = -1;
        _asyncSecondY = -1;
        _rootMoveIdx = 0;
        _rootMoveTotal = 0;
        resetStats();
    }

    private function _resetKillers():Void {
        var k:Array = _killers;
        var i:Number = 23;
        while (i >= 0) { k[i] = -1; i--; }
    }

    private function _resetHistory():Void {
        var h:Array = _history;
        var i:Number = 224;
        while (i >= 0) { h[i] = 0; i--; }
    }

    private function normalizeDepth(depth:Number):Number {
        if (depth === undefined || depth < 2) depth = 2;
        if ((depth & 1) !== 0) depth--;
        if (depth < 2) depth = 2;
        return depth;
    }

    private function hasMove(moves:Array, x:Number, y:Number):Boolean {
        for (var i:Number = 0; i < moves.length; i++) {
            if (moves[i][0] === x && moves[i][1] === y) return true;
        }
        return false;
    }

    private function promoteMove(moves:Array, x:Number, y:Number):Void {
        if (x < 0 || y < 0) return;
        for (var i:Number = 0; i < moves.length; i++) {
            if (moves[i][0] === x && moves[i][1] === y) {
                if (i === 0) return;
                var tmp:Array = moves[0];
                moves[0] = moves[i];
                moves[i] = tmp;
                return;
            }
        }
    }

    // promote 到指定位置（不覆盖更前的条目）
    private function promoteMoveAt(moves:Array, x:Number, y:Number, pos:Number):Void {
        if (x < 0 || y < 0 || pos >= moves.length) return;
        for (var i:Number = pos; i < moves.length; i++) {
            if (moves[i][0] === x && moves[i][1] === y) {
                if (i === pos) return;
                var tmp:Array = moves[pos];
                moves[pos] = moves[i];
                moves[i] = tmp;
                return;
            }
        }
    }

    private function mergeBridgeMoves(moves:Array, role:Number, limit:Number, insertPos:Number):Void {
        if (limit === undefined || limit < 1) limit = 1;
        if (insertPos === undefined || insertPos < 0) insertPos = 0;
        var bridges:Array = _eval.getBridgeMoves(role, limit);
        for (var i:Number = 0; i < bridges.length; i++) {
            var bx:Number = bridges[i][0];
            var by:Number = bridges[i][1];
            if (insertPos > moves.length) insertPos = moves.length;

            var foundAt:Number = -1;
            for (var mi:Number = 0; mi < moves.length; mi++) {
                if (moves[mi][0] === bx && moves[mi][1] === by) {
                    foundAt = mi;
                    break;
                }
            }

            if (foundAt >= 0) {
                if (foundAt > insertPos) {
                    var mv:Array = moves[foundAt];
                    while (foundAt > insertPos) {
                        moves[foundAt] = moves[foundAt - 1];
                        foundAt--;
                    }
                    moves[insertPos] = mv;
                }
            } else {
                var tail:Number = moves.length;
                moves[tail] = [bx, by];
                while (tail > insertPos) {
                    moves[tail] = moves[tail - 1];
                    tail--;
                }
                moves[insertPos] = [bx, by];
            }
            insertPos++;
        }
    }

    private function appendUniqueMove(moves:Array, x:Number, y:Number):Void {
        if (x < 0 || y < 0 || hasMove(moves, x, y)) return;
        moves[moves.length] = [x, y];
    }

    private function getBridgeProbeBias(role:Number, x:Number, y:Number):Number {
        _board.put(x, y, role);
        _eval.move(x, y, role);
        var bias:Number = 0;
        var atk:Array = _eval.getBridgeMoves(role, 1, true);
        if (atk.length > 0) {
            bias += atk[0][2] * BRIDGE_PROBE_ATTACK_WEIGHT;
        }
        var def:Array = _eval.getBridgeMoves(-role, 1, true);
        if (def.length > 0) {
            bias -= def[0][2] * BRIDGE_PROBE_DEF_WEIGHT;
        }
        _eval.undo(x, y);
        _board.undo();
        return bias;
    }

    private function collectBridgeProbeMoves(role:Number, baseX:Number, baseY:Number):Array {
        var moves:Array = [];
        moves[moves.length] = [baseX, baseY, getBridgeProbeBias(role, baseX, baseY), 0];

        var urgentFour:Array = _eval.getMoves(role, 0, false, true);
        if (urgentFour.length > 0 && urgentFour.length <= 4) {
            for (var fi:Number = 0; fi < urgentFour.length && fi < BRIDGE_PROBE_URGENT_FOUR_LIMIT; fi++) {
                if (!hasMove(moves, urgentFour[fi][0], urgentFour[fi][1])) {
                    moves[moves.length] = [urgentFour[fi][0], urgentFour[fi][1],
                        getBridgeProbeBias(role, urgentFour[fi][0], urgentFour[fi][1]), 2];
                }
            }
            if (moves.length >= 2) {
                return moves;
            }
        }

        var urgent:Array = _eval.getMoves(role, 0, true, false);
        if (urgent.length > 0 && urgent.length <= 4) {
            for (var ui:Number = 0; ui < urgent.length && ui < BRIDGE_PROBE_URGENT_LIMIT; ui++) {
                if (!hasMove(moves, urgent[ui][0], urgent[ui][1])) {
                    moves[moves.length] = [urgent[ui][0], urgent[ui][1],
                        getBridgeProbeBias(role, urgent[ui][0], urgent[ui][1]), 1];
                }
            }
            if (moves.length >= 2) {
                return moves;
            }
        }

        var atk:Array = _eval.getBridgeMoves(role, 2, true);
        for (var ai:Number = 0; ai < atk.length; ai++) {
            if (atk[ai][2] >= BRIDGE_PROBE_MIN_SCORE) {
                if (!hasMove(moves, atk[ai][0], atk[ai][1])) {
                    moves[moves.length] = [atk[ai][0], atk[ai][1], getBridgeProbeBias(role, atk[ai][0], atk[ai][1]), 0];
                }
                break;
            }
        }

        var def:Array = _eval.getBridgeMoves(-role, 2, true);
        for (var di:Number = 0; di < def.length; di++) {
            if (def[di][2] >= BRIDGE_PROBE_MIN_SCORE) {
                if (!hasMove(moves, def[di][0], def[di][1])) {
                    moves[moves.length] = [def[di][0], def[di][1], getBridgeProbeBias(role, def[di][0], def[di][1]), 0];
                }
                break;
            }
        }

        return moves.length >= 2 ? moves : null;
    }

    private function chooseBridgeProbeDepth(moves:Array):Number {
        if (moves === null || moves.length < 2) return BRIDGE_PROBE_DEPTH;
        if (moves.length > BRIDGE_PROBE_DEEP_MAX_MOVES) return BRIDGE_PROBE_DEPTH;

        var maxBias:Number = 0;
        for (var i:Number = 0; i < moves.length; i++) {
            if (moves[i].length > 3 && moves[i][3] === 2) {
                return BRIDGE_PROBE_DEEP_DEPTH;
            }
            var bias:Number = moves[i][2];
            if (bias < 0) bias = -bias;
            if (bias > maxBias) maxBias = bias;
        }
        return maxBias >= BRIDGE_PROBE_DEEP_MIN_BIAS ? BRIDGE_PROBE_DEEP_DEPTH : BRIDGE_PROBE_DEPTH;
    }

    private function beginTimedSearch(budgetMs:Number):Void {
        _budgetMs = budgetMs;
        _startTime = getTimer();
        _nodeCount = 0;
        _timedOut = false;
    }

    // ===== 同步搜索 =====

    public function search(role:Number, maxDepth:Number, enableVCT:Boolean):Object {
        maxDepth = normalizeDepth(maxDepth === undefined ? GobangConfig.searchDepth : maxDepth);
        if (enableVCT === undefined) enableVCT = true;

        _nodeCount = 0;
        _timedOut = false;
        _budgetMs = DEFAULT_BUDGET_MS;
        _startTime = getTimer();
        _rootMoveIdx = 0;
        _rootMoveTotal = 0;
        _resetKillers();
        _resetHistory();

        // 预搜索：确定性战术走法直接返回，跳过搜索
        var tactical:Object = _preSearchTactical(role);
        if (tactical !== null) {
            _statPreSearch++;
            return {x: tactical.x, y: tactical.y, score: tactical.score,
                    nodes: 0, timedOut: false, phaseLabel: tactical.tag};
        }

        var best:Object = {x: -1, y: -1, score: _eval.evaluate(role), timedOut: false};
        var prefX:Number = -1;
        var prefY:Number = -1;

        // VCT 阶段（不限根候选）
        if (enableVCT && _eval.history.length >= 8) {
            var vct:Object = searchFixedDepth(role, maxDepth + 4, true, false, -1, -1, -MAX, MAX, 0);
            if (vct.x >= 0) {
                best = vct;
                prefX = vct.x;
                prefY = vct.y;
            }
            if (!vct.timedOut && vct.score >= GobangShape.FIVE_SCORE) {
                return {x: vct.x, y: vct.y, score: vct.score, nodes: _nodeCount, timedOut: _timedOut};
            }
            if (_timedOut) {
                return {x: best.x, y: best.y, score: best.score, nodes: _nodeCount, timedOut: true};
            }
        }

        // 迭代加深 + aspiration windows
        for (var depth:Number = 2; depth <= maxDepth; depth += 2) {
            var iAlpha:Number = -MAX;
            var iBeta:Number = MAX;
            // Aspiration: depth>=4 且上一轮有有效分数
            if (depth >= 4 && best.score > -MAX / 2 && best.score < MAX / 2) {
                iAlpha = best.score - 500;
                iBeta = best.score + 500;
            }
            var cur:Object = searchFixedDepth(role, depth, false, false, prefX, prefY, iAlpha, iBeta, 0);
            // Aspiration 失败 → 全窗口重搜
            if (!_timedOut && (cur.score <= iAlpha || cur.score >= iBeta)) {
                cur = searchFixedDepth(role, depth, false, false, prefX, prefY, -MAX, MAX, 0);
            }
            if (cur.x >= 0) {
                best = cur;
                prefX = cur.x;
                prefY = cur.y;
            }
            if (_timedOut || cur.score >= GobangShape.FIVE_SCORE) break;
        }

        return {x: best.x, y: best.y, score: best.score, nodes: _nodeCount, timedOut: _timedOut};
    }

    // 对手回复覆盖数重排序：走了这手后对手还剩多少 THREE+ 威胁方向
    // 覆盖更多威胁的走法排前面 — 解决"局部强手 vs 全局拆骨架"问题
    private function rerankByCoverage(moves:Array, role:Number, maxEval:Number):Void {
        if (moves.length < 3 || _eval.history.length < 6) return;
        var opp:Number = -role;
        // 只对前 topN 个候选做 move/undo 统计（控制开销）
        var topN:Number = 5;
        if (topN > moves.length) topN = moves.length;
        var baseThreatCount:Number = countThreats(opp);

        var scores:Array = [];
        for (var i:Number = 0; i < topN; i++) {
            var mx:Number = moves[i][0];
            var my:Number = moves[i][1];
            _board.put(mx, my, role);
            _eval.move(mx, my, role);
            var remainThreats:Number = countThreats(opp);
            var ownThreats:Number = countThreats(role);
            var ownFours:Number = countFoursOrFives(role);
            var oppFours:Number = countFoursOrFives(opp);
            _eval.undo(mx, my);
            _board.undo();
            var eliminated:Number = baseThreatCount - remainThreats;
            var coverage:Number = eliminated * 300 + ownThreats * 60 - remainThreats * 150;
            if (ownFours > 0) coverage += 1000000;
            if (oppFours > 0) coverage -= 500000;
            scores[i] = coverage;
        }

        // 只对前 topN 做稳定排序
        for (var j:Number = 1; j < topN; j++) {
            var jScore:Number = scores[j];
            var jMove:Array = moves[j];
            var k:Number = j - 1;
            while (k >= 0 && scores[k] < jScore) {
                moves[k + 1] = moves[k];
                scores[k + 1] = scores[k];
                k--;
            }
            moves[k + 1] = jMove;
            scores[k + 1] = jScore;
        }
    }

    // 快速统计 FOUR/FIVE 方向数（活四、冲四、五连）
    private function countFoursOrFives(role:Number):Number {
        var sc:Array = _eval.shapeCache;
        var base:Number = (role === 1 ? 0 : 1) * 900;
        var brd:Array = _eval.board;
        var sz:Number = _board.size;
        var frontier:Array = _eval._frontierList;
        var frontierTop:Number = _eval._frontierTop;
        var count:Number = 0;
        for (var fi:Number = 0; fi < frontierTop; fi++) {
            var fp:Number = frontier[fi];
            var i:Number = (fp / sz) | 0;
            var j:Number = fp - i * sz;
            if (brd[(i + 1) * 17 + (j + 1)] !== 0) continue;
            var idx:Number = base + i * 15 + j;
            var s0:Number = sc[idx]; var s1:Number = sc[idx + 225];
            var s2:Number = sc[idx + 450]; var s3:Number = sc[idx + 675];
            // FOUR=4, FIVE=5, BLOCK_FOUR=40, BLOCK_FIVE=50
            if (s0 === 4 || s0 === 5 || s0 === 40 || s0 === 50) count++;
            if (s1 === 4 || s1 === 5 || s1 === 40 || s1 === 50) count++;
            if (s2 === 4 || s2 === 5 || s2 === 40 || s2 === 50) count++;
            if (s3 === 4 || s3 === 5 || s3 === 40 || s3 === 50) count++;
            if (count > 0) return count; // 有一个就够了
        }
        return count;
    }

    // 快速统计指定角色的 THREE+ 威胁方向总数
    private function countThreats(role:Number):Number {
        var sc:Array = _eval.shapeCache;
        var base:Number = (role === 1 ? 0 : 1) * 900;
        var brd:Array = _eval.board;
        var sz:Number = _board.size;
        var frontier:Array = _eval._frontierList;
        var frontierTop:Number = _eval._frontierTop;
        var count:Number = 0;
        for (var fi:Number = 0; fi < frontierTop; fi++) {
            var fp:Number = frontier[fi];
            var i:Number = (fp / sz) | 0;
            var j:Number = fp - i * sz;
            if (brd[(i + 1) * 17 + (j + 1)] !== 0) continue;
            var idx:Number = base + i * 15 + j;
            if (sc[idx] >= 3) count++;
            if (sc[idx + 225] >= 3) count++;
            if (sc[idx + 450] >= 3) count++;
            if (sc[idx + 675] >= 3) count++;
        }
        return count;
    }

    // rootLimit: >0 时截断根候选到前 N 个（短名单深搜核心）
    private function searchFixedDepth(role:Number, depth:Number,
            onlyThree:Boolean, onlyFour:Boolean,
            preferredX:Number, preferredY:Number,
            initAlpha:Number, initBeta:Number,
            rootLimit:Number):Object {
        _rootMoveIdx = 0;
        _rootMoveTotal = 0;

        var moves:Array = _eval.getMoves(role, 0, onlyThree, onlyFour);
        if (!onlyThree && !onlyFour) {
            var center:Number = Math.floor(_board.size / 2);
            if (_board.board[center * 15 + center] === 0 && !hasMove(moves, center, center)) {
                moves.push([center, center]);
            }
            // 根候选覆盖数重排序 — pieces>=6 即启用（早期布局同样需要多路覆盖）
            if (_eval.history.length >= 6 && moves.length >= 3) {
                rerankByCoverage(moves, role, 0);
            }
        }
        if (!moves.length) {
            return {x: -1, y: -1, score: _eval.evaluate(role), timedOut: _timedOut};
        }

        var prev:Object = _cache.get(_board.hash());
        if (preferredX >= 0) promoteMove(moves, preferredX, preferredY);
        if (prev !== null && prev.role === role && prev.onlyThree === onlyThree && prev.onlyFour === onlyFour) {
            promoteMove(moves, prev.moveX, prev.moveY);
        }

        // 可选根短名单：仅在明确启用时截断
        if (rootLimit > 0 && !onlyThree && !onlyFour && moves.length > rootLimit) {
            moves.length = rootLimit;
        }

        var alpha:Number = initAlpha;
        var beta:Number = initBeta;
        var bestScore:Number = -MAX;
        var bestX:Number = -1;
        var bestY:Number = -1;

        _rootMoveTotal = moves.length;
        for (var i:Number = 0; i < moves.length; i++) {
            if (getTimer() - _startTime > _budgetMs) {
                _timedOut = true;
                break;
            }
            _rootMoveIdx = i + 1;
            var mx:Number = moves[i][0];
            var my:Number = moves[i][1];
            _board.put(mx, my, role);
            _eval.move(mx, my, role);
            negamax(-role, depth - 1, 1, -beta, -alpha, onlyThree, onlyFour);
            var currentValue:Number = -_nmS;
            _eval.undo(mx, my);
            _board.undo();

            if (bestX < 0 || currentValue > bestScore) {
                bestScore = currentValue;
                bestX = mx;
                bestY = my;
            }
            if (currentValue > alpha) alpha = currentValue;
            if (_timedOut || alpha >= beta || currentValue >= GobangShape.FIVE_SCORE) break;
        }

        if (bestX < 0) {
            bestScore = _eval.evaluate(role);
        }
        return {x: bestX, y: bestY, score: bestScore, timedOut: _timedOut};
    }

    private function initAsyncRootSearch(depth:Number, onlyThree:Boolean, onlyFour:Boolean):Boolean {
        _asyncTargetDepth = depth;
        _asyncOnlyThree = onlyThree;
        _asyncOnlyFour = onlyFour;
        _asyncMoves = _eval.getMoves(_asyncRole, 0, onlyThree, onlyFour);
        if (!onlyThree && !onlyFour) {
            var center:Number = Math.floor(_board.size / 2);
            if (_board.board[center * 15 + center] === 0 && !hasMove(_asyncMoves, center, center)) {
                _asyncMoves.push([center, center]);
            }
            // 根候选覆盖数重排序 — pieces>=6 即启用
            if (_eval.history.length >= 6 && _asyncMoves.length >= 3) {
                rerankByCoverage(_asyncMoves, _asyncRole, 0);
            }
        }
        _asyncMoveIndex = 0;
        _asyncAlpha = -MAX;
        _asyncBeta = MAX;
        _asyncWorkingBestScore = -MAX;
        _asyncWorkingBestRawScore = -MAX;
        _asyncWorkingBestX = -1;
        _asyncWorkingBestY = -1;
        _asyncSecondRawScore = -MAX;
        _asyncSecondX = -1;
        _asyncSecondY = -1;
        _rootMoveIdx = 0;

        if (!_asyncMoves.length) {
            _rootMoveTotal = 0;
            return false;
        }

        var prev:Object = _cache.get(_board.hash());
        if (_asyncBestResult.x >= 0) {
            promoteMove(_asyncMoves, _asyncBestResult.x, _asyncBestResult.y);
        }
        if (prev !== null && prev.role === _asyncRole
                && prev.onlyThree === onlyThree && prev.onlyFour === onlyFour) {
            promoteMove(_asyncMoves, prev.moveX, prev.moveY);
        }

        // Aspiration: depth>=4 且上一轮有有效分数
        if (depth >= 4 && _asyncBestResult.score > -MAX / 2 && _asyncBestResult.score < MAX / 2) {
            _asyncAlpha = _asyncBestResult.score - 500;
            _asyncBeta = _asyncBestResult.score + 500;
        }

        _rootMoveTotal = _asyncMoves.length;
        return true;
    }

    private function initAsyncCandidateSearch(depth:Number, moves:Array):Boolean {
        if (moves === null || moves.length === 0) {
            _rootMoveTotal = 0;
            return false;
        }
        _asyncTargetDepth = depth;
        _asyncOnlyThree = false;
        _asyncOnlyFour = false;
        _asyncMoves = moves;
        _asyncMoveIndex = 0;
        _asyncAlpha = -MAX;
        _asyncBeta = MAX;
        _asyncWorkingBestScore = -MAX;
        _asyncWorkingBestRawScore = -MAX;
        _asyncWorkingBestX = -1;
        _asyncWorkingBestY = -1;
        _asyncSecondRawScore = -MAX;
        _asyncSecondX = -1;
        _asyncSecondY = -1;
        _rootMoveIdx = 0;
        _rootMoveTotal = _asyncMoves.length;
        return true;
    }

    private function tryStartAsyncBridgeProbe():Boolean {
        if (_asyncMaxDepth !== 2
                || _asyncLastCompletedDepth !== 2
                || _asyncBestResult.x < 0
                || _asyncEnableVCT
                || _eval.history.length < BRIDGE_PROBE_MIN_HISTORY) {
            return false;
        }

        var probeMoves:Array = collectBridgeProbeMoves(_asyncRole, _asyncBestResult.x, _asyncBestResult.y);
        if (probeMoves === null) return false;

        _asyncBridgeBaseDepth = _asyncLastCompletedDepth;
        _asyncPhase = 3;
        return initAsyncCandidateSearch(chooseBridgeProbeDepth(probeMoves), probeMoves);
    }

    private function stepAsyncRootSearch(frameBudgetMs:Number):Object {
        beginTimedSearch(frameBudgetMs);
        var useBridgeBias:Boolean = (_asyncPhase === 3);

        while (_asyncMoveIndex < _asyncMoves.length) {
            if (getTimer() - _startTime > _budgetMs) {
                _timedOut = true;
                break;
            }

            _rootMoveIdx = _asyncMoveIndex + 1;
            var mx:Number = _asyncMoves[_asyncMoveIndex][0];
            var my:Number = _asyncMoves[_asyncMoveIndex][1];
            _board.put(mx, my, _asyncRole);
            _eval.move(mx, my, _asyncRole);
            negamax(-_asyncRole, _asyncTargetDepth - 1, 1,
                    -_asyncBeta, -_asyncAlpha, _asyncOnlyThree, _asyncOnlyFour);
            var currentValue:Number = -_nmS;
            var compareValue:Number = currentValue;
            if (useBridgeBias && _asyncMoves[_asyncMoveIndex].length > 2) {
                compareValue += _asyncMoves[_asyncMoveIndex][2];
            }
            _eval.undo(mx, my);
            _board.undo();
            _asyncMoveIndex++;

            if (!_timedOut) {
                if (_asyncWorkingBestX < 0 || compareValue > _asyncWorkingBestScore) {
                    // 旧 best 降为 second — 只在非 bridgeBias 阶段记录（bridgeprobe 排序含 bias，与 raw score 不可比）
                    if (_asyncWorkingBestX >= 0 && !useBridgeBias) {
                        _asyncSecondRawScore = _asyncWorkingBestRawScore;
                        _asyncSecondX = _asyncWorkingBestX;
                        _asyncSecondY = _asyncWorkingBestY;
                    }
                    _asyncWorkingBestScore = compareValue;
                    _asyncWorkingBestRawScore = currentValue;
                    _asyncWorkingBestX = mx;
                    _asyncWorkingBestY = my;
                } else if (!useBridgeBias && currentValue > _asyncSecondRawScore) {
                    _asyncSecondRawScore = currentValue;
                    _asyncSecondX = mx;
                    _asyncSecondY = my;
                }
                if (!useBridgeBias && currentValue > _asyncAlpha) _asyncAlpha = currentValue;
                if ((!useBridgeBias && _asyncAlpha >= _asyncBeta) || currentValue >= GobangShape.FIVE_SCORE) {
                    _asyncMoveIndex = _asyncMoves.length;
                    break;
                }
            } else if (_asyncWorkingBestX < 0) {
                _asyncWorkingBestScore = compareValue;
                _asyncWorkingBestRawScore = currentValue;
                _asyncWorkingBestX = mx;
                _asyncWorkingBestY = my;
                break;
            } else {
                break;
            }
        }

        var finished:Boolean = (_asyncMoveIndex >= _asyncMoves.length);
        if (finished && _asyncWorkingBestX >= 0) {
            // 当本轮无 second 但上轮有时，继承上轮的 second
            // 典型场景：d=6 有多个候选产生 second，d=8 战术加深只 1 个候选
            var secX:Number = _asyncSecondX;
            var secY:Number = _asyncSecondY;
            var secScore:Number = _asyncSecondRawScore;
            var secInherited:Boolean = false;
            if (secX < 0 && _asyncBestResult.secondX !== undefined && _asyncBestResult.secondX >= 0) {
                secX = _asyncBestResult.secondX;
                secY = _asyncBestResult.secondY;
                secScore = _asyncBestResult.secondScore;
                secInherited = true;
            }
            _asyncBestResult = {
                x: _asyncWorkingBestX,
                y: _asyncWorkingBestY,
                score: _asyncWorkingBestRawScore,
                secondX: secX,
                secondY: secY,
                secondScore: secScore,
                secondInherited: secInherited
            };
            _asyncLastCompletedDepth = _asyncTargetDepth;
            _asyncMoves = null;
        }

        var showX:Number = finished ? _asyncBestResult.x : _asyncWorkingBestX;
        var showY:Number = finished ? _asyncBestResult.y : _asyncWorkingBestY;
        var showScore:Number = finished ? _asyncBestResult.score : _asyncWorkingBestRawScore;
        if (showX < 0 && _asyncBestResult.x >= 0) {
            showX = _asyncBestResult.x;
            showY = _asyncBestResult.y;
            showScore = _asyncBestResult.score;
        }
        return {
            done: finished,
            x: showX,
            y: showY,
            score: showScore,
            timedOut: _timedOut
        };
    }

    private function hasLeafTSSHint():Boolean {
        var h:Array = _board.history;
        var hLen:Number = h.length;
        if (hLen === 0) return false;

        var last:Object = h[hLen - 1];
        var lx:Number = last.i;
        var ly:Number = last.j;
        var minX:Number = lx - LEAF_TSS_HINT_RADIUS;
        var maxX:Number = lx + LEAF_TSS_HINT_RADIUS;
        var minY:Number = ly - LEAF_TSS_HINT_RADIUS;
        var maxY:Number = ly + LEAF_TSS_HINT_RADIUS;
        var sz:Number = _board.size;
        if (minX < 0) minX = 0;
        if (minY < 0) minY = 0;
        if (maxX >= sz) maxX = sz - 1;
        if (maxY >= sz) maxY = sz - 1;

        var brd:Array = _board.board;
        var sc:Array = _eval.shapeCache;
        for (var x:Number = minX; x <= maxX; x++) {
            var bOff:Number = x * 15;
            var wOff:Number = 900 + x * 15;
            for (var y:Number = minY; y <= maxY; y++) {
                if (brd[x * 15 + y] !== 0) continue;

                var bTwos:Number = 0;
                var sh:Number = sc[bOff + y];
                if (sh === 3 || sh === 4 || sh === 40 || sh === 5 || sh === 50) return true;
                if (sh === 2) bTwos++;
                sh = sc[bOff + y + 225];
                if (sh === 3 || sh === 4 || sh === 40 || sh === 5 || sh === 50) return true;
                if (sh === 2) bTwos++;
                sh = sc[bOff + y + 450];
                if (sh === 3 || sh === 4 || sh === 40 || sh === 5 || sh === 50) return true;
                if (sh === 2) bTwos++;
                sh = sc[bOff + y + 675];
                if (sh === 3 || sh === 4 || sh === 40 || sh === 5 || sh === 50) return true;
                if (sh === 2) bTwos++;
                if (bTwos >= 2) return true;

                var wTwos:Number = 0;
                sh = sc[wOff + y];
                if (sh === 3 || sh === 4 || sh === 40 || sh === 5 || sh === 50) return true;
                if (sh === 2) wTwos++;
                sh = sc[wOff + y + 225];
                if (sh === 3 || sh === 4 || sh === 40 || sh === 5 || sh === 50) return true;
                if (sh === 2) wTwos++;
                sh = sc[wOff + y + 450];
                if (sh === 3 || sh === 4 || sh === 40 || sh === 5 || sh === 50) return true;
                if (sh === 2) wTwos++;
                sh = sc[wOff + y + 675];
                if (sh === 3 || sh === 4 || sh === 40 || sh === 5 || sh === 50) return true;
                if (sh === 2) wTwos++;
                if (wTwos >= 2) return true;
            }
        }
        return false;
    }

    private function getTSSDefenseMoves(role:Number):Array {
        var origPL:Number = GobangConfig.pointsLimit;
        GobangConfig.pointsLimit = LEAF_TSS_DEFENSE_SCAN_LIMIT;
        var moves:Array = _eval.getMoves(role, 0, false, false);
        GobangConfig.pointsLimit = origPL;
        return moves;
    }

    // 防守得利检测：防守方落子后是否有成五点（FIVE shape），且攻方没有
    // 前提：调用前防守方已在棋盘上落子
    // 返回 true = 防守方有成五点且攻方没有 → 防守方必赢
    private function _defenderHasFiveShape(defRole:Number, atkRole:Number):Boolean {
        var sc:Array = _eval.shapeCache;
        var dBase:Number = (defRole === 1 ? 0 : 1) * 900;
        var aBase:Number = (atkRole === 1 ? 0 : 1) * 900;
        var brd:Array = _eval.board;
        var sz:Number = _eval.size;
        var frontier:Array = _eval._frontierList;
        var top:Number = _eval._frontierTop;
        var defHasFive:Boolean = false;
        for (var fi:Number = 0; fi < top; fi++) {
            var fp:Number = frontier[fi];
            var cx:Number = (fp / sz) | 0;
            var cy:Number = fp - cx * sz;
            if (brd[(cx + 1) * 17 + (cy + 1)] !== 0) continue;
            var aIdx:Number = aBase + cx * 15 + cy;
            // 攻方有成五 → 攻方先手可先连五，不触发早退
            if (sc[aIdx] === 5 || sc[aIdx] === 50 ||
                sc[aIdx + 225] === 5 || sc[aIdx + 225] === 50 ||
                sc[aIdx + 450] === 5 || sc[aIdx + 450] === 50 ||
                sc[aIdx + 675] === 5 || sc[aIdx + 675] === 50) {
                return false;
            }
            // 防守方有成五
            if (!defHasFive) {
                var dIdx:Number = dBase + cx * 15 + cy;
                if (sc[dIdx] === 5 || sc[dIdx] === 50 ||
                    sc[dIdx + 225] === 5 || sc[dIdx + 225] === 50 ||
                    sc[dIdx + 450] === 5 || sc[dIdx + 450] === 50 ||
                    sc[dIdx + 675] === 5 || sc[dIdx + 675] === 50) {
                    defHasFive = true;
                }
            }
        }
        return defHasFive;
    }

    private function probeThreatWin(attackerRole:Number, turnRole:Number, plyLeft:Number):Boolean {
        if (_timedOut || plyLeft <= 0 || _tssBudget <= 0) return false;
        _tssBudget--;
        if ((_tssBudget & TIME_CHECK_MASK) === 0 && getTimer() - _startTime > _budgetMs) {
            _timedOut = true;
            return false;
        }

        if (_board.isGameOver()) {
            return _board.getWinner() === attackerRole;
        }

        var moves:Array;
        var i:Number;
        if (turnRole === attackerRole) {
            moves = _eval.getThreatMoves(attackerRole, 3, LEAF_TSS_ATTACK_CAP);
            if (!moves.length && plyLeft >= 4) {
                moves = _eval.getThreatMoves(attackerRole, 2, 2);
            }
            if (!moves.length) return false;
            for (i = 0; i < moves.length; i++) {
                var ax:Number = moves[i][0];
                var ay:Number = moves[i][1];
                _board.put(ax, ay, turnRole);
                _eval.move(ax, ay, turnRole);
                var canForce:Boolean;
                if (_board.isGameOver()) {
                    canForce = (_board.getWinner() === attackerRole);
                } else {
                    canForce = probeThreatWin(attackerRole, -turnRole, plyLeft - 1);
                }
                _eval.undo(ax, ay);
                _board.undo();
                if (canForce) return true;
            }
            return false;
        }

        moves = getTSSDefenseMoves(turnRole);
        if (!moves.length) return false;
        if (moves.length > LEAF_TSS_DEFENSE_CAP) return false;
        for (i = 0; i < moves.length; i++) {
            var dx:Number = moves[i][0];
            var dy:Number = moves[i][1];
            _board.put(dx, dy, turnRole);
            _eval.move(dx, dy, turnRole);
            var defends:Boolean;
            if (_board.isGameOver()) {
                defends = (_board.getWinner() === attackerRole);
            } else if (_defenderHasFiveShape(turnRole, attackerRole)) {
                defends = false; // 防守方有成五点且攻方没有 → 防守方必赢
            } else {
                defends = probeThreatWin(attackerRole, -turnRole, plyLeft - 1);
            }
            _eval.undo(dx, dy);
            _board.undo();
            if (!defends) return false;
        }
        return true;
    }

    // VCF 门控：当前角色是否在 frontier 上有 THREE/FOUR/FIVE/BLOCK_FOUR/BLOCK_FIVE 级威胁
    // 显式枚举，排除 BLOCK_THREE(30) 等非战术形状
    private function _hasThreePlusThreat(role:Number):Boolean {
        var sc:Array = _eval.shapeCache;
        var base:Number = (role === 1 ? 0 : 1) * 900;
        var brd:Array = _eval.board;
        var sz:Number = _eval.size;
        var frontier:Array = _eval._frontierList;
        var top:Number = _eval._frontierTop;
        for (var fi:Number = 0; fi < top; fi++) {
            var fp:Number = frontier[fi];
            var cx:Number = (fp / sz) | 0;
            var cy:Number = fp - cx * sz;
            if (brd[(cx + 1) * 17 + (cy + 1)] !== 0) continue;
            var idx:Number = base + cx * 15 + cy;
            var s0:Number = sc[idx];
            if (s0 === 3 || s0 === 4 || s0 === 5 || s0 === 40 || s0 === 50) return true;
            var s1:Number = sc[idx + 225];
            if (s1 === 3 || s1 === 4 || s1 === 5 || s1 === 40 || s1 === 50) return true;
            var s2:Number = sc[idx + 450];
            if (s2 === 3 || s2 === 4 || s2 === 5 || s2 === 40 || s2 === 50) return true;
            var s3:Number = sc[idx + 675];
            if (s3 === 3 || s3 === 4 || s3 === 5 || s3 === 40 || s3 === 50) return true;
        }
        return false;
    }

    // 非叶节点 VCT 探针：检测 FOUR 级 VCF 和 多方向 THREE 的双活三/四三设置
    private function probeVCFAtNode(role:Number):Boolean {
        var sc:Array = _eval.shapeCache;
        var base:Number = (role === 1 ? 0 : 1) * 900;
        var brd:Array = _eval.board;
        var sz:Number = _eval.size;
        var frontier:Array = _eval._frontierList;
        var top:Number = _eval._frontierTop;
        var candidates:Array = [];
        for (var fi:Number = 0; fi < top; fi++) {
            var fp:Number = frontier[fi];
            var cx:Number = (fp / sz) | 0;
            var cy:Number = fp - cx * sz;
            if (brd[(cx + 1) * 17 + (cy + 1)] !== 0) continue;
            var idx:Number = base + cx * 15 + cy;
            var s0:Number = sc[idx];
            var s1:Number = sc[idx + 225];
            var s2:Number = sc[idx + 450];
            var s3:Number = sc[idx + 675];
            var maxS:Number = s0;
            if (s1 > maxS) maxS = s1;
            if (s2 > maxS) maxS = s2;
            if (s3 > maxS) maxS = s3;
            // FOUR/BLOCK_FOUR：VCF 候选
            var isFour:Boolean = (maxS === 4 || maxS === 40);
            // 双活三潜力：2+ 方向有 THREE → 落子即成双活三/四三
            var threeCount:Number = 0;
            if (s0 === 3) threeCount++;
            if (s1 === 3) threeCount++;
            if (s2 === 3) threeCount++;
            if (s3 === 3) threeCount++;
            if (isFour || threeCount >= 2) {
                candidates.push(cx, cy);
                if (candidates.length >= 8) break; // 最多 4 个候选 (4*2=8)
            }
        }
        if (candidates.length === 0) return false;

        var cLen:Number = candidates.length;
        for (var i:Number = 0; i < cLen; i += 2) {
            var mx:Number = candidates[i];
            var my:Number = candidates[i + 1];
            _board.put(mx, my, role);
            _eval.move(mx, my, role);
            var win:Boolean = false;
            if (_board.isGameOver()) {
                win = (_board.getWinner() === role);
            } else {
                var savedBudget:Number = _tssBudget;
                var vcfBudget:Number = VCF_BUDGET_BASE + _vcfDepthHint * VCF_BUDGET_PER_DEPTH;
                if (vcfBudget > VCF_BUDGET_MAX) vcfBudget = VCF_BUDGET_MAX;
                _tssBudget = vcfBudget;
                var vcfPly:Number = VCF_PLY_BASE + (_vcfDepthHint >> 1);
                if (vcfPly > VCF_PLY_MAX) vcfPly = VCF_PLY_MAX;
                win = probeThreatWin(role, -role, vcfPly);
                _tssBudget = savedBudget;
            }
            _eval.undo(mx, my);
            _board.undo();
            if (win && !_timedOut) {
                _vcfFirstX = mx;
                _vcfFirstY = my;
                return true;
            }
        }
        return false;
    }

    // Solver 风格预搜索：只处理确定性战术走法
    // P1 成五 > P2 防五 > P3 己方活四 > P4a 防对手活四 > P4b 防对手双三
    private function _preSearchTactical(role:Number):Object {
        var opp:Number = -role;
        var sz:Number = _eval.size;
        var brd:Array = _eval.board;
        var sc:Array = _eval.shapeCache;
        var mBase:Number = (role === 1 ? 0 : 1) * 900;
        var oBase:Number = (opp === 1 ? 0 : 1) * 900;
        var frontier:Array = _eval._frontierList;
        var top:Number = _eval._frontierTop;

        var opFiveCount:Number = 0;
        var opFiveX:Number = -1; var opFiveY:Number = -1;
        var myLiveFourX:Number = -1; var myLiveFourY:Number = -1;
        var opLiveFourCount:Number = 0;
        var opLiveFourX:Number = -1; var opLiveFourY:Number = -1;
        var opComboCount:Number = 0;
        var opComboX:Number = -1; var opComboY:Number = -1;

        for (var fi:Number = 0; fi < top; fi++) {
            var fp:Number = frontier[fi];
            var cx:Number = (fp / sz) | 0;
            var cy:Number = fp - cx * sz;
            if (brd[(cx + 1) * 17 + (cy + 1)] !== 0) continue;
            var xyOff:Number = cx * 15 + cy;
            var mIdx:Number = mBase + xyOff;
            var oIdx:Number = oBase + xyOff;

            // P1: 己方成五 → 最高优先级，直接返回
            if (sc[mIdx] === 5 || sc[mIdx] === 50 ||
                sc[mIdx + 225] === 5 || sc[mIdx + 225] === 50 ||
                sc[mIdx + 450] === 5 || sc[mIdx + 450] === 50 ||
                sc[mIdx + 675] === 5 || sc[mIdx + 675] === 50) {
                return {x: cx, y: cy, score: GobangShape.FIVE_SCORE, tag: "P1_myFive"};
            }

            // P2: 对手成五 → 计数所有成五点
            if (sc[oIdx] === 5 || sc[oIdx] === 50 ||
                sc[oIdx + 225] === 5 || sc[oIdx + 225] === 50 ||
                sc[oIdx + 450] === 5 || sc[oIdx + 450] === 50 ||
                sc[oIdx + 675] === 5 || sc[oIdx + 675] === 50) {
                opFiveCount++;
                if (opFiveCount === 1) { opFiveX = cx; opFiveY = cy; }
                if (opFiveCount >= 2) break;
            }

            // P3: 己方活四
            if (myLiveFourX < 0) {
                if (sc[mIdx] === 4 || sc[mIdx + 225] === 4 ||
                    sc[mIdx + 450] === 4 || sc[mIdx + 675] === 4) {
                    myLiveFourX = cx; myLiveFourY = cy;
                }
            }

            // P4a: 对手活四（shape=4，两个成五点，无法防守）
            if (opLiveFourCount < 2) {
                if (sc[oIdx] === 4 || sc[oIdx + 225] === 4 ||
                    sc[oIdx + 450] === 4 || sc[oIdx + 675] === 4) {
                    opLiveFourCount++;
                    if (opLiveFourCount === 1) { opLiveFourX = cx; opLiveFourY = cy; }
                }
            }

            // P4b: 对手复合威胁点检测
            // 双冲四(FOUR_FOUR): 2+ 方向 BLOCK_FOUR(40) → 不可防
            // 冲四活三(FOUR_THREE): BLOCK_FOUR(40) + THREE(3) → 不可防
            // 双活三(THREE_THREE): 2+ 方向 THREE(3) → 近乎不可防
            if (opComboCount < 2) {
                var obc:Number = 0; // BLOCK_FOUR count
                var otc:Number = 0; // THREE count
                var ov0:Number = sc[oIdx]; var ov1:Number = sc[oIdx + 225];
                var ov2:Number = sc[oIdx + 450]; var ov3:Number = sc[oIdx + 675];
                if (ov0 === 40) obc++; else if (ov0 === 3) otc++;
                if (ov1 === 40) obc++; else if (ov1 === 3) otc++;
                if (ov2 === 40) obc++; else if (ov2 === 3) otc++;
                if (ov3 === 40) obc++; else if (ov3 === 3) otc++;
                // 双冲四 / 冲四活三 / 双活三 — 任一组合即为致命复合威胁
                if (obc >= 2 || (obc >= 1 && otc >= 1) || otc >= 2) {
                    opComboCount++;
                    if (opComboCount === 1) { opComboX = cx; opComboY = cy; }
                }
            }
        }

        // P2: 防五
        if (opFiveCount === 1) {
            return {x: opFiveX, y: opFiveY, score: GobangShape.FIVE_SCORE - 1, tag: "P2_blockFive"};
        }
        if (opFiveCount >= 2) {
            return null;
        }

        // P3: 己方活四
        if (myLiveFourX >= 0) {
            return {x: myLiveFourX, y: myLiveFourY, score: GobangShape.FIVE_SCORE - 2, tag: "P3_myFour"};
        }

        // P4a: 防对手活四
        if (opLiveFourCount >= 1) {
            return {x: opLiveFourX, y: opLiveFourY, score: GobangShape.FIVE_SCORE - 3,
                    tag: "P4a_blockFour(" + opLiveFourCount + ")"};
        }

        // P4_combo: 防复合威胁
        if (opComboCount >= 1) {
            return {x: opComboX, y: opComboY, score: GobangShape.FIVE_SCORE - 4,
                    tag: "P4combo(" + opComboCount + ")"};
        }

        return null;
    }

    private function probeLeafTSS(role:Number, cDepth:Number, baseScore:Number):Number {
        // 轻量 TSS：cDepth>=4 即可触发（原为 6），浅层使用更小 budget
        if (cDepth < 4 || _board.history.length < 10 || !hasLeafTSSHint()) {
            return baseScore;
        }
        var cap:Number = (cDepth < 6) ? 20 : LEAF_TSS_NODE_CAP;

        _tssBudget = cap;
        if (probeThreatWin(role, role, LEAF_TSS_MAX_PLY)) {
            var winScore:Number = LEAF_TSS_SCORE - cDepth;
            // 显式缓存：叶节点不走 negamax 的 TT 存储路径
            // depth 用 ONLY_THREE_THRESHOLD（depthLeft 语义，常规搜索总可命中）
            _cache.put(_board.hash(), {
                depth: ONLY_THREE_THRESHOLD, value: winScore,
                moveX: -1, moveY: -1,
                role: role, onlyThree: false, onlyFour: false,
                flag: TT_EXACT
            });
            return winScore;
        }

        _tssBudget = cap;
        if (probeThreatWin(-role, role, LEAF_TSS_MAX_PLY)) {
            var lossScore:Number = cDepth - LEAF_TSS_SCORE;
            _cache.put(_board.hash(), {
                depth: ONLY_THREE_THRESHOLD, value: lossScore,
                moveX: -1, moveY: -1,
                role: role, onlyThree: false, onlyFour: false,
                flag: TT_EXACT
            });
            return lossScore;
        }
        return baseScore;
    }

    public function probeTSS(role:Number, maxPly:Number):Boolean {
        if (maxPly === undefined || maxPly < 1) maxPly = LEAF_TSS_MAX_PLY;
        if (!hasLeafTSSHint()) return false;
        _tssBudget = LEAF_TSS_NODE_CAP;
        return probeThreatWin(role, _board.role, maxPly);
    }

    public function probeTSSWithBudget(role:Number, maxPly:Number, budgetMs:Number):Boolean {
        if (maxPly === undefined || maxPly < 1) maxPly = LEAF_TSS_MAX_PLY;
        if (budgetMs === undefined || budgetMs < 1) budgetMs = DEFAULT_BUDGET_MS;
        if (!hasLeafTSSHint()) return false;

        var savedBudget:Number = _budgetMs;
        var savedStart:Number = _startTime;
        var savedTimedOut:Boolean = _timedOut;
        var savedNodeCount:Number = _nodeCount;
        var savedTssBudget:Number = _tssBudget;

        _budgetMs = budgetMs;
        _startTime = getTimer();
        _timedOut = false;
        _nodeCount = 0;
        _tssBudget = LEAF_TSS_NODE_CAP;

        var forced:Boolean = probeThreatWin(role, _board.role, maxPly);
        var timedOut:Boolean = _timedOut;

        _budgetMs = savedBudget;
        _startTime = savedStart;
        _timedOut = savedTimedOut;
        _nodeCount = savedNodeCount;
        _tssBudget = savedTssBudget;

        return forced && !timedOut;
    }

    // ===== negamax + LMR + Killer + leaf TSS =====
    private function negamax(role:Number, depthLeft:Number, cDepth:Number,
            alpha:Number, beta:Number, onlyThree:Boolean, onlyFour:Boolean):Void {
        _nodeCount++;
        if (_budgetMs <= 32 || (_nodeCount & TIME_CHECK_MASK) === 0) {
            if (getTimer() - _startTime > _budgetMs) {
                _timedOut = true;
            }
        }

        if (depthLeft <= 0 || _board.isGameOver() || _timedOut) {
            var winner:Number = _board.getWinner();
            if (winner !== 0) {
                _nmS = (GobangShape.FIVE_SCORE - cDepth) * winner * role;
            } else {
                var leafScore:Number = _eval.evaluate(role);
                if (!_timedOut && depthLeft <= 0) {
                    leafScore = probeLeafTSS(role, cDepth, leafScore);
                }
                _nmS = leafScore;
            }
            _nmX = -1; _nmY = -1;
            return;
        }

        // 缓存查询（含 bound type 判断 + 迭代加深 depth slack）
        var hash:String = _board.hash();
        var useOnlyThree:Boolean = onlyThree || cDepth > ONLY_THREE_THRESHOLD;
        var prev:Object = _cache.get(hash);
        if (prev !== null
                && prev.role === role
                && prev.onlyThree === useOnlyThree
                && prev.onlyFour === onlyFour) {
            var ttFlag:Number = prev.flag;
            var ttVal:Number = prev.value;
            if (prev.depth >= depthLeft) {
                // 完全匹配：depth 足够，可做截断
                if (ttFlag === TT_EXACT
                    || (ttFlag === TT_LOWER && ttVal >= beta)
                    || (ttFlag === TT_UPPER && ttVal <= alpha)) {
                    _statTTHits++;
                    _nmS = ttVal; _nmX = prev.moveX; _nmY = prev.moveY;
                    return;
                }
                // flag 不匹配：只用 TT move 做排序，不用 value
                _statTTMissFlag++;
            } else if (prev.depth >= depthLeft - 2) {
                // 浅层匹配（迭代加深跨轮）：只用边界收窄 alpha-beta 窗口，不做截断
                _statTTShallow++;
                // LOWER 边界 = 下界估计：可以尝试收紧 alpha
                if (ttFlag === TT_LOWER && ttVal > alpha) alpha = ttVal;
                // UPPER 边界 = 上界估计：可以尝试收紧 beta
                if (ttFlag === TT_UPPER && ttVal < beta) beta = ttVal;
                if (alpha >= beta) {
                    _statTTHits++;
                    _nmS = ttVal; _nmX = prev.moveX; _nmY = prev.moveY;
                    return;
                }
            }
        }
        var moves:Array = _eval.getMoves(role, cDepth, useOnlyThree, onlyFour);
        if (!moves.length) {
            _nmS = _eval.evaluate(role); _nmX = -1; _nmY = -1;
            return;
        }
        // 单候选快速路径：forced move 直接递归，跳过排序和循环开销
        if (moves.length === 1) {
            var fx:Number = moves[0][0];
            var fy:Number = moves[0][1];
            _board.put(fx, fy, role);
            _eval.move(fx, fy, role);
            negamax(-role, depthLeft - 1, cDepth + 1, -beta, -alpha, onlyThree, onlyFour);
            _nmS = -_nmS;
            _eval.undo(fx, fy);
            _board.undo();
            _nmX = fx; _nmY = fy;
            return;
        }

        // Move ordering: cache move → killer (位置 1，保留 eval-best 在位置 0)
        if (prev !== null) {
            promoteMove(moves, prev.moveX, prev.moveY);
        }
        var kBase:Number = cDepth + cDepth;
        if (kBase < 24 && moves.length > 1) {
            var k0:Number = _killers[kBase];
            if (k0 >= 0) {
                var k0y:Number = k0 % 15;
                var k0x:Number = (k0 - k0y) / 15;
                promoteMoveAt(moves, k0x, k0y, 1);
            }
        }
        // History heuristic 排序：对 pos 2+ 的走法按历史截断成功次数降序
        if (moves.length > 2) {
            var hArr:Array = _history;
            for (var si:Number = 3; si < moves.length; si++) {
                var siMove:Array = moves[si];
                var siKey:Number = hArr[siMove[0] * 15 + siMove[1]];
                var sk:Number = si - 1;
                while (sk >= 2 && hArr[moves[sk][0] * 15 + moves[sk][1]] < siKey) {
                    moves[sk + 1] = moves[sk];
                    sk--;
                }
                moves[sk + 1] = siMove;
            }
        }
        // 非叶节点 VCT 探针：depthLeft>=3 且已深入 2 层以上，两级门控
        if (depthLeft >= 3 && cDepth >= 2 && !_timedOut) {
            // Gate 1: 时间门控 — 已用 >60% 预算则跳过，保留预算给主搜索
            if (getTimer() - _startTime > _budgetMs * VCF_TIME_RATIO) {
                _statVCFSkipped++;
            // Gate 2: 威胁门控 — 当前角色无 THREE+ 级 shape 则无着力点
            } else if (!_hasThreePlusThreat(role)) {
                _statVCFSkipped++;
            } else {
                _statVCFProbes++;
                _vcfDepthHint = depthLeft;
                if (probeVCFAtNode(role)) {
                    _statVCFHits++;
                    _nmS = LEAF_TSS_SCORE - cDepth;
                    _nmX = _vcfFirstX;
                    _nmY = _vcfFirstY;
                    return;
                }
            }
        }

        var origAlpha:Number = alpha;
        var bestScore:Number = -MAX;
        var bestX:Number = -1;
        var bestY:Number = -1;
        // LMR 只留在更深、更靠后的 quiet move，避免过早错杀防守手
        var useLMR:Boolean = (depthLeft >= 5 && !onlyThree && !onlyFour);

        for (var i:Number = 0; i < moves.length; i++) {
            var mx:Number = moves[i][0];
            var my:Number = moves[i][1];
            _board.put(mx, my, role);
            _eval.move(mx, my, role);

            // ===== Late Move Reduction =====
            // 排名更靠后的走法先做浅搜（depth-2），若不超过 alpha 则跳过
            if (useLMR && i >= 4) {
                negamax(-role, depthLeft - 2, cDepth + 1, -(alpha + 1), -alpha, onlyThree, onlyFour);
                if (-_nmS <= alpha || _timedOut) {
                    _eval.undo(mx, my);
                    _board.undo();
                    continue;
                }
                // 浅搜超过 alpha → 需要全深度重搜
            }

            // ===== PVS: 非第一手用 zero-window 先探 =====
            if (i > 0) {
                negamax(-role, depthLeft - 1, cDepth + 1, -(alpha + 1), -alpha, onlyThree, onlyFour);
                if (-_nmS > alpha && -_nmS < beta && !_timedOut) {
                    negamax(-role, depthLeft - 1, cDepth + 1, -beta, -alpha, onlyThree, onlyFour);
                }
            } else {
                negamax(-role, depthLeft - 1, cDepth + 1, -beta, -alpha, onlyThree, onlyFour);
            }
            var currentValue:Number = -_nmS;
            _eval.undo(mx, my);
            _board.undo();

            if (bestX < 0 || currentValue > bestScore) {
                bestScore = currentValue;
                bestX = mx;
                bestY = my;
            }
            if (currentValue > alpha) alpha = currentValue;
            if (_timedOut || alpha >= beta || currentValue >= GobangShape.FIVE_SCORE) {
                // 记录 killer move
                if (alpha >= beta && !_timedOut) {
                    // killer move 更新
                    if (kBase < 24) {
                        var flatK:Number = mx * 15 + my;
                        if (_killers[kBase] !== flatK) {
                            _killers[kBase + 1] = _killers[kBase];
                            _killers[kBase] = flatK;
                        }
                    }
                    // history heuristic 更新
                    _history[mx * 15 + my] += depthLeft * depthLeft;
                }
                break;
            }
        }

        // 缓存存储（含 bound type）
        // 存储 useOnlyThree（实际走法生成模式）而非参数 onlyThree
        // 这保证 cDepth>6 强制 THREE-only 的条目不会被普通查询错误匹配
        // 从而可以安全移除 cDepth < ONLY_THREE_THRESHOLD 守卫
        if (!_timedOut && bestX >= 0) {
            var storeFlag:Number = TT_EXACT;
            if (bestScore <= origAlpha) storeFlag = TT_UPPER;
            else if (bestScore >= beta) storeFlag = TT_LOWER;
            _cache.put(hash, {
                depth: depthLeft,
                value: bestScore,
                moveX: bestX,
                moveY: bestY,
                role: role,
                onlyThree: useOnlyThree,
                onlyFour: onlyFour,
                flag: storeFlag
            });
        }

        _nmS = bestScore; _nmX = bestX; _nmY = bestY;
    }

    // ===== 异步分帧搜索 API =====

    public function searchStart(role:Number, maxDepth:Number, enableVCT:Boolean):Void {
        _asyncRole = role;
        _asyncMaxDepth = normalizeDepth(maxDepth === undefined ? GobangConfig.searchDepth : maxDepth);
        _asyncEnableVCT = (enableVCT === undefined ? true : enableVCT) && _eval.history.length >= 8;
        _asyncPhase = _asyncEnableVCT ? 1 : 2;
        _asyncDone = false;
        _asyncTotalNodes = 0;
        _asyncCurrentDepth = 2;
        _asyncBestResult = {x: -1, y: -1, score: _eval.evaluate(role)};
        _asyncVCTStartTime = getTimer();
        _asyncLastCompletedDepth = 0;
        _asyncMoves = null;
        _asyncMoveIndex = 0;
        _asyncTargetDepth = 0;
        _rootMoveIdx = 0;
        _rootMoveTotal = 0;
        _asyncBridgeBaseDepth = 0;
        _resetKillers();
        _resetHistory();

        // 预搜索：确定性战术走法直接完成
        var tactical:Object = _preSearchTactical(role);
        if (tactical !== null) {
            _statPreSearch++;
            _asyncBestResult = {x: tactical.x, y: tactical.y, score: tactical.score,
                                phaseLabel: tactical.tag};
            _asyncDone = true;
        }
    }

    // 每帧调用，返回 {done, phase, x, y, score, nodes, phaseLabel, rootIdx, rootTotal}
    public function step(frameBudgetMs:Number):Object {
        if (frameBudgetMs === undefined) frameBudgetMs = 40;
        if (_asyncDone) {
            var doneLabel:String = (_asyncBestResult.phaseLabel !== undefined)
                ? _asyncBestResult.phaseLabel : "done";
            return {done: true, phase: 4, x: _asyncBestResult.x, y: _asyncBestResult.y,
                    score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: doneLabel,
                    rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal,
                    secondX: _asyncBestResult.secondX, secondY: _asyncBestResult.secondY,
                    secondScore: _asyncBestResult.secondScore,
                    secondInherited: _asyncBestResult.secondInherited};
        }

        if (_asyncPhase === 1) {
            // VCT 时间上限：最多消耗 24ms（约 3 帧），把预算留给常规搜索
            if (getTimer() - _asyncVCTStartTime > 24) {
                _asyncPhase = 2;
                _asyncMoves = null;
            }
            if (_asyncPhase === 1 && _asyncMoves === null) {
                if (!initAsyncRootSearch(_asyncMaxDepth + 2, true, false)) {
                    _asyncPhase = 2;
                    _asyncMoves = null;
                }
            }
            if (_asyncPhase === 1) {
                var vct:Object = stepAsyncRootSearch(frameBudgetMs);
                _asyncTotalNodes += _nodeCount;
                if (vct.done && vct.score >= GobangShape.FIVE_SCORE) {
                    _asyncDone = true;
                    return {done: true, phase: 1, x: _asyncBestResult.x, y: _asyncBestResult.y, score: _asyncBestResult.score,
                            nodes: _asyncTotalNodes, phaseLabel: "vct_win",
                            rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal,
                            secondX: _asyncBestResult.secondX, secondY: _asyncBestResult.secondY,
                            secondScore: _asyncBestResult.secondScore,
                    secondInherited: _asyncBestResult.secondInherited};
                }
                if (!vct.done) {
                    return {done: false, phase: 1, x: vct.x, y: vct.y, score: vct.score,
                            nodes: _asyncTotalNodes, phaseLabel: "vct",
                            rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
                }
                _asyncPhase = 2;
            }
        }

        if (_asyncPhase === 2) {
            if (_asyncMoves === null) {
                var curDepth:Number = _asyncCurrentDepth;
                if (!initAsyncRootSearch(curDepth, false, false)) {
                    _asyncDone = true;
                    return {done: true, phase: 2, x: -1, y: -1, score: _eval.evaluate(_asyncRole),
                            nodes: _asyncTotalNodes, phaseLabel: "no_move",
                            rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
                }
            }
            var curD:Number = _asyncCurrentDepth;
            var mr:Object = stepAsyncRootSearch(frameBudgetMs);
            _asyncTotalNodes += _nodeCount;
            if (mr.done) {
                trace("[DEPTH] d=" + curD + " done, lastCompleted=" + _asyncLastCompletedDepth
                    + " maxDepth=" + _asyncMaxDepth + " best=(" + _asyncBestResult.x + "," + _asyncBestResult.y + ")");
            }

            if (mr.done && _asyncBestResult.x >= 0 && _asyncBestResult.score >= GobangShape.FIVE_SCORE) {
                _asyncDone = true;
                return {done: true, phase: 2, x: _asyncBestResult.x, y: _asyncBestResult.y, score: _asyncBestResult.score,
                        nodes: _asyncTotalNodes, phaseLabel: "minmax_win",
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal,
                        secondX: _asyncBestResult.secondX, secondY: _asyncBestResult.secondY,
                        secondScore: _asyncBestResult.secondScore,
                    secondInherited: _asyncBestResult.secondInherited};
            }

            if (!mr.done) {
                return {done: false, phase: 2, x: mr.x, y: mr.y,
                        score: mr.score, nodes: _asyncTotalNodes,
                        phaseLabel: "minmax_d" + curD,
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
            }

            if (curD >= _asyncMaxDepth) {
                if (tryStartAsyncBridgeProbe()) {
                    return {done: false, phase: 3, x: _asyncBestResult.x, y: _asyncBestResult.y,
                            score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: "bridgeprobe_init",
                            rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
                }
                _asyncDone = true;
                var label:String = (_asyncLastCompletedDepth > 0) ? ("minmax_d" + _asyncLastCompletedDepth) : "done";
                return {done: true, phase: 2, x: _asyncBestResult.x, y: _asyncBestResult.y,
                        score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: label,
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal,
                        secondX: _asyncBestResult.secondX, secondY: _asyncBestResult.secondY,
                        secondScore: _asyncBestResult.secondScore,
                    secondInherited: _asyncBestResult.secondInherited};
            }

            _asyncCurrentDepth = curD + 2;
            _asyncMoves = null;
            return {done: false, phase: 2, x: _asyncBestResult.x, y: _asyncBestResult.y,
                    score: _asyncBestResult.score, nodes: _asyncTotalNodes,
                    phaseLabel: "minmax_d" + curD,
                    rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
        }

        if (_asyncPhase === 3) {
            var origPL:Number = GobangConfig.pointsLimit;
            var probePL:Number = (_asyncTargetDepth >= BRIDGE_PROBE_DEEP_DEPTH)
                ? BRIDGE_PROBE_DEEP_POINTS_LIMIT
                : BRIDGE_PROBE_POINTS_LIMIT;
            if (origPL > probePL) {
                GobangConfig.pointsLimit = probePL;
            }
            var bp:Object = stepAsyncRootSearch(frameBudgetMs);
            GobangConfig.pointsLimit = origPL;
            _asyncTotalNodes += _nodeCount;

            if (!bp.done) {
                return {done: false, phase: 3, x: bp.x, y: bp.y, score: bp.score,
                        nodes: _asyncTotalNodes, phaseLabel: "bridgeprobe_d" + _asyncTargetDepth,
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
            }

            _asyncDone = true;
            return {done: true, phase: 3, x: _asyncBestResult.x, y: _asyncBestResult.y,
                    score: _asyncBestResult.score, nodes: _asyncTotalNodes,
                    phaseLabel: "bridgeprobe_d" + _asyncTargetDepth,
                    rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal,
                    secondX: _asyncBestResult.secondX, secondY: _asyncBestResult.secondY,
                    secondScore: _asyncBestResult.secondScore,
                    secondInherited: _asyncBestResult.secondInherited};
        }

        _asyncDone = true;
        return {done: true, phase: 4, x: _asyncBestResult.x, y: _asyncBestResult.y,
                score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: "done",
                rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal,
                secondX: _asyncBestResult.secondX, secondY: _asyncBestResult.secondY,
                secondScore: _asyncBestResult.secondScore};
    }

    public function isAsyncDone():Boolean {
        return _asyncDone;
    }

    public function resetStats():Void {
        _statTTHits = 0; _statTTMissFlag = 0;
        _statVCFProbes = 0; _statVCFHits = 0; _statVCFSkipped = 0;
        _statPreSearch = 0; _statTTShallow = 0;
    }

    public function getStats():Object {
        return {ttHits: _statTTHits, ttMissFlag: _statTTMissFlag,
                vcfProbes: _statVCFProbes, vcfHits: _statVCFHits,
                vcfSkipped: _statVCFSkipped, preSearch: _statPreSearch,
                ttShallow: _statTTShallow};
    }

    public function getCompletedDepth():Number {
        return _asyncLastCompletedDepth;
    }
}
