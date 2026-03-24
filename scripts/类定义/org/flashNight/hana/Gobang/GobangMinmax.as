import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangCache;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangMinmax {
    private static var MAX:Number = 1000000000;
    private static var TIMEOUT_MS:Number = 3000;
    private static var NODE_CHECK_INTERVAL:Number = 1000;

    private var _board:GobangBoard;
    private var _eval:GobangEval;
    private var _cache:GobangCache;
    private var _nodeCount:Number;
    private var _startTime:Number;
    private var _timedOut:Boolean;

    public function GobangMinmax(board:GobangBoard, eval:GobangEval) {
        _board = board;
        _eval = eval;
        _cache = new GobangCache(100000);
        _nodeCount = 0;
        _timedOut = false;
    }

    // M1: 纯 minimax，无 VCT/VCF
    public function search(role:Number, maxDepth:Number):Object {
        if (maxDepth === undefined) maxDepth = GobangConfig.searchDepth;
        _nodeCount = 0;
        _timedOut = false;
        _startTime = getTimer();

        var result:Array = negamax(role, maxDepth, 0, -MAX, MAX);
        return {x: result[1], y: result[2], score: result[0], nodes: _nodeCount, timedOut: _timedOut};
    }

    // result: [value, moveX, moveY]
    private function negamax(role:Number, depth:Number, cDepth:Number,
            alpha:Number, beta:Number):Array {
        _nodeCount++;
        // 超时检查
        if (_nodeCount % NODE_CHECK_INTERVAL === 0) {
            if (getTimer() - _startTime > TIMEOUT_MS) {
                _timedOut = true;
            }
        }

        if (cDepth >= depth || _board.isGameOver() || _timedOut) {
            // 先检查是否有赢家
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
                return [prev.value, prev.moveX, prev.moveY];
            }
        }

        var value:Number = -MAX;
        var bestX:Number = -1;
        var bestY:Number = -1;

        // 获取走法
        var moves:Array = getMovesForSearch(role, cDepth);

        // 添加中心点
        if (cDepth === 0) {
            var center:Number = Math.floor(_board.size / 2);
            if (_board.board[center][center] === 0) {
                moves.push([center, center]);
            }
        }

        if (!moves.length) {
            return [_eval.evaluate(role), -1, -1];
        }

        // 迭代加深
        for (var d:Number = cDepth + 1; d <= depth; d++) {
            if (d % 2 !== 0) continue;  // 只搜索偶数层
            var breakAll:Boolean = false;
            for (var i:Number = 0; i < moves.length; i++) {
                var mx:Number = moves[i][0];
                var my:Number = moves[i][1];
                _board.put(mx, my, role);
                _eval.move(mx, my, role);
                var child:Array = negamax(-role, d, cDepth + 1, -beta, -alpha);
                var currentValue:Number = -child[0];
                _eval.undo(mx, my);
                _board.undo();

                if (_timedOut) {
                    if (bestX === -1) { bestX = mx; bestY = my; value = currentValue; }
                    return [value, bestX, bestY];
                }

                // 迭代加深中，只在最终深度或找到必胜时更新
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

        // 缓存存储
        if (cDepth < 6) {
            _cache.put(hash, {
                depth: depth - cDepth,
                value: value,
                moveX: bestX,
                moveY: bestY,
                role: role
            });
        }

        return [value, bestX, bestY];
    }

    private function getMovesForSearch(role:Number, cDepth:Number):Array {
        return _eval.getMoves(role, cDepth);
    }
}