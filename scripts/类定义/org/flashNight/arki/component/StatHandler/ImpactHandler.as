class org.flashNight.arki.component.StatHandler.ImpactHandler {
    // 常量配置，便于外部调整
    public static var IMPACT_COEFFICIENT:Number = 50; // 冲击系数
    public static var IMPACT_DECAY_TIME:Number = 5;  // 冲击残余时间

    /**
     * 结算冲击力，将计算得到的冲击力添加到命中对象的残余冲击力中
     * @param damage Number 造成的伤害值
     * @param knockRate Number 击倒率
     * @param target Object 被命中的对象
     */
    public static function settleImpactForce(damage:Number, knockRate:Number, target:Object):Void {
        // 内联计算冲击力
        var impactForce:Number = damage * IMPACT_COEFFICIENT / knockRate;

        // 避免非有限数值影响
        if (isFinite(impactForce)) {
            target.残余冲击力 += impactForce; 
        } else {
            target.残余冲击力 = target.韧性上限 + 1; 
        }
    }

    /**
     * 刷新命中对象的冲击力状态
     * @param target Object 被命中的对象
     */
    public static function refreshImpactForce(target:Object):Void {
        var currentTime:Number = getTimer(); // 当前时间

        // 校验残余冲击力
        if (isNaN(target.残余冲击力)) { 
            _root.发布消息(target + " 触发异常残余 " + target.残余冲击力); // 保留中文函数名和属性名
            target.残余冲击力 = 0;
        }

        // 校验韧性系数
        if (isNaN(target.韧性系数)) { 
            target.韧性系数 = 1;
            _root.发布消息(target + " 触发异常韧性 " + target.韧性系数); // 保留中文函数名和属性名
        }

        // 计算韧性上限
        target.韧性上限 = target.韧性系数 * target.hp / _root.防御减伤比(target.防御力); 

        // 若存在上次受击时间，考虑冲击力衰减
        if (!isNaN(target.上次受击时间)) { 
            var interval:Number = currentTime - target.上次受击时间; // 受击间隔

            // 若受击间隔超过设定时间，计算衰减
            if (interval > 1000 * IMPACT_DECAY_TIME) {
                // 内联计算衰减比率
                var decayRate:Number = (2000 * IMPACT_DECAY_TIME - interval) / (2000 * IMPACT_DECAY_TIME);
                target.残余冲击力 = Math.max(0, target.残余冲击力 * decayRate); 
            }
        }

        // 更新受击时间
        target.上次受击时间 = currentTime; 
    }
}
