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
 
  
/*

Calculating layout
+ contentSizeForFrameSize:hasHorizontalScroller:hasVerticalScroller:borderType:
+ frameSizeForContentSize:hasHorizontalScroller:hasVerticalScroller:borderType:

*/ 
 
import org.actionstep.ASDraw;
import org.actionstep.constants.NSBorderType;
import org.actionstep.constants.NSRectEdge;
import org.actionstep.constants.NSScrollerPart;
import org.actionstep.NSClipView;
import org.actionstep.NSColor;
import org.actionstep.NSEvent;
import org.actionstep.NSPoint;
import org.actionstep.NSRect;
import org.actionstep.NSScroller;
import org.actionstep.NSSize;
import org.actionstep.NSView;

class org.actionstep.NSScrollView extends NSView {
  
  private var m_contentView:NSClipView;
  private var m_borderType:NSBorderType;
  private var m_horizontalScroller:NSScroller;
  private var m_verticalScroller:NSScroller;
  private var m_hasHorizontalScroller:Boolean;
  private var m_hasVerticalScroller:Boolean;
  private var m_autohidesScrollers:Boolean;
  private var m_scrollsDynamically:Boolean;

  private var m_horizontalLineScroll:Number;
  private var m_verticalLineScroll:Number;
  private var m_horizontalPageScroll:Number;
  private var m_verticalPageScroll:Number;

  private var m_knobMoved:Boolean;
  
  //
  // Header and corner views.
  //
  private var m_hasHeaderView:Boolean;
  private var m_headerClipView:NSClipView;
  private var m_hasCornerView:Boolean;
  private var m_cornerView:NSView;
    
  
  /**
   * Initializes and returns an NSScrollView with a frame of NSRect.ZeroRect.
   */  
  public function init():NSScrollView {
    return initWithFrame(NSRect.ZeroRect);
  }
  
  public function initWithFrame(rect:NSRect):NSScrollView {
    super.initWithFrame(rect);
    m_borderType = NSBorderType.NSNoBorder;
    m_autohidesScrollers = false;
    m_horizontalLineScroll = 10;
    m_verticalLineScroll = 10;
    m_horizontalPageScroll = 100;
    m_verticalPageScroll = 100;
    m_scrollsDynamically = true;
    m_hasHeaderView = false;
    m_hasCornerView = false;
    setContentView((new NSClipView()).init()); // this results in a tile
    return this;
  }
  
  // Determining component sizes
  
  public function contentSize():NSSize {
    return m_contentView.bounds().size;
  }
  
  public function documentVisibleRect():NSRect {
    return m_contentView.documentVisibleRect();
  }
  
  // Managing graphics attributes
  
  public function setBackgroundColor(color:NSColor) {
    m_contentView.setBackgroundColor(color);
  }
  
  public function backgroundColor():NSColor {
    return m_contentView.backgroundColor();
  }
  
  public function drawsBackground():Boolean {
    return m_contentView.drawsBackground();
  }

  public function setDrawsBackground(value:Boolean) {
    m_contentView.setDrawsBackground(value);
  }
  
  public function setBorderType(value:NSBorderType) {
    m_borderType = value;
    tile();
  }
  
  public function borderType():NSBorderType {
    return m_borderType;
  }
  
  // Managing the scrolled views
  
  /**
   * Sets the content of the NSScrollView, which is the view that clips
   * the document view. If view has a document view, it becomes the scrollview's
   * documentView.
   * 
   * This is set to an NSClipView by default.
   * 
   * @see #contentView
   * @see #documentView
   */
  public function setContentView(view:NSClipView) {
    if (view == null || !(view instanceof NSView)) {
      throw new Error("You cannot set a content view to anything other than an NSView");
    }
    if (view != m_contentView) {
      var docView:NSView = view.documentView();
      m_contentView.removeFromSuperview();
      m_contentView = view;
      addSubview(m_contentView);
      if (docView != null) {
        setDocumentView(docView);
      }
    }
    m_contentView.setAutoresizingMask(NSView.WidthSizable | NSView.HeightSizable);
    tile();
  }
  
