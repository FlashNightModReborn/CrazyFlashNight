/**
 * ColorEngine.as (ActionScript 2)
 * 位于：org.flashNight.arki.component.Effect
 *
 * 本类封装了一系列色彩引擎相关功能，包括滤镜的设置与删除、色彩调整矩阵的生成与组合、
 * 以及影片剪辑颜色的基础与高级调整。所有方法均为静态方法，可直接调用。
 *
 * 用法示例：
 *   import org.flashNight.arki.component.Effect.ColorEngine;
 *   // 应用投影滤镜
 *   ColorEngine.setDropShadowFilter(myClip, 4, 45, 0x000000, 0.8, 8, 8, 1, 1, false, false, false);
 *   // 调整颜色（使用基础参数）
 *   ColorEngine.basicAdjustColor(myClip, {红色乘数:1, 绿色乘数:1, 蓝色乘数:1, 亮度:20});
 *   // 使用颜色矩阵滤镜进行调整
 *   ColorEngine.adjustColor(myClip, {对比度:50, 饱和度:30, 色相:15});
 */
import flash.geom.ColorTransform;
import flash.filters.*;

class org.flashNight.arki.component.Effect.ColorEngine {

    /**
     * 通用设置滤镜函数
     * 为指定影片剪辑设置指定类型的滤镜，若已存在则替换之。
     *
     * @param target         目标影片剪辑
     * @param filterInstance 滤镜实例
     * @param filterType     滤镜类型（类引用）
     */
    public static function setFilter(target:MovieClip, filterInstance:Object, filterType:Function):Void {
        if (target == null) return;
        var filters:Array = target.filters;
        var found:Boolean = false;
        for (var i:Number = 0; i < filters.length; i++) {
            if (filters[i] instanceof filterType) {
                filters[i] = filterInstance;
                found = true;
                break;
            }
        }
        if (!found) {
            filters.push(filterInstance);
        }
        target.filters = filters;
    }

    /**
     * 检查并删除滤镜
     * 从目标影片剪辑中删除指定类型的滤镜。
     *
     * @param target     目标影片剪辑
     * @param filterType 滤镜类型（类引用）
     */
    public static function checkAndRemoveFilter(target:MovieClip, filterType:Function):Void {
        if (target == null) return;
        var filters:Array = target.filters;
        for (var i:Number = filters.length - 1; i >= 0; i--) {
            if (filters[i] instanceof filterType) {
                filters.splice(i, 1);
            }
        }
        target.filters = filters;
    }

    /**
     * 设置投影滤镜（DropShadowFilter）
     * 若仅传入目标影片剪辑，则删除投影滤镜；否则根据参数设置投影滤镜。
     *
     * @param target      目标影片剪辑
     * @param distance    阴影距离，默认 4
     * @param angle       阴影角度，默认 45
     * @param color       阴影颜色，默认 0x000000
     * @param alpha       阴影透明度，默认 0.8
     * @param blurX       X方向模糊，默认 8
     * @param blurY       Y方向模糊，默认 8
     * @param strength    阴影强度，默认 1
     * @param quality     阴影质量，默认 1
     * @param inner       是否内侧投影，默认 false
     * @param knockout    是否挖空，默认 false
     * @param hideObject  是否隐藏对象，默认 false
     */
    public static function setDropShadowFilter(target:MovieClip, distance:Number, angle:Number, color:Number, alpha:Number, blurX:Number, blurY:Number, strength:Number, quality:Number, inner:Boolean, knockout:Boolean, hideObject:Boolean):Void {
        if (arguments.length == 1) {
            ColorEngine.checkAndRemoveFilter(target, DropShadowFilter);
            return;
        }
        distance   = isNaN(distance)   ? 4         : distance;
        angle      = isNaN(angle)      ? 45        : angle;
        color      = (color == undefined) ? 0x000000 : color;
        alpha      = isNaN(alpha)      ? 0.8       : alpha;
        blurX      = isNaN(blurX)      ? 8         : blurX;
        blurY      = isNaN(blurY)      ? 8         : blurY;
        strength   = isNaN(strength)   ? 1         : strength;
        quality    = isNaN(quality)    ? 1         : quality;
        inner      = (inner == undefined) ? false  : inner;
        knockout   = (knockout == undefined) ? false : knockout;
        hideObject = (hideObject == undefined) ? false : hideObject;
        var shadow:DropShadowFilter = new DropShadowFilter(distance, angle, color, alpha, blurX, blurY, strength, quality, inner, knockout, hideObject);
        ColorEngine.setFilter(target, shadow, DropShadowFilter);
    }

