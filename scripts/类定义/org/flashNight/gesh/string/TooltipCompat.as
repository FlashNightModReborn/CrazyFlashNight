import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.tooltip.TooltipLayout;

/**
 * TooltipCompat.as
 *
 * 一个兼容旧有基于 _root 结构的静态工具类，用于管理和显示游戏中的各种提示框（Tooltip）。
 * 它将原本分散在 _root 上的全局函数封装起来，提供了更清晰的接口和更好的代码组织。
 *
 * 使用方法:
 * 1. 在你的主fla文件的第一帧，调用初始化方法，并传入主时间轴的引用 (_root 或 this):
 *    import org.flashNight.gesh.string.TooltipCompat;
 *    TooltipCompat.init(this);
 *
 * 2. 在需要显示提示框的地方，调用相应的静态方法:
 *    // 显示物品提示
 *    button.onRollOver = function() {
 *        var itemValue = { level: 5, tier: 2 };
 *        TooltipCompat.showItemTooltip("神圣之剑", itemValue);
 *    };
 *    button.onRollOut = function() {
 *        TooltipCompat.hide();
 *    };
 *
 */
class org.flashNight.gesh.string.TooltipCompat {

    // =================================================================================================
    // Private Static Properties
    // =================================================================================================

    private static var _rootRef:MovieClip;          // 对主时间轴的引用 (_root)
    private static var _tooltipMC:MovieClip;        // 对 _root.注释框 MovieClip 的引用
    private static var _playerSkillList:Array;      // 对 _root.主角技能表 的引用
    private static var _skillDataObject:Object;     // 对 _root.技能表对象 的引用
    private static var _skillDataList:Array;        // 对 _root.技能表 的引用

    // 私有构造函数，防止外部实例化，确保该类仅作为静态工具类使用。
    private function TooltipCompat() {}

    // =================================================================================================
    // Public Static Methods (Initialization & Control)
    // =================================================================================================

    /**
     * 初始化工具类，必须在应用启动时调用一次。
     * @param rootRef 对主时间轴的引用，通常是 _root 或 this。
     */
    public static function init(rootRef:MovieClip):Void {
        _rootRef = rootRef;
        _tooltipMC = rootRef.注释框;
        _playerSkillList = rootRef.主角技能表;
        _skillDataObject = rootRef.技能表对象;
        _skillDataList = rootRef.技能表;
    }

    /**
     * 注释结束函数，清理所有注释相关的显示元素。
     */
    public static function hide():Void {
        if (!_tooltipMC) return; // 未初始化则直接返回

        _tooltipMC._visible = false;
        showItemIconPanel(false); // 调用内部方法清理图标

        // 清理文本框内容
        _tooltipMC.文本框.htmlText = "";
        _tooltipMC.文本框._visible = false;
        _tooltipMC.简介文本框.htmlText = "";
        _tooltipMC.简介文本框._visible = false;

        // 清理背景可见性
        _tooltipMC.背景._visible = false;
        _tooltipMC.简介背景._visible = false;

        // 清理物品图标定位
        _tooltipMC.物品图标定位._visible = false;
        if (_tooltipMC.物品图标定位.icon) {
            _tooltipMC.物品图标定位.icon.removeMovieClip();
        }
    }


    // =================================================================================================
    // Public Static Methods (Tooltip Display)
    // =================================================================================================

    /**
     * 物品图标注释主入口函数
     * @param name:String 物品名称
     * @param value:Object 物品数值对象，包含level、tier等属性
     */
    public static function showItemTooltip(name:String, value:Object):Void {
        var 强化等级:Number = value.level > 0 ? value.level : 1;

        var 物品数据:Object = ItemUtil.getItemData(name);
        // Phase 3: Use text composer for unified generation
        var 完整文本:String = TooltipComposer.generateItemDescriptionText(物品数据);
        var 计算宽度:Number = TooltipLayout.estimateWidth(完整文本);

        hide(); // 保底清理

        // 调用注释函数，传递计算出的宽度和文本内容
        if (完整文本.length > 64) {
            show(计算宽度, 完整文本);
            showItemIconPanel(true, name, value);
        } else {
            showItemIconPanel(true, name, value, 完整文本);
            _tooltipMC.文本框.htmlText = "";
            _tooltipMC.文本框._visible = false;
            _tooltipMC.背景._visible = false;
        }
    }

