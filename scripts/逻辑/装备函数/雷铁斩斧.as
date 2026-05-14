_root.装备生命周期函数.雷铁斩斧初始化 = function(ref:Object, param:Object)
{
    ref.actionTypeA = param.actionTypeA || null;
    ref.actionTypeB = param.actionTypeB || "狂野";

    ref.frame = 1;
    ref.currentState = false; // false: actionTypeA, true: actionTypeB
    ref.frameMax = param.frameMax || 15;

    ref.自机.兵器动作类型 = ref.actionTypeA;

    PlacementVisual.hookVisualUpdate(ref.自机, "刀_引用", ref, _root.装备生命周期函数.雷铁斩斧视觉更新);
};

_root.装备生命周期函数.雷铁斩斧周期 = function(ref:Object, param:Object)
{
    if (!EquipmentTick.open(ref)) return;

    var target:MovieClip = ref.自机;

    if(_root.兵器使用检测(target)) {
        if(ref.frame === 1 || ref.frame === ref.frameMax) {
            if(_root.按键输入检测(target, _root.武器变形键)) {
                ref.currentState = !ref.currentState;
                target.兵器动作类型 = ref.currentState ? ref.actionTypeB : ref.actionTypeA;
            }
        }
    }

    if(ref.currentState) {
        if(ref.frame < ref.frameMax) {
            ref.frame++;
        }
    } else {
        if(ref.frame > 1) {
            ref.frame--;
        }
    }

    _root.装备生命周期函数.雷铁斩斧视觉更新(ref);
};

_root.装备生命周期函数.雷铁斩斧视觉更新 = function(ref:Object)
{
    var saber:MovieClip = ref.自机.刀_引用;
    saber.gotoAndStop(ref.frame);
};