    /**
     * 设置模糊滤镜（BlurFilter）
     * 若仅传入目标影片剪辑，则删除模糊滤镜；否则根据参数设置模糊滤镜。
     *
     * @param target  目标影片剪辑
     * @param blurX   X方向模糊，默认 10
     * @param blurY   Y方向模糊，默认 10
     * @param quality 质量，默认 1
     */
    public static function setBlurFilter(target:MovieClip, blurX:Number, blurY:Number, quality:Number):Void {
        if (arguments.length == 1) {
            ColorEngine.checkAndRemoveFilter(target, BlurFilter);
            return;
        }
        blurX   = isNaN(blurX) ? 10 : blurX;
        blurY   = isNaN(blurY) ? 10 : blurY;
        quality = isNaN(quality) ? 1  : quality;
        var blur:BlurFilter = new BlurFilter(blurX, blurY, quality);
        ColorEngine.setFilter(target, blur, BlurFilter);
    }

    /**
     * 设置发光滤镜（GlowFilter）
     * 若仅传入目标影片剪辑，则删除发光滤镜；否则根据参数设置发光滤镜。
     *
     * @param target   目标影片剪辑
     * @param color    发光颜色，默认 0xFF0000
     * @param alpha    透明度，默认 1
     * @param blurX    X方向模糊，默认 10
     * @param blurY    Y方向模糊，默认 10
     * @param strength 发光强度，默认 2
     * @param quality  质量，默认 1
     * @param inner    是否内侧发光，默认 false
     * @param knockout 是否挖空，默认 false
     */
    public static function setGlowFilter(target:MovieClip, color:Number, alpha:Number, blurX:Number, blurY:Number, strength:Number, quality:Number, inner:Boolean, knockout:Boolean):Void {
        if (arguments.length == 1) {
            ColorEngine.checkAndRemoveFilter(target, GlowFilter);
            return;
        }
        color    = (color == undefined) ? 0xFF0000 : color;
        alpha    = isNaN(alpha) ? 1 : alpha;
        blurX    = isNaN(blurX) ? 10 : blurX;
        blurY    = isNaN(blurY) ? 10 : blurY;
        strength = isNaN(strength) ? 2 : strength;
        quality  = isNaN(quality) ? 1 : quality;
        inner    = (inner == undefined) ? false : inner;
        knockout = (knockout == undefined) ? false : knockout;
        var glow:GlowFilter = new GlowFilter(color, alpha, blurX, blurY, strength, quality, inner, knockout);
        ColorEngine.setFilter(target, glow, GlowFilter);
    }

