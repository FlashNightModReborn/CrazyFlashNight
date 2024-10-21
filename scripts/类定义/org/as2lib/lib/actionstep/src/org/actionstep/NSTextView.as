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
 
import org.actionstep.ASUtils;
import org.actionstep.ASTheme;

import org.actionstep.NSText;
import org.actionstep.NSColor;
import org.actionstep.NSRange;
import org.actionstep.NSFont;
import org.actionstep.NSSize;
import org.actionstep.NSScroller;
import org.actionstep.NSRect;
import org.actionstep.NSNotificationCenter;

import org.actionstep.constants.NSTextAlignment;
import org.actionstep.constants.NSWritingDirection;

class org.actionstep.NSTextView extends NSText {

  // Notifications
  public static var NSTextDidBeginEditingNotification:Number = ASUtils.intern("NSTextDidBeginEditingNotification");
  public static var NSTextDidEndEditingNotification:Number = ASUtils.intern("NSTextDidEndEditingNotification");
  public static var NSTextDidChangeNotification:Number = ASUtils.intern("NSTextDidChangeNotification");
  public static var NSTextViewDidChangeSelectionNotification:Number = ASUtils.intern("NSTextViewDidChangeSelectionNotification");
  public static var NSTextViewWillChangeNotifyingTextViewNotification:Number = ASUtils.intern("NSTextViewWillChangeNotifyingTextViewNotification");

  private var m_textField:TextField;
  private var m_textFormat:TextFormat;
  private var m_font:NSFont;
  private var m_textColor:NSColor;
  private var m_alignment:NSTextAlignment;
  
  private var m_internalString:String;
  
  private var m_backgroundColor:NSColor;
  private var m_drawsBackground:Boolean;
  private var m_editable:Boolean;
  private var m_selectable:Boolean;
  private var m_isFieldEditor:Boolean;
  private var m_richText:Boolean;
  private var m_importsGraphics:Boolean;
  private var m_usesFontPanel:Boolean;
  private var m_selectedRange:NSRange;
  private var m_writingDirection:NSWritingDirection;
  private var m_maxSize:NSSize;
  private var m_minSize:NSSize;
  private var m_verticallyResizable:Boolean;
  private var m_horizontallyResizable:Boolean;
  private var m_delegate:Object;
  private var m_notificationCenter:NSNotificationCenter;
  
  private var m_horizontalScroller:NSScroller;
  private var m_verticalScroller:NSScroller;
  
  private var m_showsFirstResponder:Boolean;
  
  public function NSTextView() {
    m_textField = null;
    m_textFormat = null;
    m_textColor = NSColor.systemFontColor();
    m_font = NSFont.systemFontOfSize();
    m_alignment = NSTextAlignment.NSLeftTextAlignment;
    m_internalString = "";
    m_drawsBackground = true;
    m_editable = true;
    m_selectable = true;
    m_isFieldEditor = false;
    m_richText = false;
    m_importsGraphics = false;
    m_usesFontPanel = false;
    m_showsFirstResponder = false;
    m_writingDirection = NSWritingDirection.NSWritingDirectionNatural;
    m_maxSize = null;
    m_minSize = null;
    m_verticallyResizable = true;
    m_horizontallyResizable = false;
  }

  public function initWithFrame(frame:NSRect):NSTextView {
    super.initWithFrame(frame);
    m_notificationCenter = NSNotificationCenter.defaultCenter();
    m_minSize = NSSize.ZeroSize;
    //setPostsFrameChangedNotifications(true);
    return this;
  }
  
  // Getting the characters
  
  public function string():String {
    return m_internalString;
  }

  // Setting graphics attributes

  public function setBackgroundColor(value:NSColor) {
    if (m_backgroundColor != value) {
      m_backgroundColor = value;
      setNeedsDisplay(true);
    }
  }

  public function backgroundColor():NSColor {
    return m_backgroundColor;
  }

  public function setDrawsBackground(value:Boolean) {
    if (m_drawsBackground != value) {
      m_drawsBackground = value;
      setNeedsDisplay(true);
    }
  }

  public function drawsBackground():Boolean {
    return m_drawsBackground;
  }

  // Setting behavioral attributes

  public function setEditable(value:Boolean) {
    m_editable = value;
    if (m_textField != null && m_textField._parent != undefined) {
      m_textField.type = m_editable ? "input" : "dynamic";
    }
  }

  public function isEditable():Boolean {
    return m_editable;
  }

  public function setSelectable(value:Boolean) {
    m_selectable = value;
    if (!m_selectable) {
      setEditable(false);
    }
    if (m_textField != null && m_textField._parent != undefined) {
      m_textField.selectable = m_selectable;
    }
  }

  public function isSelectable():Boolean {
    return m_selectable || m_editable;
  }

  public function setFieldEditor(value:Boolean) {
    m_isFieldEditor = value;
  }

  public function isFieldEditor():Boolean {
    return m_isFieldEditor;
  }

