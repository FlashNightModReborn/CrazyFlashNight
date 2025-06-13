/**
 * @file PrattToken.as
 * @description 定义Pratt解析器中使用的核心词法单元（Token）类。
 * 
 * 该文件包含了Pratt解析流程中最基础的数据结构：`PrattToken`。
 * 每个`PrattToken`实例代表了从源代码中词法分析出的一个独立单元，
 * 如数字、标识符、运算符或关键字。
 * 
 * 它不仅存储了Token的类型和原始文本，还包含了其在源代码中的位置（行号和列号），
 * 并能自动或手动处理其语义值（例如，将文本 "123" 转换为数字 123）。
 * 这个类的设计旨在提供一个不可变的、信息丰富的对象，为后续的语法分析阶段提供支持。
 */
import org.flashNight.gesh.pratt.*;

// ============================================================================
// Token类 - 词法单元
// ============================================================================

/**
 * 代表一个词法单元（Token）。
 * 这是一个不可变的数据结构，用于存储从词法分析器（Lexer）生成的单个单元信息。
 */
class org.flashNight.gesh.pratt.PrattToken {
    
    // ============= 基础类型常量 =============
    /** 文件结束符，表示源代码的末尾。 */
    public static var T_EOF:String = "EOF";
    /** 数字字面量，例如：123, 45.67 */
    public static var T_NUMBER:String = "NUMBER";
    /** 标识符，例如：myVariable, user_name */
    public static var T_IDENTIFIER:String = "IDENTIFIER";
    /** 字符串字面量，例如："hello world", '你好' */
    public static var T_STRING:String = "STRING";
    /** 布尔字面量，即 true 或 false */
    public static var T_BOOLEAN:String = "BOOLEAN";
    /** null 字面量 */
    public static var T_NULL:String = "NULL";
    /** undefined 字面量 */
    public static var T_UNDEFINED:String = "UNDEFINED";
    
    // ============= 运算符 (分类占位符) =============
    /** 通用运算符类型，可用于代表所有运算符的父类。 */
    public static var T_OPERATOR:String = "OPERATOR";
    /** 赋值运算符，例如：=, +=, -= */
    public static var T_ASSIGNMENT:String = "ASSIGNMENT";
    /** 比较运算符，例如：==, !=, >, < */
    public static var T_COMPARISON:String = "COMPARISON";
    /** 逻辑运算符，例如：&&, ||, ! */
    public static var T_LOGICAL:String = "LOGICAL";
    /** 算术运算符，例如：+, -, *, / */
    public static var T_ARITHMETIC:String = "ARITHMETIC";
    
    // ============= 分隔符 =============
    public static var T_LPAREN:String = "LPAREN";        // (
    public static var T_RPAREN:String = "RPAREN";        // )
    public static var T_LBRACKET:String = "LBRACKET";    // [
    public static var T_RBRACKET:String = "RBRACKET";    // ]
    public static var T_LBRACE:String = "LBRACE";        // {
    public static var T_RBRACE:String = "RBRACE";        // }
    public static var T_COMMA:String = "COMMA";          // ,
    public static var T_SEMICOLON:String = "SEMICOLON";  // ;
    public static var T_DOT:String = "DOT";              // .
    public static var T_COLON:String = "COLON";          // :
    public static var T_QUESTION:String = "QUESTION";    // ?
    
    // ============= 关键字 =============
    public static var T_IF:String = "IF";
    public static var T_ELSE:String = "ELSE";
    public static var T_AND:String = "AND";
    public static var T_OR:String = "OR";
    public static var T_NOT:String = "NOT";
    public static var T_TYPEOF:String = "TYPEOF";
    public static var T_MATH:String = "MATH";
    
    // ============= 实例属性 =============
    
    /** 
     * Token的类型。值为此类中定义的 T_... 静态常量之一。
     * 例如：PrattToken.T_NUMBER, PrattToken.T_IDENTIFIER。
     */
    public var type:String;