    /**
     * 设置斜角滤镜（BevelFilter）
     * 若仅传入目标影片剪辑，则删除斜角滤镜；否则根据参数设置斜角滤镜。
     *
     * @param target         目标影片剪辑
     * @param distance       斜角距离，默认 4
     * @param angle          角度，默认 45
     * @param highlightColor 高光颜色，默认 0xFFFFFF
     * @param highlightAlpha 高光透明度，默认 0.8
     * @param shadowColor    阴影颜色，默认 0x000000
     * @param shadowAlpha    阴影透明度，默认 0.8
     * @param blurX          X方向模糊，默认 8
     * @param blurY          Y方向模糊，默认 8
     * @param strength       强度，默认 1
     * @param quality        质量，默认 1
     * @param type           类型，默认 "inner"
     * @param knockout       是否挖空，默认 false
     */
    public static function setBevelFilter(target:MovieClip, distance:Number, angle:Number, highlightColor:Number, highlightAlpha:Number, shadowColor:Number, shadowAlpha:Number, blurX:Number, blurY:Number, strength:Number, quality:Number, type:String, knockout:Boolean):Void {
        if (arguments.length == 1) {
            ColorEngine.checkAndRemoveFilter(target, BevelFilter);
            return;
        }
        distance       = isNaN(distance)       ? 4         : distance;
        angle          = isNaN(angle)          ? 45        : angle;
        highlightColor = (highlightColor == undefined) ? 0xFFFFFF : highlightColor;
        highlightAlpha = isNaN(highlightAlpha) ? 0.8       : highlightAlpha;
        shadowColor    = (shadowColor == undefined) ? 0x000000 : shadowColor;
        shadowAlpha    = isNaN(shadowAlpha)    ? 0.8       : shadowAlpha;
        blurX          = isNaN(blurX)          ? 8         : blurX;
        blurY          = isNaN(blurY)          ? 8         : blurY;
        strength       = isNaN(strength)       ? 1         : strength;
        quality        = isNaN(quality)        ? 1         : quality;
        type           = (type == undefined)     ? "inner"   : type;
        knockout       = (knockout == undefined) ? false     : knockout;
        var bevel:BevelFilter = new BevelFilter(distance, angle, highlightColor, highlightAlpha, shadowColor, shadowAlpha, blurX, blurY, strength, quality, type, knockout);
        ColorEngine.setFilter(target, bevel, BevelFilter);
    }

    /**
     * 设置渐变发光滤镜（GradientGlowFilter）
     * 若仅传入目标影片剪辑，则删除渐变发光滤镜；否则根据参数设置渐变发光滤镜。
     *
     * @param target   目标影片剪辑
     * @param distance 距离，默认 0
     * @param angle    角度，默认 45
     * @param colors   颜色数组，默认 [0xFF0000, 0x000000]
     * @param alphas   透明度数组，默认 [1, 1]
     * @param ratios   比例数组，默认 [0, 255]
     * @param blurX    X方向模糊，默认 8
     * @param blurY    Y方向模糊，默认 8
     * @param strength 强度，默认 1
     * @param quality  质量，默认 1
     * @param type     类型，默认 "outer"
     * @param knockout 是否挖空，默认 false
     */
    public static function setGradientGlowFilter(target:MovieClip, distance:Number, angle:Number, colors:Array, alphas:Array, ratios:Array, blurX:Number, blurY:Number, strength:Number, quality:Number, type:String, knockout:Boolean):Void {
        if (arguments.length == 1) {
            ColorEngine.checkAndRemoveFilter(target, GradientGlowFilter);
            return;
        }
        distance   = isNaN(distance)   ? 0         : distance;
        angle      = isNaN(angle)      ? 45        : angle;
        colors     = colors || [0xFF0000, 0x000000];
        alphas     = alphas || [1, 1];
        ratios     = ratios || [0, 255];
        blurX      = isNaN(blurX)      ? 8         : blurX;
        blurY      = isNaN(blurY)      ? 8         : blurY;
        strength   = isNaN(strength)   ? 1         : strength;
        quality    = isNaN(quality)    ? 1         : quality;
        type       = type || "outer";
        knockout   = (knockout == undefined) ? false : knockout;
        var gradGlow:GradientGlowFilter = new GradientGlowFilter(distance, angle, colors, alphas, ratios, blurX, blurY, strength, quality, type, knockout);
        ColorEngine.setFilter(target, gradGlow, GradientGlowFilter);
    }

