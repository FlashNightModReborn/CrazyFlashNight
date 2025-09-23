_root.装备生命周期函数.光斧金牛初始化 = function(ref:Object, param:Object) 
{
    ref.basicStyle = param.basicStyle || "幽红幻刃";
}; 

_root.装备生命周期函数.光斧金牛周期 = function(ref:Object, param:Object) 
{
    if(_root.打怪掉钱机率 < 6) {
        _root.装备生命周期函数.通用刀光周期(ref, param);
    }
};
