import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.arki.component.Buff.*;
/** 独立验证死者之手；复用原投影聚合内的武器用例，保留真实投影、增益及弹药系统依赖。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandControllerTest {
    private static var _passed:Number=0;
    private static var _failed:Number=0;
    private static var SLOT_KEYS:Array=["头部装备","上装装备","下装装备","手部装备","脚部装备","颈部装备","长枪","手枪","手枪2","刀","手雷"];
    public static function runAllTests():Void {
        _passed=0; _failed=0;
        testDeadHandMultiFormAndOverload(); testDeadHandBoundaries();
        trace("DeadHandControllerTest Tests Passed: "+_passed);
        trace("DeadHandControllerTest Tests Failed: "+_failed);
    }
    private static function check(ok:Boolean,label:String):Void {
        if(ok) { _passed++; trace("[PASS] "+label); }
        else { _failed++; trace("[FAIL] "+label); }
    }
    private static function owner(unit:Object,slot:String):Object {
        return {自机:unit,装备类型:slot,装备名称:unit[slot].name,版本号:unit.version};
    }
    private static function equipment(name:String, level:Number,
                                      tier:String, mods):Object {
        return {
            name:name,
            value:{
                level:level,
                tier:tier,
                mods:mods,
                shot:7,
                reloadCount:2,
                当前战技:0,
                长柄形态:true
            },
            lastUpdate:1
        };
    }

    private static function target(version:Number):Object {
        var result:Object = {version:version};
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            result[SLOT_KEYS[i]] = null;
        }
        return result;
    }

    private static function makeMockSubClip():Object {
        return {
            _currentframe: 1,
            gotoAndStop: function(f:Number):Void {
                this._currentframe = f;
            }
        };
    }

    private static function makeMockWeaponClip():Object {
        return {
            _visible: true,
            _rotation: 0,
            _x: 0,
            _y: 0,
            枪头组件: makeMockSubClip(),
            握柄组件: makeMockSubClip(),
            御坂组件: makeMockSubClip(),
            刀口位置1: {_x: 0, _y: 0, _xscale: 100, _yscale: 100},
            刀口位置2: {_x: 0, _y: 0, _xscale: 100, _yscale: 100},
            刀口位置3: {_x: 0, _y: 0, _xscale: 100, _yscale: 100}
        };
    }

    private static function testDeadHandMultiFormAndOverload():Void {
        var fns:Object = _root.装备生命周期函数;
        check(fns != null
                && typeof fns.死者之手初始化 == "function"
                && typeof fns.死者之手周期 == "function",
            "死者之手生命周期函数已注册");
        if (!fns || typeof fns.死者之手初始化 != "function") return;

        var oldTimer:Object = _root.帧计时器;
        _root.帧计时器 = {当前帧数: 1};

        var unit:Object = target(40);
        unit._name = "deadHandTestHero";
        unit.刀 = equipment("死者之手", 1, "", []);
        unit.刀属性 = {power: 550, damagetype: "物理", magictype: ""};
        unit.兵器动作类型 = "刀剑";
        unit.兵器伤害类型 = "物理";
        unit.兵器魔法伤害属性 = "";
        unit.攻击模式 = "兵器";
        unit.状态 = "兵器站立";
        unit.刀_引用 = makeMockWeaponClip();
        unit.长枪_引用 = makeMockWeaponClip();
        unit.man = {};
        unit.syncRefs = {};
        var gunShotCount:Number = 0;
        var lastGunMuzzle:Object = null;
        unit.长枪射击 = function(m:Object, bp:Object):Boolean {
            gunShotCount++;
            lastGunMuzzle = m;
            return true;
        };
        var subs:Object = {};
        unit.dispatcher = {
            subscribe: function(evt:String, cb:Function, scope:Object):Void {
                subs[evt] = {cb: cb, scope: scope};
            },
            unsubscribe: function(evt:String, cb:Function, scope:Object):Void {
                if (subs[evt] && subs[evt].cb === cb) delete subs[evt];
            }
        };

        var origLongGunCfg = _root.长枪配置;
        _root.长枪配置 = function(uName:String, wName:String, lv:Number):Void {
            unit.长枪 = wName;
            unit.长枪属性 = {power: 550, interval: 150, capacity: 30};
            unit.长枪动作类型 = "刀剑";
            unit.长枪数据 = {actiontype: "刀剑", weapontype: "刀", data: unit.长枪属性};
        };

        RuntimeEquipmentProjection.beginCanonical(unit);
        var ref:Object = {
            自机: unit,
            装备类型: "刀",
            装备名称: "死者之手",
            标签名: "死者之手初始化",
            版本号: unit.version,
            是否为主角: false,
            生命周期函数列表: []
        };
        fns.死者之手初始化(ref, {});
        var completed:Boolean = RuntimeEquipmentProjection.completeCanonical(unit);
        _root.长枪配置 = origLongGunCfg;

        check(completed && RuntimeEquipmentProjection.hasActiveAlias(unit, "长枪", "刀")
                && unit.长枪 === unit.刀
                && unit.长枪动作类型 == undefined
                && unit.长枪属性.bullet == "能量普通子弹"
                && unit.长枪属性.muzzle == "能量枪火"
                && unit.长枪属性.bullethit == "能量火花",
            "死者之手在长枪槽为空时借用长枪槽并配置有效能量弹药与枪火资源");

        check(ref.冷兵器模式 == "钝器"
                && unit.兵器动作类型 == "狂野"
                && unit.兵器伤害类型 == "破击"
                && unit.刀属性.power == Math.floor(550 * 1.15)
                && unit.刀_引用.刀口位置1._y == 180
                && unit.刀_引用._visible == true
                && unit.长枪_引用._visible == false,
            "死者之手初始冷兵器为钝器（狂野/破击/近距刀口）且隐藏背部借用长枪引用");

        fns.死者之手切换冷兵器形态(ref, null);
        check(ref.冷兵器模式 == "长矛"
                && unit.兵器动作类型 == "长柄"
                && unit.兵器伤害类型 == "魔法"
                && unit.兵器魔法伤害属性 == "电"
                && unit.刀属性.power == 550
                && unit.刀_引用.刀口位置1._y == 460,
            "死者之手变形键切至长矛（长柄/电属性/远距刀口）");

        fns.死者之手切换冷兵器形态(ref, null);
        check(ref.冷兵器模式 == "镰刀"
                && unit.兵器动作类型 == "镰刀"
                && unit.刀属性.power == Math.floor(550 * 1.05)
                && unit.刀_引用.刀口位置1._x == -175
                && unit.刀_引用.刀口位置1._y == 285,
            "死者之手变形键切至镰刀（镰刀/中距横向刀口）");

        fns.死者之手切换冷兵器形态(ref, null);
        check(ref.冷兵器模式 == "钝器", "死者之手三形态循环回到钝器");

        unit.攻击模式 = "长枪";
        unit.状态 = "长枪站立";
        fns.死者之手同步视觉(ref);
        check(ref.当前武器模式 == "长枪"
                && unit.刀_引用._visible == false
                && unit.长枪_引用._visible == true
                && unit.长枪_引用._rotation == -90
                && Math.abs(unit.长枪_引用._x - (-113.6)) < 0.01
                && Math.abs(unit.长枪_引用._y - 36.25) < 0.01,
            "死者之手切到借用长枪模式时应用美术偏转(-90°, -113.6, 36.25)并隐藏刀引用");

        var shotProps:Object = {};
        unit.长枪伤害类型 = "物理";
        unit.长枪射击(null, shotProps);
        check(gunShotCount == 1
                && lastGunMuzzle === unit.长枪_引用.枪口位置
                && shotProps.子弹种类 == "能量普通子弹"
                && shotProps.发射效果 == "能量枪火"
                && shotProps.伤害类型 == "魔法"
                && shotProps.魔法伤害属性 == "电",
            "借用长枪射击时自动解析枪口位置并补齐能量普通子弹与电魔法伤害属性");

        unit.man.兵器使用标签 = true;
        fns.死者之手同步视觉(ref);
        check(ref.当前武器模式 == "兵器"
                && unit.刀_引用._visible == true
                && unit.长枪_引用._visible == false,
            "长枪或其它模式下触发拔刀/近战战技(兵器使用标签)时切回刀引用显示");
        delete unit.man.兵器使用标签;
        fns.死者之手同步视觉(ref);

        unit.兵器伤害类型 = "物理";
        unit.长枪伤害类型 = "物理";
        _root.帧计时器.当前帧数++;
        fns.死者之手周期(ref, {});
        check(unit.兵器伤害类型 == "破击" && unit.长枪伤害类型 == "魔法",
            "属性快照重算覆盖伤害类型后由周期自动恢复形态与借用长枪伤害属性");

        var f:Number = 1;
        for (var step:Number = 0; step < 20; step++) {
            f = fns.死者之手推进组件帧(f, 32, 46);
        }
        check(f == 46, "死者之手组件帧从收纳帧平滑推进至目标段末静止帧 46");
        for (step = 0; step < 20; step++) {
            f = fns.死者之手推进组件帧(f, 2, 16);
        }
        check(f == 16, "死者之手跨段切换时先退回段起点再推进至新段末 16");

        check(unit.主动战技 && unit.主动战技.兵器 && unit.主动战技.兵器.名字 == "瞬步斩",
            "常态装载一阶段战技");
        subs.WeaponSkill.cb.call(subs.WeaponSkill.scope, "长枪");
        check(ref.超载模式 == true
                && ref.当前战技阶段 == 2
                && ref.御坂最大帧 == 16
                && unit.主动战技.兵器.名字 == "凶斩",
            "释放一阶段战技开启超载强化并切换为二阶段战技");

        unit.攻击模式 = "兵器";
        unit.状态 = "兵器站立";
        fns.死者之手处理武器切换(ref);
        check(ref.超载模式 == true, "在死者之手自身兵器与借用长枪模式间切换保持超载状态");

        ref.战技释放中 = true;
        unit.状态 = "战技";
        subs.WeaponSkill.cb.call(subs.WeaponSkill.scope, "兵器");
        check(ref.超载模式 == true && ref.二阶段待结束超载 == true,
            "二阶段战技动画播放期间保持超载强化生效");
        unit.状态 = "兵器站立";
        _root.帧计时器.当前帧数++;
        fns.死者之手周期(ref, {});
        check(ref.超载模式 == false
                && ref.当前战技阶段 == 1
                && unit.主动战技.兵器.名字 == "瞬步斩"
                && ref.超载冷却结束帧 > 0,
            "二阶段战技动画结束后强制结束超载并进入冷却");

        ref.超载冷却结束帧 = 0;
        fns.死者之手开启超载(ref);
        unit.状态 = "技能";
        unit.技能名 = "瞬步斩";
        unit.攻击模式 = "手枪";
        fns.死者之手处理武器切换(ref);
        check(ref.超载模式 == false && unit.状态 == "手枪站立",
            "超载状态下切换到其他武器强制结束技能与超载强化");

        fns.死者之手卸载(ref);
        check(ref.已卸载 == true
                && unit.刀属性.power == 550
                && unit.刀_引用._visible == true
                && unit.长枪_引用._visible == true,
            "死者之手卸载时清理超载、恢复基础刀属性与装扮可见性");
        _root.帧计时器 = oldTimer;
    }

    private static function deadHandContext(params:Object, occupied:Boolean, withBuff:Boolean):Object {
        var unit:Object = target(51);
        unit._name = "deadHandBoundary";
        unit.刀 = equipment("死者之手", 1, "", []);
        unit.刀属性 = {power:550, damagetype:"物理", magictype:""};
        unit.兵器动作类型 = "刀剑";
        unit.兵器伤害类型 = "物理";
        unit.兵器魔法伤害属性 = "";
        unit.攻击模式 = "兵器"; unit.状态 = "兵器站立";
        unit.刀_引用 = makeMockWeaponClip(); unit.长枪_引用 = makeMockWeaponClip();
        unit.man = {}; unit.syncRefs = {};
        var events:Object = {};
        unit.dispatcher = {
            subscribe:function(name:String, fn:Function, scope:Object):Void { events[name] = {fn:fn, scope:scope}; },
            unsubscribe:function(name:String, fn:Function, scope:Object):Void {
                if (events[name].fn === fn && events[name].scope === scope) delete events[name];
            }
        };
        if (occupied) {
            unit.长枪 = equipment("已有步枪", 1, "", []);
            unit.长枪属性 = {power:999, capacity:9};
        }
        if (withBuff) {
            unit.buffManager = new BuffManager(unit, null);
            unit.buffManager.addBuffImmediate(new PodBuff("刀属性.power", BuffCalculationType.PERCENT, 0.2), "other_equipment");
        }
        var originalConfig:Function = _root.长枪配置;
        _root.长枪配置 = function():Void { unit.长枪属性 = {power:550}; };
        RuntimeEquipmentProjection.beginCanonical(unit);
        var ref:Object = owner(unit, "刀");
        ref.标签名 = "deadHandBoundary"; ref.生命周期函数列表 = [];
        _root.装备生命周期函数.死者之手初始化(ref, params);
        check(RuntimeEquipmentProjection.completeCanonical(unit), "死者之手边界夹具保持 canonical 投影");
        _root.长枪配置 = originalConfig;
        return {unit:unit, ref:ref, events:events};
    }

    private static function testDeadHandBoundaries():Void {
        var fns:Object = _root.装备生命周期函数;
        var c:Object = deadHandContext({}, true, false);
        var ref:Object = c.ref, unit:Object = c.unit;
        check(!ref.借用长枪槽 && unit.长枪.name == "已有步枪" && unit.长枪属性.power == 999,
            "已有长枪时不借槽或覆盖枪械属性");
        unit.攻击模式 = "长枪";
        fns.死者之手同步视觉(ref);
        check(unit.长枪_引用._visible && !fns.死者之手开启超载(ref), "其他长枪不获得死者之手战技或超载");
        fns.死者之手卸载(ref);
        check(unit.长枪.name == "已有步枪" && unit.长枪属性.power == 999, "卸载保留其他长枪");

        c = deadHandContext({}, false, true); ref = c.ref; unit = c.unit;
        check(Math.abs(unit.刀属性.power - 550 * 1.35) < 0.01, "形态增益通过真实 BuffManager 与其他装备并存");
        fns.死者之手切换冷兵器形态(ref, "长矛");
        check(Math.abs(unit.刀属性.power - 660) < 0.01, "切形态不会叠乘或抹掉其他装备 Buff");
        fns.死者之手卸载(ref);
        check(Math.abs(unit.刀属性.power - 660) < 0.01 && unit.buffManager.getBuffById("other_equipment") != null,
            "卸载仅移除本武器 Buff，保留其他来源威力");
        check(unit.刀属性.damagetype == "物理" && unit.刀属性.magictype == "", "卸载还原刀属性中的伤害类型");

        var oldTimer:Object = _root.帧计时器;
        _root.帧计时器 = {当前帧数:100};
        c = deadHandContext({overloadDurationFrames:2, overloadCooldown:1000}, false, false);
        ref = c.ref; unit = c.unit;
        check(fns.死者之手开启超载(ref), "一阶段开启有期限超载");
        _root.帧计时器.当前帧数 = 103;
        fns.死者之手周期(ref, {});
        check(!ref.超载模式 && ref.当前战技阶段 == 1 && ref.超载冷却结束帧 > 103,
            "持续时间到期自动退超载并进入冷却");
        check(!fns.死者之手开启超载(ref) && !unit.主动战技.兵器.战技函数.释放许可判定(unit),
            "冷却内拒绝重开超载和战技");
        _root.帧计时器.当前帧数 = ref.超载冷却结束帧 + 1;
        check(fns.死者之手开启超载(ref), "冷却结束后允许重新开启");
        ref.超载能量 = 0;
        fns.死者之手周期(ref, {});
        check(!ref.超载模式 && ref.超载能量 == 0, "能量耗尽自动结束超载");
        fns.死者之手卸载(ref);

        c = deadHandContext({}, false, false); ref = c.ref; unit = c.unit;
        fns.死者之手开启超载(ref);
        ref.战技释放中 = true; unit.状态 = "战技"; unit.技能名 = "凶斩";
        check(!unit.主动战技.兵器.战技函数.释放许可判定(unit), "真实战技状态下拒绝重复释放");
        unit.攻击模式 = "手枪";
        fns.死者之手处理武器切换(ref);
        check(!ref.超载模式 && unit.状态 == "手枪站立" && unit.技能名 == null,
            "切其他武器可中止真实战技状态");
        fns.死者之手卸载(ref);

        c = deadHandContext({}, false, false); ref = c.ref; unit = c.unit;
        fns.死者之手开启超载(ref);
        ref.战技释放中 = true; unit.状态 = "战技"; unit.技能名 = "凶斩";
        fns.死者之手卸载(ref);
        check(unit.状态 == "兵器站立" && unit.技能名 == null, "换装卸载中止正在播放的战技");
        check(c.events.WeaponSkill == undefined && c.events.processShot == undefined && c.events.attackModeChanged == undefined,
            "卸载精确退订全部事件");

        var oldSkills:Object = _root.主动战技函数;
        var seen:Object = {count:0};
        _root.主动战技函数 = {兵器:{瞬步斩:{释放:function(u:Object):Void { seen.count++; seen.mode=u.攻击模式; }}}};
        c = deadHandContext({}, false, false); ref = c.ref; unit = c.unit;
        _root.主动战技函数 = oldSkills;
        unit.攻击模式 = "长枪";
        check(unit.主动战技.长枪.战技函数.释放许可判定(unit), "初始化返回后枪械战技许可回调仍持有正确上下文");
        unit.主动战技.长枪.战技函数.释放(unit);
        check(seen.count == 1 && seen.mode == "长枪" && unit.攻击模式 == "长枪",
            "枪械形态播放所配占位战技且不裸改攻击模式");
        fns.死者之手卸载(ref);

        c = deadHandContext({}, false, false); ref = c.ref; unit = c.unit;
        unit.刀 = equipment("死者之手", 1, "", []);
        c.events.WeaponSkill.fn.call(c.events.WeaponSkill.scope, "兵器");
        check(!ref.超载模式 && fns.死者之手判定武器模式(ref) == "收纳",
            "同名新装备不被旧回调接管");
        fns.死者之手卸载(ref);
        _root.帧计时器 = oldTimer;
    }
}
