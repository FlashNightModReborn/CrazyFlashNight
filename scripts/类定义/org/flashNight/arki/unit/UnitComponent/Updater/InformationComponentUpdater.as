class org.flashNight.arki.unit.UnitComponent.Updater.InformationComponentUpdater {

    public static function update(target:MovieClip):Function {
        // 设置透明度和可见性
        var ic:MovieClip = target.新版人物文字信息;

        var hpBar:MovieClip = ic.头顶血槽;
        var hpBarBottom:MovieClip = hpBar.血槽底;

        var bloodBarX:Number = hpBarBottom._x;
        var bloodBarLength:Number = hpBarBottom._width;

        ic._visible = target.状态 == "登场" ? false : ic._alpha > 0;

        // 更新血槽长度
        hpBar.血槽条._width = target.hp / target.hp满血值 * bloodBarLength;

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
                var decayThresholdFrames:Number = _root.冲击残余时间 * 30; // e.g., 5秒 * 30 = 150帧

                // 若受击间隔超过设定时间（帧数），计算衰减
                if (intervalFrames > decayThresholdFrames) {
                    // 计算衰减比率
                    // 原公式: (2000 * 冲击残余时间 - interval) / (2000 * 冲击残余时间)
                    // 假设 2000 ms 对应 60帧（2秒），因此调整为：
                    var decayRate:Number = (60 * _root.冲击残余时间 - intervalFrames) / (60 * _root.冲击残余时间);
                    remainingImpactForce = Math.max(0, target.remainingImpactForce * decayRate);
                }
            }
        }

        // 更新韧性条的位置
        hpBar.韧性条._x = bloodBarX - remainingImpactForce / target.韧性上限 * bloodBarLength;

        // 在霸体状态下改变韧性条底部颜色
        hpBar.刚体遮罩._visible = (target.刚体 || target.man.刚体标签) ? true : false;

        // 更新 lastHitTime 为当前帧数
        target.lastHitTime = _root.帧计时器.当前帧数;
    }
}
