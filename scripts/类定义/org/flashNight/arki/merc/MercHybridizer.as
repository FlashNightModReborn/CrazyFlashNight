import org.flashNight.arki.merc.*;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/*
 * 佣兵杂交器（纯函数化）。
 *
 * 入口 hybridize 现在返回杂交后的 mercData 数组，不再写 _root.随机可雇佣兵。
 * 调用方（MercSpawner.createMercData）自己接结果。
 *
 * 数据依赖：MercLibrary.bundle.teams（战队信息）/ .names（随机名称库）
 *           _root.可雇佣兵 / _root.获取随机索引 / _root.深拷贝数组
 *           _root.根据权重获取随机对象 / _root.按宽度截断字符串 / _root.getItemData
 *
 * mercData 数组列约定（位置编码，被多处直接索引）：
 *   [0] 等级  [1] 名字  [2] id  [3] 身高  [4] 脸型  [5] 发型
 *   [6] 头部  [7] 上装  [8] 手部 [9] 下装 [10] 脚部 [11] 颈部
 *   [12] 长枪 [13] 手枪 [14] 手枪2 [15] 刀 [16] 手雷 [17] 性别
 *   [18] 价格 [19] 元数据 (子对象，键名中文)
 */
class org.flashNight.arki.merc.MercHybridizer {

    private static var DEVICE_EXCLUDE:Array = [
        "小熊", "诛神", "轶事奇人", "炎魔", "合金", "钛", "章鱼", "Andy",
        "JK", "余烬", "军阀", "装甲头盔", "奇美拉", "牙狼", "K5", "兽王", "异形"
    ];

    private static var EQUIP_TYPE_BY_SLOT:Array = [
        "头部装备", "上装装备", "手部装备", "下装装备", "脚部装备", "",
        "长枪", "手枪", "手枪", "刀", "手雷"
    ];

    public static function pickHybridIndex(n:Number, chance:Number, allow:Boolean):Number {
        if (LinearCongruentialEngine.instance.successRate(chance) and allow) {
            return _root.获取随机索引(_root.可雇佣兵);
        }
        return n;
    }

    public static function randomHybridName():String {
        var b:Object = MercLibrary.bundle;
        if (b == null) return "";
        return _root.随机选择数组元素(b.names);
    }

    // 不加 :String 类型注解：原帧脚本依赖运行时 String.prototype.trim
    // (Flash Player 提供，AS2 编译器不识别)。加了类型会触发"没有名为 trim 的方法"。
    public static function validateName(name) {
        if (name == undefined or name == null or name.trim() === "") {
            return "无名的佣兵";
        }
        return name;
    }

    public static function hybridName(n:Number, allow:Boolean, teamInfo:Object):String {
        if (!allow) {
            return validateName(_root.可雇佣兵[n][1]);
        }
        return _root.按宽度截断字符串(teamInfo.战队抬头 + " " + randomHybridName(), 30);
    }

    public static function allowHybrid(input:String):Boolean {
        for (var i:Number = 0; i < DEVICE_EXCLUDE.length; i++) {
            if (input.indexOf(DEVICE_EXCLUDE[i]) != -1) {
                return false;
            }
        }
        return true;
    }

    public static function allowEquipHybrid(equip, equipChance:Number):Boolean {
        if (equip === null or equip === "null"
            or equip === undefined or equip === "undefined" or equip === "") {
            return false;
        }
        if (typeof equip !== "string" or equip.trim().length === 0) {
            return false;
        }
        return LinearCongruentialEngine.instance.successRate(equipChance);
    }

    /**
     * 杂交一个佣兵，返回新的 mercData 副本。
     * 不修改 _root.可雇佣兵 也不写 _root.随机可雇佣兵。
     */
    public static function hybridize(n:Number, chance:Number, allow:Boolean):Array {
        var sample:Array = _root.深拷贝数组(_root.可雇佣兵[n]);
        var hybridLevel:Number = _root.可雇佣兵[pickHybridIndex(n, 100, allow)][0];
        var teamInfo:Object = _root.根据权重获取随机对象(MercLibrary.bundle.teams);
        var equipFactor:Number = 3;
        var equipLevel:Number;
        var selfEquipLevel:Number;
        var equipType:String;

        for (var slot:Number = 0; slot <= 16; slot++) {
            switch (slot) {
                case 0:
                    sample[0] = Math.min(
                        Math.floor(sample[0] * 1.5),
                        Math.max(sample[0], hybridLevel)
                    );
                    break;
                case 1:
                    sample[1] = hybridName(n, allow, teamInfo);
                    break;
                case 3: case 4: case 5: case 17:
                    sample[slot] = _root.可雇佣兵[pickHybridIndex(n, chance, allow)][slot];
                    break;
                case 11:
                    break;
                default:
                    var candidate = _root.可雇佣兵[pickHybridIndex(n, 100, allow)][slot];
                    if (candidate == undefined or candidate == "null"
                        or candidate == "undefined" or candidate == "") {
                        break;
                    }
                    equipLevel = _root.getItemData(candidate).data.level;
                    selfEquipLevel = _root.getItemData(sample[slot]).data.level;
                    equipType = _root.getItemData(candidate).use;
                    var equipHybridChance:Number = (equipLevel >= selfEquipLevel)
                        ? ((chance - (sample[0] - equipLevel) * 2) * equipFactor)
                        : 0;
                    var typeOk:Boolean = (equipType == EQUIP_TYPE_BY_SLOT[slot - 6])
                        and (equipLevel <= sample[0]);
                    if (typeOk
                        and allowHybrid(candidate)
                        and allowHybrid(sample[slot])
                        and allowEquipHybrid(candidate, equipHybridChance)) {
                        sample[slot] = candidate;
                    }
                    break;
            }
        }

        // 副武器互补：13 空 14 满 → 13 取 14；反之亦然
        if ((sample[13] == null or sample[13] == "undefined" or sample[13] == "")
            and (sample[14] != null and sample[14] != "undefined" and sample[14] != "")) {
            sample[13] = sample[14];
        } else if ((sample[14] == null or sample[14] == "undefined" or sample[14] == "")
            and (sample[13] != null and sample[13] != "undefined" and sample[13] != "")) {
            sample[14] = sample[13];
        }
        sample[11] = teamInfo.战队项链;
        sample[19].是否杂交 = true;
        return sample;
    }
}
