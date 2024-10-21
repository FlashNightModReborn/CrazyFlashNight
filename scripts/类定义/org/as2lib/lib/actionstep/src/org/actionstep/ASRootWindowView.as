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
import org.actionstep.NSApplication;
import org.actionstep.NSWindow;
import org.actionstep.NSRect;
import org.actionstep.NSFont;
import org.actionstep.NSColor;
import org.actionstep.NSPoint;
import org.actionstep.NSEvent;

import flash.filters.DropShadowFilter;

class org.actionstep.ASRootWindowView extends NSView {

  // Static Functions
  
  private static var g_lowestView:ASRootWindowView = null;
  
  private var m_contentRect:NSRect;
  private var m_swfLoading:Boolean;
  private var m_swfLoaded:Boolean;
  private var m_window:NSWindow;
  private var m_titleRect:NSRect;
  private var m_resizeRect:NSRect;
  private var m_trackingData:Object;

  private var m_lowerView:ASRootWindowView;
  private var m_higherView:ASRootWindowView;
  private var m_targetDepth:Number;
  
  private var m_titleTextField:TextField;
  private var m_titleTextFormat:TextFormat;
  private var m_titleFont:NSFont;
  private var m_titleKeyFontColor:NSColor;
  private var m_titleFontColor:NSColor;
  
  private var m_resizeClip:MovieClip;
  private var m_showsResizeIndicator:Boolean;

  //
  // For Flash 8
  //
  private var m_mcBase:MovieClip;
  
  /** IF Flash8 */
  private var m_shadowFilter:DropShadowFilter;
  /** ENDIF */

  
  public function ASRootWindowView() {
    m_swfLoading = false;
    m_swfLoaded = false;
    m_showsResizeIndicator = true;
    m_titleRect = new NSRect(0,0,0,22);
    m_resizeRect = new NSRect(-11,-11,11,11);
  }

  public function initWithFrameWindow(frame:NSRect, window:NSWindow):ASRootWindowView {
    initWithFrame(frame);
    m_titleFont = NSFont.systemFontOfSize(12);
    m_titleKeyFontColor = NSColor.systemFontColor();
    m_titleFontColor = new NSColor(0x666666);
    m_titleTextFormat = m_titleFont.textFormat();
    m_titleTextFormat.bold = true;
    m_titleTextFormat.color = m_titleKeyFontColor.value;
    m_window = window;
    setLowerView(highestViewOfLevel());
    return this;
  }

  public function createMovieClips() {
    super.createMovieClips();
    if (m_mcBounds != null) {
      if (m_window.styleMask() & NSWindow.NSResizableWindowMask) {
        
        m_resizeClip = m_mcBounds.createEmptyMovieClip("ResizeClip", 1000000);
        drawResizeClip();
        m_resizeClip.view = this;
        m_resizeClip._x = m_frame.size.width-12;
        m_resizeClip._y = m_frame.size.height-12;
        m_resizeRect.origin.x = m_resizeClip._x;
        m_resizeRect.origin.y = m_resizeClip._y;
      }
    }
  }
  
  private function drawResizeClip() {
    with(m_resizeClip) {
      clear();
      beginFill(0xFFFFFF, 1);
      lineStyle(0, 0xFFFFFF, 1);
      moveTo(0,0);
      lineTo(10,0);
      lineTo(10,10);
      lineTo(0,10);
      lineTo(0,0);
      endFill();
    }
    if (m_showsResizeIndicator) {
      with(m_resizeClip) {
        //da 87 e8 ff
        lineStyle(1.5, 0xdadada, 100);
        moveTo(0,10);
        lineTo(10,0);
        lineStyle(1.5, 0x878787, 100);
        moveTo(1,10);
        lineTo(10,1);
        lineStyle(1.5, 0xe8e8e8, 100);
        moveTo(2,10);
        lineTo(10,2);

        lineStyle(1.5, 0xdadada, 100);
        moveTo(4,10);
        lineTo(10,4);
        lineStyle(1.5, 0x878787, 100);
        moveTo(5,10);
        lineTo(10,5);
        lineStyle(1.5, 0xe8e8e8, 100);
        moveTo(6,10);
        lineTo(10,6);

        lineStyle(1.5, 0xdadada, 100);
        moveTo(8,10);
        lineTo(10,8);
        lineStyle(1.5, 0x878787, 100);
        moveTo(9,10);
        lineTo(10,9);
        lineStyle(1.5, 0xe8e8e8, 100);
        moveTo(10,10);
        lineTo(10,10);
      }
    }
  }
  