    /**
     * 设置渐变斜角滤镜（GradientBevelFilter）
     * 若仅传入目标影片剪辑，则删除渐变斜角滤镜；否则根据参数设置渐变斜角滤镜。
     *
     * @param target   目标影片剪辑
     * @param distance 距离，默认 4
     * @param angle    角度，默认 45
     * @param colors   颜色数组，默认 [0xFFFFFF, 0x000000]
     * @param alphas   透明度数组，默认 [1, 1]
     * @param ratios   比例数组，默认 [0, 128, 255]
     * @param blurX    X方向模糊，默认 8
     * @param blurY    Y方向模糊，默认 8
     * @param strength 强度，默认 1
     * @param quality  质量，默认 1
     * @param type     类型，默认 "inner"
     * @param knockout 是否挖空，默认 false
     */
    public static function setGradientBevelFilter(target:MovieClip, distance:Number, angle:Number, colors:Array, alphas:Array, ratios:Array, blurX:Number, blurY:Number, strength:Number, quality:Number, type:String, knockout:Boolean):Void {
        if (arguments.length == 1) {
            ColorEngine.checkAndRemoveFilter(target, GradientBevelFilter);
            return;
        }
        distance   = isNaN(distance)   ? 4         : distance;
        angle      = isNaN(angle)      ? 45        : angle;
        colors     = colors || [0xFFFFFF, 0x000000];
        alphas     = alphas || [1, 1];
        ratios     = ratios || [0, 128, 255];
        blurX      = isNaN(blurX)      ? 8         : blurX;
        blurY      = isNaN(blurY)      ? 8         : blurY;
        strength   = isNaN(strength)   ? 1         : strength;
        quality    = isNaN(quality)    ? 1         : quality;
        type       = type || "inner";
        knockout   = (knockout == undefined) ? false : knockout;
        var gradBevel:GradientBevelFilter = new GradientBevelFilter(distance, angle, colors, alphas, ratios, blurX, blurY, strength, quality, type, knockout);
        ColorEngine.setFilter(target, gradBevel, GradientBevelFilter);
    }

    // 静态变量：空的 ColorTransform 对象，用于重置颜色
    public static var emptyColorTransform:ColorTransform = new ColorTransform();

    /**
     * 初级颜色调整
     * 根据传入参数设置目标影片剪辑的颜色变换，支持基础与高级调整。
     *
     * @param target 目标影片剪辑
     * @param params 参数对象，支持属性：
     *   红色乘数, 绿色乘数, 蓝色乘数, 透明乘数,
     *   红色偏移, 绿色偏移, 蓝色偏移, 透明偏移,
     *   亮度, 对比度, 饱和度, 色相
     *
     * @return 返回应用后的 ColorTransform 对象；若 params 为空则重置颜色变换
     */
    public static function basicAdjustColor(target:MovieClip, params:Object):ColorTransform {
        if (params instanceof ColorTransform) {
            target.transform.colorTransform = ColorTransform(params);
            return ColorTransform(params);
        }
        if (!params) {
            target.transform.colorTransform = ColorEngine.emptyColorTransform;
            return null;
        }
        var ct:ColorTransform = new ColorTransform();
        // 基础颜色乘数与偏移
        ct.redMultiplier   = params.hasOwnProperty("红色乘数")   ? params["红色乘数"]   : 1;
        ct.greenMultiplier = params.hasOwnProperty("绿色乘数")   ? params["绿色乘数"]   : 1;
        ct.blueMultiplier  = params.hasOwnProperty("蓝色乘数")   ? params["蓝色乘数"]   : 1;
        ct.alphaMultiplier = params.hasOwnProperty("透明乘数")   ? params["透明乘数"]   : 1;
        ct.redOffset       = params.hasOwnProperty("红色偏移")   ? params["红色偏移"]   : 0;
        ct.greenOffset     = params.hasOwnProperty("绿色偏移")   ? params["绿色偏移"]   : 0;
        ct.blueOffset      = params.hasOwnProperty("蓝色偏移")   ? params["蓝色偏移"]   : 0;
        ct.alphaOffset     = params.hasOwnProperty("透明偏移")   ? params["透明偏移"]   : 0;

        // 高级调整参数
        var brightness:Number = params.hasOwnProperty("亮度")   ? params["亮度"]   : 0;
        var contrast:Number   = params.hasOwnProperty("对比度") ? params["对比度"] : 0;
        var saturation:Number = params.hasOwnProperty("饱和度") ? params["饱和度"] : 0;
        var hue:Number        = params.hasOwnProperty("色相")   ? params["色相"]   : 0;

        // 色相调整：将色相值限制在 0~360 范围内，并映射到 RGB 偏移
        var newHue:Number = (ct.redOffset + hue) % 360;
        if (newHue < 0) newHue += 360;
        var hueDiff:Number = newHue - ct.redOffset;
        if (hueDiff > 180)  hueDiff -= 360;
        if (hueDiff < -180) hueDiff += 360;
        var rgbDiff:Number = hueDiff / 360 * 255 / 3;
        ct.redOffset   += rgbDiff;
        ct.greenOffset -= rgbDiff / 2;
        ct.blueOffset  -= rgbDiff / 2;

        // 对比度调整
        var contrastMul:Number = 1 + contrast / 100;
        var contrastOff:Number = 128 * (1 - contrastMul);
        ct.redMultiplier   *= contrastMul;
        ct.greenMultiplier *= contrastMul;
        ct.blueMultiplier  *= contrastMul;
        ct.redOffset   += contrastOff + brightness;
        ct.greenOffset += contrastOff + brightness;
        ct.blueOffset  += contrastOff + brightness;

        // 饱和度调整：稍作修正
        saturation += hueDiff / 5;
        if (saturation !== 0) {
            var grayAvg:Number = (ct.redMultiplier + ct.greenMultiplier + ct.blueMultiplier) / 3;
            ct.redMultiplier   = grayAvg + (ct.redMultiplier   - grayAvg) * (1 + saturation / 100);
            ct.greenMultiplier = grayAvg + (ct.greenMultiplier - grayAvg) * (1 + saturation / 100);
            ct.blueMultiplier  = grayAvg + (ct.blueMultiplier  - grayAvg) * (1 + saturation / 100);
        }
        target.transform.colorTransform = ct;
        return ct;
    }

