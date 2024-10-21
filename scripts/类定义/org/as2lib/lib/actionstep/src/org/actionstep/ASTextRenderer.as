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
 
import org.actionstep.NSView;
import org.actionstep.NSRect;
import org.actionstep.NSSize;
import org.actionstep.ASTheme;

class org.actionstep.ASTextRenderer extends NSView {
  
  private var m_textField:TextField;
  private var m_text:String;
  private var m_style:TextField.StyleSheet;
  private var m_leftMargin:Number;
  private var m_rightMargin:Number;
  private var m_topMargin:Number;
  private var m_bottomMargin:Number;
  private var m_automaticResize:Boolean;
  private var m_wordWrap:Boolean;
  private var m_drawsBackground:Boolean;
  private var m_usesEmbeddedFonts:Boolean;

  public function ASTextRenderer() {
    m_topMargin = 5;
    m_leftMargin = 5;
    m_bottomMargin = 5;
    m_rightMargin = 5;
    m_automaticResize = false;
    m_wordWrap = false;
    m_drawsBackground = true;
    m_usesEmbeddedFonts = false;
  }
  
  public function initWithFrame(rect:NSRect):ASTextRenderer {
    super.initWithFrame(rect);
    return this;
  }

  public function createMovieClips() {
    super.createMovieClips();
    if (m_mcBounds != null) {
      m_textField = createBoundsTextField();
      m_textField.border = false;
      m_textField.type = "dynamic";
      m_textField.wordWrap = m_wordWrap;
      m_textField.embedFonts = m_usesEmbeddedFonts;
      m_textField.multiline = true;
      m_textField.autoSize = false;
      m_textField.html = true;
      m_textField._x = m_leftMargin;
      m_textField._y = m_topMargin;
      m_textField.editable = false;
      m_textField.selectable = true;
      m_textField.styleSheet = m_style;
      m_textField.htmlText = m_text;
      m_textField._width = bounds().size.width - m_leftMargin - m_rightMargin;
      m_textField._height = bounds().size.height - m_topMargin - m_bottomMargin;
      autoSize();
    }
  }

  public function setRightMargin(value:Number) {
    m_rightMargin = value;
  }

  public function rightMargin():Number {
    return m_rightMargin;
  }

  public function setLeftMargin(value:Number) {
    m_leftMargin = value;
    m_textField._x = m_leftMargin;
    autoSize();
  }

  public function leftMargin():Number {
    return m_leftMargin;
  }

  public function setTopMargin(value:Number) {
    m_topMargin = value;
    m_textField._y = m_topMargin;
    autoSize();
  }

  public function topMargin():Number {
    return m_topMargin;
  }

  public function setBottomMargin(value:Number) {
    m_bottomMargin = value;
    autoSize();
  }

  public function bottomMargin():Number {
    return m_bottomMargin;
  }
  
  public function wordWrap():Boolean {
    return m_wordWrap;
  }
  
  public function setWordWrap(value:Boolean) {
    m_wordWrap = value;
    m_textField.wordWrap = m_wordWrap;
    m_textField.styleSheet = m_style;
    m_textField.htmlText = m_text;
    autoSize();
  }
  
  public function setAutomaticResize(value:Boolean) {
    if(m_automaticResize == value) return;
    m_automaticResize = value;
    autoSize();
  }
  
  public function automaticResize():Boolean {
    return m_automaticResize;
  }

  public function setStyleSheet(style:TextField.StyleSheet) {
    m_style = style;
    m_textField.styleSheet = m_style;
    m_textField.htmlText = m_text;
  }

  public function styleSheet():TextField.StyleSheet {
    return m_style;
  }
  
  public function setStyleCSS(css:String):Boolean {
    var style:TextField.StyleSheet =  new TextField.StyleSheet();
    if (style.parseCSS(css)) {
      setStyleSheet(style);
      return true;
    } else {
      return false;
    }
  }
  
  public function setUsesEmbeddedFonts(value:Boolean) {
    m_usesEmbeddedFonts = value;
    if (m_textField != undefined) {
      m_textField.embedFonts = m_usesEmbeddedFonts;
    }
  }

  public function usesEmbeddedFonts():Boolean {
    return m_usesEmbeddedFonts;
  }

  public function setText(text:String) {
    m_text = text;
    if (m_textField != null) {  
      m_textField.htmlText = m_text;
    }
    autoSize();
  }
  
  public function setDrawsBackground(value:Boolean) {
    if (m_drawsBackground == value) return;
    m_drawsBackground = value;
    setNeedsDisplay(true);
  }
  
  public function drawsBackground():Boolean {
    return m_drawsBackground;
  }

  public function text():String {
    return m_text;
  }

  public function drawRect(rect:NSRect) {
    if (m_drawsBackground) {
      ASTheme.current().drawListWithRectInView(rect, this);
    }
  }
  
  public function setFrame(rect:NSRect) {
    if (m_automaticResize && m_textField != null) {
      rect.size.height = m_textField.textHeight + m_topMargin + m_bottomMargin+10;
      if (!m_wordWrap) {
        rect.size.width = m_textField.textWidth + m_leftMargin + m_rightMargin+10;
      }
    } 
    super.setFrame(rect);
    m_textField._width = rect.size.width  - m_leftMargin - m_rightMargin;
    m_textField._height = rect.size.height - m_topMargin - m_bottomMargin;
  }
  
  public function setFrameSize(size:NSSize) {
    if (m_automaticResize && m_textField != null) {
      size.height = m_textField.textHeight + m_topMargin + m_bottomMargin+10;
      if (!m_wordWrap) {
        size.width = m_textField.textWidth + m_leftMargin + m_rightMargin+10;
      }
    } 
    super.setFrameSize(size);
    m_textField._width = size.width  - m_leftMargin - m_rightMargin;
    m_textField._height = size.height - m_topMargin - m_bottomMargin;
  }
  
  public function autoSize() {
    if (!m_automaticResize) return;
    var size:NSSize = new NSSize(0,0);
    if (m_textField != undefined) {
      if (m_wordWrap) {
        size.width = bounds().size.width;
      }
    } else {
      size.width = bounds().size.width;
    }
    setFrameSize(size);
  }
}