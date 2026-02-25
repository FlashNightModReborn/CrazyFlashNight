import org.flashNight.arki.render.RayVfxManager;

/**
 * VortexRenderer - 涡旋射线渲染器 (v2)
 *
 * 宽展双螺旋缠绕的高能涡旋光束，v2 渲染技术升级：
 * • 多层递减泛光：取代单层暗色底光，伪高斯 Bloom 自然消散
 * • 波纹自带白芯(α75)：交汇处 additive 自动爆白能量节点
 * • 直线白芯降至 α80：动态交叉点成为最亮焦点
 * • 24 点/波长采样：极致平滑零折角
 * • 炮口辉光球 + 三层命中点爆破
 *
 * 保持涡旋特色参数（宽振幅、长波长、慢波速）区别于 Wave 的紧凑风格
 *
 * 渲染层级（从后到前）：
 *   Layer 0: 直线泛光(α15+α30) → Layer 1: 螺旋波纹(α35+α70+α75白芯)
 *   → Layer 2: 直线白芯(α80) → 炮口辉光 → 命中点爆破
 *
 * LOD 降级：
 *   LOD 0: 全特效（对称双螺旋 + 脉冲 + 炮口辉光 + 命中点波纹）
 *   LOD 1: 单螺旋（无命中点波纹、无炮口辉光）
 *   LOD 2: 纯直线（无波纹，无脉冲）
 *
 * @author FlashNight
 * @version 2.0
 */
class org.flashNight.arki.render.renderer.VortexRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量（保持涡旋特色：宽展螺旋）
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY_COLOR:Number = 0x0088FF;    // 亮蓝
    private static var DEFAULT_SECONDARY_COLOR:Number = 0x88DDFF;  // 淡青白高光
    private static var DEFAULT_THICKNESS:Number = 6;
    private static var DEFAULT_WAVE_AMP:Number = 12;               // 宽振幅（涡旋特色）
    private static var DEFAULT_WAVE_LEN:Number = 90;               // 长波长（宽展缠绕）
    private static var DEFAULT_WAVE_SPEED:Number = 0.3;            // 慢波速（优雅旋转）
    private static var DEFAULT_PULSE_AMP:Number = 0.2;             // 脉冲幅度
    private static var DEFAULT_PULSE_RATE:Number = 0.3;            // 脉冲速率
    private static var DEFAULT_HIT_RIPPLE_SIZE:Number = 20;        // 命中点波纹大小
    private static var DEFAULT_HIT_RIPPLE_ALPHA:Number = 60;       // 命中点波纹透明度

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染涡旋射线
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

        // 全局加色混合
        mc.blendMode = "add";

        // 计算脉冲粗细调制
        var pulseFactor:Number = 1.0;
        if (enablePulse) {
            pulseFactor = 1.0 + pulseAmp * Math.sin(age * pulseRate * 2 * Math.PI);
        }
        var currentThick:Number = thickness * pulseFactor;

        // ─────────────────────────────────────────────────────────────
        // 路径生成：笔直主轴 + 对称双螺旋
        // ─────────────────────────────────────────────────────────────

        var pathStraight:Array = generateStraightPath(arc);
        var pathWave1:Array = null;
        var pathWave2:Array = null;

        if (enableWave) {
            pathWave1 = generateVortexPath(arc, perpX, perpY, dist,
                waveAmp, waveLen, waveSpeed, age, 0);
            if (lod == 0) {
                pathWave2 = generateVortexPath(arc, perpX, perpY, dist,
                    waveAmp, waveLen, waveSpeed, age, Math.PI);
            }
        }

        // ─────────────────────────────────────────────────────────────
        // ★ v2 渲染层级重构：多层泛光 + 波纹白芯
        // ─────────────────────────────────────────────────────────────

        // Layer 0: 直线大范围泛光（背景环境辉光）
        RayVfxManager.drawPath(mc, pathStraight, primaryColor, currentThick * 6.0, 15);
        RayVfxManager.drawPath(mc, pathStraight, secondaryColor, currentThick * 2.5, 30);

        // Layer 1: 螺旋波纹层（★ 自带白芯，交汇处 additive 爆白）
        if (enableWave) {
            var waveThick:Number = currentThick * 0.75;

            // 波纹 A：主色泛光 → 副色高光 → 白芯(α75)
            RayVfxManager.drawPath(mc, pathWave1, primaryColor, waveThick * 3.5, 35);
            RayVfxManager.drawPath(mc, pathWave1, secondaryColor, waveThick * 1.5, 70);
            RayVfxManager.drawPath(mc, pathWave1, 0xFFFFFF, waveThick * 0.4, 75);

            // 波纹 B（LOD 0 专属）
            if (pathWave2 != null) {
                RayVfxManager.drawPath(mc, pathWave2, primaryColor, waveThick * 3.5, 35);
                RayVfxManager.drawPath(mc, pathWave2, secondaryColor, waveThick * 1.5, 70);
                RayVfxManager.drawPath(mc, pathWave2, 0xFFFFFF, waveThick * 0.4, 75);
            }
        }

        // Layer 2: 直线白芯（★ 降至 α80，为波纹交汇点让路）
        RayVfxManager.drawPath(mc, pathStraight, 0xFFFFFF, currentThick * 0.5, 80);

        // ─────────────────────────────────────────────────────────────
        // 炮口辉光球
        // ─────────────────────────────────────────────────────────────

        if (enableRipple) {
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                currentThick * 4.0, primaryColor, 40);
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                currentThick * 1.5, secondaryColor, 80);
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                currentThick * 0.6, 0xFFFFFF, 100);
        }

        // ─────────────────────────────────────────────────────────────
        // pierce 命中点三层爆破波纹
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
     * 生成涡旋路径（委托给 RayVfxManager.generateSinePath）
     *
     * 与 WaveRenderer 共享同一路径生成算法，差异仅在参数（宽振幅、长波长、慢波速）。
     */
    private static function generateVortexPath(arc:Object, perpX:Number, perpY:Number,
                                              dist:Number, waveAmp:Number, waveLen:Number,
                                              waveSpeed:Number, age:Number,
                                              phaseOffset:Number):Array {
        return RayVfxManager.generateSinePath(
            arc, perpX, perpY, dist,
            waveAmp, waveLen, waveSpeed, age, phaseOffset,
            24, 250, 0);
    }

    /**
     * 生成直线路径
     *
     * @param arc 电弧数据对象
     * @return    路径点数组
     */
    private static function generateStraightPath(arc:Object):Array {
        return RayVfxManager.straightPath(arc.startX, arc.startY, arc.endX, arc.endY);
    }
}
