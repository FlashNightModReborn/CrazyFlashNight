import org.flashNight.arki.render.RayVfxManager;

/**
 * SpectrumRenderer - 光谱射线渲染器
 *
 * 致敬红警3光谱塔的视觉风格，核心特征：
 * • 彩虹渐变：多条平行线模拟连续色谱
 * • 颜色滚动：调色板随时间循环偏移，产生流动感
 * • 轻微波形：低幅度正弦抖动增加动态感
 * • fork 单色：折射线取调色板单色，模拟棱镜色散
 *
 * 渲染策略（AS2 友好）：
 *   使用多条平行线（stripeCount 条）模拟渐变，避免 Bitmap 贴图的复杂度。
 *   每条线的颜色从调色板取值，并按 age 滚动偏移。
 *
 * LOD 降级效果：
 *   LOD 0: 全特效（全量条纹 + 颜色滚动 + 波形）
 *   LOD 1: 条纹数减半
 *   LOD 2: 退化为双色渐变（首尾两色）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.renderer.SpectrumRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_THICKNESS:Number = 4;
    private static var DEFAULT_STRIPE_COUNT:Number = 7;
    private static var DEFAULT_PALETTE_SCROLL_SPEED:Number = 20;
    private static var DEFAULT_DISTORT_AMP:Number = 3;
    private static var DEFAULT_DISTORT_WAVE_LEN:Number = 60;

    /** 默认彩虹调色板 */
    private static var DEFAULT_PALETTE:Array = [
        0xFF0000,  // 红
        0xFF8800,  // 橙
        0xFFFF00,  // 黄
        0x00FF00,  // 绿
        0x00FFFF,  // 青
        0x0088FF,  // 蓝
        0x8800FF   // 紫
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

        // 解析配置参数
        var thickness:Number = (config != null && !isNaN(config.thickness)) ? config.thickness : DEFAULT_THICKNESS;
        var stripeCount:Number = (config != null && !isNaN(config.stripeCount)) ? config.stripeCount : DEFAULT_STRIPE_COUNT;
        var paletteScrollSpeed:Number = (config != null && !isNaN(config.paletteScrollSpeed)) ? config.paletteScrollSpeed : DEFAULT_PALETTE_SCROLL_SPEED;
        var distortAmp:Number = (config != null && !isNaN(config.distortAmp)) ? config.distortAmp : DEFAULT_DISTORT_AMP;
        var distortWaveLen:Number = (config != null && !isNaN(config.distortWaveLen)) ? config.distortWaveLen : DEFAULT_DISTORT_WAVE_LEN;

        // 获取调色板
        var palette:Array = (config != null && config.palette != null) ? config.palette : DEFAULT_PALETTE;

        // 应用 intensity 强度因子
        var intensity:Number = (meta != null && !isNaN(meta.intensity)) ? meta.intensity : 1.0;
        thickness *= intensity;

        // 判断是否为折射线
        var isFork:Boolean = (meta != null && meta.segmentKind == "fork");

        // LOD 降级调整
        var effectiveStripeCount:Number = stripeCount;
        var useSingleColor:Boolean = false;
        if (lod >= 2) {
            // LOD 2: 退化为双色
            effectiveStripeCount = 2;
        } else if (lod >= 1) {
            // LOD 1: 条纹数减半
            effectiveStripeCount = Math.max(2, Math.floor(stripeCount * 0.5));
        }

        // 计算电弧方向向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        // 垂直方向向量
        var perpX:Number = -dy / dist;
        var perpY:Number = dx / dist;

        // 生成基础路径（带波形抖动）
        var basePath:Array = generateSpectrumPath(arc, perpX, perpY, dist, distortAmp, distortWaveLen, age);

        // 计算条纹宽度
        var totalWidth:Number = thickness * 3;  // 光束总宽度
        var stripeWidth:Number = totalWidth / effectiveStripeCount;

        // ─────────────────────────────────────────────────────────────
        // 绘制外层光晕
        // ─────────────────────────────────────────────────────────────
        RayVfxManager.drawPath(mc, basePath, 0xFFFFFF, thickness * 6, 15);

        // ─────────────────────────────────────────────────────────────
        // fork 折射：取单色
        // ─────────────────────────────────────────────────────────────
        if (isFork) {
            // 根据 hitIndex 取调色板颜色作为固定单色（无需 totalHits）
            var hitIndex:Number = (meta.hitIndex != undefined) ? meta.hitIndex : 0;
            var singleColor:Number = palette[hitIndex % palette.length];

            // 绘制单色光束
            RayVfxManager.drawPath(mc, basePath, singleColor, thickness * 2, 85);
            RayVfxManager.drawPath(mc, basePath, 0xFFFFFF, thickness * 0.5, 100);
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 绘制多条平行彩虹条纹
        // ─────────────────────────────────────────────────────────────
        var scrollOffset:Number = Math.floor(age * paletteScrollSpeed / 10);

        for (var i:Number = 0; i < effectiveStripeCount; i++) {
            // 计算该条纹的偏移量（垂直于束方向）
            var offset:Number = (i - (effectiveStripeCount - 1) / 2) * stripeWidth;

            // 计算该条纹的颜色（调色板滚动）
            var paletteIndex:Number;
            if (lod >= 2) {
                // LOD 2: 仅首尾两色
                paletteIndex = (i == 0) ? 0 : palette.length - 1;
            } else {
                // 正常滚动
                paletteIndex = (i + scrollOffset) % palette.length;
            }
            var color:Number = palette[paletteIndex];

            // 生成偏移路径
            var offsetPath:Array = generateOffsetPath(basePath, perpX, perpY, offset);

            // 绘制该条纹
            RayVfxManager.drawPath(mc, offsetPath, color, stripeWidth, 80);
        }

        // 绘制白色高光中心线
        RayVfxManager.drawPath(mc, basePath, 0xFFFFFF, thickness * 0.3, 100);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 路径生成
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成光谱基础路径（直线 + 波形抖动）
     *
     * @param arc           电弧数据对象
     * @param perpX         垂直方向 X 分量
     * @param perpY         垂直方向 Y 分量
     * @param dist          射线总长度
     * @param distortAmp    波形抖动幅度
     * @param distortWaveLen 波形抖动波长
     * @param age           当前帧龄
     * @return              路径点数组
     */
    private static function generateSpectrumPath(arc:Object, perpX:Number, perpY:Number,
                                                   dist:Number, distortAmp:Number, distortWaveLen:Number,
                                                   age:Number):Array {
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;

        var points:Array = RayVfxManager.poolArr();

        // 分段数
        var segmentCount:Number = Math.max(5, Math.ceil(dist / 50));
        var step:Number = 1.0 / segmentCount;

        for (var i:Number = 0; i <= segmentCount; i++) {
            var t:Number = i * step;

            // 基础坐标
            var baseX:Number = arc.startX + dx * t;
            var baseY:Number = arc.startY + dy * t;

            // 计算波形偏移
            var offset:Number = 0;
            if (t > 0.001 && t < 0.999) {
                // 纺锤包络
                var envelope:Number = Math.sin(t * Math.PI);
                // 波形抖动（使用 t × dist 确保像素尺度）
                offset = distortAmp * envelope * Math.sin((t * dist / distortWaveLen + age * 0.1) * 2 * Math.PI);
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
     * 生成偏移路径（将基础路径沿垂直方向偏移）
     *
     * @param basePath 基础路径
     * @param perpX    垂直方向 X 分量
     * @param perpY    垂直方向 Y 分量
     * @param offset   偏移量
     * @return         偏移后的路径点数组
     */
    private static function generateOffsetPath(basePath:Array, perpX:Number, perpY:Number, offset:Number):Array {
        var points:Array = RayVfxManager.poolArr();

        for (var i:Number = 0; i < basePath.length; i++) {
            var p:Object = basePath[i];
            points.push(RayVfxManager.pt(p.x + perpX * offset, p.y + perpY * offset, p.t));
        }

        return points;
    }
}
