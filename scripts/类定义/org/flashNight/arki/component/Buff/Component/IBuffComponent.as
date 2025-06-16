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
}
