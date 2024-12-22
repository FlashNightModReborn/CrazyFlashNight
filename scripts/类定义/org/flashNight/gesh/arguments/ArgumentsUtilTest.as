import org.flashNight.gesh.arguments.*;
import flash.utils.getTimer;

/**
 * ArgumentsUtilTest 用于测试 Array.prototype.slice 和 ArgumentsUtil.sliceArgs 在不同参数数量下的性能和正确性。
 */
class org.flashNight.gesh.arguments.ArgumentsUtilTest {
    /**
     * 运行所有性能测试和正确性测试。
     */
    public static function runAllTests():Void {
        runCorrectnessTest();
        runPerformanceTest();
    }

    /**
     * 运行正确性测试，确保 ArgumentsUtil.sliceArgs 返回的结果与 Array.prototype.slice 一致。
     */
    private static function runCorrectnessTest():Void {
        trace("开始正确性测试...");

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
            trace("所有正确性测试均通过。");
        } else {
            trace("存在正确性测试失败。请检查 ArgumentsUtil.sliceArgs 方法。");
        }

        trace("正确性测试完成.");
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
    public static function runPerformanceTest():Void {
        var iterations:Number = 10000; // 每个测试场景的调用次数

        trace("开始性能测试...");

        for (var argCount:Number = 0; argCount <= 10; argCount++) {
            // 测试 Array.prototype.slice
            var spliceTime:Number = testSplice(argCount, iterations);
            trace("Array.prototype.slice (参数数量: " + argCount + ") 总耗时: " + spliceTime + " 毫秒");

            // 测试 ArgumentsUtil.sliceArgs
            var sliceArgsTime:Number = testSliceArgs(argCount, iterations);
            trace("ArgumentsUtil.sliceArgs (参数数量: " + argCount + ") 总耗时: " + sliceArgsTime + " 毫秒");
        }

        trace("性能测试完成.");
    }

    /**
     * 测试 Array.prototype.slice 方法在不同参数数量下的性能。
     * @param argCount 参数数量。
     * @param iterations 测试迭代次数。
     * @return Number 总耗时（毫秒）。
     */
    private static function testSplice(argCount:Number, iterations:Number):Number {
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
}
