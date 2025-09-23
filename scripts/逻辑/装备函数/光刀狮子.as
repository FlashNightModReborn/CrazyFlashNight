_root.装备生命周期函数.光刀狮子初始化 = function(ref:Object, param:Object) 
{
    ref.basicStyle = param.basicStyle || "落日鎏金";
    ref.draw = false;

    var target:MovieClip = ref.自机;
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        if (mode != "兵器") return;
        
        ref.draw = true;
    }, target);
}; 

_root.装备生命周期函数.光刀狮子周期 = function(ref:Object, param:Object) 
{
    if(ref.draw) _root.装备生命周期函数.通用刀光周期(ref, param);
};
