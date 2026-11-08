/** 配表只读模板；每发的计时、原因与一次性账本保存在 TimedDetonation 的实例状态中。 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TimedDetonationProfile {
    public var timeoutMs:Number;
    public var explosion:Object;
    public var timeoutExplosion:Object;
    public var scatter:Object;

    public function TimedDetonationProfile(timeoutMs:Number, explosion:Object, scatter:Object, timeoutExplosion:Object) {
        this.timeoutMs = timeoutMs;
        this.explosion = explosion;
        this.timeoutExplosion = timeoutExplosion != null ? timeoutExplosion : explosion;
        this.scatter = scatter;
    }

    private static function nonnegative(value:Object):Boolean {
        var n:Number = Number(value);
        return isFinite(n) && !(n < 0);
    }

    private static function readExplosion(node:Object):Object {
        if (typeof node.type != "string" || length(node.type) == 0
            || !nonnegative(node.powerScale) || !nonnegative(node.fallbackPower)
            || !(Number(node.zRange) > 0) || !isFinite(Number(node.zRange))) return null;
        return {type:String(node.type), powerScale:Number(node.powerScale),
            fallbackPower:Number(node.fallbackPower), zRange:Number(node.zRange)};
    }

    /** 缺失/畸形配置整体拒绝，不能静默退化成“只爆炸、不散射”的半套新机制。 */
    public static function fromXML(node:Object):TimedDetonationProfile {
        var timeout:Number = Number(node.timeoutMs);
        var blast:Object = readExplosion(node.explosion);
        if (!(timeout > 0) || !isFinite(timeout) || blast == null) return null;
        var timeoutBlast:Object = blast;
        if (node.timeoutExplosion != undefined) {
            timeoutBlast = readExplosion(node.timeoutExplosion);
            if (timeoutBlast == null) return null;
        }
        var scatter:Object = null;
        if (node.timeoutScatter != undefined) {
            var source:Object = node.timeoutScatter;
            var count:Number = Number(source.count);
            var fallSpeed:Number = Number(source.fallSpeed);
            var spread:Number = Number(source.spreadDegrees);
            var launchAngle:Number = source.launchAngle != undefined ? Number(source.launchAngle) : 0;
            var childBlast:Object = readExplosion(source.explosion);
            if (typeof source.type != "string" || length(source.type) == 0
                || !(count > 0) || count > 32 || count != Math.floor(count)
                || !(fallSpeed > 0) || !isFinite(fallSpeed)
                || !nonnegative(source.powerScale) || !nonnegative(spread)
                || spread > 45 || !isFinite(launchAngle)
                || launchAngle <= -90 || launchAngle >= 90 || childBlast == null) return null;
            var landing:Object = null;
            if (source.landingSpread != undefined) {
                var radiusX:Number = Number(source.landingSpread.radiusX);
                var radiusZ:Number = Number(source.landingSpread.radiusZ);
                if (!nonnegative(radiusX) || !nonnegative(radiusZ)
                    || !(radiusX + radiusZ > 0) || !(spread > 0)) return null;
                landing = {radiusX:radiusX, radiusZ:radiusZ};
            }
            scatter = {type:String(source.type), count:count,
                powerScale:Number(source.powerScale), fallSpeed:fallSpeed,
                spreadDegrees:spread, launchAngle:launchAngle,
                landingSpread:landing, explosion:childBlast};
        }
        return new TimedDetonationProfile(timeout, blast, scatter, timeoutBlast);
    }
}