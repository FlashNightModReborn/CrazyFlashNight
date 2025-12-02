import org.flashNight.neur.StateMachine.TrieDFATest;

var test:TrieDFATest = new TrieDFATest();
test.runTests();



=== TrieDFA Test Suite Initialized ===

=== Running Comprehensive TrieDFA Tests ===


--- Test: Basic Creation ---
[PASS] TrieDFA created successfully
[PASS] Alphabet size is 10 (got: 10)
[PASS] Initial state count is 1 (root) (got: 1)
[PASS] Initial pattern count is 0 (got: 0)
[PASS] Not compiled initially (got: false)

--- Test: Single Pattern Insert ---
[PASS] Insert returns valid ID
[PASS] First pattern ID is 1 (got: 1)
[PASS] Pattern count is 1 (got: 1)
[PASS] Pattern length is 3 (got: 3)
[PASS] Priority is 5 (got: 5)
[PASS] Retrieved pattern length is 3 (got: 3)
[PASS] Pattern[0] is 1 (got: 1)
[PASS] Pattern[1] is 2 (got: 2)
[PASS] Pattern[2] is 3 (got: 3)

--- Test: Multiple Pattern Insert ---
[PASS] First pattern ID is 1 (got: 1)
[PASS] Second pattern ID is 2 (got: 2)
[PASS] Third pattern ID is 3 (got: 3)
[PASS] Pattern count is 3 (got: 3)

--- Test: Prefix Sharing ---
[TrieDFA] Compiled: 3 patterns, 6 states, alphabet=5, maxPatternLen=4
[PASS] State count reflects prefix sharing (got: 6)
[PASS] Pattern count is 3 (got: 3)

--- Test: Transition ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Transition on symbol 0 exists
[PASS] Transition on symbol 1 exists
[PASS] Transition on symbol 2 exists
[PASS] No transition on symbol 3 from root (got: undefined)

--- Test: Accept States ---
[TrieDFA] Compiled: 2 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] State after [0,1] accepts pattern 1 (got: 1)
[PASS] State after [0,1,2] accepts pattern 2 (got: 2)
[PASS] Intermediate state is not accept (got: 0)
[PASS] Root is not accept (got: 0)

--- Test: Insert Validation - After Compile ---
[TrieDFA] Compiled: 1 patterns, 3 states, alphabet=5, maxPatternLen=2
[TrieDFA] Error: Cannot insert after compile()
[PASS] Cannot insert after compile (got: -1)
[PASS] Pattern count unchanged (got: 1)

--- Test: Insert Validation - Undefined Pattern ---
[TrieDFA] Error: pattern is undefined
[PASS] Cannot insert undefined pattern (got: -1)
[PASS] Pattern count is 0 (got: 0)

--- Test: Insert Validation - Empty Pattern ---
[TrieDFA] Error: Empty pattern
[PASS] Cannot insert empty pattern (got: -1)
[PASS] Pattern count is 0 (got: 0)

--- Test: Insert Validation - Invalid Symbol ---
[TrieDFA] Error: Symbol -1 at index 0 out of range [0, 5)
[PASS] Cannot insert pattern with negative symbol (got: -1)
[TrieDFA] Error: Symbol 5 at index 1 out of range [0, 5)
[PASS] Cannot insert pattern with out-of-range symbol (got: -1)
[PASS] Pattern count remains 0 after invalid inserts (got: 0)
[PASS] State count remains 1 (only root) (got: 1)

--- Test: Insert Validation - No Half Insert ---
[PASS] First valid insert succeeds (got: 1)
[TrieDFA] Error: Symbol 99 at index 2 out of range [0, 5)
[PASS] Insert with invalid symbol fails (got: -1)
[PASS] State count unchanged after failed insert (got: 4)
[PASS] Pattern count unchanged after failed insert (got: 1)
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Original pattern still matches (got: 1)

--- Test: Hint Basic ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Hint at depth 1 points to pattern (got: 1)
[PASS] Hint at depth 2 points to pattern (got: 1)

--- Test: Hint Priority Comparison ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=3
[PASS] Hint prefers higher priority pattern (got: 2)
[PASS] Hint at shared node prefers higher priority (got: 2)

--- Test: Hint Length Comparison ---
[TrieDFA] Compiled: 2 patterns, 6 states, alphabet=5, maxPatternLen=5
[PASS] Hint prefers longer pattern at same priority (got: 2)
[PASS] Hint prefers longer pattern at depth 2 (got: 2)

--- Test: Hint Prefix Conflict ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Higher priority wins over length (got: 1)

--- Test: Depth Tracking ---
[TrieDFA] Compiled: 1 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Root depth is 0 (got: 0)
[PASS] Depth at state 1 is 1 (got: 1)
[PASS] Depth at state 2 is 2 (got: 2)
[PASS] Depth at state 3 is 3 (got: 3)
[PASS] Depth at state 4 is 4 (got: 4)

