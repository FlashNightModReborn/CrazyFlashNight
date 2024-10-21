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
//import org.actionstep.ASDraw;

class org.actionstep.images.ASHighlightedSwitchRep extends NSImageRep {
  
  public function ASHighlightedSwitchRep() {
    m_size = new NSSize(16,16);
  }
  
  public function description():String {
    return "ASHighlightedSwitchRep";
  }
  
  public function draw() {
    var x:Number = m_drawPoint.x;
    var y:Number = m_drawPoint.y;
    var width:Number = m_drawRect.size.width;
    var height:Number = m_drawRect.size.height;
    m_drawClip.lineStyle(1, 0x696E79, 100);
    m_drawClip.moveTo(x, y);
    m_drawClip.lineTo(x + width, y);
    m_drawClip.lineStyle(1, 0xF6F8F9, 100);
    m_drawClip.lineTo(x + width, y + height);
    m_drawClip.lineTo(x, y + height);
    m_drawClip.lineStyle(1, 0x696E79, 100);
    m_drawClip.lineTo(x, y);
    m_drawClip.lineStyle(1, 0x232831, 100);
    m_drawClip.beginFill(0x232831);
    m_drawClip.moveTo(x+3, y+8);
    m_drawClip.lineTo(x+7, y+12);
    m_drawClip.lineTo(x+13, y+6);
    m_drawClip.lineTo(x+13, y+5);
    m_drawClip.lineTo(x+12, y+5);
    m_drawClip.lineTo(x+7, y+10);
    m_drawClip.lineTo(x+4, y+7);
    m_drawClip.endFill();
  }
}