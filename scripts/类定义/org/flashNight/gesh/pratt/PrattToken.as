import org.flashNight.gesh.pratt.*;

/* -------------------------------------------------------------------------
 *  增强版 PrattToken.as —— 支持更多token类型和位置信息
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.PrattToken {
    
    // ============= 基础类型 =============
    public static var T_EOF:String = "EOF";
    public static var T_NUMBER:String = "NUMBER";
    public static var T_IDENTIFIER:String = "IDENTIFIER";
    public static var T_STRING:String = "STRING";
    public static var T_BOOLEAN:String = "BOOLEAN";
    public static var T_NULL:String = "NULL";
    public static var T_UNDEFINED:String = "UNDEFINED";
    
    // ============= 运算符 =============
    public static var T_OPERATOR:String = "OPERATOR";
    public static var T_ASSIGNMENT:String = "ASSIGNMENT";
    public static var T_COMPARISON:String = "COMPARISON";
    public static var T_LOGICAL:String = "LOGICAL";
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
    public static var T_FUNCTION:String = "FUNCTION";
    public static var T_RETURN:String = "RETURN";
    public static var T_VAR:String = "VAR";
    public static var T_CONST:String = "CONST";
    public static var T_LET:String = "LET";
    
    // ============= Buff系统专用 =============
    public static var T_BUFF_TYPE:String = "BUFF_TYPE";
    public static var T_SET_BASE:String = "SET_BASE";
    public static var T_ADD_FLAT:String = "ADD_FLAT";
    public static var T_ADD_PERCENT_BASE:String = "ADD_PERCENT_BASE";
    public static var T_ADD_PERCENT_CURRENT:String = "ADD_PERCENT_CURRENT";
    public static var T_MUL_PERCENT:String = "MUL_PERCENT";
    public static var T_ADD_FINAL:String = "ADD_FINAL";
    public static var T_CLAMP_MAX:String = "CLAMP_MAX";
    public static var T_CLAMP_MIN:String = "CLAMP_MIN";
    
    // ============= 实例属性 =============
    public var type:String;
    public var text:String;
    public var value; // 可以是String、Number、Boolean等
    public var line:Number;
    public var column:Number;
    public var position:Number; // 在源码中的绝对位置
    
    // ============= 构造函数 =============
    public function PrattToken(tokenType:String, tokenText:String, tokenLine:Number, tokenColumn:Number, tokenValue) {
        type = tokenType;
        text = tokenText;
        line = tokenLine || 0;
        column = tokenColumn || 0;
        
        // 如果没有提供value，使用text作为默认值
        if (tokenValue !== undefined) {
            value = tokenValue;
        } else {
            // 根据类型自动转换
            switch (type) {
                case T_NUMBER:
                    value = text.indexOf(".") >= 0 ? parseFloat(text) : parseInt(text);
                    break;
                case T_BOOLEAN:
                    value = text == "true";
                    break;
                case T_NULL:
                    value = null;
                    break;
                case T_UNDEFINED:
                    value = undefined;
                    break;
                default:
                    value = text;
                    break;
            }
        }
        
        position = -1; // 可以在词法分析器中设置
    }
    
    // ============= 兼容性构造函数 =============
    // 为了兼容原有代码，保留简单的构造方式
    public static function simple(tokenType:String, tokenText:String):PrattToken {
        return new PrattToken(tokenType, tokenText, 0, 0);
    }
    
    // ============= 辅助方法 =============
    
    /**
     * 检查token是否为指定类型
     */
    public function is(tokenType:String):Boolean {
        return this.type == tokenType;
    }
    
    /**
     * 检查token是否为指定的多个类型之一
     */
    public function isOneOf(types:Array):Boolean {
        for (var i:Number = 0; i < types.length; i++) {
            if (this.type == types[i]) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 检查是否为数字类型
     */
    public function isNumber():Boolean {
        return type == T_NUMBER;
    }
    
    /**
     * 检查是否为字符串类型
     */
    public function isString():Boolean {
        return type == T_STRING;
    }
    
    /**
     * 检查是否为标识符
     */
    public function isIdentifier():Boolean {
        return type == T_IDENTIFIER;
    }
    
    /**
     * 检查是否为运算符
     */
    public function isOperator():Boolean {
        return type == T_OPERATOR || type == T_ASSIGNMENT || 
               type == T_COMPARISON || type == T_LOGICAL || 
               type == T_ARITHMETIC;
    }
    
    /**
     * 检查是否为buff类型token
     */
    public function isBuffType():Boolean {
        return isOneOf([
            T_SET_BASE, T_ADD_FLAT, T_ADD_PERCENT_BASE,
            T_ADD_PERCENT_CURRENT, T_MUL_PERCENT, T_ADD_FINAL,
            T_CLAMP_MAX, T_CLAMP_MIN
        ]);
    }
    
    /**
     * 检查是否为字面量（数字、字符串、布尔值等）
     */
    public function isLiteral():Boolean {
        return isOneOf([T_NUMBER, T_STRING, T_BOOLEAN, T_NULL, T_UNDEFINED]);
    }
    
    /**
     * 检查是否为分隔符
     */
    public function isDelimiter():Boolean {
        return isOneOf([
            T_LPAREN, T_RPAREN, T_LBRACKET, T_RBRACKET,
            T_LBRACE, T_RBRACE, T_COMMA, T_SEMICOLON,
            T_DOT, T_COLON, T_QUESTION
        ]);
    }
    
    /**
     * 获取数字值（如果是数字token）
     */
    public function getNumberValue():Number {
        if (isNumber()) {
            return Number(value);
        }
        throw new Error("Token不是数字类型: " + type);
    }
    
    /**
     * 获取字符串值（如果是字符串token）
     */
    public function getStringValue():String {
        if (isString()) {
            return String(value);
        }
        throw new Error("Token不是字符串类型: " + type);
    }
    
    /**
     * 获取布尔值（如果是布尔token）
     */
    public function getBooleanValue():Boolean {
        if (type == T_BOOLEAN) {
            return Boolean(value);
        }
        throw new Error("Token不是布尔类型: " + type);
    }
    
    /**
     * 获取位置信息字符串
     */
    public function getPositionString():String {
        return "line " + line + ", column " + column;
    }
    
    /**
     * 创建错误信息（包含位置）
     */
    public function createError(message:String):String {
        return message + " at " + getPositionString() + " (token: '" + text + "')";
    }
    
    /**
     * 检查token文本是否匹配
     */
    public function textEquals(expectedText:String):Boolean {
        return text == expectedText;
    }
    
    /**
     * 检查token文本是否为指定文本之一
     */
    public function textIsOneOf(expectedTexts:Array):Boolean {
        for (var i:Number = 0; i < expectedTexts.length; i++) {
            if (text == expectedTexts[i]) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 复制token（用于lookahead等场景）
     */
    public function clone():PrattToken {
        var cloned:PrattToken = new PrattToken(type, text, line, column, value);
        cloned.position = position;
        return cloned;
    }
    
    /**
     * 调试字符串表示
     */
    public function toString():String {
        var result:String = "[" + type;
        if (text != null) result += " '" + text + "'";
        if (value != text && value != null) result += " = " + value;
        if (line > 0) result += " @" + line + ":" + column;
        result += "]";
        return result;
    }
    
    /**
     * 简短的字符串表示
     */
    public function toShortString():String {
        return type + "('" + text + "')";
    }
    
    // ============= 静态工具方法 =============
    
    /**
     * 快速创建数字token
     */
    public static function number(value:Number, line:Number, column:Number):PrattToken {
        return new PrattToken(T_NUMBER, String(value), line, column, value);
    }
    
    /**
     * 快速创建字符串token
     */
    public static function string(value:String, line:Number, column:Number):PrattToken {
        return new PrattToken(T_STRING, "\"" + value + "\"", line, column, value);
    }
    
    /**
     * 快速创建标识符token
     */
    public static function identifier(name:String, line:Number, column:Number):PrattToken {
        return new PrattToken(T_IDENTIFIER, name, line, column, name);
    }
    
    /**
     * 快速创建运算符token
     */
    public static function operator(op:String, line:Number, column:Number):PrattToken {
        return new PrattToken(T_OPERATOR, op, line, column, op);
    }
    
    /**
     * 快速创建EOF token
     */
    public static function eof():PrattToken {
        return new PrattToken(T_EOF, "<eof>", 0, 0, null);
    }
    
    /**
     * 检查操作符优先级类别
     */
    public function getOperatorCategory():String {
        switch (text) {
            case "=":
            case "+=":
            case "-=":
            case "*=":
            case "/=":
            case "%=":
                return "assignment";
            case "||":
            case "&&":
                return "logical";
            case "==":
            case "!=":
            case "===":
            case "!==":
            case "<":
            case ">":
            case "<=":
            case ">=":
                return "comparison";
            case "+":
            case "-":
            case "*":
            case "/":
            case "%":
            case "**":
                return "arithmetic";
            default:
                return "other";
        }
    }
}