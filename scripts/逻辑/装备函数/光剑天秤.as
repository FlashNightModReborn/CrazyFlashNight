_root.装备生命周期函数.光剑天秤初始化 = function(ref:Object, param:Object) 
{
    var target:MovieClip = ref.自机;
    var key:String = "武器类型名" + target.刀;
    ref.key = key;
}; 

_root.装备生命周期函数.光剑天秤周期 = function(ref:Object, param:Object) 
{
    _root.装备生命周期函数.移除异常周期函数(ref);
    
    var target:MovieClip = ref.自机;
    switch(target[ref.key]) {
        case "攻势形态":
            ref.basicStyle = "烈焰残焰";
            _root.装备生命周期函数.通用刀光周期(ref, param);
            break;

        case "守御形态":
            ref.basicStyle = "金色余辉";
            _root.装备生命周期函数.通用刀光周期(ref, param);
            break;  

        default: 
            if(target.主动战技cd中) {
                ref.basicStyle = "薄暮幽蓝";
                _root.装备生命周期函数.通用刀光周期(ref, param);
            }
    }
    
};
