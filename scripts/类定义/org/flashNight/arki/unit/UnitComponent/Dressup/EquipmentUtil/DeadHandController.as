import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.*;

/** 死者之手的多形态与超载控制；帧脚本仅登记入口，延迟回调归属此类。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandController {
    public static function 死者之手推进组件帧(cur:Number, startF:Number, endF:Number):Number {
        var f:Number = Math.floor(Number(cur));
        if (!isFinite(f) || f < 1) f = 1;
        if (!(endF > 1)) {
            if (f <= 2 || f == 17 || f == 32) return 1;
            var curSeg:Number = (f >= 32) ? 32 : ((f >= 17) ? 17 : 2);
            return (f - 2 > curSeg) ? (f - 2) : 1;
        }
        if (f >= startF && f <= endF) {
            if (f >= endF) return endF;
            return (f + 2 <= endF) ? (f + 2) : endF;
        }
        if (f <= 1) return (startF + 1 <= endF) ? (startF + 1) : startF;
        if (f == 2 || f == 17 || f == 32) return (startF + 2 <= endF) ? (startF + 2) : endF;
        var seg:Number = (f >= 32) ? 32 : ((f >= 17) ? 17 : 2);
        return (f - 2 > seg) ? (f - 2) : seg;
    }

    public static function 死者之手判定武器模式(ref:Object):String {
        if (!ref || ref.已卸载 || !ref.自机 || ref.自机.__deadHandOwner !== ref
                || ref.自机.version !== ref.版本号 || ref.自机.刀 !== ref.武器条目) return "收纳";
        var u:MovieClip = ref.自机;
        if ((u.man && u.man.兵器使用标签) || (typeof _root.兵器使用检测 == "function" && _root.兵器使用检测(u))) {
            return "兵器";
        }
        var proj:Object = org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        if (u.攻击模式 == "长枪" && proj.hasActiveAlias(u, "长枪", "刀")
                && u.长枪 === ref.武器条目) {
            return "长枪";
        }
        if (u.攻击模式 == "兵器" && u.刀 === ref.武器条目) {
            return "兵器";
        }
        return "收纳";
    }

    public static function 死者之手是否持有模式(ref:Object):Boolean {
        return _root.装备生命周期函数.死者之手判定武器模式(ref) != "收纳";
    }

    public static function 死者之手配置借用长枪(ref:Object, p:Object):Void {
        var u:MovieClip = ref.自机;
        var proj:Object = org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        if (!u || !proj.hasActiveAlias(u, "长枪", "刀")) return;

        DeadHandTuning.applyBorrowedGunTuning(ref, u, p);

        org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime.ensure(u, "长枪", true);
        if (u.攻击模式 == "长枪" && typeof u.man.初始化长枪射击函数 == "function") {
            u.man.初始化长枪射击函数();
        }
    }

    public static function 死者之手更新形态属性(ref:Object):Void {
        if (!ref || ref.已卸载 || !ref.自机) return;
        var u:MovieClip = ref.自机;
        var cfg:Object = ref.形态配置表[ref.冷兵器模式] || ref.形态配置表["钝器"];
        var ovMult:Number = ref.超载模式 ? ref.超载威力倍率 : 1;
        var finalMult:Number = cfg.威力倍率 * ovMult;

        u.兵器动作类型 = cfg.动作类型;
        u.兵器伤害类型 = cfg.伤害类型;
        u.兵器魔法伤害属性 = cfg.魔法属性;
        if (u.刀属性) {
            u.刀属性.damagetype = cfg.伤害类型;
            u.刀属性.magictype = cfg.魔法属性;
        }

        var bm:Object = u.buffManager;
        if (bm && typeof bm.addBuffImmediate == "function") {
            var baseVal:Number = (typeof bm.getBaseValue == "function") ? Number(bm.getBaseValue("刀属性.power")) : Number.NaN;
            if (isFinite(baseVal) && baseVal > 0) ref.基础刀锋利度 = baseVal;
            if (ref.刀威力Pod && bm.getBuffById(ref.刀威力BuffId) === ref.刀威力Pod) {
                ref.刀威力Pod.deactivate();
                bm.removeBuff(ref.刀威力BuffId);
            }
            if (Math.abs(finalMult - 1) > 0.0001) {
                ref.刀威力Pod = new PodBuff("刀属性.power", BuffCalculationType.PERCENT, finalMult - 1);
                bm.addBuffImmediate(ref.刀威力Pod, ref.刀威力BuffId);
            } else {
                ref.刀威力Pod = null;
                bm.update(0);
            }
        } else if (u.刀属性) {
            u.刀属性.power = Math.floor(ref.基础刀锋利度 * finalMult);
        }
        ref.当前应用刀锋利度 = u.刀属性 ? Number(u.刀属性.power) : ref.基础刀锋利度;

        var proj:Object = org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        if (proj.hasActiveAlias(u, "长枪", "刀") && u.长枪属性) {
            var bonus:Number = isFinite(Number(u.装备枪械威力加成)) ? Number(u.装备枪械威力加成) : 0;
            ref.基础长枪威力 = Math.floor(ref.基础刀锋利度 * ref.长枪威力系数) + bonus;
            u.长枪属性.power = Math.floor(ref.基础长枪威力 * ovMult);
            u.长枪伤害类型 = ref.长枪伤害类型配置;
            u.长枪魔法伤害属性 = ref.长枪魔法属性配置;
            if (u.攻击模式 == "长枪" && u.man && typeof u.man.初始化长枪射击函数 == "function") {
                var prevBulletProps:Object = u.man.子弹属性;
                u.man.初始化长枪射击函数();
                if (prevBulletProps && u.man.子弹属性 && prevBulletProps !== u.man.子弹属性) {
                    for (var bpk:String in u.man.子弹属性) {
                        prevBulletProps[bpk] = u.man.子弹属性[bpk];
                    }
                    u.man.子弹属性 = prevBulletProps;
                }
            }
        }

        if (ref.子弹配置) {
            ref.子弹配置.子弹威力 = ref.子弹威力百分比 > 0
                ? (ref.子弹威力百分比 * ref.当前应用刀锋利度)
                : (ref.子弹固定威力 * ovMult);
        }
        if (typeof u.根据模式重新读取武器加成 == "function" && (u.攻击模式 == "兵器" || u.攻击模式 == "长枪")) {
            u.根据模式重新读取武器加成(u.攻击模式);
        }
    }

    public static function 死者之手同步视觉(ref:Object):Void {
        if (!ref || ref.已卸载 || !ref.自机 || ref.自机.__deadHandOwner !== ref
                || ref.自机.version !== ref.版本号 || ref.自机.刀 !== ref.武器条目) return;
        var u:MovieClip = ref.自机;
        var mode:String = _root.装备生命周期函数.死者之手判定武器模式(ref);
        ref.当前武器模式 = mode;
        var hasAlias:Boolean = org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.hasActiveAlias(u, "长枪", "刀");
        DeadHandVisual.sync(ref, mode, hasAlias);
    }

    public static function 死者之手触发超载雷电(ref:Object, freeShot:Boolean):Void {
        if (!ref || !ref.子弹配置 || !ref.自机) return;
        var u:MovieClip = ref.自机;
        var nowF:Number = (_root.帧计时器 && isFinite(Number(_root.帧计时器.当前帧数))) ? Number(_root.帧计时器.当前帧数) : 0;
        if (!freeShot && ref.超载触发间隔帧 > 0 && ref.上次雷电帧 > 0 && nowF > 0
                && nowF >= ref.上次雷电帧 && (nowF - ref.上次雷电帧) < ref.超载触发间隔帧) {
            return;
        }

        var sx:Number = isFinite(Number(u._x)) ? Number(u._x) : 0;
        var sy:Number = isFinite(Number(u._y)) ? Number(u._y) : 0;
        var sz:Number = isFinite(Number(u.Z轴坐标)) ? Number(u.Z轴坐标) : sy;
        var pt:Object = {x: 0, y: 0};

        if (ref.当前武器模式 == "长枪") {
            var tcm:Object = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
            var enemy:MovieClip = (tcm && typeof tcm.findNearestEnemyAtPoint2D == "function")
                ? tcm.findNearestEnemyAtPoint2D(u, 5, sx, sz, 650, ref.子弹配置.Z轴攻击范围 || 240, null) : null;
            if (enemy && enemy.hp > 0 && isFinite(Number(enemy._x))) {
                sx = Number(enemy._x);
                sy = isFinite(Number(enemy._y)) ? Number(enemy._y) : sy;
                sz = isFinite(Number(enemy.Z轴坐标)) ? Number(enemy.Z轴坐标) : sy;
            } else {
                var gunMc:MovieClip = (u.man && u.man.枪 && u.man.枪.枪 && u.man.枪.枪.装扮) ? u.man.枪.枪.装扮 : u.长枪_引用;
                var gunAnchor:MovieClip = gunMc ? (gunMc.枪口位置 || gunMc.刀口位置1 || gunMc) : null;
                if (gunAnchor && typeof gunAnchor.localToGlobal == "function"
                        && _root.gameworld && typeof _root.gameworld.globalToLocal == "function") {
                    gunAnchor.localToGlobal(pt);
                    _root.gameworld.globalToLocal(pt);
                    sx = pt.x;
                }
                var dirSign:Number = (u._xscale < 0 || u.方向 == "左") ? -1 : 1;
                sx += dirSign * 180;
            }
        } else {
            var bladeMc:MovieClip = (u.man && u.man.刀 && u.man.刀.刀 && u.man.刀.刀.装扮) ? u.man.刀.刀.装扮 : u.刀_引用;
            var bladeAnchor:MovieClip = bladeMc ? (bladeMc.刀口位置1 || bladeMc.刀口位置2 || bladeMc.刀口位置3 || bladeMc) : null;
            if (bladeAnchor && typeof bladeAnchor.localToGlobal == "function"
                    && _root.gameworld && typeof _root.gameworld.globalToLocal == "function") {
                bladeAnchor.localToGlobal(pt);
                _root.gameworld.globalToLocal(pt);
                sx = pt.x;
            }
        }

        ref.子弹配置.发射者 = u._name;
        ref.子弹配置.shootX = sx;
        ref.子弹配置.shootY = sy;
        ref.子弹配置.shootZ = sz;

        if (typeof _root.子弹区域shoot传递 != "function") return;
        _root.子弹区域shoot传递(ref.子弹配置);
        ref.上次雷电帧 = nowF;
        if (!freeShot) {
            ref.超载能量 -= ref.能量消耗;
            if (ref.超载能量 < ref.能量消耗 && !ref.二阶段待结束超载) {
                _root.装备生命周期函数.死者之手结束超载(ref, true, false);
            }
        }
    }

    public static function 死者之手装载阶段战技(ref:Object, stage:Number):Void {
        if (!ref || ref.已卸载 || !ref.自机) return;
        var u:MovieClip = ref.自机;
        var stg:Number = (stage == 2) ? 2 : 1;
        ref.当前战技阶段 = stg;
        var scfg:Object = (stg == 2) ? ref.二阶段战技配置 : ref.一阶段战技配置;
        if (!scfg || !scfg.skillname) return;

        if (!u.主动战技) {
            u.主动战技 = (_root.主角函数 && _root.主角函数.创建主动战技槽位表)
                ? _root.主角函数.创建主动战技槽位表()
                : {空手: null, 兵器: null, 长枪: null, 手枪: null, 手枪2: null};
        }
        if (typeof u.装载主动战技 == "function") {
            u.装载主动战技(scfg, "兵器", ref.装备名称);
        }

        var tbl:Object = _root.主动战技函数 ? _root.主动战技函数.兵器 : null;
        var baseFn:Object = (tbl && tbl[scfg.skillname]) ? tbl[scfg.skillname] : null;

        if (!u.主动战技.兵器 || u.主动战技.兵器.名字 != scfg.skillname) {
            u.主动战技.兵器 = {
                名字: scfg.skillname,
                装备来源: ref.装备名称,
                描述: scfg.description,
                冷却时间: Number(scfg.cd) > 100 ? Number(scfg.cd) : 1000,
                消耗hp: 0,
                消耗mp: Number(scfg.mp) > 0 ? Number(scfg.mp) : 0,
                消耗sp: 0,
                技能等级: 1
            };
        }

        u.主动战技.兵器.战技函数 = createSkillFunctions(ref, stg, baseFn, false);
        if (org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.hasActiveAlias(u, "长枪", "刀")) {
            var bs:Object = u.主动战技.兵器;
            u.主动战技.长枪 = {
                名字: bs.名字, iconKey: bs.iconKey, 装备来源: bs.装备来源, 描述: bs.描述, 信息: bs.信息,
                冷却时间: bs.冷却时间, 消耗hp: bs.消耗hp, 消耗mp: bs.消耗mp, 消耗sp: bs.消耗sp, 技能等级: bs.技能等级,
                战技函数: createSkillFunctions(ref, stg, baseFn, true)
            };
        }

        if (ref.是否为主角 && _root.玩家信息界面 && _root.玩家信息界面.玩家必要信息界面
                && _root.玩家信息界面.玩家必要信息界面.战技栏
                && typeof _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新 == "function") {
            _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
        }
    }

    public static function 死者之手开启超载(ref:Object):Boolean {
        if (!ref || ref.已卸载 || !死者之手是否持有模式(ref)) return false;
        var nowF:Number = (_root.帧计时器 && isFinite(Number(_root.帧计时器.当前帧数))) ? Number(_root.帧计时器.当前帧数) : 0;
        if (nowF < ref.超载冷却结束帧) return false;

        ref.超载模式 = true;
        ref.二阶段待结束超载 = false;
        ref.超载能量 = ref.超载上限;
        ref.超载结束帧 = nowF + ref.超载持续帧数;
        ref.御坂最大帧 = 16;

        _root.装备生命周期函数.死者之手更新形态属性(ref);
        _root.装备生命周期函数.死者之手装载阶段战技(ref, 2);

        var u:MovieClip = ref.自机;
        if (u && typeof _root.效果 == "function" && isFinite(Number(u._x))) {
            _root.效果("紫金增幅", u._x, u._y, u._xscale);
        }
        return true;
    }

    public static function 死者之手结束超载(ref:Object, enterCd:Boolean, fromStage2:Boolean):Void {
        if (!ref) return;
        var nowF:Number = (_root.帧计时器 && isFinite(Number(_root.帧计时器.当前帧数))) ? Number(_root.帧计时器.当前帧数) : 0;

        ref.超载模式 = false;
        ref.二阶段待结束超载 = false;
        ref.超载能量 = 0;
        ref.超载结束帧 = 0;
        ref.御坂最大帧 = 1;

        if (enterCd) {
            ref.超载冷却结束帧 = nowF + ref.超载冷却帧数;
            if (ref.是否为主角) {
                var cdSvc:Object = org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
                cdSvc.reset(cdSvc.WEAPON_SKILL_KEY);
                cdSvc.start(cdSvc.WEAPON_SKILL_KEY, ref.超载冷却毫秒);
            }
        }
        if (!ref.已卸载) {
            _root.装备生命周期函数.死者之手更新形态属性(ref);
            _root.装备生命周期函数.死者之手装载阶段战技(ref, 1);
        }
    }

    public static function 死者之手切换冷兵器形态(ref:Object, targetForm:String):String {
        if (!ref || ref.已卸载) return null;
        var u:MovieClip = ref.自机;
        var seq:Array = ref.形态顺序;
        var nextForm:String = targetForm;

        if (!nextForm || !ref.形态配置表[nextForm]) {
            var idx:Number = 0;
            for (var i:Number = 0; i < seq.length; i++) {
                if (seq[i] == ref.冷兵器模式) { idx = i; break; }
            }
            nextForm = seq[(idx + 1) % seq.length];
        }

        ref.冷兵器模式 = nextForm;
        if (u && u.刀 && u.刀.value) u.刀.value.meleeForm = nextForm;

        _root.装备生命周期函数.死者之手更新形态属性(ref);
        _root.装备生命周期函数.死者之手同步视觉(ref);
        if (ref.是否为主角 && targetForm == null && typeof _root.发布消息 == "function") {
            _root.发布消息("死者之手切换为[" + nextForm + "]形态");
        }
        return nextForm;
    }

    public static function 死者之手处理武器切换(ref:Object):Void {
        if (!ref || ref.已卸载 || !ref.自机) return;
        var u:MovieClip = ref.自机;

        if (!_root.装备生命周期函数.死者之手是否持有模式(ref)) {
            if ((ref.超载模式 || ref.战技释放中) && (u.状态 == "技能" || u.状态 == "战技")) {
                ref.战技释放中 = false;
                ref.二阶段待结束超载 = false;
                u.技能名 = null;
                if (typeof u.状态改变 == "function") u.状态改变(u.攻击模式 + "站立");
                else u.状态 = u.攻击模式 + "站立";
            }
            if (ref.超载模式) {
                _root.装备生命周期函数.死者之手结束超载(ref, true, false);
            }
        }
        if (_root.装备生命周期函数.死者之手判定武器模式(ref) == "长枪") {
            _root.装备生命周期函数.死者之手更新形态属性(ref);
        }
        _root.装备生命周期函数.死者之手同步视觉(ref);
    }

    public static function 死者之手卸载(ref:Object):Void {
        if (!ref || ref.已卸载) return;
        ref.已卸载 = true;
        ref.超载模式 = false;
        ref.二阶段待结束超载 = false;
        ref.超载能量 = 0;
        ref.御坂最大帧 = 1;

        var u:MovieClip = ref.自机;
        if (u) {
            var bm:Object = u.buffManager;
            if (bm && ref.刀威力Pod && bm.getBuffById(ref.刀威力BuffId) === ref.刀威力Pod) {
                ref.刀威力Pod.deactivate();
                bm.removeBuff(ref.刀威力BuffId);
                bm.update(0);
            }
            ref.刀威力Pod = null;

            if (u.刀口位置生成子弹 === ref.包装刀口位置生成子弹) {
                u.刀口位置生成子弹 = ref.原始刀口位置生成子弹;
            }
            if (u.长枪射击 === ref.包装长枪射击) {
                u.长枪射击 = ref.原始长枪射击;
            }
            ref.包装刀口位置生成子弹 = ref.原始刀口位置生成子弹 = null;
            ref.包装长枪射击 = ref.原始长枪射击 = null;

            if (u.__deadHandOwner === ref && ref.战技释放中 && (u.状态 == "技能" || u.状态 == "战技")) {
                ref.战技释放中 = false;
                u.技能名 = null;
                if (typeof u.状态改变 == "function") u.状态改变(u.攻击模式 + "站立");
                else u.状态 = u.攻击模式 + "站立";
            }
            if (u.刀 === ref.武器条目 && u.刀属性 === ref.原始刀属性) {
                // Removing our Pod must preserve buffs owned by other equipment.
                if (!bm || typeof bm.addBuffImmediate != "function") u.刀属性.power = ref.基础刀锋利度;
                u.刀属性.damagetype = ref.原始刀伤害类型;
                u.刀属性.magictype = ref.原始刀魔法属性;
                u.兵器动作类型 = ref.原始兵器动作类型;
                u.兵器伤害类型 = ref.原始兵器伤害类型;
                u.兵器魔法伤害属性 = ref.原始兵器魔法伤害属性;
            }
            DeadHandVisual.release(ref);
            if (u.主动战技 && u.主动战技.长枪 && u.主动战技.长枪.装备来源 === ref.装备名称) {
                u.主动战技.长枪 = null;
            }
            var disp:Object = u.dispatcher;
            if (disp) {
                if (ref.刀视觉回调) disp.unsubscribe("刀_引用", ref.刀视觉回调, ref);
                if (ref.长枪视觉回调) disp.unsubscribe("长枪_引用", ref.长枪视觉回调, ref);
                if (ref.战技事件回调) disp.unsubscribe("WeaponSkill", ref.战技事件回调, ref);
                if (ref.模式切换回调) disp.unsubscribe("attackModeChanged", ref.模式切换回调, ref);
                if (ref.射击事件回调) disp.unsubscribe("processShot", ref.射击事件回调, ref);
            }
            if (u.__deadHandOwner === ref) delete u.__deadHandOwner;
        }
        ref.刀视觉回调 = ref.长枪视觉回调 = ref.战技事件回调 = ref.模式切换回调 = ref.射击事件回调 = null;
    }

    public static function 死者之手初始化(反射对象:Object, 参数对象:Object):Void {
        var 自机:MovieClip = 反射对象.自机;
        var proj:Object = org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        if (反射对象.装备类型 == "长枪" && proj.hasActiveAlias(自机, "长枪", "刀")) {
            _root.装备生命周期函数.移除周期函数(反射对象);
            return;
        }
        if (自机.__deadHandOwner && 自机.__deadHandOwner !== 反射对象) {
            _root.装备生命周期函数.死者之手卸载(自机.__deadHandOwner);
        }

        参数对象 = 参数对象 || {};
        反射对象.已卸载 = false;
        反射对象.武器条目 = 自机[反射对象.装备类型];
        反射对象.原始刀属性 = 自机.刀属性;
        反射对象.基础刀锋利度 = (自机.刀属性 && isFinite(Number(自机.刀属性.power))) ? Number(自机.刀属性.power) : 550;
        反射对象.原始兵器动作类型 = 自机.兵器动作类型;
        反射对象.原始兵器伤害类型 = 自机.兵器伤害类型;
        反射对象.原始兵器魔法伤害属性 = 自机.兵器魔法伤害属性;
        反射对象.原始刀伤害类型 = 自机.刀属性.damagetype;
        反射对象.原始刀魔法属性 = 自机.刀属性.magictype;
        反射对象.刀威力BuffId = "dead_hand_blade_power_" + (反射对象.标签名 || "default");
        反射对象.刀威力Pod = null;
        自机.__deadHandOwner = 反射对象;

        DeadHandTuning.configureMount(反射对象, 参数对象);

        var 借用意图:Object = proj.reserveEmptySlotAlias(反射对象, "长枪");
        if (借用意图 != null) {
            _root.长枪配置(自机._name, "死者之手", 1);
            反射对象.借用长枪槽 = proj.commitSlotAlias(借用意图);
            if (反射对象.借用长枪槽) {
                _root.装备生命周期函数.死者之手配置借用长枪(反射对象, 参数对象);
            } else {
                proj.cancelSlotAlias(借用意图);
            }
        } else {
            反射对象.借用长枪槽 = false;
        }

        DeadHandTuning.configureCombat(反射对象, 参数对象);

        反射对象.当前武器模式 = _root.装备生命周期函数.死者之手判定武器模式(反射对象);
        反射对象.变形键按下 = _root.按键输入检测(自机, _root.武器变形键) ? true : false;
        if (反射对象.当前武器模式 == "兵器") {
            var initCfg:Object = 反射对象.形态配置表[反射对象.冷兵器模式] || 反射对象.形态配置表["钝器"];
            反射对象.枪头当前帧 = 反射对象.枪头最大帧 = initCfg.枪头目标.结束;
            反射对象.握柄当前帧 = 反射对象.握柄最大帧 = initCfg.握柄目标.结束;
        } else if (反射对象.当前武器模式 == "长枪") {
            反射对象.枪头当前帧 = 反射对象.枪头最大帧 = 46;
            反射对象.握柄当前帧 = 反射对象.握柄最大帧 = 31;
        } else {
            反射对象.枪头当前帧 = 反射对象.枪头最大帧 = 1;
            反射对象.握柄当前帧 = 反射对象.握柄最大帧 = 1;
        }
        反射对象.御坂当前帧 = 反射对象.御坂最大帧 = 1;

        _root.装备生命周期函数.死者之手更新形态属性(反射对象);
        _root.装备生命周期函数.死者之手装载阶段战技(反射对象, 1);
        _root.装备生命周期函数.死者之手同步视觉(反射对象);

        if (typeof 自机.刀口位置生成子弹 == "function") {
            反射对象.原始刀口位置生成子弹 = 自机.刀口位置生成子弹;
            反射对象.包装刀口位置生成子弹 = function() {
                if (!反射对象.已卸载 && 自机.__deadHandOwner === 反射对象 && 自机.刀 === 反射对象.武器条目) {
                    var c:Object = 反射对象.形态配置表[反射对象.冷兵器模式] || 反射对象.形态配置表["钝器"];
                    if (自机.兵器动作类型 !== c.动作类型 || 自机.兵器伤害类型 !== c.伤害类型 || 自机.兵器魔法伤害属性 !== c.魔法属性) {
                        _root.装备生命周期函数.死者之手更新形态属性(反射对象);
                    }
                    _root.装备生命周期函数.死者之手同步视觉(反射对象);
                }
                return 反射对象.原始刀口位置生成子弹.apply(this, arguments);
            };
            自机.刀口位置生成子弹 = 反射对象.包装刀口位置生成子弹;
        }
        if (typeof 自机.长枪射击 == "function") {
            反射对象.原始长枪射击 = 自机.长枪射击;
            反射对象.包装长枪射击 = function(muzzle:MovieClip, bulletProps:Object):Boolean {
                if (!反射对象.已卸载 && 自机.__deadHandOwner === 反射对象
                        && org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.hasActiveAlias(自机, "长枪", "刀")
                        && 自机.长枪 === 反射对象.武器条目) {
                    if (自机.长枪伤害类型 !== 反射对象.长枪伤害类型配置 || 自机.长枪魔法伤害属性 !== 反射对象.长枪魔法属性配置) {
                        _root.装备生命周期函数.死者之手更新形态属性(反射对象);
                    }
                    _root.装备生命周期函数.死者之手同步视觉(反射对象);
                    if (!muzzle || isNaN(muzzle._x)) muzzle = 反射对象.长枪视觉.枪口位置;
                    if (!muzzle || isNaN(muzzle._x)) return false;
                    if (bulletProps) {
                        if (自机.长枪属性) {
                            if (!bulletProps.子弹种类) bulletProps.子弹种类 = 自机.长枪属性.bullet;
                            if (!bulletProps.发射效果) bulletProps.发射效果 = 自机.长枪属性.muzzle;
                            if (!bulletProps.击中地图效果) bulletProps.击中地图效果 = 自机.长枪属性.bullethit;
                        }
                        bulletProps.伤害类型 = 反射对象.长枪伤害类型配置;
                        bulletProps.魔法伤害属性 = 反射对象.长枪魔法属性配置;
                    }
                }
                return 反射对象.原始长枪射击.call(this, muzzle, bulletProps);
            };
            自机.长枪射击 = 反射对象.包装长枪射击;
        }

        反射对象.刀视觉回调 = PlacementVisual.hookVisualUpdate(
            自机, "刀_引用", 反射对象, _root.装备生命周期函数.死者之手同步视觉, 反射对象);
        反射对象.长枪视觉回调 = PlacementVisual.hookVisualUpdate(
            自机, "长枪_引用", 反射对象, _root.装备生命周期函数.死者之手同步视觉, 反射对象);

        if (自机.dispatcher) {
            反射对象.战技事件回调 = function(mode:String):Void {
                if (反射对象.已卸载 || !_root.装备生命周期函数.死者之手是否持有模式(反射对象)) return;
                var ok:Boolean = (mode == "兵器") || (mode == "长枪" && org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.hasActiveAlias(反射对象.自机, "长枪", "刀"));
                if (!ok) return;
                if (!反射对象.超载模式) {
                    _root.装备生命周期函数.死者之手开启超载(反射对象);
                } else {
                    _root.装备生命周期函数.死者之手触发超载雷电(反射对象, true);
                    var uRef:MovieClip = 反射对象.自机;
                    if (反射对象.战技释放中 && uRef && (uRef.状态 == "技能" || uRef.状态 == "战技")) {
                        反射对象.二阶段待结束超载 = true;
                    } else {
                        _root.装备生命周期函数.死者之手结束超载(反射对象, true, true);
                    }
                }
            };
            自机.dispatcher.subscribe("WeaponSkill", 反射对象.战技事件回调, 反射对象);

            反射对象.模式切换回调 = function() {
                _root.装备生命周期函数.死者之手处理武器切换(反射对象);
            };
            自机.dispatcher.subscribe("attackModeChanged", 反射对象.模式切换回调, 反射对象);

            反射对象.射击事件回调 = function(shooter:Object, wType:String):Void {
                if (反射对象.已卸载 || !反射对象.超载模式 || shooter !== 反射对象.自机
                        || !_root.装备生命周期函数.死者之手是否持有模式(反射对象)) return;
                if (!EquipmentFireIntent.isMainLongGunProcessShot(反射对象.自机, wType)) return;
                if (!org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.hasActiveAlias(反射对象.自机, "长枪", "刀")) return;
                if (typeof _root.成功率 != "function" || _root.成功率(反射对象.长枪超载概率)) {
                    _root.装备生命周期函数.死者之手触发超载雷电(反射对象, false);
                }
            };
            自机.dispatcher.subscribe("processShot", 反射对象.射击事件回调, 反射对象);
        }

        if (!反射对象.生命周期函数列表) 反射对象.生命周期函数列表 = [];
        反射对象.卸载对象 = {动作: _root.装备生命周期函数.死者之手卸载, 额外参数: 反射对象};
        反射对象.生命周期函数列表.push(反射对象.卸载对象);
    }

    public static function 死者之手周期(ref:Object, param:Object):Void {
        if (!EquipmentTick.open(ref)) return;
        if (ref.已卸载 || !ref.自机) return;

        var u:MovieClip = ref.自机;
        var proj:Object = org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        var curCfg:Object = ref.形态配置表[ref.冷兵器模式] || ref.形态配置表["钝器"];
        if (u.兵器动作类型 !== curCfg.动作类型 || u.兵器伤害类型 !== curCfg.伤害类型 || u.兵器魔法伤害属性 !== curCfg.魔法属性
                || (proj.hasActiveAlias(u, "长枪", "刀") && (u.长枪伤害类型 !== ref.长枪伤害类型配置 || u.长枪魔法伤害属性 !== ref.长枪魔法属性配置
                    || (u.攻击模式 == "长枪" && u.man && typeof u.man.初始化长枪射击函数 == "function"
                        && (!u.man.子弹属性 || (u.长枪属性 && u.man.子弹属性.子弹种类 !== u.长枪属性.bullet)))))) {
            _root.装备生命周期函数.死者之手更新形态属性(ref);
        }

        var curMode:String = _root.装备生命周期函数.死者之手判定武器模式(ref);
        if (curMode != ref.当前武器模式) {
            ref.当前武器模式 = curMode;
            _root.装备生命周期函数.死者之手处理武器切换(ref);
        }
        if (ref.战技释放中 && u.状态 != "技能" && u.状态 != "战技") {
            ref.战技释放中 = false;
            if (ref.二阶段待结束超载 && ref.超载模式) {
                ref.二阶段待结束超载 = false;
                _root.装备生命周期函数.死者之手触发超载雷电(ref, true);
                _root.装备生命周期函数.死者之手结束超载(ref, true, true);
            }
        }

        var rise:Boolean = KeyEdgeTrigger.onRise(ref, u, _root.武器变形键, "变形键按下");
        if (!_root.暂停 && rise && u.攻击模式 == "兵器" && u.状态 != "技能" && u.状态 != "战技") {
            _root.装备生命周期函数.死者之手切换冷兵器形态(ref, null);
        }

        var nowF:Number = (_root.帧计时器 && isFinite(Number(_root.帧计时器.当前帧数))) ? Number(_root.帧计时器.当前帧数) : 0;
        var isAttackingMelee:Boolean = (typeof _root.兵器攻击检测 == "function" && _root.兵器攻击检测(u));
        if (!_root.暂停 && ref.当前武器模式 == "兵器" && isAttackingMelee && u.刀_引用) {
            var trailRenderer:Object = org.flashNight.arki.render.BladeMotionTrailsRenderer;
            if (trailRenderer && typeof trailRenderer.processBladeTrail == "function") {
                trailRenderer.processBladeTrail(u, u.刀_引用, ref.超载模式 ? "蓝色魅影" : "白色蓝框");
            }
        }
        if (ref.超载模式) {
            if (!ref.二阶段待结束超载 && (ref.超载能量 < ref.能量消耗 || (ref.超载结束帧 > 0 && nowF >= ref.超载结束帧))) {
                _root.装备生命周期函数.死者之手结束超载(ref, true, false);
            } else if (!_root.暂停 && ref.当前武器模式 == "兵器" && isAttackingMelee
                    && (typeof _root.成功率 != "function" || _root.成功率(ref.成功率))) {
                _root.装备生命周期函数.死者之手触发超载雷电(ref, false);
            }
        }

        var hs:Number = 1, he:Number = 1, gs:Number = 1, gripEnd:Number = 1, bs:Number = 1, be:Number = 1;
        if (ref.当前武器模式 == "兵器") {
            var cfg:Object = ref.形态配置表[ref.冷兵器模式] || ref.形态配置表["钝器"];
            hs = cfg.枪头目标.起始; he = cfg.枪头目标.结束;
            gs = cfg.握柄目标.起始; gripEnd = cfg.握柄目标.结束;
            if (ref.超载模式) { bs = 2; be = 16; }
        } else if (ref.当前武器模式 == "长枪") {
            hs = 32; he = 46;
            gs = ref.超载模式 ? 32 : 17;
            gripEnd = ref.超载模式 ? 46 : 31;
            if (ref.超载模式) { bs = 2; be = 16; }
        }

        ref.枪头最大帧 = he;
        ref.握柄最大帧 = gripEnd;
        ref.御坂最大帧 = be;

        if (!_root.暂停) {
            ref.枪头当前帧 = _root.装备生命周期函数.死者之手推进组件帧(ref.枪头当前帧, hs, he);
            ref.握柄当前帧 = _root.装备生命周期函数.死者之手推进组件帧(ref.握柄当前帧, gs, gripEnd);
            ref.御坂当前帧 = _root.装备生命周期函数.死者之手推进组件帧(ref.御坂当前帧, bs, be);
        }

        _root.装备生命周期函数.死者之手同步视觉(ref);
    }

    // Factory parameters remain in activation scope after the loader MovieClip is removed.
    private static function createSkillFunctions(ref:Object, stage:Number, baseFn:Object, gunMode:Boolean):Object {
        return {
            释放许可判定: function(unit:Object):Boolean {
                if (ref.已卸载 || unit !== ref.自机 || !DeadHandController.死者之手是否持有模式(ref)
                        || unit.倒地 || unit.状态 == "技能" || unit.状态 == "战技") return false;
                var nowF:Number = Number(_root.帧计时器.当前帧数);
                if (!isFinite(nowF)) nowF = 0;
                if (!ref.超载模式 && nowF < ref.超载冷却结束帧) return false;
                if (gunMode) return unit.攻击模式 === "长枪";
                return unit.攻击模式 === "兵器" && (!baseFn || typeof baseFn.释放许可判定 != "function"
                    || Boolean(baseFn.释放许可判定(unit)));
            },
            释放: function(unit:Object) {
                ref.战技释放中 = true;
                // The shared battle-skill router supports either current weapon mode.
                return (baseFn && typeof baseFn.释放 == "function") ? baseFn.释放(unit) : true;
            }
        };
    }
}
