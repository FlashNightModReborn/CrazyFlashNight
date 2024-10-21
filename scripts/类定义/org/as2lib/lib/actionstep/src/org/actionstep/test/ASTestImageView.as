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
import org.actionstep.NSPoint;
import org.actionstep.constants.NSCompositingOperation;
import org.actionstep.NSImage;

class org.actionstep.test.ASTestImageView extends NSView {
  
  private var m_image:NSImage;
  
  public function initWithFrameImage(frame:NSRect, image:String):ASTestImageView {
    super.initWithFrame(frame);
    m_image = NSImage.imageNamed(image);
    return this;
  }
  
  public function drawRect(rect:NSRect) {
    with(m_mcBounds) {
      lineStyle(0, 0x000000, 0);
      beginFill(0xBEC3C9, 100);
      moveTo(0,0);
      lineTo(rect.size.width, 0);
      lineTo(rect.size.width, rect.size.height);
      lineTo(0, rect.size.height);
      lineTo(0, 0);
      endFill();
    }
    m_image.lockFocus(m_mcBounds);
    m_image.drawAtPointFromRectOperationFraction(new NSPoint(10,10), NSRect.ZeroRect, NSCompositingOperation.NSCompositeClear, 1.0);
    m_image.unlockFocus();
  }
}