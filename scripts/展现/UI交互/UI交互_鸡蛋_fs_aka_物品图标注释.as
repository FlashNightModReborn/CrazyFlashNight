import org.flashNight.arki.item.*;
import org.flashNight.gesh.array.*;
import org.flashNight.gesh.tooltip.*;
import org.flashNight.gesh.string.*;
/**
 * 物品图标注释主入口函数
 * @param name:String 物品名称
 * @param value:Object 物品数值对象，包含level、tier等属性
 */
_root.物品图标注释 = function(name, value, baseItem) {
    var 强化等级:Number = (value.level > 0) ? value.level : 1;

    // 始终使用基础数据来生成简介内容（以正确显示属性增益）
    var itemData:Object = ItemUtil.getItemData(name);
    if(typeof baseItem !== "object") baseItem = null;

    // 1) 基础段描述（不含简介头与装备属性）
    var 描述文本:String = TooltipComposer.generateItemDescriptionText(itemData, baseItem);

    // 2) 简介面板文本（简介头 + 装备段）
    var 简介文本:String = TooltipComposer.generateIntroPanelContent(baseItem, itemData);

    // _root.服务器.发布服务器消息("描述文本:" + StringUtils.htmlToPlainTextFast(描述文本));
    // _root.服务器.发布服务器消息("简介文本:" + StringUtils.htmlToPlainTextFast(简介文本));

    // 3) 获取用于图标显示的数据（如果 baseItem 存在且是装备物品，使用 getData() 以应用涂装覆盖）
    var iconData:Object = null;
    if(baseItem && baseItem.getData != undefined && ItemUtil.isEquipment(name)){
        iconData = baseItem.getData();
    }

    // 4) 使用智能显示算法自动优化长短内容，传递 iconData 以支持涂装图标覆盖
    TooltipComposer.renderItemTooltipSmart(name, value, 描述文本, 简介文本, null, iconData);
};


/**
 * 技能栏技能图标注释（智能分栏版）
 * @param 对应数组号:Number 技能在主角技能表中的数组索引
 *
 * 布局策略：
 * - 简介面板：技能名、类型、状态、冷却、消耗、等级等基础信息
 * - 描述文本：技能的详细描述（Description），独立显示
 * - 根据内容长度自动选择单栏或双栏布局
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

    // 简介面板文本（基础信息）
    var 简介文本 = "<B>" + 技能信息.Name + "</B>";
    简介文本 += "<BR>" + 技能信息.Type + "   " + 是否装备或启用;
    简介文本 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
    简介文本 += "<BR>MP消耗：" + 技能信息.MP;
    简介文本 += "<BR>技能等级：" + 主角技能信息[1];

    // 描述文本（独立出来，用于智能分栏）
    var 描述文本 = 技能信息.Description ? String(技能信息.Description) : "";

    // 使用技能专用智能分栏渲染
    _root.renderSkillTooltipSmart(技能名, 简介文本, 描述文本);
};

/**
 * 学习界面技能图标注释（智能分栏版）
 * @param 对应数组号:Number 技能在技能表中的数组索引
 *
 * 布局策略：
 * - 简介面板：技能名、类型、等级限制、技能点需求、冷却、消耗等基础信息
 * - 描述文本：技能的详细描述（Description），独立显示
 * - 根据内容长度自动选择单栏或双栏布局
 */
_root.学习界面技能图标注释 = function(对应数组号) {
    var 技能信息 = _root.技能表[对应数组号];
    var 技能名 = 技能信息.Name;

    // 简介面板文本（基础信息）
    var 简介文本 = "<B>" + 技能名 + "</B>";
    简介文本 += "<BR>" + 技能信息.Type;
    简介文本 += "<BR>最高等级：" + 技能信息.MaxLevel;
    简介文本 += "<BR>解锁需要技能点数：" + 技能信息.UnlockSP;
    if (技能信息.MaxLevel > 1)
        简介文本 += "<BR>升级需要技能点数：" + 技能信息.UpgradeSP;
    简介文本 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
    简介文本 += "<BR>MP消耗：" + 技能信息.MP;
    简介文本 += "<BR>等级限制：" + 技能信息.UnlockLevel;

    // 描述文本（独立出来，用于智能分栏）
    var 描述文本 = 技能信息.Description ? String(技能信息.Description) : "";

    // 使用技能专用智能分栏渲染
    _root.renderSkillTooltipSmart(技能名, 简介文本, 描述文本);
};


/**
 * 技能注释智能分栏渲染
 * @param 技能名:String 技能名称（用于图标显示）
 * @param 简介文本:String 简介面板内容（基础信息）
 * @param 描述文本:String 描述内容（独立显示）
 *
 * 分栏策略（使用 TooltipLayout.shouldSplitSmart 统一判定）：
 * - 短内容：合并显示（描述文本并入简介面板底部）
 * - 长内容：分离显示（主框体显示描述，图标面板显示简介）
 */
_root.renderSkillTooltipSmart = function(技能名:String, 简介文本:String, 描述文本:String):Void {
    // 保底清理
    TooltipLayout.hideTooltip();

    // 使用统一的智能分栏判定（技能目前不需要自定义 options，传 null 即可）
    var needSplit:Boolean = TooltipLayout.shouldSplitSmart(描述文本, 简介文本, null);

    if (needSplit) {
        // 长内容策略：分离显示（主框体 + 图标面板）
        var calculatedWidth:Number = TooltipLayout.estimateWidth(描述文本);
        TooltipLayout.showTooltip(calculatedWidth, 描述文本);
        TooltipLayout.renderIconTooltip(true, 技能名, 简介文本, TooltipConstants.BASE_NUM, ItemUseTypes.TYPE_SKILL);
    } else {
        // 短内容策略：合并显示（描述并入简介面板底部）
        var 合并文本:String = 简介文本;
        if (描述文本 && 描述文本.length > 0) {
            合并文本 += "<BR>" + 描述文本;
        }
        var 计算宽度:Number = TooltipLayout.estimateWidth(合并文本);
        TooltipLayout.renderIconTooltip(true, 技能名, 合并文本, 计算宽度, ItemUseTypes.TYPE_SKILL);

        // 隐藏主框体（仅显示图标面板）
        TooltipBridge.setTextContent("main", "");
        TooltipBridge.setVisibility("main", false);
        TooltipBridge.setVisibility("mainBg", false);
    }
}

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


