import org.flashNight.arki.component.Shield.*;

/**
 * 护盾函数模块
 *
 * 提供资产文件可调用的护盾系统API，封装在 _root.护盾函数 对象下。
 *
 * 【设计目的】
 * 由于资产文件（XML）无法直接 import 类，需要通过 _root 上的函数来访问护盾系统。
 * 将所有护盾相关函数封装在 _root.护盾函数 对象下，降低 _root 级索引压力。
 *
 * 【使用示例】
 * // 在资产脚本中添加临时护盾
 * _root.护盾函数.添加临时护盾(_parent, 护盾容量, Infinity, -1, "技能护盾", {
 *     onBreak: function(shield) {
 *         // 护盾破碎时的回调
 *     }
 * });
 *
 * 【边界行为说明】
 * 新系统与原始护盾系统的主要差异：
 * - 原系统：护盾吸收后直接返回NaN阻止所有伤害，即使护盾容量不足也完全免伤
 * - 新系统：护盾按容量吸收，容量不足时剩余伤害会穿透到HP
 * 这个取舍使护盾行为更符合直觉，且与其他护盾类型保持一致。
 */

// 初始化护盾函数命名空间
_root.护盾函数 = {};

// ==================== 核心护盾操作 ====================

/**
 * 添加临时护盾（无充能，一次性）
 *
 * @param target 目标单位
 * @param capacity 护盾容量
 * @param strength 护盾强度（每次可挡最大伤害，Infinity表示无限制）
 * @param duration 持续帧数（-1表示永久，直到破碎）
 * @param name 护盾名称
 * @param callbacks 回调对象 {onBreak, onHit, onExpire}
 * @return 护盾ID（用于移除），失败返回-1
 */
_root.护盾函数.添加临时护盾 = function(target:Object, capacity:Number, strength:Number,
                                      duration:Number, name:String, callbacks:Object):Number {
    if (!target || !target.shield) return -1;

    // 处理默认值
    if (capacity == undefined || isNaN(capacity) || capacity <= 0) return -1;
    if (strength == undefined || isNaN(strength)) strength = Infinity;
    if (duration == undefined) duration = -1;
    if (name == undefined || name == null) name = "临时护盾";

    // 创建护盾
    var shield:Shield = Shield.createTemporary(capacity, strength, duration, name);

    // 设置回调
    if (callbacks != null) {
        if (callbacks.onBreak != undefined) shield.onBreakCallback = callbacks.onBreak;
        if (callbacks.onHit != undefined) shield.onHitCallback = callbacks.onHit;
        if (callbacks.onExpire != undefined) {
            // 过期回调需要在容器级别处理
            var existingExpire:Function = target.shield.onExpireCallback;
            target.shield.onExpireCallback = function(s:IShield):Void {
                callbacks.onExpire(s);
                if (existingExpire != null) existingExpire(s);
            };
        }
    }

    // 添加到单位护盾容器
    target.shield.addShield(shield);

    return shield.getId();
};

/**
 * 添加可充能护盾
 *
 * @param target 目标单位
 * @param capacity 护盾容量
 * @param strength 护盾强度
 * @param rechargeRate 充能速度（每帧）
 * @param rechargeDelay 充能延迟（帧数）
 * @param name 护盾名称
 * @param callbacks 回调对象 {onBreak, onHit, onRechargeStart, onRechargeFull}
 * @return 护盾ID，失败返回-1
 */
_root.护盾函数.添加充能护盾 = function(target:Object, capacity:Number, strength:Number,
                                      rechargeRate:Number, rechargeDelay:Number,
                                      name:String, callbacks:Object):Number {
    if (!target || !target.shield) return -1;

    // 处理默认值
    if (capacity == undefined || isNaN(capacity) || capacity <= 0) return -1;
    if (strength == undefined || isNaN(strength)) strength = Infinity;
    if (rechargeRate == undefined || isNaN(rechargeRate)) rechargeRate = 0;
    if (rechargeDelay == undefined || isNaN(rechargeDelay)) rechargeDelay = 0;
    if (name == undefined || name == null) name = "充能护盾";

    // 创建护盾
    var shield:Shield = Shield.createRechargeable(capacity, strength, rechargeRate, rechargeDelay, name);

    // 设置回调
    if (callbacks != null) {
        if (callbacks.onBreak != undefined) shield.onBreakCallback = callbacks.onBreak;
        if (callbacks.onHit != undefined) shield.onHitCallback = callbacks.onHit;
        if (callbacks.onRechargeStart != undefined) shield.onRechargeStartCallback = callbacks.onRechargeStart;
        if (callbacks.onRechargeFull != undefined) shield.onRechargeFullCallback = callbacks.onRechargeFull;
    }

    // 添加到单位护盾容器
    target.shield.addShield(shield);

    return shield.getId();
};

/**
 * 添加衰减护盾（随时间自动衰减）
 *
 * @param target 目标单位
 * @param capacity 护盾容量
 * @param strength 护盾强度
 * @param decayRate 衰减速度（每帧，正数会自动转为负数）
 * @param name 护盾名称
 * @param callbacks 回调对象 {onBreak, onHit}
 * @return 护盾ID，失败返回-1
 */
