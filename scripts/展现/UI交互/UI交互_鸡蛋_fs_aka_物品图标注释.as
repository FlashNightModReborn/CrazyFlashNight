/**
 * 物品图标注释主入口函数
 * @param name:String 物品名称
 * @param value:Object 物品数值对象，包含level、tier等属性
 * @param ownerClip:MovieClip 可选，真实 owner/图标剪辑；有效时原生注释携带 _root 系 anchorRect
 */
_root.物品图标注释 = function(name, value, baseItem, ownerClip) {
    var 强化等级:Number = (value.level > 0) ? value.level : 1;

    // 始终使用基础数据来生成简介内容（以正确显示属性增益）
    var itemData:Object = ItemUtil.getItemData(name);
    if(typeof baseItem !== "object") baseItem = null;

    // 1) 基础段描述（不含简介头与装备属性）；subBlocks 拆出「战技/副武器」「已安装插件」
    //    「额外功能」三块，各自成为一个 role:"sub" 子注释框；旧消费端按 body 内联不丢内容。
    //    docSubs 与 subBlocks 一一对应：插件块带结构化 rows（含图标），其余为同文 HTML。
    var subBlocks:Array = [];
    var docSubs:Array = [];
    var 描述文本:String = TooltipComposer.generateItemDescriptionTextEx(itemData, baseItem, subBlocks, docSubs);

    // 2) 原生专属部件：书签式插条（武器大类/子类）与枪械弹夹独立框（第二行为子弹类型）
    var 插条:Array = TooltipComposer.getRailText(itemData, baseItem);
    var 弹夹:Object = TooltipComposer.getMagazineInfo(baseItem, itemData, value);

    // 3) 简介面板文本。插条承载了类型行时才从面板省略该行（非武器保持原样不丢信息）；
    //    弹夹行/子弹类型行改由独立框显示；暴击/斩杀拆到第一个子框。
    var 暴击斩杀:Array = [];
    var 简介文本:String = TooltipComposer.generateIntroPanelContent(baseItem, itemData, value, {
        omitTypeLines: 插条 != null,
        omitActionType: 插条 != null,
        omitClipName: 弹夹 != null,
        omitBulletType: 弹夹 != null && 弹夹.ammo != null,
        omitCritSlay: true,
        critSlay: 暴击斩杀
    });
    if (暴击斩杀.length > 0) {
        var 暴击斩杀HTML:String = 暴击斩杀.join("");
        subBlocks.unshift(暴击斩杀HTML);
        docSubs.unshift(暴击斩杀HTML);
    }

    var extras:Object = null;
    if (插条 != null || 弹夹 != null) {
        extras = {};
        if (插条 != null) extras.rail = 插条;
        if (弹夹 != null) extras.magazine = 弹夹;
    }

    // _root.服务器.发布服务器消息("描述文本:" + StringUtils.htmlToPlainTextFast(描述文本));
    // _root.服务器.发布服务器消息("简介文本:" + StringUtils.htmlToPlainTextFast(简介文本));

    // 4) 图标显示数据（装备实例走 getData() 以应用涂装覆盖）
    var iconData:Object = null;
    if(baseItem && baseItem.getData != undefined && ItemUtil.isEquipment(name)){
        iconData = baseItem.getData();
    }

    // 5) 原生注释出口：document 经 native_interaction 下发；通道不可用时回退旧 Flash 渲染
    var doc:Object = NativeTooltipDocument.buildItem(name, itemData, iconData, 简介文本, 描述文本, docSubs, extras);
    if (NativeTooltipBridge.show(doc, ownerClip) == null) {
        // 回退路径无插条/弹夹框，简介需按旧版全文重建一次
        var 回退简介:String = TooltipComposer.generateIntroPanelContent(baseItem, itemData, value, null);
        var 回退全文:String = 描述文本 + subBlocks.join("");
        TooltipComposer.renderItemTooltipSmart(name, value, 回退全文, 回退简介, null, iconData);
    }
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
    var parts:Object = SkillTooltipComposer.describeLoadout(对应数组号);
    if (NativeTooltipBridge.show(parts.document) == null) {
        SkillTooltipComposer.renderSkillTooltipSmart(parts.name, parts.intro, parts.description);
    }
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

    // 原生注释出口：document 经 native_interaction 下发；通道不可用时回退旧 Flash 渲染
    var 学习文档:Object = NativeTooltipDocument.buildSkill(技能名, 简介文本, 描述文本);
    if (NativeTooltipBridge.show(学习文档) == null) {
        SkillTooltipComposer.renderSkillTooltipSmart(技能名, 简介文本, 描述文本);
    }
};


