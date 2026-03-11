import org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache;
import org.flashNight.arki.unit.UnitComponent.Targetcache.SpatialHashGrid;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/**
 * SortedUnitCache 2D Integration Test Suite
 * Tests lazy grid construction and 2D query delegation.
 * Usage: SortedUnitCache2DTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache2DTest {

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

    /**
     * Create a mock unit with AABB centered at (cx, cy).
     * Mimics real unit structure: aabbCollider.left/right/top/bottom, Z轴坐标, hp, _name
     */
    private static function makeUnit(id:Number, cx:Number, cy:Number, halfW:Number):Object {
        if (isNaN(halfW)) halfW = 8;
        return {
            _name: "u2d_" + id,
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

    /**
     * Build a SortedUnitCache from an array of units (simulating TargetCacheUpdater output).
     * Units are sorted by aabbCollider.left, parallel arrays pre-fetched.
     */
    private static function buildCache(units:Array):SortedUnitCache {
        // Sort by left
        units.sort(function(a, b) {
            return a.aabbCollider.left - b.aabbCollider.left;
        });

        var len:Number = units.length;
        var leftValues:Array = new Array(len);
        var rightValues:Array = new Array(len);
        var nameIndex:Object = {};

        for (var i:Number = 0; i < len; i++) {
            leftValues[i] = units[i].aabbCollider.left;
            rightValues[i] = units[i].aabbCollider.right;
            nameIndex[units[i]._name] = i;
        }

        return new SortedUnitCache(units, nameIndex, leftValues, rightValues, 1);
    }

    // ========================================================================
    // Test runner
    // ========================================================================

    public static function runAll():Void {
        trace("================================================================");
        trace("SortedUnitCache 2D Integration Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        // Configure grid for test map
        SortedUnitCache.configureGrid(0, 0, 1000, 600, 200, 200);

        testLazyConstruction();
        testQueryCircle2D();
        testQueryRect2D();
        testQueryNearest2D();
        testCountInCircle2D();
        testGridInvalidation();
        testSnapshotSemanticsWithinCacheLifetime();
        testGridReconfigureRebuildsExistingCache();
        testAutoBoundsResizeOnDataChange();
        testResetGridConfig();
        testCrossQueryResultIsolation();
        testManagerEmpty2DResultSelfHeals();
        testManagerEmpty2DIndependentReferences();
        testFilterFunction2D();
        testEmptyCache2D();
        testRebuildFromParallelArrays();
        testParallelArraysPerformance();
        testLazyBuildPerformance();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
    }

    // ========================================================================
    // Test cases
    // ========================================================================

    private static function testLazyConstruction():Void {
        trace("\n--- testLazyConstruction ---");
        var units:Array = [makeUnit(0, 500, 300)];
        var cache:SortedUnitCache = buildCache(units);

        // Grid should not exist yet (lazy)
        // We can't directly check _grid (private), but getGrid() should create it
        var grid:SpatialHashGrid = cache.getGrid();
        assertTrue("gridCreated", grid != null);
        assertEquals("gridUnitCount", 1, grid.getStats().unitCount, 0);
    }

    private static function testQueryCircle2D():Void {
        trace("\n--- testQueryCircle2D ---");
        var units:Array = [];
        units.push(makeUnit(0, 200, 200));
        units.push(makeUnit(1, 300, 200));
        units.push(makeUnit(2, 800, 500));

        var cache:SortedUnitCache = buildCache(units);

        var r1:Array = cache.queryCircle2D(250, 200, 100, null);
        assertEquals("circle_near2", 2, r1.length, 0);

        var r2:Array = cache.queryCircle2D(250, 200, 10, null);
        assertEquals("circle_tight", 0, r2.length, 0);

        var r3:Array = cache.queryCircle2D(500, 300, 1000, null);
        assertEquals("circle_all", 3, r3.length, 0);
    }

    private static function testQueryRect2D():Void {
        trace("\n--- testQueryRect2D ---");
        var units:Array = [];
        units.push(makeUnit(0, 100, 100));
        units.push(makeUnit(1, 500, 300));
        units.push(makeUnit(2, 900, 500));

        var cache:SortedUnitCache = buildCache(units);

        var r1:Array = cache.queryRect2D(0, 0, 600, 400, null);
        assertEquals("rect_topLeft", 2, r1.length, 0);

        var r2:Array = cache.queryRect2D(800, 400, 1000, 600, null);
        assertEquals("rect_bottomRight", 1, r2.length, 0);

        var r3:Array = cache.queryRect2D(0, 0, 1000, 600, null);
        assertEquals("rect_all", 3, r3.length, 0);

        var r4:Array = cache.queryRect2D(300, 400, 400, 500, null);
        assertEquals("rect_empty", 0, r4.length, 0);
    }

    private static function testQueryNearest2D():Void {
        trace("\n--- testQueryNearest2D ---");
        var u0:Object = makeUnit(0, 100, 100);
        var u1:Object = makeUnit(1, 200, 100);
        var u2:Object = makeUnit(2, 500, 300);
        var units:Array = [u0, u1, u2];

        var cache:SortedUnitCache = buildCache(units);

        var nearest:Object = cache.queryNearest2D(150, 100, 200, null, null);
        assertTrue("nearest_exists", nearest != null);

        // Exclude u0, should find u1
        var nearest2:Object = cache.queryNearest2D(100, 100, 200, u0, null);
        assertTrue("nearest_excludeSelf", nearest2 == u1);

        // Very small radius, nothing found
        var nearest3:Object = cache.queryNearest2D(400, 400, 10, null, null);
        assertTrue("nearest_miss", nearest3 == null);
    }

    private static function testCountInCircle2D():Void {
        trace("\n--- testCountInCircle2D ---");
        var units:Array = [];
        for (var i:Number = 0; i < 10; i++) {
            units.push(makeUnit(i, 100 + i * 80, 300));
        }
        var cache:SortedUnitCache = buildCache(units);

        var c1:Number = cache.countInCircle2D(400, 300, 200);
        assertEquals("count_circle200", 6, c1, 1);

        var c2:Number = cache.countInCircle2D(400, 300, 0);
        assertEquals("count_zero", 0, c2, 0);
    }

    private static function testGridInvalidation():Void {
        trace("\n--- testGridInvalidation ---");
        var units:Array = [makeUnit(0, 100, 100), makeUnit(1, 200, 200)];
        var cache:SortedUnitCache = buildCache(units);

        // First query — builds grid
        assertEquals("before_count", 2, cache.countInCircle2D(150, 150, 200), 0);

        // 记住 grid 引用，后续验证实例复用
        var gridBefore:SpatialHashGrid = cache.getGrid();

        // Simulate data update (new data with 3 units)
        var newUnits:Array = [makeUnit(10, 300, 300), makeUnit(11, 400, 400), makeUnit(12, 500, 500)];
        newUnits.sort(function(a, b) {
            return a.aabbCollider.left - b.aabbCollider.left;
        });

        var newLeft:Array = [];
        var newRight:Array = [];
        var newIdx:Object = {};
        for (var i:Number = 0; i < newUnits.length; i++) {
            newLeft[i] = newUnits[i].aabbCollider.left;
            newRight[i] = newUnits[i].aabbCollider.right;
            newIdx[newUnits[i]._name] = i;
        }

        cache.updateData(newUnits, newIdx, newLeft, newRight, 2);

        // After update, grid should rebuild on next query with new data
        assertEquals("after_count", 3, cache.queryCircle2D(400, 400, 500, null).length, 0);

        // P5 核心验证：数据更新后 grid 实例应被复用（同一引用），而非重新 new
        var gridAfter:SpatialHashGrid = cache.getGrid();
        assertTrue("gridInstanceReused", gridBefore == gridAfter);
    }

    private static function testSnapshotSemanticsWithinCacheLifetime():Void {
        trace("\n--- testSnapshotSemanticsWithinCacheLifetime ---");
        SortedUnitCache.configureGrid(0, 0, 800, 800, 100, 100);

        var mover:Object = makeUnit(20, 100, 100);
        var cache:SortedUnitCache = buildCache([mover]);

        assertEquals("snapshot_cache_beforeMove", 1, cache.queryCircle2D(100, 100, 20, null).length, 0);

        mover.aabbCollider.left = 492;
        mover.aabbCollider.right = 508;
        mover.Z轴坐标 = 500;

        assertEquals("snapshot_cache_oldPos", 1, cache.queryCircle2D(100, 100, 20, null).length, 0);
        assertEquals("snapshot_cache_newPos", 0, cache.queryCircle2D(500, 500, 20, null).length, 0);
    }

    private static function testGridReconfigureRebuildsExistingCache():Void {
        trace("\n--- testGridReconfigureRebuildsExistingCache ---");
        SortedUnitCache.configureGrid(0, 0, 1000, 600, 200, 200);

        var cache:SortedUnitCache = buildCache([makeUnit(30, 100, 100)]);
        var grid1:SpatialHashGrid = cache.getGrid();
        var stats1:Object = grid1.getStats();
        assertEquals("reconfig_before_cols", 5, stats1.cols, 0);

        SortedUnitCache.configureGrid(0, 0, 1000, 600, 100, 100);
        var grid2:SpatialHashGrid = cache.getGrid();
        var stats2:Object = grid2.getStats();

        assertTrue("reconfig_gridRebuilt", grid1 != grid2);
        assertEquals("reconfig_after_cols", 10, stats2.cols, 0);
        assertEquals("reconfig_after_rows", 6, stats2.rows, 0);
    }

    private static function testAutoBoundsResizeOnDataChange():Void {
        trace("\n--- testAutoBoundsResizeOnDataChange ---");
        SortedUnitCache.configureGrid(NaN, NaN, NaN, NaN, 100, 100);

        var cache:SortedUnitCache = buildCache([makeUnit(40, 100, 100)]);
        var grid1:SpatialHashGrid = cache.getGrid();
        var stats1:Object = grid1.getStats();
        assertEquals("autoBounds_before_cols", 1, stats1.cols, 0);

        var movedUnits:Array = [makeUnit(41, 100, 100), makeUnit(42, 420, 100)];
        movedUnits.sort(function(a, b) {
            return a.aabbCollider.left - b.aabbCollider.left;
        });

        var movedLeft:Array = [];
        var movedRight:Array = [];
        var movedIdx:Object = {};
        for (var i:Number = 0; i < movedUnits.length; i++) {
            movedLeft[i] = movedUnits[i].aabbCollider.left;
            movedRight[i] = movedUnits[i].aabbCollider.right;
            movedIdx[movedUnits[i]._name] = i;
        }

        cache.updateData(movedUnits, movedIdx, movedLeft, movedRight, 3);

        var farHits:Array = cache.queryCircle2D(420, 100, 30, null);
        var grid2:SpatialHashGrid = cache.getGrid();
        var stats2:Object = grid2.getStats();

        assertEquals("autoBounds_farQuery", 1, farHits.length, 0);
        assertTrue("autoBounds_gridRebuilt", grid1 != grid2);
        assertTrue("autoBounds_colsExpanded", stats2.cols > stats1.cols);

        SortedUnitCache.configureGrid(0, 0, 1000, 600, 200, 200);
    }

    private static function testResetGridConfig():Void {
        trace("\n--- testResetGridConfig ---");
        // 先显式配置
        SortedUnitCache.configureGrid(0, 0, 1000, 600, 200, 200);
        var cache:SortedUnitCache = buildCache([makeUnit(60, 100, 100)]);
        var grid1:SpatialHashGrid = cache.getGrid();
        var stats1:Object = grid1.getStats();
        assertEquals("reset_before_cols", 5, stats1.cols, 0);

        // 重置为自动模式
        SortedUnitCache.resetGridConfig();
        var grid2:SpatialHashGrid = cache.getGrid();
        assertTrue("reset_gridRebuilt", grid1 != grid2);
        // 自动模式下只有 1 个单位，边界很小，cell 数应该为 1
        var stats2:Object = grid2.getStats();
        assertEquals("reset_autoBounds_cols", 1, stats2.cols, 0);

        // 恢复显式配置供后续测试
        SortedUnitCache.configureGrid(0, 0, 1000, 600, 200, 200);
    }

    /**
     * P0 测试：SortedUnitCache 层连续两次不同类型 2D 查询，第一次结果不应被覆盖。
     * 模拟 AI 典型模式："先找敌人范围内目标，再查矩形区域友军"
     */
    private static function testCrossQueryResultIsolation():Void {
        trace("\n--- testCrossQueryResultIsolation ---");
        SortedUnitCache.configureGrid(0, 0, 1000, 600, 200, 200);

        var units:Array = [];
        units.push(makeUnit(50, 100, 100));
        units.push(makeUnit(51, 200, 100));
        units.push(makeUnit(52, 800, 500));
        var cache:SortedUnitCache = buildCache(units);

        // 第一次查询：circle 命中 2 个
        var r1:Array = cache.queryCircle2D(150, 100, 150, null);
        var r1Len:Number = r1.length;
        assertEquals("cross_circle_before", 2, r1Len, 0);
        var savedUnit:Object = r1[0];

        // 第二次查询：rect 命中 1 个（不同区域）
        var r2:Array = cache.queryRect2D(700, 400, 900, 600, null);
        assertEquals("cross_rect", 1, r2.length, 0);

        // 核心验证：第一次结果引用是否仍完好
        assertEquals("cross_circle_afterRect", 2, r1.length, 0);
        assertTrue("cross_circle_data_intact", r1[0] == savedUnit);
    }

    /**
     * P0 测试：TargetCacheManager 返回的两个空结果不应是同一个引用，
     * 否则调用方对其中一个的修改会影响另一个。
     */
    private static function testManagerEmpty2DIndependentReferences():Void {
        trace("\n--- testManagerEmpty2DIndependentReferences ---");

        var managerClass:Object = TargetCacheManager;
        var providerKey:String = "_provider";
        var originalProvider:Object = managerClass[providerKey];
        managerClass[providerKey] = {
            getCache: function(requestType:String, target:Object, interval:Number):Object {
                return null;
            }
        };

        var empty1:Array = TargetCacheManager.queryCircle2D(null, 1, "敌人", 0, 0, 100, null);
        var empty2:Array = TargetCacheManager.queryRect2D(null, 1, "敌人", 0, 0, 10, 10, null);

        // 两个空结果不应是同一引用
        assertTrue("empty2d_independent_refs", empty1 != empty2);

        // 修改其中一个不应影响另一个
        empty1.push("pollution");
        assertEquals("empty2d_no_cross_pollute", 0, empty2.length, 0);

        managerClass[providerKey] = originalProvider;
    }

    private static function testManagerEmpty2DResultSelfHeals():Void {
        trace("\n--- testManagerEmpty2DResultSelfHeals ---");

        var managerClass:Object = TargetCacheManager;
        var providerKey:String = "_provider";
        var originalProvider:Object = managerClass[providerKey];
        managerClass[providerKey] = {
            getCache: function(requestType:String, target:Object, interval:Number):Object {
                return null;
            }
        };

        // 每次空查询返回独立新数组，污染一个不影响后续
        var empty1:Array = TargetCacheManager.queryCircle2D(null, 1, "敌人", 0, 0, 100, null);
        assertEquals("manager_empty2d_initial", 0, empty1.length, 0);
        empty1.push("polluted");

        var empty2:Array = TargetCacheManager.queryRect2D(null, 1, "敌人", 0, 0, 10, 10, null);
        assertEquals("manager_empty2d_clean", 0, empty2.length, 0);
        assertTrue("manager_empty2d_freshArray", empty1 != empty2);

        managerClass[providerKey] = originalProvider;
    }

    private static function testFilterFunction2D():Void {
        trace("\n--- testFilterFunction2D ---");
        var units:Array = [];
        for (var i:Number = 0; i < 10; i++) {
            var u:Object = makeUnit(i, 100 + i * 80, 300);
            u.hp = (i < 5) ? 30 : 100;
            units.push(u);
        }
        var cache:SortedUnitCache = buildCache(units);

        var lowHP:Function = function(unit:Object):Boolean {
            return unit.hp < 50;
        };

        var r1:Array = cache.queryCircle2D(400, 300, 500, lowHP);
        assertEquals("filter_circle", 5, r1.length, 0);

        var r2:Array = cache.queryRect2D(0, 0, 1000, 600, lowHP);
        assertEquals("filter_rect", 5, r2.length, 0);
    }

    private static function testEmptyCache2D():Void {
        trace("\n--- testEmptyCache2D ---");
        var cache:SortedUnitCache = buildCache([]);

        assertEquals("empty_circle", 0, cache.queryCircle2D(500, 300, 200, null).length, 0);
        assertEquals("empty_rect", 0, cache.queryRect2D(0, 0, 1000, 600, null).length, 0);
        assertTrue("empty_nearest", cache.queryNearest2D(500, 300, 200, null, null) == null);
        assertEquals("empty_count", 0, cache.countInCircle2D(500, 300, 200), 0);
    }

    private static function testRebuildFromParallelArrays():Void {
        trace("\n--- testRebuildFromParallelArrays ---");

        // Build reference via rebuildFromUnits
        var units:Array = [];
        var n:Number = 50;
        for (var i:Number = 0; i < n; i++) {
            units.push(makeUnit(i, 50 + Math.random() * 900, 50 + Math.random() * 500));
        }

        var g1:SpatialHashGrid = new SpatialHashGrid(0, 0, 1000, 600, 200, 200);
        g1.rebuildFromUnits(units);

        // Build via parallel arrays
        var leftValues:Array = new Array(n);
        var rightValues:Array = new Array(n);
        for (var j:Number = 0; j < n; j++) {
            leftValues[j] = units[j].aabbCollider.left;
            rightValues[j] = units[j].aabbCollider.right;
        }

        var g2:SpatialHashGrid = new SpatialHashGrid(0, 0, 1000, 600, 200, 200);
        g2.rebuildFromParallelArrays(units, leftValues, rightValues);

        // Both grids should have same unit count
        assertEquals("parallelArrays_count", g1.getStats().unitCount, g2.getStats().unitCount, 0);

        // Query results should match
        var cx:Number = 500;
        var cy:Number = 300;
        var radius:Number = 300;
        var r1:Array = g1.queryCircle(cx, cy, radius);
        var count1:Number = r1.length;
        var r2:Array = g2.queryCircle(cx, cy, radius);
        var count2:Number = r2.length;
        assertEquals("parallelArrays_queryMatch", count1, count2, 0);
    }

    private static function testParallelArraysPerformance():Void {
        trace("\n--- testParallelArraysPerformance ---");

        var n:Number = 100;
        var units:Array = [];
        var leftValues:Array = new Array(n);
        var rightValues:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) {
            var u:Object = makeUnit(i, 50 + Math.random() * 1638, 274 + Math.random() * 366);
            units.push(u);
            leftValues[i] = u.aabbCollider.left;
            rightValues[i] = u.aabbCollider.right;
        }

        var g:SpatialHashGrid = new SpatialHashGrid(50, 274, 1638, 366, 200, 200);

        // Benchmark rebuildFromUnits
        var trials:Number = 1000;
        var t0:Number = getTimer();
        for (var ru:Number = 0; ru < trials; ru++) {
            g.rebuildFromUnits(units);
        }
        var fromUnitsMs:Number = getTimer() - t0;

        // Benchmark rebuildFromParallelArrays
        t0 = getTimer();
        for (var rp:Number = 0; rp < trials; rp++) {
            g.rebuildFromParallelArrays(units, leftValues, rightValues);
        }
        var fromParallelMs:Number = getTimer() - t0;

        trace("  [PERF] rebuildFromUnits x" + trials + ": " + fromUnitsMs + "ms (" + (fromUnitsMs / trials) + "ms/call)");
        trace("  [PERF] rebuildFromParallelArrays x" + trials + ": " + fromParallelMs + "ms (" + (fromParallelMs / trials) + "ms/call)");
        // 计时器粒度会让极小差异抖动，保留 25% 预算用于捕获真实退化而非噪声。
        assertTrue("parallelWithinBudget", fromParallelMs <= (fromUnitsMs * 1.25));
    }

    private static function testLazyBuildPerformance():Void {
        trace("\n--- testLazyBuildPerformance ---");

        // Measure lazy grid build cost from SortedUnitCache
        var n:Number = 100;
        var units:Array = [];
        for (var i:Number = 0; i < n; i++) {
            units.push(makeUnit(i, 50 + Math.random() * 1638, 274 + Math.random() * 366));
        }

        SortedUnitCache.configureGrid(50, 274, 1638, 366, 200, 200);
        var cache:SortedUnitCache = buildCache(units);

        // 首次查询触发 grid 构建
        cache.queryCircle2D(400, 300, 200, null);
        var gridRef:SpatialHashGrid = cache.getGrid();

        // 模拟 1000 次 invalidation + rebuild 循环
        var t0:Number = getTimer();
        var trials:Number = 1000;
        for (var q:Number = 0; q < trials; q++) {
            cache.updateData(cache.data, cache.nameIndex, cache.leftValues, cache.rightValues, q + 10);
            cache.queryCircle2D(400, 300, 200, null);
        }
        var lazyMs:Number = getTimer() - t0;
        trace("  [PERF] lazy rebuild+query x" + trials + ": " + lazyMs + "ms (" + (lazyMs / trials) + "ms/call)");
        assertTrue("lazyBuild<1ms", (lazyMs / trials) < 1);

        // 验证全程 grid 实例未被重建（P5 核心优化）
        var gridAfter:SpatialHashGrid = cache.getGrid();
        assertTrue("gridReusedAcross1000Cycles", gridRef == gridAfter);
    }
}
