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
 
import org.actionstep.NSObject;
import org.actionstep.NSView;
import org.actionstep.NSRect;
import org.actionstep.NSSize;
import org.actionstep.NSPoint;
import org.actionstep.NSTabView;
import org.actionstep.constants.NSTabState;

class org.actionstep.NSTabViewItem extends NSObject {
  
  private var m_tabView:NSTabView;
  private var m_label:String;
  private var m_identifier:Object;
  private var m_tabState:NSTabState;
  private var m_view:NSView;
  private var m_initialFirstResponder:NSView;
  private var m_textField:TextField;
  private var m_textFormat:TextFormat;
  private var m_rect:NSRect;
  
  public function initWithIdentifier(identifier:Object):NSTabViewItem {
    super.init();
    m_identifier = identifier;
    m_tabState = NSTabState.NSBackgroundTab;
    return this;
  }
  
  public function description():String {
    return "NSTabViewItem(label="+m_label+")";
  }
  
  // Working with labels

  public function drawLabelInRect(truncate:Boolean, rect:NSRect) {
    m_rect = rect;
    var size:NSSize = sizeOfLabel(truncate);
    var tlabel:String = truncatedLabel(truncate);
    if (m_textField == null || m_textField._parent == undefined) {
      m_textField = m_tabView.createBoundsTextField();
      m_textFormat = m_tabView.font().textFormat();
      m_textField.text = tlabel;
      m_textField.autoSize = true;
      m_textField.selectable = false;
      m_textField.type = "dynamic";
      m_textField.setTextFormat(m_textFormat);
    }

    if (m_textField.text != tlabel) {
      m_textField.text = tlabel;
      m_textField.setTextFormat(m_textFormat);
    }
    
    var x:Number = rect.origin.x;
    var y:Number = rect.origin.y;
    var width:Number = rect.size.width;
    var height:Number = rect.size.height;
    m_textField._x = (rect.size.width - size.width)/2 + rect.origin.x;
    m_textField._y = (rect.size.height - size.height)/2 + rect.origin.y;
  }
  
  public function label():String {
    return m_label;
  }
  
  public function setLabel(label:String) {
    m_label = label;
  }
  
  public function sizeOfLabel(truncate:Boolean):NSSize {
    return m_tabView.font().getTextExtent(truncatedLabel(truncate));
  }
  
  public function setTabView(view:NSTabView) {
    m_tabView = view;
  }
  
  public function tabView():NSTabView {
    return m_tabView;
  }
  
  public function setIdentifier(id:Object) {
    m_identifier = id;
  }
  
  public function identifier():Object {
    return m_identifier;
  }
  
  public function setTabState(state:NSTabState) {
    m_tabState = state;
  }
  
  public function tabState():NSTabState {
    return m_tabState;
  }
  
  // Assigning a view
  
  public function view():NSView {
    return m_view;
  }
  
  public function setView(view:NSView) {
    m_view = view;
  }
  
  public function initialFirstResponder():NSView {
    return m_initialFirstResponder;
  }
  
  public function setInitialFirstResponder(view:NSView) {
    m_initialFirstResponder = view;
  }
  
  // NON-OPENSTEP METHODS
  
  public function pointInTabItem(point:NSPoint):Boolean {
    return m_rect == null ? false : m_rect.pointInRect(point);
  }
  
  private function truncatedLabel(truncate:Boolean):String {
  	//! implement
    if (truncate) {
      return m_label;
    } else {
      return m_label;
    }
  }
  
}