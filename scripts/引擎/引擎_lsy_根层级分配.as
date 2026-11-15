// 常驻壳先于外部模块的类注册执行；S1 再包含本文件时必须沿用同一计数器。
// 固定系统层从 65531 开始。动态根剪辑只使用 1024..32767。
if (_root.层级管理器 == undefined) {
    _root.层级管理器 = {highest:1023};
}
_root.getNextHighestDepth = function():Number {
    var manager:Object = _root.层级管理器;
    var depth:Number = manager.highest;
    var collisions:Number = 0;
    var occupied:Object;
    // 回绕后跳过仍存活的常驻时钟、键盘轮询和 UI。下一次从本次返回层的后一层查找。
    for (var remaining:Number = 32767 - 1024 + 1; remaining > 0; --remaining) {
        depth = depth < 32767 ? depth + 1 : 1024;
        if (occupied != undefined && occupied[depth]) continue;
        if (_root.getInstanceAtDepth(depth) == undefined) {
            manager.highest = depth;
            return depth;
        }
        // 密集回绕时逐层查询会反复扫描显示列表。只缓存确认占用的直属剪辑，
        // 没枚举到的层（含文本框、按钮和重名剪辑）仍由播放器查验。
        if (++collisions == 16) {
            occupied = {};
            for (var name:String in _root) {
                var clip = _root[name];
                if (typeof clip == "movieclip" && clip._parent === _root) {
                    occupied[MovieClip.prototype.getDepth.call(clip)] = true;
                }
            }
        }
    }
    throw new Error("No free dynamic root depth (1024..32767)");
};
