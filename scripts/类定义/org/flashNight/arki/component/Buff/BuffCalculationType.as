// org/flashNight/arki/component/Buff/BuffCalculationType.as
class org.flashNight.arki.component.Buff.BuffCalculationType {
    public static var ADD:String = "add";           // 加算: base + value
    public static var MULTIPLY:String = "multiply"; // 乘算: base * value  
    public static var PERCENT:String = "percent";   // 百分比: base * (1 + value)
    public static var OVERRIDE:String = "override"; // 覆盖: value
    public static var MAX:String = "max";           // 取最大值: Math.max(base, value)
    public static var MIN:String = "min";           // 取最小值: Math.min(base, value)
}