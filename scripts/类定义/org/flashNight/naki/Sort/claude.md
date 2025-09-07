
=====================================
PDQSort Optimization - Step 0 & 1
=====================================

Step 0: Generating Baseline Report...
-------------------------------------


================================================================
PDQSort Baseline Performance Report
================================================================
Generated: Sun Sep 7 14:16:28 GMT+0800 2025



--- Array Size: 100 ---
random: 0ms | Cmp:0 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
sorted: 0ms | Cmp:99 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
reversed: 1ms | Cmp:99 Swp:50 Part:0 Bad:0 Heap:0 Stack:0 | ✓
nearlySorted: 1ms | Cmp:350 Swp:121 Part:0 Bad:0 Heap:0 Stack:1 | ✓
sawtooth2: 0ms | Cmp:305 Swp:52 Part:1 Bad:0 Heap:0 Stack:1 | ✓
sawtooth4: 2ms | Cmp:336 Swp:104 Part:2 Bad:0 Heap:0 Stack:1 | ✓
sawtooth8: 1ms | Cmp:409 Swp:195 Part:2 Bad:0 Heap:0 Stack:1 | ✗
organPipe: 1ms | Cmp:520 Swp:284 Part:2 Bad:0 Heap:0 Stack:1 | ✗
manyDuplicates: 0ms | Cmp:317 Swp:104 Part:2 Bad:0 Heap:0 Stack:1 | ✗
alternating: 1ms | Cmp:302 Swp:52 Part:1 Bad:0 Heap:0 Stack:1 | ✓

--- Array Size: 500 ---
random: 0ms | Cmp:0 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
sorted: 1ms | Cmp:499 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
reversed: 1ms | Cmp:499 Swp:250 Part:0 Bad:0 Heap:0 Stack:0 | ✓
nearlySorted: 4ms | Cmp:1976 Swp:949 Part:0 Bad:0 Heap:0 Stack:1 | ✓
sawtooth2: 3ms | Cmp:1505 Swp:252 Part:1 Bad:0 Heap:0 Stack:1 | ✓
sawtooth4: 5ms | Cmp:1765 Swp:504 Part:2 Bad:0 Heap:0 Stack:1 | ✓
sawtooth8: 5ms | Cmp:1889 Swp:691 Part:3 Bad:0 Heap:0 Stack:1 | ✗
organPipe: 8ms | Cmp:2587 Swp:1219 Part:5 Bad:1 Heap:0 Stack:1 | ✗
manyDuplicates: 4ms | Cmp:1635 Swp:508 Part:2 Bad:0 Heap:0 Stack:1 | ✗
alternating: 4ms | Cmp:1502 Swp:252 Part:1 Bad:0 Heap:0 Stack:1 | ✓

--- Array Size: 1000 ---
random: 0ms | Cmp:0 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
sorted: 3ms | Cmp:999 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
reversed: 3ms | Cmp:999 Swp:500 Part:0 Bad:0 Heap:0 Stack:0 | ✓
nearlySorted: 25ms | Cmp:9080 Swp:7082 Part:0 Bad:0 Heap:0 Stack:1 | ✓
sawtooth2: 7ms | Cmp:3006 Swp:502 Part:1 Bad:0 Heap:0 Stack:1 | ✓
sawtooth4: 10ms | Cmp:3513 Swp:1004 Part:2 Bad:0 Heap:0 Stack:1 | ✓
sawtooth8: 9ms | Cmp:3777 Swp:1381 Part:3 Bad:0 Heap:0 Stack:1 | ✗
organPipe: 15ms | Cmp:5251 Swp:2499 Part:6 Bad:1 Heap:0 Stack:1 | ✗
manyDuplicates: 11ms | Cmp:4380 Swp:1413 Part:3 Bad:0 Heap:0 Stack:1 | ✓
alternating: 7ms | Cmp:3004 Swp:502 Part:1 Bad:0 Heap:0 Stack:1 | ✓

