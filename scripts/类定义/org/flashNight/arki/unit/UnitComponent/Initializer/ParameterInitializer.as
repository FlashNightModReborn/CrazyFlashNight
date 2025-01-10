class org.flashNight.arki.unit.UnitComponent.Initializer.ParameterInitializer {
    public static function initialize(target:MovieClip):Void {
        if (isNaN(target.重量)) target.重量 = 60;
        if (isNaN(target.韧性系数)) target.韧性系数 = 1;
        if (isNaN(target.命中率)) target.命中率 = 10;
        if (isNaN(target.躲闪率)) target.躲闪率 = 999;
        if (isNaN(target.等级)) target.等级 = 1;

        if (isNaN(target.remainingImpactForce)) target.remainingImpactForce = 0;
        if (isNaN(target.lastHitTime)) target.lastHitTime = _root.帧计时器.当前帧数;
    }
}
