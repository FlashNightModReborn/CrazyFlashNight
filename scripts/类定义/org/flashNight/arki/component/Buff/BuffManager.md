org.flashNight.arki.component.Buff.test.BuffManagerTest.runAllTests();

D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerTest.as，1862 行	类型不匹配。
D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerTest.as，1838 行	类型不匹配。
D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerTest.as，1837 行	类型不匹配。
D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerTest.as，1807 行	类型不匹配。
D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerTest.as，1782 行	类型不匹配。
D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerTest.as，1756 行	类型不匹配。
D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerTest.as，1755 行	类型不匹配。




=== BuffManager Calculation Accuracy Test Suite ===

--- Phase 1: Basic Calculation Tests ---
🧪 Test 1: Basic ADD Calculation
[BuffManager] _redistributeDirtyProps for: attack,
  ✓ ADD: 100 + 30 + 20 = 150
  ✅ PASSED

🧪 Test 2: Basic MULTIPLY Calculation
[BuffManager] _redistributeDirtyProps for: defense,attack,
  ✓ MULTIPLY: 50 * 1.5 * 1.2 = 90
  ✅ PASSED

🧪 Test 3: Basic PERCENT Calculation
[BuffManager] _redistributeDirtyProps for: speed,defense,attack,
  ✓ PERCENT: 100 * 1.2 * 1.1 = 132
  ✅ PASSED

🧪 Test 4: Calculation Types Priority
[BuffManager] _redistributeDirtyProps for: power,speed,defense,attack,
  ✓ Priority: (100 + 20) * 1.5 * 1.1 = 198
  ✅ PASSED

🧪 Test 5: OVERRIDE Calculation
[BuffManager] _redistributeDirtyProps for: health,power,speed,defense,attack,
  ✓ OVERRIDE: All calculations → 100
  ✅ PASSED


--- Phase 2: MetaBuff Injection & Calculation ---
🧪 Test 6: MetaBuff Pod Injection
[BuffManager] Injected Meta=14 pods=15,16 count=2
[BuffManager] _redistributeDirtyProps for: strength,health,power,speed,defense,attack,
  ✓ MetaBuff injection: (50 + 25) * 1.2 = 90
[BuffManager] Ejecting Meta=14 injectedIds=15,16 count=2
[BuffManager]   Removing injected Pod: 16
[BuffManager]   Removing injected Pod: 15
  ✅ PASSED

🧪 Test 7: MetaBuff Calculation Accuracy
[BuffManager] Injected Meta=20 pods=21,22,23 count=3
[BuffManager] _redistributeDirtyProps for: critical,damage,strength,health,power,speed,defense,attack,
  ✓ Damage: (100 + 50) * 1.3 = 195
  ✓ Critical: 1.5 + 0.5 = 2
[BuffManager] Ejecting Meta=20 injectedIds=21,22,23 count=3
[BuffManager]   Removing injected Pod: 23
[BuffManager]   Removing injected Pod: 22
[BuffManager]   Removing injected Pod: 21
  ✅ PASSED

🧪 Test 8: MetaBuff State Transitions & Calculations
[BuffManager] Injected Meta=26 pods=27,28 count=2
[BuffManager] _redistributeDirtyProps for: agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Meta stateChanged: id=26, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=26 injectedIds=27,28 count=2
[BuffManager]   Removing injected Pod: 28
[BuffManager]   Removing injected Pod: 27
[BuffManager] _redistributeDirtyProps for: agility,
[BuffManager] Meta stateChanged: id=26, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=26 injectedIds=null count=0
  ✓ State transitions: 75 → 75 → 75 → 20 (expired)
  ✅ PASSED

🧪 Test 9: MetaBuff Dynamic Injection
[BuffManager] _redistributeDirtyProps for: intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Injected Meta=32 pods=33,34 count=2
[BuffManager] _redistributeDirtyProps for: intelligence,
  ✓ Dynamic injection: 120 → 198
[BuffManager] Ejecting Meta=32 injectedIds=33,34 count=2
[BuffManager]   Removing injected Pod: 34
[BuffManager]   Removing injected Pod: 33
  ✅ PASSED


--- Phase 3: TimeLimitComponent & Dynamic Calculations ---
🧪 Test 10: Time-Limited Buff Calculations
[BuffManager] Injected Meta=36 pods=39 count=1
[BuffManager] Injected Meta=38 pods=40 count=1
[BuffManager] _redistributeDirtyProps for: armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Meta stateChanged: id=36, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=36 injectedIds=39 count=1
[BuffManager]   Removing injected Pod: 39
[BuffManager] _redistributeDirtyProps for: armor,
[BuffManager] Meta stateChanged: id=38, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=38 injectedIds=40 count=1
[BuffManager]   Removing injected Pod: 40
[BuffManager] Meta stateChanged: id=36, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=36 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: armor,
  ✓ Time-limited calculations: 180 → 120 → 100
[BuffManager] Ejecting Meta=38 injectedIds=null count=0
  ✅ PASSED

🧪 Test 11: Dynamic Calculation Updates
[BuffManager] Injected Meta=43 pods=44 count=1
[BuffManager] _redistributeDirtyProps for: mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Meta stateChanged: id=43, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=43 injectedIds=44 count=1
[BuffManager]   Removing injected Pod: 44
[BuffManager] _redistributeDirtyProps for: mana,
[BuffManager] Meta stateChanged: id=43, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=43 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: mana,
  ✓ Dynamic updates: 450 → 300 → 200
  ✅ PASSED

🧪 Test 12: Buff Expiration Calculations
[BuffManager] Injected Meta=46 pods=47 count=1
[BuffManager] Injected Meta=49 pods=50 count=1
[BuffManager] Injected Meta=52 pods=53 count=1
[BuffManager] _redistributeDirtyProps for: resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Meta stateChanged: id=46, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=46 injectedIds=47 count=1
[BuffManager]   Removing injected Pod: 47
[BuffManager] _redistributeDirtyProps for: resistance,
[BuffManager] Meta stateChanged: id=49, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=49 injectedIds=50 count=1
[BuffManager]   Removing injected Pod: 50
[BuffManager] Meta stateChanged: id=46, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=46 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: resistance,
[BuffManager] Meta stateChanged: id=52, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=52 injectedIds=53 count=1
[BuffManager]   Removing injected Pod: 53
[BuffManager] Meta stateChanged: id=49, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=49 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: resistance,
  ✓ Cascading expiration: 110 → 100 → 80 → 50
[BuffManager] Ejecting Meta=52 injectedIds=null count=0
  ✅ PASSED

🧪 Test 13: Cascading Buff Calculations
[BuffManager] Injected Meta=56 pods=59 count=1
[BuffManager] Injected Meta=58 pods=60 count=1
[BuffManager] _redistributeDirtyProps for: energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Meta stateChanged: id=58, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=58 injectedIds=60 count=1
[BuffManager]   Removing injected Pod: 60
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Meta stateChanged: id=58, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=58 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=56, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=56 injectedIds=59 count=1
[BuffManager]   Removing injected Pod: 59
[BuffManager] _redistributeDirtyProps for: energy,
  ✓ Cascading calculations: 390 → 195 → 150
