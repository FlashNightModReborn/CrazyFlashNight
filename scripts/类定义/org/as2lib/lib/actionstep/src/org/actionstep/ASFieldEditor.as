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
 

import org.actionstep.NSCell;
import org.actionstep.NSNotificationCenter;
import org.actionstep.ASUtils;

import org.actionstep.constants.NSTextMovement;

class org.actionstep.ASFieldEditor {

  // Notifications
  public static var NSTextDidBeginEditingNotification:Number = ASUtils.intern("NSTextDidBeginEditingNotification");
  public static var NSTextDidEndEditingNotification:Number = ASUtils.intern("NSTextDidEndEditingNotification");
  public static var NSTextDidChangeNotification:Number = ASUtils.intern("NSTextDidChangeNotification");
    
  private static var g_instance:ASFieldEditor;
  
  private var m_cell:NSCell;
  private var m_delegate:Object;
  private var m_textField:TextField;
  private var m_textFormat:TextFormat;
  private var m_string:String;
  private var m_notificationCenter:NSNotificationCenter; 
  private var m_interval:Number;
  private var m_editing:Boolean;
  private var m_hasFocus:Boolean;
  private var m_ignoreNextSelect:Boolean;
  
  public static function instance():ASFieldEditor {
    if (g_instance == null) {
      g_instance = new ASFieldEditor();
    }
    return g_instance;
  }

  public static function startEditing(cell:NSCell, delegate:Object, textField:TextField):ASFieldEditor {
    var instance:ASFieldEditor = ASFieldEditor.instance();
    if (instance.isEditing()) {
      instance.notifyEndEditing(NSTextMovement.NSIllegalTextMovement);
      if (instance.isEditing()) {
        return null;
      }
      instance.ignoreNextSelect();
    }
    if (typeof(delegate["textShouldBeginEditing"]) != "function" || delegate.textShouldBeginEditing(instance)) {
      instance.setCell(cell);
      instance.setDelegate(delegate);
      instance.setTextField(textField);
      return instance;
    }
    return null;
  }

  public static function endEditing() {
    var instance:ASFieldEditor = ASFieldEditor.instance();
    instance.setDelegate(null);
    instance.setCell(null);
    instance.setTextField(null);
  }
  
  public function toString():String {
    return "ASFieldEditor(textfield="+m_textField+")";
  }

  public function ASFieldEditor() {
    m_notificationCenter = NSNotificationCenter.defaultCenter();
    m_hasFocus = false;
    m_editing = false;
    m_ignoreNextSelect = false;
  }

  public function setCell(cell:NSCell) {
    m_cell = cell;
  }
  
  public function cell():NSCell {
    return m_cell;
  }

  
  public function setDelegate(delegate:Object) {
    if(m_delegate != null) {
      m_notificationCenter.removeObserverNameObject(m_delegate, null, this);
    }
    m_delegate = delegate;
    if (m_delegate == null) {
      return;
    }
    mapDelegateNotification("DidBeginEditing");
    mapDelegateNotification("DidEndEditing");
    mapDelegateNotification("DidChange");
  }

  private function mapDelegateNotification(name:String) {
    if(typeof(m_delegate["text"+name]) == "function") {
      m_notificationCenter.addObserverSelectorNameObject(m_delegate, "text"+name, ASUtils.intern("NSText"+name+"Notification"), this);
    }
  }
  
  public function notifyBeginEditing() {
    m_notificationCenter.postNotificationWithNameObject(NSTextDidBeginEditingNotification, this);
  }
  
  public function notifyEndEditing(textMovement:NSTextMovement) {
    if (typeof(m_delegate["textShouldEndEditing"]) != "function" || m_delegate.textShouldEndEditing(this)) {
      m_notificationCenter.postNotificationWithNameObjectUserInfo(
        NSTextDidEndEditingNotification, 
        this,
        {NSTextMovement : textMovement}
      );
    }
  }
  
