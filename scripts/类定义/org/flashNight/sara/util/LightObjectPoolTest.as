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
