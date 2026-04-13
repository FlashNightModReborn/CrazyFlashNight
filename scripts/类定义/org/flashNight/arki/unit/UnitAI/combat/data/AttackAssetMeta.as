/**
 * AttackAssetMeta — 攻击资产静态元数据 + L2 平衡系数
 *
 * 用途：为 WeaponDpsEstimator 提供"每份攻击动画资产的聚合量"，
 *       以及全局 L2 平衡系数（nano 缩放 / outlier 乘数 / 伤害类型权重）。
 *
 * 精度口径（plan v4）：
 *   L1 机制级：totalFrames / effHits / bulletSpawnCount / reload controlled/tail —— 必须准
 *   L2 平衡系数：下方静态字段 —— 10-15% 误差可接受，调参入口集中在此
 *   L3 not in scope：目标 HP 感知 / 即时弹药状态
 *
 * 数据来源：Step 0 per-asset 采集（1连招 XML 里逐 helper + shoot 调用统计）
 *   空手容器：flashswf/arts/things0/LIBRARY/容器/空手攻击容器/平A/
 *   兵器容器：flashswf/arts/things0/LIBRARY/容器/兵器攻击容器/平A/
 *   换弹：scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ReloadManager.as 的 docstring
 */
class org.flashNight.arki.unit.UnitAI.combat.data.AttackAssetMeta {

    // ═══════ L2 平衡系数（调参入口）═══════

    // nano 毒伤统一缩放（plan v4: 不分 isNormal/isVertical，粗近似）
    public static var NANO_SCALE:Number = 0.5;

    // 特殊招式 outlier 乘数：仅乘主伤（不放大毒）
    public static var OUTLIER_MULT:Object = initOutliers();

    // 主伤伤害类型权重（经验设计；不是 UniversalDamageHandle 派生公式）
    public static var DAMAGE_TYPE_WEIGHT:Object = initDmgType();

    private static function initOutliers():Object {
        var m:Object = {};
        m["巨拳"]      = 1.3;   // 体重项粗估
        m["单臂巨拳"]  = 1.3;
        m["兽王崩拳"]  = 1.0;   // effHits 已反映高倍率
        m["拳击"]      = 1.0;   // effHits=7 已是低值
        return m;
    }

    private static function initDmgType():Object {
        var m:Object = {};
        m["物理"] = 1.0;
        m["破击"] = 1.5;
        m["魔法"] = 2.0;
        m["真伤"] = 3.0;
        return m;
    }

    // ═══════ 资产元数据表 ═══════

    private static var UNARMED_META:Object = initUnarmed();
    private static var MELEE_META:Object   = initMelee();
    private static var RELOAD_META:Object  = initReload();

    // ───── 空手资产聚合（11 条）─────
    //
    // 字段：
    //   totalFrames       : 1连招总帧数（含收招硬直）
    //   stages            : 段数
    //   firstStageFrames  : 首段帧数（用于 AI 决策粒度）
    //   effHits           : Σ (unarmedMult × split) —— 主伤威力乘子聚合
    //   judgmentHitCount  : Σ split —— 每弹平加项（伤害加成 / mp攻击加成）触发次数
    //   bulletSpawnCount  : _root.子弹区域shoot传递 调用次数 —— 近战毒触发次数
    //   outlierTag        : null / "巨拳" / "单臂巨拳" / "兽王崩拳" / "拳击"
    //   applyKickPassive  : 是否应用"拳脚攻击"整体乘法被动（巨拳系 false）
    private static function initUnarmed():Object {
        var m:Object = {};
        m["1连招"] = { totalFrames:79, stages:5, firstStageFrames:15,
                      effHits:26.0, judgmentHitCount:9,  bulletSpawnCount:5,
                      outlierTag:null, applyKickPassive:true };
        m["巨拳"] = { totalFrames:96, stages:4, firstStageFrames:25,
                    effHits:40.4, judgmentHitCount:25, bulletSpawnCount:8,
                    outlierTag:"巨拳", applyKickPassive:false };
        m["单臂巨拳"] = { totalFrames:88, stages:4, firstStageFrames:22,
                        effHits:32.0, judgmentHitCount:20, bulletSpawnCount:7,
                        outlierTag:"单臂巨拳", applyKickPassive:false };
        m["兽王崩拳"] = { totalFrames:72, stages:4, firstStageFrames:14,
                        effHits:34.8, judgmentHitCount:12, bulletSpawnCount:6,
                        outlierTag:"兽王崩拳", applyKickPassive:true };
        m["拳击"] = { totalFrames:55, stages:4, firstStageFrames:10,
                    effHits:7.0,  judgmentHitCount:7,  bulletSpawnCount:4,
                    outlierTag:"拳击", applyKickPassive:true };
        m["双掌"] = { totalFrames:70, stages:4, firstStageFrames:14,
                    effHits:14.0, judgmentHitCount:8,  bulletSpawnCount:4,
                    outlierTag:null, applyKickPassive:true };
        m["连掌"] = { totalFrames:74, stages:5, firstStageFrames:12,
                    effHits:18.5, judgmentHitCount:10, bulletSpawnCount:5,
                    outlierTag:null, applyKickPassive:true };
        m["连踢"] = { totalFrames:82, stages:5, firstStageFrames:16,
                    effHits:22.0, judgmentHitCount:8,  bulletSpawnCount:5,
                    outlierTag:null, applyKickPassive:true };
        m["鞭腿"] = { totalFrames:76, stages:4, firstStageFrames:18,
                    effHits:20.0, judgmentHitCount:6,  bulletSpawnCount:4,
                    outlierTag:null, applyKickPassive:true };
        m["重拳"] = { totalFrames:65, stages:3, firstStageFrames:20,
                    effHits:16.5, judgmentHitCount:5,  bulletSpawnCount:3,
                    outlierTag:null, applyKickPassive:true };
        m["爪击"] = { totalFrames:68, stages:4, firstStageFrames:13,
                    effHits:19.0, judgmentHitCount:9,  bulletSpawnCount:5,
                    outlierTag:null, applyKickPassive:true };
        return m;
    }

