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
    var 简介文本:String = TooltipComposer.generateIntroPanelContent(baseItem, itemData, value);

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
    简介文本 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 100) / 10;
    简介文本 += "<BR>MP消耗：" + 技能信息.MP;
    简介文本 += "<BR>技能等级：" + 主角技能信息[1];

    // 描述文本（独立出来，用于智能分栏）
    var 描述文本 = 技能信息.Description ? String(技能信息.Description) : "";

    // 使用技能专用智能分栏渲染（委托给 SkillTooltipComposer）
    SkillTooltipComposer.renderSkillTooltipSmart(技能名, 简介文本, 描述文本);
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
    简介文本 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 100) / 10;
    简介文本 += "<BR>MP消耗：" + 技能信息.MP;
    简介文本 += "<BR>等级限制：" + 技能信息.UnlockLevel;

    // 描述文本（独立出来，用于智能分栏）
    var 描述文本 = 技能信息.Description ? String(技能信息.Description) : "";

    // 使用技能专用智能分栏渲染（委托给 SkillTooltipComposer）
    SkillTooltipComposer.renderSkillTooltipSmart(技能名, 简介文本, 描述文本);
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
 * Web 面板物品注释 HTML 构造（无渲染版本，对应 _root.物品图标注释 的纯数据双胞胎）
 *
 * - 与 物品图标注释 共用同一条 TooltipComposer 调用链，仅区别在不调 renderItemTooltipSmart，
 *   返回 desc/intro 字符串供 Web/JSON 通道下发。
 * - LiteJSON 不转义双引号；XML 内嵌的 <font color="#xxx"> 会破坏 JSON 结构，
 *   因此输出前把 " 替换为 '（AS2 TextField 两者等效）。
 * - 各 panel 的 *_WebView.as 只需做：参数解析 → 调用本函数 → 按自身 task 名包成 response → sendResponse。
 *
 * @param name:String 物品名（缺省时返回 null）
 * @return Object | null  形如 { descHTML, introHTML, displayname, itemData }；item 找不到返回 null
 */
_root.Web物品注释HTML = function(name:String):Object {
    if (name == undefined || name == null || name == "") return null;
    var itemData:Object = ItemUtil.getItemData(name);
    if (itemData == undefined) return null;

    // value 对象：Web 入口当前没有强化等级 / 涂装上下文，统一以 level=1 走基础数据
    var value:Object = { level: 1 };
    var descHTML:String = TooltipComposer.generateItemDescriptionText(itemData, null);
    var introHTML:String = TooltipComposer.generateIntroPanelContent(null, itemData, value);

    return {
        descHTML: descHTML.split('"').join("'"),
        introHTML: introHTML.split('"').join("'"),
        displayname: String(itemData.displayname || name),
        itemData: itemData
    };
};

/**
 * 注释结束函数 (兼容接口，转发到 TooltipLayout.hideTooltip)
 */
_root.注释结束 = function() {
    TooltipLayout.hideTooltip();
};