  /**
   * Returns the content of the NSScrollView, which is the view that clips
   * the document view.
   * 
   * This is set to an NSClipView by default.
   * 
   * @see #setContentView
   */
  public function contentView():NSClipView {
    return m_contentView;
  }
  
  /**
   * Sets the view that is scrolled within the NSScrollView.
   * 
   * @see #documentView
   */
  public function setDocumentView(view:NSView) {
    m_contentView.setDocumentView(view);
    tile();
  }
  
  /**
   * Returns the view that is scrolled within the NSScrollView.
   * 
   * @see #documentView
   */
  public function documentView():NSView {
    return m_contentView.documentView();
  }

  // Managing scrollers

  public function setHorizontalScroller(scroller:NSScroller) {
    if (m_horizontalScroller != null) {
      m_horizontalScroller.removeFromSuperview();
    }
    m_horizontalScroller = scroller;
    if (m_horizontalScroller != null) {
      m_horizontalScroller.setAutoresizingMask(NSView.WidthSizable);
      m_horizontalScroller.setTarget(this);
      m_horizontalScroller.setAction("scrollAction");
    }  
  }
  
  public function horizontalScroller():NSScroller {
    return m_horizontalScroller;
  }
  
  public function setHasHorizontalScroller(value:Boolean) {
    if (m_hasHorizontalScroller == value) {
      return;
    }
    m_hasHorizontalScroller = value;
    if (m_hasHorizontalScroller) {
      if (m_horizontalScroller == null) {
        setHorizontalScroller((new NSScroller()).init());
      }
      addSubview(m_horizontalScroller);
    } else {
      m_horizontalScroller.removeFromSuperview();
    }
    tile();
  }
  
  public function hasHorizontalScroller():Boolean {
    return m_hasHorizontalScroller;
  }

  public function setVerticalScroller(scroller:NSScroller) {
    if (m_verticalScroller != null) {
      m_verticalScroller.removeFromSuperview();
    }
    m_verticalScroller = scroller;
    if (m_verticalScroller != null) {
      m_verticalScroller.setAutoresizingMask(NSView.WidthSizable);
      m_verticalScroller.setTarget(this);
      m_verticalScroller.setAction("scrollAction");
    }  
  }

  public function verticalScroller():NSScroller {
    return m_verticalScroller;
  }

  public function setHasVerticalScroller(value:Boolean) {
    if (m_hasVerticalScroller == value) {
      return;
    }
    m_hasVerticalScroller = value;
    if (m_hasVerticalScroller) {
      if (m_verticalScroller == null) {
        setVerticalScroller((new NSScroller()).init());
      }
      addSubview(m_verticalScroller);
    } else {
      m_verticalScroller.removeFromSuperview();
    }
    tile();
  }

  public function hasVerticalScroller():Boolean {
    return m_hasVerticalScroller;
  }
  
  public function setAutohidesScrollers(value:Boolean) {
    if (m_autohidesScrollers == value) {
      return;
    }
    m_autohidesScrollers = value;
    tile();
  }
  
  public function autohidesScrollers():Boolean {
    return m_autohidesScrollers;
  }
  
  // Setting scrolling behavior
  /*
  – scrollWheel:  
  */
  
  
  public function setLineScroll(value:Number) {
    m_horizontalLineScroll = value;
    m_verticalLineScroll = value;
  }
  
  public function lineScroll():Number {
    if (m_horizontalLineScroll != m_verticalLineScroll) {
      throw new Error("Horizontal and vertical line scroll values are not the same");
    }
    return m_horizontalLineScroll;
  }
  
  public function setHorizontalLineScroll(value:Number) {
    m_horizontalLineScroll = value;
  }
  
  public function horizontalLineScroll():Number {
    return m_horizontalLineScroll;
  }
  
