class org.flashNight.gesh.string.TooltipLayout {
  public static function estimateWidth(html:String, minW:Number, maxW:Number, constants:Object):Number {
    if (!html) return minW;
    
    var cleanText = html;
    cleanText = cleanText.split("<BR>").join("");
    cleanText = cleanText.split("<B>").join("");
    cleanText = cleanText.split("</B>").join("");
    
    var fontPattern = /<FONT[^>]*>([^<]*)<\/FONT>/gi;
    while (fontPattern.test(cleanText)) {
      cleanText = cleanText.replace(fontPattern, "$1");
    }
    
    var totalWidth = 0;
    for (var i = 0; i < cleanText.length; i++) {
      var char = cleanText.charAt(i);
      var charCode = cleanText.charCodeAt(i);
      
      if (charCode >= 0x4E00 && charCode <= 0x9FFF) {
        totalWidth += constants.CHAR_CJK_WIDTH;
      } else {
        totalWidth += constants.CHAR_LATIN_WIDTH;
      }
    }
    
    if (totalWidth < minW) return minW;
    if (totalWidth > maxW) return maxW;
    return totalWidth;
  }
  
  public static function applyIntroLayout(itemType:String, target:MovieClip, background:MovieClip, text:TextField, constants:Object):Object {
    var width = Number(constants.BASE_NUM);
    var heightOffset = Number(constants.BG_HEIGHT_OFFSET);
    
    if (itemType === "刀" || itemType === "手枪" || itemType === "长枪") {
      width *= constants.RATE;
    }
    
    target._width = width;
    if (background) {
      background._width = width + constants.TEXT_PAD;
      background._height = text._height + heightOffset;
    }
    
    return {width: width, heightOffset: heightOffset};
  }
  
  public static function positionTooltip(tips:MovieClip, background:MovieClip, mouseX:Number, mouseY:Number, constants:Object):Void {
    if (!tips || !background) return;
    
    var offsetX = constants.OFFSET_X || 0;
    var offsetY = constants.OFFSET_Y || 0;
    
    tips._x = mouseX + offsetX;
    tips._y = mouseY + offsetY;
    
    if (tips._x + background._width > Stage.width) {
      tips._x = mouseX - background._width - offsetX;
    }
    if (tips._y + background._height > Stage.height) {
      tips._y = mouseY - background._height - offsetY;
    }
  }
}