    /** 
     * Token在源代码中的原始文本。
     * 例如，对于数字 123，其 text 为 "123"。对于字符串 "hi"，其 text 为 "\"hi\""（包含引号）。
     */
    public var text:String;

    /** 
     * Token的语义值。这个值是经过处理和类型转换后的结果。
     * - 对于 T_NUMBER，value 是一个 Number 类型 (例如 123.45)。
     * - 对于 T_BOOLEAN，value 是一个 Boolean 类型 (true 或 false)。
     * - 对于 T_NULL，value 是 null。
     * - 对于 T_UNDEFINED，value 是 undefined。
     * - 对于 T_STRING，value 通常是去掉引号后的字符串内容。
     * - 对于其他类型（如 T_IDENTIFIER），value 默认等于其 text。
     * 
     * 该值可以在构造时被手动覆盖。
     */
    public var value;

    /** Token在源代码中起始位置的行号。默认为 0。 */
    public var line:Number;

    /** Token在源代码中起始位置的列号。默认为 0。 */
    public var column:Number;
    
    // ============= 构造函数 =============
    /**
     * 创建一个新的 PrattToken 实例。
     * 
     * @param tokenType Token的类型，应为 PrattToken.T_... 常量之一。
     * @param tokenText 从源代码中提取的原始文本。
     * @param tokenLine Token在源文件中的行号 (可选, 默认为 0)。
     * @param tokenColumn Token在源文件中的列号 (可选, 默认为 0)。
     * @param tokenValue Token的语义值 (可选)。
     * 
     * @behavior 值处理逻辑 (Value Handling Logic):
     * 1. **手动覆盖 (Manual Override):** 如果 `tokenValue` 参数被显式传递（即使其值为 `null` 或 `undefined`），
     *    那么 `this.value` 将直接被赋予 `tokenValue` 的值，并且不会进行任何自动转换。
     *    这是通过检查 `arguments.length > 4` 实现的。
     * 
     * 2. **自动转换 (Automatic Conversion):** 如果 `tokenValue` 参数未被传递，构造函数会根据 `tokenType` 自动推断 `this.value`：
     *    - `T_NUMBER`: 将 `text` 转换为 `Number` (自动区分整数和浮点数)。
     *    - `T_BOOLEAN`: 将 "true" 转换为 `true`，"false" 转换为 `false`。
     *    - `T_NULL`: 设置为 `null`。
     *    - `T_UNDEFINED`: 设置为 `undefined`。
     *    - **其他所有类型**: `value` 默认等于 `text`。
     */
    public function PrattToken(tokenType:String, tokenText:String, tokenLine:Number, tokenColumn:Number, tokenValue) {
        this.type = tokenType;
        this.text = tokenText;
        this.line = tokenLine || 0;     // 如果 tokenLine 是 undefined, null, 或 0, 结果为 0。
        this.column = tokenColumn || 0; // 如果 tokenColumn 是 undefined, null, 或 0, 结果为 0。
        
        // 使用 arguments.length 是 ActionScript 2 中判断可选参数是否被传递的可靠方法。
        // 它能区分 `new PrattToken(..., undefined)` (传递了undefined) 和 `new PrattToken(...)` (未传递第五个参数) 的情况。
        if (arguments.length > 4) { 
            // 只要调用时提供了第5个参数，就使用它的值，即使是 undefined 或 null。
            // 这覆盖了所有自动转换逻辑。
            this.value = tokenValue;
        } else {
            // 只有在未提供第5个参数时，才进行自动转换。
            switch (type) {
                case T_NUMBER:
                    // 如果文本中包含".", 则解析为浮点数，否则解析为整数。
                    this.value = text.indexOf(".") >= 0 ? parseFloat(text) : parseInt(text);
                    break;
                case T_BOOLEAN:
                    this.value = (text == "true");
                    break;
                case T_NULL:
                    this.value = null;
                    break;
                case T_UNDEFINED:
                    this.value = undefined;
                    break;
                default:
                    // 对于标识符、运算符等，其值就是其文本本身。
                    this.value = text;
                    break;
            }
        }
    }
    
