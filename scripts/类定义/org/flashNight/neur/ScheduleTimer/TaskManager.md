org.flashNight.neur.ScheduleTimer.TaskManagerTester.runAllTests();


Starting TaskManager tests...
-----------------------------------------------------
Running testAddSingleTask...
Single task executed at frame 3
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 10 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
-----------------------------------------------------
-----------------------------------------------------
Running testAddLoopTask...
Loop task executed, count=1 at frame 2
Loop task executed, count=2 at frame 4
----- Debug Info at Frame 5 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Loop task executed, count=3 at frame 6
Loop task executed, count=4 at frame 8
Loop task executed, count=5 at frame 10
----- Debug Info at Frame 10 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Loop task executed, count=6 at frame 12
Loop task executed, count=7 at frame 14
----- Debug Info at Frame 15 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Loop task executed, count=8 at frame 16
Loop task executed, count=9 at frame 18
Loop task executed, count=10 at frame 20
----- Debug Info at Frame 20 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
-----------------------------------------------------
-----------------------------------------------------
Running testAddOrUpdateTask...
First callback executed at frame 3
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 10 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
Updated callback executed at frame 12
----- Debug Info at Frame 15 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 20 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
-----------------------------------------------------
-----------------------------------------------------
Running testAddLifecycleTask...
Lifecycle task executed, count=1 at frame 2
Lifecycle task executed, count=2 at frame 4
----- Debug Info at Frame 5 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Lifecycle task executed, count=3 at frame 6
Lifecycle task executed, count=4 at frame 8
Lifecycle task executed, count=5 at frame 10
----- Debug Info at Frame 10 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Lifecycle task executed, count=6 at frame 12
Lifecycle task executed, count=7 at frame 14
----- Debug Info at Frame 15 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Lifecycle task executed, count=8 at frame 16
Lifecycle task executed, count=9 at frame 18
Lifecycle task executed, count=10 at frame 20
----- Debug Info at Frame 20 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
-----------------------------------------------------
-----------------------------------------------------
Running testRemoveTask...
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 10 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
-----------------------------------------------------
-----------------------------------------------------
Running testLocateTask...
LocateTask: Single task executed at frame 3
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 10 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
-----------------------------------------------------
-----------------------------------------------------
Running testDelayTask...
After 3 frames, delay task executed? false
Delayed task executed at frame 5
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
After additional 2 frames, delay task executed? true
-----------------------------------------------------
-----------------------------------------------------
Running testDelayTaskNonNumeric...
DEBUG: isNaN(true) = false
DEBUG: typeof(true) = boolean
DEBUG: Number(true) = 1
Non-numeric delay task executed at frame 4 (BUG!)
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 10 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
Task executed after delay(true): true at frame 10
Assertion failed at frame 10: Task with non-numeric delay (true) should not execute
Task not found - may have been executed and removed
Assertion failed: Task with non-numeric delay (true) should not execute (at frame 10)
-----------------------------------------------------
-----------------------------------------------------
Running testZeroIntervalTask...
Zero interval task executed immediately at frame 0
-----------------------------------------------------
-----------------------------------------------------
Running testNegativeIntervalTask...
Negative interval task executed immediately at frame 0
-----------------------------------------------------
-----------------------------------------------------
Running testZeroRepeatCount...
Zero repeat count task executed, count=1 at frame 2
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 10 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
TestZeroRepeatCount: final count = 1
-----------------------------------------------------
-----------------------------------------------------
Running testNegativeRepeatCount...
Negative repeat count task executed, count=1 at frame 2
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 10 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
TestNegativeRepeatCount: final count = 1
-----------------------------------------------------
-----------------------------------------------------
Running testTaskIDUniqueness...
Task IDs: 1, 2
-----------------------------------------------------
-----------------------------------------------------
Running testMixedScenarios...
Mixed scenario: Loop task executed, count=1 at frame 2
Mixed scenario: Lifecycle task executed, count=1 at frame 2
Mixed scenario: Single task executed at frame 3
Mixed scenario: Loop task executed, count=2 at frame 4
Mixed scenario: Lifecycle task executed, count=2 at frame 4
----- Debug Info at Frame 5 -----
Task Table keys: 3 2 
ZeroFrame Tasks keys: 
---------------------------------------------
Mixed scenario: Loop task executed, count=3 at frame 6
Mixed scenario: Lifecycle task executed, count=3 at frame 6
Mixed scenario: Loop task executed, count=4 at frame 8
Mixed scenario: Lifecycle task executed, count=4 at frame 8
Mixed scenario: Loop task executed, count=5 at frame 10
Mixed scenario: Lifecycle task executed, count=5 at frame 10
----- Debug Info at Frame 10 -----
Task Table keys: 3 2 
ZeroFrame Tasks keys: 
---------------------------------------------
Mixed scenario: Loop task executed, count=6 at frame 12
Mixed scenario: Lifecycle task executed, count=6 at frame 12
Mixed scenario: Loop task executed, count=7 at frame 14
Mixed scenario: Lifecycle task executed, count=7 at frame 14
----- Debug Info at Frame 15 -----
Task Table keys: 3 2 
ZeroFrame Tasks keys: 
---------------------------------------------
Mixed scenario: Loop task executed, count=8 at frame 16
Mixed scenario: Lifecycle task executed, count=8 at frame 16
Mixed scenario: Loop task executed, count=9 at frame 18
Mixed scenario: Lifecycle task executed, count=9 at frame 18
Mixed scenario: Loop task executed, count=10 at frame 20
Mixed scenario: Lifecycle task executed, count=10 at frame 20
----- Debug Info at Frame 20 -----
Task Table keys: 3 2 
ZeroFrame Tasks keys: 
---------------------------------------------
Mixed scenario: After 20 frames, singleExecuted=true, loopCount=10, lifecycleCount=10
Mixed scenario: Removed loop task at frame 20, prevLoopCount=10
Mixed scenario: Lifecycle task executed, count=11 at frame 22
Mixed scenario: Lifecycle task executed, count=12 at frame 24
----- Debug Info at Frame 25 -----
Task Table keys: 3 
ZeroFrame Tasks keys: 
---------------------------------------------
Mixed scenario: Lifecycle task executed, count=13 at frame 26
Mixed scenario: Lifecycle task executed, count=14 at frame 28
Mixed scenario: Lifecycle task executed, count=15 at frame 30
----- Debug Info at Frame 30 -----
Task Table keys: 3 
ZeroFrame Tasks keys: 
---------------------------------------------
Mixed scenario: After additional 10 frames, loopCount=10
Mixed scenario: Delayed lifecycle task at frame 30, prevLifecycleCount=15
Mixed scenario: Lifecycle task executed, count=16 at frame 35
----- Debug Info at Frame 35 -----
Task Table keys: 3 
ZeroFrame Tasks keys: 
---------------------------------------------
Mixed scenario: After delay, lifecycleCount=16
-----------------------------------------------------
-----------------------------------------------------
Running testConcurrentTasks...
Concurrent task 0 executed, count=1 at frame 2
Concurrent task 1 executed, count=1 at frame 3
Concurrent task 0 executed, count=2 at frame 4
Concurrent task 2 executed, count=1 at frame 5
----- Debug Info at Frame 5 -----
Task Table keys: 5 4 3 2 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Concurrent task 3 executed, count=1 at frame 6
Concurrent task 1 executed, count=2 at frame 6
Concurrent task 0 executed, count=3 at frame 6
Concurrent task 4 executed, count=1 at frame 8
Concurrent task 0 executed, count=4 at frame 8
Concurrent task 1 executed, count=3 at frame 9
Concurrent task 2 executed, count=2 at frame 10
Concurrent task 0 executed, count=5 at frame 10
----- Debug Info at Frame 10 -----
Task Table keys: 5 4 3 2 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Concurrent task 3 executed, count=2 at frame 12
Concurrent task 1 executed, count=4 at frame 12
Concurrent task 0 executed, count=6 at frame 12
Concurrent task 0 executed, count=7 at frame 14
Concurrent task 2 executed, count=3 at frame 15
Concurrent task 1 executed, count=5 at frame 15
----- Debug Info at Frame 15 -----
Task Table keys: 5 4 3 2 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Concurrent task 4 executed, count=2 at frame 16
Concurrent task 0 executed, count=8 at frame 16
Concurrent task 3 executed, count=3 at frame 18
Concurrent task 1 executed, count=6 at frame 18
Concurrent task 0 executed, count=9 at frame 18
Concurrent task 2 executed, count=4 at frame 20
Concurrent task 0 executed, count=10 at frame 20
----- Debug Info at Frame 20 -----
Task Table keys: 5 4 3 2 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Concurrent task 1 executed, count=7 at frame 21
Concurrent task 0 executed, count=11 at frame 22
Concurrent task 4 executed, count=3 at frame 24
Concurrent task 3 executed, count=4 at frame 24
Concurrent task 1 executed, count=8 at frame 24
Concurrent task 0 executed, count=12 at frame 24
Concurrent task 2 executed, count=5 at frame 25
----- Debug Info at Frame 25 -----
Task Table keys: 5 4 3 2 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Concurrent task 0 executed, count=13 at frame 26
Concurrent task 1 executed, count=9 at frame 27
Concurrent task 0 executed, count=14 at frame 28
Concurrent task 3 executed, count=5 at frame 30
Concurrent task 2 executed, count=6 at frame 30
Concurrent task 1 executed, count=10 at frame 30
Concurrent task 0 executed, count=15 at frame 30
----- Debug Info at Frame 30 -----
Task Table keys: 5 4 3 2 1 
ZeroFrame Tasks keys: 
---------------------------------------------
-----------------------------------------------------
-----------------------------------------------------
Running testRaceConditionBug...
Initial task ID: 1
Race condition task executed, count=1 at frame 2
Race condition task executed, count=2 at frame 4
Task removing itself at execution #2
Task exists before removal: true
Task exists after removal: false
Task removal completed
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 10 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 15 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 20 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 25 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
Task location after self-removal: null (correct)
Execution count before additional frames: 2
----- Debug Info at Frame 30 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 35 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
----- Debug Info at Frame 40 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
Execution count after additional frames: 2
WARNING: Race condition test passed, but the risk still exists in the code!
The bug may manifest under different timing or load conditions.
-----------------------------------------------------
-----------------------------------------------------
Running testAS2TypeCheckingIssue...
=== AS2 Type Checking Behavior Analysis ===
Value: true (type: boolean)
  isNaN(val): false
  Number(val): 1
  typeof(val) != 'number': true
  ---
