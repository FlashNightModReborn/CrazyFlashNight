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
import org.actionstep.NSSize;
import org.actionstep.NSPoint;
import org.actionstep.NSRect;

class org.actionstep.NSImageRep extends NSObject {
  
  private var m_drawPoint:NSPoint;
  private var m_drawRect:NSRect;
  private var m_drawClip:MovieClip;
  private var m_size:NSSize;
  private var m_defaultRect:NSRect;
  
  public function NSImageRep() {
    m_drawPoint = null;
    m_drawRect = null;
  }
  
  public function setSize(value:NSSize) {
    m_size = value;
  }

  public function size():NSSize {
    return m_size;
  }
  
  public function setFocus(clip:MovieClip) {
    m_drawClip = clip;
    m_drawPoint = NSPoint.ZeroPoint;
    if (m_defaultRect == null) {
      m_defaultRect = new NSRect(0,0,size().width, size().height);
    }
    m_drawRect = m_defaultRect;
  }
  
  public function draw() {
    // Override in subclasses to draw
  }
  
  public function drawInRect(rect:NSRect) {
    m_drawRect = rect;
    draw();
    m_drawRect = null;
  }
  
  public function drawAtPoint(point:NSPoint) {
    m_drawPoint = point;
    draw();
    m_drawPoint = null;
  }
  
  /**
   * Replaces the draw clip's clear() method with a new method that will also
   * cover the removal of MovieClip based image representations.
   */
  private function decorateDrawClipIfNeeded():Void {
    if (m_drawClip == null || m_drawClip.__oldClear != null) {
      return;
    }
    
    var dc:MovieClip = m_drawClip;
    m_drawClip.__imageReferences = new Array();
    m_drawClip.__oldClear = m_drawClip.clear;
    m_drawClip.clear = function() {
      var refs:Array = dc.__imageReferences;
      var len:Number = refs.length;
      
      for (var i:Number = 0; i < len; i++) {
        refs[i].removeMovieClip(); 
      }
      
      dc.__imageReferences = new Array();
      dc.__oldClear();
    };
  }
  
  /**
   * Adds an image rep created movieclip to a list of references held on the
   * draw clip. These references are used for clearing.
   */
  private function addImageRepToDrawClip(ref:MovieClip):Void {
    decorateDrawClipIfNeeded();
    m_drawClip.__imageReferences.push(ref);
  }
}