--- Test: Pattern Metadata ---
[TrieDFA] Compiled: 1 patterns, 6 states, alphabet=10, maxPatternLen=5
[PASS] Pattern length is 5 (got: 5)
[PASS] Priority is 42 (got: 42)
[PASS] Retrieved pattern has correct length (got: 5)
[PASS] Non-existent pattern length is 0 (got: 0)
[PASS] Non-existent pattern priority is 0 (got: 0)

--- Test: Max Pattern Length ---
[PASS] Max pattern length is 5 (got: 5)
[PASS] Max pattern length unchanged (got: 5)

--- Test: Empty DFA ---
[TrieDFA] Compiled: 0 patterns, 1 states, alphabet=5, maxPatternLen=0
[PASS] Empty DFA has 0 patterns (got: 0)
[PASS] Empty DFA has 1 state (root) (got: 1)
[PASS] Match on empty DFA returns NO_MATCH (got: 0)
[PASS] findAll on empty DFA returns empty array (got: 0)

--- Test: Single Symbol Pattern ---
[TrieDFA] Compiled: 1 patterns, 2 states, alphabet=5, maxPatternLen=1
[PASS] Single symbol pattern matches (got: 1)
[PASS] Longer sequence doesn't match exact (got: 0)
[PASS] Different symbol doesn't match (got: 0)

--- Test: Long Pattern ---
[TrieDFA] Expanding capacity to 128
[TrieDFA] Compiled: 1 patterns, 101 states, alphabet=3, maxPatternLen=100
[PASS] Long pattern inserted successfully
[PASS] Long pattern length is 100 (got: 100)
[PASS] Long pattern matches (got: 1)

--- Test: Many Patterns ---
[TrieDFA] Expanding capacity to 32
[TrieDFA] Compiled: 100 patterns, 31 states, alphabet=10, maxPatternLen=3
[PASS] All 100 patterns inserted (got: 100)
[PASS] Multiple states created

--- Test: Duplicate Patterns ---
[TrieDFA] Compiled: 2 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] First duplicate insert succeeds
[PASS] Second duplicate insert succeeds
[PASS] Different IDs for duplicate patterns
[PASS] Both patterns counted (got: 2)
[PASS] Match returns last inserted pattern (got: 2)

--- Test: Alphabet Boundary ---
[PASS] Symbol 0 is valid
[PASS] Symbol 2 (max) is valid
[TrieDFA] Error: Symbol 3 at index 0 out of range [0, 3)
[PASS] Symbol 3 is invalid (out of range) (got: -1)

--- Test: Match ---
[TrieDFA] Compiled: 2 patterns, 6 states, alphabet=5, maxPatternLen=3
[PASS] Match [0,1,2] returns id1 (got: 1)
[PASS] Match [3,4] returns id2 (got: 2)

--- Test: Match Partial ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Partial match [0,1] returns NO_MATCH (got: 0)
[PASS] Partial match [0] returns NO_MATCH (got: 0)

--- Test: Match No Match ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Completely different sequence (got: 0)
[PASS] Wrong order (got: 0)
[PASS] Too long (got: 0)
[PASS] Empty sequence (got: 0)

--- Test: FindAll ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Found 2 matches (got: 2)
[PASS] First match at position 0 (got: 0)
[PASS] First match is pattern 1 (got: 1)
[PASS] Second match at position 2 (got: 2)
[PASS] Second match is pattern 2 (got: 2)

--- Test: FindAll Overlapping ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Found 2 overlapping matches (got: 2)
[PASS] First match at position 0 (got: 0)
[PASS] Second match at position 1 (got: 1)

--- Test: FindAll With MaxLen Optimization ---
[TrieDFA] Compiled: 3 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Max pattern length is 3 (got: 3)
[PASS] Found matches in long sequence

--- Test: Auto Expansion ---
[TrieDFA] Compiled: 20 patterns, 21 states, alphabet=5, maxPatternLen=20
[PASS] All 20 patterns inserted despite small initial capacity (got: 20)
[PASS] States expanded beyond initial capacity

--- Test: Dump ---
[TrieDFA] Compiled: 2 patterns, 6 states, alphabet=5, maxPatternLen=3
===== TrieDFA Dump =====
Alphabet size: 5
States: 6
Patterns: 2
Max pattern length: 3
Compiled: true
  [1] 0,1 (priority: 5, len: 2)
  [2] 2,3,4 (priority: 10, len: 3)
========================
[PASS] dump() executed without error

--- Test: GetTransitionsFrom ---
[TrieDFA] Compiled: 3 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Root has 1 transition (got: 1)
[PASS] Root transition is on symbol 0 (got: 0)
[PASS] State after 0 has 3 transitions (got: 3)

