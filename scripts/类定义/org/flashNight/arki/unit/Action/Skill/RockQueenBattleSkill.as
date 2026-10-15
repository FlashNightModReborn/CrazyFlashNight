import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.arki.unit.Action.Skill.*;
import org.flashNight.arki.spatial.move.Mover;

/** 摇滚女皇玩家战技。资源只调用本类 root bridge，不在 things0 嵌入工程类。 */
class org.flashNight.arki.unit.Action.Skill.RockQueenBattleSkill {
    private static var specs:Object = {
        vocal:{name:"主唱突刺", family:"vocal", mode:"兵器", slot:"刀", form:"光剑", frames:30},
        keyboard:{name:"旋镰横掠", family:"keyboard", mode:"兵器", slot:"刀", form:"镰刀", frames:53},
        guitar:{name:"吉他震地", family:"guitar", mode:"兵器", slot:"长枪", frames:34}
    };

    public static function install(root:Object):Void {
        specs["guitar-gun"] = {name:"吉他机枪扫射", family:"guitar", mode:"长枪", slot:"长枪", form:"机枪", frames:31};
        specs["guitar-flame"] = {name:"吉他持续喷火", family:"guitar", mode:"长枪", slot:"长枪", form:"喷火器", frames:51};
        root.摇滚女皇战技 = {
            frame:RockQueenBattleSkill.frame, finish:RockQueenBattleSkill.finish,
            bindWeapon:RockQueenBattleSkill.bindWeapon
        };
        for (var id:String in specs) {
            var spec:Object = specs[id];
            root.主动战技函数[spec.mode][spec.name] = createDescriptor(id);
        }
    }

    private static function createDescriptor(id:String):Object {
        return {
            原子释放:true,
            固定资源消耗:true,
            初始化:null,
            释放许可判定:function(unit:MovieClip):Boolean { return RockQueenBattleSkill.canRelease(unit, id); },
            释放:function(unit:MovieClip):Boolean { return RockQueenBattleSkill.release(unit, id); }
        };
    }

    public static function bindEquipment(ref:Object, family:String):Void {
        var unit:MovieClip = ref.自机;
        var slot:String = family == "guitar" ? "长枪" : "刀";
        ref.rockFamily = family;
        ref.rockItem = unit[slot];
        ref.rockAlive = true;
        if (!unit.__rockQueenRefs) unit.__rockQueenRefs = {};
        unit.__rockQueenRefs[family] = ref;
        unit.生命周期函数列表.push({动作:RockQueenBattleSkill.releaseEquipment, 额外参数:ref});
    }

    public static function releaseEquipment(ref:Object):Void {
        ref.rockAlive = false;
        delete ref.rockResume;
        var unit:MovieClip = ref.自机;
        var cast:Object = unit.__rockQueenCast;
        if (cast.ref === ref) cancel(cast);
        if (unit.__rockQueenRefs[ref.rockFamily] === ref) delete unit.__rockQueenRefs[ref.rockFamily];
    }

    public static function isActive(unit:Object):Boolean {
        return unit.__rockQueenCast.active === true;
    }

    /** 装备周期让位给当前动作；视觉回调也用 isActive，避免同帧重新折叠/移动武器。 */
    public static function ownsCycle(ref:Object):Boolean {
        var cast:Object = ref.自机.__rockQueenCast;
        if (cast.active !== true || cast.ref !== ref) return false;
        ref.wasTransformKeyDown = _root.按键输入检测(ref.自机, _root.武器变形键) ? true : false;
        return true;
    }

    public static function syncGunSkill(ref:Object):Void {
        if (!ref.skill_1 || !ref.skill_2) return;
        var selected:Object = ref.weaponMode == "机枪" ? ref.skill_2 : ref.skill_1;
        if (ref.当前长枪战技 === selected) return;
        ref.当前长枪战技 = selected;
        ref.自机.装载主动战技(selected, "长枪", ref.装备名称);
        if (ref.是否为主角) _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
    }

