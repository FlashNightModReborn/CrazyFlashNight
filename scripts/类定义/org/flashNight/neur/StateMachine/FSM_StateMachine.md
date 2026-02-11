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
[PASS] Active state defaults to first added

--- Test: Active State Management ---
[PASS] Active state changed via ChangeState
[PASS] Last state tracks previous active state

--- Test: State Lifecycle Events ---
[PASS] AddStatus does not trigger onEnter (deferred to start())
[PASS] onEnter not called for non-active state
[PASS] start() triggers onEnter for default state
[PASS] Both onExit and onEnter called during transition
[PASS] onExit called first
[PASS] onEnter called second

--- Test: Lifecycle Event Order ---
[PASS] Correct number of lifecycle events
[PASS] Lifecycle events in correct order

--- Test: Lifecycle with Data Sharing ---
[PASS] Counter incremented on first state enter via start()
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
[PASS] All callbacks executed (start + transition)
[PASS] Initial state entered via start()
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
[PASS] Data modified by state1 onEnter via start()
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
[PASS] Active state is null before AddStatus
[PASS] Last state is null before AddStatus
[PASS] Active state name is null before AddStatus

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
[PASS] Child machine 1 has its own active state (pre-start)
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
[PASS] State has reference to super machine
[PASS] State destroyed with machine
[PASS] State super machine reference cleared

--- Test: Transition Cleanup ---
[PASS] Transitions exist before cleanup
[PASS] Transitions reference released after destroy

--- Test: Basic Performance ---
Basic Performance: Transitions=28ms, Actions=32ms for 10000 operations
[PASS] Transition performance acceptable
[PASS] Action performance acceptable

--- Test: Many States Performance ---
Many States Performance: Create 1000 states in 42ms, 100 transitions in 0ms
[PASS] State creation scalable
[PASS] State access scalable

--- Test: Frequent Transitions Performance ---
Frequent Transitions Performance: 5000 transitions in 16ms
[PASS] Frequent transitions performance acceptable

--- Test: Complex Transition Performance ---
Complex Transition Performance: 1000 complex transitions in 6ms
[PASS] Complex transition performance acceptable

--- Test: Scalability Test ---
Size 10: Create=2ms, Transition=0ms, Operation=0ms
Size 50: Create=1ms, Transition=1ms, Operation=0ms
Size 100: Create=1ms, Transition=2ms, Operation=0ms
Size 500: Create=11ms, Transition=12ms, Operation=2ms
[PASS] Scalability performance acceptable across different sizes

--- Test: Pause Gate Immediate Effect ---
[PASS] Should switch to paused state immediately
[PASS] Player action should NOT execute when paused in same frame
[PASS] Player action should not be logged
[PASS] Paused state should be entered

--- Test: Transition→Action Order ---
[PASS] Correct number of lifecycle events
[PASS] Should be in state B
[PASS] B's action should execute in same frame as transition

--- Test: Recursive Transition Safety ---
[FSM] Warning: onAction transition loop reached limit (10), possible oscillation
[FSM] Warning: onAction transition loop reached limit (10), possible oscillation
[FSM] Warning: onAction transition loop reached limit (10), possible oscillation
[FSM] Warning: onAction transition loop reached limit (10), possible oscillation
[PASS] No stack overflow during rapid transitions
[PASS] Transitions completed within reasonable frames
[PASS] Active state remains valid
[PASS] Final state is valid

--- Test: Path B - Callbacks Do Not Shadow Pipeline ---
[PASS] Pipeline Phase 2 executed (state action ran)
[PASS] Pipeline Phase 3 executed (transition fired)
[PASS] Machine-level _onActionCb fired as post-pipeline hook

--- Test: Path B - Machine Level Enter/Exit Hooks ---
[PASS] AddStatus does not trigger enter hooks (deferred to start())
[PASS] Child machine enter hooks fired on start()
[PASS] Machine-level onEnter callback fired
[PASS] Inner state onEnter propagated
[PASS] Machine onEnter fires before inner state onEnter
[PASS] Inner state onExit propagated
[PASS] Machine-level onExit callback fired
[PASS] Inner state exits before machine onExit

