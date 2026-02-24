import org.flashNight.arki.render.RayVfxManager;

/**
 * WaveRenderer - 波能射线渲染器
 *
 * 致敬红警3波能炮的视觉风格，核心特征：
 * • 正弦波路径：能量束呈波浪形态传播
 * • 脉冲膨胀：粗细随时间周期性变化
 * • 四层渲染：红底光 → 橙泛光 → 主体 → 白芯
 * • pierce 命中点增亮：穿透命中点绘制环形波纹
 *
 * 路径生成原理：
 *   waveOffset = waveAmp × envelope × sin((t × dist / waveLen - age × waveSpeed) × 2π)
 *   其中 envelope = sin(t × π) 为纺锤包络，约束两端归零。
 *
 * LOD 降级效果：
 *   LOD 0: 全特效（正弦波 + 脉冲 + 命中点波纹）
 *   LOD 1: 取消命中点波纹，简化波形
 *   LOD 2: 取消脉冲动画，直线路径
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.renderer.WaveRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY_COLOR:Number = 0xFF4400;    // 红橙色
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFAA00;  // 橙黄高光
    private static var DEFAULT_THICKNESS:Number = 5;
    private static var DEFAULT_WAVE_AMP:Number = 8;                // 波形幅度
    private static var DEFAULT_WAVE_LEN:Number = 40;               // 波长
    private static var DEFAULT_WAVE_SPEED:Number = 0.15;           // 波传播速度
    private static var DEFAULT_PULSE_AMP:Number = 0.2;             // 脉冲幅度
    private static var DEFAULT_PULSE_RATE:Number = 0.3;            // 脉冲速率
    private static var DEFAULT_HIT_RIPPLE_SIZE:Number = 15;        // 命中点波纹大小
    private static var DEFAULT_HIT_RIPPLE_ALPHA:Number = 50;       // 命中点波纹透明度

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染波能射线
     *
     * @param arc 电弧数据对象
     * @param lod 当前 LOD 等级 (0=高, 1=中, 2=低)
     * @param mc  目标 MovieClip
     */
    public static function render(arc:Object, lod:Number, mc:MovieClip):Void {
        var config:Object = arc.config;
        var meta:Object = arc.meta;
        var age:Number = arc.age;

        // 解析配置参数
        var primaryColor:Number = (config != null && !isNaN(config.primaryColor)) ? config.primaryColor : DEFAULT_PRIMARY_COLOR;
        var secondaryColor:Number = (config != null && !isNaN(config.secondaryColor)) ? config.secondaryColor : DEFAULT_SECONDARY_COLOR;
        var thickness:Number = (config != null && !isNaN(config.thickness)) ? config.thickness : DEFAULT_THICKNESS;
        var waveAmp:Number = (config != null && !isNaN(config.waveAmp)) ? config.waveAmp : DEFAULT_WAVE_AMP;
        var waveLen:Number = (config != null && !isNaN(config.waveLen)) ? config.waveLen : DEFAULT_WAVE_LEN;
        var waveSpeed:Number = (config != null && !isNaN(config.waveSpeed)) ? config.waveSpeed : DEFAULT_WAVE_SPEED;
        var pulseAmp:Number = (config != null && !isNaN(config.pulseAmp)) ? config.pulseAmp : DEFAULT_PULSE_AMP;
        var pulseRate:Number = (config != null && !isNaN(config.pulseRate)) ? config.pulseRate : DEFAULT_PULSE_RATE;
        var hitRippleSize:Number = (config != null && !isNaN(config.hitRippleSize)) ? config.hitRippleSize : DEFAULT_HIT_RIPPLE_SIZE;
        var hitRippleAlpha:Number = (config != null && !isNaN(config.hitRippleAlpha)) ? config.hitRippleAlpha : DEFAULT_HIT_RIPPLE_ALPHA;

        // 应用 intensity 强度因子
        var intensity:Number = (meta != null && !isNaN(meta.intensity)) ? meta.intensity : 1.0;
        thickness *= intensity;
        waveAmp *= intensity;

        // LOD 降级
        var enableWave:Boolean = (lod < 2);
        var enablePulse:Boolean = (lod < 2);
        var enableRipple:Boolean = (lod < 1);

        // 计算电弧方向向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        // 垂直方向向量
        var perpX:Number = -dy / dist;
        var perpY:Number = dx / dist;

        // 计算脉冲粗细调制
        var pulseFactor:Number = 1.0;
        if (enablePulse) {
            pulseFactor = 1.0 + pulseAmp * Math.sin(age * pulseRate * 2 * Math.PI);
        }
        var currentThick:Number = thickness * pulseFactor;

        // 生成路径
        var path:Array;
        if (enableWave) {
            path = generateWavePath(arc, perpX, perpY, dist, waveAmp, waveLen, waveSpeed, age);
        } else {
            // LOD 2: 直线路径
            path = generateStraightPath(arc);
        }

        // ─────────────────────────────────────────────────────────────
        // 四层渲染
        // ─────────────────────────────────────────────────────────────

        // Layer 0: 红底光（最宽，营造能量辐射感）
        RayVfxManager.drawPath(mc, path, 0xFF0000, currentThick * 8, 15);

        // Layer 1: 橙泛光
        RayVfxManager.drawPath(mc, path, primaryColor, currentThick * 4, 35);

        // Layer 2: 主体
        RayVfxManager.drawPath(mc, path, primaryColor, currentThick * 2, 85);

        // Layer 3: 白芯
        RayVfxManager.drawPath(mc, path, secondaryColor, currentThick * 0.5, 100);

        // ─────────────────────────────────────────────────────────────
        // pierce 命中点增亮
        // ─────────────────────────────────────────────────────────────
        if (enableRipple && meta != null && meta.segmentKind == "pierce" && meta.hitPoints != null) {
            var hitPoints:Array = meta.hitPoints;
            for (var i:Number = 0; i < hitPoints.length; i++) {
                var hp:Object = hitPoints[i];
                // 绘制环形波纹
                RayVfxManager.drawCircle(mc, hp.x, hp.y, hitRippleSize, secondaryColor, hitRippleAlpha);
                // 绘制内部增亮点
                RayVfxManager.drawCircle(mc, hp.x, hp.y, hitRippleSize * 0.5, 0xFFFFFF, hitRippleAlpha * 1.5);
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 路径生成
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成正弦波路径
     *
     * @param arc       电弧数据对象
     * @param perpX     垂直方向 X 分量
     * @param perpY     垂直方向 Y 分量
     * @param dist      射线总长度
     * @param waveAmp   波形幅度
     * @param waveLen   波长
     * @param waveSpeed 波传播速度
     * @param age       当前帧龄
     * @return          路径点数组
     */
    private static function generateWavePath(arc:Object, perpX:Number, perpY:Number,
                                              dist:Number, waveAmp:Number, waveLen:Number,
                                              waveSpeed:Number, age:Number):Array {
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;

        var points:Array = RayVfxManager.poolArr();

        // 分段数（波能需要更多分段以保证波形平滑）
        var segmentCount:Number = Math.max(10, Math.ceil(dist / 20));
        var step:Number = 1.0 / segmentCount;

        for (var i:Number = 0; i <= segmentCount; i++) {
            var t:Number = i * step;

            // 基础坐标
            var baseX:Number = arc.startX + dx * t;
            var baseY:Number = arc.startY + dy * t;

            // 计算波形偏移
            var offset:Number = 0;
            if (t > 0.001 && t < 0.999) {
                // 纺锤包络约束两端
                var envelope:Number = Math.sin(t * Math.PI);
                // 正弦波（沿束方向传播）
                // 使用 t × dist 确保像素尺度的波长
                offset = waveAmp * envelope * Math.sin((t * dist / waveLen - age * waveSpeed) * 2 * Math.PI);
            }

            // 端点强制锁定
            if (t <= 0.001) {
                points.push(RayVfxManager.pt(arc.startX, arc.startY, 0.0));
            } else if (t >= 0.999) {
                points.push(RayVfxManager.pt(arc.endX, arc.endY, 1.0));
            } else {
                points.push(RayVfxManager.pt(baseX + perpX * offset, baseY + perpY * offset, t));
            }
        }

        return points;
    }

    /**
     * 生成直线路径（LOD 2 降级用）
     *
     * @param arc 电弧数据对象
     * @return    路径点数组
     */
    private static function generateStraightPath(arc:Object):Array {
        var points:Array = RayVfxManager.poolArr();
        points.push(RayVfxManager.pt(arc.startX, arc.startY, 0.0));
        points.push(RayVfxManager.pt(arc.endX, arc.endY, 1.0));
        return points;
    }
}
