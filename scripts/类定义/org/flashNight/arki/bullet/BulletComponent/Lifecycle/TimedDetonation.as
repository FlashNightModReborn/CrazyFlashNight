import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;

/**
 * 限时引爆 + 仅超时散射。复用普通 MC/单位弹的“消失”方法合同，不复制 Flash 素材。
 * 计时由弹体自身帧回调驱动，无独立异步任务；移除/转场即取消。
 * 先走原碰撞判定，再判断超时；队列终止仍是唯一出口。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TimedDetonation {
    private static var SNAPSHOT_KEYS:Array = ["伤害类型", "魔法伤害属性", "毒", "nanoToxic",
        "nanoToxicDecay", "吸血", "击溃", "斩杀", "暴击", "命中率", "固伤",
        "百分比伤害", "血量上限击溃", "防御粉碎", "友军伤害", "不硬直"];

    private function TimedDetonation() {}

    /** 仅在生命周期、伤害快照与 safeRemove 均已就绪后安装。 */
    public static function bind(target:Object, profile:TimedDetonationProfile, velocity:Object):Boolean {
        if (target == null || profile == null || target.__timedDetonation != undefined
            || typeof target.gotoAndPlay != "function" || typeof target.removeMovieClip != "function") return false;
        // 已配置的引信接管存活时间，不能先被普通弹的 900px 射程剪枝吞掉。
        if (profile.timeoutMs > 0) {
            #include "../macros/STATE_LONG_RANGE.as"
            target.stateFlags |= STATE_LONG_RANGE;
        }
        var snapshot:Object = {};
        for (var i:Number = 0; i < SNAPSHOT_KEYS.length; i++) {
            var key:String = SNAPSHOT_KEYS[i];
            snapshot[key] = target[key];
        }
        snapshot.子弹威力 = target.子弹威力;
        snapshot.发射者 = target.发射者名;
        snapshot.是否为敌人 = target.是否为敌人;
        var state:Object = {profile:profile, snapshot:snapshot, elapsedMs:0, lastMs:getTimer(),
            emitted:false, cancelled:false, timeoutRequested:false, reason:"",
            precheck:target.onEnterFrame, shouldDestroy:target.shouldDestroy,
            gotoAndPlay:target.gotoAndPlay, removeMovieClip:target.removeMovieClip,
            velocity:velocity};
        target.__timedDetonation = state;
        target.shouldDestroy = function(projectile:Object):Boolean {
            return TimedDetonation.shouldDestroy(projectile);
        };
        target.gotoAndPlay = function(frame):Void {
            var own:Object = this.__timedDetonation;
            if (frame == "消失") TimedDetonation.detonate(this);
            else own.gotoAndPlay.call(this, frame);
        };
        target.removeMovieClip = function():Void {
            var own:Object = this.__timedDetonation;
            if (!own.emitted) own.cancelled = true;
            delete this.onEnterFrame;
            own.removeMovieClip.call(this);
        };
        target.onEnterFrame = function():Boolean {
            var own:Object = this.__timedDetonation;
            if (own.emitted || own.cancelled) return false;
            TimedDetonation.advanceClock(this, getTimer(), !!_root.暂停);
            if (_root.暂停) return false;
            if (own.velocity != null) TimedDetonation.disableLegacyGravity(this);
            var queued:Boolean = own.precheck.call(this);
            // 无 area 的装饰性帧也必须有到期出口，不留永生计时弹。
            if (!queued && TimedDetonation.shouldDestroy(this)) this.gotoAndPlay("消失");
            return queued;
        };
        if (velocity != null) {
            disableLegacyGravity(target);
            target.xmov = velocity.x;
            target.ymov = velocity.z + velocity.down;
            target.updateMovement = function(projectile:Object):Void {
                TimedDetonation.advanceScatter(projectile);
            };
        }
        return true;
    }

    /** 毫秒墙钟按帧采样；暂停帧只刷新采样点，不计入引信。显式参数便于边界回归。 */
    public static function advanceClock(target:Object, nowMs:Number, paused:Boolean):Void {
        var state:Object = target.__timedDetonation;
        if (state.emitted || state.cancelled) return;
        var delta:Number = nowMs - state.lastMs;
        state.lastMs = nowMs;
        if (!paused && delta > 0 && isFinite(delta)) state.elapsedMs += delta;
    }

    public static function shouldDestroy(target:Object):Boolean {
        var state:Object = target.__timedDetonation;
        if (state.emitted || state.cancelled) return false;
        #include "../macros/STATE_HIT_MAP.as"
        if (((target.stateFlags | 0) & STATE_HIT_MAP) != 0 || state.shouldDestroy.call(target, target)) {
            state.timeoutRequested = false;
            return true;
        }
        var timeout:Number = state.profile.timeoutMs;
        if (timeout > 0 && !(state.elapsedMs < timeout)) {
            state.timeoutRequested = true;
            return true;
        }
        return false;
    }

    private static function disableLegacyGravity(target:Object):Void {
        // 普通手雷 area 的 onClipEvent(load) 安装旧的向上抛物线；本弹改由统一运动更新。
        // load 事件可能迟于 attachMovie 返回，用实例属性的写屏障挡住迟到安装。
        var area:Object = target.area;
        if (area == null || area.__timedGravityBlocked) return;
        delete area.onEnterFrame;
        area.addProperty("onEnterFrame", function() { return undefined; }, function(value):Void {});
        area.__timedGravityBlocked = true;
    }

    /** x/地面纵深 z 小幅偏移，down 为相对地面的正向下落速度。 */
    public static function scatterVelocity(index:Number, count:Number, speed:Number,
            spreadDegrees:Number, sample:Number):Object {
        var radius:Number = speed * Math.tan(spreadDegrees * Math.PI / 180) * (0.75 + sample * 0.25);
        var azimuth:Number = 2 * Math.PI * (index + 0.5) / count;
        return {x:radius * Math.cos(azimuth), z:radius * Math.sin(azimuth), down:speed};
    }

    /** 与 advanceScatter 相同的离散落体：n*v + g*n*(n-1)/2 >= 离地高度。 */
    public static function landingFrames(height:Number, speed:Number, gravity:Number):Number {
        if (!(height > 0) || !isFinite(height)) return 1;
        if (!(gravity > 0) || !isFinite(gravity)) return Math.max(1, Math.ceil(height / speed));
        var linear:Number = speed - gravity / 2;
        // 稳定形式避免小高度时 sqrt(...) - linear 的相消误差。
        var frames:Number = 2 * height / (Math.sqrt(linear * linear + 2 * gravity * height) + linear);
        return Math.max(1, Math.ceil(frames));
    }

    /**
     * 可选落地区域：横向均匀排布、纵深交错，避免四角大间隙与随机聚团。
     * 根据高度和本次重力预测飞行帧数；低空时整体收缩到向下散角上限内。
     * 未声明 landingSpread 时保持旧圆锥采样，供其他弹药继续复用。
     */
    public static function launchVelocity(index:Number, count:Number, scatter:Object,
            height:Number, gravity:Number, sample:Number):Object {
        var landing:Object = scatter.landingSpread;
        if (landing == null) return scatterVelocity(index, count, scatter.fallSpeed, scatter.spreadDegrees, sample);
        var frames:Number = landingFrames(height, scatter.fallSpeed, gravity);
        var x:Number = count > 1 ? landing.radiusX * (2 * index / (count - 1) - 1) / frames : 0;
        var row:Number = count > 1 ? (index % 2 == 0 ? -1 : 1) : 0;
        if (count % 2 != 0 && index == count - 1) row = 0;
        var z:Number = landing.radiusZ * row / frames;
        var planar:Number = Math.sqrt(x * x + z * z);
        var limit:Number = scatter.fallSpeed * Math.tan(scatter.spreadDegrees * Math.PI / 180);
        if (planar > limit) {
            var scale:Number = limit / planar;
            x *= scale;z *= scale;
        }
        return {x:x, z:z, down:scatter.fallSpeed};
    }

    public static function advanceScatter(target:Object):Void {
        var state:Object = target.__timedDetonation;
        if (state.emitted || state.cancelled || _root.暂停) return;
        disableLegacyGravity(target);
        var velocity:Object = state.velocity;
        target._x += velocity.x;
        target.Z轴坐标 += velocity.z;
        target._y += velocity.z + velocity.down;
        velocity.down += _root.重力加速度;
        target.ymov = velocity.z + velocity.down;
        if (!(target._y < target.Z轴坐标)) {
            target._y = target.Z轴坐标;
            target.gotoAndPlay("消失");
        }
    }

    private static function shot(state:Object, type:String, power:Number, zRange:Number,
            x:Number, y:Number, z:Number, source:Object):Object {
        var snapshot:Object = state.snapshot;
        var props:Object = {声音:"", 霰弹值:1, 子弹散射度:0, 发射效果:"", 子弹种类:type,
            子弹威力:power, 子弹速度:0, 速度X:0, 速度Y:0, Z轴攻击范围:zRange,
            击中地图效果:"", 击倒率:1, 击中后子弹的效果:"", 最小霰弹值:1,
            shootX:x, shootY:y, shootZ:z, 发射者:snapshot.发射者,
            是否为敌人:snapshot.是否为敌人, lockShooterAttributes:true};
        for (var i:Number = 0; i < SNAPSHOT_KEYS.length; i++) {
            var key:String = SNAPSHOT_KEYS[i];
            props[key] = snapshot[key];
        }
        if (props.伤害类型 == undefined) props.伤害类型 = "物理";
        // 与旧素材的 子弹属性初始化 一致，保留已有的受控射击归组/目标约束。
        if (source.__cf6DamageMember != null) {
            org.flashNight.arki.scene.Cf6DamageGroups.inherit(source, props);
        }
        return props;
    }

    private static function emit(props:Object, faction:Object):Object {
        var projectile:Object = _root.子弹区域shoot传递(props);
        // 构造入口默认读当前 shooter；派生物仍继承发射时阵营。
        if (projectile != null) projectile.是否为敌人 = faction;
        return projectile;
    }

    /** 幂等账本先于任何派生发射；重入、重复消失、拦截和落地均不会重复出弹。 */
    public static function detonate(target:Object):Boolean {
        var state:Object = target.__timedDetonation;
        if (state == null || state.emitted || state.cancelled) return false;
        #include "../macros/STATE_HIT_MAP.as"
        var impact:Boolean = !!target._killed || ((target.stateFlags | 0) & STATE_HIT_MAP) != 0
            || !(target._y < target.Z轴坐标);
        var timedOut:Boolean = state.timeoutRequested && !impact;
        state.reason = timedOut ? "timeout" : "impact";
        state.emitted = true;
        delete target.onEnterFrame;
        var profile:TimedDetonationProfile = state.profile;
        var blast:Object = profile.explosion;
        var power:Number = Number(state.snapshot.子弹威力);
        var x:Number = target._x, y:Number = target._y, z:Number = target.Z轴坐标;
        var faction:Object = state.snapshot.是否为敌人;
        var blastPower:Number = power ? power * blast.powerScale : blast.fallbackPower;
        emit(shot(state, blast.type, blastPower, blast.zRange, x, y, z, target), faction);
        var scatter:Object = profile.scatter;
        if (timedOut && scatter != null) {
            var childProfile:TimedDetonationProfile = new TimedDetonationProfile(0, scatter.explosion, null);
            for (var i:Number = 0; i < scatter.count; i++) {
                var velocity:Object = launchVelocity(i, scatter.count, scatter,
                    z - y, Number(_root.重力加速度), Math.random());
                var props:Object = shot(state, scatter.type, power * scatter.powerScale,
                    scatter.explosion.zRange, x, y, z, target);
                props.速度X = velocity.x;
                props.速度Y = velocity.z;
                var child:Object = emit(props, faction);
                if (child != null) bind(child, childProfile, velocity);
            }
        }
        target.removeMovieClip();
        return true;
    }
}
