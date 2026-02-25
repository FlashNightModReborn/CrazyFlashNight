import org.flashNight.arki.render.RayVfxManager;
import org.flashNight.arki.render.renderer.RenderColorUtil;

/**
 * PrismRenderer - 光棱射线渲染器 (RA2 致敬版 v3)
 *
 * 致敬红警2光棱塔的视觉风格，核心设计原则：
 * • 绝对笔直：激光沿直线传播，无任何空间弯曲
 * • 叠加混合：blendMode="add"，多束交叠自然爆白致盲
 * • 能量频闪：shimmerAmp 控制粗细/亮度的高频随机脉冲（非路径抖动）
 * • 三层光学：外晕(主色) → 过渡护套(副色) → 白热内核(纯白,加粗)
 * • 棱镜色散：概率性伴生极细折射微光（LOD 0 主射线专属）
 * • 端点耀斑：锐化径向渐变，模拟枪口闪焰与命中高光
 * • fork 色偏：折射线更细 + 色相偏移（模拟棱镜色散）
 *
 * LOD 降级效果：
 *   LOD 0: 全特效（三层 + 色散伴生 + 耀斑 + 频闪）
 *   LOD 1: 三层 + 频闪（无色散伴生，无耀斑）
 *   LOD 2: 双层简化（主色 + 白核，无频闪）
 *
 * @author FlashNight
 * @version 3.0
 */
