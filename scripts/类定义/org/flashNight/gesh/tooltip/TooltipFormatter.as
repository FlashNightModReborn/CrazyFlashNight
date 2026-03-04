import org.flashNight.gesh.tooltip.TooltipConstants;

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

  /**
   * 将 XML 简介文本规范化为 HTML 片段。
   * - 统一 \r\n / \n 换行为 <BR>
   * - 去除每行行首的缩进空白（XML 格式化产生的多余空格/制表符）
   */
  public static function normalizeDescription(text:String):String {
    var normalized:String = text.split("\r\n").join("\n");
    var lines:Array = normalized.split("\n");
    var result:String = "";
    for (var i:Number = 0; i < lines.length; i++) {
      var line:String = lines[i];
      // 去除行首缩进空白（XML 格式化产生的多余空格/制表符）
      var j:Number = 0;
      while (j < line.length && (line.charAt(j) == " " || line.charAt(j) == "\t")) {
        j++;
      }
      line = line.substring(j);
      if (i == 0) {
        result = line;
      } else {
        // 若该行已以 <BR> 开头（XML 中用 &lt;BR&gt; 写的显式分隔符），
        // 则该 <BR> 本身就是分隔符，不再额外追加一个，避免产生双重换行空行。
        if (line.substring(0, 4).toUpperCase() == "<BR>") {
          result += line;
        } else {
          result += "<BR>" + line;
        }
      }
    }
    return result;
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
    buf:Array, data:Object, equipData:Object, property:String, label:String, suffix:String
  ):Void {
    var base = data[property];
    var final = equipData[property];
    if(!base && !final) return;

    if(!label) label = TooltipConstants.PROPERTY_DICT[property];
    if(!label) label = property;
    if(!suffix) suffix = "";

    // 若没有实际装备数值或实际数值与原始数值相等，则打印原始数值
    if(!equipData || final == base){
      buf.push(label, "：", base, suffix, "<BR>");
      return;
    }
    
    // 以橙色字体打印实际数值
    buf.push(label, "：<FONT COLOR='" + TooltipConstants.COL_HL + "'>", final, suffix, "</FONT>");
    if(base == null) base = 0;
    // 若属性为数字，则额外打印增幅值
    if(isNaN(final) || isNaN(base)){
      buf.push(" (" + TooltipConstants.TXT_OVERRIDE + base + ")<BR>");
    }else{
      var enhance = final - base;
      var sign:String;
      if(enhance < 0) {
        enhance = -enhance;
        sign = " - ";
      } else {
        sign = " + ";
      }
      buf.push(" (", base, sign, enhance, ")<BR>");
    }
  }
  
  public static function colorLine(buf:Array, hex:String, text:String):Void {
    if (text == undefined || text == "") return;
    buf.push("<FONT COLOR='" + hex + "'>", text, "</FONT><BR>");
  }

  public static function enhanceLine(buf:Array, type:String, data:Object, property:String, val, label:String):Void {
    var base = data[property];
    if (!val) return;

    if(!label) label = TooltipConstants.PROPERTY_DICT[property];
    if(!label) label = property;

    if(type === "add"){
      var n:Number = Number(val);
      if(isNaN(n) || n === 0) return;
      var sign = " + ";
      if(n < 0){
        n = -n;
        sign = " - ";
      }
      buf.push(label, sign, n, "<BR>");
    }else if(type === "multiply"){
      if(!base) return;
      var n:Number = (Number(val) * 100) >> 0;
      var sign = " + ";
      if(n < 0){
        n = -n;
        sign = " - ";
      }
      if(isNaN(n) || n === 0) return;
      buf.push(label, sign, n, "%<BR>");
    }else if(type === "override"){
      buf.push(label, " -> ", val, "<BR>");
    }
  }

  public static function statLine(buf:Array, type:String, property:String, val, label:String):Void {
    if (!val) return;

    if(!label) label = TooltipConstants.PROPERTY_DICT[property];
    if(!label) label = property;

    if(type === "add"){
      var n:Number = Number(val);
      if(isNaN(n) || n === 0) return;
      var sign = " + ";
      if(n < 0){
        n = -n;
        sign = " - ";
      }
      buf.push(label, sign, n, "<BR>");
    }else if(type === "multiply"){
      var n:Number = (Number(val) * 100) >> 0;
      var sign = " + ";
      if(n < 0){
        n = -n;
        sign = " - ";
      }
      if(isNaN(n) || n === 0) return;
      buf.push(label, sign, n, "%<BR>");
    }else if(type === "override"){
      buf.push(label, " -> ", val, "<BR>");
    }else if(type === "merge"){
      // merge统一显示为箭头形式（表示智能合并）
      buf.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TAG_MERGE + "</FONT> ", label, " -> ", val, "<BR>");
    }
  }
}