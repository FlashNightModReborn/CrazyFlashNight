import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.StaticDeinitializer;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;

class org.flashNight.arki.unit.UnitAI.Custom.ArmorBreakZombieController {
    public static var KIND:String = "敌人-兽化改造僵尸";
    public static var SUCCESSOR_KIND:String = "敌人-兽化僵尸1";
    public static var ATTACK_MULTIPLIER:Number = 0.6;
    public static var HP_MULTIPLIER:Number = 1.5;
    public static var DEFENSE_MULTIPLIER:Number = 1.5;
    public static var HEAL_AMOUNT:Number = 2000;
    public static var HEAL_RADIUS:Number = 180;
    public static var SPAWN_DELAY_FRAMES:Number = 15;
    public static var INIT_TIMEOUT_FRAMES:Number = 30;

    public static function initialize(target:MovieClip):Void {
        if (!isEligible(target)) return;
        if (target.__armorBreakState != null) return;
        if (target.__armorBreakWrapped === true) {
            if (target.__armorBreakOriginalDeathCheck != undefined) {
                target.死亡检测 = target.__armorBreakOriginalDeathCheck;
            }
            target.__armorBreakWrapped = false;
        }
        var original:Function = target.死亡检测;
        if (typeof original != "function") return;
        target.__armorBreakOriginalDeathCheck = original;
        target.__armorBreakWrapped = true;
        target.死亡检测 = function(para:Object):Void {
            if (ArmorBreakZombieController.tryIntercept(this)) return;
            original.call(this, para);
        };
    }

    public static function tryIntercept(target:MovieClip):Boolean {
        if (!isEligible(target)) return false;
        var state:Object = target.__armorBreakState;
        if (state != null) {
            if (state.active === true) {
                target.hp = 1;
                target._killed = true;
                return true;
            }
            return false;
        }
        if (target.__armorBreakUsed === true) return false;
        if (isNaN(Number(target.hp)) || Number(target.hp) > 0) return false;
        return begin(target);
    }

    private static function isEligible(target:MovieClip):Boolean {
        if (target == null || target._parent !== _root.gameworld) return false;
        if (String(target.兵种) != KIND) return false;
        if (target.是否为敌人 != true) return false;
        if (target.斗兽标定隔离 === true) return false;
        var unitId:Number = Number(target.单位编号);
        if (unitId > 0 && unitId != 71 && unitId != 81) return false;
        if (String(target.名字).indexOf("远古") >= 0) return false;
        return true;
    }

    private static function begin(target:MovieClip):Boolean {
        var state:Object = {
            active: true,
            attempted: false,
            retired: false,
            waitFrames: 0,
            age: 0,
            world: target._parent,
            name: String(target._name),
            level: Number(target.等级),
            side: target.是否为敌人,
            source: target.产生源,
            direction: target.方向,
            height: target.身高,
            title: target.称号,
            publishStageEvent: target.publishStageEvent === true,
            maxHp: numberOr(target.hp满血值, 0),
            attack: numberOr(target.基本空手攻击力, numberOr(target.空手攻击力, 0)),
            defense: numberOr(target.防御力, 0),
            basicDefense: numberOr(target.基本防御力, 0)
        };
        target.__armorBreakState = state;
        target.__armorBreakUsed = true;
        target.__armorBreakActive = true;
        target._封印冻结 = true;
        target._killed = true;
        target.hp = 1;
        target._rotation = 0;
        target.浮空 = false;
        target.倒地 = false;
        if (!isNaN(Number(target.Z轴坐标))) target._y = Number(target.Z轴坐标);
        target.状态 = "装甲破裂";
        target.gotoAndStop("装甲破裂");
        if (target.新版人物文字信息 != undefined) target.新版人物文字信息._visible = false;
        if (target.人物文字信息 != undefined) target.人物文字信息._visible = false;
        TargetCacheManager.removeUnit(target);
        ensureClock(target);
        return true;
    }

    private static function ensureClock(target:MovieClip):Void {
        var clock:MovieClip = target.__armorBreakClock;
        if (clock != undefined && clock._parent === target) return;
        clock = target.createEmptyMovieClip("__armorBreakClock", target.getNextHighestDepth());
        target.__armorBreakClock = clock;
        clock.onEnterFrame = function():Void {
            if (_root.暂停 === true) return;
            ArmorBreakZombieController.tick(target);
        };
    }

    private static function removeClock(target:MovieClip):Void {
        var clock:MovieClip = target.__armorBreakClock;
        if (clock != undefined) {
            if (clock._parent === target) clock.removeMovieClip();
            target.__armorBreakClock = undefined;
        }
    }

    private static function tick(target:MovieClip):Void {
        var state:Object = target.__armorBreakState;
        if (state == null || state.active !== true) {
            removeClock(target);
            return;
        }
        if (target._parent !== state.world || target._deInitialized === true) {
            removeClock(target);
            return;
        }
        state.age++;
        if (!state.attempted) {
            if (state.age >= SPAWN_DELAY_FRAMES) spawnSuccessor(target);
            return;
        }
        var child:MovieClip = state.child;
        if (child == null) {
            fail(target, "spawn-returned-empty");
            return;
        }
        if (state.world !== _root.gameworld || child._parent !== state.world
                || child._name !== state.name || state.world[state.name] !== child) {
            fail(target, "spawn-identity-lost");
            return;
        }
        state.waitFrames++;
        if (child.__unitInitializedVersion != null
                && child.__unitInitializedVersion !== undefined
                && child.__unitInitializedVersion === child.version
                && String(child.兵种) == SUCCESSOR_KIND
                && Number(child.hp满血值) > 0
                && !isNaN(Number(child.hp))) {
            if (Number(child.等级) != Number(state.level) || child.是否为敌人 != state.side) {
                fail(target, "successor-context-mismatch");
                return;
            }
            finish(target);
        } else if (state.waitFrames >= INIT_TIMEOUT_FRAMES) {
            fail(target, "successor-initialization-timeout");
        }
    }

