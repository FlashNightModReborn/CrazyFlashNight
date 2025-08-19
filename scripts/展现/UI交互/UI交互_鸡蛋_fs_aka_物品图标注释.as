import org.flashNight.arki.item.*;
import org.flashNight.gesh.array.*;
import org.flashNight.gesh.string.*;



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

    // 3) 以“信息 + 简介”的总长度作为分支依据
    var 阈值:Number = TooltipConstants.SPLIT_THRESHOLD;
    var 描述长度:Number = 描述文本.length;
    var 总长度:Number = 描述长度 + 简介文本.length;

    _root.注释结束(); // 保底清理

    if (总长度 > 阈值 * 2 && 描述长度 > 阈值 / 2) {
        // 长内容：主框体展示“描述”，简介面板单独展示
        var 计算宽度:Number = TooltipLayout.estimateWidth(描述文本);
        _root.注释(计算宽度, 描述文本);
        _root.注释物品图标(true, name, value, 简介文本, null);
    } else {
        // 短内容：把“描述”并入简介面板，主框体隐藏
        _root.注释物品图标(true, name, value, 简介文本, 描述文本);
        _root.注释框.文本框.htmlText = "";
        _root.注释框.文本框._visible = false;
        _root.注释框.背景._visible = false;
    }
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

    _root.注释结束(); // 保底清理

    // 使用技能图标显示注释
    var 计算宽度 = TooltipLayout.estimateWidth(文本数据, TooltipConstants.MIN_W, TooltipConstants.MAX_W);
    _root.注释技能图标(true, 技能名, 文本数据, 计算宽度);
};

/**
 * 学习界面技能图标注释
 * @param 对应数组号:Number 技能在技能表中的数组索引
 */
_root.学习界面技能图标注释 = function(对应数组号) {
    var 技能信息 = _root.技能表[对应数组号];

    var 文本数据 = "<B>" + 技能信息.Name + "</B>";
    文本数据 += "<BR>" + 技能信息.Type;
    文本数据 += "<BR>" + 技能信息.Description;
    文本数据 += "<BR>最高等级：" + 技能信息.MaxLevel;
    文本数据 += "<BR>解锁需要技能点数：" + 技能信息.UnlockSP;
    if (技能信息.MaxLevel > 1)
        文本数据 += "<BR>升级需要技能点数：" + 技能信息.UpgradeSP;
    文本数据 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
    文本数据 += "<BR>MP消耗：" + 技能信息.MP;
    文本数据 += "<BR>等级限制：" + 技能信息.UnlockLevel;

    var 计算宽度 = TooltipLayout.estimateWidth(文本数据, TooltipConstants.MIN_W, TooltipConstants.MAX_W);
    _root.注释(计算宽度, 文本数据);
};


/**
 * 通用图标注释核心函数
 * @param enable:Boolean 是否启用显示
 * @param iconName:String 图标名称（用于构建 "图标-" + iconName）
 * @param contentText:String 注释内容文本
 * @param contentWidth:Number 内容宽度
 * @param layoutType:String 布局类型（可选，默认为"装备"）
 */
_root.注释图标核心 = function(enable:Boolean, iconName:String, contentText:String, contentWidth:Number, layoutType:String) {
    var target:MovieClip = _root.注释框.物品图标定位;
    var background:MovieClip = _root.注释框.简介背景;
    var text:MovieClip = _root.注释框.简介文本框;

    if (enable) {
        target._visible = true;
        text._visible = true;
        background._visible = true;

        var tips:MovieClip = _root.注释框;

        // 使用指定的布局类型，默认为装备布局
        var layoutTypeToUse:String = layoutType ? layoutType : "装备";
        var layout:Object = TooltipLayout.applyIntroLayout(layoutTypeToUse, target, background, text);
        var stringWidth:Number = Math.max(contentWidth, layout.width);
        var backgroundHeightOffset:Number = layout.heightOffset;

        // 显示注释文本
        _root.注释(stringWidth, contentText, "简介");

        // 图标挂载，使用 "图标-" + 图标名 的命名规则
        if (target.icon) target.icon.removeMovieClip();
        var iconString:String = "图标-" + iconName;
        var icon:MovieClip = target.attachMovie(iconString, "icon", target.getNextHighestDepth());
        icon._xscale = icon._yscale = 150; // TODO: TooltipConstants.ICON_SCALE
        icon._x = icon._y = 19;            // TODO: TooltipConstants.ICON_OFFSET

        // 确保图标层级在简介背景之上
        if (tips.简介背景) {
            var iconDepth:Number = target.getDepth();
            var bgDepth:Number = tips.简介背景.getDepth();
            if (iconDepth <= bgDepth) {
                target.swapDepths(bgDepth + 1);
            }
        }

        background._height = text._height + backgroundHeightOffset;
    } else {
        if (target.icon) target.icon.removeMovieClip();
        target._visible = false;
        text._visible = false;
        background._visible = false;
    }
};

