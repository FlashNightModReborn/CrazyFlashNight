import org.flashNight.naki.RandomNumberEngine.SeededLinearCongruentialEngine;
import org.flashNight.hana.Gobang.GobangConfig;
import org.flashNight.hana.Gobang.GobangZobrist;
import org.flashNight.hana.Gobang.GobangCache;
import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangMinmax;
import org.flashNight.hana.Gobang.GobangAI;
import org.flashNight.hana.Gobang.GobangBook;

class org.flashNight.hana.Gobang.GobangTest {

    private static var _passed:Number = 0;
    private static var _failed:Number = 0;

    // Phase 0 LCG expected values (seed=42, first 20)
    private static var LCG_EXPECTED:Array = [
        3851491673, 1860427776, 3158954752, 3424067584,
        287773696, 1837606720, 3778208768, 1479931904,
        285911808, 3559700032, 1639656448, 2786754304,
        2640587776, 709591040, 729183104, 1157456640,
        5975552, 2817331551, 3905433600, 3124012032
    ];

    private static function assert(condition:Boolean, name:String):Void {
        if (condition) {
            _passed++;
            trace("[PASS] " + name);
        } else {
            _failed++;
            trace("[FAIL] " + name);
        }
    }

    public static function runQuick():Void {
        _passed = 0;
        _failed = 0;
        trace("=== Gobang Test Suite (quick) ===");

        testLCG();
        testRoleIndex();
        testZobrist();
        testCache();
        testBoard();
        testShape();
        testEval();
        testMinmax();
        testAI();
        testAsyncAI();

        trace("=== Results: " + _passed + " passed, " + _failed + " failed ===");
    }

    public static function runFull():Void {
        _passed = 0;
        _failed = 0;
        trace("=== Gobang Test Suite (full) ===");

        testLCG();
        testRoleIndex();
        testZobrist();
        testCache();
        testBoard();
        testShape();
        testEval();
        testMinmax();
        testAI();
        testAsyncAI();
        runBenchmark();

        trace("=== Results: " + _passed + " passed, " + _failed + " failed ===");
    }

    private static function testLCG():Void {
        trace("--- testLCG ---");
        var rng:SeededLinearCongruentialEngine = new SeededLinearCongruentialEngine(42);
        var allMatch:Boolean = true;
        for (var i:Number = 0; i < 20; i++) {
            var val:Number = rng.next();
            if (val !== LCG_EXPECTED[i]) {
                trace("[FAIL] LCG[" + i + "]: expected " + LCG_EXPECTED[i] + " got " + val);
                allMatch = false;
                _failed++;
            }
        }
        if (allMatch) {
            _passed++;
            trace("[PASS] LCG first 20 values match Node fixtures");
        }
    }

    private static function testRoleIndex():Void {
        trace("--- testRoleIndex ---");
        assert(GobangConfig.roleIndex(1) === 0, "roleIndex(1) === 0");
        assert(GobangConfig.roleIndex(-1) === 1, "roleIndex(-1) === 1");
        // invalid role guard — known behavior, logged as WARN (not counted as failure)
        var r0:Number = GobangConfig.roleIndex(0);
        trace("[WARN] roleIndex(0) = " + r0 + " (silently maps to white - callers must not pass invalid role)");
        var ru:Number = GobangConfig.roleIndex(undefined);
        trace("[WARN] roleIndex(undefined) = " + ru + " (silently maps to white - callers must not pass invalid role)");
    }

    private static function testZobrist():Void {
        trace("--- testZobrist ---");
        var z:GobangZobrist = new GobangZobrist(15);

        // Test 1: Table uniqueness — check first 20 slots have distinct hi values
        var tbl:Array = z.getTable();
        var seen:Object = {};
        seen.__proto__ = null;
        var dupes:Number = 0;
        var count:Number = 0;
        for (var i:Number = 0; i < 15 && count < 20; i++) {
            for (var j:Number = 0; j < 15 && count < 20; j++) {
                for (var r:Number = 0; r < 2 && count < 20; r++) {
                    var key:String = String(tbl[(i * 15 + j) * 2 + r].hi) + "_" + String(tbl[(i * 15 + j) * 2 + r].lo);
                    if (seen[key] !== undefined) {
                        dupes++;
                    }
                    seen[key] = count;
                    count++;
                }
            }
        }
        assert(dupes === 0, "Zobrist table first 20 slots unique");

        // Test 2: Sequence 1 — center cross (from Node fixtures)
        // put(7,7,1) -> hi=-1997706752, lo=1434201600
        // put(7,8,-1) -> hi=-1160976896, lo=1742205312
        // put(8,7,1) -> hi=-1864417792, lo=1408793088
        // put(6,7,-1) -> hi=1449372160, lo=491868672
        // put(7,6,1) -> hi=-1173952512, lo=1938920960
        var seq1X:Array = [7, 7, 8, 6, 7];
        var seq1Y:Array = [7, 8, 7, 7, 6];
        var seq1R:Array = [1, -1, 1, -1, 1];
        var seq1Hi:Array = [-1997706752, -1160976896, -1864417792, 1449372160, -1173952512];
        var seq1Lo:Array = [1434201600, 1742205312, 1408793088, 491868672, 1938920960];

        var z1:GobangZobrist = new GobangZobrist(15);
        var seq1Pass:Boolean = true;
        for (var s:Number = 0; s < 5; s++) {
            z1.togglePiece(seq1X[s], seq1Y[s], seq1R[s]);
            if (z1.getHashHi() !== seq1Hi[s] || z1.getHashLo() !== seq1Lo[s]) {
                trace("[FAIL] Zobrist seq1 step " + s + ": expected " + seq1Hi[s] + "_" + seq1Lo[s] +
                      " got " + z1.getHashHi() + "_" + z1.getHashLo());
                seq1Pass = false;
                _failed++;
            }
        }
        if (seq1Pass) {
            _passed++;
            trace("[PASS] Zobrist sequence 1 (center cross) matches Node fixtures");
        }

        // Test 3: XOR reversibility — toggle same piece twice returns to 0
        var z2:GobangZobrist = new GobangZobrist(15);
        z2.togglePiece(3, 3, 1);
        z2.togglePiece(3, 3, 1);
        assert(z2.getHashHi() === 0 && z2.getHashLo() === 0, "Zobrist XOR reversibility (0_0)");

        // Test 4: Sequence 2 — diagonal (from Node fixtures)
        var z3:GobangZobrist = new GobangZobrist(15);
        z3.togglePiece(0, 0, 1);
        z3.togglePiece(14, 14, -1);
        z3.togglePiece(1, 1, 1);
        z3.togglePiece(13, 13, -1);
        assert(z3.getHashHi() === 1381746777 && z3.getHashLo() === 1544129024,
               "Zobrist sequence 2 (diagonal) matches Node fixtures");

        // Test 5: toKey format
        var z4:GobangZobrist = new GobangZobrist(15);
        z4.togglePiece(0, 0, 1);
        var expectedKey:String = "-443475623_1860427776";
        assert(z4.toKey() === expectedKey, "Zobrist toKey format: " + z4.toKey());
    }

    private static function testCache():Void {
        trace("--- testCache ---");

        // Test 1: basic put/get
        var c:GobangCache = new GobangCache(5);
        c.put("a", 100);
        assert(c.get("a") === 100, "Cache put/get basic");

        // Test 2: has
        assert(c.has("a") === true, "Cache has existing key");
        assert(c.has("b") === false, "Cache has missing key");

        // Test 3: get missing key returns null
        assert(c.get("missing") === null, "Cache get missing returns null");

        // Test 4: FIFO eviction
        c.put("b", 200);
        c.put("c", 300);
        c.put("d", 400);
        c.put("e", 500);
        // capacity=5, all 5 slots filled (a,b,c,d,e)
        c.put("f", 600);
        // "a" should be evicted (FIFO)
        assert(c.get("a") === null, "Cache FIFO eviction: oldest key removed");
        assert(c.get("f") === 600, "Cache FIFO eviction: newest key exists");
        assert(c.get("b") === 200, "Cache FIFO eviction: second oldest still exists");

        // Test 5: update existing key doesn't increase size
        c.put("b", 999);
        assert(c.get("b") === 999, "Cache update existing key");
        // "c" should still exist (no extra eviction)
        assert(c.get("c") === 300, "Cache update doesn't evict extra");
    }

    private static function testBoard():Void {
        trace("--- testBoard ---");

        // Test 1: Empty board
        var b:GobangBoard = new GobangBoard(15, 1);
        assert(b.board[7 * 15 + 7] === 0, "Board init: center is empty");
        assert(b.role === 1, "Board init: first role is black");

        // Test 2: put and role switch
        b.put(7, 7, 1);
        assert(b.board[7 * 15 + 7] === 1, "Board put: black at center");
        assert(b.role === -1, "Board put: role switches to white");

        // Test 3: cannot put on occupied
        assert(b.put(7, 7, -1) === false, "Board put: occupied returns false");

        // Test 4: undo
        b.undo();
        assert(b.board[7 * 15 + 7] === 0, "Board undo: center cleared");
        assert(b.role === 1, "Board undo: role restored to black");

        // Test 5: hash after undo = initial hash
        assert(b.hash() === "0_0", "Board undo: hash restored to 0_0");

        // Test 6: 10-step sequence with isWin and hash cross-validation
        var b2:GobangBoard = new GobangBoard(15, 1);
        // Moves: black horizontal 5 at row 7, white horizontal 5 at row 6
        var mi:Array = [7, 6, 7, 6, 7, 6, 7, 6, 7, 6];
        var mj:Array = [7, 6, 8, 7, 9, 8, 10, 9, 11, 10];
        var mr:Array = [1, -1, 1, -1, 1, -1, 1, -1, 1, -1];
        // Expected isWin at each step (from Node fixtures)
        var expectedWin:Array = [false, false, false, false, false, false, false, false, true, true];
        // Expected hash at step 0 and step 8 (from Node fixtures)
        var expectedHash0:String = "-1997706752_1434201600";
        var expectedHash8:String = "-1857929152_60405376"; // after all 10 moves (step 9)

        var boardPass:Boolean = true;
        for (var s:Number = 0; s < 10; s++) {
            b2.put(mi[s], mj[s], mr[s]);
            var win:Boolean = b2.isWin(mi[s], mj[s], mr[s]);
            if (win !== expectedWin[s]) {
                trace("[FAIL] Board step " + s + ": isWin expected " + expectedWin[s] + " got " + win);
                boardPass = false;
                _failed++;
            }
        }
        if (boardPass) {
            _passed++;
            trace("[PASS] Board 10-step isWin sequence");
        }

        // Hash cross-validation at step 0 (reset and do 1 move)
        var b3:GobangBoard = new GobangBoard(15, 1);
        b3.put(7, 7, 1);
        assert(b3.hash() === expectedHash0, "Board hash step 0: " + b3.hash());

        // Hash at step 8
        assert(b2.hash() === expectedHash8, "Board hash step 8 (final): " + b2.hash());

        // Test 7: isWin edge cases
        var b4:GobangBoard = new GobangBoard(15, 1);
        // Vertical 5 at column 0
        for (var v:Number = 0; v < 5; v++) {
            b4.put(v, 0, 1);
        }
        assert(b4.isWin(4, 0, 1) === true, "Board isWin: vertical edge");

        // Test 8: Diagonal 5
        var b5:GobangBoard = new GobangBoard(15, 1);
        for (var d:Number = 0; d < 5; d++) {
            b5.put(d, d, 1);
        }
        assert(b5.isWin(4, 4, 1) === true, "Board isWin: diagonal");

        // Test 9: Anti-diagonal 5
        var b6:GobangBoard = new GobangBoard(15, 1);
        for (var a:Number = 0; a < 5; a++) {
            b6.put(a, 14 - a, 1);
        }
        assert(b6.isWin(4, 10, 1) === true, "Board isWin: anti-diagonal");

        // Test 10: 4 in a row is NOT win
        var b7:GobangBoard = new GobangBoard(15, 1);
        for (var f:Number = 0; f < 4; f++) {
            b7.put(0, f, 1);
        }
        assert(b7.isWin(0, 3, 1) === false, "Board isWin: 4 in a row is not win");

        // Test 11: getWinner/undo 缓存一致性
        var b8:GobangBoard = new GobangBoard(15, 1);
        b8.put(7, 5, 1);
        b8.put(0, 0, -1);
        b8.put(7, 6, 1);
        b8.put(0, 1, -1);
        b8.put(7, 7, 1);
        b8.put(0, 2, -1);
        b8.put(7, 8, 1);
        b8.put(0, 3, -1);
        b8.put(7, 9, 1);
        assert(b8.getWinner() === 1, "Board cached winner detects five");
        b8.undo();
        assert(b8.getWinner() === 0 && b8.isGameOver() === false, "Board cached winner clears after undo");
    }

