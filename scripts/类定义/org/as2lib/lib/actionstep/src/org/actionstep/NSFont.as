/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 * are permitted provided that the following conditions are met:
 * 
 * 1) Redistributions of source code must retain the above copyright notice, 
 *    this list of conditions and the following disclaimer.
 *  
 * 2) Redistributions in binary form must reproduce the above copyright notice, 
 *    this list of conditions and the following disclaimer in the documentation 
 *    and/or other materials provided with the distribution. 
 * 
 * 3) The name InfoEther, Inc. may not be used to endorse or promote products 
 *    derived from this software without specific prior written permission. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
 * POSSIBILITY OF SUCH DAMAGE.
 */
 
import org.actionstep.NSSize;
import org.actionstep.constants.NSTextAlignment;
import org.actionstep.NSException;

class org.actionstep.NSFont extends org.actionstep.NSObject {
  
  public static var DEFAULT_SYSTEM_FONT_NAME:String = "Arial";
  private static var g_system_font_name:String;
  private static var g_system_font_embedded:Boolean = false;
  private static var g_system_font_size:Number = 12;
  
  private var m_pointSize:Number;
  private var m_fontName:String;
  private var m_isBold:Boolean;
  private var m_isEmbedded:Boolean;
  
  public function NSFont() {
    m_isBold = false;
    m_isEmbedded = false;
  }
  
  public static function setDefaultSystemFontNameSizeEmbedded(name:String, size:Number, embedded:Boolean) {
    g_system_font_size = size;
    g_system_font_name = name;
    g_system_font_embedded = embedded;
  }

  public static function fontWithNameSizeEmbedded(name:String, size:Number, embedded:Boolean):NSFont {
    //! Implement correctly
    var font:NSFont = new NSFont();
    font.setFontName(name);
    font.setPointSize(size);
    font.setEmbedded(embedded);
    return font;
  }
  
  public static function fontWithNameSize(name:String, size:Number):NSFont {
    return fontWithNameSizeEmbedded(name, size, false);
  }
  
  public static function systemFontOfSize(size:Number):NSFont {
    if (size <= 0) {
      size = g_system_font_size;
    }
    if (g_system_font_name == undefined) {
      g_system_font_name = DEFAULT_SYSTEM_FONT_NAME;
    }
    return fontWithNameSizeEmbedded(g_system_font_name, size, g_system_font_embedded);
  }
  
  public static function boldSystemFontOfSize(size:Number):NSFont {
    var font:NSFont = systemFontOfSize(size);
    font.setBold(true);
    return font;
  }
	
	public static function menuFontOfSize(size:Number):NSFont {
		//! FIXME
		return systemFontOfSize(size);
	}
  
  /*
  + controlContentFontOfSize:
  + labelFontOfSize:
  + menuBarFontOfSize:
  + messageFontOfSize:
  + paletteFontOfSize:
  + titleBarFontOfSize:
  + toolTipsFontOfSize:
  */
  
  public function description():String {
    return "NSFont(fontName="+m_fontName+", pointSize="+m_pointSize+", bold="+m_isBold+")";
  }
  
  public function setPointSize(value:Number) {
    m_pointSize = value;
  }
  
  public function pointSize():Number {
    return m_pointSize;
  }
  
  public function setFontName(value:String) {
    m_fontName = value;
  }
  
  public function fontName():String {
    return m_fontName;
  }
  
  /*
  * This is an ActionStep specific function. 
  */  
  public function isBold():Boolean {
    return m_isBold;    
  }
  
  /*
  * This is an ActionStep specific function. 
  */  
  public function setBold(value:Boolean) {
    m_isBold = value;
  }
  
  /**
   * Returns if this font is based on an embedded font (must be a symbol in the Library)
   */
  public function isEmbedded():Boolean {
    return m_isEmbedded;
  }

  /**
   * Sets if this is based on an embedded font (must be a symbol in the Library)
   */
  public function setEmbedded(value:Boolean) {
    m_isEmbedded = value;
  }
  
  /**
   * Returns the TextFormat object corresponding to this font's properties.
   *
   * This is an ActionStep specific function. 
   */  
  public function textFormat():TextFormat {
    var tf:TextFormat = new TextFormat();
    tf.size = m_pointSize;
    tf.font = m_fontName;
    tf.bold = m_isBold;
    return tf;
  }
  
  /**
   * Returns the TextFormat object corresponding to this font's properties and
   * an alignment object.
   *
   * This is an ActionStep specific function. 
   */  
  public function textFormatWithAlignment(alignment:NSTextAlignment):TextFormat
  {
  	var tf:TextFormat = textFormat();
  	var setting:String;
  	
    switch (alignment.value)
    {
      case 0:
        setting = "left";
        break;
    		
      case 1:
        setting = "right";
        break;

      case 2:
        setting = "center";
        break;

      case 4:
      	setting = "left"; //! should be set to localized setting...
      	break;
      	
      default:
		var e:NSException = NSException.exceptionWithNameReasonUserInfo(
			"UnsupportedOperationException", 
			"NSTextAlignment.NSNaturalTextAlignment" +
			" is not supported.", 
			null);
		trace(e);
		throw e;
        break;
      
    }
    
    tf.align = setting;
    
    return tf;
  }
  /**
   * Returns the size of aString when rendered in this font on a single line.
   *
   * This is an ActionStep specific function. 
   */
  public function getTextExtent(aString:String):NSSize
  {
    var measure:TextField = _root.m_textMeasurer;

    if (measure == undefined)
    {
      _root.createTextField("m_textMeasurer", -16384, 0, 0, 1000, 100);
      measure = _root.m_textMeasurer;
      measure._visible = false;
    }
    
    var tf:TextFormat = this.textFormat();
    tf.align = "left";
    measure.text = aString;
    measure.setTextFormat(tf);
    
    return new NSSize(measure.textWidth + 4, measure.textHeight + 4);
  }

  public function getHTMLTextExtent(aString:String):NSSize
  {
    var measure:TextField = _root.m_htmlTextMeasurer;

    if (measure == undefined)
    {
      _root.createTextField("m_htmlTextMeasurer", -16383, 0, 0, 1000, 100);
      measure = _root.m_htmlTextMeasurer;
      measure._visible = false;
      measure.html = true;
    }
    
    var tf:TextFormat = this.textFormat();
    tf.align = "left";
    measure.htmlText = aString;
    measure.setTextFormat(tf);
    
    return new NSSize(measure.textWidth + 4, measure.textHeight + 4);
  }
  
}