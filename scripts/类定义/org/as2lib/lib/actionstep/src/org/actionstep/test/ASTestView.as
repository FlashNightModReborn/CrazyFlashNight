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
 
import org.actionstep.NSView;
import org.actionstep.NSRect;
import org.actionstep.NSColor;
import org.actionstep.NSEvent;

class org.actionstep.test.ASTestView extends NSView {
  private var m_backgroundColor:NSColor;
  private var m_borderColor:NSColor;
  private var m_headerView:ASTestView;
  private var m_cornerView:ASTestView;
  
  public function ASTestView() {
    m_backgroundColor = new NSColor(0xBEC3C9);
  }
  
  public function setBackgroundColor(color:NSColor) {
    m_backgroundColor = color;
  }
  
  public function backgroundColor():NSColor {
    return m_backgroundColor;
  }
  
  public function setBorderColor(color:NSColor) {
    m_borderColor = color;
  }
  
  public function borderColor():NSColor {
    return m_borderColor;
  }
  
  public function mouseDown(event:NSEvent) {
    trace(event.clickCount);
  }
  
  public function acceptsFirstResponder():Boolean {
    return true;
  }
  
  public function addHeaderView():Void {
    m_headerView = ASTestView(
    	(new ASTestView()).initWithFrame(new NSRect(0, 0, 40, 30)));
    m_headerView.setBackgroundColor(new NSColor(0x990000));
  }
  
  public function headerView():NSView {
    return m_headerView;
  }
  
  public function addCornerView():Void {
    m_cornerView = ASTestView(
    	(new ASTestView()).initWithFrame(new NSRect(0, 0, 40, 30)));
    m_cornerView.setBackgroundColor(new NSColor(0x009933));
  }
  
  public function cornerView():NSView {
    return m_cornerView;
  }
  
  public function drawRect(rect:NSRect) {
    with(m_mcBounds) {
      clear();
      if (m_borderColor != null) {
        lineStyle(1, m_borderColor.value, 100);
      } else {
        lineStyle(1, m_backgroundColor.value, 100);
      }
      beginFill(m_backgroundColor.value, 100);
      moveTo(0,0);
      lineTo(rect.size.width-1, 0);
      lineTo(rect.size.width-1, rect.size.height-1);
      lineTo(0, rect.size.height-1);
      lineTo(0, 0);
      endFill();
    }
    
  }
}
  