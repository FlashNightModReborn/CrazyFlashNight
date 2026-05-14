/**
 * EffectFunctionResolver - 字符串路径 → Function 引用解析 helper
 *
 * 装备 XML 把 paramObj.func 写成字符串路径（如 "_root.刀口触发特效.十文字大剑特效"），
 * 运行时需要 eval 成可调用 Function 写入 reflector.func。
 *
 * defaultPath 由调用方外参化，避免在工具内硬编码具体武器的特效路径。
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EffectFunctionResolver {

    public static function byString(path:String, defaultPath:String):Function {
        var s:String = (path != undefined) ? path : defaultPath;
        return eval(s);
    }
}