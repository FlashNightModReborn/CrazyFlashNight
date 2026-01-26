_root.装备生命周期函数.雷铁斩斧初始化 = function(ref:Object, param:Object) 
{
    ref.actionTypeA = param.actionTypeA || null;
    ref.actionTypeB = param.actionTypeB || "狂野";

    ref.frame = 1;
    ref.currentState = false; // false: actionTypeA, true: actionTypeB
    ref.frameMax = param.frameMax || 15;
}; 

_root.装备生命周期函数.雷铁斩斧周期 = function(ref:Object, param:Object) 
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var saber:MovieClip = target.刀_引用;

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

    saber.gotoAndStop(ref.frame);
};
