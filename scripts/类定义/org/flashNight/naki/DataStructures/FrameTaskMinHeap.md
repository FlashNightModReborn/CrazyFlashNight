import org.flashNight.naki.DataStructures.*;

// 创建测试类实例
var tester:FrameTaskMinHeapTest = new FrameTaskMinHeapTest();
tester.runFullTests();

╔════════════════════════════════════════════════════════════╗
║        FrameTaskMinHeap Complete Test Suite                ║
╚════════════════════════════════════════════════════════════╝

=== Running Functional Tests ===
PASS: Insert operations correctly identify the minimum frame index.
PASS: Insert operations correctly schedule tasks at their intended frames.
PASS: FindNodeById correctly locates existing tasks.
PASS: FindNodeById returns null for non-existent tasks.
PASS: PeekMin correctly identifies the minimum frame index.
PASS: PeekMin correctly identifies tasks at the minimum frame.
PASS: PeekMin returns null for an empty heap.
PASS: RemoveById correctly deletes the specified task.
PASS: Heap correctly updates the minimum frame after removal.
PASS: RescheduleTimerByID correctly updates the task's frame index.
PASS: Heap correctly updates the minimum frame after rescheduling.
PASS: Tick correctly retrieves due tasks at frame 1.
PASS: Tick correctly identifies the due task at frame 1.
PASS: Tick correctly retrieves due tasks at frame 2.
PASS: Tick correctly identifies the due task at frame 2.
PASS: Tick correctly retrieves due tasks at frame 3.
PASS: Tick correctly identifies the due task at frame 3.
PASS: Tick returns null when there are no due tasks.
PASS: RemoveById gracefully handles non-existent task IDs without affecting existing tasks.
PASS: RescheduleTimerByID gracefully handles non-existent task IDs without affecting existing tasks.
PASS: Inserting a duplicate task ID updates the existing task's frame index.
=== Functional Tests Completed ===

=== Running Heap Integrity Tests ===

--- BubbleUp Tests ---
PASS: BubbleUp descending: heap top should be 1, got 1
PASS: BubbleUp descending: index mapping should be consistent
PASS: BubbleUp descending: min-heap property should hold
PASS: BubbleUp descending: extraction order violated at count 0
PASS: BubbleUp descending: extraction order violated at count 1
PASS: BubbleUp descending: extraction order violated at count 2
PASS: BubbleUp descending: extraction order violated at count 3
PASS: BubbleUp descending: extraction order violated at count 4
PASS: BubbleUp descending: extraction order violated at count 5
PASS: BubbleUp descending: extraction order violated at count 6
PASS: BubbleUp descending: extraction order violated at count 7
PASS: BubbleUp descending: extraction order violated at count 8
PASS: BubbleUp descending: extraction order violated at count 9
PASS: BubbleUp descending: extraction order violated at count 10
PASS: BubbleUp descending: extraction order violated at count 11
PASS: BubbleUp descending: extraction order violated at count 12
PASS: BubbleUp descending: extraction order violated at count 13
PASS: BubbleUp descending: extraction order violated at count 14
PASS: BubbleUp descending: extraction order violated at count 15
PASS: BubbleUp descending: extraction order violated at count 16
PASS: BubbleUp descending: extraction order violated at count 17
PASS: BubbleUp descending: extraction order violated at count 18
PASS: BubbleUp descending: extraction order violated at count 19
PASS: BubbleUp descending: should extract 20 tasks, got 20
PASS: BubbleUp random: index mapping should be consistent
PASS: BubbleUp random: min-heap property should hold
PASS: BubbleUp random: extraction order should be ascending
PASS: BubbleUp large scale: index mapping should be consistent
PASS: BubbleUp large scale: min-heap property should hold
PASS: BubbleUp large scale: should extract 100 tasks
PASS: BubbleUp all methods: index mapping should be consistent
PASS: BubbleUp all methods: min-heap property should hold
PASS: BubbleUp all methods: min should be 5, got 5

