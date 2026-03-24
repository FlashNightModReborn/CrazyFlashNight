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
        if (board[x + offsetX + 1][y + offsetY + 1] === 0
            && board[x - offsetX + 1][y - offsetY + 1] === 0
            && board[x + 2 * offsetX + 1][y + 2 * offsetY + 1] === 0
            && board[x - 2 * offsetX + 1][y - 2 * offsetY + 1] === 0) {
            return NONE;
        }

        countShape(board, x, y, -offsetX, -offsetY, role, 0); // left → _l*
        countShape(board, x, y, offsetX, offsetY, role, 1);    // right → _r*

        var totalLength:Number = _lTotal + _rTotal + 1;
        if (totalLength < 5) return NONE;

        var noEmptySelf:Number = _lNoEmpty + _rNoEmpty + 1;
        var leftOneE:Number = _lOneEmpty + _rNoEmpty;
        var rightOneE:Number = _lNoEmpty + _rOneEmpty;
        var oneEmptySelf:Number = (leftOneE > rightOneE ? leftOneE : rightOneE) + 1;

        if (noEmptySelf >= 5) {
            return (_rSide > 0 && _lSide > 0) ? FIVE : BLOCK_FIVE;
        }
        if (noEmptySelf === 4) {
            if ((_rSide >= 1 || _rOneEmpty > _rNoEmpty)
                && (_lSide >= 1 || _lOneEmpty > _lNoEmpty)) {
                return FOUR;
            }
            if (!(_rSide === 0 && _lSide === 0)) return BLOCK_FOUR;
        }
        if (oneEmptySelf === 4) return BLOCK_FOUR;
        if (noEmptySelf === 3) {
            return ((_rSide >= 2 && _lSide >= 1) || (_rSide >= 1 && _lSide >= 2)) ? THREE : BLOCK_THREE;
        }
        if (oneEmptySelf === 3) {
            return (_rSide >= 1 && _lSide >= 1) ? THREE : BLOCK_THREE;
        }
        if ((noEmptySelf === 2 || oneEmptySelf === 2) && totalLength > 5) return TWO;
        return NONE;
    }
}