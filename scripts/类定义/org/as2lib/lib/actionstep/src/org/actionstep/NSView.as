/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 *
 * Copyright (c) 2005, Affinity Systems
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
 * 3) The name InfoEther, Inc. and Affinity Systems may not be used to endorse or promote products  
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
 
import org.actionstep.ASUtils;

import org.actionstep.NSResponder;
import org.actionstep.NSWindow;
import org.actionstep.NSNotificationCenter;
import org.actionstep.NSPoint;
import org.actionstep.NSSize;
import org.actionstep.NSRect;
import org.actionstep.NSEvent;
import org.actionstep.NSException;

import org.actionstep.NSClipView;
import org.actionstep.NSScrollView;
import org.actionstep.constants.NSWindowOrderingMode;

class org.actionstep.NSView extends NSResponder {
  
  // Constants  
  public static var NotSizable:Number = 0; //The receiver cannot be resized.
  public static var MinXMargin:Number = 1; //The left margin between the receiver and its superview is flexible.
  public static var WidthSizable:Number = 2; //The receiver’s width is flexible.
  public static var MaxXMargin:Number = 4; //The right margin between the receiver and its superview is flexible.
  public static var MinYMargin:Number = 8; //The bottom margin between the receiver and its superview is flexible.
  public static var HeightSizable:Number = 16; //The receiver’s height is flexible.
  public static var MaxYMargin:Number = 32; //The top margin between the receiver and its superview is flexible.
  
  // Notifications
  public static var NSViewFrameDidChangeNotification:Number = ASUtils.intern("NSViewFrameDidChangeNotification");
  public static var NSViewBoundsDidChangeNotification:Number = ASUtils.intern("NSViewBoundsDidChangeNotification");
  
  public static var MaxClipDepth:Number = 1048575;
  public static var MinClipDepth:Number = -16384;
  
  // private hidden instance variables
  private var m_frame:NSRect;
  private var m_frameRotation:Number;
  private var m_postsFrameChangedNotifications:Boolean;

  private var m_bounds:NSRect;
  private var m_boundsRotation:Number;
  private var m_postsBoundsChangedNotifications:Boolean;

  private var m_window:NSWindow;
  private var m_superview:NSView;
  private var m_subviews:Array;
  
  private var m_notificationCenter:NSNotificationCenter;
  
  private var m_autoresizesSubviews:Boolean;
  private var m_autoresizingMask:Number;
  
  private var m_hidden:Boolean;
  private var m_needsDisplay:Boolean;
  
  // key view loop
  private var m_nextKeyView:NSView;
  private var m_previousKeyView:NSView;
  
  // MovieClip variables
  private var m_mcFrame:MovieClip;
  private var m_mcFrameMask:MovieClip;
  private var m_mcBounds:MovieClip;
  private var m_mcDepth:Number;
  
  public function NSView() {
    m_frame = null;
    m_frameRotation = 0;
    m_postsFrameChangedNotifications = false;
    
    m_bounds = null;
    m_boundsRotation = 0;
    m_postsBoundsChangedNotifications = false;
    
    m_window = null;
    m_superview = null;
    m_subviews = new Array();
    
    m_autoresizesSubviews = true;
    m_autoresizingMask = NotSizable;
    
    m_mcDepth = 10;
    m_hidden = false;
    m_needsDisplay = false;
  }
  
  public function description():String {
    return "NSView(frame="+m_frame+", bounds="+m_bounds+" clip="+m_mcFrame+")";
  }
  
  public function init():NSView {
    return initWithFrame(NSRect.ZeroRect);
  }
  
  public function initWithFrame(newFrame:NSRect):NSView {
    m_notificationCenter = NSNotificationCenter.defaultCenter();
    m_frame = newFrame.clone();
    m_bounds = new NSRect(0, 0, m_frame.size.width, m_frame.size.height);
    return this;
  }
  
  // movieclip methods
  
  public function mcFrame():MovieClip {
    if (m_mcFrame == undefined) {
      throw new Error("Cannot access frame movieclip until NSView is inserted into view hierarchy.");
    }
    return m_mcFrame;
  }
  