--- SinkDown Tests ---
PASS: SinkDown extract: frame 1 should be >= -1
PASS: SinkDown extract: frame 2 should be >= 1
PASS: SinkDown extract: frame 3 should be >= 2
PASS: SinkDown extract: frame 4 should be >= 3
PASS: SinkDown extract: frame 5 should be >= 4
PASS: SinkDown extract: frame 6 should be >= 5
PASS: SinkDown extract: frame 7 should be >= 6
PASS: SinkDown extract: frame 8 should be >= 7
PASS: SinkDown extract: frame 9 should be >= 8
PASS: SinkDown extract: frame 10 should be >= 9
PASS: SinkDown extract: frame 11 should be >= 10
PASS: SinkDown extract: frame 12 should be >= 11
PASS: SinkDown extract: frame 14 should be >= 12
PASS: SinkDown extract: frame 14 should be >= 14
PASS: SinkDown extract: frame 15 should be >= 14
PASS: SinkDown extract: frame 18 should be >= 15
PASS: SinkDown extract: frame 18 should be >= 18
PASS: SinkDown extract: frame 18 should be >= 18
PASS: SinkDown extract: should extract all 15 unique frames, got 15
PASS: SinkDown remove middle: mapping valid after removing task7
PASS: SinkDown remove middle: heap property valid after removing task7
PASS: SinkDown remove middle: mapping valid after removing task10
PASS: SinkDown remove middle: heap property valid after removing task10
PASS: SinkDown remove middle: mapping valid after removing task13
PASS: SinkDown remove middle: heap property valid after removing task13
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 0
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 1
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 2
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 3
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 4
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 5
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 6
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 7
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 8
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 9
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 10
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 11
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 12
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 13
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 14
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 15
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: order violated at count 16
PASS: SinkDown remove middle: should extract 17 frames, got 17
PASS: SinkDown remove root: mapping valid after removal 1
PASS: SinkDown remove root: heap property valid after removal 1
PASS: SinkDown remove root: mapping valid after removal 2
PASS: SinkDown remove root: heap property valid after removal 2
PASS: SinkDown remove root: mapping valid after removal 3
PASS: SinkDown remove root: heap property valid after removal 3
PASS: SinkDown remove leaf: mapping valid after removing task7
PASS: SinkDown remove leaf: heap property valid after removing task7
PASS: SinkDown remove leaf: mapping valid after removing task6
PASS: SinkDown remove leaf: heap property valid after removing task6
PASS: SinkDown remove leaf: mapping valid after removing task5
PASS: SinkDown remove leaf: heap property valid after removing task5

--- Index Mapping Tests ---
PASS: Index mapping insert: valid after inserting task0 with delay 30
PASS: Index mapping insert: valid after inserting task1 with delay 10
PASS: Index mapping insert: valid after inserting task2 with delay 50
PASS: Index mapping insert: valid after inserting task3 with delay 20
PASS: Index mapping insert: valid after inserting task4 with delay 40
PASS: Index mapping insert: valid after inserting task5 with delay 5
PASS: Index mapping insert: valid after inserting task6 with delay 25
PASS: Index mapping insert: valid after inserting task7 with delay 35
PASS: Index mapping insert: valid after inserting task8 with delay 15
PASS: Index mapping insert: valid after inserting task9 with delay 45
PASS: Index mapping removal: valid after removing task7
PASS: Index mapping removal: valid after removing task3
PASS: Index mapping removal: valid after removing task12
PASS: Index mapping removal: valid after removing task1
PASS: Index mapping removal: valid after removing task15
PASS: Index mapping extract: valid after extraction 1
PASS: Index mapping extract: valid after extraction 2
PASS: Index mapping extract: valid after extraction 3
PASS: Index mapping extract: valid after extraction 4
PASS: Index mapping extract: valid after extraction 5
PASS: Index mapping extract: valid after extraction 6
PASS: Index mapping extract: valid after extraction 7
PASS: Index mapping extract: valid after extraction 8
PASS: Index mapping extract: valid after extraction 9
PASS: Index mapping extract: valid after extraction 10

