_root.装备生命周期函数.黑铁的剑初始化 = function (reflector:Object, paramObj:Object) {
    paramObj.position = paramObj.position || "刀口位置2";
    paramObj.func = paramObj.func || "_root.刀口触发特效.黑铁的剑特效";
    if(!paramObj.states) {
        paramObj.states = {};
        paramObj.states["兵器攻击"] = true;
    }
    _root.装备生命周期函数.通用特效刀口初始化(reflector, paramObj);
};
