/**
 * 剑圣头部装甲 - 装备生命周期函数
 *
 * 进阶等级效果（视觉增强系统）：
 * - 无进阶：无特殊视觉效果，移除周期函数
 * - 二阶：使用"高级夜视仪"预设 + 敌人AABB高亮 + 扫描标记（约4%输出等效提升）
 * - 三阶：使用"剑圣视觉三阶"预设 + 更强扫描标记（约6%输出等效提升）
 * - 四阶：使用"剑圣视觉四阶"预设 + 最强扫描标记（约8%输出等效提升），完美暗视
 *
 * 功能特性：
 * - 在低光照环境下自动扫描并高亮最近的敌人
 * - 使用AABBRenderer绘制科技感扫描框
 * - 为扫描到的敌人施加"扫描标记"debuff，降低其闪避成功率
 * - 进阶等级越高，效果越强，扫描范围越大
 *
 * 数值设计说明：
 * - 躲闪率值越大 = 敌人闪避成功率越低（历史遗留的反向逻辑）
 * - 公式：dodgeIndex = (目标等级 * 10 / 躲闪率 - 攻击者等级 * 命中率 / 3) / 40
 * - 理论最大增幅约12.7%（当敌人完全无法闪避时）
 * - 二阶乘数1.6 ≈ 4%增幅，三阶乘数2.5 ≈ 6%增幅，四阶乘数5.0 ≈ 8%增幅
 *
 * XML参数配置（initParam内按进阶等级配置）：
 * - tier_2/tier_3/tier_4: 各进阶等级的配置节点
 *   - visual: 视觉预设名称
 *   - maxBrightness: 最大启动亮度
 *   - highlightMode: AABB高亮模式（predator1/2/3）
 *   - searchRange: 敌人搜索距离
 *   - scanInterval: 扫描间隔帧数
 *   - dodgeMultiplier: 躲闪率乘数
 *   - debuffDuration: debuff持续帧数
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数（XML配置）
 */

_root.装备生命周期函数.剑圣头部装甲初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // 获取装备进阶等级
    var equipItem:Object = target[ref.装备类型];
    var tier:String = equipItem && equipItem.value ? equipItem.value.tier : null;
    ref.tier = tier;

    // 无进阶：无视觉增强，移除周期函数
    if (!tier) {
        _root.装备生命周期函数.移除周期函数(ref);
        return;
    }

    // 非主角不启用视觉增强功能（夜视仪是玩家专属）
    if (_root.装备生命周期函数.移除非主角周期函数(ref)) {
        return;
    }

    // ========== 配置初始化 ==========
    // 进阶等级映射：二阶->2, 三阶->3, 四阶->4
    var tierNum:String;
    switch (tier) {
        case "二阶": tierNum = "2"; break;
        case "三阶": tierNum = "3"; break;
        case "四阶": tierNum = "4"; break;
        default:
            _root.装备生命周期函数.移除周期函数(ref);
            return;
    }

    var config:Object = param ? param["tier_" + tierNum] : null;
    // _root.发布消息("剑圣头部装甲读取配置 - " + _root.常用工具函数.对象转JSON(config, true));
    if (!config) {
        _root.装备生命周期函数.移除周期函数(ref);
        return;
    }

    // 从XML配置读取参数
    ref.视觉情况 = config.visual;
    ref.最大启动亮度 = Number(config.maxBrightness);
    ref.高亮模式 = config.highlightMode;
    ref.搜索距离 = Number(config.searchRange);
    ref.绘制间隔 = Number(config.scanInterval);
    ref.躲闪率乘数 = Number(config.dodgeMultiplier);
    ref.标记持续帧数 = Number(config.debuffDuration);

    // 通用配置
    ref.最小启动亮度 = 0;
    ref.帧计数 = 0;
    ref.当前目标 = null;

    // ========== 夜视仪系统注册 ==========
    // 创建视觉系统对象并注册到天气系统
    var 视觉系统:Object = {
        视觉情况: ref.视觉情况,
        最小启动亮度: ref.最小启动亮度,
        最大启动亮度: ref.最大启动亮度,
        启用装备: ref.装备名称,
        装备类型: ref.装备类型,
        进阶等级: tier
    };
    _root.天气系统.夜视仪 = 视觉系统;

    // ========== 生命周期卸载回调 ==========
    var 卸载对象:Object = {
        动作: function(额外参数) {
            _root.天气系统.夜视仪 = {};
        },
        额外参数: {}
    };
    ref.生命周期函数列表.push(卸载对象);

    // 同时设置target卸载回调（双重保障）
    _root.常用工具函数.设置卸载回调(target, function() {
        _root.天气系统.夜视仪 = {};
    });

    // ========== 事件订阅 ==========
    target.dispatcher.subscribe("UnitReInitialized", function() {
        // 玩家模板重新初始化时，重新注册夜视仪
        _root.天气系统.夜视仪 = 视觉系统;
    }, target);

    // 发布启动消息
    // _root.发布消息("剑圣视觉系统启动 - " + tier);
};

