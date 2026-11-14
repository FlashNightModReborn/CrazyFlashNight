import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.naki.DataStructures.Dictionary;

/** 普通和魔法霰弹按目标去重，所有目标分享这一发的实弹预算。 */
class org.flashNight.arki.bullet.BulletComponent.Chain.ShotgunPattern {
    public static var MAX_AGE:Number = 180;
    public var age:Number = 0;
    public var hitCap:Number = 0;
    private var contacts:Object;

    /** 横向组装时守门；穿刺、透明等特殊弹继续走原规则。 */
    public static function bind(group:ChainGroup):Void {
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_TRANSPARENCY.as"
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"
        var b:Object = group.bullet;
        if (b.霰弹分配模式 == 1
            && (b.flags & (FLAG_PIERCE | FLAG_TRANSPARENCY | FLAG_MELEE | FLAG_EXPLOSIVE)) == 0) {
            group.shotgun = new ShotgunPattern();
        }
    }

    public static function hasBudget(bullet:Object):Boolean {
        var sc:Number = bullet.霰弹值;
        return sc < -65535 ? (((-sc) & 0xFFFF) > 0) : (sc > 0);
    }

    /** 暂停由统一 tick 守门；上限兜住停弹/特殊运动，不延长原射程。 */
    public function advance(group:ChainGroup):Boolean {
        age++;
        if (age > MAX_AGE || !hasBudget(group.bullet)) {
            ChainUnitManager.removeGroup(group);
            group.bullet.removeMovieClip();
            return false;
        }
        return true;
    }

    /** 在闪避、伤害和事件之前拒绝重复接触；只保存 dispatcher 数字身份。 */
    public function prepareContact(group:ChainGroup, target:Object, area:Object, zOffset:Number):Boolean {
        if (!hasBudget(group.bullet) || target.dispatcher == undefined) return false;
        var uid:Number = target.dispatcher.__dictUID;
        if (contacts != null && contacts[uid] === true) return false;
        hitCap = calculateCap(group, area, zOffset);
        if (!(hitCap > 0)) return false;
        if (contacts == null) contacts = {};
        if (uid === undefined) uid = Dictionary.getStaticUID(target.dispatcher);
        contacts[uid] = true;
        return true;
    }

    public function calculateCap(group:ChainGroup,area:Object,zOffset:Number):Number {
        var s:HorizontalShotCoverage = group.shotCoverage;
        var cap:Number = Math.round(s.contact(group,area,zOffset,true));
        // 普通霰弹沿用中距离给后排留一颗的规则。
        if (s.travel >= 90 && s.travel < 240 && s.birthCount > 1 && cap >= s.birthCount)
            cap = s.birthCount-1;
        return cap;
    }
}
