import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.unit.UnitComponent.Updater.WatchDogUpdater;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.RespawnEventComponent {
    /**
     * 初始化单位的复活事件监听
     * @param target 目标单位 (MovieClip)
     */
    public static function initialize(target:MovieClip):Void {
        // _root.发布消息("复活参数", target._name, target.respawn);
        if(!target.respawn) return; // 只为有复活功能的单位添加事件监听

        var dispatcher:EventDispatcher = target.dispatcher;

        var func:Function;

        if(_root.控制目标 === target._name) {
            func = RespawnEventComponent.onHeroRespawn;
            // _root.发布消息("主角复活挂载");
        } else {
            func = RespawnEventComponent.onRespawn;
            // _root.发布消息("复活挂载");
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

        // 复活是同一个 MovieClip 从 dead 回到 alive，不能继续依赖死亡 man 的
        // onUnload 帧脚本代替权威状态恢复。角色可能在倒地帧死亡，或该 onUnload
        // 已被路由层接管；此时残留的 倒地 会拦掉所有普通技能，只有无条件的小跳
        // 仍能释放。_killed 若不清除，下一次死亡也会被 BulletQueueProcessor 的
        // 重复死亡守卫吞掉。先恢复这些生命期事实，再重新入缓存和切换动画。
        target.倒地 = false;
        target._killed = false;
        delete target._deathDiagLogged;
        WatchDogUpdater.reset(target);

        _root.发布消息("复活");
        TargetCacheManager.addUnit(target);
        target.动画完毕(); // 通常用于强制重置动画状态
        // 旧关卡结束 MovieClip 会在自己的收尾帧隐藏弹窗；迁到 C# 后不再有
        // 那个时间轴替主角恢复显示。复活事件本身必须完整恢复单位表现，不能把
        // 一个已经恢复 HP、重新进入 TargetCache 的可攻击单位留在不可见状态。
        target._visible = true;

    }

    /**
     * 复活事件处理逻辑
     * @param target 目标单位 (MovieClip)
     */
    public static function onHeroRespawn(target:MovieClip):Void {
        RespawnEventComponent.onRespawn(target);

        _root.发布消息("主角复活");

        _root.玩家信息界面.刷新hp显示();
        _root.玩家信息界面.刷新mp显示();
        org.flashNight.arki.scene.StageRunSession.onHeroRespawn(target);

        EffectSystem.Effect("药剂动画", target._x, target._y, 100);
    }
}