--- Test: Streaming Basic ---
[TrieDFA] Compiled: 1 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Frame 0: transition exists for symbol 3
[PASS] Frame 0: intermediate state is not accept (got: 0)
[PASS] Frame 1: transition exists for symbol 4
[PASS] Frame 1: intermediate state is not accept (got: 0)
[PASS] Frame 2: transition exists for symbol 1
[PASS] Frame 2: intermediate state is not accept (got: 0)
[PASS] Frame 3: transition exists for symbol 0
[PASS] Final state accepts the pattern (got: 1)

--- Test: Streaming Multiple Patterns ---
[TrieDFA] Compiled: 3 patterns, 8 states, alphabet=5, maxPatternLen=3
[PASS] Wave pattern recognized (got: 1)
[PASS] Dash pattern recognized (got: 2)
[PASS] Back pattern recognized (got: 3)

--- Test: Streaming Hint Progression ---
[TrieDFA] Compiled: 1 patterns, 6 states, alphabet=5, maxPatternLen=5
[PASS] Frame 0: hint points to correct pattern (got: 1)
[PASS] Frame 0: depth is 1 (got: 1)
[PASS] Frame 1: hint points to correct pattern (got: 1)
[PASS] Frame 1: depth is 2 (got: 2)
[PASS] Frame 2: hint points to correct pattern (got: 1)
[PASS] Frame 2: depth is 3 (got: 3)
[PASS] Frame 3: hint points to correct pattern (got: 1)
[PASS] Frame 3: depth is 4 (got: 4)
[PASS] Frame 4: hint points to correct pattern (got: 1)
[PASS] Frame 4: depth is 5 (got: 5)

--- Test: Streaming Timeout ---
[TrieDFA] Compiled: 1 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Progressed to depth 2 (got: 2)
[PASS] Reset to root (depth 0) (got: 0)
[PASS] Pattern recognized after reset (got: 1)

--- Test: Streaming Prefix Match ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Short pattern recognized at [3,0] (got: 1)
[PASS] Intermediate state after [3,0,1] (got: 0)
[PASS] Long pattern recognized at [3,0,1,0] (got: 2)

--- Test: Basic Performance ---
[TrieDFA] Compiled: 1 patterns, 6 states, alphabet=10, maxPatternLen=5
Basic Performance: 10000 traversals in 77ms
[PASS] Basic traversal performance acceptable

--- Test: Transition Performance ---
[TrieDFA] Expanding capacity to 128
[TrieDFA] Compiled: 100 patterns, 101 states, alphabet=100, maxPatternLen=1
Transition Performance: 100000 single transitions in 389ms
[PASS] Single transition performance acceptable

--- Test: Many Patterns Performance ---
[TrieDFA] Compiled: 1000 patterns, 61 states, alphabet=20, maxPatternLen=3
Insert 1000 patterns: 18ms
Compile: 0ms
[PASS] Insert 1000 patterns in acceptable time
[PASS] Compile in acceptable time

--- Test: FindAll Performance ---
[TrieDFA] Compiled: 50 patterns, 21 states, alphabet=10, maxPatternLen=2
FindAll Performance: 100 calls on 1000-symbol sequence in 773ms
[PASS] FindAll performance acceptable

--- Test: Scalability ---
[TrieDFA] Compiled: 10 patterns, 31 states, alphabet=20, maxPatternLen=3
Scale 10: Insert 1ms, 1000 matches 8ms
[TrieDFA] Compiled: 50 patterns, 61 states, alphabet=20, maxPatternLen=3
Scale 50: Insert 1ms, 1000 matches 8ms
[TrieDFA] Compiled: 100 patterns, 61 states, alphabet=20, maxPatternLen=3
Scale 100: Insert 2ms, 1000 matches 7ms
[TrieDFA] Compiled: 500 patterns, 61 states, alphabet=20, maxPatternLen=3
Scale 500: Insert 10ms, 1000 matches 8ms
[PASS] Scalability is acceptable

=== TRIEDFA TEST FINAL REPORT ===
Tests Passed: 139
Tests Failed: 0
Success Rate: 100%
ALL TRIEDFA TESTS PASSED!

=== TRIEDFA VERIFICATION SUMMARY ===
* Basic DFA operations verified
* Insert validation (no half-insert) confirmed
* Hint priority/length strategy tested
* Prefix sharing optimization verified
* Edge cases and boundaries handled
* Convenience methods (match, findAll) tested
* Performance benchmarks established
* Auto-expansion mechanism verified
=============================


=== TRIEDFA PERFORMANCE ANALYSIS ===
Context: Basic 5-step transition
  Iterations: 10000
  Total Time: 77ms
  Avg per Operation: 0.0077ms
  Operations per Second: 129870
---
Context: Single transition
  Iterations: 100000
  Total Time: 389ms
  Avg per Operation: 0.0039ms
  Operations per Second: 257069
---
Context: FindAll on 1000-symbol sequence
  Iterations: 100
  Total Time: 773ms
  Avg per Operation: 7.73ms
  Operations per Second: 129
---
=============================

