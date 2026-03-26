import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangEval {
    public var size:Number;
    public var board:Array;        // padded (size+2)x(size+2), border=2
    public var blackScores:Array;  // [size*size] flat, index = x*SZ+y
    public var whiteScores:Array;  // [size*size] flat, index = x*SZ+y
    private var _totalBlack:Number; // 增量总分
    private var _totalWhite:Number;
    public var shapeCache:Array;   // [2][4][size][size] — roleIdx, direction, x, y
    public var history:Array;      // 仅用于记录手数（供搜索阶段判断）

    // Save/Restore undo 栈 — 消除 undo 重计算开销
    private var _undoStack:Array;
    private var _undoTop:Number;
    private var _undoMarks:Array;
    private var _undoMarkTop:Number;

    // 中心偏向权重表（root 层 sortKey 用，避免 evaluate 对称抵消）
    private static var _posWeight:Array;
    private static var _posWeightReady:Boolean = false;
    private static function _initPosWeight(sz:Number):Void {
        if (_posWeightReady) return;
        _posWeight = new Array(sz * sz);
        var center:Number = (sz - 1) >> 1;
        for (var i:Number = 0; i < sz; i++) {
            for (var j:Number = 0; j < sz; j++) {
                var dx:Number = i - center; if (dx < 0) dx = -dx;
                var dy:Number = j - center; if (dy < 0) dy = -dy;
                var dist:Number = dx > dy ? dx : dy;
                _posWeight[i * sz + j] = (center - dist) * 5; // R28: ×4→×5 中心偏好
            }
        }
        _posWeightReady = true;
    }

    // 候选前沿：只遍历当前活跃空位，避免 getMoves 全盘扫描
    private var _frontierCount:Array; // [flat] 邻近棋子数
    private var _frontierIndex:Array; // [flat] 在 _frontierList 中的位置，-1=不活跃
    public var _frontierList:Array;   // [flat, ...] — Minmax 覆盖数排序需要访问
    public var _frontierTop:Number;

    // 棋盘尺寸常量（冻结为 15 路标准五子棋）
    private static var SZ:Number = 15;
    private static var PADDED:Number = 17;     // SZ + 2（含哨兵边界）
    private static var SC_DIR:Number = 225;    // SZ * SZ，shapeCache 单方向平面大小
    private static var SC_ROLE:Number = 900;   // 4 * SC_DIR，shapeCache 单角色平面大小

    // 方向表
    private static var allDirs:Array = [[0, 1], [1, 0], [1, 1], [1, -1]];
    private static var dirtyMap:Array = null;
    private static var dirtyMapSize:Number = 0;
    private static var TWO_COMBO_BONUS:Number = 50;
    private static var BRIDGE_SIDE_BONUS:Number = 16; // R27: 12→16
    private static var BRIDGE_LINK_BONUS:Number = 18;
    private static var BRIDGE_SPAN_BONUS:Number = 12;
    private static var TRUE_THREAT_LIMIT:Number = 2;
    private static var EXACT_URGENT_OPP_WIN_PENALTY:Number = 300000;
    private static var EXACT_URGENT_OPP_TRUE_FOUR_PENALTY:Number = 90000;
    private static var EXACT_URGENT_OWN_WIN_BONUS:Number = 20000;
    private static var EXACT_URGENT_OWN_TRUE_FOUR_BONUS:Number = 4000;
    private static var EXACT_URGENT_MULTI_COVER_BONUS:Number = 30000;
    private var _exactUrgentTier:Number;
    private var _exactUrgentPriority:Number;

    public function GobangEval(size:Number) {
        if (size === undefined) size = 15;
        this.size = size;
        history = [];
        _totalBlack = 0;
        _totalWhite = 0;
        initDirtyMap(size);
        _initScoreLUT();
        _initPosWeight(size);

        // 初始化 padded board（1D 扁平数组，索引 = x*PADDED+y）
        board = new Array(289);
        for (var bi:Number = 0; bi < 289; bi++) {
            var bx2:Number = (bi / PADDED) | 0;
            var by2:Number = bi - bx2 * PADDED;
            board[bi] = (bx2 === 0 || by2 === 0 || bx2 === 16 || by2 === 16) ? 2 : 0;
        }

        // 初始化分数数组（1D 扁平，索引 = x*SZ+y）
        blackScores = new Array(225);
        whiteScores = new Array(225);
        for (var si:Number = 0; si < 225; si++) { blackScores[si] = 0; whiteScores[si] = 0; }

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

        // 初始化 shapeCache: 一维 [ri*900 + di*225 + x*15 + y]
        shapeCache = new Array(1800);
        for (var sci:Number = 0; sci < 1800; sci++) shapeCache[sci] = 0;
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
        var xy:Number = x * SZ + y;
        st[top] = sc[xy]; st[top + 1] = sc[SC_DIR + xy];
        st[top + 2] = sc[450 + xy]; st[top + 3] = sc[675 + xy];
        st[top + 4] = sc[SC_ROLE + xy]; st[top + 5] = sc[SC_ROLE + SC_DIR + xy];
        st[top + 6] = sc[SC_ROLE + 450 + xy]; st[top + 7] = sc[SC_ROLE + 675 + xy];
        st[top + 8] = bs[xy]; st[top + 9] = ws[xy];
        top += 10;

        // 清除 (x,y) 棋型和分数
        var riBase:Number = ri * SC_ROLE;
        var oriBase:Number = ori * SC_ROLE;
        sc[riBase + xy] = 0; sc[riBase + SC_DIR + xy] = 0;
        sc[riBase + 450 + xy] = 0; sc[riBase + 675 + xy] = 0;
        sc[oriBase + xy] = 0; sc[oriBase + SC_DIR + xy] = 0;
        sc[oriBase + 450 + xy] = 0; sc[oriBase + 675 + xy] = 0;
        _totalBlack -= bs[xy];
        _totalWhite -= ws[xy];
        bs[xy] = 0;
        ws[xy] = 0;

        // 更新 padded board
        board[(x + 1) * PADDED + (y + 1)] = role;
        updateFrontierMove(x, y);

        // 保存 + 更新 dirty neighbors
        var brd:Array = board;
        var flat:Array = dirtyMap[xy];
        var flen:Number = flat.length;
        for (var i:Number = 0; i < flen; i += 4) {
            var nx:Number = flat[i];
            var ny:Number = flat[i + 1];
            var pFlat:Number = (nx + 1) * PADDED + (ny + 1);
            if (brd[pFlat] !== 0) continue;
            var ox:Number = flat[i + 2];
            var oy:Number = flat[i + 3];
            // 内联 direction2index
            var dirIdx:Number;
            if (ox === 0) dirIdx = 0;
            else if (oy === 0) dirIdx = 1;
            else if (ox === oy) dirIdx = 2;
            else dirIdx = 3;
            // 快速跳过：新旧棋型均为 NONE → 无需更新
            var dFlat:Number = ox * PADDED + oy;
            var nxy:Number = nx * SZ + ny;
            if (brd[pFlat + dFlat] === 0
                && brd[pFlat - dFlat] === 0
                && brd[pFlat + dFlat + dFlat] === 0
                && brd[pFlat - dFlat - dFlat] === 0
                && sc[dirIdx * SC_DIR + nxy] === 0
                && sc[SC_ROLE + dirIdx * SC_DIR + nxy] === 0) {
                continue;
            }
            // 保存: nx, ny, dirIdx, 两角色棋型, 两角色分数
            var nOff:Number = dirIdx * SC_DIR + nxy;
            st[top] = nx; st[top + 1] = ny; st[top + 2] = dirIdx;
            st[top + 3] = sc[nOff];
            st[top + 4] = sc[SC_ROLE + nOff];
            st[top + 5] = bs[nxy];
            st[top + 6] = ws[nxy];
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
        board[(x + 1) * PADDED + (y + 1)] = 0;
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
            var nxy:Number = nx * SZ + ny;
            var nOff:Number = dIdx * SC_DIR + nxy;
            sc[nOff] = st[top + 3];
            sc[SC_ROLE + nOff] = st[top + 4];
            bs[nxy] = st[top + 5];
            ws[nxy] = st[top + 6];
        }

        // 恢复 (x,y) 棋型缓存和分数
        var xy:Number = x * SZ + y;
        sc[xy] = st[mark + 2]; sc[SC_DIR + xy] = st[mark + 3];
        sc[450 + xy] = st[mark + 4]; sc[675 + xy] = st[mark + 5];
        sc[SC_ROLE + xy] = st[mark + 6]; sc[SC_ROLE + SC_DIR + xy] = st[mark + 7];
        sc[SC_ROLE + 450 + xy] = st[mark + 8]; sc[SC_ROLE + 675 + xy] = st[mark + 9];
        bs[x * SZ + y] = st[mark + 10];
        ws[x * SZ + y] = st[mark + 11];

        // 恢复总分
        _totalBlack = st[mark];
        _totalWhite = st[mark + 1];

        _undoTop = mark;
        history.length--;
    }

    private static function initDirtyMap(size:Number):Void {
        if (dirtyMap !== null && dirtyMapSize === size) return;
        dirtyMapSize = size;
        dirtyMap = new Array(size * size);
        for (var x:Number = 0; x < size; x++) {
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
                dirtyMap[x * size + y] = flat;
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
        var flat:Array = dirtyMap[flatCenter];
        var sz:Number = size;
        for (var i:Number = 0; i < flat.length; i += 4) {
            var nx:Number = flat[i];
            var ny:Number = flat[i + 1];
            var nFlat:Number = nx * sz + ny;
            var nextCount:Number = counts[nFlat] + 1;
            counts[nFlat] = nextCount;
            if (nextCount === 1 && brd[(nx + 1) * PADDED + (ny + 1)] === 0) {
                frontierAdd(nFlat);
            }
        }
    }

    private function updateFrontierUndo(x:Number, y:Number):Void {
        var brd:Array = board;
        var counts:Array = _frontierCount;
        var flat:Array = dirtyMap[x * size + y];
        var sz:Number = size;
        for (var i:Number = 0; i < flat.length; i += 4) {
            var nx:Number = flat[i];
            var ny:Number = flat[i + 1];
            var nFlat:Number = nx * sz + ny;
            var nextCount:Number = counts[nFlat] - 1;
            counts[nFlat] = nextCount;
            if (nextCount === 0 && brd[(nx + 1) * PADDED + (ny + 1)] === 0) {
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
        // 2026-03-26 自动化调优结果（18轮迭代，Rapfi 验证）
        // 单调性链: TWO(20)×2=40 < BLOCK_THREE(100) < TWO_TWO(150)
        //   < THREE(400)×2=800 < BLOCK_FOUR(900) < FOUR(1000)×2=2000
        //   < THREE_THREE(15000) < FOUR_THREE/FOUR_FOUR(50000) < FIVE/BLOCK_FIVE(100000)
        a[2] = 20;       // TWO — 早期空间控制
        a[3] = 440;      // THREE — 活三威胁 (R14: 400→440, 保持 BF(900)>440×2=880)
        a[4] = 1200;     // FOUR — 活四 (R20: 1000→1200)
        a[5] = 100000;   // FIVE — 成五
        a[22] = 180;     // TWO_TWO — 交叉二连 (R15: 150→180)
        a[30] = 120;     // BLOCK_THREE — 堵活三 (R9: 100→120 防守意识)
        a[33] = 18000;   // THREE_THREE — 双活三 (R22: 15000→18000)
        a[40] = 1000;    // BLOCK_FOUR — 堵活四 (R21: 900→1000)
        a[43] = 60000;   // FOUR_THREE — 冲四活三 (R26: 50000→60000)
        a[44] = 60000;   // FOUR_FOUR — 双冲四 (R26: 50000→60000)
        a[50] = 100000;  // BLOCK_FIVE — 胜着
        _scoreLUT = a;
    }

    private function computeBridgePotential(x:Number, y:Number, role:Number):Number {
        var brd:Array = board;
        var opp:Number = -role;
        var ad:Array = allDirs;
        var totalBonus:Number = 0;

        for (var di:Number = 0; di < 4; di++) {
            var dv:Array = ad[di];
            var ox:Number = dv[0];
            var oy:Number = dv[1];

            var lNearest:Number = 0;
            var lFarthest:Number = 0;
            var lCount:Number = 0;
            var pos:Number = (x + 1) * PADDED + (y + 1);
            var dFlat2:Number = ox * PADDED + oy;
            var cpos:Number = pos - dFlat2;
            for (var ls:Number = 1; ls <= 4; ls++) {
                var cur:Number = brd[cpos];
                if (cur === 2 || cur === opp) break;
                if (cur === role) {
                    lCount++;
                    if (lNearest === 0) lNearest = ls;
                    lFarthest = ls;
                }
                cpos -= dFlat2;
            }

            var rNearest:Number = 0;
            var rFarthest:Number = 0;
            var rCount:Number = 0;
            cpos = pos + dFlat2;
            for (var rs:Number = 1; rs <= 4; rs++) {
                cur = brd[cpos];
                if (cur === 2 || cur === opp) break;
                if (cur === role) {
                    rCount++;
                    if (rNearest === 0) rNearest = rs;
                    rFarthest = rs;
                }
                cpos += dFlat2;
            }

            var dirBonus:Number = 0;
            var totalStones:Number = lCount + rCount;
            if (totalStones === 0) continue;

            if (lNearest > 0 && rNearest > 0) {
                dirBonus += BRIDGE_LINK_BONUS;
                if (lNearest + rNearest <= 4) dirBonus += BRIDGE_LINK_BONUS;
                if (lFarthest + rFarthest + 1 >= 6) dirBonus += BRIDGE_SPAN_BONUS;
                if (totalStones >= 3) dirBonus += BRIDGE_SIDE_BONUS;
            } else {
                var near:Number = lNearest > 0 ? lNearest : rNearest;
                var far:Number = lFarthest > 0 ? lFarthest : rFarthest;
                if (near === 2) dirBonus += BRIDGE_SIDE_BONUS;
                else if (near === 3) dirBonus += (BRIDGE_SIDE_BONUS >> 1);
                if (totalStones >= 2 && far >= 3) dirBonus += (BRIDGE_SIDE_BONUS - 2);
            }
            totalBonus += dirBonus;
        }

        return totalBonus;
    }

    private function countImmediateWins(role:Number, limit:Number):Number {
        if (limit === undefined || limit < 1) limit = 1;
        var brd:Array = board;
        var sz:Number = size;
        var frontier:Array = _frontierList;
        var frontierTop:Number = _frontierTop;
        var sc:Array = shapeCache;
        var atkBase:Number = (role === 1) ? 0 : SC_ROLE;
        var wins:Number = 0;

        for (var fi:Number = 0; fi < frontierTop; fi++) {
            var flatPos:Number = frontier[fi];
            var i:Number = flatPos / sz;
            i = i | 0;
            var j:Number = flatPos - i * sz;
            if (brd[(i + 1) * PADDED + (j + 1)] !== 0) continue;

            var ij:Number = i * SZ + j;
            var a0:Number = sc[atkBase + ij];
            var a1:Number = sc[atkBase + SC_DIR + ij];
            var a2:Number = sc[atkBase + 450 + ij];
            var a3:Number = sc[atkBase + 675 + ij];
            if (a0 === 5 || a0 === 50 || a1 === 5 || a1 === 50
                || a2 === 5 || a2 === 50 || a3 === 5 || a3 === 50) {
                wins++;
                if (wins >= limit) return wins;
            }
        }
        return wins;
    }

    private function countTrueFourMoves(role:Number, limit:Number):Number {
        if (limit === undefined || limit < 1) limit = 1;
        var brd:Array = board;
        var sz:Number = size;
        var frontier:Array = _frontierList;
        var frontierTop:Number = _frontierTop;
        var atk:Array = role === 1 ? blackScores : whiteScores;
        var sc:Array = shapeCache;
        var atkBase:Number = (role === 1) ? 0 : SC_ROLE;
        var count:Number = 0;

        for (var fi:Number = 0; fi < frontierTop; fi++) {
            var flatPos:Number = frontier[fi];
            var i:Number = flatPos / sz;
            i = i | 0;
            var j:Number = flatPos - i * sz;
            if (brd[(i + 1) * PADDED + (j + 1)] !== 0) continue;
            var ij:Number = i * SZ + j;
            if (atk[ij] === 0) continue;
            var a0:Number = sc[atkBase + ij];
            var a1:Number = sc[atkBase + SC_DIR + ij];
            var a2:Number = sc[atkBase + 450 + ij];
            var a3:Number = sc[atkBase + 675 + ij];
            if (a0 === 5 || a0 === 50 || a1 === 5 || a1 === 50
                || a2 === 5 || a2 === 50 || a3 === 5 || a3 === 50) {
                count++;
                if (count >= limit) return count;
                continue;
            }

            var attackMax:Number = a0;
            if (a1 > attackMax) attackMax = a1;
            if (a2 > attackMax) attackMax = a2;
            if (a3 > attackMax) attackMax = a3;
            var atkThrees:Number = 0;
            if (a0 === 3) atkThrees++;
            if (a1 === 3) atkThrees++;
            if (a2 === 3) atkThrees++;
            if (a3 === 3) atkThrees++;
            if (attackMax < 3 && atkThrees < 2) continue;

            move(i, j, role);
            var wins:Number = countImmediateWins(role, 1);
            undo(i, j);
            if (wins > 0) {
                count++;
                if (count >= limit) return count;
            }
        }
        return count;
    }

    private function getExactAttackThreatTier(x:Number, y:Number, role:Number,
            attackMax:Number, atkThrees:Number):Number {
        if (attackMax === 5 || attackMax === 50) return 4;
        if (attackMax < 3 && atkThrees < 2) return 0;

        move(x, y, role);
        var tier:Number = 0;
        if (countImmediateWins(role, 1) > 0) {
            tier = 3;
        } else if (countTrueFourMoves(role, TRUE_THREAT_LIMIT) >= TRUE_THREAT_LIMIT) {
            tier = 2;
        }
        undo(x, y);
        return tier;
    }

    private function analyzeExactUrgentMove(x:Number, y:Number, role:Number,
            attackMax:Number, atkThrees:Number,
            oppImmediateWins:Number, oppTrueFourMoves:Number):Void {
        move(x, y, role);

        var ownImmediateWins:Number = 0;
        var ownTrueFourMoves:Number = 0;
        var oppRemainWins:Number = 0;
        var oppRemainTrueFourMoves:Number = 0;
        var tier:Number = 0;
        if (attackMax === 5 || attackMax === 50) {
            ownImmediateWins = 1;
            tier = 4;
        } else {
            ownImmediateWins = countImmediateWins(role, TRUE_THREAT_LIMIT);
            if (ownImmediateWins > 0) {
                tier = 3;
            } else {
                ownTrueFourMoves = countTrueFourMoves(role, TRUE_THREAT_LIMIT);
                if (ownTrueFourMoves >= TRUE_THREAT_LIMIT) {
                    tier = 2;
                }
            }
        }

        oppRemainWins = countImmediateWins(-role, TRUE_THREAT_LIMIT);
        if (oppRemainWins === 0) {
            oppRemainTrueFourMoves = countTrueFourMoves(-role, TRUE_THREAT_LIMIT);
        }

        if (oppImmediateWins > 0) {
            if (oppRemainWins === 0 && tier < 3) {
                tier = 3;
            }
        } else if (oppTrueFourMoves > 0) {
            if (oppRemainWins === 0 && oppRemainTrueFourMoves === 0 && tier < 2) {
                tier = 2;
            }
        }

        var priority:Number = tier * 1000000
            - oppRemainWins * EXACT_URGENT_OPP_WIN_PENALTY
            - oppRemainTrueFourMoves * EXACT_URGENT_OPP_TRUE_FOUR_PENALTY
            + ownImmediateWins * EXACT_URGENT_OWN_WIN_BONUS
            + ownTrueFourMoves * EXACT_URGENT_OWN_TRUE_FOUR_BONUS;
        if (oppImmediateWins + oppTrueFourMoves >= 2 && oppRemainWins + oppRemainTrueFourMoves === 0) {
            priority += EXACT_URGENT_MULTI_COVER_BONUS;
        }
        _exactUrgentTier = tier;
        _exactUrgentPriority = priority;
        undo(x, y);
    }

    private function getThreatCoverageBonus(atkMajorDirs:Number, atkThrees:Number,
            defMajorDirs:Number, defThrees:Number):Number {
        var bonus:Number = defMajorDirs * 12000 + defThrees * 8000
            + atkMajorDirs * 4000 + atkThrees * 2500;
        if (defMajorDirs >= 2) bonus += 24000;
        if (defThrees >= 2) bonus += 12000;
        if (atkMajorDirs >= 2) bonus += 8000;
        return bonus;
    }

    // dirOx/dirOy: 指定只更新一个方向 (-1,-1 = 全部4方向)

    private function updateSinglePoint(x:Number, y:Number, role:Number, dirOx:Number, dirOy:Number):Void {
        // 局部变量缓存（AVM1: 局部=0ns vs 成员=144ns）
        var brd:Array = board;
        if (brd[(x + 1) * PADDED + (y + 1)] !== 0) return;

        // 内联 roleIndex: role===1 ? 0 : 1
        var ri:Number = role === 1 ? 0 : 1;
        var sc:Array = shapeCache;
        var scBase:Number = ri * SC_ROLE;
        var xOff:Number = x * SZ + y;
        var hasSingleDir:Boolean = (dirOx !== -1);

        // 内联 direction2index 清除缓存
        if (hasSingleDir) {
            var dirIdx:Number;
            if (dirOx === 0) dirIdx = 0;
            else if (dirOy === 0) dirIdx = 1;
            else if (dirOx === dirOy) dirIdx = 2;
            else dirIdx = 3;
            sc[scBase + dirIdx * SC_DIR + xOff] = 0;
        } else {
            sc[scBase + xOff] = 0;
            sc[scBase + SC_DIR + xOff] = 0;
            sc[scBase + 450 + xOff] = 0;
            sc[scBase + 675 + xOff] = 0;
        }

        var score:Number = 0;
        var comboBonus:Number = 0;
        var bfc:Number = 0;
        var thc:Number = 0;
        var twc:Number = 0;
        var es:Number;
        var lut:Array = _scoreLUT;

        // 累加已有方向分值（LUT 直接索引，消除函数调用）
        es = sc[scBase + xOff]; if (es) { score += lut[es]; if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = sc[scBase + SC_DIR + xOff]; if (es) { score += lut[es]; if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = sc[scBase + 450 + xOff]; if (es) { score += lut[es]; if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }
        es = sc[scBase + 675 + xOff]; if (es) { score += lut[es]; if (es === 40) bfc++; if (es === 3) thc++; if (es === 2) twc++; }

        // 计算新方向棋型
        var gsf:Function = GobangShape.getShapeFast;
        if (hasSingleDir) {
            var sh:Number = gsf(brd, x, y, dirOx, dirOy, role);
            if (sh) {
                sc[scBase + dirIdx * SC_DIR + xOff] = sh;
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
                sc[scBase + ni * SC_DIR + xOff] = sh2;
                if (sh2 === 40) bfc++; if (sh2 === 3) thc++; if (sh2 === 2) twc++;
                if (bfc >= 2) sh2 = 44;
                else if (bfc && thc) sh2 = 43;
                else if (thc >= 2) sh2 = 33;
                else if (twc >= 2) sh2 = 22;
                score += lut[sh2];
            }
        }

        // 组合潜力：同一点两条 TWO 协同意味着后续更容易转化为双三/冲四
        if (twc >= 2) {
            comboBonus = (twc - 1) * TWO_COMBO_BONUS;
            score += comboBonus;
        }

        if (role === 1) {
            _totalBlack += score - blackScores[xOff];
            blackScores[xOff] = score;
        } else {
            _totalWhite += score - whiteScores[xOff];
            whiteScores[xOff] = score;
        }
    }

    public function evaluate(role:Number):Number {
        return role === 1 ? _totalBlack - _totalWhite : _totalWhite - _totalBlack;
    }

    // Threat-only moves：仅保留本方能直接制造威胁的走法，供轻量 TSS 使用
    public function getThreatMoves(role:Number, minShape:Number, limit:Number):Array {
        if (minShape === undefined || minShape < 2) minShape = 2;
        if (limit === undefined || limit < 1) limit = 1;

        var brd:Array = board;
        var sz:Number = size;
        var frontier:Array = _frontierList;
        var frontierTop:Number = _frontierTop;
        var atkScores:Array = role === 1 ? blackScores : whiteScores;
        var sc:Array = shapeCache;
        var atkBase:Number = (role === 1) ? 0 : SC_ROLE;
        var result:Array = [];
        var hasFive:Boolean = false;
        var hasMajor:Boolean = false;

        for (var fi:Number = 0; fi < frontierTop; fi++) {
            var flatPos:Number = frontier[fi];
            var i:Number = flatPos / sz;
            i = i | 0;
            var j:Number = flatPos - i * sz;
            if (brd[(i + 1) * PADDED + (j + 1)] !== 0) continue;

            var ij:Number = i * SZ + j;
            var attackScore:Number = atkScores[ij];
            if (attackScore === 0) continue;
            var a0:Number = sc[atkBase + ij];
            var a1:Number = sc[atkBase + SC_DIR + ij];
            var a2:Number = sc[atkBase + 450 + ij];
            var a3:Number = sc[atkBase + 675 + ij];
            var attackMax:Number = a0;
            if (a1 > attackMax) attackMax = a1;
            if (a2 > attackMax) attackMax = a2;
            if (a3 > attackMax) attackMax = a3;

            var atkThrees:Number = 0;
            if (a0 === 3) atkThrees++;
            if (a1 === 3) atkThrees++;
            if (a2 === 3) atkThrees++;
            if (a3 === 3) atkThrees++;
            var atkTwos:Number = 0;
            if (a0 === 2) atkTwos++;
            if (a1 === 2) atkTwos++;
            if (a2 === 2) atkTwos++;
            if (a3 === 2) atkTwos++;

            var threatTier:Number = 0;
            if (attackMax === 5 || attackMax === 50) {
                threatTier = 4;
            } else if (attackMax === 4) {
                threatTier = 3;
            } else if ((minShape >= 4 && attackMax >= 3) || attackMax === 40 || atkThrees >= 2) {
                threatTier = getExactAttackThreatTier(i, j, role, attackMax, atkThrees);
            } else if (attackMax >= 3) {
                threatTier = 2;
            } else if (minShape <= 2 && atkTwos >= 2) {
                threatTier = 1;
            }
            if (threatTier === 0) continue;

            if (threatTier < minShape - 1) continue;

            if (threatTier >= 4) {
                if (!hasFive) {
                    result.length = 0;
                    hasFive = true;
                    hasMajor = false;
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

            if (threatTier >= 3) {
                if (!hasMajor) {
                    result.length = 0;
                    hasMajor = true;
                }
            } else if (hasMajor) {
                continue;
            }

            var sortKey:Number = threatTier * 100000 + attackScore;
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

        for (var ri:Number = 0; ri < result.length; ri++) {
            result[ri].length = 2;
        }
        return result;
    }

    public function getBridgeMoves(role:Number, limit:Number, keepScore:Boolean):Array {
        if (limit === undefined || limit < 1) limit = 1;
        if (keepScore === undefined) keepScore = false;
        var brd:Array = board;
        var sz:Number = size;
        var frontier:Array = _frontierList;
        var frontierTop:Number = _frontierTop;
        var result:Array = [];

        for (var fi:Number = 0; fi < frontierTop; fi++) {
            var flatPos:Number = frontier[fi];
            var i:Number = flatPos / sz;
            i = i | 0;
            var j:Number = flatPos - i * sz;
            if (brd[(i + 1) * PADDED + (j + 1)] !== 0) continue;

            var bridgeAtk:Number = computeBridgePotential(i, j, role);
            var bridgeDef:Number = computeBridgePotential(i, j, -role) >> 1;
            var sortKey:Number = bridgeAtk + bridgeDef;
            if (sortKey <= 0) continue;

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

        if (!keepScore) {
            for (var ri:Number = 0; ri < result.length; ri++) {
                result[ri].length = 2;
            }
        }
        return result;
    }

    // 轻量 getMoves — 遍历活跃前沿，紧急战术位优先
    public function getMoves(role:Number, depth:Number, onlyThree:Boolean, onlyFour:Boolean):Array {
        var brd:Array = board;
        var sz:Number = size;
        var result:Array = [];
        var limit:Number = GobangConfig.pointsLimit;
        if (limit < 1) limit = 1;
        var isRoot:Boolean = (depth === 0);
        // 深层搜索适度衰减候选数，过激截断会直接伤棋力
        if (depth >= 5 && limit > 4) limit = 4;
        else if (depth >= 3 && limit > 6) limit = 6;
        else if (depth >= 2 && limit > 8) limit = 8;
        // root 层膨胀收集，后续补算 bridge 后截断回 limit
        var effectiveLimit:Number = isRoot ? (limit + 8) : limit;
        var bs:Array = blackScores;
        var ws:Array = whiteScores;
        var atk:Array = role === 1 ? bs : ws;
        var def:Array = role === 1 ? ws : bs;
        var sc:Array = shapeCache;
        var atkBase:Number = (role === 1) ? 0 : SC_ROLE;
        var defBase:Number = (role === 1) ? SC_ROLE : 0;
        var hasFive:Boolean = false;
        var hasFour:Boolean = false;
        var frontier:Array = _frontierList;
        var frontierTop:Number = _frontierTop;
        var exactOppStateReady:Boolean = false;
        var oppImmediateWins:Number = 0;
        var oppTrueFourMoves:Number = 0;

        for (var fi:Number = 0; fi < frontierTop; fi++) {
            var flatPos:Number = frontier[fi];
            var i:Number = flatPos / sz;
            i = i | 0;
            var j:Number = flatPos - i * sz;
            if (brd[(i + 1) * PADDED + (j + 1)] !== 0) continue;

            var ij:Number = i * SZ + j;
            var attackScore:Number = atk[ij];
            var defendScore:Number = def[ij];
            if (attackScore === 0 && defendScore === 0) continue;
            var a0:Number = sc[atkBase + ij];
            var a1:Number = sc[atkBase + SC_DIR + ij];
            var a2:Number = sc[atkBase + 450 + ij];
            var a3:Number = sc[atkBase + 675 + ij];
            var d0:Number = sc[defBase + ij];
            var d1:Number = sc[defBase + SC_DIR + ij];
            var d2:Number = sc[defBase + 450 + ij];
            var d3:Number = sc[defBase + 675 + ij];

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
            if (onlyFour && maxS < 4) continue;
            if (onlyThree && maxS < 3) continue;

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

            // FOUR/BLOCK_FOUR 或 双活三 强制手检测
            var atkThrees:Number = 0;
            if (a0 === 3) atkThrees++;
            if (a1 === 3) atkThrees++;
            if (a2 === 3) atkThrees++;
            if (a3 === 3) atkThrees++;
            var defThrees:Number = 0;
            if (d0 === 3) defThrees++;
            if (d1 === 3) defThrees++;
            if (d2 === 3) defThrees++;
            if (d3 === 3) defThrees++;
            var isFourMove:Boolean = (attackMax === 4 || defendMax === 4
                || atkThrees >= 2 || defThrees >= 2);

            // 非根层(depth>0)：跳过所有重量级分析(bridge/exact/coverage)，纯 shape-score 快速路径
            if (isRoot) {
                var atkMajorDirs:Number = 0;
                if (a0 >= 3 || a0 === 40) atkMajorDirs++;
                if (a1 >= 3 || a1 === 40) atkMajorDirs++;
                if (a2 >= 3 || a2 === 40) atkMajorDirs++;
                if (a3 >= 3 || a3 === 40) atkMajorDirs++;
                var defMajorDirs:Number = 0;
                if (d0 >= 3 || d0 === 40) defMajorDirs++;
                if (d1 >= 3 || d1 === 40) defMajorDirs++;
                if (d2 >= 3 || d2 === 40) defMajorDirs++;
                if (d3 >= 3 || d3 === 40) defMajorDirs++;
                var edgeMargin:Boolean = (i <= 1 || j <= 1 || i >= sz - 2 || j >= sz - 2);
                var pseudoAtkFour:Boolean = (attackMax === 40 && edgeMargin && atkMajorDirs <= 1 && atkThrees === 0);
                var pseudoDefFour:Boolean = (defendMax === 40 && edgeMargin && defMajorDirs <= 1 && defThrees === 0);
                if ((attackMax === 40 && !pseudoAtkFour) || (defendMax === 40 && !pseudoDefFour)) {
                    isFourMove = true;
                }
                // exact 过滤仅根层 VCT 模式
                if (onlyFour || onlyThree) {
                    if (!exactOppStateReady) {
                        oppImmediateWins = countImmediateWins(-role, TRUE_THREAT_LIMIT);
                        if (oppImmediateWins === 0) {
                            oppTrueFourMoves = countTrueFourMoves(-role, TRUE_THREAT_LIMIT);
                        }
                        exactOppStateReady = true;
                    }
                    analyzeExactUrgentMove(i, j, role, attackMax, atkThrees,
                        oppImmediateWins, oppTrueFourMoves);
                    if (onlyFour && _exactUrgentTier < 3) continue;
                    if (onlyThree && _exactUrgentTier < 2) continue;
                    isFourMove = true;
                }
            } else {
                // 内部节点：简化的 BLOCK_FOUR 判定（不做 edge pseudo 校验）
                if (attackMax === 40 || defendMax === 40) isFourMove = true;
            }

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

            // 评分：shape-score + 单活三堵点加权（确保不被覆盖排序淹没）
            var major:Number = attackScore > defendScore ? attackScore : defendScore;
            var threeBoost:Number = 0;
            if (defThrees >= 1) threeBoost += 8000;  // 堵对手活三
            if (atkThrees >= 1) threeBoost += 4000;   // 自己成活三
            var sortKey:Number = attackScore + defendScore + major + threeBoost;
            var resultLen:Number = result.length;
            var tail:Array = resultLen > 0 ? result[resultLen - 1] : null;
            var tailBetter:Boolean = (tail !== null && (sortKey > tail[2]
                || (sortKey === tail[2] && flatPos < tail[0] * sz + tail[1])));
            if (resultLen < effectiveLimit || tailBetter) {
                var insertAt:Number = resultLen;
                if (insertAt >= effectiveLimit) insertAt = effectiveLimit - 1;
                while (insertAt > 0) {
                    var prev:Array = result[insertAt - 1];
                    var prevKey:Number = prev[2];
                    var prevFlat:Number = prev[0] * sz + prev[1];
                    if (sortKey < prevKey) break;
                    if (sortKey === prevKey && flatPos > prevFlat) break;
                    if (insertAt < effectiveLimit) {
                        result[insertAt] = prev;
                    }
                    insertAt--;
                }
                result[insertAt] = [i, j, sortKey];
                if (resultLen < effectiveLimit) {
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

        // Phase 2: root 层补算 bridge + posWeight，重排后截断
        if (isRoot && result.length > 0) {
            var pw:Array = _posWeight;
            for (var bi:Number = 0; bi < result.length; bi++) {
                var rm:Array = result[bi];
                rm[2] += computeBridgePotential(rm[0], rm[1], role)
                       + (computeBridgePotential(rm[0], rm[1], -role) >> 1)
                       + pw[rm[0] * SZ + rm[1]];
            }
            // 重排（插入排序，size ≤ effectiveLimit ≈ 26）
            for (var si:Number = 1; si < result.length; si++) {
                var item:Array = result[si];
                var itemKey:Number = item[2];
                var sp:Number = si - 1;
                while (sp >= 0 && result[sp][2] < itemKey) {
                    result[sp + 1] = result[sp];
                    sp--;
                }
                result[sp + 1] = item;
            }
            // 截断到真实 limit
            if (result.length > limit) result.length = limit;
        }

        // 清除排序键
        for (var ci:Number = 0; ci < result.length; ci++) {
            result[ci].length = 2;
        }
        return result;
    }
}
