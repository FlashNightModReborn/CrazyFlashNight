_root.装备生命周期函数.光刃摩羯初始化 = function(ref:Object, param:Object) 
{
    ref.basicStyle = param.basicStyle || "翠绿疾影";
    ref.draw = -9999;

    var target:MovieClip = ref.自机;
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        if (mode != "兵器") return;
        
        ref.draw = 150;
    }, target);
}; 

_root.装备生命周期函数.光刃摩羯周期 = function(ref:Object, param:Object) 
{
    if(ref.draw > 0) {
        ref.draw--;
        _root.装备生命周期函数.通用刀光周期(ref, param);
    }
};
