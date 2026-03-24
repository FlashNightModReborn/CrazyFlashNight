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

    // board 是 padded board: (size+2)x(size+2), 边界值=2
    // x,y 是非 padded 坐标 (0..size-1)
    // getShapeFast 内部使用 board[x+1+offset] 索引
    // 返回 [shape, selfCount]
    private static function countShape(board:Array, x:Number, y:Number,
            offsetX:Number, offsetY:Number, role:Number):Object {
        var opponent:Number = -role;
        var innerEmptyCount:Number = 0;
        var tempEmptyCount:Number = 0;
        var selfCount:Number = 0;
        var totalLength:Number = 0;
        var sideEmptyCount:Number = 0;
        var noEmptySelfCount:Number = 0;
        var OneEmptySelfCount:Number = 0;

        for (var i:Number = 1; i <= 5; i++) {
            var nx:Number = x + i * offsetX + 1;
            var ny:Number = y + i * offsetY + 1;
            var cur:Number = board[nx][ny];
            if (cur === 2 || cur === opponent) {
                break;
            }
            if (cur === role) {
                selfCount++;
                sideEmptyCount = 0;
                if (tempEmptyCount) {
                    innerEmptyCount += tempEmptyCount;
                    tempEmptyCount = 0;
                }
                if (innerEmptyCount === 0) {
                    noEmptySelfCount++;
                    OneEmptySelfCount++;
                } else if (innerEmptyCount === 1) {
                    OneEmptySelfCount++;
                }
            }
            totalLength++;
            if (cur === 0) {
                tempEmptyCount++;
                sideEmptyCount++;
            }
            if (sideEmptyCount >= 2) {
                break;
            }
        }
        if (!innerEmptyCount) OneEmptySelfCount = 0;
        return {
            selfCount: selfCount,
            totalLength: totalLength,
            noEmptySelfCount: noEmptySelfCount,
            OneEmptySelfCount: OneEmptySelfCount,
            innerEmptyCount: innerEmptyCount,
            sideEmptyCount: sideEmptyCount
        };
    }

    // 快速棋型检测（翻译自上游 shape.js getShapeFast）
    // board: padded (size+2)x(size+2), x/y: 非padded 坐标
    // 返回 Array [shape, selfCount]
    public static function getShapeFast(board:Array, x:Number, y:Number,
            offsetX:Number, offsetY:Number, role:Number):Array {
        // 快速跳过：四个相邻位置都为空则无棋型
        if (board[x + offsetX + 1][y + offsetY + 1] === 0
            && board[x - offsetX + 1][y - offsetY + 1] === 0
            && board[x + 2 * offsetX + 1][y + 2 * offsetY + 1] === 0
            && board[x - 2 * offsetX + 1][y - 2 * offsetY + 1] === 0) {
            return [NONE, 1];
        }

        var selfCount:Number = 1;
        var totalLength:Number = 1;
        var shape:Number = NONE;
        var leftEmpty:Number = 0;
        var rightEmpty:Number = 0;
        var noEmptySelfCount:Number = 1;
        var OneEmptySelfCount:Number = 1;

        var left:Object = countShape(board, x, y, -offsetX, -offsetY, role);
        var right:Object = countShape(board, x, y, offsetX, offsetY, role);

        selfCount = left.selfCount + right.selfCount + 1;
        totalLength = left.totalLength + right.totalLength + 1;
        noEmptySelfCount = left.noEmptySelfCount + right.noEmptySelfCount + 1;
        var leftOneEmpty:Number = left.OneEmptySelfCount + right.noEmptySelfCount;
        var rightOneEmpty:Number = left.noEmptySelfCount + right.OneEmptySelfCount;
        OneEmptySelfCount = (leftOneEmpty > rightOneEmpty ? leftOneEmpty : rightOneEmpty) + 1;
        rightEmpty = right.sideEmptyCount;
        leftEmpty = left.sideEmptyCount;

        if (totalLength < 5) return [shape, selfCount];

        // five
        if (noEmptySelfCount >= 5) {
            if (rightEmpty > 0 && leftEmpty > 0) {
                return [FIVE, selfCount];
            } else {
                return [BLOCK_FIVE, selfCount];
            }
        }
        if (noEmptySelfCount === 4) {
            if ((rightEmpty >= 1 || right.OneEmptySelfCount > right.noEmptySelfCount)
                && (leftEmpty >= 1 || left.OneEmptySelfCount > left.noEmptySelfCount)) {
                return [FOUR, selfCount];
            } else if (!(rightEmpty === 0 && leftEmpty === 0)) {
                return [BLOCK_FOUR, selfCount];
            }
        }
        if (OneEmptySelfCount === 4) {
            return [BLOCK_FOUR, selfCount];
        }
        // three
        if (noEmptySelfCount === 3) {
            if ((rightEmpty >= 2 && leftEmpty >= 1) || (rightEmpty >= 1 && leftEmpty >= 2)) {
                return [THREE, selfCount];
            } else {
                return [BLOCK_THREE, selfCount];
            }
        }
        if (OneEmptySelfCount === 3) {
            if (rightEmpty >= 1 && leftEmpty >= 1) {
                return [THREE, selfCount];
            } else {
                return [BLOCK_THREE, selfCount];
            }
        }
        if ((noEmptySelfCount === 2 || OneEmptySelfCount === 2) && totalLength > 5) {
            shape = TWO;
        }

        return [shape, selfCount];
    }
}