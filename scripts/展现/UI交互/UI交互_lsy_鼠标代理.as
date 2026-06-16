// _root.鼠标 / _root.鼠标代理 兼容代理 —— 帧脚本 bootstrap
//
// 实际实现在 org.flashNight.arki.cursor.MouseProxy。class 化的原因：
// asLoader 帧脚本中创建的 Function 闭包会暗中持有定义时的 With 链；
// asLoader 卸载后链头被 GC，闭包可能失效。把方法挂在 class 上由 SWF 持有，
// 跨 asLoader 生命周期安全。本帧脚本只做一次性安装调用。
//
// 对外 API（保持不变）：
//   _root.鼠标.gotoAndStop(state) / gotoAndPlay(state) / removeMovieClip()
//   _root.鼠标.物品图标容器.attachMovie(...)
//   _root.鼠标代理.命中目标(target, shapeFlag)
//   _root.鼠标代理.清理拖拽图标()


MouseProxy.install();