    /**
     * 生成亮度调整矩阵
     *
     * @param value 亮度值
     * @return 返回亮度调整矩阵数组
     */
    public static function brightnessMatrix(value:Number):Array {
        return [1, 0, 0, 0, value,
                0, 1, 0, 0, value,
                0, 0, 1, 0, value,
                0, 0, 0, 1, 0];
    }

    /**
     * 生成对比度调整矩阵
     *
     * @param value 对比度值（比例形式）
     * @return 返回对比度调整矩阵数组
     */
    public static function contrastMatrix(value:Number):Array {
        var scale:Number  = value + 1;
        var offset:Number = 128 * (1 - scale);
        return [scale, 0, 0, 0, offset,
                0, scale, 0, 0, offset,
                0, 0, scale, 0, offset,
                0, 0, 0, 1, 0];
    }

    /**
     * 生成饱和度调整矩阵
     *
     * @param value 饱和度值
     * @return 返回饱和度调整矩阵数组
     */
    public static function saturationMatrix(value:Number):Array {
        var lumaR:Number = 0.2126;
        var lumaG:Number = 0.7152;
        var lumaB:Number = 0.0722;
        var invSat:Number = 1 - value;
        var invLumR:Number = invSat * lumaR;
        var invLumG:Number = invSat * lumaG;
        var invLumB:Number = invSat * lumaB;
        return [invLumR + value, invLumG, invLumB, 0, 0,
                invLumR, invLumG + value, invLumB, 0, 0,
                invLumR, invLumG, invLumB + value, 0, 0,
                0, 0, 0, 1, 0];
    }

    /**
     * 生成色相调整矩阵
     *
     * @param value 色相值（弧度制）
     * @return 返回色相调整矩阵数组
     */
    public static function hueMatrix(value:Number):Array {
        var cosVal:Number = Math.cos(value);
        var sinVal:Number = Math.sin(value);
        return [
            (cosVal + (1 - cosVal) * 0.213), ((1 - cosVal) * 0.715 - sinVal * 0.715), ((1 - cosVal) * 0.072 + sinVal * 0.928), 0, 0,
            ((1 - cosVal) * 0.213 + sinVal * 0.143), (cosVal + (1 - cosVal) * 0.715), ((1 - cosVal) * 0.072 - sinVal * 0.283), 0, 0,
            ((1 - cosVal) * 0.213 - sinVal * 0.787), ((1 - cosVal) * 0.715 + sinVal * 0.715), (cosVal + (1 - cosVal) * 0.072), 0, 0,
            0, 0, 0, 1, 0
        ];
    }