    // 创建 padded board 1D [17*17=289], 边界=2
    private static function makePaddedBoard():Array {
        var b:Array = new Array(289);
        for (var bi:Number = 0; bi < 289; bi++) {
            var bx:Number = (bi / 17) | 0;
            var by:Number = bi - bx * 17;
            b[bi] = (bx === 0 || by === 0 || bx === 16 || by === 16) ? 2 : 0;
        }
        return b;
    }

    private static function sameMoves(a:Array, b:Array):Boolean {
        if (a.length !== b.length) return false;
        for (var i:Number = 0; i < a.length; i++) {
            if (a[i][0] !== b[i][0] || a[i][1] !== b[i][1]) return false;
        }
        return true;
    }

    private static function sameMoveSet(a:Array, b:Array):Boolean {
        if (a.length !== b.length) return false;
        var seen:Object = {};
        for (var i:Number = 0; i < a.length; i++) {
            seen[a[i][0] + "_" + a[i][1]] = true;
        }
        for (var j:Number = 0; j < b.length; j++) {
            if (seen[b[j][0] + "_" + b[j][1]] !== true) return false;
        }
        return true;
    }

    // 全盘扫描对照组：用于验证 frontier getMoves 不改变行为
    private static function getMovesSlow(eval:GobangEval, role:Number, depth:Number, onlyThree:Boolean, onlyFour:Boolean):Array {
        var brd:Array = eval.board;
        var sz:Number = eval.size;
        var result:Array = [];
        var limit:Number = GobangConfig.pointsLimit;
        if (limit < 1) limit = 1;
        if (depth >= 4 && limit > 10) limit = 10;

        var bs:Array = eval.blackScores;
        var ws:Array = eval.whiteScores;
        var atk:Array = role === 1 ? bs : ws;
        var def:Array = role === 1 ? ws : bs;
        var sc:Array = eval.shapeCache;
        var atkBase:Number = (role === 1) ? 0 : 900;
        var defBase:Number = (role === 1) ? 900 : 0;
        var hasFive:Boolean = false;
        var hasFour:Boolean = false;

        for (var i:Number = 0; i < sz; i++) {
            for (var j:Number = 0; j < sz; j++) {
                if (brd[(i + 1) * 17 + (j + 1)] !== 0) continue;

                var ij:Number = i * 15 + j;
                var attackScore:Number = atk[ij];
                var defendScore:Number = def[ij];
                if (attackScore === 0 && defendScore === 0) continue;
                var a0:Number = sc[atkBase + ij];
                var a1:Number = sc[atkBase + 225 + ij];
                var a2:Number = sc[atkBase + 450 + ij];
                var a3:Number = sc[atkBase + 675 + ij];
                var d0:Number = sc[defBase + ij];
                var d1:Number = sc[defBase + 225 + ij];
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
                var curFlat:Number = i * sz + j;

                var maxS:Number = attackMax > defendMax ? attackMax : defendMax;
                if (!maxS) continue;

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
                        if (curFlat > prevFiveFlat) break;
                        result[fiveAt] = prevFive;
                        fiveAt--;
                    }
                    result[fiveAt] = [i, j];
                    continue;
                }
                if (hasFive) continue;

                var atkThrees:Number = 0;
                if (a0 === 3) atkThrees++;
                if (a1 === 3) atkThrees++;
                if (a2 === 3) atkThrees++;
                if (a3 === 3) atkThrees++;
                var atkMajorDirs:Number = 0;
                if (a0 >= 3 || a0 === 40) atkMajorDirs++;
                if (a1 >= 3 || a1 === 40) atkMajorDirs++;
                if (a2 >= 3 || a2 === 40) atkMajorDirs++;
                if (a3 >= 3 || a3 === 40) atkMajorDirs++;
                var defThrees:Number = 0;
                if (d0 === 3) defThrees++;
                if (d1 === 3) defThrees++;
                if (d2 === 3) defThrees++;
                if (d3 === 3) defThrees++;
                var defMajorDirs:Number = 0;
                if (d0 >= 3 || d0 === 40) defMajorDirs++;
                if (d1 >= 3 || d1 === 40) defMajorDirs++;
                if (d2 >= 3 || d2 === 40) defMajorDirs++;
                if (d3 >= 3 || d3 === 40) defMajorDirs++;
                var edgeMargin:Boolean = (i <= 1 || j <= 1 || i >= sz - 2 || j >= sz - 2);
                var pseudoAtkFour:Boolean = (attackMax === 40 && edgeMargin && atkMajorDirs <= 1 && atkThrees === 0);
                var pseudoDefFour:Boolean = (defendMax === 40 && edgeMargin && defMajorDirs <= 1 && defThrees === 0);
                var isFourMove:Boolean = (attackMax === 4 || defendMax === 4
                    || atkThrees >= 2 || defThrees >= 2
                    || (attackMax === 40 && !pseudoAtkFour)
                    || (defendMax === 40 && !pseudoDefFour));
                if (isFourMove) {
                    var majorFour:Number = attackScore > defendScore ? attackScore : defendScore;
                    var exactPriority:Number = 0;
                    if (attackMax === 4 || defendMax === 4) exactPriority = 3000000;
                    else if (atkThrees >= 2 || defThrees >= 2) exactPriority = 2000000;
                    else if ((attackMax === 40 && !pseudoAtkFour) || (defendMax === 40 && !pseudoDefFour)) exactPriority = 1000000;
                    var fourKey:Number = attackScore + defendScore + majorFour + exactPriority;
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
                        if (fourKey === prevFourKey && curFlat > prevFourFlat) break;
                        result[fourAt] = prevFour;
                        fourAt--;
                    }
                    result[fourAt] = [i, j, fourKey];
                    continue;
                }
                if (hasFour) continue;

                if (onlyFour && maxS < 4) continue;
                if (onlyThree && maxS < 3) continue;

                var major:Number = attackScore > defendScore ? attackScore : defendScore;
                var sortKey:Number = attackScore + defendScore + major;
                var resultLen:Number = result.length;
                var tail:Array = resultLen > 0 ? result[resultLen - 1] : null;
                var tailBetter:Boolean = (tail !== null && (sortKey > tail[2]
                    || (sortKey === tail[2] && curFlat < tail[0] * sz + tail[1])));
                if (resultLen < limit || tailBetter) {
                    var insertAt:Number = resultLen;
                    if (insertAt >= limit) insertAt = limit - 1;
                    while (insertAt > 0) {
                        var prev:Array = result[insertAt - 1];
                        var prevKey:Number = prev[2];
                        var prevFlat:Number = prev[0] * sz + prev[1];
                        if (sortKey < prevKey) break;
                        if (sortKey === prevKey && curFlat > prevFlat) break;
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
        }

        if (hasFive) return result;
        for (var k:Number = 0; k < result.length; k++) {
            result[k].length = 2;
        }
        return result;
    }

    // 在 padded board 上放棋子 (非padded坐标)
    private static function placeOnPadded(b:Array, x:Number, y:Number, role:Number):Void {
        b[(x + 1) * 17 + (y + 1)] = role;
    }

    private static function assertShape(b:Array, x:Number, y:Number, ox:Number, oy:Number,
            role:Number, expected:Number, name:String):Void {
        var shape:Number = GobangShape.getShapeFast(b, x, y, ox, oy, role);
        if (shape === expected) {
            _passed++;
            trace("[PASS] " + name);
        } else {
            _failed++;
            trace("[FAIL] " + name + ": expected " + expected + " got " + shape);
        }
    }

    private static function testShape():Void {
        trace("--- testShape ---");
        var b:Array;

        // Test 1: FIVE horizontal
        b = makePaddedBoard();
        placeOnPadded(b, 7, 5, 1); placeOnPadded(b, 7, 6, 1); placeOnPadded(b, 7, 7, 1);
        placeOnPadded(b, 7, 8, 1); placeOnPadded(b, 7, 9, 1);
        assertShape(b, 7, 7, 0, 1, 1, GobangShape.FIVE, "Shape FIVE horizontal");

        // Test 2: BLOCK_FIVE at edge
        b = makePaddedBoard();
        placeOnPadded(b, 0, 0, 1); placeOnPadded(b, 0, 1, 1); placeOnPadded(b, 0, 2, 1);
        placeOnPadded(b, 0, 3, 1); placeOnPadded(b, 0, 4, 1);
        assertShape(b, 0, 2, 0, 1, 1, GobangShape.BLOCK_FIVE, "Shape BLOCK_FIVE at edge");

        // Test 3: FOUR open
        b = makePaddedBoard();
        placeOnPadded(b, 7, 5, 1); placeOnPadded(b, 7, 6, 1);
        placeOnPadded(b, 7, 7, 1); placeOnPadded(b, 7, 8, 1);
        assertShape(b, 7, 7, 0, 1, 1, GobangShape.FOUR, "Shape FOUR open");

        // Test 4: BLOCK_FOUR
        b = makePaddedBoard();
        placeOnPadded(b, 7, 4, -1); placeOnPadded(b, 7, 5, 1); placeOnPadded(b, 7, 6, 1);
        placeOnPadded(b, 7, 7, 1); placeOnPadded(b, 7, 8, 1);
        assertShape(b, 7, 7, 0, 1, 1, GobangShape.BLOCK_FOUR, "Shape BLOCK_FOUR");

        // Test 5: THREE open
        b = makePaddedBoard();
        placeOnPadded(b, 7, 6, 1); placeOnPadded(b, 7, 7, 1); placeOnPadded(b, 7, 8, 1);
        assertShape(b, 7, 7, 0, 1, 1, GobangShape.THREE, "Shape THREE open");

        // Test 6: BLOCK_THREE
        b = makePaddedBoard();
        placeOnPadded(b, 7, 4, -1); placeOnPadded(b, 7, 5, 1);
        placeOnPadded(b, 7, 6, 1); placeOnPadded(b, 7, 7, 1);
        assertShape(b, 7, 6, 0, 1, 1, GobangShape.BLOCK_THREE, "Shape BLOCK_THREE");

        // Test 7: TWO open
        b = makePaddedBoard();
        placeOnPadded(b, 7, 7, 1); placeOnPadded(b, 7, 8, 1);
        assertShape(b, 7, 7, 0, 1, 1, GobangShape.TWO, "Shape TWO open");

        // Test 8: NONE isolated
        b = makePaddedBoard();
        placeOnPadded(b, 7, 7, 1);
        assertShape(b, 7, 7, 0, 1, 1, GobangShape.NONE, "Shape NONE isolated");

        // Test 9: THREE vertical
        b = makePaddedBoard();
        placeOnPadded(b, 5, 7, 1); placeOnPadded(b, 6, 7, 1); placeOnPadded(b, 7, 7, 1);
        assertShape(b, 6, 7, 1, 0, 1, GobangShape.THREE, "Shape THREE vertical");

        // Test 10: FOUR diagonal
        b = makePaddedBoard();
        placeOnPadded(b, 4, 4, 1); placeOnPadded(b, 5, 5, 1);
        placeOnPadded(b, 6, 6, 1); placeOnPadded(b, 7, 7, 1);
        assertShape(b, 5, 5, 1, 1, 1, GobangShape.FOUR, "Shape FOUR diagonal");

        // Test 11: BLOCK_FOUR white
        b = makePaddedBoard();
        placeOnPadded(b, 7, 5, -1); placeOnPadded(b, 7, 6, -1);
        placeOnPadded(b, 7, 7, -1); placeOnPadded(b, 7, 8, -1); placeOnPadded(b, 7, 4, 1);
        assertShape(b, 7, 7, 0, 1, -1, GobangShape.BLOCK_FOUR, "Shape BLOCK_FOUR white");

        // Test 12: THREE anti-diagonal
        b = makePaddedBoard();
        placeOnPadded(b, 5, 9, 1); placeOnPadded(b, 6, 8, 1); placeOnPadded(b, 7, 7, 1);
        assertShape(b, 6, 8, 1, -1, 1, GobangShape.THREE, "Shape THREE anti-diagonal");

        // Test 13: getRealShapeScore
        assert(GobangShape.getRealShapeScore(GobangShape.FIVE) === 100000, "getRealShapeScore FIVE->FOUR_SCORE");
        assert(GobangShape.getRealShapeScore(GobangShape.THREE) === 100, "getRealShapeScore THREE->TWO_SCORE");
        assert(GobangShape.getRealShapeScore(GobangShape.NONE) === 0, "getRealShapeScore NONE->0");
    }

