
import org.flashNight.arki.component.Damage.*;
// 运行 DamageManager 测试
DamageManagerTest.runTests();



// 伤害管理器工厂中的策略函数生成代码

var generatedCode:String = "";

for (var i:Number = 1; i <= 32; i++) {
    var funcName:String = "getDamageManager" + i;
    generatedCode += "public function " + funcName + "(bullet:Object):DamageManager {\n";
    generatedCode += "    var bitmask:Number = this._skipCheckBitmask;\n";
    generatedCode += "    var handles:Array = this._handles;\n";
    generatedCode += "    var conditionalIndices:Array = this._conditionalHandlerIndices;\n";
	generatedCode += "    var index:Number;\n";
    generatedCode += "\n";

    for (var j:Number = 0; j < i; j++) {
        generatedCode += "    index = conditionalIndices[" + j + "];\n";
        generatedCode += "    if (handles[index].canHandle(bullet)) bitmask |= (1 << index);\n";

    }

    generatedCode += "\n    return DamageManager(this._managerCache.get(bitmask));\n";
    generatedCode += "}\n";
    generatedCode += "\n";
}

// 主函数：创建Evaluator
function createEvaluator(h:Array):Function {
    if (h.length <= 8) {
        return function(bitmask:Number):Object {
            var handles:Array = [];
            var temp:Number;
            var len:Number = 0;
            do {
                handles[len++] = h[
                    4 * Boolean(((temp = bitmask & -bitmask ) >= 16) && (temp >>= 4)) +
                    2 * Boolean((temp >= 4) && (temp >>= 2)) +
                    (temp >= 2)
                ];
            } while ((bitmask &= (bitmask - 1)) != 0);
            return {handles: handles};
        };
    } else {
        return function(bitmask:Number):Object {
            if (bitmask > 0xFFFFFFFF) {
                return {error: "超过 32 位掩码限制"};
            }

            var handles:Array = [];
            var len:Number = 0;
            do {
                handles[len++] = h[(Math.log(bitmask & -bitmask) * 1.4426950408889634 + 0.5) | 0];
            } while ((bitmask &= (bitmask - 1)) != 0);
            return {handles: handles};
        };
    }
}

// 辅助函数：比较结果并记录日志
function compareResults(len:Number, mask:Number, actual:Array, expected:Array):Boolean {
    if (actual.join() != expected.join()) {
        trace("失败: len=" + len + ", mask=0b" + mask.toString(2) + 
              "\n  预期: " + expected + 
              "\n  实际: " + actual);
        return false;
    }
    return true;
}

// 自动生成掩码测试
function generateTestCases():Array {
    var testCases:Array = [];
    for (var i:Number = 0; i < 32; i++) {
        testCases.push([32, (1 << i), [i]]); // 单个位开启
    }
    testCases.push([32, 0xFFFFFFFF, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]]);
    testCases.push([32, 0xAAAAAAAA, [1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31]]); // 奇偶交错
    testCases.push([32, 0x55555555, [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30]]); // 奇偶交错
    return testCases;
}

// 测试逻辑
function testEvaluatorLogic(bitWidth:Number):Boolean {
    trace("\n--- 测试 " + bitWidth + " 位算法 ---");
    var allPassed:Boolean = true;

    var testCases:Array = generateTestCases();
    for (var i:Number = 0; i < testCases.length; i++) {
        var len:Number = testCases[i][0];
        var mask:Number = testCases[i][1];
        var expectedIndices:Array = testCases[i][2];

        var h:Array = [];
        for (var j:Number = 0; j < len; j++) h.push(j);

        var evaluator:Function = createEvaluator(h);
        var result:Object = evaluator(mask);

        if (result.error) {
            trace("错误: len=" + len + ", mask=0b" + mask.toString(2) + ", 错误信息: " + result.error);
            allPassed = false;
        } else {
            var actualHandles:Array = result.handles;
            if (!compareResults(len, mask, actualHandles, expectedIndices)) {
                allPassed = false;
            }
        }
    }
    return allPassed;
}

// 性能测试
function performanceTest():Void {
    trace("\n--- 性能测试 ---");
    var h:Array = [];
    for (var i:Number = 0; i < 32; i++) h.push(i);

    var evaluator:Function = createEvaluator(h);
    var start:Number = getTimer();

    for (var i:Number = 0; i < 100000; i++) {
        evaluator(0xAAAAAAAA);
    }

    var end:Number = getTimer();
    trace("耗时: " + (end - start) + " 毫秒");
}

// 执行测试
var success8:Boolean = testEvaluatorLogic(8);
var success32:Boolean = testEvaluatorLogic(32);
performanceTest();

trace("\n=== 测试结果 ===");
trace("8 位算法: " + (success8 ? "通过" : "存在错误"));
trace("32 位算法: " + (success32 ? "通过" : "存在错误"));
trace("=== 测试结束 ===");