  public function removeFromSuperview() {
    removeMovieClips();
  }

  public function removeMovieClips():Void {
    super.removeMovieClips();
    m_mcBase.removeMovieClip();
    m_mcBase = null;
  }
  
  public function setWindowTransparency(level:Number) {
    m_mcBase._alpha = level;
  }

  private function updateFrameMovieClipSize():Void {
    super.updateFrameMovieClipSize();
    if (m_mcBase != null) {
      m_resizeClip._x = m_frame.size.width-12;
      m_resizeClip._y = m_frame.size.height-12;
      m_resizeRect.origin.x = m_resizeClip._x;
      m_resizeRect.origin.y = m_resizeClip._y;
      m_titleTextField._x = (m_frame.size.width - (m_titleTextField.textWidth+2))/2;
    }
  }

  private function updateFrameMovieClipPosition():Void {
    if (m_mcBase == null) {
      return;
    }
    m_mcBase._x = m_frame.origin.x;
    m_mcBase._y = m_frame.origin.y;
  }
  
  public static function lowestView():ASRootWindowView {
    return g_lowestView;
  }
  
  public function dump(view:ASRootWindowView) {
    if(view == null) view = g_lowestView;
    trace(view.lowerView().window().windowNumber()+" - "+view.window().windowNumber()+" - "+view.higherView().window().windowNumber());
    if(view.higherView() != null) {
      dump(view.higherView());
    } else {
      trace("---");
    }
  }
  
  public function highestViewOfLevel():ASRootWindowView {
    var view:ASRootWindowView = g_lowestView;
    while(view.higherView() != null && view.higherView().level()<=level()) {
      view = view.higherView();
    }
    if (view.level() > level()) {
      view = null;
    }
    return view;
  }

  public function lowestViewOfLevel():ASRootWindowView {
    var view:ASRootWindowView = g_lowestView;
    while(view != null && view.level()>=level()) {
      view = view.higherView();
    }
    return view;
  }
  
  public function level():Number {
    return m_window.level();
  }
  
  public function setHigherView(view:ASRootWindowView) {
    m_higherView = view;
  }
  
  public function higherView():ASRootWindowView {
    return m_higherView;
  }
  
  public function setLowerView(view:ASRootWindowView) {
    if (view == null) {
      if (g_lowestView != null) {
        g_lowestView.setLowerView(this);
      }
      m_lowerView = view;
      g_lowestView = this;
    } else {
      if (view != m_lowerView) {
        m_lowerView = view;
        view.higherView().setLowerView(this);
        view.setHigherView(this);
      }
    }
    setTargetDepths();
  }

  public function setTargetDepths() {
    var view:ASRootWindowView = g_lowestView;
    var i:Number = 100;
    view.setTargetDepth(i++);
    while(view.higherView() != null) {
      view.higherView().setTargetDepth(i++);
      view = view.higherView();
    }
  }
  
  public function setTargetDepth(depth:Number) {
    m_targetDepth = depth;
  }
  
  public function extractView() {
    var lower:ASRootWindowView = m_lowerView;
    var higher:ASRootWindowView = m_higherView;
    m_higherView = null;
    m_lowerView = null;
    if (g_lowestView == this) {
      g_lowestView = higher;
      higher.m_lowerView = null;
      return;
    }
    higher.m_lowerView = lower;
    lower.m_higherView = higher;
  }
  
  public function lowerView():ASRootWindowView {
    return m_lowerView;
  }
  
  public function matchDepth() {
    if (m_mcBase == null) {
      return;
    }
    var oldDepth:Number = m_mcBase.getDepth();
    if (m_targetDepth != oldDepth) {
      m_mcBase.swapDepths(m_targetDepth);
      _root.getInstanceAtDepth(oldDepth).view.matchDepth();
    }
  }
  
  private function createFrameMovieClip():MovieClip {
    var self:ASRootWindowView = this;
    var depth:Number = m_targetDepth;
    if (_root.getInstanceAtDepth(depth) != null) {
      depth = m_window.windowNumber()+100;
    }
    m_mcBase  = _root.createEmptyMovieClip("ASRootWindowView"+m_window.windowNumber(), depth);
    m_mcBase.view = this;
    /** IF Flash8 */
    m_shadowFilter = new DropShadowFilter();
    m_shadowFilter.blurX = 20;
    m_shadowFilter.blurY = 20;
    m_shadowFilter.alpha = .6;
    m_shadowFilter.strength = .7;
    m_shadowFilter.angle = 90;
    m_mcBase.filters = [m_shadowFilter];
    /** ENDIF */
    _root["ASRootWindowView"+m_window.windowNumber()].window = m_window;
    m_mcFrame = m_mcBase.createEmptyMovieClip("MCFRAME", 1);
    m_mcFrame.window = m_window;
    matchDepth();
    m_mcFrame.onEnterFrame = function() {
      self.window().displayIfNeeded();
    };
    return m_mcFrame;
  }
  
