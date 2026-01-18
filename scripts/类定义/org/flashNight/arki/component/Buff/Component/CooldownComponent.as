// CooldownComponent.as - 冷却时间组件
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * 冷却时间组件
 *
 * 用途：管理技能/Buff的冷却时间
 *
 * 使用场景：
 * - 主动技能冷却(兴奋剂冷却2秒、铁布衫冷却5秒)
 * - 被动效果内置CD(暴击后3秒内不再暴击)
 * - 装备主动技能冷却
 *
 * 工作模式：
 * 1. 初始状态为就绪(ready)
 * 2. 调用tryActivate()后进入冷却状态
 * 3. 冷却时间结束后自动回到就绪状态
 *
 * 示例:
 *   // 兴奋剂技能: 持续3秒，冷却2秒
 *   // 注意：CooldownComponent 持久保存在技能管理器中，MetaBuff 每次新建
 *   var cooldownComp:CooldownComponent = new CooldownComponent(60); // 冷却60帧
 *
 *   // 玩家按键时
 *   if (cooldownComp.tryActivate()) {
 *       // 每次激活都创建新的 MetaBuff 实例（因为销毁后不可复用）
 *       var speedBuffs:Array = [
 *           new PodBuff("moveSpeed", BuffCalculationType.PERCENT, 0.5)
 *       ];
 *       var timeLimitComp:TimeLimitComponent = new TimeLimitComponent(90); // 持续90帧
 *       var skillBuff:MetaBuff = new MetaBuff(speedBuffs, [timeLimitComp], 0);
 *       unit.buffManager.addBuff(skillBuff, "skill_stimulant");
 *   } else {
 *       trace("技能冷却中，剩余: " + cooldownComp.getRemainingFrames() + "帧");
 *   }
 *
 *   // 冷却组件独立于 MetaBuff 存活，在业务层保持引用并驱动 update
 *   cooldownComp.update(null, deltaFrames); // 每帧更新冷却状态
 */
class org.flashNight.arki.component.Buff.Component.CooldownComponent
    implements IBuffComponent
{
    private var _cooldownFrames:Number;    // 冷却总时长(帧)
    private var _remainingFrames:Number;   // 剩余冷却时间(帧)
    private var _isReady:Boolean;          // 是否就绪
    private var _autoReset:Boolean;        // 冷却结束后是否自动重置为就绪

    /**
     * 构造函数
     * @param cooldownFrames 冷却时长(帧数)，例如60帧=2秒@30fps
     * @param startReady 初始是否就绪，默认true
     * @param autoReset 冷却结束后是否自动重置，默认true
     */
    public function CooldownComponent(cooldownFrames:Number, startReady:Boolean, autoReset:Boolean) {
        _cooldownFrames = cooldownFrames > 0 ? cooldownFrames : 1;
        _isReady = (startReady != undefined) ? startReady : true;
        _autoReset = (autoReset != undefined) ? autoReset : true;
        _remainingFrames = _isReady ? 0 : _cooldownFrames;
    }

    /**
     * 尝试激活(使用技能/触发效果)
     * @return Boolean 是否成功激活(false表示冷却中)
     */
    public function tryActivate():Boolean {
        if (_isReady) {
            _isReady = false;
            _remainingFrames = _cooldownFrames;
            return true;
        }
        return false;
    }

    /**
     * 强制进入冷却状态
     */
    public function startCooldown():Void {
        _isReady = false;
        _remainingFrames = _cooldownFrames;
    }

    /**
     * 立即重置冷却(技能刷新)
     */
    public function resetCooldown():Void {
        _isReady = true;
        _remainingFrames = 0;
    }

    /**
     * 减少冷却时间(冷却缩减)
     * @param frames 减少的帧数
     */
    public function reduceCooldown(frames:Number):Void {
        if (!_isReady && frames > 0) {
            _remainingFrames -= frames;
            if (_remainingFrames <= 0) {
                _remainingFrames = 0;
                if (_autoReset) {
                    _isReady = true;
                }
            }
        }
    }

    /**
     * 检查是否就绪
     */
    public function isReady():Boolean {
        return _isReady;
    }

    /**
     * 获取剩余冷却时间(帧)
     */
    public function getRemainingFrames():Number {
        return _remainingFrames;
    }

    /**
     * 获取剩余冷却时间(秒，假设30fps)
     */
    public function getRemainingSeconds():Number {
        return _remainingFrames / 30;
    }

    /**
     * 获取冷却进度(0.0-1.0)
     */
    public function getCooldownProgress():Number {
        if (_cooldownFrames <= 0) return 1.0;
        return Math.max(0, Math.min(1, 1 - (_remainingFrames / _cooldownFrames)));
    }

    /**
     * 获取总冷却时长
     */
    public function getCooldownFrames():Number {
        return _cooldownFrames;
    }

    /**
     * 设置新的冷却时长(不影响当前冷却状态)
     */
    public function setCooldownFrames(frames:Number):Void {
        if (frames > 0) {
            _cooldownFrames = frames;
        }
    }

    public function onAttach(host:IBuff):Void {
        // 可记录附加时间
    }

    public function onDetach():Void {
        // 清理
    }

    /**
     * 更新组件
     * @param host 宿主Buff
     * @param deltaFrames 增量帧数
     * @return Boolean 始终返回true(冷却组件不自动销毁宿主)
     */
    public function update(host:IBuff, deltaFrames:Number):Boolean {
        if (!_isReady && _remainingFrames > 0) {
            _remainingFrames -= deltaFrames;

            if (_remainingFrames <= 0) {
                _remainingFrames = 0;
                if (_autoReset) {
                    _isReady = true;
                    // trace("[CooldownComponent] 冷却完成，已就绪");
                }
            }
        }

        // 冷却组件不销毁宿主Buff，只管理就绪状态
        return true;
    }

    /**
     * [Phase 0 契约] 冷却组件不是门控组件
     * 它只管理就绪状态，不控制宿主Buff的生死
     */
    public function isLifeGate():Boolean {
        return false;
    }
}
