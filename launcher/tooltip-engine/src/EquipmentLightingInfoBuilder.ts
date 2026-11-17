// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/EquipmentLightingInfoBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace EquipmentLightingInfoBuilder {
        const bladeOrder: any[] = ["static", "blood", "vocalist", "libra", "inductor", "lion", "capricorn"];
        const bladeText: any[] = [
            "持用兵器时照亮近处，收起后熄灭。",
            "拔剑时照亮近处，收剑或收起后熄灭。",
            "光剑形态展开时照亮近处，亮度随展开程度变化。",
            "默认形态在战技冷却期间发光；攻势与守御形态保持照明并改变光色。收起后熄灭。",
            "刀刃展开时照亮近处，亮度随展开程度变化，过载时改变光色。",
            "兵器激活期间照亮近处，失活或收起后熄灭。",
            "兵器激活窗口内照亮近处，窗口结束或收起后熄灭。"
        ];
        export function build(ctx: Context, item?: any, mods?: any[], standaloneMod?: boolean): any[] {
            var life: any = item.lifecycle;
            var result: any[] = [];
            if (!life || Array.isArray(life) || as2NotEqual(typeof life, "object"))
                return result;
            var body: boolean = false, torch: boolean = false, laser: boolean = false;
            var blades: any[] = [], baseBonus: number = 0, electricBonus: number = 0, activeBonus: number = 0;
            var electric: boolean = false, tagsRead: boolean = false;
            for (var key of as2Keys(life)) {
                if (!life.hasOwnProperty(key))
                    continue;
                var attr: any = life[key], routine: string = attr?.init?.initRoutines, param: any = attr?.init?.initParam;
                if (!param)
                    continue;
                if (as2NotEqual(param.energy, undefined) && !(as2Greater(as2Number(param.energy), 0)))
                    continue;
                if (as2Equal(routine, "装备自发光初始化")) {
                    if (as2Equal(param.group, "body"))
                        body = true;
                    else if (as2Equal(param.group, "blade")) {
                        var adapter: string = as2Equal(param.adapter, undefined) ? "static" : String(param.adapter);
                        for (var bi: number = 0; as2Less(bi, bladeOrder.length); bi++)
                            if (as2Equal(bladeOrder[bi], adapter))
                                blades[bi] = true;
                    }
                }
                else if (as2Equal(routine, "枪械激光初始化")) {
                    if (as2Equal(typeof param.beamLinkage, "string") && as2Greater(param.beamLinkage.length, 0))
                        laser = true;
                }
                else if (as2Equal(routine, "装备光源初始化")) {
                    if (as2Equal(param.kind, "laser"))
                        laser = true;
                    else if (as2Equal(param.kind, "flashlight")) {
                        torch = true;
                        if (!standaloneMod && as2Equal(attr.__modName, undefined) && param.builtinDefense !== true)
                            continue;
                        var amount: number = as2Number(param.evasionBonus);
                        var extra: number = as2Equal(param.electricEvasionBonus, undefined) ? 0 : as2Number(param.electricEvasionBonus);
                        if (!(as2Greater(amount, 0)) || !as2IsFinite(amount + extra) || as2Greater(amount + extra, 100) || as2Less(extra, 0))
                            continue;
                        if (standaloneMod) {
                            baseBonus = Math.max(baseBonus, amount);
                            electricBonus = Math.max(electricBonus, amount + extra);
                        }
                        else {
                            if (!tagsRead) {
                                electric = ctx.projection.electric === true;
                                tagsRead = true;
                            }
                            activeBonus = Math.max(activeBonus, amount + (electric ? extra : 0));
                        }
                    }
                }
            }
            if (body)
                result.push("穿戴时持续照亮自身周围，多件发光防具共同提供近身照明。<BR>");
            for (var i: number = 0; as2Less(i, bladeOrder.length); i++) {
                if (blades[i])
                    result.push(bladeText[i], "<BR>");
            }
            if (torch)
                result.push("持枪开灯时提供近身补光与前方照明；移动、换弹时保持，收枪后熄灭。<BR>");
            if (laser)
                result.push("持枪时投射激光，并提供狭窄束带的辅助照明；收枪后熄灭。<BR>");
            if (as2Greater(baseBonus, 0)) {
                result.push("持枪开灯期间：闪避加成 +", baseBonus);
                if (as2Greater(electricBonus, baseBonus))
                    result.push("；电力适配时 +", electricBonus);
                result.push("。多把手电取最高值，收枪或卸装后失效。<BR>");
            }
            else if (as2Greater(activeBonus, 0)) {
                result.push("持枪开灯期间：闪避加成 +", activeBonus, electric ? "（电力适配）" : "", "。多把手电取最高值，收枪或卸装后失效。<BR>");
            }
            if (as2Equal(result.length, 0))
                return result;
            return ["<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_LIGHTING_INFO + "</font><BR>", result.join("")];
        }
    }
}
