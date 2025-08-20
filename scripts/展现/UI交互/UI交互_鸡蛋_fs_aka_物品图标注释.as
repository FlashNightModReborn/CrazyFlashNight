import org.flashNight.arki.item.*;
import org.flashNight.gesh.array.*;
import org.flashNight.gesh.tooltip.*;

/**
 * 物品图标注释主入口函数
 * @param name:String 物品名称
 * @param value:Object 物品数值对象，包含level、tier等属性
 */
_root.物品图标注释 = function(name, value) {
    var 强化等级:Number = (value.level > 0) ? value.level : 1;
    var 物品数据:Object = ItemUtil.getItemData(name);

    // 1) 基础段描述（不含简介头与装备属性）
    var 描述文本:String = TooltipComposer.generateItemDescriptionText(物品数据);

    // 2) 简介面板文本（简介头 + 装备段）
    var 简介文本:String = TooltipComposer.generateIntroPanelContent(物品数据, value, 强化等级);

    // 3) 使用智能显示算法自动优化长短内容
    TooltipComposer.renderItemTooltipSmart(name, value, 描述文本, 简介文本, null);
};


/**
 * 技能栏技能图标注释
 * @param 对应数组号:Number 技能在主角技能表中的数组索引
 */
_root.技能栏技能图标注释 = function(对应数组号) {
    var 主角技能信息 = _root.主角技能表[对应数组号];
    var 技能名 = 主角技能信息[0];
    var 技能信息 = _root.技能表对象[技能名];

    var 是否装备或启用:String;
    if (技能信息.Equippable)
        是否装备或启用 = 主角技能信息[2] == true ? "<FONT COLOR='" + TooltipConstants.COL_HP + "'>已装备</FONT>" : "<FONT COLOR='#FFDDDD'>未装备</FONT>";
    else
        是否装备或启用 = 主角技能信息[4] == true ? "<FONT COLOR='" + TooltipConstants.COL_HP + "'>已启用</FONT>" : "<FONT COLOR='#FFDDDD'>未启用</FONT>";

    var 文本数据 = "<B>" + 技能信息.Name + "</B>";
    文本数据 += "<BR>" + 技能信息.Type + "   " + 是否装备或启用;
    文本数据 += "<BR>" + 技能信息.Description;
    文本数据 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
    文本数据 += "<BR>MP消耗：" + 技能信息.MP;
    文本数据 += "<BR>技能等级：" + 主角技能信息[1];
    // 文本数据 += "<BR>" + 是否装备或启用;

    TooltipLayout.hideTooltip(); // 保底清理

    // 使用技能图标显示注释
    var 计算宽度 = TooltipLayout.estimateWidth(文本数据, TooltipConstants.MIN_W, TooltipConstants.MAX_W);
    TooltipLayout.renderIconTooltip(true, 技能名, 文本数据, 计算宽度, "技能");
};

/**
 * 学习界面技能图标注释
 * @param 对应数组号:Number 技能在技能表中的数组索引
 */
_root.学习界面技能图标注释 = function(对应数组号) {
    var 技能信息 = _root.技能表[对应数组号];
    var 技能名 = 技能信息.Name;

    var 文本数据 = "<B>" + 技能名 + "</B>";
    文本数据 += "<BR>" + 技能信息.Type;
    文本数据 += "<BR>" + 技能信息.Description;
    文本数据 += "<BR>最高等级：" + 技能信息.MaxLevel;
    文本数据 += "<BR>解锁需要技能点数：" + 技能信息.UnlockSP;
    if (技能信息.MaxLevel > 1)
        文本数据 += "<BR>升级需要技能点数：" + 技能信息.UpgradeSP;
    文本数据 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
    文本数据 += "<BR>MP消耗：" + 技能信息.MP;
    文本数据 += "<BR>等级限制：" + 技能信息.UnlockLevel;

    TooltipLayout.hideTooltip(); // 保底清理

    // 使用技能图标显示注释
    var 计算宽度 = TooltipLayout.estimateWidth(文本数据, TooltipConstants.MIN_W, TooltipConstants.MAX_W);
    TooltipLayout.renderIconTooltip(true, 技能名, 文本数据, 计算宽度, "技能");
};


/**
 * 注释显示函数 (兼容接口，转发到 TooltipLayout.showTooltip)
 * @param 宽度:Number 注释框宽度
 * @param 内容:String 注释内容HTML文本
 * @param 框体:String 框体类型（可选，默认为主框体）
 */
_root.注释 = function(宽度, 内容, 框体) {
    TooltipLayout.showTooltip(宽度, 内容, 框体);
};

/**
 * 注释结束函数 (兼容接口，转发到 TooltipLayout.hideTooltip)
 */
_root.注释结束 = function() {
    TooltipLayout.hideTooltip();
};


