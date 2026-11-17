import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * SkillTooltipComposer - 技能注释内容权威
 *
 * 从 AS2 当前技能状态生成简介、描述与 NativeTooltipDocument，
 * 供保留的图标入口与 Native HUD 共用；不承担 Flash 绘制。
 */
class org.flashNight.gesh.tooltip.SkillTooltipComposer {

    /** One content authority for Flash callers and the native live HUD. */
    public static function describeLoadout(对应数组号:Number):Object {
    var 主角技能信息 = _root.主角技能表[对应数组号];
    var 技能名 = 主角技能信息[0];
    var 技能信息 = _root.技能表对象[技能名];

    var 是否装备或启用:String;
    if (技能信息.Equippable)
        是否装备或启用 = 主角技能信息[2] == true ? "<FONT COLOR='" + TooltipConstants.COL_HP + "'>已装备</FONT>" : "<FONT COLOR='#FFDDDD'>未装备</FONT>";
    else
        是否装备或启用 = 主角技能信息[4] == true ? "<FONT COLOR='" + TooltipConstants.COL_HP + "'>已启用</FONT>" : "<FONT COLOR='#FFDDDD'>未启用</FONT>";

    // 简介面板文本（基础信息）
    var 简介文本 = "<B>" + 技能信息.Name + "</B>";
    简介文本 += "<BR>" + 技能信息.Type + "   " + 是否装备或启用;
    简介文本 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 100) / 10;
    简介文本 += "<BR>MP消耗：" + 技能信息.MP;
    简介文本 += "<BR>技能等级：" + 主角技能信息[1];

    // 描述文本（独立出来，用于智能分栏）
    var 描述文本 = 技能信息.Description ? String(技能信息.Description) : "";

        return {name:技能名, intro:简介文本, description:描述文本,
            document:org.flashNight.gesh.tooltip.NativeTooltipDocument.buildSkill(技能名, 简介文本, 描述文本)};
    }


}
