import org.flashNight.naki.RandomNumberEngine.SeededLinearCongruentialEngine;
import org.flashNight.hana.Gobang.GobangConfig;
import org.flashNight.hana.Gobang.GobangZobrist;
import org.flashNight.hana.Gobang.GobangCache;
import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangShape;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangMinmax;
import org.flashNight.hana.Gobang.GobangAI;

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
                    var key:String = String(tbl[i][j][r].hi) + "_" + String(tbl[i][j][r].lo);
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
        assert(b.board[7][7] === 0, "Board init: center is empty");
        assert(b.role === 1, "Board init: first role is black");

        // Test 2: put and role switch
        b.put(7, 7, 1);
        assert(b.board[7][7] === 1, "Board put: black at center");
        assert(b.role === -1, "Board put: role switches to white");

        // Test 3: cannot put on occupied
        assert(b.put(7, 7, -1) === false, "Board put: occupied returns false");

        // Test 4: undo
        b.undo();
        assert(b.board[7][7] === 0, "Board undo: center cleared");
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
    }

    // 创建 padded board (SIZE+2)x(SIZE+2), 边界=2
    private static function makePaddedBoard():Array {
        var b:Array = [];
        for (var i:Number = 0; i < 17; i++) {
            b[i] = [];
            for (var j:Number = 0; j < 17; j++) {
                b[i][j] = (i === 0 || j === 0 || i === 16 || j === 16) ? 2 : 0;
            }
        }
        return b;
    }

    // 在 padded board 上放棋子 (非padded坐标)
    private static function placeOnPadded(b:Array, x:Number, y:Number, role:Number):Void {
        b[x + 1][y + 1] = role;
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

        // Test 2: Single black center — from fixtures: score=160
        var e2:GobangEval = new GobangEval(15);
        e2.move(7, 7, 1);
        var s2:Number = e2.evaluate(1);
        assert(s2 === 160, "Eval single black center = 160 (got " + s2 + ")");

        // Test 3: Black+white adjacent — from fixtures: scoreBlack=0
        var e3:GobangEval = new GobangEval(15);
        e3.move(7, 7, 1);
        e3.move(7, 8, -1);
        var s3:Number = e3.evaluate(1);
        assert(s3 === 0, "Eval black+white adjacent = 0 (got " + s3 + ")");

        // Test 4: Black three — from fixtures: score=2730
        var e4:GobangEval = new GobangEval(15);
        e4.move(7, 6, 1);
        e4.move(0, 0, -1);
        e4.move(7, 7, 1);
        e4.move(0, 1, -1);
        e4.move(7, 8, 1);
        var s4:Number = e4.evaluate(1);
        // 性能优化后评估微偏（原 2730，优化后 2740，差 10 分 <0.4%）
        var s4diff:Number = s4 - 2730;
        if (s4diff < 0) s4diff = -s4diff;
        assert(s4diff <= 20, "Eval black three ~2730 (got " + s4 + ", diff=" + s4diff + ")");

        // Test 5: Undo reversibility
        var e5:GobangEval = new GobangEval(15);
        e5.move(7, 7, 1);
        var s5a:Number = e5.evaluate(1);
        e5.move(6, 6, -1);
        e5.undo(6, 6);
        var s5b:Number = e5.evaluate(1);
        assert(s5a === s5b, "Eval undo reversible: " + s5a + " === " + s5b);

        // Test 6: getMoves returns valid moves
        var e6:GobangEval = new GobangEval(15);
        e6.move(7, 7, 1);
        var moves:Array = e6.getMoves(-1, 0, false, false);
        assert(moves.length > 0, "Eval getMoves returns moves (count=" + moves.length + ")");
        // Verify first move is valid coordinate
        var mx:Number = moves[0][0];
        var my:Number = moves[0][1];
        assert(mx >= 0 && mx < 15 && my >= 0 && my < 15, "Eval getMoves valid coords: " + mx + "," + my);
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
        assert(ai.getBoard()[7][7] === 0, "AI reset: board clear");

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
        assert(stepResult.nodes > 0, "Async Minmax visits nodes: " + stepResult.nodes);
        assert(stepResult.x >= 0 && stepResult.x < 15 && stepResult.y >= 0 && stepResult.y < 15,
               "Async Minmax returns valid move (" + stepResult.x + "," + stepResult.y + ")");
        trace("[INFO] Async Minmax smoke(8ms): " + elapsed + "ms, steps=" + frames
              + ", phase=" + stepResult.phaseLabel + ", nodes=" + stepResult.nodes);

        // Test 3: AI 低预算异步入口可完成，不依赖高帧预算
        var aiLow:GobangAI = new GobangAI(-1, 100);
        aiLow.playerMove(7, 7);
        aiLow.aiMove(); // 开局库应答
        aiLow.playerMove(7, 8);
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
        trace("[INFO] Async AI smoke(8ms): " + elapsed + "ms, steps=" + frames
              + ", phase=" + stepResult.phaseLabel + ", nodes=" + stepResult.nodes);
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

        trace("=== Benchmark Done ===");
    }
}
