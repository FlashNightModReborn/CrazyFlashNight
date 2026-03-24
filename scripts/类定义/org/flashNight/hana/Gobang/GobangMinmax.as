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
    // 根候选短名单：depth>=4 时只深搜前 N 个根走法
    private static var ROOT_SHORTLIST:Number = 4;

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
    private var _asyncWorkingBestX:Number;
    private var _asyncWorkingBestY:Number;

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
        _asyncWorkingBestX = -1;
        _asyncWorkingBestY = -1;
        _rootMoveIdx = 0;
        _rootMoveTotal = 0;
    }

    private function _resetKillers():Void {
        var k:Array = _killers;
        var i:Number = 23;
        while (i >= 0) { k[i] = -1; i--; }
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

        // 迭代加深 + 根短名单 + aspiration windows
        for (var depth:Number = 2; depth <= maxDepth; depth += 2) {
            var rootLim:Number = (depth >= 4) ? ROOT_SHORTLIST : 0;
            var iAlpha:Number = -MAX;
            var iBeta:Number = MAX;
            // Aspiration: depth>=4 且上一轮有有效分数
            if (depth >= 4 && best.score > -MAX / 2 && best.score < MAX / 2) {
                iAlpha = best.score - 500;
                iBeta = best.score + 500;
            }
            var cur:Object = searchFixedDepth(role, depth, false, false, prefX, prefY, iAlpha, iBeta, rootLim);
            // Aspiration 失败 → 全窗口重搜
            if (!_timedOut && (cur.score <= iAlpha || cur.score >= iBeta)) {
                cur = searchFixedDepth(role, depth, false, false, prefX, prefY, -MAX, MAX, rootLim);
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
            if (_board.board[center][center] === 0 && !hasMove(moves, center, center)) {
                moves.push([center, center]);
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

        // 根候选短名单：depth>=4 非 VCT 时截断
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
            if (_board.board[center][center] === 0 && !hasMove(_asyncMoves, center, center)) {
                _asyncMoves.push([center, center]);
            }
        }
        _asyncMoveIndex = 0;
        _asyncAlpha = -MAX;
        _asyncBeta = MAX;
        _asyncWorkingBestScore = -MAX;
        _asyncWorkingBestX = -1;
        _asyncWorkingBestY = -1;
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

        // 根候选短名单：depth>=4 非 VCT 时截断
        if (depth >= 4 && !onlyThree && !onlyFour && _asyncMoves.length > ROOT_SHORTLIST) {
            _asyncMoves.length = ROOT_SHORTLIST;
        }

        // Aspiration: depth>=4 且上一轮有有效分数
        if (depth >= 4 && _asyncBestResult.score > -MAX / 2 && _asyncBestResult.score < MAX / 2) {
            _asyncAlpha = _asyncBestResult.score - 500;
            _asyncBeta = _asyncBestResult.score + 500;
        }

        _rootMoveTotal = _asyncMoves.length;
        return true;
    }

    private function stepAsyncRootSearch(frameBudgetMs:Number):Object {
        beginTimedSearch(frameBudgetMs);

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
            _eval.undo(mx, my);
            _board.undo();
            _asyncMoveIndex++;

            if (!_timedOut) {
                if (_asyncWorkingBestX < 0 || currentValue > _asyncWorkingBestScore) {
                    _asyncWorkingBestScore = currentValue;
                    _asyncWorkingBestX = mx;
                    _asyncWorkingBestY = my;
                }
                if (currentValue > _asyncAlpha) _asyncAlpha = currentValue;
                if (_asyncAlpha >= _asyncBeta || currentValue >= GobangShape.FIVE_SCORE) {
                    _asyncMoveIndex = _asyncMoves.length;
                    break;
                }
            } else if (_asyncWorkingBestX < 0) {
                _asyncWorkingBestScore = currentValue;
                _asyncWorkingBestX = mx;
                _asyncWorkingBestY = my;
                break;
            } else {
                break;
            }
        }

        var finished:Boolean = (_asyncMoveIndex >= _asyncMoves.length);
        if (finished && _asyncWorkingBestX >= 0) {
            _asyncBestResult = {
                x: _asyncWorkingBestX,
                y: _asyncWorkingBestY,
                score: _asyncWorkingBestScore
            };
            _asyncLastCompletedDepth = _asyncTargetDepth;
            _asyncMoves = null;
        }

        var showX:Number = finished ? _asyncBestResult.x : _asyncWorkingBestX;
        var showY:Number = finished ? _asyncBestResult.y : _asyncWorkingBestY;
        var showScore:Number = finished ? _asyncBestResult.score : _asyncWorkingBestScore;
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

    // ===== negamax + Null Move + LMR + Killer =====
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
                _nmS = _eval.evaluate(role);
            }
            _nmX = -1; _nmY = -1;
            return;
        }

        // 缓存查询
        var hash:String = _board.hash();
        var prev:Object = _cache.get(hash);
        if (prev !== null
                && prev.role === role
                && prev.onlyThree === onlyThree
                && prev.onlyFour === onlyFour
                && prev.depth >= depthLeft) {
            _nmS = prev.value; _nmX = prev.moveX; _nmY = prev.moveY;
            return;
        }

        // ===== Null Move Pruning =====
        // 给对手一个"白送手"，若仍 >= beta 则当前局面极优，直接剪枝
        // 条件：深度足够、非 VCT 搜索、非赢棋附近
        if (depthLeft >= 4 && !onlyThree && !onlyFour && beta < GobangShape.FIVE_SCORE) {
            // R=2 reduction: search at depthLeft - 3 (skip 1 + reduce 2)
            negamax(-role, depthLeft - 3, cDepth + 1, -beta, -(beta - 1), false, false);
            if (-_nmS >= beta && !_timedOut) {
                _nmS = beta; _nmX = -1; _nmY = -1;
                return;
            }
        }

        var useOnlyThree:Boolean = onlyThree || cDepth > ONLY_THREE_THRESHOLD;
        var moves:Array = _eval.getMoves(role, cDepth, useOnlyThree, onlyFour);
        if (!moves.length) {
            _nmS = _eval.evaluate(role); _nmX = -1; _nmY = -1;
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

        var bestScore:Number = -MAX;
        var bestX:Number = -1;
        var bestY:Number = -1;
        // LMR 条件：深度足够 且 非 VCT
        var useLMR:Boolean = (depthLeft >= 3 && !onlyThree && !onlyFour);

        for (var i:Number = 0; i < moves.length; i++) {
            var mx:Number = moves[i][0];
            var my:Number = moves[i][1];
            _board.put(mx, my, role);
            _eval.move(mx, my, role);

            // ===== Late Move Reduction =====
            // 排名第 4+ 的走法先做浅搜（depth-2），若不超过 alpha 则跳过
            if (useLMR && i >= 3) {
                negamax(-role, depthLeft - 2, cDepth + 1, -(alpha + 1), -alpha, onlyThree, onlyFour);
                if (-_nmS <= alpha || _timedOut) {
                    _eval.undo(mx, my);
                    _board.undo();
                    continue;
                }
                // 浅搜超过 alpha → 需要全深度重搜（落入下方）
            }

            negamax(-role, depthLeft - 1, cDepth + 1, -beta, -alpha, onlyThree, onlyFour);
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
                if (alpha >= beta && !_timedOut && kBase < 24) {
                    var flatK:Number = mx * 15 + my;
                    if (_killers[kBase] !== flatK) {
                        _killers[kBase + 1] = _killers[kBase];
                        _killers[kBase] = flatK;
                    }
                }
                break;
            }
        }

        // 缓存存储
        if (!_timedOut && bestX >= 0 && (cDepth < ONLY_THREE_THRESHOLD || onlyThree || onlyFour)) {
            _cache.put(hash, {
                depth: depthLeft,
                value: bestScore,
                moveX: bestX,
                moveY: bestY,
                role: role,
                onlyThree: onlyThree,
                onlyFour: onlyFour
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
        _resetKillers();
    }

    // 每帧调用，返回 {done, phase, x, y, score, nodes, phaseLabel, rootIdx, rootTotal}
    public function step(frameBudgetMs:Number):Object {
        if (frameBudgetMs === undefined) frameBudgetMs = 40;
        if (_asyncDone) {
            return {done: true, phase: 4, x: _asyncBestResult.x, y: _asyncBestResult.y,
                    score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: "done",
                    rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
        }

        if (_asyncPhase === 1) {
            if (_asyncMoves === null) {
                if (!initAsyncRootSearch(_asyncMaxDepth + 4, true, false)) {
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
                            rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
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

            if (mr.done && _asyncBestResult.x >= 0 && _asyncBestResult.score >= GobangShape.FIVE_SCORE) {
                _asyncDone = true;
                return {done: true, phase: 2, x: _asyncBestResult.x, y: _asyncBestResult.y, score: _asyncBestResult.score,
                        nodes: _asyncTotalNodes, phaseLabel: "minmax_win",
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
            }

            if (!mr.done) {
                return {done: false, phase: 2, x: mr.x, y: mr.y,
                        score: mr.score, nodes: _asyncTotalNodes,
                        phaseLabel: "minmax_d" + curD,
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
            }

            if (curD >= _asyncMaxDepth) {
                _asyncDone = true;
                var label:String = (_asyncLastCompletedDepth > 0) ? ("minmax_d" + _asyncLastCompletedDepth) : "done";
                return {done: true, phase: 2, x: _asyncBestResult.x, y: _asyncBestResult.y,
                        score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: label,
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
            }

            _asyncCurrentDepth = curD + 2;
            _asyncMoves = null;
            return {done: false, phase: 2, x: _asyncBestResult.x, y: _asyncBestResult.y,
                    score: _asyncBestResult.score, nodes: _asyncTotalNodes,
                    phaseLabel: "minmax_d" + curD,
                    rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
        }

        _asyncDone = true;
        return {done: true, phase: 4, x: _asyncBestResult.x, y: _asyncBestResult.y,
                score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: "done",
                rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
    }

    public function isAsyncDone():Boolean {
        return _asyncDone;
    }
}
