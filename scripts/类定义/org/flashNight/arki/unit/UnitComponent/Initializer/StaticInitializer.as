import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.gesh.arguments.*;
import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.gesh.func.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;


class org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer implements IInitializer {
    public static var factory:IColliderFactory;

    public function initialize(target:MovieClip):Void {
        throw new Error("工具类待实现");
    }

    public static function initializeUnit(target:MovieClip):Void {
        // 排除从非gameworld召唤出的单位
        if(target._parent !== _root.gameworld) return;

        // 速度派生初始化（第一次尝试）：
        // 敌人模板在调用StaticInitializer之前已设置行走X速度，此时可以设置getter
        // 主角模板此时行走X速度还不存在，会直接return，由DressupInitializer后触发
        SpeedDeriveInitializer.initialize(target);

        ComponentInitializer.initialize(target);
        ParameterInitializer.initialize(target);
        EventInitializer.initialize(target);

        DressupInitializer.initialize(target); // 只有主角模板会执行
        DisplayNameInitializer.initialize(target);

        TargetCacheUpdater.addUnit(target);

        ExtraPropertyInitializer.initialize(target);
        BuffManagerInitializer.initialize(target);

        /*
        // 防御性调用：确保所有组件准备就绪后立即同步信息框透明度状态
        // 补充 EventInitializer 中可能过早的天气同步调用
        var wtfunc:Function = WeatherUpdater.getUpdater();
        wtfunc.call(target);
        */
    }

    /**
     * 初始化地图元件的主方法（支持预设）
     * @param target 要初始化的地图元件MovieClip
     * @param presetName 预设名称，如果不提供则使用目标现有属性
     */
    public static function initializeMapElement(target:MovieClip, presetName:String):Void {
        // 应用预设配置（如果提供了预设名称）
        if (presetName) {
            target.presetName = presetName;
            StaticInitializer.applyPreset(target, presetName);
        }

        // 1. 验证进度要求 - 如果不满足则直接移除并返回
        if (!ProgressValidator.validate(target)) {
            // _root.发布消息("移除不满足进度要求的地图元件: " + target._name);
            return;
        }

        // 2. 设置随机数量
        QuantityRandomizer.randomizeQuantity(target);

        // 3. 初始化基础属性
        BasicAttributeInitializer.initialize(target);
        
        // 4. 初始化单位组件
        StaticInitializer.initializeUnit(target);

        // 5. 设置交互功能
        InteractionHandler.initialize(target);

        // 6. 应用染色效果
        ColorStainer.applyStaining(target);

        // 7. 渲染障碍物
        ObstacleRenderer.renderObstacle(target);

        // 8. 设置显示控制
        DisplayController.initialize(target);

    }

    /**
     * 应用预设到目标
     * @param target 目标MovieClip
     * @param presetName 预设名称
     * @return Boolean 如果成功应用预设返回true
     */
    public static function applyPreset(target:MovieClip, presetName:String):Boolean {
        if (!target || !presetName) return false;

        var preset:ElementPreset = PresetManager.getPreset(presetName);
        if (!preset) {
            trace("警告: 未找到预设 '" + presetName + "'，使用默认配置");
            return false;
        }

        preset.applyTo(target);
        return true;
    }

    /**
     * 快速初始化地图元件（跳过某些步骤以提高性能）
     * @param target 要初始化的地图元件MovieClip
     * @param presetName 预设名称
     * @param skipInteraction 是否跳过交互初始化
     * @param skipObstacle 是否跳过障碍物渲染
     */
    public static function initializeMapElementFast(target:MovieClip, presetName:String, skipInteraction:Boolean, skipObstacle:Boolean):Void {
        // 应用预设配置
        if (presetName) {
            StaticInitializer.applyPreset(target, presetName);
        }

        // 必要的验证和初始化
        if (!ProgressValidator.validate(target)) {
            return;
        }

        QuantityRandomizer.randomizeQuantity(target);
        BasicAttributeInitializer.initialize(target);
        StaticInitializer.initializeUnit(target);

        // 可选的功能
        if (!skipInteraction) {
            InteractionHandler.initialize(target);
        }

        ColorStainer.applyStaining(target);

        if (!skipObstacle) {
            ObstacleRenderer.renderObstacle(target);
        }

        DisplayController.initialize(target);
    }

