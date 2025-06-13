import org.flashNight.gesh.pratt.*;

/**
 * PrattCore.as - 包含Token和Lexer核心类
 * 合并了PrattToken和PrattLexer
 */

// ============================================================================
// Token类 - 词法单元
// ============================================================================
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
    public static var T_MATH:String = "MATH";
    
    // ============= 实例属性 =============
    public var type:String;
    public var text:String;
    public var value;
    public var line:Number;
    public var column:Number;
    
    // ============= 构造函数 =============
    public function PrattToken(tokenType:String, tokenText:String, tokenLine:Number, tokenColumn:Number, tokenValue) {
        type = tokenType;
        text = tokenText;
        line = tokenLine || 0;
        column = tokenColumn || 0;
        
        if (tokenValue !== undefined) {
            value = tokenValue;
        } else {
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
    }
    
    // ============= 辅助方法 =============
    public function is(tokenType:String):Boolean {
        return this.type == tokenType;
    }
    
    public function isLiteral():Boolean {
        return type == T_NUMBER || type == T_STRING || type == T_BOOLEAN || 
               type == T_NULL || type == T_UNDEFINED;
    }
    
    public function getNumberValue():Number {
        if (type == T_NUMBER) {
            return Number(value);
        }
        throw new Error("Token不是数字类型: " + type);
    }
    
    public function getStringValue():String {
        if (type == T_STRING) {
            return String(value);
        }
        throw new Error("Token不是字符串类型: " + type);
    }
    
    public function getBooleanValue():Boolean {
        if (type == T_BOOLEAN) {
            return Boolean(value);
        }
        throw new Error("Token不是布尔类型: " + type);
    }
    
    public function createError(message:String):String {
        return message + " at line " + line + ", column " + column + " (token: '" + text + "')";
    }
    
    public function toString():String {
        var result:String = "[" + type;
        if (text != null) result += " '" + text + "'";
        if (value != text && value != null) result += " = " + value;
        if (line > 0) result += " @" + line + ":" + column;
        result += "]";
        return result;
    }
}
