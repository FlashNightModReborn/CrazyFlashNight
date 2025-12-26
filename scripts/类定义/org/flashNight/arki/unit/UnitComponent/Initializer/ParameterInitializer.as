class org.flashNight.arki.unit.UnitComponent.Initializer.ParameterInitializer {
    public static var versionCount:Number = 0;

    private static var lastInitFrame:Number = 0;

    public static function initialize(target:MovieClip):Void {
        var currentFrame:Number = _root.帧计时器.当前帧数;

        if (isNaN(target.重量)) target.重量 = 60;
        if (isNaN(target.韧性系数)) target.韧性系数 = 1;
        if (isNaN(target.命中率)) target.命中率 = 10;
        if (isNaN(target.躲闪率)) target.躲闪率 = 999;
        if (isNaN(target.等级)) target.等级 = 1;

        // 初始化体重：基于身高计算（身高 - 105）
        if (isNaN(target.身高)) target.身高 = 175;
        target.体重 = target.身高 - 105;

        if (isNaN(target.remainingImpactForce)) target.remainingImpactForce = 0;
        if (isNaN(target.lastHitTime)) target.lastHitTime = currentFrame;

        if(isNaN(target.threat)) target.threat = 10;
        if(isNaN(target.threatThreshold)) target.threatThreshold = 5;

        
        

        var ic:MovieClip = target.新版人物文字信息;

        if (isNaN(target.previousActualHpWidth)) target.previousActualHpWidth = ic.头顶血槽.血槽底._width;
        if (isNaN(target.residualHpWidth)) target.residualHpWidth = target.previousActualHpWidth;
        if (isNaN(target.hpUnchangedCounter)) target.hpUnchangedCounter = 0;
        if (isNaN(target.icX)) target.icX = ic._x;
        if (isNaN(target.icY)) target.icY = ic._y;

        if (target.状态 == "登场") ic._visible = false;
        if (isNaN(target.lastStatusChangeFrame)) target.lastStatusChangeFrame = currentFrame;
        if (!target.equipLoadStatus) target.equipLoadStatus = {};
        if (!target.syncRequiredEquips) target.syncRequiredEquips = {};

        // UpdateEventComponent 用于记录渲染剔除
        if(isNaN(target.__cullState)) target.__cullState = { outCount: 0 };

        target.updateEventComponentID = null;

        if(_root.控制目标 === target._name) {
            if(currentFrame > lastInitFrame) {

                // 部分情况主角会原地多次刷新，原因未定位
                // 多次刷新会导致版本号迭代，装备生命周期函数失效，因此手动防护避免频繁刷新
                target.version = ++versionCount;
                lastInitFrame = currentFrame;
            }
        } else {
            target.version = ++versionCount;
        }
        
    }
}
