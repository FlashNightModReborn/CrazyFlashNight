import org.flashNight.hana.Gobang.GobangZobrist;
import org.flashNight.hana.Gobang.GobangEval;

class org.flashNight.hana.Gobang.GobangBoard {
    public var size:Number;
    public var board:Array;       // [size][size], 0=empty, 1=black, -1=white
    public var firstRole:Number;
    public var role:Number;       // current role to play
    public var history:Array;     // [{i, j, role}, ...]
    public var zobrist:GobangZobrist;
    private var _historyTop:Number;
    private var _winner:Number;
    private var _winnerStack:Array;

    // 上游 board.js 在内部包含 padding（+2 边界），但 getShapeFast 需要
    // 我们的 board 维持纯净 15x15，padding 在 Shape/Eval 中处理

    public function GobangBoard(size:Number, firstRole:Number) {
        if (size === undefined) size = 15;
        if (firstRole === undefined) firstRole = 1;
        this.size = size;
        this.firstRole = firstRole;
        this.role = firstRole;
        this.history = [];
        this._historyTop = 0;
        this._winner = 0;
        this._winnerStack = [];
        this.zobrist = new GobangZobrist(size);

        // Initialize board
        board = [];
        for (var i:Number = 0; i < size; i++) {
            board[i] = [];
            for (var j:Number = 0; j < size; j++) {
                board[i][j] = 0;
            }
        }
    }

    public function put(i:Number, j:Number, r:Number):Boolean {
        if (r === undefined) r = role;
        if (board[i][j] !== 0) return false;
        board[i][j] = r;
        _winnerStack[_historyTop] = _winner;
        var entry:Object = history[_historyTop];
        if (entry === undefined) {
            history[_historyTop] = {i: i, j: j, role: r};
        } else {
            entry.i = i;
            entry.j = j;
            entry.role = r;
        }
        _historyTop++;
        history.length = _historyTop;
        if (_winner === 0 && isWin(i, j, r)) {
            _winner = r;
        }
        zobrist.togglePiece(i, j, r);
        role *= -1;
        return true;
    }

    public function undo():Boolean {
        if (_historyTop === 0) return false;
        _historyTop--;
        var last:Object = history[_historyTop];
        history.length = _historyTop;
        board[last.i][last.j] = 0;
        role = last.role;
        _winner = _winnerStack[_historyTop];
        zobrist.togglePiece(last.i, last.j, last.role);
        return true;
    }

    // 预分配方向数组（避免每次 isWin 创建）
    private static var WIN_DX:Array = [1, 0, 1, 1];
    private static var WIN_DY:Array = [0, 1, 1, -1];

    public function isWin(x:Number, y:Number, r:Number):Boolean {
        var brd:Array = board;
        var sz:Number = size;
        for (var d:Number = 0; d < 4; d++) {
            var dx:Number = WIN_DX[d];
            var dy:Number = WIN_DY[d];
            var count:Number = 1;
            var nx:Number; var ny:Number;
            nx = x + dx; ny = y + dy;
            while (nx >= 0 && nx < sz && ny >= 0 && ny < sz && brd[nx][ny] === r) { count++; nx += dx; ny += dy; }
            nx = x - dx; ny = y - dy;
            while (nx >= 0 && nx < sz && ny >= 0 && ny < sz && brd[nx][ny] === r) { count++; nx -= dx; ny -= dy; }
            if (count >= 5) return true;
        }
        return false;
    }

    // O(1) — 只检查最后一手
    public function getWinner():Number {
        return _winner;
    }

    public function isGameOver():Boolean {
        if (_historyTop === 0) return false;
        if (_winner !== 0) return true;
        // 棋盘满了才是平局（225 步）
        return _historyTop >= size * size;
    }

    public function hash():String {
        return zobrist.toKey();
    }

    // 创建反转棋盘：黑白互换，用于检测对手是否有算杀
    public function reverse():Object {
        var newBoard:GobangBoard = new GobangBoard(size, -firstRole);
        var newEval:GobangEval = new GobangEval(size);
        for (var i:Number = 0; i < _historyTop; i++) {
            var h:Object = history[i];
            var swappedRole:Number = -h.role;
            newBoard.put(h.i, h.j, swappedRole);
            newEval.move(h.i, h.j, swappedRole);
        }
        return {board: newBoard, eval: newEval};
    }
}
