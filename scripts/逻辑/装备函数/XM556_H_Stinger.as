import org.flashNight.neur.Event.*;

/* ============ 初始化 ============ */
_root.装备生命周期函数.XM556_H_Stinger初始化 = function (ref:Object, param:Object) {

    ref.gunString = ref.装备类型 + "_引用";   // target[gunString].动画
    /* --- 战斗模式白名单 --- */
    ref.modeObject = { 双枪:true, 手枪:true, 手枪2:true };
};

/* ============ 周期更新 ============ */
_root.装备生命周期函数.XM556_H_Stinger周期 = function (ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target[ref.gunString]
    var laser:MovieClip = gun.激光模组;

    laser._visible = ref.modeObject[target.攻击模式];
};
