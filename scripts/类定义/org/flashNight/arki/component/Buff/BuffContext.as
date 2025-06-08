// org/flashNight/arki/component/Buff/BuffContext.as
class org.flashNight.arki.component.Buff.BuffContext {
    public var targetObject:Object;    // 目标对象
    public var propertyName:String;    // 属性名
    public var baseValue:Number;       // 基础值
    public var currentTime:Number;     // 当前时间（用于时效性Buff）
    public var gameState:Object;       // 游戏状态（用于条件判断）
    
    public function BuffContext(target:Object, prop:String, base:Number) {
        this.targetObject = target;
        this.propertyName = prop;
        this.baseValue = base;
        this.currentTime = getTimer();
    }
}