import org.flashNight.gesh.pratt.*;

/**
 * Gesh表达式求值器。
 * 
 * PrattEvaluator 是一个高级、功能丰富的表达式求值引擎。它封装了词法分析 (PrattLexer)
 * 和语法分析 (PrattParser)，并提供了一个统一、便捷的API来执行动态表达式。
 * 
 * 核心功能：
 * - 动态求值：执行字符串形式的Gesh脚本表达式。
 * - 上下文管理：支持运行时注入和管理变量与函数。
 * - 缓存机制：内置表达式解析缓存和求值结果缓存，以优化重复计算的性能。
 * - 安全性：提供安全的求值方法，能够处理语法和运行时错误，并返回默认值。
 * - 工具方法：包含表达式验证、变量提取、性能基准测试等实用工具。
 * - 工厂模式：通过静态工厂方法提供不同用途的预配置求值器实例 (如标准型、Buff系统专用型)。
 * 
 * 使用示例：
 *   var evaluator = PrattEvaluator.createStandard();
 *   evaluator.setVariable("x", 10);
 *   var result = evaluator.evaluate("x * 2 + 5"); // result will be 25
 */
class org.flashNight.gesh.pratt.PrattEvaluator {
    /** 存储变量和函数的运行时上下文。键为变量或函数名，值为其对应的值或函数。 */
    private var _context:Object;
    /** Pratt解析器实例，用于将表达式字符串转换为AST。 */
    private var _parser:PrattParser;
    /** 表达式AST缓存。键为表达式字符串，值为已解析的 PrattExpression 对象，避免重复解析。 */
    private var _expressionCache:Object;
    /** 求值结果缓存。键为表达式字符串，值为其计算结果，避免在上下文不变时重复计算。 */
    private var _resultCache:Object;

    /**
     * PrattEvaluator 的构造函数。
     * 初始化上下文、缓存，并预置一组内置的常量和函数。
     */
    function PrattEvaluator() {
        _context = {};
        _expressionCache = {};
        _resultCache = {}; 
        _initializeBuiltins();
    }

    /**
     * 初始化内置的全局变量和函数。
     * 这为求值环境提供了一套类似JavaScript标准库的基础功能。
     * @private
     */
    private function _initializeBuiltins():Void {
        // 数学常量
        _context["Math"] = Math;
        _context["PI"] = Math.PI;
        _context["E"] = Math.E;
        
        // 内置的全局函数
        _context["isNaN"] = function(value) { return isNaN(Number(value)); };
        _context["parseInt"] = function(str, radix) { return parseInt(String(str), radix || 10); };
        _context["parseFloat"] = function(str) { return parseFloat(String(str)); };
        _context["String"] = function(value) { return String(value); };
        _context["Number"] = function(value) { return Number(value); };
        _context["Boolean"] = function(value) { return Boolean(value); };
        
        // 通用数学辅助函数
        _context["max"] = function() {
            return Math.max.apply(null, arguments);
        };
        _context["min"] = function() {
            return Math.min.apply(null, arguments);
        };
        _context["clamp"] = function(value, min, max) {
            return Math.max(min, Math.min(max, value));
        };
        _context["abs"] = function(value) {
            return Math.abs(Number(value));
        };
        _context["floor"] = function(value) {
            return Math.floor(Number(value));
        };
        _context["ceil"] = function(value) {
            return Math.ceil(Number(value));
        };
        _context["round"] = function(value) {
            return Math.round(Number(value));
        };
    }

    // ============= 主要API =============
    
    /**
     * 在求值上下文中设置或更新一个变量。
     * 设置新变量或修改现有变量后，会自动清除结果缓存，以确保后续求值能反映上下文的变化。
     * 
     * @param name 变量的名称。
     * @param value 变量的值，可以是任何类型。
     */
    public function setVariable(name:String, value):Void {
        _context[name] = value;
        _resultCache = {}; // 清除结果缓存，因为上下文已改变
    }

    /**
     * 在求值上下文中设置或更新一个函数。
     * 同样，此操作会清除结果缓存。
     * 
     * @param name 函数的名称。
     * @param func 一个可执行的Function对象。
     */
    public function setFunction(name:String, func:Function):Void {
        _context[name] = func;
        _resultCache = {}; // 清除结果缓存，因为上下文已改变
    }

    /**
     * 从上下文中获取一个变量或函数的值。
     * @param name 要获取的变量或函数的名称。
     * @return 变量或函数的值，如果不存在则返回 undefined。
     */
    public function getVariable(name:String) {
        return _context[name];
    }

    /**
     * 获取当前的完整上下文对象。
     * 这允许外部直接操作上下文，但推荐使用 setVariable/setFunction 以确保缓存一致性。
     * @return 当前的上下文对象。
     */
    public function getContext():Object {
        return _context;
    }

    /**
     * 清除所有用户定义的变量和函数，并重置所有缓存。
     * 内置的常量和函数 (如 Math) 会被重新初始化。
     */
    public function clearContext():Void {
        _context = {};
        _expressionCache = {};
        _resultCache = {};
        _initializeBuiltins();
    }

