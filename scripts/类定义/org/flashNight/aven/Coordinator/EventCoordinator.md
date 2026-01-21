# org.flashNight.aven.Coordinator.EventCoordinator

## 版本历史

### v2.2 (2026-01) - 代码审查修复
- **[CRITICAL]** `clearEventListeners` 调用 `unwatch("onUnload")` 释放 watch 拦截器，防止内存泄漏
- **[FIX]** `clearEventListeners` 正确恢复用户原始 `onUnload` 函数
  - 之前：删除语句目标对象错误，导致用户 `onUnload` 无法正确恢复
  - 现在：正确设置 `target.onUnload = userUnload`
- **[CONTRACT]** watch/unwatch 生命周期完全闭合，支持重复 addEventListener → clearEventListeners 循环

---

## 测试输出

```actionscript
org.flashNight.aven.Coordinator.EventCoordinatorTest.runAllTests();
```



=== Running EventCoordinator Tests ===

-- testCoreFunctions --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: addEventListener should return a non-null handler ID
[ASSERTION PASSED]: Handler1 should have been called exactly once
[ASSERTION PASSED]: addEventListener should return a non-null handler ID for handler2
[ASSERTION PASSED]: After second handler added, total calls should be callCount=2, callCount2=1
监听器已移除：HID1
[ASSERTION PASSED]: After removing handler1, only handler2 should be called. So callCount=2, callCount2=2.
所有事件监听器已清除。
[ASSERTION PASSED]: After clearEventListeners, no callbacks should be invoked
自动清理及用户卸载逻辑已设置。
目标对象的所有自定义事件监听器已 禁用。
[ASSERTION PASSED]: After enableEventListeners(false), no callbacks should be triggered
目标对象的所有自定义事件监听器已 启用。
[ASSERTION PASSED]: After enableEventListeners(true), both callbacks should be triggered again
-- testCoreFunctions Completed --


-- testEdgeCases --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Adding the same handler twice should return different IDs
[ASSERTION PASSED]: Handler should have been called twice for two bindings
监听器已移除：HID6
[ASSERTION PASSED]: After removing one handler, only one should be called
监听器已移除：HID7
所有监听器已移除：onMouseMove，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: After removing both handlers, none should be called
[INFO] Removing non-existent handler should not affect existing handlers.
[ASSERTION PASSED]: Removing a non-existent handler should not throw errors
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: DynamicHandler1 should have been called once
[ASSERTION PASSED]: After dynamic addition, both handlers should be called
所有事件监听器已清除。
-- testEdgeCases Completed --


-- testOriginalHandlers --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Original handler should have been called once
[ASSERTION PASSED]: Custom handler should have been called once
目标对象的所有自定义事件监听器已 禁用。
[ASSERTION PASSED]: Original handler should have been called twice
[ASSERTION PASSED]: Custom handler should not have been called when disabled
目标对象的所有自定义事件监听器已 启用。
[ASSERTION PASSED]: Original handler should have been called three times
[ASSERTION PASSED]: Custom handler should have been called twice
所有事件监听器已清除。
-- testOriginalHandlers Completed --


-- testMultipleTargets --
自动清理及用户卸载逻辑已设置。
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Target1's handler should have been called once
[ASSERTION PASSED]: Target2's handler should not have been called
[ASSERTION PASSED]: Target1's handler should remain at one call
[ASSERTION PASSED]: Target2's handler should have been called once
所有事件监听器已清除。
[ASSERTION PASSED]: After clearing, Target1's handler should not be called again
[ASSERTION PASSED]: Target2's handler should have been called twice
所有事件监听器已清除。
[ASSERTION PASSED]: After clearing, Target2's handler should not be called again
-- testMultipleTargets Completed --


-- testUnloadHandling --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Handler should have been called once before unload
所有事件监听器已清除。
onUnload 已执行并清理所有事件监听器。
[ASSERTION PASSED]: Handler should not be called after unload
[ASSERTION PASSED]: User's onUnload should have been called once
[ASSERTION PASSED]: User's onUnload should have been called twice
-- testUnloadHandling Completed --


