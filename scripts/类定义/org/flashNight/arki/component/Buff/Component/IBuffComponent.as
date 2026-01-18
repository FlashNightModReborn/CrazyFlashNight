import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
// IBuffComponent.as
interface org.flashNight.arki.component.Buff.Component.IBuffComponent {
    /**
     * 组件随帧推进
     * @return Boolean 是否仍存活；false 表示应从宿主 Buff 卸载
     */
    function update(host:IBuff, deltaFrames:Number):Boolean;

    /** 当组件挂载到宿主时调用 */
    function onAttach(host:IBuff):Void;

    /** 当组件卸载时调用 */
    function onDetach():Void;

    /**
     * [Phase 0 契约] 是否为生命周期门控组件
     *
     * - true: 门控组件（AND语义），组件update()返回false会导致宿主Buff失活
     *         例：TimeLimitComponent, TickComponent(有maxTicks), ConditionComponent, StackLimitComponent
     * - false: 非门控组件（不影响宿主生死），仅提供辅助功能
     *         例：CooldownComponent（管理就绪状态，不控制Buff生死）
     *
     * 默认实现应返回true以保持向后兼容（原OR语义下所有组件都影响生死）
     */
    function isLifeGate():Boolean;
}