    /**
     * 解析并求值一个表达式字符串。
     * 
     * @param expression 要计算的Gesh表达式字符串。
     * @param useCache (可选) 是否使用缓存。默认为 true。
     *                 - true: 会优先使用结果缓存，然后是AST缓存，性能最高。
     *                 - false: 每次都会重新解析和计算，用于需要最新结果且上下文频繁变化的场景。
     * @return 表达式的计算结果。
     * @throws {Error} 如果表达式存在语法错误或运行时错误（如除以零、变量未定义）。
     */
    public function evaluate(expression:String, useCache:Boolean) {
        if (useCache == undefined) useCache = true;
        
        // 优先从结果缓存中获取
        if (useCache && _resultCache[expression] !== undefined) {
            return _resultCache[expression];
        }

        var ast:PrattExpression;
        // 其次从已解析的AST缓存中获取
        if (useCache && _expressionCache[expression]) {
            ast = _expressionCache[expression];
        } else {
            // 如果都未命中，则进行完整解析
            var lexer:PrattLexer = new PrattLexer(expression);
            var parser:PrattParser = new PrattParser(lexer);
            ast = parser.parse();
            if (useCache) {
                _expressionCache[expression] = ast;
            }
        }
        
        var result = ast.evaluate(_context);

        // 将新计算的结果存入缓存
        if (useCache) {
            _resultCache[expression] = result;
        }
        
        return result;
    }

    /**
     * 仅将表达式字符串解析为AST (抽象语法树)，不进行求值。
     * @param expression 要解析的表达式字符串。
     * @return {PrattExpression} 解析生成的AST根节点。
     */
    public function parse(expression:String):PrattExpression {
        var lexer:PrattLexer = new PrattLexer(expression);
        var parser:PrattParser = new PrattParser(lexer);
        return parser.parse();
    }

    // ============= 工厂方法 =============
    
    /**
     * 创建一个标准的、通用的求值器实例。
     * 包含所有内置的数学和类型转换函数。
     * @return {PrattEvaluator} 一个新的标准求值器实例。
     */
    public static function createStandard():PrattEvaluator {
        return new PrattEvaluator();
    }
    
    /**
     * 创建一个为游戏Buff系统定制的求值器实例。
     * 除了标准功能外，还预置了用于处理Buff逻辑的专用函数。
     * @return {PrattEvaluator} 一个新的Buff系统专用求值器实例。
     */
    public static function createForBuff():PrattEvaluator {
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // Buff系统相关的函数，通常返回描述操作的JSON对象
        evaluator.setFunction("SET_BASE", function(value) {
            return {type: "SET_BASE", value: value};
        });
        evaluator.setFunction("ADD_FLAT", function(value) {
            return {type: "ADD_FLAT", value: value};
        });
        evaluator.setFunction("ADD_PERCENT_BASE", function(value) {
            return {type: "ADD_PERCENT_BASE", value: value};
        });
        evaluator.setFunction("ADD_PERCENT_CURRENT", function(value) {
            return {type: "ADD_PERCENT_CURRENT", value: value};
        });
        evaluator.setFunction("MUL_PERCENT", function(value) {
            return {type: "MUL_PERCENT", value: value};
        });
        evaluator.setFunction("ADD_FINAL", function(value) {
            return {type: "ADD_FINAL", value: value};
        });
        evaluator.setFunction("CLAMP_MAX", function(value) {
            return {type: "CLAMP_MAX", value: value};
        });
        evaluator.setFunction("CLAMP_MIN", function(value) {
            return {type: "CLAMP_MIN", value: value};
        });
        
        // Buff计算和条件判断的辅助函数
        evaluator.setFunction("buffValue", function(base, modifications) {
            var result:Number = base;
            for (var i:Number = 0; i < modifications.length; i++) {
                var mod = modifications[i];
                switch (mod.type) {
                    case "ADD_FLAT":
                        result += mod.value;
                        break;
                    case "MUL_PERCENT":
                        result *= (1 + mod.value / 100);
                        break;
                    // ... 可扩展其他类型的修改器
                }
            }
            return result;
        });
        evaluator.setFunction("hasTag", function(tags, tag) {
            if (!tags || !tags.length) return false;
            for (var i:Number = 0; i < tags.length; i++) {
                if (tags[i] == tag) return true;
            }
            return false;
        });
        evaluator.setFunction("stackCount", function(buffId) {
            // 这是一个需要与外部系统集成的示例，此处返回一个模拟值
            return 0;
        });
        
        return evaluator;
    }
    
    /**
     * 创建一个带有自定义解析器配置的求值器实例 (扩展示例)。
     * @param parserSetup 一个函数，用于在创建时对PrattParser进行自定义配置，如添加新运算符。
     * @return {PrattEvaluator} 一个新的自定义求值器实例。
     */
    public static function createWithCustomParser(parserSetup:Function):PrattEvaluator {
        var evaluator:PrattEvaluator = new PrattEvaluator();
        // 在实际实现中，这里会调用 parserSetup 来配置内部的PrattParser实例。
        return evaluator;
    }

