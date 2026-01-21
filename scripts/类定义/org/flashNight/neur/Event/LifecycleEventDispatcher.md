org.flashNight.neur.Event.LifecycleEventDispatcherTest.runAllTests();




=== Running LifecycleEventDispatcher Tests ===

-- testBasicLifecycle --
[ASSERTION PASSED]: Dispatcher should not be destroyed initially
[ASSERTION PASSED]: Target should be correctly set
[ASSERTION PASSED]: Bidirectional reference should be established
[ASSERTION PASSED]: EventDispatcher functionality should work
监听器已移除：HID1
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
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
监听器已移除：HID3
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID5
所有监听器已移除：onRelease，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
-- testEventBridging Completed --


-- testDestroyAndCleanup --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Events should work before destroy
监听器已移除：HID7
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID8
所有监听器已移除：onPress，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
onUnload 已执行并清理所有事件监听器。
[ASSERTION PASSED]: Dispatcher should be auto-destroyed on target unload
Warning: publish called on a destroyed EventDispatcher.
[ASSERTION PASSED]: Events should not work after destroy
[ASSERTION PASSED]: Multiple destroy calls should be safe
-- testDestroyAndCleanup Completed --


-- testBasicTransfer --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Old target should work before transfer
监听器已移除：HID10
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Transfer should return ID mapping
[ASSERTION PASSED]: Target should be updated after transfer
[ASSERTION PASSED]: New target should have correct dispatcher reference
[ASSERTION PASSED]: Old target reference should be cleared
[ASSERTION PASSED]: New target should work after transfer
[ASSERTION PASSED]: Old target should be cleaned after transfer
监听器已移除：HID16
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
所有事件监听器已清除。
onUnload 已执行并清理所有事件监听器。
onUnload 已执行并清理所有事件监听器。
[ASSERTION PASSED]: Lifecycle should be transferred to new target
-- testBasicTransfer Completed --


-- testTransferModes --
自动清理及用户卸载逻辑已设置。
监听器已移除：HID18
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Specific events should be transferred
[ASSERTION PASSED]: Non-specific events should not be transferred
[ASSERTION PASSED]: Non-transferred events should remain on old target
用户的 onUnload 函数已更新。
监听器已移除：HID27
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Non-excluded events should be transferred
[ASSERTION PASSED]: Excluded events should not be transferred
监听器已移除：HID26
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID35
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
-- testTransferModes Completed --


-- testTransferWithEventStates --
自动清理及用户卸载逻辑已设置。
目标对象的所有自定义事件监听器已 禁用。
监听器已移除：HID37
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Disabled state should be transferred to new target
目标对象的所有自定义事件监听器已 启用。
[ASSERTION PASSED]: Events should work after enabling on new target
监听器已移除：HID41
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
-- testTransferWithEventStates Completed --


-- testStaticTransferMethods --
自动清理及用户卸载逻辑已设置。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 2 个监听器
[ASSERTION PASSED]: Static transfer should return ID mapping
[ASSERTION PASSED]: Static transfer should work correctly
[ASSERTION PASSED]: Source should be cleared after static transfer
[ASSERTION PASSED]: Static transfer with null source should return null
监听器已移除：HID45
-- testStaticTransferMethods Completed --


-- testTransferEdgeCases --
[ASSERTION PASSED]: Transfer to same target should be handled gracefully
[ASSERTION PASSED]: Target should remain unchanged
[ASSERTION PASSED]: Transfer to null target should return null
监听器已移除：HID50
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: Transfer on destroyed dispatcher should return null
[ASSERTION PASSED]: Destroyed dispatcher should return empty stats
[ASSERTION PASSED]: Subscribe on destroyed dispatcher should return null
-- testTransferEdgeCases Completed --


-- testBossPhaseTransfer --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Phase1 systems should work normally
[Boss] Phase1 → Phase2 transformation...
监听器已移除：HID52
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 4 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Phase1 to Phase2 transfer should succeed
[ASSERTION PASSED]: Phase2 should work, Phase1 should be cleaned
[Boss] Phase2 → Phase3 transformation...
监听器已移除：HID62
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 3 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Phase3 critical systems should work
[ASSERTION PASSED]: Sound system should not be transferred in Phase3
[Boss] Boss defeated, cleaning up...
监听器已移除：HID67
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
[ASSERTION PASSED]: Boss dispatcher should be destroyed
-- testBossPhaseTransfer Completed --


-- testComplexTransferChain --
自动清理及用户卸载逻辑已设置。
[Chain] Transferring from target 0 to target 1
监听器已移除：HID69
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Chain transfer 0→1 should succeed
[ASSERTION PASSED]: Target 1 should work after transfer
[Chain] Transferring from target 1 to target 2
监听器已移除：HID73
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Chain transfer 1→2 should succeed
[ASSERTION PASSED]: Target 2 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[Chain] Transferring from target 2 to target 3
监听器已移除：HID76
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Chain transfer 2→3 should succeed
[ASSERTION PASSED]: Target 3 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[Chain] Transferring from target 3 to target 4
监听器已移除：HID79
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Chain transfer 3→4 should succeed
[ASSERTION PASSED]: Target 4 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[ASSERTION PASSED]: Final target should be targets[4]
[ASSERTION PASSED]: Final bidirectional reference should be correct
监听器已移除：HID82
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
-- testComplexTransferChain Completed --


-- testTransferPerformance --
自动清理及用户卸载逻辑已设置。
[Transfer Performance] Registered 500 handlers in 22 ms
监听器已移除：HID84
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 500 个监听器
用户的 onUnload 函数已更新。
[Transfer Performance] Transferred 500 handlers in 5 ms
[ASSERTION PASSED]: All transferred handlers should work
监听器已移除：HID1086
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
[Transfer Performance] Destroyed dispatcher in 78 ms
-- testTransferPerformance Completed --


-- [v2.3 I3] testHandlerTracking --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.3 I3] subscribeTargetEvent should return valid ID for onPress
[ASSERTION PASSED]: [v2.3 I3] subscribeTargetEvent should return valid ID for onRelease
[ASSERTION PASSED]: [v2.3 I3] External EventCoordinator.addEventListener should return valid ID
[ASSERTION PASSED]: [v2.3 I3] Dispatcher handlers should be called (count=2)
[ASSERTION PASSED]: [v2.3 I3] External handler should be called (count=1)
监听器已移除：HID1088
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID1089
所有监听器已移除：onPress，已恢复原生处理器。
监听器已移除：HID1090
所有监听器已移除：onRelease，已恢复原生处理器。
[ASSERTION PASSED]: [v2.3 I3] Dispatcher handlers should be cleared after destroy
[ASSERTION PASSED]: [v2.3 I3] CRITICAL - External handler should still work after dispatcher.destroy()
监听器已移除：HID1091
所有监听器已移除：onRollOver，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: [v2.3 I3] External handler should be removed after manual cleanup
-- [v2.3 I3] testHandlerTracking Completed --


=== LifecycleEventDispatcher Tests Completed ===
Total Assertions: 72
Passed Assertions: 72
Failed Assertions: 0

