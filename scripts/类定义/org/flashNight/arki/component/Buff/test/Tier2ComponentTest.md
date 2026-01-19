org.flashNight.arki.component.Buff.test.Tier2ComponentTest.runAllTests()

=== Tier 2 Component Test Suite ===

--- TimeLimitComponent Tests ---
🧪 Test 1: TimeLimit Basic Operations
  ✓ Basic: 100 frames limit, alive at 50, alive at 99
  ✅ PASSED

🧪 Test 2: TimeLimit Expiration
  ✓ Expiration: 60 frames → expire, 30 frames + 50 delta → expire
  ✅ PASSED

🧪 Test 3: TimeLimit with MetaBuff
  ✓ MetaBuff: atk=150 during buff, atk=100 after 60 frames
  ✅ PASSED


--- TickComponent Tests ---
🧪 Test 4: Tick Basic Operations
  ✓ Basic: interval=30, tick at 30 frames
  ✅ PASSED

🧪 Test 5: Tick Multiple Triggers
  ✓ Multiple: 35 frames → 3 ticks, +15 frames → 5 ticks total
  ✅ PASSED

🧪 Test 6: Tick Max Limit
  ✓ MaxLimit: 3 max ticks, ends after 3rd tick
  ✅ PASSED

🧪 Test 7: Tick Trigger On Attach
  ✓ TriggerOnAttach: immediately ticks on attach
  ✅ PASSED

🧪 Test 8: Tick with MetaBuff (DoT Simulation)
  ✓ DoT: 100 → 90 → 80 → 70, buff removed
  ✅ PASSED


--- EventListenerComponent Tests (Real EventDispatcher) ---
🧪 Test 9: EventListener Basic Operations (Real EventDispatcher)
  ✓ Basic: non-gate, IDLE state, subscribe/unsubscribe works
  ✅ PASSED

🧪 Test 10: EventListener Filter (Real EventDispatcher)
  ✓ Filter: 'nomatch' rejected, 'match' accepted
  ✅ PASSED

🧪 Test 11: EventListener State Transitions (Real EventDispatcher)
  ✓ Transitions: IDLE→ACTIVE→refresh→IDLE (duration expire)
  ✅ PASSED

🧪 Test 12: EventListener Duration (Permanent vs Timed) (Real EventDispatcher)
  ✓ Duration: 0=permanent, must manually deactivate
  ✅ PASSED

🧪 Test 13: EventListener Manual Control (Real EventDispatcher)
  ✓ Manual: activate/deactivate, setDuration works
  ✅ PASSED

🧪 Test 14: EventListener with MetaBuff (Controller Pattern) (Real EventDispatcher)
  ✓ Controller Pattern: event→ACTIVE→duration→IDLE, controller persists
  ✅ PASSED


--- DelayedTriggerComponent Tests ---
🧪 Test 15: DelayedTrigger Basic Operations
  ✓ Basic: delay=60, remaining=60, not triggered, progress=0
  ✅ PASSED

🧪 Test 16: DelayedTrigger Timing
  ✓ Timing: 30→alive, 59→alive, 60→trigger, no re-trigger
  ✅ PASSED

🧪 Test 17: DelayedTrigger Gate Behavior (isGate=true)
  ✓ Gate: isLifeGate=true, returns false on trigger
  ✅ PASSED

🧪 Test 18: DelayedTrigger Non-Gate Behavior (isGate=false)
  ✓ Non-Gate: isLifeGate=false, returns true on trigger
  ✅ PASSED

🧪 Test 19: DelayedTrigger Reset
  ✓ Reset: triggered→reset→triggered again
  ✅ PASSED

🧪 Test 20: DelayedTrigger triggerNow
  ✓ triggerNow: immediate trigger, no re-trigger
  ✅ PASSED

🧪 Test 21: DelayedTrigger with MetaBuff (Delayed Explosion)
  ✓ Delayed Explosion: HP=100→100→50, buff removed
  ✅ PASSED


=== Tier 2 Component Test Results ===
📊 Total tests: 21
✅ Passed: 21
❌ Failed: 0
📈 Success rate: 100%
🎉 All Tier 2 component tests passed!
=========================================
