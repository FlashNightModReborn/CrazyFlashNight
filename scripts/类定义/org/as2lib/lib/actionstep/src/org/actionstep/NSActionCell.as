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
import org.actionstep.NSView;
import org.actionstep.NSFont;
import org.actionstep.NSImage;
import org.actionstep.NSRect;
import org.actionstep.NSControl;

import org.actionstep.constants.NSTextAlignment;

class org.actionstep.NSActionCell extends NSCell {
  
  private static var g_controlClass:Function = org.actionstep.NSControl;

  private var m_action:String;
  private var m_target:Object;
  private var m_tag:Number;
  
  // Configuring an NSActionCell
  
  public function setAlignment(alignment:NSTextAlignment) {
    super.setAlignment(alignment);
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).updateCell(this);
      }
    }
  }
  
  public function setBezeled(value:Boolean) {
    m_bezeled = value;
    if (m_bezeled) {
      m_bordered = false;
    }
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).updateCell(this);
      }
    }
  }

  public function setBordered(value:Boolean) {
    m_bordered = value;
    if (m_bordered) {
      m_bezeled = false;
    }
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).updateCell(this);
      }
    }
  }
  
  public function setEnabled(value:Boolean) {
    m_enabled = value;
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).updateCell(this);
      }
    }
  }

  public function setFont(font:NSFont) {
    super.setFont(font);
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).updateCell(this);
      }
    }
  }

  public function setImage(image:NSImage) {
    super.setImage(image);
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).updateCell(this);
      }
    }
  }
  
  // Obtaining and setting cell values
  
  public function doubleValue():Number {
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).validateEditing();
      }
    }
    return super.doubleValue();
  }

  public function floatValue():Number {
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).validateEditing();
      }
    }
    return super.floatValue();
  }

  public function intValue():Number {
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).validateEditing();
      }
    }
    return super.intValue();
  }

  public function stringValue():String {
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).validateEditing();
      }
    }
    return super.stringValue();
  }

  public function setObjectValue(value:Object) {
    super.setObjectValue(value);
    if (m_controlView != null) {
      if (m_controlView instanceof g_controlClass) {
        NSControl(m_controlView).updateCell(this);
      }
    }
  }

  // Displaying the NSActionCell
  
  public function drawWithFrameInView(cellFrame:NSRect, inView:NSView) {
    if (m_controlView != inView) {
      m_controlView = inView;
    }
    super.drawWithFrameInView(cellFrame, inView);
  }

  // Assigning target and action
  
  public function setAction(value:String) {
    m_action = value;
  }
  
  public function action():String {
    return m_action;
  }
  
  public function setTarget(value:Object) {
    m_target = value;
  }
  
  public function target():Object {
    return m_target;
  }
  
  // Assigning a tag
  
  public function setTag(value:Number) {
    m_tag = value;
  }
  
  public function tag():Number {
    return m_tag;
  }
  
  
}