  public function setVerticalLineScroll(value:Number) {
    m_verticalLineScroll = value;
  }
  
  public function verticalLineScroll():Number {
    return m_verticalLineScroll;
  }

  public function setPageScroll(value:Number) {
    m_horizontalPageScroll = value;
    m_verticalPageScroll = value;
  }

  public function pageScroll():Number {
    if (m_horizontalPageScroll != m_verticalPageScroll) {
      throw new Error("Horizontal and vertical page scroll values are not the same");
    }
    return m_horizontalPageScroll;
  }

  public function setHorizontalPageScroll(value:Number) {
    m_horizontalPageScroll = value;
  }

  public function horizontalPageScroll():Number {
    return m_horizontalPageScroll;
  }

  public function setVerticalPageScroll(value:Number) {
    m_verticalPageScroll = value;
  }

  public function verticalPageScroll():Number {
    return m_verticalPageScroll;
  }
  
  public function setScrollsDynamically(value:Boolean) {
    if (m_scrollsDynamically == value) {
      return;
    }
    m_scrollsDynamically = value;
  }
  
  public function scrollsDynamically():Boolean {
    return m_scrollsDynamically;
  }
  
  public function scrollWheel(event:NSEvent) {
    //! Implement this?
  }
  
  /**
   * Callback from NSScroller in target/action
   */
  public function scrollAction(scroller:NSScroller) {
    var floatValue:Number = scroller.floatValue();
    var hitPart:NSScrollerPart = scroller.hitPart();
    var clipViewBounds:NSRect;
    var documentRect:NSRect;
    var amount:Number = 0;
    var point:NSPoint;
    
    if (m_contentView == null) {
      clipViewBounds = NSRect.ZeroRect;
      documentRect = NSRect.ZeroRect;
    } else {
      clipViewBounds = m_contentView.bounds();
      documentRect = m_contentView.documentRect();
    }
    point = clipViewBounds.origin.clone();
    
    if (scroller != m_verticalScroller && scroller != m_horizontalScroller) {
      //Unknown scroller
      return; 
    }
    
    m_knobMoved = false;
    switch(scroller.hitPart()) {
      case NSScrollerPart.NSScrollerKnob:
      case NSScrollerPart.NSScrollerKnobSlot:
        m_knobMoved = true;
        break;
      case NSScrollerPart.NSScrollerIncrementPage:
        if (scroller == m_horizontalScroller) {
          amount = m_horizontalPageScroll;
        } else {
          amount = m_verticalPageScroll;
        }
        break;
      case NSScrollerPart.NSScrollerIncrementLine:
        if (scroller == m_horizontalScroller) {
          amount = m_horizontalLineScroll;
        } else {
          amount = m_verticalLineScroll;
        }
        break;
      case NSScrollerPart.NSScrollerDecrementPage:
        if (scroller == m_horizontalScroller) {
          amount = -m_horizontalPageScroll;
        } else {
          amount = -m_verticalPageScroll;
        }
        break;
      case NSScrollerPart.NSScrollerDecrementLine:
        if (scroller == m_horizontalScroller) {
          amount = -m_horizontalLineScroll;
        } else {
          amount = -m_verticalLineScroll;
        }
        break;
      default:
        return;
    }
    if (!m_knobMoved) {
      if (scroller == m_horizontalScroller) {
        point.x = clipViewBounds.origin.x + amount;
      } else {
        point.y = clipViewBounds.origin.y + amount;
      }
    } else {
      if (scroller == m_horizontalScroller) {
        point.x = floatValue * (documentRect.size.width - clipViewBounds.size.width);
        point.x += documentRect.origin.x;
      } else {
        point.y = floatValue * (documentRect.size.height - clipViewBounds.size.height);
        point.y += documentRect.origin.y;
      }
    }
    m_contentView.scrollToPoint(point);
  }
   
  // Updating display after scrolling
  