    /** 按已结算的最大MP生成独立描述符，HUD与实际扣费读取同一金额。 */
    public static function slamSkill(ref:Object, source:Object):Object {
        var out:Object = {};
        for (var key:String in source) out[key] = source[key];
        out.mp = Number(source.mp) + ref.吉他震地耗蓝量;
        return out;
    }

    private static function validRef(unit:Object, spec:Object, ref:Object):Boolean {
        return ref.rockAlive === true && ref.自机 === unit && unit[spec.slot] === ref.rockItem
            && (!ref.是否为主角 || ref.版本号 === unit.version);
    }

    public static function canRelease(unit:Object, id:String):Boolean {
        var spec:Object = specs[id];
        if (!spec || !unit || unit.hasDressup !== true || !(unit.hp > 0)) return false;
        var ref:Object = unit.__rockQueenRefs[spec.family];
        if (!validRef(unit, spec, ref) || unit.攻击模式 != spec.mode) return false;
        if (_root.暂停 || unit.倒地 || unit.浮空 || unit.技能浮空 || unit.换弹中
                || unit.状态 == "战技" || unit.状态 == "技能" || isActive(unit)) return false;
        if (spec.form && ref.weaponMode != spec.form) return false;
        if (spec.mode == "兵器" && (ref.rockBlade.bullet != "近战联弹"
                || !(ref.rockBlade.pellets >= 1) || !(ref.rockBlade.hits > 0)
                || !isFinite(ref.rockBlade.bonusBudget))) return false;
        if (id == "guitar" && !ref.是否刀枪复用) return false;
        if (spec.mode == "长枪" && !(unit.长枪.value.shot < unit.长枪弹匣容量)) return false;
        if (id == "guitar-gun" && !(ref.机枪剩余弹容 > 0)) return false;
        var skill:Object = unit.主动战技[spec.mode];
        if (skill.名字 != spec.name) return false;
        var hp:Number = Number(skill.消耗hp);
        var mp:Number = Number(skill.消耗mp);
        if (!isFinite(hp) || hp < 0 || !isFinite(mp) || mp < 0) return false;
        if (!(unit.hp > hp) || !(unit.mp >= mp)) return false;
        return true;
    }

    public static function release(unit:MovieClip, id:String):Boolean {
        if (!canRelease(unit, id)) return false;
        var spec:Object = specs[id];
        var ref:Object = unit.__rockQueenRefs[spec.family];
        var skill:Object = unit.主动战技[spec.mode];
        delete ref.rockResume;
        var cost:Number = Number(skill.消耗mp);
        if (!_root.gameworld.__rockQueenSceneToken) _root.gameworld.__rockQueenSceneToken = {};
        var cast:Object = {active:true, unit:unit, ref:ref, spec:spec, id:id,
            item:ref.rockItem, lastFrame:0, damageEvents:0, shots:0, form:ref.weaponMode,
            fromShooting:spec.mode == "长枪" && unit.主手射击中 === true,
            worldToken:_root.gameworld.__rockQueenSceneToken};
        cast.legacyBladeReserve = 0;
        // 旧瞬步斩第19帧另有三刀口、当前MP参与的判定；只有旧公式可得有限值时保留。
        if (id == "keyboard" && isFinite(unit.技能等级)) {
            cast.legacyBladeReserve = Math.max(0, ref.rockBlade.legacyPointHits *
                (unit.空手攻击力 / 4 * (1 + Number(unit.技能等级)) + unit.刀属性.power
                    + (unit.mp - cost) * ref.rockBlade.legacyMpCoefficient));
        }
        unit.__rockQueenCast = cast;
        // 退出普通射击连发任务，避免延迟回调抢走战技时间轴或额外消耗弹药。
        ShootCore.cleanup(unit);
        var man:MovieClip = _root.战技路由.战技标签跳转_旧(unit, spec.name, "container");
        // attachMovie 的帧数同步可读；命名子级在重复挂载时可能下一帧才绑定。
        if (man._totalframes != spec.frames) {
            cleanup(cast);
            RoutingLifecycle.recoverMissingSkillContainer(unit);
            return false;
        }
        cast.man = man;
        man.__rockQueenCast = cast;
        var previous:Function = man.onUnload;
        man.onUnload = makeUnload(cast, previous);
        man.onEnterFrame = makeWatch(cast);
        man.rockArea._visible = false;
        unit.hp -= skill.消耗hp;
        unit.mp -= cost;
        // 战技路由默认按兵器准备加成，枪形态在成功挂载后回到真实射击槽。
        unit.根据模式重新读取武器加成(spec.mode);
        bindWeapon(man.rockWeapon.placement);
        // 所有权和付费就绪后显式进入首帧；不能把 attach 当作播放就绪握手。
        // 默认动作均从玩家站姿平滑接入；吉他保留完整举起蓄力，再进入下砸。
        man.gotoAndPlay(1);
        return true;
    }