  public function mcBounds():MovieClip {
    if (m_mcBounds == undefined) {
      throw new Error("Cannot access bounds movieclip until NSView is inserted into view hierarchy.");
    }
    return m_mcBounds;
  }
  
  public function createBoundsMovieClip():MovieClip {
    var bounds:MovieClip = this.mcBounds();
    var clipDepth:Number = getNextDepth();
    return bounds.createEmptyMovieClip("NSView"+clipDepth, clipDepth);
  }
  
  public function getNextDepth():Number {
    return m_mcDepth++;
  }
  
  public function createBoundsTextField():TextField {
    var bounds:MovieClip = this.mcBounds();
    var clipDepth:Number = m_mcDepth++;
    bounds.createTextField("TextField"+clipDepth, clipDepth, 0, 0, 0, 0);
    bounds["TextField"+clipDepth].view = this;
    return bounds["TextField"+clipDepth];
  }  
  
  public function createMovieClips():Void {
    if (m_mcFrame != null)
    {
       //return if already created
       return;
    }
    try {
      m_mcFrame = createFrameMovieClip();
    } catch (error:Error) {
      m_mcFrame = null;
      return;
    }
    m_mcFrame.view = this;

    m_mcFrameMask = m_mcFrame.createEmptyMovieClip("m_mcFrameMask", 1);
    m_mcFrameMask._x = 0;
    m_mcFrameMask._y = 0;
    m_mcFrame.setMask(m_mcFrameMask);
    updateFrameMovieClipSize();
    updateFrameMovieClipPerspective();
    initializeBoundsMovieClip();
  }
  
  private function createFrameMovieClip():MovieClip {
    return m_superview.createBoundsMovieClip();
  }
  
  private function initializeBoundsMovieClip() {
    m_mcBounds = m_mcFrame.createEmptyMovieClip("m_mcBounds", 2);
    m_mcBounds.view = this;
    updateBoundsMovieClip();
    for(var i:Number=0;i<m_subviews.length;i++) {
      m_subviews[i].createMovieClips();
    }
  }
  
  private function updateFrameMovieClipSize():Void {
    if (m_mcFrame == null) {
      return;
    }
    m_mcFrame.clear();
    m_mcFrame.beginFill(0x000000, 0);
    m_mcFrame.moveTo(0,0);
    m_mcFrame.lineTo(m_frame.size.width, 0);
    m_mcFrame.lineTo(m_frame.size.width, m_frame.size.height);
    m_mcFrame.lineTo(0, m_frame.size.height);
    m_mcFrame.endFill();
    m_mcFrame.lineTo(0, 0);
    updateFrameMovieClipPosition();

    m_mcFrameMask.clear();
    m_mcFrameMask.beginFill(0x000000, 100);
    m_mcFrameMask.moveTo(0,0);
    m_mcFrameMask.lineTo(m_frame.size.width, 0);
    m_mcFrameMask.lineTo(m_frame.size.width, m_frame.size.height);
    m_mcFrameMask.lineTo(0, m_frame.size.height);
    m_mcFrameMask.endFill();
    m_mcFrameMask.lineTo(0, 0);
  }
  
  private function updateFrameMovieClipPosition():Void {
    if (m_mcFrame == null) {
      return;
    }
    m_mcFrame._x = m_frame.origin.x;
    m_mcFrame._y = m_frame.origin.y;
  }
  
  private function updateFrameMovieClipPerspective():Void {
    if (m_mcFrame == null) {
      return;
    }
    m_mcFrame._rotation = m_frameRotation;
    if (m_mcFrame._visible != !m_hidden) {
      m_mcFrame._visible = !m_hidden;
      if (m_hidden) {
        m_mcFrame._x = 4000;
        m_mcFrame._y = 4000;
      } else {
        m_mcFrame._x = m_frame.origin.x;
        m_mcFrame._y = m_frame.origin.y;
      }
    }
  }

  private function updateBoundsMovieClip():Void {
    if (m_bounds != undefined) {
      m_mcBounds._x = -m_bounds.origin.x;
      m_mcBounds._y = -m_bounds.origin.y;
    }
  }
  