    // ───── 兵器资产聚合（15 条，subset 数组）─────
    //
    // subsets 数组字段：
    //   kind               : "blade" (走 BladeShootCore × 刀_刀口数) | "direct" (走 _root.子弹区域shoot传递 × 1)
    //   passiveScope       : "weaponOnly" (子弹威力 += 刀.power×lvl×0.075，加法)
    //                        "wholeBullet" (子弹威力 *= 1 + lvl×0.075，整段乘法)
    //                        "none"
    //   effHitsWeapon      : Σ (weaponMult × split) —— 刀威部分
    //   effHitsUnarmed     : Σ (split / unarmedDiv) —— 空手部分（分母 3/5 混用）
    //   judgmentHitCount   : Σ split —— 每弹平加项触发次数
    //   bulletSpawnCount   : 此 subset 内 shoot 调用次数 —— 毒触发基准（再 × bladeCount for blade）
    private static function initMelee():Object {
        var m:Object = {};

        // 1连招：基准 blade-only 资产
        m["1连招"] = { totalFrames:74, stages:5, firstStageFrames:14,
                      subsets: [
                          { kind:"blade", passiveScope:"weaponOnly",
                            effHitsWeapon:12.7, effHitsUnarmed:2.72,
                            judgmentHitCount:11, bulletSpawnCount:11 }
                      ]};

        // 刀剑：前半 blade/加法 + 后半 direct/整段乘
        m["刀剑"] = { totalFrames:82, stages:5, firstStageFrames:15,
                    subsets: [
                        { kind:"blade",  passiveScope:"weaponOnly",
                          effHitsWeapon:13.0, effHitsUnarmed:2.8,
                          judgmentHitCount:10, bulletSpawnCount:10 },
                        { kind:"direct", passiveScope:"wholeBullet",
                          effHitsWeapon:18.0, effHitsUnarmed:3.6,
                          judgmentHitCount:18, bulletSpawnCount:6 }
                    ]};

        // 双刀：blade-only
        m["双刀"] = { totalFrames:85, stages:5, firstStageFrames:14,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:21.5, effHitsUnarmed:5.73,
                          judgmentHitCount:20, bulletSpawnCount:20 }
                    ]};

        // 棍棒：blade-only
        m["棍棒"] = { totalFrames:80, stages:5, firstStageFrames:16,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:20.7, effHitsUnarmed:5.78,
                          judgmentHitCount:18, bulletSpawnCount:18 }
                    ]};

        // 狂野：前半 blade/加法 + 后半 direct/整段乘（高 effHits）
        m["狂野"] = { totalFrames:95, stages:6, firstStageFrames:14,
                    subsets: [
                        { kind:"blade",  passiveScope:"weaponOnly",
                          effHitsWeapon:33.5, effHitsUnarmed:5.27,
                          judgmentHitCount:17, bulletSpawnCount:17 },
                        { kind:"direct", passiveScope:"wholeBullet",
                          effHitsWeapon:15.0, effHitsUnarmed:3.0,
                          judgmentHitCount:15, bulletSpawnCount:5 }
                    ]};

        // 直剑：blade-only
        m["直剑"] = { totalFrames:76, stages:5, firstStageFrames:14,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:16.2, effHitsUnarmed:5.97,
                          judgmentHitCount:13, bulletSpawnCount:13 }
                    ]};

        // 短兵：前半 blade/加法 + 后半 direct/整段乘
        m["短兵"] = { totalFrames:81, stages:5, firstStageFrames:15,
                    subsets: [
                        { kind:"blade",  passiveScope:"weaponOnly",
                          effHitsWeapon:9.0, effHitsUnarmed:1.8,
                          judgmentHitCount:9, bulletSpawnCount:9 },
                        { kind:"direct", passiveScope:"wholeBullet",
                          effHitsWeapon:3.0, effHitsUnarmed:0.6,
                          judgmentHitCount:3, bulletSpawnCount:1 }
                    ]};

        // 短柄：采集不完整，fallback 近似（参照 1连招）
        m["短柄"] = { totalFrames:72, stages:4, firstStageFrames:14,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:11.5, effHitsUnarmed:2.5,
                          judgmentHitCount:9, bulletSpawnCount:9 }
                    ]};

        // 迅捷：采集不完整，fallback 近似
        m["迅捷"] = { totalFrames:70, stages:5, firstStageFrames:12,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:12.0, effHitsUnarmed:2.6,
                          judgmentHitCount:10, bulletSpawnCount:10 }
                    ]};

        // 重斩：blade-only（高威力重武器）
        m["重斩"] = { totalFrames:92, stages:4, firstStageFrames:22,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:26.5, effHitsUnarmed:5.8,
                          judgmentHitCount:19, bulletSpawnCount:19 }
                    ]};

        // 镰刀：blade-only
        m["镰刀"] = { totalFrames:78, stages:4, firstStageFrames:17,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:15.0, effHitsUnarmed:3.067,
                          judgmentHitCount:10, bulletSpawnCount:10 }
                    ]};

        // 长刀：blade-only（unarmedDiv 3/5 混用）
        m["长刀"] = { totalFrames:84, stages:5, firstStageFrames:15,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:24.5, effHitsUnarmed:4.933,
                          judgmentHitCount:15, bulletSpawnCount:15 }
                    ]};

        // 长枪：前半 blade + 后半 direct（旋击 split=3）
        m["长枪"] = { totalFrames:90, stages:5, firstStageFrames:18,
                    subsets: [
                        { kind:"blade",  passiveScope:"weaponOnly",
                          effHitsWeapon:19.5, effHitsUnarmed:2.0,
                          judgmentHitCount:11, bulletSpawnCount:11 },
                        { kind:"direct", passiveScope:"wholeBullet",
                          effHitsWeapon:5.4, effHitsUnarmed:5.4,
                          judgmentHitCount:27, bulletSpawnCount:9 }
                    ]};

        // 长柄：blade-only
        m["长柄"] = { totalFrames:88, stages:5, firstStageFrames:18,
                    subsets: [
                        { kind:"blade", passiveScope:"weaponOnly",
                          effHitsWeapon:20.5, effHitsUnarmed:2.867,
                          judgmentHitCount:13, bulletSpawnCount:13 }
                    ]};

        // 长棍：前半 blade + 后半 direct（旋击 split=3）
        m["长棍"] = { totalFrames:86, stages:5, firstStageFrames:17,
                    subsets: [
                        { kind:"blade",  passiveScope:"weaponOnly",
                          effHitsWeapon:18.5, effHitsUnarmed:2.4,
                          judgmentHitCount:12, bulletSpawnCount:12 },
                        { kind:"direct", passiveScope:"wholeBullet",
                          effHitsWeapon:3.6, effHitsUnarmed:3.6,
                          judgmentHitCount:18, bulletSpawnCount:6 }
                    ]};

        return m;
    }

    // ───── 换弹元数据（Σ ceil(seg × burden/100) + fixedTail）─────
    //
    // 权威来源：scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ReloadManager.as docstring:19-127
    // 手枪/手枪2：audioFrames=[40,56] 切段 → controlled=[10,16,6]；fixedTail=13（frame 29 → 62 endFrame）
    private static function initReload():Object {
        var m:Object = {};
        m["长枪"]      = { controlledSegments:[9,5,8,10], fixedTail:3 };
        m["手枪"]      = { controlledSegments:[10,16,6],  fixedTail:13 };
        m["手枪2"]     = { controlledSegments:[10,16,6],  fixedTail:13 };
        m["双枪主手"]  = { controlledSegments:[12,6,1],   fixedTail:3 };
        m["双枪副手"]  = { controlledSegments:[13,6,1],   fixedTail:2 };
        m["双枪结束"]  = { controlledSegments:[],         fixedTail:7 };
        return m;
    }

    // ═══════ 公开接口 ═══════

    public static function getUnarmed(actionType:String):Object {
        var r:Object = UNARMED_META[actionType];
        return r ? r : UNARMED_META["1连招"];
    }

    public static function getMelee(actionType:String):Object {
        var r:Object = MELEE_META[actionType];
        return r ? r : MELEE_META["1连招"];
    }

    public static function getReload(mode:String):Object {
        var r:Object = RELOAD_META[mode];
        return r ? r : RELOAD_META["手枪"];
    }
}
