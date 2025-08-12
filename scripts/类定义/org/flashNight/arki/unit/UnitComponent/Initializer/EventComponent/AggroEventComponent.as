import org.flashNight.neur.Event.EventDispatcher;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.AggroEventComponent {

    /**
     * 初始化单位的仇恨相关事件监听
     * @param target 目标单位(MovieClip)
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        if (!dispatcher) return;

        dispatcher.subscribeSingle("aggroSet", AggroEventComponent.onAggroSet, target);
    }

    /**
     * 处理设置仇恨目标的请求
     * @param target  受击单位（被设置仇恨的对象）
     * @param shooter 施加仇恨的来源（通常是射手）
     * @param bullet  触发来源的子弹（可选，用于策略扩展）
     */
    public static function onAggroSet(target:MovieClip, shooter:MovieClip, bullet:MovieClip):Void {
        // 基础校验：地图元素不参与仇恨、无 shooter 直接忽略
        if (target.element || !shooter) return;

        var dispatcher:EventDispatcher = target.dispatcher;
        if (!dispatcher) return;

        // 计算新老值
        // 说明：用 String() 保守转换，避免出现 undefined/Number 的类型噪音
        var prevAggro:String = String(target.攻击目标);
        var newAggro:String  = String(shooter._name);

        // 若无变化则早退，避免无意义写入与广播
        if (prevAggro === newAggro) return;

        // 真正落地赋值
        target.攻击目标 = newAggro;
    }
}
