import org.flashNight.sara.util.LightObjectPool;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.sara.util.LightObjectPoolTest {
    private var pool:LightObjectPool;
    private var testResults:Array;
    private var totalTests:Number;
    private var passedTests:Number;

    public function LightObjectPoolTest() {
        testResults = [];
        totalTests = 0;
        passedTests = 0;
        setup();
        runTests();
        reportResults();
    }

    /**
     * Initialize the testing environment by creating a LightObjectPool instance
     */
    private function setup():Void {
        // Define a simple create function with unique identifiers for easier tracking
        var createFunc:Function = function():Object {
            return {foo: "bar", id: Dictionary.getStaticUID(this)};
        };

        // Create the LightObjectPool instance
        pool = new LightObjectPool(createFunc);
    }

    /**
     * Run all test sections
     */
    private function runTests():Void {
        testBasicFunctionality();
        setup();  // Reinitialize the object pool
        testClearPool();
        setup();  // Reinitialize the object pool before performance tests
        testPerformance();
        testPracticalPerformance();
    }

    /**
     * Test the basic functionality of LightObjectPool
     */
    private function testBasicFunctionality():Void {
        trace("Starting Basic Functionality Tests...");

        // Initially, pool is empty
        try {
            assert(pool.getPoolSize() == 0, "Initial pool size is zero");
        } catch (e) {
            fail("Initial pool size", e.message);
        }

        // getObject should create a new object when pool is empty
        try {
            var obj1:Object = pool.getObject();
            assert(obj1 != null, "getObject returns a new object");
            assert(pool.getPoolSize() == 0, "Pool size remains zero after getting new object");
        } catch (e) {
            fail("getObject when empty", e.message);
        }

        // releaseObject should add object back to the pool
        try {
            pool.releaseObject(obj1);
            assert(pool.getPoolSize() == 1, "releaseObject adds object back to the pool");
        } catch (e) {
            fail("releaseObject", e.message);
        }

        // getObject should now return the previously released object
        try {
            var obj2:Object = pool.getObject();
            assert(obj2 == obj1, "getObject returns the previously released object");
            assert(pool.getPoolSize() == 0, "Pool size decrements after retrieving an object");
        } catch (e) {
            fail("getObject after release", e.message);
        }

        // Releasing undefined should not cause errors
        try {
            pool.releaseObject(undefined);
            assert(true, "Releasing undefined does not throw error");
        } catch (e) {
            fail("Releasing undefined", e.message);
        }

        trace("Basic Functionality Tests Completed.");
    }

    /**
     * Test clearing the pool
     */
    private function testClearPool():Void {
        trace("Starting Clear Pool Tests...");

        // Acquire multiple distinct objects without releasing them immediately
        var objs:Array = [];
        for (var i:Number = 0; i < 5; i++) {
            var o:Object = pool.getObject();
            objs.push(o);
        }

        // Release all distinct objects back to the pool
        for (var j:Number = 0; j < objs.length; j++) {
            pool.releaseObject(objs[j]);
        }

        try {
            assert(pool.getPoolSize() == 5, "Pool size is 5 after releasing 5 distinct objects");
        } catch (e) {
            fail("Pool size after releasing 5 distinct objects", e.message);
        }

        // Clear the pool
        try {
            pool.clearPool();
            assert(pool.getPoolSize() == 0, "clearPool sets pool size to 0");
        } catch (e) {
            fail("clearPool", e.message);
        }

        trace("Clear Pool Tests Completed.");
    }

    /**
     * Test the performance of LightObjectPool
     */
    private function testPerformance():Void {
        trace("Starting Performance Tests...");

        var iterations:Number = 10000; // Number of get and release operations
        var startTime:Number;
        var endTime:Number;
        var duration:Number;

        // Measure getObject and releaseObject performance
        try {
            startTime = getTimer();
            for (var i:Number = 0; i < iterations; i++) {
                var obj:Object = pool.getObject();
                // Optionally perform some operations on the object
                obj.foo = "baz";
                pool.releaseObject(obj);
            }
            endTime = getTimer();
            duration = endTime - startTime;
            trace("Performed " + iterations + " getObject and releaseObject operations in " + duration + " ms");

            // Simple performance assertion (example: should be less than 1000ms)
            // Note: Thresholds may need adjustment based on actual performance
            var threshold:Number = 100; // in milliseconds
            assert(duration < threshold, "Performance: " + iterations + " getObject/releaseObject operations < " + threshold + " ms");
        } catch (e) {
            fail("Performance: getObject/releaseObject operations", e.message);
        }

        // Additional performance test: Continuous get and release without holding references
        try {
            startTime = getTimer();
            for (var j:Number = 0; j < iterations; j++) {
                pool.releaseObject(pool.getObject());
            }
            endTime = getTimer();
            duration = endTime - startTime;
            trace("Performed " + iterations + " continuous getObject and releaseObject operations in " + duration + " ms");

            // Simple performance assertion (example: should be less than 800ms)
            var threshold2:Number = 100; // in milliseconds
            assert(duration < threshold2, "Performance: " + iterations + " continuous getObject/releaseObject operations < " + threshold2 + " ms");
        } catch (e) {
            fail("Performance: continuous getObject/releaseObject operations", e.message);
        }

        trace("Performance Tests Completed.");
    }

    /**
     * Test the performance of LightObjectPool in a practical scenario
     */
    private function testPracticalPerformance():Void {
        trace("Starting Practical Performance Tests...");

        var iterations:Number = 10000; // Number of operations
        var reuseThreshold:Number = 70; // Percentage threshold for reusing objects
        var releaseThreshold:Number = 50; // Percentage threshold for releasing objects
        var operations:Array = []; // To simulate a mixed workload
        var poolSize:Number = 0;

        // Generate operations based on thresholds
        for (var i:Number = 0; i < iterations; i++) {
            if (i % 100 < reuseThreshold) {
                operations.push("get");
            } else if (i % 100 < releaseThreshold + reuseThreshold) {
                operations.push("release");
            } else {
                operations.push("mixed");
            }
        }

        // Initialize test variables
        var startTime:Number;
        var endTime:Number;
        var duration:Number;

        // Perform mixed operations
        try {
            startTime = getTimer();
            for (var j:Number = 0; j < iterations; j++) {
                var op:String = operations[j];
                if (op == "get") {
                    // Get an object from the pool and optionally modify it
                    var obj:Object = pool.getObject();
                    obj.foo = "baz";
                    poolSize++;
                } else if (op == "release") {
                    // Release an object back to the pool if available
                    if (poolSize > 0) {
                        var releaseObj:Object = pool.getObject();
                        pool.releaseObject(releaseObj);
                        poolSize--;
                    }
                } else if (op == "mixed") {
                    // Perform both get and release
                    if (poolSize > 0) {
                        var mixedObj:Object = pool.getObject();
                        mixedObj.foo = "baz";
                        pool.releaseObject(mixedObj);
                    } else {
                        var newObj:Object = pool.getObject();
                        newObj.foo = "baz";
                        pool.releaseObject(newObj);
                    }
                }
            }
            endTime = getTimer();
            duration = endTime - startTime;

            trace("Performed " + iterations + " mixed operations in " + duration + " ms");

            // Simple performance assertion (example: should be less than 150ms)
            var threshold:Number = 150; // in milliseconds
            assert(duration < threshold, "Performance: " + iterations + " mixed operations < " + threshold + " ms");
        } catch (e) {
            fail("Performance: mixed operations", e.message);
        }

        trace("Practical Performance Tests Completed.");
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
