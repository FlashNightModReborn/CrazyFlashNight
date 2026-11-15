/** 爆炸中心散射配置只读模板；由 bullets_cases.xml <explosionScatter> 解析。 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.ExplosionScatterProfile {
    public var bulletType:String;
    public var count:Number;
    public var speed:Number;
    public var lifetimeMs:Number;
    public var powerScale:Number;
    public var fixedPower:Number;
    public var fallbackPower:Number;
    public var minAngle:Number;
    public var maxAngle:Number;
    public var zRange:Number;

    public function ExplosionScatterProfile(
        bulletType:String,
        count:Number,
        speed:Number,
        lifetimeMs:Number,
        powerScale:Number,
        fixedPower:Number,
        fallbackPower:Number,
        minAngle:Number,
        maxAngle:Number,
        zRange:Number
    ) {
        this.bulletType = bulletType;
        this.count = count;
        this.speed = speed;
        this.lifetimeMs = lifetimeMs;
        this.powerScale = powerScale;
        this.fixedPower = fixedPower;
        this.fallbackPower = fallbackPower;
        this.minAngle = minAngle;
        this.maxAngle = maxAngle;
        this.zRange = zRange;
    }

    private static function hasNumericValue(v:Object):Boolean {
        if (v == undefined || v == null) return false;
        var t:String = typeof v;
        if (t == "boolean" || t == "object" || t == "function") return false;
        if (t == "string" && length(String(v)) == 0) return false;
        return isFinite(Number(v));
    }

    /** 解析并严格校验配置节点；缺省字段采用烟花式中心散射默认值，畸形字段整体拒绝并返回 null。 */
    public static function fromXml(raw:Object):ExplosionScatterProfile {
        if (raw == null || typeof raw != "object") return null;

        var typeVal:String = "次级穿刺子弹";
        if (raw.type != undefined) {
            if (typeof raw.type != "string" || length(raw.type) == 0) return null;
            typeVal = String(raw.type);
        }

        var countVal:Number = 5;
        if (raw.count != undefined) {
            if (!hasNumericValue(raw.count)) return null;
            countVal = Number(raw.count);
            if (!(countVal >= 1 && countVal <= 32 && countVal == Math.floor(countVal))) return null;
        }

        var speedVal:Number = 25;
        if (raw.speed != undefined) {
            if (!hasNumericValue(raw.speed)) return null;
            speedVal = Number(raw.speed);
            if (speedVal < 0) return null;
        }

        var lifetimeVal:Number = 320;
        if (raw.lifetimeMs != undefined) {
            if (!hasNumericValue(raw.lifetimeMs)) return null;
            lifetimeVal = Number(raw.lifetimeMs);
            if (!(lifetimeVal > 0)) return null;
        }

        var scaleVal:Number = 0.2;
        if (raw.powerScale != undefined) {
            if (!hasNumericValue(raw.powerScale)) return null;
            scaleVal = Number(raw.powerScale);
            if (scaleVal < 0) return null;
        }

        var fixedVal:Number = NaN;
        if (raw.power != undefined) {
            if (!hasNumericValue(raw.power)) return null;
            fixedVal = Number(raw.power);
            if (fixedVal < 0) return null;
        }

        var fallbackVal:Number = 100;
        if (raw.fallbackPower != undefined) {
            if (!hasNumericValue(raw.fallbackPower)) return null;
            fallbackVal = Number(raw.fallbackPower);
            if (fallbackVal < 0) return null;
        }

        var minVal:Number = 0;
        if (raw.minAngle != undefined) {
            if (!hasNumericValue(raw.minAngle)) return null;
            minVal = Number(raw.minAngle);
        }

        var maxVal:Number = 360;
        if (raw.maxAngle != undefined) {
            if (!hasNumericValue(raw.maxAngle)) return null;
            maxVal = Number(raw.maxAngle);
        }

        if (minVal > maxVal) return null;

        var zRangeVal:Number = NaN;
        if (raw.zRange != undefined) {
            if (!hasNumericValue(raw.zRange)) return null;
            zRangeVal = Number(raw.zRange);
            if (!(zRangeVal > 0)) return null;
        }

        return new ExplosionScatterProfile(
            typeVal, countVal, speedVal, lifetimeVal,
            scaleVal, fixedVal, fallbackVal, minVal, maxVal, zRangeVal
        );
    }
}
