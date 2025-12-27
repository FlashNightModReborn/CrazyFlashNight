import org.flashNight.arki.component.Collider.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.component.Shield.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.ComponentInitializer {

    public static function initialize(target:MovieClip):Void {
        if (!target.aabbCollider) {
            target.aabbCollider = StaticInitializer.factory.createFromUnitArea(target);
        }
        if (target.dispatcher) {
            target.dispatcher.destroy(); // 销毁现有的dispatcher以避免重复绑定
        }
        
        if (!target.dispatcher) target.dispatcher = new LifecycleEventDispatcher(target);

        if(!target.unitAI){
            UnitAIInitializer.initialize(target);
        }

        // 初始化自适应护盾（空壳模式）
        // 空壳模式不参与任何逻辑，等待外部通过 addShield() 推入具体护盾
        if(!target.shield){
            target.shield = AdaptiveShield.createDormant(target._name + "_shield");
            target.shield.setOwner(target);

            // ===== 测试代码：为每个单位添加测试护盾 =====
            ComponentInitializer.addTestShield(target);
            // ===== 测试代码结束 =====
        }

        EventCoordinator.addUnloadCallback(target, function():Void {
            StaticDeinitializer.deInitializeUnit(target);
        });
    }

    // ===== 测试方法：添加测试护盾 =====
    /**
     * 为单位添加测试护盾
     * 护盾破碎后会自动重新挂载一个新护盾
     * @param target 目标单位
     */
    public static function addTestShield(target:MovieClip):Void {
        // 创建一个可充能的测试护盾
        // 容量: 单位满血HP的30%
        // 强度: 50（能挡住单次50点以下的伤害）
        // 充能速度: 每帧2点
        // 充能延迟: 60帧（约2秒）
        var hpMax:Number = target.hp满血值;

        var shieldCapacity:Number = Math.round(hpMax * 0.3);
        var testShield:Shield = Shield.createRechargeable(
            shieldCapacity,  // 容量
            target.防御力,              // 强度
            shieldCapacity / 30,               // 充能速度
            60,              // 充能延迟
            "测试护盾"        // 名称
        );

        _root.服务器.发布服务器消息("[测试] " + target._name + " 护盾已生成" + testShield.toString());

        // 设置破碎回调：重新挂载新护盾
        testShield.onBreakCallback = function(s:IShield):Void {
            // 延迟一帧后重新添加护盾，避免在回调中直接操作
            // 使用 _root.帧计时器 延迟执行
            var delayFrames:Number = 30; // 1秒后重新生成护盾
            _root.帧计时器.添加单次任务(
                function():Void {
                    if (target.shield && target.hp > 0) {
                        ComponentInitializer.addTestShield(target);
                        _root.服务器.发布服务器消息("[测试] " + target._name + " 护盾已重新生成");
                    }
                },
                delayFrames,
                target._name + "_shield_respawn"
            );
            _root.服务器.发布服务器消息("[测试] " + target._name + " 护盾破碎！" + delayFrames + "帧后重生");
        };

        // 设置命中回调（可选，用于调试）
        testShield.onHitCallback = function(s:IShield, absorbed:Number):Void {
            // _root.服务器.发布服务器消息("[测试] " + target._name + " 护盾吸收 " + absorbed + " 伤害，剩余 " + s.getCapacity());
        };

        // 添加到单位的护盾容器
        target.shield.addShield(testShield);
    }
    // ===== 测试方法结束 =====
}
