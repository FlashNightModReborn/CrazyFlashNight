=== Tier 1 Component Test Suite ===

--- StackLimitComponent Tests ---
🧪 Test 1: StackLimit Basic Operations
  ✓ Basic: init=1, add→2, remove→1
  ✅ PASSED

🧪 Test 2: StackLimit Max Stacks
  ✓ Max: 1→2→3, cannot add 4th
  ✅ PASSED

🧪 Test 3: StackLimit Decay
  ✓ Decay: 3 stacks, 60 frames → 2 stacks
  ✅ PASSED

🧪 Test 4: StackLimit with MetaBuff
  ❌ FAILED: Stack+MetaBuff test failed: Assertion failed: With 2 stacks should be 120, got 110


--- CooldownComponent Tests ---
🧪 Test 5: Cooldown Basic Operations
  ✓ Basic: ready → activate → cooling (60 frames)
  ✅ PASSED

🧪 Test 6: Cooldown Activation & Recovery
  ✓ Activation: cooling 60 frames → ready
  ✅ PASSED

🧪 Test 7: Cooldown Reset
  ✓ Reset: 40 frames remaining → instant reset → ready
  ✅ PASSED

🧪 Test 8: Cooldown Reduction
  ✓ Reduction: 100 -30 = 70, -80 = 0 (ready)
  ✅ PASSED


--- ConditionComponent Tests ---
🧪 Test 9: Condition Basic Operations
  ✓ Basic: value=50 (>30) alive, value=20 (<30) fail
  ✅ PASSED

🧪 Test 10: Condition Dynamic Check
  ✓ Dynamic: check interval=10, fails on 10th frame
  ✅ PASSED

🧪 Test 11: Condition Invert
  ✓ Invert: flag=true → fail, flag=false → alive
  ✅ PASSED

🧪 Test 12: Condition with MetaBuff
  ❌ FAILED: Condition+MetaBuff test failed: Assertion failed: MetaBuff should be removed (HP not low enough)


=== Tier 1 Component Test Results ===
📊 Total tests: 12
✅ Passed: 10
❌ Failed: 2
📈 Success rate: 83%
⚠️  2 test(s) failed.
=========================================
