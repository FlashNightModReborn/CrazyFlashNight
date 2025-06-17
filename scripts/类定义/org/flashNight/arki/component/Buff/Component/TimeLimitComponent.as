// TimeLimitComponent.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.component.Buff.Component.TimeLimitComponent
    implements IBuffComponent
{
    private var _remain:Number;          // 剩余帧数
    
    public function TimeLimitComponent(totalFrames:Number) {
        _remain = totalFrames;
    }
    
    public function onAttach(host:IBuff):Void { /* 可记录开始时间 */ }
    public function onDetach():Void { }
    
    public function update(host:IBuff, deltaFrames:Number):Boolean {
        _remain -= deltaFrames;
        // _root.发布消息(_remain)
        // 到时：通知 BuffManager 移除自身
        return _remain > 0;
    }
}
