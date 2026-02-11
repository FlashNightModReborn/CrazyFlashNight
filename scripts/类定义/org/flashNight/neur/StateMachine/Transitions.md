import org.flashNight.neur.StateMachine.*;
var a = new TransitionsTest();
a.runTests();

=== Transitions Test Suite Initialized ===
=== Running Comprehensive Transitions Tests ===

--- Test: Basic Transition Creation ---
[PASS] Transitions object created successfully
[PASS] Transit returns null for non-existent state

--- Test: Push Transition ---
[PASS] Push transition works correctly
[PASS] First pushed transition has higher priority

--- Test: Unshift Transition ---
[PASS] Unshift transition has highest priority

--- Test: Transit Method ---
[PASS] Transit returns null when condition is false
[PASS] Transit returns target when condition is true

--- Test: Transition Activation ---
[PASS] Active transition works
[PASS] Inactive condition returns null

--- Test: Transition Priority ---
[PASS] Highest priority transition executed first

--- Test: Multiple Priority Levels ---
[PASS] Priority 1 condition met
[PASS] Higher priority still wins even when lower priority conditions are true

--- Test: Priority Insertion ---
[PASS] Last unshift has highest priority

--- Test: Priority Override ---
[PASS] Lower priority executes when higher priority condition fails

--- Test: Simple Conditions ---
[PASS] Simple numeric condition works
[PASS] Simple boolean condition works

--- Test: Complex Conditions ---
[PASS] Complex AND condition works
[PASS] Advanced complex condition works

--- Test: Dynamic Conditions ---
[PASS] Dynamic time-based condition works

--- Test: Conditional Chaining ---
[PASS] First step in chain executed
[PASS] Second step in chain executed

--- Test: Nested Conditions ---
[PASS] Nested object condition works

--- Test: Data Access ---
[PASS] Numeric data accessed correctly
[PASS] String data accessed correctly

--- Test: Data Modification ---
[PASS] First call returns null
[PASS] Second call returns null
[PASS] Third call returns target
[PASS] Counter modified correctly

--- Test: Data Validation ---
[PASS] Null data handled safely
[PASS] Valid data processed correctly

--- Test: Cross-State Data Access ---
[PASS] Cross-state data modification works
[PASS] Source state deactivated
[PASS] Target state activated

--- Test: Empty Transition List ---
[PASS] Empty transition list returns null
[PASS] Empty state name returns null
[PASS] Null state name returns null

--- Test: Null Conditions ---
[PASS] Null condition handled gracefully

--- Test: Invalid State Names ---
[PASS] Invalid state name handled: ''
[PASS] Invalid state name handled: ' '
[PASS] Invalid state name handled: '	'
[PASS] Invalid state name handled: '
'
[PASS] Invalid state name handled: 'very_long_state_name_that_might_cause_issues'

--- Test: Self Transitions ---
[PASS] First self-transition check returns null
[PASS] Second self-transition check returns null
[PASS] Third self-transition succeeds

--- Test: Circular Transitions ---
[PASS] A -> B transition
[PASS] B -> C transition
[PASS] C -> A transition completes cycle

--- Test: Missing Target States ---
[PASS] Transition returns target name even if target doesn't exist

--- Test: Exception in Conditions ---
[PASS] Exception in condition properly propagated

--- Test: Malformed Transitions ---
[PASS] Malformed transitions handled without crash

--- Test: Corrupted Transition Data ---
[PASS] Corrupted data handled gracefully

--- Test: Recovery from Errors ---
[PASS] Successfully recovered from errors

--- Test: Basic Performance ---
Basic Performance: 10000 transit calls in 50ms
[PASS] Basic performance acceptable

--- Test: Many Transitions Performance ---
Many Transitions Performance: 1000 transitions, 1000 calls in 1805ms
[PASS] Many transitions performance acceptable

--- Test: Complex Conditions Performance ---
Complex Conditions Performance: 1000 complex calculations in 18ms
[PASS] Complex conditions performance acceptable

--- Test: Frequent Transit Calls Performance ---
Frequent Calls Performance: 50000 calls in 277ms
[PASS] Frequent calls performance acceptable

--- Test: Transition Scalability ---
Scale 10: 100 calls in 4ms
Scale 50: 100 calls in 12ms
Scale 100: 100 calls in 19ms
Scale 500: 100 calls in 23ms
Scale 1000: 100 calls in 28ms
[PASS] Transition scalability is acceptable

--- Test: Memory Usage Optimization ---
[PASS] Memory usage remains efficient under stress

--- Test: Transition Caching ---
[PASS] All calculations executed (no caching implemented)
Caching test: 10 calls took 9ms
[PASS] Caching test completed (baseline established)

--- Test: Conditional Short-Circuiting ---
[PASS] First transition executed
[PASS] Short-circuiting works - only first condition evaluated

