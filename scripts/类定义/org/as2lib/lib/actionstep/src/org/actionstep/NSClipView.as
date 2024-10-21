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
 
import org.actionstep.ASDraw;
 
import org.actionstep.NSView;
import org.actionstep.NSNotificationCenter;
import org.actionstep.NSNotification;
import org.actionstep.NSPoint;
import org.actionstep.NSSize;
import org.actionstep.NSColor;
import org.actionstep.NSRect;
import org.actionstep.NSScrollView;

class org.actionstep.NSClipView extends NSView {
  private var m_documentView:NSView;
  private var m_drawsBackground:Boolean;
  private var m_copiesOnScroll:Boolean;
  private var m_backgroundColor:NSColor;
  
  public function init():NSClipView {
    super.init();
    setAutoresizesSubviews(true);
    m_copiesOnScroll = true;
    m_drawsBackground = true;
    return this;
  }
  
  // Setting the document view
  
  public function setDocumentView(view:NSView) {
    var nc:NSNotificationCenter;
    if (view == m_documentView) {
      return;
    }
    nc = NSNotificationCenter.defaultCenter();
    if (m_documentView) {
      nc.removeObserverNameObject(this, null, m_documentView);
      m_documentView.removeFromSuperview();
    }
    m_documentView = view;
    if (m_documentView != null) {
      var documentFrame:NSRect;
      addSubview(m_documentView);
      documentFrame = m_documentView.frame();
      setBoundsOrigin(documentFrame.origin);
      if (typeof(m_documentView["backgroundColor"])=="function") {
        m_backgroundColor = m_documentView["backgroundColor"].call(m_documentView);
      }
      if (typeof(m_documentView["drawsBackground"])=="function") {
        m_drawsBackground = m_documentView["drawsBackground"].call(m_documentView);
      }
      m_documentView.setPostsFrameChangedNotifications(true);
      m_documentView.setPostsBoundsChangedNotifications(true);
      nc.addObserverSelectorNameObject(this, "viewFrameChanged", NSView.NSViewFrameDidChangeNotification, m_documentView);
      nc.addObserverSelectorNameObject(this, "viewBoundsChanged", NSView.NSViewBoundsDidChangeNotification, m_documentView);
    }
    NSScrollView(superview()).reflectScrolledClipView(this);
  }
  
  public function documentView():NSView {
    return m_documentView;
  }
  
  // Scrolling
  
  public function scrollToPoint(point:NSPoint) {
    point = constrainScrollPoint(point);
    setBoundsOrigin(point);
  }
  
  public function constrainScrollPoint(point:NSPoint):NSPoint {
    var newPoint:NSPoint = point.clone();
    if (m_documentView == null) {
      return null;
    }
    var documentFrame:NSRect = m_documentView.frame();
    
    if (documentFrame.size.width <= m_bounds.size.width) {
      newPoint.x = documentFrame.origin.x;
    } else if (point.x <= documentFrame.origin.x) {
      newPoint.x = documentFrame.origin.x;
    } else if ((point.x + m_bounds.size.width) >= documentFrame.maxX()) {
      newPoint.x = documentFrame.maxX() - m_bounds.size.width;
    }
    
    if (documentFrame.size.height <= m_bounds.size.height) {
      newPoint.y = documentFrame.origin.y;
    } else if (point.y <= documentFrame.origin.y) {
      newPoint.y = documentFrame.origin.y;
    } else if ((point.y + m_bounds.size.height) >= documentFrame.maxY()) {
      newPoint.y = documentFrame.maxY() - m_bounds.size.height;
    }
    return newPoint;
  }

  //Determining scrolling efficiency
  public function setCopiesOnScroll(value:Boolean) {
    m_copiesOnScroll = value;
  }
  
  public function copiesOnScroll():Boolean {
    return m_copiesOnScroll;
  }

