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
import org.actionstep.NSImage;

class org.actionstep.ASListItem extends NSObject {
  private var m_label:String;
  private var m_data:Object;
  private var m_selected:Boolean;
  private var m_image:NSImage;
  private var m_visible:Boolean;
  
  public static function listItemWithLabelData(label:String, data:Object):ASListItem {
    return (new ASListItem()).initWithLabelData(label, data);
  }
  
  public function ASListItem() {
    m_selected = false;
    m_visible = true;
  }
  
  public function initWithLabelData(label:String, data:Object):ASListItem {
    m_label = label;
    m_data = data;
    return this;
  }
  
  public function isSelected():Boolean {
    return m_selected;
  }
  
  public function setSelected(value:Boolean) {
    m_selected = value;
  }
  
  public function setImage(image:NSImage) {
    m_image = image;
  }
  
  public function image():NSImage {
    return m_image;
  }
  
  public function data():Object {
    return m_data;
  }
  
  public function setData(value:Object) {
    m_data = value;
  }
  
  public function label():String {
    return m_label;
  }
  
  public function toString():String {
    return m_data.toString();
  }
  
  public function setLabel(value:String) {
    m_label = value;
  }
  
  public function setVisible(value:Boolean) {
    m_visible = value;
  }
  
  public function isVisible():Boolean {
    return m_visible;
  }
}