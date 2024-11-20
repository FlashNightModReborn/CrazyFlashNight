/**
 * ARCCacheTest Class
 * Provides comprehensive tests for the ARCCache class.
 */
import org.flashNight.naki.Cache.ARCCache;

class org.flashNight.naki.Cache.ARCCacheTest {
    private var cache:ARCCache;
    private var testData:Array;
    private var cacheCapacity:Number;

    // Constructor
    /**
     * Initializes the ARCCacheTest with a specified cache capacity.
     * @param capacity The capacity to initialize the ARCCache with.
     */
    public function ARCCacheTest(capacity:Number) {
        this.cacheCapacity = capacity;
        this.cache = new ARCCache(this.cacheCapacity);
        this.testData = [];
    }

    /**
     * Runs all tests.
     */
    public function runTests():Void {
        trace("=== ARCCacheTest: Starting Tests ===");

        this.testPutAndGet();
        this.testCacheEviction();
        this.testCacheHitRate();
        this.testPerformance();
        this.testEdgeCases();
        this.testObjectKeys();

        trace("=== ARCCacheTest: All Tests Completed ===");
    }

    // Test Methods

    /**
     * Tests the basic functionality of put and get methods.
     */
    private function testPutAndGet():Void {
        trace("Running testPutAndGet...");

        // Insert test data
        this.cache.put("key1", "value1");
        this.cache.put("key2", "value2");
        this.cache.put("key3", "value3");

        // Retrieve and verify data
        var value1:Object = this.cache.get("key1");
        var value2:Object = this.cache.get("key2");
        var value3:Object = this.cache.get("key3");

        this._assertEqual(value1, "value1", "Value for key1 should be 'value1'");
        this._assertEqual(value2, "value2", "Value for key2 should be 'value2'");
        this._assertEqual(value3, "value3", "Value for key3 should be 'value3'");

        trace("testPutAndGet completed successfully.\n");
    }

    /**
     * Tests the cache eviction policy when capacity is exceeded.
     */
    private function testCacheEviction():Void {
        trace("Running testCacheEviction...");

        // Clear cache and insert data to fill capacity
        this.cache = new ARCCache(this.cacheCapacity);

        for (var i:Number = 1; i <= this.cacheCapacity; i++) {
            this.cache.put("key" + i, "value" + i);
        }

        // Access some keys to influence ARC's adaptive behavior
        this.cache.get("key2");
        this.cache.get("key4");

        // Insert additional item to trigger eviction
        this.cache.put("keyExtra", "valueExtra");

        // Check queue states
        this._printCacheState("After inserting keyExtra");

        // Check if the least recently used item was evicted
        var evictedValue:Object = this.cache.get("key1"); // Expected to be null or not, depending on ARC
        var existingValue:Object = this.cache.get("keyExtra"); // Should be 'valueExtra'

        this._assertEqual(evictedValue, null, "Value for key1 should be null (evicted)");
        this._assertEqual(existingValue, "valueExtra", "Value for keyExtra should be 'valueExtra'");

        trace("testCacheEviction completed successfully.\n");
    }

    /**
     * Tests cache hit rate with a realistic access pattern.
     */
    private function testCacheHitRate():Void {
        trace("Running testCacheHitRate...");

        // Clear cache and prepare test data
        this.cache = new ARCCache(this.cacheCapacity);
        var totalRequests:Number = 1000;
        var cacheHits:Number = 0;

        // Generate test data (simulate access to 2 * capacity items)
        for (var i:Number = 1; i <= 2 * this.cacheCapacity; i++) {
            this.testData.push("key" + i);
            this.cache.put("key" + i, "value" + i);
        }

        // Reset cacheHits
        cacheHits = 0;

        // Randomly access items and calculate hit rate
        for (var j:Number = 0; j < totalRequests; j++) {
            var randomIndex:Number = Math.floor(Math.random() * this.testData.length);
            var key:String = this.testData[randomIndex];
            var value:Object = this.cache.get(key);

            if (value != null) {
                cacheHits++;
            } else {
                // Simulate adding the item back into the cache
                this.cache.put(key, "value" + key.substring(3));
            }
        }

        var hitRate:Number = (cacheHits / totalRequests) * 100;
        trace("Cache Hit Rate: " + hitRate + "%");

        this._assertInRange(hitRate, 0, 100, "Cache hit rate should be between 0% and 100%");

        trace("testCacheHitRate completed successfully.\n");
    }

    /**
     * Tests the performance overhead of the cache.
     */
    private function testPerformance():Void {
        trace("Running testPerformance...");

        // Measure time taken to perform a large number of cache operations
        var operations:Number = 10000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < operations; i++) {
            var key:String = "key" + (i % (2 * this.cacheCapacity));
            this.cache.put(key, "value" + key.substring(3));
            this.cache.get(key);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;

        trace("Performed " + operations + " cache operations in " + duration + " ms.");

        var opsPerSecond:Number = (operations / duration) * 1000;
        trace("Cache Operations per Second: " + opsPerSecond + "\n");

        this._assertGreaterThan(opsPerSecond, 0, "Operations per second should be greater than 0");

        trace("testPerformance completed successfully.\n");
    }

