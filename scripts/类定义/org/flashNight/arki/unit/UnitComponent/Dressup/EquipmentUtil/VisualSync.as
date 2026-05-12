/**
 * VisualSync - 装备周期同帧 dedup 工具
 *
 * 用于支撑「tickState / applyVisual 分离」契约：
 *   - xxx周期(ref, param)        每帧推 state（节流/latch/random/IO 都在此区），末尾调 xxx视觉更新
 *   - xxx视觉更新(ref)            纯写 mc 属性，必须幂等（gotoAndStop / _visible / _x ...）
 *   - placement event handler    只调 xxx视觉更新，不调周期
 *
 * 周期函数顶部加 `if (!VisualSync.beginTick(ref)) return;` 即可保证同帧只 tick 一次。
 * 视觉更新不需要短路 —— Flash 的 gotoAndStop / _visible 等写入对未变化值是接近 no-op，
 * 而 placement handler 与周期函数若在同帧前后相继触发，需要让后一次 apply 反映新 state。
 *
 * 帧时钟源：_root.帧计时器.当前帧数（项目全局帧计数器）
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.VisualSync {

    /**
     * 周期 tick 同帧 dedup。
     *
     * 用法：
     *   _root.装备生命周期函数.xxx周期 = function(ref, param) {
     *       if (!VisualSync.beginTick(ref)) return;
     *       ...
     *   };
     *
     * @return false 表示本帧已 tick 过，调用方应立即 return；true 表示首次 tick，继续执行
     */
    public static function beginTick(ref:Object):Boolean {
        var f:Number = _root.帧计时器.当前帧数;
        if (ref.lastTickFrame === f) return false;
        ref.lastTickFrame = f;
        return true;
    }
}
