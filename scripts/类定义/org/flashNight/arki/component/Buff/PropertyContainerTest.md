org.flashNight.arki.component.Buff.test.PropertyContainerTest.runAllTests();

=== PropertyContainer Enhanced Test Suite Started ===

--- Phase 1: Basic Functionality Tests ---
🧪 Test 1: Constructor Test
  ✅ PASSED

🧪 Test 2: Base Value Operations Test
    ✓ Initial base value = 100 (Expected: 100)
      Details: Constructor sets base value
    ✓ Initial final value = 100 (Expected: 100)
      Details: No buffs = base value
    ✓ Updated base value = 150 (Expected: 150)
      Details: setBaseValue updates base
    ✓ Updated final value = 150 (Expected: 150)
      Details: Final value reflects base change
    ✓ Target property update = 150 (Expected: 150)
      Details: Target property reflects change
  ✅ PASSED

🧪 Test 3: Property name is attached to target
    ✓ Base value = 10 (Expected: 10)
      Details: 初始值应与 baseValue 一致
  ✅ PASSED


--- Phase 2: PropertyAccessor Integration Tests ---
🧪 Test 4: PropertyAccessor integration
    ✓ Setter propagation = 120 (Expected: 120)
      Details: setBaseValue ➜ target.hp
    ✓ On-set callback = 150 (Expected: 150)
      Details: 写 target.hp ➜ container base
  ✅ PASSED

🧪 Test 5: Direct target property access
    ✓ 5 * 2 = 10 (Expected: 10)
      Details: 最终值应为 10
  ✅ PASSED

🧪 Test 6: Caching mechanism
    ✓ Two reads, no change = 50 (Expected: 50)
    ✓ Cache invalidated after addBuff = 75 (Expected: 75)
  ✅ PASSED


--- Phase 3: Buff Management Tests ---
🧪 Test 7: addBuff()
    ✓ 30 + 10 = 40 (Expected: 40)
  ✅ PASSED

🧪 Test 8: removeBuff()
    ✓ Back to base = 1 (Expected: 1)
  ✅ PASSED

🧪 Test 9: clearBuffs()
    ✓ Back to 5 = 5 (Expected: 5)
  ✅ PASSED

🧪 Test 10: getBuffCount / getActiveBuffCount()
  ✅ PASSED

🧪 Test 11: hasBuff()
  ✅ PASSED


--- Phase 4: Numerical Calculation Correctness Tests ---
🧪 Test 12: Basic Calculation Types Mathematical Correctness
  Testing individual calculation types:
    ✓ ADD: 100 + 25.5 = 125.5 (Expected: 125.5)
      Details: 100 + 25.5 = 125.5
    ✓ MULTIPLY: 100 * 2.5 = 250 (Expected: 250)
      Details: 100 * 2.5 = 250
    ✓ PERCENT: 100 * (1 + 0.3) = 130 (Expected: 130)
      Details: 100 * (1 + 0.3) = 130
    ✓ OVERRIDE: 88.88 = 88.88 (Expected: 88.88)
      Details: Override replaces with 88.88
    ✓ MAX: Math.max(100, 120) = 120 (Expected: 120)
      Details: Math.max(100, 120) = 120
    ✓ MIN: Math.min(100, 80) = 80 (Expected: 80)
      Details: Math.min(100, 80) = 80
  ✅ PASSED

🧪 Test 13: Single-buff calculation
    ✓ 2 + 3 = 5 (Expected: 5)
  ✅ PASSED

🧪 Test 14: Multiple-buff calculation
    ✓ ((10+5)*2)*1.1 ≈ 33 (Expected: 33, Diff: 0)
  ✅ PASSED

🧪 Test 15: OVERRIDE priority over others
    ✓ OVERRIDE wins = 500 (Expected: 500)
  ✅ PASSED

🧪 Test 16: Complex buff chain
    ✓ Complex chain = 150 (Expected: 150)
      Details: (20+10)*1.25*3 → max(…,150)
  ✅ PASSED