--- Test: Explicit start() Method ---
[PASS] No onEnter before start()
[PASS] start() triggers default state onEnter
[PASS] Duplicate start() is no-op

--- Test: Reserved Name Validation ---
[FSM] Error: 'toString' is a reserved name (Object prototype). Choose another.
[FSM] Error: 'constructor' is a reserved name (Object prototype). Choose another.
[PASS] Reserved name 'toString' rejected by AddStatus
[PASS] Reserved name 'constructor' rejected by AddStatus
[PASS] Normal name 'Attack' works correctly

--- Test: ChangeState Chain While Loop ---
[PASS] Chain A->B->C resolved via while loop
[PASS] All three enters logged
[PASS] A entered first
[PASS] B entered second
[PASS] C entered third

--- Test: Phase 2 ActiveState Detection ---
[PASS] Phase 2 state action executed
[PASS] State changed to B via Phase 2 ChangeState
[PASS] Normal transition check skipped after Phase 2 state change

--- Test: onExit ChangeState Redirect ---
[PASS] Initial state is A
[PASS] onExit redirect: should end at C, not B
[PASS] Only 2 lifecycle events (A:exit + C:enter)
[PASS] A exits first
[PASS] C enters (redirected from B)
[PASS] B should never be entered (redirected)

--- Test: onExit Redirect + onEnter Chain ---
[PASS] Compound redirect+chain: should end at D
[PASS] Correct lifecycle event count: 4 == 4
[PASS] Lifecycle order: A:exit → C:enter → C:exit → D:enter

--- Test: destroy() Calls ActiveState onExit ---
[PASS] destroy triggers lifecycle events for started machine
[PASS] destroy() triggers activeState.onExit() for started machine
[PASS] destroy() does NOT trigger onExit for unstarted machine

--- Test: destroy() Transitions Cleanup ---
[PASS] Transitions exist before destroy
[PASS] statusDict nulled after destroy
[PASS] activeState nulled after destroy

--- Test: AddStatus Input Validation ---
[FSM] Error: State name cannot be null or empty.
[PASS] null name rejected: no default state set
[FSM] Error: State name cannot be null or empty.
[PASS] empty name rejected: no default state set
[FSM] Error: State must be an instance of FSM_Status.
[PASS] null state rejected: no default state set
[PASS] Valid input accepted: default state set
[PASS] Valid state is active

--- Test: onAction Blocked Before start() ---
[PASS] onAction blocked before start()
[PASS] No lifecycle events before start()
[PASS] onAction works after start()

--- Test: ChangeState Pointer-Only Before start() ---
[PASS] Pointer moved to B before start
[PASS] No lifecycle events (no A:exit, no B:enter) before start
[PASS] Only B:enter on start (not A:enter)
[PASS] start() enters current pointer state B
[PASS] Full lifecycle after start
[PASS] B exits with lifecycle
[PASS] A enters with lifecycle

--- Test: Nested Machine onAction Propagation ---
[PASS] start() propagates onEnter to child machine
[PASS] start() propagates onEnter to child's default leaf state
[PASS] parent.onAction() propagates to leafX.onAction()
[PASS] child machine _onActionCb fires as Phase 4 post-hook
[PASS] After child ChangeState, propagates to leafY
[PASS] leafX no longer receives onAction after switch
[PASS] Child leaves get no onAction after parent switches away
[PASS] Child machine gets no onAction after parent switches away
[PASS] plainB now receives onAction

--- Test: destroy() Nested Machine Recursive ---
[PASS] inner2.onExit called during destroy
[PASS] child machine onExit called during destroy
[PASS] Exit order: inner2 exits before child machine (inside-out)
[PASS] inner1 destroyed after parent.destroy()
[PASS] inner2 destroyed after parent.destroy()
[PASS] child machine destroyed after parent.destroy()
[PASS] other state destroyed after parent.destroy()

