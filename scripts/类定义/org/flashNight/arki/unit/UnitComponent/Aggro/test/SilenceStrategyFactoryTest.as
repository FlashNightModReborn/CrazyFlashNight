/**
 * SilenceStrategyFactory 单元测试
 * @class SilenceStrategyFactoryTest
 * @package org.flashNight.arki.unit.UnitComponent.Aggro.test
 */

import org.flashNight.arki.unit.UnitComponent.Aggro.SilenceStrategyFactory;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

class org.flashNight.arki.unit.UnitComponent.Aggro.test.SilenceStrategyFactoryTest {

    private static var testResults:Array = [];

    /**
     * 运行所有测试
     */
    public static function runAllTests():Void {
        testResults = [];

        _root.发布消息("===== SilenceStrategyFactory 测试开始 =====");

        test_create_distanceThreshold_triggersWithinThreshold();
        test_create_distanceThreshold_silencedBeyondThreshold();
        test_create_percent_returnsFunction();
        test_create_invalidPercent_returnsNull();
        test_create_null_returnsNull();
        test_create_invalidInput_returnsNull();
        test_bind_attachesStrategyToCarrier();
        test_clear_removesStrategy();
        test_clearAll_removesAllStrategies();

        // 输出测试结果
        var passed:Number = 0;
        var failed:Number = 0;

        for (var i:Number = 0; i < testResults.length; i++) {
            var result:Object = testResults[i];
            if (result.passed) {
                passed++;
                _root.发布消息("✓ " + result.name);
            } else {
                failed++;
                _root.发布消息("✗ " + result.name + " - " + result.error);
            }
        }

        _root.发布消息("===== 测试完成：通过 " + passed + "/" + testResults.length + " =====");
    }

