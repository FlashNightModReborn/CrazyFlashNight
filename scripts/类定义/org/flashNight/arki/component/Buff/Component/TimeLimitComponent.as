// TimeLimitComponent.as
/**
 * 时间限制组件 - 控制Buff的持续时间
 *
 * 版本历史:
 * v1.1 (2026-01) - 功能增强
 *   [FEAT] 添加暂停/恢复接口 pause()/resume()
 *   [FEAT] 添加剩余时间查询 getRemaining()
 *   [FEAT] 添加时间修改接口 addTime()/setRemaining()
 */
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.component.Buff.Component.TimeLimitComponent
    implements IBuffComponent
{
    private var _remain:Number;          // 剩余帧数
    private var _paused:Boolean;         // [v1.1] 暂停状态

    public function TimeLimitComponent(totalFrames:Number) {
        _remain = totalFrames;
        _paused = false;
    }

    public function onAttach(host:IBuff):Void { /* 可记录开始时间 */ }
    public function onDetach():Void { }

    public function update(host:IBuff, deltaFrames:Number):Boolean {
        // [v1.1] 暂停状态下不消耗时间
        if (!_paused) {
            _remain -= deltaFrames;
        }
        // 到时：通知 BuffManager 移除自身
        return _remain > 0;
    }

    /**
     * [Phase 0 契约] 时间限制是门控组件
     * 时间到期时必须终结宿主Buff
     */
    public function isLifeGate():Boolean {
        return true;
    }

    // =====================================================
    // [v1.1] 暂停/恢复接口
    // =====================================================

    /**
     * 暂停计时
     * 暂停后update不消耗剩余时间
     */
    public function pause():Void {
        _paused = true;
    }

    /**
     * 恢复计时
     */
    public function resume():Void {
        _paused = false;
    }

    /**
     * 检查是否暂停
     */
    public function isPaused():Boolean {
        return _paused;
    }

    // =====================================================
    // [v1.1] 时间查询和修改接口
    // =====================================================

    /**
     * 获取剩余帧数
     */
    public function getRemaining():Number {
        return _remain;
    }

    /**
     * 设置剩余帧数
     * @param frames 新的剩余帧数（负值会被设为0）
     */
    public function setRemaining(frames:Number):Void {
        _remain = (frames > 0) ? frames : 0;
    }

    /**
     * 增加/减少剩余时间
     * @param deltaFrames 帧数变化量（正数延长，负数缩短）
     */
    public function addTime(deltaFrames:Number):Void {
        _remain += deltaFrames;
        if (_remain < 0) _remain = 0;
    }
}