    private static function makeUnload(cast:Object, previous:Function):Function {
        return function():Void {
            RockQueenBattleSkill.cleanup(cast);
            if (cast.unit.__rockQueenCast.active === true) return;
            if (previous) previous.apply(this);
        };
    }

    private static function validCast(cast:Object, man:MovieClip):Boolean {
        var unit:MovieClip = cast.unit;
        return cast.active === true && unit.__rockQueenCast === cast && unit.man === man
            && man.__rockQueenCast === cast && _root.gameworld.__rockQueenSceneToken === cast.worldToken
            && unit.状态 == "战技" && unit.hp > 0
            && unit.攻击模式 == cast.spec.mode && validRef(unit, cast.spec, cast.ref)
            && cast.ref.weaponMode == cast.form;
    }

    public static function bindWeapon(placement:MovieClip):Void {
        var man:MovieClip = placement._parent._parent;
        var unit:MovieClip = man._parent;
        var cast:Object = unit.__rockQueenCast;
        if (cast.active !== true || unit.man !== man) return;
        if (!placement.装扮) {
            var gun:Boolean = cast.spec.family == "guitar";
            var skin:String = gun ? unit.长枪_装扮 : unit.刀_装扮;
            _root.装备引用配置.配置装扮(placement, skin, "装扮",
                cast.spec.mode == "长枪" ? "长枪_引用" : "刀_引用");
        }
        if (man.__rockPose) setWeaponPose(man, man.__rockPose.playerFrame);
    }

    private static function setWeaponPose(man:MovieClip, playerFrame:Number):Void {
        var weapon:MovieClip = man.rockWeapon.placement.装扮;
        var cast:Object = man._parent.__rockQueenCast;
        if (!weapon) return;
        weapon.动画._visible = true;
        weapon.动画.gotoAndStop(playerFrame);
        cast.ref.animFrame = playerFrame;
        if (weapon.枪口位置) {
            weapon.枪口位置._x = cast.id == "guitar-flame" ? 82 : 282;
            weapon.枪口位置._y = 0.9;
        }
    }

    private static function makeWatch(cast:Object):Function {
        return function():Void { RockQueenBattleSkill.watchFrame(cast); };
    }

    public static function watchFrame(cast:Object):Void {
        var man:MovieClip = cast.man;
        if (!validCast(cast, man)) {
            if (cast.active === true) cancel(cast);
            return;
        }
        if (_root.暂停) {
            man.__rockPaused = true;
            man.stop();
        } else if (man.__rockPaused) {
            man.__rockPaused = false;
            var p:Object = man.__rockPose;
            frame(man, cast.id, p.frame, p.sourceFrame, p.playerFrame);
            if (p.frame == man._totalframes) finish(man);
            else if (cast.active) man.play();
        }
    }

