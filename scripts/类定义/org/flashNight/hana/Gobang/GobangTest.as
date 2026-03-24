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
        var result:Array = GobangShape.getShapeFast(b, x, y, ox, oy, role);
        var shape:Number = result[0];
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
        assert(s4 === 2730, "Eval black three = 2730 (got " + s4 + ")");

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
        var moves:Array = e6.getMoves(-1, 0);
        assert(moves.length > 0, "Eval getMoves returns moves (count=" + moves.length + ")");
        // Verify first move is valid coordinate
        var mx:Number = moves[0][0];
        var my:Number = moves[0][1];
        assert(mx >= 0 && mx < 15 && my >= 0 && my < 15, "Eval getMoves valid coords: " + mx + "," + my);
    }

    private static function testMinmax():Void {
        trace("--- testMinmax ---");

        // Test 1: Depth 2 search from opening
        var b1:GobangBoard = new GobangBoard(15, 1);
        var ev1:GobangEval = new GobangEval(15);
        b1.put(7, 7, 1); ev1.move(7, 7, 1);
        var mm1:GobangMinmax = new GobangMinmax(b1, ev1);
        var r1:Object = mm1.search(-1, 2);
        assert(r1.x >= 0 && r1.x < 15 && r1.y >= 0 && r1.y < 15,
               "Minmax depth=2: valid move (" + r1.x + "," + r1.y + ") nodes=" + r1.nodes);

        // Test 2: Must block — black has 4 in a row, white must block
        var b2:GobangBoard = new GobangBoard(15, 1);
        var ev2:GobangEval = new GobangEval(15);
        // Black: (7,5),(7,6),(7,7),(7,8) — open four
        b2.put(7, 5, 1); ev2.move(7, 5, 1);
        b2.put(0, 0, -1); ev2.move(0, 0, -1);
        b2.put(7, 6, 1); ev2.move(7, 6, 1);
        b2.put(0, 1, -1); ev2.move(0, 1, -1);
        b2.put(7, 7, 1); ev2.move(7, 7, 1);
        b2.put(0, 2, -1); ev2.move(0, 2, -1);
        b2.put(7, 8, 1); ev2.move(7, 8, 1);
        // White must play at (7,4) or (7,9) to block
        var mm2:GobangMinmax = new GobangMinmax(b2, ev2);
        var r2:Object = mm2.search(-1, 2);
        var isBlock:Boolean = (r2.x === 7 && (r2.y === 4 || r2.y === 9));
        assert(isBlock, "Minmax must block open four: (" + r2.x + "," + r2.y + ")");

        // Test 3: Must win — black has open four, find winning move
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
        // Black's turn with open four — should play (7,4) or (7,9)
        var mm3:GobangMinmax = new GobangMinmax(b3, ev3);
        var r3:Object = mm3.search(1, 2);
        var isWinMove:Boolean = (r3.x === 7 && (r3.y === 4 || r3.y === 9));
        assert(isWinMove, "Minmax find winning move: (" + r3.x + "," + r3.y + ") score=" + r3.score);

        // Test 4: Timeout does not crash (depth=4)
        var b4:GobangBoard = new GobangBoard(15, 1);
        var ev4:GobangEval = new GobangEval(15);
        b4.put(7, 7, 1); ev4.move(7, 7, 1);
        var mm4:GobangMinmax = new GobangMinmax(b4, ev4);
        var t0:Number = getTimer();
        var r4:Object = mm4.search(-1, 4);
        var elapsed:Number = getTimer() - t0;
        assert(r4.x >= 0 && r4.x < 15, "Minmax depth=4: valid move (" + r4.x + "," + r4.y + ") " + elapsed + "ms nodes=" + r4.nodes);
    }

    private static function testAI():Void {
        trace("--- testAI ---");
        // 使用 depth=2 以保持测试速度
        GobangConfig.searchDepth = 2;

        // Test 1: Basic flow — player move then AI move
        var ai:GobangAI = new GobangAI(-1); // AI 执白
        assert(ai.playerMove(7, 7) === true, "AI playerMove succeeds");
        var aiResult:Object = ai.aiMove();
        assert(aiResult !== null, "AI aiMove returns result");
        assert(aiResult.x >= 0 && aiResult.x < 15 && aiResult.y >= 0 && aiResult.y < 15,
               "AI aiMove valid coords: (" + aiResult.x + "," + aiResult.y + ")");

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

        // 恢复默认深度
        GobangConfig.searchDepth = 4;
    }
}