[BuffManager] Ejecting Meta=56 injectedIds=null count=0
  ✅ PASSED


--- Phase 4: Complex Calculation Scenarios ---
🧪 Test 14: Stacking Buff Calculations
[BuffManager] _redistributeDirtyProps for: energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: power,
  ✓ Stacking: 5 stacks (150) → 3 stacks (130)
  ✅ PASSED

🧪 Test 15: Multi-Property Calculations
[BuffManager] Injected Meta=69 pods=70,71,72 count=3
[BuffManager] _redistributeDirtyProps for: healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✓ Multi-property: Phys 120, Mag 104, Heal 75
[BuffManager] Ejecting Meta=69 injectedIds=70,71,72 count=3
[BuffManager]   Removing injected Pod: 72
[BuffManager]   Removing injected Pod: 71
[BuffManager]   Removing injected Pod: 70
  ✅ PASSED

🧪 Test 16: Calculation Order Dependency
[BuffManager] _redistributeDirtyProps for: healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✓ Order dependency: 100 → 120 → 144 → 216 → 216 → 200
  ✅ PASSED

🧪 Test 17: Real Game Calculation Scenario
[BuffManager] Injected Meta=82 pods=83,84,85 count=3
[BuffManager] _redistributeDirtyProps for: criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✓ Combat stats: AD 195, AS 1.5, CC 30%, CD 200%
  ✓ DPS increase: 246%
[BuffManager] Ejecting Meta=82 injectedIds=83,84,85 count=3
[BuffManager]   Removing injected Pod: 85
[BuffManager]   Removing injected Pod: 84
[BuffManager]   Removing injected Pod: 83
  ✅ PASSED


--- Phase 5: PropertyContainer Integration ---
🧪 Test 18: PropertyContainer Calculations
[BuffManager] _redistributeDirtyProps for: testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✓ PropertyContainer: (200 + 100) * 1.5 = 450
  ✓ Callbacks fired: 22 times
  ✅ PASSED

🧪 Test 19: Dynamic Property Recalculation
[BuffManager] _redistributeDirtyProps for: dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: dynamicStat,
[BuffManager] _redistributeDirtyProps for: dynamicStat,
  ✓ Dynamic recalc: 75 → 150 → 100
  ✅ PASSED

🧪 Test 20: PropertyContainer Rebuild Accuracy
[BuffManager] _redistributeDirtyProps for: prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Injected Meta=96 pods=97,98 count=2
[BuffManager] _redistributeDirtyProps for: prop2,prop1,
  ✓ Container rebuild: accurate calculations maintained
[BuffManager] Ejecting Meta=96 injectedIds=97,98 count=2
[BuffManager]   Removing injected Pod: 98
[BuffManager]   Removing injected Pod: 97
  ✅ PASSED

🧪 Test 21: Concurrent Property Updates
[BuffManager] _redistributeDirtyProps for: concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: concurrent,
  ✓ Concurrent updates handled correctly
  ✅ PASSED


--- Phase 6: Edge Cases & Accuracy ---
🧪 Test 22: Extreme Value Calculations
[BuffManager] _redistributeDirtyProps for: extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: extreme,
  ✓ Extreme values: 1M and 0.000001 handled correctly
  ✅ PASSED

🧪 Test 23: Floating Point Accuracy
[BuffManager] _redistributeDirtyProps for: floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✓ Floating point: 10 * 1.1³ = 13.31 (±0.01)
  ✅ PASSED

🧪 Test 24: Negative Value Calculations
[BuffManager] _redistributeDirtyProps for: balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: balance,
  ✓ Negative values: 100 → 20 → 10
  ✅ PASSED

🧪 Test 25: Zero Value Handling
[BuffManager] _redistributeDirtyProps for: zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: zeroTest,
  ✓ Zero handling: 0+50=50, 100*0=0
  ✅ PASSED


--- Phase 7: Performance & Accuracy at Scale ---
🧪 Test 26: Large Scale Calculation Accuracy
[BuffManager] _redistributeDirtyProps for: largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✓ 100 buffs: sum = 6050 (accurate)
  ✅ PASSED

🧪 Test 27: Calculation Performance
[BuffManager] _redistributeDirtyProps for: stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✓ Performance: 100 buffs, 100 updates in 58ms
  ✅ PASSED

