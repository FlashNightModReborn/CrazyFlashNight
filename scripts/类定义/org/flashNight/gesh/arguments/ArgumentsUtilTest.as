import org.flashNight.gesh.arguments.*;
import flash.utils.getTimer;

/**
 * ArgumentsUtilTest 用于测试 Array.prototype.slice 和 ArgumentsUtil.sliceArgs 在不同参数数量下的性能和正确性。
 * 同时测试 ArgumentsUtil.combineArgs 方法的正确性和性能。
 */
class org.flashNight.gesh.arguments.ArgumentsUtilTest {
    /**
     * 运行所有性能测试和正确性测试。
     */
    public static function runAllTests():Void {
        runSliceArgsCorrectnessTest();
        runCombineArgsCorrectnessTest();
        runSliceArgsPerformanceTest();
        runCombineArgsPerformanceTest();
    }

    /**
     * 运行正确性测试，确保 ArgumentsUtil.sliceArgs 返回的结果与 Array.prototype.slice 一致。
     */
    private static function runSliceArgsCorrectnessTest():Void {
        trace("开始 sliceArgs 正确性测试...");

        var allPassed:Boolean = true;

        for (var argCount:Number = 0; argCount <= 10; argCount++) {
            // 根据参数数量调用测试函数
            var sliceArgsResult:Array;
            var sliceResult:Array;

            switch (argCount) {
                case 0:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })();

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })();
                    break;
                case 1:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1);
                    break;
                case 2:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2);
                    break;
                case 3:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3);
                    break;
                case 4:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4);
                    break;
                case 5:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5);
                    break;
                case 6:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6);
                    break;
                case 7:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7);
                    break;
                case 8:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8);
                    break;
                case 9:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8, 9);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8, 9);
                    break;
                case 10:
                    sliceArgsResult = (function () {
                        return ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);

                    sliceResult = (function () {
                        return Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
                    break;
                default:
                    // 不支持的参数数量
                    trace("不支持的参数数量: " + argCount);
                    continue;
            }

            // 比较两个结果
            if (!arraysEqual(sliceArgsResult, sliceResult)) {
                trace("错误: 参数数量 " + argCount + " 的 sliceArgs 结果与 Array.prototype.slice 不一致。");
                trace("sliceArgsResult: " + sliceArgsResult);
                trace("sliceResult: " + sliceResult);
                allPassed = false;
            } else {
                trace("正确性通过: 参数数量 " + argCount);
            }
        }

        if (allPassed) {
            trace("所有 sliceArgs 正确性测试均通过。");
        } else {
            trace("存在 sliceArgs 正确性测试失败。请检查 ArgumentsUtil.sliceArgs 方法。");
        }

        trace("sliceArgs 正确性测试完成.");
    }

    /**
     * 运行正确性测试，确保 ArgumentsUtil.combineArgs 返回的结果与预期一致。
     */
    private static function runCombineArgsCorrectnessTest():Void {
        trace("开始 combineArgs 正确性测试...");

        var allPassed:Boolean = true;

        // 定义不同的固定参数和动态参数组合
        var fixedArgsList:Array = [
            [], // 无固定参数
            ["fixed1"], // 一个固定参数
            ["fixed1", "fixed2"] // 两个固定参数
        ];

        for (var fixedIndex:Number = 0; fixedIndex < fixedArgsList.length; fixedIndex++) {
            var fixedArgs:Array = fixedArgsList[fixedIndex];
            var fixedDesc:String = "[" + fixedArgs.join(", ") + "]";

            for (var dynamicArgCount:Number = 0; dynamicArgCount <= 10; dynamicArgCount++) {
                // 创建动态参数
                var dynamicArgs:Array = [];
                for (var d:Number = 1; d <= dynamicArgCount; d++) {
                    dynamicArgs.push(d);
                }

                // 使用 combineArgs 组合参数
                var combineArgsResult:Array = (function () {
                    return ArgumentsUtil.combineArgs(fixedArgs, arguments, 0);
                }).apply(null, dynamicArgs);

                // 使用标准方法组合参数：fixedArgs.concat(sliceArgs(arguments, 0))
                var expectedResult:Array = fixedArgs.concat(dynamicArgs);

                // 比较结果
                if (!arraysEqual(combineArgsResult, expectedResult)) {
                    trace("错误: 固定参数 " + fixedDesc + " 和动态参数数量 " + dynamicArgCount + " 的 combineArgs 结果与预期不一致。");
                    trace("combineArgsResult: " + combineArgsResult);
                    trace("expectedResult: " + expectedResult);
                    allPassed = false;
                } else {
                    trace("正确性通过: 固定参数 " + fixedDesc + " 和动态参数数量 " + dynamicArgCount);
                }
            }
        }

        if (allPassed) {
            trace("所有 combineArgs 正确性测试均通过。");
        } else {
            trace("存在 combineArgs 正确性测试失败。请检查 ArgumentsUtil.combineArgs 方法。");
        }

        trace("combineArgs 正确性测试完成.");
    }

    /**
     * 比较两个数组是否相等（元素逐一相等）。
     * @param a 第一个数组。
     * @param b 第二个数组。
     * @return Boolean 如果两个数组相等则返回 true，否则返回 false。
     */
    private static function arraysEqual(a:Array, b:Array):Boolean {
        if (a.length != b.length) return false;
        for (var i:Number = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false;
        }
        return true;
    }

    /**
     * 运行性能测试，比较 Array.prototype.slice 和 ArgumentsUtil.sliceArgs 在不同参数数量下的性能。
     */
    public static function runSliceArgsPerformanceTest():Void {
        var iterations:Number = 10000; // 每个测试场景的调用次数

        trace("开始 sliceArgs 性能测试...");

        for (var argCount:Number = 0; argCount <= 10; argCount++) {
            // 测试 Array.prototype.slice
            var sliceTime:Number = testSlice(argCount, iterations);
            trace("Array.prototype.slice (参数数量: " + argCount + ") 总耗时: " + sliceTime + " 毫秒");

            // 测试 ArgumentsUtil.sliceArgs
            var sliceArgsTime:Number = testSliceArgs(argCount, iterations);
            trace("ArgumentsUtil.sliceArgs (参数数量: " + argCount + ") 总耗时: " + sliceArgsTime + " 毫秒");
        }

        trace("sliceArgs 性能测试完成.");
    }

    /**
     * 运行性能测试，比较 ArgumentsUtil.combineArgs 和标准方法在不同参数数量下的性能。
     */
    public static function runCombineArgsPerformanceTest():Void {
        var iterations:Number = 10000; // 每个测试场景的调用次数

        trace("开始 combineArgs 性能测试...");

        // 定义固定参数的列表
        var fixedArgsList:Array = [
            [], // 无固定参数
            ["fixed1"], // 一个固定参数
            ["fixed1", "fixed2"] // 两个固定参数
        ];

        for (var fixedIndex:Number = 0; fixedIndex < fixedArgsList.length; fixedIndex++) {
            var fixedArgs:Array = fixedArgsList[fixedIndex];
            var fixedDesc:String = "[" + fixedArgs.join(", ") + "]";

            for (var dynamicArgCount:Number = 0; dynamicArgCount <= 10; dynamicArgCount++) {
                // 创建动态参数
                var dynamicArgs:Array = [];
                for (var d:Number = 1; d <= dynamicArgCount; d++) {
                    dynamicArgs.push(d);
                }

                // 测试 combineArgs
                var combineArgsTime:Number = testCombineArgs(fixedArgs, dynamicArgs, iterations);
                trace("ArgumentsUtil.combineArgs (固定参数: " + fixedDesc + ", 动态参数数量: " + dynamicArgCount + ") 总耗时: " + combineArgsTime + " 毫秒");

                // 测试标准方法：fixedArgs.concat(sliceArgs(arguments, 0))
                var standardTime:Number = testStandardCombineArgs(fixedArgs, dynamicArgs, iterations);
                trace("标准方法 (固定参数: " + fixedDesc + ", 动态参数数量: " + dynamicArgCount + ") 总耗时: " + standardTime + " 毫秒");
            }
        }

        trace("combineArgs 性能测试完成.");
    }

    /**
     * 测试 Array.prototype.slice 方法在不同参数数量下的性能。
     * @param argCount 参数数量。
     * @param iterations 测试迭代次数。
     * @return Number 总耗时（毫秒）。
     */
    private static function testSlice(argCount:Number, iterations:Number):Number {
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            // 动态创建函数，根据参数数量传递参数
            switch (argCount) {
                case 0:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })();
                    break;
                case 1:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1);
                    break;
                case 2:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2);
                    break;
                case 3:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3);
                    break;
                case 4:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4);
                    break;
                case 5:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5);
                    break;
                case 6:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6);
                    break;
                case 7:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7);
                    break;
                case 8:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8);
                    break;
                case 9:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8, 9);
                    break;
                case 10:
                    (function () {
                        var a  = Array.prototype.slice.call(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
                    break;
                default:
                    // 不支持的参数数量
                    break;
            }
        }

        return getTimer() - startTime;
    }

    /**
     * 测试 ArgumentsUtil.sliceArgs 方法在不同参数数量下的性能。
     * @param argCount 参数数量。
     * @param iterations 测试迭代次数。
     * @return Number 总耗时（毫秒）。
     */
    private static function testSliceArgs(argCount:Number, iterations:Number):Number {
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            // 动态创建函数，根据参数数量传递参数
            switch (argCount) {
                case 0:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })();
                    break;
                case 1:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1);
                    break;
                case 2:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2);
                    break;
                case 3:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3);
                    break;
                case 4:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4);
                    break;
                case 5:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5);
                    break;
                case 6:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6);
                    break;
                case 7:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7);
                    break;
                case 8:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8);
                    break;
                case 9:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8, 9);
                    break;
                case 10:
                    (function () {
                        var b = ArgumentsUtil.sliceArgs(arguments, 0);
                    })(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
                    break;
                default:
                    // 不支持的参数数量
                    break;
            }
        }

        return getTimer() - startTime;
    }

    /**
     * 测试 ArgumentsUtil.combineArgs 方法在不同参数数量下的性能。
     * @param fixedArgs Array - 固定参数数组
     * @param dynamicArgs Array - 动态参数数组
     * @param iterations Number - 测试迭代次数
     * @return Number 总耗时（毫秒）
     */
    private static function testCombineArgs(fixedArgs:Array, dynamicArgs:Array, iterations:Number):Number {
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            (function () {
                var combined:Array = ArgumentsUtil.combineArgs(fixedArgs, arguments, 0);
            }).apply(null, dynamicArgs);
        }

        return getTimer() - startTime;
    }

    /**
     * 测试标准方法：fixedArgs.concat(ArgumentsUtil.sliceArgs(arguments, 0)) 在不同参数数量下的性能。
     * @param fixedArgs Array - 固定参数数组
     * @param dynamicArgs Array - 动态参数数组
     * @param iterations Number - 测试迭代次数
     * @return Number 总耗时（毫秒）
     */
    private static function testStandardCombineArgs(fixedArgs:Array, dynamicArgs:Array, iterations:Number):Number {
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            (function () {
                var sliced:Array = ArgumentsUtil.sliceArgs(arguments, 0);
                var combined:Array = fixedArgs.concat(sliced);
            }).apply(null, dynamicArgs);
        }

        return getTimer() - startTime;
    }
}
