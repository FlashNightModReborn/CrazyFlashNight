import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;

/**
 * TeslaRayConfig 配置解析回归测试
 * @class TeslaRayConfigTest
 * @package org.flashNight.arki.bullet.BulletComponent.Config
 *
 * 重点覆盖：
 * 1. vfxParams 非法数值不会污染配置（避免 NaN）
 * 2. vfxParams 布尔值解析
 * 3. palette 覆盖解析
 * 4. 非法 style/mode 回退行为
 */
class org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfigTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    private static function assertTrue(cond:Boolean, message:String):Void {
        testsRun++;
        if (cond) {
            testsPassed++;
            trace("[PASS] " + message);
        } else {
            testsFailed++;
            trace("[FAIL] " + message);
        }
    }

    private static function assertEqualsNumber(expected:Number, actual:Number, message:String):Void {
        var ok:Boolean = (Math.abs(expected - actual) < 0.0001);
        if (!ok) {
            trace("  expected=" + expected + ", actual=" + actual);
        }
        assertTrue(ok, message);
    }

    private static function assertEqualsBoolean(expected:Boolean, actual:Boolean, message:String):Void {
        var ok:Boolean = (expected == actual);
        if (!ok) {
            trace("  expected=" + expected + ", actual=" + actual);
        }
        assertTrue(ok, message);
    }

    private static function assertEqualsString(expected:String, actual:String, message:String):Void {
        var ok:Boolean = (expected == actual);
        if (!ok) {
            trace("  expected=" + expected + ", actual=" + actual);
        }
        assertTrue(ok, message);
    }

    private static function test_vfxParamsRejectNaNAndKeepPresetValue():Void {
        var presetOnly:TeslaRayConfig = TeslaRayConfig.fromXML({
            vfxStyle: "wave",
            vfxPreset: "ra3_wave"
        });

        var node:Object = {
            vfxStyle: "wave",
            vfxPreset: "ra3_wave",
            vfxParams: {
                waveAmp: "not_a_number",
                pulseRate: "0.5"
            }
        };

        var config:TeslaRayConfig = TeslaRayConfig.fromXML(node);

        assertTrue(!isNaN(config.waveAmp), "vfxParams 非法数值不会写入 NaN");
        assertEqualsNumber(presetOnly.waveAmp, config.waveAmp, "非法 waveAmp 保留预设值");
        assertEqualsNumber(0.5, config.pulseRate, "合法数值覆盖生效");
    }

    private static function test_vfxParamsBooleanParsing():Void {
        var nodeTrue:Object = {
            vfxStyle: "tesla",
            vfxParams: { flickerEnabled: "true" }
        };
        var configTrue:TeslaRayConfig = TeslaRayConfig.fromXML(nodeTrue);
        assertEqualsBoolean(true, configTrue.flickerEnabled, "flickerEnabled='true' 解析正确");

        var nodeFalse:Object = {
            vfxStyle: "tesla",
            vfxParams: { flickerEnabled: "0" }
        };
        var configFalse:TeslaRayConfig = TeslaRayConfig.fromXML(nodeFalse);
        assertEqualsBoolean(false, configFalse.flickerEnabled, "flickerEnabled='0' 解析正确");
    }

    private static function test_paletteOverride():Void {
        var node:Object = {
            vfxStyle: "spectrum",
            vfxParams: {
                palette: "0x010203,#040506,7"
            }
        };

        var config:TeslaRayConfig = TeslaRayConfig.fromXML(node);
        assertTrue(config.palette != null, "palette 覆盖后不为 null");
        assertEqualsNumber(3, config.palette.length, "palette 长度正确");
        assertEqualsNumber(0x010203, config.palette[0], "palette[0] 解析正确");
        assertEqualsNumber(0x040506, config.palette[1], "palette[1] 解析正确");
    }

    private static function test_invalidStyleAndModeFallback():Void {
        var node:Object = {
            vfxStyle: "unknown_style",
            rayMode: "unknown_mode"
        };
        var config:TeslaRayConfig = TeslaRayConfig.fromXML(node);

        assertEqualsString("tesla", config.vfxStyle, "非法 style 回退到默认值");
        assertEqualsString("single", config.rayMode, "非法 mode 回退到默认值");
    }

    private static function test_tokenNormalization():Void {
        var node:Object = {
            vfxStyle: "  PRISM ",
            rayMode: " FoRk ",
            vfxParams: { flickerEnabled: " TRUE " }
        };
        var config:TeslaRayConfig = TeslaRayConfig.fromXML(node);

        assertEqualsString("prism", config.vfxStyle, "style 支持忽略大小写与首尾空白");
        assertEqualsString("fork", config.rayMode, "mode 支持忽略大小写与首尾空白");
        assertEqualsBoolean(true, config.flickerEnabled, "布尔字符串支持忽略大小写与首尾空白");
    }

    public static function runAllTests():Void {
        testsRun = 0;
        testsPassed = 0;
        testsFailed = 0;

        trace("===== TeslaRayConfigTest 开始 =====");
        test_vfxParamsRejectNaNAndKeepPresetValue();
        test_vfxParamsBooleanParsing();
        test_paletteOverride();
        test_invalidStyleAndModeFallback();
        test_tokenNormalization();
        trace("===== TeslaRayConfigTest 结束: run=" + testsRun + ", pass=" + testsPassed + ", fail=" + testsFailed + " =====");
    }

    public static function main():Void {
        runAllTests();
    }
}