Value: false (type: boolean)
  isNaN(val): false
  Number(val): 0
  typeof(val) != 'number': true
  ---
Value: string (type: string)
  isNaN(val): true
  Number(val): NaN
  typeof(val) != 'number': true
  ---
Value: null (type: null)
  isNaN(val): true
  Number(val): NaN
  typeof(val) != 'number': true
  ---
Value: undefined (type: undefined)
  isNaN(val): true
  Number(val): NaN
  typeof(val) != 'number': true
  ---
Value: 0 (type: number)
  isNaN(val): false
  Number(val): 0
  typeof(val) != 'number': false
  ---
Value: 1 (type: number)
  isNaN(val): false
  Number(val): 1
  typeof(val) != 'number': false
  ---
Value: NaN (type: number)
  isNaN(val): true
  Number(val): NaN
  typeof(val) != 'number': false
  ---
=== Bug Demonstration ===
delayTask expects non-numeric values to set infinite delay
But isNaN(true) = false (should be true for infinite delay)
Correct check: typeof(true) != 'number' = true
Applying delay with boolean true...
Task pendingFrames after delay(true): 3
BUG: Task pendingFrames is not infinity, will execute soon!
Task executed due to AS2 type checking bug!
----- Debug Info at Frame 5 -----
Task Table keys: 
ZeroFrame Tasks keys: 
---------------------------------------------
CONFIRMED BUG: Task executed despite delay(true)
-----------------------------------------------------
-----------------------------------------------------
Running testLifecycleTaskIDReuseBug...
First task ID: 1
obj.taskLabel['testLabel']: 1
First lifecycle task executed, count=1 at frame 2
First lifecycle task executed, count=2 at frame 4
----- Debug Info at Frame 5 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
First lifecycle task executed, count=3 at frame 6
First lifecycle task executed, count=4 at frame 8
First lifecycle task executed, count=5 at frame 10
----- Debug Info at Frame 10 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
First task execution count after 10 frames: 5
Manually removed first task
obj.taskLabel['testLabel'] after manual removal: 1
Second task ID: 1
Task ID reuse detected: YES (BUG!)
Assertion failed at frame 10: Task ID should not be reused! First ID: 1, Second ID: 1
Second lifecycle task executed, count=1 at frame 12
Second lifecycle task executed, count=2 at frame 14
----- Debug Info at Frame 15 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Second lifecycle task executed, count=3 at frame 16
Second lifecycle task executed, count=4 at frame 18
Second lifecycle task executed, count=5 at frame 20
----- Debug Info at Frame 20 -----
Task Table keys: 1 
ZeroFrame Tasks keys: 
---------------------------------------------
Second task execution count: 5 (should be > 0)
Assertion failed: Task ID should not be reused! First ID: 1, Second ID: 1 (at frame 10)
-----------------------------------------------------
-----------------------------------------------------
Running testTaskIDCounterConsistency...
Generated task IDs: 1, 2, 3, 4, 5
-----------------------------------------------------
All tests completed.
