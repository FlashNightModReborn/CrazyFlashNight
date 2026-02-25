import org.flashNight.arki.render.RayVfxManager;

/**
 * PlasmaRenderer - 等离子射线渲染器
 *
 * 高能等离子体射流，核心视觉特征：
 * • 多层递减泛光叠加：伪高斯 Bloom，光芒自然向外消散
 * • 去实体化螺旋：半透明能量游丝，additive 交汇处自然过曝成白色节点
 * • 高频扰动叠加：2.7x 频率碎波打破完美函数感，模拟等离子湍流
 * • 不对称双螺旋：两条能量流各有个性，打破镜像死板感
 * • 收紧振幅：波纹紧贴主轴核心，高压等离子激流
 * • 炮口辉光球：消除直线段在起射点的平切感
 *
 * 渲染层级（从后到前）：
 *   Layer 0: 极宽散光(α10) → Layer 1: 中层光晕(α25)
 *   → Layer 2: 核心包裹(α50) → Layer 3: 螺旋游丝(半透明)
 *   → Layer 4: 致盲白芯(α100) → 炮口辉光 → 命中点爆破
 *
 * LOD 降级：
 *   LOD 0: 全特效（不对称双螺旋 + 脉冲 + 炮口辉光 + 命中点波纹）
 *   LOD 1: 单螺旋（无命中点波纹、无炮口辉光）
 *   LOD 2: 纯直线（无波纹，无脉冲）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.renderer.PlasmaRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY_COLOR:Number = 0x0088FF;    // 主蓝
    private static var DEFAULT_SECONDARY_COLOR:Number = 0x88EEFF;  // 极亮青白（交汇过曝用）
    private static var DEFAULT_THICKNESS:Number = 5;               // 白芯基础粗细
    private static var DEFAULT_WAVE_AMP:Number = 6;                // 振幅（紧贴光柱）
    private static var DEFAULT_WAVE_LEN:Number = 60;               // 波长（紧密螺旋）
    private static var DEFAULT_WAVE_SPEED:Number = 0.5;            // 波速
    private static var DEFAULT_PULSE_AMP:Number = 0.15;            // 脉冲幅度
    private static var DEFAULT_PULSE_RATE:Number = 0.4;            // 脉冲速率
    private static var DEFAULT_HIT_RIPPLE_SIZE:Number = 20;        // 命中点波纹大小
    private static var DEFAULT_HIT_RIPPLE_ALPHA:Number = 60;       // 命中点波纹透明度

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染等离子射线
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
        var primaryColor:Number = (config != null && !isNaN(config.primaryColor))
            ? config.primaryColor : DEFAULT_PRIMARY_COLOR;
        var secondaryColor:Number = (config != null && !isNaN(config.secondaryColor))
            ? config.secondaryColor : DEFAULT_SECONDARY_COLOR;
        var thickness:Number = (config != null && !isNaN(config.thickness))
            ? config.thickness : DEFAULT_THICKNESS;
        var waveAmp:Number = (config != null && !isNaN(config.waveAmp))
            ? config.waveAmp : DEFAULT_WAVE_AMP;
        var waveLen:Number = (config != null && !isNaN(config.waveLen))
            ? config.waveLen : DEFAULT_WAVE_LEN;
        var waveSpeed:Number = (config != null && !isNaN(config.waveSpeed))
            ? config.waveSpeed : DEFAULT_WAVE_SPEED;
        var pulseAmp:Number = (config != null && !isNaN(config.pulseAmp))
            ? config.pulseAmp : DEFAULT_PULSE_AMP;
        var pulseRate:Number = (config != null && !isNaN(config.pulseRate))
            ? config.pulseRate : DEFAULT_PULSE_RATE;
        var hitRippleSize:Number = (config != null && !isNaN(config.hitRippleSize))
            ? config.hitRippleSize : DEFAULT_HIT_RIPPLE_SIZE;
        var hitRippleAlpha:Number = (config != null && !isNaN(config.hitRippleAlpha))
            ? config.hitRippleAlpha : DEFAULT_HIT_RIPPLE_ALPHA;

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

        var perpX:Number = -dy / dist;
        var perpY:Number = dx / dist;

        // 全局叠加混合
        mc.blendMode = "add";

        // 计算脉冲粗细调制
        var pulseFactor:Number = 1.0;
        if (enablePulse) {
            pulseFactor = 1.0 + pulseAmp * Math.sin(age * pulseRate * 2 * Math.PI);
        }
        var currentThick:Number = thickness * pulseFactor;

        // ─────────────────────────────────────────────────────────────
        // 路径分离：笔直主轴 + 不对称双螺旋
        // ─────────────────────────────────────────────────────────────

        var pathStraight:Array = generateStraightPath(arc);
        var pathWave1:Array = null;
        var pathWave2:Array = null;

        if (enableWave) {
            pathWave1 = generatePlasmaPath(arc, perpX, perpY, dist,
                waveAmp, waveLen, waveSpeed, age, 0);
            if (lod == 0) {
                pathWave2 = generatePlasmaPath(arc, perpX, perpY, dist,
                    waveAmp * 0.9, waveLen * 1.1, waveSpeed * 1.05, age, Math.PI * 0.9);
            }
        }

        // ─────────────────────────────────────────────────────────────
        // 多层递减泛光叠加（Volumetric Bloom）
        // ─────────────────────────────────────────────────────────────

        // Layer 0: 最外层大范围散光
        RayVfxManager.drawPath(mc, pathStraight, primaryColor, currentThick * 6.5, 10);

        // Layer 1: 中层光晕
        RayVfxManager.drawPath(mc, pathStraight, primaryColor, currentThick * 3.0, 25);

        // Layer 2: 核心高亮包裹层
        RayVfxManager.drawPath(mc, pathStraight, secondaryColor, currentThick * 1.5, 50);

        // Layer 3: 螺旋游丝（半透明能量带，交汇过曝）
        if (enableWave) {
            var waveThick:Number = currentThick * 0.8;

            RayVfxManager.drawPath(mc, pathWave1, primaryColor, waveThick * 2.2, 35);
            RayVfxManager.drawPath(mc, pathWave1, secondaryColor, waveThick * 0.9, 65);

            if (pathWave2 != null) {
                RayVfxManager.drawPath(mc, pathWave2, primaryColor, waveThick * 2.2, 35);
                RayVfxManager.drawPath(mc, pathWave2, secondaryColor, waveThick * 0.9, 65);
            }
        }

        // Layer 4: 致盲白芯
        RayVfxManager.drawPath(mc, pathStraight, 0xFFFFFF, currentThick * 0.5, 100);

        // ─────────────────────────────────────────────────────────────
        // 炮口辉光球
        // ─────────────────────────────────────────────────────────────

        if (enableRipple) {
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                currentThick * 3.0, primaryColor, 35);
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                currentThick * 1.2, secondaryColor, 70);
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                currentThick * 0.6, 0xFFFFFF, 100);
        }

        // ─────────────────────────────────────────────────────────────
        // pierce 命中点多层爆破波纹
        // ─────────────────────────────────────────────────────────────

        if (enableRipple && meta != null && meta.segmentKind == "pierce" && meta.hitPoints != null) {
            var hitPoints:Array = meta.hitPoints;
            for (var i:Number = 0; i < hitPoints.length; i++) {
                var hp:Object = hitPoints[i];
                var pulseSize:Number = hitRippleSize * pulseFactor;
                RayVfxManager.drawCircle(mc, hp.x, hp.y,
                    pulseSize * 1.5, primaryColor, hitRippleAlpha * 0.6);
                RayVfxManager.drawCircle(mc, hp.x, hp.y,
                    pulseSize, secondaryColor, hitRippleAlpha);
                RayVfxManager.drawCircle(mc, hp.x, hp.y,
                    pulseSize * 0.4, 0xFFFFFF, 100);
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 路径生成
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成带高频扰动的等离子波路径
     *
     * @param arc         电弧数据对象
     * @param perpX       垂直方向 X 分量
     * @param perpY       垂直方向 Y 分量
     * @param dist        射线总长度
     * @param waveAmp     波形幅度
     * @param waveLen     波长
     * @param waveSpeed   波传播速度
     * @param age         当前帧龄
     * @param phaseOffset 相位偏移（弧度）
     * @return            路径点数组
     */
    private static function generatePlasmaPath(arc:Object, perpX:Number, perpY:Number,
                                              dist:Number, waveAmp:Number, waveLen:Number,
                                              waveSpeed:Number, age:Number,
                                              phaseOffset:Number):Array {
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;

        var points:Array = RayVfxManager.poolArr();

        var ptsPerWave:Number = 12;
        if (waveLen < 5) waveLen = 5;
        var segmentCount:Number = Math.ceil(dist / (waveLen / ptsPerWave));
        if (segmentCount < 10) segmentCount = 10;
        if (segmentCount > 200) segmentCount = 200;

        var step:Number = 1.0 / segmentCount;
        var margin:Number = 0.08;

        for (var i:Number = 0; i <= segmentCount; i++) {
            var t:Number = i * step;

            var baseX:Number = arc.startX + dx * t;
            var baseY:Number = arc.startY + dy * t;

            var offset:Number = 0;

            if (t > 0.001 && t < 0.999) {
                var envelope:Number = 1.0;
                if (t < margin) {
                    envelope = t / margin;
                } else if (t > 1.0 - margin) {
                    envelope = (1.0 - t) / margin;
                }
                envelope = envelope * envelope * (3 - 2 * envelope);

                var mainPhase:Number = (t * dist / waveLen - age * waveSpeed) * 2 * Math.PI
                    + phaseOffset;
                var mainWave:Number = Math.sin(mainPhase);

                var noisePhase:Number = (t * dist / (waveLen * 0.37) - age * waveSpeed * 1.5)
                    * 2 * Math.PI;
                var noiseWave:Number = Math.sin(noisePhase) * 0.25;

                offset = waveAmp * envelope * (mainWave + noiseWave);
            }

            if (t <= 0.001) {
                points.push(RayVfxManager.pt(arc.startX, arc.startY, 0.0));
            } else if (t >= 0.999) {
                points.push(RayVfxManager.pt(arc.endX, arc.endY, 1.0));
            } else {
                points.push(RayVfxManager.pt(
                    baseX + perpX * offset,
                    baseY + perpY * offset, t));
            }
        }

        return points;
    }

    /**
     * 生成直线路径
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
