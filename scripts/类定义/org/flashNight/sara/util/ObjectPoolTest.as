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
     * Initialize the testing environment by creating an ObjectPool instance
     */
    private function setup():Void {
        // Define a simple create function
        var createFunc:Function = function(parent:MovieClip):MovieClip {
            var mc:MovieClip = parent.createEmptyMovieClip("testMC" + Dictionary.getStaticUID(this), parent.getNextHighestDepth());
            mc.__isDestroyed = false;
            return mc;
        };

        // Define a simple reset function
        var resetFunc:Function = function():Void {
            // Simple reset logic, e.g., reset position and visibility
            this._x = 0;
            this._y = 0;
            this._visible = true;
        };

        // Define a simple release function
        var releaseFunc:Function = function():Void {
            // Simple release logic, e.g., hide the object
            this._visible = false;
        };

        // Assume a parent MovieClip exists
        var parentClip:MovieClip = _root.createEmptyMovieClip("parentClip", _root.getNextHighestDepth());

        // Create the ObjectPool instance
        // Parameters: createFunc, resetFunc, releaseFunc, parentClip, maxPoolSize=10, preloadSize=3, isLazyLoaded=false, isPrototypeEnabled=true, prototypeInitArgs=[]
        pool = new ObjectPool(createFunc, resetFunc, releaseFunc, parentClip, 10, 3, false, true, []);
    }

    /**
     * Run all test sections
     */
    private function runTests():Void {
        testPublicMethods();
        setup();  // Reinitialize the object pool
        testRealWorldUsage();
        setup();  // Reinitialize the object pool
        testPerformance();
        setup();  // Reinitialize the object pool for edge case tests
        testEdgeCases();
    }

    /**
     * Public Methods Accuracy Tests (Unit Tests)
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
            pool.preload(15); // Preload up to max capacity
            assert(pool.getPoolSize() == 15, "preload/getPoolSize");
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
            assert(pool.getPoolSize() == 14, "getObject reduces pool size");
            pool.releaseObject(obj1);
            assert(pool.getPoolSize() == 15, "releaseObject increases pool size");
        } catch (e) {
            fail("getObject/releaseObject", e.message);
        }

        // Test isPoolEmpty and isPoolFull
        try {
            var objects:Array = [];
            // Empty the pool by acquiring all objects
            for (var i:Number = 0; i < 15; i++) {
                objects.push(pool.getObject());
            }
            assert(pool.isPoolEmpty() == true, "isPoolEmpty after getting all objects");

            // Release the objects back into the pool
            for (var j:Number = 0; j < 15; j++) {
                pool.releaseObject(objects[j]);
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

        // Additional Test: Releasing an extra object when pool is full
        try {
            // Preload to full capacity
            pool.clearPool();
            pool.preload(pool.getMaxPoolSize()); // Preload 15 objects
            assert(pool.getPoolSize() == 15, "Preload to full capacity");
            assert(pool.isPoolFull() == true, "Pool is full before releasing extra object");

            // Create an extra object outside the pool
            var extraObj:MovieClip = pool.createNewObject(); // External object not from pool

            // Release the extra object; pool is full, so it should be destroyed
            pool.releaseObject(extraObj);

            // Check if the extra object is destroyed
            if (extraObj == undefined || extraObj.__isDestroyed == true || extraObj._parent == undefined) {
                assert(true, "Extra object is marked as destroyed");
            } else {
                assert(false, "Extra object is marked as destroyed");
            }
        } catch (e) {
            fail("Release Object When Pool is Full", e.message);
        }

        trace("Public Methods Accuracy Tests Completed.");
    }


    /**
     * Real-World Usage Tests
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
            var destroyedCount:Number = 0;
            for (var k:Number = 0; k < moreObjs.length; k++) {
                pool.releaseObject(moreObjs[k]);
                if (moreObjs[k] == undefined || moreObjs[k].__isDestroyed == true) {
                    destroyedCount++;
                }
            }
            // Calculate how many objects should have been destroyed
            // Total objects attempted to release: 6 (moreObjs) + 2 (objs) = 8
            // Pool capacity is 15, so 8 <= 15 no destruction should occur
            assert(destroyedCount == 0, "Extra objects are destroyed when pool is full");
        } catch (e) {
            fail("Real-World Usage Scenario", e.message);
        }

        trace("Real-World Usage Tests Completed.");
    }

    /**
     * Performance Efficiency Tests
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
     * Edge Cases and Exception Handling Tests
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
            var privatePropsOk:Boolean = true;
            for (var prop in obj) {
                if (prop == "_pool" || prop == "recycle") {
                    privatePropsOk = false;
                    break;
                }
            }
            assert(privatePropsOk, "Private properties are not enumerable");

            // Verify that __isDestroyed is false
            assert(obj.__isDestroyed == false, "Object is not destroyed when pool is not full");
        } catch (e) {
            fail("Object properties after release", e.message);
        }

        trace("Edge Cases Tests Completed.");
    }

    /**
     * Custom assertion method
     * @param condition Boolean condition to assert
     * @param testName Name of the test
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
     * Record failed tests
     * @param testName Name of the test
     * @param message Error message
     */
    private function fail(testName:String, message:String):Void {
        totalTests++;
        testResults.push("[FAIL] " + testName + ": " + message);
    }

    /**
     * Report test results
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
