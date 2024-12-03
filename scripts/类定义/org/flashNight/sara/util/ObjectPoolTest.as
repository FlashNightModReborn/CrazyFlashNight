import org.flashNight.sara.util.ObjectPool;
import org.flashNight.neur.Event.Delegate;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.sara.util.ObjectPoolTest {
    private var pool:ObjectPool;
    private var testResults:Array;
    private var totalTests:Number;
    private var passedTests:Number;

    public function ObjectPoolTest() {
        testResults = [];
        totalTests = 0;
        passedTests = 0;
        setup();
        runTests();
        reportResults();
    }

    /**
     * 初始化测试环境，创建 ObjectPool 实例
     */
    private function setup():Void {
        // 创建一个简单的创建函数
        var createFunc:Function = function(parent:MovieClip):MovieClip {
            var mc:MovieClip = parent.createEmptyMovieClip("testMC" + Dictionary.getStaticUID(this), parent.getNextHighestDepth());
            mc.__isDestroyed = false;
            return mc;
        };

        // 重置函数
        var resetFunc:Function = function():Void {
            // 简单重置逻辑，例如重置位置
            this._x = 0;
            this._y = 0;
            this._visible = true;
        };

        // 释放函数
        var releaseFunc:Function = function():Void {
            // 简单释放逻辑，例如隐藏对象
            this._visible = false;
        };

        // 假设有一个父 MovieClip
        var parentClip:MovieClip = _root.createEmptyMovieClip("parentClip", _root.getNextHighestDepth());

        // 创建 ObjectPool 实例
        pool = new ObjectPool(createFunc, resetFunc, releaseFunc, parentClip, 10, 3, false, true, []);
    }

    /**
     * 运行所有测试部分
     */
    private function runTests():Void {
        testPublicMethods();
        setup();  // 重新初始化对象池
        testRealWorldUsage();
        setup();  // 重新初始化对象池
        testPerformance();
        setup();  // 重新初始化对象池 for edge case tests
        testEdgeCases();
    }

    /**
     * 公共方法准确性测试（单元测试）
     */
    private function testPublicMethods():Void {
        trace("Starting Public Methods Accuracy Tests...");

        // Test setPoolCapacity and getMaxPoolSize
        try {
            pool.setPoolCapacity(15);
            assert(pool.getMaxPoolSize() == 15, "setPoolCapacity/getMaxPoolSize");
        } catch (e) {
            fail("setPoolCapacity/getMaxPoolSize", e.message);
        }

        // Test preload and getPoolSize
        try {
            pool.preload(5);
            assert(pool.getPoolSize() == 5, "preload/getPoolSize");
        } catch (e) {
            fail("preload/getPoolSize", e.message);
        }

        // Test isLazyLoadingEnabled and isPrototypeModeEnabled
        try {
            assert(pool.isLazyLoadingEnabled() == false, "isLazyLoadingEnabled");
            assert(pool.isPrototypeModeEnabled() == true, "isPrototypeModeEnabled");
        } catch (e) {
            fail("isLazyLoadingEnabled/isPrototypeModeEnabled", e.message);
        }

        // Test getObject and releaseObject
        try {
            var obj1:MovieClip = pool.getObject();
            assert(pool.getPoolSize() == 4, "getObject reduces pool size");
            pool.releaseObject(obj1);
            assert(pool.getPoolSize() == 5, "releaseObject increases pool size");
        } catch (e) {
            fail("getObject/releaseObject", e.message);
        }

        // Test isPoolEmpty and isPoolFull
        try {
            // Empty the pool
            for (var i:Number = 0; i < 5; i++) {
                pool.getObject();
            }
            assert(pool.isPoolEmpty() == true, "isPoolEmpty after getting all objects");

            // Fill the pool
            for (var j:Number = 0; j < 15; j++) {
                var obj:MovieClip = pool.getObject();
                pool.releaseObject(obj);
            }
            assert(pool.isPoolFull() == true, "isPoolFull after filling the pool");
        } catch (e) {
            fail("isPoolEmpty/isPoolFull", e.message);
        }

        // Test clearPool
        try {
            pool.clearPool();
            assert(pool.getPoolSize() == 0, "clearPool sets pool size to 0");
        } catch (e) {
            fail("clearPool", e.message);
        }

        // Additional Test: Releasing objects when pool is full
        try {
            // Preload to full capacity
            pool.clearPool();
            pool.preload(pool.getMaxPoolSize());
            assert(pool.getPoolSize() == pool.getMaxPoolSize(), "Preload to full capacity");

            // Attempt to release another object, which should be destroyed
            var extraObj:MovieClip = pool.getObject();
            pool.releaseObject(extraObj);
            assert(pool.getPoolSize() == pool.getMaxPoolSize(), "Release object when pool is full does not increase pool size");

            // Check if the extra object is destroyed
            assert(extraObj.__isDestroyed == true, "Extra object is marked as destroyed");
        } catch (e) {
            fail("Release Object When Pool is Full", e.message);
        }

        trace("Public Methods Accuracy Tests Completed.");
    }

    /**
     * 实战性调度测试
     */
    private function testRealWorldUsage():Void {
        trace("Starting Real-World Usage Tests...");

        // Scenario: Simulate acquiring and releasing multiple objects
        try {
            // Preload objects
            pool.preload(5);
            assert(pool.getPoolSize() == 5, "Preload 5 objects");

            // Acquire 3 objects
            var objs:Array = [];
            for (var i:Number = 0; i < 3; i++) {
                var obj:MovieClip = pool.getObject();
                obj._visible = true;
                objs.push(obj);
            }
            assert(pool.getPoolSize() == 2, "Acquire 3 objects reduces pool size to 2");

            // Release 2 objects
            pool.releaseObject(objs[0]);
            pool.releaseObject(objs[1]);
            assert(pool.getPoolSize() == 4, "Release 2 objects increases pool size to 4");

            // Acquire 6 objects (more than preload size)
            var moreObjs:Array = [];
            for (var j:Number = 0; j < 6; j++) {
                var moreObj:MovieClip = pool.getObject();
                moreObj._visible = true;
                moreObjs.push(moreObj);
            }
            assert(pool.getPoolSize() == 0, "Acquire 6 objects from pool size 4");

            // Release all acquired objects
            pool.releaseObjects(objs);
            pool.releaseObjects(moreObjs);
            assert(pool.getPoolSize() == 10, "Release all objects to fill the pool");
        } catch (e) {
            fail("Real-World Usage Scenario", e.message);
        }

        trace("Real-World Usage Tests Completed.");
    }

    /**
     * 性能效率测试
     */
    private function testPerformance():Void {
        trace("Starting Performance Efficiency Tests...");

        var startTime:Number;
        var endTime:Number;
        var duration:Number;

        // Test getObject performance
        try {
            startTime = getTimer();
            for (var i:Number = 0; i < 1000; i++) {
                var obj:MovieClip = pool.getObject();
                // Simulate some operations
                obj._x = i;
                pool.releaseObject(obj);
            }
            endTime = getTimer();
            duration = endTime - startTime;
            trace("getObject and releaseObject 1000 times took " + duration + " ms");
            // Simple performance assertion (example: should be less than 1000ms)
            assert(duration < 1000, "Performance: getObject/releaseObject 1000 times < 1000ms");
        } catch (e) {
            fail("Performance: getObject/releaseObject", e.message);
        }

        // Test preload performance
        try {
            startTime = getTimer();
            pool.clearPool();
            pool.preload(10);
            endTime = getTimer();
            duration = endTime - startTime;
            trace("Preloading 10 objects took " + duration + " ms");
            // Simple performance assertion (example: should be less than 100ms)
            assert(duration < 100, "Performance: preload 10 objects < 100ms");
        } catch (e) {
            fail("Performance: preload", e.message);
        }

        trace("Performance Efficiency Tests Completed.");
    }

    /**
     * 边界条件和异常情况测试
     */
    private function testEdgeCases():Void {
        trace("Starting Edge Cases Tests...");

        // Test setting pool capacity to 0
        try {
            pool.setPoolCapacity(0);
            assert(pool.getMaxPoolSize() == 0, "setPoolCapacity to 0");
            assert(pool.getPoolSize() == 0, "Pool size after setting capacity to 0");
            assert(pool.isPoolFull() == true, "isPoolFull when capacity is 0");
        } catch (e) {
            fail("setPoolCapacity to 0", e.message);
        }

        // Test preloading more objects than maxPoolSize
        try {
            pool.setPoolCapacity(5);
            pool.preload(10);  // Attempt to preload 10 objects into a pool with capacity 5
            assert(pool.getPoolSize() == 5, "Preload more objects than maxPoolSize");
        } catch (e) {
            fail("Preload more objects than maxPoolSize", e.message);
        }

        // Test releasing undefined object
        try {
            pool.releaseObject(undefined);
            assert(true, "Releasing undefined object does not throw error");
        } catch (e) {
            fail("Releasing undefined object", e.message);
        }

        // Test releasing the same object multiple times
        try {
            pool.setPoolCapacity(5);
            pool.preload(5);
            var obj:MovieClip = pool.getObject();
            pool.releaseObject(obj);
            pool.releaseObject(obj);  // Releasing the same object again
            assert(pool.getPoolSize() == 5, "Releasing the same object multiple times");
        } catch (e) {
            fail("Releasing the same object multiple times", e.message);
        }

        // Test releasing objects when pool is full
        try {
            pool.setPoolCapacity(3);
            pool.preload(3);
            var obj1:MovieClip = pool.getObject();
            var obj2:MovieClip = pool.getObject();
            var obj3:MovieClip = pool.getObject();
            pool.releaseObject(obj1);
            pool.releaseObject(obj2);
            pool.releaseObject(obj3);
            assert(pool.getPoolSize() == 3, "Releasing objects when pool is full");
        } catch (e) {
            fail("Releasing objects when pool is full", e.message);
        }

        // Test object properties after release
        try {
            pool.setPoolCapacity(5);
            pool.preload(5);
            var obj:MovieClip = pool.getObject();
            pool.releaseObject(obj);
            // Verify that _pool and recycle are not enumerable
            for (var prop in obj) {
                assert(prop != "_pool" && prop != "recycle", "Private properties are not enumerable");
            }
            assert(obj.__isDestroyed == undefined, "Object is not destroyed when pool is not full");
        } catch (e) {
            fail("Object properties after release", e.message);
        }

        trace("Edge Cases Tests Completed.");
    }

    /**
     * 自定义断言方法
     * @param condition 条件表达式
     * @param testName 测试名称
     */
    private function assert(condition:Boolean, testName:String):Void {
        totalTests++;
        if (condition) {
            passedTests++;
            trace("[PASS] " + testName);
        } else {
            testResults.push("[FAIL] " + testName + ": Condition failed.");
        }
    }

    /**
     * 记录失败的测试
     * @param testName 测试名称
     * @param message 错误信息
     */
    private function fail(testName:String, message:String):Void {
        totalTests++;
        testResults.push("[FAIL] " + testName + ": " + message);
    }

    /**
     * 报告测试结果
     */
    private function reportResults():Void {
        trace("----- Test Results -----");
        for (var i:Number = 0; i < testResults.length; i++) {
            trace(testResults[i]);
        }
        trace("------------------------");
        trace("Total Tests: " + totalTests + ", Passed: " + passedTests + ", Failed: " + (totalTests - passedTests));
    }
}