/**
 * 注释显示函数 (兼容接口，优先经 native_interaction 下发；通道不可用时转发到 TooltipLayout.showTooltip)
 * @param 宽度:Number 注释框宽度（旧布局参考值，原生路径不以此为布局依据）
 * @param 内容:String 注释内容HTML文本
 * @param 框体:String 框体类型（可选，默认为主框体）
 */
_root.注释 = function(宽度, 内容, 框体) {
    var doc:Object = NativeTooltipDocument.buildBody(
        (内容 == undefined || 内容 == null) ? "" : String(内容),
        NativeTooltipDocument.PROFILE_SIMPLE);
    if (NativeTooltipBridge.show(doc) == null) {
        TooltipLayout.showTooltip(宽度, 内容, 框体);
    }
};

/**
 * Web 面板物品注释 HTML 构造（无渲染版本，对应 _root.物品图标注释 的纯数据双胞胎）
 *
 * - 与 物品图标注释 共用同一条 TooltipComposer 调用链，仅区别在不调 renderItemTooltipSmart，
 *   返回 desc/intro 字符串供 Web/JSON 通道下发。
 * - wire 出口统一由消费方 sendResponse 的 LiteJSON.stringifySafe 做标准转义；
 *   这里保留 TooltipComposer 原始 htmlText（含双引号属性），不再做引号替换。
 * - 各 panel 的 *_WebView.as 只需做：参数解析 → 调用本函数 → 按自身 task 名包成 response → sendResponse。
 *
 * @param name:String 物品名（缺省时返回 null）
 * @return Object | null  形如 { descHTML, introHTML, displayname, itemData, document }；item 找不到返回 null
 */
_root.Web物品注释HTML = function(name:String):Object {
    if (name == undefined || name == null || name == "") return null;
    var itemData:Object = ItemUtil.getItemData(name);
    if (itemData == undefined) return null;

    // value 对象：Web 入口当前没有强化等级 / 涂装上下文，统一以 level=1 走基础数据
    var value:Object = { level: 1 };
    var subBlocks:Array = [];
    var docSubs:Array = [];
    var descBody:String = TooltipComposer.generateItemDescriptionTextEx(itemData, null, subBlocks, docSubs);
    var introHTML:String = TooltipComposer.generateIntroPanelContent(null, itemData, value, null);

    // 装备才可能拆出插条/弹夹/暴击斩杀，此时为语义文档再走一次省略版简介；
    // 非装备两次结果同文，直接复用避免重复构建。
    var 插条:Array = TooltipComposer.getRailText(itemData, null);
    var 弹夹:Object = TooltipComposer.getMagazineInfo(null, itemData, value);
    var extras:Object = null;
    var docIntro:String = introHTML;
    if (ItemUtil.isEquipment(name)) {
        var 暴击斩杀:Array = [];
        docIntro = TooltipComposer.generateIntroPanelContent(null, itemData, value, {
            omitTypeLines: 插条 != null,
            omitActionType: 插条 != null,
            omitClipName: 弹夹 != null,
            omitBulletType: 弹夹 != null && 弹夹.ammo != null,
            omitCritSlay: true,
            critSlay: 暴击斩杀
        });
        if (暴击斩杀.length > 0) {
            var 暴击斩杀HTML:String = 暴击斩杀.join("");
            subBlocks.unshift(暴击斩杀HTML);
            docSubs.unshift(暴击斩杀HTML);
        }
        if (插条 != null || 弹夹 != null) {
            extras = {};
            if (插条 != null) extras.rail = 插条;
            if (弹夹 != null) extras.magazine = 弹夹;
        }
    }

    return {
        // descHTML/introHTML 保持旧版全文（含子框内容与类型行）：
        // 只读 HTML 的面板（锻造/战利品/角色构筑等）不认 document，省略即丢信息。
        descHTML: descBody + subBlocks.join(""),
        introHTML: introHTML,
        displayname: String(itemData.displayname || name),
        itemData: itemData,
        // COMMON v1 语义文档（纯数据字段，消费方需先经白名单协调再接入 wire）
        // subBlocks → role:"sub" 子注释框段；extras → rail/magazine 结构部件
        document: NativeTooltipDocument.buildItem(name, itemData, null, docIntro, descBody, docSubs, extras)
    };
};

/**
 * 注释结束函数 (兼容接口，先按身份下发 native hide，再清旧 Flash 注释兜底)
 */
_root.注释结束 = function() {
    NativeTooltipBridge.hideCurrent();
    TooltipLayout.hideTooltip();
};


