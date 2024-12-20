import org.flashNight.gesh.property.*;
import org.flashNight.arki.component.Buff.*; 
import org.flashNight.arki.component.Buff.BuffHandle.*;

function addSpeedProperties(obj:Object):Void {
    // 创建 BuffProperty 管理 'speed'
    var buff:BuffProperty = new BuffProperty(obj, "speed");
    obj.buff = buff; // 暴露 BuffProperty 以便添加 buffs

    // 创建 PropertyAccessor 用于 'speedX'，依赖于 buffed 'speed'
    var speedXAccessor:PropertyAccessor = new PropertyAccessor(obj, "speedX", 0, function():Number {
        return obj.speed * 0.5;
    }, null);

    // 创建 PropertyAccessor 用于 'speedY'，依赖于 buffed 'speed'
    var speedYAccessor:PropertyAccessor = new PropertyAccessor(obj, "speedY", 0, function():Number {
        return obj.speed * 2;
    }, null);

    // 定义使 'speedX' 和 'speedY' 缓存失效的方法
    obj.invalidateDependents = function():Void {
        speedXAccessor.invalidate();
        speedYAccessor.invalidate();
        trace("Invalidated 'speedX' and 'speedY' caches.");
    };
}


function main():Void {
    // 创建目标对象
    var controller:Object = {};

    // 添加速度相关的访问器属性
    addSpeedProperties(controller);

    // 设置 speed_base 为 10
    trace("\n设置 speed_base 为 10");
    controller.speed_base = 10;
    trace("Speed: " + controller.speed);    // 应输出: Speed: 10
    trace("SpeedX: " + controller.speedX);  // 应输出: SpeedX: 5
    trace("SpeedY: " + controller.speedY);  // 应输出: SpeedY: 20

    // 添加乘算 buff: speed * 1.5
    trace("\n添加乘算 buff: 1.5");
    controller.buff.addMultiplier(1.5);
    trace("Speed: " + controller.speed);    // 应输出: Speed: 15
    trace("SpeedX: " + controller.speedX);  // 应输出: SpeedX: 7.5
    trace("SpeedY: " + controller.speedY);  // 应输出: SpeedY: 30

    // 添加加算 buff: speed + 5
    trace("\n添加加算 buff: 5");
    controller.buff.addAddition(5);
    trace("Speed: " + controller.speed);    // 应输出: Speed: 20
    trace("SpeedX: " + controller.speedX);  // 应输出: SpeedX: 10
    trace("SpeedY: " + controller.speedY);  // 应输出: SpeedY: 40

    // 修改 speed_base 为 20
    trace("\n设置 speed_base 为 20");
    controller.speed_base = 20;
    trace("Speed: " + controller.speed);    // 应输出: Speed: 35
    trace("SpeedX: " + controller.speedX);  // 应输出: SpeedX: 17.5
    trace("SpeedY: " + controller.speedY);  // 应输出: SpeedY: 70

    // 尝试设置 speed_base 为 -5（无效）
    trace("\n尝试设置 speed_base 为 -5");
    controller.speed_base = -5; // 应输出: Invalid value: -5! 'speed_base' must be non-negative.
    trace("Speed: " + controller.speed);    // 应输出: Speed: 35
    trace("SpeedX: " + controller.speedX);  // 应输出: SpeedX: 17.5
    trace("SpeedY: " + controller.speedY);  // 应输出: SpeedY: 70

    // 移除特定的乘算 buff
    trace("\n移除乘算 buff: 1.5");
    // 假设已保存 buff 实例，可直接移除
    // 这里为了示例，假设只存在一个乘算 buff
    var multiplierBuff:MultiplierBuff = controller.buff._buffs[0];
    controller.buff.removeBuff(multiplierBuff);
    trace("Speed: " + controller.speed);    // 应输出: Speed: 20 (20 * 1 + 5 = 25)
    trace("SpeedX: " + controller.speedX);  // 应输出: SpeedX: 12.5
    trace("SpeedY: " + controller.speedY);  // 应输出: SpeedY: 50
}

main();