  private function loadSwf() {
    m_mcBounds = m_mcFrame.createEmptyMovieClip("m_mcBounds", 2);
    var image_mcl:MovieClipLoader = new MovieClipLoader();
    image_mcl.addListener(this);
    m_mcBounds._lockroot = true;
    image_mcl.loadClip(m_window.swf(), m_mcBounds);
  }
  
  public function onLoadInit(target_mc:MovieClip) {
    m_swfLoading = false;
    m_swfLoaded = true;
    m_mcBounds.view = this;
    updateBoundsMovieClip();
    for(var i:Number=0;i<m_subviews.length;i++) {
      m_subviews[i].createMovieClips();
    }
    display();
  }
  
  public function setContentView(view:NSView) {
    var contentView:NSView = subviews()[0];
    if (contentView != null) {
      replaceSubviewWith(contentView, view);
    } else {
      addSubview(view);
    }
  }

  public function acceptsFirstMouse(event:NSEvent):Boolean {
    return true;
  }

  private function initializeBoundsMovieClip() {
    if (m_window.swf() != null) {
      if(m_swfLoading) {
        return;
      } else {
        m_swfLoading = true;
        loadSwf();
        return;
      }
    }
    super.initializeBoundsMovieClip();
  }
  
  public function display() {
    if(m_mcBase == undefined) {
      createMovieClips();
    }
    if(m_mcBounds.view != undefined) {
      super.display();
      m_window.windowDidDisplay();
    }
  }
  
  public function displayIfNeeded() {
    if(m_mcBase == undefined) {
      createMovieClips();
    }
    if (m_mcBounds.view != undefined) {
      super.displayIfNeeded();
    }
  }
  
  public function mouseDown(event:NSEvent) {
    if (m_window.styleMask() == NSWindow.NSBorderlessWindowMask) {
      return;
    }
    var location:NSPoint = event.mouseLocation;
    location = convertPointFromView(location);
    if(m_titleRect.pointInRect(location)) {
      dragWindow(event);
    }
    if(m_resizeRect.pointInRect(location)) {
      resizeWindow(event);
    }
  }

  private function dragWindow(event:NSEvent) {
    var point:NSPoint = convertPointFromView(event.mouseLocation, null);
    m_trackingData = { 
      offsetX: point.x,
      offsetY: point.y,
      mouseDown: true, 
      eventMask: NSEvent.NSLeftMouseDownMask | NSEvent.NSLeftMouseUpMask | NSEvent.NSLeftMouseDraggedMask
        | NSEvent.NSMouseMovedMask  | NSEvent.NSOtherMouseDraggedMask | NSEvent.NSRightMouseDraggedMask,
      complete: false
    };
    //m_mcBase._alpha = 80;
    dragWindowCallback(event);
  }

  public function dragWindowCallback(event:NSEvent) {
    if (event.type == NSEvent.NSLeftMouseUp) {
      //m_mcBase._alpha = 100;
      return;
    }
    m_window.setFrameOrigin(new NSPoint(event.mouseLocation.x - m_trackingData.offsetX, event.mouseLocation.y - m_trackingData.offsetY));
    NSApplication.sharedApplication().callObjectSelectorWithNextEventMatchingMaskDequeue(this, "dragWindowCallback", m_trackingData.eventMask, true);
  }

  private function resizeWindow(event:NSEvent) {
    var frame:NSRect = frame();
    m_trackingData = { 
      origin: frame.origin,
      offsetX: frame.origin.x + frame.size.width - event.mouseLocation.x,
      offsetY: frame.origin.y + frame.size.height - event.mouseLocation.y,
      mouseDown: true, 
      eventMask: NSEvent.NSLeftMouseDownMask | NSEvent.NSLeftMouseUpMask | NSEvent.NSLeftMouseDraggedMask
        | NSEvent.NSMouseMovedMask  | NSEvent.NSOtherMouseDraggedMask | NSEvent.NSRightMouseDraggedMask,
      complete: false
    };
    resizeWindowCallback(event);
  }

