import org.flashNight.gesh.pratt.*;

/* -------------------------------------------------------------------------
 *  PrattRegistry.as —— 操作符解析策略注册表
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.PrattRegistry {
    // {tokenText:String → {bp:Number, rightAssoc:Boolean, led:Function}}
    private static var _infix:Object = {};
    // {tokenType:String → nud:Function}
    private static var _prefix:Object = {};
    private static var _bpCache:Object = {}; // 绑定功率缓存，查一次后写入

    /* 清空（单元测试 / 热重载用） */
    public static function clear():Void {
        _infix = {}; _prefix = {}; _bpCache = {}; }

    /* 注册前缀解析器 */
    public static function registerPrefix(tokenType:String, nudFunc:Function):Void {
        _prefix[tokenType] = nudFunc; }

    /* 注册中缀解析器 */
    public static function registerInfix(tokenText:String, config:Object):Void {
        _infix[tokenText] = config; }

    /* 工具：左/右结合构造器 */
    public static function leftAssoc(bp:Number, fn:Function):Object {
        return {bp:bp, rightAssoc:false, led:fn}; }
    public static function rightAssoc(bp:Number, fn:Function):Object {
        return {bp:bp, rightAssoc:true, led:fn}; }

    /* 供 PrattParser 查询 */
    public static function getPrefix(tokenType:String):Function {
        return _prefix[tokenType]; }
    public static function getInfix(tokenText:String):Object {
        return _infix[tokenText]; }
}