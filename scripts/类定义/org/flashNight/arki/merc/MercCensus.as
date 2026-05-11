import org.flashNight.arki.merc.*;

/*
 * MercCensus：场上人员普查（只读）。
 *
 * 两套统计语义：
 *   - countAllGendered: walk gameworld 数 mc.性别 != undefined（玩家/同伴/敌人/NPC 全算）。
 *     用于沿用 Symbol 2396 frame 29 的总人形 cap 语义（i<10 比较的就是这个）。
 *   - countAlive: 仅未受雇的佣兵（mc.NPC && !mc.是否为敌人 && mc.佣兵库编号 != undefined）。
 *     用于 MercBudget 的赤字判定——只关心"还需要刷几个佣兵"。
 *
 * 实现：每次 walk gameworld 子节点。spawn 触发频率本身不高，O(n) 单次成本可忽略。
 * 若未来 hot-path 调用频繁可改成 spawn/despawn 事件维护的计数器。
 */
class org.flashNight.arki.merc.MercCensus {

    public static function countAlive():Number {
        var count:Number = 0;
        var gw:MovieClip = _root.gameworld;
        for (var key:String in gw) {
            var mc:MovieClip = gw[key];
            if (mc.NPC && mc.是否为敌人 == false && mc.佣兵库编号 != undefined) {
                count++;
            }
        }
        return count;
    }

    public static function countAllGendered():Number {
        var count:Number = 0;
        var gw:MovieClip = _root.gameworld;
        for (var key:String in gw) {
            if (gw[key].性别 != undefined) {
                count++;
            }
        }
        return count;
    }

    /**
     * 调试工具：返回 "佣兵=N1 总人形=N2 [merc1, merc2, ...]"。
     * 给 baseDensity 标定时观察真值用，非业务路径调用。
     */
    public static function dump():String {
        var alive:Array = [];
        var gendered:Number = 0;
        var gw:MovieClip = _root.gameworld;
        for (var key:String in gw) {
            var mc:MovieClip = gw[key];
            if (mc.性别 != undefined) gendered++;
            if (mc.NPC && mc.是否为敌人 == false && mc.佣兵库编号 != undefined) {
                alive.push(mc.佣兵库编号);
            }
        }
        return "佣兵=" + alive.length + " 总人形=" + gendered + " [" + alive.join(", ") + "]";
    }
}
