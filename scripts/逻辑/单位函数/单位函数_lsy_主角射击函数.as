import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.*;

/**
 * 单位函数_lsy_主角射击函数.as
 * 
 * 重构后的主角射击相关函数
 * 将原有功能分拆到不同的类中管理：
 * 1. ShootCore - 统一管理射击核心功能
 * 2. ShootInitCore - 管理武器初始化逻辑
 * 3. WeaponStateManager - 管理武器状态判断逻辑
 * 4. ReloadManager - 管理换弹和弹药显示逻辑
 */

// 射击相关函数
// Replace your original shooting methods with these refactored versions
_root.主角函数.长枪射击 = function(枪口位置:MovieClip, 子弹属性:Object) {
    return WeaponFireCore.executeShot(this, "长枪", 枪口位置, 子弹属性);
}

_root.主角函数.手枪射击 = function(枪口位置:MovieClip, 子弹属性:Object) {
    return WeaponFireCore.executeShot(this, "手枪", 枪口位置, 子弹属性);
}

_root.主角函数.手枪2射击 = function(枪口位置:MovieClip, 子弹属性:Object) {
    return WeaponFireCore.executeShot(this, "手枪2", 枪口位置, 子弹属性);
}


// 初始化长枪射击函数
_root.主角函数.初始化长枪射击函数 = function():Void {
    ShootInitCore.initLongGun(this, _parent);
};

// 初始化手枪射击函数
_root.主角函数.初始化手枪射击函数 = function():Void {
    ShootInitCore.initPistol(this, _parent);
};

// 初始化手枪2射击函数
_root.主角函数.初始化手枪2射击函数 = function():Void {
    ShootInitCore.initPistol2(this, _parent);
};

// 初始化双枪射击函数
_root.主角函数.初始化双枪射击函数 = function():Void {
    ShootInitCore.initDualGun(this, _parent);
};