    public static function frame(man:MovieClip, id:String, at:Number, sourceFrame:Number, playerFrame:Number):Void {
        var cast:Object = man._parent.__rockQueenCast;
        man.__rockPose = {frame:at, sourceFrame:sourceFrame, playerFrame:playerFrame};
        // 七个进阶与两个空中动作只入库，没有玩家释放入口。
        if (cast.active !== true || cast.id != id) { man.stop(); return; }
        if (!validCast(cast, man)) { cancel(cast); return; }
        man.rockFX.gotoAndStop(at);
        man.rockArea._visible = false;
        bindWeapon(man.rockWeapon.placement);
        if (_root.暂停) { man.__rockPaused = true; man.stop(); return; }
        if (!(at > cast.lastFrame)) return;
        cast.lastFrame = at;
        move(cast, sourceFrame);
        // 装备周期让出演出所有权，但原有猩红增幅不能一起停掉。
        // 只在已付费、仍有效、未暂停的本轮时间轴触发，共用普攻的原始冷却。
        if (id == "vocal") _root.装备生命周期函数.主唱光剑治疗周期(cast.ref);
        // 收势由原生时间轴的六帧站姿桥完成；不再提前切走造成收招跳姿。
        var event:String = eventAt(id, sourceFrame);
        if (id == "guitar-gun") {
            var firing:Boolean = sourceFrame > 138 && sourceFrame < 154;
            if (firing) cast.ref.机枪剩余弹容 = Math.max(0, cast.ref.机枪剩余弹容 - 1);
            else cast.ref.机枪剩余弹容 = Math.min(cast.ref.机枪弹容上限, cast.ref.机枪剩余弹容 + 1);
            if (firing && !(cast.ref.机枪剩余弹容 > 0)) { cancel(cast); return; }
        }
        if (!event) return;
        if (event == "gun" || event == "flame") fire(man, cast, event);
        else hit(man, cast, event);
    }

    public static function eventAt(id:String, sourceFrame:Number):String {
        if (id == "vocal" && (sourceFrame == 78 || sourceFrame == 86 || sourceFrame == 94)) return "thrust";
        if (id == "keyboard" && (sourceFrame == 51 || sourceFrame == 54 || sourceFrame == 57 || sourceFrame == 63
                || sourceFrame == 66 || sourceFrame == 69 || sourceFrame == 73 || sourceFrame == 84 || sourceFrame == 88)) return "scythe";
        if (id == "guitar" && (sourceFrame == 28 || sourceFrame == 30 || sourceFrame == 32 || sourceFrame == 34)) return "slam";
        if (id == "guitar-gun" && sourceFrame > 138 && sourceFrame < 154 && sourceFrame % 2 == 1) return "gun";
        if (id == "guitar-flame" && sourceFrame > 35 && sourceFrame < 71 && sourceFrame % 4 == 0) return "flame";
        return null;
    }

    private static function move(cast:Object, sourceFrame:Number):Void {
        var unit:MovieClip = cast.unit;
        var controlled:Boolean = unit._name == _root.控制目标;
        if (controlled) {
            if (unit.右行 && !unit.左行) unit.方向改变("右");
            else if (unit.左行 && !unit.右行) unit.方向改变("左");
        }
        var speed:Number = 0;
        var drift:Number = 0;
        if (cast.id == "vocal") {
            if ((sourceFrame > 76 && sourceFrame < 82) || (sourceFrame > 84 && sourceFrame < 90)
                    || (sourceFrame > 92 && sourceFrame < 98)) speed = 12;
            drift = 3;
        } else if (cast.id == "keyboard") {
            // 两段各五帧、25px/帧，与旧瞬步斩的两次穿行保持同一移动量级。
            if ((sourceFrame > 48 && sourceFrame < 54) || (sourceFrame > 81 && sourceFrame < 87)) speed = 25;
            drift = 4;
        } else return;
        var horizontal:Boolean = controlled && (unit.左行 != unit.右行);
        var vertical:Boolean = controlled && (unit.上行 != unit.下行);
        // 无方向输入只保留小幅冲势；按住左右才使用原来的突进速度。
        var step:Number = speed > 0 ? (horizontal || !controlled ? speed : drift) : drift;
        if (speed > 0 || horizontal) moveGround(unit, unit.方向, step);
        if (vertical) moveGround(unit, unit.上行 ? "上" : "下", step / 2);
    }