🧪 Test 28: Memory and Calculation Consistency
[BuffManager] Injected Meta=316 pods=317 count=1
[BuffManager] Injected Meta=319 pods=320 count=1
[BuffManager] Injected Meta=322 pods=323 count=1
[BuffManager] Injected Meta=325 pods=326 count=1
[BuffManager] Injected Meta=328 pods=329 count=1
[BuffManager] Injected Meta=331 pods=332 count=1
[BuffManager] Injected Meta=334 pods=335 count=1
[BuffManager] Injected Meta=337 pods=338 count=1
[BuffManager] Injected Meta=340 pods=341 count=1
[BuffManager] Injected Meta=343 pods=344 count=1
[BuffManager] _redistributeDirtyProps for: consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Meta stateChanged: id=343, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=343 injectedIds=344 count=1
[BuffManager]   Removing injected Pod: 344
[BuffManager] Meta stateChanged: id=340, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=340 injectedIds=341 count=1
[BuffManager]   Removing injected Pod: 341
[BuffManager] Meta stateChanged: id=337, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=337 injectedIds=338 count=1
[BuffManager]   Removing injected Pod: 338
[BuffManager] Meta stateChanged: id=334, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=334 injectedIds=335 count=1
[BuffManager]   Removing injected Pod: 335
[BuffManager] Meta stateChanged: id=331, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=331 injectedIds=332 count=1
[BuffManager]   Removing injected Pod: 332
[BuffManager] Meta stateChanged: id=328, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=328 injectedIds=329 count=1
[BuffManager]   Removing injected Pod: 329
[BuffManager] Meta stateChanged: id=325, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=325 injectedIds=326 count=1
[BuffManager]   Removing injected Pod: 326
[BuffManager] Meta stateChanged: id=322, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=322 injectedIds=323 count=1
[BuffManager]   Removing injected Pod: 323
[BuffManager] Meta stateChanged: id=319, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=319 injectedIds=320 count=1
[BuffManager]   Removing injected Pod: 320
[BuffManager] Meta stateChanged: id=316, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=316 injectedIds=317 count=1
[BuffManager]   Removing injected Pod: 317
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=346 pods=347 count=1
[BuffManager] Injected Meta=349 pods=350 count=1
[BuffManager] Injected Meta=352 pods=353 count=1
[BuffManager] Injected Meta=355 pods=356 count=1
[BuffManager] Injected Meta=358 pods=359 count=1
[BuffManager] Injected Meta=361 pods=362 count=1
[BuffManager] Injected Meta=364 pods=365 count=1
[BuffManager] Injected Meta=367 pods=368 count=1
[BuffManager] Injected Meta=370 pods=371 count=1
[BuffManager] Injected Meta=373 pods=374 count=1
[BuffManager] Meta stateChanged: id=343, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=343 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=340, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=340 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=337, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=337 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=334, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=334 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=331, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=331 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=328, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=328 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=325, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=325 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=322, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=322 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=319, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=319 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=316, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=316 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=373, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=373 injectedIds=374 count=1
[BuffManager]   Removing injected Pod: 374
[BuffManager] Meta stateChanged: id=370, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=370 injectedIds=371 count=1
[BuffManager]   Removing injected Pod: 371
[BuffManager] Meta stateChanged: id=367, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=367 injectedIds=368 count=1
[BuffManager]   Removing injected Pod: 368
[BuffManager] Meta stateChanged: id=364, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=364 injectedIds=365 count=1
[BuffManager]   Removing injected Pod: 365
[BuffManager] Meta stateChanged: id=361, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=361 injectedIds=362 count=1
[BuffManager]   Removing injected Pod: 362
[BuffManager] Meta stateChanged: id=358, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=358 injectedIds=359 count=1
[BuffManager]   Removing injected Pod: 359
[BuffManager] Meta stateChanged: id=355, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=355 injectedIds=356 count=1
[BuffManager]   Removing injected Pod: 356
[BuffManager] Meta stateChanged: id=352, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=352 injectedIds=353 count=1
[BuffManager]   Removing injected Pod: 353
[BuffManager] Meta stateChanged: id=349, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=349 injectedIds=350 count=1
[BuffManager]   Removing injected Pod: 350
[BuffManager] Meta stateChanged: id=346, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=346 injectedIds=347 count=1
[BuffManager]   Removing injected Pod: 347
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=376 pods=377 count=1
[BuffManager] Injected Meta=379 pods=380 count=1
[BuffManager] Injected Meta=382 pods=383 count=1
[BuffManager] Injected Meta=385 pods=386 count=1
[BuffManager] Injected Meta=388 pods=389 count=1
[BuffManager] Injected Meta=391 pods=392 count=1
[BuffManager] Injected Meta=394 pods=395 count=1
[BuffManager] Injected Meta=397 pods=398 count=1
[BuffManager] Injected Meta=400 pods=401 count=1
[BuffManager] Injected Meta=403 pods=404 count=1
[BuffManager] Meta stateChanged: id=373, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=373 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=370, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=370 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=367, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=367 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=364, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=364 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=361, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=361 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=358, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=358 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=355, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=355 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=352, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=352 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=349, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=349 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=346, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=346 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=403, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=403 injectedIds=404 count=1
[BuffManager]   Removing injected Pod: 404
[BuffManager] Meta stateChanged: id=400, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=400 injectedIds=401 count=1
[BuffManager]   Removing injected Pod: 401
[BuffManager] Meta stateChanged: id=397, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=397 injectedIds=398 count=1
[BuffManager]   Removing injected Pod: 398
[BuffManager] Meta stateChanged: id=394, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=394 injectedIds=395 count=1
[BuffManager]   Removing injected Pod: 395
[BuffManager] Meta stateChanged: id=391, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=391 injectedIds=392 count=1
[BuffManager]   Removing injected Pod: 392
[BuffManager] Meta stateChanged: id=388, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=388 injectedIds=389 count=1
[BuffManager]   Removing injected Pod: 389
[BuffManager] Meta stateChanged: id=385, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=385 injectedIds=386 count=1
[BuffManager]   Removing injected Pod: 386
[BuffManager] Meta stateChanged: id=382, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=382 injectedIds=383 count=1
[BuffManager]   Removing injected Pod: 383
[BuffManager] Meta stateChanged: id=379, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=379 injectedIds=380 count=1
[BuffManager]   Removing injected Pod: 380
[BuffManager] Meta stateChanged: id=376, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=376 injectedIds=377 count=1
[BuffManager]   Removing injected Pod: 377
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=406 pods=407 count=1
[BuffManager] Injected Meta=409 pods=410 count=1
[BuffManager] Injected Meta=412 pods=413 count=1
[BuffManager] Injected Meta=415 pods=416 count=1
[BuffManager] Injected Meta=418 pods=419 count=1
[BuffManager] Injected Meta=421 pods=422 count=1
[BuffManager] Injected Meta=424 pods=425 count=1
[BuffManager] Injected Meta=427 pods=428 count=1
[BuffManager] Injected Meta=430 pods=431 count=1
[BuffManager] Injected Meta=433 pods=434 count=1
[BuffManager] Meta stateChanged: id=403, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=403 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=400, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=400 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=397, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=397 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=394, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=394 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=391, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=391 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=388, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=388 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=385, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=385 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=382, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=382 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=379, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=379 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=376, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=376 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=433, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=433 injectedIds=434 count=1
[BuffManager]   Removing injected Pod: 434
[BuffManager] Meta stateChanged: id=430, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=430 injectedIds=431 count=1
[BuffManager]   Removing injected Pod: 431
[BuffManager] Meta stateChanged: id=427, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=427 injectedIds=428 count=1
[BuffManager]   Removing injected Pod: 428
[BuffManager] Meta stateChanged: id=424, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=424 injectedIds=425 count=1
[BuffManager]   Removing injected Pod: 425
[BuffManager] Meta stateChanged: id=421, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=421 injectedIds=422 count=1
[BuffManager]   Removing injected Pod: 422
[BuffManager] Meta stateChanged: id=418, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=418 injectedIds=419 count=1
[BuffManager]   Removing injected Pod: 419
[BuffManager] Meta stateChanged: id=415, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=415 injectedIds=416 count=1
[BuffManager]   Removing injected Pod: 416
[BuffManager] Meta stateChanged: id=412, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=412 injectedIds=413 count=1
[BuffManager]   Removing injected Pod: 413
[BuffManager] Meta stateChanged: id=409, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=409 injectedIds=410 count=1
[BuffManager]   Removing injected Pod: 410
[BuffManager] Meta stateChanged: id=406, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=406 injectedIds=407 count=1
[BuffManager]   Removing injected Pod: 407
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=436 pods=437 count=1
[BuffManager] Injected Meta=439 pods=440 count=1
[BuffManager] Injected Meta=442 pods=443 count=1
[BuffManager] Injected Meta=445 pods=446 count=1
[BuffManager] Injected Meta=448 pods=449 count=1
[BuffManager] Injected Meta=451 pods=452 count=1
[BuffManager] Injected Meta=454 pods=455 count=1
[BuffManager] Injected Meta=457 pods=458 count=1
[BuffManager] Injected Meta=460 pods=461 count=1
[BuffManager] Injected Meta=463 pods=464 count=1
[BuffManager] Meta stateChanged: id=433, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=433 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=430, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=430 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=427, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=427 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=424, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=424 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=421, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=421 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=418, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=418 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=415, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=415 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=412, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=412 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=409, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=409 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=406, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=406 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=463, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=463 injectedIds=464 count=1
[BuffManager]   Removing injected Pod: 464
[BuffManager] Meta stateChanged: id=460, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=460 injectedIds=461 count=1
[BuffManager]   Removing injected Pod: 461
[BuffManager] Meta stateChanged: id=457, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=457 injectedIds=458 count=1
[BuffManager]   Removing injected Pod: 458
[BuffManager] Meta stateChanged: id=454, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=454 injectedIds=455 count=1
[BuffManager]   Removing injected Pod: 455
[BuffManager] Meta stateChanged: id=451, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=451 injectedIds=452 count=1
[BuffManager]   Removing injected Pod: 452
[BuffManager] Meta stateChanged: id=448, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=448 injectedIds=449 count=1
[BuffManager]   Removing injected Pod: 449
[BuffManager] Meta stateChanged: id=445, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=445 injectedIds=446 count=1
[BuffManager]   Removing injected Pod: 446
[BuffManager] Meta stateChanged: id=442, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=442 injectedIds=443 count=1
[BuffManager]   Removing injected Pod: 443
[BuffManager] Meta stateChanged: id=439, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=439 injectedIds=440 count=1
[BuffManager]   Removing injected Pod: 440
[BuffManager] Meta stateChanged: id=436, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=436 injectedIds=437 count=1
[BuffManager]   Removing injected Pod: 437
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=466 pods=467 count=1
[BuffManager] Injected Meta=469 pods=470 count=1
[BuffManager] Injected Meta=472 pods=473 count=1
[BuffManager] Injected Meta=475 pods=476 count=1
[BuffManager] Injected Meta=478 pods=479 count=1
[BuffManager] Injected Meta=481 pods=482 count=1
[BuffManager] Injected Meta=484 pods=485 count=1
[BuffManager] Injected Meta=487 pods=488 count=1
[BuffManager] Injected Meta=490 pods=491 count=1
[BuffManager] Injected Meta=493 pods=494 count=1
[BuffManager] Meta stateChanged: id=463, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=463 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=460, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=460 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=457, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=457 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=454, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=454 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=451, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=451 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=448, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=448 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=445, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=445 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=442, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=442 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=439, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=439 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=436, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=436 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=493, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=493 injectedIds=494 count=1
[BuffManager]   Removing injected Pod: 494
[BuffManager] Meta stateChanged: id=490, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=490 injectedIds=491 count=1
[BuffManager]   Removing injected Pod: 491
[BuffManager] Meta stateChanged: id=487, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=487 injectedIds=488 count=1
[BuffManager]   Removing injected Pod: 488
[BuffManager] Meta stateChanged: id=484, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=484 injectedIds=485 count=1
[BuffManager]   Removing injected Pod: 485
[BuffManager] Meta stateChanged: id=481, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=481 injectedIds=482 count=1
[BuffManager]   Removing injected Pod: 482
[BuffManager] Meta stateChanged: id=478, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=478 injectedIds=479 count=1
[BuffManager]   Removing injected Pod: 479
[BuffManager] Meta stateChanged: id=475, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=475 injectedIds=476 count=1
[BuffManager]   Removing injected Pod: 476
[BuffManager] Meta stateChanged: id=472, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=472 injectedIds=473 count=1
[BuffManager]   Removing injected Pod: 473
[BuffManager] Meta stateChanged: id=469, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=469 injectedIds=470 count=1
[BuffManager]   Removing injected Pod: 470
[BuffManager] Meta stateChanged: id=466, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=466 injectedIds=467 count=1
[BuffManager]   Removing injected Pod: 467
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=496 pods=497 count=1
[BuffManager] Injected Meta=499 pods=500 count=1
[BuffManager] Injected Meta=502 pods=503 count=1
[BuffManager] Injected Meta=505 pods=506 count=1
[BuffManager] Injected Meta=508 pods=509 count=1
[BuffManager] Injected Meta=511 pods=512 count=1
[BuffManager] Injected Meta=514 pods=515 count=1
[BuffManager] Injected Meta=517 pods=518 count=1
[BuffManager] Injected Meta=520 pods=521 count=1
[BuffManager] Injected Meta=523 pods=524 count=1
[BuffManager] Meta stateChanged: id=493, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=493 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=490, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=490 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=487, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=487 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=484, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=484 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=481, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=481 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=478, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=478 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=475, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=475 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=472, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=472 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=469, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=469 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=466, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=466 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=523, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=523 injectedIds=524 count=1
[BuffManager]   Removing injected Pod: 524
[BuffManager] Meta stateChanged: id=520, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=520 injectedIds=521 count=1
[BuffManager]   Removing injected Pod: 521
[BuffManager] Meta stateChanged: id=517, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=517 injectedIds=518 count=1
[BuffManager]   Removing injected Pod: 518
[BuffManager] Meta stateChanged: id=514, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=514 injectedIds=515 count=1
[BuffManager]   Removing injected Pod: 515
[BuffManager] Meta stateChanged: id=511, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=511 injectedIds=512 count=1
[BuffManager]   Removing injected Pod: 512
[BuffManager] Meta stateChanged: id=508, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=508 injectedIds=509 count=1
[BuffManager]   Removing injected Pod: 509
[BuffManager] Meta stateChanged: id=505, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=505 injectedIds=506 count=1
[BuffManager]   Removing injected Pod: 506
[BuffManager] Meta stateChanged: id=502, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=502 injectedIds=503 count=1
[BuffManager]   Removing injected Pod: 503
[BuffManager] Meta stateChanged: id=499, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=499 injectedIds=500 count=1
[BuffManager]   Removing injected Pod: 500
[BuffManager] Meta stateChanged: id=496, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=496 injectedIds=497 count=1
[BuffManager]   Removing injected Pod: 497
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=526 pods=527 count=1
[BuffManager] Injected Meta=529 pods=530 count=1
[BuffManager] Injected Meta=532 pods=533 count=1
[BuffManager] Injected Meta=535 pods=536 count=1
[BuffManager] Injected Meta=538 pods=539 count=1
[BuffManager] Injected Meta=541 pods=542 count=1
[BuffManager] Injected Meta=544 pods=545 count=1
[BuffManager] Injected Meta=547 pods=548 count=1
[BuffManager] Injected Meta=550 pods=551 count=1
[BuffManager] Injected Meta=553 pods=554 count=1
[BuffManager] Meta stateChanged: id=523, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=523 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=520, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=520 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=517, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=517 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=514, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=514 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=511, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=511 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=508, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=508 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=505, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=505 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=502, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=502 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=499, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=499 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=496, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=496 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=553, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=553 injectedIds=554 count=1
[BuffManager]   Removing injected Pod: 554
[BuffManager] Meta stateChanged: id=550, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=550 injectedIds=551 count=1
[BuffManager]   Removing injected Pod: 551
[BuffManager] Meta stateChanged: id=547, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=547 injectedIds=548 count=1
[BuffManager]   Removing injected Pod: 548
[BuffManager] Meta stateChanged: id=544, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=544 injectedIds=545 count=1
[BuffManager]   Removing injected Pod: 545
[BuffManager] Meta stateChanged: id=541, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=541 injectedIds=542 count=1
[BuffManager]   Removing injected Pod: 542
[BuffManager] Meta stateChanged: id=538, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=538 injectedIds=539 count=1
[BuffManager]   Removing injected Pod: 539
[BuffManager] Meta stateChanged: id=535, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=535 injectedIds=536 count=1
[BuffManager]   Removing injected Pod: 536
[BuffManager] Meta stateChanged: id=532, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=532 injectedIds=533 count=1
[BuffManager]   Removing injected Pod: 533
[BuffManager] Meta stateChanged: id=529, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=529 injectedIds=530 count=1
[BuffManager]   Removing injected Pod: 530
[BuffManager] Meta stateChanged: id=526, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=526 injectedIds=527 count=1
[BuffManager]   Removing injected Pod: 527
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=556 pods=557 count=1
[BuffManager] Injected Meta=559 pods=560 count=1
[BuffManager] Injected Meta=562 pods=563 count=1
[BuffManager] Injected Meta=565 pods=566 count=1
[BuffManager] Injected Meta=568 pods=569 count=1
[BuffManager] Injected Meta=571 pods=572 count=1
[BuffManager] Injected Meta=574 pods=575 count=1
[BuffManager] Injected Meta=577 pods=578 count=1
[BuffManager] Injected Meta=580 pods=581 count=1
[BuffManager] Injected Meta=583 pods=584 count=1
[BuffManager] Meta stateChanged: id=553, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=553 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=550, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=550 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=547, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=547 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=544, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=544 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=541, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=541 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=538, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=538 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=535, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=535 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=532, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=532 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=529, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=529 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=526, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=526 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=583, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=583 injectedIds=584 count=1
[BuffManager]   Removing injected Pod: 584
[BuffManager] Meta stateChanged: id=580, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=580 injectedIds=581 count=1
[BuffManager]   Removing injected Pod: 581
[BuffManager] Meta stateChanged: id=577, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=577 injectedIds=578 count=1
[BuffManager]   Removing injected Pod: 578
[BuffManager] Meta stateChanged: id=574, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=574 injectedIds=575 count=1
[BuffManager]   Removing injected Pod: 575
[BuffManager] Meta stateChanged: id=571, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=571 injectedIds=572 count=1
[BuffManager]   Removing injected Pod: 572
[BuffManager] Meta stateChanged: id=568, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=568 injectedIds=569 count=1
[BuffManager]   Removing injected Pod: 569
[BuffManager] Meta stateChanged: id=565, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=565 injectedIds=566 count=1
[BuffManager]   Removing injected Pod: 566
[BuffManager] Meta stateChanged: id=562, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=562 injectedIds=563 count=1
[BuffManager]   Removing injected Pod: 563
[BuffManager] Meta stateChanged: id=559, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=559 injectedIds=560 count=1
[BuffManager]   Removing injected Pod: 560
[BuffManager] Meta stateChanged: id=556, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=556 injectedIds=557 count=1
[BuffManager]   Removing injected Pod: 557
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Injected Meta=586 pods=587 count=1
[BuffManager] Injected Meta=589 pods=590 count=1
[BuffManager] Injected Meta=592 pods=593 count=1
[BuffManager] Injected Meta=595 pods=596 count=1
[BuffManager] Injected Meta=598 pods=599 count=1
[BuffManager] Injected Meta=601 pods=602 count=1
[BuffManager] Injected Meta=604 pods=605 count=1
[BuffManager] Injected Meta=607 pods=608 count=1
[BuffManager] Injected Meta=610 pods=611 count=1
[BuffManager] Injected Meta=613 pods=614 count=1
[BuffManager] Meta stateChanged: id=583, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=583 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=580, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=580 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=577, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=577 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=574, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=574 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=571, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=571 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=568, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=568 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=565, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=565 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=562, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=562 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=559, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=559 injectedIds=null count=0
[BuffManager] Meta stateChanged: id=556, needsInject=false, needsEject=false, currentState=0
[BuffManager] Ejecting Meta=556 injectedIds=null count=0
[BuffManager] _redistributeDirtyProps for: consistency,
[BuffManager] Meta stateChanged: id=613, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=613 injectedIds=614 count=1
[BuffManager]   Removing injected Pod: 614
[BuffManager] Meta stateChanged: id=610, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=610 injectedIds=611 count=1
[BuffManager]   Removing injected Pod: 611
[BuffManager] Meta stateChanged: id=607, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=607 injectedIds=608 count=1
[BuffManager]   Removing injected Pod: 608
[BuffManager] Meta stateChanged: id=604, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=604 injectedIds=605 count=1
[BuffManager]   Removing injected Pod: 605
[BuffManager] Meta stateChanged: id=601, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=601 injectedIds=602 count=1
[BuffManager]   Removing injected Pod: 602
[BuffManager] Meta stateChanged: id=598, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=598 injectedIds=599 count=1
[BuffManager]   Removing injected Pod: 599
[BuffManager] Meta stateChanged: id=595, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=595 injectedIds=596 count=1
[BuffManager]   Removing injected Pod: 596
[BuffManager] Meta stateChanged: id=592, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=592 injectedIds=593 count=1
[BuffManager]   Removing injected Pod: 593
[BuffManager] Meta stateChanged: id=589, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=589 injectedIds=590 count=1
[BuffManager]   Removing injected Pod: 590
[BuffManager] Meta stateChanged: id=586, needsInject=false, needsEject=true, currentState=2
[BuffManager] Ejecting Meta=586 injectedIds=587 count=1
[BuffManager]   Removing injected Pod: 587
[BuffManager] _redistributeDirtyProps for: consistency,
  ✓ Consistency maintained across 10 rounds
