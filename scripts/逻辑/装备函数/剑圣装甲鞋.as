/**
 * 剑圣装甲鞋 - 装备生命周期函数
 *
 * 功能特性：
 * - 提供行走速度加成buff
 * - 使用buffManager持久化管理，无需周期函数
 *
 * 进阶等级效果：
 * - 无进阶：无速度加成
 * - 二阶：行走速度 +10%
 * - 三阶：行走速度 +12%
 * - 四阶：行走速度 +15%
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数：
 *   - tier_2/tier_3/tier_4: 各进阶等级的配置节点
 *     - speedMultiplier: 速度倍率（二阶1.10，三阶1.12，四阶1.15）
 */
_root.装备生命周期函数.剑圣装甲鞋初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // 获取装备进阶等级
    var equipItem:Object = target[ref.装备类型];
    var tier:String = equipItem && equipItem.value ? equipItem.value.tier : null;
    ref.tier = tier;

    // 无进阶：无速度加成，移除周期函数
    if (!tier) {
        _root.装备生命周期函数.移除周期函数(ref);
        return;
    }

    // 进阶等级映射
    var tierNum:String;
    switch (tier) {
        case "二阶": tierNum = "2"; break;
        case "三阶": tierNum = "3"; break;
        case "四阶": tierNum = "4"; break;
        default:
            _root.装备生命周期函数.移除周期函数(ref);
            return;
    }

    // 从XML读取进阶配置
    var tierConfig:Object = param ? param["tier_" + tierNum] : null;

    // 默认速度倍率（如果XML未配置则使用默认值）
    // 空洞数组：索引2/3/4对应二阶/三阶/四阶
    var defaultMultipliers:Array = [];
    defaultMultipliers[2] = 1.10;  // 二阶 +10%
    defaultMultipliers[3] = 1.12;  // 三阶 +12%
    defaultMultipliers[4] = 1.15;  // 四阶 +15%
    var speedMultiplier:Number = (tierConfig && tierConfig.speedMultiplier)
        ? Number(tierConfig.speedMultiplier)
        : defaultMultipliers[tierNum];

    // 订阅玩家模板重新初始化事件，清理buff标记
    target.dispatcher.subscribe("InitPlayerTemplateEnd", function() {
        target.剑圣装甲鞋速度增强已应用 = false;
    }, target);

    // 订阅单位初始化完成事件，应用buff
    target.dispatcher.subscribe("UnitInitialized", function() {
        _root.装备生命周期函数.剑圣装甲鞋应用Buff(ref, speedMultiplier);
    }, target);

    // 移除周期函数，不需要每帧更新
    _root.装备生命周期函数.移除周期函数(ref);

    // _root.发布消息("剑圣装甲鞋系统启动 - " + tier + " 速度倍率=" + speedMultiplier);
};

/**
 * 剑圣装甲鞋 - 应用速度增强buff
 * 使用buffManager持久化管理
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Number} speedMultiplier 速度倍率
 */
_root.装备生命周期函数.剑圣装甲鞋应用Buff = function(ref:Object, speedMultiplier:Number):Void {
    var target:MovieClip = ref.自机;
    if (!target.buffManager) return;

    // 使用target上的标记防止重复应用（跨ref对象）
    if (target.剑圣装甲鞋速度增强已应用) return;

    // 构建MetaBuff：行走X速度乘算
    var childBuffs:Array = [
        new PodBuff("行走X速度", BuffCalculationType.MULTIPLY, speedMultiplier)
    ];

    // 无时间限制，手动控制移除
    var components:Array = [];
    var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

    target.buffManager.addBuff(metaBuff, "剑圣装甲鞋速度增强");
    target.buffManager.update(0);

    // 在target上标记已应用，防止跨ref重复
    target.剑圣装甲鞋速度增强已应用 = true;

    // _root.发布消息("剑圣装甲鞋速度增强已应用，倍率=" + speedMultiplier);
};

/**
 * 剑圣装甲鞋 - 周期函数（空实现）
 * 速度buff通过buffManager管理，无需周期更新
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣装甲鞋周期 = function(ref:Object) {
    // 速度buff由buffManager管理，无需周期逻辑
    // 保留此函数以防外部调用
};