🧪 Test 17: Advanced Calculation Combinations
  Testing complex calculation combinations:
    ✓ Multi-ADD + MULTIPLY: (50+20+15+10)*2 = 190 (Expected: 190)
      Details: Step: 50 → 95 (+45) → 190 (*2)
    ✓ ADD+MULTIPLY+PERCENT: ((50+30)*1.5)*1.2 = 144 (Expected: 144)
      Details: Step: 50 → 80 (+30) → 120 (*1.5) → 144 (*1.2)
    ✓ Multi-PERCENT: 50*1.1*1.15*1.05 = 66.4125 (Expected: 66.4125)
      Details: Step: 50 → 55 (*1.1) → 63.25 (*1.15) → 66.4125 (*1.05)
  ✅ PASSED

🧪 Test 18: Floating Point Precision
  Testing floating point precision:
    ✓ Decimal ADD: 1.0+0.1+0.2+0.3 ≈ 1.6 (Expected: 1.6, Diff: 0)
      Details: Testing decimal addition precision
    ✓ Division: 1.0*(1/3) ≈ 0.333333333333333 (Expected: 0.333333333333333, Diff: 0)
      Details: Testing division precision: 1/3 = 0.333333333333333
    ✓ Complex: (1*π)*e ≈ 8.53973422267357 (Expected: 8.53973422267357, Diff: 0)
      Details: Testing π and e precision: π=3.14159265358979, e=2.71828182845905
  ✅ PASSED

🧪 Test 19: Extreme Values Handling
  Testing extreme values:
    ✓ Big numbers: 1000000*1000 = 1000000000 (Expected: 1000000000)
      Details: Testing large number multiplication
    ✓ Small numbers: 0.001+0.0001 ≈ 0.0011 (Expected: 0.0011, Diff: 0)
      Details: Testing small number addition
    ✓ Negative: (-100-50)*(-2) = 300 (Expected: 300)
      Details: Testing negative number operations: (-100-50)*(-2) = 300
    ✓ Zero base: 0+100 = 100 (Expected: 100)
      Details: Testing zero base value
  ✅ PASSED

🧪 Test 20: Calculation Order Dependency
  Testing calculation order consistency:
    ✓ Order independence = 33 (Expected: 33)
      Details: Different addition orders should yield same result: ((10+5)*2)*1.1 = 33
    ✓ OVERRIDE priority = 200 (Expected: 200)
      Details: OVERRIDE should ignore all other calculations and set value to 200
  ✅ PASSED

🧪 Test 21: Nested Calculation Scenarios
  Testing complex nested scenarios:
    ✓ Complex damage calculation = 150 (Expected: 150)
      Details: Steps: 100→150(+50)→180(*1.2)→216(*1.2)→432(*2)→432(max)→150(min)
    ✓ Character HP calculation ≈ 503.125 (Expected: 503.125, Diff: 0)
      Details: HP chain: (200+100+50)*1.15*1.25 = 503.125
  ✅ PASSED

🧪 Test 22: Mathematical Edge Cases
  Testing mathematical edge cases:
    ✓ Near zero multiply ≈ 0.0001 (Expected: 0.0001, Diff: 1.35525271560688e-20)
      Details: 100 * 0.000001 = 0.0001
    ✓ Huge percentage = 1000 (Expected: 1000)
      Details: 10 * (1 + 99) = 10 * 100 = 1000
    ✓ Negative percentage = 20 (Expected: 20)
      Details: 100 * (1 - 0.8) = 100 * 0.2 = 20
    ✓ Chain multiplication ≈ 3.22102 (Expected: 3.22102, Diff: 4.44089209850063e-16)
      Details: 2 * 1.1^5 = 3.22102
    ✓ Multiple MIN/MAX = 75 (Expected: 75)
      Details: Chain: 50→max(1000)→max(2000)→min(100)→min(75) = 75
  ✅ PASSED


--- Phase 5: Performance Tests ---
🧪 Test 23: Performance with Many Buffs
  Adding 100 buffs...
  Calculating with 100 buffs...
    📊 Performance recorded: Many Buffs
  ✅ PASSED

🧪 Test 24: Frequent Access Performance
  Performing 10000 property accesses...
    📊 Performance recorded: Frequent Access
  ✅ PASSED

🧪 Test 25: Cache Efficiency
  Testing cache hit efficiency...
    📊 Performance recorded: Cache Efficiency
  ✅ PASSED

🧪 Test 26: Memory Usage Optimization
  Testing memory usage patterns...
    📊 Performance recorded: Memory Usage
  ✅ PASSED

