/**
 * 剑圣装甲鞋 - 装备生命周期函数
 *
 * 功能特性：
 * - 提供行走速度加成buff
 * - 增强一文字落雷技能效果
 * - 使用buffManager持久化管理，无需周期函数
 *
 * 进阶等级效果：
 * - 无进阶：无速度加成，无技能增强
 * - 二阶：行走速度 +10%，启动追踪+消弹反弹
 * - 三阶：行走速度 +12%，启动追踪+消弹反弹，居合段数4，落雷段数5
 * - 四阶：行走速度 +15%，启动追踪+消弹反弹，居合段数6，落雷段数8
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数：
 *   - tier_2/tier_3/tier_4: 各进阶等级的配置节点
 *     - speedMultiplier: 速度倍率（二阶1.10，三阶1.12，四阶1.15）
 *     - enableTracking: 启动追踪（默认true）
 *     - enableReflect: 消弹反弹（默认true）
 *     - iaiCount: 居合段数（二阶无，三阶4，四阶6）
 *     - raidenCount: 落雷段数（二阶无，三阶5，四阶8）
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
        case "二阶":
            tierNum = "2";
            break;
        case "三阶":
            tierNum = "3";
            break;
        case "四阶":
            tierNum = "4";
            break;
        default:
            _root.装备生命周期函数.移除周期函数(ref);
            return;
    }

    // 从XML读取进阶配置
    var tierConfig:Object = param ? param["tier_" + tierNum] : null;

    // 默认速度倍率（如果XML未配置则使用默认值）
    // 空洞数组：索引2/3/4对应二阶/三阶/四阶
    var defaultMultipliers:Array = [];
    defaultMultipliers[2] = 1.10; // 二阶 +10%
    defaultMultipliers[3] = 1.12; // 三阶 +12%
    defaultMultipliers[4] = 1.15; // 四阶 +15%
    var speedMultiplier:Number = (tierConfig && tierConfig.speedMultiplier) ? Number(tierConfig.speedMultiplier) : defaultMultipliers[tierNum];

    // ═══════════════════════════════════════════════════════════════════════
    // 【一文字落雷技能增强配置】
    //
    // 进阶效果：
    // - 二阶：启动追踪+消弹反弹（基础增强）
    // - 三阶：居合段数4，落雷段数5
    // - 四阶：居合段数6，落雷段数8
    // ═══════════════════════════════════════════════════════════════════════

    // 默认技能增强配置
    var defaultIaiCount:Array = [];
    defaultIaiCount[2] = 0;  // 二阶不改变居合段数
    defaultIaiCount[3] = 4;  // 三阶居合段数4
    defaultIaiCount[4] = 6;  // 四阶居合段数6

    var defaultRaidenCount:Array = [];
    defaultRaidenCount[2] = 0;  // 二阶不改变落雷段数
    defaultRaidenCount[3] = 5;  // 三阶落雷段数5
    defaultRaidenCount[4] = 8;  // 四阶落雷段数8

    // 读取配置或使用默认值
    var enableTracking:Boolean = (tierConfig && tierConfig.enableTracking != undefined) ? (tierConfig.enableTracking == "true" || tierConfig.enableTracking == true) : true;
    var enableReflect:Boolean = (tierConfig && tierConfig.enableReflect != undefined) ? (tierConfig.enableReflect == "true" || tierConfig.enableReflect == true) : true;
    var iaiCount:Number = (tierConfig && tierConfig.iaiCount != undefined) ? Number(tierConfig.iaiCount) : defaultIaiCount[tierNum];
    var raidenCount:Number = (tierConfig && tierConfig.raidenCount != undefined) ? Number(tierConfig.raidenCount) : defaultRaidenCount[tierNum];

    // 存储到ref供事件回调使用
    ref.enableTracking = enableTracking;
    ref.enableReflect = enableReflect;
    ref.iaiCount = iaiCount;
    ref.raidenCount = raidenCount;

    // 订阅单位初始化完成事件，应用buff
    target.dispatcher.subscribe("UnitInitialized", function() {
        _root.装备生命周期函数.剑圣装甲鞋应用Buff(ref, speedMultiplier);
    }, target);

    // 订阅战技事件，增强一文字落雷技能
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        var target:MovieClip = ref.自机;
        if (target.技能名 == "一文字落雷") {
            var man:MovieClip = target.man;

            // 二阶及以上：启动追踪+消弹反弹
            if (ref.enableTracking) {
                man.启动追踪 = true;
            }
            if (ref.enableReflect) {
                man.消弹反弹 = true;
            }

            // 三阶及以上：提升居合/落雷段数
            if (ref.iaiCount > 0) {
                man.居合段数 = ref.iaiCount;
            }
            if (ref.raidenCount > 0) {
                man.落雷段数 = ref.raidenCount;
            }

            // 调试信息（取消注释可查看效果）
            // _root.发布消息("一文字落雷增强: 追踪=" + ref.enableTracking + " 反弹=" + ref.enableReflect + " 居合=" + ref.iaiCount + " 落雷=" + ref.raidenCount);
        }
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
    if (!target.buffManager)
        return;

    // 构建MetaBuff：行走X速度乘算（使用保守语义，多个速度buff只取最大值）
    var childBuffs:Array = [new PodBuff("行走X速度", BuffCalculationType.MULT_POSITIVE, speedMultiplier)];

    // 无时间限制，手动控制移除
    var components:Array = [];
    var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

    // 使用固定ID添加buff，重复调用会替换而非叠加
    target.buffManager.addBuff(metaBuff, "剑圣装甲鞋速度增强");
};

/**
 * 剑圣装甲鞋 - 周期函数（空实现）
 * 速度buff通过buffManager管理，无需周期更新
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣装甲鞋周期 = function(ref:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);
    // 速度buff由buffManager管理，无需周期逻辑
};
