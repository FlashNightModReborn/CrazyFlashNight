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
    public var history:Array;      // 仅用于记录手数（供搜索阶段判断）

    // Save/Restore undo 栈 — 消除 undo 重计算开销
    private var _undoStack:Array;
    private var _undoTop:Number;
    private var _undoMarks:Array;
    private var _undoMarkTop:Number;

    // 候选前沿：只遍历当前活跃空位，避免 getMoves 全盘扫描
    private var _frontierCount:Array; // [flat] 邻近棋子数
    private var _frontierIndex:Array; // [flat] 在 _frontierList 中的位置，-1=不活跃
    private var _frontierList:Array;  // [flat, ...]
    private var _frontierTop:Number;

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
        _initScoreLUT();

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

        // 初始化 undo 栈（最大深度 20 × 每层 ~240 值 = 4800）
        _undoStack = new Array(5000);
        _undoTop = 0;
        _undoMarks = new Array(24);
        _undoMarkTop = 0;

        // 初始化候选前沿
        var cellCount:Number = size * size;
        _frontierCount = new Array(cellCount);
        _frontierIndex = new Array(cellCount);
        _frontierList = new Array(cellCount);
        _frontierTop = 0;
        for (var fi:Number = 0; fi < cellCount; fi++) {
            _frontierCount[fi] = 0;
            _frontierIndex[fi] = -1;
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
        var ri:Number = role === 1 ? 0 : 1;
        var ori:Number = 1 - ri;
        var sc:Array = shapeCache;
        var st:Array = _undoStack;
        var top:Number = _undoTop;
        var bs:Array = blackScores;
        var ws:Array = whiteScores;

        // 压入标记
        _undoMarks[_undoMarkTop++] = top;

        // 保存总分（2 值）
        st[top] = _totalBlack; st[top + 1] = _totalWhite; top += 2;

        // 保存 (x,y) 棋型缓存（8 值）+ 分数（2 值）
        st[top] = sc[0][0][x][y]; st[top + 1] = sc[0][1][x][y];
        st[top + 2] = sc[0][2][x][y]; st[top + 3] = sc[0][3][x][y];
        st[top + 4] = sc[1][0][x][y]; st[top + 5] = sc[1][1][x][y];
        st[top + 6] = sc[1][2][x][y]; st[top + 7] = sc[1][3][x][y];
        st[top + 8] = bs[x][y]; st[top + 9] = ws[x][y];
        top += 10;

        // 清除 (x,y) 棋型和分数
        sc[ri][0][x][y] = 0; sc[ri][1][x][y] = 0;
        sc[ri][2][x][y] = 0; sc[ri][3][x][y] = 0;
        sc[ori][0][x][y] = 0; sc[ori][1][x][y] = 0;
        sc[ori][2][x][y] = 0; sc[ori][3][x][y] = 0;
        _totalBlack -= bs[x][y];
        _totalWhite -= ws[x][y];
        bs[x][y] = 0;
        ws[x][y] = 0;

        // 更新 padded board
        board[x + 1][y + 1] = role;
        updateFrontierMove(x, y);

        // 保存 + 更新 dirty neighbors
        var brd:Array = board;
        var flat:Array = dirtyMap[x][y];
        var flen:Number = flat.length;
        for (var i:Number = 0; i < flen; i += 4) {
            var nx:Number = flat[i];
            var ny:Number = flat[i + 1];
            if (brd[nx + 1][ny + 1] !== 0) continue;
            var ox:Number = flat[i + 2];
            var oy:Number = flat[i + 3];
            // 内联 direction2index
            var dirIdx:Number;
            if (ox === 0) dirIdx = 0;
            else if (oy === 0) dirIdx = 1;
            else if (ox === oy) dirIdx = 2;
            else dirIdx = 3;
            // 快速跳过：新旧棋型均为 NONE → 无需更新
            var px:Number = nx + 1;
            var py:Number = ny + 1;
            if (brd[px + ox][py + oy] === 0
                && brd[px - ox][py - oy] === 0
                && brd[px + ox + ox][py + oy + oy] === 0
                && brd[px - ox - ox][py - oy - oy] === 0
                && sc[0][dirIdx][nx][ny] === 0
                && sc[1][dirIdx][nx][ny] === 0) {
                continue;
            }
            // 保存: nx, ny, dirIdx, 两角色棋型, 两角色分数
            st[top] = nx; st[top + 1] = ny; st[top + 2] = dirIdx;
            st[top + 3] = sc[0][dirIdx][nx][ny];
            st[top + 4] = sc[1][dirIdx][nx][ny];
            st[top + 5] = bs[nx][ny];
            st[top + 6] = ws[nx][ny];
            top += 7;
            // 执行更新
            updateSinglePoint(nx, ny, 1, ox, oy);
            updateSinglePoint(nx, ny, -1, ox, oy);
        }

        _undoTop = top;
        history[history.length] = 1;
    }

    // 快速 undo — 从保存栈恢复，零 getShapeFast 调用
    public function undo(x:Number, y:Number):Void {
        board[x + 1][y + 1] = 0;
        updateFrontierUndo(x, y);

        var st:Array = _undoStack;
        var top:Number = _undoTop;
        var mark:Number = _undoMarks[--_undoMarkTop];
        var sc:Array = shapeCache;
        var bs:Array = blackScores;
        var ws:Array = whiteScores;

        // 逆序恢复 dirty neighbors（每条 7 值，头部 12 值为 (x,y) 和总分）
        var headerEnd:Number = mark + 12;
        while (top > headerEnd) {
            top -= 7;
            var nx:Number = st[top];
            var ny:Number = st[top + 1];
            var dIdx:Number = st[top + 2];
            sc[0][dIdx][nx][ny] = st[top + 3];
            sc[1][dIdx][nx][ny] = st[top + 4];
            bs[nx][ny] = st[top + 5];
            ws[nx][ny] = st[top + 6];
        }

        // 恢复 (x,y) 棋型缓存和分数
        sc[0][0][x][y] = st[mark + 2]; sc[0][1][x][y] = st[mark + 3];
        sc[0][2][x][y] = st[mark + 4]; sc[0][3][x][y] = st[mark + 5];
        sc[1][0][x][y] = st[mark + 6]; sc[1][1][x][y] = st[mark + 7];
        sc[1][2][x][y] = st[mark + 8]; sc[1][3][x][y] = st[mark + 9];
        bs[x][y] = st[mark + 10];
        ws[x][y] = st[mark + 11];

        // 恢复总分
        _totalBlack = st[mark];
        _totalWhite = st[mark + 1];

        _undoTop = mark;
        history.length--;
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

    private function frontierAdd(flat:Number):Void {
        if (_frontierIndex[flat] >= 0) return;
        _frontierIndex[flat] = _frontierTop;
        _frontierList[_frontierTop] = flat;
        _frontierTop++;
    }

    private function frontierRemove(flat:Number):Void {
        var idx:Number = _frontierIndex[flat];
        if (idx < 0) return;
        _frontierTop--;
        var tailFlat:Number = _frontierList[_frontierTop];
        if (idx < _frontierTop) {
            _frontierList[idx] = tailFlat;
            _frontierIndex[tailFlat] = idx;
        }
        _frontierIndex[flat] = -1;
    }

    private function updateFrontierMove(x:Number, y:Number):Void {
        var flatCenter:Number = x * size + y;
        frontierRemove(flatCenter);

        var brd:Array = board;
        var counts:Array = _frontierCount;
        var flat:Array = dirtyMap[x][y];
        var sz:Number = size;
        for (var i:Number = 0; i < flat.length; i += 4) {
            var nx:Number = flat[i];
            var ny:Number = flat[i + 1];
            var nFlat:Number = nx * sz + ny;
            var nextCount:Number = counts[nFlat] + 1;
            counts[nFlat] = nextCount;
            if (nextCount === 1 && brd[nx + 1][ny + 1] === 0) {
                frontierAdd(nFlat);
            }
        }
    }

    private function updateFrontierUndo(x:Number, y:Number):Void {
        var brd:Array = board;
        var counts:Array = _frontierCount;
        var flat:Array = dirtyMap[x][y];
        var sz:Number = size;
        for (var i:Number = 0; i < flat.length; i += 4) {
            var nx:Number = flat[i];
            var ny:Number = flat[i + 1];
            var nFlat:Number = nx * sz + ny;
            var nextCount:Number = counts[nFlat] - 1;
            counts[nFlat] = nextCount;
            if (nextCount === 0 && brd[nx + 1][ny + 1] === 0) {
                frontierRemove(nFlat);
            }
        }

        var flatCenter:Number = x * sz + y;
        if (counts[flatCenter] > 0) {
            frontierAdd(flatCenter);
        } else {
            frontierRemove(flatCenter);
        }
    }

    // 分值查找表 — 按棋型值(0-50)直接索引，消除函数调用 + if 链开销
    private static var _scoreLUT:Array = null;
    private static function _initScoreLUT():Void {
        if (_scoreLUT !== null) return;
        var a:Array = new Array(51);
        var i:Number = 50;
        while (i >= 0) { a[i] = 0; i--; }
        a[2] = 10;       // TWO → ONE_SCORE
        a[3] = 100;      // THREE → TWO_SCORE
        a[4] = 1000;     // FOUR → THREE_SCORE
        a[5] = 100000;   // FIVE → FOUR_SCORE
        a[22] = 20;      // TWO_TWO
        a[30] = 15;      // BLOCK_THREE → BLOCK_TWO_SCORE
        a[33] = 5000;    // THREE_THREE
        a[40] = 150;     // BLOCK_FOUR → BLOCK_THREE_SCORE
        a[43] = 1000;    // FOUR_THREE → THREE_SCORE
        a[44] = 1000;    // FOUR_FOUR → THREE_SCORE
        a[50] = 1500;    // BLOCK_FIVE → BLOCK_FOUR_SCORE
        _scoreLUT = a;
    }

    // dirOx/dirOy: 指定只更新一个方向 (-1,-1 = 全部4方向)

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
        var lut:Array = _scoreLUT;

        // 累加已有方向分值（LUT 直接索引，消除函数调用）
        es = scx0[y]; if (es) { score += lut[es]; if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = scx1[y]; if (es) { score += lut[es]; if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = scx2[y]; if (es) { score += lut[es]; if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = scx3[y]; if (es) { score += lut[es]; if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }

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
                score += lut[sh];
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
                score += lut[sh2];
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

    // 轻量 getMoves — 遍历活跃前沿，紧急战术位优先
    public function getMoves(role:Number, depth:Number, onlyThree:Boolean, onlyFour:Boolean):Array {
        var brd:Array = board;
        var sz:Number = size;
        var result:Array = [];
        var limit:Number = GobangConfig.pointsLimit;
        if (limit < 1) limit = 1;
        // 深层搜索适度衰减候选数（过激会破坏 alpha-beta 剪枝）
        if (depth >= 4 && limit > 10) limit = 10;
        var bs:Array = blackScores;
        var ws:Array = whiteScores;
        var atk:Array = role === 1 ? bs : ws;
        var def:Array = role === 1 ? ws : bs;
        var atkShape:Array = role === 1 ? shapeCache[0] : shapeCache[1];
        var defShape:Array = role === 1 ? shapeCache[1] : shapeCache[0];
        var atk0:Array = atkShape[0];
        var atk1:Array = atkShape[1];
        var atk2:Array = atkShape[2];
        var atk3:Array = atkShape[3];
        var def0:Array = defShape[0];
        var def1:Array = defShape[1];
        var def2:Array = defShape[2];
        var def3:Array = defShape[3];
        var hasFive:Boolean = false;
        var hasFour:Boolean = false;
        var frontier:Array = _frontierList;
        var frontierTop:Number = _frontierTop;

        for (var fi:Number = 0; fi < frontierTop; fi++) {
            var flatPos:Number = frontier[fi];
            var i:Number = flatPos / sz;
            i = i | 0;
            var j:Number = flatPos - i * sz;
            if (brd[i + 1][j + 1] !== 0) continue;

            var attackScore:Number = atk[i][j];
            var defendScore:Number = def[i][j];
            if (attackScore === 0 && defendScore === 0) continue;

            var a0:Number = atk0[i][j];
            var a1:Number = atk1[i][j];
            var a2:Number = atk2[i][j];
            var a3:Number = atk3[i][j];
            var d0:Number = def0[i][j];
            var d1:Number = def1[i][j];
            var d2:Number = def2[i][j];
            var d3:Number = def3[i][j];

            var attackMax:Number = a0;
            if (a1 > attackMax) attackMax = a1;
            if (a2 > attackMax) attackMax = a2;
            if (a3 > attackMax) attackMax = a3;
            var defendMax:Number = d0;
            if (d1 > defendMax) defendMax = d1;
            if (d2 > defendMax) defendMax = d2;
            if (d3 > defendMax) defendMax = d3;

            var maxS:Number = attackMax > defendMax ? attackMax : defendMax;
            if (!maxS) continue;

            // FIVE/BLOCK_FIVE（值 5 或 50）最高优先
            if (attackMax === 5 || attackMax === 50 || defendMax === 5 || defendMax === 50) {
                if (!hasFive) {
                    result.length = 0;
                    hasFive = true;
                    hasFour = false;
                }
                var fiveLen:Number = result.length;
                var fiveAt:Number = fiveLen;
                while (fiveAt > 0) {
                    var prevFive:Array = result[fiveAt - 1];
                    var prevFiveFlat:Number = prevFive[0] * sz + prevFive[1];
                    if (flatPos > prevFiveFlat) break;
                    result[fiveAt] = prevFive;
                    fiveAt--;
                }
                result[fiveAt] = [i, j];
                continue;
            }
            if (hasFive) continue;

            // FOUR/BLOCK_FOUR 强制手：直接缩小根分支，兼顾棋力与性能
            var isFourMove:Boolean = (attackMax >= 4 || defendMax >= 4);
            if (isFourMove) {
                var majorFour:Number = attackScore > defendScore ? attackScore : defendScore;
                var fourKey:Number = attackScore + defendScore + majorFour;
                if (!hasFour) {
                    result.length = 0;
                    hasFour = true;
                }
                var fourLen:Number = result.length;
                var fourAt:Number = fourLen;
                while (fourAt > 0) {
                    var prevFour:Array = result[fourAt - 1];
                    var prevFourKey:Number = prevFour[2];
                    var prevFourFlat:Number = prevFour[0] * sz + prevFour[1];
                    if (fourKey < prevFourKey) break;
                    if (fourKey === prevFourKey && flatPos > prevFourFlat) break;
                    result[fourAt] = prevFour;
                    fourAt--;
                }
                result[fourAt] = [i, j, fourKey];
                continue;
            }
            if (hasFour) continue;

            if (onlyFour && maxS < 4) continue;
            if (onlyThree && maxS < 3) continue;

            // 评分：优先兼顾本方进攻和对方威胁，避免排序回调开销
            var major:Number = attackScore > defendScore ? attackScore : defendScore;
            var sortKey:Number = attackScore + defendScore + major;
            var resultLen:Number = result.length;
            var tail:Array = resultLen > 0 ? result[resultLen - 1] : null;
            var tailBetter:Boolean = (tail !== null && (sortKey > tail[2]
                || (sortKey === tail[2] && flatPos < tail[0] * sz + tail[1])));
            if (resultLen < limit || tailBetter) {
                var insertAt:Number = resultLen;
                if (insertAt >= limit) insertAt = limit - 1;
                while (insertAt > 0) {
                    var prev:Array = result[insertAt - 1];
                    var prevKey:Number = prev[2];
                    var prevFlat:Number = prev[0] * sz + prev[1];
                    if (sortKey < prevKey) break;
                    if (sortKey === prevKey && flatPos > prevFlat) break;
                    if (insertAt < limit) {
                        result[insertAt] = prev;
                    }
                    insertAt--;
                }
                result[insertAt] = [i, j, sortKey];
                if (resultLen < limit) {
                    result.length = resultLen + 1;
                }
            }
        }

        if (hasFive) return result;
        if (hasFour) {
            for (var fi2:Number = 0; fi2 < result.length; fi2++) {
                result[fi2].length = 2;
            }
            return result;
        }

        // 清除排序键
        for (var ci:Number = 0; ci < result.length; ci++) {
            result[ci].length = 2;
        }
        return result;
    }
}
