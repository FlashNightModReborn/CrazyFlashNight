import org.flashNight.gesh.pratt.*;

/**
 * Pratt系统使用示例和测试
 * 展示如何使用重构后的5个类
 */
class org.flashNight.gesh.pratt.PrattTestExample {
    
    public static function runTests():Void {
        trace("========== Pratt系统测试开始 ==========");
        
        testBasicExpressions();
        testVariablesAndFunctions();
        testComplexExpressions();
        testBuffSystem();
        testErrorHandling();
        testPerformance();
        
        trace("========== Pratt系统测试完成 ==========");
    }
    
    // 测试基础表达式
    private static function testBasicExpressions():Void {
        trace("\n--- 基础表达式测试 ---");
        
        var evaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        // 算术运算
        trace("2 + 3 * 4 = " + evaluator.evaluate("2 + 3 * 4")); // 14
        trace("(2 + 3) * 4 = " + evaluator.evaluate("(2 + 3) * 4")); // 20
        trace("10 / 2 + 3 = " + evaluator.evaluate("10 / 2 + 3")); // 8
        trace("2 ** 3 = " + evaluator.evaluate("2 ** 3")); // 8
        
        // 比较运算
        trace("5 > 3 = " + evaluator.evaluate("5 > 3")); // true
        trace("10 == 5 * 2 = " + evaluator.evaluate("10 == 5 * 2")); // true
        trace("'hello' != 'world' = " + evaluator.evaluate("'hello' != 'world'")); // true
        
        // 逻辑运算
        trace("true && false = " + evaluator.evaluate("true && false")); // false
        trace("true || false = " + evaluator.evaluate("true || false")); // true
        trace("!true = " + evaluator.evaluate("!true")); // false
        
        // 三元运算符
        trace("5 > 3 ? 'yes' : 'no' = " + evaluator.evaluate("5 > 3 ? 'yes' : 'no'")); // "yes"
        
        // 空值合并
        trace("null ?? 'default' = " + evaluator.evaluate("null ?? 'default'")); // "default"
    }
    
    // 测试变量和函数
    private static function testVariablesAndFunctions():Void {
        trace("\n--- 变量和函数测试 ---");
        
        var evaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        // 设置变量
        evaluator.setVariable("x", 10);
        evaluator.setVariable("y", 5);
        evaluator.setVariable("name", "Player");
        
        trace("x + y = " + evaluator.evaluate("x + y")); // 15
        trace("x * y = " + evaluator.evaluate("x * y")); // 50
        
        // 内置函数
        trace("Math.max(10, 20, 15) = " + evaluator.evaluate("Math.max(10, 20, 15)")); // 20
        trace("Math.sqrt(16) = " + evaluator.evaluate("Math.sqrt(16)")); // 4
        trace("Math.floor(3.7) = " + evaluator.evaluate("Math.floor(3.7)")); // 3
        
        // 自定义函数
        evaluator.setFunction("double", function(n) {
            return n * 2;
        });
        
        evaluator.setFunction("greet", function(name) {
            return "Hello, " + name + "!";
        });
        
        trace("double(x) = " + evaluator.evaluate("double(x)")); // 20
        trace("greet(name) = " + evaluator.evaluate("greet(name)")); // "Hello, Player!"
    }
    
    // 测试复杂表达式
    private static function testComplexExpressions():Void {
        trace("\n--- 复杂表达式测试 ---");
        
        var evaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        // 对象和数组
        var player:Object = {
            level: 10,
            stats: {
                attack: 100,
                defense: 50
            },
            items: [
                {name: "Sword", damage: 20},
                {name: "Shield", defense: 15}
            ]
        };
        
        evaluator.setVariable("player", player);
        
        trace("player.level = " + evaluator.evaluate("player.level")); // 10
        trace("player.stats.attack = " + evaluator.evaluate("player.stats.attack")); // 100
        trace("player.items[0].damage = " + evaluator.evaluate("player.items[0].damage")); // 20
        
        // 复杂计算
        var expr1:String = "player.stats.attack + player.level * 5";
        trace(expr1 + " = " + evaluator.evaluate(expr1)); // 150
        
        var expr2:String = "player.level >= 10 ? player.stats.attack * 1.5 : player.stats.attack";
        trace(expr2 + " = " + evaluator.evaluate(expr2)); // 150
        
        // 链式属性访问
        evaluator.setVariable("game", {
            player: player,
            config: {
                difficulty: "hard",
                multiplier: 1.5
            }
        });
        
        var expr3:String = "game.player.stats.attack * game.config.multiplier";
        trace(expr3 + " = " + evaluator.evaluate(expr3)); // 150
    }
    
