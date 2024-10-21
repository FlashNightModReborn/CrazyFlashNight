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
 
import org.actionstep.NSDictionary;

class org.actionstep.NSAttributedString extends org.actionstep.NSObject {
  
  private var m_string:String;
  private var m_htmlString:String;
  
  public static function attributedStringWithHTML(html:String):NSAttributedString {
    var result:NSAttributedString = new NSAttributedString();
    result.initWithHTMLDocumentAttributes(html, null);
    return result;
  }
  
  public function NSAttributedString() {
    m_string = null;
    m_htmlString = null;
  }
  
  public function initWithString(string:String):NSAttributedString {
    m_string = string;
    return this;
  }
  
  public function initWithHTMLDocumentAttributes(html:String, docAttributes:NSDictionary):NSDictionary {
    m_htmlString = html;
    return null;
  }
  
  public function string():String {
    if (m_string == null) {
      return getNonHTMLText();
    }
    return m_string;
  }
  
  public function htmlString():String {
    if (m_string==null) {
      return m_htmlString;
    } else {
      return m_string;
    }
  }
  
  public function isFormatted():Boolean {
    return m_htmlString != null ? true : false;
  }
  
  public function length():Number {
    return m_string.length;
  }
  
  public function description():String {
    var result:String = "NSAttributedString(value='"+htmlString()+"', formatted='"+isFormatted()+"')";
    return result;
  } 
  
  private function getNonHTMLText():String
  {
    var control:TextField = _root.m_attributedString;

    if (control == undefined)
    {
      _root.createTextField("m_attributedString", -16383, 0, 0, 1000, 100);
      control = _root.m_attributedString;
      control._visible = false;
      control.html = true;
    }
    
    control.htmlText = m_htmlString;
    return control.text;
  }

}