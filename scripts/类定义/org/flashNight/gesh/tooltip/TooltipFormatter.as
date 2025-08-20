class org.flashNight.gesh.tooltip.TooltipFormatter {
  public static function bold(s:String):String {
    return "<B>" + s + "</B>";
  }
  
  public static function color(s:String, hex:String):String {
    return "<FONT COLOR='" + hex + "'>" + s + "</FONT>"; 
  }
  
  public static function br():String {
    return "<BR>";
  }
  
  public static function kv(label:String, val, suffix:String):String {
    if (suffix === undefined) suffix = "";
    return label + "：" + val + suffix;
  }
   
  public static function numLine(buf:Array, label:String, val, suffix:String):Void {
    if (val === undefined || val === null) return;
    var n:Number = Number(val);
    if (!isNaN(n) && n === 0) return;
    if (val === "" || val == "0" || val == "null") return;
    buf.push(label, "：", (isNaN(n) ? val : n), (suffix ? suffix : ""), "<BR>");
  }
  
  public static function upgradeLine(
    buf:Array, label:String, base:Number, lvl:Number,
    hlColor:String, sep:String
  ):Void {
    if (base === undefined || isNaN(base) || base === 0) return;
    if (hlColor == undefined) hlColor = org.flashNight.gesh.tooltip.TooltipConstants.COL_HL;
    if (sep == undefined) sep = "：";
    buf.push(label, sep, base);
    var enhanced:Number = _root.强化计算(base, lvl);
    buf.push("<FONT COLOR='" + hlColor + "'>(+", (enhanced - base), ")</FONT><BR>");
  }
  
  public static function colorLine(buf:Array, hex:String, text:String):Void {
    if (text == undefined || text == "") return;
    buf.push("<FONT COLOR='" + hex + "'>", text, "</FONT><BR>");
  }
}