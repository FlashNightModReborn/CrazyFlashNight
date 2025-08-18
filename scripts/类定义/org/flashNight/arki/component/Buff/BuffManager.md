org.flashNight.arki.component.Buff.test.BuffManagerTest.runAllTests();


=== BuffManager Calculation Accuracy Test Suite ===

--- Phase 1: Basic Calculation Tests ---
🧪 Test 1: Basic ADD Calculation
  ✓ ADD: 100 + 30 + 20 = 150
  ✅ PASSED

🧪 Test 2: Basic MULTIPLY Calculation
  ✓ MULTIPLY: 50 * 1.5 * 1.2 = 90
  ✅ PASSED

🧪 Test 3: Basic PERCENT Calculation
  ✓ PERCENT: 100 * 1.2 * 1.1 = 132
  ✅ PASSED

🧪 Test 4: Calculation Types Priority
  ✓ Priority: (100 + 20) * 1.5 * 1.1 = 198
  ✅ PASSED

🧪 Test 5: OVERRIDE Calculation
  ✓ OVERRIDE: All calculations → 100
  ✅ PASSED


--- Phase 2: MetaBuff Injection & Calculation ---
🧪 Test 6: MetaBuff Pod Injection
  ✓ MetaBuff injection: (50 + 25) * 1.2 = 90
  ✅ PASSED

🧪 Test 7: MetaBuff Calculation Accuracy
  ✓ Damage: (100 + 50) * 1.3 = 195
  ✓ Critical: 1.5 + 0.5 = 2
  ✅ PASSED

🧪 Test 8: MetaBuff State Transitions & Calculations
  ✓ State transitions: 75 → 75 → 75 → 20 (expired)
  ✅ PASSED

🧪 Test 9: MetaBuff Dynamic Injection
  ✓ Dynamic injection: 120 → 198
  ✅ PASSED


--- Phase 3: TimeLimitComponent & Dynamic Calculations ---
🧪 Test 10: Time-Limited Buff Calculations
  ✓ Time-limited calculations: 180 → 120 → 100
  ✅ PASSED

🧪 Test 11: Dynamic Calculation Updates
  ✓ Dynamic updates: 450 → 300 → 200
  ✅ PASSED

🧪 Test 12: Buff Expiration Calculations
  ✓ Cascading expiration: 110 → 100 → 80 → 50
  ✅ PASSED

🧪 Test 13: Cascading Buff Calculations
  ✓ Cascading calculations: 390 → 195 → 150
  ✅ PASSED


--- Phase 4: Complex Calculation Scenarios ---
🧪 Test 14: Stacking Buff Calculations
  ✓ Stacking: 5 stacks (150) → 3 stacks (130)
  ✅ PASSED

🧪 Test 15: Multi-Property Calculations
  ✓ Multi-property: Phys 120, Mag 104, Heal 75
  ✅ PASSED

🧪 Test 16: Calculation Order Dependency
  ✓ Order dependency: 100 → 120 → 144 → 216 → 216 → 200
  ✅ PASSED

🧪 Test 17: Real Game Calculation Scenario
  ✓ Combat stats: AD 195, AS 1.5, CC 30%, CD 200%
  ✓ DPS increase: 246%
  ✅ PASSED


--- Phase 5: PropertyContainer Integration ---
🧪 Test 18: PropertyContainer Calculations
  ✓ PropertyContainer: (200 + 100) * 1.5 = 450
  ✓ Callbacks fired: 22 times
  ✅ PASSED

🧪 Test 19: Dynamic Property Recalculation
  ✓ Dynamic recalc: 75 → 150 → 100
  ✅ PASSED

🧪 Test 20: PropertyContainer Rebuild Accuracy
  ✓ Container rebuild: accurate calculations maintained
  ✅ PASSED

🧪 Test 21: Concurrent Property Updates
  ✓ Concurrent updates handled correctly
  ✅ PASSED


--- Phase 6: Edge Cases & Accuracy ---
🧪 Test 22: Extreme Value Calculations
  ✓ Extreme values: 1M and 0.000001 handled correctly
  ✅ PASSED

🧪 Test 23: Floating Point Accuracy
  ✓ Floating point: 10 * 1.1³ = 13.31 (±0.01)
  ✅ PASSED

🧪 Test 24: Negative Value Calculations
  ✓ Negative values: 100 → 20 → 10
  ✅ PASSED

🧪 Test 25: Zero Value Handling
  ✓ Zero handling: 0+50=50, 100*0=0
  ✅ PASSED


--- Phase 7: Performance & Accuracy at Scale ---
🧪 Test 26: Large Scale Calculation Accuracy
  ✓ 100 buffs: sum = 6050 (accurate)
  ✅ PASSED

🧪 Test 27: Calculation Performance
  ✓ Performance: 100 buffs, 100 updates in 196ms
  ✅ PASSED

🧪 Test 28: Memory and Calculation Consistency
  ✓ Consistency maintained across 10 rounds
  ✅ PASSED


--- Phase: Sticky Container & Lifecycle Contracts ---
🧪 Test 29: Sticky container: meta jitter won't delete property
  ✅ PASSED

🧪 Test 30: unmanageProperty(finalize) then rebind uses plain value as base (independent Pods are cleaned)
  ✅ PASSED

🧪 Test 31: destroy() finalizes all managed properties
  ✅ PASSED

🧪 Test 32: Base value: zero vs undefined
  ✅ PASSED

🧪 Test 33: Calculation order independent of add sequence
  ✅ PASSED

🧪 Test 34: clearAllBuffs keeps properties and resets to base
  ✅ PASSED

🧪 Test 35: MetaBuff jitter stability (no undefined during flips)
  ✅ PASSED

--- Phase 8: Regression & Lifecycle Contracts ---
🧪 Test 36: Same-ID replacement keeps only the new instance
  ✅ PASSED

🧪 Test 37: Injected Pods fire onBuffAdded for each injected pod
  ❌ FAILED: Injected Pods add-event failed: Expected at least 3 onBuffAdded events, got 1

🧪 Test 38: Remove injected pod shrinks injected map by 1
  ❌ FAILED: Remove injected pod failed: Expected injected map to shrink by 1; before=0, after=0

🧪 Test 39: clearAllBuffs emits onBuffRemoved for independent pods
  ✅ PASSED

🧪 Test 40: removeBuff de-dup removes only once
  ✅ PASSED


=== Calculation Accuracy Test Results ===
📊 Total tests: 40
✅ Passed: 38
❌ Failed: 2
📈 Success rate: 95%
⚠️  2 test(s) failed. Please review calculation issues above.
==============================================

=== Calculation Performance Results ===
📊 Large Scale Accuracy:
   buffCount: 100
   calculationTime: 19ms
   expectedValue: 6050
   actualValue: 6050
   accurate: true

📊 Calculation Performance:
   totalBuffs: 100
   properties: 5
   updates: 100
   totalTime: 196ms
   avgUpdateTime: 1.96ms per update

=======================================
