import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.tooltip.ItemUseTypes;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * EquipmentStatProjector - 装备调制预览属性投影器
 *
 * 职责：
 * - 将装备在指定 value(level/tier/mods) 下的最终生效属性投影为有序结构化行
 * - 仅供装备调制 preview 的 before/after 对比使用：纯计算，零写，不触碰存档
 *
 * 数据流：
 *   ItemUtil.getItemData(深克隆) -> EquipmentCalculator.calculateInPlace(应用进阶/强化/配件)
 *   -> 从解析后的 itemData.data 提取数值行 -> 按 TooltipConstants.PROPERTY_PRIORITIES 排序
 *
 * 输出行形状：{key:String, label:String, value:Number}
 * - key 通常为 data 层属性名；interval 按运行时口径投影为 fireRate，
 *   magicdefence 拍平为 "magicdefence.<元素>"
 * - label 为剥离 HTML 标签后的中文显示名（PROPERTY_DICT），power 按用途特化
 * - 仅供 Web 端 diff 渲染，AS2 侧不输出 HTML
 */
class org.flashNight.arki.item.equipment.EquipmentStatProjector {

    /**
     * 投影装备在指定 value 下的最终属性行
     * @param itemName 装备内部名
     * @param value 装备值对象 {level, tier, mods}（允许缺省字段）
     * @return 有序行数组 [{key, label, value}]；任何输入异常返回 []
     */
    public static function project(itemName:String, value:Object):Array {
        var rows:Array = [];
        if (itemName == null || itemName == "") return rows;

        // getItemData 返回深克隆（cloneFast 递归），calculateInPlace 就地修改安全
        var itemData:Object = ItemUtil.getItemData(itemName);
        if (itemData == null) return rows;

        var safeValue:Object = (value != null) ? value : {};
        var level:Number = Number(safeValue.level);
        if (isNaN(level) || level < 1) level = 1;
        var mods:Array = (safeValue.mods instanceof Array) ? safeValue.mods : [];

        EquipmentCalculator.calculateInPlace(
            itemData,
            {level:level, tier:safeValue.tier, mods:mods},
            EquipmentConfigManager.getFullConfig(),
            ModRegistry.getModDict());

        var data:Object = itemData.data;
        if (data == null) return rows;

        // 数值属性行：仅提取 PROPERTY_DICT 收录的权威展示字段
        var dict:Object = TooltipConstants.PROPERTY_DICT;
        var priorities:Object = TooltipConstants.PROPERTY_PRIORITIES;
        var keyed:Array = [];
        for (var key:String in data) {
            if (ObjectUtil.isInternalKey(key)) continue;
            if (dict[key] == undefined) continue;
            var num:Number = Number(data[key]);
            if (isNaN(num) || !isFinite(num)) continue;

            // interval 是毫秒级内部参数，玩家实际使用与枪械 tooltip 展示的都是射速。
            // 单独在循环后按 GunStatsBuilder 的同一公式投影，避免 Web 把 100→77
            // 显示成难以理解的“射击间隔 -23”。
            if (key == "interval") continue;

            // impact 同样是倒数生效的内部参数：运行时显示 floor(500 / raw)。
            // 预览若透出 raw，不但数值含义错误，增减极性也会与实际效果相反。
            if (key == "impact") {
                if (num <= 0) continue;
                num = Math.floor(500 / num);
            }
            keyed.push({
                key:key,
                label:labelFor(key, String(itemData.use)),
                value:num,
                priority:Number(priorities[key])
            });
        }

        var interval:Number = Number(data.interval);
        if (!isNaN(interval) && isFinite(interval) && interval > 0) {
            var shotMultiplier:Number = 1;
            if (data.bullet != undefined && data.bullet != null
                    && BulletTypeUtil.isVertical(String(data.bullet))) {
                var split:Number = Number(data.split);
                if (!isNaN(split) && isFinite(split) && split >= 1) {
                    shotMultiplier = split;
                }
            }
            keyed.push({
                key:"fireRate",
                label:TooltipConstants.LBL_FIRE_RATE + "（" + TooltipConstants.SUF_FIRE_RATE + "）",
                value:Math.floor(10000 / interval) * 0.1 * shotMultiplier,
                priority:Number(priorities.interval)
            });
        }
        keyed.sort(sortByPriority);
        for (var i:Number = 0; i < keyed.length; i++) {
            rows.push({key:keyed[i].key, label:keyed[i].label, value:keyed[i].value});
        }

        // 魔法抗性拍平为子行（"基础" 显示为 "能量"，对齐 quickBuildMagicDefence 语义）
        var magicdefence:Object = data.magicdefence;
        if (magicdefence != null && typeof(magicdefence) == "object") {
            var elems:Array = [];
            for (var elem:String in magicdefence) {
                if (ObjectUtil.isInternalKey(elem)) continue;
                var mdValue:Number = Number(magicdefence[elem]);
                if (isNaN(mdValue) || !isFinite(mdValue)) continue;
                elems.push(elem);
            }
            elems.sort();
            for (var j:Number = 0; j < elems.length; j++) {
                var elemKey:String = String(elems[j]);
                var elemName:String = (elemKey == TooltipConstants.TXT_BASE)
                    ? TooltipConstants.TXT_ENERGY : elemKey;
                rows.push({
                    key:"magicdefence." + elemKey,
                    label:"魔法抗性·" + elemName,
                    value:Number(magicdefence[elemKey])
                });
            }
        }

        return rows;
    }

    /**
     * 属性显示名：power 按用途特化（对齐旧强化预览语义），其余取 PROPERTY_DICT 并剥离标签
     * @private
     */
    private static function labelFor(key:String, use:String):String {
        if (key == "power") {
            if (use == ItemUseTypes.MELEE) return TooltipConstants.LBL_SHARPNESS;
            if (ItemUseTypes.isGun(use)) return TooltipConstants.LBL_BULLET_POWER;
        }
        return stripTags(String(TooltipConstants.PROPERTY_DICT[key]));
    }

    /**
     * 剥离简单 HTML 标签（PROPERTY_DICT 中 hp/mp/silence/poison/vampirism/rout 等含 FONT 包装）
     * @private
     */
    private static function stripTags(text:String):String {
        if (text == null) return "";
        var result:String = "";
        var depth:Number = 0;
        for (var i:Number = 0; i < text.length; i++) {
            var ch:String = text.charAt(i);
            if (ch == "<") {
                depth++;
            } else if (ch == ">") {
                if (depth > 0) depth--;
            } else if (depth == 0) {
                result += ch;
            }
        }
        return result;
    }

    /**
     * 按 PROPERTY_PRIORITIES 升序；同优先级按 key 字典序保证确定性
     * @private
     */
    private static function sortByPriority(a:Object, b:Object):Number {
        if (a.priority != b.priority) return a.priority < b.priority ? -1 : 1;
        if (a.key == b.key) return 0;
        return a.key < b.key ? -1 : 1;
    }
}
