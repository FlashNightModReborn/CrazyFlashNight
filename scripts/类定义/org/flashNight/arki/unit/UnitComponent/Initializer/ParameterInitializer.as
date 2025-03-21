class org.flashNight.arki.unit.UnitComponent.Initializer.ParameterInitializer {
    public static function initialize(target:MovieClip):Void {
        if (isNaN(target.重量)) target.重量 = 60;
        if (isNaN(target.韧性系数)) target.韧性系数 = 1;
        if (isNaN(target.命中率)) target.命中率 = 10;
        if (isNaN(target.躲闪率)) target.躲闪率 = 999;
        if (isNaN(target.等级)) target.等级 = 1;

        if (isNaN(target.remainingImpactForce)) target.remainingImpactForce = 0;
        if (isNaN(target.lastHitTime)) target.lastHitTime = _root.帧计时器.当前帧数;
        if (isNaN(target.previousActualHpWidth)) target.previousActualHpWidth = target.新版人物文字信息.头顶血槽.血槽底._width;
        if (isNaN(target.residualHpWidth)) target.residualHpWidth = target.previousActualHpWidth;
        if (isNaN(target.hpUnchangedCounter)) target.hpUnchangedCounter = 0;
        // 主角专用
        if(target._name === _root.控制目标) {
            if(isNaN(target.version)) target.version = 0; // 用于记录换装版本号
        }
    }
}
