class org.flashNight.arki.unit.UnitComponent.Updater.InformationComponentUpdater {

    // -------------------
    // 常量定义
    // -------------------
    // 残余血槽动画开始与结束帧
    private static var ANIM_START:Number = 16;
    private static var ANIM_END:Number = 39;
    // 血槽淡出开始帧
    private static var FADE_OUT_START:Number = 50;
    private static var FADE_OUT_END:Number   = 75;

    public static function update(target:MovieClip):Void {
        // 设置透明度和可见性
        var ic:MovieClip = target.新版人物文字信息;
        // 如果是“登场”状态，或者已经完全透明，则不显示
        ic._visible = (target.状态 == "登场") ? false : (ic._alpha > 0);
        if (!ic._visible) return;

        var hpBar:MovieClip = ic.头顶血槽;
        var hpBarBottom:MovieClip = hpBar.血槽底;
        var bloodBarX:Number = hpBarBottom._x;
        var bloodBarLength:Number = hpBarBottom._width;

        // 根据是否有HP变化判断是否更新信息位置
        if (target.hpUnchangedCounter == 0) {
            ic._x = target.icX;
            ic._y = target.icY;
        }

        // =========== 1. 计算实际血槽宽度 ===========
        var actualHpWidth:Number = target.hp / target.hp满血值 * bloodBarLength;

        // =========== 2. 判断HP是否变动 ===========
        // 内联后的 HP 变化检测
        var lastHp:Number = target.lastHp;
        var currentHp:Number = target.hp;
        if (lastHp != currentHp) {
            target.lastHp = currentHp;
            target.hpUnchangedCounter = 0;
            target._animStartResidual = target.residualHpWidth;
            target._animStartActual   = actualHpWidth;
        } else {
            target.hpUnchangedCounter++;
        }

        // =========== 3. 更新即时血槽（立刻同步到当前HP） ===========
        hpBar.血槽条._width = actualHpWidth;

        // =========== 4. 根据区间处理残余血槽逻辑 ===========
        var currentCounter:Number = target.hpUnchangedCounter;
        var residualHpWidth:Number = target.residualHpWidth;

        // 4.1 HP 上升：立即追上
        if (actualHpWidth > residualHpWidth) {
            residualHpWidth = actualHpWidth;
        }
        // 4.2 HP 下降：如果在动画区间，就进行插值动画
        else if (residualHpWidth > actualHpWidth) {
            // 在 [ANIM_START, ANIM_END] 区间，执行二次缓出
            if (currentCounter >= ANIM_START && currentCounter <= ANIM_END) {
                var t:Number = (currentCounter - ANIM_START) / (ANIM_END - ANIM_START);
                // 二次缓出 progress = t * (2 - t)，可以根据需求调整
                var progress:Number = t * (2 - t);

                // 动画插值：从 animStartResidual -> animStartActual
                // animStartResidual 记录的是动画开始时的 residualHpWidth
                // animStartActual   记录的是动画开始时对应的 actualHpWidth
                residualHpWidth = target._animStartResidual - 
                    (target._animStartResidual - target._animStartActual) * progress;

                // 给个小范围保护，避免浮点误差导致的抖动
                if (Math.abs(residualHpWidth - actualHpWidth) < 0.1) {
                    residualHpWidth = actualHpWidth;
                }
            }
            // 超过动画区间，强制到实际数值
            else if (currentCounter > ANIM_END) {
                residualHpWidth = actualHpWidth;
            }
        }

        // 4.3 写回残余血槽
        target.residualHpWidth = residualHpWidth;
        hpBar.残余血槽条._width = residualHpWidth;

        // =========== 5. 处理血槽淡出 =========== 
        if (currentCounter > FADE_OUT_START) {
            // 举例：FADE_OUT_START=50 到 FADE_OUT_END=75 之间做线性衰减
            var fadeProgress:Number = (currentCounter - FADE_OUT_START) / (FADE_OUT_END - FADE_OUT_START);
            if (fadeProgress > 1) fadeProgress = 1; // 超过就归1
            hpBar._alpha = (1 - fadeProgress) * 100; // 让 alpha 在 100% -> 0% 间变化
        } else {
            hpBar._alpha = 100; // 50 帧之前保持不变
        }

        // =========== 6. 更新韧性条位置/刚体遮罩 ===========
        hpBar.韧性条._width = bloodBarLength - (target.remainingImpactForce / target.韧性上限) * bloodBarLength;
        hpBar.刚体遮罩._visible = !!(target.刚体 || target.man.刚体标签);
    }
}