--- Min-Heap Property Tests ---
PASS: Min-heap property insert: valid after inserting 25
PASS: Min-heap property insert: valid after inserting 10
PASS: Min-heap property insert: valid after inserting 45
PASS: Min-heap property insert: valid after inserting 5
PASS: Min-heap property insert: valid after inserting 30
PASS: Min-heap property insert: valid after inserting 15
PASS: Min-heap property insert: valid after inserting 50
PASS: Min-heap property insert: valid after inserting 20
PASS: Min-heap property insert: valid after inserting 35
PASS: Min-heap property insert: valid after inserting 8
PASS: Min-heap property insert: valid after inserting 40
PASS: Min-heap property insert: valid after inserting 12
PASS: Min-heap property insert: valid after inserting 55
PASS: Min-heap property insert: valid after inserting 18
PASS: Min-heap property insert: valid after inserting 28
PASS: Min-heap property insert: valid after inserting 3
PASS: Min-heap property insert: valid after inserting 60
PASS: Min-heap property insert: valid after inserting 22
PASS: Min-heap property insert: valid after inserting 38
PASS: Min-heap property insert: valid after inserting 7
PASS: Min-heap property removal: valid after removing task5
PASS: Min-heap property removal: valid after removing task12
PASS: Min-heap property removal: valid after removing task3
PASS: Min-heap property removal: valid after removing task20
PASS: Min-heap property removal: valid after removing task8
PASS: Min-heap property removal: valid after removing task15
PASS: Min-heap property removal: valid after removing task0
PASS: Min-heap property removal: valid after removing task24
PASS: Min-heap property extract: valid after extraction 1
PASS: Min-heap property extract: valid after extraction 2
PASS: Min-heap property extract: valid after extraction 3
PASS: Min-heap property extract: valid after extraction 4
PASS: Min-heap property extract: valid after extraction 5
PASS: Min-heap property extract: valid after extraction 6
PASS: Min-heap property extract: valid after extraction 7
PASS: Min-heap property extract: valid after extraction 8
PASS: Min-heap property extract: valid after extraction 9
PASS: Min-heap property extract: valid after extraction 10
PASS: Min-heap property extract: valid after extraction 11
PASS: Min-heap property extract: valid after extraction 12
PASS: Min-heap property extract: valid after extraction 13
PASS: Min-heap property extract: valid after extraction 14
PASS: Min-heap property extract: valid after extraction 15
PASS: Min-heap property extract: valid after extraction 16
PASS: Min-heap property extract: valid after extraction 17
PASS: Min-heap property extract: valid after extraction 18
PASS: Min-heap property extract: valid after extraction 19
PASS: Min-heap property extract: valid after extraction 20

--- Edge Case Tests ---
PASS: Single element: correct frame
PASS: Single element: index mapping valid
PASS: Single element: should be extracted
PASS: Single element: heap should be empty after extraction
PASS: Same frame: heap should have size 1, got 1
PASS: Same frame: index mapping valid
PASS: Same frame: should get tasks
PASS: Same frame: should have 10 tasks, got 10
PASS: Various children: index mapping valid
PASS: Various children: min-heap property valid
PASS: Various children: order violated at 0, expected >= -1 got 1
PASS: Various children: order violated at 1, expected >= 1 got 2
PASS: Various children: order violated at 2, expected >= 2 got 3
PASS: Various children: order violated at 3, expected >= 3 got 4
PASS: Various children: order violated at 4, expected >= 4 got 5
PASS: Various children: order violated at 5, expected >= 5 got 6
PASS: Various children: order violated at 6, expected >= 6 got 7
PASS: Various children: order violated at 7, expected >= 7 got 8
PASS: Various children: order violated at 8, expected >= 8 got 9
PASS: Various children: order violated at 9, expected >= 9 got 10
PASS: Various children: order violated at 10, expected >= 10 got 11
PASS: Various children: order violated at 11, expected >= 11 got 12
PASS: Various children: order violated at 12, expected >= 12 got 13
PASS: Various children: order violated at 13, expected >= 13 got 14
PASS: Various children: order violated at 14, expected >= 14 got 15
PASS: Various children: order violated at 15, expected >= 15 got 16
PASS: Various children: order violated at 16, expected >= 16 got 17
PASS: Various children: order violated at 17, expected >= 17 got 18
PASS: Various children: order violated at 18, expected >= 18 got 19
PASS: Various children: order violated at 19, expected >= 19 got 20
PASS: Various children: order violated at 20, expected >= 20 got 21
PASS: Various children: should extract 21 tasks
PASS: Alternating ops: mapping valid at iteration 0
PASS: Alternating ops: heap property valid at iteration 0
PASS: Alternating ops: mapping valid at iteration 1
PASS: Alternating ops: heap property valid at iteration 1
PASS: Alternating ops: mapping valid at iteration 2
PASS: Alternating ops: heap property valid at iteration 2
PASS: Alternating ops: mapping valid at iteration 3
PASS: Alternating ops: heap property valid at iteration 3
PASS: Alternating ops: mapping valid at iteration 4
PASS: Alternating ops: heap property valid at iteration 4
PASS: Alternating ops: mapping valid after extract 0
PASS: Alternating ops: mapping valid after extract 1
PASS: Alternating ops: mapping valid after extract 2

=== Heap Integrity Tests Completed ===