class org.flashNight.arki.render.renderer.PrismRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY_COLOR:Number   = 0xFFFF00;   // 纯正亮黄（RA2原版）
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFFFAA;   // 淡黄过渡（preset 可覆盖为白）
    private static var DEFAULT_THICKNESS:Number       = 3;
    private static var DEFAULT_SHIMMER_AMP:Number     = 0.25;       // 频闪幅度（控制粗细/亮度脉冲）
    private static var DEFAULT_FORK_THICKNESS_MUL:Number = 0.6;     // 折射线粗细倍率
    private static var DEFAULT_FLARE_RADIUS_MUL:Number   = 4.5;    // 耀斑半径 = 粗细 × 此倍率

    // 贝塞尔画圆常量：tan(π/8) 和 sin(π/4)
    private static var KAPPA:Number = 0.414213562;
    private static var DIAG:Number  = 0.707106781;

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
        var VM:Function = RayVfxManager;

        // ★ 叠加混合 ── 光棱塔的灵魂，多束交叠处自然爆白致盲
        mc.blendMode = "add";

        // 解析配置参数
        var primaryColor:Number   = VM.cfgNum(config, "primaryColor", DEFAULT_PRIMARY_COLOR);
        var secondaryColor:Number = VM.cfgNum(config, "secondaryColor", DEFAULT_SECONDARY_COLOR);
        var baseThickness:Number  = VM.cfgNum(config, "thickness", DEFAULT_THICKNESS);
        var shimmerAmp:Number     = VM.cfgNum(config, "shimmerAmp", DEFAULT_SHIMMER_AMP);
        var forkThicknessMul:Number = VM.cfgNum(config, "forkThicknessMul", DEFAULT_FORK_THICKNESS_MUL);

        // 强度因子（由生命周期系统驱动）
        var intensity:Number = VM.cfgIntensity(meta);

        // 折射线处理
        var isFork:Boolean = (meta != null && meta.segmentKind == "fork");
        if (isFork) {
            baseThickness *= forkThicknessMul;
            // 色相偏移（模拟棱镜色散）
            primaryColor = shiftHue(primaryColor, 15);
            secondaryColor = shiftHue(secondaryColor, 15);
        }

        // 方向向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        // ★ 核心1：能量频闪 ── shimmerAmp 控制粗细/亮度的随机脉冲
        //   模拟高能光束的不稳定输出（"滋滋"感），而非路径弯曲
        var pulse:Number = 1.0;
        if (lod < 2) {
            pulse = 1.0 + (Math.random() * 2 - 1) * shimmerAmp;
        }

        // 光束粗细随生命周期收束，主要靠 alpha 衰减
        var currentAlpha:Number = intensity * pulse;
        var currentThick:Number = baseThickness * (0.6 + 0.4 * intensity) * pulse;

        // ★ 核心2：绝对笔直的路径 ── 激光沿直线传播，无空间弯曲
        //   仅首尾两点连线，还原激光质感并大幅降低 CPU 负担
        var mainPath:Array = RayVfxManager.straightPath(arc.startX, arc.startY, arc.endX, arc.endY);

        // ─────────────────────────────────────────────────────────────
        // 三层光学渲染
        // ─────────────────────────────────────────────────────────────

        if (lod < 2) {
            // Layer 1: 环境外晕（极宽，低透明度，主色辉光）
            RayVfxManager.drawPath(mc, mainPath, primaryColor, currentThick * 4.5, 20 * currentAlpha);

            // Layer 2: 能量护套（中等宽度，副色过渡层，增加光学层次感）
            RayVfxManager.drawPath(mc, mainPath, secondaryColor, currentThick * 2.0, 60 * currentAlpha);

            // ★ 核心3：白热内核（0.8x 加粗！叠加爆白的关键）
            RayVfxManager.drawPath(mc, mainPath, 0xFFFFFF, currentThick * 0.8, 100 * currentAlpha);

            // ★ 核心4：棱镜色散伴生光束（LOD 0 主射线专属）
            //   模拟高能光穿透棱镜时的细微光学溢出
            if (lod == 0 && !isFork && Math.random() > 0.4) {
                var perpX:Number = -dy / dist;
                var perpY:Number =  dx / dist;
                var strandsNum:Number = (Math.random() > 0.5) ? 2 : 1;

                for (var i:Number = 0; i < strandsNum; i++) {
                    var strandPath:Array = RayVfxManager.poolArr();
                    // 终端点微量横向偏移，伴生光从同一起点散射出去
                    var offset:Number = (Math.random() * 2 - 1) * currentThick * 1.5;

                    strandPath.push(RayVfxManager.pt(arc.startX, arc.startY, 0.0));
                    strandPath.push(RayVfxManager.pt(
                        arc.endX + perpX * offset,
                        arc.endY + perpY * offset, 1.0));

                    RayVfxManager.drawPath(mc, strandPath, secondaryColor,
                        currentThick * 0.25, 60 * currentAlpha);
                }
            }
        } else {
            // LOD 2：双层简化（无频闪，无色散）
            RayVfxManager.drawPath(mc, mainPath, primaryColor, baseThickness * 2.0, 80 * intensity);
            RayVfxManager.drawPath(mc, mainPath, 0xFFFFFF, baseThickness * 0.6, 100 * intensity);
        }

        // ─────────────────────────────────────────────────────────────
        // 端点耀斑（仅 LOD 0）
        // ─────────────────────────────────────────────────────────────

        if (lod < 1) {
            var flareR:Number = currentThick * DEFAULT_FLARE_RADIUS_MUL;
            // 枪口耀斑（较小）
            drawFlare(mc, arc.startX, arc.startY, flareR * 0.6, primaryColor, currentAlpha);
            // 命中点耀斑（较大，脉冲同步爆闪）
            drawFlare(mc, arc.endX, arc.endY, flareR * 1.3, secondaryColor, currentAlpha);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 端点耀斑
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 绘制锐化能量耀斑（径向渐变圆）
     *
     * 中心纯白 → 边缘主色 → 透明。
     * ratios [0, 40, 255] 使白心区域更集中、打击感更硬朗。
     *
     * @param mc          目标 MovieClip
     * @param x           耀斑中心 X
     * @param y           耀斑中心 Y
     * @param radius      耀斑半径
     * @param color       边缘色
     * @param alphaFactor 透明度因子 (0~1)
     */
    private static function drawFlare(mc:MovieClip, x:Number, y:Number,
                                       radius:Number, color:Number, alphaFactor:Number):Void {
        mc.lineStyle(undefined);

        // 径向渐变：中心白 → 边缘主色 → 透明（锐化版）
        var alphas:Array = [100 * alphaFactor, 60 * alphaFactor, 0];
        var colors:Array = [0xFFFFFF, color, color];
        var ratios:Array = [0, 40, 255];
        var matrix:Object = {
            matrixType: "box",
            x: x - radius, y: y - radius,
            w: radius * 2, h: radius * 2, r: 0
        };

        mc.beginGradientFill("radial", colors, alphas, ratios, matrix);

        // 8 段贝塞尔近似圆
        var a:Number = radius * KAPPA;
        var b:Number = radius * DIAG;
        mc.moveTo(x + radius, y);
        mc.curveTo(x + radius, y + a, x + b, y + b);
        mc.curveTo(x + a, y + radius, x, y + radius);
        mc.curveTo(x - a, y + radius, x - b, y + b);
        mc.curveTo(x - radius, y + a, x - radius, y);
        mc.curveTo(x - radius, y - a, x - b, y - b);
        mc.curveTo(x - a, y - radius, x, y - radius);
        mc.curveTo(x + a, y - radius, x + b, y - b);
        mc.curveTo(x + radius, y - a, x + radius, y);
        mc.endFill();
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
        return RenderColorUtil.shiftHue(color, degrees);
    }
}
