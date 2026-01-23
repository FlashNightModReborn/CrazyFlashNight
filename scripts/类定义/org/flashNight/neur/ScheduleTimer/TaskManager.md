org.flashNight.neur.ScheduleTimer.TaskManagerTester.runAllTests();


=====================================================
【TaskManager 完整测试套件】
=====================================================

--- 核心功能测试 (应全部通过) ---
Running testAddSingleTask...
Single task executed at frame 3
  [PASS] testAddSingleTask
Running testAddLoopTask...
Loop task executed, count=1 at frame 2
Loop task executed, count=2 at frame 4
Loop task executed, count=3 at frame 6
Loop task executed, count=4 at frame 8
Loop task executed, count=5 at frame 10
Loop task executed, count=6 at frame 12
Loop task executed, count=7 at frame 14
Loop task executed, count=8 at frame 16
Loop task executed, count=9 at frame 18
Loop task executed, count=10 at frame 20
  [PASS] testAddLoopTask
Running testAddOrUpdateTask...
First callback executed at frame 3
Updated callback executed at frame 12
  [PASS] testAddOrUpdateTask
Running testAddLifecycleTask...
Lifecycle task executed, count=1 at frame 2
Lifecycle task executed, count=2 at frame 4
Lifecycle task executed, count=3 at frame 6
Lifecycle task executed, count=4 at frame 8
Lifecycle task executed, count=5 at frame 10
Lifecycle task executed, count=6 at frame 12
Lifecycle task executed, count=7 at frame 14
Lifecycle task executed, count=8 at frame 16
Lifecycle task executed, count=9 at frame 18
Lifecycle task executed, count=10 at frame 20
  [PASS] testAddLifecycleTask
Running testRemoveTask...
  [PASS] testRemoveTask
Running testLocateTask...
LocateTask: Single task executed at frame 3
  [PASS] testLocateTask
Running testDelayTask...
After 3 frames, delay task executed? false
Delayed task executed at frame 5
After additional 2 frames, delay task executed? true
  [PASS] testDelayTask
Running testZeroIntervalTask...
Zero interval task executed immediately at frame 0
  [PASS] testZeroIntervalTask
Running testNegativeIntervalTask...
Negative interval task executed immediately at frame 0
  [PASS] testNegativeIntervalTask
Running testZeroRepeatCount...
Zero repeat count task executed, count=1 at frame 2
TestZeroRepeatCount: final count = 1
  [PASS] testZeroRepeatCount
Running testNegativeRepeatCount...
Negative repeat count task executed, count=1 at frame 2
TestNegativeRepeatCount: final count = 1
  [PASS] testNegativeRepeatCount
Running testTaskIDUniqueness...
Task IDs: 1, 2
  [PASS] testTaskIDUniqueness
Running testMixedScenarios...
Mixed scenario: Loop task executed, count=1 at frame 2
Mixed scenario: Lifecycle task executed, count=1 at frame 2
Mixed scenario: Single task executed at frame 3
Mixed scenario: Loop task executed, count=2 at frame 4
Mixed scenario: Lifecycle task executed, count=2 at frame 4
Mixed scenario: Loop task executed, count=3 at frame 6
Mixed scenario: Lifecycle task executed, count=3 at frame 6
Mixed scenario: Loop task executed, count=4 at frame 8
Mixed scenario: Lifecycle task executed, count=4 at frame 8
Mixed scenario: Loop task executed, count=5 at frame 10
Mixed scenario: Lifecycle task executed, count=5 at frame 10
Mixed scenario: Loop task executed, count=6 at frame 12
Mixed scenario: Lifecycle task executed, count=6 at frame 12
Mixed scenario: Loop task executed, count=7 at frame 14
Mixed scenario: Lifecycle task executed, count=7 at frame 14
Mixed scenario: Loop task executed, count=8 at frame 16
Mixed scenario: Lifecycle task executed, count=8 at frame 16
Mixed scenario: Loop task executed, count=9 at frame 18
Mixed scenario: Lifecycle task executed, count=9 at frame 18
Mixed scenario: Loop task executed, count=10 at frame 20
Mixed scenario: Lifecycle task executed, count=10 at frame 20
Mixed scenario: After 20 frames, singleExecuted=true, loopCount=10, lifecycleCount=10
Mixed scenario: Removed loop task at frame 20, prevLoopCount=10
Mixed scenario: Lifecycle task executed, count=11 at frame 22
Mixed scenario: Lifecycle task executed, count=12 at frame 24
Mixed scenario: Lifecycle task executed, count=13 at frame 26
Mixed scenario: Lifecycle task executed, count=14 at frame 28
Mixed scenario: Lifecycle task executed, count=15 at frame 30
Mixed scenario: After additional 10 frames, loopCount=10
Mixed scenario: Delayed lifecycle task at frame 30, prevLifecycleCount=15
Mixed scenario: Lifecycle task executed, count=16 at frame 35
Mixed scenario: After delay, lifecycleCount=16
  [PASS] testMixedScenarios