    /**
     * Tests edge cases such as using null, undefined, and special characters as keys and values.
     */
    private function testEdgeCases():Void {
        trace("Running testEdgeCases...");

        // Clear cache
        this.cache = new ARCCache(this.cacheCapacity);

        // Test with null key and value
        this.cache.put(null, null);
        var nullValue:Object = this.cache.get(null);
        this._assertEqual(nullValue, null, "Value for null key should be null");

        // Test with undefined key and value
        this.cache.put(undefined, undefined);
        var undefinedValue:Object = this.cache.get(undefined);
        this._assertEqual(undefinedValue, undefined, "Value for undefined key should be undefined");

        // Test with special characters in keys
        this.cache.put("key@#", "value@#");
        var specialValue:Object = this.cache.get("key@#");
        this._assertEqual(specialValue, "value@#", "Value for 'key@#' should be 'value@#'");

        // Test with empty string key
        this.cache.put("", "emptyKey");
        var emptyKeyValue:Object = this.cache.get("");
        this._assertEqual(emptyKeyValue, "emptyKey", "Value for empty string key should be 'emptyKey'");

        // Test with numeric keys
        this.cache.put(123, "numericKey");
        var numericKeyValue:Object = this.cache.get(123);
        this._assertEqual(numericKeyValue, "numericKey", "Value for numeric key 123 should be 'numericKey'");

        trace("testEdgeCases completed successfully.\n");
    }

    /**
     * Tests using objects as keys to ensure UID generation works correctly.
     */
    private function testObjectKeys():Void {
        trace("Running testObjectKeys...");

        // Clear cache
        this.cache = new ARCCache(this.cacheCapacity);

        // Create object keys
        var obj1:Object = { name: "Object1" };
        var obj2:Object = { name: "Object2" };
        var obj3:Object = { name: "Object3" };

        // Insert object keys
        this.cache.put(obj1, "valueObj1");
        this.cache.put(obj2, "valueObj2");
        this.cache.put(obj3, "valueObj3");

        // Retrieve and verify
        var valObj1:Object = this.cache.get(obj1);
        var valObj2:Object = this.cache.get(obj2);
        var valObj3:Object = this.cache.get(obj3);

        this._assertEqual(valObj1, "valueObj1", "Value for obj1 should be 'valueObj1'");
        this._assertEqual(valObj2, "valueObj2", "Value for obj2 should be 'valueObj2'");
        this._assertEqual(valObj3, "valueObj3", "Value for obj3 should be 'valueObj3'");

        // Test eviction with object keys
        for (var i:Number = 4; i <= this.cacheCapacity + 2; i++) {
            this.cache.put("key" + i, "value" + i);
        }

        // Attempt to get obj1 which should have been evicted if ARC works correctly
        var evictedObj1:Object = this.cache.get(obj1); // Expected to be null
        var existingObj2:Object = this.cache.get(obj2); // Should be 'valueObj2'

        this._assertEqual(evictedObj1, null, "Value for obj1 should be null (evicted)");
        this._assertEqual(existingObj2, "valueObj2", "Value for obj2 should be 'valueObj2'");

        trace("testObjectKeys completed successfully.\n");
    }

    // Utility Methods

    /**
     * Asserts that two values are equal, logs an error if not.
     * @param actual The actual value.
     * @param expected The expected value.
     * @param message The message to display on failure.
     */
    private function _assertEqual(actual:Object, expected:Object, message:String):Void {
        if (actual !== expected) {
            trace("Assertion Failed: " + message + " (Expected: " + expected + ", Actual: " + actual + ")");
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    /**
     * Asserts that a value is within a specified range, logs an error if not.
     * @param value The value to check.
     * @param min The minimum acceptable value.
     * @param max The maximum acceptable value.
     * @param message The message to display on failure.
     */
    private function _assertInRange(value:Number, min:Number, max:Number, message:String):Void {
        if (value < min || value > max) {
            trace("Assertion Failed: " + message + " (Value: " + value + ", Range: " + min + " - " + max + ")");
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    /**
     * Asserts that a value is greater than a specified minimum, logs an error if not.
     * @param value The value to check.
     * @param min The minimum value.
     * @param message The message to display on failure.
     */
    private function _assertGreaterThan(value:Number, min:Number, message:String):Void {
        if (value <= min) {
            trace("Assertion Failed: " + message + " (Value: " + value + ", Minimum: " + min + ")");
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    /**
     * Prints the current state of the cache queues.
     * @param stage 描述当前队列状态的阶段。
     */
    private function _printCacheState(stage:String):Void {
        trace("=== Cache State at " + stage + " ===");
        trace("T1: " + this.cache.getT1());
        trace("T2: " + this.cache.getT2());
        trace("B1: " + this.cache.getB1());
        trace("B2: " + this.cache.getB2());
        trace("==============================");
    }
}