[BuffManager] Ejecting Meta=613 injectedIds=null count=0
[BuffManager] Ejecting Meta=610 injectedIds=null count=0
[BuffManager] Ejecting Meta=607 injectedIds=null count=0
[BuffManager] Ejecting Meta=604 injectedIds=null count=0
[BuffManager] Ejecting Meta=601 injectedIds=null count=0
[BuffManager] Ejecting Meta=598 injectedIds=null count=0
[BuffManager] Ejecting Meta=595 injectedIds=null count=0
[BuffManager] Ejecting Meta=592 injectedIds=null count=0
[BuffManager] Ejecting Meta=589 injectedIds=null count=0
[BuffManager] Ejecting Meta=586 injectedIds=null count=0
  ✅ PASSED


--- Phase: Sticky Container & Lifecycle Contracts ---
🧪 Test 29: Sticky container: meta jitter won't delete property
[BuffManager] Injected Meta=616 pods=617 count=1
[BuffManager] _redistributeDirtyProps for: hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Ejecting Meta=616 injectedIds=617 count=1
[BuffManager]   Removing injected Pod: 617
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=619 pods=620 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=619 injectedIds=620 count=1
[BuffManager]   Removing injected Pod: 620
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=622 pods=623 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=622 injectedIds=623 count=1
[BuffManager]   Removing injected Pod: 623
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=625 pods=626 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=625 injectedIds=626 count=1
[BuffManager]   Removing injected Pod: 626
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=628 pods=629 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=628 injectedIds=629 count=1
[BuffManager]   Removing injected Pod: 629
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=631 pods=632 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=631 injectedIds=632 count=1
[BuffManager]   Removing injected Pod: 632
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=634 pods=635 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=634 injectedIds=635 count=1
[BuffManager]   Removing injected Pod: 635
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=637 pods=638 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=637 injectedIds=638 count=1
[BuffManager]   Removing injected Pod: 638
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=640 pods=641 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=640 injectedIds=641 count=1
[BuffManager]   Removing injected Pod: 641
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=643 pods=644 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=643 injectedIds=644 count=1
[BuffManager]   Removing injected Pod: 644
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=646 pods=647 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=646 injectedIds=647 count=1
[BuffManager]   Removing injected Pod: 647
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=649 pods=650 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=649 injectedIds=650 count=1
[BuffManager]   Removing injected Pod: 650
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=652 pods=653 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=652 injectedIds=653 count=1
[BuffManager]   Removing injected Pod: 653
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=655 pods=656 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=655 injectedIds=656 count=1
[BuffManager]   Removing injected Pod: 656
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=658 pods=659 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=658 injectedIds=659 count=1
[BuffManager]   Removing injected Pod: 659
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=661 pods=662 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=661 injectedIds=662 count=1
[BuffManager]   Removing injected Pod: 662
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=664 pods=665 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=664 injectedIds=665 count=1
[BuffManager]   Removing injected Pod: 665
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=667 pods=668 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=667 injectedIds=668 count=1
[BuffManager]   Removing injected Pod: 668
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=670 pods=671 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=670 injectedIds=671 count=1
[BuffManager]   Removing injected Pod: 671
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=673 pods=674 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=673 injectedIds=674 count=1
[BuffManager]   Removing injected Pod: 674
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=676 pods=677 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=676 injectedIds=677 count=1
[BuffManager]   Removing injected Pod: 677
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=679 pods=680 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=679 injectedIds=680 count=1
[BuffManager]   Removing injected Pod: 680
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=682 pods=683 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=682 injectedIds=683 count=1
[BuffManager]   Removing injected Pod: 683
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=685 pods=686 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=685 injectedIds=686 count=1
[BuffManager]   Removing injected Pod: 686
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=688 pods=689 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=688 injectedIds=689 count=1
[BuffManager]   Removing injected Pod: 689
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=691 pods=692 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=691 injectedIds=692 count=1
[BuffManager]   Removing injected Pod: 692
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=694 pods=695 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=694 injectedIds=695 count=1
[BuffManager]   Removing injected Pod: 695
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=697 pods=698 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=697 injectedIds=698 count=1
[BuffManager]   Removing injected Pod: 698
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=700 pods=701 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=700 injectedIds=701 count=1
[BuffManager]   Removing injected Pod: 701
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=703 pods=704 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=703 injectedIds=704 count=1
[BuffManager]   Removing injected Pod: 704
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=706 pods=707 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=706 injectedIds=707 count=1
[BuffManager]   Removing injected Pod: 707
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=709 pods=710 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=709 injectedIds=710 count=1
[BuffManager]   Removing injected Pod: 710
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=712 pods=713 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=712 injectedIds=713 count=1
[BuffManager]   Removing injected Pod: 713
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=715 pods=716 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=715 injectedIds=716 count=1
[BuffManager]   Removing injected Pod: 716
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=718 pods=719 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=718 injectedIds=719 count=1
[BuffManager]   Removing injected Pod: 719
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=721 pods=722 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=721 injectedIds=722 count=1
[BuffManager]   Removing injected Pod: 722
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=724 pods=725 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=724 injectedIds=725 count=1
[BuffManager]   Removing injected Pod: 725
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=727 pods=728 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=727 injectedIds=728 count=1
[BuffManager]   Removing injected Pod: 728
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=730 pods=731 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=730 injectedIds=731 count=1
[BuffManager]   Removing injected Pod: 731
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=733 pods=734 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=733 injectedIds=734 count=1
[BuffManager]   Removing injected Pod: 734
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=736 pods=737 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=736 injectedIds=737 count=1
[BuffManager]   Removing injected Pod: 737
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=739 pods=740 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=739 injectedIds=740 count=1
[BuffManager]   Removing injected Pod: 740
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=742 pods=743 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=742 injectedIds=743 count=1
[BuffManager]   Removing injected Pod: 743
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=745 pods=746 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=745 injectedIds=746 count=1
[BuffManager]   Removing injected Pod: 746
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=748 pods=749 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=748 injectedIds=749 count=1
[BuffManager]   Removing injected Pod: 749
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=751 pods=752 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=751 injectedIds=752 count=1
[BuffManager]   Removing injected Pod: 752
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=754 pods=755 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=754 injectedIds=755 count=1
[BuffManager]   Removing injected Pod: 755
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=757 pods=758 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=757 injectedIds=758 count=1
[BuffManager]   Removing injected Pod: 758
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=760 pods=761 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=760 injectedIds=761 count=1
[BuffManager]   Removing injected Pod: 761
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Injected Meta=763 pods=764 count=1
[BuffManager] _redistributeDirtyProps for: hp,
[BuffManager] Ejecting Meta=763 injectedIds=764 count=1
[BuffManager]   Removing injected Pod: 764
[BuffManager] _redistributeDirtyProps for: hp,
  ✅ PASSED

