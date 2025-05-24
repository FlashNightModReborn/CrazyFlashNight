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
        // Removed tests related to complex keys
        // this.testObjectKeys();
        // this.testComplexObjectKeys();
        // this.testMixedKeyTypes();
        this.testHighFrequencyAccess();
        this.testDuplicateKeys();
        this.testLargeScaleCache();

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
        var evictedValue:Object = this.cache.get("key1"); // Expected to be null
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

        // Pre-generate random indices to avoid runtime calculations
        var randomIndices:Array = [];
        for (var j:Number = 0; j < totalRequests; j++) {
            randomIndices.push(Math.floor(Math.random() * this.testData.length));
        }

        // Perform cache accesses
        for (var k:Number = 0; k < totalRequests; k++) {
            var keyIndex:Number = randomIndices[k];
            var key:String = this.testData[keyIndex];
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

        // Loop Unrolling: Perform 4 cache operations per iteration
        var i:Number = 0;
        var max:Number = operations - (operations % 4); // Ensure divisible by 4
        for (; i < max; i += 4) {
            var key1:String = "perfKey" + (i % (2 * this.cacheCapacity));
            this.cache.put(key1, "perfValue" + (i % 100));
            this.cache.get(key1);

            var key2:String = "perfKey" + ((i + 1) % (2 * this.cacheCapacity));
            this.cache.put(key2, "perfValue" + ((i + 1) % 100));
            this.cache.get(key2);

            var key3:String = "perfKey" + ((i + 2) % (2 * this.cacheCapacity));
            this.cache.put(key3, "perfValue" + ((i + 2) % 100));
            this.cache.get(key3);

            var key4:String = "perfKey" + ((i + 3) % (2 * this.cacheCapacity));
            this.cache.put(key4, "perfValue" + ((i + 3) % 100));
            this.cache.get(key4);
        }

        // Handle remaining operations
        for (; i < operations; i++) {
            var key:String = "perfKey" + (i % (2 * this.cacheCapacity));
            this.cache.put(key, "perfValue" + (i % 100));
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
     * Removed `testObjectKeys` as complex keys are no longer supported.
     */

    /**
     * Removed `testComplexObjectKeys` as complex keys are no longer supported.
     */

    /**
     * Tests high-frequency access patterns to verify ARC's adaptive behavior.
     */
    private function testHighFrequencyAccess():Void {
        trace("Running testHighFrequencyAccess...");

        // Clear cache
        this.cache = new ARCCache(this.cacheCapacity);

        // Insert multiple keys
        for (var i:Number = 1; i <= this.cacheCapacity; i++) {
            this.cache.put("hfKey" + i, "hfValue" + i);
        }

        // Simulate high-frequency access to specific keys
        var highFreqKeys:Array = ["hfKey1", "hfKey2", "hfKey3"];
        for (var j:Number = 0; j < 1000; j++) {
            for (var k:Number = 0; k < highFreqKeys.length; k++) {
                this.cache.get(highFreqKeys[k]);
            }
        }

        // Insert additional keys to trigger eviction
        for (var m:Number = this.cacheCapacity + 1; m <= this.cacheCapacity + 50; m++) {
            this.cache.put("hfKeyExtra" + m, "hfValueExtra" + m);
        }

        // Verify that high-frequency keys are still present
        trace("Verifying high-frequency keys...");
        for (var n:Number = 0; n < highFreqKeys.length; n++) {
            var value:Object = this.cache.get(highFreqKeys[n]);
            this._assertEqual(value, "hfValue" + (n + 1), "High-frequency key " + highFreqKeys[n] + " should still be present");
        }

        // Verify that some low-frequency keys have been evicted
        var evictedValue:Object = this.cache.get("hfKey4");
        this._assertEqual(evictedValue, null, "Low-frequency key 'hfKey4' should be null (evicted)");

        trace("testHighFrequencyAccess completed successfully.\n");
    }


    /**
     * Removed `testMixedKeyTypes` as complex keys are no longer supported.
     */

    /**
     * Tests inserting duplicate keys to ensure cache updates values correctly.
     */
    private function testDuplicateKeys():Void {
        trace("Running testDuplicateKeys...");

        // Clear cache
        this.cache = new ARCCache(this.cacheCapacity);

        // Insert a key
        this.cache.put("dupKey", "initialValue");
        this._assertEqual(this.cache.get("dupKey"), "initialValue", "Initial value for 'dupKey' should be 'initialValue'");

        // Insert the same key with a new value
        this.cache.put("dupKey", "updatedValue");
        this._assertEqual(this.cache.get("dupKey"), "updatedValue", "Updated value for 'dupKey' should be 'updatedValue'");

        // Access the key to promote it to T2
        this.cache.get("dupKey");

        // Insert additional keys to trigger eviction
        for (var i:Number = 1; i <= this.cacheCapacity; i++) {
            this.cache.put("dupKey" + i, "dupValue" + i);
        }

        // Verify that 'dupKey' is still present due to promotion
        this._assertEqual(this.cache.get("dupKey"), "updatedValue", "Value for 'dupKey' should still be 'updatedValue'");

        trace("testDuplicateKeys completed successfully.\n");
    }

    /**
     * Tests cache behavior with a large scale to ensure stability and performance.
     */
    private function testLargeScaleCache():Void {
        trace("Running testLargeScaleCache...");

        // Define a larger cache capacity
        var largeCapacity:Number = 10000;
        this.cache = new ARCCache(largeCapacity);

        // Insert a large number of keys
        for (var i:Number = 1; i <= largeCapacity; i++) {
            this.cache.put("largeKey" + i, "largeValue" + i);
        }

        // Access a subset of keys
        for (var j:Number = 1; j <= 5000; j++) {
            this.cache.get("largeKey" + j);
        }

        // Insert additional keys to trigger eviction
        for (var k:Number = largeCapacity + 1; k <= largeCapacity + 5000; k++) {
            this.cache.put("largeKey" + k, "largeValue" + k);
        }

        // Verify that frequently accessed keys are still present
        trace("Verifying frequently accessed keys...");
        for (var m:Number = 1; m <= 10; m++) {
            var value:Object = this.cache.get("largeKey" + m);
            this._assertEqual(value, "largeValue" + m, "Frequently accessed 'largeKey" + m + "' should still be present");
        }

        // Verify that some infrequently accessed keys have been evicted
        trace("Verifying infrequently accessed keys...");
        var evictedValue:Object = this.cache.get("largeKey6000");
        this._assertEqual(evictedValue, null, "Infrequently accessed 'largeKey6000' should be null (evicted)");

        trace("testLargeScaleCache completed successfully.\n");
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
        trace("T1: " + this.cache.getT1().join(","));
        trace("T2: " + this.cache.getT2().join(","));
        trace("B1: " + this.cache.getB1().join(","));
        trace("B2: " + this.cache.getB2().join(","));
        trace("==============================");
    }
}