    private static function moveGround(unit:MovieClip, direction:String, distance:Number):Void {
        // 25px 瞬步也可能越过薄墙；沿用 Mover 的碰撞/深度维护，但最多每 5px 检测一次。
        var steps:Number = Math.ceil(distance / 5);
        for (var i:Number = 0; i < steps; i++) {
            var x:Number = unit._x;
            var z:Number = unit.Z轴坐标;
            Mover.move2DStrict(unit, direction, distance / steps);
            if (unit._x == x && unit.Z轴坐标 == z) break;
        }
    }

    /** 由原装备周期在新持枪 man 完成绑定后消费；普通射击已接手时只清请求。 */
    public static function resumeGun(ref:Object):Void {
        var pending:Object = ref.rockResume;
        if (!pending) return;
        var unit:MovieClip = ref.自机;
        if (isActive(unit) || !validRef(unit, pending.spec, ref) || !(unit.hp > 0)
                || unit.攻击模式 != "长枪" || ref.weaponMode != pending.form
                || _root.gameworld.__rockQueenSceneToken !== pending.worldToken
                || !unit.动作A || unit.动作C || unit.换弹中 || unit.man.换弹标签
                || (unit.状态 != "长枪站立" && unit.状态 != "长枪行走" && unit.状态 != "长枪跑")) {
            delete ref.rockResume;
            return;
        }
        if (_root.暂停) return;
        if (unit.主手射击中 === true) { delete ref.rockResume; return; }
        if (typeof unit.man.开始射击 == "function") {
            delete ref.rockResume;
            unit.man.开始射击();
        } else if (++pending.attempts > 8) delete ref.rockResume;
    }

    private static function configureArea(man:MovieClip, melee:Boolean):Boolean {
        var bounds:Object = man.rockFX.getBounds(man);
        if (melee) {
            // 刀光会飞到身后/头顶，不能作为唯一刀判定。补入身体前后的稳定近战区。
            var unit:MovieClip = man._parent;
            var wide:Boolean = unit.__rockQueenCast.id == "keyboard";
            var near:Object = {x:wide ? -120 : -24, y:-125};
            var far:Object = {x:wide ? 180 : 145, y:8};
            unit.localToGlobal(near); man.globalToLocal(near);
            unit.localToGlobal(far); man.globalToLocal(far);
            bounds.xMin = Math.min(bounds.xMin, Math.min(near.x, far.x));
            bounds.xMax = Math.max(bounds.xMax, Math.max(near.x, far.x));
            bounds.yMin = Math.min(bounds.yMin, Math.min(near.y, far.y));
            bounds.yMax = Math.max(bounds.yMax, Math.max(near.y, far.y));
        }
        if (!(bounds.xMax - bounds.xMin > 1) || !(bounds.yMax - bounds.yMin > 1)) return false;
        var area:MovieClip = man.rockArea;
        area._x = bounds.xMin;
        area._y = bounds.yMin;
        area._xscale = (bounds.xMax - bounds.xMin) * 10;
        area._yscale = (bounds.yMax - bounds.yMin) * 10;
        area._visible = false;
        return true;
    }

    private static function hit(man:MovieClip, cast:Object, kind:String):Void {
        if (!configureArea(man, true)) return;
        var unit:MovieClip = cast.unit;
        var ref:Object = cast.ref;
        var config:Object = ref.rockBlade;
        var props:Object = _root.子弹属性初始化(man.rockArea, config.bullet, unit);
        props.子弹速度 = 0;
        props.子弹散射度 = 0;
        props.击中地图效果 = "";
        props.区域定位area = man.rockArea;
        props.霰弹值 = props.最小霰弹值 = config.pellets;
        props.Z轴攻击范围 = kind == "slam" ? 200 : 40;
        var last:Boolean = cast.damageEvents + 1 == config.hits;
        props.击倒率 = kind == "slam" && last ? 1 : 10;
        props.不硬直 = !last;
        var blade:Number = unit.空手攻击力 * config.unarmed + unit.等级 * config.level
            + unit.刀属性.power * config.weapon;
        if (kind != "thrust" && unit.等级 < 12) blade = Math.floor(blade * (unit.等级 + 5) / 20);
        blade *= SkillDamageCore.getSkillMultiplier(unit, config.legacySkill);
        var bonus:Number;
        if (kind == "thrust") bonus = unit.空手攻击力 * ref.光刃攻击力系数 + ref.baseDamage * ref.光刃基础伤害系数;
        else if (kind == "scythe") bonus = ref.镰刀风车斩耗蓝量 * ref.子弹威力倍率 + ref.baseDamage;
        else bonus = ref.吉他震地耗蓝量 * ref.吉他震地威力倍率;
        // 每次挥砍三段刀判定，装备附加伤害在联弹段间分配，避免重复乘入。
        props.子弹威力 = blade + (bonus * config.bonusBudget + cast.legacyBladeReserve) / (config.hits * config.pellets);
        SkillAttributeCore.transferWeaponAttributes(unit, props);
        _root.子弹区域shoot传递(props);
        cast.damageEvents++;
    }

