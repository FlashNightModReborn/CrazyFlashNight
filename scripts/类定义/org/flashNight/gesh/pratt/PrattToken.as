/* -------------------------------------------------------------------------
 *  PrattToken.as
 * -------------------------------------------------------------------------*/
class org.flashNight.gesh.pratt.PrattToken {
    public static var T_EOF:String        = "EOF";
    public static var T_NUMBER:String     = "NUMBER";
    public static var T_IDENTIFIER:String = "ID";
    public static var T_OPERATOR:String   = "OP";
    public static var T_LPAREN:String     = "LPAREN";
    public static var T_RPAREN:String     = "RPAREN";

    public var type:String;
    public var text:String;
    public var value:String;

    public function PrattToken(t:String, txt:String) {
        type  = t;
        text  = txt;
        value = txt;
    }
}