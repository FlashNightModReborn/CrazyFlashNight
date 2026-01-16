/**
 * TickComponent - 周期触发组件
 *
 * 在指定的时间间隔内周期性触发回调函数。
 * 适用于持续恢复(HoT)、持续伤害(DoT)、周期性效果等场景。
 *
 * 使用场景：
 * - 缓释恢复：每秒恢复一定HP/MP
 * - 持续伤害：每秒造成毒素伤害
 * - 周期性触发：定时刷新某种状态
 *
 * 工作模式：
 * 1. 每帧累加计数器
 * 2. 达到间隔时触发回调
 * 3. 支持最大触发次数限制
 *
 * 示例:
 *   // 每30帧恢复10HP，无限次（由TimeLimitComponent控制结束）
 *   var tickComp:TickComponent = new TickComponent(
 *       30,
 *       function(host:IBuff, tickNum:Number, ctx:Object):Void {
 *           ctx.target.hp += 10;
 *       },
 *       0,
 *       {target: unit}
 *   );
 *
 * @author FlashNight
 * @version 1.0
 */
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.component.Buff.Component.TickComponent implements IBuffComponent {

    private var _interval:Number;      // tick 间隔（帧）
    private var _counter:Number;       // 帧计数器
    private var _tickCount:Number;     // 已触发次数
    private var _maxTicks:Number;      // 最大触发次数（0=无限）
    private var _onTick:Function;      // tick 回调 function(host:IBuff, tickCount:Number, context:Object):Void
    private var _context:Object;       // 回调上下文
    private var _triggerOnAttach:Boolean; // 是否在挂载时立即触发一次

    /**
     * 构造函数
     *
     * @param interval        触发间隔（帧数），默认30帧≈1秒
     * @param onTick          回调函数 function(host:IBuff, tickCount:Number, context:Object):Void
     * @param maxTicks        最大触发次数（0或不填=无限，由其他组件控制结束）
     * @param context         回调上下文（可选，用于携带额外数据如target、恢复量等）
     * @param triggerOnAttach 是否在挂载时立即触发一次（默认false）
     */
    public function TickComponent(
        interval:Number,
        onTick:Function,
        maxTicks:Number,
        context:Object,
        triggerOnAttach:Boolean
    ) {
        _interval = (interval > 0) ? interval : 30;
        _onTick = onTick;
        _maxTicks = (maxTicks > 0) ? maxTicks : 0;
        _context = context || {};
        _triggerOnAttach = (triggerOnAttach == true);
        _counter = 0;
        _tickCount = 0;
    }

    /**
     * 组件挂载时调用
     */
    public function onAttach(host:IBuff):Void {
        if (_triggerOnAttach && _onTick != null) {
            _tickCount++;
            _onTick(host, _tickCount, _context);

            // 检查首次触发后是否已达上限
            if (_maxTicks > 0 && _tickCount >= _maxTicks) {
                // 标记为已完成，下次update会返回false
                _counter = -1;
            }
        }
    }

    /**
     * 组件卸载时调用
     */
    public function onDetach():Void {
        _onTick = null;
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
        // 如果已标记完成
        if (_counter < 0) {
            return false;
        }

        _counter += deltaFrames;

        // 支持一帧内触发多次（处理大deltaFrames或小interval的情况）
        while (_counter >= _interval) {
            _counter -= _interval;
            _tickCount++;

            // 触发回调
            if (_onTick != null) {
                _onTick(host, _tickCount, _context);
            }

            // 检查是否达到最大次数
            if (_maxTicks > 0 && _tickCount >= _maxTicks) {
                return false; // 组件结束
            }
        }

        return true; // 继续存活
    }

    // ========================================
    // 访问器方法
    // ========================================

    /**
     * 获取已触发次数
     */
    public function getTickCount():Number {
        return _tickCount;
    }

    /**
     * 获取触发间隔
     */
    public function getInterval():Number {
        return _interval;
    }

    /**
     * 设置触发间隔（运行时调整）
     */
    public function setInterval(interval:Number):Void {
        if (interval > 0) {
            _interval = interval;
        }
    }

    /**
     * 获取最大触发次数
     */
    public function getMaxTicks():Number {
        return _maxTicks;
    }

    /**
     * 获取上下文对象
     */
    public function getContext():Object {
        return _context;
    }

    /**
     * 更新上下文（运行时调整）
     */
    public function updateContext(key:String, value):Void {
        if (_context) {
            _context[key] = value;
        }
    }

    /**
     * 重置计数器（用于刷新效果）
     */
    public function reset():Void {
        _counter = 0;
        _tickCount = 0;
    }

    /**
     * 获取剩余触发次数（仅当maxTicks>0时有意义）
     */
    public function getRemainingTicks():Number {
        if (_maxTicks <= 0) return -1; // 无限
        return _maxTicks - _tickCount;
    }
}
