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
 
import org.actionstep.ASList;
import org.actionstep.ASListItem;

import org.actionstep.NSView;
import org.actionstep.NSRect;
import org.actionstep.NSSize;
import org.actionstep.NSColor;
import org.actionstep.NSPoint;
import org.actionstep.NSEvent;
import org.actionstep.NSFont;
import org.actionstep.ASDraw;

class org.actionstep.ASListView extends NSView {
  
  private var m_list:ASList;
  private var m_multipleSelection:Boolean;
  private var m_textField:TextField;
  private var m_textFormat:TextFormat;
  private var m_font:NSFont;
  private var m_fontColor:NSColor;
  private var m_fontColorHex:String;
  private var m_text:String;
  private var m_indent:Number;
  private var m_showListItemImages:Boolean;
  private var m_sendsActionOnEnterOnly:Boolean;

  
  public function ASListView() {
    m_multipleSelection = false;
    m_indent = 3;
    m_sendsActionOnEnterOnly = false;
    m_showListItemImages = false;
  }
  
  public function initWithList(list:ASList) {
    super.initWithFrame(NSRect.ZeroRect);
    m_list = list;
    m_font = NSFont.systemFontOfSize(0);
    m_fontColor = NSColor.systemFontColor();
    setFontColorHex();
  }
  
  public function becomeFirstResponder():Boolean {
    m_list.setShowsFirstResponder(true);
    m_list.setNeedsDisplay(true);
    return true;
  }

  public function acceptsFirstResponder():Boolean {
    return true;
  }

  public function resignFirstResponder():Boolean {
    m_list.setShowsFirstResponder(false);
    m_list.setNeedsDisplay(true);
    return true;
  }

  public function becomeKeyWindow() {
    m_list.setShowsFirstResponder(true);
    m_list.setNeedsDisplay(true);
  }

  public function resignKeyWindow() {
    m_list.setShowsFirstResponder(false);
    m_list.setNeedsDisplay(true);
  }  
  
  public function nextKeyView():NSView {
    return m_list.nextKeyView();
  }

  public function nextValidKeyView():NSView {
    return m_list.nextValidKeyView();
  }

  public function previousKeyView():NSView {
    return m_list.previousKeyView();
  }

  public function previousValidKeyView():NSView {
    return m_list.previousValidKeyView();
  }
  
  public function setFont(font:NSFont) {
    m_font = font;
    m_textField.embedFonts = m_font.isEmbedded();
    m_textField.styleSheet = style();
  }

  public function font():NSFont {
    return m_font;
  }
  
  public function setFontColor(color:NSColor) {
    m_fontColor = color;
    setFontColorHex();
    m_textField.styleSheet = style();
  }
  
  private function setFontColorHex() {
    m_fontColorHex = m_fontColor.value.toString(16);
    m_fontColorHex = "000000".substring(0, (6-m_fontColorHex.length))+m_fontColorHex;
  }
  
  public function fontColor():NSColor {
    return m_fontColor;
  }
  
  public function setIndent(value:Number) {
    if (value < 0) {
      value = 0;
    }
    m_indent = value;
    m_textField._x = m_indent;
  }
  
  private function style():TextField.StyleSheet {
    var styleSheet:TextField.StyleSheet = new TextField.StyleSheet();
    var styleText:String = "
      s {
        color: #FFFFFF;
        font-family: "+m_font.fontName()+";
        font-size: "+m_font.pointSize()+"px;
        font-weight: bold;
        display: block;
      }
      n {
        color: #"+m_fontColorHex+";
        font-family: "+m_font.fontName()+";
        font-size: "+m_font.pointSize()+"px;
        display: block;
      }
    ";
    styleSheet.parseCSS(styleText);
    return styleSheet;
  }
  
  public function setSendsActionOnEnterOnly(value:Boolean) {
    m_sendsActionOnEnterOnly = value;
  }
  
  public function sendsActionOnEnterOnly():Boolean {
    return m_sendsActionOnEnterOnly;
  }

  public function setShowListItemImages(value:Boolean) {
    m_showListItemImages = value;
  }

  public function showListItemImages():Boolean {
    return m_showListItemImages;
  }

  public function indent():Number {
    return m_indent;
  }
  
  public function computeHeight() {
    updateText();
    var height:Number;
    if (m_textField == undefined) {
      height = m_list.frame().size.height;
    } else {
      height = m_textField.textHeight+4;
    }
    setFrameSize(new NSSize(m_list.frame().size.width, height));
  }
  
  private function updateText() {
    if (m_textField == null || m_textField._parent == undefined) {
      return;
    }
    m_text = "";
    var items:Array = m_list.visibleItems();
    for(var i:Number = 0;i < items.length;i++) {
      if (items[i].isSelected()) {
        m_text += "<s>"+items[i].label()+"</s>";
      } else {
        m_text += "<n>"+items[i].label()+"</n>";
      }
    }
    m_textField.htmlText = m_text;
    m_textField._height = m_textField.textHeight+1;
  }

  public function createMovieClips() {
    super.createMovieClips();
    if (m_mcBounds != null) {
      m_textField = createBoundsTextField();
      m_textField.border = false;
      m_textField.wordWrap = false;
      m_textField.multiline = true;
      m_textField.autoSize = true;
      m_textField.html = true;
      m_textField.styleSheet = style();
      m_textField._x = m_indent;
      m_textField._y = 0;
      m_textField.editable = false;
      m_textField.selectable = false;
      m_textField.embedFonts = m_font.isEmbedded();
      m_textField._width = m_list.frame().size.width;
      updateText();
      setFrameSize(new NSSize(m_list.frame().size.width, m_textField.textHeight+4));
    }
  }
  
