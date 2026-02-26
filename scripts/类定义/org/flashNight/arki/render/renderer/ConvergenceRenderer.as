import org.flashNight.arki.render.RayVfxManager;

/**
 * ConvergenceRenderer
 *
 * 1. HyperBeam 四重体积实体光柱 (暗鞘→极青→炽白→纯白)
 * 2. EnergyFin 贝塞尔曲面能量收束漏斗
 * 3. HoloSigil 势力Logo全息投影 (碎裂菱形+双枪托+圣矛+Z闪电)
 * 4. MachCone 三维马赫推力锥 (橙色尾焰+极青底盘+白热凹面)
 * 5. MatrixCircuit 矩阵正交闪电 (0°/45°/90°跃迁，6Hz低频)
 * 6. VolumetricRibbon Z轴遮挡双螺旋缎带 (3D光照反馈)
 * 7. ShatterImpact 暗物质撕裂爆轰 + 立体结晶碎片
 *
 * @author FlashNight 
 * @version 7.0
 */
class org.flashNight.arki.render.renderer.ConvergenceRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY_COLOR:Number   = 0x00E5FF;
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFF6600;
    private static var DEFAULT_THICKNESS:Number       = 2.0;
    private static var DEFAULT_RAIL_SPREAD:Number     = 10;
    private static var DEFAULT_CONVERGENCE_RATIO:Number = 0.18;
    private static var DEFAULT_NODE_COUNT:Number      = 6;
    private static var DEFAULT_NODE_SPEED:Number      = 0.15;
    private static var DEFAULT_CROSSHAIR_SCALE:Number = 0.9;

    private static var MAX_FOCAL_DIST:Number = 80;

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    public static function render(arc:Object, lod:Number, mc:MovieClip):Void {
        var config:Object = arc.config;
        var meta:Object   = arc.meta;
        var age:Number    = arc.age;
        var VM:Function   = RayVfxManager;

        var priColor:Number   = VM.cfgNum(config, "primaryColor", DEFAULT_PRIMARY_COLOR);
        var secColor:Number   = VM.cfgNum(config, "secondaryColor", DEFAULT_SECONDARY_COLOR);
        var railSpread:Number = VM.cfgNum(config, "railSpread", DEFAULT_RAIL_SPREAD);
        var convRatio:Number  = VM.cfgNum(config, "convergenceRatio", DEFAULT_CONVERGENCE_RATIO);
        var nodeCount:Number  = VM.cfgNum(config, "nodeCount", DEFAULT_NODE_COUNT);
        var nodeSpeed:Number  = VM.cfgNum(config, "nodeSpeed", DEFAULT_NODE_SPEED);
        var scale:Number      = VM.cfgNum(config, "crosshairScale", DEFAULT_CROSSHAIR_SCALE);

        var intensity:Number = VM.cfgIntensity(meta);
        var T:Number = VM.cfgNum(config, "thickness", DEFAULT_THICKNESS) * intensity;
        railSpread *= intensity;

        var isFork:Boolean = (meta != null && meta.segmentKind == "fork");
        if (isFork) { railSpread *= 0.5; T *= 0.6; }

        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        var dirX:Number  = dx / dist;
        var dirY:Number  = dy / dist;
        var perpX:Number = -dirY;
        var perpY:Number = dirX;

        mc.blendMode = "screen";

        // 计算收束焦点 (含V7安全钳位：焦点不超过50%总长)
        var targetFocalDist:Number = dist * convRatio;
        var actualFocalDist:Number = Math.min(targetFocalDist, MAX_FOCAL_DIST);
        actualFocalDist = Math.max(actualFocalDist, 25);
        if (actualFocalDist > dist * 0.5) actualFocalDist = dist * 0.5;
        if (isFork) actualFocalDist = 0;

        var fX:Number = arc.startX + dirX * actualFocalDist;
        var fY:Number = arc.startY + dirY * actualFocalDist;
        var postDist:Number = dist - actualFocalDist;
        var enableHeavy:Boolean = (lod == 0 && !isFork);

        // ─────────────────────────────────────────────────────────────
        // LOD 2: 极简保护
        // ─────────────────────────────────────────────────────────────
        if (lod >= 2) {
            drawQuad(mc, arc.startX, arc.startY, arc.endX, arc.endY,
                perpX, perpY, T * 3.5, T * 3.5,
                priColor, clampAlpha(60 * intensity));
            drawQuad(mc, arc.startX, arc.startY, arc.endX, arc.endY,
                perpX, perpY, T * 1.0, T * 1.0,
                0xFFFFFF, clampAlpha(100 * intensity));
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段一：柔化泛光 (非纺锤模式用均匀底光；纺锤模式泛光内置于纺锤层)
        // ─────────────────────────────────────────────────────────────
        if (lod == 0 && (isFork || dist <= 60)) {
            var pathEntire:Array = VM.straightPath(
                arc.startX, arc.startY, arc.endX, arc.endY);
            VM.drawPath(mc, pathEntire, priColor, T * 10,
                clampAlpha(50 * intensity));
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段二：贝塞尔能量收束漏斗 (EnergyFin)
        // ─────────────────────────────────────────────────────────────
        if (actualFocalDist > 0 && !isFork) {
            var finCount:Number = enableHeavy ? 4 : 2;
            for (var r:Number = 0; r < finCount; r++) {
                var offsetRatio:Number = (2.0 * r / (finCount - 1) - 1.0);
                var fSpread:Number = railSpread * offsetRatio * 1.2;
                var finColor:Number = (Math.abs(offsetRatio) > 0.6)
                    ? secColor : priColor;
                var finPulse:Number = 1.0 + Math.sin(age * 15.0 + r) * 0.2;

                drawEnergyFin(mc, arc.startX, arc.startY, fX, fY,
                    perpX, perpY, fSpread * finPulse, finColor,
                    clampAlpha(65 * intensity));
            }
        }

        // ─────────────────────────────────────────────────────────────
        // 共享计算：级联法阵节点位置 (纺锤光柱 + 级联法阵共用)
        // ─────────────────────────────────────────────────────────────
        var focalT:Number = actualFocalDist / dist;
        var cascadeCount:Number = 0;
        var sigilTs:Array = [];

        if (dist > 60 && !isFork) {
            var sigilSpacing:Number = 80;
            cascadeCount = Math.max(1, Math.floor(dist / sigilSpacing));
            if (cascadeCount > 8) cascadeCount = 8;
            for (var csi:Number = 0; csi < cascadeCount; csi++) {
                sigilTs.push((csi + 1.0) / (cascadeCount + 1.0));
            }
        }

        // 纺锤约束点 = 级联法阵节点 + 焦点
        var pinchTs:Array = sigilTs.concat();
        if (focalT > 0.02 && focalT < 0.98 && !isFork) {
            pinchTs.push(focalT);
            pinchTs.sort(Array.NUMERIC);
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段三：纺锤链光柱 (法阵节点处收束，段间弧形膨胀)
        // ─────────────────────────────────────────────────────────────
        var pulse:Number = 1.0 + Math.sin(age * 22.0) * 0.12;
        if (enableHeavy && pinchTs.length > 0) {
            drawSpindleChainBeam(mc, arc.startX, arc.startY,
                arc.endX, arc.endY, perpX, perpY, dist,
                T * pulse, priColor, clampAlpha(95 * intensity),
                pinchTs, focalT);
        } else {
            if (actualFocalDist > 0) {
                drawHyperBeam(mc, arc.startX, arc.startY, fX, fY,
                    perpX, perpY, T * 1.0 * pulse, priColor,
                    clampAlpha(75 * intensity));
            }
            drawHyperBeam(mc, fX, fY, arc.endX, arc.endY,
                perpX, perpY, T * 1.6 * pulse, priColor,
                clampAlpha(100 * intensity));
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段四：重火力物理异象
        // ─────────────────────────────────────────────────────────────
        if (postDist > 10) {
            // 1. 3D体积缎带
            if (enableHeavy) {
                drawVolumetricRibbon(mc, fX, fY, arc.endX, arc.endY,
                    dirX, dirY, perpX, perpY, postDist, 60,
                    T * 3.0, age, 0, T * 2.0,
                    priColor, clampAlpha(85 * intensity));
                drawVolumetricRibbon(mc, fX, fY, arc.endX, arc.endY,
                    dirX, dirY, perpX, perpY, postDist, 60,
                    T * 3.0, age, Math.PI, T * 2.0,
                    secColor, clampAlpha(85 * intensity));
            }

            // 2. 三维马赫推力锥
            if (enableHeavy && postDist > 60) {
                var machCount:Number = Math.floor(postDist / 80);
                for (var m:Number = 0; m < machCount; m++) {
                    var mT:Number = ((m / machCount) - age * 3.0);
                    mT = mT - Math.floor(mT);
                    if (mT > 0.05 && mT < 0.95) {
                        var mx:Number = fX + dirX * postDist * mT;
                        var my:Number = fY + dirY * postDist * mT;
                        var mScale:Number = Math.sin(mT * Math.PI) * intensity;
                        drawMachCone(mc, mx, my, dirX, dirY, perpX, perpY,
                            T * 8.0 * mScale, T * 5.0 * mScale,
                            priColor, secColor, clampAlpha(85 * mScale));
                    }
                }
            }

            // 3. 矩阵正交闪电
            if (lod == 0) {
                var cAmp:Number = T * 5.0 * intensity;
                var circuitSeed:Number = Math.floor(age * 6.0 * nodeSpeed / 0.15);

                drawMatrixCircuit(mc, fX, fY, arc.endX, arc.endY,
                    dirX, dirY, perpX, perpY, postDist, cAmp,
                    circuitSeed * 11 + 7, priColor, T * 1.5,
                    clampAlpha(90 * intensity), nodeCount);

                if (enableHeavy) {
                    drawMatrixCircuit(mc, fX, fY, arc.endX, arc.endY,
                        dirX, dirY, perpX, perpY, postDist, cAmp * 1.3,
                        circuitSeed * 17 + 88, secColor, T * 1.0,
                        clampAlpha(75 * intensity), nodeCount);
                }
            }

            // 4. 战术标尺
            if (enableHeavy) {
                var tickCount:Number = Math.floor(postDist / 80);
                for (var tk:Number = 1; tk <= tickCount; tk++) {
                    var tkT:Number = tk / (tickCount + 1);
                    var tkX:Number = fX + dirX * postDist * tkT;
                    var tkY:Number = fY + dirY * postDist * tkT;
                    var bw:Number = T * 2.5;
                    var bh:Number = T * 1.2;

                    mc.lineStyle(T * 1.0, priColor,
                        clampAlpha(45 * intensity),
                        true, "normal", "round", "miter");
                    mc.moveTo(tkX - perpX * bw - dirX * 3,
                              tkY - perpY * bw - dirY * 3);
                    mc.lineTo(tkX - perpX * bw, tkY - perpY * bw);
                    mc.lineTo(tkX - perpX * bw + dirX * bh,
                              tkY - perpY * bw + dirY * bh);
                    mc.moveTo(tkX + perpX * bw - dirX * 3,
                              tkY + perpY * bw - dirY * 3);
                    mc.lineTo(tkX + perpX * bw, tkY + perpY * bw);
                    mc.lineTo(tkX + perpX * bw + dirX * bh,
                              tkY + perpY * bw + dirY * bh);

                    mc.lineStyle(1.0, 0xFFFFFF,
                        clampAlpha(80 * intensity),
                        true, "normal", "round", "miter");
                    mc.moveTo(tkX - perpX * bw - dirX * 3,
                              tkY - perpY * bw - dirY * 3);
                    mc.lineTo(tkX - perpX * bw, tkY - perpY * bw);
                    mc.lineTo(tkX - perpX * bw + dirX * bh,
                              tkY - perpY * bw + dirY * bh);
                    mc.moveTo(tkX + perpX * bw - dirX * 3,
                              tkY + perpY * bw - dirY * 3);
                    mc.lineTo(tkX + perpX * bw, tkY + perpY * bw);
                    mc.lineTo(tkX + perpX * bw + dirX * bh,
                              tkY + perpY * bw + dirY * bh);
                }
                mc.lineStyle(undefined);
            }
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段四·五：全程级联法阵 (绘于纺锤收束节点之上)
        // ─────────────────────────────────────────────────────────────
        if (enableHeavy && cascadeCount > 0) {
            for (var cs:Number = 0; cs < cascadeCount; cs++) {
                var csT:Number = sigilTs[cs];
                var csX:Number = arc.startX + dirX * dist * csT;
                var csY:Number = arc.startY + dirY * dist * csT;

                var csEnv:Number = Math.sin(csT * Math.PI);
                var csFocalBoost:Number = Math.exp(
                    -((csT - focalT) * (csT - focalT)) / 0.02);
                var csScale:Number = 0.6 + 0.4 * csEnv
                    + 0.3 * csFocalBoost;

                var csSize:Number = T * 8.0 * csScale * scale * intensity;
                if (csSize < 2.5) continue;

                var csPhase:Number = age * (0.18 + cs * 0.07)
                    + cs * 2.094;
                var csColor:Number = (cs % 2 == 0) ? priColor : secColor;
                var csAlpha:Number = clampAlpha(
                    (70 + 20 * csEnv) * intensity);

                drawMiniSigil(mc, csX, csY, dirX, dirY, perpX, perpY,
                    csSize, csColor, csAlpha, csPhase);
            }
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段五：全息法阵 (势力Logo投影，绘于后层以镇压特效)
        // ─────────────────────────────────────────────────────────────
        if (!isFork) {
            var sigilSize:Number = T * 5.5 * scale * intensity;
            drawHoloSigil(mc, fX, fY, dirX, dirY, perpX, perpY,
                sigilSize, priColor, secColor,
                clampAlpha(100 * intensity), age);
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段六：暗物质撕裂爆轰
        // ─────────────────────────────────────────────────────────────
        if (lod < 1) {
            var hitSize:Number = T * 5.0 * scale * intensity;
            if (meta != null && meta.segmentKind == "pierce"
                && meta.hitPoints != null) {
                var hitPoints:Array = meta.hitPoints;
                for (var i:Number = 0; i < hitPoints.length; i++) {
                    drawShatterImpact(mc, hitPoints[i].x, hitPoints[i].y,
                        hitSize, priColor, secColor,
                        clampAlpha(100 * intensity), age, dirX, dirY,
                        enableHeavy);
                }
            } else {
                drawShatterImpact(mc, arc.endX, arc.endY, hitSize * 1.5,
                    priColor, secColor, clampAlpha(100 * intensity),
                    age, dirX, dirY, enableHeavy);
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 视觉引擎：核心渲染函数
    // ════════════════════════════════════════════════════════════════════════

    /** 迷你级联聚焦法阵 (碎裂菱形+Z闪电，展示能量多级压缩传递) */
    private static function drawMiniSigil(
        mc:MovieClip, cx:Number, cy:Number,
        dirX:Number, dirY:Number, perpX:Number, perpY:Number,
        size:Number, color:Number, alpha:Number, rot:Number
    ):Void {
        var a:Number = clampAlpha(alpha);
        if (a <= 0 || size <= 1) return;

        var cosR:Number = Math.cos(rot);
        var sinR:Number = Math.sin(rot);
        var rdX:Number = dirX * cosR + perpX * sinR;
        var rdY:Number = dirY * cosR + perpY * sinR;
        var rpX:Number = perpX * cosR - dirX * sinR;
        var rpY:Number = perpY * cosR - dirY * sinR;

        // 暗遮挡盘 (截断泛光，营造局部暗窗，与主法阵设计统一)
        drawSolidCircle(mc, cx, cy, size * 1.2, 0x000B1A,
            clampAlpha(a * 0.6));

        // 碎裂菱形框
        mc.lineStyle(size * 0.15, color, clampAlpha(a * 0.9),
            true, "normal", "square", "miter");
        var dPts:Array = [
            {x: cx + rdX * size, y: cy + rdY * size},
            {x: cx + rpX * size, y: cy + rpY * size},
            {x: cx - rdX * size, y: cy - rdY * size},
            {x: cx - rpX * size, y: cy - rpY * size}
        ];
        for (var j:Number = 0; j < 4; j++) {
            var p1:Object = dPts[j];
            var p2:Object = dPts[(j + 1) % 4];
            var vx:Number = p2.x - p1.x;
            var vy:Number = p2.y - p1.y;
            mc.moveTo(p1.x + vx * 0.12, p1.y + vy * 0.12);
            mc.lineTo(p1.x + vx * 0.45, p1.y + vy * 0.45);
            mc.moveTo(p1.x + vx * 0.55, p1.y + vy * 0.55);
            mc.lineTo(p1.x + vx * 0.88, p1.y + vy * 0.88);
        }
        mc.lineStyle(undefined);

        // Z型闪电
        var lx1:Number = cx - rdX * size * 0.7 + rpX * size * 0.9;
        var ly1:Number = cy - rdY * size * 0.7 + rpY * size * 0.9;
        var lx2:Number = cx + rdX * size * 0.8 - rpX * size * 0.9;
        var ly2:Number = cy + rdY * size * 0.8 - rpY * size * 0.9;
        var zmx1:Number = cx - rdX * size * 0.1 + rpX * size * 0.15;
        var zmy1:Number = cy - rdY * size * 0.1 + rpY * size * 0.15;
        var zmx2:Number = cx + rdX * size * 0.1 - rpX * size * 0.05;
        var zmy2:Number = cy + rdY * size * 0.1 - rpY * size * 0.05;

        mc.lineStyle(size * 0.22, color, a,
            true, "normal", "round", "miter");
        mc.moveTo(lx1, ly1);
        mc.lineTo(zmx1, zmy1);
        mc.lineTo(zmx2, zmy2);
        mc.lineTo(lx2, ly2);

        mc.lineStyle(size * 0.07, 0xFFFFFF, a,
            true, "normal", "round", "miter");
        mc.moveTo(lx1, ly1);
        mc.lineTo(zmx1, zmy1);
        mc.lineTo(zmx2, zmy2);
        mc.lineTo(lx2, ly2);
        mc.lineStyle(undefined);

        // 瞄准环 (稳定，不随菱形旋转)
        drawRing(mc, cx, cy, size * 0.45, size * 0.08,
            color, clampAlpha(a * 0.7));

        // 光束对齐断开式十字准星 (稳定瞄准参考，与旋转菱形形成动静对比)
        var chLen:Number = size * 0.6;
        var chGap:Number = size * 0.18;
        mc.lineStyle(size * 0.08, 0xFFFFFF, clampAlpha(a * 0.85),
            true, "normal", "none", "miter");
        mc.moveTo(cx - dirX * chLen, cy - dirY * chLen);
        mc.lineTo(cx - dirX * chGap, cy - dirY * chGap);
        mc.moveTo(cx + dirX * chLen, cy + dirY * chLen);
        mc.lineTo(cx + dirX * chGap, cy + dirY * chGap);
        mc.moveTo(cx - perpX * chLen, cy - perpY * chLen);
        mc.lineTo(cx - perpX * chGap, cy - perpY * chGap);
        mc.moveTo(cx + perpX * chLen, cy + perpY * chLen);
        mc.lineTo(cx + perpX * chGap, cy + perpY * chGap);
        mc.lineStyle(undefined);

        // 中心聚焦点
        RayVfxManager.drawCircle(mc, cx, cy, size * 0.12, 0xFFFFFF, a);
    }

    /** 四重体积重叠光柱 (深海暗鞘→极青主干→炽白过渡→纯白极点刃) */
    private static function drawHyperBeam(
        mc:MovieClip, sx:Number, sy:Number, ex:Number, ey:Number,
        px:Number, py:Number, wScale:Number, priColor:Number, alpha:Number
    ):Void {
        if (alpha <= 0) return;
        drawQuad(mc, sx, sy, ex, ey, px, py,
            wScale * 4.8, wScale * 5.2,
            0x001B33, clampAlpha(alpha * 0.45));
        drawQuad(mc, sx, sy, ex, ey, px, py,
            wScale * 2.4, wScale * 2.8,
            priColor, clampAlpha(alpha * 0.75));
        drawQuad(mc, sx, sy, ex, ey, px, py,
            wScale * 1.1, wScale * 1.3,
            0xAAFFFF, clampAlpha(alpha * 0.9));
        drawQuad(mc, sx, sy, ex, ey, px, py,
            wScale * 0.4, wScale * 0.5,
            0xFFFFFF, alpha);
    }

    /**
     * 纺锤链四重光柱 (法阵节点处能量收束，段间弧形膨胀)
     *
     * 原理：在 pinchTs 指定的 t 位置将光束收窄至极细（能量压缩节点），
     * 两个节点之间用 sin(localT*PI) 包络弧形膨胀（能量释放段），
     * 配合后焦段线性放大 (1.0x→1.6x)，再现磁约束等离子体的"糖葫芦"形态。
     *
     * 保持六层光学结构 (外泛光→内泛光→暗鞘→极青→炽白→纯白)，
     * 收束极度柔和 (外层50%→内核88%)，保持直线射线感。
     */
    private static function drawSpindleChainBeam(
        mc:MovieClip, sx:Number, sy:Number, ex:Number, ey:Number,
        px:Number, py:Number, dist:Number,
        baseWidth:Number, priColor:Number, alpha:Number,
        pinchTs:Array, focalT:Number
    ):Void {
        if (alpha <= 0 || dist <= 0) return;

        var nPinch:Number = pinchTs.length;
        var segs:Number = Math.max(16, Math.ceil(dist / 15));
        var invSegs:Number = 1.0 / segs;

        // ── 预计算纺锤包络 (扫描指针法，O(segs+nPinch)) ──
        var widths:Array = [];
        var pIdx:Number = 0;
        var leftB:Number = 0;
        var rightB:Number = (nPinch > 0) ? pinchTs[0] : 1.0;

        for (var i:Number = 0; i <= segs; i++) {
            var t:Number = i * invSegs;

            // 推进到包含 t 的约束段 [leftB, rightB]
            while (pIdx < nPinch && t > pinchTs[pIdx] + 0.001) {
                leftB = pinchTs[pIdx];
                pIdx++;
                rightB = (pIdx < nPinch) ? pinchTs[pIdx] : 1.0;
            }

            var segLen:Number = rightB - leftB;
            var localT:Number = (segLen > 0.005)
                ? (t - leftB) / segLen : 0.5;
            // sin 纺锤：端点(法阵处)=0 → 中点(段间最宽)=1
            var envelope:Number = Math.sin(localT * Math.PI);

            // 后焦段宽度线性放大 (1.0x at focal → 1.6x at end)
            var postFactor:Number = (t > focalT && focalT < 0.99)
                ? (t - focalT) / (1.0 - focalT) : 0;
            widths.push(envelope * (1.0 + 0.6 * postFactor));
        }

        // ── 六层光学结构 (含纺锤约束泛光) ──
        //       color        widthMul  alphaMul  pinchMin
        // L0: 外泛光         priColor   7.0      15%   50%  (收窄柔光晕)
        // L1: 内泛光         priColor   4.5      28%   55%  (过渡层)
        // L2: 深海暗鞘       0x001B33   3.2      45%   60%
        // L3: 极青主干       priColor   1.8      75%   68%
        // L4: 炽白过渡       0xAAFFFF   0.9      90%   78%
        // L5: 纯白刃芯       0xFFFFFF   0.35     100%  88%
        var lC:Array = [priColor, priColor, 0x001B33, priColor, 0xAAFFFF, 0xFFFFFF];
        var lW:Array = [7.0, 4.5, 3.2, 1.8, 0.9, 0.35];
        var lA:Array = [0.15, 0.28, 0.45, 0.75, 0.9, 1.0];
        var lP:Array = [0.50, 0.55, 0.60, 0.68, 0.78, 0.88];

        for (var L:Number = 0; L < lC.length; L++) {
            var layerW:Number = baseWidth * lW[L];
            var layerA:Number = clampAlpha(alpha * lA[L]);
            if (layerA <= 0) continue;
            var pMin:Number = lP[L];

            mc.lineStyle(undefined);
            mc.beginFill(lC[L], layerA);

            // 上沿（正向扫描）
            for (var fi:Number = 0; fi <= segs; fi++) {
                var w:Number = (pMin + (1 - pMin) * widths[fi]) * layerW;
                var bx:Number = sx + (ex - sx) * (fi * invSegs);
                var by:Number = sy + (ey - sy) * (fi * invSegs);
                if (fi == 0) {
                    mc.moveTo(bx + px * w, by + py * w);
                } else {
                    mc.lineTo(bx + px * w, by + py * w);
                }
            }

            // 下沿（逆向扫描）
            for (var bi:Number = segs; bi >= 0; bi--) {
                w = (pMin + (1 - pMin) * widths[bi]) * layerW;
                bx = sx + (ex - sx) * (bi * invSegs);
                by = sy + (ey - sy) * (bi * invSegs);
                mc.lineTo(bx - px * w, by - py * w);
            }

            mc.endFill();
        }
    }

    /** 贝塞尔曲面能量收束漏斗 */
    private static function drawEnergyFin(
        mc:MovieClip, sx:Number, sy:Number, fx:Number, fy:Number,
        px:Number, py:Number, offset:Number, color:Number, alpha:Number
    ):Void {
        if (alpha <= 0) return;
        var midX:Number = (sx + fx) * 0.5 + px * offset;
        var midY:Number = (sy + fy) * 0.5 + py * offset;

        mc.lineStyle(undefined);
        mc.beginFill(color, clampAlpha(alpha * 0.5));
        mc.moveTo(sx, sy);
        mc.curveTo(midX, midY, fx, fy);
        var inMidX:Number = (sx + fx) * 0.5 + px * (offset * 0.4);
        var inMidY:Number = (sy + fy) * 0.5 + py * (offset * 0.4);
        mc.curveTo(inMidX, inMidY, sx, sy);
        mc.endFill();

        mc.lineStyle(2.5, 0xFFFFFF, clampAlpha(alpha * 0.9),
            true, "normal", "none", "miter");
        mc.moveTo(sx, sy);
        mc.curveTo(midX, midY, fx, fy);
        mc.lineStyle(undefined);
    }

    /**
     * 神权全息法阵投影 (1:1重构势力Logo)
     * 暗遮挡盘 → 碎裂菱形框 → 圣矛+双枪托 → 橙色靶心 → Z闪电
     */
    private static function drawHoloSigil(
        mc:MovieClip, cx:Number, cy:Number,
        dirX:Number, dirY:Number, perpX:Number, perpY:Number,
        size:Number, priColor:Number, secColor:Number,
        alpha:Number, age:Number
    ):Void {
        var a:Number = clampAlpha(alpha);
        if (a <= 0) return;

        // 1. 暗遮挡盘 (压制下方特效，营造立体层级)
        drawSolidCircle(mc, cx, cy, size * 1.5, 0x000B1A, clampAlpha(a * 0.7));

        // 2. 碎裂菱形机甲外框 (持续自转)
        var outR:Number = size * 1.6;
        var frameRot:Number = age * 0.15;
        var cosR:Number = Math.cos(frameRot);
        var sinR:Number = Math.sin(frameRot);
        var rdX:Number = dirX * cosR + perpX * sinR;
        var rdY:Number = dirY * cosR + perpY * sinR;
        var rpX:Number = perpX * cosR - dirX * sinR;
        var rpY:Number = perpY * cosR - dirY * sinR;

        mc.lineStyle(size * 0.22, priColor, clampAlpha(a * 0.95),
            true, "normal", "square", "miter");
        var dPts:Array = [
            {x: cx + rdX * outR, y: cy + rdY * outR},
            {x: cx + rpX * outR, y: cy + rpY * outR},
            {x: cx - rdX * outR, y: cy - rdY * outR},
            {x: cx - rpX * outR, y: cy - rpY * outR}
        ];
        for (var j:Number = 0; j < 4; j++) {
            var p1:Object = dPts[j];
            var p2:Object = dPts[(j + 1) % 4];
            var vx:Number = p2.x - p1.x;
            var vy:Number = p2.y - p1.y;
            mc.moveTo(p1.x + vx * 0.10, p1.y + vy * 0.10);
            mc.lineTo(p1.x + vx * 0.42, p1.y + vy * 0.42);
            mc.moveTo(p1.x + vx * 0.58, p1.y + vy * 0.58);
            mc.lineTo(p1.x + vx * 0.90, p1.y + vy * 0.90);
        }
        mc.lineStyle(undefined);

        // 3. 贯穿圣矛 (暗色装甲底漆)
        mc.beginFill(0x001B33, a);
        mc.moveTo(cx + dirX * size * 3.5, cy + dirY * size * 3.5);
        mc.lineTo(cx + dirX * size * 1.4 + perpX * size * 0.5,
                  cy + dirY * size * 1.4 + perpY * size * 0.5);
        mc.lineTo(cx + dirX * size * 1.4 - perpX * size * 0.5,
                  cy + dirY * size * 1.4 - perpY * size * 0.5);
        mc.endFill();

        // 左沉降枪托
        mc.beginFill(0x001B33, a);
        mc.moveTo(cx - dirX * size * 0.5, cy - dirY * size * 0.5);
        mc.lineTo(cx - dirX * size * 1.8 - perpX * size * 1.1,
                  cy - dirY * size * 1.8 - perpY * size * 1.1);
        mc.lineTo(cx - dirX * size * 2.3 - perpX * size * 0.45,
                  cy - dirY * size * 2.3 - perpY * size * 0.45);
        mc.lineTo(cx - dirX * size * 1.2, cy - dirY * size * 1.2);
        mc.endFill();

        // 右沉降枪托
        mc.beginFill(0x001B33, a);
        mc.moveTo(cx - dirX * size * 0.5, cy - dirY * size * 0.5);
        mc.lineTo(cx - dirX * size * 1.8 + perpX * size * 1.1,
                  cy - dirY * size * 1.8 + perpY * size * 1.1);
        mc.lineTo(cx - dirX * size * 2.3 + perpX * size * 0.45,
                  cy - dirY * size * 2.3 + perpY * size * 0.45);
        mc.lineTo(cx - dirX * size * 1.2, cy - dirY * size * 1.2);
        mc.endFill();

        // 圣矛内部极青充能核心
        mc.beginFill(priColor, clampAlpha(a * 0.95));
        mc.moveTo(cx + dirX * size * 3.3, cy + dirY * size * 3.3);
        mc.lineTo(cx + dirX * size * 1.5 + perpX * size * 0.2,
                  cy + dirY * size * 1.5 + perpY * size * 0.2);
        mc.lineTo(cx + dirX * size * 1.5 - perpX * size * 0.2,
                  cy + dirY * size * 1.5 - perpY * size * 0.2);
        mc.endFill();

        // 4. 橙色锁定靶心
        RayVfxManager.drawCircle(mc, cx, cy, size * 0.8,
            secColor, clampAlpha(a * 0.4));
        drawRing(mc, cx, cy, size * 0.7, size * 0.15,
            secColor, a);
        drawRing(mc, cx, cy, size * 0.4, size * 0.08,
            secColor, clampAlpha(a * 0.9));

        // 光束对齐十字准星
        var crLen:Number = size * 0.9;
        var crGap:Number = size * 0.32;
        mc.lineStyle(size * 0.15, secColor, a,
            true, "normal", "none", "miter");
        mc.moveTo(cx - dirX * crLen, cy - dirY * crLen);
        mc.lineTo(cx - dirX * crGap, cy - dirY * crGap);
        mc.moveTo(cx + dirX * crLen, cy + dirY * crLen);
        mc.lineTo(cx + dirX * crGap, cy + dirY * crGap);
        mc.moveTo(cx - perpX * crLen, cy - perpY * crLen);
        mc.lineTo(cx - perpX * crGap, cy - perpY * crGap);
        mc.moveTo(cx + perpX * crLen, cy + perpY * crLen);
        mc.lineTo(cx + perpX * crGap, cy + perpY * crGap);
        mc.lineStyle(undefined);

        // 高频自转锁定圈
        drawDashedRing(mc, cx, cy, size * 1.1, 12, size * 0.1,
            priColor, clampAlpha(a * 0.8), age * 0.3);

        // 5. Z型闪电劈裂法阵 (随菱形同步旋转)
        var lx1:Number = cx - rdX * size * 1.1 + rpX * size * 1.4;
        var ly1:Number = cy - rdY * size * 1.1 + rpY * size * 1.4;
        var lx2:Number = cx + rdX * size * 1.2 - rpX * size * 1.4;
        var ly2:Number = cy + rdY * size * 1.2 - rpY * size * 1.4;
        var zmx1:Number = cx - rdX * size * 0.2 + rpX * size * 0.25;
        var zmy1:Number = cy - rdY * size * 0.2 + rpY * size * 0.25;
        var zmx2:Number = cx + rdX * size * 0.2 - rpX * size * 0.1;
        var zmy2:Number = cy + rdY * size * 0.2 - rpY * size * 0.1;

        mc.lineStyle(size * 0.35, priColor, a,
            true, "normal", "round", "miter");
        mc.moveTo(lx1, ly1);
        mc.lineTo(zmx1, zmy1);
        mc.lineTo(zmx2, zmy2);
        mc.lineTo(lx2, ly2);

        mc.lineStyle(size * 0.12, 0xFFFFFF, a,
            true, "normal", "round", "miter");
        mc.moveTo(lx1, ly1);
        mc.lineTo(zmx1, zmy1);
        mc.lineTo(zmx2, zmy2);
        mc.lineTo(lx2, ly2);
        mc.lineStyle(undefined);

        // 绝对耀眼核心
        RayVfxManager.drawCircle(mc, cx, cy, size * 0.25, 0xFFFFFF, a);
    }

    /** 3D景深实体双螺旋遮挡缎带 (Z-Depth光照反射) */
    private static function drawVolumetricRibbon(
        mc:MovieClip, sx:Number, sy:Number, ex:Number, ey:Number,
        dirX:Number, dirY:Number, perpX:Number, perpY:Number,
        dist:Number, waveLen:Number, amp:Number, age:Number,
        phase:Number, ribbonWid:Number, color:Number, alpha:Number
    ):Void {
        if (alpha <= 0) return;
        var segs:Number = Math.max(16, Math.ceil(dist / 12));
        var step:Number = 1.0 / segs;
        var prX:Number = 0, prY:Number = 0, plX:Number = 0, plY:Number = 0;

        for (var i:Number = 0; i <= segs; i++) {
            var t:Number = i * step;
            var env:Number = Math.pow(Math.sin(t * Math.PI), 0.7);
            var ang:Number = (t * dist / waveLen) * Math.PI * 2
                + age * 5.0 + phase;

            var offset:Number = Math.sin(ang) * amp * env;
            var zDepth:Number = Math.cos(ang);
            var vWid:Number = ribbonWid * env
                * (0.3 + 0.7 * Math.abs(zDepth));

            var cX:Number = sx + dirX * dist * t + perpX * offset;
            var cY:Number = sy + dirY * dist * t + perpY * offset;
            var rX:Number = cX + perpX * vWid;
            var rY:Number = cY + perpY * vWid;
            var lX:Number = cX - perpX * vWid;
            var lY:Number = cY - perpY * vWid;

            if (i > 0) {
                var fAlpha:Number = clampAlpha(
                    alpha * (0.15 + 0.85 * (zDepth + 1.0) * 0.5));
                mc.lineStyle(undefined);
                mc.beginFill(color, fAlpha);
                mc.moveTo(prX, prY);
                mc.lineTo(rX, rY);
                mc.lineTo(lX, lY);
                mc.lineTo(plX, plY);
                mc.endFill();

                if (zDepth > 0.4) {
                    var hAlpha:Number = clampAlpha(
                        alpha * (zDepth - 0.4) * 2.5);
                    mc.lineStyle(2.0, 0xFFFFFF, hAlpha,
                        true, "normal", "none", "miter");
                    mc.moveTo(prX, prY);
                    mc.lineTo(rX, rY);
                    mc.lineStyle(undefined);
                }
            }
            prX = rX; prY = rY; plX = lX; plY = lY;
        }
    }

    /** 航天级立体马赫推力锥 (橙色尾焰+极青底盘+白热凹面尖峰) */
    private static function drawMachCone(
        mc:MovieClip, cx:Number, cy:Number,
        dirX:Number, dirY:Number, perpX:Number, perpY:Number,
        length:Number, width:Number,
        priColor:Number, secColor:Number, alpha:Number
    ):Void {
        if (alpha <= 0) return;
        mc.lineStyle(undefined);

        // 底层：高温橙色尾焰
        mc.beginFill(secColor, clampAlpha(alpha * 0.6));
        mc.moveTo(cx + dirX * length * 0.8, cy + dirY * length * 0.8);
        mc.lineTo(cx + perpX * width * 1.4, cy + perpY * width * 1.4);
        mc.lineTo(cx - dirX * length * 1.1, cy - dirY * length * 1.1);
        mc.lineTo(cx - perpX * width * 1.4, cy - perpY * width * 1.4);
        mc.endFill();

        // 内层：极青菱形底盘
        mc.beginFill(priColor, clampAlpha(alpha * 0.95));
        mc.moveTo(cx + dirX * length, cy + dirY * length);
        mc.lineTo(cx + perpX * width, cy + perpY * width);
        mc.lineTo(cx - dirX * length * 0.5, cy - dirY * length * 0.5);
        mc.lineTo(cx - perpX * width, cy - perpY * width);
        mc.endFill();

        // 顶层：白热凹面透视尖峰
        mc.beginFill(0xFFFFFF, alpha);
        mc.moveTo(cx + dirX * length * 0.6, cy + dirY * length * 0.6);
        mc.lineTo(cx + perpX * width * 0.65, cy + perpY * width * 0.65);
        mc.lineTo(cx - dirX * length * 0.1, cy - dirY * length * 0.1);
        mc.lineTo(cx - perpX * width * 0.65, cy - perpY * width * 0.65);
        mc.endFill();
    }

    /** 矩阵正交电路闪电 (0°/45°/90° 强制跃迁，LCG伪随机，6Hz刷新) */
    private static function drawMatrixCircuit(
        mc:MovieClip, sx:Number, sy:Number, ex:Number, ey:Number,
        dX:Number, dY:Number, pX:Number, pY:Number, dist:Number,
        amp:Number, seed:Number, color:Number, thick:Number,
        a:Number, segDensity:Number
    ):Void {
        if (a <= 0) return;
        var pts:Array = [];
        var currU:Number = 0;
        var currV:Number = 0;
        pts.push({u: 0, v: 0});

        var rSeed:Number = seed;
        var nextRand:Function = function():Number {
            rSeed = (rSeed * 93.01 + 49.297) % 233280.0;
            return rSeed / 233280.0;
        };

        var stepBase:Number = dist / (segDensity * 2);
        var safetyLimit:Number = 100;

        while (currU < dist && --safetyLimit > 0) {
            var r:Number = nextRand();
            var stepU:Number = 0;
            var stepV:Number = 0;
            var slen:Number = stepBase * (0.5 + nextRand() * 0.9);

            if (r < 0.35) {
                stepU = slen;
            } else if (r < 0.7) {
                stepU = slen;
                stepV = slen * (nextRand() > 0.5 ? 1 : -1);
            } else {
                stepV = slen * 1.5 * (nextRand() > 0.5 ? 1 : -1);
                stepU = slen * 0.15;
            }

            var maxV:Number = amp * Math.sin((currU / dist) * Math.PI);
            if (currV + stepV > maxV) stepV = maxV - currV;
            if (currV + stepV < -maxV) stepV = -maxV - currV;

            currU += stepU;
            currV += stepV;
            if (currU > dist) { currU = dist; currV = 0; }
            pts.push({u: currU, v: currV});
        }

        // 泛光外晕
        mc.lineStyle(thick * 2.8, color, clampAlpha(a * 0.6),
            true, "normal", "square", "miter");
        mc.moveTo(sx, sy);
        for (var i:Number = 1; i < pts.length; i++) {
            mc.lineTo(sx + dX * pts[i].u + pX * pts[i].v,
                      sy + dY * pts[i].u + pY * pts[i].v);
        }

        // 极白内核
        mc.lineStyle(thick * 0.9, 0xFFFFFF, a,
            true, "normal", "square", "miter");
        mc.moveTo(sx, sy);
        for (var k:Number = 1; k < pts.length; k++) {
            mc.lineTo(sx + dX * pts[k].u + pX * pts[k].v,
                      sy + dY * pts[k].u + pY * pts[k].v);
        }
        mc.lineStyle(undefined);
    }

    /** 精密弹着标记 (狙击精准风格：环+十字+方向星芒+细碎片) */
    private static function drawShatterImpact(
        mc:MovieClip, x:Number, y:Number, size:Number,
        priColor:Number, secColor:Number, alpha:Number,
        age:Number, dirX:Number, dirY:Number, isHeavy:Boolean
    ):Void {
        var a:Number = clampAlpha(alpha);
        if (a <= 0) return;
        var pX:Number = -dirY;
        var pY:Number = dirX;

        // 1. 精密外环
        drawRing(mc, x, y, size * 1.8, 2.0,
            priColor, clampAlpha(a * 0.5));

        // 2. 方向星芒 (窄长精准，非爆炸式)
        drawDiamondFlare(mc, x, y, dirX, dirY,
            size * 4.0, size * 0.35, priColor, clampAlpha(a * 0.85));
        drawDiamondFlare(mc, x, y, pX, pY,
            size * 2.8, size * 0.25, secColor, clampAlpha(a * 0.7));
        drawDiamondFlare(mc, x, y, dirX, dirY,
            size * 2.0, size * 0.15, 0xFFFFFF, a);

        // 3. 弹着核心
        RayVfxManager.drawCircle(mc, x, y, size * 0.55,
            priColor, clampAlpha(a * 0.7));
        drawSolidCircle(mc, x, y, size * 0.2, 0xFFFFFF, a);

        // 4. 断开式弹着十字 (与法阵准星呼应)
        var chLen:Number = size * 1.3;
        var chGap:Number = size * 0.45;
        mc.lineStyle(2.5, secColor, a,
            true, "normal", "none", "miter");
        mc.moveTo(x - dirX * chLen, y - dirY * chLen);
        mc.lineTo(x - dirX * chGap, y - dirY * chGap);
        mc.moveTo(x + dirX * chLen, y + dirY * chLen);
        mc.lineTo(x + dirX * chGap, y + dirY * chGap);
        mc.moveTo(x - pX * chLen, y - pY * chLen);
        mc.lineTo(x - pX * chGap, y - pY * chGap);
        mc.moveTo(x + pX * chLen, y + pY * chLen);
        mc.lineTo(x + pX * chGap, y + pY * chGap);
        mc.lineStyle(undefined);

        // 5. 精密碎片 (细长扇形约束)
        if (isHeavy) {
            var spread:Number = Math.PI * 0.45;
            var baseAng:Number = Math.atan2(dirY, dirX);
            for (var fi:Number = 0; fi < 5; fi++) {
                var rAng:Number = baseAng - spread * 0.5
                    + (fi / 4) * spread + age * 0.15;
                var fLen:Number = size * (1.0 + Math.sin(fi * 5.3) * 0.3);
                var fWid:Number = size * 0.3;

                var vX:Number = Math.cos(rAng);
                var vY:Number = Math.sin(rAng);
                var fpX:Number = -vY;
                var fpY:Number = vX;
                var cX:Number = x + vX * size * 0.4;
                var cY:Number = y + vY * size * 0.4;

                mc.lineStyle(undefined);
                mc.beginFill((fi % 2 == 0) ? secColor : priColor,
                    clampAlpha(a * 0.85));
                mc.moveTo(cX, cY);
                mc.lineTo(cX + vX * fLen + fpX * fWid,
                          cY + vY * fLen + fpY * fWid);
                mc.lineTo(cX + vX * (fLen * 1.2),
                          cY + vY * (fLen * 1.2));
                mc.endFill();

                mc.beginFill(0xFFFFFF, clampAlpha(a * 0.9));
                mc.moveTo(cX, cY);
                mc.lineTo(cX + vX * (fLen * 1.2),
                          cY + vY * (fLen * 1.2));
                mc.lineTo(cX + vX * fLen - fpX * (fWid * 0.35),
                          cY + vY * fLen - fpY * (fWid * 0.35));
                mc.endFill();
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 基础图元
    // ════════════════════════════════════════════════════════════════════════

    /** 实体矩形光柱 (梯形截面) */
    private static function drawQuad(
        mc:MovieClip, sx:Number, sy:Number, ex:Number, ey:Number,
        px:Number, py:Number, startW:Number, endW:Number,
        color:Number, alpha:Number
    ):Void {
        if (alpha <= 0) return;
        mc.lineStyle(undefined);
        mc.beginFill(color, alpha);
        mc.moveTo(sx - px * startW, sy - py * startW);
        mc.lineTo(sx + px * startW, sy + py * startW);
        mc.lineTo(ex + px * endW, ey + py * endW);
        mc.lineTo(ex - px * endW, ey - py * endW);
        mc.endFill();
    }

    /** 实体填充圆 (8段二次贝塞尔) */
    private static function drawSolidCircle(
        mc:MovieClip, cx:Number, cy:Number, r:Number,
        color:Number, alpha:Number
    ):Void {
        if (r <= 0 || alpha <= 0) return;
        var k:Number = r * 0.414213562;
        var d:Number = r * 0.707106781;
        mc.lineStyle(undefined);
        mc.beginFill(color, alpha);
        mc.moveTo(cx + r, cy);
        mc.curveTo(cx + r, cy + k, cx + d, cy + d);
        mc.curveTo(cx + k, cy + r, cx, cy + r);
        mc.curveTo(cx - k, cy + r, cx - d, cy + d);
        mc.curveTo(cx - r, cy + k, cx - r, cy);
        mc.curveTo(cx - r, cy - k, cx - d, cy - d);
        mc.curveTo(cx - k, cy - r, cx, cy - r);
        mc.curveTo(cx + k, cy - r, cx + d, cy - d);
        mc.curveTo(cx + r, cy - k, cx + r, cy);
        mc.endFill();
    }

    /** 菱形星芒 (实心填充) */
    private static function drawDiamondFlare(
        mc:MovieClip, cx:Number, cy:Number,
        dirX:Number, dirY:Number,
        length:Number, width:Number,
        color:Number, alpha:Number
    ):Void {
        if (alpha <= 0) return;
        var pX:Number = -dirY;
        var pY:Number = dirX;
        mc.lineStyle(undefined);
        mc.beginFill(color, alpha);
        mc.moveTo(cx + dirX * length, cy + dirY * length);
        mc.lineTo(cx - pX * width, cy - pY * width);
        mc.lineTo(cx - dirX * length, cy - dirY * length);
        mc.lineTo(cx + pX * width, cy + pY * width);
        mc.lineTo(cx + dirX * length, cy + dirY * length);
        mc.endFill();
    }

    /** 空心圆环 (8段二次贝塞尔) */
    private static function drawRing(
        mc:MovieClip, cx:Number, cy:Number,
        radius:Number, thick:Number,
        color:Number, alpha:Number
    ):Void {
        if (radius <= 0 || alpha <= 0) return;
        mc.lineStyle(thick, color, alpha,
            true, "normal", "none", "round");
        var a:Number = radius * 0.414213562;
        var b:Number = radius * 0.707106781;
        mc.moveTo(cx + radius, cy);
        mc.curveTo(cx + radius, cy + a, cx + b, cy + b);
        mc.curveTo(cx + a, cy + radius, cx, cy + radius);
        mc.curveTo(cx - a, cy + radius, cx - b, cy + b);
        mc.curveTo(cx - radius, cy + a, cx - radius, cy);
        mc.curveTo(cx - radius, cy - a, cx - b, cy - b);
        mc.curveTo(cx - a, cy - radius, cx, cy - radius);
        mc.curveTo(cx + a, cy - radius, cx + b, cy - b);
        mc.curveTo(cx + radius, cy - a, cx + radius, cy);
        mc.lineStyle(undefined);
    }

    /** 旋转虚线环 */
    private static function drawDashedRing(
        mc:MovieClip, cx:Number, cy:Number,
        radius:Number, dashes:Number, thick:Number,
        color:Number, alpha:Number, rot:Number
    ):Void {
        if (alpha <= 0) return;
        mc.lineStyle(thick, color, alpha,
            true, "normal", "none", "none");
        var step:Number = (Math.PI * 2) / dashes;
        for (var i:Number = 0; i < dashes; i++) {
            var startA:Number = i * step + rot;
            var endA:Number = startA + step * 0.45;
            mc.moveTo(cx + Math.cos(startA) * radius,
                      cy + Math.sin(startA) * radius);
            mc.lineTo(cx + Math.cos(endA) * radius,
                      cy + Math.sin(endA) * radius);
        }
        mc.lineStyle(undefined);
    }

    /** alpha 安全钳位 [0, 100] */
    private static function clampAlpha(val:Number):Number {
        return (val < 0) ? 0 : ((val > 100) ? 100 : val);
    }
}
