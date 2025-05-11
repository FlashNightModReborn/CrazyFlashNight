import org.flashNight.neur.Event.EventDispatcher;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.RespawnEventComponent {
    /**
     * 初始化单位的复活事件监听
     * @param target 目标单位 (MovieClip)
     */
    public static function initialize(target:MovieClip):Void {
        if(!target.respawn) return; // 只为有复活功能的单位添加事件监听

        var dispatcher:EventDispatcher = target.dispatcher;

        var func:Function;

        if(_root.控制目标 === target._name) {
            func = RespawnEventComponent.onHeroRespawn;
        } else {
            func = RespawnEventComponent.onRespawn;
        }
        // 订阅复活事件
        dispatcher.subscribeSingle("respawn", func, target);
    }

    /**
     * 复活事件处理逻辑
     * @param target 目标单位 (MovieClip)
     */
    public static function onRespawn(target:MovieClip):Void {
        target.hp = target.hp满血值;
        target.mp = target.mp满血值;

        target.动画完毕(); // 通常用于强制重置动画状态
    }

    /**
     * 复活事件处理逻辑
     * @param target 目标单位 (MovieClip)
     */
    public static function onHeroRespawn(target:MovieClip):Void {
        RespawnEventComponent.onRespawn(target);

        _root.玩家信息界面.刷新hp显示();
        _root.玩家信息界面.刷新mp显示();

        if (_root.关卡是否结束) {
            _root.gotoAndStop("关卡结束");
        } else {
            target._visible = false;
        }

        _root.效果("药剂动画", target._x, target._y, 100);
    }
}