  public function removeMovieClips():Void {
    for(var i:Number=0;i<m_subviews.length;i++) {
      m_subviews[i].removeMovieClips();
    }
    release();
    m_mcFrame.removeMovieClip();
    m_mcFrame = null;
    m_mcFrameMask = null;
    m_mcBounds = null;
  }

  // Managing the view hierarchy
  
  public function superview():NSView {
    return m_superview;
  }
  
  public function subviews():Array {
    return m_subviews;
  }
  
  public function window():NSWindow {
    return m_window;
  }
  
  public function addSubview(view:NSView):Void {
    if (view.isDescendantOf(this)) {
      var e:NSException = NSException.exceptionWithNameReasonUserInfo("ViewHierarchyError", "Cannot add a view to its child", null);
      trace(e);
      e.raise();
    }
    view.removeFromSuperview();
    view.viewWillMoveToSuperview(this);
    view.viewWillMoveToWindow(m_window);
    view.setNextResponder(this);
    m_subviews.push(view);
    view.setNeedsDisplay(true);
    view.viewDidMoveToWindow();
    view.viewDidMoveToSuperview();
    didAddSubview(view);
  }
  
  public function addSubviewPositionedRelativeTo(view:NSView, positioned:NSWindowOrderingMode, otherView:NSView) {
    var i:Number;
    for(i=0;i<m_subviews.length;i++) {
      if (m_subviews[i] == otherView) {
        break;
      }
    }
    if(i == m_subviews.length || otherView == null) {
      switch(positioned) {
      case NSWindowOrderingMode.NSWindowAbove:
        i = m_subviews.length;
        break;
      case NSWindowOrderingMode.NSWindowBelow:
        i = 0;
        break;
      case NSWindowOrderingMode.NSWindowOut:
        //! How to handle this?
        break;
      }
    } else {
      switch(positioned) {
      case NSWindowOrderingMode.NSWindowAbove:
        i = i+1;
        break;
      case NSWindowOrderingMode.NSWindowBelow:
        break;
      case NSWindowOrderingMode.NSWindowOut:
        //! How to handle this?
        break;
      }
    }
    view.removeFromSuperview();
    view.viewWillMoveToSuperview(this);
    view.viewWillMoveToWindow(m_window);
    m_subviews.splice(i, 0, view);
    view.setNeedsDisplay(true);
    view.viewDidMoveToWindow();
    view.viewDidMoveToSuperview();
    didAddSubview(view);
  }
  
  public function didAddSubview(view:NSView) {
  }
  
  public function removeFromSuperview() {
    var superview:NSView = m_superview;
    var view:NSView;
    
    if (superview == null) return;
    
    superview.setNeedsDisplay(true);
    
    for (view = NSView(m_window.firstResponder());view != null && view["superview"] != undefined;
     view = view.superview()) {
      if (view == this) {
        m_window.makeFirstResponder(m_window);
        break;
      }
    }
    
    superview.willRemoveSubview(this);
    m_superview = null;
    viewWillMoveToWindow(null);
    m_window = null;
    viewWillMoveToSuperview(null);
    setNextResponder(null);

    var i:Number;
    var parentSubviews:Array = superview.subviews();
    for(i=0;i<parentSubviews.length;i++) {
      if (parentSubviews[i] == this) {
        parentSubviews.splice(i,1);
        break;
      }
    }
    setNeedsDisplay(false);
    viewDidMoveToWindow();
    viewDidMoveToSuperview();
  }
  
  public function removeFromSuperviewWithoutNeedingDisplay() {
    var superview:NSView = m_superview;
    var view:NSView;

    if (superview == null) return;
    
    for (view = NSView(m_window.firstResponder());view != null && view["superview"] != undefined;
     view = view.superview()) {
      if (view == this) {
        m_window.makeFirstResponder(m_window);
        break;
      }
    }

    superview.willRemoveSubview(this);
    m_superview = null;
    viewWillMoveToWindow(null);
    m_window = null;
    viewWillMoveToSuperview(null);
    setNextResponder(null);

    var i:Number;
    var parentSubviews:Array = superview.subviews();
    for(i=0;i<parentSubviews.length;i++) {
      if (parentSubviews[i] == this) {
        parentSubviews.splice(i,1);
        break;
      }
    }
    setNeedsDisplay(false);
    viewDidMoveToWindow();
    viewDidMoveToSuperview();
  }
  
