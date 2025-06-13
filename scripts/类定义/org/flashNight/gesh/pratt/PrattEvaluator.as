import org.flashNight.gesh.pratt.*;

/**
 * 表达式求值器 - 合并了ExpressionEvaluator和Factory功能
 */
class org.flashNight.gesh.pratt.PrattEvaluator {
    private var _context:Object;
    private var _parser:PrattParser;
    private var _expressionCache:Object; // 缓存已解析的表达式

    function PrattEvaluator() {
        _context = {};
        _expressionCache = {};
        _initializeBuiltins();
    }

    private function _initializeBuiltins():Void {
        // 数学常量
        _context["Math"] = Math;
        _context["PI"] = Math.PI;
        _context["E"] = Math.E;
        
        // 内置函数
        _context["isNaN"] = function(value) { return isNaN(Number(value)); };
        _context["parseInt"] = function(str, radix) { return parseInt(String(str), radix || 10); };
        _context["parseFloat"] = function(str) { return parseFloat(String(str)); };
        _context["String"] = function(value) { return String(value); };
        _context["Number"] = function(value) { return Number(value); };
        _context["Boolean"] = function(value) { return Boolean(value); };
        
        // 通用数学函数
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
    
    public function setVariable(name:String, value):Void {
        _context[name] = value;
    }

    public function setFunction(name:String, func:Function):Void {
        _context[name] = func;
    }

    public function getVariable(name:String) {
        return _context[name];
    }

    public function getContext():Object {
        return _context;
    }

    public function clearContext():Void {
        _context = {};
        _expressionCache = {};
        _initializeBuiltins();
    }

    public function evaluate(expression:String, useCache:Boolean) {
        if (useCache == undefined) useCache = true;
        
        var ast:PrattExpression;
        
        if (useCache && _expressionCache[expression]) {
            ast = _expressionCache[expression];
        } else {
            var lexer:PrattLexer = new PrattLexer(expression);
            var parser:PrattParser = new PrattParser(lexer);
            ast = parser.parse();
            
            if (useCache) {
                _expressionCache[expression] = ast;
            }
        }
        
        return ast.evaluate(_context);
    }

    public function parse(expression:String):PrattExpression {
        var lexer:PrattLexer = new PrattLexer(expression);
        var parser:PrattParser = new PrattParser(lexer);
        return parser.parse();
    }

    // ============= 工厂方法 =============
    
    /**
     * 创建标准求值器
     */
    public static function createStandard():PrattEvaluator {
        return new PrattEvaluator();
    }
    
    /**
     * 创建Buff系统专用求值器
     */
    public static function createForBuff():PrattEvaluator {
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // Buff系统相关的变量和函数
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
        
        // Buff相关辅助函数
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
                    // ... 其他类型
                }
            }
            return result;
        });
        
        // Buff条件函数
        evaluator.setFunction("hasTag", function(tags, tag) {
            if (!tags || !tags.length) return false;
            for (var i:Number = 0; i < tags.length; i++) {
                if (tags[i] == tag) return true;
            }
            return false;
        });
        
        evaluator.setFunction("stackCount", function(buffId) {
            // 这里需要访问Buff系统的实际数据
            // 暂时返回模拟值
            return 0;
        });
        
        return evaluator;
    }
    
    /**
     * 创建带有自定义解析器的求值器
     */
    public static function createWithCustomParser(parserSetup:Function):PrattEvaluator {
        var evaluator:PrattEvaluator = new PrattEvaluator();
        // 这里可以通过parserSetup函数来自定义解析器
        // 例如添加自定义运算符等
        return evaluator;
    }

    // ============= 高级功能 =============
    
    /**
     * 批量求值多个表达式
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
     * 安全求值（带错误处理）
     */
    public function evaluateSafe(expression:String, defaultValue) {
        try {
            return evaluate(expression);
        } catch (e) {
            return defaultValue;
        }
    }
    
    /**
     * 表达式验证（不执行，只检查语法）
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
     * 获取表达式中的变量列表
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
                _extractVariablesFromAST(expr.object, variables);
                break;
            case PrattExpression.ARRAY_ACCESS:
                _extractVariablesFromAST(expr.array, variables);
                _extractVariablesFromAST(expr.index, variables);
                break;
        }
    }
    
    /**
     * 性能测试
     */
    public function benchmark(expression:String, iterations:Number):Object {
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < iterations; i++) {
            evaluate(expression, false); // 不使用缓存
        }
        
        var totalTime:Number = getTimer() - startTime;
        
        return {
            expression: expression,
            iterations: iterations,
            totalTime: totalTime,
            averageTime: totalTime / iterations
        };
    }
}