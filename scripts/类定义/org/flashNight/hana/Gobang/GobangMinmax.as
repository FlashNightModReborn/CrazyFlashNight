import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangCache;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangMinmax {
    private static var MAX:Number = 1000000000;
    private static var ONLY_THREE_THRESHOLD:Number = 6;

    private var _board:GobangBoard;
    private var _eval:GobangEval;
    private var _cache:GobangCache;
    private var _nodeCount:Number;
    private var _startTime:Number;
    private var _timedOut:Boolean;
    private var _budgetMs:Number;

    // 异步搜索状态
    // phase: 0=IDLE, 1=VCT, 2=MINMAX, 3=COUNTER_VCT, 4=DONE
    private var _asyncPhase:Number;
    private var _asyncRole:Number;
    private var _asyncMaxDepth:Number;
    private var _asyncEnableVCT:Boolean;
    private var _asyncBestResult:Object;
    private var _asyncVCTResult:Array;
    private var _asyncMMResult:Array;
    private var _asyncTotalNodes:Number;
    private var _asyncCurrentDepth:Number;
    private var _asyncDone:Boolean;

    // 根层进度追踪（negamax cDepth===0 时写入）
    private var _rootMoveIdx:Number;
    private var _rootMoveTotal:Number;
    private var _asyncVCTStartTime:Number; // VCT 开始时间（跨帧累计）

    public function GobangMinmax(board:GobangBoard, eval:GobangEval) {
        _board = board;
        _eval = eval;
        _cache = new GobangCache(100000);
        _nodeCount = 0;
        _timedOut = false;
        _budgetMs = 3000;
        _asyncPhase = 0;
        _asyncDone = true;
        _asyncTotalNodes = 0;
        _rootMoveIdx = 0;
        _rootMoveTotal = 0;
    }

    // ===== 同步搜索（保留兼容） =====
    public function search(role:Number, maxDepth:Number, enableVCT:Boolean):Object {
        if (maxDepth === undefined) maxDepth = GobangConfig.searchDepth;
        if (enableVCT === undefined) enableVCT = true;
        _nodeCount = 0;
        _timedOut = false;
        _budgetMs = 3000;
        _startTime = getTimer();

        // 棋子 < 8 时无算杀可能
        if (enableVCT && _eval.history.length < 8) enableVCT = false;

        if (!enableVCT) {
            var result:Array = negamax(role, maxDepth, 0, -MAX, MAX, false, false);
            return {x: result[1], y: result[2], score: result[0], nodes: _nodeCount, timedOut: _timedOut};
        }

        var vctDepth:Number = maxDepth + 4;

        // 1. 先看自己有没有算杀
        var vctResult:Array = negamax(role, vctDepth, 0, -MAX, MAX, true, false);
        if (vctResult[0] >= GobangShape.FIVE_SCORE) {
            return {x: vctResult[1], y: vctResult[2], score: vctResult[0], nodes: _nodeCount, timedOut: _timedOut};
        }

        // 2. 普通 minimax
        _timedOut = false;
        var mmResult:Array = negamax(role, maxDepth, 0, -MAX, MAX, false, false);
        var mmValue:Number = mmResult[0];
        var mmX:Number = mmResult[1];
        var mmY:Number = mmResult[2];

        if (mmX < 0) {
            return {x: mmX, y: mmY, score: mmValue, nodes: _nodeCount, timedOut: _timedOut};
        }

        // 3. 检查对手反杀：走完自己的最优步后，对手是否有算杀
        _board.put(mmX, mmY, role);
        _eval.move(mmX, mmY, role);
        var rev:Object = _board.reverse();
        var revBoard:GobangBoard = GobangBoard(rev.board);
        var revEval:GobangEval = GobangEval(rev.eval);
        var revMM:GobangMinmax = new GobangMinmax(revBoard, revEval);
        revMM._startTime = _startTime;
        revMM._timedOut = _timedOut;
        var counterVCT:Array = revMM.negamax(role, vctDepth, 0, -MAX, MAX, true, false);
        _eval.undo(mmX, mmY);
        _board.undo();

        if (mmValue < GobangShape.FIVE_SCORE && counterVCT[0] >= GobangShape.FIVE_SCORE) {
            // 对手有反杀，检查不走棋时对手是否同样有杀
            var rev2:Object = _board.reverse();
            var rev2Board:GobangBoard = GobangBoard(rev2.board);
            var rev2Eval:GobangEval = GobangEval(rev2.eval);
            var rev2MM:GobangMinmax = new GobangMinmax(rev2Board, rev2Eval);
            rev2MM._startTime = _startTime;
            rev2MM._timedOut = _timedOut;
            var counterVCT2:Array = rev2MM.negamax(role, vctDepth, 0, -MAX, MAX, true, false);
            // 如果走棋后对手杀棋没有变长，说明走错了，用对手的杀棋走法来防守
            if (counterVCT[1] >= 0 && counterVCT[1] < 15 && counterVCT2[0] >= GobangShape.FIVE_SCORE) {
                return {x: counterVCT[1], y: counterVCT[2], score: mmValue, nodes: _nodeCount, timedOut: _timedOut};
            }
        }

        return {x: mmX, y: mmY, score: mmValue, nodes: _nodeCount, timedOut: _timedOut};
    }

    // 通用 negamax — onlyThree/onlyFour 控制 VCT/VCF 模式
    // result: [value, moveX, moveY]
    private function negamax(role:Number, depth:Number, cDepth:Number,
            alpha:Number, beta:Number, onlyThree:Boolean, onlyFour:Boolean):Array {
        _nodeCount++;
        // 每 100 节点检查一次时间预算
        if ((_nodeCount & 63) === 0) {
            if (getTimer() - _startTime > _budgetMs) {
                _timedOut = true;
            }
        }

        if (cDepth >= depth || _board.isGameOver() || _timedOut) {
            var winner:Number = _board.getWinner();
            var score:Number;
            if (winner !== 0) {
                score = GobangShape.FIVE_SCORE * winner * role;
            } else {
                score = _eval.evaluate(role);
            }
            return [score, -1, -1];
        }

        // 缓存查询
        var hash:String = _board.hash();
        var prev:Object = _cache.get(hash);
        if (prev !== null && prev.role === role) {
            var absVal:Number = prev.value;
            if (absVal < 0) absVal = -absVal;
            if (absVal >= GobangShape.FIVE_SCORE || prev.depth >= depth - cDepth) {
                if (prev.onlyThree === onlyThree && prev.onlyFour === onlyFour) {
                    return [prev.value, prev.moveX, prev.moveY];
                }
            }
        }

        var value:Number = -MAX;
        var bestX:Number = -1;
        var bestY:Number = -1;

        // 获取走法 — VCT/VCF 模式传递过滤参数
        var useOnlyThree:Boolean = onlyThree || cDepth > ONLY_THREE_THRESHOLD;
        var moves:Array = _eval.getMoves(role, cDepth, useOnlyThree, onlyFour);

        // 添加中心点（仅普通搜索）
        if (cDepth === 0 && !onlyThree && !onlyFour) {
            var center:Number = Math.floor(_board.size / 2);
            if (_board.board[center][center] === 0) {
                moves.push([center, center]);
            }
        }

        if (!moves.length) {
            return [_eval.evaluate(role), -1, -1];
        }

        // 根层记录总走法数
        if (cDepth === 0) {
            _rootMoveTotal = moves.length;
        }

        // 迭代加深
        for (var d:Number = cDepth + 1; d <= depth; d++) {
            if (d % 2 !== 0) continue;
            var breakAll:Boolean = false;
            for (var i:Number = 0; i < moves.length; i++) {
                // 根层记录当前进度
                if (cDepth === 0) {
                    _rootMoveIdx = i;
                }
                var mx:Number = moves[i][0];
                var my:Number = moves[i][1];
                _board.put(mx, my, role);
                _eval.move(mx, my, role);
                var child:Array = negamax(-role, d, cDepth + 1, -beta, -alpha, onlyThree, onlyFour);
                var currentValue:Number = -child[0];
                _eval.undo(mx, my);
                _board.undo();

                if (_timedOut) {
                    if (bestX === -1) { bestX = mx; bestY = my; value = currentValue; }
                    return [value, bestX, bestY];
                }

                if (currentValue >= GobangShape.FIVE_SCORE || d === depth) {
                    if (currentValue > value) {
                        value = currentValue;
                        bestX = mx;
                        bestY = my;
                    }
                }
                if (value > alpha) alpha = value;
                if (alpha >= GobangShape.FIVE_SCORE) {
                    breakAll = true;
                    break;
                }
                if (alpha >= beta) break;
            }
            if (breakAll) break;
        }

        // 缓存
        if (cDepth < ONLY_THREE_THRESHOLD || onlyThree || onlyFour) {
            if (!prev || prev.depth < depth - cDepth) {
                _cache.put(hash, {
                    depth: depth - cDepth,
                    value: value,
                    moveX: bestX,
                    moveY: bestY,
                    role: role,
                    onlyThree: onlyThree,
                    onlyFour: onlyFour
                });
            }
        }

        return [value, bestX, bestY];
    }

    // ===== 异步分帧搜索 API =====

    // 开始异步搜索（不阻塞，需要反复调用 step）
    public function searchStart(role:Number, maxDepth:Number, enableVCT:Boolean):Void {
        if (maxDepth === undefined) maxDepth = GobangConfig.searchDepth;
        if (enableVCT === undefined) enableVCT = true;
        _asyncRole = role;
        _asyncMaxDepth = maxDepth;
        // 棋子 < 8 时无算杀可能，跳过 VCT 直接进 MINMAX
        var pieceCount:Number = _eval.history.length;
        var useVCT:Boolean = enableVCT && pieceCount >= 8;
        _asyncEnableVCT = useVCT;
        _asyncPhase = useVCT ? 1 : 2;
        _asyncDone = false;
        _asyncTotalNodes = 0;
        _asyncVCTStartTime = getTimer();
        _asyncBestResult = {x: -1, y: -1, score: 0};
        _asyncVCTResult = null;
        _asyncMMResult = null;
        _asyncCurrentDepth = 2; // 从 depth=2 开始迭代
    }

    // 每帧调用，返回 {done, phase, x, y, score, nodes, phaseLabel, rootIdx, rootTotal}
    public function step(frameBudgetMs:Number):Object {
        if (frameBudgetMs === undefined) frameBudgetMs = 40;
        if (_asyncDone) {
            return {done: true, phase: 4, x: _asyncBestResult.x, y: _asyncBestResult.y,
                    score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: "done",
                    rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
        }

        _budgetMs = frameBudgetMs;
        _startTime = getTimer();
        _nodeCount = 0;
        _timedOut = false;

        if (_asyncPhase === 1) {
            // VCT 搜索（节点上限熔断：累计超 5000 节点无算杀则放弃）
            var vctDepth:Number = _asyncMaxDepth + 4;
            var vr:Array = negamax(_asyncRole, vctDepth, 0, -MAX, MAX, true, false);
            _asyncTotalNodes += _nodeCount;
            if (vr[0] >= GobangShape.FIVE_SCORE) {
                _asyncBestResult = {x: vr[1], y: vr[2], score: vr[0]};
                _asyncDone = true;
                return {done: true, phase: 1, x: vr[1], y: vr[2], score: vr[0],
                        nodes: _asyncTotalNodes, phaseLabel: "vct_win",
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
            }
            // 放弃 VCT 条件：搜索完成 || 累计超 3 秒 || 超 3000 节点
            var vctElapsed:Number = getTimer() - _asyncVCTStartTime;
            if (!_timedOut || vctElapsed > 3000 || _asyncTotalNodes > 3000) {
                _asyncPhase = 2;
                _asyncCurrentDepth = 2;
            }
            return {done: false, phase: 1, x: -1, y: -1, score: 0,
                    nodes: _asyncTotalNodes, phaseLabel: "vct",
                    rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
        }

        if (_asyncPhase === 2) {
            // MINMAX 渐进加深 — 每帧搜索当前 _asyncCurrentDepth
            var curD:Number = _asyncCurrentDepth;
            var mr:Array = negamax(_asyncRole, curD, 0, -MAX, MAX, false, false);
            _asyncTotalNodes += _nodeCount;

            // 更新最优结果
            if (mr[1] >= 0) {
                _asyncBestResult = {x: mr[1], y: mr[2], score: mr[0]};
            }

            if (mr[0] >= GobangShape.FIVE_SCORE) {
                // 找到必胜，不需要更深
                _asyncPhase = _asyncEnableVCT ? 3 : 4;
                if (_asyncPhase === 4) _asyncDone = true;
                return {done: _asyncDone, phase: 2, x: mr[1], y: mr[2], score: mr[0],
                        nodes: _asyncTotalNodes, phaseLabel: "minmax_win",
                        rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
            }

            if (!_timedOut) {
                if (curD >= _asyncMaxDepth) {
                    _asyncPhase = _asyncEnableVCT ? 3 : 4;
                    if (_asyncPhase === 4) _asyncDone = true;
                } else {
                    _asyncCurrentDepth = curD + 2;
                }
            }
            return {done: _asyncDone, phase: 2, x: _asyncBestResult.x, y: _asyncBestResult.y,
                    score: _asyncBestResult.score, nodes: _asyncTotalNodes,
                    phaseLabel: "minmax_d" + curD,
                    rootIdx: _rootMoveIdx, rootTotal: _rootMoveTotal};
        }

        if (_asyncPhase === 3) {
            // AS2 性能约束：跳过反杀检测（reverse + VCT 开销太大）
            // 直接使用 minimax 的结果
            _asyncPhase = 4;
            _asyncDone = true;
            return {done: true, phase: 3, x: _asyncBestResult.x, y: _asyncBestResult.y,
                    score: _asyncBestResult.score, nodes: _asyncTotalNodes, phaseLabel: "counter",
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