  //Getting the visible portion
  public function documentRect():NSRect {
    if (m_documentView == null) {
      return m_bounds;
    }
    var documentFrame:NSRect = m_documentView.frame();
    return new NSRect(documentFrame.origin.x, documentFrame.origin.y, 
      Math.max(documentFrame.size.width, m_bounds.size.width), 
      Math.max(documentFrame.size.height, m_bounds.size.height));
  }
  
  public function documentVisibleRect():NSRect {
    if (m_documentView == null) {
      return NSRect.ZeroRect;
    }
    return m_documentView.bounds().intersectionRect(convertRectToView(m_bounds, m_documentView));
  }
  
  // notification callbacks
  
  /**
   * This is fired when the boundary of this clip view's document view is
   * changed.
   */
  public function viewBoundsChanged(notification:NSNotification) {
    NSScrollView(superview()).reflectScrolledClipView(this);
  }

  /**
   * This is fired when the frame rectangle of this clip view's document view is
   * changed.
   */  
  public function viewFrameChanged(notification:NSNotification) {
    setBoundsOrigin(constrainScrollPoint(m_bounds.origin));
    if (!m_documentView.frame().containsRect(m_bounds)) {
      setNeedsDisplay();
    }
    NSScrollView(superview()).reflectScrolledClipView(this);
  }

  // Working with background color
  
  public function drawsBackground():Boolean {
    return m_drawsBackground;
  }
  
  public function setDrawsBackground(value:Boolean) {
    if (m_drawsBackground != value) {
      m_drawsBackground = value;
      setNeedsDisplay(true);      
    }
  }
  
  public function setBackgroundColor(color:NSColor) {
    m_backgroundColor = color;
    setNeedsDisplay(true);
  }
  
  public function backgroundColor():NSColor {
    return m_backgroundColor;
  }

  // Overridden functions

  public function setBoundsOrigin(point:NSPoint) {
    if (point.isEqual(m_bounds.origin) || m_documentView == null) {
      return;
    }
    super.setBoundsOrigin(point);
    //m_documentView.setNeedsDisplay(true);
    NSScrollView(m_superview).reflectScrolledClipView(this);
  }

  public function scaleUnitSquareToSize(size:NSSize) {
    super.scaleUnitSquareToSize(size);
    NSScrollView(m_superview).reflectScrolledClipView(this);
  }

  public function setBoundsSize(size:NSSize) {
    super.setBoundsSize(size);
    NSScrollView(m_superview).reflectScrolledClipView(this);
  }

  public function setFrameSize(size:NSSize) {
    super.setFrameSize(size);
    setBoundsOrigin(constrainScrollPoint(m_bounds.origin));
    NSScrollView(m_superview).reflectScrolledClipView(this);
  }

  public function setFrameOrigin(origin:NSPoint) {
    super.setFrameOrigin(origin);
    setBoundsOrigin(constrainScrollPoint(m_bounds.origin));
    NSScrollView(m_superview).reflectScrolledClipView(this);
  }

  public function setFrame(rect:NSRect) {
    super.setFrame(rect);
    setBoundsOrigin(constrainScrollPoint(m_bounds.origin));
    NSScrollView(m_superview).reflectScrolledClipView(this);
  }

  public function translateOriginToPoint(point:NSPoint) {
    super.translateOriginToPoint(point);
    NSScrollView(m_superview).reflectScrolledClipView(this);
  } 

  public function rotateByAngle(angle:Number) { 
    // IGNORE 
  } 

  public function setBoundsRotation(angle:Number) { 
    // IGNORE 
  } 

  public function setFrameRotation(angle:Number) { 
    // IGNORE 
  }

  public function acceptsFirstResponder():Boolean {
    if (m_documentView == null) {
      return false;
    } else {
      return m_documentView.acceptsFirstResponder();
    }
  }

  public function becomeFirstResponder():Boolean {
    if (m_documentView == null) {
      return false;
    } else {
      return m_window.makeFirstResponder(m_documentView);
    }
  }
  
  public function drawRect(rect:NSRect) {
    m_mcBounds.clear();
    if (m_drawsBackground) {
      ASDraw.solidRectWithRect(m_mcBounds, rect, m_backgroundColor.value);
    }
  }

    
}