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
 
import org.actionstep.NSActionCell;
import org.actionstep.NSControl;
import org.actionstep.NSColor;
import org.actionstep.NSFont;
import org.actionstep.NSRect;
import org.actionstep.NSView;
import org.actionstep.NSEvent;

import org.actionstep.ASTheme;
import org.actionstep.ASFieldEditor;

import org.actionstep.ASFieldEditingProtocol;

import org.actionstep.constants.NSBezelStyle;

class org.actionstep.NSTextFieldCell extends NSActionCell 
  implements ASFieldEditingProtocol {

  private var m_bezelStyle:NSBezelStyle;
  private var m_textColor:NSColor;
  private var m_backgroundColor:NSColor;
  private var m_drawsBackground:Boolean;
  private var m_beingEditedBy:Object;
  
  // Flash Text Field
  private var m_textField:TextField;
  private var m_textFormat:TextFormat;
  private var m_actionMask:Number;
  
  public function NSTextFieldCell() {
    m_drawsBackground = false;
    m_beingEditedBy = null;
    m_textField = null;
    m_textFormat = null;
    m_textColor = NSColor.systemFontColor();
    m_actionMask = NSEvent.NSKeyUpMask | NSEvent.NSKeyDownMask;  
  }
  
  private function init():NSTextFieldCell {
    initTextCell("");
    return this;
  }

  public function initTextCell(string:String):NSTextFieldCell {
    super.initTextCell(string);
    m_drawsBackground = false;
    return this;
  }  
    
  // Controlling rich text behavior

  //! Not dealing with the following
  /*
  – setAllowsEditingTextAttributes:
  – allowsEditingTextAttributes
  – setImportsGraphics:
  – importsGraphics
  */

  /**
   * Returns the cell's textfield. Will build if necessary.
   */
  private function textField():TextField {
    if (m_textField == null || m_textField._parent == undefined) {
      //
      // Build the text format and textfield
      //
      m_textField = m_controlView.createBoundsTextField();
      m_textFormat = m_font.textFormatWithAlignment(m_alignment);
      m_textFormat.color = m_textColor.value;
      m_textField.self = this;
      m_textField.text = stringValue();
      m_textField.embedFonts = m_font.isEmbedded();
      m_textField.selectable = false;
      m_textField.type = "dynamic";
      //
      // Assign the textformat.
      //
      m_textField.setTextFormat(m_textFormat);
    }
    
    return m_textField;
  }
  
  public function beginEditingWithDelegate(delegate:Object):ASFieldEditor {
    if (!isSelectable()) {
      return null;
    }
    if (m_textField != null && m_textField._parent != undefined) {
      m_textField.text = stringValue();
      var editor:ASFieldEditor = ASFieldEditor.startEditing(this, delegate, m_textField);
      return editor;
    }
    return null;
  }
  
  public function endEditingWithDelegate(delegate:Object):Void {
    ASFieldEditor.endEditing();
    m_textField.setTextFormat(m_textFormat);
  }

  public function setEditable(value:Boolean) {
    super.setEditable(value);
  }

  public function setSelectable(value:Boolean) {
    super.setSelectable(value);
  }
  
  public function setTextColor(value:NSColor) {
    m_textColor = value;
    m_textFormat.color = m_textColor.value;
    if (m_controlView && (m_controlView instanceof NSControl)) {
      NSControl(m_controlView).updateCell(this);
    }  
  }
  
  public function textColor():NSColor {
    return m_textColor;
  }
  
  public function setFont(font:NSFont) {
    super.setFont(font);
    m_textFormat = m_font.textFormat();
    m_textFormat.color = m_textColor.value;
    if (m_textField != null) {
      m_textField.embedFonts = m_font.isEmbedded();
    }
  }
  
  public function setBackgroundColor(value:NSColor) {
    m_backgroundColor = value;
    if (m_controlView && (m_controlView instanceof NSControl)) {
      NSControl(m_controlView).updateCell(this);
    }
  }

  public function backgroundColor():NSColor {
    return m_backgroundColor;
  }  

  public function setDrawsBackground(value:Boolean) {
    m_drawsBackground = value;
    if (m_controlView && (m_controlView instanceof NSControl)) {
      NSControl(m_controlView).updateCell(this);
    }
  }

  public function drawsBackground():Boolean {
    return m_drawsBackground;
  }
  
  public function setBezelStyle(value:NSBezelStyle) {
    m_bezelStyle = value;
  }

  public function bezelStyle():NSBezelStyle {
    return m_bezelStyle;
  }
  
  public function release() {
    if (m_textField != null) {
      m_textField.removeTextField();
      m_textField = null;
    }
  }
  
  private function validateTextField(cellFrame:NSRect) {
    var mc:MovieClip = m_controlView.mcBounds();

    var width:Number = cellFrame.size.width - 1;
    var height:Number = cellFrame.size.height - 1;
    var x:Number = cellFrame.origin.x;
    var y:Number = cellFrame.origin.y;
    var text:String = stringValue();
    var fontHeight:Number = m_font.getTextExtent("Why").height;
    //
    // Get the textfield. Will be build if necessary.
    //
    var tf:TextField = textField();

    if (tf.text != stringValue()) {
      tf.text = text;
      tf.setTextFormat(m_textFormat);
    }

    tf._x = x+(m_drawsBackground ? 3 : 0);
    tf._y = y + (m_drawsBackground ? (height - fontHeight)/2 : 0);
    tf._width = width-1;
    tf._height = fontHeight;
  }

  public function drawWithFrameInView(cellFrame:NSRect, inView:NSView) {
    if (m_controlView != inView) {
      m_controlView = inView;
    }
    if (m_drawsBackground) {
      ASTheme.current().drawTextFieldWithRectInView(cellFrame, inView);
	  }
    if (m_showsFirstResponder) {
      ASTheme.current().drawFirstResponderWithRectInView(cellFrame, inView);
    }
    if (ASFieldEditor.instance().cell() != this) {
      validateTextField(cellFrame);
    }
  }
}
