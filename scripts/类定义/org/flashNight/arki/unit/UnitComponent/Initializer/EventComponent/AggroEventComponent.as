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
        dispatcher.subscribeSingle("aggroClear", AggroEventComponent.onAggroClear, target);
    }

    /**
     * 处理设置仇恨目标的事件
     * @param sender 发布事件的单位（谁的仇恨目标发生了变化）
     * @param newTarget 新的攻击目标对象
     */
    public static function onAggroSet(sender:MovieClip, newTarget:MovieClip):Void {
        // 基础校验：地图元素不参与仇恨、无 newTarget 直接忽略
        if (sender.element || !newTarget) return;

        var dispatcher:EventDispatcher = sender.dispatcher;
        if (!dispatcher) return;

        // 计算新老值
        // 说明：用 String() 保守转换，避免出现 undefined/Number 的类型噪音
        var prevAggro:String = String(sender.攻击目标);
        var newAggro:String  = String(newTarget._name);

        // 若无变化则早退，避免无意义写入与广播
        if (prevAggro === newAggro) return;

        // 真正落地赋值
        sender.攻击目标 = newAggro;

        // 可以在这里添加额外的逻辑，比如UI更新、音效播放等
        // 例如：notifyUIOfAggroChange(sender, newTarget);
    }

    /**
     * 处理清除仇恨目标的事件
     * @param sender 发布事件的单位（谁的仇恨目标被清除了）
     */
    public static function onAggroClear(sender:MovieClip):Void {
        // 基础校验：地图元素不参与仇恨
        if (sender.element) return;

        var dispatcher:EventDispatcher = sender.dispatcher;
        if (!dispatcher) return;

        // 计算新老值
        var prevAggro:String = String(sender.攻击目标);
        var newAggro:String  = "无";

        // 若无变化则早退，避免无意义写入与广播
        if (prevAggro === newAggro) return;

        // 真正落地赋值
        sender.攻击目标 = "无";

        // 可以在这里添加额外的逻辑，比如UI更新、音效播放等
        // 例如：notifyUIOfAggroClear(sender);
    }
}