-- testClosureCapture --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: When calling onPress, counters[onPress] should be 1, got 1
[ASSERTION PASSED]: When calling onPress, counters[onRelease] should be 0, got 0
[ASSERTION PASSED]: When calling onPress, counters[onMouseUp] should be 0, got 0
[ASSERTION PASSED]: When calling onPress, counters[onMouseDown] should be 0, got 0
[ASSERTION PASSED]: When calling onRelease, counters[onPress] should be 0, got 0
[ASSERTION PASSED]: When calling onRelease, counters[onRelease] should be 1, got 1
[ASSERTION PASSED]: When calling onRelease, counters[onMouseUp] should be 0, got 0
[ASSERTION PASSED]: When calling onRelease, counters[onMouseDown] should be 0, got 0
[ASSERTION PASSED]: When calling onMouseUp, counters[onPress] should be 0, got 0
[ASSERTION PASSED]: When calling onMouseUp, counters[onRelease] should be 0, got 0
[ASSERTION PASSED]: When calling onMouseUp, counters[onMouseUp] should be 1, got 1
[ASSERTION PASSED]: When calling onMouseUp, counters[onMouseDown] should be 0, got 0
[ASSERTION PASSED]: When calling onMouseDown, counters[onPress] should be 0, got 0
[ASSERTION PASSED]: When calling onMouseDown, counters[onRelease] should be 0, got 0
[ASSERTION PASSED]: When calling onMouseDown, counters[onMouseUp] should be 0, got 0
[ASSERTION PASSED]: When calling onMouseDown, counters[onMouseDown] should be 1, got 1
所有事件监听器已清除。
-- testClosureCapture Completed --


-- testBasicTransfer --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Old target handlers should work before transfer
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 3 个监听器
[ASSERTION PASSED]: transferEventListeners should return an ID mapping object
[ASSERTION PASSED]: New target handlers should work after transfer
[ASSERTION PASSED]: Old target handlers should be cleared after transfer with clearOld=true
所有事件监听器已清除。
-- testBasicTransfer Completed --


-- testSpecificTransfer --
自动清理及用户卸载逻辑已设置。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 2 个监听器
[ASSERTION PASSED]: transferSpecificEventListeners should return an ID mapping object
[ASSERTION PASSED]: Transferred events should work on new target
[ASSERTION PASSED]: Non-transferred events should still work on old target
[ASSERTION PASSED]: Transferred events should be cleared from old target when clearOld=true
所有事件监听器已清除。
所有事件监听器已清除。
-- testSpecificTransfer Completed --


-- testTransferWithStates --
自动清理及用户卸载逻辑已设置。
目标对象的所有自定义事件监听器已 禁用。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
[ASSERTION PASSED]: Custom handlers should be disabled on new target (state sync)
[ASSERTION PASSED]: Original handler should work on new target
目标对象的所有自定义事件监听器已 启用。
[ASSERTION PASSED]: Custom handlers should work after enabling on new target
[ASSERTION PASSED]: Original handler should continue working
所有事件监听器已清除。
-- testTransferWithStates Completed --


-- testTransferIDMapping --
自动清理及用户卸载逻辑已设置。
自动清理及用户卸载逻辑已设置。
transferEventListeners 完成：已转移 2 个监听器
[ASSERTION PASSED]: Old ID1 should be mapped to a new ID
[ASSERTION PASSED]: Old ID2 should be mapped to a new ID
[ASSERTION PASSED]: Different old IDs should map to different new IDs
监听器已移除：HID48
[ASSERTION PASSED]: After removing first handler via new ID, only second should be called
所有事件监听器已清除。
所有事件监听器已清除。
-- testTransferIDMapping Completed --


-- testTransferEdgeCases --
transferEventListeners：旧对象无事件监听器，无需转移
[ASSERTION PASSED]: Transfer from empty target should return empty mapping
[ASSERTION PASSED]: Should return object even for empty transfer
自动清理及用户卸载逻辑已设置。
transferEventListeners 警告：源对象与目标对象相同，无需转移
[ASSERTION PASSED]: Transfer to same target should be handled gracefully
transferEventListeners 错误：目标对象不能为空
[ASSERTION PASSED]: Transfer with null old target should return null
transferEventListeners 错误：目标对象不能为空
[ASSERTION PASSED]: Transfer with undefined new target should return null
[ASSERTION PASSED]: Transfer of non-existent events should return empty mapping
所有事件监听器已清除。
-- testTransferEdgeCases Completed --


-- testMultiPhaseTransfer --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Phase1 should work normally
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 3 个监听器
[ASSERTION PASSED]: Phase1 to Phase2 transfer should succeed
[ASSERTION PASSED]: Phase2 should work, Phase1 should be cleared
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 3 个监听器
[ASSERTION PASSED]: Phase2 to Phase3 transfer should succeed
[ASSERTION PASSED]: Phase3 should work, Phase2 should be cleared
所有事件监听器已清除。
-- testMultiPhaseTransfer Completed --


