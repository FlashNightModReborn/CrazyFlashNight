import org.flashNight.arki.component.Buff.*;
/**
 * 非激活Buff测试辅助类
 * 用于测试PropertyContainer对非激活buff的处理
 */
class org.flashNight.arki.component.Buff.test.InactiveBuff extends PodBuff {
    private var _type:String = "InactiveBuff";
    
    public function InactiveBuff(
        targetProperty:String, 
        calculationType:String,
        value:Number
    ) {
        super(targetProperty, calculationType, value);
    }
    
    public function isActive():Boolean {
        return false; // 始终非激活
    }
    
    public function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void {
        // 非激活buff不应该被调用到这里，但如果被调用了，添加一个明显的值用于检测
        calculator.addModification(BuffCalculationType.ADD, 999);
    }
    
    public function getType():String {
        return this._type;
    }
}