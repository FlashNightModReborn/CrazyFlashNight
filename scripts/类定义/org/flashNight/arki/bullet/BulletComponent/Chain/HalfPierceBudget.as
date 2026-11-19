import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;

class org.flashNight.arki.bullet.BulletComponent.Chain.HalfPierceBudget {
    private static var randomState:Number = 0;

    public var birthTotal:Number;
    public var carry:Number = 0;
    public var age:Number = 0;
    public var started:Boolean = false;
    public var visualStart:Number = 0;
    private var lastLive:Number = 0;
    public var soleSource:Object;
    private var sources:Object;
    private var chance:Number;
    private var groupDeduplicates:Boolean;

    public static function accepts(bullet:Object):Boolean {
        #include "../macros/FLAG_NORMAL.as"
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_TRANSPARENCY.as"
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"
        var mask:Number = FLAG_NORMAL | FLAG_PIERCE | FLAG_TRANSPARENCY | FLAG_MELEE | FLAG_EXPLOSIVE;
        return (bullet.flags & mask) == FLAG_NORMAL;
    }

    public static function bind(group:ChainGroup, vertical:Boolean):Void {
        var bullet:Object = group.bullet;
        if (!group.isObject || !(bullet.continuationChance > 0)) return;
        var scatter:Number = bullet.霰弹值;
        if (!accepts(bullet) || !(scatter > 0) || scatter > 32767) return;

        group.halfPierce = new HalfPierceBudget(vertical ? scatter : 0, bullet.continuationChance, group.shotgun != null);
        if (vertical) bullet.霰弹值 = 1;
    }

    public function HalfPierceBudget(plannedBirths:Number, percent:Number, deduplicates:Boolean) {
        birthTotal = plannedBirths;
        chance = percent;
        groupDeduplicates = deduplicates;
    }

    public static function seed(value:Number):Void {
        randomState = (value | 0) || 0x6D2B79F5;
    }

    private static function nextWord():Number {
        var word:Number = randomState;
        if (word == 0) {
            seed((new Date().getTime() | 0) ^ getTimer());
            word = randomState;
        }
        word ^= word << 13;
        word ^= word >>> 17;
        word ^= word << 5;
        randomState = word;
        return word;
    }

    public static function rollSingle(percent:Number):Boolean {
        if (percent == 100) return true;
        if (percent == 50) return (nextWord() & 1) != 0;
        if (percent == 75) return (nextWord() & 3) != 0;
        return percent == 25 && (nextWord() & 3) == 3;
    }

    public static function sample(count:Number, percent:Number):Number {
        if (!(count > 0)) return 0;
        if (percent == 100) return count;
        var granted:Number = 0;
        do {
            var bits:Number;
            if (percent == 50) bits = nextWord();
            else if (percent == 75) bits = nextWord() | nextWord();
            else if (percent == 25) bits = nextWord() & nextWord();
            else return 0;

            // 单段（含最后一个尾段）直接取低位。25/75 档仍各取两个随机字，保持联弹原序列。
            if (count == 1) return granted + (bits & 1);
            if (count < 32) bits &= -1 >>> (32 - count);
            bits -= (bits >>> 1) & 0x55555555;
            bits = (bits & 0x33333333) + ((bits >>> 2) & 0x33333333);
            bits = (bits + (bits >>> 4)) & 0x0F0F0F0F;
            bits += bits >>> 8;
            bits += bits >>> 16;
            granted += bits & 63;
            count -= 32;
        } while (count > 0);
        return granted;
    }

    public function lockedCarry(dispatcher:Object):Number {
        if (sources == null) return soleSource === dispatcher ? carry : 0;
        var source:Object = sources;
        while (source != null) {
            if (source.dispatcher === dispatcher) return source.count;
            source = source.next;
        }
        return 0;
    }

    // 补弹中的纵联弹锚在枪口，长盒可以先于锚点到墙。续段沿地图层探测到目标的路径。
    public static function blocksVerticalCarry(bullet:Object, target:MovieClip):Boolean {
        var dx:Number = target._x - bullet._x;
        var steps:Number = Math.ceil(Math.abs(dx) / 24);
        var stepX:Number = dx / steps;
        var x:Number = bullet._x;
        var z:Number = bullet.Z轴坐标;
        var map:MovieClip = _root.collisionLayer;
        while (steps-- > 0) {
            x += stepX;
            if (map.hitTest(x, z, true)) return true;
        }
        return false;
    }

    public function trimTo(live:Number):Void {
        var lost:Number = lastLive - live;
        if (carry > 0 && lost > 0) spendCarry(lost < carry ? lost : carry, null);
        lastLive = live;
    }

    // 先分配正常首段，再消费来自其他目标的续存。新额度最后入账。
    public function settle(dispatcher:Object, live:Number, spent:Number, misses:Number):Number {
        var fresh:Number = live - carry;
        var firstUsed:Number = spent < fresh ? spent : fresh;
        var secondUsed:Number = spent - firstUsed;
        if (secondUsed > 0) spendCarry(secondUsed, dispatcher);

        var granted:Number = 0;
        if (firstUsed > 0 && misses < spent) {
            var effectiveFirst:Number = firstUsed;
            if (misses > 0) {
                effectiveFirst = secondUsed == 0 ? firstUsed - misses
                    : sampleEffectiveFirst(firstUsed, spent, misses);
            }
            granted = sample(effectiveFirst, chance);
            if (granted > 0) grantCarry(dispatcher, granted);
        }

        lastLive = live - spent + granted;
        return granted;
    }

    private function spendCarry(count:Number, excluded:Object):Void {
        if (count == carry) {
            sources = soleSource = null;
            carry = 0;
            return;
        }
        carry -= count;
        if (sources == null) return;
        var previous:Object = null;
        var source:Object = sources;
        while (count > 0 && source != null) {
            if (source.dispatcher === excluded) {
                previous = source;
                source = source.next;
                continue;
            }
            if (count < source.count) {
                source.count -= count;
                break;
            }
            count -= source.count;
            if (previous != null) previous.next = source.next;
            else sources = source.next;
            source = source.next;
        }
        if (sources.next == null) {
            soleSource = sources.dispatcher;
            sources = null;
        }
    }

    private function grantCarry(dispatcher:Object, count:Number):Void {
        var oldCarry:Number = carry;
        carry += count;
        // 标准横向霰弹已在 ShotgunPattern 拒绝整组重复接触。
        if (groupDeduplicates) return;
        if (sources == null) {
            if (oldCarry == 0 || soleSource === dispatcher) {
                soleSource = dispatcher;
                return;
            }
            sources = {dispatcher:soleSource, count:oldCarry};
            soleSource = null;
        }
        var source:Object = sources;
        while (source != null) {
            if (source.dispatcher === dispatcher) {
                source.count += count;
                return;
            }
            source = source.next;
        }
        sources = {dispatcher: dispatcher, count: count, next: sources};
    }

    // 仅在首、续段混合且存在部分 MISS 时，从总 MISS 数做无放回分配。
    private static function sampleEffectiveFirst(first:Number, total:Number, misses:Number):Number {
        var hits:Number = total - misses;
        var sampleHits:Boolean = hits < misses;
        var draws:Number = sampleHits ? hits : misses;
        var remainingFirst:Number = first;
        var picked:Number = 0;
        while (draws > 0 && remainingFirst > 0 && remainingFirst < total) {
            if (((nextWord() >>> 0) / 4294967296) * total < remainingFirst) {
                remainingFirst--;
                picked++;
            }
            draws--;
            total--;
        }
        if (remainingFirst == total) picked += draws;
        return sampleHits ? picked : first - picked;
    }
}
