import org.flashNight.arki.unit.UnitComponent.Dressup.SkinReadyClass;

/**
 * DressupReferenceManager - 装扮引用配置（运行时）
 *
 * 接管 _root.装备引用配置 的实现。_root 接口（配置装扮 / 刷新所有装扮）
 * 由 单位函数_fs_装备引用配置.as 以函数桥接形式赋值，参见该 shim。
 *
 * ============================================================================
 * 事件通道
 * ============================================================================
 *
 * 【同步通道】placement-ready 时刻
 *   key = referenceName（如 "刀_引用"）
 *   触发：attach 完成后立即 publish；订阅方可信地读 unit[refName]、其
 *         _x/_y/_visible/_parent，以及 placement 子的 _x/_y。
 *   订阅方写：unit.syncRefs[refName] = true; unit.dispatcher.subscribe(...)
 *
 * 【Deferred 通道】load-fully-ready 时刻
 *   key = referenceName + ":ready"（如 "刀_引用:ready"）
 *   触发：在 load flush 阶段尾、定时器/enterFrame 之前；订阅方可信地读子 MC
 *         的 onClipEvent(load) 写入字段、嵌套 attachMovie 的孙级。
 *   订阅方写：unit.syncRefs[refName + ":ready"] = true; unit.dispatcher.subscribe(...)
 *   实现：register-attach-unregister + SkinReadyClass.onLoad（详见 doConfig）
 *
 * 【组级 refresh 通道】
 *   key = "dressup:refreshed"
 *   触发：refreshAll 串行遍历完所有 entry 后 publish 一次
 *   订阅方约定：在引用同步回调里若 unit.dressupRefreshing === true，可
 *              选择跳过本次重算，由组级事件统一驱动。订阅方迁移自愿。
 *
 * 时序依据：agentsDoc/as2-load-timing.md
 *
 * ============================================================================
 * 性能基线 (2026-05-09) — DressupReferenceManagerTest.runBench()
 * ============================================================================
 *
 * 测试机：Intel i7-9750H @ 2.6/4.5GHz, 6C/12T, 32GB RAM, Win11 + Flash Player 20
 * 参考机：Steam Deck (AMD Aerith / Zen 2 @ 2.4/3.5GHz, 4C/8T)
 *        AVM1 单线程，Steam Deck 单核约本机 70–80% → 预期 per-call avg ×1.25–1.4
 *
 *   (baseline empty wrapper)                       avg=  2.5us
 *   doConfig (no deferred, no fallback)            avg= 16.8us  (净 ~14us)
 *   doConfig (deferred, real registerClass x2)     avg= 24.8us  (净 ~22us, Plan B 增量 ~8us)
 *   doConfig (female fallback, no deferred)        avg= 22.8us  (净 ~20us, fallback 增量 ~6us)
 *   attach (fresh unit, 1 attach)                  avg= 97.5us  (含 mock setup)
 *   refreshAll (11 entries, no deferred)           avg=186.6us  (~17us/entry)
 *
 * 注：bench 走 mock attachMovie，不含真实 Flash attachMovie 成本（经验值
 * ~0.5–2ms/次，约 100× 于本表数值）。本类逻辑优化是噪声，refresh 性能优化
 * 唯一有意义方向是减少 attachMovie 调用（diff-based refresh：skinConfig
 * 未变则跳过 doConfig）。
 *
 * Regression 用法：runBench() 后比对此表，单项 >1.5× 偏离即需调查。换基准
 * 机时按预期倍率折算后再比对。
 * ============================================================================
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager {

    // ====================================================================
    // Lookup tables（原 _root.装备引用配置 的 5 张表，全部下沉）
    // 表名英化；keys/values 保留中文——它们是外部依赖（unit 字段名、
    // unit.空手动作类型 取值、FLA library 名），不可改。
    // ====================================================================

    public static var fistModeExclusions:Object = {
        单臂巨拳: { 右下臂_引用: true },
        巨拳:     { 右下臂_引用: true, 左下臂_引用: true }
    };

    public static var refDepths:Object = {
        发型_引用: 1,
        面具_引用: 2
    };

    public static var femaleFallbacks:Object = {
        身体_引用:    "女变装-裸体身体",
        上臂_引用:    "女变装-裸体上臂",
        右下臂_引用:  "女变装-裸体右下臂",
        左下臂_引用:  "女变装-裸体左下臂",
        右手_引用:    "女变装-裸体右手",
        左手_引用:    "女变装-裸体左手",
        屁股_引用:    "女变装-裸体屁股",
        右大腿_引用:  "女变装-裸体右大腿",
        左大腿_引用:  "女变装-裸体左大腿",
        小腿_引用:    "女变装-裸体小腿",
        脚_引用:      "女变装-裸体脚"
    };

    public static var skinKeyOverrides:Object = {
        刀_引用:    "刀_装扮",
        刀2_引用:   "刀2_装扮",
        刀3_引用:   "刀3_装扮",
        长枪_引用:  "长枪_装扮",
        手枪_引用:  "手枪_装扮",
        手枪2_引用: "手枪2_装扮",
        手雷_引用:  "手雷_装扮"
    };

    public static var refNameAliases:Object = {
        小腿1_引用: "小腿_引用",
        脚1_引用:   "脚_引用",
        上臂1_引用: "上臂_引用"
    };

    // ====================================================================
    // 内部：执行装扮配置（不进行注册，refreshAll 复用此函数避免重复注册）
    // ====================================================================

    public static function doConfig(mc:MovieClip, skinConfig:String,
            instanceName:String, referenceName:String, unit:MovieClip):MovieClip {

        // 基础引用名（用于查找映射表和深度配置）
        var baseRefName:String = refNameAliases[referenceName] || referenceName;

        // 巨拳模式排除
        if (unit.空手动作类型 == "巨拳" || unit.空手动作类型 == "单臂巨拳") {
            if (fistModeExclusions[unit.空手动作类型][baseRefName]) {
                return null;
            }
        }

        // 移除旧装扮
        if (mc[instanceName]) {
            mc[instanceName].removeMovieClip();
        }

        // ============ Plan B-精准：deferred 通道 register-attach-unregister ============
        // 仅当订阅方注册了 deferred 通道时才走类绑定路径，未订阅 unit 零开销
        var deferredKey:String = referenceName + ":ready";
        var hasDeferred:Boolean = (unit.syncRefs[deferredKey] === true);
        var depth:Number = refDepths[baseRefName];

        var skin:MovieClip;
        if (skinConfig) {
            if (hasDeferred) {
                Object.registerClass(skinConfig, SkinReadyClass);
                skin = mc.attachMovie(skinConfig, instanceName, depth,
                    { __unit: unit, __publishKey: deferredKey });
                Object.registerClass(skinConfig, null);
            } else {
                skin = mc.attachMovie(skinConfig, instanceName, depth);
            }
        }

        // 女性 fallback 处理（fallback 路径同样支持 deferred 通道）
        if (!skin && unit.性别 == "女") {
            var fallback:String = femaleFallbacks[baseRefName];
            if (fallback) {
                if (hasDeferred) {
                    Object.registerClass(fallback, SkinReadyClass);
                    skin = mc.attachMovie(fallback, instanceName, depth,
                        { __unit: unit, __publishKey: deferredKey });
                    Object.registerClass(fallback, null);
                } else {
                    skin = mc.attachMovie(fallback, instanceName, depth);
                }
            }
        }

        // 引用始终有效：换装成功用皮肤子级，否则用基本款（与皮肤同层级）
        unit[referenceName] = skin || mc.基本款 || mc;

        // 同步通道：placement-ready 时刻
        if (unit.syncRefs[referenceName]) {
            unit.dispatcher.publish(referenceName, unit);
        }

        return skin;
    }

    // ====================================================================
    // 配置装扮（对外接口）
    // 在 load 时被肢体素材的 onClipEvent(load) 调用，自动注册到刷新列表并执行配置
    // 注：FLA 肢体素材通过 _root.装备引用配置.配置装扮 调用，shim 直接桥接到此
    // ====================================================================

    public static function attach(movieClip:MovieClip, skinConfig:String,
            instanceName:String, referenceName:String):MovieClip {

        var unit:MovieClip = movieClip._parent._parent._parent;

        if (!unit.dressupRegistry) {
            unit.dressupRegistry = {};
        }

        // 生成唯一的 regKey + actualRefName：已存在且 MC 仍有效则追加数字后缀；
        // 旧 MC 失效则清理并复用。regKey 与 actualRefName 用同款 split-base + counter
        // 命名约定（小腿1_引用@装扮 / 小腿1_引用），便于调试时对照
        var baseRefSplit:String = referenceName.split("_引用")[0];
        var actualRefName:String = referenceName;
        var regKey:String = actualRefName + "@" + instanceName;
        var counter:Number = 1;
        while (unit.dressupRegistry[regKey]) {
            var oldEntry:Object = unit.dressupRegistry[regKey];
            if (!oldEntry.mc || !oldEntry.mc._parent) {
                delete unit.dressupRegistry[regKey];
                break;
            }
            actualRefName = baseRefSplit + counter + "_引用";
            regKey = actualRefName + "@" + instanceName;
            counter++;
        }

        unit.dressupRegistry[regKey] = {
            mc: movieClip,
            instanceName: instanceName,
            referenceName: actualRefName,
            baseReferenceName: referenceName,
            skinKeyName: skinKeyOverrides[referenceName] || referenceName.split("_引用")[0]
        };

        return doConfig(movieClip, skinConfig, instanceName, actualRefName, unit);
    }

    // ====================================================================
    // 刷新所有已注册的装扮（换装后调用）
    // ====================================================================

    public static function refreshAll(unit:MovieClip):Void {

        var registry:Object = unit.dressupRegistry;
        if (!registry) return;

        // 标记 burst 期间：订阅方可选地用 if (unit.dressupRefreshing) return; 去重
        // 让组级 "dressup:refreshed" 事件统一驱动重算（订阅方迁移自愿）
        unit.dressupRefreshing = true;

        for (var regKey:String in registry) {
            var entry:Object = registry[regKey];
            var mc:MovieClip = entry.mc;

            // 检查 MC 是否仍然有效（未被销毁）
            if (!mc || !mc._parent) {
                delete registry[regKey];
                continue;
            }

            // 从 unit 获取最新 skinConfig，执行刷新配置
            doConfig(mc, unit[entry.skinKeyName], entry.instanceName, entry.referenceName, unit);
        }

        unit.dressupRefreshing = false;

        // 组级 refresh 完毕事件（同步通道，all-attaches-issued 语义）
        if (unit.syncRefs["dressup:refreshed"]) {
            unit.dispatcher.publish("dressup:refreshed", unit);
        }
    }
}