  public function reflectScrolledClipView(view:NSView) {
    var documentFrame:NSRect = NSRect.ZeroRect;
    var clipViewBounds:NSRect = NSRect.ZeroRect;
    var floatValue:Number = 0;
    var knobProportion:Number = 0;
    var documentView:NSView;
    if (view != m_contentView) {
      return;
    }
    if (m_contentView != null) {
      clipViewBounds = m_contentView.bounds();
      documentView = m_contentView.documentView();
    }
    if (documentView != null) {
      documentFrame = documentView.frame();
    }
    if (m_hasVerticalScroller) {
      if (documentFrame.size.height <= clipViewBounds.size.height) {
        m_verticalScroller.setEnabled(false);
      } else {
        m_verticalScroller.setEnabled(true);
        knobProportion = clipViewBounds.size.height / documentFrame.size.height;
        floatValue = (clipViewBounds.origin.y - documentFrame.origin.y) /
                     (documentFrame.size.height - clipViewBounds.size.height);
        m_verticalScroller.setFloatValueKnobProportion(floatValue, knobProportion);   
        m_verticalScroller.setNeedsDisplay(true);
      }
    }
    if (m_hasHorizontalScroller) {
      if (documentFrame.size.width <= clipViewBounds.size.width) {
        m_horizontalScroller.setEnabled(false);
      } else {
        m_horizontalScroller.setEnabled(true);
        knobProportion = clipViewBounds.size.width / documentFrame.size.width;
        floatValue = (clipViewBounds.origin.x - documentFrame.origin.x) /
                     (documentFrame.size.width - clipViewBounds.size.width);
        m_horizontalScroller.setFloatValueKnobProportion(floatValue, knobProportion);          
        m_horizontalScroller.setNeedsDisplay(true);
      }
    }
  }
  
  // Arranging components
  
  public function tile() {  	  	
    var contentRect:NSRect;
    var vScrollerRect:NSRect;
    var hScrollerRect:NSRect;
    var headerRect:NSRect = NSRect.ZeroRect;
    var topEdge:NSRectEdge = NSRectEdge.NSMinYEdge;
    var bottomEdge:NSRectEdge = NSRectEdge.NSMaxYEdge;
    var headerViewHeight:Number = 0;
    var scrollerWidth:Number = NSScroller.scrollerWidth();
        
    //
    // Inset for the borders
    //      
    contentRect = m_bounds.insetRect(m_borderType.size.width, m_borderType.size.height);
    
    //
    // Deal with header / corner views
    //
    synchronizeHeaderAndCornerView();
    
    if (m_hasHeaderView) {
      headerViewHeight = m_headerClipView.documentView().frame().size.height;
    }
    
    if (m_hasCornerView) {
      if (headerViewHeight == 0) {
        headerViewHeight = m_cornerView.frame().size.height;
      }
    }
        
    //
    // Determine the respective sizes of the content and header views
    //
    NSRect.divideRect(contentRect, headerRect, contentRect, headerViewHeight,
      topEdge);
        
    //
    // Position scrollers
    //
    if (m_hasVerticalScroller) {
      if (m_hasHorizontalScroller) {
        vScrollerRect = new NSRect(contentRect.maxX() - scrollerWidth, contentRect.minY(), scrollerWidth, contentRect.size.height - scrollerWidth);
        hScrollerRect = new NSRect(contentRect.minX(), contentRect.maxY() - scrollerWidth, contentRect.size.width - scrollerWidth, scrollerWidth);
        m_verticalScroller.setFrame(vScrollerRect);
        m_horizontalScroller.setFrame(hScrollerRect);
      } else {
        vScrollerRect = new NSRect(contentRect.maxX() - scrollerWidth, contentRect.minY(), scrollerWidth, contentRect.size.height);
        m_verticalScroller.setFrame(vScrollerRect);
      }
    } else if (m_hasHorizontalScroller) {
      hScrollerRect = new NSRect(contentRect.minX(), contentRect.maxY() - scrollerWidth, contentRect.size.width, scrollerWidth);
      m_horizontalScroller.setFrame(hScrollerRect);
    }
    if (m_hasVerticalScroller) {
      contentRect.size.width  -= (vScrollerRect.size.width);
    }
    if (m_hasHorizontalScroller) {
      contentRect.size.height -= (hScrollerRect.size.height);
    }
    
    //
    // Position header and corner views
    //
    if (m_hasHeaderView) {
      var rect:NSRect = headerRect.clone();
      rect.origin.x = contentRect.origin.x;
      rect.size.width = contentRect.size.width;
      
      m_headerClipView.setFrame(rect);
    }
    
    if (m_hasCornerView) {
      m_cornerView.setFrame(NSRect.withOriginSize(
      	headerRect.origin.translate(contentRect.size.width, 0),
      	new NSSize(vScrollerRect.size.width, headerViewHeight)));
    }
    
    m_contentView.setFrame(contentRect);
    setNeedsDisplay(true);
  }
  
