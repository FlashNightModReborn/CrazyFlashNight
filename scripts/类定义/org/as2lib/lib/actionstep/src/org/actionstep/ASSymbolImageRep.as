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

import org.actionstep.NSImageRep;
import org.actionstep.NSSize;
import org.actionstep.NSView;

class org.actionstep.ASSymbolImageRep extends NSImageRep {
  
  var m_symbolName:String;

  public function ASSymbolImageRep(symbolName:String, size:NSSize) {
  	//as specified by Aqua guidelines
    m_size = size;
    m_symbolName = symbolName;
  }

  public function description():String {
    return "ASSymbolImageRep";
  }
  
  private function embedName():String {
    return "__"+m_symbolName+"__";
  }

  public function draw() {
    var clip:MovieClip = m_drawClip[embedName()];
    if (clip == undefined) {
      var level:Number = NSView.MaxClipDepth - 1000;
      if (m_drawClip.view != undefined) {
        level = m_drawClip.view.getNextDepth();
      }
      m_drawClip.attachMovie(m_symbolName, embedName(), level);
      clip = m_drawClip[embedName()];
      clip.view = m_drawClip.view;
    }
    clip._x = m_drawPoint.x;
    clip._y = m_drawPoint.y;
    clip._width = m_size.width;
    clip._height = m_size.height;
  }
}