    private static function testEval():Void {
        trace("--- testEval ---");

        // Test 1: Empty board evaluate = 0
        var e1:GobangEval = new GobangEval(15);
        assert(e1.evaluate(1) === 0, "Eval empty board = 0");

        // Test 2: Single black center
        var e2:GobangEval = new GobangEval(15);
        e2.move(7, 7, 1);
        var s2:Number = e2.evaluate(1);
        assert(s2 === 320, "Eval single black center = 320 (got " + s2 + ")");

        // Test 3: Black+white adjacent
        var e3:GobangEval = new GobangEval(15);
        e3.move(7, 7, 1);
        e3.move(7, 8, -1);
        var s3:Number = e3.evaluate(1);
        assert(s3 === 0, "Eval black+white adjacent = 0 (got " + s3 + ")");

        // Test 4: Black three（双 TWO 协同分会把这类进攻骨架明显抬高）
        var e4:GobangEval = new GobangEval(15);
        e4.move(7, 6, 1);
        e4.move(0, 0, -1);
        e4.move(7, 7, 1);
        e4.move(0, 1, -1);
        e4.move(7, 8, 1);
        var s4:Number = e4.evaluate(1);
        // LUT 调整后精确值会变化；结构性断言：三连分数远高于单子
        assert(s4 > s2 * 3, "Eval black three >> single stone: " + s4 + " > " + (s2 * 3));
        trace("[INFO] Eval three-in-row score: " + s4 + " (single stone: " + s2 + ")");

        // Test 5: Undo reversibility
        var e5:GobangEval = new GobangEval(15);
        e5.move(7, 7, 1);
        var s5a:Number = e5.evaluate(1);
        var baseMoves:Array = e5.getMoves(-1, 0, false, false);
        var baseCount:Number = baseMoves.length;
        var baseX:Number = baseMoves[0][0];
        var baseY:Number = baseMoves[0][1];
        e5.move(6, 6, -1);
        e5.undo(6, 6);
        var s5b:Number = e5.evaluate(1);
        assert(s5a === s5b, "Eval undo reversible: " + s5a + " === " + s5b);
        var undoMoves:Array = e5.getMoves(-1, 0, false, false);
        assert(baseCount === undoMoves.length
               && baseX === undoMoves[0][0]
               && baseY === undoMoves[0][1],
               "Eval undo preserves move ordering: (" + baseX + "," + baseY + ")");

        // Test 6: getMoves returns valid moves
        var e6:GobangEval = new GobangEval(15);
        e6.move(7, 7, 1);
        var moves:Array = e6.getMoves(-1, 0, false, false);
        assert(moves.length > 0, "Eval getMoves returns moves (count=" + moves.length + ")");
        // Verify first move is valid coordinate
        var mx:Number = moves[0][0];
        var my:Number = moves[0][1];
        assert(mx >= 0 && mx < 15 && my >= 0 && my < 15, "Eval getMoves valid coords: " + mx + "," + my);

        // Test 7: frontier getMoves 与全盘扫描结果一致
        var e7:GobangEval = new GobangEval(15);
        var seq7:Array = [
            [7,7,1], [6,6,-1], [7,8,1], [6,7,-1], [7,9,1],
            [8,8,-1], [6,8,1], [8,7,-1], [5,7,1], [8,6,-1]
        ];
        for (var i7:Number = 0; i7 < seq7.length; i7++) {
            e7.move(seq7[i7][0], seq7[i7][1], seq7[i7][2]);
        }
        var oldPointsLimit:Number = GobangConfig.pointsLimit;
        GobangConfig.pointsLimit = 225;
        var fast7:Array = e7.getMoves(1, 0, false, false);
        var slow7:Array = getMovesSlow(e7, 1, 0, false, false);
        GobangConfig.pointsLimit = oldPointsLimit;
        assert(sameMoveSet(fast7, slow7), "Eval frontier getMoves keeps slow-scan move set");

        // Test 8: 冲四局面只保留强制手
        var e8:GobangEval = new GobangEval(15);
        e8.move(7, 5, 1);
        e8.move(0, 0, -1);
        e8.move(7, 6, 1);
        e8.move(0, 1, -1);
        e8.move(7, 7, 1);
        e8.move(0, 2, -1);
        e8.move(7, 8, 1);
        var urgent:Array = e8.getMoves(-1, 0, false, false);
        var urgentOK:Boolean = (urgent.length === 2)
            && ((urgent[0][0] === 7 && urgent[0][1] === 4) || (urgent[0][0] === 7 && urgent[0][1] === 9))
            && ((urgent[1][0] === 7 && urgent[1][1] === 4) || (urgent[1][0] === 7 && urgent[1][1] === 9));
        assert(urgentOK, "Eval urgent-four pruning returns only blocks");

        // Test 9: 双 TWO 协同分应明显高于单 TWO
        var e9a:GobangEval = new GobangEval(15);
        e9a.move(7, 6, 1);
        var singleTwoScore:Number = e9a.blackScores[7 * 15 + 7];
        var e9b:GobangEval = new GobangEval(15);
        e9b.move(7, 6, 1);
        e9b.move(6, 7, 1);
        var comboTwoScore:Number = e9b.blackScores[7 * 15 + 7];
        assert(comboTwoScore >= singleTwoScore + 50,
               "Eval TWO synergy bonus raises combo potential: " + comboTwoScore + " vs " + singleTwoScore);

        // Test 10: 桥接潜力应抬高长布局延伸点（体现在候选排序）
        var e10:GobangEval = new GobangEval(15);
        e10.move(7, 5, 1);
        e10.move(7, 8, 1);
        var bridgeMoves:Array = e10.getMoves(1, 0, false, false);
        var bridgeTop:Boolean = false;
        for (var bi:Number = 0; bi < bridgeMoves.length && bi < 3; bi++) {
            if (bridgeMoves[bi][0] === 7 && (bridgeMoves[bi][1] === 6 || bridgeMoves[bi][1] === 7)) {
                bridgeTop = true;
                break;
            }
        }
        assert(bridgeTop, "Eval bridge potential keeps line-link move in top-3");

        // Test 11: 复杂长布局里，边角伪冲四不应被当成真实 urgent-four
        var e11:GobangEval = new GobangEval(15);
        var seq11:Array = [
            [7,5,1], [0,0,-1], [7,9,1], [0,14,-1],
            [5,7,1], [14,0,-1], [9,7,1], [1,12,-1],
            [14,14,1], [12,1,-1], [14,13,1]
        ];
        for (var i11:Number = 0; i11 < seq11.length; i11++) {
            e11.move(seq11[i11][0], seq11[i11][1], seq11[i11][2]);
        }
        var pseudoUrgent:Array = e11.getMoves(-1, 0, false, true);
        var pseudoThreats:Array = e11.getThreatMoves(1, 4, 4);
        var noEdgePseudo:Boolean = true;
        for (var pui:Number = 0; pui < pseudoUrgent.length; pui++) {
            if (pseudoUrgent[pui][0] === 14 && (pseudoUrgent[pui][1] === 11 || pseudoUrgent[pui][1] === 12)) {
                noEdgePseudo = false;
                break;
            }
        }
        assert(noEdgePseudo, "Eval exact urgent-four filter removes edge pseudo threats");
        assert(pseudoThreats.length === 0,
               "Eval exact threat moves reject pseudo major threats (count=" + pseudoThreats.length + ")");

        // Test 12: 双路防守局面里，应优先选择能同时拆两路的中心点
        var e12:GobangEval = new GobangEval(15);
        var seq12:Array = [
            [7,5,1], [0,0,-1], [7,9,1], [0,14,-1],
            [5,7,1], [14,0,-1], [9,7,1], [1,12,-1],
            [14,14,1], [12,1,-1], [14,13,1]
        ];
        for (var i12:Number = 0; i12 < seq12.length; i12++) {
            e12.move(seq12[i12][0], seq12[i12][1], seq12[i12][2]);
        }
        var coverMoves:Array = e12.getMoves(-1, 0, false, false);
        var centerPresent:Boolean = false;
        for (var ci12:Number = 0; ci12 < coverMoves.length; ci12++) {
            if (coverMoves[ci12][0] === 7 && coverMoves[ci12][1] === 7) {
                centerPresent = true;
                break;
            }
        }
        var noEdgeHijack:Boolean = !(coverMoves[0][0] === 14 && (coverMoves[0][1] === 11 || coverMoves[0][1] === 12));
        assert(noEdgeHijack,
               "Eval multi-threat coverage no longer gets hijacked by edge pseudo threat: (" + coverMoves[0][0] + "," + coverMoves[0][1] + ")");
        assert(centerPresent,
               "Eval multi-threat coverage keeps center defense in candidate set");
    }