  public function setRichText(value:Boolean) {
    m_richText = value;
  }

  public function isRichText():Boolean {
    return m_richText;
  }

  public function setImportsGraphics(value:Boolean) {
    m_importsGraphics = value;
  }

  public function importsGraphics():Boolean {
    return m_importsGraphics;
  }

  // Using the Font panel and menu

  public function setUsesFontPanel(value:Boolean) {
    m_usesFontPanel = value;
  }

  public function usesFontPanel():Boolean {
    return m_usesFontPanel;
  }

  // Using the ruler

  public function toggleRuler(sender:Object) {
    //! Need to implement
  }

  public function isRulerVisible():Boolean {
    //! Need to implement
    return false;
  }

  // Changing the selection

  public function setSelectedRange(range:NSRange) {
    if (m_textField != null && m_textField._parent != undefined) {
      Selection.setFocus(eval(m_textField._target));
      Selection.setSelection(range.location, range.location + range.length);
    }
    m_selectedRange = range;
  }

  public function selectedRange():NSRange {
    if (m_textField != null && m_textField._parent != undefined && Selection.getFocus()==m_textField._target) {
      m_selectedRange = new NSRange(Selection.getBeginIndex(), Selection.getEndIndex() - Selection.getBeginIndex());
    }
    return m_selectedRange;
  }

  // Replacing text

  public function replaceCharactersInRangeWithString(range:NSRange, string:String) {
    if (m_textField != null && m_textField._parent != undefined) {
      m_textField.replaceText(range.location, range.location + range.length, string);
    } else {
    }
  }

  public function setString(string:String) {
    m_internalString = string;
    if (m_textField != null && m_textField._parent != undefined) {
      m_textField.text = string;
      m_textField.setTextFormat(m_textFormat);
      m_textField.setNewTextFormat(m_textFormat);
    }
  }

  // Action methods for editing

  public function selectAll(sender:Object) {
    setSelectedRange(new NSRange(0, m_internalString.length));
  }

  public function copy(sender:Object) {
    //! How to copy?
  }

  public function cut(sender:Object) {
    copy(sender);
    clear(sender);
  }

  public function paste(sender:Object) {
    //! How to paste?
  }

  public function copyFont(sender:Object) {
    //! How to copyFont?
  }

  public function pasteFont(sender:Object) {
    //! How to pastFont?
  }

  public function copyRuler(sender:Object) {
    //! What to do here?
  }

  public function pasteRuler(sender:Object) {
    //! What to do here?
  }

  /**
  * Remove all text from the text editor but do not place it on the clipboard
  * NOTE: Changed from the Cocoa delete method because delete is a keyword in ActionScript
  *
  */
  public function clear(sender:Object) {
    if (m_textField != null && m_textField._parent != undefined && Selection.getFocus()==m_textField._target) {
      m_textField.text = "";
    }  
    m_internalString = "";
  }

  // Changing the font
  public function changeFont(sender:Object) {
    if (!m_usesFontPanel) {
      return;
    }
    //! What to do here?
  }

  public function setFont(font:NSFont) {
    m_textFormat.font = font.fontName();
    m_textFormat.size = font.pointSize();
    if (m_textField != null && m_textField._parent != undefined) {
      m_textField.setTextFormat(m_textFormat);
      m_textField.setNewTextFormat(m_textFormat);
    }
  }

  public function font():NSFont {
    return NSFont.fontWithNameSize(m_textFormat.font, m_textFormat.size);
  }

  public function setFontRange(font:NSFont, range:NSRange) {
    if (m_textField != null && m_textField._parent != undefined) {
      var format:TextFormat = m_textField.getTextFormat(range.location, range.location + range.length);
      format.font = font.fontName();
      format.size = font.pointSize();
      m_textField.setTextFormat(m_textFormat, range.location, range.location + range.length);
    }  
  }

  // Setting text alignment

  public function setAlignment(value:NSTextAlignment) {
    m_alignment = value;
    __setAlignment(value, 0, m_internalString.length);
  }

  public function alignCenter(sender:Object) {
    __setAlignment(NSTextAlignment.NSCenterTextAlignment, 0, m_internalString.length);
  }

  public function alignLeft(sender:Object) {
    __setAlignment(NSTextAlignment.NSLeftTextAlignment, 0, m_internalString.length);
  }

  public function alignRight(sender:Object) {
    __setAlignment(NSTextAlignment.NSRightTextAlignment, 0, m_internalString.length);
  }

  public function alignment():NSTextAlignment {
    return m_alignment;
  }
  
  private function __setAlignment(value:NSTextAlignment, begin:Number, end:Number) {
    var format:TextFormat = new TextFormat();
    format.align = value.string;
    m_textField.setTextFormat(format, begin, end);
  }

  // Setting text color

  public function setTextColor(color:NSColor) {
    m_textFormat.color = color.value;
    if (m_textField != null && m_textField._parent != undefined) {
      m_textField.setTextFormat(m_textFormat);
      m_textField.setNewTextFormat(m_textFormat);
    }  
  }