/**
 * 注释技能图标显示控制函数
 * @param enable:Boolean 是否启用显示
 * @param skillName:String 技能名称
 * @param skillText:String 技能描述文本
 * @param textWidth:Number 文本宽度
 */
_root.注释技能图标 = function(enable:Boolean, skillName:String, skillText:String, textWidth:Number) {
    _root.注释图标核心(enable, skillName, skillText, textWidth);
};

/**
 * 注释物品图标显示控制函数
 * @param enable:Boolean 是否启用显示
 * @param name:String 物品名称
 * @param value:Object 物品数值对象
 * @param introString:String 预先拼好的简介面板文本（简介头 + 装备段）
 * @param extraString:String 额外显示的文本（可选；用于把短描述并入简介面板）
 */
_root.注释物品图标 = function(enable:Boolean, name:String, value:Object, introString:String, extraString:String) {
    if (enable) {
        var data:Object = ItemUtil.getItemData(name);
        
        // 交给布局模块决定尺寸与偏移
        var target:MovieClip = _root.注释框.物品图标定位;
        var background:MovieClip = _root.注释框.简介背景;
        var text:MovieClip = _root.注释框.简介文本框;
        var layout:Object = TooltipLayout.applyIntroLayout(data.type, target, background, text);
        var stringWidth:Number = layout.width;

        // 使用传入的简介文本；如有 extraString（短描述），并入简介面板
        var introduction:String = introString ? introString : "";
        if (extraString) {
            introduction += "<BR>" + extraString;
        }

        // 调用通用图标核心函数
        _root.注释图标核心(true, data.icon, introduction, stringWidth, data.type);
    } else {
        _root.注释图标核心(false);
    }
};



/**
 * 注释显示函数
 * @param 宽度:Number 注释框宽度
 * @param 内容:String 注释内容HTML文本
 * @param 框体:String 框体类型（可选，默认为主框体）
 */
_root.注释 = function(宽度, 内容, 框体) {
    if(!框体) {
        框体 = "";
        _root.注释框.文本框._visible = true;
        _root.注释框.背景._visible = true;
    }

    _root.注释框.文本框._y = 0;
    _root.注释框.背景._y = 0;

    var tips:MovieClip = _root.注释框;
    var target:MovieClip = tips[框体 + "文本框"];
    var background:MovieClip = tips[框体 + "背景"]

    tips._visible = true;
    target.htmlText = 内容;
    target._width = 宽度;

    background._width = target._width;
    background._height = target.textHeight + TooltipConstants.TEXT_PAD;
    target._height = target.textHeight + TooltipConstants.TEXT_PAD;

    // 使用新的布局模块处理注释框定位
    TooltipLayout.positionTooltip(tips, background, _root._xmouse, _root._ymouse);
};

/**
 * 注释结束函数，清理所有注释相关的显示元素
 */
_root.注释结束 = function() {
    _root.注释框._visible = false;
    _root.注释图标核心(false);
    
    // 清理文本框内容
    _root.注释框.文本框.htmlText = "";
    _root.注释框.文本框._visible = false;
    _root.注释框.简介文本框.htmlText = "";
    _root.注释框.简介文本框._visible = false;
    
    // 清理背景可见性
    _root.注释框.背景._visible = false;
    _root.注释框.简介背景._visible = false;
};