  public function replaceSubviewWith(oldView:NSView, newView:NSView) {
    if (oldView == null || newView == null) return;
    var i:Number;
    for(i=0;i<m_subviews.length;i++) {
      if (m_subviews[i] == oldView) {
        break;
      }
    }
    if (i == m_subviews.length) {
      return; // oldview does not exist
    }
    
    newView.removeFromSuperview();
    oldView.removeFromSuperview();
    newView.viewWillMoveToWindow(m_window);
    newView.viewWillMoveToSuperview(this);
    newView.setNextResponder(this);
    m_subviews.splice(i, 0, newView);
    newView.setNeedsDisplay(true);
    newView.viewDidMoveToWindow();
    newView.viewDidMoveToSuperview();
    didAddSubview(newView);
  }
  
  public function isDescendantOf(view:NSView):Boolean {
    var check:NSView = m_superview;
    while(check != null) {
      if (check == view) return true;
      check = check.superview();
    }
    return false;
  }
  
  public function opaqueAncestor():NSView {
    if (isOpaque()) {
      return this;
    } else {
      m_superview.opaqueAncestor();
    }
  }
  
  public function ancestorSharedWithView(view:NSView):NSView {
    if (view == this) {
      return this;
    }
    var check:NSView = view.superview();
    while(check != null) {
      if (this.isDescendantOf(check)) return check;
      check = check.superview();
    }
    return null;
  }
  
  public function sortSubviewsUsingFunction(func:Function) {
    m_subviews = m_subviews.sort(func);
  }
  
  public function viewDidMoveToSuperview() {
  }

  public function viewDidMoveToWindow():Void {
  }
  
  public function viewWillMoveToSuperview(view:NSView):Void {
    m_superview = view;
    if (m_superview == null) {
      removeMovieClips();
    } else {
      createMovieClips();
    }
  }

  public function viewWillMoveToWindow(window:NSWindow):Void {
    m_window = window;
    setNeedsDisplay(true);
    for(var i:Number=0;i<m_subviews.length;i++) {
      m_subviews[i].viewWillMoveToWindow(window);
    }
  }
  
  public function willRemoveSubview(view:NSView):Void {
  }
  
  // Searching by tag
  
  public function viewWithTag(tagToFind:Number):NSView {
    if (tag() == tagToFind) return this;
    var i:Number;
    var view:NSView = null;
    for(i=0;i<m_subviews.length;i++) {
      if (m_subviews[i].tag() == tagToFind) {
        return m_subviews[i];
      }
    }
    for(i=0;i<m_subviews.length;i++) {
      view = m_subviews[i].viewWithTag(tagToFind);
      if (view != null) {
        return view;
      }
    }
    return null;
  }
  
  public function tag():Number {
    return -1;
  }
  
  // Modifying the frame rectangle
  
  public function setFrame(newFrame:NSRect):Void {
    var changedOrigin:Boolean = !m_frame.origin.isEqual(newFrame.origin);
    var changedSize:Boolean = !m_frame.size.isEqual(newFrame.size);
    if (changedSize || changedOrigin) {
      m_frame = newFrame.clone();
      updateFrameMovieClipSize();
      if (changedSize) {
        if (m_bounds == null) {
          m_bounds = new NSRect(0,0,m_frame.size.width, m_frame.size.height);
        } else {
          m_bounds.size = m_frame.size.clone();
        }
      }
      if(m_postsFrameChangedNotifications) {
        m_notificationCenter.postNotificationWithNameObject(NSViewFrameDidChangeNotification, this);
      }
    }
  }
  
  public function frame():NSRect {
    return m_frame.clone();
  }
  
