// ARCEnhancedLazyCache 测试
org.flashNight.gesh.func.ARCEnhancedLazyCacheTest.runTests();


=== ARCEnhancedLazyCacheTest v2.0: Starting Tests ===
Running: testBasicFunctionality
[PASS] Cache should compute and return Value-A for key 'A'
[PASS] Evaluator should be called once for key 'A'
[PASS] Cache should return cached Value-A for key 'A'
[PASS] Evaluator should not be called again for key 'A'
[PASS] Cache should compute and return Value-B for key 'B'
[PASS] Evaluator should be called once for key 'B'
[PASS] Cache should compute and return Value-C for key 'C'
[PASS] Evaluator should be called once for key 'C'
[PASS] Cache should compute and return Value-D for key 'D'
[PASS] Evaluator should be called once for key 'D'
[PASS] Cache should return Value-A (recomputed or cached)
Running: testEvictionStrategy
[PASS] Hot key 'A' should still be cached
[PASS] Evaluator should not be called again for hot key 'A'
[PASS] Key 'B' should return correct value (cached or recomputed)
[PASS] Key 'C' should return correct value (cached or recomputed)
Running: testMapFunction
[PASS] Mapped cache should return transformed value for key 'A'
[PASS] Evaluator should not be called again for cached key 'A'
[PASS] Mapped cache should compute and transform value for key 'C'
[PASS] Evaluator should be called once for key 'C'
[PASS] Original cache should return untransformed value
[PASS] Evaluator should not be called again
Running: testResetFunction
[PASS] Cache should return Initial-A for key 'A'
[PASS] Initial evaluator called once
[PASS] After reset, cache should return New-A
[PASS] New evaluator called once after reset
[PASS] New evaluator should compute New-B
[PASS] New evaluator called for key 'B'
[PASS] After reset without clear, cached 'A' should still return New-A
[PASS] Evaluator not called again for cached 'A'
Running: testEdgeCases
[PASS] Cache should return Value-null for null key
[PASS] Evaluator called once for null key
[PASS] Cache should hit for null key
[PASS] Evaluator not called again for null key
[PASS] Evaluator called for object key
[PASS] Evaluator not called again for same object key
[PASS] After first reset, returns Reset1-A
[PASS] Evaluator called once after first reset
[PASS] After second reset, returns Reset2-A
[PASS] Evaluator called once after second reset
Running: testNullValueEvaluator
[PASS] Evaluator returned null, get should return null
[PASS] Evaluator should be called once for 'A'
[PASS] Cached null should be returned on hit
[PASS] [CRITICAL-1] Evaluator must NOT be called again for cached null value
[PASS] All three null-value keys should be cached, no extra evaluator calls
Running: testUndefinedValueEvaluator
[PASS] Evaluator called once for 'X'
[PASS] [CRITICAL-1] Evaluator must NOT be called again for cached undefined value
Running: testCapacityInvariantLazyCache
  LazyCache: T1=50 T2=0 B1=0 B2=0
[PASS] [HIGH-2] |T1|+|T2|=50 should be <= capacity 50
[PASS] [HIGH-2] total=50 should be <= 2*capacity 100
Running: testGhostHitRoundTrip
[PASS] Evaluator should be called for ghost-hit key 'A'
[PASS] Recomputed value should be 'v5-A'
[PASS] After ghost-hit refill, 'A' should be cached — evaluator not called again
[PASS] Cached value should still be 'v5-A'
Running: testPutGetInteraction
[PASS] Manual put value should be returned, not evaluator result
[PASS] Evaluator should NOT be called for manually put key
[PASS] Manual put should override evaluator value
[PASS] Evaluator should not be called again after manual put
Running: testPerformance
[PASS] Evaluator should be called 1000 times to fill cache
Performance: 10000 cache hits took 44ms
[PASS] 10000 cache hits should complete in under 200ms (actual: 44ms)
=== ARCEnhancedLazyCacheTest v2.0: 58 assertions, 58 passed, 0 failed ===
