// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/FireEventComponent.as
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.*;

/**
 * @class FireEventComponent
 * @description 武器开火事件组件
 * 
 * 该组件通过事件机制处理武器开火过程中的各个步骤，
 * 增强了代码的模块化和可维护性。
 * 
 * 主要功能：
 * 1. 初始化单位的开火监听事件
 * 2. 处理增加射击计数
 * 3. 处理枪口位置更新
 * 4. 处理子弹散射度计算
 * 5. 处理自动瞄准逻辑
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent {
    
    /**
     * 初始化单位的开火监听
     * @param target 目标单位(MovieClip)
     */
    public static function initialize(target:MovieClip):Void {
        if(target.兵种 != "主角-男") return;

        var dispatcher:EventDispatcher = target.dispatcher;

        dispatcher.subscribe("processShot", processShot, target);
    }
    
    /**
     * 处理完整的射击流程
     * @param target 目标单位(MovieClip)
     * @param weaponType 武器类型字符串
     * @param muzzlePosition 枪口位置的MovieClip对象
     * @param bulletProps 子弹属性对象
     */
    public static function processShot(target:MovieClip, weaponType:String, muzzlePosition:MovieClip, bulletProps:Object):Void {
        // 增加射击计数
        target[weaponType + "射击次数"][target[weaponType]]++;
        
        // 更新枪口位置
        WeaponFireCore.updateMuzzlePosition(target, muzzlePosition, bulletProps);
        
        // 设置子弹散射度
        bulletProps.子弹散射度 = (target.状态.indexOf('行走') > -1) ? 
            bulletProps.移动子弹散射度 : 
            bulletProps.站立子弹散射度;
        
        // 应用瞄准逻辑
        WeaponFireCore.applyAimingLogic(target, weaponType, bulletProps);
    }
}