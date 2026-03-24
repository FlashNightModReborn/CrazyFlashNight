import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangMinmax;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangAI {
    private var _board:GobangBoard;
    private var _eval:GobangEval;
    private var _minmax:GobangMinmax;
    private var _aiRole:Number;    // AI 执黑 (1) 或执白 (-1)

    public function GobangAI(aiRole:Number) {
        if (aiRole === undefined) aiRole = -1; // 默认 AI 执白
        _aiRole = aiRole;
        reset();
    }

    public function reset():Void {
        _board = new GobangBoard(15, 1);
        _eval = new GobangEval(15);
        _minmax = new GobangMinmax(_board, _eval);
    }

    // 玩家落子
    public function playerMove(x:Number, y:Number):Boolean {
        var role:Number = _board.role;
        if (role === _aiRole) return false; // 不是玩家的回合
        if (!_board.put(x, y, role)) return false;
        _eval.move(x, y, role);
        return true;
    }

    // AI 计算走法并落子
    public function aiMove():Object {
        if (_board.role !== _aiRole) return null;
        if (_board.isGameOver()) return null;

        var result:Object = _minmax.search(_aiRole, GobangConfig.searchDepth);
        if (result.x < 0) return null;

        _board.put(result.x, result.y, _aiRole);
        _eval.move(result.x, result.y, _aiRole);
        return {x: result.x, y: result.y, score: result.score};
    }

    // 悔棋（撤销最后一步）
    public function undo():Boolean {
        if (_board.history.length === 0) return false;
        var last:Object = _board.history[_board.history.length - 1];
        _eval.undo(last.i, last.j);
        _board.undo();
        return true;
    }

    // 获取棋盘状态 (15x15 数组, 0=空, 1=黑, -1=白)
    public function getBoard():Array {
        return _board.board;
    }

    // 获取当前角色
    public function getCurrentRole():Number {
        return _board.role;
    }

    // 是否游戏结束
    public function isGameOver():Boolean {
        return _board.isGameOver();
    }

    // 获胜方 (0=无, 1=黑, -1=白)
    public function getWinner():Number {
        return _board.getWinner();
    }
}