  private function drawSelectedItems(rect:NSRect) {
    var items:Array = m_list.visibleItems();
    if (items.length > 0) {
      var height:Number = (m_textField.textHeight+1)/items.length;
      var width:Number = rect.size.width-10;
      for(var i:Number = 0;i < items.length;i++) {
        if (ASListItem(items[i]).isSelected()) {
          ASDraw.gradientRectWithAlphaRect(m_mcBounds, new NSRect(0,i*height+1,width, height+1), ASDraw.ANGLE_LEFT_TO_RIGHT, 
                                               [0x494D56, 0x494D56, 0x494D56, 0x494D56], [265,373,413,430], [40,40,0,0]);
          //ASDraw.solidRectWithRect(m_mcBounds, new NSRect(0,i*height,width, height+2), 0x858994);
        }
      }
    }
  }
  
  public function drawRect(rect:NSRect) {
    m_mcBounds.clear();
    drawSelectedItems(rect);
  }
  
  public function mouseDown(event:NSEvent) {
    var location:NSPoint = event.mouseLocation;
    location = convertPointFromView(location);
    m_window.makeFirstResponder(this);
    selectItemAtIndex(locationToIndex(location.y));
    setNeedsDisplay(true);
  }
  
  public function mouseUp(event:NSEvent) {
    m_list.sendActionTo(m_list.action(), m_list.target());
  }
  
  public function itemHeight():Number {
    return (m_textField.textHeight+1) / m_list.numberOfVisibleItems();
  }
  
  public function locationToIndex(y:Number):Number {
    return Math.floor( y / itemHeight() );
  }

  public function indexToLocation(index:Number):Number {
    return index * itemHeight();
  }
  
  public function keyDown(event:NSEvent) {
    var mods:Number = event.modifierFlags;
    var char:Number = event.keyCode;

    switch (char) {
      case NSUpArrowFunctionKey:
      case NSDownArrowFunctionKey:

      	if (mods & NSEvent.NSShiftKeyMask) {
      		//! implement
      	}
      	else if (mods & NSEvent.NSAlternateKeyMask) {
      		//! implement
      	}
      	else {
      		switch (char) {
      			case NSUpArrowFunctionKey:
      			  selectPreviousItem();
      				break;

      			case NSDownArrowFunctionKey:
      			  selectNextItem();
      				break;
      		}
      	}
        return;
      case NSEnterCharacter:
        m_list.sendActionTo(m_list.action(), m_list.target());
        return;
      case NSEscapeCharacter:
        m_list.deselectAllItems();
        m_list.sendActionTo(m_list.action(), m_list.target());
        return;
    }
    super.keyDown(event);
  }
  
  public function selectItemAtIndex(index:Number) {
    var items:Array = m_list.visibleItems();
    var length:Number = items.length;
    if (m_multipleSelection) {
    } else {
      for(var i:Number = 0;i < length;i++) {
        ASListItem(items[i]).setSelected(false);
      }
      items[index].setSelected(true);
      m_list.scrollItemAtIndexToVisible(index);
      updateText();
      setNeedsDisplay(true);
    }
  }
  
  private function selectPreviousItem() {
    var items:Array = m_list.visibleItems();
    var index:Number = NSNotFound;
    var length:Number = items.length;
    for(var i:Number = 0;i < length;i++) {
      if (ASListItem(items[i]).isSelected()) {
        ASListItem(items[i]).setSelected(false);
        index = i;
      }
    }
    // Extracted from selectItemAtIndex
    if (m_multipleSelection) {
    } else {
      if (index > 0) {
        index--;
        items[index].setSelected(true);
        m_list.scrollItemAtIndexToVisible(index);
        updateText();
        setNeedsDisplay(true);
        if (!m_sendsActionOnEnterOnly) {
          m_list.sendActionTo(m_list.action(), m_list.target());
        }
      } else {
        items[0].setSelected(true);
        m_list.scrollItemAtIndexToVisible(0);
        updateText();
        setNeedsDisplay(true);
        if (!m_sendsActionOnEnterOnly) {
          m_list.sendActionTo(m_list.action(), m_list.target());
        }
      }
    }
  }
  
  private function selectNextItem() {
    var items:Array = m_list.visibleItems();
    var index:Number = NSNotFound;
    var length:Number = items.length;
    for(var i:Number = 0;i < length;i++) {
      if (ASListItem(items[i]).isSelected()) {
        if (i == (length-1)) {
          return;
        }
        ASListItem(items[i]).setSelected(false);
        index = i;
        break;
      }
    }
    // Extracted from selectItemAtIndex
    if (m_multipleSelection) {
    } else {
      if (index != NSNotFound) {
        index++;
        items[index].setSelected(true);
        m_list.scrollItemAtIndexToVisible(index);
        updateText();
        setNeedsDisplay(true);
        if (!m_sendsActionOnEnterOnly) {
          m_list.sendActionTo(m_list.action(), m_list.target());
        }
      } else {
        items[0].setSelected(true);
        m_list.scrollItemAtIndexToVisible(0);
        updateText();
        setNeedsDisplay(true);
        if (!m_sendsActionOnEnterOnly) {
          m_list.sendActionTo(m_list.action(), m_list.target());
        }
      }
    }
  }

  /** 
   * Returns whether multiple selection is supported by the list. TRUE is
   * multiple selection, FALSE is single selection.
   *
   * The default value is FALSE.
   */
  public function multipleSelection():Boolean {
    return m_multipleSelection;
  }

  /**
   * Sets whether multiple selection is supported by the list. TRUE allows
   * multiple selection, FALSE is single selection only.
   *
   * The default value is FALSE.
   */
  public function setMultipleSelection(flag:Boolean):Void {
    if (m_multipleSelection == flag) {
      return;
    }
    m_multipleSelection = flag;
  }

}