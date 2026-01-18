// ConditionComponent.as - 条件触发组件
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * 条件触发组件
 *
 * 用途：基于动态条件控制Buff的激活/失效
 *
 * 使用场景：
 * - 背水一战：HP < 30%时激活+50%伤害Buff
 * - 瞄准状态：移动时失效
 * - 武器限定被动：装备特定武器才生效
 * - 环境Buff：进入/离开特定区域时激活/失效
 *
 * 工作模式：
 * 1. 周期性调用条件函数检查
 * 2. 条件返回false时Buff失效
 * 3. 条件返回true时Buff继续存活
 *
 * 示例:
 *   // 背水一战：HP < 30%时+50%伤害
 *   var berserkBuffs:Array = [
 *       new PodBuff("damage", BuffCalculationType.PERCENT, 0.5)
 *   ];
 *   var conditionComp:ConditionComponent = new ConditionComponent(
 *       function():Boolean {
 *           return unit.hp < unit.maxHp * 0.3; // HP低于30%时生效
 *       },
 *       30 // 每秒检查一次
 *   );
 *   var berserkMeta:MetaBuff = new MetaBuff(berserkBuffs, [conditionComp], 0);
 *
 * 注意事项：
 * - 条件函数应尽量轻量，避免复杂计算
 * - 合理设置检查间隔，避免每帧检查造成性能开销
 * - 条件函数内访问外部变量时注意作用域
 */
class org.flashNight.arki.component.Buff.Component.ConditionComponent
    implements IBuffComponent
{
    private var _conditionFunc:Function;   // 条件检查函数，返回Boolean
    private var _checkInterval:Number;     // 检查间隔(帧)
    private var _frameCounter:Number;      // 帧计数器
    private var _invertCondition:Boolean;  // 是否反转条件(false时失效变为true时失效)
    private var _lastCheckResult:Boolean;  // 上次检查结果(用于调试)

    /**
     * 构造函数
     * @param conditionFunc 条件函数，返回Boolean。true=继续存活，false=失效
     * @param checkInterval 检查间隔(帧数)，默认1(每帧检查)
     * @param invertCondition 是否反转条件，默认false
     *
     * 示例条件函数:
     *   function():Boolean { return unit.hp > 0; }  // 单位存活
     *   function():Boolean { return unit.速度 == 0; } // 静止时
     */
    public function ConditionComponent(
        conditionFunc:Function,
        checkInterval:Number,
        invertCondition:Boolean
    ) {
        _conditionFunc = conditionFunc;
        _checkInterval = (checkInterval != undefined && checkInterval > 0) ? checkInterval : 1;
        _invertCondition = (invertCondition != undefined) ? invertCondition : false;
        _frameCounter = 0;
        _lastCheckResult = true; // 假设初始条件满足
    }

    /**
     * 立即执行条件检查
     * @return Boolean 条件是否满足
     */
    public function checkCondition():Boolean {
        if (!_conditionFunc) {
            return true; // 无条件函数则始终满足
        }

        try {
            var result:Boolean = _conditionFunc();
            _lastCheckResult = _invertCondition ? !result : result;
            return _lastCheckResult;
        } catch (e) {
            trace("[ConditionComponent] 条件检查出错: " + e);
            return true; // 出错时默认继续存活
        }
    }

    /**
     * 获取上次检查结果
     */
    public function getLastCheckResult():Boolean {
        return _lastCheckResult;
    }

    /**
     * 设置新的条件函数
     */
    public function setConditionFunc(newFunc:Function):Void {
        _conditionFunc = newFunc;
        _frameCounter = 0; // 重置计数器，立即检查
    }

    /**
     * 设置检查间隔
     */
    public function setCheckInterval(interval:Number):Void {
        if (interval > 0) {
            _checkInterval = interval;
        }
    }

    /**
     * 获取当前检查间隔
     */
    public function getCheckInterval():Number {
        return _checkInterval;
    }

    /**
     * 重置帧计数器(强制下次update时检查)
     */
    public function resetCounter():Void {
        _frameCounter = 0;
    }

    public function onAttach(host:IBuff):Void {
        // 附加时立即检查一次
        checkCondition();
    }

    public function onDetach():Void {
        // 清理引用
        _conditionFunc = null;
    }

    /**
     * 更新组件
     * @param host 宿主Buff
     * @param deltaFrames 增量帧数
     * @return Boolean 条件是否满足(false则Buff失效)
     */
    public function update(host:IBuff, deltaFrames:Number):Boolean {
        _frameCounter += deltaFrames;

        // 达到检查间隔时执行条件检查
        if (_frameCounter >= _checkInterval) {
            _frameCounter -= _checkInterval; // 保留余数，避免累积误差

            var conditionMet:Boolean = checkCondition();

            if (!conditionMet) {
                // 条件不满足，Buff失效
                // trace("[ConditionComponent] 条件不满足，Buff失效");
                return false;
            }
        }

        // 条件满足或未到检查时间，继续存活
        return true;
    }

    /**
     * [Phase 0 契约] 条件组件是门控组件
     * 条件不满足时必须终结宿主Buff
     */
    public function isLifeGate():Boolean {
        return true;
    }
}