  public function setFrameOrigin(origin:NSPoint) {
    m_frame.origin.x = origin.x;
    m_frame.origin.y = origin.y;
    updateFrameMovieClipPosition();
    if(m_postsFrameChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewFrameDidChangeNotification, this);
    }
  }

  public function setFrameSize(size:NSSize) {
    m_frame.size = size.clone();
    m_bounds.size = size.clone();
    updateFrameMovieClipSize();
    if(m_postsFrameChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewFrameDidChangeNotification, this);
    }
  }
  
  public function setFrameRotation(angle:Number) {
    m_frameRotation = angle;
    updateFrameMovieClipPerspective();
    if(m_postsFrameChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewFrameDidChangeNotification, this);
    }
  }
  
  public function frameRotation():Number {
    return m_frameRotation;
  }
    
  // Modifying the bounds rectangle
  
  public function setBounds(bounds:NSRect):Void {
    m_bounds = bounds.clone();
    updateBoundsMovieClip();
    if(m_postsBoundsChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewBoundsDidChangeNotification, this);
    }
  }

  public function bounds():NSRect {
    return m_bounds.clone();
  }

  public function setBoundsOrigin(origin:NSPoint) {
    m_bounds.origin = origin.clone();
    updateBoundsMovieClip();
    if(m_postsBoundsChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewBoundsDidChangeNotification, this);
    }
  }

  public function setBoundsSize(size:NSSize) {
    m_bounds.size = size.clone();
    updateBoundsMovieClip();
    if(m_postsBoundsChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewBoundsDidChangeNotification, this);
    }
  }

  public function setBoundsRotation(angle:Number) {
    m_boundsRotation = angle;
    updateBoundsMovieClip();
    if(m_postsBoundsChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewBoundsDidChangeNotification, this);
    }
  }

  public function boundsRotation():Number {
    return m_boundsRotation;
  }
  
  public function scaleUnitSquareToSize(size:NSSize) {
    size = size.clone();
    if (size.width < 0) {
      size.width = 0;
    }
    if (size.height < 0) {
      size.height = 0;
    }
    m_bounds.size.width = m_bounds.size.width / size.width;
    m_bounds.size.height = m_bounds.size.height / size.height;
    updateBoundsMovieClip();
    if(m_postsBoundsChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewBoundsDidChangeNotification, this);
    }
  }
  
  //******************************************************															 
  //*          Modifying the coordinate system
  //******************************************************
  
  public function translateOriginToPoint(point:NSPoint) {
    m_bounds.origin.x -= point.x;
    m_bounds.origin.y -= point.y;
    updateBoundsMovieClip();
    if(m_postsBoundsChangedNotifications) {
      m_notificationCenter.postNotificationWithNameObject(NSViewBoundsDidChangeNotification, this);
    }
  }
  
  public function rotateByAngle(angle:Number) { 
   setBoundsRotation(boundsRotation() + angle);
  }
     
  //******************************************************															 
  //*      Examining coordiante system modifications
  //******************************************************
  
  //******************************************************															 
  //*              Converting Coordinates	
  //******************************************************
  
  /**
   * Converts aPoint from the coordinate system of aView to this view's
   * coordinate system.
   *
   * If aView is null, aPoint is converted from global coordinates (_root).
   */
  public function convertPointFromView(aPoint:NSPoint, aView:NSView):NSPoint {
    var pt:NSPoint = aPoint.clone();
    if (m_mcBounds != null) { // Simple case
      var from:MovieClip = (aView == null) ? _root : aView.mcBounds();
      from.localToGlobal(pt);
      mcBounds().globalToLocal(pt);
    } else { // Difficult case
    }
    return pt;
  }
  
  
  /**
   * Converts aPoint from this view's coordinate system to the coordinate
   * system of aView.
   *
   * If aView is null, aPoint is converted to global coordinates (_root).
   */
  public function convertPointToView(aPoint:NSPoint, aView:NSView):NSPoint {
    var pt:NSPoint = aPoint.clone();
    if (m_mcBounds != null) { // Simple case
      var to:MovieClip = (aView == null) ? _root : aView.mcBounds();
      mcBounds().localToGlobal(pt);
      to.globalToLocal(pt);
    } else { // Difficult case
    }
    return pt;
  }
  

  /**
   * Converts aSize from the coordinate system of aView to this view's
   * coordinate system.
   *
   * If aView is null, aSize is converted from global coordinates (_root).
   */
  public function convertSizeFromView(aSize:NSSize, aView:NSView):NSSize {
    var wdt:NSPoint = convertPointFromView(new NSPoint(aSize.width, 0), aView);
    var hgt:NSPoint = convertPointFromView(new NSPoint(0, aSize.height), aView);
  	
    return new NSSize(wdt.x, hgt.y);
  }
  
  
  /**
   * Converts aSize from this view's coordinate system to the coordinate
   * system of aView.
   *
   * If aView is null, aSize is converted to global coordinates (_root).
   */
  public function convertSizeToView(aSize:NSSize, aView:NSView):NSSize {
    var wdt:NSPoint = convertPointToView(new NSPoint(aSize.width, 0), aView);
    var hgt:NSPoint = convertPointToView(new NSPoint(0, aSize.height), aView);
  	
    return new NSSize(wdt.x, hgt.y);
  }
  
  
  /**
   * Converts aRect from the coordinate system of aView to this view's
   * coordinate system.
   *
   * If aView is null, aRect is converted from global coordinates (_root).
   */
  public function convertRectFromView(aRect:NSRect, aView:NSView):NSRect {
    var pt:NSPoint = convertPointFromView(aRect.origin, aView);
    var sz:NSSize = convertSizeFromView(aRect.size, aView);
  	
    return NSRect.withOriginSize(pt, sz);
  }
  
  
  /**
   * Converts aRect from this view's coordinate system to the coordinate
   * system of aView.
   *
   * If aView is null, aRect is converted to global coordinates (_root).
   */
  public function convertRectToView(aRect:NSRect, aView:NSView):NSRect {
    var pt:NSPoint = convertPointToView(aRect.origin, aView);
    var sz:NSSize = convertSizeToView(aRect.size, aView);
  	
    return NSRect.withOriginSize(pt, sz);
  }
  
  //******************************************************															 
  //*                  Scrolling
  //******************************************************
  
  public function scrollPoint(point:NSPoint) {
    var view:NSView = m_superview;
    while (view != null && view.getClass()!=NSClipView) {
      view = view.superview();
    }
    if (view != null) {
      point = convertPointToView(point, view);
      if (!point.isEqual(view.bounds().origin)) {
        NSClipView(view).scrollToPoint(point);
      }
    }
  }
  
  /**
   * Scrolls this view's drawing surface the minimum distance for
   * aRect to be completely visible. 
   * 
   * Returns TRUE if scrolling is performed, FALSE otherwise.
   */
  public function scrollRectToVisible(aRect:NSRect):Boolean {
    var view:NSView = m_superview;
    while (view != null && view.getClass()!=NSClipView) {
      view = view.superview();
    }
    if (view != null) {
      var vRect:NSRect = visibleRect();
      var scrollPoint:NSPoint = vRect.origin.clone();
      if (vRect.size.width == 0 && vRect.size.height == 0) {
        return false;
      }
      var ldiff:Number = vRect.minX() - aRect.minX();
      var rdiff:Number = aRect.maxX() - vRect.maxX();
      var tdiff:Number = vRect.minY() - aRect.minY();
      var bdiff:Number = aRect.maxY() - vRect.maxY();
      
      if ((ldiff*rdiff) > 0) ldiff = rdiff = 0;
      if ((tdiff*bdiff) > 0) tdiff = bdiff = 0;
      scrollPoint.x += (Math.abs(ldiff) < Math.abs(rdiff)) ? (-ldiff) : rdiff;
      scrollPoint.y += (Math.abs(tdiff) < Math.abs(bdiff)) ? (-tdiff) : bdiff;
      if (!vRect.origin.isEqual(scrollPoint)) {
        scrollPoint = convertPointToView(scrollPoint, view);
        NSClipView(view).scrollToPoint(scrollPoint);
        return true;
      }
    }
    return false;
  }
  
  public function autoscroll(event:NSEvent):Boolean {
    if (m_superview) {
      return m_superview.autoscroll(event);
    } else {
      return false;
    }
  }
  
  public function adjustScroll(proposedRect:NSRect):NSRect {
    return proposedRect;
  }
  
  public function scrollRectBy(rect:NSRect, size:NSSize) {
    // DO NOTHING 
  }
  
  public function enclosingScrollView():NSScrollView {
    var view:NSView = m_superview;
    while (view != null && view.getClass()!=NSScrollView) {
      view = view.superview();
    }
    return view == null ? null : NSScrollView(view);
  }
  
  public function scrollClipViewToPoint(clipView:NSClipView, point:NSPoint) {
    //DO NOTHING
  }
  
  public function reflectScrolledClipView(clipView:NSClipView) {
    //DO NOTHING
  }
  
  // Managing the key view loop
  
  public function canBecomeKeyView():Boolean {
    return acceptsFirstResponder() && !isHiddenOrHasHiddenAncestor();
  }
  
  public function needsPanelToBecomeKey():Boolean {
    return false;
  }
  
  public function setNextKeyView(view:NSView) {
    if (view == null || view instanceof NSView) {
      if (view == null) {
        m_nextKeyView.m_previousKeyView = null;
        m_nextKeyView = null;
      } else {
        m_nextKeyView = view;
        view.m_previousKeyView = this;
      }
    } else {
      throw new Error("NSInternalInconsistencyException");
    }
  }
  
  public function nextKeyView():NSView {
    return m_nextKeyView;
  }
  
  public function nextValidKeyView():NSView {
    var result:NSView = m_nextKeyView;
    while (true) {
      if (result == null || result == this || result.canBecomeKeyView()) {
        return result;
      }
      result = result.m_nextKeyView;
    }
  }

  public function previousKeyView():NSView {
    return m_previousKeyView;
  }

  public function previousValidKeyView():NSView {
    var result:NSView = m_previousKeyView;
    while (true) {
      if (result == null || result == this || result.canBecomeKeyView()) {
        return result;
      }
      result = result.m_previousKeyView;
    }
  }
  
  //******************************************************															 
  //*            Controlling Notifications
  //******************************************************
  
  public function setPostsFrameChangedNotifications(value:Boolean) {
    m_postsFrameChangedNotifications = value;
  }

  public function postsFrameChangedNotifications():Boolean {
    return m_postsFrameChangedNotifications;
  }

  public function setPostsBoundsChangedNotifications(value:Boolean) {
    m_postsBoundsChangedNotifications = value;
  }

  public function postsBoundsChangedNotifications():Boolean {
    return m_postsBoundsChangedNotifications;
  }
  
  // Resizing subviews
  
  public function resizeSubviewsWithOldSize(oldBoundsSize:NSSize) {
    //! Figure out which methods need to calll this function
    if (m_autoresizesSubviews) {
      var i:Number;
      for(i=0;i<m_subviews.length;i++) {
        m_subviews[i].resizeWithOldSuperviewSize(oldBoundsSize);
      }
    }
  }
  
  public function resizeWithOldSuperviewSize(oldBoundsSize:NSSize) {
    if (m_autoresizingMask == NSView.NotSizable) {
      return;
    }
    var options:Number = 0;
    var superViewFrameSize:NSSize = m_superview == null ? NSSize.ZeroSize : m_superview.frame().size;
    var newFrame:NSRect = m_frame.clone();
    var changedOrigin:Boolean = false;
    var changedSize:Boolean = false;
    if (m_autoresizingMask & NSView.WidthSizable) {
      options++;
    }
    if (m_autoresizingMask & NSView.MinXMargin) {
      options++;
    }
    if (m_autoresizingMask & NSView.MaxXMargin) {
      options++;
    }
    if (options > 0) {
      var change:Number = superViewFrameSize.width - oldBoundsSize.width;
      var changePerOption:Number = change/options;
      if (m_autoresizingMask & NSView.WidthSizable) {
        newFrame.size.width += changePerOption;
        changedSize = true;
      }
      if (m_autoresizingMask & NSView.MinXMargin) {
        newFrame.origin.x += changePerOption;
        changedOrigin = true;
      }
    }

    options = 0;
    if (m_autoresizingMask & NSView.HeightSizable) {
      options++;
    }
    if (m_autoresizingMask & NSView.MinYMargin) {
      options++;
    }
    if (m_autoresizingMask & NSView.MaxYMargin) {
      options++;
    }
    if (options > 0) {
      var change:Number = superViewFrameSize.height - oldBoundsSize.height;
      var changePerOption:Number = change/options;
      if (m_autoresizingMask & NSView.HeightSizable) {
        newFrame.size.height += changePerOption;
        changedSize = true;
      }
      if (m_autoresizingMask & NSView.MinYMargin) {
        newFrame.origin.y += changePerOption;
        changedOrigin = true;
      }
    }
    setFrame(newFrame);
  }
  
  public function setAutoresizesSubviews(value:Boolean) {
    m_autoresizesSubviews = value;
  }
  
  public function autoresizesSubviews():Boolean {
    return m_autoresizesSubviews;
  }
  
  public function setAutoresizingMask(value:Number) {
    m_autoresizingMask = value;
  }
  
  public function autoresizingMask():Number {
    return m_autoresizingMask;
  }
  
  // Focusing
  
  public function display() {
    if (m_hidden || m_mcBounds == null) {
      return;
    }
    drawRect(m_bounds);
    m_needsDisplay = false;
    var i:Number;
    for(i=0;i<m_subviews.length;i++) {
      m_subviews[i].display();
    }    
  }
  
  //! Is this type of lockfocus is needed in AS ?
  
  // Displaying
  
  public function displayIfNeeded() {
    if (m_hidden || m_mcBounds == null) {
      return;
    }
    if (m_needsDisplay) {
      drawRect(m_bounds);
      m_needsDisplay = false;
    }
    var i:Number;
    for(i=0;i<m_subviews.length;i++) {
      m_subviews[i].displayIfNeeded();
    }    
  }
  
  public function setNeedsDisplay(value:Boolean) {
    m_needsDisplay = value;
    if (value) {
      m_window.setViewsNeedDisplay(true);
    }
  }
  
  public function needsDisplay():Boolean {
    return m_needsDisplay;
  }
  
  public function isOpaque():Boolean {
    return false;
  }
  
  // Hiding views
  
  public function setHidden(value:Boolean) {
    m_hidden = value;
    updateFrameMovieClipPerspective();
    //! move the clip offscreen if hidden
  }
  
  public function isHidden():Boolean {
    return m_hidden;
  }
  
  public function isHiddenOrHasHiddenAncestor():Boolean {
    if (isHidden()) {
      return true;
    } else if (superview() == null) {
      return false;
    } else {
      return superview().isHiddenOrHasHiddenAncestor();
    }
  }
  
  // Drawing
  
  public function drawRect(rect:NSRect) {
  }
  
  public function visibleRect():NSRect {
    if (m_window == null) {
      return NSRect.ZeroRect;
    }
    if (m_superview == null) {
      return m_bounds;
    }
    return convertRectFromView(m_superview.visibleRect(), m_superview).intersectionRect(m_bounds);
  }
  
  public function wantsDefaultClipping():Boolean {
    return true;
  }

  //! which other functions in the drawing group are needed?
  //  – canDraw
  //  – shouldDrawColor
  //  – getRectsBeingDrawn:count:
  //  – needsToDrawRect:
  
  // Managing live resize

  // – inLiveResize
  // – viewWillStartLiveResize
  // – viewDidEndLiveResize
  
  // Managing a graphics state

  // – allocateGState
  // – gState
  // – setUpGState
  // – renewGState
  // – releaseGState

  // Event handling
  
  public function acceptsFirstMouse(event:NSEvent):Boolean {
    return false;
  }
  
  public function performKeyEquivalent(event:NSEvent):Boolean {
    var i:Number;
    var result:Boolean = false;
    for(i=0;i<m_subviews.length;i++) {
      if (m_subviews[i].performKeyEquivalent(event)) {
        result = true;
      }
    }
    return result;
  }

  public function performMnemonic(string:String):Boolean {
    var i:Number;
    var result:Boolean = false;
    for(i=0;i<m_subviews.length;i++) {
      if (m_subviews[i].performMnemonic(string)) {
        result = true;
      }
    }
    return result;
  }
  
  public function release() {
    // Override 
  }
}