import org.flashNight.arki.render.RayVfxManager;

/**
 * SpectrumRenderer - 光谱射线渲染器 (RA3 致敬版 v3)
 *
 * 致敬红警3光谱武器的视觉风格，核心设计原则：
 * • 长波优雅交织：极大波长(300px+)，几条光带在飞行中仅交织1~2次
 * • 平顶等宽轮廓：90%笔直圆柱段，仅在首尾30px急速收束
 * • 高饱和冷色：少量色条(3条)+大振幅(10px+)，避免叠加过曝糊白
 * • 实体光纤：每根彩带自带极细白核，"多股激光拧结"的视觉错觉
 * • 混沌波长：每条线振幅/波长微量不同，打破机械弹簧感
 * • 叠加混合：blendMode="add"，交汇处自然过曝白斑
 *
 * LOD 降级效果：
 *   LOD 0: 全特效（底层双色泛光 + 全量交织 + 每线白核 + 主轴白核）
 *   LOD 1: 2条交织（无底层泛光）
 *   LOD 2: 单条 + 白核（最简化）
 *
 * @author FlashNight
 * @version 3.0
 */
class org.flashNight.arki.render.renderer.SpectrumRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_THICKNESS:Number = 4;
    private static var DEFAULT_STRIPE_COUNT:Number = 3;             // 3条：高饱和度不糊白
    private static var DEFAULT_PALETTE_SCROLL_SPEED:Number = 30;    // 颜色流速
    private static var DEFAULT_DISTORT_AMP:Number = 10;             // 大振幅：色条间留出镂空
    private static var DEFAULT_DISTORT_WAVE_LEN:Number = 300;       // 长波：优雅交织1~2次

    /** RA3 光谱专属调色板（精简为最纯净的冷色三原色） */
    private static var DEFAULT_PALETTE:Array = [
        0xFF00FF,  // 纯洋红 (Magenta)
        0x00FFFF,  // 亮青 (Cyan)
        0x0066FF   // 湛蓝 (Deep Blue)
    ];

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染光谱射线
     *
     * @param arc 电弧数据对象
     * @param lod 当前 LOD 等级 (0=高, 1=中, 2=低)
     * @param mc  目标 MovieClip
     */
    public static function render(arc:Object, lod:Number, mc:MovieClip):Void {
        var config:Object = arc.config;
        var meta:Object = arc.meta;
        var age:Number = arc.age;
        var VM:Function = RayVfxManager;

        // 解析配置参数
        var thickness:Number         = VM.cfgNum(config, "thickness", DEFAULT_THICKNESS);
        var stripeCount:Number       = VM.cfgNum(config, "stripeCount", DEFAULT_STRIPE_COUNT);
        var paletteScrollSpeed:Number = VM.cfgNum(config, "paletteScrollSpeed", DEFAULT_PALETTE_SCROLL_SPEED);

        // 振幅/波长保底：防止旧配置的小值导致退化为密集弹簧
        var distortAmp:Number = VM.cfgNum(config, "distortAmp", DEFAULT_DISTORT_AMP);
        if (distortAmp < 6) distortAmp = 8;

        var distortWaveLen:Number = VM.cfgNum(config, "distortWaveLen", DEFAULT_DISTORT_WAVE_LEN);
        if (distortWaveLen < 150) distortWaveLen = 250;

        var palette:Array = VM.cfgArr(config, "palette", DEFAULT_PALETTE);

        // 强度因子
        var intensity:Number = VM.cfgIntensity(meta);
        var baseThickness:Number = thickness * intensity;

        var isFork:Boolean = (meta != null && meta.segmentKind == "fork");

        // LOD 降级（上限 4 条，保证色条间镂空不糊白）
        var effectiveStripeCount:Number = Math.min(stripeCount, 4);
        if (lod >= 2) effectiveStripeCount = 1;
        else if (lod >= 1) effectiveStripeCount = 2;

        // 方向向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        var perpX:Number = -dy / dist;
        var perpY:Number =  dx / dist;

        // ★ 叠加混合
        mc.blendMode = "add";

        // 绝对笔直的中心轴线
        var straightPath:Array = RayVfxManager.straightPath(arc.startX, arc.startY, arc.endX, arc.endY);

        // ─────────────────────────────────────────────────────────────
        // 图层 1：底层有色泛光（仅 LOD 0）
        // ─────────────────────────────────────────────────────────────

        if (lod == 0) {
            var glowColor:Number = isFork
                ? palette[((meta.hitIndex != undefined) ? meta.hitIndex : 0) % palette.length]
                : 0x5500FF;
            // 深邃暗电紫外发光
            RayVfxManager.drawPath(mc, straightPath, glowColor, baseThickness * 6, 15);
            // 亮青内发光
            RayVfxManager.drawPath(mc, straightPath, 0x00FFFF, baseThickness * 2.5, 25);
        }

        // ─────────────────────────────────────────────────────────────
        // Fork 折射：单色 + 白核，提前返回
        // ─────────────────────────────────────────────────────────────

        if (isFork) {
            var hitIndex:Number = (meta.hitIndex != undefined) ? meta.hitIndex : 0;
            var singleColor:Number = palette[hitIndex % palette.length];

            var forkPath:Array = generateBraidedPath(
                arc, perpX, perpY, dist,
                distortAmp * 0.6, distortWaveLen * 1.5,
                age, 0, paletteScrollSpeed);
            RayVfxManager.drawPath(mc, forkPath, singleColor, baseThickness * 1.5, 60);
            RayVfxManager.drawPath(mc, forkPath, 0xFFFFFF, baseThickness * 0.4, 90);
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 图层 2：高能交织的彩色等离子游丝
        // ─────────────────────────────────────────────────────────────

        var scrollOffset:Number = Math.floor(age * paletteScrollSpeed / 10);
        var strandThickness:Number = baseThickness * 0.6;

        for (var i:Number = 0; i < effectiveStripeCount; i++) {
            var paletteIndex:Number = (lod >= 2)
                ? 0
                : ((i + scrollOffset) % palette.length);
            var color:Number = palette[paletteIndex];
            var phaseOffset:Number = (i / effectiveStripeCount) * Math.PI * 2;

            // 混沌注入：每条线的振幅和波长微量不同
            var currentAmp:Number = distortAmp * (0.8 + 0.3 * Math.sin(i * 137.5));
            var currentWaveLen:Number = distortWaveLen * (0.8 + 0.3 * Math.cos(i * 42.1));

            var strandPath:Array = generateBraidedPath(
                arc, perpX, perpY, dist,
                currentAmp, currentWaveLen,
                age, phaseOffset, paletteScrollSpeed);

            // 宽幅色彩外发光 + 实体色彩内管
            RayVfxManager.drawPath(mc, strandPath, color, strandThickness * 2.5, 30);
            RayVfxManager.drawPath(mc, strandPath, color, strandThickness * 1.0, 70);
            // 每根色带自带极细白核 → "多股实体激光拧结"的错觉
            RayVfxManager.drawPath(mc, strandPath, 0xFFFFFF, strandThickness * 0.3, 80);
        }

        // ─────────────────────────────────────────────────────────────
        // 图层 3：笔直主干极光轴心
        // ─────────────────────────────────────────────────────────────

        // 极淡青白内晕
        RayVfxManager.drawPath(mc, straightPath, 0xDDEEFF, baseThickness * 1.2, 50);
        // 纯白高光核心
        RayVfxManager.drawPath(mc, straightPath, 0xFFFFFF, baseThickness * 0.6, 100);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 路径生成
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成带独立相位偏移的螺旋缠绕路径
     *
     * 使用平顶包络（Flat-top Envelope）：中间90%保持等宽圆柱，
     * 仅在首尾 taperDist(30px) 内急速收束至零。
     * 自适应采样率确保长波短波都丝滑无锯齿。
     *
     * @param arc          电弧数据对象
     * @param perpX        垂直方向 X 分量
     * @param perpY        垂直方向 Y 分量
     * @param dist         射线总长度
     * @param amp          交织振幅（像素）
     * @param waveLen      交织波长（像素）
     * @param age          当前帧龄
     * @param phaseOffset  相位偏移（弧度）
     * @param speed        波动流速
     * @return             路径点数组
     */
    private static function generateBraidedPath(arc:Object, perpX:Number, perpY:Number,
                                                 dist:Number, amp:Number, waveLen:Number,
                                                 age:Number, phaseOffset:Number,
                                                 speed:Number):Array {
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;

        var points:Array = RayVfxManager.poolArr();

        // 自适应采样：每20px一段，最少15段 → 长波短波都丝滑
        var segmentCount:Number = Math.max(15, Math.ceil(dist / 20));
        var step:Number = 1.0 / segmentCount;

        // 平顶包络收束距离（首尾30px，不超过总长的45%）
        var taperDist:Number = 30;
        var taperRatio:Number = taperDist / dist;
        if (taperRatio > 0.45) taperRatio = 0.45;

        for (var i:Number = 0; i <= segmentCount; i++) {
            var t:Number = i * step;

            // 端点强制锁定
            if (t <= 0.001) {
                points.push(RayVfxManager.pt(arc.startX, arc.startY, 0.0));
            } else if (t >= 0.999) {
                points.push(RayVfxManager.pt(arc.endX, arc.endY, 1.0));
            } else {
                var baseX:Number = arc.startX + dx * t;
                var baseY:Number = arc.startY + dy * t;

                // 平顶包络：中间段=1.0，首尾taperDist内sin半周收束
                var envelope:Number = 1.0;
                if (t < taperRatio) {
                    envelope = Math.sin((t / taperRatio) * (Math.PI / 2));
                } else if (t > 1.0 - taperRatio) {
                    envelope = Math.sin(((1.0 - t) / taperRatio) * (Math.PI / 2));
                }

                // 波动公式：空间频率 - 时间流动(加速) + 独立相位
                var waveAngle:Number = (t * dist / waveLen) * Math.PI * 2
                    - (age * speed * 0.05)
                    + phaseOffset;
                var offset:Number = amp * envelope * Math.sin(waveAngle);

                points.push(RayVfxManager.pt(
                    baseX + perpX * offset,
                    baseY + perpY * offset, t));
            }
        }

        return points;
    }
}