-- testTransferPerformance --
自动清理及用户卸载逻辑已设置。
[Transfer Performance] Registered 1000 handlers in 19 ms
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1000 个监听器
[Transfer Performance] Transferred 1000 handlers in 13 ms
[ASSERTION PASSED]: All transferred handlers should work
所有事件监听器已清除。
[Transfer Performance] Cleared 1000 handlers in 0 ms
-- testTransferPerformance Completed --


-- testStatisticsFeatures --
[ASSERTION PASSED]: Initial stats should show 0 events
[ASSERTION PASSED]: Initial stats should show 0 handlers
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Should show 2 different events
[ASSERTION PASSED]: Should show 3 total handlers
[ASSERTION PASSED]: onPress should have 2 handlers
[ASSERTION PASSED]: onRelease should have 1 handler
[ASSERTION PASSED]: Events should be enabled by default
目标对象的所有自定义事件监听器已 禁用。
[ASSERTION PASSED]: Events should show disabled state
[ASSERTION PASSED]: Should detect original handler
=== EventCoordinator 全局统计 ===
目标 EC2069: 3 个事件, 4 个处理器
目标 EC0: 1 个事件, 2 个处理器
总计: 2 个目标对象, 6 个监听器
================================
[ASSERTION PASSED]: listAllTargets should execute without errors
所有事件监听器已清除。
-- testStatisticsFeatures Completed --


-- [v2.2 P0-3] testWatchUnwatchLifecycle --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.2 P0-3] Listener should work before clear
所有事件监听器已清除。
[ASSERTION PASSED]: [v2.2 P0-3] Listener should not work after clear
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.2 P0-3] New listener should work after clear and re-add
所有事件监听器已清除。
-- [v2.2 P0-3] testWatchUnwatchLifecycle Completed --


-- [v2.2 P0-3] testClearRestoresUserOnUnload --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.2 P0-3 ext] Custom listener should work
所有事件监听器已清除。
[ASSERTION PASSED]: [v2.2 P0-3 ext] onUnload should be restored after clear
[ASSERTION PASSED]: [v2.2 P0-3 ext] User's original onUnload should be called
[ASSERTION PASSED]: [v2.2 P0-3 ext] User's onUnload should continue to work
-- [v2.2 P0-3] testClearRestoresUserOnUnload Completed --


-- [v2.3 I2] testRemoveEventListenerFullCleanup --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.3 I2] addEventListener should return valid ID for onPress
[ASSERTION PASSED]: [v2.3 I2] addEventListener should return valid ID for onRelease
[ASSERTION PASSED]: [v2.3 I2] onPress handler should work
[ASSERTION PASSED]: [v2.3 I2] onRelease handler should work
监听器已移除：HID2080
所有监听器已移除：onPress，已恢复原生处理器。
[ASSERTION PASSED]: [v2.3 I2] removeEventListener should return true for valid removal
[ASSERTION PASSED]: [v2.3 I2] onPress handler should be removed
[ASSERTION PASSED]: [v2.3 I2] onRelease handler should still work
监听器已移除：HID2081
所有监听器已移除：onRelease，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: [v2.3 I2] removeEventListener should return true for last event removal
[ASSERTION PASSED]: [v2.3 I2] onRelease handler should be removed after full cleanup
[ASSERTION PASSED]: [v2.3 I2] CRITICAL - User's original onUnload should be restored after full cleanup
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.3 I2] Should be able to add new listener after full cleanup
[ASSERTION PASSED]: [v2.3 I2] New listener should work after full cleanup
所有事件监听器已清除。
-- [v2.3 I2] testRemoveEventListenerFullCleanup Completed --


-- [v2.3.3] testOnUnloadRecursionFix --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.3.3] onPress should work after autoCleanup enabled
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: [v2.3.3] Should be able to add onUnload listener after autoCleanup
所有事件监听器已清除。
onUnload 已执行并清理所有事件监听器。
[ASSERTION PASSED]: [v2.3.3] CRITICAL - No infinite recursion should occur on unload
[ASSERTION PASSED]: [v2.3.3] Custom onUnload handler should be called exactly once (got: 1)
[v2.3.3] Test completed - userUnloadCount: 1, onUnloadHandlerCount: 1
-- [v2.3.3] testOnUnloadRecursionFix Completed --


-- performanceTest --
自动清理及用户卸载逻辑已设置。
[Performance] Registered 5000 handlers in 114 ms.
[Performance] Called onPress 10 times in 133 ms.
[Performance] CallCounter = 50000 (expected 50000)
所有事件监听器已清除。
[Performance] Cleared all handlers in 0 ms.
-- performanceTest Completed --


=== Tests Completed ===
Total Assertions: 109
Passed Assertions: 109
Failed Assertions: 0

onUnload 已执行并清理所有事件监听器。