--- Test: onExit Lock Nested Interaction ---
[PASS] inner.onExit executed and attempted reentrant ChangeState
[PASS] Reentrant ChangeState blocked by _isChanging lock
[PASS] Parent safely reached target state despite reentrant attempt
[PASS] Both exit events fired
[PASS] inner exits before child (inside-out order preserved)

--- Test: onExit Machine Callback ChangeState Blocked ---
[PASS] Inner state onExit called exactly once during machine exit
[PASS] Machine-level onExit callback fired exactly once
[PASS] ChangeState inside machine onExit callback is swallowed (no enter)
[PASS] Parent safely reached target state despite machine-level reentrant attempt

--- Test: Risk A - onEnterCb ChangeState Safety ---
[PASS] Risk A fix: idle.onExit NOT called (never entered, no exit-before-enter)
[PASS] Risk A fix: idle.onEnter NOT called (pointer moved past idle before propagation)
[PASS] Risk A fix: combat.onEnter called exactly once (not double-entered), got 1
[PASS] Risk A fix: activeState is combat after start()
[PASS] Risk A fix: lastState correctly set to idle by pointer-only branch
[PASS] Risk A fix: actionCount reset to 0 by pointer-only branch
[PASS] Risk A fix: duplicate start() still no-op (guarded by _booted)

--- Test: Risk B - Construction Phase lastState/actionCount Sync ---
[PASS] Risk B: pointer moved to B
[PASS] Risk B: lastState synced to A (previous activeState)
[PASS] Risk B: actionCount reset to 0 after first pointer-only ChangeState
[PASS] Risk B: pointer moved to C
[PASS] Risk B: lastState synced to B (previous activeState)
[PASS] Risk B: actionCount still 0 after second pointer-only ChangeState
[PASS] Risk B: no lifecycle events during construction phase
[PASS] Risk B: start() enters current pointer state C
[PASS] Risk B: lastState updated by full lifecycle ChangeState
[PASS] Risk B: full lifecycle after start()

--- Test: Gate Invalid Target No Spin ---
[PASS] Gate invalid target: activeState unchanged
[PASS] Gate invalid target: Phase 2 action skipped (gate fired but target invalid)
[PASS] Gate invalid target: Phase 4 actionCount still increments
[PASS] Gate invalid target: multiple frames stable, no oscillation spin

--- Test: Normal Invalid Target No Spin ---
[PASS] Normal invalid target: activeState unchanged
[PASS] Normal invalid target: Phase 2 action executed normally
[PASS] Normal invalid target: Phase 4 actionCount increments
[PASS] Normal invalid target: action executes every frame, no spin
[PASS] Normal invalid target: actionCount stable across frames

--- Test: Gate Valid Target Still Works ---
[PASS] Gate valid: stays in A when condition is false
[PASS] Gate valid: A's action executes when gate not triggered
[PASS] Gate valid: transitions to B when condition is true
[PASS] Gate valid: B's action executes in same frame after gate transition

--- Test: T1 - Exception in _csRun Locks Pipeline ---
[PASS] T1: Exception propagated from B.onEnter
[PASS] T1: activeState advanced to B (Phase C completed before Phase D threw)
[PASS] T1: ChangeState locked (_csPend) — cannot transition to C
[PASS] T1: C.onEnter never called (pipeline locked)
[PASS] T1: onAction still ticks (actionCount increments)
[PASS] T1: After delete, prototype ChangeState (pointer-only) works
[PASS] T1: Prototype ChangeState is pointer-only (no onEnter)

--- Test: T2 - Gate Invalid Target Skips Action ---
[PASS] T2: Phase 2 action skipped when Gate fires with invalid target
[PASS] T2: Phase 3 Normal check skipped when Gate fires with invalid target
[PASS] T2: State unchanged
[PASS] T2: Phase 4 actionCount still increments after Gate break

