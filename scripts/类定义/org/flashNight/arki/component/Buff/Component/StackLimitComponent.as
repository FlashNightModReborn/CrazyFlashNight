// StackLimitComponent.as - 可叠加次数限制组件
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * 层数限制组件
 *
 * 用途：控制Buff可叠加的最大层数
 *
 * 使用场景：
 * - 攻击叠加暴击率(最多10层)
 * - DOT层数控制(中毒最多5层)
 * - 装备被动效果叠加(等离子切割机击杀奖励层数)
 *
 * 示例:
 *   var stackComp:StackLimitComponent = new StackLimitComponent(5);
 *   var poisonMeta:MetaBuff = new MetaBuff(childBuffs, [stackComp], 0);
 *
 *   // 每次攻击命中时
 *   if (stackComp.addStack()) {
 *       // 成功叠加层数
 *       trace("当前层数: " + stackComp.getCurrentStacks());
 *   } else {
 *       trace("已达最大层数");
 *   }
 */
class org.flashNight.arki.component.Buff.Component.StackLimitComponent
    implements IBuffComponent
{
    private var _maxStacks:Number;      // 最大层数
    private var _currentStacks:Number;  // 当前层数
    private var _stackDecayFrames:Number; // 层数衰减间隔(0=不衰减)
    private var _decayCounter:Number;   // 衰减计数器

    /**
     * 构造函数
     * @param maxStacks 最大可叠加层数
     * @param stackDecayFrames 层数自然衰减间隔(帧)，0表示不衰减
     */
    public function StackLimitComponent(maxStacks:Number, stackDecayFrames:Number) {
        _maxStacks = maxStacks > 0 ? maxStacks : 1;
        _currentStacks = 1; // 初始1层
        _stackDecayFrames = stackDecayFrames || 0;
        _decayCounter = 0;
    }

    /**
     * 尝试增加层数
     * @return Boolean 是否成功增加(false表示已达上限)
     */
    public function addStack():Boolean {
        if (_currentStacks < _maxStacks) {
            _currentStacks++;
            _resetDecayCounter(); // 重置衰减计时
            return true;
        }
        return false;
    }

    /**
     * 减少层数
     * @param amount 减少的层数，默认1
     * @return Boolean 是否还有剩余层数
     */
    public function removeStack(amount:Number):Boolean {
        if (amount == undefined || amount <= 0) amount = 1;
        _currentStacks -= amount;
        if (_currentStacks <= 0) {
            _currentStacks = 0;
            return false; // 层数耗尽
        }
        return true;
    }

    /**
     * 获取当前层数
     */
    public function getCurrentStacks():Number {
        return _currentStacks;
    }

    /**
     * 获取最大层数
     */
    public function getMaxStacks():Number {
        return _maxStacks;
    }

    /**
     * 设置当前层数(直接设置，不受上限限制用于特殊情况)
     */
    public function setStacks(stacks:Number):Void {
        _currentStacks = Math.max(0, Math.min(stacks, _maxStacks));
    }

    /**
     * 检查是否已满层
     */
    public function isMaxStacks():Boolean {
        return _currentStacks >= _maxStacks;
    }

    /**
     * 重置衰减计时器
     */
    private function _resetDecayCounter():Void {
        _decayCounter = 0;
    }

    public function onAttach(host:IBuff):Void {
        // 可记录初始时间
    }

    public function onDetach():Void {
        // 清理
    }

    /**
     * 更新组件
     * @param host 宿主Buff
     * @param deltaFrames 增量帧数
     * @return Boolean 是否仍存活(层数>0)
     */
    public function update(host:IBuff, deltaFrames:Number):Boolean {
        // 处理层数自然衰减
        if (_stackDecayFrames > 0) {
            _decayCounter += deltaFrames;
            if (_decayCounter >= _stackDecayFrames) {
                _decayCounter = 0;
                if (!removeStack(1)) {
                    return false; // 层数衰减至0，Buff失效
                }
            }
        }

        // 层数大于0则继续存活
        return _currentStacks > 0;
    }
}
