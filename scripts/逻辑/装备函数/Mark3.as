// ============================================================
// 初始化
// ============================================================

_root.装备生命周期函数.Mark3手甲初始化 =  function(反射对象, 参数对象)
{
    var 自机 = 反射对象.自机;
    反射对象.射击间隔 = 参数对象.interval ? 参数对象.interval : 1000;
    if(!自机.Mark3消耗能量电池){
        自机.Mark3消耗能量电池 = false;
    }
    if (反射对象.是否为主角 && _root.Mark3消耗能量电池)
    {
        自机.Mark3消耗能量电池 = _root.Mark3消耗能量电池;
    }

};

// ============================================================
// 周期
// ============================================================
_root.装备生命周期函数.Mark3手甲周期 = function(反射对象, 参数对象)
{
	EquipmentTick.cleanup(反射对象);
    var 自机 = 反射对象.自机;
    if(自机.攻击模式 == "空手"){
        var input:Object = _root.GameInput;
        var released:Boolean = false;
        var vk:Number = _root.武器变形键;
        if (input.passiveActive === true) {
            var press:Number = KeyEdgeTrigger.getEquipmentPress(反射对象, 自机, vk);
            var armed:Number = 反射对象.transformPress;
            if (press > 0 && 自机.按键检测(vk, 0)) {
                反射对象.transformPress = press;
                反射对象.transformKey = vk;
            } else if (armed > 0) {
                反射对象.transformPress = 0;
                released = !_root.暂停 && _root.gameworld.__combatAdmitted !== false
                    && 自机.__cf6TraversalOwner === undefined && 自机.__cf6ElevatorPoseOwner === undefined
                    && 自机.__cf6VehicleOwner === undefined && 反射对象.transformKey === vk
                    && 反射对象.inputItem === 自机.手部装备 && 反射对象.版本号 === 自机.version
                    && input.wasActorPressReleased(自机, vk, armed);
            }
        } else {
            var down:Boolean = 自机.按键检测(vk, 0);
            released = !down && 自机.武器变形键按键中;
            自机.武器变形键按键中 = down;
        }
        if (released) {
            自机.Mark3消耗能量电池 = !自机.Mark3消耗能量电池;
            if (反射对象.是否为主角)
            {
                _root.Mark3消耗能量电池 = 自机.Mark3消耗能量电池;
                if(自机.Mark3消耗能量电池){
                    _root.发布消息("开启能量电池消耗！");
                }else{
                    _root.发布消息("关闭能量电池消耗！");
                }
            }
        }
    } else {
        反射对象.transformPress = 0;
    }
};