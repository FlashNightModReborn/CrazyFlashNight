new org.flashNight.sara.util.LightObjectPoolTest();

Starting Basic Functionality Tests...
[PASS] Initial pool size is zero
[PASS] getObject returns a new object
[PASS] Pool size remains zero after getting new object
[PASS] releaseObject adds object back to the pool
[PASS] getObject returns the previously released object
[PASS] Pool size decrements after retrieving an object
[PASS] Releasing undefined does not throw error
Basic Functionality Tests Completed.
Starting Clear Pool Tests...
[PASS] Pool size is 5 after releasing 5 distinct objects
[PASS] clearPool sets pool size to 0
Clear Pool Tests Completed.
Starting Performance Tests...
Performed 10000 getObject and releaseObject operations in 26 ms
[PASS] Performance: 10000 getObject/releaseObject operations < 100 ms
Performed 10000 continuous getObject and releaseObject operations in 25 ms
[PASS] Performance: 10000 continuous getObject/releaseObject operations < 100 ms
Performance Tests Completed.
Starting Practical Performance Tests...
Performed 10000 mixed operations in 30 ms
[PASS] Performance: 10000 mixed operations < 150 ms
Practical Performance Tests Completed.
----- Test Results -----
------------------------
Total Tests: 12, Passed: 12, Failed: 0