🧪 Test 27: Calculation Complexity Scaling
  Testing calculation time scaling with buff count...
    📊 Performance recorded: Complexity Scaling
  ✅ PASSED

🧪 Test 28: Concurrent Access Simulation
  Simulating concurrent property access and modification...
    📊 Performance recorded: Concurrent Access
  ✅ PASSED


--- Phase 6: Callback and Integration Tests ---
🧪 Test 29: Change-callback invocation
    ✓ Callback value = 8 (Expected: 8)
  ✅ PASSED

🧪 Test 30: External set invalidates cache
    ✓ After external set = 60 (Expected: 60)
  ✅ PASSED


--- Phase 7: Caching and Optimization Tests ---
🧪 Test 31: Final value cached until dirty
    ✓ Cache stable = 100 (Expected: 100)
    ✓ Cache invalid after buff = 150 (Expected: 150)
  ✅ PASSED

🧪 Test 32: forceRecalculate()
    ✓ 1*10 = 10 (Expected: 10)
  ✅ PASSED

🧪 Test 33: Dirty flag on mutation
    ✓ 5+5 = 10 (Expected: 10)
  ✅ PASSED


--- Phase 8: Edge Cases and Error Handling ---
🧪 Test 34: Empty container behaves
    ✓ No buffs = 0 (Expected: 0)
  ✅ PASSED

🧪 Test 35: Inactive buffs ignored
[PropertyContainer] 警告：PodBuff 目标属性不匹配。 期望: stealth, 实际: undefined
    ✓ Value unchanged = 1 (Expected: 1)
  ✅ PASSED

🧪 Test 36: Gracefully handle invalid inputs
  ✅ PASSED

🧪 Test 37: Misc edge cases
    ✓ min(-10,-20) = -20 (Expected: -20)
  ✅ PASSED


--- Phase 9: Debug and Utility Tests ---
🧪 Test 38: toString() content
  ✅ PASSED

🧪 Test 39: destroy() safety
  ✅ PASSED


--- Phase 10: Accessor–Container Lifecycle Integration ---
🧪 Test 40: Finalize to plain data property (detach underlying accessor)
    ✓ Before finalize (10+5)*2 = 30 (Expected: 30)
    ✓ Direct write after finalize = 99 (Expected: 99)
    ✓ Container changes no longer affect target = 99 (Expected: 99)
  ✅ PASSED

🧪 Test 41: Rebind container on same target/prop after finalize
    ✓ Rebind new container base = 100 (Expected: 100)
    ✓ External write flows to new container = 123 (Expected: 123)
  ✅ PASSED

🧪 Test 42: destroy() removes property from target (align with accessor.destroy)
  ✅ PASSED

🧪 Test 43: Isolation: multi containers on same target different props
    ✓ A calc = 11 (Expected: 11)
    ✓ B calc = 60 (Expected: 60)
    ✓ A stays frozen (plain data) = 11 (Expected: 11)
  ❌ FAILED: Isolation across containers failed: B changes continue - Expected: 65, Got: 75, Diff: 10

🧪 Test 44: External write behavior: before vs after finalize
    ✓ Before finalize external set = 60 (Expected: 60)
    ✓ After finalize external set (plain) = 77 (Expected: 77)
  ✅ PASSED


=== PropertyContainer Enhanced Test Suite Results ===
📊 Total tests: 44
✅ Passed: 43
❌ Failed: 1
📈 Success rate: 98%
⚠️  1 test(s) failed. Please review the failures above.
====================================================

=== Performance Test Results ===
📊 Many Buffs:
   buffCount: 100
   addTime: 3
   calcTime: 3
   avgCalcTime: 0.03

📊 Frequent Access:
   accessCount: 10000
   totalTime: 86
   avgAccessTime: 0.0086

📊 Cache Efficiency:
   firstCompute: 1
   cacheHits: 0
   efficiency: 100% cache hit rate

📊 Memory Usage:
   created: 100
   destroyed: 50
   remaining: 50

📊 Complexity Scaling:
   3: [object Object]
   2: [object Object]
   1: [object Object]
   0: [object Object]

📊 Concurrent Access:
   reads: 100
   modifications: 10
   finalValue: 525
   finalBuffCount: 12

================================