/**
 * UnitActionIntentService - 单位动作意图邮箱
 *
 * 只管理“请求已发生、由谁消费、何时过期”，不裁决资源、冷却、姿态或动画。
 * 每个 channel 只保留一个 pending intent；提交发生在按键边沿/锁存出口，不产生逐帧对象。
 *
 * 当前试点：
 *   - 普通战技：提交 COMBAT/WEAPON_SKILL 后由 WeaponSkillInputService 同帧消费。
 *   - 副武器 F 换弹：提交 COMBAT/SUBWEAPON_RELOAD 后由持枪行走状态机消费。
 */
class org.flashNight.arki.unit.Action.Input.UnitActionIntentService {

    public static var CHANNEL_COMBAT:Number = 1;

    public static var KIND_WEAPON_SKILL:Number = 1;
    public static var KIND_SUBWEAPON_RELOAD:Number = 2;
    public static var KIND_PRIMARY_RELOAD:Number = 3;

    public static var DEFAULT_TTL_FRAMES:Number = 1;

    public static function submit(unit:Object,
                                  channel:Number,
                                  kind:Number,
                                  inputFrame:Number,
                                  ttlFrames:Number,
                                  payload:Object,
                                  priority:Number):Boolean {
        if (!unit || channel <= 0 || kind <= 0) return false;

        var frame:Number = normalizeFrame(inputFrame);
        var ttl:Number = normalizeTtl(ttlFrames);
        var resolvedPriority:Number = normalizePriority(priority);
        var slots:Object = getSlots(unit, true);
        var current:Object = slots[channel];

        if (current && !isExpired(current, frame)) {
            var currentPriority:Number = normalizePriority(current.priority);
            if (currentPriority > resolvedPriority) return false;
        }

        slots[channel] = {
            channel: channel,
            kind: kind,
            frame: frame,
            ttlFrames: ttl,
            payload: payload,
            priority: resolvedPriority
        };
        return true;
    }

    /**
     * 取得并消费指定 kind。suppressed=true 用于高优先级动作抢占：匹配意图会被清除但不返回。
     */
    public static function take(unit:Object,
                                channel:Number,
                                expectedKind:Number,
                                currentFrame:Number,
                                suppressed:Boolean):Object {
        var slots:Object = getSlots(unit, false);
        if (!slots) return null;

        var intent:Object = slots[channel];
        if (!intent) return null;
        if (isExpired(intent, normalizeFrame(currentFrame))) {
            delete slots[channel];
            return null;
        }
        if (expectedKind > 0 && intent.kind != expectedKind) return null;

        delete slots[channel];
        return suppressed ? null : intent;
    }

    public static function peek(unit:Object, channel:Number, currentFrame:Number):Object {
        var slots:Object = getSlots(unit, false);
        if (!slots) return null;

        var intent:Object = slots[channel];
        if (!intent) return null;
        if (isExpired(intent, normalizeFrame(currentFrame))) {
            delete slots[channel];
            return null;
        }
        return intent;
    }

    public static function has(unit:Object, channel:Number, kind:Number, currentFrame:Number):Boolean {
        var intent:Object = peek(unit, channel, currentFrame);
        return intent != null && (kind <= 0 || intent.kind == kind);
    }

    public static function cancelKind(unit:Object, channel:Number, kind:Number):Boolean {
        var slots:Object = getSlots(unit, false);
        if (!slots) return false;
        var intent:Object = slots[channel];
        if (!intent || (kind > 0 && intent.kind != kind)) return false;
        delete slots[channel];
        return true;
    }

    public static function clearAll(unit:Object):Void {
        if (!unit) return;
        delete unit.__unitActionIntentSlots;
    }

    private static function getSlots(unit:Object, create:Boolean):Object {
        if (!unit) return null;
        var slots:Object = unit.__unitActionIntentSlots;
        if (!slots && create) {
            slots = {};
            unit.__unitActionIntentSlots = slots;
        }
        return slots;
    }

    private static function isExpired(intent:Object, currentFrame:Number):Boolean {
        var age:Number = currentFrame - Number(intent.frame);
        return isNaN(age) || age < 0 || age > normalizeTtl(intent.ttlFrames);
    }

    private static function normalizeFrame(frame:Number):Number {
        return isNaN(frame) ? 0 : frame;
    }

    private static function normalizeTtl(ttlFrames:Number):Number {
        if (isNaN(ttlFrames) || ttlFrames < 0) return DEFAULT_TTL_FRAMES;
        return ttlFrames;
    }

    private static function normalizePriority(priority:Number):Number {
        return isNaN(priority) ? 0 : priority;
    }
}
