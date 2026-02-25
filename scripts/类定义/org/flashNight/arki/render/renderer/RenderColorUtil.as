/**
 * 渲染颜色工具类，提供渲染器共用的颜色变换能力
 * @class RenderColorUtil
 * @package org.flashNight.arki.render.renderer
 * @author FlashNight
 * @version 1.0.0
 */
class org.flashNight.arki.render.renderer.RenderColorUtil {

    private function RenderColorUtil() {
    }

    /**
     * 对颜色做 HSV 空间色相偏移（模拟棱镜色散）
     * @param {Number} color 原始颜色 (0xRRGGBB)
     * @param {Number} degrees 偏移角度 (-180 ~ 180)
     * @return {Number} 偏移后的颜色 (0xRRGGBB)
     */
    public static function shiftHue(color:Number, degrees:Number):Number {
        var r:Number = (color >> 16) & 0xFF;
        var g:Number = (color >> 8) & 0xFF;
        var b:Number = color & 0xFF;

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

        h = (h + degrees) % 360;
        if (h < 0) h += 360;

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