  /**
   * Sets up or removes the header and corner views.
   */
  private function synchronizeHeaderAndCornerView():Void {
  	  	
    var hadHeaderView:Boolean = m_hasHeaderView;
    var hadCornerView:Boolean = m_hasCornerView;
    var aView:NSView = null;

    //
    // Deal with header view
    //    
    m_hasHeaderView = documentView().respondsToSelector("headerView") &&
      null != (aView = documentView()["headerView"]());

    if (m_hasHeaderView) {
      if (!hadHeaderView) { // Create header clip view if needed
        m_headerClipView = (new NSClipView()).init();
        addSubview(m_headerClipView);
      }
      
      m_headerClipView.setDocumentView(aView);
    }
    else if (hadHeaderView) { // Remove header clip view
      m_headerClipView.removeFromSuperview();
      m_headerClipView = null;
    }
    
    //
    // Deal with corner view
    //
    if (m_hasVerticalScroller) { // corner views appear above the vert scroller
      aView = null;
      m_hasCornerView = documentView().respondsToSelector("cornerView") &&
        null != (aView = documentView()["cornerView"]());
      
      if (aView == m_cornerView) { // no change, so return
        return;
      }
      
      if (m_hasCornerView) { // Add (or replace) the corner view
        if (!hadCornerView) {
          addSubview(aView);
        } else {
          replaceSubviewWith(m_cornerView, aView);
        }
      }
      else if (hadCornerView) { // Remove the current corner view
        m_cornerView.removeFromSuperview();
      }
      
      m_cornerView = aView;
    }
    else if (m_cornerView != null) { // no place to put it, so remove it
      m_cornerView.removeFromSuperview();
      m_cornerView = null;
      m_hasCornerView = false;
    }
  }
  
  // Overridden functions
  
  public function drawRect(rect:NSRect) {
    m_mcBounds.clear();
    switch(m_borderType) {
      case NSBorderType.NSNoBorder:
        break;
      case NSBorderType.NSLineBorder:
        ASDraw.outlineRectWithRect(m_mcBounds, rect, [0]);
        break;
      case NSBorderType.NSBezelBorder:
        ASDraw.outlineRectWithRect(m_mcBounds, rect, [0]);
        break;
      case NSBorderType.NSGrooveBorder:
        ASDraw.outlineRectWithRect(m_mcBounds, rect, [0]);
        break;
    }
  }
  
  public function willRemoveSubview(view:NSView) {
    if (view == m_contentView) {
      m_contentView = null;
    }
  }
  
  public function setFrame(rect:NSRect) {
    super.setFrame(rect);
    tile();
  }
  
  public function setFrameSize(size:NSSize) {
    super.setFrameSize(size);
    tile();
  }
  
  public function resizeSubviewsWithOldSize(size:NSSize) {
    super.resizeSubviewsWithOldSize(size);
    tile();
  }
  
  public function isOpaque():Boolean {
    return true;
  }
  
}