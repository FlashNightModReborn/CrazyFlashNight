import org.flashNight.arki.render.RayVfxManager;

/**
 * BaguaRodRenderer - 八门金锁束流渲染器 (镇暴霰弹专用)
 *
 * 视觉概念:
 *   • 8 切片横向压缩堆叠, 八边形截面 + 4 主对角 (减为 2 条)
 *   • 暖白 + 深石墨二极配色 (避开黑场吞噬)
 *   • 偶/奇切片反向自旋 → DNA 双螺旋意象
 *   • 黑白分界沿对角旋进 (太极动态平衡)
 *   • 律动脉冲沿轴从源头传到末端 (尺寸 + α 双调制)
 *   • 中枢贯穿线 + 切片间 8 顶点连杆
 *   • 暖白半边外发光描边
 *
 * Python 原型参考: tools/ray-vfx-prototype/八门金锁_视觉原型.py (v4 锁定)
 *
 * 渲染分层:
 *   L0: 中枢贯穿线 (深金, α 跟随律动峰值)
 *   L1: 切片间纵向连杆 (按顶点黑/白染色, α 取两端较小值)
 *   L2: 外发光描边 (仅暖白半边, 厚低 α)
 *   L3: 切片外轮廓 8 边
 *   L4: 切片内部主对角 2 条
 *
 * LOD 降级:
 *   LOD 0: 全特效
 *   LOD 1: 关闭外发光描边 (省 8 条厚线/切片)
 *   LOD 2: 关闭内部对角与切片间连杆 (仅保留中枢 + 外轮廓)
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.renderer.BaguaRodRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置 (与 TeslaRayConfig/VfxPresets 同步, 仅作 null-config fallback)
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY:Number       = 0xFFE5C4;  // 暖白 (阳极)
    private static var DEFAULT_DARK:Number          = 0x36404A;  // 深石墨 (阴极)
    private static var DEFAULT_MIXED:Number         = 0x7A6F66;  // 跨界中性
    private static var DEFAULT_SPINE:Number         = 0xFFB347;  // 深金中枢
    private static var DEFAULT_THICKNESS:Number     = 1.8;
    private static var DEFAULT_SLICES:Number        = 8;
    private static var DEFAULT_SLICE_SPACING:Number = 90;
    private static var DEFAULT_SLICE_RADIUS:Number  = 35;
    private static var DEFAULT_COMPRESS_X:Number    = 0.5;
    private static var DEFAULT_ANG_VEL:Number       = 15;
    private static var DEFAULT_PHASE_OFFSET:Number  = 22.5;
    private static var DEFAULT_PULSE_AMP:Number     = 0.55;
    private static var DEFAULT_PULSE_WIDTH:Number   = 2.5;
    private static var DEFAULT_IDLE_ALPHA:Number    = 10;    // 0-100
    private static var DEFAULT_GLOW_ALPHA:Number    = 18;    // 0-100
    private static var DEFAULT_GLOW_WIDTH_MULT:Number = 4.5;
    private static var DEFAULT_N_DIAGONALS:Number   = 2;
    private static var DEFAULT_LINKER_STRIDE:Number = 1;
    private static var DEFAULT_VISUAL_DURATION:Number = 15;
    private static var DEFAULT_FADE_DURATION:Number   = 3;

    // 数学常量
    private static var DEG2RAD:Number     = 0.017453292519943295;  // π/180
    private static var EIGHTH_PI:Number   = 0.7853981633974483;    // π/4

    // 线条样式 (lineStyle 完整签名复用)
    // (thickness, color, alpha, pixelHinting, scaleMode, capsStyle, jointStyle, miterLimit)
    // 使用 round 线帽避免锯齿端点

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染八门金锁束流
     *
     * @param arc 电弧数据对象 {startX, startY, endX, endY, age, config, meta}
     * @param lod 当前 LOD 等级 (0=高, 1=中, 2=低)
     * @param mc  目标 MovieClip (已 clear)
     */
    public static function render(arc:Object, lod:Number, mc:MovieClip):Void {
        var config:Object = arc.config;
        var meta:Object   = arc.meta;
        var age:Number    = arc.age;
        var VM:Function   = RayVfxManager;

        // ─── 读取配置 ───
        var primaryColor:Number   = VM.cfgNum(config, "primaryColor",   DEFAULT_PRIMARY);
        var darkColor:Number      = VM.cfgNum(config, "secondaryColor", DEFAULT_DARK);
        var mixedColor:Number     = VM.cfgNum(config, "mixedColor",     DEFAULT_MIXED);
        var spineColor:Number     = VM.cfgNum(config, "spineColor",     DEFAULT_SPINE);
        var thickness:Number      = VM.cfgNum(config, "thickness",      DEFAULT_THICKNESS);
        var slicesCount:Number    = VM.cfgNum(config, "slicesCount",    DEFAULT_SLICES);
        var sliceSpacing:Number   = VM.cfgNum(config, "sliceSpacing",   DEFAULT_SLICE_SPACING);
        var sliceRadius:Number    = VM.cfgNum(config, "sliceRadius",    DEFAULT_SLICE_RADIUS);
        var sliceCompressX:Number = VM.cfgNum(config, "sliceCompressX", DEFAULT_COMPRESS_X);
        var angVelDeg:Number      = VM.cfgNum(config, "angVelDeg",      DEFAULT_ANG_VEL);
        var phaseOffsetDeg:Number = VM.cfgNum(config, "phaseOffsetDeg", DEFAULT_PHASE_OFFSET);
        var pulseAmp:Number       = VM.cfgNum(config, "pulseAmp",       DEFAULT_PULSE_AMP);
        var pulseWidth:Number     = VM.cfgNum(config, "pulseWidth",     DEFAULT_PULSE_WIDTH);
        var baseIdleAlpha:Number  = VM.cfgNum(config, "baseIdleAlpha",  DEFAULT_IDLE_ALPHA);
        var glowAlpha:Number      = VM.cfgNum(config, "glowAlpha",      DEFAULT_GLOW_ALPHA);
        var glowWidthMult:Number  = VM.cfgNum(config, "glowWidthMult",  DEFAULT_GLOW_WIDTH_MULT);
        var nDiagonals:Number     = VM.cfgNum(config, "nDiagonals",     DEFAULT_N_DIAGONALS);
        var linkerStride:Number   = VM.cfgNum(config, "linkerStride",   DEFAULT_LINKER_STRIDE);
        var visualDuration:Number = VM.cfgNum(config, "visualDuration", DEFAULT_VISUAL_DURATION);
        var fadeDuration:Number   = VM.cfgNum(config, "fadeOutDuration", DEFAULT_FADE_DURATION);
        var counterRotate:Boolean = (config != null && config.counterRotate === true);

        // ─── 计算 burst_frame 与 cycle_alpha (爆发→淡出二阶段) ───
        var burstFrame:Number;
        var cycleAlpha:Number;
        if (age < visualDuration) {
            burstFrame = age;
            cycleAlpha = 1.0;
        } else {
            burstFrame = visualDuration - 1;
            var fadeT:Number = (age - visualDuration) / (fadeDuration > 0 ? fadeDuration : 1);
            cycleAlpha = 1.0 - fadeT;
            if (cycleAlpha <= 0) return;
        }

        // ─── 强度因子 ───
        var intensity:Number = VM.cfgIntensity(meta);
        thickness   *= intensity;
        sliceRadius *= intensity;

        // ─── 射线方向 ───
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (!(dist > 0)) return;
        var dirX:Number = dx / dist;
        var dirY:Number = dy / dist;
        var perpX:Number = -dirY;
        var perpY:Number = dirX;

        // 加色混合
        mc.blendMode = "add";

        // ─── 切片中心位置 (沿 ray 方向; 间距优先, 超长则压缩) ───
        var stride:Number;
        var firstOffset:Number;
        var sliceCountM1:Number = slicesCount - 1;
        var stackLen:Number = sliceCountM1 * sliceSpacing;
        if (stackLen <= dist) {
            stride = sliceSpacing;
            firstOffset = (dist - stackLen) * 0.5;
        } else {
            stride = (sliceCountM1 > 0) ? (dist / sliceCountM1) : 0;
            firstOffset = 0;
        }

        // ─── 预计算切片几何 (顶点世界坐标 + 黑/白侧) ───
        // 数据结构: slicesCount × 8 顶点 = (x, y, side[Boolean]) 共 3 × 8 × N
        // 用扁平数组减少 Object 分配; 索引: slice_i × 24 + vertex_k × 3 + (0:x,1:y,2:side)
        var totalVerts:Number = slicesCount * 8;
        var vX:Array = new Array(totalVerts);
        var vY:Array = new Array(totalVerts);
        var vSide:Array = new Array(totalVerts);  // 1 = 暖白, 0 = 深石墨
        var sliceCenterX:Array = new Array(slicesCount);
        var sliceCenterY:Array = new Array(slicesCount);
        var sliceAlpha:Array   = new Array(slicesCount);
        var sliceRadiusArr:Array = new Array(slicesCount);
        var maxAlpha:Number = 0;

        var burstFramesM1:Number = (visualDuration > 1) ? (visualDuration - 1) : 1;
        var progress:Number = burstFrame / burstFramesM1;
        var pulseCenter:Number = -0.5 + progress * slicesCount;

        for (var i:Number = 0; i < slicesCount; i++) {
            var t:Number = firstOffset + i * stride;
            var cx:Number = arc.startX + dirX * t;
            var cy:Number = arc.startY + dirY * t;

            // 律动脉冲强度 (cosine bump)
            var pDist:Number = Math.abs(i - pulseCenter) / pulseWidth;
            var pIntensity:Number = 0;
            if (pDist < 1.0) {
                pIntensity = 0.5 * (1.0 + Math.cos(Math.PI * pDist));
            }

            var R:Number = sliceRadius * (1 + pulseAmp * pIntensity);
            // sliceAlphaI: 0-1 范围, 后续乘以 100 才是 AS2 lineStyle alpha
            var alphaI:Number = (baseIdleAlpha + (100 - baseIdleAlpha) * pIntensity) * 0.01;
            if (alphaI > maxAlpha) maxAlpha = alphaI;

            // 自旋
            var dir:Number = (counterRotate && (i % 2) == 1) ? -1 : 1;
            var rotRad:Number = (i * phaseOffsetDeg + dir * angVelDeg * burstFrame) * DEG2RAD;

            // 黑白分界轴 (跟随自旋旋进; 法向 = (-sin, cos) of rot)
            var nxL:Number = -Math.sin(rotRad);
            var nyL:Number = Math.cos(rotRad);

            sliceCenterX[i] = cx;
            sliceCenterY[i] = cy;
            sliceAlpha[i]   = alphaI;
            sliceRadiusArr[i] = R;

            var baseIdx:Number = i * 8;
            for (var k:Number = 0; k < 8; k++) {
                var theta:Number = rotRad + k * EIGHTH_PI;
                var xL:Number = Math.cos(theta) * R;
                var yL:Number = Math.sin(theta) * R;
                // 世界坐标变换: 局部 x 沿 ray 方向压缩, 局部 y 沿垂直方向
                var wx:Number = cx + xL * sliceCompressX * dirX + yL * perpX;
                var wy:Number = cy + xL * sliceCompressX * dirY + yL * perpY;
                var idx:Number = baseIdx + k;
                vX[idx] = wx;
                vY[idx] = wy;
                vSide[idx] = (xL * nxL + yL * nyL) >= 0 ? 1 : 0;
            }
        }

        // ─── LOD 控制 ───
        var enableGlow:Boolean    = (lod < 1);
        var enableLinkers:Boolean = (lod < 2);
        var enableDiagonals:Boolean = (lod < 2);

        // ════════════════════════════════════════════════════════════════
        // L0: 中枢贯穿线 (深金, α 跟随律动峰值)
        // ════════════════════════════════════════════════════════════════
        var spineAlpha:Number = (45 + 40 * maxAlpha) * cycleAlpha;
        mc.lineStyle(thickness * 1.4, spineColor, spineAlpha, true, "normal", "round", "round", 3);
        mc.moveTo(sliceCenterX[0], sliceCenterY[0]);
        mc.lineTo(sliceCenterX[sliceCountM1], sliceCenterY[sliceCountM1]);

        // ════════════════════════════════════════════════════════════════
        // L1: 切片间纵向连杆 (按顶点黑/白染色, α 取较小端)
        // ════════════════════════════════════════════════════════════════
        if (enableLinkers && slicesCount > 1) {
            var stepK:Number = (linkerStride > 0) ? linkerStride : 1;
            for (var li:Number = 0; li < sliceCountM1; li++) {
                var aAlpha:Number = sliceAlpha[li];
                var bAlpha:Number = sliceAlpha[li + 1];
                var linkAlpha:Number = (aAlpha < bAlpha ? aAlpha : bAlpha) * cycleAlpha;
                var aBase:Number = li * 8;
                var bBase:Number = (li + 1) * 8;
                for (var lk:Number = 0; lk < 8; lk += stepK) {
                    var sA:Number = vSide[aBase + lk];
                    var sB:Number = vSide[bBase + lk];
                    var col:Number;
                    var baseAlpha:Number;
                    if (sA == sB) {
                        col = (sA == 1) ? primaryColor : darkColor;
                        baseAlpha = 70;
                    } else {
                        col = mixedColor;
                        baseAlpha = 45;
                    }
                    mc.lineStyle(thickness * 0.7, col, baseAlpha * linkAlpha,
                                 true, "normal", "round", "round", 3);
                    mc.moveTo(vX[aBase + lk], vY[aBase + lk]);
                    mc.lineTo(vX[bBase + lk], vY[bBase + lk]);
                }
            }
        }

        // ════════════════════════════════════════════════════════════════
        // L2 + L3 + L4: 逐切片 (glow → 外轮廓 → 内部对角)
        // ════════════════════════════════════════════════════════════════
        var glowThick:Number = thickness * glowWidthMult;
        var diagThick:Number = thickness * 0.75;
        // 内部对角间隔 (从 4 个 k=0..3 中等距取 nDiagonals 条)
        var diagStride:Number = (nDiagonals > 0) ? Math.floor(4 / nDiagonals) : 4;
        if (diagStride < 1) diagStride = 1;

        for (var si:Number = 0; si < slicesCount; si++) {
            var alphaI:Number = sliceAlpha[si];
            // 早退优化: α 过低 (< 3%) 直接跳过整个切片
            if (alphaI * cycleAlpha < 0.03) continue;

            var sliceR:Number = sliceRadiusArr[si];
            var radiusBoost:Number = (sliceR / sliceRadius) - 1.0;  // 0 ~ pulseAmp
            var glowBoost:Number = 1.0 + radiusBoost * 1.5;
            var sliceBase:Number = si * 8;
            var alphaOut:Number = 100 * alphaI * cycleAlpha;

            // ─── L2: 外发光描边 (仅暖白半边相邻边) ───
            if (enableGlow) {
                var glowA:Number = glowAlpha * glowBoost * alphaI * cycleAlpha;
                if (glowA > 1) {
                    mc.lineStyle(glowThick, primaryColor, glowA,
                                 true, "normal", "round", "round", 3);
                    for (var gk:Number = 0; gk < 8; gk++) {
                        var gk1:Number = (gk + 1) & 7;
                        if (vSide[sliceBase + gk] == 1 && vSide[sliceBase + gk1] == 1) {
                            mc.moveTo(vX[sliceBase + gk], vY[sliceBase + gk]);
                            mc.lineTo(vX[sliceBase + gk1], vY[sliceBase + gk1]);
                        }
                    }
                }
            }

            // ─── L3: 外轮廓 8 边 ───
            for (var ek:Number = 0; ek < 8; ek++) {
                var ek1:Number = (ek + 1) & 7;
                var s0:Number = vSide[sliceBase + ek];
                var s1:Number = vSide[sliceBase + ek1];
                var ecol:Number;
                if (s0 == s1) {
                    ecol = (s0 == 1) ? primaryColor : darkColor;
                } else {
                    ecol = mixedColor;
                }
                mc.lineStyle(thickness, ecol, alphaOut,
                             true, "normal", "round", "round", 3);
                mc.moveTo(vX[sliceBase + ek], vY[sliceBase + ek]);
                mc.lineTo(vX[sliceBase + ek1], vY[sliceBase + ek1]);
            }

            // ─── L4: 内部主对角 (顶点 k 与 k+4 相连, 按 side 染色) ───
            if (enableDiagonals && nDiagonals > 0) {
                var diagAlpha:Number = 90 * alphaI * cycleAlpha;
                for (var dk:Number = 0; dk < 4; dk += diagStride) {
                    var dSide:Number = vSide[sliceBase + dk];
                    var dcol:Number = (dSide == 1) ? primaryColor : darkColor;
                    mc.lineStyle(diagThick, dcol, diagAlpha,
                                 true, "normal", "round", "round", 3);
                    mc.moveTo(vX[sliceBase + dk], vY[sliceBase + dk]);
                    mc.lineTo(vX[sliceBase + dk + 4], vY[sliceBase + dk + 4]);
                }
            }
        }
    }
}