--- Array Size: 5000 ---
random: 0ms | Cmp:0 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
sorted: 12ms | Cmp:4999 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
reversed: 16ms | Cmp:4999 Swp:2500 Part:0 Bad:0 Heap:0 Stack:0 | ✓
nearlySorted: 602ms | Cmp:204732 Swp:194648 Part:0 Bad:0 Heap:0 Stack:1 | ✓
sawtooth2: 34ms | Cmp:15006 Swp:2502 Part:1 Bad:0 Heap:0 Stack:1 | ✓
sawtooth4: 43ms | Cmp:17513 Swp:5004 Part:2 Bad:0 Heap:0 Stack:1 | ✓
sawtooth8: 46ms | Cmp:18769 Swp:6881 Part:3 Bad:0 Heap:0 Stack:1 | ✗
organPipe: 67ms | Cmp:25991 Swp:11765 Part:12 Bad:4 Heap:0 Stack:1 | ✗
manyDuplicates: 40ms | Cmp:16125 Swp:5025 Part:2 Bad:0 Heap:0 Stack:1 | ✗
alternating: 34ms | Cmp:15004 Swp:2502 Part:1 Bad:0 Heap:0 Stack:1 | ✓

--- Array Size: 10000 ---
random: 0ms | Cmp:0 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
sorted: 24ms | Cmp:9999 Swp:0 Part:0 Bad:0 Heap:0 Stack:0 | ✓
reversed: 30ms | Cmp:9999 Swp:5000 Part:0 Bad:0 Heap:0 Stack:0 | ✓
nearlySorted: 1855ms | Cmp:627719 Swp:607712 Part:0 Bad:0 Heap:0 Stack:1 | ✓
sawtooth2: 69ms | Cmp:30003 Swp:5002 Part:1 Bad:0 Heap:0 Stack:1 | ✓
sawtooth4: 97ms | Cmp:40016 Swp:12504 Part:2 Bad:0 Heap:0 Stack:1 | ✓
sawtooth8: 94ms | Cmp:37522 Swp:13756 Part:3 Bad:0 Heap:0 Stack:1 | ✗
organPipe: 145ms | Cmp:53130 Swp:24082 Part:17 Bad:8 Heap:0 Stack:1 | ✗
manyDuplicates: 90ms | Cmp:36082 Swp:12110 Part:2 Bad:0 Heap:0 Stack:1 | ✓
alternating: 72ms | Cmp:30004 Swp:5002 Part:1 Bad:0 Heap:0 Stack:1 | ✓


================================================================
Summary Statistics
================================================================

alternating:
  Avg Time: 24ms
  Avg Comparisons: 9963
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 1

manyDuplicates:
  Avg Time: 29ms
  Avg Comparisons: 11708
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 1

organPipe:
  Avg Time: 47ms
  Avg Comparisons: 17496
  Total Bad Splits: 14
  Total Heapsort Calls: 0
  Max Stack Depth: 1

sawtooth8:
  Avg Time: 31ms
  Avg Comparisons: 12473
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 1

sawtooth4:
  Avg Time: 31ms
  Avg Comparisons: 12629
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 1

sawtooth2:
  Avg Time: 23ms
  Avg Comparisons: 9965
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 1

nearlySorted:
  Avg Time: 497ms
  Avg Comparisons: 168771
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 1

reversed:
  Avg Time: 10ms
  Avg Comparisons: 3319
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 0

sorted:
  Avg Time: 8ms
  Avg Comparisons: 3319
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 0

random:
  Avg Time: 0ms
  Avg Comparisons: 0
  Total Bad Splits: 0
  Total Heapsort Calls: 0
  Max Stack Depth: 0


================================================================
Problem Areas Identified
================================================================
❌ sawtooth8 (size=100): Sort result incorrect!
❌ organPipe (size=100): Sort result incorrect!
❌ manyDuplicates (size=100): Sort result incorrect!
❌ sawtooth8 (size=500): Sort result incorrect!
❌ organPipe (size=500): Sort result incorrect!
❌ manyDuplicates (size=500): Sort result incorrect!
❌ sawtooth8 (size=1000): Sort result incorrect!
❌ organPipe (size=1000): Sort result incorrect!
❌ sawtooth8 (size=5000): Sort result incorrect!
❌ organPipe (size=5000): Sort result incorrect!
❌ manyDuplicates (size=5000): Sort result incorrect!
❌ sawtooth8 (size=10000): Sort result incorrect!
❌ organPipe (size=10000): Sort result incorrect!


Step 1: Verifying Small-First Optimization...
-------------------------------------

Stack Depth Analysis:
Size	Expected Max	Actual Max	Status
----	------------	----------	------
100	8		1		✓ PASS
1000	11		1		✓ PASS
10000	15		1		✓ PASS
50000	17		1		✓ PASS

✅ Stack depth optimization successful!
All stack depths are within O(log n) bounds.


Running Regression Tests...
-------------------------------------

Regression Test Results:
Total: 40 | Passed: 40 | Failed: 0
✅ All regression tests passed!
