import org.flashNight.gesh.arguments.*;
import org.flashNight.naki.Sort.*;

// 文件路径: org/flashNight/gesh/arguments/TestArgs.as
class org.flashNight.gesh.arguments.TestArgs {
    // 断言计数器
    private static var assertions:Number = 0;
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    
    // 性能测试常量
    private static var TEST_ITERATIONS:Number = 10000;
    
    public static function runAllTests():Void {
        trace("=== 开始参数类测试 ===");
        
        // 基础功能测试
        testInitialization();
        testFromArguments();
        testTypeChecking();
        testArrayCompatibility();
        testEdgeCases();
        testArraySorting();
        testArrayReverse();
        testArrayClear();
        testArrayConcat();
        testArrayWithOtherTypes();
        testEmptyArrayOperations();
        
        // 性能测试
        testCreationPerformance();
        testMethodPerformance();
        testConversionPerformance();
        testSortPerformance();
        
        trace("\n=== 测试结果 ===");
        trace("总断言数: " + assertions);
        trace("通过: " + passed + " (" + ((passed/assertions)*100) + "%)");
        trace("失败: " + failed + " (" + ((failed/assertions)*100) + "%)");
    }
    
    // ================== 断言系统 ==================
    private static function assert(condition:Boolean, message:String):Void {
        assertions++;
        if (condition) {
            passed++;
            trace("[PASS] " + message);
        } else {
            failed++;
            trace("[FAIL] " + message);
        }
    }
    
    // ================ 准确性测试用例 ================
    private static function testInitialization():Void {
        trace("\n[测试初始化]");
        
        // 多参数初始化
        var a1 = new args(1,2,3);
        assert(a1.length == 3, "多参数长度应为3");
        assert(a1.toString() == "[Arguments] 1, 2, 3", "多参数初始化内容");
        
        // 单数组参数初始化
        var a2 = new args([4,5]);
        assert(a2.length == 2, "数组参数长度应为2");
        assert(a2[1] == 5, "数组参数索引访问");
        
        // 空初始化
        var a3 = new args();
        assert(a3.length == 0, "空初始化长度应为0");
    }
    
    private static function testFromArguments():Void {
        trace("\n[测试参数解析]");
        
        function testFunc(a, b, rest) { // 声明3个参数
            return args.fromArguments(
                3, // 总声明参数数
                arguments
            );
        }
        
        // 参数不足
        var r1 = testFunc(1);
        assert(r1.length == 0, "参数不足时应返回空数组");
        
        // 参数正好
        var r2 = testFunc(1,2,3);
        assert(r2.length == 1, "参数正好时应包含最后一个参数");
        assert(r2[0] == 3, "最后一个参数值验证");
        
        // 参数溢出
        var r3 = testFunc(1,2,3,4,5);
        assert(r3.length == 3, "应捕获3个额外参数");
        assert(r3.toString() == "[Arguments] 3, 4, 5", "参数溢出内容验证");
    }
    
    private static function testTypeChecking():Void {
        trace("\n[测试类型检测]");
        
        var a = new args();
        assert(a instanceof Array, "必须继承Array类型");
        assert(a instanceof args, "必须识别自定义类型");
        
        // 类型转换验证
        var arr:Array = a.valueOf();
        assert(arr instanceof Array && !(arr instanceof args), "valueOf应返回原生数组");
    }
    
    private static function testArrayCompatibility():Void {
        trace("\n[测试数组兼容性]");
        
        var a = new args(1,2,3);
        
        // 测试push/pop
        a.push(4);
        assert(a.length == 4, "push后长度应为4");
        assert(a.pop() == 4, "pop返回值验证");
        
        // 测试splice
        var removed = a.splice(1, 2);
        assert(removed.toString() == "2,3", "splice删除内容验证");
        assert(a.toString() == "[Arguments] 1", "splice后剩余内容");
        
        // 测试迭代
        var sum:Number = 0;
        for (var i:Number=0; i<a.length; i++) {
            sum += a[i];
        }
        assert(sum == 1, "数组迭代求和验证");
    }
    
    private static function testEdgeCases():Void {
        trace("\n[测试边界条件]");
        
        // 测试undefined参数
        var a1 = new args(undefined);
        assert(a1.length == 1, "undefined应被视为有效参数");
        assert(typeof a1[0] == "undefined", "undefined参数存储验证");
        
        // 测试null参数
        var a2 = new args(null);
        assert(a2[0] === null, "null参数存储验证");
        
        // 测试混合类型
        var a3 = new args("text", true, {prop:1});
        assert(typeof a3[0] == "string", "字符串类型保留");
        assert(typeof a3[1] == "boolean", "布尔类型保留");
        assert(typeof a3[2] == "object", "对象类型保留");
    }