--- Test: Transition Grouping ---
[PASS] Group A low priority selected
[PASS] Group A high priority selected

--- Test: Dynamic Transition Management ---
[PASS] Phase 1 active
[PASS] Phase 2 active
[PASS] Disabled state active

--- Test: Gate/Normal Separation ---
[PASS] TransitGate returns Gate transition
[PASS] TransitNormal returns Normal transition
[PASS] TransitGate does not return Normal transition
[PASS] TransitNormal does not return Gate transition

--- Test: Gate/Normal Isolation ---
[PASS] No Normal result for Gate-only state
[PASS] Gate result exists for Gate-only state
[PASS] No Gate result for Normal-only state
[PASS] Normal result exists for Normal-only state

--- Test: Gate/Normal Clear and Reset ---
[PASS] Gate cleared for state
[PASS] Normal cleared for state
[PASS] Gate cleared after reset
[PASS] Normal cleared after reset

--- Test: Remove Normal Transition ---
[PASS] remove() returns true for existing rule
[PASS] After remove, next rule takes effect

--- Test: Remove Gate Transition ---
[PASS] Gate rule exists before remove
[PASS] remove(isGate=true) returns true
[PASS] Gate rule removed successfully

--- Test: Remove Non-Existent ---
[PASS] remove() returns false for wrong target
[PASS] remove() returns false for different func ref
[PASS] remove() returns false for non-existent state
[PASS] Original rule still active after failed removes

--- Test: setActive Disable/Enable ---
[PASS] setActive() returns true for existing rule
[PASS] Disabled rule skipped, B takes effect
[PASS] Re-enabled rule takes effect again

--- Test: setActive Gate Transition ---
[PASS] Gate rule active initially
[PASS] Gate rule disabled via setActive
[PASS] Gate rule re-enabled via setActive

--- Test: setActive Non-Existent ---
[PASS] setActive() returns false for non-existent state
[PASS] setActive() returns false for wrong target

--- Test: Remove and Re-Add ---
[PASS] Rule removed
[PASS] Rule re-added and working

--- Test: setActive with Priority ---
[PASS] Highest priority rule fires
[PASS] Mid priority fires when high disabled
[PASS] Low priority fires when high+mid disabled
[PASS] All re-enabled, highest priority fires again

--- Test: Condition Function Receives No Transitions Ref ---
[PASS] Condition function was called
[PASS] Condition receives exactly 2 arguments (current, target)
[PASS] 1st argument is current state name
[PASS] 2nd argument is target state name
[PASS] Gate condition also receives exactly 2 arguments

=== TRANSITIONS TEST FINAL REPORT ===
Tests Passed: 108
Tests Failed: 0
Success Rate: 100%
🎉 ALL TRANSITIONS TESTS PASSED!
=== TRANSITIONS VERIFICATION SUMMARY ===
✓ Basic transition operations verified
✓ Priority system robustness confirmed
✓ Condition logic extensively tested
✓ Data access patterns validated
✓ Error handling mechanisms verified
✓ Performance benchmarks established
✓ Advanced features tested
=============================

=== TRANSITIONS PERFORMANCE ANALYSIS ===
Context: Basic Transit Call
  Iterations: 10000
  Total Time: 50ms
  Avg per Operation: 0.005ms
  Operations per Second: 200000
---
Context: Many Transitions
  Iterations: 1000
  Total Time: 1805ms
  Avg per Operation: 1.805ms
  Operations per Second: 554
---
Context: Complex Conditions
  Iterations: 1000
  Total Time: 18ms
  Avg per Operation: 0.018ms
  Operations per Second: 55556
---
Context: Frequent Transit Calls
  Iterations: 50000
  Total Time: 277ms
  Avg per Operation: 0.00554ms
  Operations per Second: 180505
---
Context: Scale 10
  Iterations: 100
  Total Time: 4ms
  Avg per Operation: 0.04ms
  Operations per Second: 25000
---
Context: Scale 50
  Iterations: 100
  Total Time: 12ms
  Avg per Operation: 0.12ms
  Operations per Second: 8333
---
Context: Scale 100
  Iterations: 100
  Total Time: 19ms
  Avg per Operation: 0.19ms
  Operations per Second: 5263
---
Context: Scale 500
  Iterations: 100
  Total Time: 23ms
  Avg per Operation: 0.23ms
  Operations per Second: 4348
---
Context: Scale 1000
  Iterations: 100
  Total Time: 28ms
  Avg per Operation: 0.28ms
  Operations per Second: 3571
---
Context: Memory Stress Test
  Iterations: 1000
  Total Time: 7ms
  Avg per Operation: 0.007ms
  Operations per Second: 142857
---
=== PERFORMANCE RECOMMENDATIONS ===
Overall Average: 0.0353228346456693ms per operation
✅ Excellent performance - suitable for real-time applications
=============================