    // ============= 辅助方法 =============
    /**
     * 检查当前Token的类型是否与给定的类型匹配。
     * @param tokenType 要比较的Token类型字符串，例如 `PrattToken.T_NUMBER`。
     * @return 如果类型匹配，则返回 `true`；否则返回 `false`。
     */
    public function is(tokenType:String):Boolean {
        return this.type == tokenType;
    }
    
    /**
     * 检查当前Token是否为字面量类型。
     * 字面量类型包括：数字、字符串、布尔值、null 和 undefined。
     * @return 如果是字面量类型，则返回 `true`；否则返回 `false`。
     */
    public function isLiteral():Boolean {
        return type == T_NUMBER || type == T_STRING || type == T_BOOLEAN || 
               type == T_NULL || type == T_UNDEFINED;
    }
    
    /**
     * 获取Token的数字值。
     * 这是一个类型安全的获取器。
     * @return 返回 `Number` 类型的 `value`。
     * @throws Error 如果Token的类型不是 `T_NUMBER`，则抛出错误。
     */
    public function getNumberValue():Number {
        if (type == T_NUMBER) {
            return Number(value);
        }
        throw new Error("Token不是数字类型: " + type);
    }
    
    /**
     * 获取Token的字符串值。
     * 这是一个类型安全的获取器。
     * @return 返回 `String` 类型的 `value`。
     * @throws Error 如果Token的类型不是 `T_STRING`，则抛出错误。
     */
    public function getStringValue():String {
        if (type == T_STRING) {
            return String(value);
        }
        throw new Error("Token不是字符串类型: " + type);
    }
    
    /**
     * 获取Token的布尔值。
     * 这是一个类型安全的获取器。
     * @return 返回 `Boolean` 类型的 `value`。
     * @throws Error 如果Token的类型不是 `T_BOOLEAN`，则抛出错误。
     */
    public function getBooleanValue():Boolean {
        if (type == T_BOOLEAN) {
            return Boolean(value);
        }
        throw new Error("Token不是布尔类型: " + type);
    }
    
    /**
     * 创建一个包含此Token上下文信息的错误消息字符串。
     * 用于生成清晰、易于定位的解析错误。
     * @param message 核心错误信息。
     * @return 格式化后的完整错误字符串，例如："Syntax error at line 10, column 5 (token: '+')"。
     */
    public function createError(message:String):String {
        return message + " at line " + line + ", column " + column + " (token: '" + text + "')";
    }

    /**
     * 返回Token的字符串表示形式，主要用于调试。
     * @return 格式化的字符串，例如："[NUMBER '123' = 123 @1:5]" 或 "[IDENTIFIER 'myVar' @2:10]"。
     * 
     * @behavior 字符串格式：
     * - `[TYPE 'text' = value @line:column]`
     * - `TYPE`: Token的类型。
     * - `'text'`: Token的原始文本。
     * - `= value`: 仅当 `value` 和 `text` 不等且 `value` 不为 `null` 时显示，以避免冗余。
     * - `@line:column`: 仅当 `line` 大于 0 时显示位置信息。
     */
    public function toString():String {
        var result:String = "[" + type;
        if (text != null) result += " '" + text + "'";
        
        // 修正条件：仅当 `value` 与 `text` 的值不同时才显示 `value` 部分。
        // 这样可以避免为 T_IDENTIFIER 等类型显示多余信息 (如 "value = myVar")。
        // 同时，`value` 为 `null` 时也不显示，因为 `T_NULL` 类型本身已经足够明确。
        if (value !== text && value !== null) {
            result += " = " + value;
        }
        
        // 只有当行号有效时（大于0），才显示位置信息。
        if (line > 0) result += " @" + line + ":" + column;
        
        result += "]";
        return result;
    }
}