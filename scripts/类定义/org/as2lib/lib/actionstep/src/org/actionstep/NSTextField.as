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
 
import org.actionstep.NSControl;
import org.actionstep.NSRect;
import org.actionstep.NSColor;
import org.actionstep.NSBeep;
import org.actionstep.NSEvent;
import org.actionstep.NSNotificationCenter;
import org.actionstep.NSNotification;
import org.actionstep.ASUtils;
import org.actionstep.ASFieldEditor;
import org.actionstep.NSTextFieldCell;

import org.actionstep.constants.NSTextMovement;
import org.actionstep.constants.NSBezelStyle;

class org.actionstep.NSTextField extends NSControl {

  // Notifications
  public static var NSControlTextDidBeginEditingNotification:Number = ASUtils.intern("NSControlTextDidBeginEditingNotification");
  public static var NSControlTextDidEndEditingNotification:Number = ASUtils.intern("NSControlTextDidEndEditingNotification");
  public static var NSControlTextDidChangeNotification:Number = ASUtils.intern("NSControlTextDidChangeNotification");

  private static var g_cellClass:Function = org.actionstep.NSTextFieldCell;

  public static function cellClass():Function {
    return g_cellClass;
  }

  public static function setCellClass(cellClass:Function) {
    if (cellClass == null) {
      g_cellClass = org.actionstep.NSTextFieldCell;
    } else {
      g_cellClass = cellClass;
    }
  }
  
  private var m_editor:ASFieldEditor;
  private var m_delegate:Object;
  private var m_notificationCenter:NSNotificationCenter;
  private var m_needsToSelectText:Boolean;
  
  public function NSTextField() {
    m_editor = null;
    m_needsToSelectText = false;
  }

  public function initWithFrame(frame:NSRect):NSTextField {
    super.initWithFrame(frame);
    m_notificationCenter = NSNotificationCenter.defaultCenter();
    m_cell.setState(1);
    m_cell.setBezeled(true);
    m_cell.setSelectable(true);
    m_cell.setEnabled(true);
    m_cell.setEditable(true);
    NSTextFieldCell(m_cell).setDrawsBackground(true);
    return this;
  }
  
  public function removeMovieClips():Void {
    validateEditing();
    abortEditing();
    super.removeMovieClips();
  }  

  // Controlling editability and selectability

  public function setEditable(value:Boolean) {
    m_cell.setEditable(value);
  }

  public function isEditable():Boolean {
    return m_cell.isEditable();
  }

  public function isSelectable():Boolean {
    return m_cell.isSelectable();
  }

  public function setSelectable(value:Boolean) {
    m_cell.setSelectable(value);
  }

  // Controlling rich text behavior

  //! Not dealing with the following
  /*
  – setAllowsEditingTextAttributes:
  – allowsEditingTextAttributes
  – setImportsGraphics:
  – importsGraphics
  */  
  
  // Setting the text color
  
  public function setTextColor(value:NSColor) {
    NSTextFieldCell(m_cell).setTextColor(value);
  }
  
  public function textColor():NSColor {
    return NSTextFieldCell(m_cell).textColor();
  }
  
  // Controlling the background

  public function setBackgroundColor(value:NSColor) {
    NSTextFieldCell(m_cell).setBackgroundColor(value);
  }

  public function backgroundColor():NSColor {
    return NSTextFieldCell(m_cell).backgroundColor();
  }
  
  public function setDrawsBackground(value:Boolean) {
    NSTextFieldCell(m_cell).setDrawsBackground(value);
  }
  
  public function drawsBackground():Boolean {
    return NSTextFieldCell(m_cell).drawsBackground();
  }
  
  // Setting a border

  public function setBezeled(value:Boolean) {
    m_cell.setBezeled(value);
  }
  
  public function isBezeled():Boolean {
    return m_cell.isBezeled();
  }
  
  public function setBezelStyle(value:NSBezelStyle) {
    NSTextFieldCell(m_cell).setBezelStyle(value);
  }
  
  public function bezelStyle():NSBezelStyle {
    return NSTextFieldCell(m_cell).bezelStyle();
  }
  
  public function setBordered(value:Boolean) {
    m_cell.setBordered(value);
  }
  
  public function isBordered():Boolean {
    return m_cell.isBordered();
  }
  
  // Selecting the text
  
  public function selectText(sender:Object) {
    if (isSelectable() && superview() != null) {
      if (m_editor == null) {
        var x:ASFieldEditor = NSTextFieldCell(m_cell).beginEditingWithDelegate(this);
        m_editor = x;
        m_cell.setShowsFirstResponder(true);
        setNeedsDisplay(true);
        if (m_editor == null) {
          m_needsToSelectText = true;
          return;
        }
      }
      m_editor.select();
    }
  }
  
