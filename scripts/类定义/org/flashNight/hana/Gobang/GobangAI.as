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

        // 早期缩小候选数（棋子少时信息不足）但不压深度
        if (pieces < 4) {
            if (pl > 8) pl = 8;
        } else if (pieces < 10) {
            if (pl > 10) pl = 10;
        } else if (pieces < 18 && pl > 12) {
            pl = 12;
        }

        // 根短名单(4)+LMR+NullMove 控制树规模；VCT 提供战术必杀
        if (frameBudgetMs <= 8) {
            if (depth > 8) depth = 8;
            if (pl > 8) pl = 8;
        } else if (frameBudgetMs <= 16) {
            if (depth > 8) depth = 8;
            if (pl > 10) pl = 10;
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
