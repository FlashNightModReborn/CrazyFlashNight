import org.flashNight.arki.component.StatHandler.*;


class org.flashNight.arki.unit.UnitComponent.Updater.ImpactUpdater {
    public static function update(target:MovieClip):Void {
        // 计算剩余冲击力
        var remainingImpactForce:Number = target.remainingImpactForce;

        if (target.浮空 || target.倒地 || remainingImpactForce >= target.韧性上限) {
            remainingImpactForce = target.韧性上限;
        } else {
            // 使用帧计时器获取当前帧数
            var currentFrame:Number = _root.帧计时器.当前帧数;

            if (!isNaN(target.lastHitTime)) {
                var intervalFrames:Number = currentFrame - target.lastHitTime; // 受击间隔（帧数）

                // 将冲击残余时间从秒转换为帧数（30帧/秒）
                var decayThresholdFrames:Number = ImpactHandler.IMPACT_DECAY_TIME * 30; // e.g., 5秒 * 30 = 150帧

                // 若受击间隔超过设定时间（帧数），计算衰减
                if (intervalFrames > decayThresholdFrames) {
                    // 计算衰减比率
                    // 原公式: (2000 * 冲击残余时间 - interval) / (2000 * 冲击残余时间)
                    // 假设 2000 ms 对应 60帧（2秒），因此调整为：
                    var decayRate:Number = (60 * ImpactHandler.IMPACT_DECAY_TIME - intervalFrames) / (60 * ImpactHandler.IMPACT_DECAY_TIME);
                    remainingImpactForce = Math.max(0, target.remainingImpactForce * decayRate);
                }
            }
        }

        // 更新 lastHitTime 为当前帧数
        target.lastHitTime = _root.帧计时器.当前帧数;
    }
}