    // 测试Buff系统
    private static function testBuffSystem():Void {
        trace("\n--- Buff系统测试 ---");
        
        var buffEvaluator:PrattEvaluator = PrattEvaluator.createForBuff();
        
        buffEvaluator.setVariable("baseAttack", 100);
        buffEvaluator.setVariable("level", 15);
        buffEvaluator.setVariable("hasBerserk", true);
        
        // ================== FIX START ==================
        // 修正测试1: 直接求值Buff函数，检查返回的对象
        var buffExpr1:String = "ADD_FLAT(20)";
        var result1 = buffEvaluator.evaluate(buffExpr1);
        trace(buffExpr1 + " = {type: " + result1.type + ", value: " + result1.value + "}");

        // 测试2（原先已正确）
        var buffExpr2:String = "hasBerserk ? ADD_PERCENT_BASE(50) : ADD_FLAT(10)";
        var result2 = buffEvaluator.evaluate(buffExpr2);
        trace(buffExpr2 + " result type = " + result2.type);

        // 测试3（原先有bug，现已修复）
        var buffExpr3:String = "level > 10 ? MUL_PERCENT(level * 2) : ADD_FLAT(level * 5)";
        var result3 = buffEvaluator.evaluate(buffExpr3);
        trace(buffExpr3 + " = {type: " + result3.type + ", value: " + result3.value + "}");

        // 测试4（原先有bug，现已修复）
        buffEvaluator.setVariable("mods", [
            buffEvaluator.evaluate("ADD_FLAT(20)"),
            buffEvaluator.evaluate("MUL_PERCENT(50)")
        ]);
        trace("buffValue(100, mods) = " + buffEvaluator.evaluate("buffValue(100, mods)"));
        // =================== FIX END ===================
    }
    
    // 测试错误处理
    private static function testErrorHandling():Void {
        trace("\n--- 错误处理测试 ---");
        
        var evaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        // 未定义变量
        var result1 = evaluator.evaluateSafe("undefinedVar + 10", -1);
        trace("未定义变量结果: " + result1); // -1
        
        // 除零错误
        var result2 = evaluator.evaluateSafe("10 / 0", "ERROR");
        trace("除零错误结果: " + result2); // "ERROR"
        
        // 语法错误
        var validation = evaluator.validate("2 + + 3");
        trace("语法验证: " + (validation.valid ? "有效" : "无效 - " + validation.error));
        
        // 空值访问
        evaluator.setVariable("nullVar", null);
        var result3 = evaluator.evaluateSafe("nullVar.property", "NULL_ACCESS");
        trace("空值访问结果: " + result3); // "NULL_ACCESS"
    }
    
    // 测试性能
    private static function testPerformance():Void {
        trace("\n--- 性能测试 ---");
        
        var evaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        // 设置测试变量
        evaluator.setVariable("a", 10);
        evaluator.setVariable("b", 20);
        evaluator.setVariable("c", 30);
        
        // 简单表达式性能
        var simple = evaluator.benchmark("a + b * c", 1000);
        trace("简单表达式 (1000次): " + simple.totalTime + "ms, 平均: " + simple.averageTime + "ms");
        
        // 复杂表达式性能
        var complex = evaluator.benchmark(
            "Math.sqrt(a * a + b * b) > c ? Math.max(a, b, c) : Math.min(a, b, c)", 
            1000
        );
        trace("复杂表达式 (1000次): " + complex.totalTime + "ms, 平均: " + complex.averageTime + "ms");
        
        // 测试缓存效果
        var expr:String = "a + b + c + Math.sqrt(a * b * c)";
        
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < 1000; i++) {
            evaluator.evaluate(expr, false); // 不使用缓存
        }
        var noCacheTime:Number = getTimer() - startTime;
        
        startTime = getTimer();
        for (var j:Number = 0; j < 1000; j++) {
            evaluator.evaluate(expr, true); // 使用缓存
        }
        var cacheTime:Number = getTimer() - startTime;
        
        trace("不使用缓存: " + noCacheTime + "ms");
        trace("使用缓存: " + cacheTime + "ms");
        trace("性能提升: " + Math.round((1 - cacheTime / noCacheTime) * 100) + "%");
    }
    
    // 辅助方法：获取当前时间（毫秒）
    private static function getTimer():Number {
        return new Date().getTime();
    }
}