Running testConcurrentTasks...
Concurrent task 0 executed, count=1 at frame 2
Concurrent task 1 executed, count=1 at frame 3
Concurrent task 0 executed, count=2 at frame 4
Concurrent task 2 executed, count=1 at frame 5
Concurrent task 3 executed, count=1 at frame 6
Concurrent task 1 executed, count=2 at frame 6
Concurrent task 0 executed, count=3 at frame 6
Concurrent task 4 executed, count=1 at frame 8
Concurrent task 0 executed, count=4 at frame 8
Concurrent task 1 executed, count=3 at frame 9
Concurrent task 2 executed, count=2 at frame 10
Concurrent task 0 executed, count=5 at frame 10
Concurrent task 3 executed, count=2 at frame 12
Concurrent task 1 executed, count=4 at frame 12
Concurrent task 0 executed, count=6 at frame 12
Concurrent task 0 executed, count=7 at frame 14
Concurrent task 2 executed, count=3 at frame 15
Concurrent task 1 executed, count=5 at frame 15
Concurrent task 4 executed, count=2 at frame 16
Concurrent task 0 executed, count=8 at frame 16
Concurrent task 3 executed, count=3 at frame 18
Concurrent task 1 executed, count=6 at frame 18
Concurrent task 0 executed, count=9 at frame 18
Concurrent task 2 executed, count=4 at frame 20
Concurrent task 0 executed, count=10 at frame 20
Concurrent task 1 executed, count=7 at frame 21
Concurrent task 0 executed, count=11 at frame 22
Concurrent task 4 executed, count=3 at frame 24
Concurrent task 3 executed, count=4 at frame 24
Concurrent task 1 executed, count=8 at frame 24
Concurrent task 0 executed, count=12 at frame 24
Concurrent task 2 executed, count=5 at frame 25
Concurrent task 0 executed, count=13 at frame 26
Concurrent task 1 executed, count=9 at frame 27
Concurrent task 0 executed, count=14 at frame 28
Concurrent task 3 executed, count=5 at frame 30
Concurrent task 2 executed, count=6 at frame 30
Concurrent task 1 executed, count=10 at frame 30
Concurrent task 0 executed, count=15 at frame 30
  [PASS] testConcurrentTasks
Running testTaskIDCounterConsistency...
Generated task IDs: 1, 2, 3, 4, 5
  [PASS] testTaskIDCounterConsistency
  [PASS] testZombieTaskFix_v1_1
  [PASS] testRescheduleNodeReferenceFix_v1_1
  [PASS] testNodePoolReuse_v1_1
Running testGhostIDFix_v1_3...
First task ID: 1
Manually removed first task
obj.taskLabel['ghostTest'] after removal: 1
Second task ID: 2
  [PASS] testGhostIDFix_v1_3
Running testZeroDelayBoundaryFix_v1_3...
[FIX v1.3] Zero delay task executed at frame 1
  [PASS] testZeroDelayBoundaryFix_v1_3
Running testArrayReuseFix_v1_3...
_reusableZeroIds length after updateFrame: 3
_reusableToDelete length after updateFrame: 3
  [PASS] testArrayReuseFix_v1_3
Running testFramesPerMsRename_v1_3...
  [PASS] testFramesPerMsRename_v1_3