========================================
开始 FIX v1.6 验证测试
========================================
=== [FIX v1.6] Testing removeNode Defensive Check ===
Task inserted at frameIndex: 5
Extracted tasks at frame: 5
Attempting to remove node after extraction...
removeDirectly completed without error
PASS: removeNode defensive: heap property should hold after defensive removal
PASS: removeNode defensive: should not throw error
=== removeNode Defensive Check Test Completed ===

=== [FIX v1.6] Testing Callback Self-Removal Scenario ===
Inserted 5 tasks at same frame (delay=10)
PASS: Callback self-removal: should have 1 frame in heap, got 1
Task list at frame 10 has 5 tasks
Removing task1 from list...
Removing task3 from list...
PASS: Callback self-removal: heap property should hold
Remaining tasks in list: 3
=== Callback Self-Removal Scenario Test Completed ===

=== [FIX v1.6] Testing removeNode on Already Recycled Node ===
First removal completed
Second removal completed (should be no-op or safe)
PASS: removeNode already recycled: should not throw error
PASS: removeNode already recycled: heap property should hold
=== removeNode Already Recycled Test Completed ===

========================================
FIX v1.6 验证测试完成
========================================

=== Running Performance Tests ===

--- Performance Tests for Scale: 100 ---
Insert Performance (100): 1 ms using addTimerByID with loop unrolling
Find Performance (100): 0 ms using taskMap with loop unrolling
PeekMin Performance (100): 0 ms with loop unrolling
Remove Performance (100): 1 ms using taskMap with loop unrolling
Reschedule Performance (100): 2 ms using taskMap with loop unrolling
Tick Performance (979): 4 ms to process ticks with loop unrolling

--- Performance Tests for Scale: 300 ---
Insert Performance (300): 3 ms using addTimerByID with loop unrolling
Find Performance (300): 1 ms using taskMap with loop unrolling
PeekMin Performance (300): 1 ms with loop unrolling
Remove Performance (300): 4 ms using taskMap with loop unrolling
Reschedule Performance (300): 5 ms using taskMap with loop unrolling
Tick Performance (999): 6 ms to process ticks with loop unrolling

--- Performance Tests for Scale: 1000 ---
Insert Performance (1000): 10 ms using addTimerByID with loop unrolling
Find Performance (1000): 0 ms using taskMap with loop unrolling
PeekMin Performance (1000): 2 ms with loop unrolling
Remove Performance (1000): 10 ms using taskMap with loop unrolling
Reschedule Performance (1000): 17 ms using taskMap with loop unrolling
Tick Performance (999): 11 ms to process ticks with loop unrolling

--- Performance Tests for Scale: 3000 ---
Insert Performance (3000): 31 ms using addTimerByID with loop unrolling
Find Performance (3000): 1 ms using taskMap with loop unrolling
PeekMin Performance (3000): 5 ms with loop unrolling
Remove Performance (3000): 31 ms using taskMap with loop unrolling
Reschedule Performance (3000): 41 ms using taskMap with loop unrolling
Tick Performance (999): 17 ms to process ticks with loop unrolling

--- Performance Tests for Scale: 10000 ---
Insert Performance (10000): 86 ms using addTimerByID with loop unrolling
Find Performance (10000): 4 ms using taskMap with loop unrolling
PeekMin Performance (10000): 18 ms with loop unrolling
Remove Performance (10000): 98 ms using taskMap with loop unrolling
Reschedule Performance (10000): 145 ms using taskMap with loop unrolling
Tick Performance (1000): 18 ms to process ticks with loop unrolling

--- Performance Tests for Scale: 30000 ---
Insert Performance (30000): 299 ms using addTimerByID with loop unrolling
Find Performance (30000): 36 ms using taskMap with loop unrolling
PeekMin Performance (30000): 62 ms with loop unrolling
Remove Performance (30000): 316 ms using taskMap with loop unrolling
Reschedule Performance (30000): 452 ms using taskMap with loop unrolling
Tick Performance (1000): 18 ms to process ticks with loop unrolling

--- Performance Tests for Scale: 100000 ---
Insert Performance (100000): 1102 ms using addTimerByID with loop unrolling
Find Performance (100000): 101 ms using taskMap with loop unrolling
PeekMin Performance (100000): 234 ms with loop unrolling
Remove Performance (100000): 1167 ms using taskMap with loop unrolling
Reschedule Performance (100000): 1713 ms using taskMap with loop unrolling
Tick Performance (1000): 19 ms to process ticks with loop unrolling

=== Performance Tests Completed ===

╔════════════════════════════════════════════════════════════╗
║        All Tests Completed in 13805 ms
╚════════════════════════════════════════════════════════════╝
