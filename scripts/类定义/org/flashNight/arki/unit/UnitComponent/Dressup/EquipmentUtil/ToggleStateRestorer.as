/**
 * ToggleStateRestorer - 通用变形装备 toggle 状态恢复 helper
 *
 * 装备生命周期初始化的【4】块固定逻辑：根据 item.value 持久化值
 * 决定是恢复完成态、还是首次预设切换、还是不做任何事。
 *
 * 三分支语义：
 *   1. 持久化分支：value 中 toggleProperty 有值 → 瞬时恢复完成态
 *      （写 currentFrame / 实例标签 / 自机 toggle 属性 / gotoAndStop），return true
 *   2. 预设分支：value 无记录但 updateloadExecution > 0 → 执行预设切换次数，return false
 *   3. 都不满足 → 不做任何事，return false
 *
 * Boolean 返回让调用方区分恢复 vs 首次初始化，便于后续覆盖默认帧、
 * 调度初始化副作用、或做单元测试断言。
 */
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.WeaponAnimationTarget;

class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.ToggleStateRestorer {

    public static function restore(反射对象:Object, 参数对象:Object):Boolean {
        var _wv:Object = 反射对象.自机[反射对象.装备类型].value;
        var _tfp:Object = 参数对象.updateFuncParam ? 参数对象.updateFuncParam.triggerFuncParam : undefined;
        if (_tfp && _wv[_tfp.toggleProperty] != undefined) {
            反射对象.自机[_tfp.toggleProperty] = _wv[_tfp.toggleProperty];
            if (_tfp.toggleInstanceLabel != undefined) {
                反射对象[_tfp.toggleInstanceLabel] = _wv[_tfp.toggleProperty]
                    ? _tfp.trueInstance : _tfp.falseInstance;
            }
            反射对象.currentFrame = _wv[_tfp.toggleProperty]
                ? 反射对象.animationDuration : 1;
            var _tgt:MovieClip = WeaponAnimationTarget.resolve(反射对象);
            _tgt.gotoAndStop(反射对象.currentFrame);
            return true;
        } else if (参数对象.updateloadExecution) {
            for (var i:Number = Number(参数对象.updateloadExecution); i > 0; i--) {
                _root.装备生命周期函数[参数对象.updateFuncParam.triggerFunc](反射对象, 参数对象.updateFuncParam.triggerFuncParam);
            }
        }
        return false;
    }
}