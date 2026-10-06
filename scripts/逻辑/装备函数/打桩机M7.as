// 原打桩机的重锤进阶；玩法、数值参数与完整姿态分层。
_root.装备生命周期函数.打桩机M7初始化 = function(ref:Object, param:Object):Void {
    if (ref.pileBunkerController) ref.pileBunkerController.dispose();
    ref.pileBunkerController = new org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PileBunkerM7Controller(ref, param);
};

_root.装备生命周期函数.打桩机M7周期 = function(ref:Object, param:Object):Void {
    if (!EquipmentTick.open(ref)) return;
    ref.pileBunkerController.tick();
};

_root.装备生命周期函数.打桩机M7视觉更新 = function(ref:Object):Void {
    ref.pileBunkerController.syncVisual();
};

if (!_root.主动战技函数) _root.主动战技函数 = {};
if (!_root.主动战技函数.长枪) _root.主动战技函数.长枪 = {};
_root.主动战技函数.长枪.打桩过载 = {
    初始化:null,
    原子释放:true,
    释放许可判定:function(unit:MovieClip):Boolean {
        return unit.__pileBunkerM7 && unit.__pileBunkerM7.canSkill();
    },
    释放:function(unit:MovieClip):Boolean {
        return unit.__pileBunkerM7 && unit.__pileBunkerM7.releaseSkill();
    }
};

if (!_root.主动战技函数.兵器) _root.主动战技函数.兵器 = {};
_root.主动战技函数.兵器.燃气破坏 = {
    初始化:null,
    释放许可判定:function(unit:MovieClip):Boolean {
        return unit.__pileBunkerM7 && unit.__pileBunkerM7.canHammerSkill();
    },
    释放:function(unit:MovieClip):Void {
        _root.战技路由.战技标签跳转_旧(unit, "破坏殆尽");
    }
};