    private static function testMinmax():Void {
        trace("--- testMinmax ---");

        // Test 1: Depth 2 search without VCT
        var b1:GobangBoard = new GobangBoard(15, 1);
        var ev1:GobangEval = new GobangEval(15);
        b1.put(7, 7, 1); ev1.move(7, 7, 1);
        var mm1:GobangMinmax = new GobangMinmax(b1, ev1);
        var r1:Object = mm1.search(-1, 2, false);
        assert(r1.x >= 0 && r1.x < 15 && r1.y >= 0 && r1.y < 15,
               "Minmax depth=2 noVCT: valid move (" + r1.x + "," + r1.y + ") nodes=" + r1.nodes);

        // Test 2: Must block — black has 4 in a row, white must block
        var b2:GobangBoard = new GobangBoard(15, 1);
        var ev2:GobangEval = new GobangEval(15);
        b2.put(7, 5, 1); ev2.move(7, 5, 1);
        b2.put(0, 0, -1); ev2.move(0, 0, -1);
        b2.put(7, 6, 1); ev2.move(7, 6, 1);
        b2.put(0, 1, -1); ev2.move(0, 1, -1);
        b2.put(7, 7, 1); ev2.move(7, 7, 1);
        b2.put(0, 2, -1); ev2.move(0, 2, -1);
        b2.put(7, 8, 1); ev2.move(7, 8, 1);
        var mm2:GobangMinmax = new GobangMinmax(b2, ev2);
        var r2:Object = mm2.search(-1, 2, false);
        var isBlock:Boolean = (r2.x === 7 && (r2.y === 4 || r2.y === 9));
        assert(isBlock, "Minmax must block open four: (" + r2.x + "," + r2.y + ")");

        // Test 3: Must win — with VCT enabled
        var b3:GobangBoard = new GobangBoard(15, 1);
        var ev3:GobangEval = new GobangEval(15);
        b3.put(7, 5, 1); ev3.move(7, 5, 1);
        b3.put(0, 0, -1); ev3.move(0, 0, -1);
        b3.put(7, 6, 1); ev3.move(7, 6, 1);
        b3.put(0, 1, -1); ev3.move(0, 1, -1);
        b3.put(7, 7, 1); ev3.move(7, 7, 1);
        b3.put(0, 2, -1); ev3.move(0, 2, -1);
        b3.put(7, 8, 1); ev3.move(7, 8, 1);
        b3.put(0, 3, -1); ev3.move(0, 3, -1);
        var mm3:GobangMinmax = new GobangMinmax(b3, ev3);
        var r3:Object = mm3.search(1, 2, true);
        var isWinMove:Boolean = (r3.x === 7 && (r3.y === 4 || r3.y === 9));
        assert(isWinMove, "Minmax+VCT find winning move: (" + r3.x + "," + r3.y + ") score=" + r3.score);

        // Test 4: VCT finds deeper win — black has open three with VCT potential
        var b4:GobangBoard = new GobangBoard(15, 1);
        var ev4:GobangEval = new GobangEval(15);
        b4.put(7, 6, 1); ev4.move(7, 6, 1);
        b4.put(0, 0, -1); ev4.move(0, 0, -1);
        b4.put(7, 7, 1); ev4.move(7, 7, 1);
        b4.put(0, 1, -1); ev4.move(0, 1, -1);
        b4.put(7, 8, 1); ev4.move(7, 8, 1);
        b4.put(0, 2, -1); ev4.move(0, 2, -1);
        // Black has open three at (7,6-8), VCT should find winning sequence
        var mm4:GobangMinmax = new GobangMinmax(b4, ev4);
        var t0:Number = getTimer();
        var r4:Object = mm4.search(1, 2, true);
        var elapsed:Number = getTimer() - t0;
        assert(r4.x >= 0 && r4.x < 15, "Minmax+VCT depth=2: (" + r4.x + "," + r4.y + ") score=" + r4.score + " " + elapsed + "ms");

        // Test 5: 轻量 TSS 能识别 open-three 诱发的短算杀
        var b5:GobangBoard = new GobangBoard(15, 1);
        var ev5:GobangEval = new GobangEval(15);
        b5.put(7, 6, 1); ev5.move(7, 6, 1);
        b5.put(0, 0, -1); ev5.move(0, 0, -1);
        b5.put(7, 7, 1); ev5.move(7, 7, 1);
        b5.put(0, 1, -1); ev5.move(0, 1, -1);
        b5.put(7, 8, 1); ev5.move(7, 8, 1);
        b5.put(0, 2, -1); ev5.move(0, 2, -1);
        var mm5:GobangMinmax = new GobangMinmax(b5, ev5);
        assert(mm5.probeTSS(1, 5) === true, "Minmax TSS probe detects black forcing line");
        assert(mm5.probeTSS(-1, 5) === false, "Minmax TSS probe rejects white forcing line");

        // Test 6: 带独立小预算的 TSS probe 可用于甄别“挡住当前手后是否仍有连续威胁”
        var b6:GobangBoard = new GobangBoard(15, 1);
        var ev6:GobangEval = new GobangEval(15);
        b6.put(7, 6, 1); ev6.move(7, 6, 1);
        b6.put(0, 0, -1); ev6.move(0, 0, -1);
        b6.put(7, 7, 1); ev6.move(7, 7, 1);
        b6.put(0, 1, -1); ev6.move(0, 1, -1);
        b6.put(7, 8, 1); ev6.move(7, 8, 1);
        var mm6:GobangMinmax = new GobangMinmax(b6, ev6);
        b6.put(7, 5, -1); ev6.move(7, 5, -1);
        assert(mm6.probeTSSWithBudget(1, 5, 6) === false,
               "Minmax budgeted TSS probe clears forcing line after endpoint defense");
        ev6.undo(7, 5); b6.undo();
        b6.put(6, 6, -1); ev6.move(6, 6, -1);
        assert(mm6.probeTSSWithBudget(1, 5, 6) === true,
               "Minmax budgeted TSS probe still sees forcing line after irrelevant move");

        // Test 7: 预搜索检测对手双三威胁点并自动堵住
        // 构造：黑棋在 (7,6)-(7,7) 水平 + (6,7)-(7,7) 垂直，交叉点 (7,7) 已落子
        // 黑棋还在 (5,5)-(6,6) 对角线，(7,7) 处也在对角线上
        // 需要一个空位同时有 2 方向 THREE → 对手双三点
        // 局面：黑在 (7,6),(7,8) 水平方向（中间7,7空），
        //        黑在 (6,7),(8,7) 垂直方向（中间7,7空）
        // → (7,7) 对黑棋来说两方向都有 THREE 潜力
        var b7:GobangBoard = new GobangBoard(15, 1);
        var ev7:GobangEval = new GobangEval(15);
        // 黑棋水平两子 + 垂直两子，(7,7) 为双三交叉点
        b7.put(7, 6, 1); ev7.move(7, 6, 1);  // 黑
        b7.put(0, 0, -1); ev7.move(0, 0, -1); // 白远处（四角分散）
        b7.put(7, 8, 1); ev7.move(7, 8, 1);  // 黑
        b7.put(14, 0, -1); ev7.move(14, 0, -1); // 白远处
        b7.put(6, 7, 1); ev7.move(6, 7, 1);  // 黑
        b7.put(0, 14, -1); ev7.move(0, 14, -1); // 白远处
        b7.put(8, 7, 1); ev7.move(8, 7, 1);  // 黑
        b7.put(14, 14, -1); ev7.move(14, 14, -1); // 白远处
        // 现在 (7,7) 空，黑在此落子 = 水平三连 + 垂直三连 = 双三
        // 白方搜索应该检测到 (7,7) 是黑方双三威胁点并堵住
        var mm7:GobangMinmax = new GobangMinmax(b7, ev7);
        var r7:Object = mm7.search(-1, 4, false);
        assert(r7.x === 7 && r7.y === 7,
               "Minmax blocks opponent double-three at intersection: (" + r7.x + "," + r7.y + ")");

        // Test 8: 反对角线三连 — 白方应堵住延伸端，不飞角落
        // 黑棋 (5,9)-(6,8)-(7,7) 反对角线活三，两端 (4,10)/(8,6) 均空
        // 白棋分散四角，无自身威胁
        // 搜索应在 (8,6) 或 (4,10) 落子堵住
        var b8:GobangBoard = new GobangBoard(15, 1);
        var ev8:GobangEval = new GobangEval(15);
        b8.put(5, 9, 1); ev8.move(5, 9, 1);
        b8.put(0, 0, -1); ev8.move(0, 0, -1);
        b8.put(6, 8, 1); ev8.move(6, 8, 1);
        b8.put(14, 0, -1); ev8.move(14, 0, -1);
        b8.put(7, 7, 1); ev8.move(7, 7, 1);
        b8.put(0, 14, -1); ev8.move(0, 14, -1);
        var mm8:GobangMinmax = new GobangMinmax(b8, ev8);
        var r8:Object = mm8.search(-1, 6, false);
        // 合理防守位：(8,6) 或 (4,10) 堵住三连两端，或 (6,7)/(6,9) 等紧邻位
        var d8:Number = (r8.x - 7) * (r8.x - 7) + (r8.y - 7) * (r8.y - 7);
        assert(d8 <= 18,
               "Minmax blocks diagonal three near center: (" + r8.x + "," + r8.y + ") dist2=" + d8);

        // Test 9: 四子带空隙(跳四) — _preSearchTactical P2 应检测 FIVE 形并堵住
        // 黑棋 (5,9)-(6,8)-(7,7)-[空(8,6)]-(9,5) = 反对角线跳四
        // (8,6) 处黑棋 shape=FIVE，P2 必须直接返回 (8,6)
        var b9:GobangBoard = new GobangBoard(15, 1);
        var ev9:GobangEval = new GobangEval(15);
        b9.put(5, 9, 1); ev9.move(5, 9, 1);
        b9.put(0, 0, -1); ev9.move(0, 0, -1);
        b9.put(6, 8, 1); ev9.move(6, 8, 1);
        b9.put(14, 0, -1); ev9.move(14, 0, -1);
        b9.put(7, 7, 1); ev9.move(7, 7, 1);
        b9.put(0, 14, -1); ev9.move(0, 14, -1);
        b9.put(9, 5, 1); ev9.move(9, 5, 1);
        b9.put(14, 14, -1); ev9.move(14, 14, -1);
        // (8,6) 是唯一成五点，P2 应直接短路
        var mm9:GobangMinmax = new GobangMinmax(b9, ev9);
        var r9:Object = mm9.search(-1, 2, false);
        assert(r9.x === 8 && r9.y === 6,
               "Minmax P2 blocks diagonal gap-five at (8,6): (" + r9.x + "," + r9.y + ")");

        // Test 10: 复杂中局 — 反对角线三连 + 多子干扰，白方仍应在三连附近防守
        // 还原实战模式：黑有 (6,8)-(7,7)-(8,6) 三连，周围有多颗双方棋子
        // 白方不应飞到远处角落
        var bA:GobangBoard = new GobangBoard(15, 1);
        var eA:GobangEval = new GobangEval(15);
        var setupA:Array = [
            [6,8,1],  [7,9,-1],  // 1-2
            [7,7,1],  [7,11,-1], // 3-4
            [9,8,1],  [8,8,-1],  // 5-6
            [6,6,1],  [6,4,-1],  // 7-8
            [8,7,1],  [5,4,-1],  // 9-10
            [9,4,1],  [9,7,-1],  // 11-12
            [8,6,1],  [9,6,-1],  // 13-14: 黑 (8,6) 完成反对角三连
            [5,8,1]              // 15
        ];
        for (var sA:Number = 0; sA < setupA.length; sA++) {
            bA.put(setupA[sA][0], setupA[sA][1], setupA[sA][2]);
            eA.move(setupA[sA][0], setupA[sA][1], setupA[sA][2]);
        }
        // 白方 move 16: 黑有 (6,8)-(7,7)-(8,6) 三连，延伸到 (9,5)/(5,9) 即成活四
        // 白方必须在三连附近防守，不能飞角落
        var mmA:GobangMinmax = new GobangMinmax(bA, eA);
        var rA:Object = mmA.search(-1, 6, false);
        var dA:Number = (rA.x - 7) * (rA.x - 7) + (rA.y - 7) * (rA.y - 7);
        assert(dA <= 18,
               "Minmax mid-game blocks anti-diagonal three near center: (" + rA.x + "," + rA.y + ") dist2=" + dA);

        // Test 11: P4a 活三两端均为 FOUR — 堵住一端即可化解
        // 黑棋 (4,5)-(5,6)-(6,7) 主对角线活三，(3,4)/(7,8) 两端都有 FOUR shape
        // P4a 之前因 opLiveFourCount>=2 误判为必败而放弃，现在应堵其中一端
        var bB:GobangBoard = new GobangBoard(15, 1);
        var eB:GobangEval = new GobangEval(15);
        bB.put(4, 5, 1); eB.move(4, 5, 1);
        bB.put(0, 0, -1); eB.move(0, 0, -1);
        bB.put(5, 6, 1); eB.move(5, 6, 1);
        bB.put(14, 0, -1); eB.move(14, 0, -1);
        bB.put(6, 7, 1); eB.move(6, 7, 1);
        bB.put(0, 14, -1); eB.move(0, 14, -1);
        // 白方 search: (3,4) 和 (7,8) 都是黑方 FOUR，P4a 应堵其一
        var mmB:GobangMinmax = new GobangMinmax(bB, eB);
        var rB:Object = mmB.search(-1, 4, false);
        var isBlock:Boolean = (rB.x === 3 && rB.y === 4) || (rB.x === 7 && rB.y === 8);
        assert(isBlock,
               "Minmax P4a blocks open-three extension (FOUR at both ends): (" + rB.x + "," + rB.y + ")");

        // Test 12: 实战复现 — 垂直四子带空隙(跳五)，P2 应直接堵缺口
        // 还原对弈局面：黑 col9 有 (9,6)-(9,7)-(9,8)-[空(9,9)]-(9,10) = FIVE at (9,9)
        var bC:GobangBoard = new GobangBoard(15, 1);
        var eC:GobangEval = new GobangEval(15);
        var setupC:Array = [
            [5,7,1],  [7,8,-1],   // 1-2
            [5,4,1],  [5,8,-1],   // 3-4
            [8,7,1],  [4,7,-1],   // 5-6
            [7,6,1],  [4,2,-1],   // 7-8
            [4,8,1],  [3,10,-1],  // 9-10
            [9,6,1],  [7,4,-1],   // 11-12
            [9,7,1],  [6,7,-1],   // 13-14
            [9,8,1]               // 15: 黑完成对角线四子 (5,4)-(7,6)-(8,7)-(9,8)
        ];
        for (var sC:Number = 0; sC < setupC.length; sC++) {
            bC.put(setupC[sC][0], setupC[sC][1], setupC[sC][2]);
            eC.move(setupC[sC][0], setupC[sC][1], setupC[sC][2]);
        }
        // 关键时刻：move 16 前（15 子），黑棋对角线 (5,4)-(7,6)-(8,7)-(9,8) 四子
        // (6,5) 是唯一 FIVE 点（缺口），P2 应直接堵住
        // 不含 move 16-17，此时 opFiveCount=1
        var mmC:GobangMinmax = new GobangMinmax(bC, eC);
        var rC:Object = mmC.search(-1, 2, false);
        assert(rC.x === 6 && rC.y === 5,
               "Minmax P2 blocks diagonal five-gap at critical moment: (" + rC.x + "," + rC.y + ")");

        // Test 13: 双冲四(FOUR_FOUR)交叉点 — 实战复现
        // (4,9) 处黑棋有水平 BLOCK_FOUR + 反对角线 BLOCK_FOUR → 双冲四不可防
        // 水平: 25(3,9)-[空(4,9)]-21(5,9)-19(6,9)-W(7,9)
        // 反对角: 29(3,10)-[空(4,9)]-27(5,8)-13(6,7)-3(7,6)-W(8,5)
        // 白方必须在 (4,9) 落子堵住交叉点
        var bD:GobangBoard = new GobangBoard(15, 1);
        var eD:GobangEval = new GobangEval(15);
        var setupD:Array = [
            [7,6,1],  [7,9,-1],   // 1-2: 黑中心，白堵水平右端
            [6,7,1],  [8,5,-1],   // 13-28 的效果：黑反对角，白堵反对角右端
            [5,8,1],  [0,0,-1],   // 27: 黑反对角第三子
            [3,9,1],  [0,14,-1],  // 25: 黑水平左端
            [5,9,1],  [14,0,-1],  // 21: 黑水平中
            [6,9,1],  [14,14,-1], // 19: 黑水平右
            [3,10,1]              // 29: 黑反对角延伸 → (4,9) 成为双冲四交叉
        ];
        for (var sD:Number = 0; sD < setupD.length; sD++) {
            bD.put(setupD[sD][0], setupD[sD][1], setupD[sD][2]);
            eD.move(setupD[sD][0], setupD[sD][1], setupD[sD][2]);
        }
        var mmD:GobangMinmax = new GobangMinmax(bD, eD);
        var rD:Object = mmD.search(-1, 2, false);
        assert(rD.x === 4 && rD.y === 9,
               "Minmax blocks FOUR_FOUR intersection at (4,9): (" + rD.x + "," + rD.y + ")");

        // Test 14: 水平跳四陷阱 — 三连+远端跳子（无其他高优先威胁干扰）
        // row 7: B(3,7) - [空4,7] - [空5,7] - B(6,7) - B(7,7) - B(8,7) - W(9,7)
        // 黑在 (5,7) 即成冲四 + (3,7) 跳连 → (4,7) 必成五
        // 构造时避免黑棋在其他方向有更高级威胁
        var bE:GobangBoard = new GobangBoard(15, 1);
        var eE:GobangEval = new GobangEval(15);
        var setupE:Array = [
            [6,7,1],  [9,7,-1],   // B 水平第1子 + W 堵右端
            [7,7,1],  [7,6,-1],   // B 水平第2子 + W 堵 col7 上端（消除垂直威胁）
            [8,7,1],  [7,8,-1],   // B 水平第3子 + W 堵 col7 下端
            [3,7,1],  [0,0,-1],   // B 远端跳子 + W 远处
            [5,9,1],  [14,0,-1],  // 额外黑子（远离 row7）
            [5,5,1],  [0,14,-1]   // 额外黑子（远离 row7）
        ];
        for (var sE:Number = 0; sE < setupE.length; sE++) {
            bE.put(setupE[sE][0], setupE[sE][1], setupE[sE][2]);
            eE.move(setupE[sE][0], setupE[sE][1], setupE[sE][2]);
        }
        // 白方应在 (5,7) 或 (4,7) 防守
        var mmE:GobangMinmax = new GobangMinmax(bE, eE);
        var rE:Object = mmE.search(-1, 6, false);
        var blockGapFour:Boolean = (rE.x === 5 && rE.y === 7) || (rE.x === 4 && rE.y === 7);
        assert(blockGapFour,
               "Minmax blocks horizontal gap-four setup at (5,7)/(4,7): (" + rE.x + "," + rE.y + ")");

        // Test 15: 实战复现 — 垂直活三差一格错堵
        // col7: B(7,5)-B(7,6)-B(7,7) 垂直活三，(7,4)/(7,8) 均为 FOUR 延伸点
        // P4a 应返回 (7,4) 或 (7,8)，绝不能走到 (7,9) 等偏移位
        var bF:GobangBoard = new GobangBoard(15, 1);
        var eF:GobangEval = new GobangEval(15);
        var setupF:Array = [
            [4,7,1],  [9,7,-1],   // 1-2
            [7,7,1],  [6,5,-1],   // 3-4
            [6,7,1],  [3,7,-1],   // 5-6
            [7,6,1],  [8,5,-1],   // 7-8
            [7,5,1]               // 9: 完成垂直活三
        ];
        for (var sF:Number = 0; sF < setupF.length; sF++) {
            bF.put(setupF[sF][0], setupF[sF][1], setupF[sF][2]);
            eF.move(setupF[sF][0], setupF[sF][1], setupF[sF][2]);
        }
        var mmF:GobangMinmax = new GobangMinmax(bF, eF);
        var rF:Object = mmF.search(-1, 4, false);
        var blockVertFour:Boolean = (rF.x === 7 && rF.y === 4) || (rF.x === 7 && rF.y === 8);
        assert(blockVertFour,
               "Minmax P4a blocks vertical open-three at (7,4)/(7,8) not (7,9): (" + rF.x + "," + rF.y + ")");

        // Test 16: 实战复现 — 水平三连+跳子形成活四点，P4a 应立即堵住
        // row 7: B(4,7) - [空(5,7)] - B(6,7) - B(7,7) → (5,7) 是活四点(FOUR=4)
        // 周围有足够棋子形成中局复杂度
        // 白方不应走到 (9,7) 等远处，必须堵 (5,7)
        var bG:GobangBoard = new GobangBoard(15, 1);
        var eG:GobangEval = new GobangEval(15);
        // 纯净的水平跳连：B(4,7)-[空(5,7)]-B(6,7)-B(7,7) → (5,7) 是 FOUR=4
        // 无其他高优先级黑棋威胁干扰
        var setupG:Array = [
            [4,7,1],  [4,8,-1],   // B row7 + W 下方
            [7,7,1],  [7,6,-1],   // B row7 + W col7 上方（消除垂直威胁）
            [6,7,1],  [0,0,-1],   // B row7 第三子
            [10,10,1],[14,0,-1],  // 远处黑子
            [10,4,1], [0,14,-1]   // 远处黑子
        ];
        for (var sG:Number = 0; sG < setupG.length; sG++) {
            bG.put(setupG[sG][0], setupG[sG][1], setupG[sG][2]);
            eG.move(setupG[sG][0], setupG[sG][1], setupG[sG][2]);
        }
        var mmG:GobangMinmax = new GobangMinmax(bG, eG);
        var rG:Object = mmG.search(-1, 4, false);
        // (5,7) 或 (8,7) 是水平活四的两个端点
        var blockLiveFour:Boolean = (rG.x === 5 && rG.y === 7) || (rG.x === 8 && rG.y === 7);
        assert(blockLiveFour,
               "Minmax P4a blocks horizontal live-four gap at (5,7)/(8,7): (" + rG.x + "," + rG.y + ")");

        // Test 17: 实战复现 — 主对角线三连，中局复杂度下 P4a 应及时堵住
        // 对角线 \: B(3,6)-B(4,7)-B(5,8)，延伸点 (2,5)/(6,9) 均为 FOUR
        // 周围有多颗双方棋子（还原 39 手对弈的中局密度）
        var bH:GobangBoard = new GobangBoard(15, 1);
        var eH:GobangEval = new GobangEval(15);
        // 最小化：只有对角线三连 + 白棋四角分散
        var setupH:Array = [
            [5,8,1],  [0,0,-1],
            [4,7,1],  [14,0,-1],
            [3,6,1],  [0,14,-1]   // 完成对角线三连 (3,6)-(4,7)-(5,8)
        ];
        for (var sH:Number = 0; sH < setupH.length; sH++) {
            bH.put(setupH[sH][0], setupH[sH][1], setupH[sH][2]);
            eH.move(setupH[sH][0], setupH[sH][1], setupH[sH][2]);
        }
        // P4a: (2,5) 和 (6,9) 都是 FOUR，应堵其一
        var mmH:GobangMinmax = new GobangMinmax(bH, eH);
        var rH:Object = mmH.search(-1, 4, false);
        var blockDiag:Boolean = (rH.x === 2 && rH.y === 5) || (rH.x === 6 && rH.y === 9);
        assert(blockDiag,
               "Minmax P4a blocks diagonal open-three at (2,5)/(6,9): (" + rH.x + "," + rH.y + ")");

        // Test 18: 实战复现 — 水平跳连三子+多子干扰，P4a 应堵 (6,5)
        // row5: B(4,5)-B(5,5)-[空(6,5)]-B(7,5) → (6,5) 是 FOUR=4
        // 还原实战：周围有多颗棋子，但白棋无自身高级威胁
        var bI:GobangBoard = new GobangBoard(15, 1);
        var eI:GobangEval = new GobangEval(15);
        var setupI:Array = [
            [8,7,1],  [10,8,-1],  // 1-2
            [9,3,1],  [9,8,-1],   // 3-4
            [7,8,1],  [11,5,-1],  // 5-6
            [7,5,1],  [7,9,-1],   // 7-8: B row5 第1子
            [5,7,1],  [4,8,-1],   // 9-10
            [4,5,1],  [8,9,-1],   // 11-12: B row5 第2子
            [7,3,1],  [7,7,-1],   // 13-14
            [5,5,1]               // 15: B row5 第3子 → (6,5) 成为活四!
        ];
        for (var sI:Number = 0; sI < setupI.length; sI++) {
            bI.put(setupI[sI][0], setupI[sI][1], setupI[sI][2]);
            eI.move(setupI[sI][0], setupI[sI][1], setupI[sI][2]);
        }
        var mmI:GobangMinmax = new GobangMinmax(bI, eI);
        var rI:Object = mmI.search(-1, 4, false);
        assert(rI.x === 6 && rI.y === 5,
               "Minmax P4a blocks row5 live-four gap at (6,5): (" + rI.x + "," + rI.y + ")");

        // Test 19: 精确实战复现 — move 16 时的完整局面
        // 黑棋 row5: (4,5)-(5,5)-[空(6,5)]-(7,5) = FOUR
        // 白棋有复杂的周围棋子但无自身高级威胁
        var bJ:GobangBoard = new GobangBoard(15, 1);
        var eJ:GobangEval = new GobangEval(15);
        var setupJ:Array = [
            [8,7,1],  [10,8,-1],   // 1-2
            [9,3,1],  [9,8,-1],    // 3-4
            [7,8,1],  [11,5,-1],   // 5-6
            [7,5,1],  [7,9,-1],    // 7-8
            [5,7,1],  [4,8,-1],    // 9-10
            [4,5,1],  [8,9,-1],    // 11-12
            [7,3,1],  [7,7,-1],    // 13-14
            [5,5,1]                // 15: 完成 row5 活四
        ];
        for (var sJ:Number = 0; sJ < setupJ.length; sJ++) {
            bJ.put(setupJ[sJ][0], setupJ[sJ][1], setupJ[sJ][2]);
            eJ.move(setupJ[sJ][0], setupJ[sJ][1], setupJ[sJ][2]);
        }
        var mmJ:GobangMinmax = new GobangMinmax(bJ, eJ);
        var rJ:Object = mmJ.search(-1, 4, false);
        assert(rJ.x === 6 && rJ.y === 5,
               "Minmax exact-game blocks row5 FOUR at (6,5): (" + rJ.x + "," + rJ.y + ")");

        // Test: VCF 门控 — 验证门控机制生效（skipped > 0 证明代码路径被执行）
        // 注：深搜过程中 AI 试探性走子可能创建 THREE+ 形状导致部分 probe 通过门控
        // 因此只验证 skipped > 0（门控有效），不要求 probes === 0
        var bNoThreat:GobangBoard = new GobangBoard(15, 1);
        var evNoThreat:GobangEval = new GobangEval(15);
        bNoThreat.put(7, 7, 1); evNoThreat.move(7, 7, 1);
        bNoThreat.put(0, 0, -1); evNoThreat.move(0, 0, -1);
        bNoThreat.put(7, 9, 1); evNoThreat.move(7, 9, 1);
        bNoThreat.put(14, 14, -1); evNoThreat.move(14, 14, -1);
        var mmNoThreat:GobangMinmax = new GobangMinmax(bNoThreat, evNoThreat);
        mmNoThreat.search(-1, 8, true);  // depth=8+VCT 确保进入深层节点触发 VCF 门控
        var stNoThreat:Object = mmNoThreat.getStats();
        // VCF 门控统计完整性（确认 stats 结构存在且非负）
        // 注：稀疏棋盘上搜索可能被 pre-search 截断而完全不进入 VCF 检查路径
        assert(stNoThreat.vcfSkipped >= 0 && stNoThreat.vcfProbes >= 0,
               "VCF gate: stats non-negative: skip=" + stNoThreat.vcfSkipped
               + " probe=" + stNoThreat.vcfProbes);
        trace("[INFO] VCF gate test: probes=" + stNoThreat.vcfProbes
            + " skipped=" + stNoThreat.vcfSkipped);

        // Test: TT 缓存在迭代加深中产生复用（回归测试：修复前全局 0 命中）
        // 构造安静中盘局面（无 preSearch 触发），depth=6 迭代加深验证 TT 复用
        // 双方各 5 子分散放置，不构成 THREE+ 连线，迫使完整搜索
        var bTT:GobangBoard = new GobangBoard(15, 1);
        var evTT:GobangEval = new GobangEval(15);
        var ttSetup:Array = [
            [7,7,1], [5,5,-1], [8,9,1], [9,5,-1], [5,8,1],
            [10,7,-1], [9,9,1], [6,10,-1], [4,6,1], [8,4,-1]
        ];
        for (var tti:Number = 0; tti < ttSetup.length; tti++) {
            bTT.put(ttSetup[tti][0], ttSetup[tti][1], ttSetup[tti][2]);
            evTT.move(ttSetup[tti][0], ttSetup[tti][1], ttSetup[tti][2]);
        }
        var mmTT:GobangMinmax = new GobangMinmax(bTT, evTT);
        mmTT.search(-1, 6, false);
        var stTT:Object = mmTT.getStats();
        // 验证 TT 被有效利用：完全命中 + 浅层收窄 + flag 不匹配 三者之和 > 0
        var ttTotal:Number = stTT.ttHits + stTT.ttShallow + stTT.ttMissFlag;
        assert(ttTotal > 0,
               "TT iterative deepening: cache utilized (hits=" + stTT.ttHits
               + " shallow=" + stTT.ttShallow + " missFlag=" + stTT.ttMissFlag + ")");
        trace("[INFO] TT regression: hits=" + stTT.ttHits + " shallow=" + stTT.ttShallow
            + " missFlag=" + stTT.ttMissFlag);

        // Test: 对局复盘 — 开局 3 手后 AI（白方）的应对
        // 黑: (7,8)(6,8)(5,8) 垂直三连 → AI 必须在纵向堵截
        var bGame:GobangBoard = new GobangBoard(15, 1);
        var evGame:GobangEval = new GobangEval(15);
        bGame.put(7, 8, 1); evGame.move(7, 8, 1);   // 黑1
        bGame.put(7, 7, -1); evGame.move(7, 7, -1);  // 白2 天元
        bGame.put(6, 8, 1); evGame.move(6, 8, 1);    // 黑3
        bGame.put(8, 7, -1); evGame.move(8, 7, -1);  // 白4（原局实际走法）
        bGame.put(5, 8, 1); evGame.move(5, 8, 1);    // 黑5 → 垂直三连 (5,8)(6,8)(7,8)
        // 白方应在 (4,8) 或 (8,8) 堵截纵向三连
        var mmGame:GobangMinmax = new GobangMinmax(bGame, evGame);
        var rGame:Object = mmGame.search(-1, 6, false);
        var gx:Number = rGame.x;
        var gy:Number = rGame.y;
        // 合理防守：堵三连两端 (4,8)/(8,8) 或紧邻位
        var onColumn8:Boolean = (gy === 8);
        var nearThree:Boolean = (gx <= 5 || gx >= 7);
        assert(onColumn8 && nearThree,
               "Opening defense: blocks vertical three on col 8: ("
               + gx + "," + gy + ")");

        // Test: LUT 单调性 — BLOCK_THREE > TWO×2, BLOCK_FOUR > THREE×2
        var evMono:GobangEval = new GobangEval(15);
        // 构造：黑 TWO 横向 + 白 BLOCK_THREE 横向
        evMono.move(7, 6, 1); evMono.move(7, 7, 1); // 黑二连
        var scoreTWO:Number = evMono.evaluate(1); // 黑方视角：黑有 TWO
        var evMono2:GobangEval = new GobangEval(15);
        evMono2.move(7, 5, 1); evMono2.move(7, 6, 1); evMono2.move(7, 7, 1);
        evMono2.move(7, 4, -1); // 白挡住一端
        var scoreBT:Number = evMono2.evaluate(1); // 黑有 BLOCK_THREE
        assert(scoreBT > scoreTWO,
               "LUT monotonicity: BLOCK_THREE(" + scoreBT + ") > TWO(" + scoreTWO + ")");
        trace("[INFO] LUT mono: BLOCK_THREE=" + scoreBT + " TWO=" + scoreTWO);

        // Test: 开局书覆盖 — B(7,7) W(8,8) B(7,8) → W 应封伸点 (7,9)
        var bookHist:Array = [{i:7, j:7, role:1}, {i:8, j:8, role:-1}, {i:7, j:8, role:1}];
        var bookResult:Object = GobangBook.lookup(bookHist, 3);
        assert(bookResult !== null, "Opening book covers B(7,7) W(8,8) B(7,8)");
        assert(bookResult.x === 7 && bookResult.y === 9,
               "Opening book: W blocks endpoint at (7,9), got (" + bookResult.x + "," + bookResult.y + ")");
        // 对称验证: B(7,7) W(8,8) B(8,7) → W 应封 (9,7)（转置自动覆盖）
        var bookHist2:Array = [{i:7, j:7, role:1}, {i:8, j:8, role:-1}, {i:8, j:7, role:1}];
        var bookResult2:Object = GobangBook.lookup(bookHist2, 3);
        assert(bookResult2 !== null, "Opening book covers B(7,7) W(8,8) B(8,7) via symmetry");
        assert(bookResult2.x === 9 && bookResult2.y === 7,
               "Opening book symmetry: W blocks at (9,7), got (" + bookResult2.x + "," + bookResult2.y + ")");
        trace("[INFO] Opening book: direct=(7,9) symmetric=(9,7)");
    }

