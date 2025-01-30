org.flashNight.aven.Coordinator.EventCoordinatorTest.runAllTests();





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
用户的 onUnload 函数已更新。
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
[ASSERTION PASSED]: After removing both handlers, none should be called
[INFO] Removing non-existent handler should not affect existing handlers.
[ASSERTION PASSED]: Removing a non-existent handler should not throw errors
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
onUnload 已执行并清理所有事件监听器。
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


-- performanceTest --
自动清理及用户卸载逻辑已设置。
[Performance] Registered 5000 handlers in 98 ms.
[Performance] Called onPress 10 times in 141 ms.
[Performance] CallCounter = 50000 (expected 50000)
所有事件监听器已清除。
[Performance] Cleared all handlers in 0 ms.
-- performanceTest Completed --


=== Tests Completed ===
Total Assertions: 48
Passed Assertions: 48
Failed Assertions: 0