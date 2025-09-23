_root.装备生命周期函数.光刀狮子初始化 = function(ref:Object, param:Object) 
{
    ref.basicStyle = param.basicStyle || "落日鎏金";
}; 

_root.装备生命周期函数.光刀狮子周期 = function(ref:Object, param:Object) 
{
    _root.装备生命周期函数.通用刀光周期(ref, param);
};
