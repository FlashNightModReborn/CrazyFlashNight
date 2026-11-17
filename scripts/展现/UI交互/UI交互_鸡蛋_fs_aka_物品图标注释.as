/** Tooltip entry points: freeze input and let the Launcher generate the document. */
_root.物品图标注释 = function(name, value, baseItem, ownerClip) {
    var input:Object = TooltipInputProjection.forItem(name, value, baseItem, "native");
    if (input != null) NativeTooltipBridge.show(input, ownerClip);
};

_root.技能栏技能图标注释 = function(对应数组号) {
    NativeTooltipBridge.show(TooltipInputProjection.loadoutSkill(对应数组号));
};

_root.学习界面技能图标注释 = function(对应数组号) {
    NativeTooltipBridge.show(TooltipInputProjection.learningSkill(对应数组号));
};

/** Kept call signature for existing scene producers; no Flash renderer or layout. */
_root.注释 = function(宽度, 内容, 框体) {
    NativeTooltipBridge.show(TooltipInputProjection.body(
        (内容 == undefined || 内容 == null) ? "" : String(内容), "simple"));
};

/**
 * Legacy function name only. Synchronous return is TooltipInput plus identity;
 * no HTML is generated in AVM1. All live callers forward tooltipInput to Host.
 */
_root.Web物品注释HTML = function(name:String):Object {
    return TooltipInputProjection.preview(name);
};

_root.注释结束 = function() {
    NativeTooltipBridge.hideCurrent();
    _root.注释框._visible = false;
};
