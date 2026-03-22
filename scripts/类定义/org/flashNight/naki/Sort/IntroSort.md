import org.flashNight.naki.Sort.*;

IntroSortTest.runTests();


=================================================================
IntroSort Comprehensive Test Suite
=================================================================

--- Basic Functionality Tests ---
PASS: Empty Array
PASS: Single Element
PASS: Two Elements (Reverse)
PASS: Two Elements (Sorted)
PASS: Two Elements (Equal)
PASS: Three Elements (All 6 Permutations) - All correct
PASS: Already Sorted
PASS: Reverse Sorted
PASS: Random Array
PASS: Duplicate Elements
PASS: All Same Elements
PASS: Negative Numbers
PASS: Large Range

--- Boundary Case Tests ---
PASS: Threshold Boundary Sizes (3~200) - All sizes correct
PASS: Mixed Types With Comparator - Correct
PASS: Moderate Array (1000) - Sorted in 4ms
PASS: Extreme Duplicates (50~1000) - All handled correctly

--- Algorithm-Specific Tests ---
PASS: Few Unique (DNF path) - 5 values sorted correctly
PASS: Unique Values (Hoare path) - Sorted correctly
PASS: Two Values (DNF path) - Sorted correctly
PASS: Heapsort Fallback - Organ pipe sorted correctly
PASS: Ordered Detection - All scenarios correct
PASS: Pivot Selection

--- Data Type Tests ---
PASS: String Array
PASS: Object Array - Sorted by age
PASS: Custom Objects - Sorted by priority

--- Compare Function Tests ---
PASS: Case-Insensitive Compare - Works correctly
PASS: Reverse Compare
PASS: Multi-Level Compare - Works correctly
PASS: Null Compare Function

--- Consistency Tests ---
PASS: Consistent Results - Multiple sorts produce identical results
PASS: In-Place Sorting - Returns same array reference
PASS: Idempotency - Sorting sorted array doesn't change it

--- Adversarial Input Tests ---
PASS: Organ Pipe (500) - Sorted correctly
PASS: Saw Tooth (500, period=10) - Sorted correctly
PASS: Alternating Two Values (500) - Sorted correctly
PASS: Three Values Random (1000) - Sorted correctly
PASS: Mostly Equal + Outliers - Sorted correctly
PASS: Sorted + Tail Perturbation - Sorted correctly
PASS: Large Organ Pipe (10000) - Sorted in 53ms
PASS: Organ Pipe (comparator path) - Sorted correctly

--- Cross-Validation vs PDQSort ---
PASS: Cross-Validation (4 sizes x 6 distributions) - IntroSort and PDQSort produce identical results
PASS: Cross-Validation (comparator path, 1000) - Results match

--- Stress Tests ---
PASS: Stress Test (10000, 6 distributions) - All correct
PASS: Repeated Sorting - 5 iterations consistent

--- Performance Benchmarks ---
Format: IntroSort(null) / PDQSort(null) / PDQSort(cmp) / TimSort(cmp) / Array.sort(NUMERIC) ms

  Size: 100
    random      :     1 /     1 /     2 /     1 /     1
    sorted      :     0 /     0 /     0 /     0 /     0
    reverse     :     0 /     0 /     0 /     0 /     0
    duplicates  :     0 /     0 /     0 /     1 /     0
    organPipe   :     0 /     1 /     1 /     0 /     0
    fewUnique   :     0 /     0 /     0 /     1 /     0

  Size: 1000
    random      :     3 /     5 /    10 /    10 /     1
    sorted      :     0 /     1 /     1 /     1 /     6
    reverse     :     0 /     1 /     1 /     1 /     6
    duplicates  :     1 /     1 /     2 /     8 /     1
    organPipe   :     4 /     6 /    11 /     2 /     0
    fewUnique   :     1 /     1 /     3 /     9 /     1

  Size: 5000
    random      :    20 /    30 /    61 /    63 /     2
    sorted      :     3 /     3 /     4 /     3 /   147
    reverse     :     4 /     4 /     6 /     4 /   146
    duplicates  :     4 /     4 /     9 /    44 /    31
    organPipe   :    24 /    32 /    65 /     9 /     4
    fewUnique   :     5 /     6 /    13 /    50 /    16

  Size: 10000
    random      :    42 /    63 /   139 /   143 /     5
    sorted      :     5 /     5 /     9 /     7 /   608
    reverse     :     7 /     7 /    12 /     9 /   594
    duplicates  :     8 /     8 /    19 /    86 /   122
    organPipe   :    51 /    71 /   149 /    19 /     7
    fewUnique   :    10 /    13 /    29 /   108 /    62

=================================================================
TEST SUMMARY
=================================================================
Total: 45  Passed: 45  Failed: 0
Success Rate: 100%
ALL TESTS PASSED!
=================================================================
[compile] done
