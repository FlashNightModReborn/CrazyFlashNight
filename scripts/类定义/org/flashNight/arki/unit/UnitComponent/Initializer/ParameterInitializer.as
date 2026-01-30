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

        // 承伤系数：用于统一控制目标受到伤害的倍率
        // - 默认值 1 表示正常承伤
        // - 小于 1 表示减伤（如 0.5 = 减伤50%，常用于霸体状态）
        // - 大于 1 表示增伤（如 1.5 = 易伤50%）
        // - 可通过 BuffManager 动态调整
        if (isNaN(target.damageTakenMultiplier)) target.damageTakenMultiplier = 1;

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
        if (!target.syncRefs) target.syncRefs = {};
        // UpdateEventComponent 用于记录渲染剔除
        if(isNaN(target.__cullState)) target.__cullState = { outCount: 0 };

        // 修复：不要无条件重置 updateEventComponentID，避免时间轮重复注册
        // 只在真正未初始化时（undefined）才设置为 null，换装时保持原值
        if(target.updateEventComponentID == undefined) {
            target.updateEventComponentID = null;
        }

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