    private static function testArraySorting():Void {
        trace("\n[测试数组排序]");
        
        var a = new args(5, 3, 8, 1, 4);
        
        // 排序前检查
        assert(a.toString() == "[Arguments] 5, 3, 8, 1, 4", "排序前的内容检查");
        
        // 排序
        a.sort();
        assert(a.toString() == "[Arguments] 1, 3, 4, 5, 8", "排序后内容验证");
    }


    private static function testArrayReverse():Void {
        trace("\n[测试数组反转]");
        
        var a = new args(1, 2, 3, 4, 5);
        
        // 反转前检查
        assert(a.toString() == "[Arguments] 1, 2, 3, 4, 5", "反转前内容检查");
        
        // 反转
        a.reverse();
        assert(a.toString() == "[Arguments] 5, 4, 3, 2, 1", "反转后内容验证");
    }

    private static function testArrayClear():Void {
        trace("\n[测试数组清空]");
        
        var a = new args(1, 2, 3, 4, 5);
        
        // 清空数组
        a.length = 0;
        assert(a.length == 0, "清空后的数组长度应为0");
        assert(a.toString() == "[Arguments]", "清空后的数组内容应为空");
    }

    private static function testArrayConcat():Void {
        trace("\n[测试数组合并]");
        
        var a = new args(1, 2, 3);
        var b = new args(4, 5, 6);
        
        // 合并两个数组
        var merged = a.concat(b);
        assert(merged.toString() == "[Arguments] 1, 2, 3, 4, 5, 6", "数组合并结果验证");
    }

    private static function testArrayWithOtherTypes():Void {
        trace("\n[测试数组与其他类型的混合操作]");
        
        var a = new args(1, 2, 3);
        var b = [4, 5, 6];
        
        // 合并 args 与普通数组
        var merged = a.concat(b);
        assert(merged.toString() == "[Arguments] 1, 2, 3, 4, 5, 6", "混合操作合并结果验证");
        
        // 测试和非数组类型的合并
        var mixed = a.concat("text", true, null);
        assert(mixed.toString() == "[Arguments] 1, 2, 3, text, true, null", "和其他类型的合并结果验证");
    }

    private static function testEmptyArrayOperations():Void {
        trace("\n[测试空数组操作]");
        
        var a = new args();
        
        // 测试空数组的push操作
        a.push(1);
        assert(a.toString() == "[Arguments] 1", "空数组push操作验证");
        
        // 测试空数组的pop操作
        var removed = a.pop();
        assert(removed == 1, "空数组pop操作验证");
        assert(a.length == 0, "空数组pop后应为空");
}


    
    // ================ 性能测试部分 ================
    private static function testCreationPerformance():Void {
        trace("\n[性能测试-创建实例]");
        var start:Number = getTimer();
        
        for (var i:Number=0; i<TEST_ITERATIONS; i++) {
            var a = new args(1,2,3,4,5);
        }
        
        var elapsed:Number = getTimer() - start;
        trace(TEST_ITERATIONS + "次实例创建耗时: " + elapsed + "ms");
    }
    
    private static function testMethodPerformance():Void {
        trace("\n[性能测试-数组操作]");
        var a = new args();
        
        // Push性能
        var startPush:Number = getTimer();
        for (var i:Number=0; i<TEST_ITERATIONS; i++) {
            a.push(i);
        }
        var pushTime:Number = getTimer() - startPush;
        
        // Pop性能
        var startPop:Number = getTimer();
        for (i=0; i<TEST_ITERATIONS; i++) {
            a.pop();
        }
        var popTime:Number = getTimer() - startPop;
        
        trace("Push操作: " + pushTime + "ms");
        trace("Pop操作: " + popTime + "ms");
    }
    
    private static function testConversionPerformance():Void {
        trace("\n[性能测试-类型转换]");
        var a = new args(1,2,3);
        
        var start:Number = getTimer();
        for (var i:Number=0; i<TEST_ITERATIONS; i++) {
            var arr:Array = a.valueOf();
        }
        var elapsed:Number = getTimer() - start;
        
        trace(TEST_ITERATIONS + "次valueOf转换耗时: " + elapsed + "ms");
    }

    private static function testSortPerformance():Void {
        trace("\n[性能测试-排序操作]");
        var start:Number = getTimer();
        
        var largeArray = new args();
        for (var i:Number = 0; i < TEST_ITERATIONS; i++) {
            largeArray.push(Math.random() * 1000);
        }
        
        TimSort.sort(largeArray);
        
        var elapsed:Number = getTimer() - start;
        trace(TEST_ITERATIONS + "次排序耗时: " + elapsed + "ms");
    }

}