  public function drawRect(rect:NSRect) {
    super.drawRect(rect);
    if (m_needsToSelectText) {
      m_needsToSelectText = false;
      selectText(this);
    }
  }
  
  // Working with the responder chain
  
  public function acceptsFirstMouse(event:NSEvent):Boolean {
    return isEditable();
  }
  
  public function acceptsFirstResponder():Boolean {
    return isSelectable();
  }
  
  public function becomeFirstResponder():Boolean {
    if (acceptsFirstResponder()) {
      selectText(this);
      if (m_editor != null || m_needsToSelectText) {
        return true;
      } else {
        return false;
      }
    } else {
      return false;
    }
  }
  
  public function resignKeyWindow() {
    if (m_editor != null) {
      m_editor.notifyEndEditing(NSTextMovement.NSIllegalTextMovement);
    }
    m_needsToSelectText = false;
  }
  
  public function resignFirstResponder():Boolean {
    if (m_editor != null) {
      m_editor.notifyEndEditing(NSTextMovement.NSIllegalTextMovement);
    }
    m_needsToSelectText = false;
    return super.resignFirstResponder();
  }
  
  public function mouseDown(event:NSEvent) {
    if (!isSelectable()) {
      super.mouseDown(event);
      return;
    }
    m_window.makeFirstResponder(this);
  }

  public function abortEditing():Boolean {
    if (m_editor) {
      m_editor = null;
      NSTextFieldCell(m_cell).endEditingWithDelegate(this);
      return true;
    } else {
      return false;
    }
  }

  public function validateEditing() {
    if (m_editor != null) {
      m_cell.setStringValue(m_editor.string());
    }
  } 
  
  public function textShouldBeginEditing(editor:Object):Boolean {
    if (!(isEditable() || isSelectable())) {
      return false;
    }
    if (m_delegate != null) {
      if(typeof(m_delegate["controlTextShouldBeginEditing"]) == "function") {
        return m_delegate["controlTextShouldBeginEditing"].call(m_delegate, this, editor);
      }
    }
    return true;
  }

  public function textDidBeginEditing(notification:NSNotification) {
    m_notificationCenter.postNotificationWithNameObjectUserInfo(
      NSControlTextDidBeginEditingNotification, 
      this, 
      { NSFieldEditor : notification.object }
    );
  }
  
  public function textDidChange(notification:NSNotification) {
    m_notificationCenter.postNotificationWithNameObjectUserInfo(
      NSControlTextDidChangeNotification, 
      this, 
      { NSFieldEditor : notification.object }
    );
    //! what else to do here ?
  }
  
  public function textShouldEndEditing(editor:Object):Boolean {
    //! need to validate that text is acceptable
    //if (m_cell.isEntryAcceptable(editor.text) {
    //}
    if (m_delegate != null) {
      if(typeof(m_delegate["controlTextShouldEndEditing"]) == "function") {
        if (!m_delegate["controlTextShouldEndEditing"].call(m_delegate, this, editor)) {
          NSBeep.beep();
          return false;
        }
      }
    }
    //! check for controlIsValidObject on delegate?
    return true;
  }
  
  public function keyDown(event:NSEvent) {
  }

  public function keyUp(event:NSEvent) {
  }

  public function textDidEndEditing(notification:NSNotification) {
    validateEditing();
    m_editor = null;
    m_cell.setShowsFirstResponder(false);
    setNeedsDisplay(true);
    NSTextFieldCell(m_cell).endEditingWithDelegate(this);
    m_notificationCenter.postNotificationWithNameObjectUserInfo(
      NSControlTextDidEndEditingNotification, 
      this, 
      { NSFieldEditor : notification.object }
    );
    switch(notification.userInfo.NSTextMovement) {
      case NSTextMovement.NSReturnTextMovement:
        if (!sendActionTo(action(), target())) {
          selectText(this);
        } else {
          m_window.makeFirstResponder(m_window);
        }
        break;
      case NSTextMovement.NSTabTextMovement:
        sendActionTo(action(), target());
        m_window.selectKeyViewFollowingView(this);
        if (m_window.firstResponder() == m_window) {
          selectText(this);
        }
        break;
      case NSTextMovement.NSBacktabTextMovement:
        sendActionTo(action(), target());
        m_window.selectKeyViewPrecedingView(this);
        if (m_window.firstResponder() == m_window) {
          selectText(this);
        }
        break;
      case NSTextMovement.NSIllegalTextMovement:
        m_window.makeFirstResponder(m_window);
        break;
    }
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
  }

  private function mapDelegateNotification(name:String) {
    if(typeof(m_delegate["controlText"+name]) == "function") {
      m_notificationCenter.addObserverSelectorNameObject(m_delegate, "controlText"+name, ASUtils.intern("NSControlText"+name+"Notification"), this);
    }
  }
}