import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangMinmax;
import org.flashNight.hana.Gobang.GobangConfig;
import org.flashNight.hana.Gobang.GobangShape;

class org.flashNight.hana.Gobang.GobangAI {
    private var _board:GobangBoard;
    private var _eval:GobangEval;
    private var _minmax:GobangMinmax;
    private var _aiRole:Number;
    private var _difficulty:Number;  // 0-100，100=最强

    // 难度映射表 [difficulty 下限, searchDepth, pointsLimit, 最优走法概率(%), enableVCT]
    // 迭代加深只搜索偶数层，最低 depth 必须 >= 2
    private static var DIFFICULTY_TABLE:Array = [
        [0,   2,  5,  30, false],
        [21,  2,  8,  50, false],
        [41,  2,  12, 70, false],
        [61,  4,  15, 90, true],
        [81,  4,  20, 100, true]
    ];

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
    }

    public function setDifficulty(d:Number):Void {
        _difficulty = d;
    }

    public function getDifficulty():Number {
        return _difficulty;
    }

    // 获取当前难度对应的参数
    private function getDifficultyParams():Object {
        var row:Array = DIFFICULTY_TABLE[0];
        for (var i:Number = DIFFICULTY_TABLE.length - 1; i >= 0; i--) {
            if (_difficulty >= DIFFICULTY_TABLE[i][0]) {
                row = DIFFICULTY_TABLE[i];
                break;
            }
        }
        var depth:Number = row[1];
        var pl:Number = row[2];
        // AS2 性能约束：自适应深度 + 候选数控制
        // AVM1 每节点 ~3-8ms，depth=4 需要候选数足够少才不超时
        var pieces:Number = _board.history.length;
        if (pieces < 6) {
            depth = 2; pl = 8;
        } else if (pieces < 20) {
            // 中局：depth=2 快速响应，VCT 负责看深
            depth = 2; if (pl > 12) pl = 12;
        }
        // depth=4 仅在后期（>=20子）且高难度时启用
        return {
            searchDepth: depth,
            pointsLimit: pl,
            bestProb: row[3],
            enableVCT: row[4]
        };
    }

    public function playerMove(x:Number, y:Number):Boolean {
        var role:Number = _board.role;
        if (role === _aiRole) return false;
        if (!_board.put(x, y, role)) return false;
        _eval.move(x, y, role);
        return true;
    }

    // AI 计算走法并落子（M3: 支持难度调节）
    public function aiMove():Object {
        if (_board.role !== _aiRole) return null;
        if (_board.isGameOver()) return null;

        var params:Object = getDifficultyParams();

        // 临时覆盖全局配置
        var origPL:Number = GobangConfig.pointsLimit;
        GobangConfig.pointsLimit = params.pointsLimit;

        var result:Object = _minmax.search(_aiRole, params.searchDepth, params.enableVCT);

        // 恢复全局配置
        GobangConfig.pointsLimit = origPL;

        if (result.x < 0) return null;

        var finalX:Number = result.x;
        var finalY:Number = result.y;

        // M3: 难度降级 — 以一定概率选择非最优走法
        if (params.bestProb < 100 && result.score < GobangShape.FIVE_SCORE) {
            // 不在必胜局面降级（保证 AI 不会在该赢的时候放水到输）
            var roll:Number = Math.random() * 100;
            if (roll >= params.bestProb) {
                // 选择次优走法：获取走法列表，跳过最优
                var moves:Array = _eval.getMoves(_aiRole, 0, false, false);
                if (moves.length > 1) {
                    // 从第 2-4 名中随机选
                    var pickIdx:Number = 1 + Math.floor(Math.random() * Math.min(3, moves.length - 1));
                    if (pickIdx < moves.length) {
                        finalX = moves[pickIdx][0];
                        finalY = moves[pickIdx][1];
                    }
                }
            }
        }

        _board.put(finalX, finalY, _aiRole);
        _eval.move(finalX, finalY, _aiRole);
        return {x: finalX, y: finalY, score: result.score};
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
    // 棋子 <= 3 时查表，避免开局复杂度爆炸
    // 返回 {x, y} 或 null（无匹配时走搜索）
    private function _lookupOpening():Object {
        var h:Array = _board.history;
        var n:Number = h.length;
        var c:Number = Math.floor(_board.size / 2); // 7

        // AI 先手（0 颗棋子）：下天元
        if (n === 0) return {x: c, y: c};

        // 1 颗棋子：对手已下，我应靠近
        if (n === 1) {
            var ox:Number = h[0].i;
            var oy:Number = h[0].j;
            // 对手下天元 → 斜靠
            if (ox === c && oy === c) return {x: c + 1, y: c + 1};
            // 对手下其他位置 → 天元
            return {x: c, y: c};
        }

        // 2 颗棋子（我下了 1 颗，对手下了 1 颗）
        if (n === 2) {
            var myX:Number, myY:Number, opX:Number, opY:Number;
            if (h[0].role === _aiRole) {
                myX = h[0].i; myY = h[0].j; opX = h[1].i; opY = h[1].j;
            } else {
                opX = h[0].i; opY = h[0].j; myX = h[1].i; myY = h[1].j;
            }
            // 对手紧靠我 → 向另一侧延伸
            var dx:Number = opX - myX;
            var dy:Number = opY - myY;
            var adx:Number = dx; if (adx < 0) adx = -adx;
            var ady:Number = dy; if (ady < 0) ady = -ady;
            if (adx <= 1 && ady <= 1) {
                // 对手贴靠，向反方向走
                var nx:Number = myX - dx;
                var ny:Number = myY - dy;
                if (nx >= 0 && nx < _board.size && ny >= 0 && ny < _board.size && _board.board[nx][ny] === 0) {
                    return {x: nx, y: ny};
                }
            }
            return null; // 走搜索
        }

        // 3 颗棋子
        if (n === 3) {
            // 我有 2 颗 vs 对手 1 颗，或反之 — 搜索空间已经小了，走正常搜索
            return null;
        }

        return null;
    }

    // ===== 异步 AI 接口 =====

    // 开局标记：null = 需要搜索，非 null = 开局走法
    private var _openingMove:Object;

    public function aiMoveStart():Boolean {
        if (_board.role !== _aiRole) return false;
        if (_board.isGameOver()) return false;

        // 先查开局库
        _openingMove = _lookupOpening();
        if (_openingMove !== null) return true;

        // 需要搜索
        var params:Object = getDifficultyParams();
        GobangConfig.pointsLimit = params.pointsLimit;
        _minmax.searchStart(_aiRole, params.searchDepth, params.enableVCT);
        return true;
    }

    public function aiMoveStep(frameBudgetMs:Number):Object {
        if (frameBudgetMs === undefined) frameBudgetMs = 16;

        // 开局库命中：立即落子
        if (_openingMove !== null) {
            var ox:Number = _openingMove.x;
            var oy:Number = _openingMove.y;
            _openingMove = null;
            _board.put(ox, oy, _aiRole);
            _eval.move(ox, oy, _aiRole);
            return {done: true, x: ox, y: oy, score: 0, phaseLabel: "opening",
                    nodes: 0, rootIdx: 0, rootTotal: 0};
        }

        var stepResult:Object = _minmax.step(frameBudgetMs);
        if (!stepResult.done) {
            return stepResult;
        }
        // 搜索完成 — 应用难度降级并落子
        var params:Object = getDifficultyParams();
        var finalX:Number = stepResult.x;
        var finalY:Number = stepResult.y;
        if (finalX < 0) {
            return {done: true, x: -1, y: -1, score: 0, phaseLabel: "no_move",
                    nodes: stepResult.nodes, rootIdx: 0, rootTotal: 0};
        }
        // 难度降级
        if (params.bestProb < 100 && stepResult.score < GobangShape.FIVE_SCORE) {
            var roll:Number = Math.random() * 100;
            if (roll >= params.bestProb) {
                var moves:Array = _eval.getMoves(_aiRole, 0, false, false);
                if (moves.length > 1) {
                    var pickIdx:Number = 1 + Math.floor(Math.random() * Math.min(3, moves.length - 1));
                    if (pickIdx < moves.length) {
                        finalX = moves[pickIdx][0];
                        finalY = moves[pickIdx][1];
                    }
                }
            }
        }
        _board.put(finalX, finalY, _aiRole);
        _eval.move(finalX, finalY, _aiRole);
        return {done: true, x: finalX, y: finalY, score: stepResult.score,
                phaseLabel: stepResult.phaseLabel, nodes: stepResult.nodes,
                rootIdx: stepResult.rootIdx, rootTotal: stepResult.rootTotal};
    }
}