  public function setEditing(value:Boolean) {
    m_editing = value;
  }
  
  public function isEditing():Boolean {
    return m_editing;
  }
  
  public function setHasFocus(value:Boolean) {
    m_hasFocus = value;
  }
  
  public function hasFocus():Boolean {
    return m_hasFocus;
  }
  
  public function ignoreNextSelect() {
    m_ignoreNextSelect = true;
  }
  
  public function regainFocus() {
    if (!m_hasFocus) {
      var obj:Object = {focus:true, select:false};
      obj.interval = setInterval(this, "focusCallback", 20, obj);
    }
  }
  
  public function regainFocusSelect() {
    if (!m_hasFocus) {
      var obj:Object = {focus:true, select:true};
      obj.interval = setInterval(this, "focusCallback", 20, obj);
    }
  }
  
  public function select() {
    var obj:Object = {focus:false, select:true};
    obj.interval = setInterval(this, "focusCallback", 20, obj);
  }

  public function focusCallback(flags:Object) {
    if (flags.focus) {
      Selection.setFocus(String(m_textField));
    }
    if (!m_ignoreNextSelect) {
      if (flags.select) {
        Selection.setSelection(0, m_textField.text.length);
      } else {
        Selection.setSelection(m_textField.text.length, m_textField.text.length);
      }
    } else {
      m_ignoreNextSelect = false;
    }
    clearInterval(flags.interval);
  }
  
  public function notifyChange() {
    m_string = m_textField.text;
    m_notificationCenter.postNotificationWithNameObject(NSTextDidChangeNotification, this);
  }
  
  public function delegate():Object {
    return m_delegate;
  }
  
  public function string():String {
    return m_string;
  }
  
  public function onKeyDown() {
    if (Key.getCode() == Key.ENTER) {
      notifyEndEditing(NSTextMovement.NSReturnTextMovement);
    } else if(Key.getCode() == Key.TAB) {
      if (Key.isDown(Key.SHIFT)) {
        notifyEndEditing(NSTextMovement.NSBacktabTextMovement);
      } else {
        notifyEndEditing(NSTextMovement.NSTabTextMovement);
      }
    }
  }
    
  public function setTextField(textField:TextField) {
    var self:ASFieldEditor = this;
    if (m_textField != null) { // reset old TextField
      m_textField.selectable = false;
      m_textField.hscroll = 0;
      m_textField.background = false;
      m_textField.type = "dynamic";
      m_textField.onKillFocus = null;
      m_textField.onSetFocus = null;
      m_textField.onScroller = null;
      m_textField.onChanged = null;
      m_string = m_textField.text;
      Selection.setSelection(m_textField.text.length, m_textField.text.length);
      m_textField.setTextFormat(m_textFormat);
      Key.removeListener(this);
    }
    setEditing(false);
    m_textField = textField;
    if (m_textField != null) { // enable new TextField
      m_textFormat = m_textField.getTextFormat();
      m_string = m_cell.stringValue();
      m_textField.selectable = true;
      m_textField.type = m_cell.isEditable() ? "input" : "dynamic";
      m_textField.tabEnabled = false;
      m_textField.text = m_cell.stringValue();
      
      var tform:TextFormat;
      
      if (m_cell.alignment() != undefined)
        tform = m_cell.font().textFormatWithAlignment(m_cell.alignment());
      else
        tform = m_cell.font().textFormat();
      
      m_textField.setTextFormat(tform);
      m_textField.setNewTextFormat(tform);
      self.setEditing(true);
      m_textField.onSetFocus = function(oldFocus) {
        self.setHasFocus(true);
      };
      m_textField.onKillFocus = function(oldFocus) {
        self.setHasFocus(false);
      };
      m_textField.onScroller = function(tf) {
      };
      m_textField.onChanged = function(tf) {
        self.notifyChange();
      };
      Key.addListener(this);
      Selection.setFocus(String(m_textField));
      notifyBeginEditing();
    }
  }

}