Running testLifecycleTaskIDReuseBug...
First task ID: 1
obj.taskLabel['testLabel']: 1
First lifecycle task executed, count=1 at frame 2
First lifecycle task executed, count=2 at frame 4
First lifecycle task executed, count=3 at frame 6
First lifecycle task executed, count=4 at frame 8
First lifecycle task executed, count=5 at frame 10
First task execution count after 10 frames: 5
Manually removed first task
obj.taskLabel['testLabel'] after manual removal: 1
Second task ID: 2
Task ID reuse detected: NO (correct)
Second lifecycle task executed, count=1 at frame 12
Second lifecycle task executed, count=2 at frame 14
Second lifecycle task executed, count=3 at frame 16
Second lifecycle task executed, count=4 at frame 18
Second lifecycle task executed, count=5 at frame 20
Second task execution count: 5 (should be > 0)
  [PASS] testLifecycleTaskIDReuseBug
Running testExpiredNodeRecycling_v1_4...
Initial node pool size: 770
After adding 10 tasks, pool size: 760
After execution, pool size: 770
  [PASS] testExpiredNodeRecycling_v1_4
Running testLoopTaskNodeRecycling_v1_4...
Initial pool size: 750
Loop task executed 30 times
After loop executions, pool size: 749
  [PASS] testLoopTaskNodeRecycling_v1_4
Running testOwnerTypeRemovalDispatch_v1_4...
Short task ownerType: 1
Long task ownerType: 3
  [PASS] testOwnerTypeRemovalDispatch_v1_4
Running testSharedNodePoolIntegration_v1_5...
Initial pool size: 750
After adding 3 tasks to different wheels, pool size: 747
After removing all tasks, pool size: 750
  [PASS] testSharedNodePoolIntegration_v1_5
Running testDoubleRecycleProtection_v1_5...
After acquire, pool size: 749
After first recycle, pool size: 750
After second recycle, pool size: 750
  [PASS] testDoubleRecycleProtection_v1_5
Running testMinHeapCallbackSelfRemoval_v1_6...
Task ownerType: 3
Testing min heap removeNode with extracted frame...
Heap task found, simulating self-removal...
Self-removal completed without crash - FIX VERIFIED
  [PASS] testMinHeapCallbackSelfRemoval_v1_6
Running testAddOrUpdateTaskGhostID_v1_6...
First task ID: 2
obj.taskLabel['ghostTestLabel']: 2
First task execution count: 1
Manually removed first task
obj.taskLabel['ghostTestLabel'] after removal: 2
Second task ID: 3
  [PASS] testAddOrUpdateTaskGhostID_v1_6
Running testRemoveLifecycleTaskAPI_v1_6...
Task ID: 1
Execution count after 10 frames: 5
removeLifecycleTask result: true
  [PASS] testRemoveLifecycleTaskAPI_v1_6
Running testChainBreakingWheel_v1_7...
[v1.7 S1 Wheel] A executed at frame 3, removing B...
[v1.7 S1 Wheel] C executed at frame 3
[v1.7 S1 Wheel] PASS: Chain-breaking prevented, C executed correctly
  [PASS] testChainBreakingWheel_v1_7
Running testChainBreakingHeap_v1_7...
[v1.7 S1 Heap] A executed at frame 260, removing B...
[v1.7 S1 Heap] C executed at frame 260
[v1.7 S1 Heap] PASS: Chain-breaking prevented in heap tasks
  [PASS] testChainBreakingHeap_v1_7
Running testNeverEarlyTrigger_v1_7...
[v1.7 P0-3] Never-Early 测试完成:
  总测试数: 116
  提前触发数: 0
  二级最大延后: 9 帧
  三级最大延后: 47 帧
  [PASS] testNeverEarlyTrigger_v1_7
Running testStressRandomOps_v1_7...
[v1.7 Stress] 压测完成:
  总帧数: 3000
  创建任务: 1255
  取消任务: 579
  延迟任务: 332
  执行回调: 1417
  峰值活跃: 96
  最终活跃: 67
  节点池大小: 99
  [PASS] testStressRandomOps_v1_7