_root.护盾函数.添加衰减护盾 = function(target:Object, capacity:Number, strength:Number,
                                      decayRate:Number, name:String, callbacks:Object):Number {
    if (!target || !target.shield) return -1;

    // 处理默认值
    if (capacity == undefined || isNaN(capacity) || capacity <= 0) return -1;
    if (strength == undefined || isNaN(strength)) strength = Infinity;
    if (decayRate == undefined || isNaN(decayRate)) decayRate = 1;
    if (name == undefined || name == null) name = "衰减护盾";

    // 创建护盾
    var shield:Shield = Shield.createDecaying(capacity, strength, decayRate, name);

    // 设置回调
    if (callbacks != null) {
        if (callbacks.onBreak != undefined) shield.onBreakCallback = callbacks.onBreak;
        if (callbacks.onHit != undefined) shield.onHitCallback = callbacks.onHit;
    }

    // 添加到单位护盾容器
    target.shield.addShield(shield);

    return shield.getId();
};

/**
 * 添加抗真伤护盾（可抵抗真实伤害）
 *
 * @param target 目标单位
 * @param capacity 护盾容量
 * @param strength 护盾强度
 * @param duration 持续帧数（-1表示永久）
 * @param name 护盾名称
 * @param callbacks 回调对象
 * @return 护盾ID，失败返回-1
 */
_root.护盾函数.添加抗真伤护盾 = function(target:Object, capacity:Number, strength:Number,
                                        duration:Number, name:String, callbacks:Object):Number {
    if (!target || !target.shield) return -1;

    // 处理默认值
    if (capacity == undefined || isNaN(capacity) || capacity <= 0) return -1;
    if (strength == undefined || isNaN(strength)) strength = Infinity;
    if (duration == undefined) duration = -1;
    if (name == undefined || name == null) name = "抗真伤护盾";

    // 创建护盾
    var shield:Shield = Shield.createResistant(capacity, strength, duration, name);

    // 设置回调
    if (callbacks != null) {
        if (callbacks.onBreak != undefined) shield.onBreakCallback = callbacks.onBreak;
        if (callbacks.onHit != undefined) shield.onHitCallback = callbacks.onHit;
    }

    // 添加到单位护盾容器
    target.shield.addShield(shield);

    return shield.getId();
};

// ==================== 护盾查询与管理 ====================

/**
 * 移除指定ID的护盾
 *
 * @param target 目标单位
 * @param shieldId 护盾ID
 * @return 是否成功移除
 */
_root.护盾函数.移除护盾 = function(target:Object, shieldId:Number):Boolean {
    if (!target || !target.shield) return false;
    return target.shield.removeShieldById(shieldId);
};

/**
 * 清空单位所有护盾
 *
 * @param target 目标单位
 */
_root.护盾函数.清空护盾 = function(target:Object):Void {
    if (target && target.shield) {
        target.shield.clear();
    }
};

/**
 * 获取单位当前护盾容量
 *
 * @param target 目标单位
 * @return 当前总护盾容量
 */
_root.护盾函数.获取护盾容量 = function(target:Object):Number {
    if (!target || !target.shield) return 0;
    return target.shield.getCapacity();
};

/**
 * 获取单位护盾最大容量
 *
 * @param target 目标单位
 * @return 最大总护盾容量
 */
_root.护盾函数.获取护盾最大容量 = function(target:Object):Number {
    if (!target || !target.shield) return 0;
    return target.shield.getMaxCapacity();
};

/**
 * 获取单位护盾强度
 *
 * @param target 目标单位
 * @return 当前护盾强度（最外层护盾的强度）
 */
_root.护盾函数.获取护盾强度 = function(target:Object):Number {
    if (!target || !target.shield) return 0;
    return target.shield.getStrength();
};

/**
 * 检查单位是否有护盾
 *
 * @param target 目标单位
 * @return 是否有有效护盾（容量>0）
 */
_root.护盾函数.有护盾 = function(target:Object):Boolean {
    if (!target || !target.shield) return false;
    return !target.shield.isEmpty();
};

/**
 * 获取单位护盾层数
 *
 * @param target 目标单位
 * @return 当前护盾层数
 */
_root.护盾函数.获取护盾层数 = function(target:Object):Number {
    if (!target || !target.shield) return 0;
    return target.shield.getShieldCount();
};

/**
 * 检查单位是否有抗真伤护盾
 *
 * @param target 目标单位
 * @return 是否有抗真伤护盾
 */
_root.护盾函数.有抗真伤护盾 = function(target:Object):Boolean {
    if (!target || !target.shield) return false;
    return target.shield.getResistantCount() > 0;
};

// ==================== 便捷方法 ====================

/**
 * 为单位设置护盾破碎全局回调
 * 当任意护盾破碎时触发
 *
 * @param target 目标单位
 * @param callback 回调函数 function(shield:IShield):Void
 */
_root.护盾函数.设置破碎回调 = function(target:Object, callback:Function):Void {
    if (target && target.shield) {
        target.shield.onBreakCallback = callback;
    }
};

/**
 * 为单位设置护盾全部耗尽回调
 * 当所有护盾都耗尽时触发
 *
 * @param target 目标单位
 * @param callback 回调函数 function(shield:AdaptiveShield):Void
 */
_root.护盾函数.设置耗尽回调 = function(target:Object, callback:Function):Void {
    if (target && target.shield) {
        target.shield.onAllShieldsDepletedCallback = callback;
    }
};