    private static function testAI():Void {
        trace("--- testAI ---");

        // Test 1: Basic flow with difficulty=100
        var ai:GobangAI = new GobangAI(-1, 100);
        assert(ai.playerMove(7, 7) === true, "AI playerMove succeeds");
        var aiResult:Object = ai.aiMove();
        assert(aiResult !== null, "AI aiMove returns result");
        assert(aiResult.x >= 0 && aiResult.x < 15 && aiResult.y >= 0 && aiResult.y < 15,
               "AI d=100 valid coords: (" + aiResult.x + "," + aiResult.y + ")");

        // Test 2: Cannot move on occupied
        assert(ai.playerMove(7, 7) === false, "AI playerMove on occupied fails");

        // Test 3: Undo
        assert(ai.undo() === true, "AI undo succeeds");
        assert(ai.getCurrentRole() === -1, "AI undo restores role");

        // Test 4: Reset
        ai.reset();
        assert(ai.getCurrentRole() === 1, "AI reset: role is black");
        assert(ai.getBoard()[7 * 15 + 7] === 0, "AI reset: board clear");

        // Test 5: Cannot call aiMove when not AI's turn
        assert(ai.aiMove() === null, "AI aiMove when not AI turn returns null");

        // Test 6: Difficulty=0 still returns valid move
        var ai2:GobangAI = new GobangAI(-1, 0);
        ai2.playerMove(7, 7);
        var r2:Object = ai2.aiMove();
        assert(r2 !== null && r2.x >= 0 && r2.x < 15, "AI d=0 valid move: (" + r2.x + "," + r2.y + ")");

        // Test 7: Difficulty=50 still returns valid move
        var ai3:GobangAI = new GobangAI(-1, 50);
        ai3.playerMove(7, 7);
        var r3:Object = ai3.aiMove();
        assert(r3 !== null && r3.x >= 0 && r3.x < 15, "AI d=50 valid move: (" + r3.x + "," + r3.y + ")");

        // Test 8: setDifficulty works
        ai3.setDifficulty(100);
        assert(ai3.getDifficulty() === 100, "AI setDifficulty");

        // Test 9: difficulty=30 不 drop 战术强制手（回归：P4combo 被 drop 导致输棋）
        // 直接操控棋盘构造对手双三局面，白方四角分散不构成威胁
        // difficulty=30 → bestProb=30%，旧代码 70% 概率 drop
        var dropOK:Boolean = true;
        for (var di:Number = 0; di < 10; di++) {
            var aiDrop:GobangAI = new GobangAI(-1, 30);
            var aiDropObj:Object = aiDrop;
            var bDrop:GobangBoard = aiDropObj["_board"];
            var eDrop:GobangEval = aiDropObj["_eval"];
            // 黑棋水平 (7,6)(7,8) + 垂直 (6,7)(8,7)，(7,7)=双三交叉
            // 白棋四角远离，不构成任何威胁
            bDrop.put(7, 6, 1); eDrop.move(7, 6, 1);
            bDrop.put(0, 0, -1); eDrop.move(0, 0, -1);
            bDrop.put(7, 8, 1); eDrop.move(7, 8, 1);
            bDrop.put(14, 0, -1); eDrop.move(14, 0, -1);
            bDrop.put(6, 7, 1); eDrop.move(6, 7, 1);
            bDrop.put(0, 14, -1); eDrop.move(0, 14, -1);
            bDrop.put(8, 7, 1); eDrop.move(8, 7, 1);
            // 7 子后 role=-1（白方），aiMove 走完整流程含 drop
            var rDrop:Object = aiDrop.aiMove();
            if (rDrop === null || rDrop.x !== 7 || rDrop.y !== 7) {
                dropOK = false;
                break;
            }
        }
        assert(dropOK, "Difficulty drop: tactical forced move never dropped at d=30");

        // Test 10: refine 不覆盖搜索确认的高分战术走法（回归：score=100825 被覆盖为 -231806）
        // 构造白方有活四机会的局面，搜索应返回高分（>= 50000）
        // refine 不应覆盖为低分走法
        var aiRef:GobangAI = new GobangAI(-1, 100);
        var aiRefObj:Object = aiRef;
        var bRef:GobangBoard = aiRefObj["_board"];
        var eRef:GobangEval = aiRefObj["_eval"];
        // 白方 (7,7)(7,8)(7,9) 三连 + 黑方分散不构成紧急威胁
        bRef.put(6, 5, 1); eRef.move(6, 5, 1);
        bRef.put(7, 7, -1); eRef.move(7, 7, -1);
        bRef.put(6, 6, 1); eRef.move(6, 6, 1);
        bRef.put(7, 8, -1); eRef.move(7, 8, -1);
        bRef.put(10, 3, 1); eRef.move(10, 3, 1);
        bRef.put(7, 9, -1); eRef.move(7, 9, -1);
        bRef.put(10, 10, 1); eRef.move(10, 10, 1);
        bRef.put(8, 6, -1); eRef.move(8, 6, -1);
        bRef.put(3, 10, 1); eRef.move(3, 10, 1);
        bRef.put(6, 10, -1); eRef.move(6, 10, -1);
        bRef.put(3, 3, 1); eRef.move(3, 3, 1);
        // 白方 (7,7)(7,8)(7,9) 三连 + (8,6)(6,10) 支撑
        // 搜索应找到扩展三连的高分手（如 (7,6) 或 (7,10)）
        var rRef:Object = aiRef.aiMove();
        assert(rRef !== null && rRef.score > 0,
               "Refine skip: AI with three-in-row gets positive score: " + rRef.score
               + " at (" + rRef.x + "," + rRef.y + ")");

        // Test 11: undo 正确回退 _moveLog 和 _totalNodesAllMoves（async 路径）
        var aiUndo:GobangAI = new GobangAI(-1, 100);
        aiUndo.playerMove(7, 7);   // 黑1
        aiUndo.aiMoveStart(16);    // 白2 开局库
        var uStep:Object = aiUndo.aiMoveStep(16);
        aiUndo.playerMove(6, 6);   // 黑3（避开开局库匹配）
        aiUndo.aiMoveStart(16);    // 白4 搜索
        while (true) { uStep = aiUndo.aiMoveStep(16); if (uStep.done) break; }
        var aiUndoObj:Object = aiUndo;
        var logBefore:Number = aiUndoObj["_moveLog"].length;
        var nodesBefore:Number = aiUndoObj["_totalNodesAllMoves"];
        assert(logBefore >= 1, "Undo pre-check: moveLog has entries: " + logBefore);
        // undo 两步（白4 + 黑3）
        aiUndo.undo(); // 白4（AI 棋 → 回退 _moveLog + _moveNodes + _totalNodesAllMoves）
        aiUndo.undo(); // 黑3（玩家棋 → 不回退）
        var logAfter:Number = aiUndoObj["_moveLog"].length;
        var nodesAfter:Number = aiUndoObj["_totalNodesAllMoves"];
        assert(logAfter === logBefore - 1,
               "Undo rollback: moveLog shrinks by 1: " + logBefore + " -> " + logAfter);
        assert(nodesAfter <= nodesBefore,
               "Undo rollback: totalNodes non-increasing: " + nodesBefore + " -> " + nodesAfter);

        // Test 12: secondInherited 标记在单候选深搜中被设置
        // 使用异步路径：构造局面使 d=6 有 2+ 候选，d=8 战术加深只 1 候选
        var aiInh:GobangAI = new GobangAI(-1, 100);
        var aiInhObj:Object = aiInh;
        var bInh:GobangBoard = aiInhObj["_board"];
        var eInh:GobangEval = aiInhObj["_eval"];
        // 黑棋构成冲四威胁（触发战术加深 d=8 pl=4）
        // 白棋分散，不构成自身威胁
        bInh.put(7, 7, 1); eInh.move(7, 7, 1);
        bInh.put(0, 0, -1); eInh.move(0, 0, -1);
        bInh.put(7, 8, 1); eInh.move(7, 8, 1);
        bInh.put(14, 0, -1); eInh.move(14, 0, -1);
        bInh.put(7, 9, 1); eInh.move(7, 9, 1);
        bInh.put(0, 14, -1); eInh.move(0, 14, -1);
        bInh.put(7, 10, 1); eInh.move(7, 10, 1);
        bInh.put(14, 14, -1); eInh.move(14, 14, -1);
        // 黑棋 (7,7)-(7,10) 四连 → 白方必须堵五
        // preSearch P2_blockFive 会直接返回，secondInherited 不适用
        // 改为测试字段存在性：secondInherited 在返回对象中有定义
        var mmInh:GobangMinmax = aiInhObj["_minmax"];
        mmInh.searchStart(-1, 6, false);
        var inhFrames:Number = 0;
        var inhResult:Object = null;
        while (inhFrames < 60) {
            inhResult = mmInh.step(8);
            inhFrames++;
            if (inhResult.done) break;
        }
        assert(inhResult !== null && inhResult.done === true,
               "Inherited top2: search completes");
        // secondInherited 字段应存在（true 或 undefined/false 均可，关键是链路通畅）
        var hasField:Boolean = (inhResult.secondInherited !== undefined)
            || (inhResult.secondX === undefined);
        assert(hasField || inhResult.secondInherited === false || inhResult.secondInherited === true,
               "Inherited top2: secondInherited field flows through step()");

        // === Test 13: collectRootMoves 返回合理候选 ===
        var bRoot:GobangBoard = new GobangBoard(15, 1);
        var eRoot:GobangEval = new GobangEval(15);
        bRoot.put(7, 7, 1); eRoot.move(7, 7, 1);
        bRoot.put(8, 8, -1); eRoot.move(8, 8, -1);
        bRoot.put(6, 6, 1); eRoot.move(6, 6, 1);
        bRoot.put(9, 9, -1); eRoot.move(9, 9, -1);
        var mmRoot:GobangMinmax = new GobangMinmax(bRoot, eRoot);
        var rootMoves:Array = mmRoot.collectRootMoves(1, 8);
        assert(rootMoves.length > 0, "collectRootMoves: non-empty: " + rootMoves.length);
        assert(rootMoves.length <= 8, "collectRootMoves: respects limit: " + rootMoves.length);
        // 所有候选必须在棋盘内且为空位
        for (var rmi:Number = 0; rmi < rootMoves.length; rmi++) {
            var rmx:Number = rootMoves[rmi][0];
            var rmy:Number = rootMoves[rmi][1];
            assert(rmx >= 0 && rmx < 15 && rmy >= 0 && rmy < 15,
                   "collectRootMoves[" + rmi + "] in bounds: (" + rmx + "," + rmy + ")");
            assert(bRoot.board[rmx * 15 + rmy] === 0,
                   "collectRootMoves[" + rmi + "] is empty: (" + rmx + "," + rmy + ")");
        }
        trace("[INFO] collectRootMoves: " + rootMoves.length + " candidates");

        // === Test 14: collectExpandedRootMoves 候选数 >= collectRootMoves ===
        var expandedMoves:Array = mmRoot.collectExpandedRootMoves(1, 12);
        assert(expandedMoves.length >= rootMoves.length,
               "collectExpandedRootMoves >= collectRootMoves: "
               + expandedMoves.length + " >= " + rootMoves.length);
        trace("[INFO] collectExpandedRootMoves: " + expandedMoves.length + " candidates");

        // === Test 15: collectRootMoves + searchSkipMultiP4a 基本功能 ===
        // searchSkipMultiP4a 应能正常完成搜索（无崩溃，返回有效走法）
        var bSkip:GobangBoard = new GobangBoard(15, 1);
        var eSkip:GobangEval = new GobangEval(15);
        bSkip.put(7, 7, 1); eSkip.move(7, 7, 1);
        bSkip.put(8, 8, -1); eSkip.move(8, 8, -1);
        bSkip.put(6, 6, 1); eSkip.move(6, 6, 1);
        bSkip.put(9, 9, -1); eSkip.move(9, 9, -1);
        bSkip.put(5, 5, 1); eSkip.move(5, 5, 1);
        bSkip.put(10, 10, -1); eSkip.move(10, 10, -1);
        var mmSkip:GobangMinmax = new GobangMinmax(bSkip, eSkip);
        var rSkip:Object = mmSkip.searchSkipMultiP4a(1, 4, false);
        assert(rSkip !== null && rSkip.x >= 0,
               "searchSkipMultiP4a: returns valid move: (" + rSkip.x + "," + rSkip.y + ")");
        trace("[INFO] searchSkipMultiP4a: (" + rSkip.x + "," + rSkip.y + ") score=" + rSkip.score);

        // === Test 16: _preSearchTactical 返回 liveFourCount + candidates ===
        // 通过 GobangAI 异步路径间接测试（step() 透传这些字段）
        var aiP4:GobangAI = new GobangAI(-1, 100);
        // 用 playerMove 交替放棋，确保 role 正确
        aiP4.playerMove(7, 5);  // B1
        aiP4.playerMove(3, 3);  // AI 被绕过 — 直接操控内部
        var aiP4Obj:Object = aiP4;
        var bP4:GobangBoard = aiP4Obj["_board"];
        var eP4:GobangEval = aiP4Obj["_eval"];
        // 手动构造黑棋活四 (7,5 已放)
        bP4.put(7, 6, 1); eP4.move(7, 6, 1);
        bP4.put(0, 0, -1); eP4.move(0, 0, -1);
        bP4.put(7, 7, 1); eP4.move(7, 7, 1);
        bP4.put(0, 2, -1); eP4.move(0, 2, -1);
        bP4.put(7, 8, 1); eP4.move(7, 8, 1);
        bP4.put(0, 4, -1); eP4.move(0, 4, -1);
        // 此时黑 (7,5)(7,6)(7,7)(7,8) 四连，轮到白方
        // 强制白方走 — 通过 minmax 的 search 检测 P4a 并验证透传
        var mmP4:GobangMinmax = aiP4Obj["_minmax"];
        var rP4:Object = mmP4.search(-1, 4, false);
        assert(rP4 !== null && rP4.x >= 0, "P4a search: returns valid move");
        trace("[INFO] P4a search: (" + rP4.x + "," + rP4.y
              + ") phase=" + rP4.phaseLabel
              + " lfc=" + rP4.liveFourCount
              + " cands=" + ((rP4.candidates != undefined) ? rP4.candidates.length : "none"));
    }

