/** XML 调参与形态默认值；与控制逻辑分开，避免 CS6 类初始化分支超过 32K。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandTuning {
    public static function configureMount(反射对象:Object, 参数对象:Object):Void {
        反射对象.长矛外观偏移Y = isFinite(Number(参数对象.spearVisualOffsetY)) ? Number(参数对象.spearVisualOffsetY) : -12;
        反射对象.长枪旋转角度 = isFinite(Number(参数对象.gunRotation)) ? Number(参数对象.gunRotation) : -90;
        反射对象.长枪偏移X = isFinite(Number(参数对象.gunOffsetX)) ? Number(参数对象.gunOffsetX) : -113.6;
        反射对象.长枪偏移Y = isFinite(Number(参数对象.gunOffsetY)) ? Number(参数对象.gunOffsetY) : 36.25;
        反射对象.枪口偏移X = isFinite(Number(参数对象.muzzleX)) ? Number(参数对象.muzzleX) : 6.5;
        反射对象.枪口偏移Y = isFinite(Number(参数对象.muzzleY)) ? Number(参数对象.muzzleY) : 330;
        反射对象.长枪威力系数 = isFinite(Number(参数对象.gunPowerCoeff)) ? Number(参数对象.gunPowerCoeff) : 0.65;
        反射对象.长枪伤害类型配置 = 参数对象.damageTypeGun || "魔法";
        反射对象.长枪魔法属性配置 = 参数对象.magicTypeGun || "电";
    }

    public static function configureCombat(反射对象:Object, 参数对象:Object):Void {
        var 自机:MovieClip = 反射对象.自机;
        反射对象.形态顺序 = ["钝器", "长矛", "镰刀"];
        反射对象.形态配置表 = {
            钝器: {
                动作类型: 参数对象.actionTypeBlunt || "狂野",
                伤害类型: 参数对象.damageTypeBlunt || "破击",
                魔法属性: 参数对象.magicTypeBlunt || "冲",
                威力倍率: isFinite(Number(参数对象.powerMultBlunt)) ? Number(参数对象.powerMultBlunt) : 1.15,
                枪头目标: {起始: 1, 结束: 1},
                握柄目标: {起始: 2, 结束: 16},
                刀口: [
                    {x: isFinite(Number(参数对象.bluntPos1X)) ? Number(参数对象.bluntPos1X) : -25, y: isFinite(Number(参数对象.bluntPos1Y)) ? Number(参数对象.bluntPos1Y) : 180, xscale: isFinite(Number(参数对象.bluntPos1XScale)) ? Number(参数对象.bluntPos1XScale) : 200, yscale: isFinite(Number(参数对象.bluntPos1YScale)) ? Number(参数对象.bluntPos1YScale) : 620},
                    {x: isFinite(Number(参数对象.bluntPos2X)) ? Number(参数对象.bluntPos2X) : -33.5, y: isFinite(Number(参数对象.bluntPos2Y)) ? Number(参数对象.bluntPos2Y) : 66.5, xscale: isFinite(Number(参数对象.bluntPos2XScale)) ? Number(参数对象.bluntPos2XScale) : 200, yscale: isFinite(Number(参数对象.bluntPos2YScale)) ? Number(参数对象.bluntPos2YScale) : 620},
                    {x: isFinite(Number(参数对象.bluntPos3X)) ? Number(参数对象.bluntPos3X) : -45, y: isFinite(Number(参数对象.bluntPos3Y)) ? Number(参数对象.bluntPos3Y) : -60, xscale: isFinite(Number(参数对象.bluntPos3XScale)) ? Number(参数对象.bluntPos3XScale) : 240, yscale: isFinite(Number(参数对象.bluntPos3YScale)) ? Number(参数对象.bluntPos3YScale) : 560}
                ]
            },
            长矛: {
                动作类型: 参数对象.actionTypeSpear || "长柄",
                伤害类型: 参数对象.damageTypeSpear || "魔法",
                魔法属性: 参数对象.magicTypeSpear || "电",
                威力倍率: isFinite(Number(参数对象.powerMultSpear)) ? Number(参数对象.powerMultSpear) : 1.0,
                枪头目标: {起始: 2, 结束: 16},
                握柄目标: {起始: 32, 结束: 46},
                刀口: [
                    {x: isFinite(Number(参数对象.spearPos1X)) ? Number(参数对象.spearPos1X) : -28, y: isFinite(Number(参数对象.spearPos1Y)) ? Number(参数对象.spearPos1Y) : 460, xscale: isFinite(Number(参数对象.spearPos1XScale)) ? Number(参数对象.spearPos1XScale) : 220, yscale: isFinite(Number(参数对象.spearPos1YScale)) ? Number(参数对象.spearPos1YScale) : 900},
                    {x: isFinite(Number(参数对象.spearPos2X)) ? Number(参数对象.spearPos2X) : -28, y: isFinite(Number(参数对象.spearPos2Y)) ? Number(参数对象.spearPos2Y) : 260, xscale: isFinite(Number(参数对象.spearPos2XScale)) ? Number(参数对象.spearPos2XScale) : 220, yscale: isFinite(Number(参数对象.spearPos2YScale)) ? Number(参数对象.spearPos2YScale) : 880},
                    {x: isFinite(Number(参数对象.spearPos3X)) ? Number(参数对象.spearPos3X) : -25, y: isFinite(Number(参数对象.spearPos3Y)) ? Number(参数对象.spearPos3Y) : 80, xscale: isFinite(Number(参数对象.spearPos3XScale)) ? Number(参数对象.spearPos3XScale) : 200, yscale: isFinite(Number(参数对象.spearPos3YScale)) ? Number(参数对象.spearPos3YScale) : 760}
                ]
            },
            镰刀: {
                动作类型: 参数对象.actionTypeScythe || "镰刀",
                伤害类型: 参数对象.damageTypeScythe || "魔法",
                魔法属性: 参数对象.magicTypeScythe || "电",
                威力倍率: isFinite(Number(参数对象.powerMultScythe)) ? Number(参数对象.powerMultScythe) : 1.05,
                枪头目标: {起始: 17, 结束: 31},
                握柄目标: {起始: 17, 结束: 31},
                刀口: [
                    {x: isFinite(Number(参数对象.scythePos1X)) ? Number(参数对象.scythePos1X) : -175, y: isFinite(Number(参数对象.scythePos1Y)) ? Number(参数对象.scythePos1Y) : 285, xscale: isFinite(Number(参数对象.scythePos1XScale)) ? Number(参数对象.scythePos1XScale) : 720, yscale: isFinite(Number(参数对象.scythePos1YScale)) ? Number(参数对象.scythePos1YScale) : 580},
                    {x: isFinite(Number(参数对象.scythePos2X)) ? Number(参数对象.scythePos2X) : -95, y: isFinite(Number(参数对象.scythePos2Y)) ? Number(参数对象.scythePos2Y) : 195, xscale: isFinite(Number(参数对象.scythePos2XScale)) ? Number(参数对象.scythePos2XScale) : 460, yscale: isFinite(Number(参数对象.scythePos2YScale)) ? Number(参数对象.scythePos2YScale) : 640},
                    {x: isFinite(Number(参数对象.scythePos3X)) ? Number(参数对象.scythePos3X) : -33.5, y: isFinite(Number(参数对象.scythePos3Y)) ? Number(参数对象.scythePos3Y) : 66.5, xscale: isFinite(Number(参数对象.scythePos3XScale)) ? Number(参数对象.scythePos3XScale) : 220, yscale: isFinite(Number(参数对象.scythePos3YScale)) ? Number(参数对象.scythePos3YScale) : 720}
                ]
            }
        };

        var 刀值:Object = (自机.刀 && 自机.刀.value) ? 自机.刀.value : null;
        var 初始形态:String = (刀值 && 反射对象.形态配置表[刀值.meleeForm])
            ? String(刀值.meleeForm)
            : (反射对象.形态配置表[参数对象.defaultMeleeForm] ? String(参数对象.defaultMeleeForm) : "钝器");
        反射对象.冷兵器模式 = 初始形态;
        if (刀值) 刀值.meleeForm = 初始形态;

        var 威力描述:String = (参数对象.power != undefined) ? String(参数对象.power) : "445%";
        var 威力百分比:Number = Number(威力描述.split("%")[0]);
        反射对象.子弹威力百分比 = (威力描述.indexOf("%") == 威力描述.length - 1 && 威力百分比 > 0) ? (威力百分比 / 100) : 0;
        反射对象.子弹固定威力 = isFinite(Number(参数对象.power)) ? Number(参数对象.power) : 550;

        反射对象.子弹配置 = (typeof _root.子弹属性初始化 == "function")
            ? _root.子弹属性初始化(null, 参数对象.bullet || "诛神闪电", 自机) : null;
        if (!反射对象.子弹配置) {
            反射对象.子弹配置 = {发射者: 自机._name, 子弹种类: 参数对象.bullet || "诛神闪电", 子弹速度: 0, 霰弹值: 1, 子弹散射度: 0};
        }
        反射对象.子弹配置.子弹威力 = 反射对象.子弹威力百分比 > 0
            ? (反射对象.子弹威力百分比 * 反射对象.基础刀锋利度) : 反射对象.子弹固定威力;
        反射对象.子弹配置.Z轴攻击范围 = Number(参数对象.range) || 300;
        反射对象.子弹配置.击倒率 = 1;

        反射对象.成功率 = Number(参数对象.probability) > 0 ? Number(参数对象.probability) : 35;
        反射对象.长枪超载概率 = Number(参数对象.gunProbability) > 0 ? Number(参数对象.gunProbability) : 40;
        反射对象.超载模式 = false;
        反射对象.超载能量 = 0;
        反射对象.超载上限 = Number(参数对象.threshold) > 0 ? Number(参数对象.threshold) : 120;
        反射对象.能量消耗 = Number(参数对象.output) > 0 ? Number(参数对象.output) : 15;
        反射对象.超载触发间隔帧 = isFinite(Number(参数对象.overloadTriggerInterval)) ? Number(参数对象.overloadTriggerInterval) : 6;
        反射对象.上次雷电帧 = -999;
        反射对象.超载威力倍率 = isFinite(Number(参数对象.overloadPowerMult)) ? Number(参数对象.overloadPowerMult) : 1.25;
        反射对象.超载持续帧数 = Number(参数对象.overloadDurationFrames) > 0 ? Number(参数对象.overloadDurationFrames) : 450;
        反射对象.超载冷却毫秒 = Number(参数对象.overloadCooldown) > 0 ? Number(参数对象.overloadCooldown) : 10000;
        反射对象.超载冷却帧数 = Math.max(1, Math.ceil(反射对象.超载冷却毫秒 / 33.33333));
        反射对象.超载结束帧 = 0;
        反射对象.超载冷却结束帧 = 0;
        反射对象.战技释放中 = false;
        反射对象.二阶段待结束超载 = false;

        反射对象.一阶段战技配置 = 参数对象.skill_1 || {
            skillname: 参数对象.stage1Skill || "瞬步斩",
            description: "释放一阶段战技并展开制御板进入超载强化状态。",
            cd: Number(参数对象.stage1Cd) || 1000,
            mp: (参数对象.stage1Mp != undefined) ? 参数对象.stage1Mp : 25,
            skillLocked: true
        };
        反射对象.二阶段战技配置 = 参数对象.skill_2 || {
            skillname: 参数对象.stage2Skill || "凶斩",
            description: "超载状态下释放二阶段终结战技，释放后强制结束超载并进入冷却。",
            cd: 反射对象.超载冷却毫秒,
            mp: (参数对象.stage2Mp != undefined) ? 参数对象.stage2Mp : 40,
            skillLocked: true
        };
    }

    public static function applyBorrowedGunTuning(ref:Object, u:MovieClip, p:Object):Void {
        var src:Object = u.长枪属性 || {};
        var gp:Object = {};
        for (var k:String in src) gp[k] = src[k];

        var bonus:Number = isFinite(Number(u.装备枪械威力加成)) ? Number(u.装备枪械威力加成) : 0;
        gp.dressup = p.gunDressup || "刀-死者之手";
        gp.capacity = Number(p.gunCapacity) > 0 ? Number(p.gunCapacity) : 36;
        gp.split = Number(p.gunSplit) > 0 ? Number(p.gunSplit) : 1;
        gp.diffusion = isFinite(Number(p.gunDiffusion)) ? Number(p.gunDiffusion) : 2;
        gp.interval = Number(p.gunInterval) > 0 ? Number(p.gunInterval) : 135;
        gp.velocity = Number(p.gunVelocity) > 0 ? Number(p.gunVelocity) : 35;
        gp.bullet = p.gunBullet || "能量普通子弹";
        gp.sound = p.gunSound || "re_Rifle_L85A2.wav";
        gp.muzzle = p.gunMuzzle || "能量枪火";
        gp.bullethit = p.gunBulletHit || "能量火花";
        gp.clipname = p.gunClipName || "突击步枪通用弹药";
        gp.bulletsize = Number(p.gunBulletSize) > 0 ? Number(p.gunBulletSize) : 25;
        gp.impact = Number(p.gunImpact) > 0 ? Number(p.gunImpact) : 45;
        gp.reloadPenalty = isFinite(Number(p.gunReloadPenalty)) ? Number(p.gunReloadPenalty) : 0;
        gp.singleshoot = (p.gunSingleShoot === true || p.gunSingleShoot == "true");
        gp.weapontype = p.gunWeaponType || "突击步枪";

        var baseGunPow:Number = Math.floor(ref.基础刀锋利度 * ref.长枪威力系数) + bonus;
        if (!isFinite(baseGunPow) || baseGunPow < 1) baseGunPow = 100;
        ref.基础长枪威力 = baseGunPow;
        gp.power = baseGunPow;

        u.长枪属性 = gp;
        u.长枪_装扮 = gp.dressup;
        var gunAct:String = (p.gunActionType != undefined && p.gunActionType != "") ? String(p.gunActionType) : undefined;
        u.长枪动作类型 = gunAct;
        if (u.长枪数据) {
            u.长枪数据.actiontype = gunAct;
            u.长枪数据.weapontype = gp.weapontype;
            u.长枪数据.data = gp;
        }
        u.长枪弹匣容量 = gp.capacity;
        u.长枪伤害类型 = p.damageTypeGun || "魔法";
        u.长枪魔法伤害属性 = p.magicTypeGun || "电";
    }

    public static function syncBladeClip(bladeClip:MovieClip, ref:Object, showBlade:Boolean, cfg:Object):Void {
        if (!bladeClip) return;
        bladeClip._visible = showBlade;
        if (cfg && cfg.刀口) {
            for (var i:Number = 0; i < 3; i++) {
                var edgeMc:MovieClip = bladeClip["刀口位置" + (i + 1)];
                var ep:Object = cfg.刀口[i];
                if (edgeMc && ep) {
                    edgeMc._x = ep.x;
                    edgeMc._y = ep.y;
                    edgeMc._xscale = ep.xscale;
                    edgeMc._yscale = ep.yscale;
                }
            }
        }
        if (bladeClip.枪头组件) bladeClip.枪头组件.gotoAndStop(ref.枪头当前帧);
        if (bladeClip.握柄组件) bladeClip.握柄组件.gotoAndStop(ref.握柄当前帧);
        if (bladeClip.御坂组件) bladeClip.御坂组件.gotoAndStop(ref.御坂当前帧);
    }

    public static function syncGunClip(gunClip:MovieClip, ref:Object, showGun:Boolean):Void {
        if (!gunClip) return;
        gunClip._visible = showGun;
        if (showGun) {
            gunClip._rotation = ref.长枪旋转角度;
            gunClip._x = ref.长枪偏移X;
            gunClip._y = ref.长枪偏移Y;
        }
        if (!gunClip.枪口位置 && typeof gunClip.createEmptyMovieClip == "function") {
            var d:Number = (typeof gunClip.getNextHighestDepth == "function") ? gunClip.getNextHighestDepth() : 99;
            gunClip.createEmptyMovieClip("枪口位置", d);
        }
        if (gunClip.枪口位置) {
            gunClip.枪口位置._x = ref.枪口偏移X;
            gunClip.枪口位置._y = ref.枪口偏移Y;
        }
        if (gunClip.枪头组件) gunClip.枪头组件.gotoAndStop(ref.枪头当前帧);
        if (gunClip.握柄组件) gunClip.握柄组件.gotoAndStop(ref.握柄当前帧);
        if (gunClip.御坂组件) gunClip.御坂组件.gotoAndStop(ref.御坂当前帧);
    }
}
