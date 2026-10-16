/** Lee 攻入篇的运行账与判定；不依赖画面、存档或计时器。 */
class org.flashNight.arki.scene.LeeAssaultRules {
    public static function create(roomCount:Number, bolts:Number, threshold:Number):Object {
        var rooms:Array = [];
        for (var i:Number = 0; i < roomCount; i++) rooms.push({index:i, hits:0, damage:0,
            seen:{}, fired:0, resolved:false, cleared:false, powerOff:false});
        return {v:1, bolts:bolts, threshold:threshold, hits:0, damage:0, revives:0,
            awakened:false, awakeningRoom:-1, ending:"", rooms:rooms};
    }
    /** 每个落雷只能在真实命中回调中记一次；失效世界、假命中由调用方拒绝。 */
    public static function recordHit(state:Object, index:Number, bolt:Number, damage:Number):Boolean {
        var room:Object = state.rooms[index];
        if (room == null || room.resolved === true || room.cleared !== true
                || !(damage > 0) || !isFinite(damage) || isNaN(bolt)
                || Math.floor(bolt) != bolt || bolt < 0 || !(bolt < state.bolts)
                || room.seen["$" + bolt] === true) return false;
        room.seen["$" + bolt] = true;
        room.hits++; room.damage += damage;
        state.hits++; state.damage += damage;
        return true;
    }
    public static function resolve(state:Object, index:Number, alive:Boolean):Boolean {
        var room:Object = state.rooms[index];
        if (room == null || room.resolved === true || room.fired != state.bolts) return false;
        room.resolved = true; room.powerOff = true;
        if (!state.awakened && alive && state.revives == 0 && !(state.hits < state.threshold)) {
            state.awakened = true; state.awakeningRoom = index;
            return true;
        }
        return false;
    }
    /** 放电进度控制光照上下限；躲开伤害也不阻止线路耗尽。 */
    public static function powerBounds(battle:Number, outage:Number, progress:Number):Object {
        if (isNaN(progress)) progress = 0;
        progress = Math.max(0, Math.min(1, progress));
        return {min:battle * (1-progress), max:progress == 1 ? outage : battle + (outage-battle) * progress};
    }
    public static function respawn(state:Object):Void { state.revives++; }
    /** 原生电伤公式的逆投影；固伤不含随机波动，结果仍经过真实命中、护盾和电抗。 */
    public static function lightningSolid(target:Object, hpCost:Number):Number {
        var table:Object = target.魔法抗性;
        var resist:Number = table.电;
        if (resist == undefined) resist = table.基础;
        if (resist == undefined || isNaN(resist)) resist = 10 + (Number(target.等级) >> 1);
        resist = Math.max(-1000, resist);
        if (resist > 95) resist = Math.min(100, 95 + (resist - 95) / 10);
        // 全身电免目标不作反向补偿；黑龙的免疫仍成立。
        if (!(resist < 100)) return 0;
        var taken:Number = Number(target.damageTakenMultiplier);
        if (!(taken > 0) || !isFinite(taken)) taken = 1;
        return Math.ceil(hpCost / ((100 - resist) * .01 * taken));
    }
}