    // ============= 高级功能 =============
    
    /**
     * 批量求值一系列表达式。
     * @param expressions 一个包含表达式字符串的数组。
     * @return 一个结果数组，每个元素是一个对象，包含 `expression`, `result` (或 `error`), 和 `success` 状态。
     */
    public function evaluateMultiple(expressions:Array):Array {
        var results:Array = [];
        for (var i:Number = 0; i < expressions.length; i++) {
            try {
                results.push({
                    expression: expressions[i],
                    result: evaluate(expressions[i]),
                    success: true
                });
            } catch (e) {
                results.push({
                    expression: expressions[i],
                    error: e.message,
                    success: false
                });
            }
        }
        return results;
    }
    
    /**
     * 安全地求值一个表达式。
     * 如果在解析或求值过程中发生任何错误，此方法会捕获异常并返回一个指定的默认值，而不是抛出错误。
     * @param expression 要计算的表达式字符串。
     * @param defaultValue 发生错误时要返回的默认值。
     * @return 表达式的计算结果或指定的默认值。
     */
    public function evaluateSafe(expression:String, defaultValue) {
        // 先进行快速的语法验证，避免不必要的求值尝试
        if (!this.validate(expression).valid) {
            return defaultValue;
        }
        try {
            return evaluate(expression);
        } catch (e) {
            return defaultValue;
        }
    }
    
    /**
     * 验证一个表达式字符串的语法是否正确，不进行求值。
     * @param expression 要验证的表达式字符串。
     * @return 一个对象，包含 `{valid: Boolean, error: String}`。
     *         - 如果有效，`valid`为true。
     *         - 如果无效，`valid`为false，且`error`包含错误信息。
     */
    public function validate(expression:String):Object {
        try {
            parse(expression);
            return {valid: true};
        } catch (e) {
            return {valid: false, error: e.message};
        }
    }
    
    /**
     * 从表达式中提取所有唯一的变量和函数名。
     * 这对于静态分析表达式的依赖关系非常有用。
     * @param expression 要分析的表达式字符串。
     * @return 一个包含所有唯一标识符名称的字符串数组。
     */
    public function extractVariables(expression:String):Array {
        var ast:PrattExpression = parse(expression);
        var variables:Object = {};
        _extractVariablesFromAST(ast, variables);
        
        var result:Array = [];
        for (var name:String in variables) {
            result.push(name);
        }
        return result;
    }
    
    /**
     * 递归遍历AST以提取变量名的内部辅助函数。
     * @param expr 当前遍历的AST节点。
     * @param variables 用于收集变量名的对象（作为Set使用）。
     * @private
     */
    private function _extractVariablesFromAST(expr:PrattExpression, variables:Object):Void {
        if (!expr) return;
        
        switch (expr.type) {
            case PrattExpression.IDENTIFIER:
                variables[expr.name] = true;
                break;
            case PrattExpression.BINARY:
                _extractVariablesFromAST(expr.left, variables);
                _extractVariablesFromAST(expr.right, variables);
                break;
            case PrattExpression.UNARY:
                _extractVariablesFromAST(expr.operand, variables);
                break;
            case PrattExpression.TERNARY:
                _extractVariablesFromAST(expr.condition, variables);
                _extractVariablesFromAST(expr.trueExpr, variables);
                _extractVariablesFromAST(expr.falseExpr, variables);
                break;
            case PrattExpression.FUNCTION_CALL:
                _extractVariablesFromAST(expr.functionExpr, variables);
                for (var i:Number = 0; i < expr.arguments.length; i++) {
                    _extractVariablesFromAST(expr.arguments[i], variables);
                }
                break;
            case PrattExpression.PROPERTY_ACCESS:
                // 只提取基础对象名，不提取属性名
                _extractVariablesFromAST(expr.object, variables);
                break;
            case PrattExpression.ARRAY_ACCESS:
                _extractVariablesFromAST(expr.array, variables);
                _extractVariablesFromAST(expr.index, variables);
                break;
            case PrattExpression.OBJECT_LITERAL:
                for (var i:Number = 0; i < expr.properties.length; i++) {
                    // 键是字面量，只需检查作为表达式的值
                    _extractVariablesFromAST(expr.properties[i].value, variables);
                }
                break;
        }
    }
    
    /**
     * 对一个表达式进行性能基准测试。
     * 此方法会重复执行表达式指定次数，并计算总耗时和平均耗时。
     * 为了准确测量性能，此方法在求值期间会强制禁用缓存。
     * 
     * @param expression 要测试的表达式字符串。
     * @param iterations 执行的次数。
     * @return 一个包含性能数据的对象: {expression, iterations, totalTime, averageTime}。
     */
    public function benchmark(expression:String, iterations:Number):Object {
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < iterations; i++) {
            evaluate(expression, false); // 强制不使用缓存以获得真实性能数据
        }
        
        var totalTime:Number = getTimer() - startTime;
        
        return {
            expression: expression,
            iterations: iterations,
            totalTime: totalTime,
            averageTime: iterations > 0 ? totalTime / iterations : 0
        };
    }
}