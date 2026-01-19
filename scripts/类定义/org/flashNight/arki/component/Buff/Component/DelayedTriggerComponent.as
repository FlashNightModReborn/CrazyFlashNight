/**
 * DelayedTriggerComponent - 延迟触发组件（一次性）
 *
 * TickComponent 的轻量级替代品，适用于只需要执行一次回调的场景。
 * 在指定帧数后触发回调，然后根据配置决定是否终结宿主Buff。
 *
 * 对比 TickComponent：
 * ┌─────────────────────┬──────────────────┬─────────────────────┐
 * │ 特性                 │ DelayedTrigger   │ TickComponent       │
 * ├─────────────────────┼──────────────────┼─────────────────────┤
 * │ 触发次数             │ 1次              │ 多次（可配置）       │
 * │ 内存占用             │ 4个字段          │ 7个字段              │
 * │ 计数器逻辑           │ 无               │ 有（while循环）      │
 * │ 适用场景             │ 延迟效果、定时炸弹 │ DoT、HoT、周期效果   │
 * └─────────────────────┴──────────────────┴─────────────────────┘
 *
 * 使用场景：
 * - 延迟爆炸：X帧后造成伤害
 * - 延迟触发：X帧后激活某个效果
 * - 定时清理：X帧后移除buff并执行清理逻辑
 *
 * 示例:
 *   // 60帧后爆炸，造成100伤害，然后移除buff
 *   var delayComp:DelayedTriggerComponent = new DelayedTriggerComponent(
 *       60,
 *       function(host:IBuff, ctx:Object):Void {
 *           ctx.target.hp -= ctx.damage;
 *       },
 *       {target: enemy, damage: 100},
 *       true  // 触发后终结buff
 *   );
 *
 * @author FlashNight
 * @version 1.0
 */
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.component.Buff.Component.DelayedTriggerComponent implements IBuffComponent {

    private var _delay:Number;         // 延迟帧数
    private var _remaining:Number;     // 剩余帧数
    private var _onTrigger:Function;   // 触发回调 function(host:IBuff, context:Object):Void
    private var _context:Object;       // 回调上下文
    private var _isGate:Boolean;       // 是否为门控组件
    private var _triggered:Boolean;    // 是否已触发

    /**
     * 构造函数
     *
     * @param delay      延迟帧数（触发前等待的帧数）
     * @param onTrigger  触发回调 function(host:IBuff, context:Object):Void
     * @param context    回调上下文（可选）
     * @param isGate     是否为门控组件（默认true，触发后终结buff）
     */
    public function DelayedTriggerComponent(
        delay:Number,
        onTrigger:Function,
        context:Object,
        isGate:Boolean
    ) {
        _delay = (delay > 0) ? delay : 1;
        _remaining = _delay;
        _onTrigger = onTrigger;
        _context = context || {};
        _isGate = (isGate !== false); // 默认为true
        _triggered = false;
    }

    /**
     * 组件挂载时调用
     */
    public function onAttach(host:IBuff):Void {
        // 无需特殊处理
    }

    /**
     * 组件卸载时调用
     */
    public function onDetach():Void {
        _onTrigger = null;
        _context = null;
    }

    /**
     * 更新组件
     *
     * @param host        宿主Buff
     * @param deltaFrames 增量帧数
     * @return Boolean    组件是否继续存活
     */
    public function update(host:IBuff, deltaFrames:Number):Boolean {
        // 已触发则直接返回（根据门控设置）
        if (_triggered) {
            return !_isGate;
        }

        _remaining -= deltaFrames;

        // 检查是否到达触发时机
        if (_remaining <= 0) {
            _triggered = true;

            // 执行回调
            if (_onTrigger != null) {
                _onTrigger(host, _context);
            }

            // 门控组件返回false终结buff，非门控返回true继续存活
            return !_isGate;
        }

        return true;
    }

    // ========================================
    // 访问器方法
    // ========================================

    /**
     * 获取是否已触发
     */
    public function hasTriggered():Boolean {
        return _triggered;
    }

    /**
     * 获取剩余帧数
     */
    public function getRemaining():Number {
        return _remaining;
    }

    /**
     * 获取配置的延迟帧数
     */
    public function getDelay():Number {
        return _delay;
    }

    /**
     * 获取上下文对象
     */
    public function getContext():Object {
        return _context;
    }

    /**
     * 更新上下文
     */
    public function updateContext(key:String, value):Void {
        if (_context) {
            _context[key] = value;
        }
    }

    /**
     * 重置组件（允许重新触发）
     */
    public function reset():Void {
        _remaining = _delay;
        _triggered = false;
    }

    /**
     * 立即触发（跳过剩余延迟）
     * @return Boolean 是否成功触发（已触发过则返回false）
     */
    public function triggerNow(host:IBuff):Boolean {
        if (_triggered) {
            return false;
        }

        _triggered = true;
        _remaining = 0;

        if (_onTrigger != null) {
            _onTrigger(host, _context);
        }

        return true;
    }

    /**
     * 获取进度百分比 (0.0 ~ 1.0)
     */
    public function getProgress():Number {
        if (_delay <= 0) return 1;
        return 1 - (_remaining / _delay);
    }

    /**
     * [Phase 0 契约] 门控行为由构造参数决定
     */
    public function isLifeGate():Boolean {
        return _isGate;
    }
}