    /**
     * 批量初始化地图元件
     * @param targets 要初始化的地图元件数组
     * @param presetName 预设名称（应用到所有目标）
     * @param useFastMode 是否使用快速模式
     */
    public static function batchInitializeMapElements(targets:Array, presetName:String, useFastMode:Boolean):Void {
        if (!targets || targets.length == 0) return;

        for (var i:Number = 0; i < targets.length; i++) {
            var target:MovieClip = targets[i];
            if (target) {
                if (useFastMode) {
                    StaticInitializer.initializeMapElementFast(target, presetName, false, true);
                } else {
                    StaticInitializer.initializeMapElement(target, presetName);
                }
            }
        }

        // 批量渲染障碍物（如果使用快速模式）
        if (useFastMode) {
            ObstacleRenderer.renderMultipleObstacles(targets);
        }
    }

    /**
     * 批量初始化地图元件（支持不同预设）
     * @param targetsWithPresets 包含{target, preset}对象的数组
     * @param useFastMode 是否使用快速模式
     */
    public static function batchInitializeMapElementsWithPresets(targetsWithPresets:Array, useFastMode:Boolean):Void {
        if (!targetsWithPresets || targetsWithPresets.length == 0) return;

        var targets:Array = [];
        
        for (var i:Number = 0; i < targetsWithPresets.length; i++) {
            var item:Object = targetsWithPresets[i];
            var target:MovieClip = item.target;
            var presetName:String = item.preset;
            
            if (target) {
                targets.push(target);
                
                if (useFastMode) {
                    StaticInitializer.initializeMapElementFast(target, presetName, false, true);
                } else {
                    StaticInitializer.initializeMapElement(target, presetName);
                }
            }
        }

        // 批量渲染障碍物（如果使用快速模式）
        if (useFastMode) {
            ObstacleRenderer.renderMultipleObstacles(targets);
        }
    }

    /**
     * 重新初始化地图元件（用于运行时更新）
     * @param target 要重新初始化的地图元件MovieClip
     */
    public static function reinitializeMapElement(target:MovieClip):Void {
        if (!target) return;

        // 清理现有状态
        InteractionHandler.cleanup(target);

        // 重新初始化
        StaticInitializer.initializeMapElement(target);
    }

    public static function initializeGameWorldUnit():Void {
        var gameworld:MovieClip = _root.gameworld;
        for (var each in gameworld) {
            var target = gameworld[each];
            if (target.hp > 0) StaticInitializer.initializeUnit(target);
        }
    }

    /**
     * 初始化游戏世界中的所有地图元件
     */
    public static function initializeGameWorldMapElements():Void {
        var gameworld:MovieClip = _root.gameworld;
        if (!gameworld) return;

        var mapElements:Array = [];
        
        // 收集所有地图元件
        for (var each in gameworld) {
            var target:MovieClip = gameworld[each];
            if (target && StaticInitializer.isMapElement(target)) {
                mapElements.push(target);
            }
        }

        // 批量初始化
        StaticInitializer.batchInitializeMapElements(mapElements, null, true);
    }

    /**
     * 判断目标是否为地图元件
     * @param target 要判断的目标MovieClip
     * @return Boolean 如果是地图元件返回true
     */
    private static function isMapElement(target:MovieClip):Boolean {
        // 可以根据具体需求调整判断条件
        return !!(target.element);
    }

    public static function onSceneChanged():Void {
        if (!_root.gameworld) return;
        StaticInitializer.factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);
        StaticInitializer.onSceneChanged = StaticInitializer.initializeGameWorldUnit;
        StaticInitializer.initializeGameWorldUnit();
        
        // 同时初始化地图元件
        StaticInitializer.initializeGameWorldMapElements();
    }

    /**
     * 清理所有地图元件相关资源
     */
    public static function cleanupMapElements():Void {
        var gameworld:MovieClip = _root.gameworld;
        if (!gameworld) return;

        // 清理障碍物
        ObstacleRenderer.clearAllObstacles(gameworld);

        // 清理交互监听器 
        for (var each in gameworld) {
            var target:MovieClip = gameworld[each];
            if (target && StaticInitializer.isMapElement(target)) {
                InteractionHandler.cleanup(target);
            }
        }
    }
}