Running testDelayTaskNonNumeric...
DEBUG: isNaN(true) = false
DEBUG: typeof(true) = boolean
DEBUG: Number(true) = 1
Task executed after delay(true): false at frame 10
Non-numeric delay task pendingFrames: Infinity
  [PASS] testDelayTaskNonNumeric
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
Task pendingFrames after delay(true): Infinity
Correct: Task properly delayed to infinity
Task correctly delayed
  [PASS] testAS2TypeCheckingIssue
Running testRepeatingRemoveDuringDispatch_v1_7_1...
[v1.7.1 Dispatch] A first exec at frame 3, removing B...
[v1.7.1 Dispatch] aCount=3, bCount=0
  [PASS] testRepeatingRemoveDuringDispatch_v1_7_1
Running testDelayTaskDuringDispatch_v1_7_1...
[v1.7.1 DelayDispatch] A executed at frame 3, delaying B by 200ms...
[v1.7.1 DelayDispatch] C executed at frame 3
[v1.7.1 DelayDispatch] B executed at frame 12
[v1.7.1 DelayDispatch] PASS: B executed at frame 12 (delayed from frame 3)
  [PASS] testDelayTaskDuringDispatch_v1_7_1
Running testDelayTaskDuringDispatch_Reschedule_v1_7_1...
[v1.7.1 RescheduleDispatch] A delaying B at frame 3
[v1.7.1 RescheduleDispatch] B executed at frame 12
[v1.7.1 RescheduleDispatch] B executed at frame 15
[v1.7.1 RescheduleDispatch] B executed at frame 18
[v1.7.1 RescheduleDispatch] aCount=6, bCount=3, bFirstFrame=12, bLastFrame=18
  [PASS] testDelayTaskDuringDispatch_Reschedule_v1_7_1
Running testAddToMinHeapByIDPoolRecycling_v1_7_1...
[v1.7.1 HeapPool] Initial - wheel pool: 750, heap pool: 128
[v1.7.1 HeapPool] After add - wheel pool: 750, heap pool: 123
[v1.7.1 HeapPool] After recycle - wheel pool: 750, heap pool: 128
[v1.8 HeapPool] PASS: ownerType-based recycling verified. addToMinHeapByID nodes (ownerType=4) correctly recycled back to heap pool. Heap recovered: 5/5
  [PASS] testAddToMinHeapByIDPoolRecycling_v1_7_1
Running testRemoveOverridesDelayDuringDispatch_v1_7_2...
[v1.7.2 RemoveOverride] A delaying then removing B at frame 3
[v1.7.2 RemoveOverride] aCount=10, bCount=0
[v1.7.2 RemoveOverride] PASS: removeTask correctly overrides delayTask during dispatch
  [PASS] testRemoveOverridesDelayDuringDispatch_v1_7_2
Running testRemoveThenDelayFailsDuringDispatch_v1_7_2...
[v1.7.2 DelayAfterRemove] A: delay→remove→delay(B) at frame 3
[v1.7.2 DelayAfterRemove] First delayTask result: true
[v1.7.2 DelayAfterRemove] Second delayTask result: false
[v1.7.2 DelayAfterRemove] aCount=10, bCount=0, secondDelayResult=false
[v1.7.2 DelayAfterRemove] PASS: delay after remove correctly returns false
  [PASS] testRemoveThenDelayFailsDuringDispatch_v1_7_2

--- 已知限制/Bug复现测试 (部分预期失败) ---
Running testRaceConditionBug...
Initial task ID: 1
Race condition task executed, count=1 at frame 2
Race condition task executed, count=2 at frame 4
Task removing itself at execution #2
Task exists before removal: true
Task exists after removal: false
Task removal completed
Task location after self-removal: null (correct)
Execution count before additional frames: 2
Execution count after additional frames: 2
WARNING: Race condition test passed, but the risk still exists in the code!
The bug may manifest under different timing or load conditions.
  [PASS] testRaceConditionBug

=====================================================
【测试结果汇总】
-----------------------------------------------------
  核心功能测试: 43/43 通过 [OK]
  已知限制测试: 1/1 通过
-----------------------------------------------------
  总计: 44/44 通过
=====================================================
[OK] 核心功能测试全部通过！
