import org.flashNight.arki.render.RayVfxManager;

/**
 * PrismRenderer - 光棱射线渲染器
 *
 * 致敬红警2光棱塔的视觉风格，核心特征：
 * • 稳定直束：极低抖动，保持几何锐利感
 * • 三层渲染：外晕 → 主束 → 白热内核
 * • 呼吸动画：低频正弦波调制亮度/粗细
 * • fork 色偏：折射线更细 + 轻微色相偏移（模拟棱镜色散）
 *
 * 路径生成原理：
 *   沿垂直于束方向做低频正弦微扰，而非 Tesla 的随机锯齿：
 *   offset = shimmerAmp × sin(age × shimmerFreq × 2π) × sin(t × π)
 *
 * LOD 降级效果：
 *   LOD 0: 全特效（呼吸动画 + 三层渲染）
 *   LOD 1: 取消呼吸动画
 *   LOD 2: 单层渲染（仅主束）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.renderer.PrismRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY_COLOR:Number = 0xFFDD00;    // 金黄色
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFFFAA;  // 淡黄高光
    private static var DEFAULT_THICKNESS:Number = 3;
    private static var DEFAULT_SHIMMER_AMP:Number = 0.1;           // 呼吸幅度
    private static var DEFAULT_SHIMMER_FREQ:Number = 0.5;          // 呼吸频率
    private static var DEFAULT_FORK_THICKNESS_MUL:Number = 0.7;    // 折射线粗细倍率

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染光棱射线
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
        var shimmerAmp:Number = (config != null && !isNaN(config.shimmerAmp)) ? config.shimmerAmp : DEFAULT_SHIMMER_AMP;
        var shimmerFreq:Number = (config != null && !isNaN(config.shimmerFreq)) ? config.shimmerFreq : DEFAULT_SHIMMER_FREQ;
        var forkThicknessMul:Number = (config != null && !isNaN(config.forkThicknessMul)) ? config.forkThicknessMul : DEFAULT_FORK_THICKNESS_MUL;

        // 应用 intensity 强度因子
        var intensity:Number = (meta != null && !isNaN(meta.intensity)) ? meta.intensity : 1.0;
        thickness *= intensity;

        // 判断是否为折射线
        var isFork:Boolean = (meta != null && meta.segmentKind == "fork");
        if (isFork) {
            thickness *= forkThicknessMul;
            // 折射线色相偏移（模拟棱镜色散）
            primaryColor = shiftHue(primaryColor, 15);
        }

        // LOD 降级
        var enableShimmer:Boolean = (lod < 1);
        var fullLayers:Boolean = (lod < 2);

        // 计算电弧方向向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        // 垂直方向向量（用于微扰偏移）
        var perpX:Number = -dy / dist;
        var perpY:Number = dx / dist;

        // 生成路径（直线 + 低频正弦微扰）
        var path:Array = generatePrismPath(arc, perpX, perpY, dist, shimmerAmp, shimmerFreq, age, enableShimmer);

        // 计算呼吸动画的亮度调制
        var breathFactor:Number = 1.0;
        if (enableShimmer) {
            breathFactor = 1.0 + shimmerAmp * Math.sin(age * shimmerFreq * 2 * Math.PI);
        }

        // ─────────────────────────────────────────────────────────────
        // 三层渲染
        // ─────────────────────────────────────────────────────────────

        if (fullLayers) {
            // Layer 1: 外晕（宽域泛光）
            var alpha1:Number = Math.min(100, 20 * breathFactor);
            RayVfxManager.drawPath(mc, path, primaryColor, thickness * 5.0, alpha1);

            // Layer 2: 主束
            var alpha2:Number = Math.min(100, 90 * breathFactor);
            RayVfxManager.drawPath(mc, path, primaryColor, thickness * 1.5, alpha2);

            // Layer 3: 白热内核
            RayVfxManager.drawPath(mc, path, secondaryColor, thickness * 0.5, 100);
        } else {
            // LOD 2: 单层渲染（仅主束）
            RayVfxManager.drawPath(mc, path, primaryColor, thickness * 1.5, 90);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 路径生成
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成光棱路径（直线 + 低频正弦微扰）
     *
     * 微扰沿垂直于束方向偏移，而非全局 y，确保任意角度下表现一致。
     *
     * @param arc         电弧数据对象
     * @param perpX       垂直方向 X 分量
     * @param perpY       垂直方向 Y 分量
     * @param dist        射线总长度
     * @param shimmerAmp  呼吸幅度
     * @param shimmerFreq 呼吸频率
     * @param age         当前帧龄
     * @param enableShimmer 是否启用呼吸动画
     * @return            路径点数组
     */
    private static function generatePrismPath(arc:Object, perpX:Number, perpY:Number,
                                               dist:Number, shimmerAmp:Number, shimmerFreq:Number,
                                               age:Number, enableShimmer:Boolean):Array {
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;

        var points:Array = RayVfxManager.poolArr();

        // 分段数（光棱使用较少分段，保持直线感）
        var segmentCount:Number = Math.max(3, Math.ceil(dist / 100));
        var step:Number = 1.0 / segmentCount;

        for (var i:Number = 0; i <= segmentCount; i++) {
            var t:Number = i * step;

            // 基础坐标
            var baseX:Number = arc.startX + dx * t;
            var baseY:Number = arc.startY + dy * t;

            // 计算微扰偏移
            var offset:Number = 0;
            if (enableShimmer && t > 0.001 && t < 0.999) {
                // 纺锤包络 + 呼吸动画
                var envelope:Number = Math.sin(t * Math.PI);
                offset = shimmerAmp * 10 * envelope * Math.sin(age * shimmerFreq * 2 * Math.PI);
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

    // ════════════════════════════════════════════════════════════════════════
    // 颜色处理
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 色相偏移（模拟棱镜色散）
     *
     * @param color     原始颜色 (0xRRGGBB)
     * @param degrees   偏移角度 (-180 ~ 180)
     * @return          偏移后的颜色
     */
    private static function shiftHue(color:Number, degrees:Number):Number {
        // 提取 RGB
        var r:Number = (color >> 16) & 0xFF;
        var g:Number = (color >> 8) & 0xFF;
        var b:Number = color & 0xFF;

        // RGB to HSV
        var max:Number = Math.max(r, Math.max(g, b));
        var min:Number = Math.min(r, Math.min(g, b));
        var delta:Number = max - min;

        var h:Number = 0;
        var s:Number = (max == 0) ? 0 : delta / max;
        var v:Number = max / 255;

        if (delta > 0) {
            if (max == r) {
                h = 60 * (((g - b) / delta) % 6);
            } else if (max == g) {
                h = 60 * ((b - r) / delta + 2);
            } else {
                h = 60 * ((r - g) / delta + 4);
            }
        }
        if (h < 0) h += 360;

        // 偏移色相
        h = (h + degrees) % 360;
        if (h < 0) h += 360;

        // HSV to RGB
        var c:Number = v * s;
        var x:Number = c * (1 - Math.abs((h / 60) % 2 - 1));
        var m:Number = v - c;

        var r1:Number, g1:Number, b1:Number;
        if (h < 60) {
            r1 = c; g1 = x; b1 = 0;
        } else if (h < 120) {
            r1 = x; g1 = c; b1 = 0;
        } else if (h < 180) {
            r1 = 0; g1 = c; b1 = x;
        } else if (h < 240) {
            r1 = 0; g1 = x; b1 = c;
        } else if (h < 300) {
            r1 = x; g1 = 0; b1 = c;
        } else {
            r1 = c; g1 = 0; b1 = x;
        }

        var newR:Number = Math.round((r1 + m) * 255);
        var newG:Number = Math.round((g1 + m) * 255);
        var newB:Number = Math.round((b1 + m) * 255);

        return (newR << 16) | (newG << 8) | newB;
    }
}
