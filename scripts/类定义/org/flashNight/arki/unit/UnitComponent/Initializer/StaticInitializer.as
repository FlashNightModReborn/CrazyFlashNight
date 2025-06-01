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

class org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer implements IInitializer {
    public static var factory:IColliderFactory;

    public function initialize(target:MovieClip):Void {
        throw new Error("工具类待实现");
    }

    public static function initializeUnit(target:MovieClip):Void {
        // 排除从非gameworld召唤出的单位
        if(target._parent !== _root.gameworld) return;
        
        ComponentInitializer.initialize(target);
        ParameterInitializer.initialize(target);
        EventInitializer.initialize(target);
        DisplayNameInitializer.initialize(target);
        TargetCacheUpdater.addUnit(target);
    }

    public static function initializeMapElement(target:MovieClip):Void {
        // 检查主线任务进度限制
        if (
            (!isNaN(target.最小主线进度) && _root.主线任务进度 < target.最小主线进度) ||
            (!isNaN(target.最大主线进度) && _root.主线任务进度 > target.最大主线进度)
        ) {
            target.removeMovieClip();
            return;
        }

        // 设置随机数量
        if (target.数量_min > 0 && target.数量_max > 0) {
            target.数量 = target.数量_min + random(target.数量_max - target.数量_min + 1);
        }

        // 设置基本属性
        target.是否为敌人 = true;

        // 初始化生命值
        if (isNaN(target.hitPoint)) {
            target.hitPoint = target.hitPointMax = 10;
        } else {
            target.hitPointMax = target.hitPoint;
        }

        // 设置特殊属性
        target.hp = 9999999;
        target.防御力 = 99999;
        target.躲闪率 = 100;
        target.击中效果 = target.击中效果 || "火花";
        target.Z轴坐标 = target._y;
        target.unitAIType = "None";
        
        // 初始化单位组件
        StaticInitializer.initializeUnit(target);

        // 设置显示状态
        target.gotoAndStop("正常");
        target.element.stop();

        // 设置拾取功能
        var pickUpFunc:Function = function():Void {
            if (this._killed) return; // 避免多次触发

            var focusedObject:MovieClip = TargetCacheManager.findHero();
            if (Math.abs(this.Z轴坐标 - focusedObject.Z轴坐标) < 50 && focusedObject.area.hitTest(this.area)) {
                this.dispatcher.publish("pickUp", this);
            }
        };

        target.dispatcher.subscribeGlobal("interactionKeyDown", pickUpFunc, target);

        // 设置拾取处理
        var pickFunc:Function = function(target:MovieClip):Void {
            target.dispatcher.publish("kill", target);

            var scavenger:MovieClip = TargetCacheManager.findHero();
            var audio:String = target.audio || "拾取音效";
            _root.播放音效(audio);

            scavenger.拾取();
        };

        target.dispatcher.subscribe("pickUp", pickFunc, target);

        // 处理染色目标
        if (target.stainedTarget) {
            // 初始化并校验色彩参数（默认值：乘数为1，偏移为0）
            target.redMultiplier = isNaN(target.redMultiplier) ? 1 : target.redMultiplier;
            target.greenMultiplier = isNaN(target.greenMultiplier) ? 1 : target.greenMultiplier;
            target.blueMultiplier = isNaN(target.blueMultiplier) ? 1 : target.blueMultiplier;
            target.alphaMultiplier = isNaN(target.alphaMultiplier) ? 1 : target.alphaMultiplier;

            target.redOffset = isNaN(target.redOffset) ? 0 : target.redOffset;
            target.greenOffset = isNaN(target.greenOffset) ? 0 : target.greenOffset;
            target.blueOffset = isNaN(target.blueOffset) ? 0 : target.blueOffset;
            target.alphaOffset = isNaN(target.alphaOffset) ? 0 : target.alphaOffset;

            // 应用色彩设置
            _root.设置色彩(target[target.stainedTarget],
                        target.redMultiplier,
                        target.greenMultiplier,
                        target.blueMultiplier,
                        target.redOffset,
                        target.greenOffset,
                        target.blueOffset,
                        target.alphaMultiplier,
                        target.alphaOffset);
        }

        // 将碰撞箱附加到地图
        var gameworld = _root.gameworld;

        if (target.obstacle && target.area) {
            var rect = target.area.getRect(gameworld);
            var 地图 = gameworld.地图;

            // 设置 `地图` 为不可枚举
            _global.ASSetPropFlags(gameworld, ["地图"], 1, false);

            地图.beginFill(0x000000);
            地图.moveTo(rect.xMin, rect.yMin);
            地图.lineTo(rect.xMax, rect.yMin);
            地图.lineTo(rect.xMax, rect.yMax);
            地图.lineTo(rect.xMin, rect.yMax);
            地图.lineTo(rect.xMin, rect.yMin);
            地图.endFill();
        }

        // 设置区域不可见并调整深度
        target.area._visible = false;
        target.swapDepths(target._y);
    }

    public static function initializeGameWorldUnit():Void {
        var gameworld:MovieClip = _root.gameworld;
        
        for (var each in gameworld) {
            var target = gameworld[each];
            if (target.hp > 0) {
                if(target.element) {
                    StaticInitializer.initializeMapElement(target);
                } else {
                    StaticInitializer.initializeUnit(target);
                }
            }
        }
    }

    public static function onSceneChanged():Void {
        if (!_root.gameworld) return;
        StaticInitializer.factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);
        StaticInitializer.onSceneChanged = StaticInitializer.initializeGameWorldUnit;
        StaticInitializer.initializeGameWorldUnit();
    }
}