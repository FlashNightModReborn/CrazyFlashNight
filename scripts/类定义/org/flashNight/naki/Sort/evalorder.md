=== AVM1 Evaluation Order Tests ===
Hypothesis: LHS array index is evaluated BEFORE RHS value

--- Group 1: Pattern A (arr[j+1]=arr[j]; j-- → arr[j+1]=arr[j--]) ---
  PASS: T1.1 baseline: a[j+1]=a[j]; j--
  PASS: T1.2 SAFE: a[j+1]=a[j--]
  INFO: T1.3 a[j--+1]=a[j] → a=[10,20,30,20,50] j=1 [LHS-first]

--- Group 2: Pattern B (arr[j]=arr[j-1]; j-- → arr[j]=arr[--j]) ---
  PASS: T2.1 baseline: a[j]=a[j-1]; j--
  PASS: T2.2 SAFE: a[j]=a[--j]
  PASS: T2.3 ALT: a[j--]=a[j] (also valid if LHS-first)
  INFO: T2.4 a[j--]=a[j-1] → a=[10,20,30,20,50] j=2 [LHS-first]

--- Group 3: Cross-variable (a[d++]=b[p++], a[d--]=b[p--]) ---
  PASS: T3.1 a[d++]=b[p++]
  PASS: T3.2 a[d--]=b[p--]
  PASS: T3.3 same arr a[d++]=a[p++]
  PASS: T3.4 batch x4 copy
  PASS: T3.5 batch x4 reverse copy

--- Group 4: LHS-first vs RHS-first discriminators ---
  PASS: T4.1 a[i++]=a[i] → a[1]=30 i=2 [LHS-first confirmed]
  INFO: T4.2 a[i]=a[i++] → a=[10,20,30,40,50] i=2 [LHS-first]
  INFO: T4.3 a[--i]=a[i] → a=[10,20,30,40,50] i=2 [LHS-first: a[2] unchanged]
  INFO: T4.4 a[i]=++i → a=[10,2,30,40,50] i=2 [LHS-first: a[1]=2]

--- Group 5: Full while-loop pattern tests ---
  PASS: T5.1 Pattern A loop: shift-down insert 25 into [10,30,50,70]
  PASS: T5.2 Pattern A loop: key=5 shifts entire array
  PASS: T5.3 Pattern A loop: already sorted, no shift
  PASS: T5.4 Pattern B loop: shift block [60,70,80] right, insert 25 at pos 2
  PASS: T5.5 Pattern B loop: shift single element
  PASS: T5.6 Pattern B loop: shift entire array right

--- Group 6: Full insertion sort equivalence ---
  PASS: T6.1 sort n=5
  PASS: T6.2 sort n=1
  PASS: T6.3 sort n=2
  PASS: T6.4 sort n=3
  PASS: T6.5 sort n=5
  PASS: T6.6 sort n=5
  PASS: T6.7 sort n=8
  PASS: T6.8 sort n=4
  PASS: T6.9 sort n=8
  PASS: T6.10 sort n=15
  PASS: T6.11 sort n=7
  PASS: T6.12 sort n=16
  PASS: T6.13 sort n=16
  PASS: T6.14 sort n=9

--- Group 7: Exhaustive [1..5] permutations (120 total) ---
  PASS: T7.1 All 120 permutations of [1..5]
  PASS: T7.2 All 720 permutations of [1..6] (covers binary insertion path)

--- Group 8: Edge cases ---
  PASS: T8.1 j=0: a[j+1]=a[j--]
  PASS: T8.2 chained 3x Pattern A
  PASS: T8.3 chained 3x Pattern B
  PASS: T8.4 single element, no shift
  PASS: T8.5 two-element swap via Pattern A loop
  PASS: T8.6 shift 9 elements right
  PASS: T8.7 Pattern B shift 8 elements right
  PASS: T8.8 --copyEnd>=0 batch control (8 elements, 2 rounds)

=== Summary: 41 passed, 0 failed ===
All tests passed! Safe transformations:
  Pattern A: arr[j+1]=arr[j]; j--  -->  arr[j+1]=arr[j--]
  Pattern B: arr[j]=arr[j-1]; j--  -->  arr[j]=arr[--j]
