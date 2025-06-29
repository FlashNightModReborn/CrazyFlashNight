org.flashNight.neur.Event.LifecycleEventDispatcherTest.runAllTests();




=== Running LifecycleEventDispatcher Tests ===

-- testBasicLifecycle --
[ASSERTION PASSED]: Dispatcher should not be destroyed initially
[ASSERTION PASSED]: Target should be correctly set
[ASSERTION PASSED]: Bidirectional reference should be established
[ASSERTION PASSED]: EventDispatcher functionality should work
[LifecycleEventDispatcher] Destroying instance for target: _level0.testLifecycleMC
监听器已移除：HID1
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
[ASSERTION PASSED]: Dispatcher should be destroyed after destroy() call
[ASSERTION PASSED]: Target reference should be cleared
-- testBasicLifecycle Completed --


-- testEventBridging --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: subscribeTargetEvent should return valid ID
[ASSERTION PASSED]: subscribeTargetEvent should return valid ID
[ASSERTION PASSED]: Target events should be triggered
目标对象的所有自定义事件监听器已 禁用。
[ASSERTION PASSED]: Events should be disabled
目标对象的所有自定义事件监听器已 启用。
[ASSERTION PASSED]: Events should be re-enabled
监听器已移除：HID4
所有监听器已移除：onPress，已恢复原生处理器。
[ASSERTION PASSED]: Unsubscribed event should not trigger
[ASSERTION PASSED]: Should show 2 remaining events (onRelease, onUnload)
[ASSERTION PASSED]: Should show 2 remaining handlers
[ASSERTION PASSED]: onRelease event should have exactly 1 handler
[LifecycleEventDispatcher] Destroying instance for target: _level0.testBridgeMC
监听器已移除：HID3
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
-- testEventBridging Completed --


-- testDestroyAndCleanup --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Events should work before destroy
[LifecycleEventDispatcher] Destroying instance for target: _level0.testDestroyMC
监听器已移除：HID7
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
onUnload 已执行并清理所有事件监听器。
[ASSERTION PASSED]: Dispatcher should be auto-destroyed on target unload
Warning: publish called on a destroyed EventDispatcher.
[ASSERTION PASSED]: Events should not work after destroy
[ASSERTION PASSED]: Multiple destroy calls should be safe
-- testDestroyAndCleanup Completed --


-- testBasicTransfer --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Old target should work before transfer
[LifecycleEventDispatcher] Starting transfer from _level0.oldTransferMC to _level0.newTransferMC
监听器已移除：HID10
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Transfer should return ID mapping
[ASSERTION PASSED]: Target should be updated after transfer
[ASSERTION PASSED]: New target should have correct dispatcher reference
[ASSERTION PASSED]: Old target reference should be cleared
[ASSERTION PASSED]: New target should work after transfer
[ASSERTION PASSED]: Old target should be cleaned after transfer
[LifecycleEventDispatcher] Destroying instance for target: _level0.newTransferMC
监听器已移除：HID16
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
onUnload 已执行并清理所有事件监听器。
onUnload 已执行并清理所有事件监听器。
[ASSERTION PASSED]: Lifecycle should be transferred to new target
-- testBasicTransfer Completed --


-- testTransferModes --
自动清理及用户卸载逻辑已设置。
[LifecycleEventDispatcher] Starting transfer from _level0.oldModeMC to _level0.newModeMC
监听器已移除：HID18
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Specific events should be transferred
[ASSERTION PASSED]: Non-specific events should not be transferred
[ASSERTION PASSED]: Non-transferred events should remain on old target
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Starting transfer from _level0.oldModeMC to _level0.newMode2MC
监听器已移除：HID27
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Non-excluded events should be transferred
[ASSERTION PASSED]: Excluded events should not be transferred
[LifecycleEventDispatcher] Destroying instance for target: _level0.newModeMC
监听器已移除：HID26
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
[LifecycleEventDispatcher] Destroying instance for target: _level0.newMode2MC
监听器已移除：HID35
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
-- testTransferModes Completed --


-- testTransferWithEventStates --
自动清理及用户卸载逻辑已设置。
目标对象的所有自定义事件监听器已 禁用。
[LifecycleEventDispatcher] Starting transfer from _level0.oldStateMC to _level0.newStateMC
监听器已移除：HID37
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Disabled state should be transferred to new target
目标对象的所有自定义事件监听器已 启用。
[ASSERTION PASSED]: Events should work after enabling on new target
[LifecycleEventDispatcher] Destroying instance for target: _level0.newStateMC
监听器已移除：HID41
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
-- testTransferWithEventStates Completed --


