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
 
import org.actionstep.NSSize;
import org.actionstep.NSPoint;
import org.actionstep.NSRect;
import org.actionstep.NSImageRep;

import org.actionstep.constants.NSCompositingOperation;

class org.actionstep.NSImage extends org.actionstep.NSObject {
  
  private static var g_images:Array = [];
  
  public static function get images():Array {
    return g_images;
  }
  
  private var m_name:String;
  private var m_size:NSSize;
  private var m_sizeWasSet:Boolean;
  private var m_representations:Array;
  private var m_movieClipStack:Array;
  
  public function NSImage() {
    m_representations = [];
    m_movieClipStack = [];
    m_sizeWasSet = false;
  }
  
  public function init():NSImage {
    return initWithSize(NSSize.ZeroSize);
  }
  
  public function initWithSize(size:NSSize):NSImage {
    super.init();
    m_size = size;
    m_sizeWasSet = true;
    return this;
  }
  
  public function description():String {
    return "NSImage(name="+name()+", size="+size()+", representation="+bestRepresentationForDevice(null)+")";
  }
  
  // Setting the size of the image

  public function setSize(value:NSSize) {
    m_size = value;
  }

  public function size():NSSize {
    if (m_size.width == 0) {
      var rep:NSImageRep = bestRepresentationForDevice(null);
      if (rep != null) {
        m_size = rep.size();
      } else {
        m_size = NSSize.ZeroSize;
      }
    }
    return m_size;
  }
  
  // Referring to images by name

  public static function imageNamed(name:String):NSImage {
    if(NSImage.images[name]!=undefined) {
      return NSImage.images[name];
    }
    return null;
  }
  
  public function setName(name:String):Boolean {
    if(NSImage.images[name]!=undefined) {
      return false;
    }
    NSImage.images[name] = this;
    m_name = name;
    return true;
  }
  
  public function name():String {
    return m_name;
  }
  
  // Specifying the image
  
  public function addRepresentation(rep:NSImageRep) {
    m_representations.push(rep);
  }
  
  public function lockFocus(mc:MovieClip) {
    m_movieClipStack.push(mc);
  }
  
  public function unlockFocus() {
    m_movieClipStack.pop();
  }
  
  public function focusClip():MovieClip {
    return m_movieClipStack[m_movieClipStack.length-1];
  }
  
  // Getting the representations
  
  public function bestRepresentationForDevice(description:String):NSImageRep {
    //! this is a major hack
    return m_representations[0];
  }
  
  // Drawing the image
  
  public function drawRepresentationInRect(rep:NSImageRep, rect:NSRect) {
  }
  
  public function drawAtPoint(point:NSPoint) {
    var rep:NSImageRep = bestRepresentationForDevice(null);
    if (rep != null) {
      rep.setFocus(focusClip());
      rep.drawAtPoint(point);
      rep.setFocus(null);
    }
  }
  
  public function drawAtPointFromRectOperationFraction(point:NSPoint, fromRect:NSRect, operation:NSCompositingOperation, fraction:Number) {
    var rep:NSImageRep = bestRepresentationForDevice(null);
    if (rep != null) {
      rep.setFocus(focusClip());
      rep.drawAtPoint(point);
      rep.setFocus(null);
    }
  }

  public function drawInRectFromRectOperationFraction(inRect:NSRect, fromRect:NSRect, operation:NSCompositingOperation, fraction:Number) {
    var rep:NSImageRep = bestRepresentationForDevice(null);
    if (rep != null) {
      rep.setFocus(focusClip());
      rep.drawInRect(inRect);
      rep.setFocus(null);
    }
  }
}