import org.flashNight.arki.render.RayVfxManager;

/**
 * WaveRenderer - 波能射线渲染器 (RA3 深度还原版 v6)
 *
 * v6 核心变更（基于四模型交叉审阅）：
 *
 * 1. drawCircle 底层已修复（RayVfxManager: 8段curveTo+beginFill填充圆盘）
 *    → 彻底消除"八边形/六边形空心护盾"伪影
 *
 * 2. 删除 drawCircle 节点，改用"能量光矛"(Energy Lance)
 *    → 沿射线方向的圆角粗线段，round 线帽天然形成运动模糊胶囊体
 *    → 消除"冰糖葫芦"静态球体感，重现 RA3 高速流动的能量脉冲
 *
 * 3. 波纹大幅弱化：振幅 12→5，成为半透明等离子鞘
 *    → 不再是"发光铁丝弹簧"，而是隐约的高温气体包裹层
 *
 * 4. 新增管道填充层 (Tube Fill)
 *    → 中等宽度直线泛光填充螺旋间隙，形成 RA3 能量圆柱轮廓
 *
 * 5. 超宽三层 Bloom → 模拟 RA3 高温辉光溢出
 *
 * 6. 波长拉伸至200 + 波速2.2 → 真正的高速拉伸能量流
 *
 * 渲染层级（后→前）：
 *   L0: 超宽大气泛光 (straight, α6+α12+α20)
 *   L1: 管道填充 (straight, α25) → 填充螺旋间隙
 *   L2: 极淡等离子鞘 (wave×2, α25+α50)
 *   L3: 核心主轴 (straight, α85+α100)
 *   L4: ★能量光矛 (lance segments, round caps → 运动模糊胶囊)
 *   → 炮口辉光 → 命中点爆破
 *
 * LOD 降级：
 *   LOD 0: 全特效（双螺旋鞘 + 光矛 + 炮口辉光 + 命中波纹）
 *   LOD 1: 单螺旋鞘（无光矛、无命中波纹、无炮口辉光）
 *   LOD 2: 纯直线（无螺旋）
 *
 * @author FlashNight
 * @version 6.0
 */