    private static function spawnSuccessor(target:MovieClip):Void {
        var state:Object = target.__armorBreakState;
        if (state == null || state.active !== true || state.attempted) return;
        state.attempted = true;
        state.x = target._x;
        state.z = target.Z轴坐标;
        if (!isFinite(state.x) || !isFinite(state.z)) {
            fail(target, "invalid-handoff-position");
            return;
        }
        if (state.world !== _root.gameworld) {
            fail(target, "world-mismatch");
            return;
        }
        var name:String = String(target._name) + "__unarmored";
        if (state.world[name] != undefined) name = name + "_" + getTimer();
        state.name = name;
        var stats:Object = formStats(state.maxHp, state.attack, state.defense, state.basicDefense);
        var params:Object = {
            _x: state.x,
            _y: state.z,
            等级: state.level,
            是否为敌人: state.side,
            身高: state.height,
            产生源: state.source,
            名字: "兽化僵尸",
            _visible: false,
            extra: {set: {
                hp满血值: stats.hp,
                hp: stats.hp,
                空手攻击力: stats.attack,
                基本空手攻击力: stats.attack,
                基本防御力: stats.basicDefense,
                防御力: stats.defense
            }}
        };
        if (state.title != undefined) params.称号 = state.title;
        if (state.publishStageEvent === true) params.publishStageEvent = true;
        try {
            state.child = _root.加载游戏世界人物(SUCCESSOR_KIND, name, state.world.getNextHighestDepth(), params);
        } catch (spawnError:Error) {
            state.child = null;
        }
        if (state.child == null) fail(target, "spawn-returned-empty");
    }

    private static function finish(target:MovieClip):Void {
        var state:Object = target.__armorBreakState;
        if (state == null || state.active !== true || state.retired === true) return;
        var child:MovieClip = state.child;
        state.retired = true;
        state.active = false;
        target._visible = false;
        try {
            child.方向改变(state.direction);
        } catch (directionError:Error) {
        }
        child._visible = true;
        try {
            healAllies(child);
        } catch (healError:Error) {
        }
        removeClock(target);
        retireOld(target);
    }

    private static function healAllies(center:MovieClip):Void {
        var allies:Array = TargetCacheManager.findAlliesInRadius(center, 5, HEAL_RADIUS);
        if (allies == null) return;
        for (var i:Number = 0; i < allies.length; i++) {
            var ally:MovieClip = allies[i];
            if (ally == null || ally == center) continue;
            if (isNaN(Number(ally.hp)) || Number(ally.hp) <= 0) continue;
            if (isNaN(Number(ally.hp满血值)) || Number(ally.hp) >= Number(ally.hp满血值)) continue;
            HealApplier.applyHpCapped(ally, HEAL_AMOUNT, Number(ally.hp满血值));
        }
    }

    private static function retireOld(target:MovieClip):Void {
        target.__armorBreakActive = false;
        target.__armorBreakState = null;
        target.hp = 0;
        TargetCacheManager.removeUnit(target);
        try {
            target.死亡检测({noCount: true, noCorpse: true, remainMovie: true});
            if (target._deInitialized !== true) {
                target.已加经验值 = true;
                StaticDeinitializer.deInitializeUnit(target);
            }
            target.removeMovieClip();
        } catch (retireError:Error) {
            target.已加经验值 = true;
            try {
                StaticDeinitializer.deInitializeUnit(target);
            } catch (deinitError:Error) {
            }
            target.removeMovieClip();
        }
    }

    private static function fail(target:MovieClip, reason:String):Void {
        var state:Object = target.__armorBreakState;
        var orphan:MovieClip = null;
        if (state != null) {
            state.active = false;
            state.error = reason;
            if (state.child != null && state.world != null
                    && state.child._parent === state.world
                    && state.world[state.name] === state.child) {
                orphan = state.child;
            }
        }
        target.__armorBreakState = null;
        target.__armorBreakActive = false;
        target.__armorBreakFailed = true;
        removeClock(target);
        target._visible = true;
        target._killed = false;
        target.hp = 0;
        if (orphan != null) {
            orphan.已加经验值 = true;
            TargetCacheManager.removeUnit(orphan);
            try {
                StaticDeinitializer.deInitializeUnit(orphan);
            } catch (orphanError:Error) {
            }
            orphan.removeMovieClip();
        }
        var original:Function = target.__armorBreakOriginalDeathCheck;
        if (typeof original == "function") {
            try {
                original.call(target, {});
            } catch (error:Error) {
                target.removeMovieClip();
            }
        } else {
            target.死亡检测();
        }
    }

    public static function formStats(maxHp:Number, attack:Number, defense:Number, basicDefense:Number):Object {
        var hp:Number = Math.max(1, Math.round(numberOr(maxHp, 0) * HP_MULTIPLIER));
        var atk:Number = Math.max(1, Math.round(numberOr(attack, 0) * ATTACK_MULTIPLIER));
        var def:Number = Math.max(1, Math.round(numberOr(defense, 0) * DEFENSE_MULTIPLIER));
        var basicDef:Number = Math.max(1, Math.round(numberOr(basicDefense, 0) * DEFENSE_MULTIPLIER));
        return {hp: hp, attack: atk, defense: def, basicDefense: basicDef};
    }

    private static function numberOr(value:Object, fallback:Number):Number {
        var result:Number = Number(value);
        return isNaN(result) ? fallback : result;
    }
}
