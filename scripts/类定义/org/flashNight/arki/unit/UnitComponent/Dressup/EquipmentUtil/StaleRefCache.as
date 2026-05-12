/**
 * StaleRefCache - stale-ref window 坐标快照缓存
 *
 * 解决问题：装扮 holder mc 在 timeline 切帧 destroy 时，订阅方读到的
 * unit[refName] 是 detached MovieClip（_parent==null），localToGlobal 退化
 * 为 (0,0)。详见 DressupSubscriber.as 类头【stale-ref window】段。
 *
 * 适用于 DressupSubscriber **Idiom B**（不可丢事件，如玩家攻击判定）：
 *
 *   挂载方周期函数（每帧 30fps）：
 *     StaleRefCache.snapshot(unit, unit.刀_引用, "刀口位置3");
 *
 *   订阅方 callback（事件触发时）：
 *     var pt = StaleRefCache.resolve(unit, unit.刀_引用, "刀口位置3");
 *     if (!pt) pt = {x: unit._x, y: unit._y};  // bootstrap fallback
 *
 * 误差边界：stale window 内 resolve 返回的是上次 snapshot 的坐标，滞后
 * ≤1 帧玩家位移（~10-15px @ 30fps），低于人眼帧间分辨。
 *
 * 性能：snapshot ~5-10us / call（localToGlobal + globalToLocal + dict write）。
 *
 * Testload 实测依据（FP20）：T10 否决了 "detached MC localToGlobal 当帧仍
 * walks" 假设，T11/T12/T13 否决了 onUnload 事件驱动路径（跨 phase remove
 * 后 GC 抢先，onUnload 丢失）。详见 agentsDoc/as2-load-timing.md 第 2.5 节。
 *
 * 用例样本：
 *   挂载方：scripts/逻辑/装备函数/通用装备函数.as 通用特效刀口周期
 *   订阅方：scripts/逻辑/装备函数/主唱光剑.as "主唱光剑光刃" subscriber
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.StaleRefCache {

    /**
     * 写：每帧由"挂载方周期"调用。saber stale 时不写（保留上次值，让
     * resolve 在 stale window 内仍有可用 cache）。
     *
     * @param unit       承载 cache 的 MC（通常是 player unit）
     * @param saber      装扮引用 MC（unit[refName]，如 unit.刀_引用）
     * @param childName  saber 内的 placement child 名（如 "刀口位置3"）
     * @return true 写入成功；false stale / 缺 child（cache 保留旧值）
     */
    public static function snapshot(unit:MovieClip, saber:MovieClip, childName:String):Boolean {
        if (!saber || !saber._parent) return false;
        var child:MovieClip = saber[childName];
        if (!child) return false;
        var pt:Object = {x: child._x, y: child._y};
        saber.localToGlobal(pt);
        _root.gameworld.globalToLocal(pt);
        if (!unit._staleRefCache) unit._staleRefCache = {};
        unit._staleRefCache[childName] = pt;
        return true;
    }

    /**
     * 读：由"订阅方 callback"调用，二级回落：
     *   ① saber chain live → 当帧精确计算（不走 cache，最高精度）
     *   ② cache 存在 → 读 cache（stale window 滞后 ≤1 帧）
     *   ③ 都无 → null（调用方需自行 bootstrap fallback，如 target 中心）
     *
     * 订阅方在 fire 瞬间应重新读 unit[refName] 传入，确保 saber 是当下值。
     *
     * @return {x:Number, y:Number} 或 null
     */
    public static function resolve(unit:MovieClip, saber:MovieClip, childName:String):Object {
        if (saber && saber._parent && saber[childName]) {
            var child:MovieClip = saber[childName];
            var pt:Object = {x: child._x, y: child._y};
            saber.localToGlobal(pt);
            _root.gameworld.globalToLocal(pt);
            return pt;
        }
        if (unit._staleRefCache && unit._staleRefCache[childName]) {
            var cached:Object = unit._staleRefCache[childName];
            return {x: cached.x, y: cached.y};
        }
        return null;
    }
}