class org.flashNight.arki.render.renderer.WaveRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置（v6: 贴近 RA3 参数组合）
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY_COLOR:Number = 0x0099FF;    // 电光蓝
    private static var DEFAULT_SECONDARY_COLOR:Number = 0x77EEFF;  // 亮青白
    private static var DEFAULT_THICKNESS:Number = 8;               // 加粗基准
    private static var DEFAULT_WAVE_AMP:Number = 7;                // 低振幅等离子鞘，微可见包裹质感
    private static var DEFAULT_WAVE_LEN:Number = 200;              // ★ 拉伸波长，高速流感
    private static var DEFAULT_WAVE_SPEED:Number = 2.2;            // ★ 快速流动
    private static var DEFAULT_PULSE_AMP:Number = 0.12;            // 呼吸脉冲
    private static var DEFAULT_PULSE_RATE:Number = 0.35;           // 呼吸频率
    private static var DEFAULT_HIT_RIPPLE_SIZE:Number = 25;        // 命中点波纹大小
    private static var DEFAULT_HIT_RIPPLE_ALPHA:Number = 70;       // 命中点波纹透明度

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染波能射线
     *
     * @param arc 电弧数据对象 {startX, startY, endX, endY, age, config, meta}
     * @param lod 当前 LOD 等级 (0=高, 1=中, 2=低)
     * @param mc  目标 MovieClip
     */
    public static function render(arc:Object, lod:Number, mc:MovieClip):Void {
        var config:Object = arc.config;
        var meta:Object = arc.meta;
        var age:Number = arc.age;
        var VM:Function = RayVfxManager;

        // 解析配置参数
        var primaryColor:Number   = VM.cfgNum(config, "primaryColor", DEFAULT_PRIMARY_COLOR);
        var secondaryColor:Number = VM.cfgNum(config, "secondaryColor", DEFAULT_SECONDARY_COLOR);
        var thickness:Number      = VM.cfgNum(config, "thickness", DEFAULT_THICKNESS);
        var waveAmp:Number        = VM.cfgNum(config, "waveAmp", DEFAULT_WAVE_AMP);
        var waveLen:Number        = VM.cfgNum(config, "waveLen", DEFAULT_WAVE_LEN);
        var waveSpeed:Number      = VM.cfgNum(config, "waveSpeed", DEFAULT_WAVE_SPEED);
        var pulseAmp:Number       = VM.cfgNum(config, "pulseAmp", DEFAULT_PULSE_AMP);
        var pulseRate:Number      = VM.cfgNum(config, "pulseRate", DEFAULT_PULSE_RATE);
        var hitRippleSize:Number  = VM.cfgNum(config, "hitRippleSize", DEFAULT_HIT_RIPPLE_SIZE);
        var hitRippleAlpha:Number = VM.cfgNum(config, "hitRippleAlpha", DEFAULT_HIT_RIPPLE_ALPHA);

        // 应用 intensity 强度因子
        var intensity:Number = VM.cfgIntensity(meta);
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

        var dirX:Number = dx / dist;
        var dirY:Number = dy / dist;
        var perpX:Number = -dirY;
        var perpY:Number = dirX;

        // 全局加色混合
        mc.blendMode = "add";

        // 呼吸脉冲
        var pulseFactor:Number = 1.0;
        if (enablePulse) {
            pulseFactor = 1.0 + pulseAmp * Math.sin(age * pulseRate * 2 * Math.PI);
        }
        var T:Number = thickness * pulseFactor;

        // ─────────────────────────────────────────────────────────────
        // 路径生成：笔直主轴 + 对称双螺旋（低振幅等离子鞘）
        // ─────────────────────────────────────────────────────────────

        var pathStraight:Array = generateStraightPath(arc);
        var pathWave1:Array = null;
        var pathWave2:Array = null;

        if (enableWave) {
            pathWave1 = generateWavePath(arc, perpX, perpY, dist,
                waveAmp, waveLen, waveSpeed, age, 0);
            if (lod == 0) {
                pathWave2 = generateWavePath(arc, perpX, perpY, dist,
                    waveAmp, waveLen, waveSpeed, age, Math.PI);
            }
        }

        // ─────────────────────────────────────────────────────────────
        // L0: 超宽大气泛光（RA3 标志性辉光溢出，三层递减）
        // ─────────────────────────────────────────────────────────────

        RayVfxManager.drawPath(mc, pathStraight, primaryColor, T * 14.0, 6);
        RayVfxManager.drawPath(mc, pathStraight, primaryColor, T * 9.0, 12);
        RayVfxManager.drawPath(mc, pathStraight, secondaryColor, T * 5.0, 20);

        // ─────────────────────────────────────────────────────────────
        // L1: 管道填充（填充螺旋间隙，形成 RA3 能量圆柱轮廓）
        // ─────────────────────────────────────────────────────────────

        RayVfxManager.drawPath(mc, pathStraight, primaryColor, T * 3.0, 25);

        // ─────────────────────────────────────────────────────────────
        // L2: 极淡等离子鞘（波纹彻底退为背景包裹层）
        // ─────────────────────────────────────────────────────────────

        if (enableWave) {
            var waveThick:Number = T * 0.8;

            // 波纹 A：蓝色外晕 + 亮青内层，无白芯
            RayVfxManager.drawPath(mc, pathWave1, primaryColor, waveThick * 2.0, 25);
            RayVfxManager.drawPath(mc, pathWave1, secondaryColor, waveThick * 0.8, 50);

            // 波纹 B（LOD 0 专属）
            if (pathWave2 != null) {
                RayVfxManager.drawPath(mc, pathWave2, primaryColor, waveThick * 2.0, 25);
                RayVfxManager.drawPath(mc, pathWave2, secondaryColor, waveThick * 0.8, 50);
            }
        }

        // ─────────────────────────────────────────────────────────────
        // L3: 核心主轴（直线 + 强白芯，RA3 贯穿感的核心）
        // ─────────────────────────────────────────────────────────────

        RayVfxManager.drawPath(mc, pathStraight, secondaryColor, T * 2.0, 85);
        RayVfxManager.drawPath(mc, pathStraight, 0xFFFFFF, T * 0.7, 100);

        // ─────────────────────────────────────────────────────────────
        // L4: ★★★ 能量光矛 (Energy Lance / Motion Blur Slugs)
        //
        //   数学解算双螺旋交汇坐标（同 v5），但不再画圆——
        //   改为沿射线方向的圆角粗线段。round 线帽天然形成
        //   流线型运动模糊胶囊体，消除冰糖葫芦/六边形感。
        //   高速游走的拉伸光矛 >> 静态球体，更贴合 RA3。
        // ─────────────────────────────────────────────────────────────

        if (enableWave && lod == 0) {
            var k_min:Number = Math.ceil(-2 * age * waveSpeed);
            var k_max:Number = Math.floor(2 * (dist / waveLen - age * waveSpeed));

            // 光矛长度 = 波长的45%，强调运动模糊方向感
            var lanceLen:Number = waveLen * 0.45;

            for (var k:Number = k_min; k <= k_max; k++) {
                var nodeDist:Number = (k * 0.5 + age * waveSpeed) * waveLen;
                var t:Number = nodeDist / dist;

                if (t <= 0.03 || t >= 0.97) continue;

                // smoothstep 包络
                var envelope:Number = 1.0;
                var margin:Number = 0.08;
                if (t < margin) {
                    envelope = t / margin;
                } else if (t > 1.0 - margin) {
                    envelope = (1.0 - t) / margin;
                }
                envelope = envelope * envelope * (3 - 2 * envelope);

                if (envelope > 0.05) {
                    var nodeX:Number = arc.startX + dx * t;
                    var nodeY:Number = arc.startY + dy * t;
                    var scale:Number = T * envelope;
                    var curLen:Number = lanceLen * envelope;

                    // 三层递减光矛：round 线帽 → 修长胶囊体
                    // 外层收窄(5→3)避免气泡感，拉长比例强调方向
                    drawLance(mc, nodeX, nodeY, dirX, dirY, curLen,
                        primaryColor, scale * 3.0, 22);
                    drawLance(mc, nodeX, nodeY, dirX, dirY, curLen * 0.75,
                        secondaryColor, scale * 1.5, 75);
                    drawLance(mc, nodeX, nodeY, dirX, dirY, curLen * 0.5,
                        0xFFFFFF, scale * 0.6, 100);
                }
            }
        }

        // ─────────────────────────────────────────────────────────────
        // 炮口辉光球（drawCircle 已修复为平滑填充圆盘）
        // ─────────────────────────────────────────────────────────────

        if (enableRipple) {
            // 填充圆盘比旧描边重很多，缩小半径+降低alpha补偿
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                T * 3.0, primaryColor, 25);
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                T * 1.4, secondaryColor, 55);
            RayVfxManager.drawCircle(mc, arc.startX, arc.startY,
                T * 0.5, 0xFFFFFF, 100);
        }

        // ─────────────────────────────────────────────────────────────
        // pierce 命中点三层爆破波纹
        // ─────────────────────────────────────────────────────────────

        if (enableRipple && meta != null && meta.segmentKind == "pierce" && meta.hitPoints != null) {
            var hitPoints:Array = meta.hitPoints;
            for (var i:Number = 0; i < hitPoints.length; i++) {
                var hp:Object = hitPoints[i];
                var pulseSize:Number = hitRippleSize * pulseFactor;
                // 填充圆盘补偿：缩小半径，降低alpha
                RayVfxManager.drawCircle(mc, hp.x, hp.y,
                    pulseSize * 1.0, primaryColor, hitRippleAlpha * 0.3);
                RayVfxManager.drawCircle(mc, hp.x, hp.y,
                    pulseSize * 0.55, secondaryColor, hitRippleAlpha * 0.7);
                RayVfxManager.drawCircle(mc, hp.x, hp.y,
                    pulseSize * 0.2, 0xFFFFFF, 100);
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 能量光矛绘制
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 绘制能量光矛 —— 沿射线方向的圆角粗线段
     *
     * 利用 Flash lineStyle 的 "round" 线帽（caps），线段两端自然生成
     * 半径 = thickness/2 的半圆，使整体形状为流线型胶囊体（stadium）。
     * 在 additive blend 下，多层递减叠加产生：
     *   外层蓝色大胶囊 → 中层亮青 → 内层白热芯
     * 视觉效果：高速运动模糊的能量弹头，替代静态球体。
     *
     * @param mc    目标 MovieClip
     * @param cx    光矛中心 X
     * @param cy    光矛中心 Y
     * @param dirX  射线方向 X（单位向量）
     * @param dirY  射线方向 Y（单位向量）
     * @param len   光矛总长度
     * @param color 颜色
     * @param thick 线粗（即胶囊直径）
     * @param alpha 透明度 0-100
     */
    private static function drawLance(mc:MovieClip, cx:Number, cy:Number,
                                       dirX:Number, dirY:Number, len:Number,
                                       color:Number, thick:Number, alpha:Number):Void {
        var halfLen:Number = len * 0.5;
        mc.lineStyle(thick, color, alpha, true, "normal", "round", "round", 3);
        mc.moveTo(cx - dirX * halfLen, cy - dirY * halfLen);
        mc.lineTo(cx + dirX * halfLen, cy + dirY * halfLen);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 路径生成
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成纯正弦波路径（委托给 RayVfxManager.generateSinePath）
     */
    private static function generateWavePath(arc:Object, perpX:Number, perpY:Number,
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
     */
    private static function generateStraightPath(arc:Object):Array {
        return RayVfxManager.straightPath(arc.startX, arc.startY, arc.endX, arc.endY);
    }
}
