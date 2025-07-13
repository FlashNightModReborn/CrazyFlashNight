import org.flashNight.neur.Event.*;

/* ---------------------------------------------------------
 * XM556_H "Stinger"  初始化
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM556_H_Stinger初始化 = function (ref:Object, param:Object)
{
    /* --- ① 先完整复用 XM556 基础初始化 --- */
    _root.装备生命周期函数.XM556初始化(ref, param);

    /* --- ② Stinger 专属初始化 --- */
    // 战斗模式白名单：在以下模式才显示激光模组
    ref.modeObject = { 双枪:true, 手枪:true, 手枪2:true };

    var equipmentType:String = ref.装备类型;
    ref.gunString = equipmentType + "_引用";
    var target:MovieClip = ref.自机;
    var upgradeLevel:Number;

    if(ref.是否为主角) {
        var equipment = _root.物品栏.装备栏;
        upgradeLevel = equipment.getLevel(equipmentType);
    } else {
        upgradeLevel = _root.主角函数.获取人形怪强化等级(target.等级, target.名字);
    }

    var criticalhitUpgrade:Number = param.criticalhitUpgrade || 3; // 默认值为 3
    ref.自机[equipmentType + "暴击"] = upgradeLevel * criticalhitUpgrade;
    // _root.发布消息(upgradeLevel, ref.自机[equipmentType + "暴击"])
};

/* ---------------------------------------------------------
 * XM556_H "Stinger"  周期更新
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM556_H_Stinger周期 = function (ref:Object, param:Object)
{
    /* --- ① 先执行 XM556 周期逻辑（旋转 / 连射 / 退转等） --- */
    _root.装备生命周期函数.XM556周期(ref, param);

    /* --- ② Stinger 专属逻辑：激光模组显隐 --- */
    var target:MovieClip = ref.自机;
    var gun:MovieClip    = target[ref.gunString];

    // 激光模组存在时，根据当前攻击模式决定可见性
    if (gun && gun.激光模组)
    {
        gun.激光模组._visible = ref.modeObject[target.攻击模式];
    }
};
