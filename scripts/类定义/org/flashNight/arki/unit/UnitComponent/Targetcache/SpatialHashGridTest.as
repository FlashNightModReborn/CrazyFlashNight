import org.flashNight.arki.unit.UnitComponent.Targetcache.SpatialHashGrid;

/**
 * SpatialHashGrid Test Suite
 * Usage: SpatialHashGridTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.SpatialHashGridTest {

    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    private static function assertEquals(name:String, expected:Number, actual:Number, tol:Number):Void {
        testCount++;
        if (isNaN(tol)) tol = 0;
        var d:Number = expected - actual;
        if (d < 0) d = -d;
        if (d <= tol) {
            passedTests++;
            trace("  [PASS] " + name + " (exp=" + expected + " act=" + actual + ")");
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (exp=" + expected + " act=" + actual + " d=" + d + ")");
        }
    }

    private static function assertTrue(name:String, cond:Boolean):Void {
        testCount++;
        if (cond) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name);
        }
    }

    private static function makeUnit(id:Number, cx:Number, cy:Number, halfW:Number):Object {
        if (isNaN(halfW)) halfW = 8;
        return {
            _name: "u_" + id,
            hp: 100,
            maxhp: 100,
            Z轴坐标: cy,
            aabbCollider: {
                left: cx - halfW,
                right: cx + halfW,
                top: cy - 20,
                bottom: cy + 20
            }
        };
    }

    public static function runAll():Void {
        trace("================================================================");
        trace("SpatialHashGrid Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testConstruction();
        testInsertAndClear();
        testRebuildFromUnits();
        testQueryRect();
        testQueryCircle();
        testQueryNearest();
        testCountInCircle();
        testEdgeCases();
        testCellBoundary();
        testLargeScale();
        testFilterFunction();
        testPerformanceBenchmark();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
    }

    private static function testConstruction():Void {
        trace("\n--- testConstruction ---");
        var g:SpatialHashGrid = new SpatialHashGrid(50, 274, 1638, 366, 200, 200);
        var s:Object = g.getStats();
        assertEquals("cols", 9, s.cols, 0);
        assertEquals("rows", 2, s.rows, 0);
        assertEquals("cellCount", 18, s.cellCount, 0);
        assertEquals("unitCount", 0, s.unitCount, 0);
    }

    private static function testInsertAndClear():Void {
        trace("\n--- testInsertAndClear ---");
        var g:SpatialHashGrid = new SpatialHashGrid(0, 0, 1000, 500, 200, 200);

        g.insert(makeUnit(1, 100, 100), 100, 100);
        g.insert(makeUnit(2, 300, 300), 300, 300);
        g.insert(makeUnit(3, 900, 400), 900, 400);
        assertEquals("insertCount", 3, g.getStats().unitCount, 0);

        g.clear();
        assertEquals("afterClear", 0, g.getStats().unitCount, 0);

        var r:Array = g.queryRect(0, 0, 1000, 500);
        assertEquals("emptyQueryLen", 0, r.length, 0);
    }

    private static function testRebuildFromUnits():Void {
        trace("\n--- testRebuildFromUnits ---");
        var g:SpatialHashGrid = new SpatialHashGrid(50, 274, 1638, 366, 200, 200);
        var units:Array = [];
        units.push(makeUnit(0, 200, 350));
        units.push(makeUnit(1, 500, 400));
        units.push(makeUnit(2, 800, 500));
        units.push(makeUnit(3, 1200, 300));
        units.push(makeUnit(4, 1600, 600));

        g.rebuildFromUnits(units);
        assertEquals("rebuildCount", 5, g.getStats().unitCount, 0);

        var units2:Array = [];
        units2.push(makeUnit(10, 100, 300));
        g.rebuildFromUnits(units2);
        assertEquals("rebuildReplace", 1, g.getStats().unitCount, 0);
    }

    private static function testQueryRect():Void {
        trace("\n--- testQueryRect ---");
        var g:SpatialHashGrid = new SpatialHashGrid(0, 0, 1000, 600, 200, 200);

        g.insert(makeUnit(1, 100, 100), 100, 100);
        g.insert(makeUnit(2, 800, 100), 800, 100);
        g.insert(makeUnit(3, 100, 500), 100, 500);
        g.insert(makeUnit(4, 800, 500), 800, 500);

        var r1:Array = g.queryRect(0, 0, 500, 600);
        assertEquals("leftHalf", 2, r1.length, 0);

        var r2:Array = g.queryRect(0, 0, 1000, 600);
        assertEquals("fullMap", 4, r2.length, 0);

        var r3:Array = g.queryRect(400, 200, 600, 400);
        assertEquals("emptyArea", 0, r3.length, 0);

        var r4:Array = g.queryRect(750, 50, 850, 150);
        assertEquals("singleHit", 1, r4.length, 0);
    }

    private static function testQueryCircle():Void {
        trace("\n--- testQueryCircle ---");
        var g:SpatialHashGrid = new SpatialHashGrid(0, 0, 1000, 600, 200, 200);

        g.insert(makeUnit(0, 500, 300), 500, 300);
        g.insert(makeUnit(1, 600, 300), 600, 300);
        g.insert(makeUnit(2, 800, 500), 800, 500);

        var r1:Array = g.queryCircle(500, 300, 150);
        assertEquals("circle150", 2, r1.length, 0);

        var r2:Array = g.queryCircle(500, 300, 50);
        assertEquals("circle50", 1, r2.length, 0);

        var r3:Array = g.queryCircle(500, 300, 500);
        assertEquals("circle500", 3, r3.length, 0);

        var r4:Array = g.queryCircle(500, 300, 0);
        assertEquals("circleZero", 0, r4.length, 0);
    }

    private static function testQueryNearest():Void {
        trace("\n--- testQueryNearest ---");
        var g:SpatialHashGrid = new SpatialHashGrid(0, 0, 1000, 600, 200, 200);

        var u1:Object = makeUnit(1, 100, 100);
        var u2:Object = makeUnit(2, 200, 100);
        var u3:Object = makeUnit(3, 500, 300);

        g.insert(u1, 100, 100);
        g.insert(u2, 200, 100);
        g.insert(u3, 500, 300);

        var nearest:Object = g.queryNearest(150, 100, 300, null);
        assertTrue("nearestExists", nearest != null);

        var nearest2:Object = g.queryNearest(500, 300, 1000, u3);
        assertTrue("nearestExcludeSelf", nearest2 != null && nearest2 != u3);

        var g2:SpatialHashGrid = new SpatialHashGrid(0, 0, 100, 100, 50, 50);
        var nearest4:Object = g2.queryNearest(50, 50, 100, null);
        assertTrue("nearestEmpty", nearest4 == null);
    }

    private static function testCountInCircle():Void {
        trace("\n--- testCountInCircle ---");
        var g:SpatialHashGrid = new SpatialHashGrid(0, 0, 1000, 600, 200, 200);

        for (var i:Number = 0; i < 10; i++) {
            g.insert(makeUnit(i, 100 + i * 80, 300), 100 + i * 80, 300);
        }

        var c:Number = g.countInCircle(400, 300, 200);
        assertEquals("countCircle200", 6, c, 1);
        assertEquals("countCircleZero", 0, g.countInCircle(400, 300, 0), 0);
    }

    private static function testEdgeCases():Void {
        trace("\n--- testEdgeCases ---");
        var g:SpatialHashGrid = new SpatialHashGrid(0, 0, 100, 100, 50, 50);

        assertEquals("emptyRect", 0, g.queryRect(0, 0, 100, 100).length, 0);
        assertEquals("emptyCircle", 0, g.queryCircle(50, 50, 100).length, 0);
        assertEquals("emptyCount", 0, g.countInCircle(50, 50, 100), 0);

        g.insert(makeUnit(0, 50, 50), 50, 50);
        assertEquals("singleUnit", 1, g.queryRect(0, 0, 100, 100).length, 0);

        var g2:SpatialHashGrid = new SpatialHashGrid(0, 0, 100, 100, 50, 50);
        g2.insert(makeUnit(1, -50, -50), -50, -50);
        g2.insert(makeUnit(2, 200, 200), 200, 200);
        assertEquals("outOfBoundsInsert", 2, g2.getStats().unitCount, 0);
    }

    private static function testCellBoundary():Void {
        trace("\n--- testCellBoundary ---");
        var g:SpatialHashGrid = new SpatialHashGrid(0, 0, 300, 300, 100, 100);

        g.insert(makeUnit(1, 99, 50), 99, 50);
        g.insert(makeUnit(2, 100, 50), 100, 50);

        var r1:Array = g.queryRect(0, 0, 99, 100);
        assertEquals("boundary_leftCell", 1, r1.length, 0);

        var r2:Array = g.queryRect(100, 0, 200, 100);
        assertEquals("boundary_rightCell", 1, r2.length, 0);

        var r3:Array = g.queryRect(50, 0, 150, 100);
        assertEquals("boundary_cross", 2, r3.length, 0);
    }

    private static function testLargeScale():Void {
        trace("\n--- testLargeScale ---");
        var g:SpatialHashGrid = new SpatialHashGrid(50, 274, 1638, 366, 200, 200);
        var units:Array = [];
        var n:Number = 200;

        for (var i:Number = 0; i < n; i++) {
            var cx:Number = 50 + Math.random() * 1638;
            var cy:Number = 274 + Math.random() * 366;
            units.push(makeUnit(i, cx, cy));
        }

        g.rebuildFromUnits(units);
        assertEquals("largeInsert", n, g.getStats().unitCount, 0);

        var all:Array = g.queryRect(0, 0, 2000, 1000);
        assertEquals("largeFullQuery", n, all.length, 0);
    }

    private static function testFilterFunction():Void {
        trace("\n--- testFilterFunction ---");
        var g:SpatialHashGrid = new SpatialHashGrid(0, 0, 1000, 600, 200, 200);

        for (var i:Number = 0; i < 10; i++) {
            var u:Object = makeUnit(i, 100 + i * 80, 300);
            u.hp = (i < 5) ? 30 : 100;
            g.insert(u, 100 + i * 80, 300);
        }

        var lowHP:Function = function(unit:Object):Boolean {
            return unit.hp < 50;
        };

        var r:Array = g.queryCircle(400, 300, 500, lowHP);
        assertEquals("filterLowHP", 5, r.length, 0);

        var r2:Array = g.queryRect(0, 0, 1000, 600, lowHP);
        assertEquals("filterRectLowHP", 5, r2.length, 0);
    }

    private static function testPerformanceBenchmark():Void {
        trace("\n--- testPerformanceBenchmark ---");
        var g:SpatialHashGrid = new SpatialHashGrid(50, 274, 1638, 366, 200, 200);
        var units:Array = [];
        var n:Number = 100;

        for (var i:Number = 0; i < n; i++) {
            units.push(makeUnit(i, 50 + Math.random() * 1638, 274 + Math.random() * 366));
        }

        // rebuild benchmark
        var trials:Number = 1000;
        var t0:Number = getTimer();
        for (var rb:Number = 0; rb < trials; rb++) {
            g.rebuildFromUnits(units);
        }
        var rebuildMs:Number = (getTimer() - t0);
        trace("  [PERF] rebuild " + n + " units x" + trials + ": " + rebuildMs + "ms (" + (rebuildMs / trials) + "ms/call)");
        assertTrue("rebuild<1ms", (rebuildMs / trials) < 1);

        // queryCircle benchmark
        trials = 5000;
        t0 = getTimer();
        for (var qc:Number = 0; qc < trials; qc++) {
            g.queryCircle(50 + Math.random() * 1638, 274 + Math.random() * 366, 150);
        }
        var circleMs:Number = (getTimer() - t0);
        trace("  [PERF] queryCircle x" + trials + ": " + circleMs + "ms (" + (circleMs / trials) + "ms/call)");
        assertTrue("queryCircle<0.1ms", (circleMs / trials) < 0.1);

        // queryRect benchmark
        trials = 5000;
        t0 = getTimer();
        for (var qr:Number = 0; qr < trials; qr++) {
            var rx:Number = 50 + Math.random() * 1438;
            var ry:Number = 274 + Math.random() * 166;
            g.queryRect(rx, ry, rx + 200, ry + 200);
        }
        var rectMs:Number = (getTimer() - t0);
        trace("  [PERF] queryRect x" + trials + ": " + rectMs + "ms (" + (rectMs / trials) + "ms/call)");
        assertTrue("queryRect<0.1ms", (rectMs / trials) < 0.1);

        // queryNearest benchmark
        trials = 5000;
        t0 = getTimer();
        for (var qn:Number = 0; qn < trials; qn++) {
            g.queryNearest(50 + Math.random() * 1638, 274 + Math.random() * 366, 300, null);
        }
        var nearMs:Number = (getTimer() - t0);
        trace("  [PERF] queryNearest x" + trials + ": " + nearMs + "ms (" + (nearMs / trials) + "ms/call)");
        assertTrue("queryNearest<0.15ms", (nearMs / trials) < 0.15);

        // countInCircle benchmark
        trials = 5000;
        t0 = getTimer();
        for (var qi:Number = 0; qi < trials; qi++) {
            g.countInCircle(50 + Math.random() * 1638, 274 + Math.random() * 366, 150);
        }
        var countMs:Number = (getTimer() - t0);
        trace("  [PERF] countInCircle x" + trials + ": " + countMs + "ms (" + (countMs / trials) + "ms/call)");
        assertTrue("countInCircle<0.1ms", (countMs / trials) < 0.1);

        // brute-force correctness validation
        trace("\n  --- Brute-force validation ---");
        g.rebuildFromUnits(units);
        var vcx:Number = 869;
        var vcy:Number = 457;
        var vr:Number = 200;
        var vr2:Number = vr * vr;
        var bruteCount:Number = 0;
        for (var b:Number = 0; b < units.length; b++) {
            var bu:Object = units[b];
            var bx:Number = (bu.aabbCollider.left + bu.aabbCollider.right) * 0.5;
            var by:Number = bu.Z轴坐标;
            var ddx:Number = bx - vcx;
            var ddy:Number = by - vcy;
            if (ddx * ddx + ddy * ddy <= vr2) bruteCount++;
        }
        var gridResult:Array = g.queryCircle(vcx, vcy, vr);
        assertEquals("bruteForceMatch", bruteCount, gridResult.length, 0);
    }
}
