import org.flashNight.hana.Gobang.GobangZobrist;

class org.flashNight.hana.Gobang.GobangBoard {
    public var size:Number;
    public var board:Array;       // [size][size], 0=empty, 1=black, -1=white
    public var firstRole:Number;
    public var role:Number;       // current role to play
    public var history:Array;     // [{i, j, role}, ...]
    public var zobrist:GobangZobrist;

    // 上游 board.js 在内部包含 padding（+2 边界），但 getShapeFast 需要
    // 我们的 board 维持纯净 15x15，padding 在 Shape/Eval 中处理

    public function GobangBoard(size:Number, firstRole:Number) {
        if (size === undefined) size = 15;
        if (firstRole === undefined) firstRole = 1;
        this.size = size;
        this.firstRole = firstRole;
        this.role = firstRole;
        this.history = [];
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
        history.push({i: i, j: j, role: r});
        zobrist.togglePiece(i, j, r);
        role *= -1;
        return true;
    }

    public function undo():Boolean {
        if (history.length === 0) return false;
        var last:Object = history.pop();
        board[last.i][last.j] = 0;
        role = last.role;
        zobrist.togglePiece(last.i, last.j, last.role);
        return true;
    }

    public function isWin(x:Number, y:Number, r:Number):Boolean {
        // Check 4 directions: horizontal, vertical, diagonal, anti-diagonal
        var dirs:Array = [[1, 0], [0, 1], [1, 1], [1, -1]];
        for (var d:Number = 0; d < 4; d++) {
            var dx:Number = dirs[d][0];
            var dy:Number = dirs[d][1];
            var count:Number = 1;
            // Forward
            for (var k:Number = 1; k < 5; k++) {
                var nx:Number = x + dx * k;
                var ny:Number = y + dy * k;
                if (nx < 0 || nx >= size || ny < 0 || ny >= size) break;
                if (board[nx][ny] !== r) break;
                count++;
            }
            // Backward
            for (var k2:Number = 1; k2 < 5; k2++) {
                var nx2:Number = x - dx * k2;
                var ny2:Number = y - dy * k2;
                if (nx2 < 0 || nx2 >= size || ny2 < 0 || ny2 >= size) break;
                if (board[nx2][ny2] !== r) break;
                count++;
            }
            if (count >= 5) return true;
        }
        return false;
    }

    public function getWinner():Number {
        for (var i:Number = 0; i < size; i++) {
            for (var j:Number = 0; j < size; j++) {
                if (board[i][j] !== 0) {
                    if (isWin(i, j, board[i][j])) return board[i][j];
                }
            }
        }
        return 0;
    }

    public function isGameOver():Boolean {
        if (getWinner() !== 0) return true;
        for (var i:Number = 0; i < size; i++) {
            for (var j:Number = 0; j < size; j++) {
                if (board[i][j] === 0) return false;
            }
        }
        return true;
    }

    public function hash():String {
        return zobrist.toKey();
    }
}