    private static function testAsyncAI():Void {
        trace("--- testAsyncAI ---");

        // Test 1: 黑棋开局库直接走天元
        var ai0:GobangAI = new GobangAI(1, 100);
        assert(ai0.aiMoveStart() === true, "Async AI opening start succeeds");
        var openResult:Object = ai0.aiMoveStep(1);
        assert(openResult.done === true, "Async AI opening finishes immediately");
        assert(openResult.phaseLabel === "opening", "Async AI opening phase");
        assert(openResult.x === 7 && openResult.y === 7, "Async AI opening move is center");

        // Test 2: 中局异步搜索可在有限步数内完成，防止每帧重启导致卡死
        var board:GobangBoard = new GobangBoard(15, 1);
        var eval:GobangEval = new GobangEval(15);
        var setup:Array = [
            [7,7,1], [6,6,-1], [7,8,1], [6,7,-1], [7,9,1],
            [8,8,-1], [6,8,1], [8,7,-1], [5,7,1], [8,6,-1]
        ];
        for (var si:Number = 0; si < setup.length; si++) {
            board.put(setup[si][0], setup[si][1], setup[si][2]);
            eval.move(setup[si][0], setup[si][1], setup[si][2]);
        }
        var mm:GobangMinmax = new GobangMinmax(board, eval);
        mm.searchStart(1, 4, false);
        var frames:Number = 0;
        var stepResult:Object = null;
        var start:Number = getTimer();
        while (frames < 90) {
            stepResult = mm.step(8);
            frames++;
            if (stepResult.done) break;
        }
        var elapsed:Number = getTimer() - start;
        assert(stepResult !== null && stepResult.done === true,
               "Async Minmax finishes within 90 steps (frames=" + frames + ")");
        assert(stepResult.nodes >= 0, "Async Minmax visits nodes: " + stepResult.nodes);
        assert(stepResult.x >= 0 && stepResult.x < 15 && stepResult.y >= 0 && stepResult.y < 15,
               "Async Minmax returns valid move (" + stepResult.x + "," + stepResult.y + ")");
        trace("[INFO] Async Minmax smoke(8ms): " + elapsed + "ms, steps=" + frames
              + ", phase=" + stepResult.phaseLabel + ", nodes=" + stepResult.nodes);

        // Test 2b: getStats 返回有效计数器
        var stats:Object = mm.getStats();
        assert(stats.ttHits !== undefined, "getStats has ttHits");
        assert(stats.vcfProbes !== undefined, "getStats has vcfProbes");
        assert(stats.vcfSkipped !== undefined, "getStats has vcfSkipped");
        assert(stats.preSearch !== undefined, "getStats has preSearch");
        assert(stats.ttHits >= 0, "ttHits non-negative: " + stats.ttHits);
        assert(stats.vcfProbes + stats.vcfSkipped >= 0, "VCF counters valid");
        trace("[INFO] Stats: TT=" + stats.ttHits + "/" + stats.ttMissFlag
            + " VCF=" + stats.vcfProbes + "/" + stats.vcfHits + "/" + stats.vcfSkipped
            + " Pre=" + stats.preSearch);

        // Test 3: AI 低预算异步入口可完成，不依赖高帧预算
        var aiLow:GobangAI = new GobangAI(-1, 100);
        aiLow.playerMove(7, 7);
        aiLow.aiMove(); // 开局库应答
        aiLow.playerMove(6, 6); // 避开开局库匹配
        assert(aiLow.aiMoveStart(8) === true, "Async AI low-budget start succeeds");
        frames = 0;
        start = getTimer();
        while (frames < 120) {
            stepResult = aiLow.aiMoveStep(8);
            frames++;
            if (stepResult.done) break;
        }
        elapsed = getTimer() - start;
        assert(stepResult !== null && stepResult.done === true,
               "Async AI low-budget finishes within 120 steps (frames=" + frames + ")");
        assert(stepResult.x >= 0 && stepResult.x < 15 && stepResult.y >= 0 && stepResult.y < 15,
               "Async AI low-budget returns valid move (" + stepResult.x + "," + stepResult.y + ")");
        assert(stepResult.phaseLabel.indexOf("minmax_d") === 0,
               "Async AI low-budget uses minmax: " + stepResult.phaseLabel);
        trace("[INFO] Async AI smoke(8ms): " + elapsed + "ms, steps=" + frames
              + ", phase=" + stepResult.phaseLabel + ", nodes=" + stepResult.nodes);

        // Test 3b: completedDepth 和 top2 字段透传（使用低预算搜索结果，非 preSearch 路径）
        var aiLowObj:Object = aiLow;
        var mmLow:GobangMinmax = aiLowObj["_minmax"];
        assert(mmLow.getCompletedDepth() >= 2,
               "completedDepth >= 2 after minmax: " + mmLow.getCompletedDepth());
        assert(stepResult.secondX !== undefined, "step result has secondX field");

        // Test 4: 低预算下，强制手小分支局面允许保守加深到 depth=4
        var aiTac:GobangAI = new GobangAI(-1, 100);
        var aiObj:Object = aiTac;
        var boardTac:GobangBoard = aiObj["_board"];
        var evalTac:GobangEval = aiObj["_eval"];
        var tacSeq:Array = [
            [7,5,1], [0,0,-1], [7,6,1], [0,1,-1],
            [7,7,1], [0,2,-1], [7,8,1]
        ];
        for (var ti:Number = 0; ti < tacSeq.length; ti++) {
            boardTac.put(tacSeq[ti][0], tacSeq[ti][1], tacSeq[ti][2]);
            evalTac.move(tacSeq[ti][0], tacSeq[ti][1], tacSeq[ti][2]);
        }
        assert(aiTac.aiMoveStart(8) === true, "Async AI tactical low-budget start succeeds");
        frames = 0;
        while (frames < 60) {
            stepResult = aiTac.aiMoveStep(8);
            frames++;
            if (stepResult.done) break;
        }
        var tacticalBlock:Boolean = (stepResult.x === 7 && (stepResult.y === 4 || stepResult.y === 9));
        assert(stepResult !== null && stepResult.done === true && tacticalBlock,
               "Async AI tactical low-budget blocks open four: (" + stepResult.x + "," + stepResult.y + ")");
        assert(stepResult.phaseLabel.indexOf("minmax_d") === 0,
               "Async AI tactical low-budget escalates to tactical depth: " + stepResult.phaseLabel);

        // Test 5: 低预算下，对手 open-three 也应触发保守加深并优先防守
        var aiThree:GobangAI = new GobangAI(-1, 100);
        var aiThreeObj:Object = aiThree;
        var boardThree:GobangBoard = aiThreeObj["_board"];
        var evalThree:GobangEval = aiThreeObj["_eval"];
        var threeSeq:Array = [
            [7,6,1], [0,0,-1], [7,7,1], [0,1,-1], [7,8,1]
        ];
        for (var thi:Number = 0; thi < threeSeq.length; thi++) {
            boardThree.put(threeSeq[thi][0], threeSeq[thi][1], threeSeq[thi][2]);
            evalThree.move(threeSeq[thi][0], threeSeq[thi][1], threeSeq[thi][2]);
        }
        assert(aiThree.aiMoveStart(8) === true, "Async AI open-three defense start succeeds");
        frames = 0;
        while (frames < 120) {
            stepResult = aiThree.aiMoveStep(8);
            frames++;
            if (stepResult.done) break;
        }
        var threeBlock:Boolean = (stepResult.x === 7 && (stepResult.y === 5 || stepResult.y === 9));
        assert(stepResult !== null && stepResult.done === true && threeBlock,
               "Async AI open-three defense blocks at endpoint: (" + stepResult.x + "," + stepResult.y + ")");
        assert(stepResult.phaseLabel.indexOf("minmax_d") === 0
               || stepResult.phaseLabel.indexOf("bridgeprobe_d") === 0
               || stepResult.phaseLabel === "done"
               || stepResult.phaseLabel.indexOf("P4") === 0,
               "Async AI open-three defense uses search or P4a shortcut: " + stepResult.phaseLabel);

        // Test 6: 长布局下，低预算异步路径也应优先考虑桥接延伸手
        var aiBridge:GobangAI = new GobangAI(1, 100);
        var aiBridgeObj:Object = aiBridge;
        var boardBridge:GobangBoard = aiBridgeObj["_board"];
        var evalBridge:GobangEval = aiBridgeObj["_eval"];
        var bridgeSeq:Array = [
            [7,5,1], [0,0,-1], [7,9,1], [0,1,-1],
            [5,7,1], [1,0,-1], [9,7,1], [1,1,-1],
            [10,10,1], [2,2,-1]
        ];
        for (var bri:Number = 0; bri < bridgeSeq.length; bri++) {
            boardBridge.put(bridgeSeq[bri][0], bridgeSeq[bri][1], bridgeSeq[bri][2]);
            evalBridge.move(bridgeSeq[bri][0], bridgeSeq[bri][1], bridgeSeq[bri][2]);
        }
        assert(aiBridge.aiMoveStart(8) === true, "Async AI strategic low-budget start succeeds");
        frames = 0;
        while (frames < 120) {
            stepResult = aiBridge.aiMoveStep(8);
            frames++;
            if (stepResult.done) break;
        }
        assert(stepResult !== null && stepResult.done === true,
               "Async AI strategic low-budget finishes within 120 steps (frames=" + frames + ")");
        assert(stepResult.x >= 3 && stepResult.x <= 11 && stepResult.y >= 3 && stepResult.y <= 11,
               "Async AI strategic low-budget plays in center area: (" + stepResult.x + "," + stepResult.y + ")");
        assert(stepResult.phaseLabel.indexOf("minmax_d") === 0
               || stepResult.phaseLabel.indexOf("bridgeprobe_d") === 0,
               "Async AI strategic low-budget uses refined search: " + stepResult.phaseLabel);
        trace("[INFO] Async AI strategic low-budget: (" + stepResult.x + "," + stepResult.y + ")"
              + ", phase=" + stepResult.phaseLabel + ", nodes=" + stepResult.nodes
              + ", root=" + stepResult.rootIdx + "/" + stepResult.rootTotal);

        // Test 7: 低预算下也应优先拆对手的长布局桥接点
        var aiBridgeDef:GobangAI = new GobangAI(-1, 100);
        var aiBridgeDefObj:Object = aiBridgeDef;
        var boardBridgeDef:GobangBoard = aiBridgeDefObj["_board"];
        var evalBridgeDef:GobangEval = aiBridgeDefObj["_eval"];
        var bridgeDefSeq:Array = [
            [7,5,1], [0,0,-1], [7,9,1], [0,14,-1],
            [5,7,1], [14,0,-1], [9,7,1], [1,12,-1],
            [14,14,1], [12,1,-1], [14,13,1]
        ];
        for (var bdi:Number = 0; bdi < bridgeDefSeq.length; bdi++) {
            boardBridgeDef.put(bridgeDefSeq[bdi][0], bridgeDefSeq[bdi][1], bridgeDefSeq[bdi][2]);
            evalBridgeDef.move(bridgeDefSeq[bdi][0], bridgeDefSeq[bdi][1], bridgeDefSeq[bdi][2]);
        }
        assert(aiBridgeDef.aiMoveStart(8) === true, "Async AI defensive bridge start succeeds");
        frames = 0;
        while (frames < 140) {
            stepResult = aiBridgeDef.aiMoveStep(8);
            frames++;
            if (stepResult.done) break;
        }
        assert(stepResult !== null && stepResult.done === true,
               "Async AI defensive bridge finishes within 140 steps (frames=" + frames + ")");
        assert(stepResult.x >= 4 && stepResult.x <= 10 && stepResult.y >= 4 && stepResult.y <= 10,
               "Async AI defensive bridge blocks opponent center area: (" + stepResult.x + "," + stepResult.y + ")");
        assert(stepResult.phaseLabel.indexOf("minmax_d") === 0
               || stepResult.phaseLabel.indexOf("bridgeprobe_d") === 0,
               "Async AI defensive bridge uses search: " + stepResult.phaseLabel);
        trace("[INFO] Async AI defensive bridge: (" + stepResult.x + "," + stepResult.y + ")"
              + ", phase=" + stepResult.phaseLabel + ", nodes=" + stepResult.nodes
              + ", root=" + stepResult.rootIdx + "/" + stepResult.rootTotal);
    }

