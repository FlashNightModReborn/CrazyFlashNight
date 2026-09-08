// 发射器是常驻美术；光束仅由装备生命周期动态挂载，不进入静态图标或纸娃娃烘焙。
_root.装备生命周期函数.枪械激光绑定有效 = function(ref:Object):Boolean {
    var actor:MovieClip = ref.自机;
    return ref.laserActive && actor.version === ref.laserVersion
        && actor[ref.装备类型] === ref.laserEquipment;
};

_root.装备生命周期函数.枪械激光初始化 = function(ref:Object, param:Object):Boolean {
    if (ref.laserPlacementHandler || ref.laserBeam) {
        _root.装备生命周期函数.枪械激光卸载(ref);
    }
    var actor:MovieClip = ref.自机;
    ref.laserEquipment = actor[ref.装备类型];
    ref.laserVersion = actor.version;
    ref.laserContainer = ref.装备类型 + "_引用";
    ref.laserLinkage = param.beamLinkage != undefined ? String(param.beamLinkage) : "";
    ref.laserLength = param.length != undefined ? Number(param.length) : 750;
    ref.laserActive = false;
    ref.laserFireControl = ref.装备类型 == "长枪" && String(param.fireControl) == "titanium61";
    if (!ref.laserEquipment || !ref.laserLinkage || !isFinite(ref.laserLength) || ref.laserLength <= 0) {
        return false;
    }
    ref.laserModes = ref.装备类型 == "长枪"
        ? {长枪:true} : {双枪:true, 手枪:true, 手枪2:true};
    ref.laserActive = true;
    ref.laserPlacementHandler = PlacementVisual.hookVisualUpdate(
        actor, ref.laserContainer, ref, _root.装备生命周期函数.枪械激光视觉更新, ref);
    if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
    if (!ref.laserCleanup) {
        ref.laserCleanup = {动作:_root.装备生命周期函数.枪械激光卸载, 额外参数:ref};
    }
    var registered:Boolean = false;
    for (var i:Number = 0; i < ref.生命周期函数列表.length; i++) {
        if (ref.生命周期函数列表[i] === ref.laserCleanup) registered = true;
    }
    if (!registered) ref.生命周期函数列表.push(ref.laserCleanup);
    _root.装备生命周期函数.枪械激光视觉更新(ref);
    return true;
};

_root.装备生命周期函数.枪械激光周期 = function(ref:Object):Void {
    if (!EquipmentTick.open(ref)) return;
    _root.装备生命周期函数.枪械激光视觉更新(ref);
};

_root.装备生命周期函数.枪械激光移除光束 = function(ref:Object):Void {
    var beam:MovieClip = ref.laserBeam;
    if (beam._parent && beam._cf7LaserOwner === ref) beam.removeMovieClip();
    ref.laserBeam = null;
    ref.laserGun = null;
};

_root.装备生命周期函数.枪械激光视觉更新 = function(ref:Object):Void {
    if (!_root.装备生命周期函数.枪械激光绑定有效(ref)) {
        _root.装备生命周期函数.枪械激光卸载(ref);
        return;
    }
    var actor:MovieClip = ref.自机;
    var gun:MovieClip = actor[ref.laserContainer];
    if (ref.laserGun !== gun) {
        _root.装备生命周期函数.枪械激光移除光束(ref);
        ref.laserGun = gun;
    }
    var emitter:MovieClip = gun.激光发射器;
    var outlet:MovieClip = emitter.出光位置;
    if (!ref.laserModes[actor.攻击模式] || !gun._parent || !outlet._parent) {
        if (ref.laserBeam._cf7LaserOwner === ref) ref.laserBeam._visible = false;
        return;
    }

    // 两个点走完整变换；外层镜像、旋转和双持容器都由实际实例关系决定。
    var origin:Object = {x:0, y:0};
    var forward:Object = {x:100, y:0};
    outlet.localToGlobal(origin);
    outlet.localToGlobal(forward);
    gun.globalToLocal(origin);
    gun.globalToLocal(forward);
    var dx:Number = forward.x - origin.x;
    var dy:Number = forward.y - origin.y;
    if (!isFinite(origin.x) || !isFinite(origin.y) || !isFinite(dx) || !isFinite(dy)
        || dx * dx + dy * dy <= 0) {
        if (ref.laserBeam._cf7LaserOwner === ref) ref.laserBeam._visible = false;
        return;
    }

    var beam:MovieClip = gun.激光模组;
    // 不占用或删除其他装备已经放置的同名元件。
    if (beam && beam._cf7LaserOwner !== ref) return;
    if (!beam) {
        beam = gun.attachMovie(ref.laserLinkage, "激光模组", gun.getNextHighestDepth(),
            {_visible:false, _cf7LaserOwner:ref});
        if (!beam) return;
        ref.laserBeam = beam;
        beam.stop();
    }
    ref.laserBeam = beam;
    beam._x = origin.x;
    beam._y = origin.y;
    beam._rotation = Math.atan2(dy, dx) * 180 / Math.PI;
    // 共用参考束长 250；横向延长，保持束体、亮芯与外晕的原生厚度。
    beam._xscale = ref.laserLength / 250 * 100;
    beam._yscale = 100;
    // 基础瞄准保留弱红束；火控强度直接读取与子弹相同的权威入口，视觉不写战斗数值。
    var progress:Number = 0;
    var runtime:Object = actor.__titaniumType61;
    if (ref.laserFireControl && runtime && typeof runtime.getFireControlProgress == "function") {
        progress = Number(runtime.getFireControlProgress());
        if (!isFinite(progress)) progress = 0;
        progress = Math.max(0, Math.min(1, progress));
    }
    beam._alpha = ref.laserFireControl ? 18 + 82 * progress : 100;
    beam._visible = true;
};

_root.装备生命周期函数.枪械激光卸载 = function(ref:Object):Void {
    if (!ref) return;
    ref.laserActive = false;
    _root.装备生命周期函数.枪械激光移除光束(ref);
    var dispatcher:Object = ref.自机.dispatcher;
    if (dispatcher && ref.laserPlacementHandler) {
        dispatcher.unsubscribe(ref.laserContainer, ref.laserPlacementHandler, ref);
    }
    ref.laserPlacementHandler = null;
};
