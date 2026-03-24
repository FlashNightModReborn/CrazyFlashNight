class org.flashNight.hana.Gobang.GobangShape {

    // ===== 基础棋型枚举 (getShapeFast 返回值) =====
    public static var NONE:Number        = 0;
    public static var TWO:Number         = 2;
    public static var BLOCK_THREE:Number = 30;
    public static var THREE:Number       = 3;
    public static var BLOCK_FOUR:Number  = 40;
    public static var FOUR:Number        = 4;
    public static var BLOCK_FIVE:Number  = 50;
    public static var FIVE:Number        = 5;

    // ===== 复合棋型 (Eval 跨方向合成) =====
    public static var FOUR_FOUR:Number   = 44;
    public static var FOUR_THREE:Number  = 43;
    public static var THREE_THREE:Number = 33;
    public static var TWO_TWO:Number     = 22;

    // ===== 分值常量 =====
    public static var FIVE_SCORE:Number        = 10000000;
    public static var BLOCK_FIVE_SCORE:Number  = 10000000;
    public static var FOUR_SCORE:Number        = 100000;
    public static var FOUR_FOUR_SCORE:Number   = 100000;
    public static var FOUR_THREE_SCORE:Number  = 100000;
    public static var THREE_THREE_SCORE:Number = 50000;
    public static var BLOCK_FOUR_SCORE:Number  = 1500;
    public static var THREE_SCORE:Number       = 1000;
    public static var BLOCK_THREE_SCORE:Number = 150;
    public static var TWO_TWO_SCORE:Number     = 200;
    public static var TWO_SCORE:Number         = 100;
    public static var BLOCK_TWO_SCORE:Number   = 15;
    public static var ONE_SCORE:Number         = 10;
    public static var BLOCK_ONE_SCORE:Number   = 1;

    // 完全按上游 eval.js 映射，不做本地重设计
    public static function getRealShapeScore(shape:Number):Number {
        if (shape === FIVE) return FOUR_SCORE;
        if (shape === BLOCK_FIVE) return BLOCK_FOUR_SCORE;
        if (shape === FOUR) return THREE_SCORE;
        if (shape === FOUR_FOUR) return THREE_SCORE;
        if (shape === FOUR_THREE) return THREE_SCORE;
        if (shape === BLOCK_FOUR) return BLOCK_THREE_SCORE;
        if (shape === THREE) return TWO_SCORE;
        if (shape === THREE_THREE) return THREE_THREE_SCORE / 10;
        if (shape === BLOCK_THREE) return BLOCK_TWO_SCORE;
        if (shape === TWO) return ONE_SCORE;
        if (shape === TWO_TWO) return TWO_TWO_SCORE / 10;
        return 0;
    }

    public static function isFive(shape:Number):Boolean {
        return shape === FIVE || shape === BLOCK_FIVE;
    }

    public static function isFour(shape:Number):Boolean {
        return shape === FOUR || shape === BLOCK_FOUR;
    }

    // 方向 (ox,oy) → 索引 0-3
    public static function direction2index(ox:Number, oy:Number):Number {
        if (ox === 0) return 0;
        if (oy === 0) return 1;
        if (ox === oy) return 2;
        return 3;
    }

    // ===== 零分配 countShape：结果写入静态字段 =====
    // 左侧 countShape 结果
    private static var _lSelf:Number;
    private static var _lTotal:Number;
    private static var _lNoEmpty:Number;
    private static var _lOneEmpty:Number;
    private static var _lSide:Number;
    // 右侧 countShape 结果
    private static var _rSelf:Number;
    private static var _rTotal:Number;
    private static var _rNoEmpty:Number;
    private static var _rOneEmpty:Number;
    private static var _rSide:Number;

    // 写入 _l* 或 _r* 静态字段，isRight: 0=左, 1=右
    private static function countShape(board:Array, x:Number, y:Number,
            offsetX:Number, offsetY:Number, role:Number, isRight:Number):Void {
        var opponent:Number = -role;
        var innerEmpty:Number = 0;
        var tempEmpty:Number = 0;
        var self:Number = 0;
        var total:Number = 0;
        var sideEmpty:Number = 0;
        var noEmpty:Number = 0;
        var oneEmpty:Number = 0;

        var cx:Number = x + offsetX + 1;
        var cy:Number = y + offsetY + 1;
        for (var i:Number = 1; i <= 5; i++) {
            var cur:Number = board[cx][cy];
            cx += offsetX;
            cy += offsetY;
            if (cur === 2 || cur === opponent) break;
            if (cur === role) {
                self++;
                sideEmpty = 0;
                if (tempEmpty) { innerEmpty += tempEmpty; tempEmpty = 0; }
                if (innerEmpty === 0) { noEmpty++; oneEmpty++; }
                else if (innerEmpty === 1) { oneEmpty++; }
            }
            total++;
            if (cur === 0) { tempEmpty++; sideEmpty++; }
            if (sideEmpty >= 2) break;
        }
        if (!innerEmpty) oneEmpty = 0;

        if (isRight) {
            _rSelf = self; _rTotal = total; _rNoEmpty = noEmpty; _rOneEmpty = oneEmpty; _rSide = sideEmpty;
        } else {
            _lSelf = self; _lTotal = total; _lNoEmpty = noEmpty; _lOneEmpty = oneEmpty; _lSide = sideEmpty;
        }
    }

    // 零分配版本：返回 shape Number（不返回 selfCount，调用者不使用）
    public static function getShapeFast(board:Array, x:Number, y:Number,
            offsetX:Number, offsetY:Number, role:Number):Number {
        var brd:Array = board;
        var px:Number = x + 1;
        var py:Number = y + 1;
        var off2X:Number = offsetX + offsetX;
        var off2Y:Number = offsetY + offsetY;
        if (brd[px + offsetX][py + offsetY] === 0
            && brd[px - offsetX][py - offsetY] === 0
            && brd[px + off2X][py + off2Y] === 0
            && brd[px - off2X][py - off2Y] === 0) {
            return NONE;
        }

        var opponent:Number = -role;
        var lTotal:Number = 0;
        var lNoEmpty:Number = 0;
        var lOneEmpty:Number = 0;
        var lSide:Number = 0;
        var rTotal:Number = 0;
        var rNoEmpty:Number = 0;
        var rOneEmpty:Number = 0;
        var rSide:Number = 0;
        var innerEmpty:Number;
        var tempEmpty:Number;
        var sideEmpty:Number;
        var cx:Number;
        var cy:Number;
        var cur:Number;
        var i:Number;

        innerEmpty = 0;
        tempEmpty = 0;
        sideEmpty = 0;
        cx = px - offsetX;
        cy = py - offsetY;
        for (i = 1; i <= 5; i++) {
            cur = brd[cx][cy];
            cx -= offsetX;
            cy -= offsetY;
            if (cur === 2 || cur === opponent) break;
            if (cur === role) {
                sideEmpty = 0;
                if (tempEmpty) { innerEmpty += tempEmpty; tempEmpty = 0; }
                if (innerEmpty === 0) { lNoEmpty++; lOneEmpty++; }
                else if (innerEmpty === 1) { lOneEmpty++; }
            }
            lTotal++;
            if (cur === 0) { tempEmpty++; sideEmpty++; }
            if (sideEmpty >= 2) break;
        }
        lSide = sideEmpty;
        if (!innerEmpty) lOneEmpty = 0;

        innerEmpty = 0;
        tempEmpty = 0;
        sideEmpty = 0;
        cx = px + offsetX;
        cy = py + offsetY;
        for (i = 1; i <= 5; i++) {
            cur = brd[cx][cy];
            cx += offsetX;
            cy += offsetY;
            if (cur === 2 || cur === opponent) break;
            if (cur === role) {
                sideEmpty = 0;
                if (tempEmpty) { innerEmpty += tempEmpty; tempEmpty = 0; }
                if (innerEmpty === 0) { rNoEmpty++; rOneEmpty++; }
                else if (innerEmpty === 1) { rOneEmpty++; }
            }
            rTotal++;
            if (cur === 0) { tempEmpty++; sideEmpty++; }
            if (sideEmpty >= 2) break;
        }
        rSide = sideEmpty;
        if (!innerEmpty) rOneEmpty = 0;

        var totalLength:Number = lTotal + rTotal + 1;
        if (totalLength < 5) return NONE;

        var noEmptySelf:Number = lNoEmpty + rNoEmpty + 1;
        var leftOneE:Number = lOneEmpty + rNoEmpty;
        var rightOneE:Number = lNoEmpty + rOneEmpty;
        var oneEmptySelf:Number = (leftOneE > rightOneE ? leftOneE : rightOneE) + 1;

        if (noEmptySelf >= 5) {
            return (rSide > 0 && lSide > 0) ? FIVE : BLOCK_FIVE;
        }
        if (noEmptySelf === 4) {
            if ((rSide >= 1 || rOneEmpty > rNoEmpty)
                && (lSide >= 1 || lOneEmpty > lNoEmpty)) {
                return FOUR;
            }
            if (!(rSide === 0 && lSide === 0)) return BLOCK_FOUR;
        }
        if (oneEmptySelf === 4) return BLOCK_FOUR;
        if (noEmptySelf === 3) {
            return ((rSide >= 2 && lSide >= 1) || (rSide >= 1 && lSide >= 2)) ? THREE : BLOCK_THREE;
        }
        if (oneEmptySelf === 3) {
            return (rSide >= 1 && lSide >= 1) ? THREE : BLOCK_THREE;
        }
        if ((noEmptySelf === 2 || oneEmptySelf === 2) && totalLength > 5) return TWO;
        return NONE;
    }
}
