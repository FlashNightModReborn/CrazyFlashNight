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

    public function GobangEval(size:Number) {
        if (size === undefined) size = 15;
        this.size = size;
        history = [];
        _totalBlack = 0;
        _totalWhite = 0;

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
        updatePoint(x, y);
        history.push([x * size + y, role]);
    }

    public function undo(x:Number, y:Number):Void {
        board[x + 1][y + 1] = 0;
        updatePoint(x, y);
        history.pop();
    }

    private function updatePoint(x:Number, y:Number):Void {
        var brd:Array = board;
        updateSinglePoint(x, y, 1, -1, -1);
        updateSinglePoint(x, y, -1, -1, -1);

        var ad:Array = allDirs;
        for (var di:Number = 0; di < 4; di++) {
            var dv:Array = ad[di];
            var ox:Number = dv[0];
            var oy:Number = dv[1];
            // 正方向
            var nx:Number = x + 1 + ox;
            var ny:Number = y + 1 + oy;
            for (var step:Number = 1; step < 5; step++) {
                var cv:Number = brd[nx][ny];
                if (cv === 2) break;       // 边界
                if (cv === 0) {
                    updateSinglePoint(nx - 1, ny - 1, 1, ox, oy);
                    updateSinglePoint(nx - 1, ny - 1, -1, ox, oy);
                }
                nx += ox; ny += oy;
            }
            // 反方向
            nx = x + 1 - ox;
            ny = y + 1 - oy;
            for (var step2:Number = 1; step2 < 5; step2++) {
                var cv2:Number = brd[nx][ny];
                if (cv2 === 2) break;
                if (cv2 === 0) {
                    updateSinglePoint(nx - 1, ny - 1, 1, -ox, -oy);
                    updateSinglePoint(nx - 1, ny - 1, -1, -ox, -oy);
                }
                nx -= ox; ny -= oy;
            }
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

        brd[bx][by] = role;

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

        brd[bx][by] = 0;

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
        var hLen:Number = history.length;
        var result:Array = [];
        // 阈值：onlyFour 只要 4+5 级，onlyThree 要 3+4+5 级
        var minShape:Number = onlyFour ? 4 : (onlyThree ? 3 : 0);

        var rIdx0:Number = role === 1 ? 0 : 1;
        var rIdx1:Number = 1 - rIdx0;
        // 使用 blackScores+whiteScores 做排序键（已有增量计算）
        var bs:Array = blackScores;
        var ws:Array = whiteScores;
        var hasFive:Boolean = false;

        for (var i:Number = 0; i < sz; i++) {
            if (brd[i + 1] === undefined) continue;
            for (var j:Number = 0; j < sz; j++) {
                if (brd[i + 1][j + 1] !== 0) continue;

                // 快速检查：该位置有没有任何棋型
                var maxS:Number = 0;
                for (var ri2:Number = 0; ri2 < 2; ri2++) {
                    var s0:Number = sc[ri2][0][i][j];
                    var s1:Number = sc[ri2][1][i][j];
                    var s2:Number = sc[ri2][2][i][j];
                    var s3:Number = sc[ri2][3][i][j];
                    if (s0 > maxS) maxS = s0;
                    if (s1 > maxS) maxS = s1;
                    if (s2 > maxS) maxS = s2;
                    if (s3 > maxS) maxS = s3;
                }
                if (!maxS) continue;
                // FIVE/BLOCK_FIVE（值 5 或 50）最高优先
                if (maxS === 5 || maxS === 50) {
                    if (!hasFive) { result.length = 0; hasFive = true; }
                    result.push([i, j]);
                    continue;
                }
                if (hasFive) continue; // 已有五连，跳过非五连

                // 过滤：onlyFour 只要 FOUR(4)/BLOCK_FOUR(40)+
                if (onlyFour && maxS < 4) continue;
                // onlyThree 只要 THREE(3)/BLOCK_FOUR(40)/FOUR(4)+
                if (onlyThree && maxS < 3) continue;

                // 分数排序键：两方分数之和
                var sortKey:Number = bs[i][j] + ws[i][j];
                result.push([i, j, sortKey]);
            }
        }

        if (hasFive) return result;

        // 按分数降序排序
        result.sort(function(a, b) { return b[2] - a[2]; });

        // 截断到 pointsLimit
        var limit:Number = GobangConfig.pointsLimit;
        if (result.length > limit) result.length = limit;

        // 清除排序键
        for (var ci:Number = 0; ci < result.length; ci++) {
            result[ci].length = 2;
        }
        return result;
    }
}