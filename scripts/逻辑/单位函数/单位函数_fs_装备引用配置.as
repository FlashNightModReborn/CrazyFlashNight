import org.flashNight.neur.Event.*;

_root.装备引用配置 = {};

// 定义巨拳模式下需要排除的引用名集合
_root.装备引用配置.巨拳排除引用 = {
    单臂巨拳: {
        右下臂_引用: true
    },
    巨拳: {
        右下臂_引用: true,
        左下臂_引用: true
    }
};

// 定义各引用名对应的固定深度，未在此处定义的引用名将使用默认深度0
_root.装备引用配置.引用深度配置 = {
    发型_引用: 1,
    面具_引用: 2
};

// 女性裸体 fallback 映射表
_root.装备引用配置.女性裸体映射 = {
    身体_引用: "女变装-裸体身体",
    上臂_引用: "女变装-裸体上臂",
    右下臂_引用: "女变装-裸体右下臂",
    左下臂_引用: "女变装-裸体左下臂",
    右手_引用: "女变装-裸体右手",
    左手_引用: "女变装-裸体左手",
    屁股_引用: "女变装-裸体屁股",
    右大腿_引用: "女变装-裸体右大腿",
    左大腿_引用: "女变装-裸体左大腿",
    小腿_引用: "女变装-裸体小腿",
    脚_引用: "女变装-裸体脚"
};

// skinKeyName 特殊映射表
// 武器类的 skinConfig 从 unit[xxx_装扮] 读取，而非 unit[xxx]
_root.装备引用配置.skinKey映射 = {
    刀_引用: "刀_装扮",
    刀2_引用: "刀2_装扮",
    长枪_引用: "长枪_装扮",
    手枪_引用: "手枪_装扮",
    手枪2_引用: "手枪2_装扮",
    手雷_引用: "手雷_装扮"
};

// 数字后缀引用名到基础引用名的映射（仅小腿和脚需要）
_root.装备引用配置.引用名基础映射 = {
    小腿1_引用: "小腿_引用",
    脚1_引用: "脚_引用"
};

/**
 * 内部执行函数：执行装扮配置但不进行注册
 * 用于刷新时避免重复注册
 */
_root.装备引用配置._执行配置 = function(mc:MovieClip, skinConfig:String,
        instanceName:String, referenceName:String, unit:MovieClip):MovieClip {

    var cfg:Object = _root.装备引用配置;  // 缓存引用减少属性查找

    // 获取基础引用名（用于查找映射表和深度配置）
    var baseRefName:String = cfg.引用名基础映射[referenceName] || referenceName;

    // 检查巨拳模式下是否需要排除（使用基础引用名检查）
    if (unit.空手动作类型 == "巨拳" || unit.空手动作类型 == "单臂巨拳") {
        if (cfg.巨拳排除引用[unit.空手动作类型][baseRefName]) {
            return null;
        }
    }

    // 移除旧装扮（如果存在）
    if (mc[instanceName]) {
        mc[instanceName].removeMovieClip();
    }

    // 尝试挂载新装扮（深度配置使用基础引用名）
    var skin:MovieClip = skinConfig
        ? mc.attachMovie(skinConfig, instanceName, cfg.引用深度配置[baseRefName])
        : null;

    // 女性 fallback 处理（映射表使用基础引用名）
    if (!skin && unit.性别 == "女") {
        var fallback:String = cfg.女性裸体映射[baseRefName];
        if (fallback) {
            skin = mc.attachMovie(fallback, instanceName, cfg.引用深度配置[baseRefName]);
        }
    }

    // 设置基本款可见性
    if (mc.基本款) {
        mc.基本款._visible = !skin;
    }

    // 引用始终有效：换装成功用皮肤子级，否则用基本款（与皮肤同层级）
    unit[referenceName] = skin || mc.基本款 || mc;

    // 仅在有订阅者注册了该引用的同步标签时才发布事件
    if (unit.syncRefs[referenceName]) {
        unit.dispatcher.publish(referenceName, unit);
    }

    return skin;
};

/**
 * 配置装扮（对外接口）
 * 在 load 时被肢体素材调用，自动注册到刷新列表并执行配置
 *
 * @param movieClip 肢体素材 MovieClip
 * @param skinConfig 皮肤配置名称（从 unit 属性读取）
 * @param instanceName 装扮实例名称
 * @param referenceName 引用名称（如 "身体_引用"）
 * @return 挂载成功的皮肤 MovieClip，失败返回 null
 */
_root.装备引用配置.配置装扮 = function(movieClip:MovieClip,
                                     skinConfig:String,
                                     instanceName:String,
                                     referenceName:String):MovieClip {
    var cfg:Object = _root.装备引用配置;
    var unit:MovieClip = movieClip._parent._parent._parent;

    // 注册到刷新列表
    if (!unit.dressupRegistry) {
        unit.dressupRegistry = {};
    }

    // 生成唯一的 regKey：如果已存在则追加数字后缀
    var baseKey:String = referenceName + "@" + instanceName;
    var regKey:String = baseKey;
    var counter:Number = 1;
    while (unit.dressupRegistry[regKey]) {
        regKey = referenceName + counter + "@" + instanceName;
        counter++;
    }

    // 同时生成对应的实际引用名（用于 unit[xxx_引用] 的注册）
    var actualRefName:String = (counter > 1) ? (referenceName.split("_引用")[0] + (counter - 1) + "_引用") : referenceName;

    unit.dressupRegistry[regKey] = {
        mc: movieClip,
        instanceName: instanceName,
        referenceName: actualRefName,
        baseReferenceName: referenceName,
        skinKeyName: cfg.skinKey映射[referenceName] || referenceName.split("_引用")[0]
    };

    // 执行配置（使用实际引用名）
    return cfg._执行配置(movieClip, skinConfig, instanceName, actualRefName, unit);
};

/**
 * 刷新所有已注册的装扮
 * 在换装后调用，遍历注册表重新配置所有活跃的肢体素材
 *
 * @param unit 目标单位 MovieClip
 */
_root.装备引用配置.刷新所有装扮 = function(unit:MovieClip):Void {
    var registry:Object = unit.dressupRegistry;
    if (!registry) return;

    var 执行配置:Function = _root.装备引用配置._执行配置;
    for (var regKey:String in registry) {
        var entry:Object = registry[regKey];
        var mc:MovieClip = entry.mc;

        // 检查 MC 是否仍然有效（未被销毁）
        if (!mc || !mc._parent) {
            delete registry[regKey];
            continue;
        }

        // 从 unit 获取最新的 skinConfig，执行刷新配置
        执行配置(mc, unit[entry.skinKeyName], entry.instanceName, entry.referenceName, unit);
    }
};
