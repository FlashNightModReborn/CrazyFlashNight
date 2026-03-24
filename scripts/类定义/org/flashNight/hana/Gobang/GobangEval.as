import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangEval {
    public var size:Number;
    public var board:Array;        // padded (size+2)x(size+2), border=2
    public var blackScores:Array;  // [size][size]
    public var whiteScores:Array;  // [size][size]
    public var shapeCache:Array;   // [2][4][size][size] — roleIdx, direction, x, y
    public var history:Array;      // [[position, role], ...]

    // 方向表
    private static var allDirs:Array = [[0, 1], [1, 0], [1, 1], [1, -1]];

    public function GobangEval(size:Number) {
        if (size === undefined) size = 15;
        this.size = size;
        history = [];

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
        updateSinglePoint(x, y, 1, undefined);
        updateSinglePoint(x, y, -1, undefined);

        for (var di:Number = 0; di < 4; di++) {
            var ox:Number = allDirs[di][0];
            var oy:Number = allDirs[di][1];
            for (var sign:Number = -1; sign <= 1; sign += 2) {
                var reachEdge:Boolean = false;
                for (var step:Number = 1; step <= 5; step++) {
                    for (var roleIter:Number = 0; roleIter < 2; roleIter++) {
                        var role:Number = roleIter === 0 ? 1 : -1;
                        var nx:Number = x + sign * step * ox + 1;
                        var ny:Number = y + sign * step * oy + 1;
                        if (board[nx][ny] === 2) {
                            reachEdge = true;
                            break;
                        } else if (board[nx][ny] === -role) {
                            continue;
                        } else if (board[nx][ny] === 0) {
                            var dir:Array = [sign * ox, sign * oy];
                            updateSinglePoint(nx - 1, ny - 1, role, dir);
                        }
                    }
                    if (reachEdge) break;
                }
            }
        }
    }

    private function updateSinglePoint(x:Number, y:Number, role:Number, direction):Void {
        if (board[x + 1][y + 1] !== 0) return;

        // 临时放子
        board[x + 1][y + 1] = role;

        var ri:Number = GobangConfig.roleIndex(role);
        var sc:Array = shapeCache[ri];
        var directions:Array;

        if (direction !== undefined) {
            directions = [direction];
        } else {
            directions = allDirs;
        }

        // 先清除待更新方向的缓存
        for (var ci:Number = 0; ci < directions.length; ci++) {
            var dox:Number = directions[ci][0];
            var doy:Number = directions[ci][1];
            sc[GobangShape.direction2index(dox, doy)][x][y] = GobangShape.NONE;
        }

        var score:Number = 0;
        var blockfourCount:Number = 0;
        var threeCount:Number = 0;
        var twoCount:Number = 0;

        // 先累加已有（未被清除的）方向的分值
        for (var ei:Number = 0; ei < 4; ei++) {
            var existingShape:Number = sc[ei][x][y];
            if (existingShape > GobangShape.NONE) {
                score += GobangShape.getRealShapeScore(existingShape);
                if (existingShape === GobangShape.BLOCK_FOUR) blockfourCount++;
                if (existingShape === GobangShape.THREE) threeCount++;
                if (existingShape === GobangShape.TWO) twoCount++;
            }
        }

        // 计算新方向的棋型
        for (var ni:Number = 0; ni < directions.length; ni++) {
            var nox:Number = directions[ni][0];
            var noy:Number = directions[ni][1];
            var intDir:Number = GobangShape.direction2index(nox, noy);
            var result:Array = GobangShape.getShapeFast(board, x, y, nox, noy, role);
            var shape:Number = result[0];
            if (!shape) continue;
            // 缓存单个棋型
            sc[intDir][x][y] = shape;
            if (shape === GobangShape.BLOCK_FOUR) blockfourCount++;
            if (shape === GobangShape.THREE) threeCount++;
            if (shape === GobangShape.TWO) twoCount++;
            // 检测复合棋型
            if (blockfourCount >= 2) {
                shape = GobangShape.FOUR_FOUR;
            } else if (blockfourCount && threeCount) {
                shape = GobangShape.FOUR_THREE;
            } else if (threeCount >= 2) {
                shape = GobangShape.THREE_THREE;
            } else if (twoCount >= 2) {
                shape = GobangShape.TWO_TWO;
            }
            score += GobangShape.getRealShapeScore(shape);
        }

        // 移除临时棋子
        board[x + 1][y + 1] = 0;

        if (role === 1) {
            blackScores[x][y] = score;
        } else {
            whiteScores[x][y] = score;
        }
    }

    public function evaluate(role:Number):Number {
        var blackScore:Number = 0;
        var whiteScore:Number = 0;
        for (var i:Number = 0; i < size; i++) {
            for (var j:Number = 0; j < size; j++) {
                blackScore += blackScores[i][j];
                whiteScore += whiteScores[i][j];
            }
        }
        return role === 1 ? blackScore - whiteScore : whiteScore - blackScore;
    }

    // M1 简化版 getMoves — 不含 VCT/VCF
    public function getMoves(role:Number, depth:Number):Array {
        var points:Object = getPoints(role, depth);
        return movesFromPoints(points);
    }

    private function getPoints(role:Number, depth:Number):Object {
        // 收集所有棋型的点位
        var points:Object = {};
        points.__proto__ = null;
        // 初始化每种棋型的点集
        var shapeKeys:Array = [GobangShape.FIVE, GobangShape.BLOCK_FIVE, GobangShape.FOUR,
            GobangShape.FOUR_FOUR, GobangShape.FOUR_THREE, GobangShape.THREE_THREE,
            GobangShape.BLOCK_FOUR, GobangShape.THREE, GobangShape.BLOCK_THREE,
            GobangShape.TWO_TWO, GobangShape.TWO, GobangShape.NONE];
        for (var ki:Number = 0; ki < shapeKeys.length; ki++) {
            points[shapeKeys[ki]] = {};
            points[shapeKeys[ki]].__proto__ = null;
        }

        var lastPoints:Array = [];
        var hLen:Number = history.length;
        var startIdx:Number = hLen - 4;
        if (startIdx < 0) startIdx = 0;
        for (var hi:Number = startIdx; hi < hLen; hi++) {
            lastPoints.push(history[hi][0]);
        }

        var roles:Array = [role, -role];
        for (var ri:Number = 0; ri < 2; ri++) {
            var r:Number = roles[ri];
            var rIdx:Number = GobangConfig.roleIndex(r);
            for (var i:Number = 0; i < size; i++) {
                for (var j:Number = 0; j < size; j++) {
                    if (board[i + 1][j + 1] !== 0) continue;
                    var fourCount:Number = 0;
                    var blockFourCount:Number = 0;
                    var threeCount:Number = 0;
                    for (var d:Number = 0; d < 4; d++) {
                        var shape:Number = shapeCache[rIdx][d][i][j];
                        if (!shape) continue;
                        var point:Number = i * size + j;
                        // depth > 2 时低价值棋型需在 lastPoints 连线上
                        if (depth > 2 && (shape === GobangShape.TWO || shape === GobangShape.TWO_TWO
                            || shape === GobangShape.BLOCK_THREE)) {
                            if (!hasInLine(point, lastPoints)) continue;
                        }
                        points[shape][point] = true;
                        if (shape === GobangShape.FOUR) fourCount++;
                        else if (shape === GobangShape.BLOCK_FOUR) blockFourCount++;
                        else if (shape === GobangShape.THREE) threeCount++;
                        var unionShape:Number = 0;
                        if (fourCount >= 2) unionShape = GobangShape.FOUR_FOUR;
                        else if (blockFourCount && threeCount) unionShape = GobangShape.FOUR_THREE;
                        else if (threeCount >= 2) unionShape = GobangShape.THREE_THREE;
                        if (unionShape) {
                            points[unionShape][point] = true;
                        }
                    }
                }
            }
        }
        return points;
    }

    private function hasInLine(point:Number, lastPoints:Array):Boolean {
        var px:Number = Math.floor(point / size);
        var py:Number = point % size;
        for (var i:Number = 0; i < lastPoints.length; i++) {
            var lx:Number = Math.floor(lastPoints[i] / size);
            var ly:Number = lastPoints[i] % size;
            var dx:Number = px - lx;
            var dy:Number = py - ly;
            if (dx < 0) dx = -dx;
            if (dy < 0) dy = -dy;
            if (dx === 0 || dy === 0 || dx === dy) {
                if (dx <= GobangConfig.inLineDistance && dy <= GobangConfig.inLineDistance) {
                    return true;
                }
            }
        }
        return false;
    }

    private function movesFromPoints(points:Object):Array {
        // 优先级: FIVE > FOUR > FOUR_FOUR > FOUR_THREE > THREE_THREE > BLOCK_FOUR+THREE > rest
        var fives:Object = points[GobangShape.FIVE];
        var blockFives:Object = points[GobangShape.BLOCK_FIVE];
        var fiveKeys:Array = objectKeys(fives);
        var blockFiveKeys:Array = objectKeys(blockFives);
        if (fiveKeys.length || blockFiveKeys.length) {
            return positionsToMoves(fiveKeys.concat(blockFiveKeys));
        }

        var fours:Object = points[GobangShape.FOUR];
        var blockFours:Object = points[GobangShape.BLOCK_FOUR];
        var fourKeys:Array = objectKeys(fours);
        if (fourKeys.length) {
            return positionsToMoves(fourKeys.concat(objectKeys(blockFours)));
        }

        var fourFours:Object = points[GobangShape.FOUR_FOUR];
        var ffKeys:Array = objectKeys(fourFours);
        if (ffKeys.length) {
            return positionsToMoves(ffKeys.concat(objectKeys(blockFours)));
        }

        var threes:Object = points[GobangShape.THREE];
        var fourThrees:Object = points[GobangShape.FOUR_THREE];
        var ftKeys:Array = objectKeys(fourThrees);
        if (ftKeys.length) {
            return positionsToMoves(ftKeys.concat(objectKeys(blockFours)).concat(objectKeys(threes)));
        }
        var threeThrees:Object = points[GobangShape.THREE_THREE];
        var ttKeys:Array = objectKeys(threeThrees);
        if (ttKeys.length) {
            return positionsToMoves(ttKeys.concat(objectKeys(blockFours)).concat(objectKeys(threes)));
        }

        // 没有高优先级棋型，收集剩余
        var blockThrees:Object = points[GobangShape.BLOCK_THREE];
        var twoTwos:Object = points[GobangShape.TWO_TWO];
        var twos:Object = points[GobangShape.TWO];
        var all:Array = objectKeys(blockFours).concat(objectKeys(threes))
            .concat(objectKeys(blockThrees)).concat(objectKeys(twoTwos))
            .concat(objectKeys(twos));
        // 去重
        var seen:Object = {};
        seen.__proto__ = null;
        var unique:Array = [];
        for (var i:Number = 0; i < all.length && unique.length < GobangConfig.pointsLimit; i++) {
            if (seen[all[i]] === undefined) {
                seen[all[i]] = true;
                unique.push(all[i]);
            }
        }
        return positionsToMoves(unique);
    }

    private function objectKeys(obj:Object):Array {
        var keys:Array = [];
        for (var k:String in obj) {
            keys.push(Number(k));
        }
        return keys;
    }

    private function positionsToMoves(positions:Array):Array {
        // 去重
        var seen:Object = {};
        seen.__proto__ = null;
        var moves:Array = [];
        for (var i:Number = 0; i < positions.length; i++) {
            var p:Number = positions[i];
            if (seen[p] !== undefined) continue;
            seen[p] = true;
            moves.push([Math.floor(p / size), p % size]);
        }
        return moves;
    }
}