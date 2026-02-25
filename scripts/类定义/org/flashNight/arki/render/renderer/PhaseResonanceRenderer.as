import org.flashNight.arki.render.RayVfxManager;

/**
 * PhaseResonanceRenderer - 相位谐振波渲染器
 *
 * 密集多频相位缠绕的高能射线，核心特征：
 * • 短波密织：短波长(80px)产生密集DNA螺旋般的缠绕交织
 * • 多股叠加：5条霓虹色光带在狭窄振幅内高频穿插
 * • 纺锤包络：pow(sin(t*PI), 0.8) 确保端点紧实收束
 * • 叠加混合：blendMode="add"，多线交汇处自动过曝
 * • 冷色霓虹：洋红/亮青/电紫/湛蓝/亮粉五色轮转
 * • 三明治分层：底层有色泛光 -> 中层交织光谱 -> 顶层纯白核心
 *
 * 与 SpectrumRenderer（长波优雅交织）互为对照：
 *   SpectrumRenderer = 长波 + 少量线 + 平顶等宽（RA3致敬）
 *   PhaseResonanceRenderer = 短波 + 多线 + 纺锤包络（谐振态）
 *
 * LOD 降级效果：
 *   LOD 0: 全特效（底层双色泛光 + 全量交织条纹 + 白核）
 *   LOD 1: 条纹数x0.6（无底层泛光）
 *   LOD 2: 双股螺旋 + 白核（无底层泛光）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.renderer.PhaseResonanceRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_THICKNESS:Number = 4;
    private static var DEFAULT_STRIPE_COUNT:Number = 5;             // 5条螺旋视觉最饱满
    private static var DEFAULT_PALETTE_SCROLL_SPEED:Number = 30;    // 颜色流速
    private static var DEFAULT_DISTORT_AMP:Number = 8;              // 交织振幅（像素）
    private static var DEFAULT_DISTORT_WAVE_LEN:Number = 80;        // 交织波长（像素）

    /** 相位谐振专属调色板（高能冷色系） */
    private static var DEFAULT_PALETTE:Array = [
        0xFF00FF,  // 洋红 (Magenta)
        0x00FFFF,  // 亮青 (Cyan)
        0x8800FF,  // 亮紫 (Purple)
        0x0088FF,  // 湛蓝 (Deep Blue)
        0xFF66FF   // 亮粉 (Pink)
    ];

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染相位谐振波射线
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
        var thickness:Number = (config != null && !isNaN(config.thickness))
            ? config.thickness : DEFAULT_THICKNESS;
        var stripeCount:Number = (config != null && !isNaN(config.stripeCount))
            ? config.stripeCount : DEFAULT_STRIPE_COUNT;
        var paletteScrollSpeed:Number = (config != null && !isNaN(config.paletteScrollSpeed))
            ? config.paletteScrollSpeed : DEFAULT_PALETTE_SCROLL_SPEED;
        var distortAmp:Number = (config != null && !isNaN(config.distortAmp))
            ? config.distortAmp : DEFAULT_DISTORT_AMP;
        var distortWaveLen:Number = (config != null && !isNaN(config.distortWaveLen))
            ? config.distortWaveLen : DEFAULT_DISTORT_WAVE_LEN;
        var palette:Array = (config != null && config.palette != null)
            ? config.palette : DEFAULT_PALETTE;

        // 强度因子（由生命周期系统驱动）
        var intensity:Number = (meta != null && !isNaN(meta.intensity)) ? meta.intensity : 1.0;
        var baseThickness:Number = thickness * intensity;

        var isFork:Boolean = (meta != null && meta.segmentKind == "fork");

        // LOD 降级：调整条纹数
        var effectiveStripeCount:Number = stripeCount;
        if (lod >= 2) {
            effectiveStripeCount = 2;
        } else if (lod >= 1) {
            effectiveStripeCount = Math.max(2, Math.floor(stripeCount * 0.6));
        }

        // 方向向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        var perpX:Number = -dy / dist;
        var perpY:Number =  dx / dist;

        // 叠加混合 -- 光束交汇处自动过曝泛白
        mc.blendMode = "add";

        // 绝对笔直的中心轴线（用于核心高光和底层泛光）
        var straightPath:Array = RayVfxManager.straightPath(arc.startX, arc.startY, arc.endX, arc.endY);

        // ─────────────────────────────────────────────────────────────
        // 图层 1：底层有色泛光（营造冷色光污染氛围，仅 LOD 0）
        // ─────────────────────────────────────────────────────────────

        if (lod == 0) {
            var glowColor:Number = isFork
                ? palette[((meta.hitIndex != undefined) ? meta.hitIndex : 0) % palette.length]
                : 0x8800FF;
            // 超宽暗紫外发光
            RayVfxManager.drawPath(mc, straightPath, glowColor, baseThickness * 7, 12);
            // 稍亮的青色内发光
            RayVfxManager.drawPath(mc, straightPath, 0x00FFFF, baseThickness * 3.5, 20);
        }

        // ─────────────────────────────────────────────────────────────
        // Fork 折射：单色交织 + 白核，提前返回
        // ─────────────────────────────────────────────────────────────

        if (isFork) {
            var hitIndex:Number = (meta.hitIndex != undefined) ? meta.hitIndex : 0;
            var singleColor:Number = palette[hitIndex % palette.length];

            // 单一频率的交织波形（振幅减半）
            var forkPath:Array = generateResonancePath(
                arc, perpX, perpY, dist,
                distortAmp * 0.5, distortWaveLen, age, 0, paletteScrollSpeed);
            RayVfxManager.drawPath(mc, forkPath, singleColor, baseThickness * 1.5, 60);
            RayVfxManager.drawPath(mc, straightPath, 0xFFFFFF, baseThickness * 0.6, 100);
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 图层 2：中层多条独立缠绕的彩色光谱
        // ─────────────────────────────────────────────────────────────

        var scrollOffset:Number = Math.floor(age * paletteScrollSpeed / 10);
        var strandThickness:Number = baseThickness * 0.8;

        for (var i:Number = 0; i < effectiveStripeCount; i++) {
            // 调色板颜色（LOD 2 退化为首尾两色）
            var paletteIndex:Number = (lod >= 2)
                ? ((i == 0) ? 0 : 3)
                : ((i + scrollOffset) % palette.length);
            var color:Number = palette[paletteIndex];

            // 每根线的独立相位差：均匀分布在 2PI 圆周上 -> 螺旋交织
            var phaseOffset:Number = (i / effectiveStripeCount) * Math.PI * 2;

            // 黄金角振幅变化，打破规则性
            var currentAmp:Number = distortAmp * (0.7 + 0.3 * Math.sin(i * 137.5));

            var strandPath:Array = generateResonancePath(
                arc, perpX, perpY, dist,
                currentAmp, distortWaveLen, age, phaseOffset, paletteScrollSpeed);

            // 双层绘制：模糊外发光 + 实心线
            RayVfxManager.drawPath(mc, strandPath, color, strandThickness * 2, 35);
            RayVfxManager.drawPath(mc, strandPath, color, strandThickness, 80);
        }

        // ─────────────────────────────────────────────────────────────
        // 图层 3：笔直纯白能量核心（致盲过曝感）
        // ─────────────────────────────────────────────────────────────

        // 极淡青白内晕
        RayVfxManager.drawPath(mc, straightPath, 0xDDEEFF, baseThickness * 1.5, 60);
        // 纯白高光核心
        RayVfxManager.drawPath(mc, straightPath, 0xFFFFFF, baseThickness * 0.5, 100);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 路径生成
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成带独立相位偏移的谐振缠绕路径
     *
     * 短波长 + 多线相位偏移产生密集 DNA 螺旋交织。
     * 纺锤包络 pow(sin(t*PI), 0.8) 确保端点紧实收束。
     *
     * @param arc          电弧数据对象
     * @param perpX        垂直方向 X 分量
     * @param perpY        垂直方向 Y 分量
     * @param dist         射线总长度
     * @param amp          交织振幅（像素）
     * @param waveLen      交织波长（像素）
     * @param age          当前帧龄
     * @param phaseOffset  相位偏移（弧度），区分不同线条
     * @param speed        颜色/波动流速
     * @return             路径点数组
     */
    private static function generateResonancePath(arc:Object, perpX:Number, perpY:Number,
                                                 dist:Number, amp:Number, waveLen:Number,
                                                 age:Number, phaseOffset:Number,
                                                 speed:Number):Array {
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;

        var points:Array = RayVfxManager.poolArr();

        // 细分段数：每 25px 一段，保证交汇点平滑
        var segmentCount:Number = Math.max(8, Math.ceil(dist / 25));
        var step:Number = 1.0 / segmentCount;

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

                // 纺锤包络：pow 指数 < 1 使端点收束更紧实
                var envelope:Number = Math.pow(Math.sin(t * Math.PI), 0.8);

                // 波动公式：空间频率 - 时间流动 + 独立相位
                var waveAngle:Number = (t * dist / waveLen) * Math.PI * 2
                    - (age * speed * 0.015)
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