  public function resizeWindowCallback(event:NSEvent) {
    if (event.type == NSEvent.NSLeftMouseUp) {
      return;
    }
    var width:Number = event.mouseLocation.x - m_trackingData.origin.x + m_trackingData.offsetX;
    var height:Number = event.mouseLocation.y - m_trackingData.origin.y + m_trackingData.offsetY;
    /* don't constrain here, constrain in NSWindow
    if (width < m_titleTextField.textWidth+30) {
      width = m_titleTextField.textWidth+30;
    }
    if (height < 24) {
      height = 24;
    }*/
    m_window.setFrame(new NSRect(m_trackingData.origin.x, m_trackingData.origin.y, width, height));
    NSApplication.sharedApplication().callObjectSelectorWithNextEventMatchingMaskDequeue(this, "resizeWindowCallback", m_trackingData.eventMask, true);
  }

  public function showsResizeIndicator():Boolean {
    return m_showsResizeIndicator;
  }

  public function setShowsResizeIndicator(value:Boolean) {
    if (m_showsResizeIndicator != value) {
      m_showsResizeIndicator = value;
      drawResizeClip();
    }
  }
  
  public function drawRect(rect:NSRect) {
    m_mcBounds.clear();
    var styleMask:Number = m_window.styleMask();
    
    var isKey:Boolean = m_window.isKeyWindow();
    if (isKey) {
      /** IF Flash8 */
      m_shadowFilter.blurX = 20;
      m_shadowFilter.blurY = 15;
      m_shadowFilter.alpha = .6;
      m_shadowFilter.strength = .7;
      m_shadowFilter.angle = 90;
      m_mcBase.filters = [m_shadowFilter];
      /** ENDIF */
    } else {
      /** IF Flash8 */
      m_shadowFilter.blurX = 10;
      m_shadowFilter.blurY = 4;
      m_shadowFilter.alpha = .4;
      m_shadowFilter.strength = .3;
      m_shadowFilter.angle = 90;    
      m_mcBase.filters = [m_shadowFilter];
      /** ENDIF */
    }

    if (styleMask == NSWindow.NSBorderlessWindowMask) {
      return;
    }

    
    var fillColors:Array = isKey ? [0xFFFFFF, 0xDEDEDE, 0xC6C6C6] : [0xFFFFFF, 0xDEDEDE, 0xFFFFFF];
    var fillAlpha:Number = 100;
    var cornerRadius:Number = 4;
    var x:Number = rect.origin.x;
    var y:Number = rect.origin.y;
    var width:Number = rect.size.width-1;
    var height:Number = 22;
    m_titleRect.size.width = width;
    
    if (m_titleTextField == null || m_titleTextField._parent == null) {
      m_titleTextField = createBoundsTextField();
      m_titleTextField.autoSize = true;
      m_titleTextField.align = "center";
      m_titleTextField.selectable = false;
      m_titleTextField._alpha = m_titleFontColor.alphaComponent()*100;
      m_titleTextField.embedFonts = m_titleFont.isEmbedded();
    }
    if (m_titleTextField.text != m_window.title()) {
      m_titleTextField.text = m_window.title();
      m_titleTextField._y = (22 - (m_titleTextField.textHeight+2))/2;;
      m_titleTextField._x = (width - (m_titleTextField.textWidth+2))/2;
    }
    m_titleTextFormat.color = isKey ? m_titleKeyFontColor.value : m_titleFontColor.value;
    m_titleTextField.setTextFormat(m_titleTextFormat);
    
    var totalHeight:Number = rect.size.height-1;
    with (m_mcBounds) {
      lineStyle(1.5, 0x8E8E8E, 100);
      beginGradientFill("linear", fillColors, [100,100,100], [0, 50, 255], 
                        {matrixType:"box", x:x,y:y,w:width,h:height,r:(.5*Math.PI)});
      moveTo(x+cornerRadius, y);
      lineTo(x+width-cornerRadius, y);
      lineTo(x+width, y+cornerRadius); //Angle
      lineTo(x+width, y+height);
      lineStyle(1.5, 0x6E6E6E, 100);
      lineTo(x, y+height);
      lineStyle(1.5, 0x8E8E8E, 100); 
      lineTo(x, y+cornerRadius);
      lineTo(x+cornerRadius, y); //Angle
      endFill();
      moveTo(x, y+height);
      lineStyle(1.5, 0x8E8E8E, 100); 
      lineTo(x, y+totalHeight);
      lineTo(x+width, y+totalHeight);
      lineTo(x+width, y+height);
    }
  }
  
  public function titleRect():NSRect {
  	return m_titleRect.clone();
  }
  
}