/**
 * 为敌人施加扫描标记debuff
 * 使用同ID替换机制，每次扫描会刷新debuff持续时间
 *
 * 注意：躲闪率值越大 = 敌人闪避成功率越低
 * 躲闪率在分母，所以躲闪率值越大，dodgeIndex越小，sigmoid后闪避率越低
 *
 * @param enemy 目标敌人
 * @param 躲闪率乘数 躲闪率的乘数（>1表示增加躲闪率值，降低敌人闪避能力）
 * @param 持续帧数 debuff持续的帧数
 */
_root.装备生命周期函数.施加扫描标记 = function(enemy:MovieClip, 躲闪率乘数:Number, 持续帧数:Number):Void {
    if (!enemy || !enemy.buffManager) {
        return;
    }

    // 创建增加躲闪率值的PodBuff（降低敌人闪避能力）
    var podBuff:PodBuff = new PodBuff(
        "躲闪率",
        BuffCalculationType.MULTIPLY,
        躲闪率乘数
    );

    // 准备组件数组，添加时间限制组件实现自动移除
    var components:Array = [];
    if (持续帧数 > 0) {
        components.push(new TimeLimitComponent(持续帧数));
    }

    // 创建MetaBuff包装PodBuff
    var metaBuff:MetaBuff = new MetaBuff(
        [podBuff],
        components,
        0
    );

    // 使用固定ID，确保同一敌人只有一个扫描标记，重复扫描会刷新
    enemy.buffManager.addBuff(metaBuff, "剑圣扫描标记");
};

/**
 * 剑圣头部装甲 - 周期函数
 * 负责敌人高亮渲染和施加扫描标记debuff
 *
 * @param {Object} ref 生命周期反射对象（包含所有配置和状态）
 */
_root.装备生命周期函数.剑圣头部装甲周期 = function(ref:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var tier:String = ref.tier;

    // 无进阶等级直接返回
    if (!tier) {
        return;
    }

    // 检查当前光照等级是否在有效范围内
    var 当前光照:Number = _root.天气系统.当前光照等级;
    if (当前光照 > ref.最大启动亮度) {
        // 光照太亮，不需要高亮
        ref.当前目标 = null;
        return;
    }

    // 帧计数递增
    ref.帧计数++;

    // 只在特定间隔帧执行搜索、绘制和施加debuff
    if (ref.帧计数 < ref.绘制间隔) {
        return;
    }

    // 重置帧计数
    ref.帧计数 = 0;

    // 搜索最近的一个敌人
    ref.当前目标 = TargetCacheManager.findNearestEnemy(target, ref.搜索距离);

    // 处理当前目标
    var enemy:MovieClip = ref.当前目标;
    if (!enemy || enemy._x == undefined || enemy.hp <= 0) {
        return;
    }

    // 绘制AABB高亮
    if (enemy.aabbCollider) {
        AABBRenderer.renderAABB(enemy.aabbCollider, 0, ref.高亮模式);
    }

    // 施加扫描标记debuff
    _root.装备生命周期函数.施加扫描标记(
        enemy,
        ref.躲闪率乘数,
        ref.标记持续帧数
    );
};