--- Test: T3 - Three Level Nested onAction ---
[PASS] T3: leafA.onAction executed
[PASS] T3: leafA exited after ChangeState
[PASS] T3: leafB entered after ChangeState
[PASS] T3: middle's activeState is now leafB
[PASS] T3: top's activeState unchanged (still middle)
[PASS] T3: Second tick propagates to leafB
[PASS] T3: leafA no longer receives onAction

--- Test: T4 - onExit Double ChangeState Last Wins ---
[PASS] T4: Last ChangeState in onExit wins (D, not C or B)
[PASS] T4: B never entered (overridden by redirect)
[PASS] T4: C never entered (overridden by second redirect)
[PASS] T4: D entered (final redirect target)

--- Test: T5 - destroy() Then start() Safety ---
[PASS] T5: start() after destroy() does not crash
[PASS] T5: activeState remains null after destroy+start

--- Test: T6 - onExit Redirect to Original Target ---
[PASS] T6: Correctly ends at B (redirect to same target)
[PASS] T6: B.onEnter called exactly once (no double-enter from redundant redirect)
[PASS] T6: Exactly 2 lifecycle events
[PASS] T6: A exits first
[PASS] T6: B enters second

--- Test: T7 - destroy() Calls Machine-Level onExit ---
[PASS] T7: Child state onExit called during destroy
[PASS] T7: Machine-level onExit callback called during destroy
[PASS] T7: Child exits before machine-level callback (correct order)

--- Test: T8 - destroy() Seals All Entry Points ---
[PASS] T8: All public methods are safe after destroy (no crash)
[PASS] T8: Machine-level onEnter not re-triggered (no revival)
[PASS] T8: activeState remains null (sealed)
[PASS] T8: activeStateName remains null (sealed)
[PASS] T8: isDestroyed flag intact

--- Test: T9 - AddStatus Duplicate Name Warning ---
[PASS] T9: First AddStatus sets defaultState
[PASS] T9: First AddStatus sets activeState
[FSM] Warning: State 'dup' already registered, overwriting. Previous state instance will have stale superMachine/name/data references.
[PASS] T9: defaultState still points to original (not overwritten by duplicate)
[PASS] T9: ChangeState uses overwritten state from statusDict
[PASS] T9: Old state has stale superMachine reference (documented behavior)

--- Test: T10 - destroy() Seal Covers ChangeState and onAction ---
[PASS] T10: ChangeState is sealed noop after destroy (no crash with any argument)
[PASS] T10: onAction is sealed noop after destroy
[PASS] T10: activeState stays null after sealed ChangeState calls
[PASS] T10: Prototype ChangeState safe after destroy (statusDict=null → silent return)
[PASS] T10: activeState still null after prototype ChangeState on destroyed machine

=== FINAL FSM TEST REPORT ===
Tests Passed: 271
Tests Failed: 0
Success Rate: 100%
🎉 ALL TESTS PASSED! FSM StateMachine implementation is robust and performant.
=== FSM VERIFICATION SUMMARY ===
  Basic state machine operations verified
  State lifecycle management tested
  Transition system robustness confirmed
  Data blackboard functionality verified
  Error handling and edge cases tested
  Memory management and cleanup verified
  Performance benchmarks completed
  Complex workflow scenarios tested
  Path B callback field safety verified
  Explicit start() separation verified
  Reserved name validation verified
  While-loop ChangeState chain verified
  Phase 2 activeState detection verified
  onExit ChangeState redirect verified
  onExit redirect + onEnter chain verified
  destroy() activeState onExit lifecycle verified
  destroy() Transitions cleanup verified
  AddStatus input validation verified
  _started gate: onAction blocked verified
  _started gate: ChangeState pointer-only verified
  Nested machine onAction propagation verified
  Nested machine recursive destroy verified
  onExit lock nested interaction verified
  Risk A: onEnterCb ChangeState safety verified
  Risk B: construction-phase lastState/actionCount sync verified
  Gate invalid target no-spin verified
  Normal invalid target no-spin verified
  Gate valid target regression verified
  AddStatus duplicate name detection verified
  destroy() complete seal (ChangeState+onAction) verified
=============================
