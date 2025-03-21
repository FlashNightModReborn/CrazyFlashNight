import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.unit.UnitComponent.Updater.InformationComponentUpdater {

    public static function update(target:MovieClip):Void {
        // 设置透明度和可见性
        var ic:MovieClip = target.新版人物文字信息;
        if (!(ic._visible = target.状态 == "登场" ? false : ic._alpha > 0)) return;

        var hpBar:MovieClip = ic.头顶血槽;
        var hpBarBottom:MovieClip = hpBar.血槽底;
        var bloodBarX:Number = hpBarBottom._x;
        var bloodBarLength:Number = hpBarBottom._width;

        // 计算实际血槽条的宽度
        var actualHpWidth:Number = target.hp / target.hp满血值 * bloodBarLength;
        hpBar.血槽条._width = actualHpWidth;

        // 新增：检测连续更新时实际血槽宽度是否未发生变化
        if (actualHpWidth == target.previousActualHpWidth) {
            target.hpUnchangedCounter++;
        } else {
            target.hpUnchangedCounter = 0;
        }

        target.previousActualHpWidth = actualHpWidth;

        // 根据连续未变化的次数调整更新速度
        // 游戏帧率：30帧/秒，update每4帧执行一次 => 每秒7.5次update
        // 每次update间隔：4/30 ≈ 0.1333秒

        // 设置衰减开始条件：target.hpUnchangedCounter >= 15
        // 15次update ≈ 15 * 0.1333 ≈ 2秒
        // 即血量连续2秒未变化后，开始衰减残余血槽条，提供视觉提示

        // 设置衰减速度：currentSpeed = 0.2
        // 目标：在接下来的3秒内完成衰减（差值衰减到初始差值的1%以下）
        // 3秒内update次数：3 / 0.1333 ≈ 22.5次，取23次
        // 衰减公式：(1 - currentSpeed)^23 < 0.01
        // 解得 currentSpeed > 1 - 0.01^(1/23) ≈ 0.1996
        // 因此 currentSpeed = 0.2 可确保3秒内衰减完成，总计2+3=5秒，与冲击力衰减时间匹配

        var currentSpeed:Number = (target.hpUnchangedCounter >= 15) ? 0.2 : 0;

        // 更新残余血槽条的宽度
        var residualHpWidth:Number = target.residualHpWidth;
        if (residualHpWidth > actualHpWidth) {
            residualHpWidth -= (residualHpWidth - actualHpWidth) * currentSpeed;
            if (residualHpWidth < actualHpWidth) {
                residualHpWidth = actualHpWidth; // 防止过减
            }
        } else {
            residualHpWidth = actualHpWidth; // 如果血量增加，直接同步
        }
        target.residualHpWidth = residualHpWidth;
        hpBar.残余血槽条._width = residualHpWidth;

        // 更新韧性条的位置
        hpBar.韧性条._x = bloodBarX - target.remainingImpactForce / target.韧性上限 * bloodBarLength;
        // 在霸体状态下改变韧性条底部颜色
        hpBar.刚体遮罩._visible = !!(target.刚体 || target.man.刚体标签);
    }
}