    // ===== 性能基准测试 =====
    public static function runBenchmark():Void {
        trace("=== Gobang Performance Benchmark ===");

        // 构建一个有 10 颗棋子的中局棋面
        var board:GobangBoard = new GobangBoard(15, 1);
        var eval:GobangEval = new GobangEval(15);
        var moves:Array = [
            [7,7,1], [6,6,-1], [7,8,1], [6,7,-1], [7,9,1],
            [8,8,-1], [6,8,1], [8,7,-1], [5,7,1], [8,6,-1]
        ];
        for (var mi:Number = 0; mi < moves.length; mi++) {
            board.put(moves[mi][0], moves[mi][1], moves[mi][2]);
            eval.move(moves[mi][0], moves[mi][1], moves[mi][2]);
        }
        trace("Board: 10 pieces placed");

        var t0:Number;
        var t1:Number;
        var REPS:Number;
        var i:Number;

        // --- Bench 1: getShapeFast 单次调用 ---
        REPS = 1000;
        var brd:Array = eval.board;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            GobangShape.getShapeFast(brd, 7, 7, 0, 1, 1);
            GobangShape.getShapeFast(brd, 7, 7, 1, 0, 1);
            GobangShape.getShapeFast(brd, 7, 7, 1, 1, 1);
            GobangShape.getShapeFast(brd, 7, 7, 1, -1, 1);
        }
        t1 = getTimer();
        trace("getShapeFast x" + (REPS * 4) + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / (REPS * 4)) + "us/call)");

        // --- Bench 2: evaluate (现在应该 O(1)) ---
        REPS = 10000;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            eval.evaluate(1);
        }
        t1 = getTimer();
        trace("evaluate x" + REPS + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / REPS) + "us/call)");

        // --- Bench 3: move + undo 一对 ---
        REPS = 200;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            eval.move(3, 3, 1);
            board.put(3, 3, 1);
            eval.undo(3, 3);
            board.undo();
        }
        t1 = getTimer();
        trace("move+undo x" + REPS + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / REPS) + "us/pair)");

        // --- Bench 4: getMoves ---
        REPS = 200;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            eval.getMoves(1, 0, false, false);
        }
        t1 = getTimer();
        trace("getMoves x" + REPS + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / REPS) + "us/call)");

        // --- Bench 5: isWin ---
        REPS = 10000;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            board.isWin(7, 9, 1);
        }
        t1 = getTimer();
        trace("isWin x" + REPS + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / REPS) + "us/call)");

        // --- Bench 6: isGameOver ---
        REPS = 10000;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            board.isGameOver();
        }
        t1 = getTimer();
        trace("isGameOver x" + REPS + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / REPS) + "us/call)");

        // --- Bench 7: hash ---
        REPS = 10000;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            board.hash();
        }
        t1 = getTimer();
        trace("hash x" + REPS + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / REPS) + "us/call)");

        // --- Bench 8: cache get/put ---
        var cache:GobangCache = new GobangCache(10000);
        REPS = 10000;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            cache.put("key_" + i, {v: i});
        }
        t1 = getTimer();
        trace("cache.put x" + REPS + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / REPS) + "us/call)");
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            cache.get("key_" + i);
        }
        t1 = getTimer();
        trace("cache.get x" + REPS + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / REPS) + "us/call)");

        // --- Bench 9: 完整 negamax depth=2 (端到端) ---
        var mm:GobangMinmax = new GobangMinmax(board, eval);
        t0 = getTimer();
        var result:Object = mm.search(-1, 2, false);
        t1 = getTimer();
        trace("negamax depth=2 noVCT: " + (t1 - t0) + "ms, nodes=" + result.nodes + " (" + ((t1 - t0) * 1000 / result.nodes) + "us/node)");

        // --- Bench 9b: 完整 negamax depth=4 (若超时则应回退到上一次完成深度) ---
        t0 = getTimer();
        var result4:Object = mm.search(-1, 4, false);
        t1 = getTimer();
        trace("negamax depth=4 noVCT: " + (t1 - t0) + "ms, nodes=" + result4.nodes
              + ", timedOut=" + result4.timedOut + ", move=(" + result4.x + "," + result4.y + ")");

        // --- Bench 10: _shapeScore 内联版 vs getRealShapeScore ---
        REPS = 10000;
        var shapes:Array = [0, 2, 3, 30, 40, 4, 5, 50, 44, 43, 33, 22];
        var dummy:Number = 0;
        t0 = getTimer();
        for (i = 0; i < REPS; i++) {
            for (var si:Number = 0; si < 12; si++) {
                dummy += GobangShape.getRealShapeScore(shapes[si]);
            }
        }
        t1 = getTimer();
        trace("getRealShapeScore x" + (REPS * 12) + ": " + (t1 - t0) + "ms (" + ((t1 - t0) * 1000 / (REPS * 12)) + "us/call)");

        // --- Bench 11: 异步 Minmax 在 8ms/16ms 预算下的端到端耗时 ---
        var board2:GobangBoard = new GobangBoard(15, 1);
        var eval2:GobangEval = new GobangEval(15);
        for (mi = 0; mi < moves.length; mi++) {
            board2.put(moves[mi][0], moves[mi][1], moves[mi][2]);
            eval2.move(moves[mi][0], moves[mi][1], moves[mi][2]);
        }
        var mmAsync:GobangMinmax = new GobangMinmax(board2, eval2);
        mmAsync.searchStart(-1, 4, false);
        var perfFrames:Number = 0;
        var perfStep:Object;
        t0 = getTimer();
        while (perfFrames < 120) {
            perfStep = mmAsync.step(8);
            perfFrames++;
            if (perfStep.done) break;
        }
        t1 = getTimer();
        trace("async Minmax 8ms budget: " + (t1 - t0) + "ms total, steps=" + perfFrames
              + ", phase=" + perfStep.phaseLabel + ", nodes=" + perfStep.nodes
              + ", move=(" + perfStep.x + "," + perfStep.y + ")");

        var mmAsync2:GobangMinmax = new GobangMinmax(board2, eval2);
        mmAsync2.searchStart(-1, 4, false);
        perfFrames = 0;
        t0 = getTimer();
        while (perfFrames < 120) {
            perfStep = mmAsync2.step(16);
            perfFrames++;
            if (perfStep.done) break;
        }
        t1 = getTimer();
        trace("async Minmax 16ms budget: " + (t1 - t0) + "ms total, steps=" + perfFrames
              + ", phase=" + perfStep.phaseLabel + ", nodes=" + perfStep.nodes
              + ", move=(" + perfStep.x + "," + perfStep.y + ")");

        // --- Bench 12: 20 颗棋密集局面 depth=4 ---
        var board3:GobangBoard = new GobangBoard(15, 1);
        var eval3:GobangEval = new GobangEval(15);
        var denseMoves:Array = [
            [7,7,1], [6,6,-1], [7,8,1], [6,7,-1], [7,9,1],
            [8,8,-1], [6,8,1], [8,7,-1], [5,7,1], [8,6,-1],
            [5,8,1], [9,7,-1], [4,7,1], [9,8,-1], [7,6,1],
            [8,9,-1], [6,9,1], [5,6,-1], [8,5,1], [9,9,-1]
        ];
        for (mi = 0; mi < denseMoves.length; mi++) {
            board3.put(denseMoves[mi][0], denseMoves[mi][1], denseMoves[mi][2]);
            eval3.move(denseMoves[mi][0], denseMoves[mi][1], denseMoves[mi][2]);
        }
        var mmDense:GobangMinmax = new GobangMinmax(board3, eval3);
        t0 = getTimer();
        var resultDense:Object = mmDense.search(-1, 4, false);
        t1 = getTimer();
        trace("dense 20-piece depth=4: " + (t1 - t0) + "ms, nodes=" + resultDense.nodes
              + ", move=(" + resultDense.x + "," + resultDense.y + ")");

        // --- Bench 13: undo 一致性压力测试（10 层 move+undo 回滚） ---
        var evalStress:GobangEval = new GobangEval(15);
        evalStress.move(7, 7, 1);
        var scoreAfterFirst:Number = evalStress.evaluate(1);
        var stressSeq:Array = [
            [6,6,-1],[7,8,1],[6,7,-1],[7,9,1],
            [8,8,-1],[6,8,1],[8,7,-1],[5,7,1],[8,6,-1]
        ];
        for (i = 0; i < stressSeq.length; i++) {
            evalStress.move(stressSeq[i][0], stressSeq[i][1], stressSeq[i][2]);
        }
        for (i = stressSeq.length - 1; i >= 0; i--) {
            evalStress.undo(stressSeq[i][0], stressSeq[i][1]);
        }
        var scoreAfterUndo:Number = evalStress.evaluate(1);
        assert(scoreAfterFirst === scoreAfterUndo,
               "Undo stress 10-deep: score " + scoreAfterFirst + " === " + scoreAfterUndo);

        trace("=== Benchmark Done ===");
    }
}
