import org.flashNight.arki.render.RayVfxManager;

/**
 * FlameStreamRenderer - 喷火束渲染器
 *
 * 下放自 tools/ray-vfx-prototype/喷火束_视觉原型.py 的多边形分层方案：
 *   • 外层暗烟/暗红锥形填充，提供燃烧体积
 *   • 多条局部火舌错相叠加，避免等宽线条的能量束感
 *   • 黄白核心改为短分段高亮，不贯穿全长
 *   • 阻挡端点用堆火圆盘表达“撞到穿刺上限后截止”
 *
 * 不使用滤镜、渐变和 MovieClip 粒子，只依赖 beginFill/lineTo/lineStyle/drawCircle。
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.arki.render.renderer.FlameStreamRenderer {

    // 默认配置
    private static var DEFAULT_PRIMARY_COLOR:Number = 0xFF6A00;
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFE650;
    private static var DEFAULT_SMOKE_COLOR:Number = 0x3A251B;
    private static var DEFAULT_THICKNESS:Number = 14;
    private static var DEFAULT_WAVE_AMP:Number = 28;
    private static var DEFAULT_WAVE_LEN:Number = 120;
    private static var DEFAULT_WAVE_SPEED:Number = 0.55;
    private static var DEFAULT_PULSE_AMP:Number = 0.12;
    private static var DEFAULT_PULSE_RATE:Number = 0.35;
    private static var DEFAULT_HIT_RIPPLE_SIZE:Number = 12;
    private static var DEFAULT_HIT_RIPPLE_ALPHA:Number = 45;
    private static var DEFAULT_TONGUE_COUNT:Number = 5;
    private static var DEFAULT_TIP_BLOOM_SCALE:Number = 1.0;

    // 固定调色
    private static var DEEP_COLOR:Number = 0x5A1400;
    private static var OUTER_COLOR:Number = 0x9C2A00;
    private static var HOT_ORANGE_COLOR:Number = 0xFF9A12;
    private static var HOT_COLOR:Number = 0xFFF3B0;
    private static var WHITE_CORE_COLOR:Number = 0xFFF8D2;

    private static var PI:Number = 3.141592653589793;
    private static var EDGE_NOISE_FREQ:Number = 20.0;
    private static var EDGE_NOISE_SPEED:Number = 1.1;

    /**
     * 渲染喷火束。
     *
     * @param arc 电弧数据对象
     * @param lod 当前 LOD 等级 (0=高, 1=中, 2=低)
     * @param mc  目标 MovieClip
     */
    public static function render(arc:Object, lod:Number, mc:MovieClip):Void {
        var config:Object = arc.config;
        var meta:Object = arc.meta;
        var age:Number = (arc.phaseAge != undefined) ? Number(arc.phaseAge) : arc.age;

        mc.blendMode = "normal";
        var bodyMc:MovieClip = prepareLayer(mc, "flameBody", 1, "normal");
        var glowMc:MovieClip = prepareLayer(mc, "flameGlow", 2, "add");

        var primaryColor:Number   = RayVfxManager.cfgNum(config, "primaryColor", DEFAULT_PRIMARY_COLOR);
        var secondaryColor:Number = RayVfxManager.cfgNum(config, "secondaryColor", DEFAULT_SECONDARY_COLOR);
        var smokeColor:Number     = RayVfxManager.cfgNum(config, "smokeColor", DEFAULT_SMOKE_COLOR);
        var thickness:Number      = RayVfxManager.cfgNum(config, "thickness", DEFAULT_THICKNESS);
        var waveAmp:Number        = RayVfxManager.cfgNum(config, "waveAmp", DEFAULT_WAVE_AMP);
        var waveLen:Number        = RayVfxManager.cfgNum(config, "waveLen", DEFAULT_WAVE_LEN);
        var waveSpeed:Number      = RayVfxManager.cfgNum(config, "waveSpeed", DEFAULT_WAVE_SPEED);
        var pulseAmp:Number       = RayVfxManager.cfgNum(config, "pulseAmp", DEFAULT_PULSE_AMP);
        var pulseRate:Number      = RayVfxManager.cfgNum(config, "pulseRate", DEFAULT_PULSE_RATE);
        var hitRippleSize:Number  = RayVfxManager.cfgNum(config, "hitRippleSize", DEFAULT_HIT_RIPPLE_SIZE);
        var hitRippleAlpha:Number = RayVfxManager.cfgNum(config, "hitRippleAlpha", DEFAULT_HIT_RIPPLE_ALPHA);
        var tongueCount:Number    = RayVfxManager.cfgNum(config, "tongueCount", DEFAULT_TONGUE_COUNT);
        var tipBloomScale:Number  = RayVfxManager.cfgNum(config, "tipBloomScale", DEFAULT_TIP_BLOOM_SCALE);

        var pulseIndex:Number = 0;
        var pulseCount:Number = 1;
        var isHotPulse:Boolean = false;
        var isDamagePulse:Boolean = true;
        var shotSeed:Number = 0;
        if (meta != null) {
            if (meta.pulseIndex != undefined) pulseIndex = Number(meta.pulseIndex);
            if (meta.pulseCount != undefined) pulseCount = Number(meta.pulseCount);
            isHotPulse = (meta.isHotPulse == true);
            isDamagePulse = (meta.isDamagePulse != false);
            if (meta.shotSeed != undefined) shotSeed = Number(meta.shotSeed);
        }
        if (!(pulseIndex >= 0)) pulseIndex = 0;
        if (!(pulseCount > 0)) pulseCount = 1;
        if (pulseIndex >= pulseCount) pulseIndex = pulseCount - 1;

        age += shotSeed + pulseIndex * 0.83;

        if (isHotPulse) {
            primaryColor = HOT_ORANGE_COLOR;
            secondaryColor = WHITE_CORE_COLOR;
            smokeColor = 0x4A2414;
            thickness *= 1.08;
            waveAmp *= 1.12;
            tongueCount += 1;
            hitRippleAlpha *= 1.22;
        } else if (pulseIndex >= 4) {
            primaryColor = 0xC83A00;
            secondaryColor = 0xFF9720;
            smokeColor = 0x2B211A;
            thickness *= 0.90;
            waveAmp *= 0.88;
            hitRippleAlpha *= 0.72;
        } else if (pulseIndex >= 3) {
            primaryColor = 0xE64A00;
            secondaryColor = 0xFFB233;
            smokeColor = 0x33241B;
            thickness *= 0.96;
            waveAmp *= 0.96;
            hitRippleAlpha *= 0.86;
        } else if (pulseIndex == 0) {
            primaryColor = 0xFF5A00;
            secondaryColor = 0xFFD24A;
            smokeColor = 0x3D2118;
        }

        if (!isDamagePulse) {
            thickness *= 0.82;
            waveAmp *= 0.92;
            hitRippleAlpha *= 0.50;
        }

        var intensity:Number = RayVfxManager.cfgIntensity(meta);
        thickness *= intensity;
        waveAmp *= intensity;

        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (!(dist > 0)) return;

        var dirX:Number = dx / dist;
        var dirY:Number = dy / dist;
        var perpX:Number = -dy / dist;
        var perpY:Number = dx / dist;

        var blocked:Boolean = (meta != null && meta.isBlocked == true);
        var pulseFactor:Number = 1.0 + pulseAmp * Math.sin(age * pulseRate * 2 * PI);
        var currentThick:Number = thickness * pulseFactor;

        var polySteps:Number;
        var tongueSteps:Number;
        var edgeStreaks:Number;
        if (lod <= 0) {
            polySteps = 24;
            tongueSteps = 16;
            edgeStreaks = 6;
            if (tongueCount > 5) tongueCount = 5;
        } else if (lod == 1) {
            polySteps = 16;
            tongueSteps = 10;
            edgeStreaks = 3;
            if (tongueCount > 3) tongueCount = 3;
        } else {
            polySteps = 8;
            tongueSteps = 6;
            edgeStreaks = 0;
            tongueCount = 0;
        }
        if (!(tongueCount > 0)) tongueCount = 0;

        var outerBase:Number = currentThick * 0.56;
        var outerMax:Number = currentThick * 3.70;
        var bodyBase:Number = currentThick * 0.30;
        var bodyMax:Number = currentThick * 2.45;
        var hotMax:Number = currentThick * 1.30;
        var edgeAmp:Number = currentThick * 0.46;
        var waveFreq:Number = Math.max(5, Math.min(14, dist / Math.max(60, waveLen) * 2.0));
        var outerWaveFreq:Number = waveFreq * 0.67;
        var outerWaveAmp:Number = waveAmp * 1.35;
        var freeTip:Number = blocked ? 0 : currentThick * 1.7;

        // 暗烟底层
        drawFlamePolygon(bodyMc, arc, dirX, dirY, perpX, perpY, dist, age,
            smokeColor, 16, outerBase + currentThick * 0.22, outerMax + currentThick * 1.55,
            outerWaveAmp * 1.08, outerWaveFreq * 0.85, waveSpeed, 2.1,
            1.0, polySteps, edgeAmp, 1.22, freeTip * 1.4);

        // 深红外缘
        drawFlamePolygon(bodyMc, arc, dirX, dirY, perpX, perpY, dist, age,
            DEEP_COLOR, 24, outerBase + currentThick * 0.08, outerMax + currentThick * 0.72,
            outerWaveAmp * 1.18, outerWaveFreq * 1.05, waveSpeed, 3.6,
            0.94, polySteps, edgeAmp, 1.10, freeTip * 1.1);

        // 暗红主外焰
        drawFlamePolygon(bodyMc, arc, dirX, dirY, perpX, perpY, dist, age,
            OUTER_COLOR, 42, outerBase, outerMax,
            outerWaveAmp, outerWaveFreq, waveSpeed, 0.6,
            1.0, polySteps, edgeAmp, 1.0, freeTip);

        // 错相外焰，打散规则锥形
        drawFlamePolygon(bodyMc, arc, dirX, dirY, perpX, perpY, dist, age,
            OUTER_COLOR, 30, outerBase * 0.70, outerMax * 0.72,
            outerWaveAmp * 0.78, outerWaveFreq * 1.28, waveSpeed, 4.8,
            0.88, polySteps, edgeAmp, 1.35, freeTip * 0.8);

        // 橙色主体
        drawFlamePolygon(bodyMc, arc, dirX, dirY, perpX, perpY, dist, age,
            primaryColor, 72, bodyBase, bodyMax,
            waveAmp, waveFreq, waveSpeed, 1.9,
            0.96, polySteps, edgeAmp, 0.82, freeTip * 0.8);

        // 局部火舌层
        drawHotTongues(glowMc, arc, dirX, dirY, perpX, perpY, dist, age,
            primaryColor, secondaryColor, waveAmp, waveFreq, waveSpeed,
            hotMax, edgeAmp, tongueSteps, tongueCount);

        // 短黄焰面
        drawFlamePolygon(glowMc, arc, dirX, dirY, perpX, perpY, dist, age,
            secondaryColor, 36, bodyBase * 0.45, hotMax * 0.72,
            waveAmp * 0.38, waveFreq * 0.80, waveSpeed, 3.2,
            0.64, tongueSteps, edgeAmp, 0.45, freeTip * 0.35);

        drawCoreSegments(glowMc, arc, dirX, dirY, perpX, perpY, dist, age,
            secondaryColor, currentThick, waveSpeed);
        drawPulseBand(glowMc, arc, dirX, dirY, perpX, perpY, dist, age,
            currentThick, pulseIndex, pulseCount, isHotPulse, isDamagePulse, secondaryColor);

        drawMuzzleBloom(glowMc, arc, dirX, dirY, currentThick, secondaryColor, primaryColor, age);
        drawTipPile(bodyMc, arc, dirX, dirY, perpX, perpY, dist, age,
            blocked, currentThick, tipBloomScale, primaryColor, secondaryColor, waveAmp, waveFreq, waveSpeed);
        drawEdgeStreaks(glowMc, arc, dirX, dirY, perpX, perpY, dist, age,
            blocked, edgeStreaks, outerBase, outerMax, outerWaveAmp, outerWaveFreq, waveSpeed);

        if (lod < 1 && meta != null) {
            var hitPoints:Array = (meta.damageHitPoints != null) ? meta.damageHitPoints : meta.hitPoints;
            if (hitPoints == null) return;
            for (var i:Number = 0; i < hitPoints.length; i++) {
                var hp:Object = hitPoints[i];
                RayVfxManager.drawCircle(glowMc, hp.x, hp.y, hitRippleSize, secondaryColor, hitRippleAlpha);
                RayVfxManager.drawCircle(glowMc, hp.x, hp.y, hitRippleSize * 0.45, HOT_COLOR, hitRippleAlpha * 1.2);
            }
        }
    }

    private static function prepareLayer(parent:MovieClip, name:String, depth:Number, blend:String):MovieClip {
        var layer:MovieClip = parent[name];
        if (layer == null) {
            layer = parent.createEmptyMovieClip(name, depth);
        }
        layer.clear();
        layer._alpha = 100;
        if (layer.blendMode !== undefined) {
            layer.blendMode = blend;
        }
        return layer;
    }

    private static function drawFlamePolygon(mc:MovieClip, arc:Object,
                                             dirX:Number, dirY:Number, perpX:Number, perpY:Number,
                                             dist:Number, age:Number, color:Number, alpha:Number,
                                             baseHalfWidth:Number, maxHalfWidth:Number,
                                             waveAmp:Number, waveFreq:Number, waveSpeed:Number,
                                             phase:Number, lengthScale:Number, steps:Number,
                                             edgeAmp:Number, edgeScale:Number, tipExtension:Number):Void {
        if (!(alpha > 0) || !(dist > 0)) return;

        var drawLen:Number = Math.max(1, dist * lengthScale);
        var i:Number;
        var t:Number;
        var x:Number;
        var y:Number;
        var coneW:Number;
        var ripple:Number;
        var topW:Number;
        var botW:Number;
        var off:Number;

        mc.lineStyle(undefined);
        mc.beginFill(color, clampAlpha(alpha));

        for (i = 0; i <= steps; i++) {
            t = i / steps;
            x = arc.startX + dirX * drawLen * t;
            y = arc.startY + dirY * drawLen * t;
            off = axisOffset(t, age, waveAmp, waveFreq, waveSpeed, phase);
            x += perpX * off;
            y += perpY * off;
            coneW = baseHalfWidth + (maxHalfWidth - baseHalfWidth) * t;
            ripple = edgeNoise(t, age, phase, edgeAmp) * edgeScale;
            topW = Math.max(1, coneW + ripple);
            if (i == 0) {
                mc.moveTo(x - perpX * topW, y - perpY * topW);
            } else {
                mc.lineTo(x - perpX * topW, y - perpY * topW);
            }
        }

        if (tipExtension > 0) {
            off = axisOffset(1, age, waveAmp, waveFreq, waveSpeed, phase);
            off += edgeNoise(1, age, phase + 1.1, edgeAmp) * 0.45;
            mc.lineTo(
                arc.startX + dirX * (drawLen + tipExtension) + perpX * off,
                arc.startY + dirY * (drawLen + tipExtension) + perpY * off
            );
        }

        for (i = steps; i >= 0; i--) {
            t = i / steps;
            x = arc.startX + dirX * drawLen * t;
            y = arc.startY + dirY * drawLen * t;
            off = axisOffset(t, age, waveAmp, waveFreq, waveSpeed, phase);
            x += perpX * off;
            y += perpY * off;
            coneW = baseHalfWidth + (maxHalfWidth - baseHalfWidth) * t;
            ripple = edgeNoise(t, age, phase, edgeAmp) * edgeScale;
            botW = Math.max(1, coneW - ripple * 0.65);
            mc.lineTo(x + perpX * botW, y + perpY * botW);
        }

        mc.endFill();
    }

    private static function drawHotTongues(mc:MovieClip, arc:Object,
                                           dirX:Number, dirY:Number, perpX:Number, perpY:Number,
                                           dist:Number, age:Number, primaryColor:Number, secondaryColor:Number,
                                           waveAmp:Number, waveFreq:Number, waveSpeed:Number,
                                           hotMax:Number, edgeAmp:Number, steps:Number, count:Number):Void {
        if (count > 0) {
            drawTongueLayer(mc, arc, dirX, dirY, perpX, perpY, dist, age,
                primaryColor, 38, 0.04, 0.96, hotMax * 0.82,
                waveAmp * 0.92, waveFreq * 0.96, waveSpeed, 0.4, -hotMax * 0.38, edgeAmp, steps);
        }
        if (count > 1) {
            drawTongueLayer(mc, arc, dirX, dirY, perpX, perpY, dist, age,
                HOT_ORANGE_COLOR, 58, 0.02, 0.78, hotMax * 0.58,
                waveAmp * 0.56, waveFreq * 1.12, waveSpeed, 2.4, hotMax * 0.32, edgeAmp, steps);
        }
        if (count > 2) {
            drawTongueLayer(mc, arc, dirX, dirY, perpX, perpY, dist, age,
                secondaryColor, 42, 0.08, 0.68, hotMax * 0.42,
                waveAmp * 0.34, waveFreq * 0.85, waveSpeed, 4.0, -hotMax * 0.12, edgeAmp, steps);
        }
        if (count > 3) {
            drawTongueLayer(mc, arc, dirX, dirY, perpX, perpY, dist, age,
                HOT_ORANGE_COLOR, 34, 0.30, 0.98, hotMax * 0.66,
                waveAmp * 1.12, waveFreq * 1.35, waveSpeed, 5.3, hotMax * 0.54, edgeAmp, steps);
        }
        if (count > 4) {
            drawTongueLayer(mc, arc, dirX, dirY, perpX, perpY, dist, age,
                WHITE_CORE_COLOR, 26, 0.10, 0.56, hotMax * 0.24,
                waveAmp * 0.18, waveFreq * 0.70, waveSpeed, 1.6, hotMax * 0.06, edgeAmp, steps);
        }
    }

    private static function drawTongueLayer(mc:MovieClip, arc:Object,
                                            dirX:Number, dirY:Number, perpX:Number, perpY:Number,
                                            dist:Number, age:Number, color:Number, alpha:Number,
                                            startT:Number, endT:Number, maxHalfWidth:Number,
                                            waveAmp:Number, waveFreq:Number, waveSpeed:Number,
                                            phase:Number, yBias:Number, edgeAmp:Number, steps:Number):Void {
        if (dist < 80 || !(alpha > 0)) return;

        if (startT < 0) startT = 0;
        if (startT > 0.96) startT = 0.96;
        if (endT > 1) endT = 1;
        if (endT < startT + 0.04) endT = startT + 0.04;

        var i:Number;
        var u:Number;
        var t:Number;
        var x:Number;
        var y:Number;
        var envelope:Number;
        var tailBias:Number;
        var pulse:Number;
        var halfW:Number;
        var ripple:Number;
        var off:Number;

        mc.lineStyle(undefined);
        mc.beginFill(color, clampAlpha(alpha));

        for (i = 0; i <= steps; i++) {
            u = i / steps;
            t = startT + (endT - startT) * u;
            x = arc.startX + dirX * dist * t;
            y = arc.startY + dirY * dist * t;
            off = axisOffset(t, age, waveAmp, waveFreq, waveSpeed, phase);
            off += yBias * Math.sin(PI * u) * (0.35 + t * 0.75);
            x += perpX * off;
            y += perpY * off;

            envelope = Math.sin(PI * u);
            tailBias = 0.70 + t * 0.42;
            pulse = 0.92 + 0.10 * Math.sin(age * 0.78 + phase);
            halfW = Math.max(1.4, maxHalfWidth * (0.16 + 0.84 * Math.pow(envelope, 0.62)) * tailBias * pulse);
            ripple = edgeNoise(t, age, phase + 2.7, edgeAmp) * 0.55;

            if (i == 0) {
                mc.moveTo(x - perpX * Math.max(1, halfW + ripple), y - perpY * Math.max(1, halfW + ripple));
            } else {
                mc.lineTo(x - perpX * Math.max(1, halfW + ripple), y - perpY * Math.max(1, halfW + ripple));
            }
        }

        off = axisOffset(endT, age, waveAmp, waveFreq, waveSpeed, phase);
        off += edgeNoise(endT, age, phase + 1.4, edgeAmp) * 0.28;
        mc.lineTo(
            arc.startX + dirX * (dist * endT + maxHalfWidth * 0.42) + perpX * off,
            arc.startY + dirY * (dist * endT + maxHalfWidth * 0.42) + perpY * off
        );

        for (i = steps; i >= 0; i--) {
            u = i / steps;
            t = startT + (endT - startT) * u;
            x = arc.startX + dirX * dist * t;
            y = arc.startY + dirY * dist * t;
            off = axisOffset(t, age, waveAmp, waveFreq, waveSpeed, phase);
            off += yBias * Math.sin(PI * u) * (0.35 + t * 0.75);
            x += perpX * off;
            y += perpY * off;

            envelope = Math.sin(PI * u);
            tailBias = 0.70 + t * 0.42;
            pulse = 0.92 + 0.10 * Math.sin(age * 0.78 + phase);
            halfW = Math.max(1.4, maxHalfWidth * (0.16 + 0.84 * Math.pow(envelope, 0.62)) * tailBias * pulse);
            ripple = edgeNoise(t, age, phase + 2.7, edgeAmp) * 0.55;
            mc.lineTo(x + perpX * Math.max(1, halfW - ripple * 0.75), y + perpY * Math.max(1, halfW - ripple * 0.75));
        }

        mc.endFill();
    }

    private static function drawCoreSegments(mc:MovieClip, arc:Object,
                                             dirX:Number, dirY:Number, perpX:Number, perpY:Number,
                                             dist:Number, age:Number, coreColor:Number,
                                             currentThick:Number, waveSpeed:Number):Void {
        var coreLen:Number = Math.max(20, dist * 0.50);
        var coreTMax:Number = Math.min(1, coreLen / Math.max(1, dist));
        drawCoreRange(mc, arc, dirX, dirY, perpX, perpY, coreLen, coreTMax, age,
            coreColor, currentThick * 0.40, 46, 0.00, 0.58, waveSpeed);
        drawCoreRange(mc, arc, dirX, dirY, perpX, perpY, coreLen, coreTMax, age,
            HOT_COLOR, currentThick * 0.23, 72, 0.00, 0.28, waveSpeed);
        drawCoreRange(mc, arc, dirX, dirY, perpX, perpY, coreLen, coreTMax, age,
            HOT_COLOR, currentThick * 0.23, 72, 0.36, 0.46, waveSpeed);
        drawCoreRange(mc, arc, dirX, dirY, perpX, perpY, coreLen, coreTMax, age,
            HOT_COLOR, currentThick * 0.23, 72, 0.54, 0.60, waveSpeed);
        drawCoreRange(mc, arc, dirX, dirY, perpX, perpY, coreLen, coreTMax, age,
            WHITE_CORE_COLOR, currentThick * 0.09, 86, 0.00, 0.20, waveSpeed);
        drawCoreRange(mc, arc, dirX, dirY, perpX, perpY, coreLen, coreTMax, age,
            WHITE_CORE_COLOR, currentThick * 0.09, 86, 0.34, 0.40, waveSpeed);
    }

    private static function drawCoreRange(mc:MovieClip, arc:Object,
                                           dirX:Number, dirY:Number, perpX:Number, perpY:Number,
                                           coreLen:Number, coreTMax:Number, age:Number,
                                           color:Number, thickness:Number, alpha:Number,
                                           startU:Number, endU:Number, waveSpeed:Number):Void {
        var steps:Number = 5;
        var i:Number;
        var u:Number;
        var t:Number;
        var off:Number;
        var x:Number;
        var y:Number;

        mc.lineStyle(thickness, color, clampAlpha(alpha), true, "normal", "round", "round", 3);
        for (i = 0; i <= steps; i++) {
            u = startU + (endU - startU) * (i / steps);
            t = coreTMax * u;
            off = axisOffset(t, age, 2.2, 9.0, waveSpeed * 0.48, 0.0);
            x = arc.startX + dirX * coreLen * u + perpX * off;
            y = arc.startY + dirY * coreLen * u + perpY * off;
            if (i == 0) {
                mc.moveTo(x, y);
            } else {
                mc.lineTo(x, y);
            }
        }
    }

    private static function drawPulseBand(mc:MovieClip, arc:Object,
                                          dirX:Number, dirY:Number, perpX:Number, perpY:Number,
                                          dist:Number, age:Number, currentThick:Number,
                                          pulseIndex:Number, pulseCount:Number,
                                          isHotPulse:Boolean, isDamagePulse:Boolean,
                                          pulseColor:Number):Void {
        if (!(dist > 60) || !(pulseCount > 0)) return;

        var maxMarks:Number = Math.min(5, pulseIndex + 1);
        var markColor:Number = isHotPulse ? WHITE_CORE_COLOR : pulseColor;
        var markAlpha:Number = isHotPulse ? 72 : 48;
        if (!isDamagePulse) markAlpha *= 0.42;

        for (var k:Number = 0; k < maxMarks; k++) {
            var kt:Number = 0.16 + 0.64 * ((k + 0.5) / pulseCount);
            if (kt > 0.92) kt = 0.92;
            var koff:Number = axisOffset(kt, age, currentThick * 0.14, 8.0, 0.36, k * 1.17);
            var kx:Number = arc.startX + dirX * dist * kt + perpX * koff;
            var ky:Number = arc.startY + dirY * dist * kt + perpY * koff;
            var kr:Number = currentThick * (k == pulseIndex ? 0.38 : 0.22);
            var ka:Number = (k == pulseIndex) ? markAlpha : markAlpha * 0.34;
            RayVfxManager.drawCircle(mc, kx, ky, kr, markColor, ka);
        }

        if (!isDamagePulse) return;

        var t:Number = 0.16 + 0.64 * ((pulseIndex + 0.5) / pulseCount);
        if (t > 0.92) t = 0.92;
        var off:Number = axisOffset(t, age, currentThick * 0.18, 8.0, 0.42, pulseIndex * 1.31);
        var x:Number = arc.startX + dirX * dist * t + perpX * off;
        var y:Number = arc.startY + dirY * dist * t + perpY * off;
        var half:Number = currentThick * (isHotPulse ? 1.18 : 0.82);
        var slant:Number = currentThick * 0.42;

        mc.lineStyle(currentThick * (isHotPulse ? 0.22 : 0.16), markColor,
            clampAlpha(isHotPulse ? 78 : 52), true, "normal", "round", "round", 3);
        mc.moveTo(x - perpX * half - dirX * slant, y - perpY * half - dirY * slant);
        mc.lineTo(x + perpX * half + dirX * slant, y + perpY * half + dirY * slant);
    }

    private static function drawMuzzleBloom(mc:MovieClip, arc:Object,
                                            dirX:Number, dirY:Number, currentThick:Number,
                                            secondaryColor:Number, primaryColor:Number, age:Number):Void {
        var pulse:Number = 1.0 + Math.sin(age * 1.2) * 0.08;
        RayVfxManager.drawCircle(mc, arc.startX + dirX * 5, arc.startY + dirY * 5,
            currentThick * 0.93 * pulse, WHITE_CORE_COLOR, 78);
        RayVfxManager.drawCircle(mc, arc.startX + dirX * 12, arc.startY + dirY * 12,
            currentThick * 1.42 * pulse, secondaryColor, 54);
        RayVfxManager.drawCircle(mc, arc.startX + dirX * 20, arc.startY + dirY * 20,
            currentThick * 2.20 * pulse, primaryColor, 24);
    }

    private static function drawTipPile(mc:MovieClip, arc:Object,
                                        dirX:Number, dirY:Number, perpX:Number, perpY:Number,
                                        dist:Number, age:Number, blocked:Boolean, currentThick:Number,
                                        tipBloomScale:Number, primaryColor:Number, secondaryColor:Number,
                                        waveAmp:Number, waveFreq:Number, waveSpeed:Number):Void {
        var tipScale:Number = tipBloomScale * (blocked ? 1.8 : 0.8);
        var backoff:Number = blocked ? currentThick * 0.55 : 0;
        var tipX:Number = arc.endX - dirX * backoff;
        var tipY:Number = arc.endY - dirY * backoff;
        var off:Number = axisOffset(1.0, age, blocked ? waveAmp * 0.45 : waveAmp, waveFreq, waveSpeed, 1.3);
        tipX += perpX * off;
        tipY += perpY * off;

        var pulse:Number = 1.0 + Math.sin(age * 1.7) * (blocked ? 0.18 : 0.08);
        RayVfxManager.drawCircle(mc, tipX - dirX * currentThick * 0.65 + perpX * currentThick * 0.35,
            tipY - dirY * currentThick * 0.65 + perpY * currentThick * 0.35,
            currentThick * 2.25 * tipScale * pulse, DEEP_COLOR, 26);
        RayVfxManager.drawCircle(mc, tipX + dirX * currentThick * 0.30 - perpX * currentThick * 0.22,
            tipY + dirY * currentThick * 0.30 - perpY * currentThick * 0.22,
            currentThick * 1.70 * tipScale * pulse, OUTER_COLOR, 36);
        RayVfxManager.drawCircle(mc, tipX + dirX * currentThick * 0.55 + perpX * currentThick * 0.28,
            tipY + dirY * currentThick * 0.55 + perpY * currentThick * 0.28,
            currentThick * 1.20 * tipScale * pulse, primaryColor, 86);
        RayVfxManager.drawCircle(mc, tipX - dirX * currentThick * 0.15 - perpX * currentThick * 0.15,
            tipY - dirY * currentThick * 0.15 - perpY * currentThick * 0.15,
            currentThick * 0.78 * tipScale, HOT_ORANGE_COLOR, 92);
        RayVfxManager.drawCircle(mc, tipX + dirX * currentThick * 0.20, tipY + dirY * currentThick * 0.20,
            currentThick * 0.42 * tipScale, HOT_COLOR, 100);
    }

    private static function drawEdgeStreaks(mc:MovieClip, arc:Object,
                                            dirX:Number, dirY:Number, perpX:Number, perpY:Number,
                                            dist:Number, age:Number, blocked:Boolean, count:Number,
                                            outerBase:Number, outerMax:Number,
                                            waveAmp:Number, waveFreq:Number, waveSpeed:Number):Void {
        if (!(count > 0) || dist < 180) return;

        for (var k:Number = 0; k < count; k++) {
            var drift:Number = (age * 0.016 + stableNoise(k * 3.7) * 0.12) % 0.18;
            var t:Number = 0.30 + (k + 0.5) / count * 0.62 + drift;
            if (t > 0.98) t -= 0.28;
            if (blocked && t > 0.92) t = 0.88;

            var side:Number = (k % 2 == 0) ? -1.0 : 1.0;
            var off:Number = axisOffset(t, age, waveAmp, waveFreq, waveSpeed, 0.6);
            var width:Number = outerBase + (outerMax - outerBase) * t;
            off += side * (width + 3.0 + stableNoise(k + 9.0) * 10.0);

            var x:Number = arc.startX + dirX * dist * t + perpX * off;
            var y:Number = arc.startY + dirY * dist * t + perpY * off;
            var lineLen:Number = 14.0 + stableNoise(k + Math.floor(age) * 0.11) * 24.0;
            var sideDrift:Number = side * (3.0 + 8.0 * stableNoise(k + 4.0));
            var color:Number = (k % 3 == 0) ? HOT_COLOR : HOT_ORANGE_COLOR;
            var alpha:Number = 36 + stableNoise(k + 1.0) * 28;

            mc.lineStyle(1.1 + stableNoise(k + 2.0) * 1.4, color, clampAlpha(alpha), true, "normal", "round", "round", 3);
            mc.moveTo(x, y);
            mc.lineTo(x + dirX * lineLen + perpX * sideDrift, y + dirY * lineLen + perpY * sideDrift);
        }
    }

    private static function axisOffset(t:Number, age:Number, amp:Number, freq:Number, speed:Number, phase:Number):Number {
        var t2:Number = t * t;
        var primary:Number = Math.sin(t * freq - age * speed + phase);
        var secondary:Number = 0.35 * Math.sin(t * freq * 1.83 + age * speed * 0.72 + phase * 0.5);
        return (primary + secondary) * amp * t2;
    }

    private static function edgeNoise(t:Number, age:Number, phase:Number, amp:Number):Number {
        return Math.sin(t * EDGE_NOISE_FREQ - age * EDGE_NOISE_SPEED + phase) * amp * t;
    }

    private static function stableNoise(seed:Number):Number {
        var v:Number = Math.sin(seed * 12.9898) * 43758.5453;
        return v - Math.floor(v);
    }

    private static function clampAlpha(alpha:Number):Number {
        if (!(alpha > 0)) return 0;
        if (alpha > 100) return 100;
        return alpha;
    }
}