    /**
     * 组合色彩矩阵
     * 将两个 4x5 矩阵组合为一个新的色彩矩阵。
     *
     * @param base    基础矩阵
     * @param overlay 叠加矩阵
     * @return 返回组合后的矩阵数组
     */
    public static function composeColorMatrix(base:Array, overlay:Array):Array {
        var result:Array = new Array(20);
        for (var i:Number = 0; i < 4; i++) {
            var index:Number = i * 5;
            for (var j:Number = 0; j < 4; j++) {
                result[index + j] = base[index]     * overlay[j] +
                                      base[index + 1] * overlay[j + 5] +
                                      base[index + 2] * overlay[j + 10] +
                                      base[index + 3] * overlay[j + 15];
            }
            result[index + 4] = base[index]     * overlay[4] +
                                base[index + 1] * overlay[9] +
                                base[index + 2] * overlay[14] +
                                base[index + 3] * overlay[19] +
                                base[index + 4];
        }
        return result;
    }

    /**
     * 调整颜色滤镜
     * 根据传入参数生成颜色矩阵滤镜，并应用到目标影片剪辑上。
     *
     * @param target 目标影片剪辑
     * @param params 参数对象，支持属性：
     *   红色乘数, 绿色乘数, 蓝色乘数, 透明乘数,
     *   红色偏移, 绿色偏移, 蓝色偏移, 透明偏移,
     *   亮度, 对比度, 饱和度, 色相
     *
     * @return 返回生成的 ColorMatrixFilter 对象
     */
    public static function adjustColor(target:MovieClip, params:Object):ColorMatrixFilter {
        if (params instanceof ColorMatrixFilter) {
            ColorEngine.setFilter(target, params, ColorMatrixFilter);
            return ColorMatrixFilter(params);
        }
        if (!params) {
            ColorEngine.checkAndRemoveFilter(target, ColorMatrixFilter);
            return null;
        }
        // 默认矩阵为恒等矩阵
        var matrix:Array = [1, 0, 0, 0, 0,
                             0, 1, 0, 0, 0,
                             0, 0, 1, 0, 0,
                             0, 0, 0, 1, 0];
        // 基础颜色乘数与偏移
        var baseMatrix:Array = [
            params.hasOwnProperty("红色乘数")   ? params["红色乘数"]   : 1, 0, 0, 0, params.hasOwnProperty("红色偏移")   ? params["红色偏移"]   : 0,
            0, params.hasOwnProperty("绿色乘数")   ? params["绿色乘数"]   : 1, 0, 0, params.hasOwnProperty("绿色偏移")   ? params["绿色偏移"]   : 0,
            0, 0, params.hasOwnProperty("蓝色乘数")   ? params["蓝色乘数"]   : 1, 0, params.hasOwnProperty("蓝色偏移")   ? params["蓝色偏移"]   : 0,
            0, 0, 0, params.hasOwnProperty("透明乘数") ? params["透明乘数"] : 1, params.hasOwnProperty("透明偏移") ? params["透明偏移"] : 0
        ];
        matrix = ColorEngine.composeColorMatrix(matrix, baseMatrix);
        if (params.hasOwnProperty("亮度"))    matrix = ColorEngine.composeColorMatrix(matrix, ColorEngine.brightnessMatrix(params["亮度"]));
        if (params.hasOwnProperty("对比度"))  matrix = ColorEngine.composeColorMatrix(matrix, ColorEngine.contrastMatrix(params["对比度"] * 0.01));
        if (params.hasOwnProperty("饱和度"))  matrix = ColorEngine.composeColorMatrix(matrix, ColorEngine.saturationMatrix(params["饱和度"] * 0.01 + 1));
        if (params.hasOwnProperty("色相"))    matrix = ColorEngine.composeColorMatrix(matrix, ColorEngine.hueMatrix(params["色相"] * Math.PI / 180));
        var colorMatrixFilter:ColorMatrixFilter = new ColorMatrixFilter(matrix);
        ColorEngine.setFilter(target, colorMatrixFilter, ColorMatrixFilter);
        return colorMatrixFilter;
    }
}