🧪 Test 30: unmanageProperty(finalize) then rebind uses plain value as base (independent Pods are cleaned)
[BuffManager] _redistributeDirtyProps for: atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: atk,
  ✅ PASSED

🧪 Test 31: destroy() finalizes all managed properties
[BuffManager] _redistributeDirtyProps for: def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✅ PASSED

🧪 Test 32: Base value: zero vs undefined
[BuffManager] _redistributeDirtyProps for: x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: y,
  ✅ PASSED

🧪 Test 33: Calculation order independent of add sequence
[BuffManager] _redistributeDirtyProps for: dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] _redistributeDirtyProps for: dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✅ PASSED

🧪 Test 34: clearAllBuffs keeps properties and resets to base
[BuffManager] _redistributeDirtyProps for: spd,dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✅ PASSED

🧪 Test 35: MetaBuff jitter stability (no undefined during flips)
[BuffManager] Injected Meta=777 pods=778 count=1
[BuffManager] _redistributeDirtyProps for: spd,dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
[BuffManager] Ejecting Meta=777 injectedIds=778 count=1
[BuffManager]   Removing injected Pod: 778
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=780 pods=781 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=780 injectedIds=781 count=1
[BuffManager]   Removing injected Pod: 781
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=783 pods=784 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=783 injectedIds=784 count=1
[BuffManager]   Removing injected Pod: 784
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=786 pods=787 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=786 injectedIds=787 count=1
[BuffManager]   Removing injected Pod: 787
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=789 pods=790 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=789 injectedIds=790 count=1
[BuffManager]   Removing injected Pod: 790
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=792 pods=793 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=792 injectedIds=793 count=1
[BuffManager]   Removing injected Pod: 793
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=795 pods=796 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=795 injectedIds=796 count=1
[BuffManager]   Removing injected Pod: 796
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=798 pods=799 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=798 injectedIds=799 count=1
[BuffManager]   Removing injected Pod: 799
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=801 pods=802 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=801 injectedIds=802 count=1
[BuffManager]   Removing injected Pod: 802
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=804 pods=805 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=804 injectedIds=805 count=1
[BuffManager]   Removing injected Pod: 805
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=807 pods=808 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=807 injectedIds=808 count=1
[BuffManager]   Removing injected Pod: 808
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=810 pods=811 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=810 injectedIds=811 count=1
[BuffManager]   Removing injected Pod: 811
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=813 pods=814 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=813 injectedIds=814 count=1
[BuffManager]   Removing injected Pod: 814
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=816 pods=817 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=816 injectedIds=817 count=1
[BuffManager]   Removing injected Pod: 817
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=819 pods=820 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=819 injectedIds=820 count=1
[BuffManager]   Removing injected Pod: 820
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=822 pods=823 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=822 injectedIds=823 count=1
[BuffManager]   Removing injected Pod: 823
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=825 pods=826 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=825 injectedIds=826 count=1
[BuffManager]   Removing injected Pod: 826
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=828 pods=829 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=828 injectedIds=829 count=1
[BuffManager]   Removing injected Pod: 829
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=831 pods=832 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=831 injectedIds=832 count=1
[BuffManager]   Removing injected Pod: 832
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=834 pods=835 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=834 injectedIds=835 count=1
[BuffManager]   Removing injected Pod: 835
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=837 pods=838 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=837 injectedIds=838 count=1
[BuffManager]   Removing injected Pod: 838
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=840 pods=841 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=840 injectedIds=841 count=1
[BuffManager]   Removing injected Pod: 841
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=843 pods=844 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=843 injectedIds=844 count=1
[BuffManager]   Removing injected Pod: 844
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=846 pods=847 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=846 injectedIds=847 count=1
[BuffManager]   Removing injected Pod: 847
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=849 pods=850 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=849 injectedIds=850 count=1
[BuffManager]   Removing injected Pod: 850
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=852 pods=853 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=852 injectedIds=853 count=1
[BuffManager]   Removing injected Pod: 853
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=855 pods=856 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=855 injectedIds=856 count=1
[BuffManager]   Removing injected Pod: 856
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=858 pods=859 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=858 injectedIds=859 count=1
[BuffManager]   Removing injected Pod: 859
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=861 pods=862 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=861 injectedIds=862 count=1
[BuffManager]   Removing injected Pod: 862
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=864 pods=865 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=864 injectedIds=865 count=1
[BuffManager]   Removing injected Pod: 865
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=867 pods=868 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=867 injectedIds=868 count=1
[BuffManager]   Removing injected Pod: 868
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=870 pods=871 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=870 injectedIds=871 count=1
[BuffManager]   Removing injected Pod: 871
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=873 pods=874 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=873 injectedIds=874 count=1
[BuffManager]   Removing injected Pod: 874
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=876 pods=877 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=876 injectedIds=877 count=1
[BuffManager]   Removing injected Pod: 877
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=879 pods=880 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=879 injectedIds=880 count=1
[BuffManager]   Removing injected Pod: 880
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=882 pods=883 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=882 injectedIds=883 count=1
[BuffManager]   Removing injected Pod: 883
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=885 pods=886 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=885 injectedIds=886 count=1
[BuffManager]   Removing injected Pod: 886
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=888 pods=889 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=888 injectedIds=889 count=1
[BuffManager]   Removing injected Pod: 889
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=891 pods=892 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=891 injectedIds=892 count=1
[BuffManager]   Removing injected Pod: 892
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=894 pods=895 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=894 injectedIds=895 count=1
[BuffManager]   Removing injected Pod: 895
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=897 pods=898 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=897 injectedIds=898 count=1
[BuffManager]   Removing injected Pod: 898
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=900 pods=901 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=900 injectedIds=901 count=1
[BuffManager]   Removing injected Pod: 901
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=903 pods=904 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=903 injectedIds=904 count=1
[BuffManager]   Removing injected Pod: 904
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=906 pods=907 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=906 injectedIds=907 count=1
[BuffManager]   Removing injected Pod: 907
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=909 pods=910 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=909 injectedIds=910 count=1
[BuffManager]   Removing injected Pod: 910
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=912 pods=913 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=912 injectedIds=913 count=1
[BuffManager]   Removing injected Pod: 913
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=915 pods=916 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=915 injectedIds=916 count=1
[BuffManager]   Removing injected Pod: 916
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=918 pods=919 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=918 injectedIds=919 count=1
[BuffManager]   Removing injected Pod: 919
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=921 pods=922 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=921 injectedIds=922 count=1
[BuffManager]   Removing injected Pod: 922
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=924 pods=925 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=924 injectedIds=925 count=1
[BuffManager]   Removing injected Pod: 925
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=927 pods=928 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=927 injectedIds=928 count=1
[BuffManager]   Removing injected Pod: 928
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=930 pods=931 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=930 injectedIds=931 count=1
[BuffManager]   Removing injected Pod: 931
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=933 pods=934 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=933 injectedIds=934 count=1
[BuffManager]   Removing injected Pod: 934
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=936 pods=937 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=936 injectedIds=937 count=1
[BuffManager]   Removing injected Pod: 937
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=939 pods=940 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=939 injectedIds=940 count=1
[BuffManager]   Removing injected Pod: 940
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=942 pods=943 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=942 injectedIds=943 count=1
[BuffManager]   Removing injected Pod: 943
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=945 pods=946 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=945 injectedIds=946 count=1
[BuffManager]   Removing injected Pod: 946
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=948 pods=949 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=948 injectedIds=949 count=1
[BuffManager]   Removing injected Pod: 949
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=951 pods=952 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=951 injectedIds=952 count=1
[BuffManager]   Removing injected Pod: 952
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=954 pods=955 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=954 injectedIds=955 count=1
[BuffManager]   Removing injected Pod: 955
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=957 pods=958 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=957 injectedIds=958 count=1
[BuffManager]   Removing injected Pod: 958
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=960 pods=961 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=960 injectedIds=961 count=1
[BuffManager]   Removing injected Pod: 961
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=963 pods=964 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=963 injectedIds=964 count=1
[BuffManager]   Removing injected Pod: 964
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=966 pods=967 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=966 injectedIds=967 count=1
[BuffManager]   Removing injected Pod: 967
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=969 pods=970 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=969 injectedIds=970 count=1
[BuffManager]   Removing injected Pod: 970
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=972 pods=973 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=972 injectedIds=973 count=1
[BuffManager]   Removing injected Pod: 973
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=975 pods=976 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=975 injectedIds=976 count=1
[BuffManager]   Removing injected Pod: 976
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=978 pods=979 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=978 injectedIds=979 count=1
[BuffManager]   Removing injected Pod: 979
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=981 pods=982 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=981 injectedIds=982 count=1
[BuffManager]   Removing injected Pod: 982
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=984 pods=985 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=984 injectedIds=985 count=1
[BuffManager]   Removing injected Pod: 985
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=987 pods=988 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=987 injectedIds=988 count=1
[BuffManager]   Removing injected Pod: 988
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=990 pods=991 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=990 injectedIds=991 count=1
[BuffManager]   Removing injected Pod: 991
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=993 pods=994 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=993 injectedIds=994 count=1
[BuffManager]   Removing injected Pod: 994
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=996 pods=997 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=996 injectedIds=997 count=1
[BuffManager]   Removing injected Pod: 997
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=999 pods=1000 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=999 injectedIds=1000 count=1
[BuffManager]   Removing injected Pod: 1000
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1002 pods=1003 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1002 injectedIds=1003 count=1
[BuffManager]   Removing injected Pod: 1003
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1005 pods=1006 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1005 injectedIds=1006 count=1
[BuffManager]   Removing injected Pod: 1006
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1008 pods=1009 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1008 injectedIds=1009 count=1
[BuffManager]   Removing injected Pod: 1009
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1011 pods=1012 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1011 injectedIds=1012 count=1
[BuffManager]   Removing injected Pod: 1012
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1014 pods=1015 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1014 injectedIds=1015 count=1
[BuffManager]   Removing injected Pod: 1015
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1017 pods=1018 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1017 injectedIds=1018 count=1
[BuffManager]   Removing injected Pod: 1018
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1020 pods=1021 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1020 injectedIds=1021 count=1
[BuffManager]   Removing injected Pod: 1021
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1023 pods=1024 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1023 injectedIds=1024 count=1
[BuffManager]   Removing injected Pod: 1024
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1026 pods=1027 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1026 injectedIds=1027 count=1
[BuffManager]   Removing injected Pod: 1027
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1029 pods=1030 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1029 injectedIds=1030 count=1
[BuffManager]   Removing injected Pod: 1030
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1032 pods=1033 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1032 injectedIds=1033 count=1
[BuffManager]   Removing injected Pod: 1033
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1035 pods=1036 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1035 injectedIds=1036 count=1
[BuffManager]   Removing injected Pod: 1036
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1038 pods=1039 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1038 injectedIds=1039 count=1
[BuffManager]   Removing injected Pod: 1039
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1041 pods=1042 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1041 injectedIds=1042 count=1
[BuffManager]   Removing injected Pod: 1042
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1044 pods=1045 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1044 injectedIds=1045 count=1
[BuffManager]   Removing injected Pod: 1045
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1047 pods=1048 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1047 injectedIds=1048 count=1
[BuffManager]   Removing injected Pod: 1048
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1050 pods=1051 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1050 injectedIds=1051 count=1
[BuffManager]   Removing injected Pod: 1051
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1053 pods=1054 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1053 injectedIds=1054 count=1
[BuffManager]   Removing injected Pod: 1054
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1056 pods=1057 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1056 injectedIds=1057 count=1
[BuffManager]   Removing injected Pod: 1057
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1059 pods=1060 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1059 injectedIds=1060 count=1
[BuffManager]   Removing injected Pod: 1060
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1062 pods=1063 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1062 injectedIds=1063 count=1
[BuffManager]   Removing injected Pod: 1063
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1065 pods=1066 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1065 injectedIds=1066 count=1
[BuffManager]   Removing injected Pod: 1066
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1068 pods=1069 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1068 injectedIds=1069 count=1
[BuffManager]   Removing injected Pod: 1069
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1071 pods=1072 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1071 injectedIds=1072 count=1
[BuffManager]   Removing injected Pod: 1072
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Injected Meta=1074 pods=1075 count=1
[BuffManager] _redistributeDirtyProps for: energy,
[BuffManager] Ejecting Meta=1074 injectedIds=1075 count=1
[BuffManager]   Removing injected Pod: 1075
[BuffManager] _redistributeDirtyProps for: energy,
  ✅ PASSED