  public function setTextColorRange(color:NSColor, range:NSRange) {
    if (m_textField != null && m_textField._parent != undefined) {
      var format:TextFormat = m_textField.getTextFormat(range.location, range.location + range.length);
      format.color = color.value;
      m_textField.setTextFormat(m_textFormat, range.location, range.location + range.length);
    }     
  }

  public function textColor():NSColor {
    return new NSColor(m_textFormat.color);
  }

  // Writing direction

  public function writingDirection():NSWritingDirection {
    return m_writingDirection;
  }

  public function setWritingDirection(direction:NSWritingDirection) {
    m_writingDirection = direction;
  }

  // Setting superscripting and subscripting

  public function superscript(sender:Object) {
    //! What to do here?
  }

  public function subscript(sender:Object) {
    //! What to do here?
  }

  public function unscript(sender:Object) {
    //! What to do here?
  }

  // Underlining text

  public function underline(sender:Object) {
    m_textFormat.underline = true;
    if (m_textField != null && m_textField._parent != undefined) {
      m_textField.setTextFormat(m_textFormat);
      m_textField.setNewTextFormat(m_textFormat);
    }  
  }

  // Constraining size

  public function setMaxSize(size:NSSize) {
    m_maxSize = size;
    setNeedsDisplay(true);
  }

  public function maxSize():NSSize {
    return m_maxSize;
  }

  public function setMinSize(size:NSSize) {
    m_minSize = size;
    setNeedsDisplay(true);
  }

  public function minSize():NSSize {
    return m_minSize;
  }

  public function setVerticallyResizable(value:Boolean) {
    m_verticallyResizable = value;
  }

  public function isVerticallyResizable():Boolean {
    return m_verticallyResizable;
  }  

  public function setHorizontallyResizable(value:Boolean) {
    m_horizontallyResizable = value;
    m_textField.wordWrap = !m_horizontallyResizable;
  }

  public function isHorizontallyResizable():Boolean {
    return m_horizontallyResizable;
  }  

  public function sizeToFit() {
    //! Leave us at our current size
  }

  // Checking spelling

  public function checkSpelling(sender:Object) {
    //! What to do here?
  }

  public function showGuessPanel(sender:Object) {
    //! What to do here?
  }

  // Scrolling

  public function scrollRangeToVisible(range:NSRange) {
    //! What to do here?
  }

  // Setting the delegate

  public function delegate():Object {
    return m_delegate;
  }

  public function setDelegate(value:Object) {
    if(m_delegate != null) {
      m_notificationCenter.removeObserverNameObject(m_delegate, null, this);
    }
    m_delegate = value;
    if (value == null) {
      return;
    }
    mapDelegateNotification("DidBeginEditing");
    mapDelegateNotification("DidEndEditing");
    mapDelegateNotification("DidChange");

    mapDelegateNotification("ViewDidChangeSelection");
    mapDelegateNotification("ViewWillChangeNotifyingTextView");
  }
  
  private function mapDelegateNotification(name:String) {
    if(typeof(m_delegate["text"+name]) == "function") {
      m_notificationCenter.addObserverSelectorNameObject(m_delegate, "text"+name, ASUtils.intern("NSText"+name+"Notification"), this);
    }
  }

  private function textField():TextField {
    if (m_textField == null || m_textField._parent == undefined) {
      //
      // Build the text format and textfield
      //
      m_textField = createBoundsTextField();
      m_textFormat = m_font.textFormatWithAlignment(m_alignment);
      m_textFormat.color = m_textColor.value;
      m_textField.view = this;
      m_textField.type = m_editable ? "input" : "dynamic";
      m_textField.selectable = m_selectable;
      m_textField.text = m_internalString;
      m_textField.embedFonts = m_font.isEmbedded();
      m_textField.multiline = true;
      m_textField.wordWrap = !m_horizontallyResizable;

      //
      // Assign the textformat.
      //
      m_textField.setTextFormat(m_textFormat);
      m_textField.setNewTextFormat(m_textFormat);
      var b:NSRect = bounds();
      m_textField._x = 0;
      m_textField._y = 0;
      m_textField._width = b.size.width;
      m_textField._height = b.size.height;
      m_textField.addListener(this);
    }

    return m_textField;
  }
  
  private function onChanged(tf:TextField) {
    m_internalString = tf.text;
  }

  private function onScroller(tf:TextField) {
    trace(tf.scroll);
  }

  public function drawRect(rect:NSRect) {
    var mc:MovieClip = mcBounds();
    mc.clear();
    if (m_drawsBackground) {
      ASTheme.current().drawTextFieldWithRectInView(rect, this);
    }
    if (m_showsFirstResponder) {
      ASTheme.current().drawFirstResponderWithRectInView(rect, this);
    }
    var tf:TextField = textField();
    if (tf.text != m_internalString) {
      tf.text = m_internalString;
      tf.setTextFormat(m_textFormat);
    }

  }



}