    /**
     * 技能栏技能图标注释
     * @param skillIndex:Number 技能在主角技能表中的数组索引
     */
    public static function showSkillbarTooltip(skillIndex:Number):Void {
        var 主角技能信息:Array = _playerSkillList[skillIndex];
        var 技能名:String = 主角技能信息[0];
        var 技能信息:Object = _skillDataObject[技能名];

        var 是否装备或启用:String;
        if (技能信息.Equippable) {
            是否装备或启用 = 主角技能信息[2] == true ? "<FONT COLOR='#66FF00'>已装备</FONT>" : "<FONT COLOR='#FFDDDD'>未装备</FONT>";
        } else {
            是否装备或启用 = 主角技能信息[4] == true ? "<FONT COLOR='#66FF00'>已启用</FONT>" : "<FONT COLOR='#FFDDDD'>未启用</FONT>";
        }

        var 文本数据:String = "<B>" + 技能信息.Name + "</B>";
        文本数据 += "<BR>" + 技能信息.Type + "   " + 是否装备或启用;
        文本数据 += "<BR>" + 技能信息.Description;
        文本数据 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
        文本数据 += "<BR>MP消耗：" + 技能信息.MP;
        文本数据 += "<BR>技能等级：" + 主角技能信息[1];

        var 计算宽度:Number = TooltipLayout.estimateWidth(文本数据, 160, 200);
        show(计算宽度, 文本数据);
    }

    /**
     * 学习界面技能图标注释
     * @param skillIndex:Number 技能在技能表中的数组索引
     */
    public static function showLearnSkillTooltip(skillIndex:Number):Void {
        var 技能信息:Object = _skillDataList[skillIndex];

        var 文本数据:String = "<B>" + 技能信息.Name + "</B>";
        文本数据 += "<BR>" + 技能信息.Type;
        文本数据 += "<BR>" + 技能信息.Description;
        文本数据 += "<BR>最高等级：" + 技能信息.MaxLevel;
        文本数据 += "<BR>解锁需要技能点数：" + 技能信息.UnlockSP;
        if (技能信息.MaxLevel > 1) {
            文本数据 += "<BR>升级需要技能点点数：" + 技能信息.UpgradeSP;
        }
        文本数据 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
        文本数据 += "<BR>MP消耗：" + 技能信息.MP;
        文本数据 += "<BR>等级限制：" + 技能信息.UnlockLevel;

        var 计算宽度:Number = TooltipLayout.estimateWidth(文本数据, 160, 200);
        show(计算宽度, 文本数据);
    }


    // =================================================================================================
    // Private Static Helper Methods
    // =================================================================================================

    /**
     * 注释物品图标显示控制函数 (内部使用)
     * @param enable:Boolean 是否启用显示
     * @param name:String 物品名称
     * @param value:Object 物品数值对象
     * @param extraString:String 额外显示的文本（可选）
     */
    private static function showItemIconPanel(enable:Boolean, name?:String, value?:Object, extraString?:String):Void {
        if (!_tooltipMC) return;

        var target:MovieClip = _tooltipMC.物品图标定位;
        var background:MovieClip = _tooltipMC.简介背景;
        var text:MovieClip = _tooltipMC.简介文本框;

        if (enable) {
            target._visible = true;
            text._visible = true;
            background._visible = true;

            var data:Object = ItemUtil.getItemData(name);
            var level:Number = value.level > 0 ? value.level : 1;

            var layout:Object = TooltipLayout.applyIntroLayout(data.type, target, background, text);
            var stringWidth:Number = layout.width;
            var backgroundHeightOffset:Number = layout.heightOffset;

            var introduction:String = TooltipComposer.generateIntroPanelContent(data, value, level);
            if (extraString) {
                introduction += "<BR>" + extraString;
            }

            show(stringWidth, introduction, "简介");

            var iconString:String = "图标-" + data.icon;
            if (target.icon) {
                target.icon.removeMovieClip();
            }

            var icon:MovieClip = target.attachMovie(iconString, "icon", target.getNextHighestDepth());
            icon._xscale = icon._yscale = 150;
            icon._x = icon._y = 19;
            
            if (_tooltipMC.简介背景) {
              var iconDepth:Number = target.getDepth();
              var bgDepth:Number = _tooltipMC.简介背景.getDepth();
              if (iconDepth <= bgDepth) {
                target.swapDepths(bgDepth + 1);
              }
            }

            background._height = text._height + backgroundHeightOffset;
        } else {
            if (target.icon) {
                target.icon.removeMovieClip();
            }
            target._visible = false;
            text._visible = false;
            background._visible = false;
        }
    }


    /**
     * 注释显示函数 (内部使用)
     * @param width:Number 注释框宽度
     * @param content:String 注释内容HTML文本
     * @param frameType:String 框体类型（可选，默认为主框体）
     */
    private static function show(width:Number, content:String, frameType?:String):Void {
        if (!_tooltipMC) return;

        if (!frameType) {
            frameType = "";
            _tooltipMC.文本框._visible = true;
            _tooltipMC.背景._visible = true;
        }

        _tooltipMC.文本框._y = 0;
        _tooltipMC.背景._y = 0;

        var target:MovieClip = _tooltipMC[frameType + "文本框"];
        var background:MovieClip = _tooltipMC[frameType + "背景"];

        _tooltipMC._visible = true;
        target.htmlText = content;
        target._width = width;

        background._width = target._width;
        background._height = target.textHeight + 10;
        target._height = target.textHeight + 10;

        TooltipLayout.positionTooltip(_tooltipMC, background, _rootRef._xmouse, _rootRef._ymouse);
    }
}