--- Phase 8: Regression & Lifecycle Contracts ---
🧪 Test 36: Same-ID replacement keeps only the new instance
[BuffManager] _redistributeDirtyProps for: undefined,spd,dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✅ PASSED

🧪 Test 37: Injected Pods fire onBuffAdded for each injected pod
[BuffManager] Injected Meta=M pods=P1,P2 count=2
[BuffManager] Meta stateChanged: id=M, needsInject=true, needsEject=undefined, currentState=N/A
[BuffManager] Injected Meta=M pods=P1,P2 count=2
[BuffManager] _redistributeDirtyProps for: undefined,spd,dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✅ PASSED

🧪 Test 38: Remove injected pod shrinks injected map by 1
[BuffManager] Injected Meta=M pods=P1,P2 count=2
[BuffManager] Meta stateChanged: id=M, needsInject=true, needsEject=undefined, currentState=N/A
[BuffManager] Injected Meta=M pods=P1,P2 count=2
[BuffManager] _redistributeDirtyProps for: undefined,spd,dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✅ PASSED

🧪 Test 39: clearAllBuffs emits onBuffRemoved for independent pods
[BuffManager] _redistributeDirtyProps for: undefined,spd,dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✅ PASSED

🧪 Test 40: removeBuff de-dup removes only once
[BuffManager] _redistributeDirtyProps for: undefined,spd,dmg,x,def,atk,hp,consistency,stat5,stat4,stat3,stat2,stat1,largeStat,zeroTest,balance,floatTest,extreme,concurrent,prop3,prop2,prop1,dynamicStat,testStat,criticalDamage,criticalChance,attackSpeed,attackDamage,healingPower,magicalDamage,physicalDamage,energy,resistance,mana,armor,intelligence,agility,critical,damage,strength,health,power,speed,defense,attack,
  ✅ PASSED


=== Calculation Accuracy Test Results ===
📊 Total tests: 40
✅ Passed: 40
❌ Failed: 0
📈 Success rate: 100%
🎉 All calculation tests passed! BuffManager calculations are accurate.
==============================================

=== Calculation Performance Results ===
📊 Large Scale Accuracy:
   buffCount: 100
   calculationTime: 6ms
   expectedValue: 6050
   actualValue: 6050
   accurate: true

📊 Calculation Performance:
   totalBuffs: 100
   properties: 5
   updates: 100
   totalTime: 58ms
   avgUpdateTime: 0.58ms per update

=======================================
