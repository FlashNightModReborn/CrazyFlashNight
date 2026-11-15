import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;

/**
 * 爆炸中心散射控制器。
 * 为配置了 <explosionScatter> 的普通子弹绑定：
 * 1. 出生属性与飞行朝向/安全位置跟踪（用于撞墙/落地时回退到碰撞表面再散射）；
 * 2. 命中单位 / 命中地图 / 时间轴 "爆炸" 帧 幂等一次性散射；
 * 3. 子弹以毫秒计时 (lifetimeMs，排除暂停帧) 与防无限递归保护。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.ExplosionScatter {
    private static var SNAPSHOT_KEYS:Array = [
        "伤害类型", "魔法伤害属性", "毒", "nanoToxic", "nanoToxicDecay",
        "吸血", "击溃", "斩杀", "暴击", "命中率", "固伤",
        "百分比伤害", "血量上限击溃", "防御粉碎", "友军伤害", "不硬直"
    ];

    /** 测试可注入毫秒时钟与随机数函数；生产默认 null，分别使用 getTimer() / Math.random()。 */
    public static var clockOverride:Function = null;
    public static var rngOverride:Function = null;

    private function ExplosionScatter() {}

    private static function nowMs():Number {
        return (clockOverride != null) ? Number(clockOverride()) : getTimer();
    }

    private static function nextRand():Number {
        var r:Number = (rngOverride != null) ? Number(rngOverride()) : Math.random();
        if (!isFinite(r) || r < 0) return 0;
        if (r >= 1) return 0.999999999;
        return r;
    }

    private static function normalizeDeg(deg:Number):Number {
        var a:Number = deg % 360;
        if (a > 180) a -= 360;
        else if (a <= -180) a += 360;
        return a;
    }

    public static function isMapColliding(x:Number, y:Number, z:Number):Boolean {
        if (y > z) return true;
        var layer:Object = _root.collisionLayer;
        if (layer != null && layer.hitTest(x, z, true)) return true;
        return false;
    }

    public static function updateHeading(state:Object, target:Object):Void {
        var vx:Number = target.xmov;
        var vy:Number = target.ymov;
        if (isFinite(vx) && isFinite(vy) && (vx != 0 || vy != 0)) {
            state.baseAngleDeg = Math.atan2(vy, vx) * (180 / Math.PI);
            state.mirrorSign = (vx < 0) ? -1 : 1;
        }
    }

    public static function resolveSurfacePoint(state:Object, curX:Number, curY:Number, curZ:Number):Object {
        if (!isMapColliding(curX, curY, curZ)) {
            return {x:curX, y:curY};
        }
        if (state.hasSafePos && !isMapColliding(state.lastSafeX, state.lastSafeY, curZ)) {
            var loX:Number = state.lastSafeX;
            var loY:Number = state.lastSafeY;
            var hiX:Number = curX;
            var hiY:Number = curY;
            for (var i:Number = 0; i < 5; i++) {
                var midX:Number = (loX + hiX) * 0.5;
                var midY:Number = (loY + hiY) * 0.5;
                if (!isMapColliding(midX, midY, curZ)) {
                    loX = midX;
                    loY = midY;
                } else {
                    hiX = midX;
                    hiY = midY;
                }
            }
            return {x:loX, y:loY};
        }
        var clampedY:Number = (curY > curZ) ? curZ : curY;
        return {x:curX, y:clampedY};
    }

    public static function syncHooks(target:Object, state:Object):Void {
        if (target == null || state == null) return;
        if (target.击中时触发函数 !== state.hitWrapper) {
            if (typeof target.击中时触发函数 == "function") {
                state.origHitHook = target.击中时触发函数;
            }
            target.击中时触发函数 = state.hitWrapper;
        }
        if (target.击中地图时触发函数 !== state.mapWrapper) {
            if (typeof target.击中地图时触发函数 == "function") {
                state.origMapHook = target.击中地图时触发函数;
            }
            target.击中地图时触发函数 = state.mapWrapper;
        }
    }

    /** 绑定中心散射生命周期钩子；子级散射弹 (__scatterDepth >= 1) 不再二次绑定以阻断嵌套。 */
    public static function bind(target:Object, profile:ExplosionScatterProfile):Boolean {
        if (target == null || profile == null || target.__explosionScatter != undefined) return false;
        var depth:Number = target.__scatterDepth | 0;
        if (depth >= 1) return false;

        var snapshot:Object = {};
        for (var i:Number = 0; i < SNAPSHOT_KEYS.length; i++) {
            var key:String = SNAPSHOT_KEYS[i];
            snapshot[key] = target[key];
        }
        snapshot.发射者 = target.发射者名;
        snapshot.是否为敌人 = target.是否为敌人;

        var shooter:Object = (_root.gameworld != null) ? _root.gameworld[target.发射者名] : null;
        var facingLeft:Boolean = (shooter != null && shooter.方向 == "左");
        var baseDeg:Number = facingLeft ? 180 : 0;
        var mirror:Number = facingLeft ? -1 : 1;
        if (isFinite(target.xmov) && isFinite(target.ymov) && (target.xmov != 0 || target.ymov != 0)) {
            baseDeg = Math.atan2(target.ymov, target.xmov) * (180 / Math.PI);
            mirror = (target.xmov < 0) ? -1 : 1;
        }

        var parentZ:Number = target.Z轴攻击范围;
        var state:Object = {
            profile: profile,
            snapshot: snapshot,
            parentType: target.子弹种类,
            parentPower: Number(target.子弹威力),
            parentZRange: (isFinite(parentZ) && parentZ > 0) ? Number(parentZ) : 25,
            baseAngleDeg: baseDeg,
            mirrorSign: mirror,
            depth: depth,
            triggered: false,
            hasSafePos: false,
            lastSafeX: target._x,
            lastSafeY: target._y,
            lastSafeZ: target.Z轴坐标,
            hasResolvedPos: false,
            resolvedX: target._x,
            resolvedY: target._y,
            resolvedZ: target.Z轴坐标,
            hasImpactPos: false,
            impactX: target._x,
            impactY: target._y,
            impactZ: target.Z轴坐标,
            cf6Inherit: (target.__cf6DamageMember != null),
            origUpdate: target.updateMovement,
            origHitHook: null,
            origMapHook: null,
            hitWrapper: null,
            mapWrapper: null
        };

        if (!isMapColliding(target._x, target._y, target.Z轴坐标)) {
            state.hasSafePos = true;
        }

        target.__explosionScatter = state;

        target.updateMovement = function(projectile:Object):Void {
            var own:Object = projectile.__explosionScatter;
            if (own != null && !own.triggered) {
                ExplosionScatter.syncHooks(projectile, own);
                ExplosionScatter.updateHeading(own, projectile);
                if (!ExplosionScatter.isMapColliding(projectile._x, projectile._y, projectile.Z轴坐标)) {
                    own.lastSafeX = projectile._x;
                    own.lastSafeY = projectile._y;
                    own.lastSafeZ = projectile.Z轴坐标;
                    own.hasSafePos = true;
                }
            }
            if (own != null && typeof own.origUpdate == "function") {
                own.origUpdate.call(this, projectile);
            }
        };

        target.爆炸散射触发函数 = function():Void {
            ExplosionScatter.trigger(this);
        };

        state.mapWrapper = function():Void {
            var own:Object = this.__explosionScatter;
            if (own != null && !own.triggered) {
                ExplosionScatter.updateHeading(own, this);
                var safePt:Object = ExplosionScatter.resolveSurfacePoint(own, this._x, this._y, this.Z轴坐标);
                this._x = safePt.x;
                this._y = safePt.y;
                own.resolvedX = safePt.x;
                own.resolvedY = safePt.y;
                own.resolvedZ = this.Z轴坐标;
                own.hasResolvedPos = true;
            }
            if (own != null && typeof own.origMapHook == "function") {
                own.origMapHook.apply(this, arguments);
            } else if (typeof this.触发命中爆炸 == "function") {
                this.触发命中爆炸.apply(this, arguments);
            }
            if (own != null) {
                ExplosionScatter.triggerState(own, this);
            }
        };

        state.hitWrapper = function():Void {
            var own:Object = this.__explosionScatter;
            if (own != null && !own.triggered) {
                ExplosionScatter.updateHeading(own, this);
                var safePt:Object = ExplosionScatter.resolveSurfacePoint(own, this._x, this._y, this.Z轴坐标);
                own.impactX = safePt.x;
                own.impactY = safePt.y;
                own.impactZ = this.Z轴坐标;
                own.hasImpactPos = true;
            }
            if (own != null && typeof own.origHitHook == "function") {
                own.origHitHook.apply(this, arguments);
            } else if (typeof this.触发命中爆炸 == "function") {
                this.触发命中爆炸.apply(this, arguments);
            }
            if (own != null) {
                ExplosionScatter.triggerState(own, this);
            }
        };

        syncHooks(target, state);
        return true;
    }

    /** 由母弹时间轴 "爆炸" 帧或外部钩子调用；内部幂等，最多触发一次。 */
    public static function trigger(target:Object):Boolean {
        if (target == null) return false;
        return triggerState(target.__explosionScatter, target);
    }

    public static function triggerState(state:Object, target:Object):Boolean {
        if (state == null || state.triggered) return false;
        state.triggered = true;

        if ((state.depth | 0) >= 1) return false;
        var profile:ExplosionScatterProfile = state.profile;
        if (profile == null || profile.bulletType == null || profile.bulletType == ""
            || profile.bulletType == state.parentType) {
            return false;
        }

        var spawnX:Number;
        var spawnY:Number;
        var spawnZ:Number;
        if (state.hasResolvedPos) {
            spawnX = state.resolvedX;
            spawnY = state.resolvedY;
            spawnZ = state.resolvedZ;
        } else if (state.hasImpactPos) {
            spawnX = state.impactX;
            spawnY = state.impactY;
            spawnZ = state.impactZ;
        } else if (target != null) {
            var pt:Object = resolveSurfacePoint(state, target._x, target._y, target.Z轴坐标);
            spawnX = pt.x;
            spawnY = pt.y;
            spawnZ = target.Z轴坐标;
        } else {
            return false;
        }

        var childPower:Number;
        if (isFinite(profile.fixedPower)) {
            childPower = profile.fixedPower;
        } else if (isFinite(state.parentPower) && state.parentPower > 0) {
            childPower = state.parentPower * profile.powerScale;
        } else {
            childPower = profile.fallbackPower;
        }

        var childZRange:Number = (isFinite(profile.zRange) && profile.zRange > 0)
            ? profile.zRange : state.parentZRange;
        var snapshot:Object = state.snapshot;
        var angleSpan:Number = profile.maxAngle - profile.minAngle;
        var childDepth:Number = (state.depth | 0) + 1;

        for (var i:Number = 0; i < profile.count; i++) {
            var localDeg:Number = profile.minAngle + nextRand() * angleSpan;
            var worldDeg:Number = normalizeDeg(state.baseAngleDeg + state.mirrorSign * localDeg);
            var props:Object = {
                声音: "",
                霰弹值: 1,
                最小霰弹值: 1,
                子弹散射度: 0,
                发射效果: "",
                子弹种类: profile.bulletType,
                子弹威力: childPower,
                子弹速度: profile.speed,
                fixedRotation: worldDeg,
                Z轴攻击范围: childZRange,
                击中地图效果: "",
                击倒率: 10,
                击中后子弹的效果: "",
                noShell: true,
                shootX: spawnX,
                shootY: spawnY,
                shootZ: spawnZ,
                发射者: snapshot.发射者,
                是否为敌人: snapshot.是否为敌人,
                lockShooterAttributes: true
            };
            for (var k:Number = 0; k < SNAPSHOT_KEYS.length; k++) {
                var key:String = SNAPSHOT_KEYS[k];
                props[key] = snapshot[key];
            }
            if (props.伤害类型 == undefined) props.伤害类型 = "物理";
            if (state.cf6Inherit && target != null) {
                org.flashNight.arki.scene.Cf6DamageGroups.inherit(target, props);
            }
            var child:Object = _root.子弹区域shoot传递(props);
            if (child != null) {
                child.是否为敌人 = snapshot.是否为敌人;
                child.__scatterDepth = childDepth;
                if (isFinite(profile.lifetimeMs) && profile.lifetimeMs > 0) {
                    bindLifetime(child, profile.lifetimeMs);
                }
            }
        }
        return true;
    }

    /** 为次级散射弹绑定基于毫秒的生命周期 (不计入 _root.暂停 时长)。 */
    public static function bindLifetime(child:Object, lifetimeMs:Number):Boolean {
        if (child == null || !(lifetimeMs > 0) || !isFinite(lifetimeMs)
            || child.__scatterLifetime != undefined) return false;
        #include "../macros/STATE_LONG_RANGE.as"
        child.stateFlags |= STATE_LONG_RANGE;

        child.__scatterLifetime = {
            durationMs: lifetimeMs,
            elapsedMs: 0,
            lastClockMs: nowMs(),
            expired: false,
            origPrecheck: child.onEnterFrame,
            origShouldDestroy: child.shouldDestroy
        };

        child.onEnterFrame = function():Boolean {
            if (ExplosionScatter.advanceLifetime(this)) {
                this.removeMovieClip();
                return false;
            }
            var life:Object = this.__scatterLifetime;
            if (life != null && typeof life.origPrecheck == "function") {
                return life.origPrecheck.call(this);
            }
            return false;
        };

        child.shouldDestroy = function(projectile:Object):Boolean {
            if (ExplosionScatter.advanceLifetime(projectile)) {
                return true;
            }
            var life:Object = projectile.__scatterLifetime;
            if (life != null && typeof life.origShouldDestroy == "function") {
                return life.origShouldDestroy.call(this, projectile);
            }
            return false;
        };

        return true;
    }

    /** 推进次级弹毫秒时钟；到期返回 true。 */
    public static function advanceLifetime(child:Object):Boolean {
        var life:Object = (child != null) ? child.__scatterLifetime : null;
        if (life == null) return false;
        if (life.expired) return true;

        var now:Number = nowMs();
        var delta:Number = now - life.lastClockMs;
        if (isFinite(delta) && delta > 0) {
            life.lastClockMs = now;
            if (!_root.暂停) {
                life.elapsedMs += delta;
            }
        } else if (isFinite(now) && delta < 0) {
            life.lastClockMs = now;
        }

        if (!(life.elapsedMs < life.durationMs)) {
            life.expired = true;
            return true;
        }
        return false;
    }
}
