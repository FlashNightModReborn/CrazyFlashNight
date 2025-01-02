class org.flashNight.arki.component.StatHandler.ImpactHandler {
    // 常量配置，便于外部调整
    public static var IMPACT_COEFFICIENT:Number = 50; // 冲击系数
    public static var IMPACT_DECAY_TIME:Number = 5;  // 冲击残余时间
    public static var IMPACT_DECAY_FRAME:Number = ImpactHandler.IMPACT_DECAY_TIME * 30;
    public static var IMPACT_DECAY_DFRAME:Number = ImpactHandler.IMPACT_DECAY_FRAME * 2;

    /**
     * 结算冲击力，将计算得到的冲击力添加到命中对象的remainingImpactForce中
     * @param damage Number 造成的伤害值
     * @param knockRate Number 击倒率
     * @param target Object 被命中的对象
     */
    public static function settleImpactForce(damage:Number, knockRate:Number, target:Object):Void {
        // 内联计算冲击力
        var impactForce:Number = damage * IMPACT_COEFFICIENT / knockRate;

        // 避免非有限数值影响
        if (isFinite(impactForce)) {
            target.remainingImpactForce += impactForce; 
        } else {
            target.remainingImpactForce = target.韧性上限 + 1; 
        }
    }

    /**
     * 刷新命中对象的冲击力状态
     * @param target Object 被命中的对象
     */
    public static function refreshImpactForce(target:Object):Void {
        // 使用帧计时器获取当前帧数
        var currentFrame:Number = _root.帧计时器.当前帧数; // 当前帧数

        // 校验 remainingImpactForce
        if (isNaN(target.remainingImpactForce)) { 
            _root.发布消息(target + " 触发异常残余 " + target.remainingImpactForce); // 保留中文函数名和属性名
            target.remainingImpactForce = 0;
        }

        // 校验韧性系数
        if (isNaN(target.韧性系数)) { 
            target.韧性系数 = 1;
            _root.发布消息(target + " 触发异常韧性 " + target.韧性系数); // 保留中文函数名和属性名
        }

        // 计算韧性上限
        target.韧性上限 = target.韧性系数 * target.hp / _root.防御减伤比(target.防御力); 

        // 若存在 lastHitTime，考虑冲击力衰减
        if (!isNaN(target.lastHitTime)) { 
            var intervalFrames:Number = currentFrame - target.lastHitTime; // 受击间隔（帧数）

            // 将冲击残余时间从秒转换为帧数
            var decayThresholdFrames:Number = IMPACT_DECAY_FRAME; // 30帧/秒

            // 若受击间隔超过设定时间（帧数），计算衰减
            if (intervalFrames > decayThresholdFrames) {
                // 将 2000 * IMPACT_DECAY_TIME 从毫秒转换为帧数
                var decayRate:Number = (IMPACT_DECAY_DFRAME - intervalFrames) / (IMPACT_DECAY_DFRAME);
                target.remainingImpactForce = Math.max(0, target.remainingImpactForce * decayRate); 
            }
        }

        // 更新受击时间为当前帧数
        target.lastHitTime = currentFrame; 
    }

}
