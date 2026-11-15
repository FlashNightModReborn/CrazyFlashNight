// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/LoiteringMissileMovement.as

import org.flashNight.arki.bullet.BulletComponent.Movement.MissileMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.Util.PreLaunchMoveCallbacks;

/**
 * LoiteringMissileMovement
 * ========================
 * 巡飞弹 / 有限导引导弹运动组件（继承自 MissileMovement，实现 IMovement）。
 *
 * 为兼容旧时间轴『小型导弹』巡飞弹手感而设计：
 *  1. 发射速度缩放：实际位移按 velocity / baseVelocity（默认 20）等比缩放，
 *     使玩家武器（20）与不同敌兵/单位配置（8、16）均保持原有弹道速度曲线。
 *  2. 弹道上抛与初段散射：出生施加角度/位置随机散射与初始上抛速度（-10..-5），
 *     逐帧按 upwardTossDrag（0.4）衰减；锁定目标时可再次触发上抛。
 *  3. Z 轴加权索敌：通过 TargetCache 批量索敌，按 |dx| + zDistanceWeight * |dy| 选优，
 *     自动排除 FLAG_UNIT_BULLET（可拦截单位子弹）。
 *  4. 快照坐标 + 有限转向燃料：仅在首次锁定时记录目标坐标快照 (target._x, target._y + aimYOffset)，
 *     随后仅提供 turnFrames（18）帧有限角速度转向；燃料耗尽即转入 FreeFly 直线俯冲，
 *     不再追踪移动后的目标或重新索敌，保留玩家走位躲避窗口。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.LoiteringMissileMovement
    extends MissileMovement implements IMovement
{
    public var shooterName:String;
    public var _speedScale:Number = 1;
    public var _upwardVelocity:Number = 0;
    public var _upwardDrag:Number = 0.4;
    public var _linearDrag:Number = 0.02;
    public var _turnDrag:Number = 0.05;
    public var _turnSpeedFloor:Number = 5;
    public var _turnFramesLeft:Number = 0;
    public var _turnFramesTotal:Number = 1;
    public var _lockedOnce:Boolean = false;
    public var _lockX:Number = 0;
    public var _lockY:Number = 0;
    public var _lockZ:Number = 0;
    public var _initialY:Number = 0;
    public var _initialZ:Number = 0;
    public var _baseZ:Number = 0;
    public var _frameTurnDeg:Number = 0;
    public var _launchAngleDeg:Number = 0;
    public var _birthClipInitialized:Boolean = false;
    public var _searchIndex:Number = 0;
    public var _searchLen:Number = 0;
    public var _bestTarget:MovieClip = null;
    public var _minDist:Number = 2000;

    private static var DEFAULT_LOITER_CONFIG:Object = {
        mode: "loitering",
        baseVelocity: 20,
        initialSpeedMin: 0,
        initialSpeedMax: 3,
        cruiseAcceleration: 0.25,
        cruiseMaxSpeed: 5,
        lockAccelerationBoost: 1.25,
        lockedMaxSpeed: 80,
        linearDrag: 0.02,
        rotationSpeed: 36,
        dragCoefficient: 0.001,
        navigationRatio: 0,
        angleCorrection: 0,
        turnFrames: 18,
        turnDrag: 0.05,
        turnSpeedFloor: 5,
        birthAngleJitter: 15,
        birthOffsetXMin: 0,
        birthOffsetXMax: 30,
        birthOffsetYMin: -30,
        birthOffsetYMax: 0,
        upwardTossMin: -10,
        upwardTossMax: -5,
        upwardTossDrag: 0.4,
        reTossOnLock: true,
        aimYOffset: -30,
        lockRange: 2000,
        zDistanceWeight: 5,
        searchBatchSize: 16,
        searchRange: 30,
        preLaunchFrames: {min: 2, max: 4},
        preLaunchPeakHeight: {min: 5, max: 10},
        preLaunchHorizAmp: {min: 1, max: 3},
        preLaunchCycles: {min: 0.5, max: 1},
        rotationShakeTime: {start: 0.1, end: 0.2},
        rotationShakeAmplitude: 0.2
    };

    public function LoiteringMissileMovement(params:Object) {
        super(params);
    }

    private static function rand():Number {
        return (typeof(_root.basic_random) == "function") ? _root.basic_random() : Math.random();
    }

    private static function normalizeDeg(deg:Number):Number {
        if ((deg - deg) != 0) return 0;
        while (deg > 180) deg -= 360;
        while (deg <= -180) deg += 360;
        return deg;
    }

    private static function finiteOrDefault(val:Object, fallback:Number):Number {
        var n:Number = Number(val);
        return ((n - n) == 0) ? n : fallback;
    }

    private static function mergeConfig(raw:Object):Object {
        var cfg:Object = {};
        for (var key:String in DEFAULT_LOITER_CONFIG) {
            cfg[key] = DEFAULT_LOITER_CONFIG[key];
        }
        if (raw != null) {
            for (var rKey:String in raw) {
                if (raw[rKey] != undefined) {
                    cfg[rKey] = raw[rKey];
                }
            }
        }
        cfg.baseVelocity = finiteOrDefault(cfg.baseVelocity, DEFAULT_LOITER_CONFIG.baseVelocity);
        if (cfg.baseVelocity <= 0) cfg.baseVelocity = DEFAULT_LOITER_CONFIG.baseVelocity;
        cfg.initialSpeedMin = finiteOrDefault(cfg.initialSpeedMin, DEFAULT_LOITER_CONFIG.initialSpeedMin);
        cfg.initialSpeedMax = finiteOrDefault(cfg.initialSpeedMax, DEFAULT_LOITER_CONFIG.initialSpeedMax);
        cfg.cruiseAcceleration = finiteOrDefault(cfg.cruiseAcceleration, DEFAULT_LOITER_CONFIG.cruiseAcceleration);
        cfg.cruiseMaxSpeed = finiteOrDefault(cfg.cruiseMaxSpeed, DEFAULT_LOITER_CONFIG.cruiseMaxSpeed);
        cfg.lockAccelerationBoost = finiteOrDefault(cfg.lockAccelerationBoost, DEFAULT_LOITER_CONFIG.lockAccelerationBoost);
        cfg.lockedMaxSpeed = finiteOrDefault(cfg.lockedMaxSpeed, DEFAULT_LOITER_CONFIG.lockedMaxSpeed);
        cfg.linearDrag = finiteOrDefault(cfg.linearDrag, DEFAULT_LOITER_CONFIG.linearDrag);
        cfg.rotationSpeed = finiteOrDefault(cfg.rotationSpeed, DEFAULT_LOITER_CONFIG.rotationSpeed);
        cfg.turnFrames = finiteOrDefault(cfg.turnFrames, DEFAULT_LOITER_CONFIG.turnFrames);
        cfg.turnDrag = finiteOrDefault(cfg.turnDrag, DEFAULT_LOITER_CONFIG.turnDrag);
        cfg.turnSpeedFloor = finiteOrDefault(cfg.turnSpeedFloor, DEFAULT_LOITER_CONFIG.turnSpeedFloor);
        cfg.birthAngleJitter = finiteOrDefault(cfg.birthAngleJitter, DEFAULT_LOITER_CONFIG.birthAngleJitter);
        cfg.birthOffsetXMin = finiteOrDefault(cfg.birthOffsetXMin, DEFAULT_LOITER_CONFIG.birthOffsetXMin);
        cfg.birthOffsetXMax = finiteOrDefault(cfg.birthOffsetXMax, DEFAULT_LOITER_CONFIG.birthOffsetXMax);
        cfg.birthOffsetYMin = finiteOrDefault(cfg.birthOffsetYMin, DEFAULT_LOITER_CONFIG.birthOffsetYMin);
        cfg.birthOffsetYMax = finiteOrDefault(cfg.birthOffsetYMax, DEFAULT_LOITER_CONFIG.birthOffsetYMax);
        cfg.upwardTossMin = finiteOrDefault(cfg.upwardTossMin, DEFAULT_LOITER_CONFIG.upwardTossMin);
        cfg.upwardTossMax = finiteOrDefault(cfg.upwardTossMax, DEFAULT_LOITER_CONFIG.upwardTossMax);
        cfg.upwardTossDrag = finiteOrDefault(cfg.upwardTossDrag, DEFAULT_LOITER_CONFIG.upwardTossDrag);
        cfg.aimYOffset = finiteOrDefault(cfg.aimYOffset, DEFAULT_LOITER_CONFIG.aimYOffset);
        cfg.lockRange = finiteOrDefault(cfg.lockRange, DEFAULT_LOITER_CONFIG.lockRange);
        cfg.zDistanceWeight = finiteOrDefault(cfg.zDistanceWeight, DEFAULT_LOITER_CONFIG.zDistanceWeight);
        cfg.searchBatchSize = finiteOrDefault(cfg.searchBatchSize, DEFAULT_LOITER_CONFIG.searchBatchSize);
        if (cfg.searchBatchSize < 1) cfg.searchBatchSize = 1;
        cfg.searchRange = finiteOrDefault(cfg.searchRange, DEFAULT_LOITER_CONFIG.searchRange);
        if (typeof(cfg.reTossOnLock) == "string") {
            var s:String = String(cfg.reTossOnLock).toLowerCase();
            cfg.reTossOnLock = (s == "true" || s == "1");
        } else {
            cfg.reTossOnLock = (cfg.reTossOnLock !== false && cfg.reTossOnLock !== 0);
        }
        return cfg;
    }

    /**
     * 工厂方法：按巡飞弹参数构造有限导引导弹运动组件
     */
    public static function create(shooter:MovieClip,
                                  velocity:Number,
                                  angleDegrees:Number,
                                  config:Object,
                                  usePreLaunch:Boolean):LoiteringMissileMovement {
        var cfg:Object = mergeConfig(config);
        var initAngle:Number = normalizeDeg(finiteOrDefault(angleDegrees, 0));
        var initVel:Number = finiteOrDefault(velocity, cfg.baseVelocity);
        if (initVel < 0) initVel = 0;
        var scale:Number = initVel / cfg.baseVelocity;
        var ownerName:String = (shooter != null && shooter._name != undefined) ? shooter._name : null;
        var preLaunchFlag:Boolean = (usePreLaunch === true);

        var onInit:Function = function():Void {
            this.shooterName = ownerName;
            this.shooter = ownerName;
            this._launchAngleDeg = initAngle;
            this.rotationAngle = initAngle;
            this._speedScale = scale;

            var spdSpan:Number = cfg.initialSpeedMax - cfg.initialSpeedMin;
            this.speed = cfg.initialSpeedMin + rand() * (spdSpan > 0 ? spdSpan : 0);
            if (this.speed < 0 || (this.speed - this.speed) != 0) this.speed = 0;

            this.acceleration = cfg.cruiseAcceleration;
            this.maxSpeed = cfg.cruiseMaxSpeed;
            this._rotationSpeed = cfg.rotationSpeed;
            this._linearDrag = cfg.linearDrag;
            this._turnDrag = cfg.turnDrag;
            this._turnSpeedFloor = cfg.turnSpeedFloor;
            this._upwardDrag = cfg.upwardTossDrag;
            this._upwardVelocity = 0;
            this._turnFramesLeft = 0;
            this._turnFramesTotal = 1;
            this._lockedOnce = false;
            this._lockX = 0;
            this._lockY = 0;
            this._lockZ = 0;
            this._initialY = 0;
            this._initialZ = 0;
            this._baseZ = 0;
            this._frameTurnDeg = 0;
            this._birthClipInitialized = false;

            this._searchIndex = 0;
            this._searchLen = 0;
            this._bestTarget = null;
            this._minDist = cfg.lockRange;

            var initRad:Number = this.rotationAngle * Math.PI / 180;
            this.vx = Math.cos(initRad) * this.speed * this._speedScale;
            this.vy = Math.sin(initRad) * this.speed * this._speedScale;
            this.desiredAngularVelocity = 0;
        };

        var onSearch:Function = function():Boolean {
            // 巡飞弹特性：一旦锁定过快照目标并燃尽有限转向帧，永不重新索敌
            if (this._lockedOnce === true) {
                this._searchIndex = 0;
                this._searchLen = 0;
                this._bestTarget = null;
                this._minDist = cfg.lockRange;
                return false;
            }

            var targetObj:MovieClip = this.targetObject;
            if (targetObj != null && targetObj.cf6FixedFlight === true) {
                if (!org.flashNight.arki.scene.Cf6DamageGroups.enforceTarget(targetObj)) {
                    this._searchIndex = 0;
                    this._searchLen = 0;
                    return false;
                }
                var bound:MovieClip = targetObj.cf6BoundTarget;
                return this.lockSnapshotTarget(bound, cfg);
            }

            var gw:MovieClip = _root.gameworld;
            var currentShooter:MovieClip = (gw != null && this.shooterName != null) ? gw[this.shooterName] : null;
            if (!currentShooter || currentShooter.hp <= 0) {
                this.target = null;
                this.hasTarget = false;
                this._searchIndex = 0;
                this._searchLen = 0;
                this._bestTarget = null;
                this._minDist = cfg.lockRange;
                return false;
            }

            var searchCache:Array = _root.帧计时器.获取敌人缓存(currentShooter, cfg.searchRange);
            var len:Number = (searchCache != null) ? searchCache.length : 0;
            if (len <= 0) {
                this.target = null;
                this.hasTarget = false;
                this._searchIndex = 0;
                this._searchLen = 0;
                this._bestTarget = null;
                this._minDist = cfg.lockRange;
                return false;
            }

            if (this._searchLen != len) {
                this._searchIndex = 0;
                this._bestTarget = null;
                this._minDist = cfg.lockRange;
                this._searchLen = len;
            }

            // 排除可拦截子弹单位，沿用 |dx| + zDistanceWeight * |dy| 同行加权距离
            #include "../macros/FLAG_UNIT_BULLET.as"
            var endIndex:Number = Math.min(this._searchIndex + cfg.searchBatchSize, len);
            var curX:Number = (targetObj != null) ? targetObj._x : 0;
            var baseZ:Number = ((this._initialZ - this._initialZ) == 0) ? this._initialZ : this._initialY;
            var zWeight:Number = cfg.zDistanceWeight;

            for (var i:Number = this._searchIndex; i < endIndex; i++) {
                var potentialTarget:MovieClip = searchCache[i];
                if (potentialTarget && potentialTarget.hp > 0
                        && (potentialTarget.flags & FLAG_UNIT_BULLET) == 0) {
                    var px:Number = potentialTarget._x;
                    var rawPz:Number = potentialTarget.Z轴坐标;
                    var py:Number = ((rawPz - rawPz) == 0) ? rawPz : potentialTarget._y;
                    if ((px - px) == 0 && (py - py) == 0) {
                        var d:Number = Math.abs(px - curX) + zWeight * Math.abs(py - baseZ);
                        if (d < this._minDist) {
                            this._minDist = d;
                            this._bestTarget = potentialTarget;
                        }
                    }
                }
            }
            this._searchIndex = endIndex;

            if (this._searchIndex >= len) {
                var winner:MovieClip = this._bestTarget;
                this._searchIndex = 0;
                this._searchLen = 0;
                this._bestTarget = null;
                this._minDist = cfg.lockRange;
                if (winner != null) {
                    return this.lockSnapshotTarget(winner, cfg);
                }
                this.target = null;
                this.hasTarget = false;
                return false;
            }
            return false;
        };

        var onTrack:Function = function():Void {
            var targetObj:MovieClip = this.targetObject;
            if (targetObj != null && targetObj.cf6FixedFlight === true) {
                if (!org.flashNight.arki.scene.Cf6DamageGroups.enforceTarget(targetObj)) {
                    this._frameTurnDeg = 0;
                    return;
                }
                var bound:MovieClip = targetObj.cf6BoundTarget;
                if (bound != null) {
                    if ((bound._x - bound._x) == 0) this._lockX = bound._x;
                    if ((bound._y - bound._y) == 0) this._lockY = bound._y + cfg.aimYOffset;
                }
            }

            if (this._turnFramesLeft > 0) {
                this._turnFramesLeft--;
                var tx:Number = (targetObj != null) ? targetObj._x : 0;
                var ty:Number = (targetObj != null) ? targetObj._y : 0;
                var desiredDeg:Number = Math.atan2(this._lockY - ty, this._lockX - tx) * 180 / Math.PI;
                var diff:Number = normalizeDeg(desiredDeg - this.rotationAngle);
                var maxStep:Number = this._rotationSpeed;
                if (diff > maxStep) diff = maxStep;
                else if (diff < -maxStep) diff = -maxStep;
                this._frameTurnDeg = diff;

                var p:Number = 1 - (this._turnFramesLeft / this._turnFramesTotal);
                this._baseZ = this._initialZ + (this._lockZ - this._initialZ) * p;

                if (this._turnFramesLeft <= 0) {
                    this.hasTarget = false;
                    this.target = null;
                }
            } else {
                this._frameTurnDeg = 0;
                this.hasTarget = false;
                this.target = null;
            }
        };

        var params:Object = {
            usePreLaunch: preLaunchFlag,
            config: cfg,
            onInitializeMissile: onInit,
            onSearchForTarget: onSearch,
            onTrackTarget: onTrack,
            onPreLaunchMove: PreLaunchMoveCallbacks.create(cfg, initAngle)
        };

        return new LoiteringMissileMovement(params);
    }

    /**
     * 锁定单次目标快照（不随目标后续移动刷新坐标）
     */
    public function lockSnapshotTarget(chosen:MovieClip, cfg:Object):Boolean {
        if (!chosen) return false;
        this._lockedOnce = true;
        this.target = chosen;
        this.hasTarget = true;

        var fallbackX:Number = (this.targetObject != null) ? this.targetObject._x : 0;
        var fallbackY:Number = (this.targetObject != null) ? this.targetObject._y : 0;
        this._lockX = ((chosen._x - chosen._x) == 0) ? chosen._x : fallbackX;
        this._lockY = (((chosen._y - chosen._y) == 0) ? chosen._y : fallbackY) + cfg.aimYOffset;

        var cz:Number = chosen.Z轴坐标;
        if ((cz - cz) == 0) {
            this._lockZ = cz;
        } else if ((chosen._y - chosen._y) == 0) {
            this._lockZ = chosen._y;
        } else {
            this._lockZ = this._initialZ;
        }

        this.acceleration += cfg.lockAccelerationBoost;
        this.maxSpeed = cfg.lockedMaxSpeed;

        var budget:Number = Math.floor(cfg.turnFrames);
        if ((budget - budget) != 0 || budget < 0) budget = 18;
        this._turnFramesLeft = budget;
        this._turnFramesTotal = (budget > 0) ? budget : 1;

        if (cfg.reTossOnLock) {
            var tSpan:Number = cfg.upwardTossMax - cfg.upwardTossMin;
            this._upwardVelocity = cfg.upwardTossMin + rand() * (tSpan > 0 ? tSpan : 0);
        }
        return true;
    }

    private function initBirthClip(target:MovieClip, applyJitter:Boolean):Void {
        var cfg:Object = this.config;
        if (applyJitter) {
            var jitter:Number = finiteOrDefault(cfg.birthAngleJitter, 0);
            this.rotationAngle = normalizeDeg(this._launchAngleDeg + jitter - rand() * (jitter * 2));
            target._rotation = this.rotationAngle;

            var radDir:Number = this._launchAngleDeg * Math.PI / 180;
            var dirSign:Number = (Math.cos(radDir) >= 0) ? 1 : -1;
            var oxMin:Number = finiteOrDefault(cfg.birthOffsetXMin, 0);
            var oxMax:Number = finiteOrDefault(cfg.birthOffsetXMax, 0);
            var oxSpan:Number = oxMax - oxMin;
            target._x += dirSign * (oxMin + rand() * (oxSpan > 0 ? oxSpan : 0));

            var oyMin:Number = finiteOrDefault(cfg.birthOffsetYMin, 0);
            var oyMax:Number = finiteOrDefault(cfg.birthOffsetYMax, 0);
            var oySpan:Number = oyMax - oyMin;
            target._y += oyMin + rand() * (oySpan > 0 ? oySpan : 0);
        }

        this._initialY = target._y;
        this._initialZ = target.Z轴坐标;
        this._baseZ = this._initialZ;

        var tossMin:Number = finiteOrDefault(cfg.upwardTossMin, 0);
        var tossMax:Number = finiteOrDefault(cfg.upwardTossMax, 0);
        var tossSpan:Number = tossMax - tossMin;
        this._upwardVelocity = tossMin + rand() * (tossSpan > 0 ? tossSpan : 0);
        this._birthClipInitialized = true;
    }

    /**
     * 每帧由 BulletManager / lifecycle 驱动的巡飞弹运动更新
     */
    public function updateMovement(target:MovieClip):Void {
        if (target.cf6FixedFlight === true && !org.flashNight.arki.scene.Cf6DamageGroups.enforceTarget(target)) {
            return;
        }
        if ((target._x - target._x) != 0) {
            target._x = 0;
        }
        var targetY:Number = target._y;
        if ((targetY - targetY) != 0) {
            targetY = 0;
            target._y = 0;
        }
        if ((target._rotation - target._rotation) != 0) {
            target._rotation = 0;
        }
        var targetPlaneZ:Number = target.Z轴坐标;
        if ((targetPlaneZ - targetPlaneZ) != 0) {
            targetPlaneZ = targetY;
            target.Z轴坐标 = targetPlaneZ;
        }

        if (!this._birthClipInitialized && !this.usePreLaunch) {
            this.initBirthClip(target, true);
        }

        this._frameTurnDeg = 0;

        // 直接驱动状态机（不调用 MissileMovement.updateMovement，避免叠加比例导引向量物理）
        this.targetObject = target;
        this.stateMachine.onAction();

        ++this.frame;
        if (this.frame >= 150) {
            target.shouldDestroy = function():Boolean {
                return true;
            };
        }

        if (this.lockRotation) {
            this.lockRotation = false;
            if (!this._birthClipInitialized) {
                this._initialY = target._y;
                this._initialZ = target.Z轴坐标;
                this._baseZ = this._initialZ;
            }
            return;
        }

        if (!this._birthClipInitialized) {
            this.initBirthClip(target, false);
        }

        if (this._upwardVelocity < 0) {
            this._upwardVelocity += this._upwardDrag;
        }
        if (this._upwardVelocity > 0 || (this._upwardVelocity - this._upwardVelocity) != 0) {
            this._upwardVelocity = 0;
        }

        if ((this.speed - this.speed) != 0 || this.speed < 0) {
            this.speed = 0;
        }
        if ((this.acceleration - this.acceleration) != 0) {
            this.acceleration = 0;
        }
        if ((this.maxSpeed - this.maxSpeed) != 0 || this.maxSpeed < 0) {
            this.maxSpeed = 0;
        }
        if (this.speed < this.maxSpeed) {
            this.speed = this.speed + this.acceleration - this.speed * this._linearDrag;
        }
        if (this.speed > this.maxSpeed) {
            this.speed = this.maxSpeed;
        }
        if (this.speed < 0 || (this.speed - this.speed) != 0) {
            this.speed = 0;
        }

        var turnDeg:Number = this._frameTurnDeg;
        if ((turnDeg - turnDeg) != 0) turnDeg = 0;
        if (turnDeg != 0) {
            if (this.speed > this._turnSpeedFloor) {
                this.speed -= Math.abs(turnDeg * this._turnDrag);
                if (this.speed < 0) this.speed = 0;
            }
            this.rotationAngle = normalizeDeg(this.rotationAngle + turnDeg);
        } else {
            this.rotationAngle = normalizeDeg(this.rotationAngle);
        }
        target._rotation = this.rotationAngle;

        var rad:Number = this.rotationAngle * Math.PI / 180;
        var scaleVal:Number = ((this._speedScale - this._speedScale) == 0 && this._speedScale >= 0) ? this._speedScale : 1;
        var effSpeed:Number = this.speed * scaleVal;
        var dx:Number = Math.cos(rad) * effSpeed;
        var dy:Number = Math.sin(rad) * effSpeed;
        if ((dx - dx) != 0) dx = 0;
        if ((dy - dy) != 0) dy = 0;

        this.vx = dx;
        this.vy = dy + this._upwardVelocity;
        target.xmov = this.vx;
        target.ymov = this.vy;
        target._x += dx;
        target._y += this.vy;

        var zOut:Number = ((this._baseZ - this._baseZ) == 0) ? this._baseZ : target.Z轴坐标;
        if (this._lockedOnce && this._turnFramesLeft > 0 && zOut < target._y) {
            zOut = target._y;
        }
        target.Z轴坐标 = zOut;
    }

    public function freeFly():Void {
    }
}
