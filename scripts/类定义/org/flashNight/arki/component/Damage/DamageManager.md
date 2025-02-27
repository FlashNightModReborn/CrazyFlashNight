
import org.flashNight.arki.component.Damage.*;
// 运行 DamageManager 测试
DamageManagerTest.runTests();



// ================================ 核心测试逻辑 ================================ // 定义伪 DamageManager 构造器（替代 class 实现）
var DamageManager:Function = function (handles) {
    this.handles = handles.slice().sort(function (a, b) { return a - b; }); // 结果排序便于验证
};

// 创建 evaluator 的三种实现方式
function createEvaluator(h) {
    var hlen = h.length;
    if (hlen <= 8) {
        return function (bitmask) {
            var handles = [], temp, len = 0;
            do {
				handles[len++] = h[ 
								    6 - ( ( ( !((temp = bitmask & -bitmask) >= 16 && (temp >>= 4)) << 1 )
						            + !(temp >= 4 && (temp >>= 2)) ) << 1 )
           							+ (temp >= 2)
								];

            } while ((bitmask &= (bitmask - 1)) != 0);
            return new DamageManager(handles);
        };
    } else if (hlen < 32) {
        return function (bitmask) {
            var handles = [], len = 0;
            do {
                handles[len++] = h[(Math.log(bitmask & -bitmask) * 1.4426950408889634 + 0.5) | 0];
            } while ((bitmask &= (bitmask - 1)) != 0);
            return new DamageManager(handles);
        };
    } else if (hlen == 32) {
        return function (bitmask) {
            var handles = [], len = 0, index = 0;
            while (bitmask != 0 && index < 32) {
                if (bitmask & 1) handles[len++] = h[index];
                bitmask >>>= 1;
                index++;
            }
            return new DamageManager(handles);
        };
    } else { 
        throw new Error("Exceeds 32-bit limit");
    }
}

// ================================ 测试工具函数 ================================ // 生成可视化掩码字符串
function visualizeMask(mask, bits) {
    var str = "";
    for (var i = bits - 1; i >= 0; i--) {
        str += (mask >> i) & 1 ? "1" : "0";
        if (i > 0 && i % 4 == 0) { str += "_"; }
    }
    return "0b" + str;
}

// 结果比较函数
function compareHandles(testCase, actual, expected) {
    var success = actual.join(",") == expected.join(",");
    if (!success) {
        trace("测试失败: " + testCase.desc);
        trace("输入掩码: " + visualizeMask(testCase.mask, testCase.bits));
        trace("预期索引: [" + expected.join(", ") + "]");
        trace("实际索引: [" + actual.join(", ") + "]\n");
    }
    return success;
}

// ================================ 测试用例配置 ================================ // ==================== 测试用例构建工具函数 ====================
function createTestCase(bits, mask, expect, desc) {
    var tc = new Object();
    tc.bits = bits;
    tc.mask = mask;
    tc.expect = expect;
    tc.desc = desc;
    return tc;
}

// ==================== 手动构建测试用例集 ====================
var testCases = new Array();

// 基础测试组
testCases.push(createTestCase(4, 0x1, [0], "4位掩码最低位"));
testCases.push(createTestCase(4, 0x8, [3], "4位掩码最高位"));
testCases.push(createTestCase(8, 0xA, [1, 3], "8位交错掩码"));

// 边界测试组
testCases.push(createTestCase(32, 0x80000000, [31], "32位最高位"));
testCases.push(createTestCase(32, 0x1, [0], "32位最低位"));
testCases.push(createTestCase(32, 0xFFFFFFFF, [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31], "32位全掩码"));
testCases.push(createTestCase(32, 0x00000000, [], "32位空掩码"));

// 特殊模式测试
var pattern16 = [1, 3, 5, 7, 9, 11, 13, 15];
testCases.push(createTestCase(16, 0xAAAA, pattern16, "16位交错模式"));

var pattern32 = new Array();
for (var j = 1; j < 32; j += 2) { pattern32.push(j); }
testCases.push(createTestCase(32, 0xAAAAAAAA, pattern32, "32位交错模式"));

// ================================ 测试执行引擎 ================================ 
function runTestSuite() {
    var total = 0, passed = 0;
    for (var i = 0; i < testCases.length; i++) {
        var tc = testCases[i];
        total++;
        // 生成测试处理器数组
        var handlers = [];
        for (var j = 0; j < tc.bits; j++) {
            handlers.push(j);
        }
        try {
            // 创建 evaluator 并获取结果
            var evaluator = createEvaluator(handlers);
            var dm = evaluator(tc.mask);
            if (compareHandles(tc, dm.handles, tc.expect)) {
                passed++;
            }
        } catch (e) {
            trace("运行时错误: " + e.message + " - " + tc.desc);
        }
    }
    // 显示统计结果
    trace("\n=== 测试统计 ===");
    trace("总用例: " + total);
    trace("通过数: " + passed);
    trace("失败数: " + (total - passed));
    trace("通过率: " + (passed / total * 100) + "%");
}

// ================================ 性能基准测试 ================================ 
function runBenchmark() {
    var testMasks = {
        八位优化: 0xA5, // 8位有效掩码 0b10100101
        二十四位对数: 0xAAAAAA, // 24位掩码
        三十二位逐位: 0xAAAAAAAA // 32位掩码
    };

    var cycles = 50000;

    // 准备测试数据
    function createHandlers(length) {
        var arr = [];
        for (var i = 0; i < length; i++) { arr.push(i); } // 填充实际内容
        return arr;
    }

    var evaluators = {
        八位优化: createEvaluator(createHandlers(8)),
        二十四位对数: createEvaluator(createHandlers(24)),
        三十二位逐位: createEvaluator(createHandlers(32))
    };

    // 执行基准测试
    trace("\n=== 性能基准 (" + cycles + "次迭代) ===");
    for (var name in evaluators) {
        var start = getTimer();
        var e = evaluators[name];
        var n = cycles / 10;
        for (var i = 0; i < n; i++) {
            var ii = i % 4;
            for (var j = 0; j < 10; j++) {
                e(testMasks[ii]);
            }
        }
        var duration = getTimer() - start;
        trace(name + ": " + duration + "ms (" + (cycles / duration * 1000) + " ops/sec)");
    }
}

// ================================ 执行测试 ================================
trace("//================ 开始自动化测试 ================//");
runTestSuite();
runBenchmark();
trace("//================ 测试执行完毕 ================//");



//================ 开始自动化测试 ================//

=== 测试统计 ===
总用例: 9
通过数: 9
失败数: 0
通过率: 100%

=== 性能基准 (50000次迭代) ===
八位优化: 1156ms (43252.5951557093 ops/sec)
二十四位对数: 1248ms (40064.1025641026 ops/sec)
三十二位逐位: 1168ms (42808.2191780822 ops/sec)
//================ 测试执行完毕 ================//
