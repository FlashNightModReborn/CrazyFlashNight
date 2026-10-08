import org.flashNight.arki.item.equipment.TagManager;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.gesh.tooltip.TooltipConstants;

// Read the effective lifecycle (including tier and installed mod projections).
// This is a description of supported behavior, not a query of live actor state.
class org.flashNight.gesh.tooltip.builder.EquipmentLightingInfoBuilder {
    private static var bladeOrder:Array = ["static","blood","vocalist","libra","inductor","lion","capricorn"];
    private static var bladeText:Array = [
        "持用兵器时照亮近处，收起后熄灭。",
        "拔剑时照亮近处，收剑或收起后熄灭。",
        "光剑形态展开时照亮近处，亮度随展开程度变化。",
        "默认形态在战技冷却期间发光；攻势与守御形态保持照明并改变光色。收起后熄灭。",
        "刀刃展开时照亮近处，亮度随展开程度变化，过载时改变光色。",
        "兵器激活期间照亮近处，失活或收起后熄灭。",
        "兵器激活窗口内照亮近处，窗口结束或收起后熄灭。"
    ];

    public static function build(item:Object, mods:Array, standaloneMod:Boolean):Array {
        var life:Object = item.lifecycle;
        var result:Array = [];
        if (!life || life instanceof Array || typeof life != "object") return result;
        var body:Boolean = false, torch:Boolean = false, laser:Boolean = false;
        var blades:Array = [], baseBonus:Number = 0, electricBonus:Number = 0, activeBonus:Number = 0;
        var electric:Boolean = false, tagsRead:Boolean = false;
        for (var key:String in life) {
            if (!life.hasOwnProperty(key)) continue;
            var attr:Object = life[key], routine:String = attr.init.initRoutines, param:Object = attr.init.initParam;
            if (param.energy != undefined && !(Number(param.energy) > 0)) continue;
            if (routine == "装备自发光初始化") {
                if (param.group == "body") body = true;
                else if (param.group == "blade") {
                    var adapter:String = param.adapter == undefined ? "static" : String(param.adapter);
                    for (var bi:Number = 0; bi < bladeOrder.length; bi++) if (bladeOrder[bi] == adapter) blades[bi] = true;
                }
            } else if (routine == "枪械激光初始化") {
                if (typeof param.beamLinkage == "string" && length(param.beamLinkage) > 0) laser = true;
            } else if (routine == "装备光源初始化") {
                if (param.kind == "laser") laser = true;
                else if (param.kind == "flashlight") {
                    torch = true;
                    // Ordinary built-in lamps remain visual-only. Sealed tactical lamps
                    // explicitly opt in through the same flag used by gameplay.
                    if (!standaloneMod && attr.__modName == undefined && param.builtinDefense !== true) continue;
                    var amount:Number = Number(param.evasionBonus);
                    var extra:Number = param.electricEvasionBonus == undefined ? 0 : Number(param.electricEvasionBonus);
                    if (!(amount > 0) || !isFinite(amount+extra) || amount+extra > 100 || extra < 0) continue;
                    if (standaloneMod) {
                        baseBonus = Math.max(baseBonus,amount);
                        electricBonus = Math.max(electricBonus,amount+extra);
                    } else {
                        if (!tagsRead) {
                            var present:Object = TagManager.buildPresentTagsDict(mods,item,ModRegistry.getModDict());
                            electric = !!present["电力"]; tagsRead = true;
                        }
                        activeBonus = Math.max(activeBonus,amount+(electric ? extra : 0));
                    }
                }
            }
        }
        if (body) result.push("穿戴时持续照亮自身周围，多件发光防具共同提供近身照明。<BR>");
        for (var i:Number = 0; i < bladeOrder.length; i++) {
            if (blades[i]) result.push(bladeText[i],"<BR>");
        }
        if (torch) result.push("持枪开灯时提供近身补光与前方照明；移动、换弹时保持，收枪后熄灭。<BR>");
        if (laser) result.push("持枪时投射激光，并提供狭窄束带的辅助照明；收枪后熄灭。<BR>");
        if (baseBonus > 0) {
            result.push("持枪开灯期间：闪避加成 +",baseBonus);
            if (electricBonus > baseBonus) result.push("；电力适配时 +",electricBonus);
            result.push("。多把手电取最高值，收枪或卸装后失效。<BR>");
        } else if (activeBonus > 0) {
            result.push("持枪开灯期间：闪避加成 +",activeBonus,electric ? "（电力适配）" : "",
                "。多把手电取最高值，收枪或卸装后失效。<BR>");
        }
        if (result.length == 0) return result;
        return ["<font color='"+TooltipConstants.COL_HL+"'>"+TooltipConstants.LBL_LIGHTING_INFO+"</font><BR>",result.join("")];
    }
}
