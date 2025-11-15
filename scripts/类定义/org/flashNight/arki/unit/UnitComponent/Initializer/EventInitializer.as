// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventInitializer.as
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventInitializer {
    /**
     * 统一初始化单位的事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        // 初始化受击事件组件
        HitEventComponent.initialize(target);
        // 初始化天气事件组件
        WeatherEventComponent.initialize(target);
        // 初始化死亡事件组件
        KillEventComponent.initialize(target);
        DeathEventComponent.initialize(target);
        // 初始化击杀统计事件组件
        EnemyKilledEventComponent.initialize(target);
        // 初始化血量相关事件组件
        HPEventComponent.initialize(target);
        // 初始化敌人ai组件

        UpdateEventComponent.initialize(target);
        RespawnEventComponent.initialize(target);
        
        // 初始化仇恨事件组件
        AggroEventComponent.initialize(target);

        DyeEventComponent.initialize(target);


        // 发布特殊单位出生事件
        if(target.publishStageEvent === true){
            _root.gameworld.dispatcher.publish("UnitSpawn",target._name);
        }

        if(target.兵种 != "主角-男") return; // 主角限定

        ReloadEventComponent.initialize(target);
        FireEventComponent.initialize(target);
    }
}
