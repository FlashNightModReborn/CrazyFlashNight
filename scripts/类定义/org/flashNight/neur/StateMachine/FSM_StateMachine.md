import org.flashNight.neur.StateMachine.*;
var a = new FSM_StateMachineTest();
a.runTests();  


=== Enhanced FSM StateMachine Test Initialized ===
=== Running Enhanced FSM StateMachine Tests ===

--- Test: Basic StateMachine Creation ---
[PASS] StateMachine created successfully
[PASS] Initial default state is null
[PASS] Initial active state is null

--- Test: Add and Get States ---
[PASS] First added state is default
[PASS] Active state is default state
[PASS] Active state name is 'idle'

--- Test: Basic State Transition ---
[PASS] Initial state is idle
[PASS] State changed to running
[PASS] Last state is idle

--- Test: Default State Handling ---
[PASS] Default state is first added
[PASS] Setting null active state reverts to default

--- Test: Active State Management ---
[PASS] Active state set correctly
[PASS] Last state set correctly

--- Test: State Lifecycle Events ---
[PASS] onEnter called when state added as first state
[PASS] onEnter not called for non-active state
[PASS] Both onExit and onEnter called during transition
[PASS] onExit called first
[PASS] onEnter called second

--- Test: Lifecycle Event Order ---
[PASS] Correct number of lifecycle events
[PASS] Lifecycle events in correct order

--- Test: Lifecycle with Data Sharing ---
[PASS] Counter incremented on first state enter
[PASS] Counter decremented on state change
[PASS] Counter incremented again

--- Test: Action Count Tracking ---
[PASS] Action executed successfully
[PASS] State changed successfully

--- Test: Basic Transitions ---
[PASS] Initial state is idle
[PASS] Still in idle state
[PASS] Transitioned to running state

--- Test: Transition Priority ---
[PASS] Higher priority transition executed

--- Test: Conditional Transitions ---
[PASS] Initial state is healthy
[PASS] Transitioned to tired when energy low
[PASS] Recovered to healthy when energy high
[PASS] Transitioned to injured when health low

--- Test: Transition with Callback ---
[PASS] All callbacks executed
[PASS] Initial state entered
[PASS] Transition condition checked
[PASS] Old state exited
[PASS] New state entered

--- Test: Complex Transition Logic ---
[PASS] Game over when lives = 0
[PASS] Next level when score sufficient

--- Test: Data Blackboard Sharing ---
[PASS] State1 shares data with machine
[PASS] State2 shares data with machine
[PASS] State1 modified shared data
[PASS] State2 modified shared data

--- Test: Data Isolation Between Machines ---
[PASS] Machine1 data modified correctly
[PASS] Machine2 data modified correctly
[PASS] Data isolated between machines

--- Test: Data Persistence Across Transitions ---
[PASS] Persistent data maintained
[PASS] Data modified by state1 onEnter
[PASS] Persistent data maintained across transition
[PASS] Data modified by state2 onEnter

--- Test: Invalid State Transition ---
[PASS] State unchanged for invalid transition

--- Test: Self Transition ---
[PASS] No lifecycle events for self-transition
[PASS] State remains the same

--- Test: Empty StateMachine ---
[PASS] Default state is null for empty machine
[PASS] Active state is null for empty machine
[PASS] Last state is null for empty machine
[PASS] Empty machine handles operations gracefully

--- Test: Rapid State Changes ---
[PASS] Final state is correct after rapid changes
[PASS] Active state is valid

--- Test: Transition to Same State ---
[PASS] No transition event for same-state change

--- Test: Null State Handling ---
[PASS] Null active state defaults to default
[PASS] Last state can be set to null

--- Test: Exception in Lifecycle Methods ---
[PASS] Exceptions properly propagated from lifecycle methods

--- Test: Exception in Transition Conditions ---
[PASS] Exception in transition condition properly propagated

--- Test: Corrupted State Handling ---
[PASS] Invalid state transition handled gracefully

--- Test: Invalid Transition Handling ---
[PASS] Invalid transition target handled gracefully

--- Test: Nested StateMachines ---
[PASS] Parent machine active state is child machine
[PASS] Child machine 1 has its own active state
[PASS] Parent machine state changed
[PASS] Child machine state changed independently

--- Test: Complex Workflow ---
Initializing workflow...
Processing...
Retrying...
Processing...
Retrying...
Processing...
Retrying...
Processing...
Workflow failed!
[PASS] Workflow reached final state

--- Test: State Chaining ---
[PASS] All chain steps executed
[PASS] Chain started correctly
[PASS] Chain ended correctly

--- Test: Conditional Branching ---
[PASS] Conditional branching led to valid path: C

--- Test: StateMachine Composition ---
[PASS] Login machine starts at login
[PASS] Game machine starts at playing
[PASS] Menu machine starts at main
[PASS] Login machine state changed
[PASS] Game machine state changed
[PASS] Menu machine state changed

--- Test: StateMachine Destroy ---
[PASS] Active state exists before destroy
[PASS] Default state exists before destroy
[PASS] Child state1 destroyed
[PASS] Child state2 destroyed
[PASS] Destroy method completed without crash

--- Test: Memory Leak Prevention ---
[PASS] Memory leak prevention test completed (check manually for leaks)

--- Test: State Cleanup ---
[PASS] State not destroyed initially
[PASS] State is active initially
[PASS] State has reference to super machine
[PASS] State destroyed with machine
[PASS] State inactive after destroy
[PASS] State super machine reference cleared

--- Test: Transition Cleanup ---
[PASS] Transitions exist before cleanup
[PASS] Transition cleanup completed

--- Test: Basic Performance ---
Basic Performance: Transitions=80ms, Actions=93ms for 10000 operations
[PASS] Transition performance acceptable
[PASS] Action performance acceptable

--- Test: Many States Performance ---
Many States Performance: Create 1000 states in 32ms, 100 transitions in 1ms
[PASS] State creation scalable
[PASS] State access scalable

--- Test: Frequent Transitions Performance ---
Frequent Transitions Performance: 5000 transitions in 81ms
[PASS] Frequent transitions performance acceptable

--- Test: Complex Transition Performance ---
Complex Transition Performance: 1000 complex transitions in 38ms
[PASS] Complex transition performance acceptable

--- Test: Scalability Test ---
Size 10: Create=1ms, Transition=0ms, Operation=1ms
Size 50: Create=1ms, Transition=0ms, Operation=1ms
Size 100: Create=1ms, Transition=1ms, Operation=1ms
Size 500: Create=6ms, Transition=5ms, Operation=1ms
[PASS] Scalability performance acceptable across different sizes

=== FINAL FSM TEST REPORT ===
Tests Passed: 103
Tests Failed: 0
Success Rate: 100%
🎉 ALL TESTS PASSED! FSM StateMachine implementation is robust and performant.
=== FSM VERIFICATION SUMMARY ===
✓ Basic state machine operations verified
✓ State lifecycle management tested
✓ Transition system robustness confirmed
✓ Data blackboard functionality verified
✓ Error handling and edge cases tested
✓ Memory management and cleanup verified
✓ Performance benchmarks completed
✓ Complex workflow scenarios tested
=============================