    /**
     * 测试距离阈值策略 - 阈值内触发仇恨
     */
    private static function test_create_distanceThreshold_triggersWithinThreshold():Void {
        var testName:String = "距离阈值策略 - 阈值内触发仇恨";

        try {
            var strategy:Function = SilenceStrategyFactory.create(300);
            var shooter:Object = {_name: "shooter"};
            var target:Object = {_name: "target"};

            // 距离200，小于阈值300，应该触发仇恨（返回true）
            var result:Boolean = strategy(shooter, target, 200);

            if (result == true) {
                addTestResult(testName, true);
            } else {
                addTestResult(testName, false, "期望true，实际" + result);
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 测试距离阈值策略 - 阈值外消音成功
     */
    private static function test_create_distanceThreshold_silencedBeyondThreshold():Void {
        var testName:String = "距离阈值策略 - 阈值外消音成功";

        try {
            var strategy:Function = SilenceStrategyFactory.create(300);
            var shooter:Object = {_name: "shooter"};
            var target:Object = {_name: "target"};

            // 距离400，大于阈值300，应该消音成功（返回false）
            var result:Boolean = strategy(shooter, target, 400);

            if (result == false) {
                addTestResult(testName, true);
            } else {
                addTestResult(testName, false, "期望false，实际" + result);
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 测试百分比策略 - 返回函数
     */
    private static function test_create_percent_returnsFunction():Void {
        var testName:String = "百分比策略 - 返回有效函数";

        try {
            var strategy:Function = SilenceStrategyFactory.create("90%");

            if (strategy != null && typeof(strategy) == "function") {
                // 测试函数可调用
                var shooter:Object = {_name: "shooter"};
                var target:Object = {_name: "target"};
                var result:Boolean = strategy(shooter, target, 100);

                // 结果应该是布尔值
                if (typeof(result) == "boolean") {
                    addTestResult(testName, true);
                } else {
                    addTestResult(testName, false, "函数返回值不是布尔类型");
                }
            } else {
                addTestResult(testName, false, "未返回有效函数");
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 测试无效百分比 - 返回null
     */
    private static function test_create_invalidPercent_returnsNull():Void {
        var testName:String = "无效百分比 - 返回null";

        try {
            var testCases:Array = ["150%", "-10%", "abc%", "%"];
            var allNull:Boolean = true;

            for (var i:Number = 0; i < testCases.length; i++) {
                var strategy:Function = SilenceStrategyFactory.create(testCases[i]);
                if (strategy != null) {
                    allNull = false;
                    break;
                }
            }

            if (allNull) {
                addTestResult(testName, true);
            } else {
                addTestResult(testName, false, "无效百分比应返回null");
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 测试null输入 - 返回null
     */
    private static function test_create_null_returnsNull():Void {
        var testName:String = "null输入 - 返回null";

        try {
            var strategy1:Function = SilenceStrategyFactory.create(null);
            var strategy2:Function = SilenceStrategyFactory.create(undefined);

            if (strategy1 == null && strategy2 == null) {
                addTestResult(testName, true);
            } else {
                addTestResult(testName, false, "null输入应返回null");
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 测试无效输入 - 返回null
     */
    private static function test_create_invalidInput_returnsNull():Void {
        var testName:String = "无效输入 - 返回null";

        try {
            var testCases:Array = ["abc", -100, 0, ""];
            var allNull:Boolean = true;

            for (var i:Number = 0; i < testCases.length; i++) {
                var strategy:Function = SilenceStrategyFactory.create(testCases[i]);
                if (strategy != null) {
                    allNull = false;
                    break;
                }
            }

            if (allNull) {
                addTestResult(testName, true);
            } else {
                addTestResult(testName, false, "无效输入应返回null");
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 测试bind方法 - 成功挂载策略
     */
    private static function test_bind_attachesStrategyToCarrier():Void {
        var testName:String = "bind方法 - 挂载策略";

        try {
            var carrier:Object = {};
            SilenceStrategyFactory.bind(carrier, "测试消音策略", 300);

            if (carrier["测试消音策略"] != null && typeof(carrier["测试消音策略"]) == "function") {
                addTestResult(testName, true);
            } else {
                addTestResult(testName, false, "策略未成功挂载");
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 测试clear方法 - 清除策略
     */
    private static function test_clear_removesStrategy():Void {
        var testName:String = "clear方法 - 清除策略";

        try {
            var carrier:Object = {};
            SilenceStrategyFactory.bind(carrier, "测试消音策略", 300);
            SilenceStrategyFactory.clear(carrier, "测试消音策略");

            if (carrier["测试消音策略"] == null) {
                addTestResult(testName, true);
            } else {
                addTestResult(testName, false, "策略未被清除");
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 测试clearAll方法 - 清除所有策略
     */
    private static function test_clearAll_removesAllStrategies():Void {
        var testName:String = "clearAll方法 - 清除所有策略";

        try {
            var carrier:Object = {};
            carrier["手枪消音策略"] = function():Boolean { return true; };
            carrier["长枪消音策略"] = function():Boolean { return true; };
            carrier["手枪2消音策略"] = function():Boolean { return true; };
            carrier["兵器消音策略"] = function():Boolean { return true; };

            SilenceStrategyFactory.clearAll(carrier);

            var allCleared:Boolean = true;
            var weaponTypes:Array = ["手枪", "手枪2", "长枪", "兵器"];
            for (var i:Number = 0; i < weaponTypes.length; i++) {
                if (carrier[weaponTypes[i] + "消音策略"] != null) {
                    allCleared = false;
                    break;
                }
            }

            if (allCleared) {
                addTestResult(testName, true);
            } else {
                addTestResult(testName, false, "未能清除所有策略");
            }
        } catch (e:Error) {
            addTestResult(testName, false, e.toString());
        }
    }

    /**
     * 添加测试结果
     */
    private static function addTestResult(name:String, passed:Boolean, error:String):Void {
        testResults.push({
            name: name,
            passed: passed,
            error: error || ""
        });
    }
}