// File: org/flashNight/arki/unit/Action/Shoot/WeaponFireCore.as
import org.flashNight.arki.unit.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Event.*;

/**
 * @class WeaponFireCore
 * @description 武器射击核心类
 * 
 * 该类采用策略模式实现了对不同武器类型射击逻辑的统一处理，
 * 减少了代码重复，提高了可维护性，同时保持了良好的性能表现。
 * 
 * 主要功能：
 * 1. 统一处理不同武器类型的射击逻辑
 * 2. 处理子弹散射度计算
 * 3. 处理自动瞄准逻辑（仅长枪支持）
 * 4. 弹药管理
 * 5. 提供射击函数工厂方法，减少重复代码
 * 
 */
class org.flashNight.arki.unit.Action.Shoot.WeaponFireCore {
    
    public static var LONG_GUN_SHOOT:Function   = createWeaponFireFunction("长枪");
    public static var PISTOL_SHOOT:Function     = createWeaponFireFunction("手枪");
    public static var PISTOL2_SHOOT:Function    = createWeaponFireFunction("手枪2");


    /**
     * 创建武器射击函数的工厂方法
     * 
     * 该方法是一个高阶函数，接受武器类型参数，返回一个预先绑定该武器类型的射击函数。
     * 通过使用函数工厂模式，我们可以：
     * 1. 减少重复代码，提高代码的可维护性
     * 2. 直接赋值给武器射击函数，避免额外的包装函数
     * 3. 在返回的函数中保持正确的上下文（this引用）
     * 
     * @param weaponType 武器类型字符串，如"长枪"、"手枪"或"手枪2"
     * 
     * @return Function 返回一个接受枪口位置和子弹属性的函数
     */
    public static function createWeaponFireFunction(weaponType:String):Function {
        return function(muzzlePosition:MovieClip, bulletProps:Object):Boolean {
            // 这里的'this'在调用时会指向函数的拥有者（例如，_root.主角函数）
            return WeaponFireCore.executeShot(this, weaponType, muzzlePosition, bulletProps);
        };
    }
    
    /**
     * 执行武器射击的核心方法
     * 
     * 该方法是策略模式的主入口，根据传入的武器类型参数执行对应的射击逻辑。
     * 它将处理通用的射击流程：弹药检查、弹药计数增加、枪口位置刷新、
     * 散射度设置、自动瞄准应用，以及最终的子弹发射。
     * 
     * @param owner 武器拥有者对象（通常是玩家角色或NPC）
     * @param weaponType 武器类型字符串，如"长枪"、"手枪"或"手枪2"
     * @param muzzlePosition 枪口位置的MovieClip对象
     * @param bulletProps 子弹属性对象，包含速度、散射度等参数
     * 
     * @return Boolean 射击是否成功执行（弹药不足时返回false）
     */
    public static function executeShot(owner, weaponType:String, muzzlePosition:MovieClip, bulletProps:Object):Boolean {
        // 获取当前武器的弹药信息
        var currentShot:Number = owner[weaponType].value.shot;
        var maxAmmo:Number = owner[weaponType + "弹匣容量"];
        
        // 检查是否有足够的弹药
        if (currentShot >= maxAmmo)
            return false;
        
        var dispatcher:EventDispatcher = owner.dispatcher;

        dispatcher.publish("processShot", owner, weaponType, muzzlePosition, bulletProps);
        
        // 发射子弹
        _root.子弹区域shoot传递(bulletProps);
        
        return true;
    }
    
    /**
     * 应用武器特定的瞄准逻辑
     * 
     * 该方法根据武器类型应用不同的瞄准策略。目前只有长枪支持自动瞄准功能。
     * 自动瞄准时，会计算从射击位置到目标之间的弹道轨迹，并设置相应的速度参数。
     * 
     * @param owner 武器拥有者对象
     * @param weaponType 武器类型字符串
     * @param bulletProps 子弹属性对象
     * 
     * @return Void
     */
    public static function applyAimingLogic(owner, weaponType:String, bulletProps:Object):Void {
        // 只有长枪且处于自瞄模式时才应用自动瞄准逻辑
        if (weaponType == "长枪" && owner.自瞄中) {
            var target = _root.gameworld[owner.攻击目标];
            
            if (target.hp > 0) {
                // 计算到目标的轨迹
                var distX:Number = target._x - bulletProps.shootX;
                var defaultHeight:Number = UnitUtil.calculateCenterOffset(target);
                var distY:Number = target._y - defaultHeight - bulletProps.shootY;
                var distZ:Number = target.Z轴坐标 - bulletProps.shootZ;
                
                // 计算水平速度，保持子弹速度恒定
                var speedX:Number = distX >= 0 ? bulletProps.子弹速度 : -bulletProps.子弹速度;
                var speedY:Number = speedX * distY / distX;
                
                // 限制垂直速度，确保不超过子弹速度上限
                // 如果垂直速度超限，则重新计算水平速度
                if (speedY > bulletProps.子弹速度 || speedY < -bulletProps.子弹速度) {
                    speedY = speedY >= 0 ? bulletProps.子弹速度 : -bulletProps.子弹速度;
                    speedX = speedY * distX / distY;
                }
                
                // 设置子弹速度和Z轴比例参数
                bulletProps.速度X = speedX;
                bulletProps.速度Y = speedY;
                bulletProps.ZY比例 = target.Z轴坐标 / (target._y - defaultHeight);
            } else {
                // 目标已死亡，重置瞄准属性
                resetAimingProperties(bulletProps);
            }
        } else {
            // 非长枪或未开启自瞄，重置瞄准属性
            resetAimingProperties(bulletProps);
        }
    }
    
    /**
     * 重置瞄准属性
     * 
     * 当不需要自动瞄准时，将子弹的自动瞄准相关属性重置为undefined，
     * 使子弹按默认散射规则飞行。
     * 
     * @param bulletProps 子弹属性对象
     * 
     * @return Void
     */
    private static function resetAimingProperties(bulletProps:Object):Void {
        bulletProps.速度X = undefined;
        bulletProps.速度Y = undefined;
        bulletProps.ZY比例 = undefined;
    }

    public static var position:Vector = new Vector(null)

    /**
     * 更新枪口位置
     * 
     * 该方法将枪口局部坐标转换为游戏世界坐标，并更新子弹发射属性。
     * 原先位于角色函数中，现移入核心类以提高代码内聚性。
     * 
     * @param owner 武器拥有者对象（玩家角色或NPC）
     * @param muzzlePosition 枪口位置的MovieClip对象
     * @param bulletProps 子弹属性对象
     * 
     * @return Void
     */
    public static function updateMuzzlePosition(owner, muzzlePosition:MovieClip, bulletProps:Object):Void {
        if (isNaN(muzzlePosition._x)) return;
        
        var myPoint:Vector = position;

        myPoint.x = muzzlePosition._x;
        myPoint.y = muzzlePosition._y

        muzzlePosition._parent.localToGlobal(myPoint); 
        _root.gameworld.globalToLocal(myPoint); 
        
        bulletProps.shootX = myPoint.x; 
        bulletProps.shootY = myPoint.y; 
        bulletProps.shootZ = owner.Z轴坐标;
    }
}