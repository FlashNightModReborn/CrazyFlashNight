//牙狼剑可以在攻击过程中随时切换剑形态和斩马刀形态
//特效：斩马刀形态平砍附带烈焰斩马刀的特效（带金色滤镜）
//战技：撼地裂狱，（在things0战技文件夹内同名）
//动作：剑形态使用"刀剑"动作，斩马刀形态使用"狂野"动作。
//斩马刀有战技和属性伤的特效，剑形态纯白板但补一个最高概率的暴击
//变形动画：牙狼剑变斩马刀，（在things0文件内）

_root.装备生命周期函数.牙狼剑初始化 = function(ref:Object, param:Object)
{
    ref.actionTypeA = param.actionTypeA || null;
    ref.actionTypeB = param.actionTypeB || "狂野";

    ref.frame = 1;
    ref.currentState = false; // false: 剑形态, true: 斩马刀形态
    ref.frameMax = param.frameMax || 11;

    ref.skill_0 = param.skill_0; // 斩马刀形态战技：撼地烈狱
    ref.lastCurrentState = false;

    ref.自机.兵器动作类型 = ref.actionTypeA;

    PlacementVisual.hookVisualUpdate(ref.自机, "刀_引用", ref, _root.装备生命周期函数.牙狼剑视觉更新);
};

_root.装备生命周期函数.牙狼剑周期 = function(ref:Object, param:Object)
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

    if(ref.lastCurrentState !== ref.currentState) {
        target.装载主动战技(ref.currentState ? ref.skill_0 : {skillname: null}, "兵器");
        ref.lastCurrentState = ref.currentState;
        if(ref.是否为主角) {
            _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
        }
    }

    _root.装备生命周期函数.牙狼剑视觉更新(ref);
};

_root.装备生命周期函数.牙狼剑视觉更新 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var saber:MovieClip = target.刀_引用;

    target.牙狼剑帧 = ref.frame;
    saber.gotoAndStop(ref.frame);
};
