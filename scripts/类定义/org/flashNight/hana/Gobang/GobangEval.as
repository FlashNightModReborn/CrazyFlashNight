import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangEval {
    public var size:Number;
    public var board:Array;        // padded (size+2)x(size+2), border=2
    public var blackScores:Array;  // [size][size]
    public var whiteScores:Array;  // [size][size]
    private var _totalBlack:Number; // 增量总分
    private var _totalWhite:Number;
    public var shapeCache:Array;   // [2][4][size][size] — roleIdx, direction, x, y
    public var history:Array;      // [[position, role], ...]

    // 方向表
    private static var allDirs:Array = [[0, 1], [1, 0], [1, 1], [1, -1]];
    private static var dirtyMap:Array = null;
    private static var dirtyMapSize:Number = 0;

    public function GobangEval(size:Number) {
        if (size === undefined) size = 15;
        this.size = size;
        history = [];
        _totalBlack = 0;
        _totalWhite = 0;
        initDirtyMap(size);

        // 初始化 padded board
        board = [];
        for (var i:Number = 0; i < size + 2; i++) {
            board[i] = [];
            for (var j:Number = 0; j < size + 2; j++) {
                board[i][j] = (i === 0 || j === 0 || i === size + 1 || j === size + 1) ? 2 : 0;
            }
        }

        // 初始化分数数组
        blackScores = [];
        whiteScores = [];
        for (var si:Number = 0; si < size; si++) {
            blackScores[si] = [];
            whiteScores[si] = [];
            for (var sj:Number = 0; sj < size; sj++) {
                blackScores[si][sj] = 0;
                whiteScores[si][sj] = 0;
            }
        }

        // 初始化 shapeCache: [roleIdx][direction][x][y]
        shapeCache = [];
        for (var ri:Number = 0; ri < 2; ri++) {
            shapeCache[ri] = [];
            for (var d:Number = 0; d < 4; d++) {
                shapeCache[ri][d] = [];
                for (var ci:Number = 0; ci < size; ci++) {
                    shapeCache[ri][d][ci] = [];
                    for (var cj:Number = 0; cj < size; cj++) {
                        shapeCache[ri][d][ci][cj] = GobangShape.NONE;
                    }
                }
            }
        }
    }

    public function move(x:Number, y:Number, role:Number):Void {
        var ri:Number = GobangConfig.roleIndex(role);
        var ori:Number = GobangConfig.roleIndex(-role);
        // 清除该位置的缓存
        for (var d:Number = 0; d < 4; d++) {
            shapeCache[ri][d][x][y] = 0;
            shapeCache[ori][d][x][y] = 0;
        }
        _totalBlack -= blackScores[x][y];
        _totalWhite -= whiteScores[x][y];
        blackScores[x][y] = 0;
        whiteScores[x][y] = 0;

        // 更新 padded board
        board[x + 1][y + 1] = role;
        updatePointMove(x, y);
        history.push([x * size + y, role]);
    }

    public function undo(x:Number, y:Number):Void {
        board[x + 1][y + 1] = 0;
        updatePointUndo(x, y);
        history.pop();
    }

    private static function initDirtyMap(size:Number):Void {
        if (dirtyMap !== null && dirtyMapSize === size) return;
        dirtyMapSize = size;
        dirtyMap = [];
        for (var x:Number = 0; x < size; x++) {
            dirtyMap[x] = [];
            for (var y:Number = 0; y < size; y++) {
                var flat:Array = [];
                for (var di:Number = 0; di < 4; di++) {
                    var dv:Array = allDirs[di];
                    var ox:Number = dv[0];
                    var oy:Number = dv[1];
                    for (var step:Number = 1; step < 5; step++) {
                        var nx:Number = x + step * ox;
                        var ny:Number = y + step * oy;
                        if (nx >= 0 && nx < size && ny >= 0 && ny < size) {
                            flat.push(nx, ny, ox, oy);
                        }
                        nx = x - step * ox;
                        ny = y - step * oy;
                        if (nx >= 0 && nx < size && ny >= 0 && ny < size) {
                            flat.push(nx, ny, -ox, -oy);
                        }
                    }
                }
                dirtyMap[x][y] = flat;
            }
        }
    }

    private function updatePointMove(x:Number, y:Number):Void {
        updateDirtyNeighbors(x, y);
    }

    private function updatePointUndo(x:Number, y:Number):Void {
        updateSinglePoint(x, y, 1, -1, -1);
        updateSinglePoint(x, y, -1, -1, -1);
        updateDirtyNeighbors(x, y);
    }

    private function updateDirtyNeighbors(x:Number, y:Number):Void {
        var brd:Array = board;
        var flat:Array = dirtyMap[x][y];
        for (var i:Number = 0; i < flat.length; i += 4) {
            var nx:Number = flat[i];
            var ny:Number = flat[i + 1];
            if (brd[nx + 1][ny + 1] !== 0) continue;
            var ox:Number = flat[i + 2];
            var oy:Number = flat[i + 3];
            updateSinglePoint(nx, ny, 1, ox, oy);
            updateSinglePoint(nx, ny, -1, ox, oy);
        }
    }

    // dirOx/dirOy: 指定只更新一个方向 (-1,-1 = 全部4方向)
    // 内联 getRealShapeScore — 消除函数调用开销(485ns→0)
    private static function _shapeScore(s:Number):Number {
        // 按频率排序：TWO 最多，BLOCK_THREE 次之...
        if (s === 2) return 10;       // TWO → ONE_SCORE
        if (s === 30) return 15;      // BLOCK_THREE → BLOCK_TWO_SCORE
        if (s === 3) return 100;      // THREE → TWO_SCORE
        if (s === 40) return 150;     // BLOCK_FOUR → BLOCK_THREE_SCORE
        if (s === 5) return 100000;   // FIVE → FOUR_SCORE
        if (s === 50) return 1500;    // BLOCK_FIVE → BLOCK_FOUR_SCORE
        if (s === 4) return 1000;     // FOUR → THREE_SCORE
        if (s === 44) return 1000;    // FOUR_FOUR → THREE_SCORE
        if (s === 43) return 1000;    // FOUR_THREE → THREE_SCORE
        if (s === 33) return 5000;    // THREE_THREE → THREE_THREE_SCORE/10
        if (s === 22) return 20;      // TWO_TWO → TWO_TWO_SCORE/10
        return 0;
    }

    private function updateSinglePoint(x:Number, y:Number, role:Number, dirOx:Number, dirOy:Number):Void {
        // 局部变量缓存（AVM1: 局部=0ns vs 成员=144ns）
        var brd:Array = board;
        var bx:Number = x + 1;
        var by:Number = y + 1;
        if (brd[bx][by] !== 0) return;

        // 内联 roleIndex: role===1 ? 0 : 1
        var ri:Number = role === 1 ? 0 : 1;
        var sc:Array = shapeCache[ri];
        var hasSingleDir:Boolean = (dirOx !== -1);
        var scx0:Array = sc[0][x];
        var scx1:Array = sc[1][x];
        var scx2:Array = sc[2][x];
        var scx3:Array = sc[3][x];

        // 内联 direction2index 清除缓存
        if (hasSingleDir) {
            var dirIdx:Number;
            if (dirOx === 0) dirIdx = 0;
            else if (dirOy === 0) dirIdx = 1;
            else if (dirOx === dirOy) dirIdx = 2;
            else dirIdx = 3;
            sc[dirIdx][x][y] = 0;
        } else {
            scx0[y] = 0; scx1[y] = 0; scx2[y] = 0; scx3[y] = 0;
        }

        var score:Number = 0;
        var bfc:Number = 0;
        var thc:Number = 0;
        var twc:Number = 0;
        var es:Number;

        // 累加已有方向分值（内联 _shapeScore）
        es = scx0[y]; if (es) { score += _shapeScore(es); if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = scx1[y]; if (es) { score += _shapeScore(es); if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = scx2[y]; if (es) { score += _shapeScore(es); if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = scx3[y]; if (es) { score += _shapeScore(es); if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }

        // 计算新方向棋型
        var gsf:Function = GobangShape.getShapeFast;
        if (hasSingleDir) {
            var sh:Number = gsf(brd, x, y, dirOx, dirOy, role);
            if (sh) {
                sc[dirIdx][x][y] = sh;
                if (sh === 40) bfc++; if (sh === 3) thc++; if (sh === 2) twc++;
                if (bfc >= 2) sh = 44;
                else if (bfc && thc) sh = 43;
                else if (thc >= 2) sh = 33;
                else if (twc >= 2) sh = 22;
                score += _shapeScore(sh);
            }
        } else {
            var ad:Array = allDirs;
            for (var ni:Number = 0; ni < 4; ni++) {
                var dv:Array = ad[ni];
                var sh2:Number = gsf(brd, x, y, dv[0], dv[1], role);
                if (!sh2) continue;
                sc[ni][x][y] = sh2;
                if (sh2 === 40) bfc++; if (sh2 === 3) thc++; if (sh2 === 2) twc++;
                if (bfc >= 2) sh2 = 44;
                else if (bfc && thc) sh2 = 43;
                else if (thc >= 2) sh2 = 33;
                else if (twc >= 2) sh2 = 22;
                score += _shapeScore(sh2);
            }
        }

        if (role === 1) {
            _totalBlack += score - blackScores[x][y];
            blackScores[x][y] = score;
        } else {
            _totalWhite += score - whiteScores[x][y];
            whiteScores[x][y] = score;
        }
    }

    public function evaluate(role:Number):Number {
        return role === 1 ? _totalBlack - _totalWhite : _totalWhite - _totalBlack;
    }

    // 轻量 getMoves — 单次遍历，单数组收集，按分数排序截断
    public function getMoves(role:Number, depth:Number, onlyThree:Boolean, onlyFour:Boolean):Array {
        var brd:Array = board;
        var sz:Number = size;
        var sc:Array = shapeCache;
        var result:Array = [];
        var limit:Number = GobangConfig.pointsLimit;
        if (limit < 1) limit = 1;
        var bs:Array = blackScores;
        var ws:Array = whiteScores;
        var atk:Array = role === 1 ? bs : ws;
        var def:Array = role === 1 ? ws : bs;
        var hasFive:Boolean = false;
        var sc0:Array = sc[0];
        var sc1:Array = sc[1];

        for (var i:Number = 0; i < sz; i++) {
            if (brd[i + 1] === undefined) continue;
            for (var j:Number = 0; j < sz; j++) {
                if (brd[i + 1][j + 1] !== 0) continue;
                var attackScore:Number = atk[i][j];
                var defendScore:Number = def[i][j];
                if (attackScore === 0 && defendScore === 0) continue;

                // 快速检查：该位置有没有任何棋型
                var maxS:Number = 0;
                var s0:Number = sc0[0][i][j];
                var s1:Number = sc0[1][i][j];
                var s2:Number = sc0[2][i][j];
                var s3:Number = sc0[3][i][j];
                var s4:Number = sc1[0][i][j];
                var s5:Number = sc1[1][i][j];
                var s6:Number = sc1[2][i][j];
                var s7:Number = sc1[3][i][j];
                if (s0 > maxS) maxS = s0;
                if (s1 > maxS) maxS = s1;
                if (s2 > maxS) maxS = s2;
                if (s3 > maxS) maxS = s3;
                if (s4 > maxS) maxS = s4;
                if (s5 > maxS) maxS = s5;
                if (s6 > maxS) maxS = s6;
                if (s7 > maxS) maxS = s7;
                if (!maxS) continue;

                // FIVE/BLOCK_FIVE（值 5 或 50）最高优先
                if (maxS === 5 || maxS === 50) {
                    if (!hasFive) { result.length = 0; hasFive = true; }
                    result.push([i, j]);
                    continue;
                }
                if (hasFive) continue; // 已有五连，跳过非五连

                if (onlyFour && maxS < 4) continue;
                if (onlyThree && maxS < 3) continue;

                // 评分：优先兼顾本方进攻和对方威胁，避免排序回调开销
                var major:Number = attackScore > defendScore ? attackScore : defendScore;
                var sortKey:Number = attackScore + defendScore + major;
                var resultLen:Number = result.length;
                if (resultLen < limit || sortKey > result[resultLen - 1][2]) {
                    var insertAt:Number = resultLen;
                    if (insertAt >= limit) insertAt = limit - 1;
                    while (insertAt > 0 && sortKey > result[insertAt - 1][2]) {
                        if (insertAt < limit) {
                            result[insertAt] = result[insertAt - 1];
                        }
                        insertAt--;
                    }
                    result[insertAt] = [i, j, sortKey];
                    if (resultLen < limit) {
                        result.length = resultLen + 1;
                    }
                }
            }
        }

        if (hasFive) return result;

        // 清除排序键
        for (var ci:Number = 0; ci < result.length; ci++) {
            result[ci].length = 2;
        }
        return result;
    }
}
