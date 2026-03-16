/**
 * ModStatBuilder - 配件属性构建器
 *
 * 从 TooltipTextBuilder.buildModStat 提取。
 * 包含配件查找、属性展示、installCondition 解析等逻辑。
 */
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.TooltipTextBuilder;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.tooltip.builder.UseSwitchStatsBuilder;
import org.flashNight.gesh.tooltip.builder.TagSwitchStatsBuilder;

class org.flashNight.gesh.tooltip.builder.ModStatBuilder {

    public static function build(itemName:String):Array {
        var result = [];

        var modData = EquipmentUtil.modDict[itemName];

        if(!modData) {
            modData = ModRegistry.getModDataByDisplayName(itemName);
            if(modData && EquipmentUtil.DEBUG_MODE) {
                TooltipBridge.debugLog("[buildModStat] 通过displayname索引找到配件: '" + itemName + "'");
            }
        }

        if(!modData) {
            var trimmedName:String = StringUtils.trim(itemName);
            if(trimmedName != itemName) {
                modData = EquipmentUtil.modDict[trimmedName];
                if(!modData) {
                    modData = ModRegistry.getModDataByDisplayName(trimmedName);
                }
                if(modData && EquipmentUtil.DEBUG_MODE) {
                    TooltipBridge.debugLog("[buildModStat] 通过trim后找到配件: '" + trimmedName + "'");
                }
            }
        }

        if(EquipmentUtil.DEBUG_MODE) {
            TooltipBridge.debugLog("[buildModStat] itemName='" + itemName + "', 找到配件=" + (modData != undefined));
        }

        if(!modData) return result;
        result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_MOD_INFO + "</font><BR>");
        result.push(TooltipConstants.LBL_MOD_USE_TYPE, "：", modData.use, "<BR>");
        if(modData.tagValue){
            result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.LBL_MOD_SLOT + "：</font>", modData.tagValue, "<BR>");
        }
        if(modData.weapontype){
            result.push(TooltipConstants.LBL_MOD_WEAPON_TYPE, "：", modData.weapontype, "<BR>");
        }
        if(modData.excludeWeapontype){
            result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_MOD_EXCLUDE_WEAPON_TYPE + "：</font>", modData.excludeWeapontype, "<BR>");
        }
        if(modData.grantsUse){
            result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_MOD_GRANTS_USE + "：</font>", modData.grantsUse, "<BR>");
        }
        if(modData.grantsWeapontype){
            result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_MOD_GRANTS_WEAPON_TYPE + "：</font>", modData.grantsWeapontype, "<BR>");
        }

        if(modData.provideTagDict){
            var provideTags = [];
            for(var pTag in modData.provideTagDict){
                if (ObjectUtil.isInternalKey(pTag)) continue;
                provideTags.push(pTag);
            }
            if(provideTags.length > 0){
                result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_PROVIDE_TAGS + "：</font>", provideTags.join(", "), "<BR>");
            }
        }

        if(modData.requireTagDict){
            var requireTags = [];
            for(var rTag in modData.requireTagDict){
                if (ObjectUtil.isInternalKey(rTag)) continue;
                requireTags.push(rTag);
            }
            if(requireTags.length > 0){
                result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_REQUIRE_TAGS + "：</font>", requireTags.join(", "), "<BR>");
            }
        }

        if(modData.excludeBulletTypeDict){
            var excludeNames:Array = bulletTypeDictToNames(modData.excludeBulletTypeDict);
            if(excludeNames.length > 0){
                result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_EXCLUDE_BULLET_TYPES + "：</font>", excludeNames.join(", "), "<BR>");
            }
        }

        if(modData.requireBulletTypeDict){
            var requireNames:Array = bulletTypeDictToNames(modData.requireBulletTypeDict);
            if(requireNames.length > 0){
                result.push("<font color='" + TooltipConstants.COL_INSTALL_COND + "'>" + TooltipConstants.LBL_REQUIRE_BULLET_TYPES + "：</font>", requireNames.join(", "), "<BR>");
            }
        }

        if(modData.installCondList){
            var condLines:Array = buildInstallConditionText(modData.installCondList);
            if(condLines.length > 0){
                result.push("<font color='" + TooltipConstants.COL_INSTALL_COND + "'>" + TooltipConstants.LBL_INSTALL_CONDITION + "：</font><BR>");
                for(var ci:Number = 0; ci < condLines.length; ci++){
                    result.push("  " + condLines[ci] + "<BR>");
                }
            }
        }

        var stats = modData.stats;
        UseSwitchStatsBuilder.buildStatBlock(result, stats, "");
        UseSwitchStatsBuilder.buildDetailed(result, stats);
        TagSwitchStatsBuilder.buildDetailed(result, stats);
        UseSwitchStatsBuilder.buildBulletSwitchDetailed(result, stats);

        if(modData.skill){
            // 反向依赖：buildSkillInfo 留在 TooltipTextBuilder 中
            result = result.concat(TooltipTextBuilder.buildSkillInfo(modData.skill));
        }

        if(typeof modData.description === "string"){
            result.push(TooltipFormatter.normalizeDescription(modData.description), TooltipFormatter.br());
        }
        return result;
    }

    // ==================== 辅助方法 ====================

    private static function bulletTypeDictToNames(typeDict:Object):Array {
        var names:Array = [];
        var nameMap:Object = TooltipConstants.BULLET_TYPE_NAMES;
        for(var key:String in typeDict){
            if(ObjectUtil.isInternalKey(key)) continue;
            var name:String = nameMap[key];
            names.push(name ? name : key);
        }
        return names;
    }

    private static var _pathNameMap:Object = null;
    private static function getPathNameMap():Object {
        if (_pathNameMap) return _pathNameMap;
        _pathNameMap = {actiontype: "动作类型"};
        _pathNameMap["data.damagetype"] = "伤害类型";
        _pathNameMap["data.interval"] = "攻击间隔";
        _pathNameMap["data.power"] = "威力";
        _pathNameMap["data.defence"] = "防御";
        _pathNameMap["data.weight"] = "重量";
        _pathNameMap["data.hp"] = "生命值";
        _pathNameMap["data.mp"] = "魔法值";
        _pathNameMap["data.accuracy"] = "精准";
        _pathNameMap["data.diffusion"] = "散布";
        _pathNameMap["data.velocity"] = "弹速";
        _pathNameMap["data.capacity"] = "弹匣容量";
        _pathNameMap["data.damage"] = "伤害";
        _pathNameMap["data.force"] = "力度";
        _pathNameMap["data.punch"] = "冲击";
        _pathNameMap["data.bullet"] = "子弹类型";
        _pathNameMap["data.magictype"] = "魔法属性";
        _pathNameMap["data.criticalhit"] = "暴击";
        _pathNameMap["data.bulletsize"] = "纵向范围";
        _pathNameMap["data.modslot"] = "插件槽";
        _pathNameMap["data.split"] = "霰弹值";
        return _pathNameMap;
    }

    private static var _opSymbolMap:Object = null;
    private static function getOpSymbolMap():Object {
        if (_opSymbolMap) return _opSymbolMap;
        _opSymbolMap = {
            isNot: " ≠ ",
            above: " > ",
            atLeast: " ≥ ",
            below: " &lt; ",
            atMost: " ≤ ",
            oneOf: " ∈ ",
            noneOf: " ∉ ",
            contains: " 包含 ",
            range: "",
            exists: " 存在",
            missing: " 不存在"
        };
        _opSymbolMap["is"] = " 为 ";
        return _opSymbolMap;
    }

    private static function buildInstallConditionText(condList:Object):Array {
        var lines:Array = [];
        if (!condList || !condList.conditions) return lines;

        var pathNames:Object = getPathNameMap();
        var opSymbols:Object = getOpSymbolMap();
        var conditions:Array = condList.conditions;

        for (var i:Number = 0; i < conditions.length; i++) {
            var cond:Object = conditions[i];
            if (!cond) continue;

            if (cond.type == "group") {
                var subLines:Array = buildInstallConditionText(cond);
                var modeLabel:String = (cond.mode == "any") ? "任一满足" : "全部满足";
                lines.push("<font color='" + TooltipConstants.COL_INSTALL_COND + "'>[" + modeLabel + "]</font>");
                for (var s:Number = 0; s < subLines.length; s++) {
                    lines.push("  " + subLines[s]);
                }
                continue;
            }

            var line:String;

            if (cond.path == "data.interval") {
                var rateValue:Number = Math.floor(10000 / Number(cond.value)) * 0.1;
                line = "射速" + reverseIntervalOp(cond.op) + rateValue + TooltipConstants.SUF_FIRE_RATE;
            } else {
                var pathLabel:String = pathNames[cond.path] || cond.path;
                var opSymbol:String = opSymbols[cond.op] || " " + cond.op + " ";
                if (cond.op == "exists" || cond.op == "missing") {
                    line = pathLabel + opSymbol;
                } else if (cond.op == "range") {
                    line = pathLabel + " ∈ [" + cond.min + ", " + cond.max + "]";
                } else if (cond.op == "oneOf" || cond.op == "noneOf") {
                    line = pathLabel + opSymbol + "{" + cond.value + "}";
                } else {
                    line = pathLabel + opSymbol + mapCondValue(cond.path, cond.value);
                }
            }

            lines.push(line);
        }

        return lines;
    }

    private static function reverseIntervalOp(op:String):String {
        if (op == "above")   return " &lt; ";
        if (op == "atLeast") return " ≤ ";
        if (op == "below")   return " &gt; ";
        if (op == "atMost")  return " ≥ ";
        return " = ";
    }

    private static function mapCondValue(path:String, value:String):String {
        if (path == "data.damagetype" && value == TooltipConstants.TXT_MAGIC) {
            return "属性";
        }
        return value;
    }
}