-- testStaticTransferMethods --
自动清理及用户卸载逻辑已设置。
自动清理及用户卸载逻辑已设置。
用户的 onUnload 函数已更新。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 2 个监听器
[ASSERTION PASSED]: Static transfer should return ID mapping
[ASSERTION PASSED]: Static transfer should work correctly
[ASSERTION PASSED]: Source should be cleared after static transfer
[LifecycleEventDispatcher] Error: Source and target dispatchers cannot be null
[ASSERTION PASSED]: Static transfer with null source should return null
[LifecycleEventDispatcher] Destroying instance for target: _level0.staticMC1
[LifecycleEventDispatcher] Destroyed successfully.
[LifecycleEventDispatcher] Destroying instance for target: _level0.staticMC2
监听器已移除：HID45
用户的 onUnload 函数已更新。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
-- testStaticTransferMethods Completed --


-- testTransferEdgeCases --
[LifecycleEventDispatcher] Warning: New target is same as current target
[ASSERTION PASSED]: Transfer to same target should be handled gracefully
[ASSERTION PASSED]: Target should remain unchanged
[LifecycleEventDispatcher] Error: New target cannot be null
[ASSERTION PASSED]: Transfer to null target should return null
[LifecycleEventDispatcher] Destroying instance for target: _level0.edgeMC1
监听器已移除：HID50
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
[LifecycleEventDispatcher] Error: Cannot transfer destroyed instance
[ASSERTION PASSED]: Transfer on destroyed dispatcher should return null
[ASSERTION PASSED]: Destroyed dispatcher should return empty stats
[LifecycleEventDispatcher] Warning: Cannot subscribe on destroyed or null target
[ASSERTION PASSED]: Subscribe on destroyed dispatcher should return null
-- testTransferEdgeCases Completed --


-- testBossPhaseTransfer --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Phase1 systems should work normally
[Boss] Phase1 → Phase2 transformation...
[LifecycleEventDispatcher] Starting transfer from _level0.bossPhase1 to _level0.bossPhase2
监听器已移除：HID52
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 4 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Phase1 to Phase2 transfer should succeed
[ASSERTION PASSED]: Phase2 should work, Phase1 should be cleaned
[Boss] Phase2 → Phase3 transformation...
[LifecycleEventDispatcher] Starting transfer from _level0.bossPhase2 to _level0.bossPhase3
监听器已移除：HID62
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 3 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Phase3 critical systems should work
[ASSERTION PASSED]: Sound system should not be transferred in Phase3
[Boss] Boss defeated, cleaning up...
[LifecycleEventDispatcher] Destroying instance for target: _level0.bossPhase3
监听器已移除：HID67
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
[ASSERTION PASSED]: Boss dispatcher should be destroyed
-- testBossPhaseTransfer Completed --


-- testComplexTransferChain --
自动清理及用户卸载逻辑已设置。
[Chain] Transferring from target 0 to target 1
[LifecycleEventDispatcher] Starting transfer from _level0.chainMC0 to _level0.chainMC1
监听器已移除：HID69
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Chain transfer 0→1 should succeed
[ASSERTION PASSED]: Target 1 should work after transfer
[Chain] Transferring from target 1 to target 2
[LifecycleEventDispatcher] Starting transfer from _level0.chainMC1 to _level0.chainMC2
监听器已移除：HID73
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Chain transfer 1→2 should succeed
[ASSERTION PASSED]: Target 2 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[Chain] Transferring from target 2 to target 3
[LifecycleEventDispatcher] Starting transfer from _level0.chainMC2 to _level0.chainMC3
监听器已移除：HID76
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Chain transfer 2→3 should succeed
[ASSERTION PASSED]: Target 3 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[Chain] Transferring from target 3 to target 4
[LifecycleEventDispatcher] Starting transfer from _level0.chainMC3 to _level0.chainMC4
监听器已移除：HID79
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[ASSERTION PASSED]: Chain transfer 3→4 should succeed
[ASSERTION PASSED]: Target 4 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[ASSERTION PASSED]: Final target should be targets[4]
[ASSERTION PASSED]: Final bidirectional reference should be correct
[LifecycleEventDispatcher] Destroying instance for target: _level0.chainMC4
监听器已移除：HID82
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
-- testComplexTransferChain Completed --


-- testTransferPerformance --
自动清理及用户卸载逻辑已设置。
[Transfer Performance] Registered 500 handlers in 14 ms
[LifecycleEventDispatcher] Starting transfer from _level0.perfOldMC to _level0.perfNewMC
监听器已移除：HID84
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 500 个监听器
用户的 onUnload 函数已更新。
[LifecycleEventDispatcher] Transfer completed successfully
[Transfer Performance] Transferred 500 handlers in 4 ms
[ASSERTION PASSED]: All transferred handlers should work
[LifecycleEventDispatcher] Destroying instance for target: _level0.perfNewMC
监听器已移除：HID1086
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
[LifecycleEventDispatcher] Destroyed successfully.
[Transfer Performance] Destroyed dispatcher in 0 ms
-- testTransferPerformance Completed --


=== LifecycleEventDispatcher Tests Completed ===
Total Assertions: 64
Passed Assertions: 64
Failed Assertions: 0