    private static function fire(man:MovieClip, cast:Object, kind:String):Void {
        var unit:MovieClip = cast.unit;
        var muzzle:MovieClip = man.rockWeapon.placement.装扮.枪口位置;
        if (!muzzle) { cancel(cast); return; }
        var props:Object = ShootInitCore.generateBulletProps(unit, "长枪", unit.长枪属性, {});
        props.固定枪口方向 = true;
        props.发射效果 = ""; // 枪火/火舌已在同一原生演出帧，无重复叠加。
        props.Z轴攻击范围 = kind == "flame" ? 50 : props.Z轴攻击范围;
        if (kind == "gun") {
            props.霰弹值 = 3;
            // 航向取实际枪管世界轴，固定枪口模式不被普通长枪自瞄改写。
            var from:Object = {x:0, y:0};
            var axis:Object = {x:100, y:0};
            man.rockWeapon.localToGlobal(from);
            man.rockWeapon.localToGlobal(axis);
            _root.gameworld.globalToLocal(from);
            _root.gameworld.globalToLocal(axis);
            var angle:Number = Math.atan2(axis.y-from.y, axis.x-from.x) * 180 / Math.PI;
            props.角度偏移 = unit.方向 == "左" ? angle - 180 : angle;
        } else {
            if (!configureArea(man, false)) return;
            props.子弹种类 = "透明子弹";
            props.子弹速度 = 0;
            props.霰弹值 = 1;
            props.区域定位area = man.rockArea;
            props.伤害类型 = "魔法";
            props.魔法伤害属性 = "热";
        }
        if (!WeaponFireCore.executeShot(unit, "长枪", muzzle, props)) { cancel(cast); return; }
        cast.shots++;
        if (cast.ref.weaponMode == "机枪") unit.长枪.value.machineGunShot = unit.长枪.value.shot;
    }

    public static function cleanup(cast:Object):Void {
        if (!cast || cast.active !== true) return;
        cast.active = false;
        var unit:MovieClip = cast.unit;
        if (unit.__rockQueenCast === cast) delete unit.__rockQueenCast;
        if (cast.man.__rockQueenCast === cast) {
            delete cast.man.onEnterFrame;
            cast.man.rockFX.stop();
            if (unit.skillShadow === cast.man.rockShadow) delete unit.skillShadow;
        }
    }

    public static function cancel(cast:Object):Void {
        var unit:MovieClip = cast.unit;
        var man:MovieClip = cast.man;
        var owns:Boolean = unit.__rockQueenCast === cast && unit.man === man;
        cleanup(cast);
        // 被别的状态取代时只收自己的租约；不能把死亡/受击/新动作跳回站立。
        if (owns && unit.状态 == "战技") _root.战技路由.动画完毕(man, unit);
    }

    public static function finish(man:MovieClip):Void {
        var cast:Object = man.__rockQueenCast;
        if (!validCast(cast, man) || _root.暂停) return;
        if (cast.spec.mode == "长枪" && cast.unit.动作A) {
            cast.ref.rockResume = {spec:cast.spec, form:cast.form, worldToken:cast.worldToken, attempts:0};
        }
        cleanup(cast);
        _root.战技路由.动画完毕(man, man._parent);
    }
}
